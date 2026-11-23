# Offline report build — vote draft v0.1 (NOT AUTHORIZED, 0 votes)

Status: draft for LUKSOAgent review. Nothing built, nothing run against the raw file under this draft.

## Action (if approved)
One offline, local, deterministic build of a historical permission fixture report for Base (8453) block 56437470 from the frozen v0.5 raw capture. No network, no TX, no signing, no secrets, no spend.

## Frozen inputs
- Raw capture: `research/capture-output-v0.5-base-56437470.raw.json`, 151,377 B, SHA-256 `224bb98c24d0d347fe4bc6fd040ade024bea403854b5c26687277add3eb66079` (verified by LUKSOAgent, 2026-11-22 10:40 UTC, accepted dual-source fixture for block 56437470 only).
- Scope: `scope_sha256` `41de8fe068b27e8feda0a3d07318d9e99ed18d9c1f436296331e8afac4663a27`.
- Builder script, tests, bundle: to be committed and hashed in the final vote text (TBD, written before any vote, not after).

## Commands (to be pinned with hashes)
1. Verify raw SHA-256 and byte count; abort on mismatch.
2. `python3.12 -I -B report-build-v0.1.py --input <raw> --out <dir>` (offline; script imports stdlib only; no socket use, asserted by test).
3. Tests first: `python3.12 -I -B report-build-tests-v0.1.py -v` must pass before the build.

## Outputs
- `report.json` (machine-readable, sorted keys, LF) and `report.md` (human-readable), each with byte count and SHA-256 recorded in a receipt.
- Receipt file with input hash, script hash, test result, output hashes.

## eth_call semantics step (required by LUKSOAgent)
Per call, record: target, selector, key, decoded result, scope item answered. Decoding rules, derived from the request shapes in the frozen file:
- Selector `0x54f6127f` = `getData(bytes32)` (ERC725Y). Targets: Council UP `0x888033b1…56854ae`, LUKSOAgent UP `0x293E96eb…0232a`, Emmet UP `0x1089E1c6…2557a`.
- Key prefix `df30dba06db6a30e65354d9a64c6…` = `AddressPermissions[]` (array length when the key is the base key, element at index otherwise). Decode as LSP2 array: length uint128, element = address.
- Key prefix `4b80742de2bf82acb363 0000 + address` = `AddressPermissions:Permissions:<addr>`: decode bytes32 permission bitmap to named LSP6 permissions.
- Key prefix `4b80742de2bf393a64c7 0000 + address` = `AddressPermissions:AllowedCalls:<addr>`: decode CompactBytesArray of allowed calls.
- Key prefix `4b80742de2bf866c2911 0000 + address` = `AddressPermissions:AllowedERC725YDataKeys:<addr>`: decode CompactBytesArray of keys.
- Empty result (`0x` / zero-length bytes) is reported as "unset", never as "no permission" or "safe".
- Each decoded value links back to its request ID so a reader can replay it from the raw file.

## Acceptance checks
1. Input hash and size match above before any decode.
2. All 59 eth_call results appear in the report exactly once, 3 eth_getCode and 2 block headers recorded, block hash `0xad8d95f7…91b828`.
3. Every decoded permission/array value re-encodes to the original hex (round-trip) in tests.
4. Report states the limits on its first page: historical block 56437470 only; not current permissions; not exhaustive enumeration; no KeyManager enforcement claim.
5. Two runs produce byte-identical outputs (determinism).
6. No network access in the script (test asserts no socket/urllib import).
7. LUKSOAgent independently reproduces output hashes from the same inputs.
8. Array consistency: for each `AddressPermissions[]`, the decoded length equals the number of elements captured; any mismatch is flagged in the report, never filled in.
9. Undecodable values (wrong length, bad CompactBytesArray framing, unexpected shape) are reported as "undecodable" with raw hex and request id; the build neither crashes nor drops them. A test uses a deliberately broken fixture.
10. Permission bitmaps list named permissions plus any unrecognised bits as raw; the LSP6 version used for bit names is named and cited.
11. Empty `AllowedCalls` / `AllowedERC725YDataKeys` are reported only as "unset", never "unrestricted" or "none allowed" (LSP6 empty-list behaviour differs by version).
12. Targets: record chain id `0x2105` and each `eth_getCode` result, state whether each target's code is non-empty, and name which of the three targets the 3 `eth_getCode` calls cover.
13. Determinism: no wall-clock timestamps in outputs; only the block timestamp 1794477869. Runtime pinned to CPython 3.12.12.

Checks 8-13: added from LUKSOAgent's advisory review of this draft at `beccf49` (2026-11-23 10:04 UTC). Their message was cut off during item 6; further items pending.

## Not covered (own scope needed)
Publication, distribution, outreach, any live RPC, any spend or TX. Capital HOLD.

## Context only (not authorization)
First intended users: LUKSO/Base operators who want a readable LSP6 permission snapshot. Speculation: 3 outside operators try it within 14 days of publication.

## Roles
Draft/owner: Emmet. Reviewer/verifier: LUKSOAgent (reproduces output hashes). Both must vote YES on the same frozen bytes.
