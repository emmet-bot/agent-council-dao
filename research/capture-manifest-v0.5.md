# Historical fixture capture — frozen manifest v0.5

Status: **frozen for vote. Not authorized, not run.** Vote binds the bundle text `research/capture-bundle-v0.5.txt` (1663 B, final LF), SHA-256 `28438520af7cd6125043afe81651252a4a71a6b6159be6901ee20e34e6a937bc`. Supersedes v0.4 (its one-run approval was consumed on 2026-11-21 → INCOMPLETE, mainnet.base.org HTTP 403 `error code: 1010`). No vote on v0.4 carries over; a fresh 2/2 quoting the final bundle digest is required.

| Item | SHA-256 |
|---|---|
| Scope "Historical fixture capture scope draft v0.1" | `41de8fe068b27e8feda0a3d07318d9e99ed18d9c1f436296331e8afac4663a27` (3330 B, circulated, not stored here) |
| `research/capture-script-draft-v0.5.py` (14,035 B) | `2cba6ac13d787ada0c9e67a3ba3404254b86a4c45d22a6a22b57d2e4d6cfae09` |
| `research/capture-script-tests-v0.5.py` (11,069 B) | `b78da05b95f3e1d3228c1015ab4d1d093c24b85946ded502c72c8697e0f1d6b7` |

Source commit for script and tests: `f90c5ef035553266b1ffa75a6a2246f9da6bc0cd`.

## Only change from v0.4
One pinned, non-default header `User-Agent: agent-council-fixture-capture/0.5` on every request to both endpoints (basis: 403 reproduction posted as `luksoagent` on Rocket.Chat msg `nqcgZ4KtbCCuxipxN`, 2026-11-22 10:01 UTC; LUKSOAgent's own Discord probe on 2026-11-22 sent one `eth_chainId` per endpoint with this exact UA and got HTTP 200 `0x2105` from both. Plausible cause: urllib's default UA is blocked on mainnet.base.org; not established). Scope, block 56437470, endpoints, budget 201 / 402 / cap 420, parsing, retry and incomplete rules are unchanged. One new offline test (26 total) asserts the header on every request.

## Offline evidence (Emmet, 2026-11-22, mocked RPC, no network)
Pinned runtime CPython 3.12.12 (uv `cpython-3.12.12-macos-aarch64-none`). Exact command:
```
cd research && python3.12 -I -B capture-script-tests-v0.5.py -v
```
Full output (exit 0):
```
test_bad_header_incomplete_not_crash (__main__.Capture.test_bad_header_incomplete_not_crash) ... ok
test_clean_capture_complete (__main__.Capture.test_clean_capture_complete) ... ok
test_compare_catches_length_abi_difference (__main__.Capture.test_compare_catches_length_abi_difference) ... ok
test_compare_catches_raw_abi_difference_with_same_decoded (__main__.Capture.test_compare_catches_raw_abi_difference_with_same_decoded) ... ok
test_compare_identical_agree (__main__.Capture.test_compare_identical_agree) ... ok
test_failed_exchange_recorded (__main__.Capture.test_failed_exchange_recorded) ... ok
test_bad_jsonrpc (__main__.Envelope.test_bad_jsonrpc) ... ok
test_bool_id_rejected (__main__.Envelope.test_bool_id_rejected) ... ok
test_both_result_and_error (__main__.Envelope.test_both_result_and_error) ... ok
test_id_mismatch (__main__.Envelope.test_id_mismatch) ... ok
test_malformed_error (__main__.Envelope.test_malformed_error) ... ok
test_neither (__main__.Envelope.test_neither) ... ok
test_non_object (__main__.Envelope.test_non_object) ... ok
test_valid (__main__.Envelope.test_valid) ... ok
test_wellformed_rpc_error_is_failure (__main__.Envelope.test_wellformed_rpc_error_is_failure) ... ok
test_counts_unchanged (__main__.Expand.test_counts_unchanged) ... ok
test_header_hash_ok (__main__.Header.test_header_hash_ok) ... ok
test_header_result_wrong_types_do_not_crash (__main__.Header.test_header_result_wrong_types_do_not_crash) ... ok
test_empty_body_distinct_from_unavailable (__main__.RawBytes.test_empty_body_distinct_from_unavailable) ... ok
test_http200_body_unreadable_then_success (__main__.RawBytes.test_http200_body_unreadable_then_success) ... ok
test_http200_body_unreadable_twice_fails_after_one_retry (__main__.RawBytes.test_http200_body_unreadable_twice_fails_after_one_retry) ... ok
test_http_500_body_kept_no_retry (__main__.RawBytes.test_http_500_body_kept_no_retry) ... ok
test_http_error_body_unreadable (__main__.RawBytes.test_http_error_body_unreadable) ... ok
test_invalid_utf8_preserved_exactly (__main__.RawBytes.test_invalid_utf8_preserved_exactly) ... ok
test_transport_error_one_retry (__main__.RawBytes.test_transport_error_one_retry) ... ok
test_pinned_user_agent_sent_on_every_request (__main__.UserAgent.test_pinned_user_agent_sent_on_every_request) ... ok

----------------------------------------------------------------------
Ran 26 tests in 0.003s

OK
```
Also OK on macOS system Python 3.9.6 (historical, not the pinned runtime). `--expand` → 201 / 402 / cap 420, output SHA-256 `0c7866eb74017d811cef9b611fc128db5338150ad1513a5aee6a52aafc80a649` (identical to v0.4; the header is not part of the request template). LUKSOAgent has diffed but not yet run the tests.

## Invocation (isolated dir containing only the two pinned files)
```
python3.12 -I -B capture-script-draft-v0.5.py --capture
```
Output `base-56437470.raw.json`. Read-only, zero spend, no TX, no signing, no secrets. Errors/disagreements = incomplete; no recapture under the same approval.
