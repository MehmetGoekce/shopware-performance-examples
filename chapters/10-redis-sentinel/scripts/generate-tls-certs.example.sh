#!/usr/bin/env bash
#
# generate-tls-certs.example.sh
#
# Erzeugt eine selbstsignierte Test-CA + Server-Cert (mit SubjectAltNames
# fuer alle 3 Sentinel-Nodes) + Client-Cert fuer Redis-TLS-Setup.
#
# NUR FUER TEST- UND STAGING-UMGEBUNGEN. Production-Setups verwenden:
#   - Let's Encrypt fuer publik erreichbare Hostnames
#   - Interne PKI (Microsoft AD CS, HashiCorp Vault PKI, OpenBao, etc.)
#   - Kubernetes cert-manager fuer K8s-Deployments
#
# Diese Test-CA hat KEINE Revocation, KEIN OCSP-Stapling, KEIN Auto-Renewal.
#
# Verwendung:
#   ./generate-tls-certs.example.sh /etc/redis/tls
#
# Anschliessend Permissions setzen:
#   sudo chown -R redis:redis /etc/redis/tls
#   sudo chmod 640 /etc/redis/tls/*.key
#   sudo chmod 644 /etc/redis/tls/*.crt

set -euo pipefail

TARGET_DIR="${1:?Verzeichnis muss angegeben werden, z.B. /etc/redis/tls}"

# Sentinel-Node-Hostnames anpassen!
NODE1_HOST="redis-node1.example.lan"
NODE2_HOST="redis-node2.example.lan"
NODE3_HOST="redis-node3.example.lan"

mkdir -p "${TARGET_DIR}"
cd "${TARGET_DIR}"

echo "==> 1. Test-CA (Root) erzeugen"
openssl genrsa -out ca.key 4096
openssl req -x509 -new -nodes -key ca.key \
    -sha256 -days 3650 \
    -subj "/C=CH/ST=Test/L=Test/O=Test CA/CN=Redis Test CA" \
    -out ca.crt

echo "==> 2. Server-Cert mit SubjectAltNames erzeugen"
openssl genrsa -out server.key 2048
openssl req -new -key server.key \
    -subj "/C=CH/ST=Test/L=Test/O=Test/CN=${NODE1_HOST}" \
    -out server.csr

cat > server.ext <<EOF
subjectAltName = @alt_names
[alt_names]
DNS.1 = ${NODE1_HOST}
DNS.2 = ${NODE2_HOST}
DNS.3 = ${NODE3_HOST}
DNS.4 = localhost
IP.1  = 127.0.0.1
EOF

openssl x509 -req -in server.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out server.crt -days 365 -sha256 \
    -extfile server.ext

echo "==> 3. Client-Cert erzeugen (fuer Mutual TLS)"
openssl genrsa -out client.key 2048
openssl req -new -key client.key \
    -subj "/C=CH/ST=Test/L=Test/O=Test/CN=redis-client" \
    -out client.csr
openssl x509 -req -in client.csr \
    -CA ca.crt -CAkey ca.key -CAcreateserial \
    -out client.crt -days 365 -sha256

echo "==> 4. Aufraeumen"
rm -f server.csr server.ext client.csr ca.srl

echo ""
echo "Fertig. Generierte Dateien in ${TARGET_DIR}:"
ls -la "${TARGET_DIR}"

echo ""
echo "Naechste Schritte:"
echo "  sudo chown -R redis:redis ${TARGET_DIR}"
echo "  sudo chmod 640 ${TARGET_DIR}/*.key"
echo "  sudo chmod 644 ${TARGET_DIR}/*.crt"
echo "  sudo systemctl restart redis-server redis-sentinel"
echo ""
echo "Test (auf einem Node):"
echo "  redis-cli --tls --cert ${TARGET_DIR}/client.crt --key ${TARGET_DIR}/client.key --cacert ${TARGET_DIR}/ca.crt -a \"\${REDIS_AUTH_PASSWORD}\" PING"
