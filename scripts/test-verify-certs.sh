#!/usr/bin/env bash
#
# Regression tests for the certificate verifier. Generates throwaway RSA and
# EC pairs directly with openssl in a sandbox - no mkcert dependency needed
# for these checks, and nothing here touches a real CA or trust store.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

run_verify() {
  "$ROOT_DIR/scripts/verify-certs.sh" "$@"
}

gen_rsa_pair() {
  local dir="$1"
  mkdir -p "$dir"
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
    -subj "/CN=localtest.me" \
    -addext "subjectAltName=DNS:localtest.me,DNS:*.localtest.me" \
    -keyout "$dir/leaf.key" -out "$dir/leaf.crt" >/dev/null 2>&1
  chmod 600 "$dir/leaf.key"
}

gen_ec_pair() {
  local dir="$1"
  mkdir -p "$dir"
  openssl ecparam -name prime256v1 -genkey -noout -out "$dir/leaf.key" >/dev/null 2>&1
  openssl req -x509 -new -key "$dir/leaf.key" -sha256 -days 1 \
    -subj "/CN=localtest.me" \
    -addext "subjectAltName=DNS:localtest.me,DNS:*.localtest.me" \
    -out "$dir/leaf.crt" >/dev/null 2>&1
  chmod 600 "$dir/leaf.key"
}

# 1. Matching RSA pair passes (expiry WARN is expected for a 1-day cert; no
# FAIL means the overall exit code is 0).
rsa_dir="$TEST_ROOT/rsa"
gen_rsa_pair "$rsa_dir"
if ! out="$(run_verify --cert "$rsa_dir/leaf.crt" --key "$rsa_dir/leaf.key" 2>&1)"; then
  echo "Expected a matching RSA pair to pass, got:" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -q "PASS pairing" <<<"$out"; then
  echo "Expected a PASS pairing line for a matching RSA pair, got:" >&2
  echo "$out" >&2
  exit 1
fi

# 2. Matching EC pair passes too - the pairing check must be key-type-agnostic.
ec_dir="$TEST_ROOT/ec"
gen_ec_pair "$ec_dir"
if ! out="$(run_verify --cert "$ec_dir/leaf.crt" --key "$ec_dir/leaf.key" 2>&1)"; then
  echo "Expected a matching EC pair to pass, got:" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -q "PASS pairing" <<<"$out"; then
  echo "Expected a PASS pairing line for a matching EC pair, got:" >&2
  echo "$out" >&2
  exit 1
fi

# 3. Mismatched cert/key fails, regardless of key type.
mismatch_dir="$TEST_ROOT/mismatch"
mkdir -p "$mismatch_dir"
cp "$rsa_dir/leaf.crt" "$mismatch_dir/leaf.crt"
cp "$ec_dir/leaf.key" "$mismatch_dir/leaf.key"
if run_verify --cert "$mismatch_dir/leaf.crt" --key "$mismatch_dir/leaf.key" >"$TEST_ROOT/mismatch.out" 2>&1; then
  echo "Expected a mismatched cert/key pair to fail." >&2
  cat "$TEST_ROOT/mismatch.out" >&2
  exit 1
fi
if ! grep -q "FAIL pairing" "$TEST_ROOT/mismatch.out"; then
  echo "Expected a FAIL pairing line for a mismatched pair, got:" >&2
  cat "$TEST_ROOT/mismatch.out" >&2
  exit 1
fi

# 4. SAN coverage is a WARN, not a FAIL, when the certificate covers
# different names on purpose.
other_san_dir="$TEST_ROOT/other-san"
mkdir -p "$other_san_dir"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
  -subj "/CN=example.internal" \
  -addext "subjectAltName=DNS:example.internal" \
  -keyout "$other_san_dir/leaf.key" -out "$other_san_dir/leaf.crt" >/dev/null 2>&1
chmod 600 "$other_san_dir/leaf.key"
if ! out="$(run_verify --cert "$other_san_dir/leaf.crt" --key "$other_san_dir/leaf.key" 2>&1)"; then
  echo "Expected a certificate with different SAN coverage to still pass overall (WARN, not FAIL), got:" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -q "WARN SAN coverage" <<<"$out"; then
  echo "Expected a WARN SAN coverage line, got:" >&2
  echo "$out" >&2
  exit 1
fi

# 5. Key file permissions: WARN (not FAIL) when not 600.
loose_dir="$TEST_ROOT/loose-perms"
gen_rsa_pair "$loose_dir"
chmod 644 "$loose_dir/leaf.key"
if ! out="$(run_verify --cert "$loose_dir/leaf.crt" --key "$loose_dir/leaf.key" 2>&1)"; then
  echo "Expected loose key permissions to still pass overall (WARN, not FAIL), got:" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -q "WARN permissions" <<<"$out"; then
  echo "Expected a WARN permissions line, got:" >&2
  echo "$out" >&2
  exit 1
fi

# 6. Missing cert/key files are a hard FAIL with a clear message.
if run_verify --cert "$TEST_ROOT/nope.crt" --key "$TEST_ROOT/nope.key" >"$TEST_ROOT/missing.out" 2>&1; then
  echo "Expected missing cert/key files to fail." >&2
  exit 1
fi

# 7. Unknown arguments are rejected.
if run_verify --cert "$rsa_dir/leaf.crt" --key "$rsa_dir/leaf.key" --bogus >/dev/null 2>&1; then
  echo "Expected an unknown argument to fail." >&2
  exit 1
fi

# 8. A flag with no value fails cleanly with a usage message, instead of an
# unbound-variable crash under set -u.
if run_verify --cert >"$TEST_ROOT/missing-value.out" 2>&1; then
  echo "Expected --cert with no value to fail." >&2
  exit 1
fi
if ! grep -q "Missing value for --cert" "$TEST_ROOT/missing-value.out"; then
  echo "Expected a clear missing-value message, got:" >&2
  cat "$TEST_ROOT/missing-value.out" >&2
  exit 1
fi

# 9. SAN coverage must not false-positive on a substring match: a SAN of
# exactly "notlocaltest.me" contains the substring "localtest.me" but is not
# actually covered, so this must WARN like any other uncovered certificate.
false_positive_dir="$TEST_ROOT/false-positive-san"
mkdir -p "$false_positive_dir"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
  -subj "/CN=notlocaltest.me" \
  -addext "subjectAltName=DNS:notlocaltest.me" \
  -keyout "$false_positive_dir/leaf.key" -out "$false_positive_dir/leaf.crt" >/dev/null 2>&1
chmod 600 "$false_positive_dir/leaf.key"
if ! out="$(run_verify --cert "$false_positive_dir/leaf.crt" --key "$false_positive_dir/leaf.key" 2>&1)"; then
  echo "Expected a substring-only SAN match to still pass overall (WARN, not FAIL), got:" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -q "WARN SAN coverage" <<<"$out"; then
  echo "Expected a WARN SAN coverage line for DNS:notlocaltest.me (substring match, not a real cover), got:" >&2
  echo "$out" >&2
  exit 1
fi

# 10. SAN coverage requires the wildcard: an apex-only "DNS:localtest.me" does
# not cover any routed *.localtest.me subdomain, so it must WARN, not PASS.
apex_only_dir="$TEST_ROOT/apex-only-san"
mkdir -p "$apex_only_dir"
openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
  -subj "/CN=localtest.me" \
  -addext "subjectAltName=DNS:localtest.me" \
  -keyout "$apex_only_dir/leaf.key" -out "$apex_only_dir/leaf.crt" >/dev/null 2>&1
chmod 600 "$apex_only_dir/leaf.key"
if ! out="$(run_verify --cert "$apex_only_dir/leaf.crt" --key "$apex_only_dir/leaf.key" 2>&1)"; then
  echo "Expected an apex-only certificate to still pass overall (WARN, not FAIL), got:" >&2
  echo "$out" >&2
  exit 1
fi
if ! grep -q "WARN SAN coverage" <<<"$out"; then
  echo "Expected a WARN SAN coverage line for an apex-only DNS:localtest.me SAN, got:" >&2
  echo "$out" >&2
  exit 1
fi

# 11. An invalid/unreadable certificate must FAIL cleanly on expiry and still
# run the remaining diagnostics, not abort the whole script under set -e when
# the openssl expiry pipeline returns nonzero.
invalid_dir="$TEST_ROOT/invalid-cert"
gen_rsa_pair "$invalid_dir"
printf 'not a certificate\n' >"$invalid_dir/leaf.crt"
if run_verify --cert "$invalid_dir/leaf.crt" --key "$invalid_dir/leaf.key" >"$TEST_ROOT/invalid.out" 2>&1; then
  echo "Expected an invalid certificate to fail overall." >&2
  cat "$TEST_ROOT/invalid.out" >&2
  exit 1
fi
if ! grep -q "FAIL expiry" "$TEST_ROOT/invalid.out"; then
  echo "Expected a FAIL expiry line (script must not abort before it), got:" >&2
  cat "$TEST_ROOT/invalid.out" >&2
  exit 1
fi

echo "Certificate verification regression tests passed."
