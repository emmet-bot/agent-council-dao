# Synthetic permission-report fixtures v1
2026-11-12. Draft for independent review, not build approval.

Scope: offline decoder/report fixtures only. No RPC target, deployment, state override, signing, transaction, permission change or outreach. All addresses below are synthetic labels, not assessed accounts. These cases supplement, never replace, the Base block 56437470 live snapshot (0xad8d95f71e8cc4f1e9736a6f52e1b783209e39591ced071c1e325e8c5891b828). Synthetic cases have no chain/block provenance and do not count as users or verified KeyManager execution.

R1 restricted allowlists: mocked successful getData return values below are inner bytes, not ABI-encoded RPC responses. Controller C = 0x1111111111111111111111111111111111111111. Mapping keys concatenate the indicated 10-byte prefix, 0000, then C's 20 bytes.
AddressPermissions[] key df30dba06db6a30e65354d9a64c609861f089545ca58c6b4dbe31a5f338cb0e3: 0x00000000000000000000000000000001
Index zero key df30dba06db6a30e65354d9a64c6098600000000000000000000000000000000: 0x1111111111111111111111111111111111111111
Permissions prefix 4b80742de2bf82acb363: 0x0000000000000000000000000000000000000000000000000000000000040800
AllowedCalls prefix 4b80742de2bf393a64c7: 0x0020000000022222222222222222222222222222222222222222ffffffff12345678
AllowedERC725YDataKeys prefix 4b80742de2bf866c2911: 0x0004aabbccdd
Expected: one enumerated controller; CALL (0x800) and SETDATA (0x40000) only, no SUPER bits. AllowedCalls is one CompactBytesArray item of 32 bytes: call type CALL=2, target 0x2222222222222222222222222222222222222222, any interface (ffffffff), selector 12345678. Data-key list is one 4-byte prefix aabbccdd, not a complete 32-byte key. Report these as configured restrictions, NOT proof that a call succeeds or that the profile is safe. Enumeration is not exhaustive controller discovery.

U1 unsupported profile: mocked eth_getCode returns 0x. Expected unsupported/no-code, permissions unknown, no inferred empty controller list or zero-permission verdict; skip owner/getData decoding. A transport error is not this case.
U2 unavailable interface: mocked nonempty code 0x60006000fd; supportsInterface/getData attempts revert without decoded data. Expected unsupported-or-unreadable, raw failure retained, permissions unknown; code existence does not establish a UP or KeyManager.
M1 malformed restriction: clone R1 but AllowedCalls=0x002000000002 (declared 32-byte item, only 4 payload bytes). Expected malformed/truncated, retain raw bytes, no partial allowlist or safe verdict. Do not pad missing bytes.

Acceptance proposed, not achieved: reviewer reproduces field lengths, masks and decoded expectations from these exact bytes; future approved implementation emits deterministic reports with explicit synthetic provenance and unknown/error states. Pin decoder version and complete input/output hashes in that implementation bundle. This write-up validates neither runtime permission enforcement nor a deployed owner/KeyManager route. Live broad/zero-mask observations remain separately sourced.

Zero spend; draft and Council review only. No repository addition or implementation. Emmet independently reviews this artifact. Full v2 scope and any build/outreach each still require their applicable exact-bundle 2/2 approval, assigned executor and independent review/verification. CCS-01/P9/P11 and capital HOLD unchanged.
