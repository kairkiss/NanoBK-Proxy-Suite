#!/usr/bin/env python3
"""
NanoBK VPS IP Detection Skeleton

Fixture-first IPv4/IPv6 candidate classification for DNS target preparation.
Read-only. No external IP echo calls. No Cloudflare calls. No DNS mutation.

Usage:
    python3 lib/nanobk_ip_detect.py detect [--json]

Test hook:
    NANOBK_IP_DETECT_FIXTURE=/path/to/fixture.json
"""

import argparse
import ipaddress
import json
import os
import sys


# ── Documentation ranges ───────────────────────────────────────────────────

_IPV4_DOC_RANGES = [
    ipaddress.IPv4Network("192.0.2.0/24"),
    ipaddress.IPv4Network("198.51.100.0/24"),
    ipaddress.IPv4Network("203.0.113.0/24"),
]

_IPV6_DOC_RANGES = [
    ipaddress.IPv6Network("2001:db8::/32"),
]


# ── Classification ─────────────────────────────────────────────────────────

def classify_scope(addr_str, family):
    """Classify an IP address scope."""
    try:
        if family == "ipv4":
            addr = ipaddress.IPv4Address(addr_str)
            # Check documentation ranges first
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
            # Check documentation ranges first
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
                # ULA (fc00::/7) falls under is_private
                return "ula"
            if addr.is_reserved:
                return "reserved"
            return "global"
    except (ipaddress.AddressValueError, ValueError):
        return "unknown"


def is_usable_for_dns(scope):
    """Check if scope is usable for DNS target."""
    return scope in ("global", "documentation")


# ── Masking ─────────────────────────────────────────────────────────────────

def mask_ipv4(addr_str):
    """Mask IPv4: 203.0.113.10 -> 203.0.113.xxx"""
    parts = addr_str.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.{parts[2]}.xxx"
    return "xxx.xxx.xxx.xxx"


def mask_ipv6(addr_str):
    """Mask IPv6: show first 1-2 groups + ellipsis."""
    try:
        addr = ipaddress.IPv6Address(addr_str)
        compressed = addr.compressed  # e.g. 2001:db8::10
        # Split on :: or : to get leading groups
        if "::" in compressed:
            leading = compressed.split("::")[0]
        else:
            leading = compressed
        groups = [g for g in leading.split(":") if g]
        if len(groups) >= 2:
            return f"{groups[0]}:{groups[1]}:…"
        elif len(groups) == 1:
            return f"{groups[0]}:…"
        else:
            return "…"
    except (ipaddress.AddressValueError, ValueError):
        return "…"


# ── Detection logic ────────────────────────────────────────────────────────

def load_fixture(fixture_path):
    """Load IP candidates from fixture file."""
    try:
        with open(fixture_path, "r") as f:
            data = json.load(f)
    except FileNotFoundError:
        raise RuntimeError(f"Fixture file not found: {fixture_path}") from None
    except json.JSONDecodeError:
        raise RuntimeError("Fixture file contains invalid JSON") from None
    except OSError as e:
        raise RuntimeError(f"Cannot read fixture file: {e}") from None

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

        mask_fn = mask_ipv4 if family == "ipv4" else mask_ipv6
        candidates.append({
            "family": family,
            "ip_redacted": mask_fn(addr),
            "scope": scope,
            "source": source,
            "usable_for_dns": usable,
        })

    return candidates


def compute_result(candidates):
    """Compute detection result from classified candidates."""
    ipv4_usable = [c for c in candidates if c["family"] == "ipv4" and c["usable_for_dns"]]
    ipv6_usable = [c for c in candidates if c["family"] == "ipv6" and c["usable_for_dns"]]
    ipv4_all = [c for c in candidates if c["family"] == "ipv4"]
    ipv6_all = [c for c in candidates if c["family"] == "ipv6"]

    dual_stack = len(ipv4_usable) > 0 and len(ipv6_usable) > 0

    # Multiple candidates of same family = can't auto-choose
    multiple_ipv4 = len(ipv4_usable) > 1
    multiple_ipv6 = len(ipv6_usable) > 1

    # DNS target readiness
    has_usable = len(ipv4_usable) > 0 or len(ipv6_usable) > 0
    no_conflict = not multiple_ipv4 and not multiple_ipv6
    dns_target_ready = has_usable and no_conflict
    manual_input_required = not dns_target_ready

    # Build checks
    checks = []

    if len(ipv4_all) == 0:
        checks.append({"name": "ipv4_detection", "status": "skipped", "message": "no IPv4 address found"})
    elif len(ipv4_usable) == 0:
        checks.append({"name": "ipv4_detection", "status": "warning", "message": "IPv4 found but not usable for DNS (private/link-local/loopback)"})
    elif multiple_ipv4:
        checks.append({"name": "ipv4_detection", "status": "manual_pending", "message": f"{len(ipv4_usable)} usable IPv4 candidates — manual selection required"})
    else:
        checks.append({"name": "ipv4_detection", "status": "ok", "message": "1 usable IPv4 candidate"})

    if len(ipv6_all) == 0:
        checks.append({"name": "ipv6_detection", "status": "skipped", "message": "no IPv6 address found"})
    elif len(ipv6_usable) == 0:
        checks.append({"name": "ipv6_detection", "status": "warning", "message": "IPv6 found but not usable for DNS (link-local/ULA/loopback)"})
    elif multiple_ipv6:
        checks.append({"name": "ipv6_detection", "status": "manual_pending", "message": f"{len(ipv6_usable)} usable IPv6 candidates — manual selection required"})
    else:
        checks.append({"name": "ipv6_detection", "status": "ok", "message": "1 usable IPv6 candidate"})

    return {
        "ok": True,
        "mutation": False,
        "dns_target_ready": dns_target_ready,
        "dual_stack": dual_stack,
        "manual_input_required": manual_input_required,
        "candidates": candidates,
        "checks": checks,
    }


def run_detect(fixture_path=None):
    """Run IP detection. Returns result dict."""
    if not fixture_path:
        return {
            "ok": True,
            "mutation": False,
            "dns_target_ready": False,
            "dual_stack": False,
            "manual_input_required": True,
            "candidates": [],
            "checks": [
                {"name": "detection_source", "status": "manual_pending",
                 "message": "live detection not enabled — provide NANOBK_IP_DETECT_FIXTURE or use manual input"},
            ],
        }

    raw_addresses = load_fixture(fixture_path)
    candidates = classify_candidates(raw_addresses)
    return compute_result(candidates)


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable IP detection report."""
    print()
    print("  NanoBK VPS IP detection")
    print()

    candidates = result.get("candidates", [])
    ipv4 = [c for c in candidates if c["family"] == "ipv4"]
    ipv6 = [c for c in candidates if c["family"] == "ipv6"]

    # IPv4 section
    print("  IPv4:")
    if ipv4:
        for c in ipv4:
            usable = "usable" if c["usable_for_dns"] else "not usable"
            print(f"    candidate: {c['ip_redacted']}  scope: {c['scope']}  ({usable})")
    else:
        print("    status: unavailable")

    # IPv6 section
    print()
    print("  IPv6:")
    if ipv6:
        for c in ipv6:
            usable = "usable" if c["usable_for_dns"] else "not usable"
            print(f"    candidate: {c['ip_redacted']}  scope: {c['scope']}  ({usable})")
    else:
        print("    status: unavailable")

    # DNS target readiness
    print()
    print("  DNS target readiness:")
    print(f"    dual_stack: {str(result.get('dual_stack', False)).lower()}")
    print(f"    manual_input_required: {str(result.get('manual_input_required', True)).lower()}")

    # Detection source info
    checks = result.get("checks", [])
    for check in checks:
        if check.get("status") == "manual_pending":
            print(f"\n  Note: {check.get('message', '')}")

    print()
    print("  No DNS records were created, updated, or deleted.")
    print("  No Cloudflare API calls were made.")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mutation": False,
                  "dns_target_ready": False, "dual_stack": False,
                  "manual_input_required": True, "candidates": [], "checks": []}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK VPS IP Detection (read-only, fixture-first)"
    )
    sub = parser.add_subparsers(dest="command")

    detect_parser = sub.add_parser("detect", help="Detect and classify IP candidates")
    detect_parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.command != "detect":
        parser.print_help()
        sys.exit(1)

    fixture_path = os.environ.get("NANOBK_IP_DETECT_FIXTURE")

    try:
        result = run_detect(fixture_path)
    except RuntimeError as e:
        output_error(str(e), args.json)
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)


if __name__ == "__main__":
    main()
