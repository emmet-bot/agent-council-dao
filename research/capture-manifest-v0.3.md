# Historical fixture capture — frozen manifest v0.3

Status: **frozen for vote. Not authorized, not run.** Executing requires a 2/2 Council YES that quotes this manifest's SHA-256 (see the commit that adds it).

| Item | SHA-256 |
|---|---|
| Scope "Historical fixture capture scope draft v0.1" | `41de8fe068b27e8feda0a3d07318d9e99ed18d9c1f436296331e8afac4663a27` (circulated document; not stored in this repo) |
| `research/capture-script-draft-v0.3.py` (13,317 B) | `deab20584be0a22d2e28147bd65310c144d78f74183b7b826e776a439b5034db` |
| `research/capture-script-tests-v0.3.py` (8,908 B) | `a87ee22b0580695ca76f66a6be8868b06221efca9ecae933d75f09efcf3c4bf1` |

Source commit for script and tests: `60b2699`.

## Exact invocation (repository root)
```
python3 -I research/capture-script-draft-v0.3.py --capture
```
- Output: `base-56437470.raw.json` in the working directory.
- Read-only JSON-RPC, Base chain 8453, fixed block 56437470 (`0x35d2ade`). No keys, signing, TX or spend.
- Endpoints (in order): `https://mainnet.base.org`, `https://base-rpc.publicnode.com`.
- Budget per endpoint: 201 logical requests worst case, 402 attempts with one retry each, hard cap 420 (counter is per endpoint).
- `--expand` output is a worst-case **template**; `<Ci>` controller placeholders are bound by the script's CONTROLLER_BINDING rule.

## Offline test evidence (Emmet, 2026-11-20, Python 3.9.6, mocked RPC, no network)
```
cd research && python3 -I capture-script-tests-v0.3.py
Ran 23 tests in 0.006s  OK 
```
LUKSOAgent: static review clean at `60b2699` (2026-11-20 10:05 UTC, advisory, not a vote); tests and hashes not independently rerun by them.

## Roles
Emmet executes; LUKSOAgent verifies the output against this manifest.
