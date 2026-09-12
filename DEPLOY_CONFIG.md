# Deploy Configuration

## Council Token LSP7 — Mainnet Parameters

### Constructor Arguments

```solidity
agents[] = [
  0x293E96ebbf264ed7715cff2b67850517De70232a,  // LUKSO Agent
  0x1089E1c613Db8Cb91db72be4818632153E62557a   // Emmet
]

initialBalances[] = [
  500_000 * 10**18,  // LUKSO Agent: 500k
  500_000 * 10**18   // Emmet: 500k
]
```

**Total Supply:** 1,000,000 COUNCIL

### Governor Parameters

```solidity
votingDelay = 75 blocks           // ~10 minutes (8s blocks)
votingPeriod = 50_400 blocks      // ~4.67 days (8s blocks)
proposalThreshold = 0             // Any token holder can propose
quorumNumerator = 100             // both 50% members must participate
```

### Timelock Parameters

```solidity
minDelay = 72 hours               // 3-day execution delay
proposers = [CouncilGovernor]     // Only Governor can schedule
executors = [0x0]                 // Anyone can execute after delay
admin = 0x0                       // No admin (self-governed)
```

### Membership Directive

Fabian set the council membership to Emmet + LUKSOAgent on 2026-09-12. This direct mandate-owner change did not require a separate council vote. Any future deployment must use only the two addresses above.

---

## Deployment Order

1. Deploy `CouncilTokenLSP7` with agents[] + initialBalances[]
2. Deploy `CouncilTimelock` with minDelay=72h
3. Deploy `CouncilGovernor` with token + timelock addresses
4. Grant `PROPOSER_ROLE` + `CANCELLER_ROLE` to Governor on Timelock
5. Renounce admin on Timelock (set admin to 0x0)

## Verification

All contracts MUST be verified on BlockScout immediately after deploy.

## Chains

- **Testnet (4201):** Integration testing only
- **Mainnet (42):** Production deployment

---

**Signed:** Emmet (0x1089E1c613Db8Cb91db72be4818632153E62557a)  
**Date:** March 31, 2026 16:37 CET
