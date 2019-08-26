#!/bin/bash

die(){
    log_error "$1"
    exit "$2"
}

__log() {
    local LEVEL="${1}"
    local MSG="${2}"
    if [[ $# -lt 2 ]]; then
        local LEVEL="ERROR"
        local MSG="${1}"
        log_debug "Invalid use of log system"
    fi

    local NOW=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${NOW}" "${LEVEL}" "${MSG}"
}

log_error() {
    __log "ERROR" "$*" >> /dev/stderr
}

log_warn() {
    __log "WARNING" "$*"
}

log_info() {
    __log "INFO" "$*"
}

log_debug() {
    if [[ "${DEBUG}" -ne "0" ]]; then
        if [[ $# -gt 0 ]]; then
            __log "DEBUG" "$*"
        else
            echo
        fi
    fi
}

# Check the required dependencies 
checkoc() {
    local COMMANDS="oc jq mkdir rm"
    if [[ ! -z "${COMPRESS}" && "${COMPRESS}" != "0" ]]; then
        local COMMANDS="${COMMANDS} tar gzip"
    fi

    if [[ ! -z "${ENCRYPT}" && "${ENCRYPT}" != "0" ]]; then
        local COMMANDS="${COMMANDS} openssl"
    fi

    for i in ${COMMANDS}; do
        command -v $i >/dev/null 2>&1 || die "$i required but not found" 3
    done

    oc get all > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        die "You are not logged in to the cluster." 4
    fi
}

usage(){
    echo "$0 [<projectname...>]"
    echo "          Export project(s) <projectname> [<projectname2>]..."
    echo "$0 --all"
    echo "          Export all projects from cluster"
    echo "$0 --help"
    echo "          Show help"
    echo
    echo "$0 supports the following environment variables:"
    echo "       COMPRESS - Enable Compression (default: 0)"
    echo "       ENCRYPT - Enable Encryption, must contain or point to Public Key in PEM Format (default: empty -> disabled)"
    echo "       OUTPUT_PATH - The directory where the backups should be stored. Falls back to current working directory when output path is not writable. (default: /backup/data)"
    echo "       DIR_NAME - Name of the directory where the next backup will be stored. (default: export-[YEAR]-[MONTH]-[DAY])"
    echo "       SECURE_DELETE - Whether the unencrypted data should be safely deleted after encryption or compression. (default: 1)"
    echo "       EXPORT_ALL - Export all cluster projects. (default: 0)"
    echo "       EXPORT_PROJECTS - Export one or more projects separated by space. (default: empty)"
}

# Exports a given type of objects
export_type(){
    if [ $# -lt 1 ]; then
        log_error "Invalid parameters for export type; Project: ${PROJECT}"
        return
    fi

    if [[ ! -z "${PROJECT}" ]]; then
        local NAMESPACE="-n ${PROJECT}"
    fi

    local KIND="$1"
    local BUFFER=$(oc get "${KIND}" --export -o json ${NAMESPACE} || true)

    # return if resource type unknown or access denied
    if [ -z "${BUFFER}" ]; then
        return
    fi

    # Make list object if not already a list
    local BUFFER=$(make_list "${BUFFER}")

    # return if list empty
    truncate_empty_list "${BUFFER}"
}

# Check whether the given JSON list is empty
# Warning: Probably the most used function. Change carefully!
truncate_empty_list() {
    local BUFFER="$1"
    # return if list empty
    if [[ -z "${BUFFER}" || "$(echo "${BUFFER}" | jq '.items | length > 0')" == "false" ]]; then
        return
    fi

    echo "${BUFFER}"
}

# If JSON output is not a list, make it one with only one entry
# Most jq processing requires the input to be a list.
make_list() {
    if [[ -z "$1" ]]; then
        return
    fi
    
    local BUFFER="$1"
    if [[ ! -z $(echo "${BUFFER}" | jq 'select(.kind=="List")') ]]; then
        echo "${BUFFER}"
        return
    fi

    echo "{\"apiVersion\": \"v1\", \"items\": [${BUFFER}], \"kind\": \"List\"}"
}

# Helper function to parse passed CLI or ENV variables
sanitize_var() {
    if [[ -z "$1" || "$1"  == "0" || "$1" == "false" ]]; then
        echo  "0"
    else
        echo "$1"
    fi 
}

# Function to removed unused attributes which is applied to nearly all exports.
# Warning: Change carefully
delete_common_attr() {
    delete_attr "$1" 'del('\
'.items[].status,'\
'.items[].metadata.uid,'\
'.items[].metadata.selfLink,'\
'.items[].metadata.resourceVersion,'\
'.items[].metadata.creationTimestamp,'\
'.items[].metadata.generation,'\
'.items[].metadata.annotations["kubectl.kubernetes.io/last-applied-configuration"]'\
')'
}

# Helper function to call jq
delete_attr() {
    if [ $# -ne 2 ]; then
        echo "Error: Invalid parameters for export type" > /dev/stderr
        echo "Parameters: $@" > /dev/stderr
        echo "Project: ${PROJECT}" > /dev/stderr
        return
    fi

    local INPUT=$(truncate_empty_list "$1")
    if [[ -z "${INPUT}" ]]; then
        return
    fi

    local RESULT=$(echo "${INPUT}" | jq "$2")
    truncate_empty_list "${RESULT}"
}

# Create base directory
make_base() {
    if [[ -d "${BASENAME}" ]]; then
        rm -rf "${BASENAME}"
    fi

    mkdir -p "${BASENAME}" > /dev/null
    if [[ $? -ne 0 ]]; then
        die "Error creating base export directory" 7
    fi
}

# Get list of cluster objects which should be exported
cluster_objects_config() {
    cat "${BASE}/scripts/objects.json" | jq '."cluster-objects" | to_entries[] | .value' | xargs
}

# Get list of namespace objects which should be exported
namespace_objects_config() {
    cat "${BASE}/scripts/objects.json" | jq '."namespace-objects" | to_entries[] | .value' | xargs
}

# Function to compress exported files
compress_export() {
    local ARCHIVE="${OUTPUT_PATH}/${DIR_NAME}.tar.gz"
    echo "Compress exported files to ${DIR_NAME}.tar.gz"
    tar czf "${ARCHIVE}" "${BASENAME}" > /dev/null

    if [[ -z "${SECURE_DELETE}" ||  "${SECURE_DELETE}" == "0" ]]; then
        # No deleteion of sensible files
        return
    fi

    # Safe delete with shred or dd (fallback)
    local HAS_SHRED=$(command -v shred)
    if [[ ! -z "${HAS_SHRED}" ]]; then
        find "${BASENAME}/" -type f -exec shred -u -z {} \;
    else
        echo "Warning: Cannot safely delete sensible files. Fall back to 'dd' and 'rm'" > /dev/stderr
        local FILES=$(find "${BASENAME}/" -type f | xargs)
        for FILE in ${FILES}; do 
            overwrite_with_dd "${FILE}"
            rm -f "${FILE}"
        done
    fi

    rm -rf "${BASENAME}/"
}

# Function to encrypt exported archive
encrypt_export() {
    local KEY="$1"
    if [[ -z "${KEY}" ]]; then
        die "No Public Key provided" 12
    fi

    if [[ ! -r "${KEY}" && "${#KEY}" -gt "100" ]]; then
        echo "${KEY}" > "/tmp/${CUR_DATETIME_ISO}.pem"
        local KEY="/tmp/${CUR_DATETIME_ISO}.pem"
    fi

    if [[ ! -r "${KEY}" ]]; then 
        die "Illegal encryption key given" 12
    fi

    local ARCHIVE="${OUTPUT_PATH}/${DIR_NAME}.tar.gz"
    if [[ ! -f "${ARCHIVE}" ]]; then
        # If backup has not been compressed yet, compress now
        compress_export
    fi

    local KEY_FILE="key.bin"
    local ENCRYPTED_KEY_FILE="${KEY_FILE}.enc"
    local OUTPUT_FILE="${OUTPUT_PATH}/${DIR_NAME}.enc"
    local FINAL_ARCHIVE="${OUTPUT_PATH}/${DIR_NAME}-encrypted.tar"

    # Generate Secret Key
    openssl rand -base64 128 > key.bin

    # Encrypt Secret Key
    openssl rsautl -encrypt -inkey "$1" -pubin -in "${KEY_FILE}" -out "${ENCRYPTED_KEY_FILE}"

    # Encrypt Archive
    openssl enc -aes256 -salt -in "${ARCHIVE}" -out "${OUTPUT_FILE}" -pass "file:${KEY_FILE}"

    # Archive Key and encrypted archive together
    tar cf "${FINAL_ARCHIVE}" "${OUTPUT_FILE}" "${ENCRYPTED_KEY_FILE}"
    log_info "Encrypt exported files to ${DIR_NAME}-encrypted.tar"

    if [[ -z "${SECURE_DELETE}" ||  "${SECURE_DELETE}" == "0" ]]; then
        # No deleteion of sensible files
        return
    fi

    # Safe delete sensible files with shred or dd (fallback)
    local FILES="${ARCHIVE} ${OUTPUT_FILE} ${ENCRYPTED_KEY_FILE} ${KEY_FILE}"
    local HAS_SHRED=$(command -v shred 2>/dev/null)
    if [[ ! -z "${HAS_SHRED}" ]]; then
        shred -u -z ${FILES}
    else
        log_warn "Cannot safely delete sensitive files. Fall back to 'dd' and 'rm'"
        for FILE in ${FILES}; do 
            overwrite_with_dd "${FILE}"
            rm -f "${FILE}"
        done
    fi
}

# Function to overwrite data with dd when shred is not available
overwrite_with_dd() {
    if [[ ! -w "$1" ]]; then
        log_error "Cannot overwrite $1"
        return
    fi

    local SIZE=$(stat -c '%s' "$1")
    local BS_COUNT=$((SIZE / 1024))
    dd conv=notrunc if=/dev/zero of="$1" bs=1024 count="${BS_COUNT}" fsync > /dev/null
}


COMPRESS=$(sanitize_var "${COMPRESS}")
COMPRESS_OUTPUT_PATH=""
ENCRYPT=$(sanitize_var "${ENCRYPT}")
ENCRYPT_OUTPUT_PATH=""

OUTPUT_PATH=${OUTPUT_PATH:-"/backup"}
DIR_NAME=${DIR_NAME}
SECURE_DELETE=${SECURE_DELETE:-"1"}
EXPORT_ALL=${EXPORT_ALL:-0}
EXPORT_PROJECTS=${EXPORT_PROJECTS}
DEBUG=$(sanitize_var "${DEBUG}")

CUR_DATETIME_ISO=$(date +%Y-%m-%d)

if [[ -z "${DIR_NAME}" ]]; then
    DIR_NAME="export-${CUR_DATETIME_ISO}"
fi

mkdir -p "${OUTPUT_PATH}" > /dev/null 2>&1 || true
if [[ ! -d "${OUTPUT_PATH}" || ! -w "${OUTPUT_PATH}" ]]; then
    OUTPUT_PATH="."
fi

OUTPUT_PATH=$(echo "${OUTPUT_PATH}" | sed -r 's/\/$//')
DIR_NAME=$(echo "${DIR_NAME}" | sed -r 's/\/$//')
BASENAME="${OUTPUT_PATH}/${DIR_NAME}"

if [[ "${DEBUG}" -ne "0" ]]; then
    log_warn "Running in debug mode. This mode should not be used in production"
fi