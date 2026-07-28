#!/usr/bin/env bash
#
# Confirms docker-compose.disable-http-to-https-redirect.yml's command list
# differs from docker-compose.yml's own command list by exactly the 3
# HTTP-to-HTTPS redirect entries - nothing more, nothing less. Guards
# against the override silently drifting out of sync with a future edit to
# the base command list, since Compose's command: key fully replaces
# (rather than merges) across -f files.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

base_command="$(docker compose --env-file .env.example -f docker-compose.yml config --format json | jq -c '.services.proxy.command')"
override_command="$(docker compose --env-file .env.example -f docker-compose.yml -f docker-compose.disable-http-to-https-redirect.yml config --format json | jq -c '.services.proxy.command')"

only_in_base="$(jq -cn --argjson a "$base_command" --argjson b "$override_command" '($a - $b) | sort')"
only_in_override="$(jq -cn --argjson a "$base_command" --argjson b "$override_command" '($b - $a) | sort')"

redirect_to_value="$(jq -r '.[] | select(startswith("--entrypoints.web.http.redirections.entrypoint.to="))' <<<"$base_command")"

if [[ -z "$redirect_to_value" ]]; then
  echo "Could not find the redirect 'to=' entry in docker-compose.yml's rendered command - is the redirect still there at all?" >&2
  exit 1
fi

expected_removed="$(jq -cn --arg to "$redirect_to_value" '[
  $to,
  "--entrypoints.web.http.redirections.entrypoint.scheme=https",
  "--entrypoints.web.http.redirections.entrypoint.permanent=false"
] | sort')"

if [[ "$only_in_override" != "[]" ]]; then
  echo "The redirect override adds command entries it should not:" >&2
  echo "$only_in_override" >&2
  exit 1
fi

if [[ "$only_in_base" != "$expected_removed" ]]; then
  echo "The redirect override removes different entries than expected." >&2
  echo "Expected to remove exactly: $expected_removed" >&2
  echo "Actually removes:           $only_in_base" >&2
  exit 1
fi

echo "Redirect override parity OK - differs from the base command by exactly the 3 redirect entries."
