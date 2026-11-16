#!/usr/bin/env python3
"""Read-only historical fixture capture for scope v0.1
(SHA-256 41de8fe068b27e8feda0a3d07318d9e99ed18d9c1f436296331e8afac4663a27).

REVIEW DRAFT. Do not run before both exact-scope YES votes.
Stdlib only. No credentials, signing, transactions or writes besides the output file.

Usage: capture_base_56437470.py --i-have-2of2-approval --out base-56437470.raw.json
"""
import argparse
import datetime
import hashlib
import json
import sys
import urllib.error
import urllib.request

CHAIN_ID = "0x2105"
BLOCK_TAG = "0x35d2ade"  # 56437470
BLOCK_HASH = "0xad8d95f71e8cc4f1e9736a6f52e1b783209e39591ced071c1e325e8c5891b828"
ENDPOINTS = ["https://mainnet.base.org", "https://base-rpc.publicnode.com"]
TARGETS = [
    ("Council", "0x888033b1492161B5F867573d675d178FA56854Ae"),
    ("LUKSOAgent", "0x293E96ebbf264ed7715cff2b67850517De70232a"),
    ("Emmet", "0x1089E1c613Db8Cb91db72be4818632153E62557a"),
]
TIMEOUT_S = 15
MAX_RETRIES = 1
MAX_REQUESTS_PER_ENDPOINT = 420  # counts every attempt, including retries
MAX_CONTROLLERS = 16

GETDATA = "0x54f6127f"
ARRAY_KEY = "df30dba06db6a30e65354d9a64c609861f089545ca58c6b4dbe31a5f338cb0e3"
ARRAY_INDEX_PREFIX = "df30dba06db6a30e65354d9a64c60986"
CONTROLLER_PREFIXES = [
    ("permissions", "4b80742de2bf82acb363"),
    ("allowedCalls", "4b80742de2bf393a64c7"),
    ("allowedERC725YDataKeys", "4b80742de2bf866c2911"),
]


class Halt(Exception):
    pass


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class Endpoint:
    def __init__(self, url):
        self.url = url
        self.attempts = 0
        self.next_id = 1
        self.exchanges = []

    def call(self, method, params):
        """One logical request, at most MAX_RETRIES retries on transport error only."""
        for attempt in range(MAX_RETRIES + 1):
            if self.attempts >= MAX_REQUESTS_PER_ENDPOINT:
                raise Halt(f"request cap reached on {self.url}")
            self.attempts += 1
            req_id = self.next_id
            self.next_id += 1
            body = json.dumps({"jsonrpc": "2.0", "id": req_id, "method": method, "params": params})
            ex = {
                "order": len(self.exchanges),
                "attempt": attempt,
                "requestId": req_id,
                "retrievedAt": utc_now(),
                "requestBody": body,
                "httpStatus": None,
                "responseBody": None,
                "transportError": None,
            }
            self.exchanges.append(ex)
            try:
                r = urllib.request.Request(self.url, data=body.encode(), headers={"content-type": "application/json", "user-agent": "agent-council-capture/0.1"})
                with urllib.request.urlopen(r, timeout=TIMEOUT_S) as resp:
                    ex["httpStatus"] = resp.status
                    ex["responseBody"] = resp.read().decode("utf-8")
            except urllib.error.HTTPError as e:
                ex["httpStatus"] = e.code
                ex["responseBody"] = e.read().decode("utf-8", "replace")
                return ex, None, {"http": e.code}
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                ex["transportError"] = repr(e)
                continue
            try:
                parsed = json.loads(ex["responseBody"])
            except ValueError as e:
                return ex, None, {"parse": repr(e)}
            if "error" in parsed:
                return ex, None, parsed["error"]  # code/message/data kept exactly as returned
            return ex, parsed.get("result"), None
        return ex, None, {"transport": ex["transportError"]}


def abi_inner_bytes(result_hex):
    """Decode ABI-encoded `bytes` return; returns inner hex or raises ValueError."""
    if not isinstance(result_hex, str) or not result_hex.startswith("0x"):
        raise ValueError("not hex")
    raw = bytes.fromhex(result_hex[2:])
    if len(raw) < 64:
        raise ValueError("short ABI return")
    off = int.from_bytes(raw[0:32], "big")
    if off + 32 > len(raw):
        raise ValueError("bad offset")
    n = int.from_bytes(raw[off:off + 32], "big")
    if off + 32 + n > len(raw):
        raise ValueError("bad length")
    return "0x" + raw[off + 32:off + 32 + n].hex()


def check_header(ep, phase, record):
    ex, chain, err = ep.call("eth_chainId", [])
    record[f"{phase}ChainId"] = {"result": chain, "error": err}
    if err is not None or chain != CHAIN_ID:
        raise Halt(f"{ep.url} {phase}: chain mismatch {chain!r} {err!r}")
    ex, blk, err = ep.call("eth_getBlockByNumber", [BLOCK_TAG, False])
    got = blk.get("hash") if isinstance(blk, dict) else None
    record[f"{phase}BlockHash"] = {"result": got, "error": err}
    if err is not None or got != BLOCK_HASH:
        raise Halt(f"{ep.url} {phase}: block hash mismatch {got!r} {err!r}")


def get_data(ep, target, key_hex):
    data = GETDATA + key_hex
    ex, result, err = ep.call("eth_call", [{"to": target, "data": data}, BLOCK_TAG])
    entry = {"key": "0x" + key_hex, "abiResult": result, "innerBytes": None, "error": err, "exchangeOrder": ex["order"]}
    if err is None:
        entry["innerBytes"] = abi_inner_bytes(result)
    return entry


def capture_target(ep, name, addr):
    t = {"name": name, "address": addr, "code": None, "codeError": None, "arrayLength": None,
         "controllers": [], "complete": False, "stopReason": None}
    ex, code, err = ep.call("eth_getCode", [addr, BLOCK_TAG])
    t["code"], t["codeError"] = code, err
    if err is not None:
        t["stopReason"] = "getCode error"
        return t
    try:
        length = get_data(ep, addr, ARRAY_KEY)
    except ValueError as e:
        t["stopReason"] = f"array length ABI decode: {e}"
        return t
    t["arrayLength"] = length
    inner = length["innerBytes"]
    if length["error"] is not None or inner is None or len(inner) != 2 + 32:
        t["stopReason"] = "array length not exactly 16 bytes"
        return t
    n = int(inner, 16)
    if n > MAX_CONTROLLERS:
        t["stopReason"] = f"array length {n} > {MAX_CONTROLLERS}"
        return t
    for i in range(n):
        try:
            idx = get_data(ep, addr, ARRAY_INDEX_PREFIX + i.to_bytes(16, "big").hex())
        except ValueError as e:
            t["stopReason"] = f"index {i} ABI decode: {e}"
            return t
        c_inner = idx["innerBytes"]
        ctrl = {"index": i, "indexRead": idx, "address": None, "fields": {}}
        t["controllers"].append(ctrl)
        if idx["error"] is not None or c_inner is None or len(c_inner) != 2 + 40:
            t["stopReason"] = f"index {i} not exactly 20 bytes"
            return t
        c = c_inner[2:].lower()
        ctrl["address"] = "0x" + c
        for field, prefix in CONTROLLER_PREFIXES:
            try:
                ctrl["fields"][field] = get_data(ep, addr, prefix + "0000" + c)
            except ValueError as e:
                t["stopReason"] = f"index {i} {field} ABI decode: {e}"
                return t
            if ctrl["fields"][field]["error"] is not None:
                t["stopReason"] = f"index {i} {field} RPC error"
                return t
    t["complete"] = True
    return t


def capture_endpoint(url):
    ep = Endpoint(url)
    rec = {"endpoint": url, "targets": [], "complete": False, "haltReason": None}
    try:
        check_header(ep, "before", rec)
        for name, addr in TARGETS:
            rec["targets"].append(capture_target(ep, name, addr))
        check_header(ep, "after", rec)
        rec["complete"] = all(t["complete"] for t in rec["targets"])
    except Halt as e:
        rec["haltReason"] = str(e)
    rec["attempts"] = ep.attempts
    rec["exchanges"] = ep.exchanges
    return rec


def compare(a, b):
    """Raw result bytes must agree across endpoints; any difference is recorded, never resolved."""
    diffs = []
    if not (a["complete"] and b["complete"]):
        return ["at least one endpoint incomplete"]
    for ta, tb in zip(a["targets"], b["targets"]):
        if ta["code"] != tb["code"]:
            diffs.append(f"{ta['name']} code")
        if ta["arrayLength"]["abiResult"] != tb["arrayLength"]["abiResult"]:
            diffs.append(f"{ta['name']} arrayLength")
        if len(ta["controllers"]) != len(tb["controllers"]):
            diffs.append(f"{ta['name']} controller count")
            continue
        for ca, cb in zip(ta["controllers"], tb["controllers"]):
            if ca["indexRead"]["abiResult"] != cb["indexRead"]["abiResult"]:
                diffs.append(f"{ta['name']}[{ca['index']}] address")
            for field, _ in CONTROLLER_PREFIXES:
                if ca["fields"][field]["abiResult"] != cb["fields"][field]["abiResult"]:
                    diffs.append(f"{ta['name']}[{ca['index']}] {field}")
    return diffs


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--i-have-2of2-approval", action="store_true", required=True)
    p.add_argument("--out", required=True)
    args = p.parse_args()
    endpoints = [capture_endpoint(u) for u in ENDPOINTS]
    diffs = compare(*endpoints)
    doc = {
        "kind": "historical-fixture-capture/0.1",
        "scopeSha256": "41de8fe068b27e8feda0a3d07318d9e99ed18d9c1f436296331e8afac4663a27",
        "chainId": CHAIN_ID,
        "blockTag": BLOCK_TAG,
        "blockHash": BLOCK_HASH,
        "capturedAt": utc_now(),
        "endpoints": endpoints,
        "endpointDisagreements": diffs,
        "complete": not diffs and all(e["complete"] for e in endpoints),
        "limitations": "Historical snapshot only; enumeration is not exhaustive; no KeyManager enforcement or safety claim.",
    }
    data = (json.dumps(doc, indent=2) + "\n").encode("utf-8")
    with open(args.out, "wb") as f:
        f.write(data)
    print(json.dumps({"out": args.out, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "complete": doc["complete"]}))
    return 0 if doc["complete"] else 2


if __name__ == "__main__":
    sys.exit(main())
