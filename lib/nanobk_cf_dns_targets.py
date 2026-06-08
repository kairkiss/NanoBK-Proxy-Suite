#!/usr/bin/env python3
"""
NanoBK DNS Target Preview Skeleton

Preview-only DNS target for proxy.<zone> using fixture-backed IP candidates.
Read-only. No DNS profile writes. No Cloudflare calls. No mutation.

Usage:
    python3 lib/nanobk_cf_dns_targets.py preview --zone DOMAIN [--node NODE] --ip-fixture PATH [--json]
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nanobk_ip_detect import run_detect, mask_ipv4, mask_ipv6


# ── Validation ──────────────────────────────────────────────────────────────

_DNS_LABEL_RE = re.compile(r"^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$")


def validate_zone(zone):
    """Validate zone/domain. Returns error string or None.
    Does not echo raw zone in error messages."""
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
        return "zone must have at least two labels (e.g. example.com)"
    for label in labels:
        if not label:
            return "zone must not have empty labels"
        if not _DNS_LABEL_RE.match(label):
            return "invalid zone label"
    return None


def validate_node(node):
    """Validate node prefix. Returns error string or None.
    Does not echo raw node in error messages."""
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


# ── Masking ─────────────────────────────────────────────────────────────────

def mask_domain(name):
    """Mask domain: example.com -> ex***e.com"""
    if not name or "." not in name:
        return "***"
    parts = name.split(".", 1)
    prefix = parts[0]
    suffix = parts[1]
    if len(prefix) <= 2:
        return f"{prefix[0]}***.{suffix}"
    return f"{prefix[:2]}***{prefix[-1]}.{suffix}"


def mask_hostname(node, zone):
    """Mask full hostname: proxy.example.com -> proxy.ex***e.com"""
    return f"{node}.{mask_domain(zone)}"


# ── Preview logic ───────────────────────────────────────────────────────────

def run_preview(zone, node, ip_fixture_path):
    """Run DNS target preview. Returns result dict."""
    # Validate inputs
    zone_err = validate_zone(zone)
    if zone_err:
        return {"ok": False, "error": zone_err, "mutation": False,
                "profile_write": False, "target_ready": False}

    node_err = validate_node(node)
    if node_err:
        return {"ok": False, "error": node_err, "mutation": False,
                "profile_write": False, "target_ready": False}

    # Run IP detection from fixture
    try:
        ip_result = run_detect(ip_fixture_path)
    except RuntimeError as e:
        return {"ok": False, "error": str(e), "mutation": False,
                "profile_write": False, "target_ready": False}

    candidates = ip_result.get("candidates", [])
    dual_stack = ip_result.get("dual_stack", False)
    manual_required = ip_result.get("manual_input_required", True)

    # Build record preview from usable candidates
    record_preview = []
    ipv4_usable = [c for c in candidates if c["family"] == "ipv4" and c["usable_for_dns"]]
    ipv6_usable = [c for c in candidates if c["family"] == "ipv6" and c["usable_for_dns"]]

    # Multiple candidates of same family = can't auto-choose
    multiple_ipv4 = len(ipv4_usable) > 1
    multiple_ipv6 = len(ipv6_usable) > 1

    if len(ipv4_usable) == 1:
        record_preview.append({
            "type": "A",
            "value_redacted": ipv4_usable[0]["ip_redacted"],
            "source": ipv4_usable[0]["source"],
            "usable_for_dns": True,
        })
    elif multiple_ipv4:
        for c in ipv4_usable:
            record_preview.append({
                "type": "A",
                "value_redacted": c["ip_redacted"],
                "source": c["source"],
                "usable_for_dns": True,
                "note": "multiple candidates — manual selection required",
            })

    if len(ipv6_usable) == 1:
        record_preview.append({
            "type": "AAAA",
            "value_redacted": ipv6_usable[0]["ip_redacted"],
            "source": ipv6_usable[0]["source"],
            "usable_for_dns": True,
        })
    elif multiple_ipv6:
        for c in ipv6_usable:
            record_preview.append({
                "type": "AAAA",
                "value_redacted": c["ip_redacted"],
                "source": c["source"],
                "usable_for_dns": True,
                "note": "multiple candidates — manual selection required",
            })

    # Compute target readiness
    has_usable = len(ipv4_usable) > 0 or len(ipv6_usable) > 0
    no_conflict = not multiple_ipv4 and not multiple_ipv6
    target_ready = has_usable and no_conflict and not manual_required

    # Stack mode
    has_ipv4 = len(ipv4_usable) == 1
    has_ipv6 = len(ipv6_usable) == 1
    if has_ipv4 and has_ipv6:
        stack_mode = "dual_stack"
    elif has_ipv4:
        stack_mode = "ipv4_only"
    elif has_ipv6:
        stack_mode = "ipv6_only"
    else:
        stack_mode = "none"

    # Build checks
    checks = []
    if not has_usable:
        checks.append({"name": "ip_candidates", "status": "failed",
                        "message": "no usable IP candidates"})
    elif multiple_ipv4 or multiple_ipv6:
        checks.append({"name": "ip_candidates", "status": "manual_pending",
                        "message": "multiple candidates — manual selection required"})
    else:
        checks.append({"name": "ip_candidates", "status": "ok"})

    if not has_ipv4 and has_ipv6:
        checks.append({"name": "ipv4_available", "status": "warning",
                        "message": "no IPv4 candidate — IPv6-only deployment"})
    elif not has_ipv4:
        checks.append({"name": "ipv4_available", "status": "failed",
                        "message": "no IPv4 candidate"})

    if not has_ipv6 and has_ipv4:
        checks.append({"name": "ipv6_available", "status": "skipped",
                        "message": "no IPv6 candidate — IPv4-only deployment"})
    elif not has_ipv6:
        checks.append({"name": "ipv6_available", "status": "skipped",
                        "message": "no IPv6 candidate"})

    return {
        "ok": True,
        "mutation": False,
        "profile_write": False,
        "target_ready": target_ready,
        "zone_redacted": mask_domain(zone),
        "node": node,
        "hostname_redacted": mask_hostname(node, zone),
        "stack_mode": stack_mode,
        "dual_stack": dual_stack and has_ipv4 and has_ipv6,
        "manual_input_required": not target_ready,
        "record_preview": record_preview,
        "checks": checks,
    }


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable preview."""
    print()
    print("  NanoBK DNS target preview")
    print()

    # Target hostname
    print("  Target hostname:")
    print(f"    {result.get('hostname_redacted', '***')}")
    print()

    # Record preview
    records = result.get("record_preview", [])
    print("  Record preview:")
    if records:
        for rec in records:
            rtype = rec.get("type", "?")
            val = rec.get("value_redacted", "***")
            note = rec.get("note", "")
            line = f"    {rtype:6s} {val}"
            if note:
                line += f"  ({note})"
            print(line)
    else:
        print("    (no usable records)")

    # Readiness
    print()
    print("  Readiness:")
    print(f"    target_ready: {str(result.get('target_ready', False)).lower()}")
    print(f"    dual_stack: {str(result.get('dual_stack', False)).lower()}")
    print(f"    manual_input_required: {str(result.get('manual_input_required', True)).lower()}")
    print(f"    profile_write: false")
    print(f"    mutation: false")

    # Footer
    print()
    print("  No DNS profile was written.")
    print("  No DNS records were created, updated, or deleted.")
    print("  No Cloudflare API calls were made.")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mutation": False,
                  "profile_write": False, "target_ready": False}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK DNS Target Preview (read-only, preview-only)"
    )
    parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    parser.add_argument("--node", default="proxy", help="Node prefix (default: proxy)")
    parser.add_argument("--ip-fixture", help="Path to IP fixture JSON")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    # Manual required-field validation (clean JSON errors in --json mode)
    if not args.zone:
        output_error("zone is required", args.json)
        sys.exit(1)
    if not args.ip_fixture:
        output_error("ip fixture is required", args.json)
        sys.exit(1)

    result = run_preview(args.zone, args.node, args.ip_fixture)

    if not result.get("ok", False):
        output_error(result.get("error", "unknown error"), args.json)
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)


if __name__ == "__main__":
    main()
