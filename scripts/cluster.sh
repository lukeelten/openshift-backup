#!/bin/bash

export_cluster() {
    echo "Exporting all projects"
    local PROJECTS=$(get_all_projects)

    echo 
    export_cluster_objects
    export_projects "${PROJECTS}"
}

# Function to export the concrete project objects
export_project_objects() {
    if [[ -z  "$1" ]]; then
        return
    fi

    local BUFFER=$(oc get ns $* --export -o json)
    local BUFFER=$(make_list "${BUFFER}")

    delete_common_attr "${BUFFER}"
}

# Exports a given list of projects
export_projects() {
    if [[ -z  "$1" ]]; then
        return
    fi

    export_project_objects "$*" > "${BASENAME}/projects.json"

    for PRJ in $*; do
        echo "Exporting project: ${PRJ}"
        echo 
        
        export_project "${PRJ}"
    done
}

# Loads all projects
get_all_projects() {
    oc get projects --no-headers | awk '{ print $1 }' | xargs
}

# Exports cluster objects
export_cluster_objects() {
    # It is important to set PROJECT to an empty string
    # Save current value to a local variable and restore value afterwards
    local PRJ_TMP="${PROJECT}"
    PROJECT=""

    local OBJECTS=$(cluster_objects_config)

    for OBJ in ${OBJECTS}; do
        echo "Exporting cluster obejcts ${OBJ}"

        if [[ ! -z $(declare -F "${OBJ}") ]]; then
            local BUFFER=$(${OBJ})
        else
            local BUFFER=$(export_type "${OBJ}")
            local BUFFER=$(delete_common_attr "${BUFFER}")
        fi

        local BUFFER=$(truncate_empty_list "${BUFFER}")

        if [[ ! -z "${BUFFER}" ]]; then
            echo "Write result to ${OBJ}.json"
            echo "${BUFFER}" > "${BASENAME}/${OBJ}.json"
        else
            echo "... Empty result ... Skipping"
        fi

        echo
    done

    PROJECT="${PRJ_TMP}"
}

clusterrole() {
    local BUFFER=$(export_type clusterrole)
    local BUFFER=$(echo "${BUFFER}" | jq 'del(.items[] | select(.metadata.annotations["authorization.openshift.io/system-only"]=="true"))')
    local BUFFER=$(delete_common_attr "${BUFFER}")
    echo "${BUFFER}"
}

namespace() {
    local BUFFER=$(export_type namespace)
    local BUFFER=$(echo "${BUFFER}" | jq 'del (.items[] | select(.metadata.labels["project-key"]==null))')
    local BUFFER=$(delete_attr "${BUFFER}" 'del(.items[].metadata.namespace')
    echo "${BUFFER}"
}