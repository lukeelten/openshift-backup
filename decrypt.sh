#!/bin/bash

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <keyfile> <archive>"
    exit 1
fi

KEYFILE="$1"
ARCHIVE="$2"
BASENAME=$(echo "${ARCHIVE}" | sed -r 's/(\/?.*\/)*(.*)-encrypted.tar$/\2/')

echo "export-2019-03-27-encrypted.tar" | sed -r 's/-encrypted\.tar$//'
# Entpacken des Archives
tar xf "${ARCHIVE}"

# Entschluesseln des AES Keys
openssl rsautl -decrypt -inkey "${KEYFILE}" -in key.bin.enc -out key.bin

# Entschluesseln des Backups
openssl enc -d -aes256 -in "${BASENAME}.enc" -out "${BASENAME}.tar.gz" -pass "file:./key.bin"

# Entpacken des Backups
tar xzf "${BASENAME}.tar.gz"