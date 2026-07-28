#!/usr/bin/env bash
#
# Live routing smoke test. Uses high loopback ports and refuses to disturb an
# existing stack that uses the fixed container names or proxy network.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/smoke-helpers.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/smoke-helpers.sh"

PROXY_PROJECT="traefik-local-proxy-smoke"
DEMO_PROJECT="traefik-whoami-smoke"
BASELINE_PROJECT="traefik-baseline-smoke"
BASELINE_CONTAINER="traefik-baseline-demo"
HTTP_PORT="${SMOKE_HTTP_PORT:-18080}"
HTTPS_PORT="${SMOKE_HTTPS_PORT:-18443}"
CRT="$ROOT_DIR/certs/localtest.me.crt"
KEY="$ROOT_DIR/certs/localtest.me.key"
GENERATED_CERTS=0
HEADERS_FILE="$(mktemp)"

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

# Fixture with no traefik.hostname label at all - characterizes today's actual
# behavior (no route generated) so a later hostname-fallback rework can prove
# it didn't change this case unless a fallback flag is deliberately enabled.
# Compose service name and container name are deliberately different strings
# so a future fallback test can tell which tier (if any) produced a route.
baseline_compose_yaml() {
  cat <<EOF
services:
  baselinesvc:
    image: traefik/whoami:v1.11.0
    container_name: $BASELINE_CONTAINER
    networks:
      - proxy
    labels:
      traefik.enable: "true"

networks:
  proxy:
    external: true
    name: proxy
EOF
}

baseline_https() {
  baseline_compose_yaml | docker compose --project-name "$BASELINE_PROJECT" -f - "$@"
}

cleanup() {
  set +e
  compose_down_quiet "$BASELINE_PROJECT"
  demo_https down --remove-orphans >/dev/null 2>&1
  proxy_https down --remove-orphans >/dev/null 2>&1
  if [[ "$GENERATED_CERTS" -eq 1 ]]; then
    rm -f -- "$CRT" "$KEY"
  fi
  rm -f -- "$HEADERS_FILE"
}
trap cleanup EXIT

refuse_if_containers_exist proxy traefik-socket-proxy traefik-whoami-demo "$BASELINE_CONTAINER"
refuse_if_network_exists proxy

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

assert_https_mode() {
  wait_for_health proxy
  wait_for_url proxy "https://demo.localtest.me:$HTTPS_PORT/" \
    --insecure --resolve "demo.localtest.me:$HTTPS_PORT:127.0.0.1"
  assert_status 200 "https://demo.localtest.me:$HTTPS_PORT/" \
    --insecure --resolve "demo.localtest.me:$HTTPS_PORT:127.0.0.1"
  wait_for_url proxy "https://proxy.localtest.me:$HTTPS_PORT/api/version" \
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

# Baseline characterization: a container with no traefik.hostname label gets
# no usable route today. Neither its Compose service name nor its container
# name should resolve to anything - both must 404, the same as any other
# unmatched host on this entrypoint.
assert_no_route_without_hostname_label() {
  assert_status 404 "https://baselinesvc.localtest.me:$HTTPS_PORT/" \
    --insecure --resolve "baselinesvc.localtest.me:$HTTPS_PORT:127.0.0.1"
  assert_status 404 "https://${BASELINE_CONTAINER}.localtest.me:$HTTPS_PORT/" \
    --insecure --resolve "${BASELINE_CONTAINER}.localtest.me:$HTTPS_PORT:127.0.0.1"
}

echo "Starting HTTPS mode on 127.0.0.1:$HTTP_PORT and 127.0.0.1:$HTTPS_PORT..."
proxy_https up -d
demo_https up -d
assert_https_mode

echo "Confirming a container without traefik.hostname gets no route (baseline)..."
baseline_https up -d
wait_for_health proxy
assert_no_route_without_hostname_label
baseline_https down --remove-orphans

echo "Switching the same Compose projects to HTTP-only mode..."
proxy_http up -d
demo_http up -d
wait_for_health proxy
wait_for_url proxy "http://demo.localtest.me:$HTTP_PORT/" \
  --resolve "demo.localtest.me:$HTTP_PORT:127.0.0.1"
assert_status 200 "http://demo.localtest.me:$HTTP_PORT/" \
  --resolve "demo.localtest.me:$HTTP_PORT:127.0.0.1"
wait_for_url proxy "http://proxy.localtest.me:$HTTP_PORT/api/version" \
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
