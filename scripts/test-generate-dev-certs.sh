#!/usr/bin/env bash
#
# Regression tests for CA mismatch handling. A small fake mkcert keeps the test
# self-contained and ensures no real CAROOT or trust store is touched.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
MOCK_BIN="$TEST_ROOT/bin"
MOCK_CAROOT="$TEST_ROOT/caroot"
TEST_CERT_DIR="$TEST_ROOT/certs"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN" "$MOCK_CAROOT" "$TEST_CERT_DIR"

cat >"$MOCK_BIN/mkcert" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-CAROOT" ]]; then
  printf '%s\n' "$MOCK_MKCERT_CAROOT"
  exit 0
fi

cert_file=""
key_file=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -cert-file)
      cert_file="$2"
      shift 2
      ;;
    -key-file)
      key_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$cert_file" && -n "$key_file" ]]
printf 'generated leaf certificate\n' >"$cert_file"
printf 'generated leaf private key\n' >"$key_file"
EOF
chmod +x "$MOCK_BIN/mkcert"

cat >"$MOCK_BIN/openssl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sha256 Fingerprint=TEST\n'
EOF
chmod +x "$MOCK_BIN/openssl"

printf 'current root CA\n' >"$MOCK_CAROOT/rootCA.pem"
printf 'old root CA\n' >"$TEST_CERT_DIR/ca.crt"
printf 'old leaf certificate\n' >"$TEST_CERT_DIR/localtest.me.crt"
printf 'old leaf private key\n' >"$TEST_CERT_DIR/localtest.me.key"
cp "$TEST_CERT_DIR/ca.crt" "$TEST_ROOT/old-ca.crt"

run_generator() {
  PATH="$MOCK_BIN:$PATH" \
    MOCK_MKCERT_CAROOT="$MOCK_CAROOT" \
    TRAEFIK_CERT_DIR="$TEST_CERT_DIR" \
    "$ROOT_DIR/scripts/generate-dev-certs.sh" "$@"
}

if run_generator --force >"$TEST_ROOT/force.out" 2>&1; then
  echo "Expected --force to reject a mismatched CA." >&2
  exit 1
fi

if ! grep -Fq "Refusing to overwrite the old CA certificate" "$TEST_ROOT/force.out"; then
  echo "The CA mismatch error did not explain the overwrite guard." >&2
  exit 1
fi

if ! grep -Fq "$TEST_CERT_DIR/ca.crt" "$TEST_ROOT/force.out"; then
  echo "The CA mismatch error did not report the overridden certificate path." >&2
  exit 1
fi

if ! cmp -s "$TEST_ROOT/old-ca.crt" "$TEST_CERT_DIR/ca.crt"; then
  echo "--force changed the stored CA despite the mismatch." >&2
  exit 1
fi

run_generator --replace-ca >"$TEST_ROOT/replace.out"

if ! cmp -s "$MOCK_CAROOT/rootCA.pem" "$TEST_CERT_DIR/ca.crt"; then
  echo "--replace-ca did not stage the current mkcert root." >&2
  exit 1
fi

if run_generator --replace-ca >"$TEST_ROOT/repeat.out" 2>&1; then
  echo "Expected --replace-ca to reject an already-current CA." >&2
  exit 1
fi

rm -f -- "$TEST_CERT_DIR/ca.crt"
if run_generator --replace-ca >"$TEST_ROOT/missing.out" 2>&1; then
  echo "Expected --replace-ca to reject a missing staged CA." >&2
  exit 1
fi

if ! grep -Fq "there is no staged CA to replace" "$TEST_ROOT/missing.out"; then
  echo "The missing staged CA error was not reported accurately." >&2
  exit 1
fi

if run_generator --unknown >"$TEST_ROOT/unknown.out" 2>&1; then
  echo "Expected an unknown argument to fail." >&2
  exit 1
fi

echo "Certificate lifecycle regression tests passed."
