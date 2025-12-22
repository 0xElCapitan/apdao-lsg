# Technical Constraints

## Immutability
- No contract upgrades (proxy or otherwise)
- No pause mechanisms that break governance
- Code changes require new deployment

## Solidity
- Target: 0.8.x
- No experimental features
- Compiler: optimization enabled (runs: 200)

## Gas Optimization
- Weekly distributions to all seat holders
- Accumulator pattern (not iteration)
- No unbounded loops

## Audit Requirements
- All fund operations immutable post-audit
- Access control explicit
- No hidden state transitions
- Clear code comments on precision/rounding

## Business Constraints
- No breaking changes to governance interface
- Vase integration must remain stable
- Reward distribution formula constant
- Berachain ecosystem dependency

## Audit Scope
**In Scope**: All contracts, all public/external functions, access control, math precision, Vase integration, multi-token handling

**Out of Scope**: Berachain validator mechanics, strategy internals, off-chain voting, economic design
