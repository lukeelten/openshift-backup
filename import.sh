#!/bin/bash

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <export directory>"
    exit 1
fi

EXPORT_DIR="$1"
CLUSTER_OBJECTS=$(find "${EXPORT_DIR}" -maxdepth 1 -type f -name *.json | sed -r "s/^(\.\/)?${EXPORT_DIR}\/?(.*)\.json/\2/" | xargs)

for OBJ in ${CLUSTER_OBJECTS}; do 
    echo "Importing ${OBJ}"
    oc apply -f "${EXPORT_DIR}/${OBJ}.json" > /dev/null
done

PROJECTS=$(find "${EXPORT_DIR}" -maxdepth 1 -type d | grep -v "${EXPORT_DIR}$" | sed -r "s/^(\.\/)?${EXPORT_DIR}\/?//" | xargs)
for PRJ in ${PROJECTS}; do
    echo "Importing project: ${PRJ}"
    oc apply -f "${EXPORT_DIR}/${PRJ}" > /dev/null
done

echo "Import finished"