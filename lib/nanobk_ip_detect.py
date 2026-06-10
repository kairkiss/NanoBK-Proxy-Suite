#!/usr/bin/env python3
"""
NanoBK VPS IP Auto-detect (Dry-run)

Detects public IPv4/IPv6 of the current VPS for DNS target preparation.
Read-only. No DNS mutation. No Cloudflare calls. No system changes.

Usage:
    python3 lib/nanobk_ip_detect.py detect [--json]

Test hooks (env vars):
    NANOBK_IP_DETECT_FIXTURE=/path/to/fixture.json   — load candidates from fixture
    NANOBK_TEST_DETECTED_IPV4=203.0.113.10            — mock IPv4 result
    NANOBK_TEST_DETECTED_IPV6=2001:db8::10            — mock IPv6 result
    NANOBK_TEST_DETECT_IPV4_FAIL=1                    — simulate IPv4 detection failure
    NANOBK_TEST_DETECT_IPV6_FAIL=1                    — simulate IPv6 detection failure
    NANOBK_TEST_LOCAL_IPV4=203.0.113.20               — mock local interface IPv4 fallback
    NANOBK_TEST_LOCAL_IPV6=2001:db8::20               — mock local interface IPv6 fallback
    NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL=1            — force HTTPS endpoint IPv4 failure (triggers fallback)
    NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL=1            — force HTTPS endpoint IPv6 failure (triggers fallback)
"""

import argparse
import ipaddress
import json
import os
import re
import subprocess
import sys
import urllib.request
import urllib.error


# ── Public IP echo endpoints ────────────────────────────────────────────────

_IPV4_ENDPOINTS = [
    "https://api.ipify.org?format=json",
    "https://ifconfig.me/ip",
    "https://icanhazip.com",
]

_IPV6_ENDPOINTS = [
    "https://api6.ipify.org?format=json",
    "https://ifconfig.me/ip",
    "https://icanhazip.com",
]

_DETECT_TIMEOUT = 5  # seconds per endpoint


# ── IP classification ──────────────────────────────────────────────────────

_IPV4_DOC_RANGES = [
    ipaddress.IPv4Network("192.0.2.0/24"),
    ipaddress.IPv4Network("198.51.100.0/24"),
    ipaddress.IPv4Network("203.0.113.0/24"),
]

_IPV6_DOC_RANGES = [
    ipaddress.IPv6Network("2001:db8::/32"),
]


def classify_scope(addr_str, family):
    """Classify an IP address scope."""
    try:
        if family == "ipv4":
            addr = ipaddress.IPv4Address(addr_str)
            for net in _IPV4_DOC_RANGES:
                if addr in net:
                    return "documentation"
            if addr.is_loopback:
                return "loopback"
            if addr.is_multicast:
                return "multicast"
            if addr.is_private:
                return "private"
            if addr.is_reserved:
                return "reserved"
            if addr.is_link_local:
                return "link_local"
            return "global"
        else:
            addr = ipaddress.IPv6Address(addr_str)
            for net in _IPV6_DOC_RANGES:
                if addr in net:
                    return "documentation"
            if addr.is_loopback:
                return "loopback"
            if addr.is_multicast:
                return "multicast"
            if addr.is_link_local:
                return "link_local"
            if addr.is_private:
                return "ula"
            if addr.is_reserved:
                return "reserved"
            return "global"
    except (ipaddress.AddressValueError, ValueError):
        return "unknown"


def is_usable_for_dns(scope):
    """Check if scope is usable for DNS target."""
    return scope in ("global", "documentation")


# ── Real detection ──────────────────────────────────────────────────────────

def _fetch_text(url, timeout=_DETECT_TIMEOUT):
    """Fetch text from URL with short timeout."""
    req = urllib.request.Request(url, method="GET")
    req.add_header("User-Agent", "nanobk-ip-detect/1.0")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode("utf-8").strip()
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, TimeoutError):
        return None


def _parse_ip_from_response(text, family):
    """Parse IP address from endpoint response text."""
    if not text:
        return None
    text = text.strip()
    # Try JSON first (ipify format)
    try:
        data = json.loads(text)
        ip = data.get("ip", "").strip()
        if ip:
            return ip
    except (json.JSONDecodeError, AttributeError):
        pass
    # Try plain text (ifconfig.me, icanhazip)
    # Take first line, strip whitespace
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        # Validate it looks like an IP
        try:
            if family == "ipv4":
                ipaddress.IPv4Address(line)
            else:
                ipaddress.IPv6Address(line)
            return line
        except (ipaddress.AddressValueError, ValueError):
            continue
    return None


def detect_public_ip(family):
    """Detect public IP via HTTPS endpoints. Returns (address, source) or (None, None)."""
    # Test override: force endpoint failure
    if family == "ipv4" and os.environ.get("NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL") == "1":
        return None, None
    if family == "ipv6" and os.environ.get("NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL") == "1":
        return None, None
    endpoints = _IPV4_ENDPOINTS if family == "ipv4" else _IPV6_ENDPOINTS
    for url in endpoints:
        text = _fetch_text(url)
        addr = _parse_ip_from_response(text, family)
        if addr:
            return addr, url
    return None, None


def detect_local_interface(family):
    """Detect IP from local network interfaces. Returns (address, source) or (None, None).

    Uses 'ip addr show scope global' to extract candidates.
    Only returns addresses that pass ipaddress validation and DNS usability check.
    Does NOT print raw interface dump.
    """
    # Test override: mock local fallback
    if family == "ipv4":
        mock = os.environ.get("NANOBK_TEST_LOCAL_IPV4")
        if mock:
            scope = classify_scope(mock, "ipv4")
            if is_usable_for_dns(scope):
                return mock, "local_interface_mock"
            return None, None
    else:
        mock = os.environ.get("NANOBK_TEST_LOCAL_IPV6")
        if mock:
            scope = classify_scope(mock, "ipv6")
            if is_usable_for_dns(scope):
                return mock, "local_interface_mock"
            return None, None

    # Real local interface detection
    ip_flag = "-4" if family == "ipv4" else "-6"
    try:
        result = subprocess.run(
            ["ip", ip_flag, "-o", "addr", "show", "scope", "global"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            return None, None
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        return None, None

    # Parse ip output: "N: iface inet ADDR/MASK scope global ..."
    # Extract the IP address (4th field)
    candidates = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) < 4:
            continue
        addr_with_mask = parts[3]
        # Strip CIDR prefix length if present
        addr = addr_with_mask.split("/")[0]
        scope = classify_scope(addr, family)
        if is_usable_for_dns(scope):
            candidates.append(addr)

    if not candidates:
        return None, None

    # Return first usable candidate (stable global address)
    return candidates[0], "local_interface"


# ── Detection orchestration ─────────────────────────────────────────────────

def detect_ipv4():
    """Detect IPv4: env mock → HTTPS endpoint → local interface fallback → not_detected."""
    # 1. Test override: simulate failure
    if os.environ.get("NANOBK_TEST_DETECT_IPV4_FAIL") == "1":
        return {"status": "not_detected", "address": None, "scope": None,
                "source": "test_override_fail"}
    # 2. Test override: mock result
    mock = os.environ.get("NANOBK_TEST_DETECTED_IPV4")
    if mock:
        scope = classify_scope(mock, "ipv4")
        if not is_usable_for_dns(scope):
            return {"status": "not_usable", "address": mock, "scope": scope,
                    "source": "test_override"}
        return {"status": "detected", "address": mock, "scope": scope,
                "source": "test_override"}
    # 3. HTTPS endpoint detection
    addr, source = detect_public_ip("ipv4")
    if addr:
        scope = classify_scope(addr, "ipv4")
        if not is_usable_for_dns(scope):
            return {"status": "not_usable", "address": addr, "scope": scope,
                    "source": source}
        return {"status": "detected", "address": addr, "scope": scope,
                "source": source}
    # 4. Local interface fallback
    addr, source = detect_local_interface("ipv4")
    if addr:
        scope = classify_scope(addr, "ipv4")
        return {"status": "detected", "address": addr, "scope": scope,
                "source": source}
    return {"status": "not_detected", "address": None, "scope": None,
            "source": None}


def detect_ipv6():
    """Detect IPv6: env mock → HTTPS endpoint → local interface fallback → not_detected."""
    # 1. Test override: simulate failure
    if os.environ.get("NANOBK_TEST_DETECT_IPV6_FAIL") == "1":
        return {"status": "not_detected", "address": None, "scope": None,
                "source": "test_override_fail"}
    # 2. Test override: mock result
    mock = os.environ.get("NANOBK_TEST_DETECTED_IPV6")
    if mock:
        scope = classify_scope(mock, "ipv6")
        if not is_usable_for_dns(scope):
            return {"status": "not_usable", "address": mock, "scope": scope,
                    "source": "test_override"}
        return {"status": "detected", "address": mock, "scope": scope,
                "source": "test_override"}
    # 3. HTTPS endpoint detection
    addr, source = detect_public_ip("ipv6")
    if addr:
        scope = classify_scope(addr, "ipv6")
        if not is_usable_for_dns(scope):
            return {"status": "not_usable", "address": addr, "scope": scope,
                    "source": source}
        return {"status": "detected", "address": addr, "scope": scope,
                "source": source}
    # 4. Local interface fallback
    addr, source = detect_local_interface("ipv6")
    if addr:
        scope = classify_scope(addr, "ipv6")
        return {"status": "detected", "address": addr, "scope": scope,
                "source": source}
    return {"status": "not_detected", "address": None, "scope": None,
            "source": None}


def run_detect():
    """Run full IP detection. Returns result dict."""
    ipv4 = detect_ipv4()
    ipv6 = detect_ipv6()

    ipv4_ok = ipv4["status"] == "detected"
    ipv6_ok = ipv6["status"] == "detected"

    if ipv4_ok and ipv6_ok:
        a_rec = "ready"
        aaaa_rec = "ready"
    elif ipv4_ok:
        a_rec = "ready"
        aaaa_rec = "skipped"
    elif ipv6_ok:
        a_rec = "skipped"
        aaaa_rec = "ready"
    else:
        a_rec = "skipped"
        aaaa_rec = "skipped"

    ok = ipv4_ok or ipv6_ok

    return {
        "ok": ok,
        "ipv4": {
            "status": ipv4["status"],
            "address": ipv4["address"],
            "scope": ipv4["scope"],
        },
        "ipv6": {
            "status": ipv6["status"],
            "address": ipv6["address"],
            "scope": ipv6["scope"],
        },
        "recommendation": {
            "a_record": a_rec,
            "aaaa_record": aaaa_rec,
        },
        "safety": {
            "dry_run": True,
            "system_changed": False,
            "cloudflare_touched": False,
            "raw_interface_dump_printed": False,
        },
    }


# ── Fixture-based detection (legacy) ───────────────────────────────────────

def load_fixture(fixture_path):
    """Load IP candidates from fixture file."""
    try:
        with open(fixture_path, "r") as f:
            data = json.load(f)
    except FileNotFoundError:
        raise RuntimeError(f"Fixture file not found") from None
    except json.JSONDecodeError:
        raise RuntimeError("Fixture file contains invalid JSON") from None
    except OSError:
        raise RuntimeError("Cannot read fixture file") from None

    addresses = data.get("addresses", [])
    if not isinstance(addresses, list):
        raise RuntimeError("Fixture 'addresses' must be a list")

    return addresses


def classify_candidates(raw_addresses):
    """Classify raw address entries into candidates."""
    candidates = []
    for entry in raw_addresses:
        family = entry.get("family", "").lower()
        addr = entry.get("address", "")
        source = entry.get("source", "unknown")

        if family not in ("ipv4", "ipv6"):
            continue
        if not addr:
            continue

        scope = classify_scope(addr, family)
        usable = is_usable_for_dns(scope)

        candidates.append({
            "family": family,
            "address": addr,
            "scope": scope,
            "source": source,
            "usable_for_dns": usable,
        })

    return candidates


def compute_fixture_result(candidates):
    """Compute detection result from classified fixture candidates."""
    ipv4_usable = [c for c in candidates if c["family"] == "ipv4" and c["usable_for_dns"]]
    ipv6_usable = [c for c in candidates if c["family"] == "ipv6" and c["usable_for_dns"]]

    ipv4_ok = len(ipv4_usable) > 0
    ipv6_ok = len(ipv6_usable) > 0

    if ipv4_ok and ipv6_ok:
        a_rec = "ready"
        aaaa_rec = "ready"
    elif ipv4_ok:
        a_rec = "ready"
        aaaa_rec = "skipped"
    elif ipv6_ok:
        a_rec = "skipped"
        aaaa_rec = "ready"
    else:
        a_rec = "skipped"
        aaaa_rec = "skipped"

    ipv4_addr = ipv4_usable[0]["address"] if ipv4_usable else None
    ipv6_addr = ipv6_usable[0]["address"] if ipv6_usable else None
    ipv4_scope = ipv4_usable[0]["scope"] if ipv4_usable else None
    ipv6_scope = ipv6_usable[0]["scope"] if ipv6_usable else None

    return {
        "ok": ipv4_ok or ipv6_ok,
        "ipv4": {
            "status": "detected" if ipv4_ok else "not_detected",
            "address": ipv4_addr,
            "scope": ipv4_scope,
        },
        "ipv6": {
            "status": "detected" if ipv6_ok else "not_detected",
            "address": ipv6_addr,
            "scope": ipv6_scope,
        },
        "recommendation": {
            "a_record": a_rec,
            "aaaa_record": aaaa_rec,
        },
        "safety": {
            "dry_run": True,
            "system_changed": False,
            "cloudflare_touched": False,
            "raw_interface_dump_printed": False,
        },
    }


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable IP detection report."""
    ipv4 = result.get("ipv4", {})
    ipv6 = result.get("ipv6", {})
    rec = result.get("recommendation", {})
    safety = result.get("safety", {})

    ipv4_status = ipv4.get("status", "not_detected")
    ipv6_status = ipv6.get("status", "not_detected")
    ipv4_addr = ipv4.get("address")
    ipv6_addr = ipv6.get("address")

    print()
    print("  NanoBK VPS address detection")
    print()
    print(f"  IPv4: {ipv4_status}")
    print(f"  IPv6: {ipv6_status}")
    print()
    print("  Detected addresses:")
    if ipv4_status == "detected" and ipv4_addr:
        print(f"    * IPv4: {ipv4_addr}")
    else:
        print("    * IPv4: not available")
    if ipv6_status == "detected" and ipv6_addr:
        print(f"    * IPv6: {ipv6_addr}")
    else:
        print("    * IPv6: not available")
    print()
    print("  Recommendation:")
    print(f"    * A record: {rec.get('a_record', 'skipped')}")
    print(f"    * AAAA record: {rec.get('aaaa_record', 'skipped')}")
    print()
    print("  Safety:")
    print(f"    Dry-run: {str(safety.get('dry_run', True)).lower()}")
    print(f"    System changed: {str(safety.get('system_changed', False)).lower()}")
    print(f"    Cloudflare touched: {str(safety.get('cloudflare_touched', False)).lower()}")
    print(f"    Raw interface dump printed: {str(safety.get('raw_interface_dump_printed', False)).lower()}")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {
            "ok": False,
            "error": message,
            "ipv4": {"status": "error", "address": None, "scope": None},
            "ipv6": {"status": "error", "address": None, "scope": None},
            "recommendation": {"a_record": "skipped", "aaaa_record": "skipped"},
            "safety": {
                "dry_run": True,
                "system_changed": False,
                "cloudflare_touched": False,
                "raw_interface_dump_printed": False,
            },
        }
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK VPS IP Auto-detect (dry-run)"
    )
    sub = parser.add_subparsers(dest="command")

    detect_parser = sub.add_parser("detect", help="Detect public IPv4/IPv6")
    detect_parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.command != "detect":
        parser.print_help()
        sys.exit(1)

    fixture_path = os.environ.get("NANOBK_IP_DETECT_FIXTURE")

    try:
        if fixture_path:
            # Legacy fixture-based path
            raw_addresses = load_fixture(fixture_path)
            candidates = classify_candidates(raw_addresses)
            result = compute_fixture_result(candidates)
        else:
            # Real detection (with test env var overrides)
            result = run_detect()
    except RuntimeError as e:
        output_error(str(e), args.json)
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)

    # Exit non-zero if nothing detected
    if not result.get("ok", False):
        sys.exit(1)


if __name__ == "__main__":
    main()
