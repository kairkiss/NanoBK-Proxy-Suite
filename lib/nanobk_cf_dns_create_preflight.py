#!/usr/bin/env python3
"""
NanoBK Controlled Proxy DNS Create Preflight (plan-only, no mutation)

Wraps the plan generator and adds create-preflight semantics.
Default: mutation_allowed=false, apply_ready=false, preflight_only=true.

Usage:
    python3 lib/nanobk_cf_dns_create_preflight.py preflight --zone DOMAIN --api-env PATH [--json]

Test hooks: same as plan generator (NANOBK_TEST_*, NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP).
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cf_dns_plan_generator import generate_plan


# ── Preflight logic ─────────────────────────────────────────────────────────

def run_preflight(zone, nodes_str, api_env_path):
    """Run create-preflight. Wraps plan generator, never mutates DNS."""
    plan = generate_plan(zone, nodes_str, api_env_path)

    if not plan.get("ok", False):
        return {
            "ok": False,
            "error": plan.get("error", "plan generation failed"),
            "preflight_status": "blocked",
            "mutation_allowed": False,
            "apply_ready": False,
            "preflight_only": True,
        }

    plan_status = plan.get("plan_status", "unknown")
    nodes = plan.get("nodes", [])

    # Derive preflight status from plan
    if plan_status == "ready":
        preflight_status = "ready_for_owner_review"
        execution_gate = "requires_owner_approval"
    elif plan_status == "blocked":
        preflight_status = "blocked"
        execution_gate = "blocked_by_plan"
    else:
        preflight_status = "incomplete"
        execution_gate = "incomplete_plan"

    # Build create candidates (what WOULD be created, not what WILL be created)
    create_candidates = []
    for n in nodes:
        node = n.get("node", "")
        hostname = n.get("hostname_redacted", f"{node}.*")
        node_plan = n.get("plan_status", "unknown")
        a_rec = n.get("a_record", "unknown")
        aaaa_rec = n.get("aaaa_record", "unknown")

        would_create = []
        if a_rec == "ready":
            would_create.append("A")
        if aaaa_rec == "ready":
            would_create.append("AAAA")

        create_candidates.append({
            "node": node,
            "hostname_redacted": hostname,
            "would_create": would_create,
            "blocked": node_plan == "blocked",
        })

    return {
        "ok": True,
        "preflight_status": preflight_status,
        "execution_gate": execution_gate,
        "mutation_allowed": False,
        "apply_ready": False,
        "preflight_only": True,
        "dns_changed": False,
        "records_created": False,
        "records_modified": False,
        "records_deleted": False,
        "overwrite_existing": False,
        "force": False,
        "plan_status": plan_status,
        "zone_redacted": plan.get("zone_redacted", "***"),
        "ip_detection": plan.get("ip_detection", {}),
        "create_candidates": create_candidates,
        "all_available": plan.get("all_available", False),
        "any_conflict": plan.get("any_conflict", False),
        "requires_owner_approval": True,
        "requires_disposable_first": True,
        "requires_post_check": True,
        "requires_cleanup_or_rollback_plan": True,
        "safety": {
            "preflight_only": True,
            "mutation_allowed": False,
            "apply_ready": False,
            "dns_changed": False,
            "records_created": False,
            "records_modified": False,
            "records_deleted": False,
            "overwrite_existing": False,
            "force": False,
            "cloudflare_touched": "read_only",
        },
    }


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable preflight report."""
    ip = result.get("ip_detection", {})
    ipv4 = ip.get("ipv4", {})
    ipv6 = ip.get("ipv6", {})
    candidates = result.get("create_candidates", [])

    print()
    print("  NanoBK Controlled Proxy DNS Create Preflight")
    print()
    print(f"  Zone: {result.get('zone_redacted', '***')}")
    print()
    print(f"  Preflight status: {result.get('preflight_status', 'unknown')}")
    print(f"  Execution gate: {result.get('execution_gate', 'unknown')}")
    print()
    print("  IP detection:")
    print(f"    IPv4: {ipv4.get('status', 'not_detected')}")
    print(f"    IPv6: {ipv6.get('status', 'not_detected')}")
    print()
    print("  Create candidates:")
    for c in candidates:
        hostname = c.get("hostname_redacted", "***")
        would = c.get("would_create", [])
        blocked = c.get("blocked", False)
        if blocked:
            print(f"    {hostname}: blocked")
        elif would:
            types = ", ".join(would)
            print(f"    {hostname}: A would create [{types}]")
        else:
            print(f"    {hostname}: nothing to create")
    print()
    print("  Requirements:")
    print(f"    requires_owner_approval: {str(result.get('requires_owner_approval', True)).lower()}")
    print(f"    requires_disposable_first: {str(result.get('requires_disposable_first', True)).lower()}")
    print(f"    requires_post_check: {str(result.get('requires_post_check', True)).lower()}")
    print(f"    requires_cleanup_or_rollback_plan: {str(result.get('requires_cleanup_or_rollback_plan', True)).lower()}")
    print()
    print("  Safety:")
    safety = result.get("safety", {})
    print(f"    Preflight-only: {str(safety.get('preflight_only', True)).lower()}")
    print(f"    Mutation allowed: {str(safety.get('mutation_allowed', False)).lower()}")
    print(f"    Apply ready: {str(safety.get('apply_ready', False)).lower()}")
    print(f"    DNS changed: {str(safety.get('dns_changed', False)).lower()}")
    print(f"    Records created: {str(safety.get('records_created', False)).lower()}")
    print(f"    Overwrite existing: {str(safety.get('overwrite_existing', False)).lower()}")
    print(f"    Force: {str(safety.get('force', False)).lower()}")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "preflight_status": "blocked",
                  "mutation_allowed": False, "apply_ready": False, "preflight_only": True}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Controlled DNS Create Preflight (plan-only, no mutation)"
    )
    sub = parser.add_subparsers(dest="command")

    pf_parser = sub.add_parser("preflight", help="Run create preflight")
    pf_parser.add_argument("--zone", help="Domain zone (e.g. example.com)")
    pf_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    pf_parser.add_argument("--nodes", default="proxy,web",
                           help="Comma-separated node labels (default: proxy,web)")
    pf_parser.add_argument("--json", action="store_true", help="JSON output")

    # Reject dangerous flags
    pf_parser.add_argument("--apply", action="store_true", help=argparse.SUPPRESS)
    pf_parser.add_argument("--yes", action="store_true", help=argparse.SUPPRESS)
    pf_parser.add_argument("--force", action="store_true", help=argparse.SUPPRESS)
    pf_parser.add_argument("--overwrite", action="store_true", help=argparse.SUPPRESS)

    args = parser.parse_args()

    if args.command != "preflight":
        parser.print_help()
        sys.exit(1)

    # Reject dangerous flags
    for flag in ("apply", "yes", "force", "overwrite"):
        if getattr(args, flag, False):
            output_error(f"--{flag} is not allowed in preflight mode", args.json)
            sys.exit(1)

    if not args.zone:
        output_error("zone is required", args.json)
        sys.exit(1)
    if not args.api_env:
        output_error("api-env is required", args.json)
        sys.exit(1)

    result = run_preflight(args.zone, args.nodes, args.api_env)

    if not result.get("ok", False):
        output_error(result.get("error", "preflight failed"), args.json)
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)


if __name__ == "__main__":
    main()
