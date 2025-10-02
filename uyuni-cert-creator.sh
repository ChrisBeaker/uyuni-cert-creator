#!/bin/bash

# A script to create server certificates signed by a local CA.
# It reads the subject info from the CA and sets the expiration to be
# one day before the CA's expiration date.

# --- Configuration ---
# Set the paths to your CA certificate and private key.
# ~ character will be expanded to the user's home directory.
# we assume user root is running this script.
CA_CERT_PATH="~/ssl-build/RHN-ORG-TRUSTED-SSL-CERT"
CA_KEY_PATH="~/ssl-build/RHN-ORG-PRIVATE-SSL-KEY"
# --- End Configuration ---


# --- Script Logic ---
# Use color codes for output makes it nicer ;-)
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Expand ~ to the full home directory path
CA_CERT=$(eval echo "$CA_CERT_PATH")
CA_KEY=$(eval echo "$CA_KEY_PATH")


# 1. Check for required tools and files
if ! command -v openssl &> /dev/null; then
    echo -e "${RED}Error: openssl command not found. Please install it.${NC}"
    exit 1
fi

if [ ! -f "$CA_CERT" ] || [ ! -f "$CA_KEY" ]; then
    echo -e "${RED}Error: CA certificate or key not found at the specified paths.${NC}"
    echo "CA Certificate expected at: $CA_CERT"
    echo "CA Key expected at: $CA_KEY"
    exit 1
fi

# --- Argument Parsing ---
usage() {
  echo "Usage: $0 -f <common_name_fqdn> [-s <san1,san2>] [-e <email>]"
  exit 1
}

FQDN=""
SANS=""
EMAIL_ADDRESS=""

while getopts "f:s:e:h" opt; do
  case $opt in
    f) FQDN="$OPTARG" ;;
    s) SANS="$OPTARG" ;;
    e) EMAIL_ADDRESS="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [ -z "$FQDN" ]; then
  echo -e "${RED}Error: No FQDN provided.${NC}"
  usage
fi
KEY_FILE="${FQDN}.key.pem"
CERT_FILE="${FQDN}.crt.pem"
CSR_FILE="${FQDN}.csr.pem"

if [ -f "$CERT_FILE" ]; then
  echo -e "${RED}Error: Certificate file '$CERT_FILE' already exists. Aborting.${NC}"
  exit 1
fi

echo "--- Starting Certificate Generation for: $FQDN ---"

# 2. Read the subject from the CA certificate and create the new subject
echo "Reading subject info from CA..."
CA_SUBJECT_LINE=$(openssl x509 -in "$CA_CERT" -noout -subject)

# Robustly parse and reformat the subject line from "C = DE, ..." to "/C=DE/..."
BASE_SUBJECT=$(echo "$CA_SUBJECT_LINE" | \
  sed -e 's/subject=//' \
      -e 's/, CN = [^,]*//' \
      -e 's/ = /=/g' \
      -e 's/, /\//g' \
      -e 's/^/\//' \
      -e 's/\/L=[^\/]*//')

# Construct the new subject string
NEW_SUBJECT="${BASE_SUBJECT}/CN=${FQDN}"
if [ -n "$EMAIL_ADDRESS" ]; then
  NEW_SUBJECT="${NEW_SUBJECT}/emailAddress=${EMAIL_ADDRESS}"
fi
echo "New certificate subject will be: ${NEW_SUBJECT}"

# 3. Read the expiration date from the CA and calculate the remaining days minus one
echo "Reading expiration date from CA..."
CA_END_DATE_STR=$(openssl x509 -in "$CA_CERT" -noout -enddate)
CA_END_DATE_VAL=${CA_END_DATE_STR#notAfter=}

# Get expiration and current date in seconds since epoch
END_SECONDS=$(date -d "$CA_END_DATE_VAL" "+%s")
NOW_SECONDS=$(date "+%s")

# MODIFIED: Calculate the difference in days and subtract one
VALIDITY_DAYS=$(( (END_SECONDS - NOW_SECONDS) / 86400 - 1 ))

# Add a safety check to ensure the CA is not already expired
if [ "$VALIDITY_DAYS" -le 0 ]; then
  echo -e "${RED}Error: CA has already expired or expires in less than one day. Cannot issue new certificate.${NC}"
  exit 1
fi
echo "CA expires in $((VALIDITY_DAYS + 1)) days. Setting new certificate validity to $VALIDITY_DAYS days."


# 4. Generate a new private key for the server certificate
echo "Generating private key: $KEY_FILE..."
openssl genpkey -algorithm RSA -out "$KEY_FILE" -pkeyopt rsa_keygen_bits:2048 &> /dev/null


# 5. Create a Certificate Signing Request (CSR)
echo "Generating CSR: $CSR_FILE..."
openssl req -new -key "$KEY_FILE" -out "$CSR_FILE" -subj "$NEW_SUBJECT"
if [ $? -ne 0 ]; then
    echo -e "${RED}✖ Error: Failed to create CSR. Check subject format.${NC}"
    exit 1
fi


# 6. Sign the certificate with the CA
echo "Signing certificate with CA key... (Password will be requested now)"

# Create a temporary config file for X509v3 extensions
TMP_CONF=$(mktemp)
cat > "$TMP_CONF" << EOF
[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
nsCertType = server
nsComment = "RHN SSL Tool Generated Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${FQDN}
EOF

# Add additional SANs if provided
if [ -n "$SANS" ]; then
  echo "SANs requested: $SANS. Creating certificate with extensions."
  i=2
  echo "$SANS" | tr ',' '\n' | while read -r san; do
    echo "DNS.$i = $san" >> "$TMP_CONF"
    i=$((i + 1))
  done
else
    echo "No SANs requested. Creating standard certificate."
fi

# Sign the certificate
openssl x509 -req -in "$CSR_FILE" \
  -CA "$CA_CERT" -CAkey "$CA_KEY" \
  -CAcreateserial -out "$CERT_FILE" -days "$VALIDITY_DAYS" -sha256 \
  -extfile "$TMP_CONF" -extensions v3_req
SIGNING_RESULT=$?

rm "$TMP_CONF"

# Check if signing was successful before cleaning up
if [ $SIGNING_RESULT -eq 0 ]; then
    rm "$CSR_FILE"
    echo -e "\n${GREEN}✔ Success!${NC}"
    echo "  Private Key:  $KEY_FILE"
    echo "  Certificate:  $CERT_FILE"
else
    echo -e "\n${RED}✖ Error: Certificate signing failed. Check the CA password or paths.${NC}"
    rm "$KEY_FILE" "$CSR_FILE" # Clean up all generated files on failure
    exit 1
fi
