#!/bin/bash

set -eo pipefail

BASE=$(dirname "$0")

source "${BASE}/scripts/common.sh"
source "${BASE}/scripts/project.sh"
source "${BASE}/scripts/cluster.sh"


if [[ $# -gt 1 ]]; then
    EXPORT_PROJECTS="$*"
elif [[ $# -eq 1 ]]; then 
    if [[ "$1" == "--help" ||  "$1" == "-h" ]]; then
        usage
        exit 0
    fi

    if [[ "$1" == "--all" ]]; then
        EXPORT_ALL=1
    else 
        EXPORT_PROJECTS="${EXPORT_PROJECTS} $1"
    fi
fi

checkoc

if [[ ! -z "${EXPORT_ALL}" && "${EXPORT_ALL}" != "0" ]]; then
    make_base
    export_cluster
elif [[ ! -z "${EXPORT_PROJECTS}" ]]; then
    make_base
    export_projects "${EXPORT_PROJECTS}"
else
    usage
    die "Invalid usage" 1
fi

echo

if [[ ! -z "${COMPRESS}" && "${COMPRESS}" != "0" ]]; then
    compress_export
fi

if [[ ! -z "${ENCRYPT}" && "${ENCRYPT}" != "0" ]]; then
    encrypt_export "${ENCRYPT}"
fi

exit 0
