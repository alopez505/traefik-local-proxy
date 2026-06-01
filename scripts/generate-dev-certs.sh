#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="$ROOT_DIR/certs"
DOMAIN="${DOMAIN:-localtest.me}"

CRT="$CERT_DIR/${DOMAIN}.crt"
KEY="$CERT_DIR/${DOMAIN}.key"
CA_CRT="$CERT_DIR/ca.crt"
CA_KEY="$CERT_DIR/ca.key"
CSR="$CERT_DIR/${DOMAIN}.csr"
CONF="$(mktemp)"

cleanup() {
  rm -f "$CSR" "$CERT_DIR/ca.srl" "$CONF"
}

trap cleanup EXIT

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required" >&2
  exit 1
fi

mkdir -p "$CERT_DIR"

if [[ "${1:-}" == "--force" ]]; then
  rm -f "$CRT" "$KEY" "$CA_CRT" "$CA_KEY" "$CSR" "$CERT_DIR/ca.srl"
fi

if [[ -f "$CRT" && -f "$KEY" && -f "$CA_CRT" && -f "$CA_KEY" ]]; then
  echo "Dev CA and wildcard cert already exist in certs/. Use --force to regenerate."
  exit 0
fi

# ---------------------------------------------------------------------------
# OpenSSL config for the leaf (server) certificate
# ---------------------------------------------------------------------------
cat > "$CONF" <<EOF
[req]
default_bits       = 2048
prompt             = no
default_md         = sha256
distinguished_name = dn
req_extensions     = req_ext

[dn]
C  = ${CERT_COUNTRY:-US}
ST = ${CERT_STATE:-CA}
L  = ${CERT_LOCALITY:-Local}
O  = ${CERT_ORG:-Local Development}
OU = ${CERT_OU:-Traefik Local Proxy}
CN = ${DOMAIN}

[req_ext]
subjectAltName     = @alt_names
basicConstraints   = critical,CA:FALSE
extendedKeyUsage   = serverAuth
keyUsage           = digitalSignature,keyEncipherment

[alt_names]
DNS.1 = ${DOMAIN}
DNS.2 = *.${DOMAIN}
DNS.3 = localhost
IP.1  = 127.0.0.1
EOF

echo "Generating local development CA (2-year validity)..."
openssl genrsa -out "$CA_KEY" 2048 >/dev/null 2>&1
openssl req -x509 -new -nodes -key "$CA_KEY" -sha256 -days 730 \
  -subj "/C=${CERT_COUNTRY:-US}/ST=${CERT_STATE:-CA}/L=${CERT_LOCALITY:-Local}/O=${CERT_ORG:-Local Development}/OU=${CERT_OU:-Traefik Local Proxy}/CN=${CERT_CA_CN:-Traefik Local Proxy Dev CA}" \
  -addext "basicConstraints = critical,CA:TRUE" \
  -addext "keyUsage = critical,keyCertSign,cRLSign" \
  -addext "subjectKeyIdentifier = hash" \
  -out "$CA_CRT" >/dev/null 2>&1

echo "Generating wildcard server certificate for ${DOMAIN} (825-day validity)..."
openssl genrsa -out "$KEY" 2048 >/dev/null 2>&1
openssl req -new -key "$KEY" -out "$CSR" -config "$CONF" >/dev/null 2>&1
openssl x509 -req -in "$CSR" \
  -CA "$CA_CRT" -CAkey "$CA_KEY" -CAcreateserial \
  -out "$CRT" -days 825 -sha256 -extensions req_ext -extfile "$CONF" >/dev/null 2>&1

# Harden permissions: private keys read only by owner, certs world-readable.
chmod 600 "$CA_KEY" "$KEY" 2>/dev/null || true
chmod 644 "$CA_CRT" "$CRT" 2>/dev/null || true

echo "Created:"
echo "  certs/ca.crt         (CA certificate - import into Windows trust store)"
echo "  certs/ca.key         (CA private key - keep local, do not share)"
echo "  certs/${DOMAIN}.crt"
echo "  certs/${DOMAIN}.key"
echo
echo "Next step: run 'mise run trust-ca' to import certs/ca.crt into Windows"
echo "CurrentUser\\Root (no admin required) so browsers trust HTTPS from WSL2."
echo
echo "Note: on a managed/corporate device, confirm that installing a custom"
echo "root CA is permitted by your IT policy before running trust-ca."
echo
echo "CA fingerprint (SHA-256):"
openssl x509 -in "$CA_CRT" -noout -fingerprint -sha256
