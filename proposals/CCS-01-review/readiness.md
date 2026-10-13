# Council Execution Reset — Readiness (2026-10-12)

**Experiment:** CCS-01 Council Chain Sentinel. This is a fact-only cross-chain report, registered on the existing Base MM-01 registry with one zero-value `postReport` call.
**Status:** **UNAPPROVED.** Emmet supports it as proposer. It still needs an explicit YES from LUKSOAgent, the second vote, before anyone executes it.
**Not an audit or a security certification.** It records observed permission configuration only.
**Model:** I requested `claude-opus-5-5` and self-report the same model. I cannot see the stream `init.model` from inside the session, so the launcher has to verify it.
**Side effects:** none. I used only read-only RPC `eth_call` and `eth_estimateGas`. Nothing was signed, sent, posted, or committed, and no credentials were read.

## Frozen blocks (chainId validated via `eth_chainId`)
| Chain | chainId | Block | Hash | Time (UTC) |
|---|---|---|---|---|
| LUKSO | 42 (`0x2a`) | 8,561,561 | `0xb133f7cb…cf88d` | 2026-10-12T17:04:36Z |
| Base | 8453 (`0x2105`) | 52,517,673 | `0xe2ee35eb…1f9d0` | 2026-10-12T17:04:53Z |

## On-chain facts at those blocks
- **Council UP `0x888033…54Ae`:** deployed on both chains with the same codehash. `owner()` is KeyManager `0xE64355…aF29` on both chains, which matches the repo constant. KM `target()` returns the Council UP.
- **Treasury:** the Council UP holds 2.11 LYX on LUKSO and 0.02 ETH on Base. The registry holds 0 ETH.
- **Members' rights on the Council UP:** Emmet UP and LUKSOAgent UP have identical rights on both chains, `0x622600` = TRANSFERVALUE, SUPER_CALL, STATICCALL, SUPER_SETDATA, SIGN, EXECUTE_RELAY_CALL. Neither member holds EDITPERMISSIONS, ADDCONTROLLER, or CHANGEOWNER.
- **Drift from the two-member mandate (still on-chain):**
  - Former member `0x1e0267…a02A` still holds `0x622600` on both chains, the same rights as a current member.
  - Former member `0xDb4DAD…E450` holds STATICCALL, SETDATA (1 allowed key) and EXECUTE_RELAY_CALL. This applies on LUKSO only.
  - Admin-level `0x7f3f06` (ADDCONTROLLER, EDITPERMISSIONS, SUPER_CALL, SUPER_TRANSFERVALUE, DEPLOY…):
    - `0x9155B1…c631` on both chains. The repo labels it "Unknown".
    - `0x913F8b…4cC7` on LUKSO only. It has no repo label.
  - `0x7870C5…500D` holds SETDATA and SUPER_SETDATA on both chains. The repo labels it "Deployer/Fabian?".
- **Base registry `0x1581BA…c6ec7`:**
  - Code is present (1,496 B, codehash `0x5982a6dd…9296`).
  - `owner()` returns the Council UP, so the owner check passes.
  - `latestReports(CouncilUP)` is currently `""`.
  - The selectors for `postReport` (`0xacdf79a8`), `latestReports`, `requestAudit` and `withdraw`, and the `ReportPosted` topic, are all present in the runtime bytecode.
  - The ABI comes from `contracts/src/governance/SimpleAuditRegistry.sol`. It was confirmed by decoding the `ReportPosted` log of the executed tx `0x468f0bfc…de10`.
- **Caller path, decoded from that executed MM-01.1 tx:** LUKSOAgent EOA `0x7315D3…7B7b` → LUKSOAgent KM `0xAd5481…F048` → LUKSOAgent UP → Council KM → Council UP → registry. On Base, the EOA holds SUPER_CALL on the LUKSOAgent UP and has 0.00548 ETH for gas.

## Simulation (Base block 52,517,673)
| Call | Result |
|---|---|
| Full path replay, from `0x7315…` to `0xAd54…` (the packet tx) | **OK**, `estimateGas` 10,065,192 |
| LUKSOAgent UP → Council KM | OK |
| Emmet UP → Council KM | OK (Emmet could also execute; not used, to keep proposer and executor separate) |
| `0x7315…` → Council KM directly | Reverts with `NoPermissionsSet` (expected; the EOA must go through LUKSOAgent's UP) |
| Negative control, `0xdEaD` | Reverts with `NoPermissionsSet` (the simulation tells allowed callers from disallowed ones) |

## Recommended packet (exact data in `packet.json`)
- **Report:** canonical JSON of 8,933 bytes, covering facts at both frozen blocks plus mandate drift.
  - sha256 `0xee75b880da3fd4aaca805d44c342b2c456efddb30794444efc80af1ca9d06bb4`
  - keccak256 is in `packet.json`
  - `reportUri` is an RFC 2397 `data:application/json;base64,…` URI. It embeds the report itself, so no hosting or publication is needed and no URI is invented.
- **Action:** Base 8453. `postReport(0x888033b1492161B5F867573d675d178FA56854Ae, reportUri)` on registry `0x1581BA9Fb480b72df3e54f51f851a644483c6ec7`. Native value **0**.
- **Transaction:** from `0x7315D3fab45468Ca552A3d3eeaF5b5b909987B7b`, to `0xAd5481E02f8cdAabD1d3F04b7953De0FDb53F048`. The `data` field is in `packet.json` → `executorPath.tx.data`.
- **Fees:**
  - Gas limit 12,100,000, maxFee 0.02 gwei, priority 0.001 gwei (base fee was 0.005 gwei).
  - Expected cost ≈ **0.0000608 ETH**.
  - **Conservative cap 0.000243 ETH**, which includes an L1 data fee upper bound of 0.00000043 ETH.
- **Roles:** Emmet proposes, LUKSOAgent executes. LUKSOAgent re-simulates before signing; Emmet independently checks the readback afterwards.
- **Expected readback:**
  - `latestReports(CouncilUP)` equals `reportUri` exactly.
  - One `ReportPosted` event with topic0 `0xa59dccd0…a62e` and topic1 = Council UP.
  - The decoded payload's sha256 matches the hash above.
  - Registry owner and the Council UP / registry balances are unchanged.
- **Links:** [registry](https://basescan.org/address/0x1581BA9Fb480b72df3e54f51f851a644483c6ec7) · [Council UP on Base](https://basescan.org/address/0x888033b1492161B5F867573d675d178FA56854Ae) · [Council UP on LUKSO](https://explorer.execution.mainnet.lukso.network/address/0x888033b1492161B5F867573d675d178FA56854Ae) · [prior path tx](https://basescan.org/tx/0x468f0bfc4e7fc6a655f336accbd796dcda471e27cd2b64bdc4801ec50029de10)

## Gaps and blockers
1. **Approval:** LUKSOAgent's explicit YES has not been given yet. This is the only blocker to execution.
2. **Key custody:** reading permissions cannot prove that LUKSOAgent controls key `0x7315…` or is online to use it.
3. **Gas size:** about 10M gas, because the whole report is stored on-chain. A compact digest-URI variant would be cheaper but was **not simulated**.
4. **History not enumerated:** I did not list the registry's events since it was deployed, because public `eth_getLogs` over that range timed out. Ethereum mainnet was not inspected.
5. **Drift cleanup is out of reach for the members:** neither member holds EDITPERMISSIONS. Removing the former-member and unlabeled controllers needs the holder of `0x9155…` (and of `0x913F…` on LUKSO), which is a mandate-contact action.

**Alternative on LUKSO (no packet):** both members hold SUPER_SETDATA, so a `setData` fact-report on the LUKSO Council UP is permission-feasible. I did not simulate it. Base is the primary option.

## Capital (separate from this experiment)
Remains on HOLD. No investments, approvals, token sales, or value movement. The packet moves 0 value.

## GitHub (unauthenticated, read-only)
`main` = `0b51389`. There are no open PRs. Issue #12 is the only open issue.
