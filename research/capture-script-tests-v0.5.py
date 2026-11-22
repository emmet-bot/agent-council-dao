#!/usr/bin/env python3
"""Offline regression tests for capture-script-draft-v0.5.py. Mocked RPC only, no network.
Run: python3 -I capture-script-tests-v0.5.py"""
import importlib.util, io, json, os, sys, unittest, urllib.error
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cap", os.path.join(HERE, "capture-script-draft-v0.5.py"))
cap = importlib.util.module_from_spec(spec); spec.loader.exec_module(cap)


class Resp:
    def __init__(self, body, status=200): self.body, self.status = body, status
    def read(self): return self.body
    def __enter__(self): return self
    def __exit__(self, *a): return False


def abi(inner_hex):
    b = bytes.fromhex(inner_hex)
    return "0x" + (32).to_bytes(32, "big").hex() + len(b).to_bytes(32, "big").hex() + b.hex().ljust(((len(b) + 31) // 32) * 64, "0")


def state(): return {"n": 0, "rid": 0, "exchanges": []}


def run_rpc(body, status=200):
    with mock.patch.object(cap.urllib.request, "urlopen", lambda *a, **k: Resp(body, status)):
        st = state(); r = cap.rpc("http://x", st, "eth_chainId", [])
    return r, st["exchanges"][0]


class Envelope(unittest.TestCase):
    def test_valid(self):
        r, ex = run_rpc(b'{"jsonrpc":"2.0","id":1,"result":"0x2105"}')
        self.assertEqual(r["result"], "0x2105"); self.assertIsNone(ex["failure"])
    def test_id_mismatch(self):
        r, ex = run_rpc(b'{"jsonrpc":"2.0","id":99,"result":"0x2105"}')
        self.assertIsNone(r); self.assertEqual(ex["failure"], "id mismatch")
    def test_both_result_and_error(self):
        r, ex = run_rpc(b'{"jsonrpc":"2.0","id":1,"result":"0x1","error":{"code":-1,"message":"m"}}')
        self.assertIsNone(r); self.assertIn("exactly one", ex["failure"])
    def test_neither(self):
        r, ex = run_rpc(b'{"jsonrpc":"2.0","id":1}')
        self.assertIsNone(r); self.assertIn("exactly one", ex["failure"])
    def test_non_object(self):
        r, ex = run_rpc(b'[1,2]')
        self.assertIsNone(r); self.assertEqual(ex["failure"], "envelope not an object")
    def test_bool_id_rejected(self):
        r, ex = run_rpc(b'{"jsonrpc":"2.0","id":true,"result":"0x1"}')
        self.assertIsNone(r); self.assertEqual(ex["failure"], "id mismatch")
    def test_bad_jsonrpc(self):
        r, ex = run_rpc(b'{"jsonrpc":"1.0","id":1,"result":"0x1"}')
        self.assertIsNone(r); self.assertEqual(ex["failure"], "jsonrpc != 2.0")
    def test_malformed_error(self):
        r, ex = run_rpc(b'{"jsonrpc":"2.0","id":1,"error":"boom"}')
        self.assertIsNone(r); self.assertEqual(ex["failure"], "malformed error object")
    def test_wellformed_rpc_error_is_failure(self):
        r, ex = run_rpc(b'{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"x"}}')
        self.assertIsNone(r); self.assertEqual(ex["failure"], "rpc error -32000")


class RawBytes(unittest.TestCase):
    def test_invalid_utf8_preserved_exactly(self):
        raw = b'\xff\xfe{"jsonrpc"'
        r, ex = run_rpc(raw)
        a = ex["attempts"][0]
        self.assertEqual(bytes.fromhex(a["response_hex"]), raw)  # no U+FFFD replacement
        self.assertTrue(a["body_available"]); self.assertIn("not valid UTF-8", ex["failure"])
    def test_empty_body_distinct_from_unavailable(self):
        r, ex = run_rpc(b"")
        a = ex["attempts"][0]
        self.assertTrue(a["body_available"]); self.assertEqual(a["response_hex"], ""); self.assertIn("empty body", ex["failure"])
    def test_http_500_body_kept_no_retry(self):
        err = urllib.error.HTTPError("http://x", 500, "ISE", {}, io.BytesIO(b"oops\xff"))
        with mock.patch.object(cap.urllib.request, "urlopen", side_effect=err):
            st = state(); r = cap.rpc("http://x", st, "eth_chainId", [])
        ex = st["exchanges"][0]
        self.assertIsNone(r); self.assertEqual(st["n"], 1); self.assertEqual(len(ex["attempts"]), 1)
        self.assertEqual(bytes.fromhex(ex["attempts"][0]["response_hex"]), b"oops\xff")
        self.assertEqual(ex["failure"], "http status 500")
    def test_http_error_body_unreadable(self):
        class Bad(io.BytesIO):
            def read(self, *a): raise OSError("reset")
        err = urllib.error.HTTPError("http://x", 502, "BG", {}, Bad())
        with mock.patch.object(cap.urllib.request, "urlopen", side_effect=err):
            st = state(); cap.rpc("http://x", st, "eth_chainId", [])
        a = st["exchanges"][0]["attempts"][0]
        self.assertFalse(a["body_available"]); self.assertNotIn("response_hex", a); self.assertIn("OSError", a["body_error"])
    def test_http200_body_unreadable_then_success(self):
        class Bad(Resp):
            def read(self): raise OSError("reset")
        good = json.dumps({"jsonrpc": "2.0", "id": 1, "result": "0x1"}).encode()
        seq = [Bad(b""), Resp(good)]
        with mock.patch.object(cap.urllib.request, "urlopen", lambda *a, **k: seq.pop(0)):
            st = state(); r = cap.rpc("http://x", st, "eth_chainId", [])
        ex = st["exchanges"][0]
        self.assertEqual(st["n"], 2); self.assertEqual(len(ex["attempts"]), 2)
        a0 = ex["attempts"][0]
        self.assertEqual(a0["http_status"], 200); self.assertFalse(a0["body_available"])
        self.assertNotIn("response_hex", a0); self.assertIn("OSError", a0["body_error"])
        self.assertTrue(ex["attempts"][1]["body_available"]); self.assertIsNone(ex["failure"]); self.assertIsNotNone(r)
    def test_http200_body_unreadable_twice_fails_after_one_retry(self):
        class Bad(Resp):
            def read(self): raise OSError("reset")
        with mock.patch.object(cap.urllib.request, "urlopen", lambda *a, **k: Bad(b"")):
            st = state(); r = cap.rpc("http://x", st, "eth_chainId", [])
        ex = st["exchanges"][0]
        self.assertIsNone(r); self.assertEqual(st["n"], 2); self.assertEqual(len(ex["attempts"]), 2)
        self.assertEqual(ex["failure"], "body unavailable")
        self.assertTrue(all(a["http_status"] == 200 and not a["body_available"] for a in ex["attempts"]))
    def test_transport_error_one_retry(self):
        with mock.patch.object(cap.urllib.request, "urlopen", side_effect=OSError("dns")):
            st = state(); r = cap.rpc("http://x", st, "eth_chainId", [])
        self.assertIsNone(r); self.assertEqual(st["n"], 2); self.assertEqual(st["exchanges"][0]["failure"], "transport error")


class Header(unittest.TestCase):
    def test_header_result_wrong_types_do_not_crash(self):
        for res in ('"0xabc"', "null", "[]", '{"hash":5}', "{}"):
            body = ('{"jsonrpc":"2.0","id":%d,"result":%s}' % (2, res)).encode()
            def fake(req, timeout=None, body=body): return Resp(body)
            with mock.patch.object(cap.urllib.request, "urlopen", fake):
                st = state(); st["rid"] = 1
                r = cap.rpc("http://x", st, *cap.header())
            self.assertNotEqual(cap.header_hash(r), cap.BLOCK_HASH)
    def test_header_hash_ok(self):
        r = {"result": {"hash": cap.BLOCK_HASH}}
        self.assertEqual(cap.header_hash(r), cap.BLOCK_HASH)


def fake_chain(mutate=None, bad_header=False):
    """Mock server: 1 controller per target, all perms 0x..01. mutate(method, params, result)->result."""
    ctrl = "11" * 20
    def handler(req, timeout=None):
        q = json.loads(req.data)
        m, p = q["method"], q["params"]
        if m == "eth_chainId": res = cap.CHAIN_ID
        elif m == "eth_getBlockByNumber": res = "oops" if bad_header else {"hash": cap.BLOCK_HASH}
        elif m == "eth_getCode": res = "0x6000"
        else:
            d = p[0]["data"][10:]
            if d == cap.ARRAY_KEY: res = abi((1).to_bytes(16, "big").hex())
            elif d.startswith(cap.INDEX_PREFIX): res = abi(ctrl)
            else: res = abi("00" * 31 + "01")
        if mutate: res = mutate(m, p, res)
        return Resp(json.dumps({"jsonrpc": "2.0", "id": q["id"], "result": res}).encode())
    return handler


class Capture(unittest.TestCase):
    def cap_one(self, **kw):
        with mock.patch.object(cap.urllib.request, "urlopen", fake_chain(**kw)):
            return cap.capture_endpoint("http://x")
    def test_clean_capture_complete(self):
        out = self.cap_one(); self.assertEqual(out["incomplete"], [])
    def test_bad_header_incomplete_not_crash(self):
        out = self.cap_one(bad_header=True)
        self.assertTrue(any("invalid header" in i for i in out["incomplete"]))
    def test_failed_exchange_recorded(self):
        def mut(m, p, res): return res
        orig = fake_chain()
        def handler(req, timeout=None):
            q = json.loads(req.data)
            if q["method"] == "eth_chainId":
                return Resp(json.dumps({"jsonrpc": "2.0", "id": 999, "result": cap.CHAIN_ID}).encode())
            return orig(req, timeout)
        with mock.patch.object(cap.urllib.request, "urlopen", handler):
            out = cap.capture_endpoint("http://x")
        self.assertTrue(any("id mismatch" in i for i in out["incomplete"]))
    def test_compare_identical_agree(self):
        a, b = self.cap_one(), self.cap_one(); self.assertTrue(cap.compare(a, b)["agree"])
    def test_compare_catches_raw_abi_difference_with_same_decoded(self):
        a = self.cap_one()
        def mut(m, p, res):  # same inner bytes, different ABI padding wrapper (extra trailing word)
            if m == "eth_call" and p[0]["data"][10:].startswith(cap.INDEX_PREFIX): return res + "00" * 32
            return res
        b = self.cap_one(mutate=mut)
        for n in ("Council", "LUKSOAgent", "Emmet"):  # decoded values are identical
            self.assertEqual(a["targets"][n]["controllers"][0]["controller"], b["targets"][n]["controllers"][0]["controller"])
        r = cap.compare(a, b)
        self.assertFalse(r["agree"]); self.assertTrue(any("raw ABI" in d for d in r["disagreements"]))
    def test_compare_catches_length_abi_difference(self):
        a = self.cap_one()
        def mut(m, p, res):
            if m == "eth_call" and p[0]["data"][10:] == cap.ARRAY_KEY: return res + "00" * 32
            return res
        b = self.cap_one(mutate=mut)
        self.assertFalse(cap.compare(a, b)["agree"])


class UserAgent(unittest.TestCase):
    def test_pinned_user_agent_sent_on_every_request(self):
        seen = []
        def fake(req, timeout=None):
            seen.append(req.get_header("User-agent"))
            return Resp(b'{"jsonrpc":"2.0","id":%d,"result":"0x2105"}' % st["rid"])
        st = state()
        with mock.patch.object(cap.urllib.request, "urlopen", fake):
            for ep in cap.ENDPOINTS:
                self.assertIsNotNone(cap.rpc(ep, st, "eth_chainId", []))
        self.assertEqual(cap.USER_AGENT, "agent-council-fixture-capture/0.5")
        self.assertEqual(seen, [cap.USER_AGENT] * len(cap.ENDPOINTS))
        self.assertNotIn("Python-urllib", cap.USER_AGENT)


class Expand(unittest.TestCase):
    def test_counts_unchanged(self):
        self.assertEqual(len(cap.expand_worst_case()), 201)


if __name__ == "__main__":
    unittest.main(verbosity=2)
