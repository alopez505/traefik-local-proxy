#!/usr/bin/env bash
set -euo pipefail

# Generate the local development TLS material with mkcert.
#
# mkcert manages a local CA in its CAROOT (outside this repo) and signs a leaf
# covering localtest.me, *.localtest.me, localhost, and the loopback IPs. The
# CA private key never enters the repo; only the leaf cert/key and a copy of the
# CA certificate land in certs/.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${TRAEFIK_CERT_DIR:-$ROOT_DIR/certs}"

CRT="$CERT_DIR/localtest.me.crt"
KEY="$CERT_DIR/localtest.me.key"
CA_CRT="$CERT_DIR/ca.crt"

usage() {
  cat <<EOF
Usage: generate-dev-certs.sh [--force | --replace-ca]

  --force       Regenerate the leaf certificate using the same mkcert CA.
  --replace-ca  Replace $CA_CRT after the old CA has been untrusted.
                Prefer the guarded workflow: mise run replace-ca
EOF
}

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
REPLACE_CA=0

case "${1:-}" in
  "")
    ;;
  --force)
    FORCE=1
    ;;
  --replace-ca)
    FORCE=1
    REPLACE_CA=1
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    echo "Unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
esac

if [[ "$#" -gt 1 ]]; then
  echo "Only one argument is supported." >&2
  usage >&2
  exit 2
fi

CAROOT="$(mkcert -CAROOT)"
CURRENT_CA="$CAROOT/rootCA.pem"
CA_MISMATCH=0

if [[ -f "$CA_CRT" ]]; then
  if [[ ! -f "$CURRENT_CA" ]] || ! cmp -s "$CURRENT_CA" "$CA_CRT"; then
    CA_MISMATCH=1
  fi
fi

if [[ "$CA_MISMATCH" -eq 1 && "$REPLACE_CA" -eq 0 ]]; then
  echo "Error: $CA_CRT does not match mkcert's current root CA." >&2
  echo "Refusing to overwrite the old CA certificate, including with --force," >&2
  echo "because it is needed to remove the exact old root from trust stores." >&2
  echo >&2
  echo "Run 'mise run replace-ca' to untrust the old Windows root before replacing it." >&2
  echo "Remove the old CA separately from any other trust stores where you installed it." >&2
  exit 1
fi

if [[ "$REPLACE_CA" -eq 1 && "$CA_MISMATCH" -eq 0 ]]; then
  echo "Error: $CA_CRT already matches mkcert's current root CA." >&2
  echo "Use --force if you only want to regenerate the leaf certificate." >&2
  exit 1
fi

if [[ -f "$CRT" && -f "$KEY" && -f "$CA_CRT" && "$FORCE" -eq 0 ]]; then
  echo "Certificates already exist in $CERT_DIR. Use --force to regenerate the leaf."
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
if [[ ! -f "$CAROOT/rootCA.pem" ]]; then
  echo "Error: mkcert did not create its root CA at $CAROOT/rootCA.pem." >&2
  exit 1
fi
cp "$CAROOT/rootCA.pem" "$CA_CRT"

chmod 600 "$KEY" 2>/dev/null || true
chmod 644 "$CRT" "$CA_CRT" 2>/dev/null || true

echo "Created:"
echo "  $CRT (wildcard leaf, mkcert-signed)"
echo "  $KEY (leaf private key - keep local, do not share)"
echo "  $CA_CRT (mkcert root CA - import into a trust store)"
echo
echo "mkcert CAROOT (holds the CA and its private key): $CAROOT"
if [[ "$CERT_DIR" == "$ROOT_DIR/certs" ]]; then
  echo
  echo "Next step: run 'mise run trust-ca' to import $CA_CRT into Windows"
  echo "CurrentUser\\Root (no admin required) so Windows browsers trust HTTPS from WSL2."
fi
echo "Optional, to also trust HTTPS from inside WSL (curl, etc.): mkcert -install"
echo
echo "Note: on a managed/corporate device, confirm that installing a custom"
echo "root CA is permitted by your IT policy before trusting the CA."

if command -v openssl >/dev/null 2>&1; then
  echo
  echo "CA fingerprint (SHA-256):"
  openssl x509 -in "$CA_CRT" -noout -fingerprint -sha256
fi
