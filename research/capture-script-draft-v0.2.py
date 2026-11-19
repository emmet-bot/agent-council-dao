#!/usr/bin/env python3
"""Historical fixture capture script - REVIEW DRAFT v0.2 (not run, not authorized).

Implements "Historical fixture capture scope draft v0.1"
(SHA-256 41de8fe068b27e8feda0a3d07318d9e99ed18d9c1f436296331e8afac4663a27).
Read-only JSON-RPC against Base 8453 at fixed block 56437470. Stdlib only.
No keys, no signing, no TX, no spend.

Modes:
  --expand   Print the worst-case request TEMPLATE for one endpoint (N=16 per
             target) and the count. <Ci> placeholders are bound by rule (see
             CONTROLLER_BINDING). Performs NO network access.
  --capture  Network-enabled capture. Only run after 2/2 exact-bundle YES.

Changes from v0.1 (LUKSOAgent review, 2026-11-18): endpoint comparison step;
permission-field RPC failures mark the capture incomplete; HTTP status + body
kept on errors and HTTP/JSON-RPC errors are not retried; malformed ABI hex
records an incomplete target instead of crashing; decoded permission bytes
stored separately from ABI-wrapped results; --expand labelled a worst-case
template with explicit controller binding.
"""
import hashlib, json, sys, time, urllib.error, urllib.request

CHAIN_ID = "0x2105"
BLOCK = "0x35d2ade"
BLOCK_HASH = "0xad8d95f71e8cc4f1e9736a6f52e1b783209e39591ced071c1e325e8c5891b828"
ENDPOINTS = ["https://mainnet.base.org", "https://base-rpc.publicnode.com"]
TARGETS = [
    ("Council", "0x888033b1492161B5F867573d675d178FA56854Ae"),
    ("LUKSOAgent", "0x293E96ebbf264ed7715cff2b67850517De70232a"),
    ("Emmet", "0x1089E1c613Db8Cb91db72be4818632153E62557a"),
]
GETDATA = "0x54f6127f"
ARRAY_KEY = "df30dba06db6a30e65354d9a64c609861f089545ca58c6b4dbe31a5f338cb0e3"
INDEX_PREFIX = "df30dba06db6a30e65354d9a64c60986"
PERM_PREFIXES = ["4b80742de2bf82acb363", "4b80742de2bf393a64c7", "4b80742de2bf866c2911"]
MAX_N = 16
TIMEOUT = 15
MAX_REQUESTS = 420
CONTROLLER_BINDING = (
    "<Ci> = the i-th controller address of the same target on the same endpoint: "
    "the 20-byte inner value (40 lowercase hex chars, no 0x) decoded from the "
    "index-i call's ABI-wrapped result. Controllers are never substituted from "
    "another target or endpoint."
)


def call(to, key):
    return ("eth_call", [{"to": to, "data": GETDATA + key}, BLOCK])


def header():
    return ("eth_getBlockByNumber", [BLOCK, False])


def abi_inner(hexstr):
    """Decode ABI-wrapped bytes -> inner bytes hex (no 0x), or None if malformed."""
    try:
        if not isinstance(hexstr, str) or not hexstr.startswith("0x"):
            return None
        b = bytes.fromhex(hexstr[2:])
    except ValueError:
        return None
    if len(b) < 64 or int.from_bytes(b[:32], "big") != 32:
        return None
    n = int.from_bytes(b[32:64], "big")
    if len(b) < 64 + n:
        return None
    return b[64:64 + n].hex()


def result_of(r):
    """Return the JSON-RPC result string, or None on transport/HTTP/RPC error."""
    if isinstance(r, dict) and isinstance(r.get("result"), str):
        return r["result"]
    return None


def expand_worst_case():
    """Deterministic worst-case request list for one endpoint (N=16 for every target)."""
    reqs = [("eth_chainId", []), header()]
    for _, t in TARGETS:
        reqs.append(("eth_getCode", [t, BLOCK]))
        reqs.append(call(t, ARRAY_KEY))
        for i in range(MAX_N):
            reqs.append(call(t, INDEX_PREFIX + format(i, "032x")))
            for p in PERM_PREFIXES:
                reqs.append(call(t, p + "0000" + "<C%d>" % i))
    reqs.append(header())
    return reqs


class Budget(Exception):
    pass


def rpc(endpoint, state, method, params):
    state["rid"] += 1
    rid = state["rid"]
    body = json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": params}, separators=(",", ":"))
    ex = {"id": rid, "method": method, "request": body, "attempts": []}
    for attempt in range(2):  # at most one retry; every attempt counts against the cap
        if state["n"] >= MAX_REQUESTS:
            raise Budget("request cap reached")
        state["n"] += 1
        a = {"utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        try:
            req = urllib.request.Request(endpoint, body.encode(), {"Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                a["http_status"] = r.status
                a["response"] = r.read().decode("utf-8", "replace")
            ex["attempts"].append(a)
            break
        except urllib.error.HTTPError as e:  # server answered: keep status + body, do not retry
            a["http_status"] = e.code
            try:
                a["response"] = e.read().decode("utf-8", "replace")
            except Exception:
                a["response"] = ""
            ex["attempts"].append(a)
            break
        except Exception as e:  # pure transport failure (DNS/timeout/reset): one retry allowed
            a["transport_error"] = "%s: %s" % (type(e).__name__, e)
            ex["attempts"].append(a)
    state["exchanges"].append(ex)
    last = ex["attempts"][-1]
    if "response" not in last:
        return None
    try:
        parsed = json.loads(last["response"])
    except ValueError:
        return None
    return parsed if last.get("http_status") == 200 else None


def capture_endpoint(endpoint):
    state = {"n": 0, "rid": 0, "exchanges": []}
    out = {"endpoint": endpoint, "incomplete": [], "targets": {}}
    r = rpc(endpoint, state, "eth_chainId", [])
    if result_of(r) != CHAIN_ID:
        out["incomplete"].append("chainId mismatch or error")
    for tag in ("before",):
        r = rpc(endpoint, state, *header())
        if not r or (r.get("result") or {}).get("hash") != BLOCK_HASH:
            out["incomplete"].append("block hash mismatch (%s)" % tag)
    try:
        for name, t in TARGETS:
            tr = {"code": None, "length_abi": None, "length_decoded": None, "controllers": [], "stop": None}
            r = rpc(endpoint, state, "eth_getCode", [t, BLOCK])
            tr["code"] = result_of(r)
            if tr["code"] is None:
                tr["stop"] = "eth_getCode failed"
            r = rpc(endpoint, state, *call(t, ARRAY_KEY))
            tr["length_abi"] = result_of(r)
            inner = abi_inner(tr["length_abi"])
            if inner is None or len(inner) != 32:  # exact 16-byte unsigned length
                tr["stop"] = tr["stop"] or "array length missing/invalid"
            else:
                tr["length_decoded"] = inner
                n = int(inner, 16)
                if n > MAX_N:
                    tr["stop"] = tr["stop"] or "N=%d exceeds bound %d" % (n, MAX_N)
                else:
                    for i in range(n):
                        r = rpc(endpoint, state, *call(t, INDEX_PREFIX + format(i, "032x")))
                        abi = result_of(r)
                        c = abi_inner(abi)
                        if c is None or len(c) != 40:
                            tr["stop"] = "controller %d invalid" % i
                            break
                        entry = {"index": i, "controller": c, "controller_abi": abi, "perms": {}}
                        for p in PERM_PREFIXES:
                            pr = rpc(endpoint, state, *call(t, p + "0000" + c))
                            pabi = result_of(pr)
                            pdec = abi_inner(pabi)
                            # abi-wrapped result and decoded permission-field bytes stored separately
                            entry["perms"][p] = {"abi_wrapped": pabi, "decoded": pdec}
                            if pdec is None:
                                out["incomplete"].append("%s: controller %d perm %s missing/invalid" % (name, i, p))
                        tr["controllers"].append(entry)  # duplicates and zero entries preserved
            if tr["stop"]:
                out["incomplete"].append("%s: %s" % (name, tr["stop"]))
            out["targets"][name] = tr
    except Budget as e:
        out["incomplete"].append("budget: %s" % e)
    r = None
    try:
        r = rpc(endpoint, state, *header())
    except Budget as e:
        out["incomplete"].append("budget: %s" % e)
    if not r or (r.get("result") or {}).get("hash") != BLOCK_HASH:
        out["incomplete"].append("block hash mismatch (after)")
    out["request_count"] = state["n"]
    out["exchanges"] = state["exchanges"]
    return out


def compare(a, b):
    """Record disagreements between two endpoint datasets (decoded data only)."""
    diffs = []
    if a["incomplete"] or b["incomplete"]:
        diffs.append("at least one dataset incomplete")
    for name, _ in TARGETS:
        ta, tb = a["targets"].get(name), b["targets"].get(name)
        if ta is None or tb is None:
            diffs.append("%s: missing target in one dataset" % name)
            continue
        for k in ("code", "length_decoded", "stop"):
            if ta.get(k) != tb.get(k):
                diffs.append("%s: %s differs" % (name, k))
        ca = [(e["controller"], {p: v["decoded"] for p, v in e["perms"].items()}) for e in ta["controllers"]]
        cb = [(e["controller"], {p: v["decoded"] for p, v in e["perms"].items()}) for e in tb["controllers"]]
        if ca != cb:
            diffs.append("%s: controllers/permissions differ" % name)
    return {"agree": not diffs, "disagreements": diffs}


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "--expand":
        reqs = expand_worst_case()
        print("WORST-CASE TEMPLATE for one endpoint (not a literal call list: <Ci> is substituted at capture time)")
        print("BINDING:", CONTROLLER_BINDING)
        for i, (m, p) in enumerate(reqs, 1):
            print(i, m, json.dumps(p, separators=(",", ":")))
        print("TOTAL per endpoint (worst case, no retries):", len(reqs), "| with one retry each:", 2 * len(reqs), "| cap:", MAX_REQUESTS)
        return
    if mode == "--capture":
        datasets = [capture_endpoint(e) for e in ENDPOINTS]
        raw = {"scope_sha256": "41de8fe068b27e8feda0a3d07318d9e99ed18d9c1f436296331e8afac4663a27",
               "datasets": datasets, "comparison": compare(datasets[0], datasets[1])}
        blob = (json.dumps(raw, sort_keys=True, separators=(",", ":")) + "\n").encode()
        open("base-56437470.raw.json", "wb").write(blob)
        print(len(blob), hashlib.sha256(blob).hexdigest())
        return
    print(__doc__)


if __name__ == "__main__":
    main()
