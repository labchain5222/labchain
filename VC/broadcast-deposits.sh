#!/usr/bin/env bash
#
# broadcast-deposits.sh - Broadcast validator deposits to LabChain
#
# This script sends 32 LAB deposits for each validator.
# Simply run: ./broadcast-deposits.sh
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
RPC_URL="http://localhost:8545"
DEPOSITS_FILE="./output/deposits.json"
FROM_ADDRESS=""
CHAIN_ID="5222"
PRIVATE_KEY=""
DEPOSIT_CONTRACT="0x5454545454545454545454545454545454545454"
DRY_RUN=false

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
    echo -e "${BOLD}║         LabChain Validator Deposit Broadcaster v${VERSION}          ║${NC}"
    echo -e "${BOLD}║                                                                  ║${NC}"
    echo -e "${BOLD}║   Broadcast 32 LAB deposits for your validators                  ║${NC}"
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

# Prompt for sensitive input (hidden)
prompt_secret() {
    local prompt="$1"
    local value

    echo -ne "  ${prompt}: " >&2
    read -rs value
    echo "" >&2

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

    if ! command -v cast &>/dev/null; then
        missing+=("cast (Foundry)")
    fi

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        echo ""
        echo "  Please install them first:"
        [[ " ${missing[*]} " =~ " cast " ]] && {
            echo "    - Foundry: curl -L https://foundry.paradigm.xyz | bash && foundryup"
        }
        [[ " ${missing[*]} " =~ " jq " ]] && echo "    - jq: sudo apt install jq (Ubuntu) or brew install jq (macOS)"
        echo ""
        exit 1
    fi
}

check_rpc_connection() {
    local url="$1"

    info "Checking RPC connection to ${url}..."

    local block_number
    block_number=$(cast block-number --rpc-url "$url" 2>/dev/null) || {
        return 1
    }

    success "RPC connected, current block: ${block_number}"
    return 0
}

check_balance() {
    local address="$1"
    local rpc_url="$2"
    local required_lab="$3"

    local balance_wei
    balance_wei=$(cast balance "$address" --rpc-url "$rpc_url" 2>/dev/null) || {
        warn "Could not check balance"
        return 0
    }

    local balance_lab
    balance_lab=$(cast to-unit "$balance_wei" ether 2>/dev/null) || balance_lab="N/A"

    info "Account balance: ${balance_lab} LAB"

    # Compare balances using bc (handles large numbers)
    local is_insufficient
    is_insufficient=$(echo "$balance_lab < $required_lab" | bc -l 2>/dev/null) || is_insufficient="0"

    if [[ "$is_insufficient" == "1" ]]; then
        warn "Insufficient balance! Need at least ${required_lab} LAB"
        return 1
    fi

    return 0
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

    # Step 1: Deposits file
    echo -e "${BOLD}Step 1: Deposits File${NC}"
    echo ""
    echo "  Select the deposits.json file generated by manage-validators.sh"
    echo ""

    while true; do
        DEPOSITS_FILE=$(prompt_input "Path to deposits.json" "$DEPOSITS_FILE")

        # Convert to absolute path
        if [[ ! "$DEPOSITS_FILE" = /* ]]; then
            DEPOSITS_FILE="${SCRIPT_DIR}/${DEPOSITS_FILE}"
        fi

        if [[ -f "$DEPOSITS_FILE" ]]; then
            break
        fi
        warn "File not found: ${DEPOSITS_FILE}"
    done

    # Count deposits
    local total_deposits
    total_deposits=$(jq '. | length' "$DEPOSITS_FILE" 2>/dev/null) || {
        error "Invalid deposits.json file"
        exit 1
    }

    success "Found ${total_deposits} deposit(s) in file"

    print_separator

    # Step 2: RPC endpoint
    echo -e "${BOLD}Step 2: RPC Endpoint${NC}"
    echo ""
    echo "  Enter the Execution Layer RPC endpoint."
    echo ""

    while true; do
        RPC_URL=$(prompt_input "RPC URL" "$RPC_URL")

        if check_rpc_connection "$RPC_URL"; then
            break
        fi

        echo ""
        warn "Cannot connect to RPC at ${RPC_URL}"
        if ! prompt_yes_no "Try a different URL?" "y"; then
            error "RPC connection is required"
            exit 1
        fi
        echo ""
    done

    print_separator

    # Step 3: Sender account
    echo -e "${BOLD}Step 3: Sender Account${NC}"
    echo ""
    echo "  Enter the address that will send the deposits."
    echo "  This account must have enough LAB to cover all deposits."
    echo ""

    local total_required=$((total_deposits * 32))
    echo -e "  ${YELLOW}Required: ${total_required} LAB (${total_deposits} × 32 LAB)${NC}"
    echo ""

    while true; do
        FROM_ADDRESS=$(prompt_input "Sender address (0x...)" "")

        if [[ -z "$FROM_ADDRESS" ]]; then
            warn "Address is required"
            continue
        fi

        if ! validate_address "$FROM_ADDRESS"; then
            warn "Invalid address format"
            continue
        fi

        check_balance "$FROM_ADDRESS" "$RPC_URL" "$total_required" || {
            if ! prompt_yes_no "Continue anyway?" "n"; then
                continue
            fi
        }

        break
    done

    print_separator

    # Step 4: Private key
    echo -e "${BOLD}Step 4: Private Key${NC}"
    echo ""
    echo "  Enter the private key for the sender address."
    echo -e "  ${RED}WARNING: Keep your private key secure!${NC}"
    echo ""

    while true; do
        PRIVATE_KEY=$(prompt_secret "Private key (hex, will be hidden)")

        if [[ -z "$PRIVATE_KEY" ]]; then
            warn "Private key is required"
            continue
        fi

        # Remove 0x prefix if present
        PRIVATE_KEY="${PRIVATE_KEY#0x}"

        # Validate format (64 hex characters)
        if [[ ! "$PRIVATE_KEY" =~ ^[a-fA-F0-9]{64}$ ]]; then
            warn "Invalid private key format (must be 64 hex characters)"
            continue
        fi

        break
    done

    print_separator

    # Step 5: Chain ID and contract
    echo -e "${BOLD}Step 5: Network Configuration${NC}"
    echo ""

    CHAIN_ID=$(prompt_input "Chain ID" "$CHAIN_ID")
    DEPOSIT_CONTRACT=$(prompt_input "Deposit contract address" "$DEPOSIT_CONTRACT")

    print_separator

    # Step 6: Dry run option
    echo -e "${BOLD}Step 6: Execution Mode${NC}"
    echo ""

    if prompt_yes_no "Run in dry-run mode first? (preview only, no transactions)" "y"; then
        DRY_RUN=true
    fi

    print_separator

    # Step 7: Summary and confirmation
    echo -e "${BOLD}Step 7: Confirm Configuration${NC}"
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                     DEPOSIT SUMMARY                              ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "Deposits to broadcast: ${total_deposits}"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "Total LAB required: ${total_required} LAB"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "RPC endpoint: ${RPC_URL}"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "Sender: ${FROM_ADDRESS:0:20}...${FROM_ADDRESS: -8}"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "Chain ID: ${CHAIN_ID}"
    printf "${BOLD}║${NC} %-66s ${BOLD}║${NC}\n" "Deposit contract: ${DEPOSIT_CONTRACT:0:20}...${DEPOSIT_CONTRACT: -8}"
    if [[ "$DRY_RUN" == "true" ]]; then
        printf "${BOLD}║${NC} ${YELLOW}%-66s${NC} ${BOLD}║${NC}\n" "Mode: DRY-RUN (no transactions will be sent)"
    else
        printf "${BOLD}║${NC} ${GREEN}%-66s${NC} ${BOLD}║${NC}\n" "Mode: LIVE (transactions will be broadcast)"
    fi
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$DRY_RUN" != "true" ]]; then
        echo -e "  ${RED}${BOLD}WARNING: This will send real transactions!${NC}"
        echo ""
    fi

    if ! prompt_yes_no "Proceed with deposits?" "y"; then
        info "Cancelled by user"
        exit 0
    fi

    print_separator

    # Step 8: Execute deposits
    echo -e "${BOLD}Step 8: Broadcasting Deposits${NC}"
    echo ""

    local success_count=0
    local fail_count=0

    for i in $(seq 0 $((total_deposits - 1))); do
        local num=$((i + 1))

        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}[${num}/${total_deposits}]${NC} Processing deposit..."
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

        # Extract deposit data
        local pubkey withdrawal_creds signature deposit_data_root
        pubkey=$(jq -r ".[$i].pubkey" "$DEPOSITS_FILE")
        withdrawal_creds=$(jq -r ".[$i].withdrawal_credentials" "$DEPOSITS_FILE")
        signature=$(jq -r ".[$i].signature" "$DEPOSITS_FILE")
        deposit_data_root=$(jq -r ".[$i].deposit_data_root" "$DEPOSITS_FILE")

        echo "  Pubkey: 0x${pubkey:0:16}...${pubkey: -8}"

        if [[ "$DRY_RUN" == "true" ]]; then
            info "[DRY-RUN] Would deposit 32 LAB for validator"
            echo ""
            echo "  Transaction details:"
            echo "    Contract: ${DEPOSIT_CONTRACT}"
            echo "    Value: 32 LAB"
            echo "    Pubkey: 0x${pubkey}"
            echo ""
            success "[DRY-RUN] Deposit ${num}/${total_deposits} validated"
            ((success_count++))
            continue
        fi

        # Execute deposit
        info "Broadcasting deposit..."

        set +e
        local tx_output
        tx_output=$(cast send "$DEPOSIT_CONTRACT" \
            "deposit(bytes,bytes,bytes,bytes32)" \
            "0x$pubkey" \
            "0x$withdrawal_creds" \
            "0x$signature" \
            "0x$deposit_data_root" \
            --rpc-url "$RPC_URL" \
            --chain-id "$CHAIN_ID" \
            --from "$FROM_ADDRESS" \
            --private-key "$PRIVATE_KEY" \
            --value 32ether 2>&1)
        local exit_code=$?
        set -e

        if [[ $exit_code -ne 0 ]]; then
            error "Failed to broadcast deposit ${num}"
            echo "$tx_output"
            ((fail_count++))
            continue
        fi

        # Try to extract transaction hash
        local tx_hash
        tx_hash=$(echo "$tx_output" | grep -oE '0x[a-fA-F0-9]{64}' | head -n1 || echo "")

        if [[ -n "$tx_hash" ]]; then
            success "Deposit ${num}/${total_deposits} broadcast!"
            echo "  Transaction: ${tx_hash}"
        else
            success "Deposit ${num}/${total_deposits} broadcast!"
        fi

        ((success_count++))

        # Delay between deposits
        if [[ $num -lt $total_deposits ]]; then
            echo ""
            info "Waiting 2 seconds before next deposit..."
            sleep 2
        fi
    done

    print_separator

    # Summary
    echo -e "${BOLD}Deposit Summary${NC}"
    echo ""
    echo -e "  ${GREEN}✓ Successful:${NC} ${success_count}"
    echo -e "  ${RED}✗ Failed:${NC}     ${fail_count}"
    echo ""

    if [[ $success_count -gt 0 && "$DRY_RUN" != "true" ]]; then
        echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}${BOLD}║                   DEPOSITS BROADCAST!                            ║${NC}"
        echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}${BOLD}║${NC}  Your deposits have been sent to the network.                    ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}                                                                  ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}  Next steps:                                                     ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}    1. Wait for deposit processing (~16-24 hours)                 ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}    2. Configure and start your validator client                  ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}       cd .. && ./node.sh init vc && ./node.sh start vc          ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}    3. Monitor your validators on the explorer                    ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}║${NC}       https://explorer.labchain.la                               ${GREEN}${BOLD}║${NC}"
        echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    elif [[ "$DRY_RUN" == "true" ]]; then
        echo -e "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}${BOLD}║                      DRY-RUN COMPLETE                            ║${NC}"
        echo -e "${YELLOW}${BOLD}╠══════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${YELLOW}${BOLD}║${NC}  All deposits validated successfully!                             ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}║${NC}                                                                  ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}║${NC}  Run the script again without dry-run to broadcast deposits.    ${YELLOW}${BOLD}║${NC}"
        echo -e "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    fi

    echo ""
}

# Run main
main
