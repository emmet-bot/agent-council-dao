# P11 — LSP7 + IVotes Governance Token Specification

**Status:** Proposed March 27, 2026  
**Target:** Replace the current P9 ERC20Votes test token with a LUKSO-native LSP7 voting token on LUKSO mainnet, while keeping ERC20Votes deployments on Base and Ethereum where appropriate.

## Current Repo State

- `proposals/P11-lsp7-ivotes-spec.md` did not exist before this work.
- Branch `feat/p11-lsp7-ivotes` did not exist before this work.
- Repo currently has a working P9 implementation under `contracts/src/governance/` based on:
  - `CouncilToken.sol` using `ERC20Votes`
  - `CouncilGovernor.sol` using OpenZeppelin `GovernorVotes`
  - `CouncilGovernor.t.sol` integration tests
- The comment in `contracts/src/governance/CouncilToken.sol` claiming `LSP7VotesInitAbstract` does not exist is outdated. The LUKSO contracts repo now includes both `LSP7Votes.sol` and `LSP7VotesInitAbstract.sol`.

## Research Summary

### 1. Does `LSP7VotesInitAbstract` implement the interface required by OpenZeppelin `GovernorVotes`?

Yes.

`LSP7VotesInitAbstract` inherits `IERC5805` directly. `IERC5805` extends both:
- `IVotes`
- `IERC6372`

OpenZeppelin `GovernorVotes` takes an `IVotes` in its constructor, but internally stores it as `IERC5805`:

```solidity
constructor(IVotes tokenAddress) {
    _token = IERC5805(address(tokenAddress));
}
```

That means a token must behave as both:
- `IVotes` for vote lookups and delegation
- `IERC6372` / `IERC5805` for clock compatibility

`LSP7VotesInitAbstract` provides the required surface:
- `getVotes(address)`
- `getPastVotes(address,uint256)`
- `getPastTotalSupply(uint256)`
- `delegates(address)`
- `delegate(address)`
- `delegateBySig(...)`
- `clock()`
- `CLOCK_MODE()`

### 2. Does it plug into `GovernorVotes` directly?

Yes, in principle.

No adapter is required for OpenZeppelin governor compatibility, because `LSP7VotesInitAbstract` already implements `IERC5805`, which is strictly more specific than the `IVotes` constructor type used by `GovernorVotes`.

A governor can be constructed against the LSP7 token exactly the same way the current P9 governor is constructed against `ERC20Votes`:

```solidity
GovernorVotes(IVotes(address(councilTokenLSP7)))
```

### 3. What still needs custom work?

A concrete token contract is still required.

`LSP7VotesInitAbstract` is an abstract base. We still need a concrete `CouncilTokenLSP7` that:
- calls `_initialize(...)`
- exposes mint/distribution logic
- defines transfer/mint/burn hooks correctly so voting checkpoints move with token balances
- chooses divisibility (`isNonDivisible_ = false` if we want ERC20-like 18-decimal governance units)
- chooses owner/controller model compatible with the Council Universal Profile

So the answer is:
- **No IVotes wrapper needed for GovernorVotes**
- **Yes, a concrete LSP7 governance token contract is needed**

## Proposed Architecture

### CouncilTokenLSP7

Create a new contract:
- `contracts/src/governance/CouncilTokenLSP7.sol`

Design:
- Base: `LSP7VotesInitAbstract` (or `LSP7Votes` if a non-initializable constructor-based deployment is preferred for Foundry-only testing)
- Name: `Agent Council Token`
- Symbol: `COUNCIL`
- Supply model: fixed initial mint of `1_000_000 * 10^18`
- Initial distribution: preserve the P9 skewed test distribution unless governance approves new economics
  - 40% agent1
  - 30% agent2
  - 20% agent3
  - 10% agent4

Implementation expectations:
- mint balances during initialization/deployment
- require self-delegation for checkpoints, same as OZ `Votes`
- keep `clock()` on block number mode for governor compatibility and parity with current tests
- expose only minimal minting authority; likely one-shot initialization mint only unless later governance explicitly wants inflation

### Governor Compatibility

Keep `CouncilGovernor` on OpenZeppelin Governor stack.

Expected constructor pattern:

```solidity
new CouncilGovernor(IVotes(address(councilTokenLSP7)), timelock)
```

No special governor fork should be required if tests confirm:
- proposal threshold reads correctly
- quorum snapshots use `getPastTotalSupply`
- voting power snapshots use `getPastVotes`
- delegation works after self-delegation

## Universal Profile Integration

The governance token should be controlled in a way that matches LUKSO account architecture.

Recommended model:
- The **Council Universal Profile** is the owner/controller of the LSP7 token contract, or is the holder of privileged mint/setup permissions if ownership must be retained elsewhere during bootstrap.
- The **Governor + Timelock** should be authorized as a controller on the Council UP through LSP6 permissions.
- Governance actions then execute through the Council UP rather than through an EOA.

Practical implication:
- once bootstrap is complete, the governor/timelock should be able to instruct the Council UP to perform controlled actions such as treasury management, metadata changes, and approved protocol operations
- exact permission bits and allowed calls need to be specified in the deployment playbook, not left implicit

## Multi-Chain Plan

This should **not** be forced into a single token standard across all chains.

Recommended split:
- **LUKSO mainnet:** `CouncilTokenLSP7` based on `LSP7VotesInitAbstract`
- **Base:** separate `ERC20Votes` deployment
- **Ethereum:** separate `ERC20Votes` deployment

Reason:
- LSP7 is the native fit on LUKSO and integrates with Universal Profiles
- Base/Ethereum should remain standard ERC20Votes for tooling, wallets, bridges, and governor compatibility on those chains
- trying to make one token contract pattern span all chains adds complexity without upside

Cross-chain governance should therefore be treated as coordination between chain-local governance assets, not as a fake “single token everywhere” abstraction.

## Migration Path from P9 ERC20 Testnet Token

P9 should be treated as a validation phase, not production token finality.

Recommended migration:
1. Keep the existing P9 `ERC20Votes` contracts as the testnet reference implementation.
2. Add `CouncilTokenLSP7` beside the current `CouncilToken` instead of mutating P9 in place immediately.
3. Re-run the current governor integration suite against the LSP7 token.
4. Add LUKSO-mainnet-specific tests for:
   - self-delegation
   - vote movement on transfers
   - UP ownership/controller flows
   - any LSP1/LSP6 side effects
5. Once validated, make `CouncilTokenLSP7` the LUKSO production path.
6. Keep `CouncilToken` / `ERC20Votes` as separate chain-specific implementations for Base and Ethereum.

This avoids pretending the P9 ERC20 test token can be upgraded in place into an LSP7. It cannot. This is a controlled replacement on LUKSO, not a magical in-place migration.

## Estimated Work

### Phase A — Contract Build (1-2 days)
- implement `CouncilTokenLSP7`
- wire constructor/initializer
- reproduce initial skewed mint
- compile against current foundry config and remappings

### Phase B — Governor Integration Tests (1 day)
- port the existing `CouncilGovernor.t.sol` flow to LSP7
- verify proposal lifecycle, quorum, and delegation checkpoints
- verify no custom Governor adapter is needed

### Phase C — Universal Profile Authorization (1-2 days)
- define Council UP permission model
- grant Governor/Timelock controller rights through LSP6
- test execution path through the UP

### Phase D — Mainnet Readiness Review (0.5-1 day)
- validate metadata / decimals assumptions
- validate explorer and wallet behavior for divisibility
- confirm deployment scripts and operational runbooks

## Open Research Questions

1. **Concrete base choice:** should production use `LSP7VotesInitAbstract` directly in an upgradeable-style pattern, or `LSP7Votes` for simpler constructor-based deployment?
2. **Decimals/divisibility semantics:** confirm the cleanest LSP7 setup for ERC20-like 18-decimal governance amounts and whether any UI/indexer assumptions need special handling.
3. **Mint hook behavior:** verify the exact internal hooks required so vote checkpoints always track mint, burn, and transfer correctly in the concrete implementation.
4. **UP permissions:** define the minimal LSP6 permission set for Governor/Timelock on the Council UP.
5. **Cross-chain policy:** decide whether governance power is chain-local or whether off-chain coordination / mirrored distributions are required across LUKSO, Base, and Ethereum.
6. **Signature UX:** confirm `delegateBySig` domain/version choices and any wallet compatibility quirks for LUKSO ecosystem tooling.

## Recommendation

Proceed with P11 as a LUKSO-native governance-token track.

The key conclusion from the interface review is simple:
- `LSP7VotesInitAbstract` is already `IERC5805` / `IVotes` compatible enough for OpenZeppelin `GovernorVotes`
- no wrapper layer is required just to make Governor work
- the real work is the concrete token implementation and the Universal Profile permission model

That means P11 is viable and should move into implementation after this proposal is accepted.
