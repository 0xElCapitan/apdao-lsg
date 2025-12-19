# apDAO LSG Deployment Runbook

## Overview

This runbook provides step-by-step instructions for deploying the apDAO Liquid Signal Governance (LSG) system to Berachain.

**System Components:**
- **LSGVoter**: Core voting contract with NFT-gated governance
- **Bribe**: Synthetix-style reward distribution for voters
- **MultiTokenRouter**: Multi-token revenue aggregation
- **DirectDistributionStrategy**: Forwards revenue to Bribe (voter rewards)
- **GrowthTreasuryStrategy**: Forwards revenue to growth treasury
- **LBTBoostStrategy**: Swaps tokens and adds to LBT backing

---

## Prerequisites

### Required Tools
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast, anvil)
- Git
- Access to deployer wallet private key

### Required Addresses (Before Deployment)
| Address | Description | Who Provides |
|---------|-------------|--------------|
| SEAT_NFT | apDAO membership NFT contract | Vase team |
| TREASURY | Treasury multisig (fallback revenue) | apDAO team |
| EMERGENCY_MULTISIG | Emergency pause authority | apDAO team |
| GROWTH_TREASURY | Growth fund multisig | apDAO team |
| KODIAK_ROUTER | Kodiak DEX router (optional) | Berachain docs |
| LBT | Liquid Backing Token (optional) | Berachain docs |
| TARGET_TOKEN | Swap target token, e.g., WETH (optional) | Berachain docs |

---

## Testnet Deployment

### Step 1: Environment Setup

```bash
# Navigate to contracts directory
cd contracts

# Copy and configure environment
cp script/config/testnet.env.example .env.testnet

# Edit .env.testnet with your values
# IMPORTANT: Never commit .env files with real private keys
```

### Step 2: Configure Environment Variables

Edit `.env.testnet`:
```bash
# Required
PRIVATE_KEY=0x...       # Deployer private key
SEAT_NFT=0x...          # Seat NFT address
TREASURY=0x...          # Treasury multisig
EMERGENCY_MULTISIG=0x... # Emergency multisig
GROWTH_TREASURY=0x...   # Growth treasury

# Optional (for LBTBoostStrategy)
KODIAK_ROUTER=0x...     # Leave empty to skip
LBT=0x...               # Leave empty to skip
TARGET_TOKEN=0x...      # Leave empty to skip
```

### Step 3: Deploy Contracts

```bash
# Load environment
source .env.testnet

# Run deployment (dry-run first)
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  -vvvv

# If dry-run succeeds, broadcast transaction
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvvv
```

### Step 4: Record Deployed Addresses

After deployment, record the addresses from console output:
```
=== Deployment Summary ===

Core Contracts:
  LSGVoter: 0x...
  Bribe: 0x...
  MultiTokenRouter: 0x...

Strategy Contracts:
  DirectDistributionStrategy: 0x...
  GrowthTreasuryStrategy: 0x...
  LBTBoostStrategy: 0x... (if configured)
```

Create a `deployed-addresses.json`:
```json
{
  "network": "berachain-bartio",
  "chainId": 80084,
  "deployedAt": "2025-12-19T00:00:00Z",
  "contracts": {
    "LSGVoter": "0x...",
    "Bribe": "0x...",
    "MultiTokenRouter": "0x...",
    "DirectDistributionStrategy": "0x...",
    "GrowthTreasuryStrategy": "0x...",
    "LBTBoostStrategy": "0x..."
  }
}
```

### Step 5: Verify Contracts

```bash
# Verify LSGVoter
forge verify-contract \
  --chain-id 80084 \
  --compiler-version v0.8.19 \
  <VOTER_ADDRESS> \
  src/LSGVoter.sol:LSGVoter \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" $SEAT_NFT $TREASURY $EMERGENCY_MULTISIG)

# Repeat for each contract...
# See VERIFICATION-COMMANDS.md for full list
```

### Step 6: Configure Revenue Tokens

```bash
# Export deployed addresses
export ROUTER=0x...
export LBT_BOOST_STRATEGY=0x... # if deployed

# Run configuration script
forge script script/ConfigureTokens.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

---

## Mainnet Deployment

### Pre-Deployment Checklist

- [ ] All contracts audited
- [ ] Testnet deployment verified
- [ ] Multisig addresses confirmed
- [ ] Emergency procedures documented
- [ ] Team notified of deployment timeline
- [ ] Gas price acceptable
- [ ] Hardware wallet configured

### Deployment Steps

Same as testnet, but use `.env.mainnet`:

```bash
# Copy and configure mainnet environment
cp script/config/mainnet.env.example .env.mainnet

# Load environment
source .env.mainnet

# Deploy (always dry-run first on mainnet!)
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  -vvvv

# Review output carefully, then broadcast
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvvv
```

---

## Post-Deployment Verification

### Verify Contract Configuration

```bash
# Check LSGVoter router is set
cast call $VOTER "router()(address)" --rpc-url $RPC_URL

# Check Bribe voter reference
cast call $BRIBE "voter()(address)" --rpc-url $RPC_URL

# Check strategies are added
cast call $VOTER "isStrategy(address)(bool)" $DIRECT_DIST --rpc-url $RPC_URL
```

### Test Voting Flow

1. **Vote for a strategy**:
```bash
cast send $VOTER "vote(uint256,address)" <TOKEN_ID> $DIRECT_DIST \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

2. **Check vote is recorded**:
```bash
cast call $VOTER "getVote(uint256)(address)" <TOKEN_ID> --rpc-url $RPC_URL
```

---

## Emergency Procedures

### Pause System

```bash
# Only emergency multisig can pause
cast send $VOTER "pause()" \
  --rpc-url $RPC_URL \
  --private-key $EMERGENCY_MULTISIG_KEY
```

### Unpause System

```bash
# Only emergency multisig can unpause
cast send $VOTER "unpause()" \
  --rpc-url $RPC_URL \
  --private-key $EMERGENCY_MULTISIG_KEY
```

### Rescue Stuck Tokens

```bash
# Strategy owner can rescue tokens from strategy
cast send $STRATEGY "rescueTokens(address,address,uint256)" \
  $TOKEN $RECIPIENT $AMOUNT \
  --rpc-url $RPC_URL \
  --private-key $OWNER_KEY
```

---

## Upgrade/Maintenance Procedures

### Update Treasury Address (GrowthTreasuryStrategy)

```bash
cast send $GROWTH_TREASURY_STRATEGY "setGrowthTreasury(address)" $NEW_TREASURY \
  --rpc-url $RPC_URL \
  --private-key $OWNER_KEY
```

### Add New Revenue Token

```bash
cast send $ROUTER "addToken(address)" $NEW_TOKEN \
  --rpc-url $RPC_URL \
  --private-key $OWNER_KEY
```

### Add New Strategy

```bash
cast send $VOTER "addStrategy(address)" $NEW_STRATEGY \
  --rpc-url $RPC_URL \
  --private-key $OWNER_KEY
```

### Update Swap Path (LBTBoostStrategy)

```bash
# Encode swap path (example: TOKEN -> WETH via 0.3% pool)
SWAP_PATH=$(cast abi-encode "f(bytes)" $(cast --concat-hex $TOKEN 0x000bb8 $WETH))

cast send $LBT_BOOST "setSwapPath(address,bytes)" $TOKEN $SWAP_PATH \
  --rpc-url $RPC_URL \
  --private-key $OWNER_KEY
```

---

## Troubleshooting

### Deployment Fails: "SEAT_NFT not set"
Ensure all required environment variables are set in your `.env` file.

### Verification Fails
- Check compiler version matches (0.8.19)
- Ensure constructor args are correctly encoded
- Wait a few minutes after deployment for indexing

### Transaction Reverts
- Check gas price and limit
- Ensure caller has proper permissions
- Verify addresses are not zero

### Strategy Not Executing
- Check if tokens are in strategy contract
- Verify swap path is configured (for LBTBoostStrategy)
- Check if strategy is added to voter

---

## Contact

For deployment support:
- Discord: apDAO Discord Server
- GitHub: [agentic-base repository](https://github.com/0xElCapitan/agentic-base)
