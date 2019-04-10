OpenShift Backup
-----

*Project based on [openshift-backup](https://github.com/gerald1248/openshift-backup) by [gerald1248](https://github.com/gerald1248).*

This projects provides a tool which regularly creates backups of your OpenShift / OKD cluster.



# CLI Parameters
Use `./export.sh [--all] [--help] [<projectname>...]` to export one or more projects manually.

# Environment Variables

Environment Variable | Default Value | Description
-------------------- | ------------- | -----------
COMPRESS | 0 | This option enables compression after a successful backup. The original files are removed after compression.
ENCRYPT | 0 | This option enables encryption of the backup with RSA asymmetric encryption. If activated the path to the public key or the public key itself have to be provided in PEM format with this otpion. For more informatio see section Encryption.
OUTPUT_PATH | /backup | Gibt den Speicherort der Backups an. Sollte bestenfalls ein externer Datenträger oder Persistent Volume sein.
DIR_NAME | export-[YEAR]-[MONTH]-[DAY] | Contains the name of the directory where to store the backup. The default value is calculated using system time. Attention: There is no placeholder substitution if the default value is changed.
SECURE_DELETE | 1 | If this option is activated the backup files will be removed safely after compression or encryption.
EXPORT_ALL | 0 | If this option is set, the backup tool will export the whole cluster. This option override any given "EXPORT_PROJECTS" parameter.
EXPORT_PROJECTS | &lt;empty&gt; | This option allows to export one or more projects in particular. The projects have to be separated with a single space.

**Either EXPORT_PROJECTS or EXPORT_ALL have to be set in order to run this tool.**

# Deployment

Use the template provided in "cronjob.yml" to deploy the backup tool as cronjob into the cluster itself.
During deployment a service account and a cluster role will be added.
**Note:** The cluster role and hence also the serviceaccount, needs read access to **all** cluster resources. Be careful about who can access the backup project because anyone who can rsh into the backup pod can also read the whole cluster.


# Encryption

## Concept
The backup will contain any secret available in the projects which will be saved. So secure the sensible information the backup can be encrypted with an RSA public key. This ensures that only the administrator, who has to store the private key savely, can decrypt the backups even if someone manages to get access to the backup storage or to the backup tool instance itself.

## Configuration

Example Configuration to the 
```bash
# Pass path to find public key
export ENCRYPT="/backup/key.pem"
# Pass public key directly
export ENCRYPT="-----BEGIN PUBLIC KEY-----\nMIIBIjANBgkqhki\n-----END PUBLIC KEY-----"
```

## Generate Key Pair
The following bash commands show how to generate an encryption keypair to use with this backup tool.
```bash
# Generate new RSA keypair
ssh-keygen -t rsa -b 4096 -f backupkey
# Convert public key to PEM format
openssl rsa -in backupkey -pubout -out backupkey.pem
```

# Decryption

To decrypt an encrypted backup a shell script is available which performs all necessary steps automatically.
```bash
# Usage: ./decrypt.sh <keyfile> <archive>
./decrypt.sh "key.pem" "export-2019-03-28-encrypted.tar"
```

If for some reason the shell script is not available or apllicable, the backup can be decrypt manually with the following steps.
```bash
# Extract archive with encrypted files
tar xf "export-2019-03-28-encrypted.tar"
# Decrypt AES Key
openssl rsautl -decrypt -inkey "<PRIVATE KEYFILE>" -in key.bin.enc -out key.bin
# Decrypt backup archive
openssl enc -d -aes256 -in export-2019-03-28.enc -out export-2019-03-28.tar.gz -pass "file:./key.bin"
# Extract backup archive
tar xzf "export-2019-03-28.tar.gz"
```

# Import

### Automatic import via shell script
```bash
# Usage: ./import.sh <backup directory>
./import.sh "export-2019-03-28"
```

### Manual import 
```bash
# Import the cluster objects first
oc apply -f export/*.json
 
# After that import each project individually
oc apply -f export/projektname/
```