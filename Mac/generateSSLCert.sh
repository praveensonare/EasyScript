#!/bin/sh

if [ "$#" -ne 2 ]
then
  echo "Usage: Must supply a domain and PG_VERSION"
  exit 1
fi
DOMAIN=$1

COUNTRY="SG"
STATE="Singapore"
LOCATION="Singapore"
ORGANISATION="BLACKMAGIC DESIGN TECHNOLOGY PTE LTD"
UNIT="Resolve"
COMMON_NAME=""
EMAIL="support@blackmagicdesign.com"
SUBJECT="/C=AU/ST=NSW/L=Sydney/O=MongoDB/OU=root/CN=`hostname -f`/emailAddress=kevinadi@mongodb.com"

ROOT_KEY="root-ca.key"
ROOT_CERT="root-ca.pem"
SERVER_KEY="server-key.pem"
SERVER_CERT="server-cert.pem"
SERVER_CSR="server-cert.csr"

DB_DATA_DIR="/Library/PostgreSQL/${2}/data/"

SUBJECT="/C=${COUNTRY}/ST=${STATE}/L=${LOCATION}/O=${ORGANISATION}/OU=${UNIT}/CN=${COMMON_NAME}/emailAddress=${EMAIL}"
echo "SUBJECT : ${SUBJECT}"
openssl genrsa -out ${ROOT_KEY} 2048
chmod 600 ${ROOT_KEY}
openssl req -x509 -new -key ${ROOT_KEY} -days 10000 -out ${ROOT_CERT} -subj "${SUBJECT}"

COMMON_NAME=${DOMAIN}
SUBJECT="/C=${COUNTRY}/ST=${STATE}/L=${LOCATION}/O=${ORGANISATION}/OU=${UNIT}/CN=${COMMON_NAME}/emailAddress=${EMAIL}"
echo "SUBJECT : ${SUBJECT}"
openssl genrsa -out ${SERVER_KEY} 2048
chmod 600 ${SERVER_KEY}
openssl req -new -key ${SERVER_KEY} -out ${SERVER_CSR} -subj "${SUBJECT}"
openssl x509 -req -in ${SERVER_CSR} -CA ${ROOT_CERT} -CAkey ${ROOT_KEY} -CAcreateserial -out ${SERVER_CERT} -days 5000

rm ${DB_DATA_DIR}/${ROOT_CERT}
rm ${DB_DATA_DIR}/${SERVER_KEY}
rm ${DB_DATA_DIR}/${SERVER_CERT}
ls -ltra ${DB_DATA_DIR}
cp ${ROOT_CERT} ${DB_DATA_DIR}/.
cp ${SERVER_KEY} ${DB_DATA_DIR}/.
cp ${SERVER_CERT} ${DB_DATA_DIR}/.
ls -ltra ${DB_DATA_DIR}
exit 1


