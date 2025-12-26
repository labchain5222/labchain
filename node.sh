#!/usr/bin/env bash
# LabChain Node Management Script
# Easy control for Execution Layer (EL), Consensus Layer (CL), and Validator Client (VC)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored messages
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Usage information
usage() {
  cat <<'EOF'
LabChain Node Manager

USAGE:
  ./node.sh <command> [node]

COMMANDS:
  init <node>       Interactive configuration for a node
  start <node>      Start a node
  stop <node>       Stop a node
  restart <node>    Restart a node
  logs <node>       View node logs (follow mode)
  status            Show status of all nodes
  health            Check network health

NODES:
  el      Execution Layer (Reth)
  cl      Consensus Layer (Lighthouse Beacon)
  vc      Validator Client (Lighthouse VC)
  all     All nodes

EXAMPLES:
  ./node.sh init el           # Configure EL (ports, bootnode)
  ./node.sh init cl           # Configure CL (ports, discovery, bootnodes)
  ./node.sh init vc           # Configure VC (beacon endpoints, fee recipient)
  ./node.sh init all          # Configure all nodes interactively
  ./node.sh start all         # Start all nodes (EL, CL, VC)
  ./node.sh start el          # Start only EL
  ./node.sh stop vc           # Stop validator client
  ./node.sh logs cl           # View CL logs
  ./node.sh status            # Check status of all nodes

ENVIRONMENT VARIABLES:
  EL:
    BOOTNODES           - Comma-separated list of EL bootnodes (enode://...)
    EL_DATA_DIR         - Path to EL data directory
    GENESIS_DIR         - Path to genesis files
    JWT_SECRET          - Path to JWT secret file

  CL:
    BOOT_NODES          - Comma-separated list of CL bootnodes (enr:...)
    EXECUTION_ENDPOINT  - URL of execution layer RPC
    CL_DATA_DIR         - Path to CL data directory
    CONSENSUS_DIR       - Path to consensus config files

  VC:
    KEYSTORE_DIR        - Path to validator keystores (required)
    BEACON_NODE_ENDPOINTS - URL of beacon node API
    FEE_RECIPIENT       - Fee recipient address

EOF
}

# Truncate long text for display
truncate_text() {
  local text="$1"
  local max_len="${2:-40}"

  if [ ${#text} -gt $max_len ]; then
    echo "${text:0:$max_len}..."
  else
    echo "$text"
  fi
}

# Prompt for input with default value
# Usage: prompt_input "Description" "default_value"
# Returns: the user input or default value
prompt_input() {
  local description="$1"
  local default="$2"
  local value
  local display_default

  if [ -n "$default" ]; then
    display_default=$(truncate_text "$default" 40)
    read -p "  [$description (default: $display_default)]: " value
    value="${value:-$default}"
  else
    read -p "  [$description]: " value
  fi

  echo "$value"
}

# Prompt for IP selection (public/internal/custom)
prompt_ip_selection() {
  local description="$1"
  local default="$2"

  echo -e "  [${description} (default: $default)]:" >&2

  local public_ip internal_ip
  public_ip=$(get_public_ip 2>/dev/null) || public_ip=""
  internal_ip=$(get_internal_ip 2>/dev/null) || internal_ip=""

  local options=()
  local option_num=1

  if [ -n "$public_ip" ]; then
    echo -e "    ${GREEN}$option_num)${NC} Public IP: $public_ip" >&2
    options+=("$public_ip")
    ((option_num++))
  fi

  if [ -n "$internal_ip" ]; then
    echo -e "    ${GREEN}$option_num)${NC} Internal IP: $internal_ip" >&2
    options+=("$internal_ip")
    ((option_num++))
  fi

  echo -e "    ${GREEN}$option_num)${NC} Keep current ($default)" >&2
  options+=("$default")
  ((option_num++))

  echo -e "    ${GREEN}$option_num)${NC} Custom IP (enter manually)" >&2
  options+=("custom")

  local selection
  while true; do
    read -p "  Select [1-$option_num]: " selection

    if [ -z "$selection" ]; then
      echo "$default"
      return
    fi

    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$option_num" ]; then
      break
    fi
    warn "Invalid selection"
  done

  local idx=$((selection - 1))
  local selected="${options[$idx]}"

  if [ "$selected" = "custom" ]; then
    while true; do
      read -p "  Enter custom IP: " selected
      if [[ $selected =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        break
      fi
      warn "Invalid IP format (e.g., 192.168.1.100)"
    done
  fi

  echo "$selected"
}

# Prompt for discovery mode selection
prompt_discovery_mode() {
  local default="$1"
  local selected

  echo -e "  [Discovery mode (default: $default)]:" >&2
  echo -e "    ${GREEN}1)${NC} enr - ENR-based discovery (--boot-nodes)" >&2
  echo -e "    ${GREEN}2)${NC} libp2p - libp2p multiaddr (--libp2p-addresses)" >&2

  local selection
  read -p "  Select [1-2]: " selection

  case "$selection" in
    1) selected="enr" ;;
    2) selected="libp2p" ;;
    *) selected="$default" ;;
  esac

  echo "$selected"
}

# Update a variable in .env file
update_env_var() {
  local env_file="$1"
  local var_name="$2"
  local new_value="$3"

  if grep -q "^${var_name}=" "$env_file"; then
    sed -i.bak "s|^${var_name}=.*|${var_name}=${new_value}|" "$env_file"
    rm -f "${env_file}.bak"
  else
    echo "${var_name}=${new_value}" >> "$env_file"
  fi
}

# Get current value from .env file
get_env_var() {
  local env_file="$1"
  local var_name="$2"
  local default="$3"

  if [ -f "$env_file" ] && grep -q "^${var_name}=" "$env_file"; then
    grep "^${var_name}=" "$env_file" | cut -d'=' -f2-
  else
    echo "$default"
  fi
}

# Get public IP address
get_public_ip() {
  local ip=""

  # Try multiple services to get public IP
  ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null) || \
  ip=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null) || \
  ip=$(curl -s --max-time 5 https://icanhazip.com 2>/dev/null) || \
  ip=$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null)

  # Validate IP format
  if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$ip"
  else
    return 1
  fi
}

# Get internal/local IP address
get_internal_ip() {
  local ip=""

  # Try to get the primary internal IP
  if command -v ip &> /dev/null; then
    # Linux with ip command
    ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
  fi

  if [ -z "$ip" ] && command -v ifconfig &> /dev/null; then
    # macOS / BSD
    ip=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')
  fi

  # Validate IP format
  if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$ip"
  else
    return 1
  fi
}

# Initialize node configuration
init_node() {
  local node=$1

  case $node in
    el)
      init_el
      ;;
    cl)
      init_cl
      ;;
    vc)
      init_vc
      ;;
    all)
      info "Initializing all nodes..."
      echo ""
      init_el
      echo ""
      echo -e "${BLUE}────────────────────────────────────────${NC}"
      init_cl
      echo ""
      echo -e "${BLUE}────────────────────────────────────────${NC}"
      init_vc
      echo ""
      success "All nodes initialized"
      ;;
    *)
      error "Unknown node: $node. Use 'el', 'cl', 'vc', or 'all'"
      return 1
      ;;
  esac
}

# Initialize VC configuration
init_vc() {
  local env_file="$SCRIPT_DIR/VC/.env"

  if [ ! -f "$env_file" ]; then
    error "VC/.env file not found"
    return 1
  fi

  echo ""
  echo -e "${BLUE}=== Validator Client (VC) Configuration ===${NC}"
  echo -e "${YELLOW}Press Enter to keep current/default value${NC}"
  echo ""

  # Get current values
  local cur_beacon_endpoints=$(get_env_var "$env_file" "BEACON_NODE_ENDPOINTS" "http://lighthouse-bn:5052")
  local cur_fee_recipient=$(get_env_var "$env_file" "FEE_RECIPIENT" "0x0000000000000000000000000000000000000000")
  local cur_keystore_dir=$(get_env_var "$env_file" "KEYSTORE_DIR" "./managed-keystores")

  # Prompt for each config
  local new_beacon_endpoints=$(prompt_input "Beacon node REST endpoints (comma-separated)" "$cur_beacon_endpoints")
  echo ""

  local new_fee_recipient=$(prompt_input "Fee recipient address for block proposals (0x...)" "$cur_fee_recipient")
  echo ""

  local new_keystore_dir=$(prompt_input "Root directory for validator keystores" "$cur_keystore_dir")

  # Update .env file
  echo ""
  info "Updating VC/.env..."

  update_env_var "$env_file" "BEACON_NODE_ENDPOINTS" "$new_beacon_endpoints"
  update_env_var "$env_file" "FEE_RECIPIENT" "$new_fee_recipient"
  update_env_var "$env_file" "KEYSTORE_DIR" "$new_keystore_dir"

  success "VC configuration updated successfully!"
  echo ""
  echo -e "${BLUE}Configuration Summary:${NC}"
  echo -e "  ${GREEN}BEACON_NODE_ENDPOINTS${NC} (Beacon node REST endpoints)"
  echo -e "    → $new_beacon_endpoints"
  echo -e "  ${GREEN}FEE_RECIPIENT${NC} (Fee recipient address for block proposals)"
  echo -e "    → $new_fee_recipient"
  echo -e "  ${GREEN}KEYSTORE_DIR${NC} (Root directory for validator keystores)"
  echo -e "    → $new_keystore_dir"
}

# Initialize EL configuration
init_el() {
  local env_file="$SCRIPT_DIR/EL/.env"

  if [ ! -f "$env_file" ]; then
    error "EL/.env file not found"
    return 1
  fi

  echo ""
  echo -e "${BLUE}=== Execution Layer (EL) Configuration ===${NC}"
  echo -e "${YELLOW}Press Enter to keep current/default value${NC}"
  echo ""

  # Get current values
  local cur_http_port=$(get_env_var "$env_file" "HTTP_PORT" "8545")
  local cur_ws_port=$(get_env_var "$env_file" "WS_PORT" "8546")
  local cur_authrpc_port=$(get_env_var "$env_file" "AUTHRPC_PORT" "8551")
  local cur_p2p_port=$(get_env_var "$env_file" "P2P_PORT" "30303")
  local cur_bootnode_enode=$(get_env_var "$env_file" "BOOTNODE_ENODE" "")

  # Prompt for each config
  local new_http_port=$(prompt_input "JSON-RPC HTTP port" "$cur_http_port")
  echo ""

  local new_ws_port=$(prompt_input "WebSocket RPC port" "$cur_ws_port")
  echo ""

  local new_authrpc_port=$(prompt_input "Auth RPC port (engine API for CL)" "$cur_authrpc_port")
  echo ""

  local new_p2p_port=$(prompt_input "P2P networking port" "$cur_p2p_port")
  echo ""

  local new_bootnode_enode=$(prompt_input "Bootnode enode URL (enode://...@host:port)" "$cur_bootnode_enode")

  # Update .env file
  echo ""
  info "Updating EL/.env..."

  update_env_var "$env_file" "HTTP_PORT" "$new_http_port"
  update_env_var "$env_file" "WS_PORT" "$new_ws_port"
  update_env_var "$env_file" "AUTHRPC_PORT" "$new_authrpc_port"
  update_env_var "$env_file" "P2P_PORT" "$new_p2p_port"
  update_env_var "$env_file" "BOOTNODE_ENODE" "$new_bootnode_enode"

  success "EL configuration updated successfully!"
  echo ""
  echo -e "${BLUE}Configuration Summary:${NC}"
  echo -e "  ${GREEN}HTTP_PORT${NC} (JSON-RPC HTTP port)"
  echo -e "    → $new_http_port"
  echo -e "  ${GREEN}WS_PORT${NC} (WebSocket RPC port)"
  echo -e "    → $new_ws_port"
  echo -e "  ${GREEN}AUTHRPC_PORT${NC} (Auth RPC port for CL engine API)"
  echo -e "    → $new_authrpc_port"
  echo -e "  ${GREEN}P2P_PORT${NC} (P2P networking port)"
  echo -e "    → $new_p2p_port"
  echo -e "  ${GREEN}BOOTNODE_ENODE${NC} (Bootnode enode URL)"
  echo -e "    → ${new_bootnode_enode:-(not set)}"
}

# Initialize CL configuration
init_cl() {
  local env_file="$SCRIPT_DIR/CL/.env"

  if [ ! -f "$env_file" ]; then
    error "CL/.env file not found"
    return 1
  fi

  echo ""
  echo -e "${BLUE}=== Consensus Layer (CL) Configuration ===${NC}"
  echo -e "${YELLOW}Press Enter to keep current/default value${NC}"
  echo ""

  # Get current values
  local cur_exec_endpoint=$(get_env_var "$env_file" "EXECUTION_ENDPOINT" "http://reth-node:8551")
  local cur_http_port=$(get_env_var "$env_file" "HTTP_PORT" "5052")
  local cur_p2p_port=$(get_env_var "$env_file" "P2P_PORT" "9000")
  local cur_target_peers=$(get_env_var "$env_file" "TARGET_PEERS" "64")
  local cur_enr_address=$(get_env_var "$env_file" "BEACON_ENR_ADDRESS" "127.0.0.1")
  local cur_discovery_mode=$(get_env_var "$env_file" "DISCOVERY_MODE" "enr")
  local cur_bootnode_enr=$(get_env_var "$env_file" "BOOTNODE_ENR" "")
  local cur_bootnode_libp2p=$(get_env_var "$env_file" "BOOTNODE_LIBP2P" "")

  # Prompt for each config
  local new_exec_endpoint=$(prompt_input "Execution engine endpoint (reth engine API)" "$cur_exec_endpoint")
  echo ""

  local new_http_port=$(prompt_input "Beacon HTTP API port" "$cur_http_port")
  echo ""

  local new_p2p_port=$(prompt_input "P2P networking port" "$cur_p2p_port")
  echo ""

  local new_target_peers=$(prompt_input "Target number of peers" "$cur_target_peers")
  echo ""

  info "Detecting IP addresses for ENR..."
  local new_enr_address=$(prompt_ip_selection "ENR address for P2P discovery" "$cur_enr_address")
  echo ""

  local new_discovery_mode=$(prompt_discovery_mode "$cur_discovery_mode")
  echo ""

  local new_bootnode_enr
  if [ "$new_discovery_mode" = "enr" ]; then
    new_bootnode_enr=$(prompt_input "ENR bootnode(s) for sync (comma-separated enr:-...)" "$cur_bootnode_enr")
  else
    new_bootnode_enr="$cur_bootnode_enr"
  fi
  echo ""

  local new_bootnode_libp2p
  if [ "$new_discovery_mode" = "libp2p" ]; then
    new_bootnode_libp2p=$(prompt_input "libp2p bootnode(s) (comma-separated /ip4/.../tcp/.../p2p/...)" "$cur_bootnode_libp2p")
  else
    new_bootnode_libp2p="$cur_bootnode_libp2p"
  fi

  # Update .env file
  echo ""
  info "Updating CL/.env..."

  update_env_var "$env_file" "EXECUTION_ENDPOINT" "$new_exec_endpoint"
  update_env_var "$env_file" "HTTP_PORT" "$new_http_port"
  update_env_var "$env_file" "P2P_PORT" "$new_p2p_port"
  update_env_var "$env_file" "TARGET_PEERS" "$new_target_peers"
  update_env_var "$env_file" "BEACON_ENR_ADDRESS" "$new_enr_address"
  update_env_var "$env_file" "DISCOVERY_MODE" "$new_discovery_mode"
  update_env_var "$env_file" "BOOTNODE_ENR" "$new_bootnode_enr"
  update_env_var "$env_file" "BOOTNODE_LIBP2P" "$new_bootnode_libp2p"

  success "CL configuration updated successfully!"
  echo ""
  echo -e "${BLUE}Configuration Summary:${NC}"
  echo -e "  ${GREEN}EXECUTION_ENDPOINT${NC} (Execution engine endpoint - reth engine API)"
  echo -e "    → $new_exec_endpoint"
  echo -e "  ${GREEN}HTTP_PORT${NC} (Beacon HTTP API port)"
  echo -e "    → $new_http_port"
  echo -e "  ${GREEN}P2P_PORT${NC} (P2P networking port)"
  echo -e "    → $new_p2p_port"
  echo -e "  ${GREEN}TARGET_PEERS${NC} (Target number of peers)"
  echo -e "    → $new_target_peers"
  echo -e "  ${GREEN}BEACON_ENR_ADDRESS${NC} (ENR address for P2P discovery)"
  echo -e "    → $new_enr_address"
  echo -e "  ${GREEN}DISCOVERY_MODE${NC} (Discovery protocol: enr or libp2p)"
  echo -e "    → $new_discovery_mode"
  if [ "$new_discovery_mode" = "enr" ]; then
    echo -e "  ${GREEN}BOOTNODE_ENR${NC} (ENR bootnode addresses)"
    echo -e "    → ${new_bootnode_enr:-(not set)}"
  else
    echo -e "  ${GREEN}BOOTNODE_LIBP2P${NC} (libp2p bootnode addresses)"
    echo -e "    → ${new_bootnode_libp2p:-(not set)}"
  fi
}

# Get docker compose command for a node
get_compose_cmd() {
  local node=$1

  case $node in
    el)
      echo "docker compose -f EL/docker-compose.yml"
      ;;
    cl)
      echo "docker compose -f CL/docker-compose.yml"
      ;;
    vc)
      echo "docker compose -f VC/docker-compose.yml"
      ;;
    *)
      error "Unknown node: $node"
      return 1
      ;;
  esac
}

# Start a node
start_node() {
  local node=$1

  if [ "$node" = "all" ]; then
    info "Starting all nodes..."
    start_node el
    sleep 5
    start_node cl
    sleep 5
    start_node vc
    success "All nodes started"
    return 0
  fi

  info "Starting $node..."
  local cmd=$(get_compose_cmd "$node")
  eval "$cmd up -d"
  success "$node started"
}

# Stop a node
stop_node() {
  local node=$1

  if [ "$node" = "all" ]; then
    info "Stopping all nodes..."
    stop_node vc 2>/dev/null || true
    stop_node cl 2>/dev/null || true
    stop_node el 2>/dev/null || true
    success "All nodes stopped"
    return 0
  fi

  info "Stopping $node..."
  local cmd=$(get_compose_cmd "$node")
  eval "$cmd down" 2>/dev/null || warn "$node was not running"
  success "$node stopped"
}

# Restart a node
restart_node() {
  local node=$1

  if [ "$node" = "all" ]; then
    info "Restarting all nodes..."
    stop_node all
    sleep 3
    start_node all
    success "All nodes restarted"
    return 0
  fi

  info "Restarting $node..."
  stop_node "$node"
  sleep 2
  start_node "$node"
  success "$node restarted"
}

# View logs
view_logs() {
  local node=$1

  if [ "$node" = "all" ]; then
    info "Showing logs for all running nodes..."
    info "Press Ctrl+C to exit"
    sleep 2

    # Show logs from all running containers
    docker compose -f EL/docker-compose.yml -f CL/docker-compose.yml -f VC/docker-compose.yml logs -f --tail=50
    return 0
  fi

  info "Showing logs for $node - Press Ctrl+C to exit"
  local cmd=$(get_compose_cmd "$node")
  eval "$cmd logs -f --tail=100"
}

# Show status of all nodes
show_status() {
  info "Checking node status..."
  echo ""

  # Check EL
  echo -e "${BLUE}=== Execution Layer (EL) ===${NC}"
  if docker ps --filter "name=reth" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q reth; then
    docker ps --filter "name=reth" --format "table {{.Names}}\t{{.Status}}"

    # Get block number
    BLOCK=$(curl -s -X POST -H "Content-Type: application/json" \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
      http://localhost:8545 2>/dev/null | grep -o '"result":"[^"]*"' | cut -d'"' -f4)

    if [ -n "$BLOCK" ]; then
      BLOCK_NUM=$((16#${BLOCK#0x}))
      echo -e "  ${GREEN}✓${NC} Block number: $BLOCK_NUM"
    fi
  else
    echo -e "  ${RED}✗${NC} Not running"
  fi
  echo ""

  # Check CL
  echo -e "${BLUE}=== Consensus Layer (CL) ===${NC}"
  if docker ps --filter "name=lighthouse" --format "table {{.Names}}\t{{.Status}}" | grep -q lighthouse; then
    docker ps --filter "name=lighthouse" --format "table {{.Names}}\t{{.Status}}" | grep -v "\-vc"

    # Get head slot
    if curl -s http://localhost:5052/eth/v1/node/health > /dev/null 2>&1; then
      HEAD_SLOT=$(curl -s http://localhost:5052/eth/v1/beacon/headers/head 2>/dev/null | grep -o '"slot":"[^"]*"' | head -1 | cut -d'"' -f4)
      echo -e "  ${GREEN}✓${NC} Head slot: ${HEAD_SLOT:-0}"
    fi
  else
    echo -e "  ${RED}✗${NC} Not running"
  fi
  echo ""

  # Check VC
  echo -e "${BLUE}=== Validator Client (VC) ===${NC}"
  if docker ps --filter "name=lighthouse-vc" --format "table {{.Names}}\t{{.Status}}" | grep -q lighthouse-vc; then
    docker ps --filter "name=lighthouse-vc" --format "table {{.Names}}\t{{.Status}}"
    echo -e "  ${GREEN}✓${NC} Validator client running"
  else
    echo -e "  ${RED}✗${NC} Not running"
  fi
  echo ""
}

# Check network health
check_health() {
  info "Running health checks..."

  if [ ! -f "./check-engine-api.sh" ]; then
    error "check-engine-api.sh not found"
    return 1
  fi

  ./check-engine-api.sh
}

# Main command handler
main() {
  if [ $# -eq 0 ]; then
    usage
    exit 0
  fi

  local command=$1
  shift

  case $command in
    init)
      if [ $# -eq 0 ]; then
        error "Please specify a node (el/cl/vc/all)"
        exit 1
      fi
      init_node "$@"
      ;;
    start)
      if [ $# -eq 0 ]; then
        error "Please specify a node (el/cl/vc/all)"
        exit 1
      fi
      start_node "$@"
      ;;
    stop)
      if [ $# -eq 0 ]; then
        error "Please specify a node (el/cl/vc/all)"
        exit 1
      fi
      stop_node "$@"
      ;;
    restart)
      if [ $# -eq 0 ]; then
        error "Please specify a node (el/cl/vc/all)"
        exit 1
      fi
      restart_node "$@"
      ;;
    logs)
      if [ $# -eq 0 ]; then
        error "Please specify a node (el/cl/vc/all)"
        exit 1
      fi
      view_logs "$@"
      ;;
    status)
      show_status
      ;;
    health)
      check_health
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      error "Unknown command: $command"
      echo ""
      usage
      exit 1
      ;;
  esac
}

main "$@"
