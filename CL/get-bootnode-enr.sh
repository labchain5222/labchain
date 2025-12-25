#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:5052}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse lighthouse identity responses." >&2
  exit 1
fi

response="$(curl -sSf "${RPC_URL}/eth/v1/node/identity")"
enr="$(echo "${response}" | jq -r '.data.enr')"

if [[ -z "${enr}" || "${enr}" == "null" ]]; then
  echo "Unable to extract ENR from ${RPC_URL}. Full response:" >&2
  echo "${response}" >&2
  exit 1
fi

printf '%s\n' "${enr}"
printf '\nExport this value before launching follower nodes, e.g.\n  export BOOTNODE_ENR=\"%s\"\n' "${enr}"
