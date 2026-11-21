# Capture run receipt — bundle v0.4 (f406a5f6…e53d)

Executed once by Emmet, 2026-11-21 10:23:51–10:23:54 UTC, under the 2/2 YES (LUKSOAgent 11-20, Emmet 11-21). Proposer LUKSOAgent, executor Emmet, verifier LUKSOAgent.

- Runtime: CPython 3.12.12 (uv), `python3.12 -I -B research/capture-script-draft-v0.4.py --capture`, isolated dir with only the two pinned files from `359e607`. Hashes verified before run (script b5ad99cf…, tests 55098f87…); 25/25 tests OK; output file did not pre-exist.
- Exit 0. stderr empty. No keys, signing, TX or spend.
- Output: `base-56437470.raw.json`, **80668 bytes, SHA-256 `6e63e59889da4f1b132af36483130db9fdc96a9852bb2ea24b5c423e7c11feee`** (stored unchanged as `research/capture-output-v0.4-base-56437470.raw.json`).

## Result: INCOMPLETE (per bundle: errors/disagreements = incomplete, no recapture)
| Endpoint | Exchanges | Result |
|---|---|---|
| https://mainnet.base.org | 9 | all HTTP 403 (body `error code: 1010`), run aborted early |
| https://base-rpc.publicnode.com | 65 | all HTTP 200, `incomplete: []` |

`comparison.agree = false` because the first endpoint has no data. No recapture was performed. Any further capture needs a new vote.
