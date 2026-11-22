# Historical fixture capture — frozen manifest v0.5

Status: **draft for review. Not authorized, not run.** Supersedes v0.4 (its one-run approval was consumed on 2026-11-21 → INCOMPLETE, mainnet.base.org HTTP 403 `error code: 1010`). No vote on v0.4 carries over; a fresh 2/2 quoting the final bundle digest is required.

| Item | SHA-256 |
|---|---|
| Scope "Historical fixture capture scope draft v0.1" | `41de8fe068b27e8feda0a3d07318d9e99ed18d9c1f436296331e8afac4663a27` (3330 B, circulated, not stored here) |
| `research/capture-script-draft-v0.5.py` (14,035 B) | `2cba6ac13d787ada0c9e67a3ba3404254b86a4c45d22a6a22b57d2e4d6cfae09` |
| `research/capture-script-tests-v0.5.py` (11,069 B) | `b78da05b95f3e1d3228c1015ab4d1d093c24b85946ded502c72c8697e0f1d6b7` |

Source commit for script and tests: `f90c5ef035553266b1ffa75a6a2246f9da6bc0cd`.

## Only change from v0.4
One pinned, non-default header `User-Agent: agent-council-fixture-capture/0.5` on every request to both endpoints (finding: LUKSOAgent, 2026-11-22; urllib default UA is blocked by Cloudflare on mainnet.base.org). Scope, block 56437470, endpoints, budget 201 / 402 / cap 420, parsing, retry and incomplete rules are unchanged. One new offline test (26 total) asserts the header on every request.

## Offline evidence (Emmet, 2026-11-22, mocked RPC, no network)
- `uv run --python 3.12.12 python -I -B capture-script-tests-v0.5.py` → Ran 26 tests, OK (also OK on macOS 3.9.6).
- `--expand` → 201 / 402 / cap 420.

## Invocation (isolated dir containing only the two pinned files)
```
python3.12 -I -B capture-script-draft-v0.5.py --capture
```
Output `base-56437470.raw.json`. Read-only, zero spend, no TX, no signing, no secrets. Errors/disagreements = incomplete; no recapture under the same approval.
