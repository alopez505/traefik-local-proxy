#!/usr/bin/env bash
#
# Regression tests for the advisory exposure checker. A fake `docker` binary
# keeps the test self-contained and lets it simulate a large, unrelated
# environment dump the way `docker compose config --environment` actually
# produces one in practice.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
MOCK_BIN="$TEST_ROOT/bin"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN"

# Fake `docker compose config --environment` that prints whatever the test
# staged at $FAKE_ENV_DUMP, padded with a large block of unrelated shell vars
# first - the real command dumps the entire merged environment, not a
# filtered view, so the checker must grep for its keys rather than assume a
# short/clean output.
cat >"$MOCK_BIN/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "compose" && "${2:-}" == "config" && "${3:-}" == "--environment" ]]; then
  for i in $(seq 1 300); do
    printf 'UNRELATED_VAR_%d=some-value-%d\n' "$i" "$i"
  done
  if [[ -n "${FAKE_ENV_DUMP:-}" ]]; then
    cat "$FAKE_ENV_DUMP"
  fi
  exit 0
fi

echo "unexpected docker invocation: $*" >&2
exit 1
EOF
chmod +x "$MOCK_BIN/docker"

run_checker() {
  PATH="$MOCK_BIN:$PATH" FAKE_ENV_DUMP="$1" "$ROOT_DIR/scripts/check-exposure.sh"
}

# 1. Loopback defaults (no relevant vars set at all): silent, exit 0.
printf '' >"$TEST_ROOT/defaults.env"
out="$(run_checker "$TEST_ROOT/defaults.env")"
if [[ -n "$out" ]]; then
  echo "Expected silence on loopback defaults, got: $out" >&2
  exit 1
fi

# 2. Explicit loopback values buried among decoys: still silent.
cat >"$TEST_ROOT/explicit-loopback.env" <<'EOF'
TRAEFIK_WEB_BIND_ADDRESS=127.0.0.1
TRAEFIK_TCP_BIND_ADDRESS=127.0.0.1
TRAEFIK_DASHBOARD_ENABLED=true
EOF
out="$(run_checker "$TEST_ROOT/explicit-loopback.env")"
if [[ -n "$out" ]]; then
  echo "Expected silence on explicit loopback values, got: $out" >&2
  exit 1
fi

# 3. Non-loopback web bind + dashboard enabled: warns about both.
cat >"$TEST_ROOT/web-exposed.env" <<'EOF'
TRAEFIK_WEB_BIND_ADDRESS=0.0.0.0
TRAEFIK_DASHBOARD_ENABLED=true
EOF
out="$(run_checker "$TEST_ROOT/web-exposed.env" 2>&1)"
if [[ "$out" != *"TRAEFIK_WEB_BIND_ADDRESS"* || "$out" != *"dashboard"* ]]; then
  echo "Expected a web-bind + dashboard warning, got: $out" >&2
  exit 1
fi

# 4. Non-loopback web bind + dashboard disabled: no dashboard warning.
cat >"$TEST_ROOT/web-exposed-no-dashboard.env" <<'EOF'
TRAEFIK_WEB_BIND_ADDRESS=0.0.0.0
TRAEFIK_DASHBOARD_ENABLED=false
EOF
out="$(run_checker "$TEST_ROOT/web-exposed-no-dashboard.env" 2>&1)"
if [[ -n "$out" ]]; then
  echo "Expected silence when the dashboard is disabled, got: $out" >&2
  exit 1
fi

# 5. Non-loopback TCP bind: warns, regardless of dashboard/web settings.
cat >"$TEST_ROOT/tcp-exposed.env" <<'EOF'
TRAEFIK_TCP_BIND_ADDRESS=0.0.0.0
EOF
out="$(run_checker "$TEST_ROOT/tcp-exposed.env" 2>&1)"
if [[ "$out" != *"TRAEFIK_TCP_BIND_ADDRESS"* ]]; then
  echo "Expected a TCP-bind warning, got: $out" >&2
  exit 1
fi

# 6. Never fails, even when both exposure settings warn simultaneously.
cat >"$TEST_ROOT/both-exposed.env" <<'EOF'
TRAEFIK_WEB_BIND_ADDRESS=0.0.0.0
TRAEFIK_TCP_BIND_ADDRESS=0.0.0.0
TRAEFIK_DASHBOARD_ENABLED=true
EOF
PATH="$MOCK_BIN:$PATH" FAKE_ENV_DUMP="$TEST_ROOT/both-exposed.env" "$ROOT_DIR/scripts/check-exposure.sh" >/dev/null 2>&1
status=$?
if [[ "$status" -ne 0 ]]; then
  echo "Expected exit 0 even when warnings fire, got exit $status." >&2
  exit 1
fi

# 7. Never fails even if `docker compose config --environment` itself fails.
cat >"$MOCK_BIN/docker" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MOCK_BIN/docker"
PATH="$MOCK_BIN:$PATH" "$ROOT_DIR/scripts/check-exposure.sh" >/dev/null 2>&1
status=$?
if [[ "$status" -ne 0 ]]; then
  echo "Expected exit 0 even when the underlying docker compose call fails, got exit $status." >&2
  exit 1
fi

echo "Exposure checker regression tests passed."
