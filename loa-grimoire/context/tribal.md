# apDAO LSG Tribal Knowledge

## Known Gotchas

### Token Burn Issue (Historical)
- Previous iteration had token accumulation bugs
- Synthetix-style accumulator in Bribe.sol prevents this
- Lesson: Precision over simplicity in reward math

### Vase Finance Dependency
- Revenue depends on maintaining subvalidator position
- Position requires minimum staking
- Seat voting doesn't directly control position (owner-gated, intentional)
- Separates governance signal from protocol mechanics

### Epoch Boundaries
- Voting locks at epoch end
- Attempts to vote after epoch close revert
- Tests should use block height, not time

### Strategy Complexity
- LBTBoost is most complex (Kodiak integration)
- All strategies are external call surface (security consideration)
- Strategy changes require owner governance proposal
- No unpermissioned deployment

## Design Decisions (Not Obvious from Code)

### Why Soulbound NFTs?
- Prevents vote purchasing/gaming
- Locks governance to committed participants
- Simplifies reward distribution

### Why Weekly Epochs?
- Frequent enough for responsive governance
- Infrequent enough to avoid spam
- Aligns with subvalidator reward cycles

### Why Multiple Sleeves?
- Allows strategy experimentation
- Seat holders vote for preferred revenue use
- Diversifies treasury composition

## Testing Notes
- 242 tests cover happy path + edge cases
- Key categories: epoch transitions, bribe accumulation, multi-token distribution, Vase integration
- [Document any known test gaps]

## Previous Iterations
- Built with Onomancer framework initially
- Migration to Loa motivated by token efficiency needs
- LSG architecture proven in 242 test scenarios
