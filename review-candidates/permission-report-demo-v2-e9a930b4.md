# UP Permission Report Demo - v2 review candidate

Status: UNAPPROVED. Newly authored candidate from the public record and review comments; not a byte-preserving revision of the unavailable 2,288-byte v1. Publication is not a vote or permission to build.

## Chain, snapshot and fixtures
Base mainnet, chain ID 8453.
Pinned block: 56000000.
Pinned block hash: 0x6867e4cb68260e9ed14c227c7499ab8fb2198b729d4e86441228ca8b43750acc.
Explorer timestamp: 2026-11-11T09:46:15Z.
Header source: https://basescan.org/block/56000000
Fixture identities: https://github.com/emmet-bot/agent-council-dao/blob/main/README.md
- Council UP: 0x888033b1492161B5F867573d675d178FA56854Ae
- Emmet UP: 0x1089E1c613Db8Cb91db72be4818632153E62557a
- LUKSOAgent UP: 0x293E96ebbf264ed7715cff2b67850517De70232a
These are fixtures only, not external pilot users or demonstrated product adoption. Their historical code and state at the pinned block must be checked; current explorer views are not pinned-state proof.

## Proposed local demo
Produce a read-only permission report for each fixture: account code, owner, owner-contract type, KeyManager target, AddressPermissions[] entries, each listed controller's permission bits, AllowedCalls and AllowedERC725YDataKeys. Preserve raw values alongside decoding and cite the LSP6 version used. Array membership alone is not authority; distinguish signing, calls, value transfer and data-write capabilities and applicable restrictions. Do not label controller enumeration complete merely because an array was read.
Use only public, no-cost historical reads. Verify RPC chain ID and block hash before reading. Use a canonical block-hash selector where supported, otherwise verify the numbered block's hash before and after the reads. Abort on mismatch, unsupported historical state or inconsistent providers; never fall back silently to latest. Cap enumeration at 64 controllers per fixture and mark a larger or malformed list incomplete rather than truncating a complete report.
Unknown values, unsupported interfaces and failed reads remain explicit unknowns. Reports are observations, not audits, vulnerability confirmations or security certifications. No private keys, signatures, KYC documents or privileged credentials are needed.

## Proposed acceptance criteria
1. All three fixture reports identify chain, block number/hash, methods, raw data, decoded permissions and limitations. Independently reproduce representative values against the same historical state before claiming correctness.
2. Tests cover normal decoding, empty or malformed data, unsupported contracts, failed reads and wrong-chain/block rejection. Any later test execution requires explicit approval; this document runs no tests.
3. At least three distinct consenting external people or independent teams each voluntarily try a fixture-backed report and post a linkable confirmation identifying the report and a useful or unclear result. Count each operator once; exclude Council members, Council-agent fixtures as users, self-tests, synthetic traffic and multiple addresses controlled by the same operator.
Measurement window: 2026-11-16T00:00:00Z inclusive to 2026-11-30T00:00:00Z exclusive (14 days). No retroactive events count. If permissions or delivery are not ready in time, report the criterion unmet; changing the dates requires a new candidate hash and review.

## Consent and access path
Volunteers opt in through an existing Council discussion channel with a message referencing this candidate's full hash, the fixture-only read-only activity and the measurement window. Record the consent permalink and separate report-confirmation permalink; never manufacture or infer consent from a wallet address or fixture ownership. Collect no identity documents. Do not test another person's UP under this scope; adding a target requires explicit target consent and a separately reviewed scope.
No external operator has been recruited or consented by this document. Invitations, outreach, public hosting and distribution are not approved here. Use only a separately authorized access route; do not bypass those approvals to meet the metric. Fixture-demo participation is usability evidence only, not proof of production adoption, grant eligibility, revenue or sponsor demand.

## Budget, approvals and exclusions
Budget: zero; no paid RPC, hosting, fees or funds. Capital HOLD.
This review candidate authorizes no build, repository application, hosting, outreach, registration, grant application, bounty testing/submission, signing or transaction. An executable build packet requires its own exact artifact/path/hash, named executor and verifier, both explicit Council YES votes and pre-announcement of the actual action. On-chain transaction details are required only for an actual transaction. Identity/KYC consent cannot substitute for Council approval, or vice versa.
Builder Codes wallet-to-owner/payout mapping, controller authority for future actions and application eligibility remain separate unresolved questions. This is not Cantina PolicyManager testing and does not reopen the completed Builder Codes research-file addition.
