#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for parsing admin_nodeInfo responses." >&2
  exit 1
fi

payload='{"jsonrpc":"2.0","method":"admin_nodeInfo","params":[],"id":1}'
response="$(curl -sSf -H "Content-Type: application/json" -d "${payload}" "${RPC_URL}")"
enode="$(echo "${response}" | jq -r '.result.enode')"

if [[ -z "${enode}" || "${enode}" == "null" ]]; then
  echo "Unable to extract enode from ${RPC_URL}. Full response:" >&2
  echo "${response}" >&2
  exit 1
fi

printf '%s\n\n' "${enode}"
echo "Export this value before starting non-boot nodes, e.g."
echo "  export BOOTNODE_ENODE=\"${enode}\""
