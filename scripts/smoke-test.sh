#!/usr/bin/env bash
#
# Live routing smoke test. Uses high loopback ports and a dedicated network,
# and refuses to disturb an existing stack that uses the fixed container names.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROXY_PROJECT="traefik-local-proxy-smoke"
DEMO_PROJECT="traefik-whoami-smoke"
SMOKE_SUFFIX="$$"
SMOKE_NETWORK="traefik-proxy-smoke-$SMOKE_SUFFIX"
HTTP_PORT="${SMOKE_HTTP_PORT:-18080}"
HTTPS_PORT="${SMOKE_HTTPS_PORT:-18443}"
CRT="$ROOT_DIR/certs/localtest.me.crt"
KEY="$ROOT_DIR/certs/localtest.me.key"
GENERATED_CERTS=0
HEADERS_FILE="$(mktemp)"

export TRAEFIK_PROXY_NETWORK="$SMOKE_NETWORK"
export TRAEFIK_HTTP_PORT="$HTTP_PORT"
export TRAEFIK_HTTPS_PORT="$HTTPS_PORT"
export TRAEFIK_LOG_LEVEL="INFO"

proxy_https() {
  docker compose --project-name "$PROXY_PROJECT" \
    --env-file "$ROOT_DIR/.env.example" \
    -f "$ROOT_DIR/docker-compose.yml" "$@"
}

proxy_http() {
  docker compose --project-name "$PROXY_PROJECT" \
    --env-file "$ROOT_DIR/.env.example" \
    -f "$ROOT_DIR/docker-compose.http.yml" "$@"
}

demo_https() {
  docker compose --project-name "$DEMO_PROJECT" \
    --env-file "$ROOT_DIR/.env.example" \
    -f "$ROOT_DIR/examples/whoami/docker-compose.yml" "$@"
}

demo_http() {
  docker compose --project-name "$DEMO_PROJECT" \
    --env-file "$ROOT_DIR/.env.example" \
    -f "$ROOT_DIR/examples/whoami/docker-compose.http.yml" "$@"
}

cleanup() {
  set +e
  demo_https down --remove-orphans >/dev/null 2>&1
  proxy_https down --remove-orphans >/dev/null 2>&1
  if [[ "$GENERATED_CERTS" -eq 1 ]]; then
    rm -f -- "$CRT" "$KEY"
  fi
  rm -f -- "$HEADERS_FILE"
}
trap cleanup EXIT

for container in traefik-local traefik-socket-proxy traefik-whoami-demo; do
  if docker container inspect "$container" >/dev/null 2>&1; then
    echo "Refusing to run: container '$container' already exists." >&2
    echo "Stop the active proxy/demo stack before running this smoke test." >&2
    exit 1
  fi
done

if [[ -f "$CRT" && -f "$KEY" ]]; then
  :
elif [[ -e "$CRT" || -e "$KEY" ]]; then
  echo "Refusing to replace an incomplete local certificate pair." >&2
  exit 1
else
  mkdir -p "$ROOT_DIR/certs"
  openssl req -x509 -newkey rsa:2048 -sha256 -nodes -days 1 \
    -subj "/CN=localtest.me" \
    -addext "subjectAltName=DNS:localtest.me,DNS:*.localtest.me" \
    -keyout "$KEY" -out "$CRT" >/dev/null 2>&1
  chmod 600 "$KEY"
  GENERATED_CERTS=1
fi

wait_for_health() {
  local health

  for _ in {1..30}; do
    health="$(docker inspect --format '{{.State.Health.Status}}' traefik-local 2>/dev/null || true)"
    if [[ "$health" == "healthy" ]]; then
      return 0
    fi
    sleep 2
  done

  echo "Traefik did not become healthy." >&2
  docker logs traefik-local >&2 || true
  return 1
}

wait_for_url() {
  local url="$1"
  shift

  for _ in {1..30}; do
    if curl --fail --silent --show-error --max-time 2 --noproxy '*' \
      "$@" "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for $url" >&2
  docker logs traefik-local >&2 || true
  docker inspect traefik-whoami-demo \
    --format 'whoami networks={{json .NetworkSettings.Networks}} labels={{json .Config.Labels}}' \
    >&2 || true
  return 1
}

assert_status() {
  local expected="$1"
  local url="$2"
  shift 2
  local actual

  actual="$(curl --silent --show-error --max-time 5 --output /dev/null \
    --write-out '%{http_code}' --noproxy '*' "$@" "$url")"
  if [[ "$actual" != "$expected" ]]; then
    echo "Expected HTTP $expected from $url, received $actual." >&2
    return 1
  fi
}

assert_https_mode() {
  wait_for_health
  wait_for_url "https://demo.localtest.me:$HTTPS_PORT/" \
    --insecure --resolve "demo.localtest.me:$HTTPS_PORT:127.0.0.1"
  assert_status 200 "https://demo.localtest.me:$HTTPS_PORT/" \
    --insecure --resolve "demo.localtest.me:$HTTPS_PORT:127.0.0.1"
  wait_for_url "https://proxy.localtest.me:$HTTPS_PORT/api/version" \
    --insecure --resolve "proxy.localtest.me:$HTTPS_PORT:127.0.0.1"
  assert_status 200 "https://proxy.localtest.me:$HTTPS_PORT/api/version" \
    --insecure --resolve "proxy.localtest.me:$HTTPS_PORT:127.0.0.1"

  curl --silent --show-error --max-time 5 --output /dev/null \
    --dump-header "$HEADERS_FILE" \
    --noproxy '*' \
    --resolve "demo.localtest.me:$HTTP_PORT:127.0.0.1" \
    "http://demo.localtest.me:$HTTP_PORT/"

  if ! grep -Eq '^HTTP/[0-9.]+ 302 ' "$HEADERS_FILE"; then
    echo "Expected a temporary HTTP 302 redirect." >&2
    sed -n '1,12p' "$HEADERS_FILE" >&2
    return 1
  fi

  if ! grep -Fqi "Location: https://demo.localtest.me:${HTTPS_PORT}/" "$HEADERS_FILE"; then
    echo "Redirect did not target the published HTTPS port $HTTPS_PORT." >&2
    sed -n '1,12p' "$HEADERS_FILE" >&2
    return 1
  fi
}

echo "Starting HTTPS mode on 127.0.0.1:$HTTP_PORT and 127.0.0.1:$HTTPS_PORT..."
proxy_https up -d
demo_https up -d
assert_https_mode

echo "Switching the same Compose projects to HTTP-only mode..."
proxy_http up -d
demo_http up -d
wait_for_health
wait_for_url "http://demo.localtest.me:$HTTP_PORT/" \
  --resolve "demo.localtest.me:$HTTP_PORT:127.0.0.1"
assert_status 200 "http://demo.localtest.me:$HTTP_PORT/" \
  --resolve "demo.localtest.me:$HTTP_PORT:127.0.0.1"
wait_for_url "http://proxy.localtest.me:$HTTP_PORT/api/version" \
  --resolve "proxy.localtest.me:$HTTP_PORT:127.0.0.1"
assert_status 200 "http://proxy.localtest.me:$HTTP_PORT/api/version" \
  --resolve "proxy.localtest.me:$HTTP_PORT:127.0.0.1"

if curl --fail --silent --show-error --max-time 2 --noproxy '*' \
  --insecure --resolve "demo.localtest.me:$HTTPS_PORT:127.0.0.1" \
  "https://demo.localtest.me:$HTTPS_PORT/" >/dev/null 2>&1; then
  echo "HTTPS port $HTTPS_PORT is still published in HTTP-only mode." >&2
  exit 1
fi

echo "Switching back to HTTPS mode..."
proxy_https up -d
demo_https up -d
assert_https_mode

echo "Live HTTPS/HTTP transition and custom-port smoke tests passed."
