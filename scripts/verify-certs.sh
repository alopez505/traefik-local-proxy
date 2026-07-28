#!/usr/bin/env bash
#
# Verifies a certificate/key pair: expiry, SAN coverage, cert/key pairing,
# chain structure, and key file permissions. Takes explicit --cert/--key
# paths and does not read .env itself - `mise run certificates:verify` is
# what resolves the currently-configured paths and passes them in, so this
# script always verifies whatever paths you actually give it.

set -euo pipefail

CERT=""
KEY=""

usage() {
  cat <<'EOF'
Usage: verify-certs.sh --cert FILE --key FILE

Checks (each prints PASS, WARN, or FAIL):
  - expiry            FAIL if already expired, WARN if within 30 days
  - SAN coverage       WARN only if localtest.me/*.localtest.me are absent -
                       a legitimate bring-your-own certificate may cover
                       different names on purpose
  - cert/key pairing   FAIL on mismatch - the certificate's public key must
                       match the private key
  - chain structure    full chain verification against certs/ca.crt when its
                       subject matches the leaf's issuer, otherwise a
                       structural summary with a note that chain trust
                       cannot be verified locally
  - key permissions    WARN (not FAIL) if the key file is not mode 600

Exits 0 if there are no FAILs (WARNs are still printed), 1 otherwise.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cert)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --cert" >&2
        usage >&2
        exit 2
      fi
      CERT="$2"
      shift 2
      ;;
    --key)
      if [[ -z "${2:-}" ]]; then
        echo "Missing value for --key" >&2
        usage >&2
        exit 2
      fi
      KEY="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$CERT" || -z "$KEY" ]]; then
  echo "Both --cert and --key are required." >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$CERT" ]]; then
  echo "FAIL expiry: certificate file not found: $CERT" >&2
  exit 1
fi

if [[ ! -f "$KEY" ]]; then
  echo "FAIL pairing: key file not found: $KEY" >&2
  exit 1
fi

FAILED=0

# --- Expiry ------------------------------------------------------------------
# Use openssl -checkend for the actual decisions: it is portable, whereas
# `date -d` is GNU-only and would silently skip the expiry check on BSD/macOS.
# The human-readable end date is still read, for display only.
end_date_raw="$(openssl x509 -in "$CERT" -noout -enddate 2>/dev/null | sed 's/^notAfter=//' || true)"
if ! openssl x509 -in "$CERT" -noout -enddate >/dev/null 2>&1; then
  echo "FAIL expiry: could not read the certificate's expiry date."
  FAILED=1
elif ! openssl x509 -in "$CERT" -noout -checkend 0 >/dev/null 2>&1; then
  echo "FAIL expiry: certificate has expired${end_date_raw:+ (was valid until $end_date_raw)}."
  FAILED=1
elif ! openssl x509 -in "$CERT" -noout -checkend "$((30 * 24 * 3600))" >/dev/null 2>&1; then
  echo "WARN expiry: certificate expires soon${end_date_raw:+ ($end_date_raw)}."
else
  echo "PASS expiry: certificate is valid${end_date_raw:+ until $end_date_raw}."
fi

# --- SAN coverage --------------------------------------------------------------
# Routed hosts are all *.localtest.me subdomains (proxy.localtest.me,
# demo.localtest.me, ...), so the wildcard SAN is what actually matters. An
# apex-only "localtest.me" SAN covers none of those routes, so require the
# wildcard specifically rather than any localtest.me match.
san="$(openssl x509 -in "$CERT" -noout -ext subjectAltName 2>/dev/null || true)"
if grep -Eq 'DNS:\*\.localtest\.me([,[:space:]]|$)' <<<"$san"; then
  echo "PASS SAN coverage: *.localtest.me is covered."
else
  echo "WARN SAN coverage: *.localtest.me not found in the certificate's SAN - expected for a bring-your-own certificate covering different names, otherwise routed hosts such as proxy.localtest.me will not be covered."
fi

# --- Cert/key pairing ----------------------------------------------------------
cert_pubkey="$(openssl x509 -in "$CERT" -noout -pubkey 2>/dev/null || true)"
key_pubkey="$(openssl pkey -in "$KEY" -pubout 2>/dev/null || true)"
if [[ -z "$cert_pubkey" || -z "$key_pubkey" ]]; then
  echo "FAIL pairing: could not derive a public key from the certificate and/or key file."
  FAILED=1
elif [[ "$cert_pubkey" == "$key_pubkey" ]]; then
  echo "PASS pairing: the certificate and key match."
else
  echo "FAIL pairing: the certificate's public key does not match the private key."
  FAILED=1
fi

# --- Chain structure -------------------------------------------------------
cert_dir="$(dirname "$CERT")"
ca_crt="$cert_dir/ca.crt"
if [[ -f "$ca_crt" ]]; then
  cert_issuer="$(openssl x509 -in "$CERT" -noout -issuer 2>/dev/null || true)"
  ca_subject="$(openssl x509 -in "$ca_crt" -noout -subject 2>/dev/null || true)"
  if [[ -n "$cert_issuer" && "${cert_issuer#issuer=}" == "${ca_subject#subject=}" ]]; then
    if openssl verify -CAfile "$ca_crt" "$CERT" >/dev/null 2>&1; then
      echo "PASS chain: verifies against $ca_crt."
    else
      echo "FAIL chain: does not verify against $ca_crt despite a matching issuer/subject."
      FAILED=1
    fi
  else
    echo "WARN chain: $ca_crt does not match this certificate's issuer - printing structural details only."
    openssl x509 -in "$CERT" -noout -issuer -subject 2>/dev/null || true
  fi
else
  echo "WARN chain: no $ca_crt found alongside the certificate - chain trust cannot be verified locally."
  openssl x509 -in "$CERT" -noout -issuer -subject 2>/dev/null || true
fi

# --- Key file permissions ----------------------------------------------------
key_perms="$(stat -c '%a' "$KEY" 2>/dev/null || stat -f '%Lp' "$KEY" 2>/dev/null || true)"
if [[ "$key_perms" == "600" ]]; then
  echo "PASS permissions: key file is mode 600."
else
  echo "WARN permissions: key file is mode ${key_perms:-unknown}, expected 600."
fi

exit "$FAILED"
