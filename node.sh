#!/usr/bin/env bash
# Homychain Node Management Script
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
Homychain Node Manager

USAGE:
  ./node.sh <command> [options]

COMMANDS:
  start <node> [profile]    Start a node
  stop <node> [profile]     Stop a node
  restart <node> [profile]  Restart a node
  logs <node> [profile]     View node logs (follow mode)
  status                    Show status of all nodes
  init                      Initialize network (generate genesis + start all)
  clean <target>            Clean data directories
  health                    Check network health

NODES:
  el      Execution Layer (Reth)
  cl      Consensus Layer (Lighthouse Beacon)
  vc      Validator Client (Lighthouse VC)
  all     All nodes

CLEAN TARGETS:
  el      Clean EL data directory only
  cl      Clean CL data directory only
  vc      Clean VC data directory only
  config  Clean all generated config (genesis, keys, jwt, data)
  all     Clean everything (config + all data)

PROFILES:
  For EL and CL:
    bootnode    Bootnode (first node in network)
    default     Regular node (connects to bootnode)

  For VC:
    genesis     Genesis validators (from genesis generation)
    managed     Managed validators (imported separately)

EXAMPLES:
  ./node.sh start all              # Start all bootnodes (EL, CL, VC genesis)
  ./node.sh start el bootnode      # Start EL bootnode
  ./node.sh stop vc genesis        # Stop genesis validator client
  ./node.sh logs cl bootnode       # View CL bootnode logs
  ./node.sh status                 # Check status of all nodes
  ./node.sh init                   # Full initialization (genesis + start)
  ./node.sh clean all              # Clean everything (stop nodes + delete all data)
  ./node.sh clean el               # Clean only EL chain data
  ./node.sh clean config           # Clean generated config (requires regenerating genesis)

WORKFLOW:
  1. Generate genesis:  ./genesis/gen.sh
  2. Initialize:        ./node.sh init
  3. Check status:      ./node.sh status
  4. View logs:         ./node.sh logs all

For more help, see NODE_MANAGEMENT.md
EOF
}

# Get docker compose command for a node
get_compose_cmd() {
  local node=$1
  local profile=${2:-bootnode}

  case $node in
    el)
      echo "docker compose -f EL/docker-compose.yml --profile $profile"
      ;;
    cl)
      echo "docker compose -f CL/docker-compose.yml --profile $profile"
      ;;
    vc)
      echo "docker compose -f VC/docker-compose.yml --profile $profile"
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
  local profile=${2:-bootnode}

  if [ "$node" = "all" ]; then
    info "Starting all nodes..."
    start_node el bootnode
    sleep 5
    start_node cl bootnode
    sleep 5
    start_node vc genesis
    success "All nodes started"
    return 0
  fi

  info "Starting $node (profile: $profile)..."
  local cmd=$(get_compose_cmd "$node" "$profile")
  eval "$cmd up -d"
  success "$node started"
}

# Stop a node
stop_node() {
  local node=$1
  local profile=${2:-bootnode}

  if [ "$node" = "all" ]; then
    info "Stopping all nodes..."
    stop_node vc genesis 2>/dev/null || true
    stop_node vc managed 2>/dev/null || true
    stop_node cl bootnode 2>/dev/null || true
    stop_node cl default 2>/dev/null || true
    stop_node el bootnode 2>/dev/null || true
    stop_node el default 2>/dev/null || true
    success "All nodes stopped"
    return 0
  fi

  info "Stopping $node (profile: $profile)..."
  local cmd=$(get_compose_cmd "$node" "$profile")
  eval "$cmd down" 2>/dev/null || warn "$node was not running"
  success "$node stopped"
}

# Restart a node
restart_node() {
  local node=$1
  local profile=${2:-bootnode}

  if [ "$node" = "all" ]; then
    info "Restarting all nodes..."
    stop_node all
    sleep 3
    start_node all
    success "All nodes restarted"
    return 0
  fi

  info "Restarting $node (profile: $profile)..."
  stop_node "$node" "$profile"
  sleep 2
  start_node "$node" "$profile"
  success "$node restarted"
}

# View logs
view_logs() {
  local node=$1
  local profile=${2:-bootnode}

  if [ "$node" = "all" ]; then
    info "Showing logs for all running nodes..."
    info "Press Ctrl+C to exit"
    sleep 2

    # Show logs from all running containers
    docker compose -f EL/docker-compose.yml -f CL/docker-compose.yml -f VC/docker-compose.yml logs -f --tail=50
    return 0
  fi

  info "Showing logs for $node (profile: $profile) - Press Ctrl+C to exit"
  local cmd=$(get_compose_cmd "$node" "$profile")
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
  if docker ps --filter "name=lighthouse" --filter "name=bootnode" --format "table {{.Names}}\t{{.Status}}" | grep -q lighthouse; then
    docker ps --filter "name=lighthouse" --filter "name=bootnode" --format "table {{.Names}}\t{{.Status}}"

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

    # Count validators
    VC_COUNT=$(docker logs lighthouse-vc-genesis 2>&1 | grep -i "enabled: true" | wc -l | tr -d ' ')
    if [ "$VC_COUNT" -gt 0 ]; then
      echo -e "  ${GREEN}✓${NC} Active validators: $VC_COUNT"
    fi
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

# Full initialization
init_network() {
  info "Initializing Homychain network..."
  echo ""

  # Check if genesis exists
  if [ ! -f "config/metadata/genesis.json" ]; then
    error "Genesis not found! Run './genesis/gen.sh' first"
    exit 1
  fi

  # Check if data directories are clean
  if [ -d "config/el-data" ] && [ "$(ls -A config/el-data 2>/dev/null)" ]; then
    warn "EL data directory is not empty"
    read -p "Clear existing data? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
      rm -rf config/el-data/*
      success "EL data cleared"
    fi
  fi

  if [ -d "config/cl-data" ] && [ "$(ls -A config/cl-data 2>/dev/null)" ]; then
    warn "CL data directory is not empty"
    read -p "Clear existing data? (yes/no): " -r
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
      rm -rf config/cl-data/*
      success "CL data cleared"
    fi
  fi

  # Create directories
  mkdir -p config/el-data config/cl-data config/vc-data/genesis config/vc-data/managed

  # Start nodes
  info "Starting EL bootnode..."
  start_node el bootnode
  sleep 10

  info "Starting CL bootnode..."
  start_node cl bootnode
  sleep 15

  info "Starting VC (genesis validators)..."
  start_node vc genesis
  sleep 5

  success "Network initialized!"
  echo ""
  info "Checking status..."
  show_status
}

# Clean data directories
clean_data() {
  local target=$1

  case $target in
    el)
      warn "This will delete all EL (Reth) blockchain data!"
      read -p "Are you sure? (yes/no): " -r
      echo
      if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Aborted"
        return 0
      fi

      info "Stopping EL nodes..."
      stop_node el bootnode 2>/dev/null || true
      stop_node el default 2>/dev/null || true

      info "Cleaning EL data..."
      rm -rf config/el-data/*
      success "EL data cleaned"
      ;;

    cl)
      warn "This will delete all CL (Lighthouse) beacon chain data!"
      read -p "Are you sure? (yes/no): " -r
      echo
      if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Aborted"
        return 0
      fi

      info "Stopping CL nodes..."
      stop_node cl bootnode 2>/dev/null || true
      stop_node cl default 2>/dev/null || true

      info "Cleaning CL data..."
      rm -rf config/cl-data/*
      success "CL data cleaned"
      ;;

    vc)
      warn "This will delete all VC (Validator Client) data!"
      read -p "Are you sure? (yes/no): " -r
      echo
      if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Aborted"
        return 0
      fi

      info "Stopping VC nodes..."
      stop_node vc genesis 2>/dev/null || true
      stop_node vc managed 2>/dev/null || true

      info "Cleaning VC data..."
      rm -rf config/vc-data/*
      success "VC data cleaned"
      ;;

    config)
      warn "This will delete ALL generated configuration files!"
      warn "You will need to regenerate genesis after this."
      echo ""
      warn "This will delete:"
      warn "  - config/metadata/ (genesis.json, config.yaml)"
      warn "  - config/keystores/ (validator keys)"
      warn "  - config/jwt/ (JWT secret)"
      warn "  - config/el-data/ (EL blockchain data)"
      warn "  - config/cl-data/ (CL beacon chain data)"
      warn "  - config/vc-data/ (VC data)"
      echo ""
      read -p "Are you sure? (yes/no): " -r
      echo
      if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Aborted"
        return 0
      fi

      info "Stopping all nodes..."
      stop_node all

      info "Cleaning all generated config..."
      rm -rf config/metadata/*
      rm -rf config/keystores/*
      rm -rf config/jwt/*
      rm -rf config/el-data/*
      rm -rf config/cl-data/*
      rm -rf config/vc-data/*

      success "All generated config cleaned"
      info "To restart, run: ./genesis/gen.sh && ./node.sh init"
      ;;

    all)
      warn "This will stop all nodes and delete ALL data and configuration!"
      warn "This includes genesis, keystores, JWT secrets, and all blockchain data."
      echo ""
      read -p "Are you sure? (yes/no): " -r
      echo
      if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        info "Aborted"
        return 0
      fi

      info "Stopping all nodes..."
      stop_node all

      info "Cleaning all data and config..."
      rm -rf config/metadata/*
      rm -rf config/keystores/*
      rm -rf config/jwt/*
      rm -rf config/el-data/*
      rm -rf config/cl-data/*
      rm -rf config/vc-data/*

      success "All data and config cleaned"
      info "To restart, run: ./genesis/gen.sh && ./node.sh init"
      ;;

    *)
      error "Unknown clean target: $target"
      echo ""
      info "Valid targets: el, cl, vc, config, all"
      exit 1
      ;;
  esac
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
    init)
      init_network
      ;;
    clean)
      if [ $# -eq 0 ]; then
        error "Please specify a clean target (el/cl/vc/config/all)"
        echo ""
        info "Examples:"
        info "  ./node.sh clean el      - Clean only EL data"
        info "  ./node.sh clean config  - Clean all generated config"
        info "  ./node.sh clean all     - Clean everything"
        exit 1
      fi
      clean_data "$@"
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
