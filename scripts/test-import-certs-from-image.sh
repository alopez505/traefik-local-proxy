#!/usr/bin/env bash
#
# Regression tests for the certificate importer. A fake `docker` binary
# keeps the test self-contained, offline, and fast, and lets it assert the
# importer never calls `docker run`/`start` - it never touches a real
# registry or a real image.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
MOCK_BIN="$TEST_ROOT/bin"
FAKE_IMAGE_FILES="$TEST_ROOT/fake-image-files"

cleanup() {
  chmod -R u+w "$TEST_ROOT" 2>/dev/null || true
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN" "$FAKE_IMAGE_FILES/certs"

# Fake `docker` supporting exactly the subcommands the importer uses. Any
# `run`/`start` invocation is a hard test failure - the importer must never
# start the source image.
cat >"$MOCK_BIN/docker" <<EOF
#!/usr/bin/env bash
set -euo pipefail

FAKE_IMAGE_FILES="$FAKE_IMAGE_FILES"

case "\${1:-}" in
  pull)
    echo "(fake) pulled \$2"
    exit 0
    ;;
  create)
    echo "fakecontainerid0123456789"
    exit 0
    ;;
  rm)
    exit 0
    ;;
  cp)
    src="\$2"
    dest="\$3"
    path="\${src#*:}"
    if [[ ! -e "\$FAKE_IMAGE_FILES\$path" ]]; then
      echo "docker cp: no such path in fake image: \$path" >&2
      exit 1
    fi
    cp "\$FAKE_IMAGE_FILES\$path" "\$dest"
    exit 0
    ;;
  run | start)
    echo "TEST FAILURE: docker \$1 must never be called by the importer" >&2
    exit 1
    ;;
  *)
    echo "unexpected docker invocation: \$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$MOCK_BIN/docker"

# A valid, matching RSA pair as the fake image's cert/key content.
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
  -subj "/CN=localtest.me" \
  -addext "subjectAltName=DNS:localtest.me,DNS:*.localtest.me" \
  -keyout "$FAKE_IMAGE_FILES/certs/valid.key" -out "$FAKE_IMAGE_FILES/certs/valid.crt" >/dev/null 2>&1

# A mismatched key for the mismatch test.
openssl genrsa -out "$FAKE_IMAGE_FILES/certs/other.key" 2048 >/dev/null 2>&1

# Not a certificate at all, for the invalid-cert test.
printf 'not a certificate\n' >"$FAKE_IMAGE_FILES/certs/invalid.crt"

run_importer() {
  PATH="$MOCK_BIN:$PATH" "$ROOT_DIR/scripts/import-certs-from-image.sh" "$@"
}

# 1. Successful import: matching pair, correct permissions, no run/start call,
# no private key content anywhere in the captured output.
dest1="$TEST_ROOT/dest1"
mkdir -p "$dest1"
out="$(run_importer fake-image:1 --cert-path /certs/valid.crt --key-path /certs/valid.key --dest-dir "$dest1" 2>&1)"
if [[ ! -f "$dest1/imported.crt" || ! -f "$dest1/imported.key" ]]; then
  echo "Expected both files to be installed, got:" >&2
  echo "$out" >&2
  exit 1
fi
if grep -q "TEST FAILURE" <<<"$out"; then
  echo "Importer invoked docker run/start:" >&2
  echo "$out" >&2
  exit 1
fi
if grep -qi "BEGIN.*PRIVATE KEY" <<<"$out"; then
  echo "Importer printed private key contents to its own output:" >&2
  echo "$out" >&2
  exit 1
fi
key_perms="$(stat -c '%a' "$dest1/imported.key" 2>/dev/null || stat -f '%Lp' "$dest1/imported.key")"
if [[ "$key_perms" != "600" ]]; then
  echo "Expected imported key permissions 600, got $key_perms." >&2
  exit 1
fi

# 2. Overwrite refusal without --force.
if run_importer fake-image:1 --cert-path /certs/valid.crt --key-path /certs/valid.key --dest-dir "$dest1" >"$TEST_ROOT/refuse.out" 2>&1; then
  echo "Expected a re-import without --force to fail." >&2
  exit 1
fi
if ! grep -q "Refusing to overwrite" "$TEST_ROOT/refuse.out"; then
  echo "Expected an overwrite-refusal message, got:" >&2
  cat "$TEST_ROOT/refuse.out" >&2
  exit 1
fi

# 3. Mismatched cert/key pair is rejected before install; nothing written.
dest2="$TEST_ROOT/dest2"
mkdir -p "$dest2"
if run_importer fake-image:1 --cert-path /certs/valid.crt --key-path /certs/other.key --dest-dir "$dest2" >"$TEST_ROOT/mismatch.out" 2>&1; then
  echo "Expected a mismatched pair to be rejected." >&2
  exit 1
fi
if [[ -e "$dest2/imported.crt" || -e "$dest2/imported.key" ]]; then
  echo "Expected no files to be installed for a mismatched pair." >&2
  exit 1
fi

# 4. Invalid certificate content is rejected before install.
dest3="$TEST_ROOT/dest3"
mkdir -p "$dest3"
if run_importer fake-image:1 --cert-path /certs/invalid.crt --key-path /certs/valid.key --dest-dir "$dest3" >"$TEST_ROOT/invalid.out" 2>&1; then
  echo "Expected an invalid certificate to be rejected." >&2
  exit 1
fi
if [[ -e "$dest3/imported.crt" ]]; then
  echo "Expected no certificate to be installed for invalid content." >&2
  exit 1
fi

# 5. Missing path inside the image (simulated docker cp failure) leaves no
# half-written destination file.
dest4="$TEST_ROOT/dest4"
mkdir -p "$dest4"
if run_importer fake-image:1 --cert-path /certs/does-not-exist.crt --key-path /certs/valid.key --dest-dir "$dest4" >"$TEST_ROOT/copyfail.out" 2>&1; then
  echo "Expected a missing in-image path to fail." >&2
  exit 1
fi
if [[ -e "$dest4/imported.crt" || -e "$dest4/imported.key" ]]; then
  echo "Expected no files to be installed after a docker cp failure." >&2
  exit 1
fi

# 6. Forced replacement that fails partway through rolls back to the
# original pair. Force the key move to fail by making its destination
# directory read-only after the cert has already been moved.
dest5_cert_dir="$TEST_ROOT/dest5-cert"
dest5_key_dir="$TEST_ROOT/dest5-key"
mkdir -p "$dest5_cert_dir" "$dest5_key_dir"
printf 'original cert\n' >"$dest5_cert_dir/active.crt"
printf 'original key\n' >"$dest5_key_dir/active.key"
chmod 555 "$dest5_key_dir"
if run_importer fake-image:1 --cert-path /certs/valid.crt --key-path /certs/valid.key \
  --dest-cert "$dest5_cert_dir/active.crt" --dest-key "$dest5_key_dir/active.key" \
  --dest-dir "$dest5_cert_dir" --force >"$TEST_ROOT/rollback.out" 2>&1; then
  echo "Expected the forced replacement to fail when the key move fails." >&2
  chmod u+w "$dest5_key_dir"
  exit 1
fi
chmod u+w "$dest5_key_dir"
if ! grep -q "rolling back" "$TEST_ROOT/rollback.out"; then
  echo "Expected a rollback message, got:" >&2
  cat "$TEST_ROOT/rollback.out" >&2
  exit 1
fi
if [[ "$(cat "$dest5_cert_dir/active.crt")" != "original cert" ]]; then
  echo "Expected the original certificate to be restored after rollback." >&2
  exit 1
fi
if [[ "$(cat "$dest5_key_dir/active.key")" != "original key" ]]; then
  echo "Expected the original key to be untouched after the failed move." >&2
  exit 1
fi

# 7. Missing required arguments and unknown flags are rejected.
if run_importer fake-image:1 --cert-path /certs/valid.crt >/dev/null 2>&1; then
  echo "Expected a missing --key-path to fail." >&2
  exit 1
fi
if run_importer fake-image:1 --cert-path /certs/valid.crt --key-path /certs/valid.key --bogus >/dev/null 2>&1; then
  echo "Expected an unknown argument to fail." >&2
  exit 1
fi

# 8. A flag with no value fails cleanly with a usage message, instead of an
# unbound-variable crash under set -u.
if run_importer fake-image:1 --cert-path >"$TEST_ROOT/missing-value.out" 2>&1; then
  echo "Expected --cert-path with no value to fail." >&2
  exit 1
fi
if ! grep -q "Missing value for --cert-path" "$TEST_ROOT/missing-value.out"; then
  echo "Expected a clear missing-value message, got:" >&2
  cat "$TEST_ROOT/missing-value.out" >&2
  exit 1
fi

# 9. Identical destination cert/key paths are rejected before anything is
# pulled or written, so a private key can never be left where the cert should
# be under a false success.
dest_same="$TEST_ROOT/dest-same"
mkdir -p "$dest_same"
if run_importer fake-image:1 --cert-path /certs/valid.crt --key-path /certs/valid.key \
  --dest-cert "$dest_same/same.pem" --dest-key "$dest_same/same.pem" >"$TEST_ROOT/same-dest.out" 2>&1; then
  echo "Expected identical --dest-cert/--dest-key to be rejected." >&2
  exit 1
fi
if ! grep -q "must be different paths" "$TEST_ROOT/same-dest.out"; then
  echo "Expected an identical-destination rejection message, got:" >&2
  cat "$TEST_ROOT/same-dest.out" >&2
  exit 1
fi
if [[ -e "$dest_same/same.pem" ]]; then
  echo "Expected nothing to be written when destinations are identical." >&2
  exit 1
fi

echo "Certificate import regression tests passed."
