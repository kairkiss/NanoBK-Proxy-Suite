#!/usr/bin/env python3
"""
NanoBK DNS Profile Preview

Preview-only: builds and validates an in-memory DNS profile candidate.
No file writes. No Cloudflare calls. No DNS apply/check. No DNS mutation.

Usage:
    python3 lib/nanobk_cf_dns_profile.py preview --zone DOMAIN --node NODE --ipv4 VALUE [--ipv6 VALUE] [--json] [--allow-documentation-ips]
"""

import argparse
import ipaddress
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nanobk_cf_dns_targets import mask_domain


# ── Constants ───────────────────────────────────────────────────────────────

_DNS_LABEL_RE = re.compile(r"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$")

_IPV4_DOC_RANGES = [
    ipaddress.IPv4Network("192.0.2.0/24"),
    ipaddress.IPv4Network("198.51.100.0/24"),
    ipaddress.IPv4Network("203.0.113.0/24"),
]

_IPV6_DOC_RANGES = [
    ipaddress.IPv6Network("2001:db8::/32"),
]

_SECRET_SUBSTRINGS = ["token", "secret", "private", "password", "key", "cf_api_token"]
_ALLOWED_KEYS = {"zoneId"}


# ── Validation ──────────────────────────────────────────────────────────────

def validate_zone(zone):
    """Validate zone/domain. Returns error string or None."""
    if not zone:
        return "zone is required"
    if "://" in zone:
        return "zone must be a domain name, not a URL"
    if "/" in zone:
        return "zone must not contain slashes"
    if " " in zone:
        return "zone must not contain spaces"
    if "*" in zone:
        return "zone must not contain wildcards"
    if len(zone) > 253:
        return "zone is too long"
    labels = zone.split(".")
    if len(labels) < 2:
        return "zone must have at least two labels"
    for label in labels:
        if not label:
            return "zone must not have empty labels"
        if not _DNS_LABEL_RE.match(label):
            return "invalid zone label"
    return None


def validate_node(node):
    """Validate node prefix. Returns error string or None."""
    if not node:
        return "node is required"
    if "/" in node:
        return "node must not contain slashes"
    if " " in node:
        return "node must not contain spaces"
    if "*" in node:
        return "node must not contain wildcards"
    if "." in node:
        return "node must be a single label (no dots)"
    if len(node) > 63:
        return "node is too long"
    if not _DNS_LABEL_RE.match(node):
        return "invalid node label"
    return None


def validate_ipv4(addr, allow_docs=False):
    """Validate IPv4 address. Returns error string or None."""
    if not addr:
        return "ipv4 is required"
    try:
        parsed = ipaddress.IPv4Address(addr)
    except (ipaddress.AddressValueError, ValueError):
        return "invalid IPv4"
    if parsed.is_loopback:
        return "loopback IPv4 is not allowed"
    if parsed.is_multicast:
        return "multicast IPv4 is not allowed"
    if parsed.is_reserved:
        return "reserved IPv4 is not allowed"
    if parsed.is_link_local:
        return "link-local IPv4 is not allowed"
    if parsed.is_unspecified:
        return "unspecified IPv4 is not allowed"
    # Check documentation ranges
    for net in _IPV4_DOC_RANGES:
        if parsed in net:
            if not allow_docs:
                return "documentation IPv4 is allowed only in test mode (--allow-documentation-ips)"
            return None
    # Check private
    if parsed.is_private:
        return "private IPv4 is not allowed"
    return None


def validate_ipv6(addr, allow_docs=False):
    """Validate IPv6 address. Returns error string or None."""
    if not addr:
        return None  # IPv6 is optional
    try:
        parsed = ipaddress.IPv6Address(addr)
    except (ipaddress.AddressValueError, ValueError):
        return "invalid IPv6"
    if parsed.is_loopback:
        return "loopback IPv6 is not allowed"
    if parsed.is_multicast:
        return "multicast IPv6 is not allowed"
    if parsed.is_reserved:
        return "reserved IPv6 is not allowed"
    if parsed.is_link_local:
        return "link-local IPv6 is not allowed"
    if parsed.is_unspecified:
        return "unspecified IPv6 is not allowed"
    # Check documentation ranges
    for net in _IPV6_DOC_RANGES:
        if parsed in net:
            if not allow_docs:
                return "documentation IPv6 is allowed only in test mode (--allow-documentation-ips)"
            return None
    # Check ULA / private
    if parsed.is_private:
        return "private IPv6 is not allowed"
    return None


def mask_ipv4(addr):
    """Mask IPv4: 203.0.113.10 -> 203.0.113.xxx"""
    parts = addr.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.{parts[2]}.xxx"
    return "xxx.xxx.xxx.xxx"


def mask_ipv6(addr):
    """Mask IPv6: 2001:db8::10 -> 2001:db8:…"""
    try:
        parsed = ipaddress.IPv6Address(addr)
        compressed = parsed.compressed
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


def mask_hostname(node, zone):
    """Mask full hostname: proxy.example.com -> proxy.ex***e.com"""
    return f"{node}.{mask_domain(zone)}"


# ── Profile preview logic ───────────────────────────────────────────────────

def build_profile_candidate(zone, node, ipv4, ipv6=None):
    """Build an in-memory profile candidate dict."""
    candidate = {
        "zoneName": zone,
        "nodePrefix": node,
        "defaultProxied": False,
        "reserved": {
            "panelPrefix": "panel",
            "nanokPrefix": "nanok",
            "nanobPrefix": "nanob",
        },
    }
    if ipv4:
        candidate["ipv4"] = ipv4
    if ipv6:
        candidate["ipv6"] = ipv6
    return candidate


def validate_profile_candidate(candidate, allow_docs=False):
    """Validate profile candidate. Returns (ok, errors_list)."""
    errors = []

    zone = candidate.get("zoneName", "")
    zone_err = validate_zone(zone)
    if zone_err:
        errors.append(zone_err)

    node = candidate.get("nodePrefix", "")
    node_err = validate_node(node)
    if node_err:
        errors.append(node_err)

    ipv4 = candidate.get("ipv4")
    ipv6 = candidate.get("ipv6")

    if not ipv4 and not ipv6:
        errors.append("at least one of ipv4 or ipv6 is required")
    else:
        if ipv4:
            ipv4_err = validate_ipv4(ipv4, allow_docs)
            if ipv4_err:
                errors.append(ipv4_err)
        if ipv6:
            ipv6_err = validate_ipv6(ipv6, allow_docs)
            if ipv6_err:
                errors.append(ipv6_err)

    proxied = candidate.get("defaultProxied")
    if proxied is not None and proxied is not False:
        errors.append("defaultProxied must be false or omitted")

    # Check for secret-like keys
    for key in candidate:
        key_lower = key.lower()
        for secret in _SECRET_SUBSTRINGS:
            if secret in key_lower and key not in _ALLOWED_KEYS:
                errors.append(f"secret-like field rejected: {key}")
                break

    return len(errors) == 0, errors


def run_preview(zone, node, ipv4, ipv6, allow_docs):
    """Run profile preview. Returns result dict."""
    # Validate inputs
    zone_err = validate_zone(zone)
    if zone_err:
        return {"ok": False, "error": zone_err, "mutation": False,
                "profile_written": False, "profile_write_mode": "preview",
                "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}

    node_err = validate_node(node)
    if node_err:
        return {"ok": False, "error": node_err, "mutation": False,
                "profile_written": False, "profile_write_mode": "preview",
                "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}

    if not ipv4:
        return {"ok": False, "error": "ipv4 is required", "mutation": False,
                "profile_written": False, "profile_write_mode": "preview",
                "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}

    # Validate IPs
    ipv4_err = validate_ipv4(ipv4, allow_docs)
    if ipv4_err:
        return {"ok": False, "error": ipv4_err, "mutation": False,
                "profile_written": False, "profile_write_mode": "preview",
                "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}

    if ipv6:
        ipv6_err = validate_ipv6(ipv6, allow_docs)
        if ipv6_err:
            return {"ok": False, "error": ipv6_err, "mutation": False,
                    "profile_written": False, "profile_write_mode": "preview",
                    "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}

    # Build candidate
    candidate = build_profile_candidate(zone, node, ipv4, ipv6)

    # Validate candidate
    valid, errors = validate_profile_candidate(candidate, allow_docs)

    # Build record preview
    record_preview = []
    if ipv4:
        record_preview.append({
            "type": "A",
            "value_redacted": mask_ipv4(ipv4),
            "proxied": False,
        })
    if ipv6:
        record_preview.append({
            "type": "AAAA",
            "value_redacted": mask_ipv6(ipv6),
            "proxied": False,
        })

    # Build IP preview
    ip_preview = {}
    if ipv4:
        ip_preview["ipv4_redacted"] = mask_ipv4(ipv4)
    if ipv6:
        ip_preview["ipv6_redacted"] = mask_ipv6(ipv6)

    return {
        "ok": True,
        "mutation": False,
        "profile_written": False,
        "profile_write_mode": "preview",
        "dns_mutation": False,
        "cloudflare_mutation": False,
        "dns_apply": False,
        "zone_redacted": mask_domain(zone),
        "node": node,
        "hostname_redacted": mask_hostname(node, zone),
        "ip_preview": ip_preview,
        "profile_valid": valid,
        "validation_status": "passed" if valid else "failed",
        "validation_errors": errors if errors else [],
        "record_preview": record_preview,
        "test_mode": allow_docs,
    }


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable preview."""
    print()
    print("  NanoBK DNS profile preview")
    print()

    print("  Target:")
    print(f"    {result.get('hostname_redacted', '***')}")
    print()

    print("  Profile:")
    zone_r = result.get("zone_redacted", "***")
    node = result.get("node", "***")
    ip_preview = result.get("ip_preview", {})
    ipv4_r = ip_preview.get("ipv4_redacted", "not set")
    ipv6_r = ip_preview.get("ipv6_redacted", "not set")
    print(f"    zone: {zone_r}")
    print(f"    node: {node}")
    print(f"    ipv4: {ipv4_r}")
    print(f"    ipv6: {ipv6_r}")
    print()

    print("  Validation:")
    print(f"    profile_valid: {str(result.get('profile_valid', False)).lower()}")
    print(f"    validation_status: {result.get('validation_status', 'unknown')}")
    if result.get("test_mode"):
        print(f"    test_mode: true")
    print()

    print("  Safety:")
    print(f"    profile_written: false")
    print(f"    profile_write_mode: preview")
    print(f"    dns_mutation: false")
    print(f"    cloudflare_mutation: false")
    print(f"    dns_apply: false")
    print()

    # Record preview
    records = result.get("record_preview", [])
    if records:
        print("  Record preview:")
        for rec in records:
            rtype = rec.get("type", "?")
            val = rec.get("value_redacted", "***")
            proxied = rec.get("proxied", False)
            print(f"    {rtype:6s} {val}  proxied={str(proxied).lower()}")
        print()

    print("  No DNS profile was written.")
    print("  No DNS records were created, updated, or deleted.")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mutation": False,
                  "profile_written": False, "profile_write_mode": "preview",
                  "dns_mutation": False, "cloudflare_mutation": False, "dns_apply": False}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK DNS Profile Preview (preview-only, no file write)"
    )
    parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    parser.add_argument("--node", help="Node prefix (e.g. proxy)")
    parser.add_argument("--ipv4", help="IPv4 address for A record")
    parser.add_argument("--ipv6", help="IPv6 address for AAAA record (optional)")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--allow-documentation-ips", action="store_true",
                        help="Allow documentation IP ranges (tests/examples only)")
    args = parser.parse_args()

    # Manual required-field validation (clean JSON errors)
    if not args.zone:
        output_error("zone is required", args.json)
        sys.exit(1)
    if not args.node:
        output_error("node is required", args.json)
        sys.exit(1)
    if not args.ipv4:
        output_error("ipv4 is required", args.json)
        sys.exit(1)

    result = run_preview(args.zone, args.node, args.ipv4, args.ipv6,
                         args.allow_documentation_ips)

    if not result.get("ok", False):
        output_error(result.get("error", "unknown error"), args.json)
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)


if __name__ == "__main__":
    main()
