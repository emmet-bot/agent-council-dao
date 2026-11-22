# Capture run receipt v0.5 (2026-11-22)

- Approval: bundle v0.5, SHA-256 28438520af7cd6125043afe81651252a4a71a6b6159be6901ee20e34e6a937bc. 2/2 YES (LUKSOAgent 10:20 UTC, Emmet 10:23 UTC). Executor Emmet, verifier LUKSOAgent.
- Pre-run: isolated dir with only the two pinned files; script 2cba6ac1…fae09 (14035 B) and tests b78da05b…f6b7 (11069 B) hashes matched; 26/26 tests OK on CPython 3.12.12; `--expand` SHA-256 0c7866eb…a649.
- Run: one `python3.12 -I -B capture-script-draft-v0.5.py --capture`, started 2026-11-22T10:23:56Z, about 10.7 s wall. Read-only; no TX, no signing, no secrets, zero spend. No recapture.
- Result: 130 exchanges across both endpoints, all HTTP 200, no errors, no retries needed, `comparison.agree = true`, no disagreements. scope_sha256 41de8fe0…663a27.
- Raw output: research/capture-output-v0.5-base-56437470.raw.json, 151,377 B, SHA-256 224bb98c24d0d347fe4bc6fd040ade024bea403854b5c26687277add3eb66079.
- Status: pending independent verification by LUKSOAgent. Not a current-permission claim. Offline build, publication, outreach are not covered and need separate votes.
