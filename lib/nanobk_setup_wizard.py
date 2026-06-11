#!/usr/bin/env python3
"""
NanoBK Guided CLI Setup Wizard

Beginner-friendly interactive wizard that guides users through:
1. Zone input
2. API env path input
3. Nodes selection
4. Profile save
5. Read-only DNS setup summary

Usage:
    Interactive:  python3 lib/nanobk_setup_wizard.py wizard
    Non-interactive: python3 lib/nanobk_setup_wizard.py wizard --zone DOMAIN --api-env PATH --yes [--json]

Test hooks:
    NANOBK_TEST_DETECTED_IPV4=8.8.8.8
    NANOBK_TEST_DETECTED_IPV6=2001:4860:4860::8888
    NANOBK_TEST_DETECT_IPV4_FAIL=1
    NANOBK_TEST_DETECT_IPV6_FAIL=1
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP=/path/to/map.json
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_profile import save_profile, load_profile, default_profile_path
from nanobk_dns_setup_assistant import run_setup
from nanobk_setup_explain import explain_setup_result, format_explanation_text


# ── Safety constants ────────────────────────────────────────────────────────

_WIZARD_SAFETY = {
    "wizard_only": True,
    "assistant_only": True,
    "plan_only": True,
    "dns_changed": False,
    "records_created": False,
    "records_modified": False,
    "records_deleted": False,
    "production_apply_enabled": False,
    "owner_smoke_create_executed": False,
    "raw_api_response_printed": False,
}


def _safety():
    return dict(_WIZARD_SAFETY)


# ── Wizard logic ────────────────────────────────────────────────────────────

def run_wizard(zone, api_env, nodes, confirm_yes, interactive):
    """Run the setup wizard. Returns result dict."""

    # Collect inputs (interactive or from args)
    try:
        if interactive and not zone:
            zone = input("  Zone (e.g. example.com): ").strip()
        if interactive and not api_env:
            api_env = input("  API env path: ").strip()
        if interactive and nodes == "proxy,web":
            user_nodes = input("  Nodes [proxy,web]: ").strip()
            if user_nodes:
                nodes = user_nodes
    except EOFError:
        result = {
            "ok": True,
            "wizard_status": "cancelled",
            "profile": {"saved": False},
            "safety": _safety(),
        }
        return explain_setup_result(result, zone)

    # Validate required inputs
    if not zone:
        result = {
            "ok": False,
            "wizard_status": "blocked",
            "error": "zone is required",
            "safety": _safety(),
        }
        return explain_setup_result(result, zone)
    if not api_env:
        result = {
            "ok": False,
            "wizard_status": "blocked",
            "error": "api-env path is required",
            "safety": _safety(),
        }
        return explain_setup_result(result, zone)

    # Interactive confirmation
    if interactive and not confirm_yes:
        print()
        print("  This wizard does not change DNS.")
        print("  Production proxy/web DNS creation remains blocked.")
        print()
        try:
            answer = input("  Continue saving profile and running read-only setup? [y/N]: ").strip().lower()
        except EOFError:
            result = {
                "ok": True,
                "wizard_status": "cancelled",
                "profile": {"saved": False},
                "safety": _safety(),
            }
            return explain_setup_result(result, zone)
        if answer not in ("y", "yes"):
            result = {
                "ok": True,
                "wizard_status": "cancelled",
                "profile": {"saved": False},
                "safety": _safety(),
            }
            return explain_setup_result(result, zone)

    # Parse nodes
    nodes_list = [n.strip() for n in nodes.split(",") if n.strip()]

    # Save profile
    profile_result = save_profile(zone, api_env, nodes_list)
    if not profile_result.get("ok", False):
        result = {
            "ok": False,
            "wizard_status": "blocked",
            "error": profile_result.get("error", "failed to save profile"),
            "safety": _safety(),
        }
        return explain_setup_result(result, zone)

    # Run setup assistant
    try:
        setup_result = run_setup(zone, api_env, nodes)
    except Exception as e:
        result = {
            "ok": False,
            "wizard_status": "blocked",
            "error": "setup assistant failed: {}".format(e),
            "profile": {
                "saved": True,
                "zone_name": zone,
                "nodes": nodes_list,
                "api_env_configured": True,
                "api_env_path_printed": False,
                "profile_path_printed": False,
            },
            "safety": _safety(),
        }
        return explain_setup_result(result, zone)

    wizard_status = setup_result.get("setup_status", "unknown")

    result = {
        "ok": setup_result.get("ok", False),
        "wizard_status": wizard_status,
        "profile": {
            "saved": True,
            "zone_name": zone,
            "nodes": nodes_list,
            "api_env_configured": True,
            "api_env_path_printed": False,
            "profile_path_printed": False,
        },
        "setup": {
            "setup_status": wizard_status,
            "ip_detection": setup_result.get("ip_detection", {}),
            "nodes": [
                {
                    "label": n.get("label", ""),
                    "availability": n.get("availability", "unknown"),
                    "a_record": n.get("a_record", "unknown"),
                    "aaaa_record": n.get("aaaa_record", "unknown"),
                }
                for n in setup_result.get("nodes", [])
            ],
        },
        "safety": _safety(),
    }

    # Add explanation
    result["setup_status"] = wizard_status
    result = explain_setup_result(result, zone)
    return result


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable wizard summary."""
    profile = result.get("profile", {})
    setup = result.get("setup", {})
    safety = result.get("safety", {})
    status = result.get("wizard_status", "unknown")
    nodes = setup.get("nodes", [])
    ip = setup.get("ip_detection", {})
    ipv4 = ip.get("ipv4", {})
    ipv6 = ip.get("ipv6", {})

    print()
    print("  NanoBK Setup Wizard")
    print()

    if status == "cancelled":
        print("  Wizard cancelled by user.")
        print("  No profile saved. No DNS changes made.")
        print()
        return

    print("  Step 1 - Setup profile:")
    print("    Zone: {}".format(profile.get("zone_name", "***")))
    print("    Nodes: {}".format(", ".join(profile.get("nodes", []))))
    print("    API env: {}".format("configured" if profile.get("api_env_configured") else "not configured"))
    print("    Profile saved: {}".format(str(profile.get("saved", False)).lower()))
    print()

    print("  Step 2 - DNS setup assistant:")
    print("    IPv4: {}".format(ipv4.get("status", "not_detected")))
    print("    IPv6: {}".format(ipv6.get("status", "not_detected")))
    for n in nodes:
        print("    {}: {}".format(
            "{}.{}".format(n.get("label", "?"), profile.get("zone_name", "***")),
            n.get("availability", "unknown"),
        ))
    print()

    print("  Step 3 - Plan summary:")
    for n in nodes:
        print("    {}:".format(n.get("label", "?")))
        print("      A: {}".format(n.get("a_record", "unknown")))
        print("      AAAA: {}".format(n.get("aaaa_record", "unknown")))
    print()

    print("  Final status:")
    print("    {}".format(status))
    print()

    print("  Safety:")
    print("    DNS changed: {}".format(str(safety.get("dns_changed", False)).lower()))
    print("    Records created: {}".format(str(safety.get("records_created", False)).lower()))
    print("    Records modified: {}".format(str(safety.get("records_modified", False)).lower()))
    print("    Records deleted: {}".format(str(safety.get("records_deleted", False)).lower()))
    print("    Production apply enabled: {}".format(str(safety.get("production_apply_enabled", False)).lower()))
    print("    Owner smoke create executed: {}".format(str(safety.get("owner_smoke_create_executed", False)).lower()))
    print()

    # Print explanation if available
    explanation = result.get("explanation", {})
    if explanation:
        print(format_explanation_text(explanation))


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "wizard_status": "blocked", "error": message, "safety": _safety()}
        print(json.dumps(result, indent=2))
    else:
        print("  Error: {}".format(message), file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Guided CLI Setup Wizard"
    )
    sub = parser.add_subparsers(dest="command")

    wizard_parser = sub.add_parser("wizard", help="Run guided setup wizard")
    wizard_parser.add_argument("--zone", help="Domain zone")
    wizard_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    wizard_parser.add_argument("--nodes", default="proxy,web", help="Comma-separated node labels")
    wizard_parser.add_argument("--yes", action="store_true", help="Non-interactive: skip confirmation")
    wizard_parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.command != "wizard":
        parser.print_help()
        sys.exit(1)

    interactive = not args.yes and not args.zone and not args.api_env

    result = run_wizard(
        zone=args.zone or "",
        api_env=args.api_env or "",
        nodes=args.nodes,
        confirm_yes=args.yes,
        interactive=interactive,
    )

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)

    if not result.get("ok", False):
        sys.exit(1)
    if result.get("wizard_status") == "cancelled":
        sys.exit(0)


if __name__ == "__main__":
    main()
