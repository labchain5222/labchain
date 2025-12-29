# LAB Chain - Join the Network

Welcome to LAB Chain! This guide will help you join our network as a node operator or validator.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Network Information](#network-information)
- [Getting Started](#getting-started)
- [Running Nodes](#running-nodes)
- [Becoming a Validator](#becoming-a-validator)
- [Node Management](#node-management)

---

## Overview

LAB Chain is a Proof-of-Stake Ethereum network. There are three types of nodes you can run:

| Node Type | What It Does | When to Use |
|-----------|--------------|-------------|
| **Full Node** | Runs EL + CL together | You want to run your own complete node |
| **Beacon Node** | Runs CL only | You have access to an external EL |
| **Validator** | Runs VC only | You have access to an external Beacon Node and want to validate |

**Components:**
- **Execution Layer (EL)**: Reth - processes transactions and smart contracts
- **Consensus Layer (CL)**: Lighthouse Beacon Node - handles proof-of-stake consensus
- **Validator Client (VC)**: Lighthouse VC - proposes and attests to blocks

---

## Prerequisites

Before you begin, make sure you have:

**1. Docker & Docker Compose**

Install Docker:
```bash
curl -fsSL https://get.docker.com | sh
```

Create a new user and grant docker permissions:
```bash
# Create new user (replace 'nodeuser' with your preferred username)
sudo useradd -m -s /bin/bash nodeuser

# Add user to docker group
sudo usermod -aG docker nodeuser

# Switch to new user
su - nodeuser
```

Verify installation:
```bash
docker --version
docker compose version
```

**2. Foundry (for validators only)**
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Verify installation
cast --version
```

**3. jq (for validators only)**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq
```

**4. Minimum Hardware**
- CPU: 4 cores
- RAM: 8 GB
- Storage: 100 GB SSD

**5. Network Ports** (open in your firewall)
- `30303` (TCP/UDP) - EL peer discovery
- `9000` (TCP/UDP) - CL peer discovery

---

## Network Information

| Parameter | Value |
|-----------|-------|
| Network Name | `lab-chain` |
| Chain ID | `5222` |
| Slot Duration | 12 seconds |
| Deposit Contract | `0x5454545454545454545454545454545454545454` |
| Explorer | https://explorer.labchain.la |

---

## Getting Started

Follow these steps to set up your environment before running any node.

### Step 1: Clone the Repository

```bash
git clone https://github.com/AIDappLab/labchain.git
cd labchain
```

### Step 2: Create Docker Network

```bash
docker network create labchain-net
```

### Step 3: Generate JWT Secret

The JWT secret secures communication between EL and CL.

```bash
mkdir -p config/jwt
openssl rand -hex 32 > config/jwt/jwtsecret
```

You're now ready to run nodes!

---

## Running Nodes

Use the `./node.sh` script to configure and manage all nodes.

**Note:** The default configuration is pre-configured and ready to use. You can simply press Enter to accept defaults during `./node.sh init`, or skip the init step entirely and start nodes directly.

### Run Execution Layer (EL)

**1. Configure EL (optional - defaults are ready to use):**
```bash
./node.sh init el
```

Configuration options:

| Config | Default |
|--------|---------|
| JSON-RPC HTTP port | `8545` |
| WebSocket RPC port | `8546` |
| Auth RPC port (engine API for CL) | `8551` |
| P2P networking port | `30303` |
| Bootnode enode URL for peer discovery | Pre-configured |

**2. Start EL:**
```bash
./node.sh start el
```

**3. Verify EL is running:**
```bash
./node.sh logs el

# Test RPC
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545
```

---

### Run Consensus Layer (CL)

**1. Configure CL (optional - defaults are ready to use):**
```bash
./node.sh init cl
```

Configuration options:

| Config | Default |
|--------|---------|
| Execution engine endpoint (Reth engine API) | `http://reth-node:8551` |
| Beacon HTTP API port | `5052` |
| P2P networking port | `9000` |
| Target number of peers to connect | `64` |
| Your public IP for P2P discovery | Auto-detected |
| Discovery protocol (`enr` or `libp2p`) | `enr` |
| ENR bootnode addresses (if using ENR mode) | Pre-configured |
| libp2p bootnode addresses (if using libp2p mode) | Pre-configured |

**2. Start CL:**
```bash
./node.sh start cl
```

**3. Verify CL is running:**
```bash
./node.sh logs cl

# Test beacon API
curl http://localhost:5052/eth/v1/node/syncing
```

---

## Becoming a Validator

To become a validator, you need to:
1. Have a running Beacon Node (CL)
2. Generate validator keystores
3. Deposit 32 LAB per validator
4. Run the Validator Client (VC)

### Step 1: Generate Validator Keystores

```bash
cd VC
./manage-validators.sh
```

The script will guide you through:
1. Number of validators to create (default: 1)
2. Your LAB withdrawal address
3. Starting validator index (default: 0)
4. Output directories

**Important:** Save your mnemonic securely when prompted! This is the only way to recover your validator keys.

This creates:
- `./output/deposits.json` - Deposit data for broadcasting
- `./managed-keystores/validators/` - Keystore files
- `./managed-keystores/secrets/` - Password files

### Step 2: Fund Your Validators (Deposit 32 LAB)

You need 32 LAB per validator. Use the deposit script:

```bash
./broadcast-deposits.sh
```

The script will guide you through:
1. Path to deposits.json (default: ./output/deposits.json)
2. RPC endpoint (default: http://localhost:8545)
3. Sender address (your funded wallet)
4. Private key (hidden input)
5. Chain ID and deposit contract (pre-configured defaults)
6. Dry-run option to preview before sending

**Note:** Each deposit costs 32 LAB. Wait for deposits to be processed (about 16-24 hours).

### Step 3: Configure and Start Validator Client

```bash
cd ..

# Configure VC (optional - defaults are ready to use)
./node.sh init vc
```

Configuration options:

| Config | Default |
|--------|---------|
| Beacon node REST API endpoints (comma-separated) | `http://lighthouse-bn:5052` |
| Fee recipient address for block proposals | `0x0000...0000` |
| Root directory for validator keystores | `./managed-keystores` |

```bash
# Start VC
./node.sh start vc
```

### Step 4: Verify Your Validator

```bash
./node.sh logs vc
```

Look for these messages in the logs:
- `Enabled validator` - Your validator is loaded
- `Successfully published attestation` - Validator is attesting (after activation)
- `Successfully published block` - Validator proposed a block

### Exiting Validators (Withdraw Funds)

To exit your validator and withdraw all funds (stake + rewards), use the exit script:

```bash
cd VC
./exit-validators.sh
```

The script will guide you through the process interactively:
1. Configure beacon node URL (default: http://localhost:5052)
2. Configure keystore directory (default: ./managed-keystores)
3. Select validators to exit (all, specific numbers, or by public key)
4. Confirm the exit

**Important:** Voluntary exits are **irreversible**. After exit:
1. Validator enters exit queue
2. Exit processing (~27 hours minimum)
3. Withdrawal delay (~27 hours after exit)
4. Funds (32 LAB + rewards) sent to your withdrawal address

---

## Node Management

The `./node.sh` script provides all commands for managing your nodes.

### Commands

| Command | Description |
|---------|-------------|
| `./node.sh init <node>` | Configure a node interactively (optional) |
| `./node.sh start <node>` | Start a node |
| `./node.sh stop <node>` | Stop a node |
| `./node.sh restart <node>` | Restart a node |
| `./node.sh logs <node>` | View node logs (follow mode) |
| `./node.sh status` | Show status of all nodes |
| `./node.sh health` | Check network health |

### Node Options

| Node | Description |
|------|-------------|
| `el` | Execution Layer (Reth) |
| `cl` | Consensus Layer (Lighthouse Beacon) |
| `vc` | Validator Client (Lighthouse VC) |
| `all` | All nodes |

### Examples

```bash
# Start EL with default settings
./node.sh start el

# Start all nodes
./node.sh start all

# Stop validator client
./node.sh stop vc

# View CL logs
./node.sh logs cl

# Check status of all nodes
./node.sh status

# Restart CL
./node.sh restart cl
```

### Check Sync Status

```bash
# EL sync status
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
  http://localhost:8545

# CL sync status
curl http://localhost:5052/eth/v1/node/syncing
```

### Get Current Block/Slot

```bash
# Current EL block
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545

# Current CL slot
curl http://localhost:5052/eth/v1/beacon/headers/head
```

### Get Bootnode Information

If you're running a bootnode and need to share connection info with other nodes:

**Get EL Bootnode Enode:**
```bash
cd EL
./get-bootnode-enode.sh
```
This returns the enode URL (e.g., `enode://abc123...@IP:30303`) that other EL nodes can use to connect.

**Note:** When sharing bootnode addresses with other operators, replace `IP` with your server's public IP address so they can connect to your node.

**Get CL Bootnode ENR:**
```bash
cd CL
./get-bootnode-enr.sh
```
This returns the ENR record (e.g., `enr:-...`) that other CL nodes can use for peer discovery.

**Get CL Bootnode libp2p Address:**
```bash
# Get libp2p multiaddr from beacon node
curl -s http://localhost:5052/eth/v1/node/identity | jq -r '.data.p2p_addresses[0]'
```
This returns the libp2p multiaddr (e.g., `/ip4/IP/tcp/9000/p2p/PEER_ID`) for nodes using libp2p discovery mode.

**Note:** When sharing bootnode addresses with other operators, replace `IP` with your server's public IP address so they can connect to your node.

You can also specify a custom RPC URL:
```bash
# Custom EL RPC
RPC_URL=http://192.168.1.100:8545 ./get-bootnode-enode.sh

# Custom CL RPC
RPC_URL=http://192.168.1.100:5052 ./get-bootnode-enr.sh
```

---

**LAB Chain** - LAO Blockchain Made with love, by Uncle Os555 and Xangnam - LAOITDEV Team
