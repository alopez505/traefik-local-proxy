#!/usr/bin/env bash
#
# Imports a certificate/key pair out of an arbitrary container image without
# ever starting it. Validates the pair (parseable, matching) before touching
# the real destination files, and rolls back a --force overwrite that fails
# partway through. Never prints private key contents.

set -euo pipefail

IMAGE=""
CERT_PATH_IN_IMAGE=""
KEY_PATH_IN_IMAGE=""
DEST_DIR="./certs"
DEST_CERT=""
DEST_KEY=""
FORCE=0

usage() {
  cat <<'EOF'
Usage: import-certs-from-image.sh IMAGE --cert-path PATH --key-path PATH
                                   [--dest-dir DIR] [--dest-cert FILE]
                                   [--dest-key FILE] [--force]

  IMAGE          Image to import from. Recommend pinning by digest, e.g.
                 myregistry/certs@sha256:..., so the import is reproducible.
  --cert-path    Path to the certificate inside the image (required).
  --key-path     Path to the private key inside the image (required).
  --dest-dir     Directory the default filenames land in (default: ./certs).
  --dest-cert    Full destination path for the certificate, overriding the
                 default "<dest-dir>/imported.crt". Point this at
                 <dest-dir>/localtest.me.crt to make the import the active
                 certificate (see TRAEFIK_CERTIFICATE_FILE in .env.example).
  --dest-key     Full destination path for the key, overriding the default
                 "<dest-dir>/imported.key".
  --force        Overwrite existing destination files. Without it, an
                 existing destination file is left untouched and the import
                 fails.

The image is never started (docker create, never run/start). The
certificate and key are validated against each other before either
destination file is touched; an invalid or mismatched pair is rejected and
nothing is installed. With --force, if writing the new pair fails partway
through, the previous pair is restored.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cert-path)
      CERT_PATH_IN_IMAGE="$2"
      shift 2
      ;;
    --key-path)
      KEY_PATH_IN_IMAGE="$2"
      shift 2
      ;;
    --dest-dir)
      DEST_DIR="$2"
      shift 2
      ;;
    --dest-cert)
      DEST_CERT="$2"
      shift 2
      ;;
    --dest-key)
      DEST_KEY="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [[ -n "$IMAGE" ]]; then
        echo "Unexpected extra argument: $1" >&2
        usage >&2
        exit 2
      fi
      IMAGE="$1"
      shift
      ;;
  esac
done

if [[ -z "$IMAGE" || -z "$CERT_PATH_IN_IMAGE" || -z "$KEY_PATH_IN_IMAGE" ]]; then
  echo "IMAGE, --cert-path, and --key-path are all required." >&2
  usage >&2
  exit 2
fi

DEST_CERT="${DEST_CERT:-$DEST_DIR/imported.crt}"
DEST_KEY="${DEST_KEY:-$DEST_DIR/imported.key}"

if [[ ( -e "$DEST_CERT" || -e "$DEST_KEY" ) && "$FORCE" -ne 1 ]]; then
  echo "Refusing to overwrite existing destination files without --force:" >&2
  [[ -e "$DEST_CERT" ]] && echo "  $DEST_CERT" >&2
  [[ -e "$DEST_KEY" ]] && echo "  $DEST_KEY" >&2
  exit 1
fi

mkdir -p "$DEST_DIR" "$(dirname "$DEST_CERT")" "$(dirname "$DEST_KEY")"

echo "Pulling $IMAGE..."
docker pull "$IMAGE"

CONTAINER_ID="$(docker create "$IMAGE")"
STAGE_DIR=""

cleanup() {
  local status=$?
  docker rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true
  if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
    rm -rf -- "$STAGE_DIR" || true
  fi
  exit "$status"
}
trap cleanup EXIT

STAGE_DIR="$(mktemp -d "${DEST_DIR%/}/.certificate-import.XXXXXX")"

docker cp "$CONTAINER_ID:$CERT_PATH_IN_IMAGE" "$STAGE_DIR/cert"
docker cp "$CONTAINER_ID:$KEY_PATH_IN_IMAGE" "$STAGE_DIR/key"

chmod 644 "$STAGE_DIR/cert" 2>/dev/null || true
chmod 600 "$STAGE_DIR/key" 2>/dev/null || true

if ! openssl x509 -in "$STAGE_DIR/cert" -noout -enddate >/dev/null 2>&1; then
  echo "Refusing to install: the imported certificate file is not a valid certificate." >&2
  exit 1
fi

cert_pubkey="$(openssl x509 -in "$STAGE_DIR/cert" -noout -pubkey 2>/dev/null || true)"
key_pubkey="$(openssl pkey -in "$STAGE_DIR/key" -pubout 2>/dev/null || true)"
if [[ -z "$cert_pubkey" || -z "$key_pubkey" || "$cert_pubkey" != "$key_pubkey" ]]; then
  echo "Refusing to install: the imported certificate and key do not match." >&2
  exit 1
fi

backup_cert=""
backup_key=""
if [[ "$FORCE" -eq 1 ]]; then
  if [[ -e "$DEST_CERT" ]]; then
    backup_cert="$STAGE_DIR/backup-cert"
    cp -p "$DEST_CERT" "$backup_cert"
  fi
  if [[ -e "$DEST_KEY" ]]; then
    backup_key="$STAGE_DIR/backup-key"
    cp -p "$DEST_KEY" "$backup_key"
  fi
fi

install_failed=0
if ! mv -f "$STAGE_DIR/cert" "$DEST_CERT"; then
  install_failed=1
elif ! mv -f "$STAGE_DIR/key" "$DEST_KEY"; then
  install_failed=1
fi

if [[ "$install_failed" -eq 1 ]]; then
  echo "Install failed partway through - rolling back." >&2
  if [[ -n "$backup_cert" ]]; then
    cp -p "$backup_cert" "$DEST_CERT"
  elif [[ -e "$DEST_CERT" && -z "$backup_cert" ]]; then
    rm -f "$DEST_CERT"
  fi
  if [[ -n "$backup_key" ]]; then
    cp -p "$backup_key" "$DEST_KEY"
  fi
  exit 1
fi

echo "Imported certificate -> $DEST_CERT"
echo "Imported key         -> $DEST_KEY"
echo "Next: run 'mise run certificates:verify', and if this should become the"
echo "active certificate, update TRAEFIK_CERTIFICATE_FILE/TRAEFIK_CERTIFICATE_KEY_FILE in .env."
