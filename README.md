# apDAO LSG Contracts

Liquid Signal Governance contracts for apDAO revenue allocation.

## Setup

```bash
# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0
forge install transmissions11/solmate@v6.2.0

# Build
forge build

# Test
forge test

# Test with coverage
forge coverage

# Run specific test
forge test --match-test test_Flush_SingleToken -vvv
```

## Contract Architecture

- **MultiTokenRouter**: Receives revenue from Vase and forwards to LSGVoter
- **LSGVoter**: Core voting contract (Sprint 2)
- **Bribe**: Reward distribution (Sprint 3)
- **Strategies**: LBT Boost, Direct Distribution, Growth Treasury, PoL Reinvestment (Sprint 4)

## Deployment

See `script/Deploy.s.sol` for deployment scripts.

## Testing

- Unit tests: `test/*.t.sol`
- Mock contracts: `test/mocks/`
- Integration tests: Coming in Sprint 5

## Security

This code will undergo professional audit by Pashov Audit Group before mainnet deployment.
