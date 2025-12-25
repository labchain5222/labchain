# Homychain - Private Ethereum Network

A private Ethereum network with custom genesis attribution, running Reth (EL) and Lighthouse (CL/VC).

---

## 🏗️ Architecture

- **Execution Layer**: Reth (latest)
- **Consensus Layer**: Lighthouse Beacon Node (latest)
- **Validator Client**: Lighthouse VC (64 genesis validators)
- **Network**: Post-merge PoS, 12-second slots
- **Chain ID**: 1337

---

## 📚 Documentation

### Quick Guides
- **[Node Management Guide](docs/NODE_MANAGEMENT.md)** ⭐ **START HERE** - Complete guide for using `./node.sh`

### Component Documentation
- [Execution layer (`EL/`)](docs/execution-layer.md) – Reth nodes, bootnodes, RPC endpoints
- [Consensus layer (`CL/`)](docs/consensus-layer.md) – Lighthouse beacon nodes
- [Genesis tooling (`genesis/`)](docs/genesis.md) – Generate chainspec, JWT secret, validator keystores
- [Validator clients (`VC/`)](docs/validator-client.md) – Manage validators and deposits

---

## 🚀 Quick Start

### Prerequisites

- Docker & Docker Compose
- Ports: 8545, 8546, 8551, 30303 (EL) | 5052, 9000 (CL)
- Shared Docker network: `homychain-net`

### Step 1: Configure Your Network

Edit `genesis.conf` at the project root with your network parameters:

```bash
# Network identity
CONFIG_NAME="mynetwork"           # Your network name (lowercase, no spaces)
CHAIN_ID="12345"                  # Unique chain ID (avoid conflicts on chainlist.org)

# Validator settings
NUMBER_OF_VALIDATORS="64"         # Number of validators at genesis
EL_AND_CL_MNEMONIC="your 24-word mnemonic here"  # Generate with: cast wallet new-mnemonic --words 24

# Withdrawal configuration
WITHDRAWAL_ADDRESS="0x..."        # Your ETH address for validator rewards
WITHDRAWAL_TYPE="0x01"            # Use 0x01 for execution-address withdrawals

# Timing
SLOT_DURATION_IN_SECONDS="12"     # Block time in seconds
GENESIS_DELAY="120"               # Wait time before chain starts (seconds)

# Initial state
GENESIS_GASLIMIT="45000000"       # Block gas limit (45M = mainnet default)
VALIDATOR_BALANCE="32000000000"   # 32 ETH per validator (in gwei)
```

**Key Parameters Explained:**

- **`CONFIG_NAME`** - A unique identifier for your network (e.g., "testnet", "devnet")
- **`CHAIN_ID`** - Must be unique to prevent transaction replay attacks
- **`EL_AND_CL_MNEMONIC`** - **Keep this secret!** Controls all validator keys
- **`WITHDRAWAL_ADDRESS`** - Where validator rewards go (create with `cast wallet new`)
- **`NUMBER_OF_VALIDATORS`** - More validators = more decentralization, slower on single machine

**Fast development chain (3 second blocks):**
```bash
SLOT_DURATION_IN_SECONDS="3"
SLOT_DURATION_MS="3000"
```

**More initial ETH per validator:**
```bash
VALIDATOR_BALANCE="100000000000"  # 100 ETH instead of 32
```

**Larger validator set:**
```bash
NUMBER_OF_VALIDATORS="256"  # Requires more CPU/RAM
```

### Step 2: Create Docker Network

```bash
docker network create homychain-net
```

### Step 3: Generate Genesis Files

```bash
./genesis/gen.sh
```

This creates:
- `config/metadata/genesis.json` - Execution layer genesis
- `config/metadata/config.yaml` - Consensus layer config
- `config/jwt/jwtsecret.hex` - Secure authentication between EL/CL
- `config/keystores/` - Validator private keys

### Step 4: Initialize and Start the Network

```bash
./node.sh init
```

This command:
1. Initializes Reth with the genesis block
2. Sets up Lighthouse beacon node
3. Imports validator keystores
4. Starts all services in the correct order

**Startup Order (handled automatically):**
1. EL (Reth) - Loads genesis
2. CL (Lighthouse) - Connects to EL
3. VC (Validators) - Connects to CL

### Step 5: Verify Everything Works

```bash
# Check all services are running
./node.sh status

# View real-time logs
./node.sh logs all

# Test RPC endpoint
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545
```

### Step 6: Start Building!

Your network is now ready. Connect to:
- **HTTP RPC**: `http://localhost:8545`
- **WebSocket**: `ws://localhost:8546`
- **Beacon API**: `http://localhost:5052`

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Homychain** - Made with love, by Uncle Os and Xangnam - LAOITDEV Team
