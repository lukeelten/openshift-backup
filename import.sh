#!/bin/bash

PROJECT_BLACKLIST="default glusterfs kube-public kube-system management-infra openshift openshift-console openshift-infra openshift-logging openshift-metrics-server openshift-monitoring openshift-node openshift-sdn openshift-web-console"

EXPORT_DIR=$(echo "$1" | sed -r 's/(.*[^\/])\/?$/\1/')
if [[ ! -d "${EXPORT_DIR}" ]]; then
    echo "Usage: $0 <export directory>"
    exit 1
fi

CLUSTER_OBJECTS=$(find "${EXPORT_DIR}" -maxdepth 1 -type f | grep -E "\.json$" | sed -r "s/^(\.\/)?${EXPORT_DIR}\/?(.*)\.json/\2/" | xargs)

for OBJ in ${CLUSTER_OBJECTS}; do 
    echo "Importing ${OBJ}"
    oc apply -f "${EXPORT_DIR}/${OBJ}.json" > /dev/null
done

PROJECTS=$(find "${EXPORT_DIR}" -maxdepth 1 -type d | grep -v "${EXPORT_DIR}$" | sed -r "s/^(\.\/)?${EXPORT_DIR}\/?//")
# Remove blacklisted projects from list of projects
for REMOVE_PRJ in ${PROJECT_BLACKLIST}; do
    PROJECTS=$(echo "${PROJECTS}" | grep -v "${REMOVE_PRJ}")
done

PROJECTS=$(echo "${PROJECTS}" | xargs)

for PRJ in ${PROJECTS}; do
    echo "Importing project: ${PRJ}"
    oc apply -f "${EXPORT_DIR}/${PRJ}" > /dev/null
done

echo "Import finished"