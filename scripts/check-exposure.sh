#!/usr/bin/env bash
# Non-blocking advisory exposure check. Warns about non-default (non-loopback)
# bind-address settings before starting the proxy - it never fails and never
# blocks a start, it only prints a warning to stderr.
#
# This only runs on mise-managed paths (mise run up / validate / ...). It
# cannot protect a raw `docker compose up` invocation that bypasses mise
# entirely - see README "Configuration" for the same caveat spelled out for
# people who don't use mise.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 0

# docker compose config --environment prints the full merged shell + .env
# environment as flat KEY=VALUE lines - not a filtered view scoped to this
# project's own vars - so pull out only the keys this check cares about.
ENV_DUMP="$(docker compose config --environment 2>/dev/null)" || exit 0

get_var() {
  local name="$1"
  local default="$2"
  local line

  line="$(grep "^${name}=" <<<"$ENV_DUMP" | tail -1)"
  if [[ -z "$line" ]]; then
    echo "$default"
  else
    echo "${line#*=}"
  fi
}

web_bind="$(get_var TRAEFIK_WEB_BIND_ADDRESS 127.0.0.1)"
tcp_bind="$(get_var TRAEFIK_TCP_BIND_ADDRESS 127.0.0.1)"
dashboard_enabled="$(get_var TRAEFIK_DASHBOARD_ENABLED true)"

warned=0

if [[ "$web_bind" != "127.0.0.1" ]]; then
  echo "WARNING: TRAEFIK_WEB_BIND_ADDRESS is '$web_bind' (non-loopback). Every routed web service will be reachable on that interface, not just on 127.0.0.1." >&2
  if [[ "$dashboard_enabled" == "true" ]]; then
    echo "         The dashboard is also still enabled. Consider TRAEFIK_DASHBOARD_ENABLED=false, or otherwise protecting the dashboard, before exposing the web ports beyond 127.0.0.1." >&2
  fi
  warned=1
fi

if [[ "$tcp_bind" != "127.0.0.1" ]]; then
  echo "WARNING: TRAEFIK_TCP_BIND_ADDRESS is '$tcp_bind' (non-loopback). Every currently-enabled database override port will be reachable on that interface, not just the one you meant to open." >&2
  warned=1
fi

if [[ "$warned" -eq 1 ]]; then
  echo "NOTE: this check only runs on mise-managed tasks. It cannot protect a raw 'docker compose up' invocation that bypasses mise." >&2
fi

exit 0
