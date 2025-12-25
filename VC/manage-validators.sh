#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./manage-validators.sh [options]

Options:
  -o, --output <dir>          Directory to store lighthouse validator-manager output (default: ./output)
  -m, --managed-root <dir>    Directory to store extracted keystores (default: ./managed-keystores)
  -c, --consensus <dir>       Path to consensus metadata (default: ./config/metadata)
  -w, --withdrawal <address>  ETH withdrawal address (default: 0x000...000)
  -n, --count <int>           Number of validators to generate (default: 64)
  -f, --first-index <int>     Starting validator index (default: 0)
  -i, --image <name>          Lighthouse image tag (default: sigp/lighthouse:latest)
  -h, --help                  Show this help text
USAGE
}

OUTPUT_DIR="./output"
MANAGED_ROOT="./managed-keystores"
CONSENSUS_DIR="../config/metadata"
WITHDRAWAL_ADDRESS="0x0000000000000000000000000000000000000000"
VALIDATOR_COUNT=64
FIRST_INDEX=0
LIGHTHOUSE_IMAGE="sigp/lighthouse:latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      OUTPUT_DIR="$2"; shift 2;;
    -m|--managed-root)
      MANAGED_ROOT="$2"; shift 2;;
    -c|--consensus)
      CONSENSUS_DIR="$2"; shift 2;;
    -w|--withdrawal)
      WITHDRAWAL_ADDRESS="$2"; shift 2;;
    -n|--count)
      VALIDATOR_COUNT="$2"; shift 2;;
    -f|--first-index)
      FIRST_INDEX="$2"; shift 2;;
    -i|--image)
      LIGHTHOUSE_IMAGE="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option $1" >&2; usage; exit 1;;
  esac
done

mkdir -p "$OUTPUT_DIR" "$MANAGED_ROOT"
if [[ ! -d "$CONSENSUS_DIR" ]]; then
  echo "Consensus metadata missing at $CONSENSUS_DIR" >&2; exit 1
fi

OUTPUT_ABS="$(cd "$OUTPUT_DIR" && pwd)"
CONSENSUS_ABS="$(cd "$CONSENSUS_DIR" && pwd)"

echo "[vc] Creating $VALIDATOR_COUNT validators (first index $FIRST_INDEX)"

docker run --rm -it \
  -v "$OUTPUT_ABS:/output" \
  -v "$CONSENSUS_ABS:/consensus:ro" \
  "$LIGHTHOUSE_IMAGE" \
  lighthouse validator-manager create \
    --testnet-dir /consensus \
    --first-index "$FIRST_INDEX" \
    --count "$VALIDATOR_COUNT" \
    --eth1-withdrawal-address "$WITHDRAWAL_ADDRESS" \
    --output-path /output

VALIDATORS_JSON="$OUTPUT_ABS/validators.json"
if [[ ! -f "$VALIDATORS_JSON" ]]; then
  echo "Expected validators.json in $OUTPUT_ABS" >&2; exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse $VALIDATORS_JSON" >&2; exit 1
fi

KEYS_DIR="${MANAGED_ROOT%/}/validators"
SECRETS_DIR="${MANAGED_ROOT%/}/secrets"
mkdir -p "$KEYS_DIR" "$SECRETS_DIR"

count=0
while IFS= read -r entry; do
  raw_pubkey=$(jq -r '.voting_keystore | fromjson | .pubkey' <<<"$entry")
  keystore_json=$(jq -r '.voting_keystore' <<<"$entry")
  password=$(jq -r '.voting_keystore_password' <<<"$entry")
  [[ -z "$raw_pubkey" || "$raw_pubkey" == "null" ]] && continue
  pubkey="0x${raw_pubkey#0x}"
  mkdir -p "$KEYS_DIR/$pubkey"
  printf '%s\n' "$keystore_json" > "$KEYS_DIR/$pubkey/voting-keystore.json"
  chmod 400 "$KEYS_DIR/$pubkey/voting-keystore.json"
  printf '%s\n' "$password" > "$SECRETS_DIR/$pubkey"
  chmod 400 "$SECRETS_DIR/$pubkey"
  printf '[vc] Extracted pubkey %s\n' "$pubkey"
  count=$((count + 1))
done < <(jq -c '.[]' "$VALIDATORS_JSON")

printf '[vc] Finished: %s validators ready under %s\n' "$count" "$MANAGED_ROOT"
printf 'Deposits located at %s/deposits.json\n' "$OUTPUT_ABS"
