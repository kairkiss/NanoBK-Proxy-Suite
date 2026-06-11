#!/usr/bin/env python3
"""
NanoBK Beginner DNS Setup Assistant

Combines VPS IP detection, subdomain availability, DNS plan generation,
and create-preflight into one beginner-friendly summary.
Assistant-only. Plan-only. No Cloudflare mutation.

Usage:
    python3 lib/nanobk_dns_setup_assistant.py setup --zone DOMAIN --api-env PATH [--nodes proxy,web] [--json]

Test hooks:
    NANOBK_TEST_DETECTED_IPV4=203.0.113.10
    NANOBK_TEST_DETECTED_IPV6=2001:db8::10
    NANOBK_TEST_DETECT_IPV4_FAIL=1
    NANOBK_TEST_DETECT_IPV6_FAIL=1
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP=/path/to/map.json
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_ip_detect import run_detect
from nanobk_cf_dns_availability import (
    validate_zone,
    validate_env_for_summary,
    run_summary,
    parse_nodes,
)
from nanobk_cf_dns_plan_generator import generate_plan
from nanobk_cf_dns_create_preflight import run_preflight
from nanobk_setup_profile import load_profile
from nanobk_setup_explain import explain_setup_result, format_explanation_text


# ── Safety constants ────────────────────────────────────────────────────────

_SAFETY = {
    "assistant_only": True,
    "plan_only": True,
    "dns_changed": False,
    "cloudflare_touched": "read_only",
    "records_created": False,
    "records_modified": False,
    "records_deleted": False,
    "production_apply_enabled": False,
    "bot_web_installer_enabled": False,
    "raw_api_response_printed": False,
}


def _safety():
    """Return a copy of the safety dict."""
    return dict(_SAFETY)


# ── Setup logic ─────────────────────────────────────────────────────────────

def run_setup(zone, api_env_path, nodes_str):
    """Run the beginner DNS setup assistant. Returns result dict."""

    # Validate zone
    zone_err = validate_zone(zone)
    if zone_err:
        return {
            "ok": False,
            "setup_status": "blocked_invalid_input",
            "error": zone_err,
            "safety": _safety(),
        }

    # Parse nodes
    nodes_list, nodes_err = parse_nodes(nodes_str)
    if nodes_err:
        return {
            "ok": False,
            "setup_status": "blocked_invalid_input",
            "error": nodes_err,
            "safety": _safety(),
        }

    # Validate credential
    try:
        env, env_err = validate_env_for_summary(api_env_path, zone)
        if env_err:
            return {
                "ok": False,
                "setup_status": "blocked_credential",
                "error": env_err,
                "safety": _safety(),
            }
    except Exception as e:
        return {
            "ok": False,
            "setup_status": "blocked_credential",
            "error": str(e),
            "safety": _safety(),
        }

    # Step 1: IP detection
    try:
        ip_result = run_detect()
    except Exception as e:
        return {
            "ok": False,
            "setup_status": "manual_review_required",
            "error": "IP detection failed: {}".format(e),
            "safety": _safety(),
        }

    ipv4 = ip_result.get("ipv4", {})
    ipv6 = ip_result.get("ipv6", {})
    ipv4_ok = ipv4.get("status") == "detected"
    ipv6_ok = ipv6.get("status") == "detected"

    if not ipv4_ok and not ipv6_ok:
        return {
            "ok": False,
            "setup_status": "incomplete_no_ip",
            "zone_name": zone,
            "nodes": [],
            "ip_detection": {
                "ipv4": {"status": ipv4.get("status", "not_detected")},
                "ipv6": {"status": ipv6.get("status", "not_detected")},
            },
            "preflight": {
                "status": "blocked",
                "mutation_allowed": False,
                "apply_ready": False,
            },
            "safety": _safety(),
        }

    # Step 2: Subdomain availability
    try:
        avail_result = run_summary(zone, nodes_list, api_env_path)
    except Exception as e:
        return {
            "ok": False,
            "setup_status": "manual_review_required",
            "error": "Availability check failed: {}".format(e),
            "safety": _safety(),
        }

    if not avail_result.get("ok", False):
        return {
            "ok": False,
            "setup_status": "manual_review_required",
            "error": avail_result.get("error", "availability check failed"),
            "safety": _safety(),
        }

    # Check for conflicts
    if avail_result.get("any_conflict", False):
        node_results = []
        for h in avail_result.get("hosts", []):
            node_results.append({
                "label": h.get("node", ""),
                "hostname": h.get("hostname_redacted", ""),
                "availability": h.get("status", "unknown"),
                "plan_status": "blocked",
                "a_record": "blocked",
                "aaaa_record": "blocked",
            })
        return {
            "ok": True,
            "setup_status": "blocked_subdomain_conflict",
            "zone_name": zone,
            "nodes": node_results,
            "ip_detection": {
                "ipv4": {"status": ipv4.get("status")},
                "ipv6": {"status": ipv6.get("status")},
            },
            "preflight": {
                "status": "blocked",
                "mutation_allowed": False,
                "apply_ready": False,
            },
            "safety": _safety(),
        }

    # Step 3: DNS plan
    try:
        plan_result = generate_plan(zone, nodes_str, api_env_path)
    except Exception as e:
        return {
            "ok": False,
            "setup_status": "manual_review_required",
            "error": "Plan generation failed: {}".format(e),
            "safety": _safety(),
        }

    if not plan_result.get("ok", False):
        return {
            "ok": False,
            "setup_status": "manual_review_required",
            "error": plan_result.get("error", "plan generation failed"),
            "safety": _safety(),
        }

    # Step 4: Create preflight
    try:
        preflight_result = run_preflight(zone, nodes_str, api_env_path)
    except Exception:
        preflight_result = {
            "preflight_status": "unknown",
            "mutation_allowed": False,
            "apply_ready": False,
        }

    # Build node results
    node_results = []
    for pn in plan_result.get("nodes", []):
        node_results.append({
            "label": pn.get("node", ""),
            "hostname": pn.get("hostname_redacted", ""),
            "availability": pn.get("availability", "unknown"),
            "plan_status": pn.get("plan_status", "unknown"),
            "a_record": pn.get("a_record", "unknown"),
            "aaaa_record": pn.get("aaaa_record", "unknown"),
        })

    # Determine setup status
    plan_status = plan_result.get("plan_status", "unknown")
    preflight_status = preflight_result.get("preflight_status", "unknown")

    if plan_status == "ready" and preflight_status == "ready_for_owner_review":
        setup_status = "ready_for_owner_review"
    elif plan_status == "blocked":
        setup_status = "blocked_subdomain_conflict"
    elif plan_status == "incomplete":
        setup_status = "incomplete_no_ip"
    else:
        setup_status = "manual_review_required"

    return {
        "ok": True,
        "setup_status": setup_status,
        "zone_name": zone,
        "nodes": node_results,
        "ip_detection": {
            "ipv4": {"status": ipv4.get("status", "not_detected")},
            "ipv6": {"status": ipv6.get("status", "not_detected")},
        },
        "preflight": {
            "status": preflight_result.get("preflight_status", "unknown"),
            "mutation_allowed": False,
            "apply_ready": False,
            "requires_owner_approval": True,
            "requires_cleanup_or_rollback_plan": True,
        },
        "safety": _safety(),
    }


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable setup summary."""
    ipv4 = result.get("ip_detection", {}).get("ipv4", {})
    ipv6 = result.get("ip_detection", {}).get("ipv6", {})
    nodes = result.get("nodes", [])
    preflight = result.get("preflight", {})
    safety = result.get("safety", {})
    status = result.get("setup_status", "unknown")

    print()
    print("  NanoBK DNS Setup Assistant")
    print()
    print("  Zone: {}".format(result.get("zone_name", "***")))
    print()
    print("  Step 1 - VPS address detection:")
    print("    IPv4: {}".format(ipv4.get("status", "not_detected")))
    print("    IPv6: {}".format(ipv6.get("status", "not_detected")))
    print()
    print("  Step 2 - Subdomain availability:")
    for n in nodes:
        print("    {}: {}".format(n.get("hostname", "***"), n.get("availability", "unknown")))
    print()
    print("  Step 3 - DNS plan:")
    for n in nodes:
        print("    {}:".format(n.get("label", "?")))
        print("      A: {}".format(n.get("a_record", "unknown")))
        print("      AAAA: {}".format(n.get("aaaa_record", "unknown")))
    print()
    print("  Step 4 - Create preflight:")
    print("    preflight_status: {}".format(preflight.get("status", "unknown")))
    print("    mutation_allowed: {}".format(str(preflight.get("mutation_allowed", False)).lower()))
    print("    apply_ready: {}".format(str(preflight.get("apply_ready", False)).lower()))
    print()
    print("  Summary:")
    print("    setup_status: {}".format(status))
    print("    DNS changed: {}".format(str(safety.get("dns_changed", False)).lower()))
    print("    Records created: {}".format(str(safety.get("records_created", False)).lower()))
    print("    Records modified: {}".format(str(safety.get("records_modified", False)).lower()))
    print("    Records deleted: {}".format(str(safety.get("records_deleted", False)).lower()))
    print("    Cloudflare touched: {}".format(safety.get("cloudflare_touched", "read_only")))
    print()
    print("  Next step:")
    if status == "ready_for_owner_review":
        print("    Run owner-approved preflight or operator-only create flow.")
        print("    Production proxy/web create remains blocked.")
    elif status == "blocked_subdomain_conflict":
        print("    Resolve subdomain conflict before proceeding.")
        print("    Production proxy/web create remains blocked.")
    elif status == "incomplete_no_ip":
        print("    No public IP detected. Check VPS network configuration.")
    else:
        print("    Review the above results and proceed manually.")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {
            "ok": False,
            "setup_status": "blocked",
            "error": message,
            "safety": _safety(),
        }
        print(json.dumps(result, indent=2))
    else:
        print("  Error: {}".format(message), file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Beginner DNS Setup Assistant"
    )
    sub = parser.add_subparsers(dest="command")

    setup_parser = sub.add_parser("setup", help="Run DNS setup assistant")
    setup_parser.add_argument("--zone", help="Domain zone")
    setup_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    setup_parser.add_argument("--nodes", default="proxy,web", help="Comma-separated node labels")
    setup_parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.command != "setup":
        parser.print_help()
        sys.exit(1)

    zone = args.zone
    api_env = args.api_env
    nodes = args.nodes

    # Fall back to saved profile if CLI args not provided
    if not zone or not api_env:
        profile, profile_err = load_profile()
        if profile_err:
            msg = "No setup profile found. Run: nanobk setup profile save --zone example.com --api-env /path/to/cloudflare.env"
            output_error(msg, args.json)
            sys.exit(1)
        if not zone:
            zone = profile.get("zone_name", "")
        if not api_env:
            api_env = profile.get("api_env_path", "")
        if nodes == "proxy,web" and profile.get("nodes"):
            nodes = ",".join(profile["nodes"])

    if not zone:
        output_error("zone is required (provide --zone or save a profile)", args.json)
        sys.exit(1)
    if not api_env:
        output_error("api-env is required (provide --api-env or save a profile)", args.json)
        sys.exit(1)

    result = run_setup(zone, api_env, nodes)
    result = explain_setup_result(result, zone)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)
        explanation = result.get("explanation", {})
        if explanation:
            print(format_explanation_text(explanation))

    if not result.get("ok", False):
        sys.exit(1)


if __name__ == "__main__":
    main()
