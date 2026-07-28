#!/usr/bin/env bash
# Renders two Compose configurations as JSON and compares a jq path between
# them. Used by CI/mise validate to prove two configurations only differ the
# way they're supposed to - e.g. that docker-compose.http.yml's
# --providers.docker.defaultrule argument matches docker-compose.yml's
# byte-for-byte, or that an override file changes exactly the fields it
# claims to.
#
# Usage:
#   compose-config-diff.sh <jq-path> -- <compose-args-A...> -- <compose-args-B...>
#
# Prints the extracted value from each configuration, then a diff between
# them. Exits 0 if the two extracted values are byte-identical, 1 otherwise.
# For comparisons that need something other than exact equality (e.g. "these
# two command lists must differ by exactly these 3 known entries"), source
# this file's render_config_json function directly instead of relying on the
# exit code.
#
# Requires: docker compose (with `config --format json` support), jq on PATH.

set -euo pipefail

# render_config_json <compose-args...>
# Renders a Compose configuration as JSON. Intended to be sourced by callers
# that need more than an equality check (see phase 7's redirect parity test).
render_config_json() {
  docker compose "$@" config --format json
}

usage() {
  echo "Usage: $0 <jq-path> -- <compose-args-A...> -- <compose-args-B...>" >&2
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 2
  fi

  local jq_path="$1"
  shift

  if [[ "${1:-}" != "--" ]]; then
    echo "Expected '--' before the first compose argument list." >&2
    usage
    exit 2
  fi
  shift

  local args_a=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do
    args_a+=("$1")
    shift
  done

  if [[ "${1:-}" != "--" ]]; then
    echo "Expected a second '--' separating the two compose argument lists." >&2
    usage
    exit 2
  fi
  shift

  local args_b=("$@")
  if [[ ${#args_b[@]} -eq 0 ]]; then
    echo "Expected at least one compose argument after the second '--'." >&2
    usage
    exit 2
  fi

  local value_a value_b
  value_a="$(render_config_json "${args_a[@]}" | jq -c "$jq_path")"
  value_b="$(render_config_json "${args_b[@]}" | jq -c "$jq_path")"

  echo "A ($jq_path): $value_a"
  echo "B ($jq_path): $value_b"

  if [[ "$value_a" == "$value_b" ]]; then
    echo "Match: $jq_path is identical between the two configurations."
    return 0
  fi

  echo "Mismatch at $jq_path:" >&2
  diff <(jq -n "$value_a") <(jq -n "$value_b") >&2 || true
  return 1
}

# Allow sourcing (for render_config_json) without executing main.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
