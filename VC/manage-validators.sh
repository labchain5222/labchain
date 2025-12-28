#!/usr/bin/env bash
#
# manage-validators.sh - Generate validator keystores for LabChain
#
# This script creates validator keystores using Lighthouse.
# Simply run: ./manage-validators.sh
# The script will guide you through the process interactively.
#
set -euo pipefail

# =============================================================================
# Constants
# =============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERSION="1.0.0"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# =============================================================================
# Default Configuration
# =============================================================================
OUTPUT_DIR="./output"
MANAGED_ROOT="./managed-keystores"
CONSENSUS_DIR="../config/metadata"
WITHDRAWAL_ADDRESS=""
VALIDATOR_COUNT=1
FIRST_INDEX=0
LIGHTHOUSE_IMAGE="sigp/lighthouse:latest"

# =============================================================================
# Logging Functions
# =============================================================================
info() { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# =============================================================================
# Utility Functions
# =============================================================================
print_header() {
    clear
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║       LabChain Validator Keystore Generator v${VERSION}             ║${NC}"
    echo -e "${BOLD}║                                                                  ║${NC}"
    echo -e "${BOLD}║   Generate validator keystores for staking on LabChain          ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_separator() {
    echo ""
    echo -e "${BLUE}──────────────────────────────────────────────────────────────────${NC}"
    echo ""
}

# Prompt for input with default value
prompt_input() {
    local prompt="$1"
    local default="$2"
    local value

    if [[ -n "$default" ]]; then
        echo -ne "  ${prompt} ${CYAN}(default: ${default})${NC}: " >&2
        read -r value
        value="${value:-$default}"
    else
        echo -ne "  ${prompt}: " >&2
        read -r value
    fi

    echo "$value"
}

# Prompt for yes/no
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local value

    if [[ "$default" == "y" ]]; then
        echo -ne "  ${prompt} ${CYAN}[Y/n]${NC}: " >&2
    else
        echo -ne "  ${prompt} ${CYAN}[y/N]${NC}: " >&2
    fi

    read -r value
    value="${value:-$default}"
    value=$(echo "$value" | tr '[:upper:]' '[:lower:]')

    [[ "$value" == "y" || "$value" == "yes" ]]
}

# Validate Ethereum address
validate_address() {
    local address="$1"
    if [[ "$address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# Check Functions
# =============================================================================
check_dependencies() {
    local missing=()

    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    fi

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        echo ""
        echo "  Please install them first:"
        [[ " ${missing[*]} " =~ " docker " ]] && echo "    - Docker: curl -fsSL https://get.docker.com | sh"
        [[ " ${missing[*]} " =~ " jq " ]] && echo "    - jq: sudo apt install jq (Ubuntu) or brew install jq (macOS)"
        echo ""
        exit 1
    fi
}

# =============================================================================
# Main Interactive Flow
# =============================================================================
main() {
    print_header

    # Check dependencies
    info "Checking required tools..."
    check_dependencies
    success "All required tools are installed"

    print_separator

    # Step 1: Number of validators
    echo -e "${BOLD}Step 1: Number of Validators${NC}"
    echo ""
    echo "  How many validators do you want to create?"
    echo "  Each validator requires 32 LAB deposit."
    echo ""

    while true; do
        VALIDATOR_COUNT=$(prompt_input "Number of validators" "1")
        if [[ "$VALIDATOR_COUNT" =~ ^[0-9]+$ ]] && [[ "$VALIDATOR_COUNT" -gt 0 ]]; then
            break
        fi
        warn "Please enter a valid number greater than 0"
    done

    print_separator

    # Step 2: Withdrawal address
    echo -e "${BOLD}Step 2: Withdrawal Address${NC}"
    echo ""
    echo "  Enter your LAB address for withdrawals."
    echo "  This is where your stake and rewards will be sent when you exit."
    echo ""
    echo -e "  ${RED}IMPORTANT: Make sure you control this address!${NC}"
    echo ""

    while true; do
        WITHDRAWAL_ADDRESS=$(prompt_input "Withdrawal address (0x...)" "")
        if [[ -z "$WITHDRAWAL_ADDRESS" ]]; then
            warn "Withdrawal address is required"
            continue
        fi
        if validate_address "$WITHDRAWAL_ADDRESS"; then
            break
        fi
        warn "Invalid address format. Must be 0x followed by 40 hex characters"
    done

    print_separator

    # Step 3: Starting index
    echo -e "${BOLD}Step 3: Starting Validator Index${NC}"
    echo ""
    echo "  If this is your first time creating validators, use 0."
    echo "  If you're adding more validators, use the next index."
    echo ""

    while true; do
        FIRST_INDEX=$(prompt_input "Starting index" "0")
        if [[ "$FIRST_INDEX" =~ ^[0-9]+$ ]]; then
            break
        fi
        warn "Please enter a valid number"
    done

    print_separator

    # Step 4: Output directories
    echo -e "${BOLD}Step 4: Output Directories${NC}"
    echo ""

    OUTPUT_DIR=$(prompt_input "Output directory for deposits.json" "$OUTPUT_DIR")
    MANAGED_ROOT=$(prompt_input "Keystore directory" "$MANAGED_ROOT")

    # Convert to absolute paths
    if [[ ! "$OUTPUT_DIR" = /* ]]; then
        OUTPUT_DIR="${SCRIPT_DIR}/${OUTPUT_DIR}"
    fi
    if [[ ! "$MANAGED_ROOT" = /* ]]; then
        MANAGED_ROOT="${SCRIPT_DIR}/${MANAGED_ROOT}"
    fi
    if [[ ! "$CONSENSUS_DIR" = /* ]]; then
        CONSENSUS_DIR="${SCRIPT_DIR}/${CONSENSUS_DIR}"
    fi

    # Check consensus directory
    if [[ ! -d "$CONSENSUS_DIR" ]]; then
        error "Consensus metadata not found at: ${CONSENSUS_DIR}"
        exit 1
    fi

    # Create output directories
    mkdir -p "$OUTPUT_DIR" "$MANAGED_ROOT"

    print_separator

    # Step 5: Summary and confirmation
    echo -e "${BOLD}Step 5: Confirm Configuration${NC}"
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                     CONFIGURATION SUMMARY                        ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "Validators to create: ${VALIDATOR_COUNT}"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "Starting index: ${FIRST_INDEX}"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "Withdrawal address: ${WITHDRAWAL_ADDRESS:0:20}...${WITHDRAWAL_ADDRESS: -8}"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "Output directory: ${OUTPUT_DIR}"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "Keystore directory: ${MANAGED_ROOT}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local total_deposit=$((VALIDATOR_COUNT * 32))
    echo -e "  ${YELLOW}Total deposit required: ${total_deposit} LAB${NC}"
    echo ""

    if ! prompt_yes_no "Proceed with validator generation?" "y"; then
        info "Cancelled by user"
        exit 0
    fi

    print_separator

    # Step 6: Generate validators
    echo -e "${BOLD}Step 6: Generating Validator Keystores${NC}"
    echo ""

    info "Creating ${VALIDATOR_COUNT} validators (starting from index ${FIRST_INDEX})..."
    echo ""

    OUTPUT_ABS="$(cd "$OUTPUT_DIR" && pwd)"
    CONSENSUS_ABS="$(cd "$CONSENSUS_DIR" && pwd)"

    # Run lighthouse validator-manager
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

    # Check if validators.json was created
    VALIDATORS_JSON="$OUTPUT_ABS/validators.json"
    if [[ ! -f "$VALIDATORS_JSON" ]]; then
        error "Failed to create validators. Expected validators.json in $OUTPUT_ABS"
        exit 1
    fi

    print_separator

    # Step 7: Extract keystores
    echo -e "${BOLD}Step 7: Extracting Keystores${NC}"
    echo ""

    KEYS_DIR="${MANAGED_ROOT}/validators"
    SECRETS_DIR="${MANAGED_ROOT}/secrets"
    mkdir -p "$KEYS_DIR" "$SECRETS_DIR"

    local count=0
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

        success "Extracted: ${pubkey:0:20}...${pubkey: -8}"
        count=$((count + 1))
    done < <(jq -c '.[]' "$VALIDATORS_JSON")

    print_separator

    # Summary
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                   GENERATION COMPLETE!                           ║${NC}"
    echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  ${count} validator(s) created successfully!                          ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Files created:                                                  ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}    • Deposits: ${OUTPUT_ABS}/deposits.json"
    echo -e "${GREEN}${BOLD}║${NC}    • Keystores: ${KEYS_DIR}"
    echo -e "${GREEN}${BOLD}║${NC}    • Secrets: ${SECRETS_DIR}"
    echo -e "${GREEN}${BOLD}║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}  Next steps:                                                     ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}    1. Run ./broadcast-deposits.sh to deposit 32 LAB per validator${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}    2. Wait for deposit processing (~16-24 hours)                 ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}║${NC}    3. Start your validator client with ./node.sh start vc       ${GREEN}${BOLD}║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Run main
main
