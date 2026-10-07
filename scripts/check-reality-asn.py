#!/usr/bin/env python3
"""Compare public origin ASNs. Never print raw responses or exception details."""
import argparse
import ipaddress
import json
import urllib.parse
import urllib.request


def lookup(address, timeout):
    query = urllib.parse.urlencode({"resource": str(address)})
    request = urllib.request.Request(
        "https://stat.ripe.net/data/network-info/data.json?" + query,
        headers={"User-Agent": "xray-dual-node-asn-check"},
    )
    # Query the public routing database directly, without environment proxies.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=timeout) as response:
        payload = json.load(response)
    if payload.get("status") != "ok":
        raise ValueError("lookup unavailable")
    asns = {int(value) for value in payload["data"]["asns"]}
    if not asns or any(value < 1 or value > 4294967295 for value in asns):
        raise ValueError("invalid ASN")
    return asns


def compare(source, targets, timeout=5, resolve=lookup):
    def result(status, detail):
        return {"status": status, "detail": detail}

    def address(value):
        parsed = ipaddress.ip_address(value)
        return getattr(parsed, "ipv4_mapped", None) or parsed

    try:
        source = address(source)
        targets = sorted({address(value) for value in targets},
                         key=lambda value: (value.version, int(value)))
    except ValueError:
        return result("WARN", "ASN not checked: missing/invalid origin IP or DNS address")
    if source in targets:
        return result("FAIL", "target resolves to origin IP; reject self-target routing loop")
    if not source.is_global or not targets or any(not value.is_global for value in targets):
        return result("WARN", "ASN not checked: public origin and target addresses required")
    try:
        origin = resolve(source, timeout)
    except Exception:
        return result("WARN", "ASN lookup unavailable for origin; no match inferred")
    matched = different = unavailable = 0
    observed = set()
    # Bound lookup time and cost for large CDN DNS answers. Never claim full coverage.
    for target in targets[:8]:
        try:
            asns = resolve(target, timeout)
            observed.update(asns)
            if origin & asns:
                matched += 1
            else:
                different += 1
        except Exception:
            unavailable += 1
    omitted = max(0, len(targets) - 8)
    label = lambda values: ",".join("AS" + str(value) for value in sorted(values)) or "unknown"
    detail = (f"origin={label(origin)}; target={label(observed)}; matched={matched}; "
              f"different={different}; unavailable={unavailable}; omitted={omitted}; "
              "DNS snapshot only; same ASN is advisory, not a REALITY requirement")
    return result("PASS" if matched and not (different or unavailable or omitted) else "WARN", detail)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-ip", default="")
    parser.add_argument("--dns-file", required=True)
    parser.add_argument("--timeout", type=int, default=5)
    args = parser.parse_args()
    try:
        with open(args.dns_file, encoding="utf-8") as stream:
            targets = [line.split()[0] for line in stream if line.strip()]
        output = compare(args.source_ip, targets, args.timeout)
    except Exception:
        output = {"status": "WARN", "detail": "ASN check unavailable; details withheld"}
    print(json.dumps(output))


if __name__ == "__main__":
    main()
