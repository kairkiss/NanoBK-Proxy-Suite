#!/usr/bin/env python3
"""
NanoBK Combined DNS Preparation Report

Report-only composition of DNS target preview and multi-host availability summary.
Read-only. No DNS profile writes. No Cloudflare mutation. No DNS mutation.

Usage:
    python3 lib/nanobk_cf_dns_report.py --zone DOMAIN --api-env PATH --ip-fixture PATH [--nodes proxy,web] [--json]
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nanobk_cf_dns_targets import run_preview, mask_domain, validate_zone, validate_node
from nanobk_cf_dns_availability import run_summary, parse_nodes


# ── Error output ────────────────────────────────────────────────────────────

def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mutation": False,
                  "profile_write": False, "ready_for_profile_generation": False,
                  "manual_review_required": True}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Report logic ────────────────────────────────────────────────────────────

def compute_ready(target_result, summary_result):
    """Compute ready_for_profile_generation conservatively."""
    # Target must be ready
    if not target_result.get("ok", False):
        return False
    if not target_result.get("target_ready", False):
        return False

    # Summary must be ok
    if not summary_result.get("ok", False):
        return False
    if summary_result.get("manual_review_required", True):
        return False

    # Overall status must be acceptable
    overall = summary_result.get("overall_status", "unknown")
    if overall not in ("available", "partially_owned"):
        return False

    # Every host must be available or nanobk_owned
    hosts = summary_result.get("hosts", [])
    for host in hosts:
        status = host.get("status", "unknown")
        if status not in ("available", "nanobk_owned"):
            return False

    return True


def run_report(zone, api_env_path, ip_fixture_path, nodes):
    """Run combined DNS preparation report."""
    # Validate zone
    zone_err = validate_zone(zone)
    if zone_err:
        return {"ok": False, "error": zone_err, "mutation": False,
                "profile_write": False, "ready_for_profile_generation": False,
                "manual_review_required": True}

    # Run target preview for proxy
    target_result = run_preview(zone, "proxy", ip_fixture_path)
    if not target_result.get("ok", False):
        return {"ok": False, "error": target_result.get("error", "target preview failed"),
                "mutation": False, "profile_write": False,
                "ready_for_profile_generation": False, "manual_review_required": True}

    # Run availability summary for all nodes
    summary_result = run_summary(zone, nodes, api_env_path)
    if not summary_result.get("ok", False):
        return {"ok": False, "error": summary_result.get("error", "availability summary failed"),
                "mutation": False, "profile_write": False,
                "ready_for_profile_generation": False, "manual_review_required": True}

    # Compute readiness
    ready = compute_ready(target_result, summary_result)

    # Build report
    # Strip internal fields from target_preview
    target_preview = {
        "node": target_result.get("node", "proxy"),
        "hostname_redacted": target_result.get("hostname_redacted", "***"),
        "target_ready": target_result.get("target_ready", False),
        "stack_mode": target_result.get("stack_mode", "none"),
        "dual_stack": target_result.get("dual_stack", False),
        "record_preview": target_result.get("record_preview", []),
    }

    # Strip detailed records from availability hosts
    availability_hosts = []
    for host in summary_result.get("hosts", []):
        availability_hosts.append({
            "node": host.get("node", ""),
            "hostname_redacted": host.get("hostname_redacted", "***"),
            "status": host.get("status", "unknown"),
            "available": host.get("available", False),
            "records_found": host.get("records_found", 0),
            "manual_review_required": host.get("manual_review_required", True),
        })

    availability_summary = {
        "overall_status": summary_result.get("overall_status", "unknown"),
        "all_available": summary_result.get("all_available", False),
        "any_conflict": summary_result.get("any_conflict", False),
        "manual_review_required": summary_result.get("manual_review_required", True),
        "hosts": availability_hosts,
    }

    return {
        "ok": True,
        "mutation": False,
        "profile_write": False,
        "zone_redacted": mask_domain(zone),
        "ready_for_profile_generation": ready,
        "manual_review_required": not ready,
        "target_preview": target_preview,
        "availability_summary": availability_summary,
    }


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable report."""
    print()
    print("  NanoBK DNS preparation report")
    print()

    # Zone
    print("  Zone:")
    print(f"    {result.get('zone_redacted', '***')}")
    print()

    # Target preview
    tp = result.get("target_preview", {})
    print("  Target preview:")
    print(f"    {tp.get('hostname_redacted', '***')}")
    for rec in tp.get("record_preview", []):
        rtype = rec.get("type", "?")
        val = rec.get("value_redacted", "***")
        print(f"    {rtype:6s} {val}")
    print()

    # Availability
    avail = result.get("availability_summary", {})
    hosts = avail.get("hosts", [])
    if hosts:
        print("  Availability:")
        for h in hosts:
            hostname = h.get("hostname_redacted", "***")
            status = h.get("status", "unknown")
            print(f"    {hostname:30s} {status}")
        print()

    # Overall
    print("  Overall:")
    print(f"    ready_for_profile_generation: {str(result.get('ready_for_profile_generation', False)).lower()}")
    print(f"    manual_review_required: {str(result.get('manual_review_required', True)).lower()}")
    print(f"    mutation: false")
    print(f"    profile_write: false")
    print()
    print("  No DNS profile was written.")
    print("  No DNS records were created, updated, or deleted.")
    print()


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Combined DNS Preparation Report (read-only, report-only)"
    )
    parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    parser.add_argument("--ip-fixture", help="Path to IP fixture JSON")
    parser.add_argument("--nodes", default="proxy,web", help="Comma-separated node labels (default: proxy,web)")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    # Manual required-field validation
    if not args.zone:
        output_error("zone is required", args.json)
        sys.exit(1)
    if not args.api_env:
        output_error("api-env is required", args.json)
        sys.exit(1)
    if not args.ip_fixture:
        output_error("ip-fixture is required", args.json)
        sys.exit(1)

    # Parse nodes
    nodes = [n.strip() for n in args.nodes.split(",") if n.strip()]
    if not nodes:
        output_error("no valid nodes provided", args.json)
        sys.exit(1)

    # Validate nodes
    for node in nodes:
        err = validate_node(node)
        if err:
            output_error(err, args.json)
            sys.exit(1)

    # Check duplicates
    if len(nodes) != len(set(nodes)):
        output_error("duplicate nodes are not allowed", args.json)
        sys.exit(1)

    result = run_report(args.zone, args.api_env, args.ip_fixture, nodes)

    if not result.get("ok", False):
        output_error(result.get("error", "unknown error"), args.json)
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)


if __name__ == "__main__":
    main()
