#!/usr/bin/env bash
# Shared helpers for live smoke tests. Source this file; do not execute it
# directly. Callers must set -euo pipefail themselves.
#
# Requires: curl, docker on PATH.

# refuse_if_containers_exist <container_name>...
# Exits 1 if any of the given container names already exist, so a smoke test
# never disturbs an already-running stack.
refuse_if_containers_exist() {
  local container
  for container in "$@"; do
    if docker container inspect "$container" >/dev/null 2>&1; then
      echo "Refusing to run: container '$container' already exists." >&2
      echo "Stop the active stack before running this test." >&2
      exit 1
    fi
  done
}

# refuse_if_network_exists <network_name>
# Exits 1 if the given docker network already exists.
refuse_if_network_exists() {
  local network="$1"
  if docker network inspect "$network" >/dev/null 2>&1; then
    echo "Refusing to run: the '$network' network already exists." >&2
    echo "Stop the active stack before running this test." >&2
    exit 1
  fi
}

# compose_down_quiet <project_name> [compose args...]
# Brings a compose project down without failing - safe to call from an EXIT
# trap alongside other cleanup steps.
compose_down_quiet() {
  local project="$1"
  shift
  docker compose --project-name "$project" "$@" down --remove-orphans >/dev/null 2>&1 || true
}

# wait_for_health <container_name>
# Polls a container's Docker healthcheck status until healthy or timeout.
wait_for_health() {
  local container="$1"
  local health

  for _ in {1..30}; do
    health="$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || true)"
    if [[ "$health" == "healthy" ]]; then
      return 0
    fi
    sleep 2
  done

  echo "$container did not become healthy." >&2
  docker logs "$container" >&2 || true
  return 1
}

# wait_for_url <diag_container> <url> [curl args...]
# Polls a URL until it responds successfully or timeout. On timeout, dumps
# diag_container's logs to help debugging.
wait_for_url() {
  local diag_container="$1"
  local url="$2"
  shift 2

  for _ in {1..30}; do
    if curl --fail --silent --show-error --max-time 2 --noproxy '*' \
      "$@" "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "Timed out waiting for $url" >&2
  docker logs "$diag_container" >&2 || true
  return 1
}

# assert_status <expected_code> <url> [curl args...]
# Fails if the URL's HTTP status code doesn't match expected_code.
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

# traefik_api <diag_container> <base_url> <api_path> [curl args...]
# Fetches a Traefik API endpoint (e.g. /api/rawdata) and prints the raw
# response body to stdout. Used to assert on dynamic/router config load
# state directly, rather than inferring it from the healthcheck alone.
traefik_api() {
  local diag_container="$1"
  local base_url="$2"
  local api_path="$3"
  shift 3

  if ! curl --fail --silent --show-error --max-time 5 --noproxy '*' \
    "$@" "${base_url}${api_path}"; then
    echo "Traefik API request to ${api_path} failed." >&2
    docker logs "$diag_container" >&2 || true
    return 1
  fi
}
