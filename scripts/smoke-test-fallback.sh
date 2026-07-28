#!/usr/bin/env bash
#
# Live smoke test for hostname fallback. Confirms, against a real running
# Traefik, the exact resolution order documented in README "Adding a
# service": traefik.hostname label (always wins) -> Compose service name if
# enabled -> container name if enabled -> no route. Also confirms fallback
# hostnames are normalized (underscores become hyphens) while an explicit
# label is used exactly as written.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/smoke-helpers.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/smoke-helpers.sh"

PROXY_PROJECT="traefik-fallback-smoke"
FIXTURE_PROJECT="traefik-fallback-fixture-smoke"
HTTP_PORT="${SMOKE_FALLBACK_HTTP_PORT:-18280}"
HTTPS_PORT="${SMOKE_FALLBACK_HTTPS_PORT:-18543}"
CRT="$ROOT_DIR/certs/localtest.me.crt"
KEY="$ROOT_DIR/certs/localtest.me.key"
GENERATED_CERTS=0

SVC_CONTAINER="traefik-fallback-svc-demo"
UNDERSCORE_CONTAINER="traefik-fallback-underscore-demo"
EXPLICIT_CONTAINER="traefik-fallback-explicit-demo"

export TRAEFIK_HTTP_PORT="$HTTP_PORT"
export TRAEFIK_HTTPS_PORT="$HTTPS_PORT"
export TRAEFIK_LOG_LEVEL="INFO"

proxy() {
  docker compose --project-name "$PROXY_PROJECT" \
    --env-file "$ROOT_DIR/.env.example" \
    -f "$ROOT_DIR/docker-compose.yml" "$@"
}

# Three fixtures, deliberately distinct service/container names so a hit on
# a given hostname unambiguously proves which tier produced it:
#   - svcname / traefik-fallback-svc-demo: no traefik.hostname label
#   - my_underscore_svc: no label, name has an underscore to normalize
#   - explicitsvc / traefik-fallback-explicit-demo: explicit traefik.hostname,
#     to prove it always wins regardless of the fallback flags
fixture_compose_yaml() {
  cat <<EOF
services:
  svcname:
    image: traefik/whoami:v1.11.0
    container_name: $SVC_CONTAINER
    networks:
      - proxy
    labels:
      traefik.enable: "true"

  my_underscore_svc:
    image: traefik/whoami:v1.11.0
    container_name: $UNDERSCORE_CONTAINER
    networks:
      - proxy
    labels:
      traefik.enable: "true"

  explicitsvc:
    image: traefik/whoami:v1.11.0
    container_name: $EXPLICIT_CONTAINER
    networks:
      - proxy
    labels:
      traefik.enable: "true"
      traefik.hostname: "fallback-explicit-wins"

networks:
  proxy:
    external: true
    name: proxy
EOF
}

fixture() {
  fixture_compose_yaml | docker compose --project-name "$FIXTURE_PROJECT" -f - "$@"
}

cleanup() {
  set +e
  compose_down_quiet "$FIXTURE_PROJECT"
  proxy down --remove-orphans >/dev/null 2>&1
  if [[ "$GENERATED_CERTS" -eq 1 ]]; then
    rm -f -- "$CRT" "$KEY"
  fi
}
trap cleanup EXIT

refuse_if_containers_exist traefik-local traefik-socket-proxy "$SVC_CONTAINER" "$UNDERSCORE_CONTAINER" "$EXPLICIT_CONTAINER"
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

svc_url() { echo "https://svcname.localtest.me:$HTTPS_PORT/"; }
svc_container_url() { echo "https://${SVC_CONTAINER}.localtest.me:$HTTPS_PORT/"; }
underscore_url() { echo "https://my-underscore-svc.localtest.me:$HTTPS_PORT/"; }
underscore_raw_url() { echo "https://my_underscore_svc.localtest.me:$HTTPS_PORT/"; }
explicit_url() { echo "https://fallback-explicit-wins.localtest.me:$HTTPS_PORT/"; }
explicit_service_name_url() { echo "https://explicitsvc.localtest.me:$HTTPS_PORT/"; }

resolve_args() {
  local host="$1"
  echo "--insecure" "--resolve" "${host}:${HTTPS_PORT}:127.0.0.1"
}

echo "Starting proxy (both fallback flags false) and fixtures..."
export TRAEFIK_FALLBACK_TO_COMPOSE_SERVICE_NAME=false
export TRAEFIK_FALLBACK_TO_CONTAINER_NAME=false
proxy up -d
wait_for_health traefik-local
fixture up -d

echo "Regression: explicit traefik.hostname always wins, regardless of flags..."
# shellcheck disable=SC2046
wait_for_url traefik-local "$(explicit_url)" $(resolve_args fallback-explicit-wins.localtest.me)
# shellcheck disable=SC2046
assert_status 200 "$(explicit_url)" $(resolve_args fallback-explicit-wins.localtest.me)
# shellcheck disable=SC2046
assert_status 404 "$(explicit_service_name_url)" $(resolve_args explicitsvc.localtest.me)

echo "Flags 00 (both false): expect no route for either candidate hostname..."
# shellcheck disable=SC2046
assert_status 404 "$(svc_url)" $(resolve_args svcname.localtest.me)
# shellcheck disable=SC2046
assert_status 404 "$(svc_container_url)" $(resolve_args "${SVC_CONTAINER}.localtest.me")

echo "Flags 10 (Compose service name only)..."
export TRAEFIK_FALLBACK_TO_COMPOSE_SERVICE_NAME=true
export TRAEFIK_FALLBACK_TO_CONTAINER_NAME=false
proxy up -d
wait_for_health traefik-local
# shellcheck disable=SC2046
wait_for_url traefik-local "$(svc_url)" $(resolve_args svcname.localtest.me)
# shellcheck disable=SC2046
assert_status 200 "$(svc_url)" $(resolve_args svcname.localtest.me)
# shellcheck disable=SC2046
assert_status 404 "$(svc_container_url)" $(resolve_args "${SVC_CONTAINER}.localtest.me")

echo "Normalization: my_underscore_svc routes as my-underscore-svc, not as-is..."
# shellcheck disable=SC2046
wait_for_url traefik-local "$(underscore_url)" $(resolve_args my-underscore-svc.localtest.me)
# shellcheck disable=SC2046
assert_status 200 "$(underscore_url)" $(resolve_args my-underscore-svc.localtest.me)
# shellcheck disable=SC2046
assert_status 404 "$(underscore_raw_url)" $(resolve_args my_underscore_svc.localtest.me)

echo "Flags 01 (container name only)..."
export TRAEFIK_FALLBACK_TO_COMPOSE_SERVICE_NAME=false
export TRAEFIK_FALLBACK_TO_CONTAINER_NAME=true
proxy up -d
wait_for_health traefik-local
# shellcheck disable=SC2046
assert_status 404 "$(svc_url)" $(resolve_args svcname.localtest.me)
# shellcheck disable=SC2046
wait_for_url traefik-local "$(svc_container_url)" $(resolve_args "${SVC_CONTAINER}.localtest.me")
# shellcheck disable=SC2046
assert_status 200 "$(svc_container_url)" $(resolve_args "${SVC_CONTAINER}.localtest.me")

echo "Flags 11 (both true): Compose service name tier wins..."
export TRAEFIK_FALLBACK_TO_COMPOSE_SERVICE_NAME=true
export TRAEFIK_FALLBACK_TO_CONTAINER_NAME=true
proxy up -d
wait_for_health traefik-local
# shellcheck disable=SC2046
wait_for_url traefik-local "$(svc_url)" $(resolve_args svcname.localtest.me)
# shellcheck disable=SC2046
assert_status 200 "$(svc_url)" $(resolve_args svcname.localtest.me)
# shellcheck disable=SC2046
assert_status 404 "$(svc_container_url)" $(resolve_args "${SVC_CONTAINER}.localtest.me")

echo "Hostname fallback smoke tests passed."
