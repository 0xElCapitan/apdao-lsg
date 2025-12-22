# apDAO LSG Architecture

## System Overview
The apDAO Liquid Signal Governance system enables soulbound seat holders to vote weekly on revenue allocation from a Vase Finance subvalidator. It's the first NFT-based liquid signal governance system on Berachain.

## Core Contracts (9 total)

### Primary (3)
- **LSGVoter.sol**: Core voting mechanism. Manages weekly voting epochs. Tracks seat NFT holder votes. Allocates votes to revenue sleeves. Single-transaction voting model.
- **Bribe.sol**: Manages incentive distribution. Accumulates rewards from protocol revenue. Uses Synthetix-style accumulator for precision. Supports multiple token types and deposit times. Epoch-based reward distribution.
- **MultiTokenRouter.sol**: Routes tokens to appropriate destinations. Manages revenue splits. External call surface for integrations.

### Strategies (6)
- **LBTBoost Strategy**: Kodiak swap integration + LBT deposits. Most complex strategy.
- [Additional 5 strategies]: Document as known

## Key Design Patterns

### Single-Transaction Voting
- Users vote and claim rewards in same call
- No async state machines
- Simplifies security model
- Requires careful epoch timing

### Accumulator Pattern
- Synthetix-style fixed-point math
- Avoids iterating over all seat holders
- Enables gas-efficient distribution
- Key invariant: accumulator only increases (monotonic)

### Owner-Gated Strategy
- Owner (apDAO governance) controls active strategies
- No unpermissioned strategy deployment
- Allows ecosystem integration safely
- Pre-approval required before activation

## Data Flows
```
Vase Subvalidator Revenue
    ↓
MultiTokenRouter (distribute to sleeves)
    ↓
Strategy Contracts (execute strategies)
    ↓
Bribe Contract (accumulate rewards)
    ↓
Seat Holders (vote via LSGVoter)
    ↓
Next Epoch (rewards claimed)
```

## Governance Model
- **Seat**: Soulbound ERC-721 NFT. One vote per seat per epoch.
- **Epoch**: Weekly voting period. Votes reset at epoch boundary.
- **Revenue Sleeve**: Destination for protocol revenue.
- **Subvalidator**: Vase Finance validator. Revenue feeds apDAO treasury.

## Integration Points
- **Vase Finance**: Subvalidator position (source of truth for revenue)
- **Berachain Ecosystem**: Leverages native AMM and lending
- **ERC-721**: Seat governance tokens
