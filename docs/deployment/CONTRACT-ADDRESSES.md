# apDAO LSG Contract Addresses

## Berachain Bartio Testnet (Chain ID: 80084)

**Deployment Date**: _TBD_
**Deployer**: _TBD_

### Core Contracts

| Contract | Address | Verified |
|----------|---------|----------|
| LSGVoter | `0x...` | [ ] |
| Bribe | `0x...` | [ ] |
| MultiTokenRouter | `0x...` | [ ] |

### Strategy Contracts

| Contract | Address | Verified |
|----------|---------|----------|
| DirectDistributionStrategy | `0x...` | [ ] |
| GrowthTreasuryStrategy | `0x...` | [ ] |
| LBTBoostStrategy | `0x...` | [ ] |

### External Dependencies

| Contract | Address | Description |
|----------|---------|-------------|
| Seat NFT | `0x...` | apDAO membership NFT |
| Treasury | `0x...` | Fallback revenue destination |
| Emergency Multisig | `0x...` | Emergency pause authority |
| Growth Treasury | `0x...` | Growth fund destination |
| Kodiak Router | `0x...` | DEX for swaps |
| LBT | `0x...` | Liquid Backing Token |
| WETH | `0x...` | Target token for swaps |

### Configured Revenue Tokens

| Token | Address | Added |
|-------|---------|-------|
| HONEY | `0x...` | [ ] |
| WETH | `0x...` | [ ] |
| USDC | `0x...` | [ ] |

---

## Berachain Mainnet (Chain ID: 81457)

**Deployment Date**: _TBD_
**Deployer**: _TBD_
**Audit Report**: _TBD_

### Core Contracts

| Contract | Address | Verified |
|----------|---------|----------|
| LSGVoter | `0x...` | [ ] |
| Bribe | `0x...` | [ ] |
| MultiTokenRouter | `0x...` | [ ] |

### Strategy Contracts

| Contract | Address | Verified |
|----------|---------|----------|
| DirectDistributionStrategy | `0x...` | [ ] |
| GrowthTreasuryStrategy | `0x...` | [ ] |
| LBTBoostStrategy | `0x...` | [ ] |

### External Dependencies

| Contract | Address | Description |
|----------|---------|-------------|
| Seat NFT | `0x...` | apDAO membership NFT |
| Treasury | `0x...` | Fallback revenue destination |
| Emergency Multisig | `0x...` | Emergency pause authority |
| Growth Treasury | `0x...` | Growth fund destination |
| Kodiak Router | `0x...` | DEX for swaps |
| LBT | `0x...` | Liquid Backing Token |
| WETH | `0x...` | Target token for swaps |

---

## Verification Commands

### LSGVoter
```bash
forge verify-contract \
  --chain-id <CHAIN_ID> \
  --compiler-version v0.8.19 \
  <ADDRESS> \
  src/LSGVoter.sol:LSGVoter \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" <SEAT_NFT> <TREASURY> <EMERGENCY_MULTISIG>)
```

### Bribe
```bash
forge verify-contract \
  --chain-id <CHAIN_ID> \
  --compiler-version v0.8.19 \
  <ADDRESS> \
  src/Bribe.sol:Bribe \
  --constructor-args $(cast abi-encode "constructor(address)" <VOTER>)
```

### MultiTokenRouter
```bash
forge verify-contract \
  --chain-id <CHAIN_ID> \
  --compiler-version v0.8.19 \
  <ADDRESS> \
  src/MultiTokenRouter.sol:MultiTokenRouter \
  --constructor-args $(cast abi-encode "constructor(address)" <VOTER>)
```

### DirectDistributionStrategy
```bash
forge verify-contract \
  --chain-id <CHAIN_ID> \
  --compiler-version v0.8.19 \
  <ADDRESS> \
  src/strategies/DirectDistributionStrategy.sol:DirectDistributionStrategy \
  --constructor-args $(cast abi-encode "constructor(address,address)" <VOTER> <BRIBE>)
```

### GrowthTreasuryStrategy
```bash
forge verify-contract \
  --chain-id <CHAIN_ID> \
  --compiler-version v0.8.19 \
  <ADDRESS> \
  src/strategies/GrowthTreasuryStrategy.sol:GrowthTreasuryStrategy \
  --constructor-args $(cast abi-encode "constructor(address,address)" <VOTER> <GROWTH_TREASURY>)
```

### LBTBoostStrategy
```bash
forge verify-contract \
  --chain-id <CHAIN_ID> \
  --compiler-version v0.8.19 \
  <ADDRESS> \
  src/strategies/LBTBoostStrategy.sol:LBTBoostStrategy \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address)" <VOTER> <KODIAK_ROUTER> <LBT> <TARGET_TOKEN>)
```
