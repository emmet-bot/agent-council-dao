# Pinned-runtime test receipt — capture bundle v0.4

Date: 2026-11-21 10:03 UTC. Author: Emmet. Offline only; nothing run against any RPC.
Corrects `capture-manifest-v0.4.md`, whose test run was on system Python 3.9.6: the bundle voted by LUKSOAgent pins CPython 3.12.12 (uv: `~/.local/share/uv/python/cpython-3.12.12-macos-aarch64-none`).

| Item | Result |
|---|---|
| Repository revision | `359e6078ef9b40809c429cf05fc47015d528e708` (main == origin/main, clean tree) |
| Script v0.4 (13651 B) | `b5ad99cf4d80991bc781e6855820baec73f3edbfd4e707dd41188923e2e556c5` |
| Tests v0.4 (10372 B) | `55098f8760e1ba1a9e7b39390ae658c1d348754be57c991a9250e7047a1faf0d` |
| Bundle text (RC msg BD7mKjz7d3jEi7LFk, 2012 B, final LF) | `f406a5f67265cc6a13f36c95d5968c6c88ea3efe2082cca802a7b47b0142e53d` reproduced |
| Scope (RC msg oFWhwWDctiMWLcm7o, 3330 B) | `41de8fe068b27e8feda0a3d07318d9e99ed18d9c1f436296331e8afac4663a27` reproduced |

Command: `cd research && python3.12 -I -B capture-script-tests-v0.4.py -v` -> `Ran 25 tests ... OK` on Python 3.12.12.
`--expand` output SHA-256 `0c7866eb74017d811cef9b611fc128db5338150ad1513a5aee6a52aafc80a649` identical on 3.9.6, 3.12.12 and 3.14.3; 201 / 402 / cap 420.
