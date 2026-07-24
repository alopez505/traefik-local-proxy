#!/usr/bin/env bash
set -euo pipefail

# Generate the local development TLS material with mkcert.
#
# mkcert manages a local CA in its CAROOT (outside this repo) and signs a leaf
# covering localtest.me, *.localtest.me, localhost, and the loopback IPs. The
# CA private key never enters the repo; only the leaf cert/key and a copy of the
# CA certificate land in certs/.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="$ROOT_DIR/certs"

CRT="$CERT_DIR/localtest.me.crt"
KEY="$CERT_DIR/localtest.me.key"
CA_CRT="$CERT_DIR/ca.crt"

if ! command -v mkcert >/dev/null 2>&1; then
  echo "mkcert is required but was not found on PATH." >&2
  echo >&2
  echo "Install it one of these ways:" >&2
  echo "  - mise install            (this repo pins mkcert in mise.toml)" >&2
  echo "  - https://github.com/FiloSottile/mkcert#installation" >&2
  exit 1
fi

mkdir -p "$CERT_DIR"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

if [[ -f "$CRT" && -f "$KEY" && -f "$CA_CRT" && "$FORCE" -eq 0 ]]; then
  CAROOT="$(mkcert -CAROOT)"
  CURRENT_CA="$CAROOT/rootCA.pem"

  if [[ ! -f "$CURRENT_CA" ]]; then
    echo "Error: mkcert root CA not found at $CURRENT_CA." >&2
    echo "Run mkcert -install, then regenerate the certificates." >&2
    exit 1
  fi

  if ! cmp -s "$CURRENT_CA" "$CA_CRT"; then
    echo "Error: certs/ca.crt does not match mkcert's current root CA." >&2
    echo "Run this command again with --force to regenerate the leaf and CA copy." >&2
    echo "Then run 'mise run trust-ca' to trust the new CA in Windows." >&2
    exit 1
  fi

  echo "Certificates already exist in certs/. Use --force to regenerate the leaf."
  exit 0
fi

# Signing the leaf below creates the mkcert local CA on first use if it does
# not exist yet. Regenerating with --force reuses the same CA, so a CA already
# trusted via 'mise run trust-ca' stays trusted (no re-import needed).
echo "Generating wildcard certificate for localtest.me with mkcert..."
mkcert -cert-file "$CRT" -key-file "$KEY" \
  localtest.me "*.localtest.me" localhost 127.0.0.1 ::1

# Stage the mkcert root CA so the Windows trust step can import it. The CA
# private key stays in CAROOT and is intentionally not copied here.
CAROOT="$(mkcert -CAROOT)"
cp "$CAROOT/rootCA.pem" "$CA_CRT"

chmod 600 "$KEY" 2>/dev/null || true
chmod 644 "$CRT" "$CA_CRT" 2>/dev/null || true

echo "Created:"
echo "  certs/localtest.me.crt (wildcard leaf, mkcert-signed)"
echo "  certs/localtest.me.key (leaf private key - keep local, do not share)"
echo "  certs/ca.crt          (mkcert root CA - import into Windows trust store)"
echo
echo "mkcert CAROOT (holds the CA and its private key): $CAROOT"
echo
echo "Next step: run 'mise run trust-ca' to import certs/ca.crt into Windows"
echo "CurrentUser\\Root (no admin required) so Windows browsers trust HTTPS from WSL2."
echo "Optional, to also trust HTTPS from inside WSL (curl, etc.): mkcert -install"
echo
echo "Note: on a managed/corporate device, confirm that installing a custom"
echo "root CA is permitted by your IT policy before trusting the CA."

if command -v openssl >/dev/null 2>&1; then
  echo
  echo "CA fingerprint (SHA-256):"
  openssl x509 -in "$CA_CRT" -noout -fingerprint -sha256
fi
