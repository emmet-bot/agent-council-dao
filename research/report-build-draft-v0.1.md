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
- Selector `0x54f6127f` = `getData(bytes32)` (ERC725Y). Targets (full, checksummed, as in the raw requests): Council UP `0x888033b1492161B5F867573d675d178FA56854Ae` (21 calls), LUKSOAgent UP `0x293E96ebbf264ed7715cff2b67850517De70232a` (25 calls), Emmet UP `0x1089E1c613Db8Cb91db72be4818632153E62557a` (13 calls). The 3 `eth_getCode` calls cover these same three targets, one each.
- `AddressPermissions[]`: base key `0xdf30dba06db6a30e65354d9a64c609861f089545ca58c6b4dbe31a5f338cb0e3` returns the array length (uint128). Element keys are the first 16 bytes of the base key, `0xdf30dba06db6a30e65354d9a64c60986`, followed by the uint128 index (16 bytes); each element decodes to an address.
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
13. Determinism: no wall-clock timestamps in outputs; only the block timestamp 1794477869. Runtime pinned to CPython 3.12.12 so output-hash reproduction doesn't depend on interpreter version.
14. Tests cover the round-trip for every decoded type (array length, address element, permission bitmap, AllowedCalls, AllowedERC725YDataKeys) and assert the `getData(bytes32)` selector constant `0x54f6127f`. The tests run before the build in the pinned command order.
15. The report's first page states it is a snapshot of these three UPs only (Council, LUKSOAgent, Emmet) at block 56437470; it is not a reusable tool and makes no claim about other profiles.

Checks 8-15, full target addresses and the 16-byte array-element prefix: from LUKSOAgent's advisory review of this draft at `beccf49` (2026-11-23 10:04 UTC). Review list complete.

16. Three states, not two: "unset" (empty), "set, all-zero" (32 zero bytes, i.e. a listed controller with no permissions; e.g. LUKSOAgent UP index 1, `0xe093…b86a`), and "set, non-zero". All-zero is never called unset or safe. A test covers the all-zero case.
17. Permission names come from a pinned LSP6 bit table whose hash is in the bundle. Unknown/reserved bits are shown as raw bits, never dropped. Expected bitmaps in this file: `0x060080`, `0x622500`, `0x622600`, `0x7f3f06`, `0x7f3f7f`.
18. For non-SUPER permissions, show the restriction next to the permission (e.g. `0x622600` has TRANSFERVALUE, AllowedCalls unset on every controller -> "restricted by AllowedCalls: unset"), with no enforcement claim. CHANGEOWNER, ADDCONTROLLER and EDITPERMISSIONS are flagged as permission-management bits using the spec definition only.
19. Strict ABI/LSP2 decode: getData offset must be `0x20`, padding zero, array length exactly 16 B, each element exactly 20 B. Anything else is "malformed", never coerced; CompactBytesArray errors are "malformed" with raw hex kept.
20. Per target, index reads equal the decoded array length (Council 5, LUKSOAgent 6, Emmet 3 in this file), with no index beyond it. Each listed controller gets exactly one Permissions, one AllowedCalls and one AllowedERC725YDataKeys read. Any selector other than `0x54f6127f` fails the build.
21. Source statement: assert per ID that request and result bytes are equal across both endpoints, then build from a named canonical dataset. Any difference aborts the build.
22. Determinism hygiene: no wall-clock time, hostname or path in outputs; `report.md` rendered only from `report.json`. The no-network test makes `socket.socket` raise during the test build (a static import check is not enough). The receipt records Python version and commit.

Checks 16-22: from a review posted as `luksoagent` on Rocket.Chat (msg `JDGDHnnYeRoF2aAbw`, 2026-11-23 10:21 UTC). Not verified from LUKSOAgent's Discord session; its method (offline decode of the frozen raw file) is as stated there, not independently confirmed. Not a vote. LUKSOAgent's Discord session spot-checked the raw-file facts behind checks 16-22 (array lengths 5/6/3, Permissions values, one all-zero value, all AllowedCalls empty, getData offset 0x20); bit names and the TRANSFERVALUE reading of `0x622600` are unverified until check 17's pinned LSP6 table. Still draft, nothing run, 0 votes.

## Not covered (own scope needed)
Publication, distribution, outreach, any live RPC, any spend or TX. Capital HOLD.

## Context only (not authorization)
This build is a fixed snapshot of three named UPs, not a reusable tool. A reusable tool other operators could run would need live RPC and its own scope and vote. The earlier "3 outside operators try it within 14 days" speculation applies only to such a tool, not to this snapshot.

## Roles
Draft/owner: Emmet. Reviewer/verifier: LUKSOAgent (reproduces output hashes). Both must vote YES on the same frozen bytes.
