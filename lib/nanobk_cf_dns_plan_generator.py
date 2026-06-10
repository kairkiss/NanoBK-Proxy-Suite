#!/usr/bin/env python3
"""
NanoBK Proxy DNS Plan Generator (plan-only, no mutation)

Combines VPS IP detection + subdomain availability check into a DNS plan summary.
Read-only. No DNS mutation. No Cloudflare POST/PATCH/DELETE.

Usage:
    python3 lib/nanobk_cf_dns_plan_generator.py generate --zone DOMAIN --api-env PATH [--json]

Test hooks:
    NANOBK_TEST_DETECTED_IPV4=203.0.113.10
    NANOBK_TEST_DETECTED_IPV6=2001:db8::10
    NANOBK_TEST_DETECT_IPV4_FAIL=1
    NANOBK_TEST_DETECT_IPV6_FAIL=1
    NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL=1
    NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL=1
    NANOBK_TEST_LOCAL_IPV4=203.0.113.20
    NANOBK_TEST_LOCAL_IPV6=2001:db8::20
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP=/path/to/map.json
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_ip_detect import run_detect
from nanobk_cf_dns_availability import (
    validate_zone, validate_env_for_summary, run_summary, parse_nodes
)


# ── Plan generation ─────────────────────────────────────────────────────────

def generate_plan(zone, nodes_str, api_env_path):
    """Generate a DNS plan combining IP detection and availability check.

    Returns result dict. Never mutates DNS.
    """
    # Validate zone
    zone_err = validate_zone(zone)
    if zone_err:
        return {"ok": False, "error": zone_err, "plan_status": "blocked",
                "mutation": False}

    # Parse nodes
    nodes_list, nodes_err = parse_nodes(nodes_str)
    if nodes_err:
        return {"ok": False, "error": nodes_err, "plan_status": "blocked",
                "mutation": False}

    # Step 1: IP detection
    try:
        ip_result = run_detect()
    except Exception as e:
        return {"ok": False, "error": f"IP detection failed: {e}",
                "plan_status": "blocked", "mutation": False}

    ipv4 = ip_result.get("ipv4", {})
    ipv6 = ip_result.get("ipv6", {})
    ipv4_detected = ipv4.get("status") == "detected"
    ipv6_detected = ipv6.get("status") == "detected"

    # Step 2: Subdomain availability
    try:
        avail_result = run_summary(zone, nodes_list, api_env_path)
    except Exception as e:
        return {"ok": False, "error": f"Availability check failed: {e}",
                "plan_status": "blocked", "mutation": False}

    if not avail_result.get("ok", False):
        return {"ok": False, "error": avail_result.get("error", "availability check failed"),
                "plan_status": "blocked", "mutation": False}

    # Step 3: Combine into plan
    hosts = avail_result.get("hosts", [])
    all_available = avail_result.get("all_available", False)
    any_conflict = avail_result.get("any_conflict", False)

    # Build per-node plan entries
    plan_nodes = []
    for h in hosts:
        node = h.get("node", "")
        hostname = h.get("hostname_redacted", f"{node}.*")
        avail_status = h.get("status", "unknown")

        if avail_status == "available" and ipv4_detected and ipv6_detected:
            node_plan = "ready"
            a_status = "ready"
            aaaa_status = "ready"
        elif avail_status == "available" and ipv4_detected:
            node_plan = "ready"
            a_status = "ready"
            aaaa_status = "skipped"
        elif avail_status == "available" and ipv6_detected:
            node_plan = "ready"
            a_status = "skipped"
            aaaa_status = "ready"
        elif avail_status == "available" and not ipv4_detected and not ipv6_detected:
            node_plan = "blocked"
            a_status = "skipped"
            aaaa_status = "skipped"
        elif avail_status in ("conflict", "manual_review", "nanobk_owned"):
            node_plan = "blocked"
            a_status = "blocked"
            aaaa_status = "blocked"
        else:
            node_plan = "unknown"
            a_status = "unknown"
            aaaa_status = "unknown"

        plan_nodes.append({
            "node": node,
            "hostname_redacted": hostname,
            "availability": avail_status,
            "plan_status": node_plan,
            "a_record": a_status,
            "aaaa_record": aaaa_status,
            "records_found": h.get("records_found", 0),
        })

    # Overall plan status
    any_blocked = any(n["plan_status"] == "blocked" for n in plan_nodes)
    any_unknown = any(n["plan_status"] == "unknown" for n in plan_nodes)
    all_ready = all(n["plan_status"] == "ready" for n in plan_nodes)

    if all_ready:
        overall_plan = "ready"
    elif any_blocked:
        overall_plan = "blocked"
    elif any_unknown:
        overall_plan = "incomplete"
    else:
        overall_plan = "incomplete"

    return {
        "ok": True,
        "mutation": False,
        "plan_status": overall_plan,
        "zone_redacted": avail_result.get("zone_redacted", "***"),
        "all_available": all_available,
        "any_conflict": any_conflict,
        "ip_detection": {
            "ipv4": {
                "status": ipv4.get("status", "not_detected"),
                "address": ipv4.get("address"),
                "scope": ipv4.get("scope"),
            },
            "ipv6": {
                "status": ipv6.get("status", "not_detected"),
                "address": ipv6.get("address"),
                "scope": ipv6.get("scope"),
            },
        },
        "nodes": plan_nodes,
        "safety": {
            "plan_only": True,
            "dns_changed": False,
            "cloudflare_touched": "read_only",
            "mutation_allowed": False,
        },
    }


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable plan summary."""
    ip = result.get("ip_detection", {})
    ipv4 = ip.get("ipv4", {})
    ipv6 = ip.get("ipv6", {})
    nodes = result.get("nodes", [])

    print()
    print("  NanoBK Proxy DNS Plan")
    print()
    print(f"  Zone: {result.get('zone_redacted', '***')}")
    print()
    print("  IP detection:")
    print(f"    IPv4: {ipv4.get('status', 'not_detected')}")
    print(f"    IPv6: {ipv6.get('status', 'not_detected')}")
    print()
    print("  Subdomains:")
    for n in nodes:
        hostname = n.get("hostname_redacted", "***")
        avail = n.get("availability", "unknown")
        plan = n.get("plan_status", "unknown")
        a_rec = n.get("a_record", "unknown")
        aaaa_rec = n.get("aaaa_record", "unknown")
        print(f"    {hostname}:")
        print(f"      availability: {avail}")
        print(f"      plan: {plan}")
        print(f"      A record: {a_rec}")
        print(f"      AAAA record: {aaaa_rec}")
    print()
    print(f"  Overall plan: {result.get('plan_status', 'unknown')}")
    print()
    print("  Safety:")
    safety = result.get("safety", {})
    print(f"    Plan-only: {str(safety.get('plan_only', True)).lower()}")
    print(f"    DNS changed: {str(safety.get('dns_changed', False)).lower()}")
    print(f"    Cloudflare touched: {safety.get('cloudflare_touched', 'read_only')}")
    print(f"    Mutation allowed: {str(safety.get('mutation_allowed', False)).lower()}")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "plan_status": "blocked",
                  "mutation": False}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Proxy DNS Plan Generator (plan-only, no mutation)"
    )
    sub = parser.add_subparsers(dest="command")

    gen_parser = sub.add_parser("generate", help="Generate DNS plan")
    gen_parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    gen_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    gen_parser.add_argument("--nodes", default="proxy,web",
                            help="Comma-separated node labels (default: proxy,web)")
    gen_parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.command != "generate":
        parser.print_help()
        sys.exit(1)

    if not args.zone:
        output_error("zone is required", args.json)
        sys.exit(1)
    if not args.api_env:
        output_error("api-env is required", args.json)
        sys.exit(1)

    result = generate_plan(args.zone, args.nodes, args.api_env)

    if not result.get("ok", False):
        output_error(result.get("error", "plan generation failed"), args.json)
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)


if __name__ == "__main__":
    main()
