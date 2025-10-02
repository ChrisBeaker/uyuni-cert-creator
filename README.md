# Uyuni Certificate Creator

A shell script to generate server certificates signed by a local Certificate Authority (CA).

This script simplifies the process of creating SSL certificates for services like Uyuni/SUSE Manager. It automatically inherits subject information (like Organization, Country, etc.) from the CA certificate and sets the new certificate's expiration to be one day before the CA's expiration date.

## Prerequisites

*   `openssl`: The OpenSSL command-line tool must be installed and available in your system's PATH.
*   **CA Certificate and Key**: You must have access to the CA's certificate (`RHN-ORG-TRUSTED-SSL-CERT`) and its private key (`RHN-ORG-PRIVATE-SSL-KEY`).

## Configuration

Before running the script, you may need to configure the paths to your CA certificate and private key. Edit the following variables at the top of the `uyuni-cert-creator.sh` script:

```bash
# Set the paths to your CA certificate and private key.
# ~ character will be expanded to the user's home directory.
# we assume user root is running this script.
CA_CERT_PATH="~/ssl-build/RHN-ORG-TRUSTED-SSL-CERT"
CA_KEY_PATH="~/ssl-build/RHN-ORG-PRIVATE-SSL-KEY"
```

## Usage

The script requires a Fully Qualified Domain Name (FQDN) for the certificate's Common Name (CN). You can also provide optional Subject Alternative Names (SANs) and an email address.

```shell
./uyuni-cert-creator.sh -f <common_name_fqdn> [-s <san1,san2,...>] [-e <email>]
```

### Options

*   `-f <common_name_fqdn>`: **(Required)** The FQDN for the certificate's Common Name. For example, `uyuni.example.com`.
*   `-s <san1,san2,...>`: (Optional) A comma-separated list of Subject Alternative Names (SANs). For example, `reportdb,db`.
*   `-e <email>`: (Optional) An email address to be included in the certificate subject.
*   `-h`: Display the help message.

## Examples

### Basic Certificate

To create a certificate for a server with a single hostname:

```shell
./uyuni-cert-creator.sh -f uyuni.example.com
```

### Certificate with SANs

To create a certificate for a database server that might be accessed via multiple hostnames:

```shell
./uyuni-cert-creator.sh -f uyuni-db.example.com -s "reportdb,db"
```

### Certificate with Email Address

To include an email address in the certificate:

```shell
./uyuni-cert-creator.sh -f uyuni.example.com -e 'admin@example.com'
```

## Output

On successful execution, the script will generate two files in the current directory, named after the FQDN provided:

*   `<fqdn>.key.pem`: The private key for the new certificate. **Keep this file secure.**
*   `<fqdn>.crt.pem`: The newly signed public certificate.

## Security

During the signing process, you will be prompted to enter the password for the CA private key (`CA_KEY_PATH`).

```
Signing certificate with CA key... (Password will be requested now)
Enter pass phrase for /root/ssl-build/RHN-ORG-PRIVATE-SSL-KEY:
```

The script will clean up the temporary Certificate Signing Request (CSR) file upon success, but on failure, it will remove all generated files to avoid leaving partial or insecure artifacts.