#!/bin/bash

# Function to export one project
export_project() {
    # Has to be global. Do not make it local
    PROJECT="$1"

    if [[ -z "${PROJECT}" ]]; then
        echo "Error: No project name given" > /dev/stderr
        return
    fi

    # Switch to project
    oc project "${PROJECT}" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        echo "Error: The given project \"${PROJECT}\" does not exist." > /dev/stderr
        return
    fi

    # Check whether export directory already exists
    if [[ -d "${BASENAME}/${PROJECT}" ]]; then
        rm -rf "${BASENAME}/${PROJECT}/" > /dev/null
    fi
    mkdir -p "${BASENAME}/${PROJECT}/" > /dev/null

    local OBJECTS=$(namespace_objects_config)

    for OBJ in ${OBJECTS}; do
        echo "Exporting ${OBJ} of project ${PROJECT}"

        # the script checks whether there is a function with the name of the object to export
        # if so the function will be called to export the object, otherwise a default machanism will run
        # This is a special hack to customize the way to export some of the objects without maintaining a list of special treatments
        # Simply define a function with the name of the object to customize the export process
        if [[ ! -z $(declare -F "${OBJ}") ]]; then
            local BUFFER=$(${OBJ})
        else
            local BUFFER=$(export_type "${OBJ}")
            local BUFFER=$(delete_common_attr "${BUFFER}")
        fi

        # Check if result contains an empty list
        local BUFFER=$(truncate_empty_list "${BUFFER}")

        # If result is not empty write to file
        if [[ ! -z "${BUFFER}" ]]; then
            echo "Write result to ${PROJECT}/${OBJ}.json"
            echo "${BUFFER}" > "${BASENAME}/${PROJECT}/${OBJ}.json"
        else
            echo "... Empty result ... Skipping"
        fi

        echo
    done
}

pv() {
    if [[ -z "${PROJECT}" ]]; then
        # It is too dangerous to simply export all PVs
        return
    fi

    local PV=$(oc get pvc -n "${PROJECT}" --no-headers 2> /dev/null | awk '{print $3}' | xargs)
    if [[ -z "${PV}" ]]; then
        return
    fi

    local BUFFER=$(oc get --export -o json pv ${PV})
    if [[ -z "${BUFFER}" ]]; then
        return
    fi

    local BUFFER=$(make_list "${BUFFER}")
    local BUFFER=$(delete_common_attr "${BUFFER}")
    delete_attr "${BUFFER}" "del(.items[].spec.claimRef.resourceVersion,.items[].spec.claimRef.uid)"
}

serviceaccount(){
    local BUFFER=$(export_type serviceaccounts)
    local BUFFER=$(delete_common_attr "${BUFFER}")
    local BUFFER=$(delete_attr "${BUFFER}" 'del(.items[]|select(.metadata.name=="builder"))')
    local BUFFER=$(delete_attr "${BUFFER}" 'del(.items[]|select(.metadata.name=="deployer"))')
    local BUFFER=$(delete_attr "${BUFFER}" 'del(.items[]|select(.metadata.name=="default"))')
    echo "${BUFFER}"
}

replicaset(){
    local BUFFER=$(export_type replicasets)
    local BUFFER=$(delete_common_attr "${BUFFER}")
    echo "${BUFFER}" | jq 'del(.items[].ownerReferences.uid)'
}

deployment() {
    local BUFFER=$(export_type replicasets)
    local BUFFER=$(delete_common_attr "${BUFFER}")
    echo "${BUFFER}" | jq 'del(.items[].metadata.annotations["deployment.kubernetes.io/revision"])'
}

secret(){
    local BUFFER=$(export_type secrets)
    local BUFFER=$(delete_common_attr "${BUFFER}")
    local BUFFER=$(delete_attr "${BUFFER}" 'del(.items[]|select(.type=="kubernetes.io/service-account-token")) | del(.items[].metadata.annotations."kubernetes.io/service-account.uid")')
    delete_attr "${BUFFER}" 'del(.items[]|select(.metadata.annotations["service.alpha.openshift.io/originating-service-name"] != null))'
}

dc(){
    local BUFFER=$(export_type dc)
    local BUFFER=$(delete_common_attr "${BUFFER}")
    echo "${BUFFER}" | jq 'del(.items[].spec.triggers[].imageChangeParams.lastTriggeredImage)'
}

bc(){
    local BUFFER=$(export_type bc)
    local BUFFER=$(delete_common_attr "${BUFFER}")
    echo "${BUFFER}" | jq 'del(.items[].spec.triggers[].imageChangeParams.lastTriggeredImage)'
}

is(){
    local BUFFER=$(export_type is)
    local BUFFER=$(delete_common_attr "${BUFFER}")
    echo "${BUFER}" | jq 'del(.items[].metadata.annotations."openshift.io/image.dockerRepositoryCheck")'
}

svc(){
    local BUFFER=$(export_type svc)
    local BUFFER=$(delete_common_attr "${BUFFER}")
    echo "${BUFFER}" | jq 'del(.items[].spec.clusterIP,.items[].metadata.annotations["service.alpha.openshift.io/serving-cert-signed-by"])'
}

pvc(){
    local BUFFER=$(export_type pvc)
    local BUFFER=$(delete_common_attr "${BUFFER}")
    delete_attr "${BUFFER}" 'del('\
'.items[].metadata.annotations["pv.kubernetes.io/bind-completed"],'\
'.items[].metadata.annotations["pv.kubernetes.io/bound-by-controller"],'\
'.items[].metadata.annotations["volume.beta.kubernetes.io/storage-provisioner"],'\
'.items[].spec.volumeName)'
}

pod() {
    local BUFFER=$(export_type pod)
    delete_attr "${BUFFER}" 'del(.items[]|select(.metadata.ownerReferences[].controller==true))'
}