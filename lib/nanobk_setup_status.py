#!/usr/bin/env python3
"""
NanoBK Unified Setup Status / CLI Home

Provides a beginner-friendly overview of the current NanoBK setup state.
Read-only. No DNS mutation. No Cloudflare mutation.

Usage:
    python3 lib/nanobk_setup_status.py home [--json]
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_profile import load_profile, default_profile_path
from nanobk_dns_setup_assistant import run_setup
from nanobk_setup_explain import explain_setup_result, format_explanation_text


# ── Safety constants ────────────────────────────────────────────────────────

_HOME_SAFETY = {
    "home_only": True,
    "read_only": True,
    "dns_changed": False,
    "cloudflare_touched": "read_only_or_false",
    "records_created": False,
    "records_modified": False,
    "records_deleted": False,
    "production_apply_enabled": False,
    "owner_smoke_create_executed": False,
    "raw_api_response_printed": False,
}


def _safety(cloudflare_touched="read_only_or_false"):
    result = dict(_HOME_SAFETY)
    result["cloudflare_touched"] = cloudflare_touched
    return result


# ── Home logic ──────────────────────────────────────────────────────────────

def run_home():
    """Run the home/status overview. Returns result dict."""

    # Check if profile exists
    profile_path = default_profile_path()

    if not os.path.isfile(profile_path):
        return {
            "ok": True,
            "home_status": "no_profile",
            "profile": {
                "status": "not_configured",
                "zone_name": None,
                "nodes": [],
                "api_env_configured": False,
                "api_env_path_printed": False,
                "profile_path_printed": False,
            },
            "explanation": {
                "summary_title": "No setup profile found",
                "plain_status": "NanoBK has not been configured yet.",
                "completed": [],
                "not_done": [
                    "No setup profile saved",
                    "No DNS check performed",
                    "No DNS records were created",
                ],
                "why_blocked": [
                    "NanoBK needs a setup profile before it can check DNS readiness.",
                ],
                "next_actions": [
                    {
                        "label": "Run setup wizard",
                        "command": "nanobk setup wizard",
                        "safe": True,
                    },
                ],
                "fix_hints": [],
                "safety": {
                    "dns_changed": False,
                    "records_created": False,
                    "records_modified": False,
                    "records_deleted": False,
                    "production_apply_enabled": False,
                },
            },
            "next_actions": [
                {
                    "label": "Run setup wizard",
                    "command": "nanobk setup wizard",
                    "safe": True,
                },
            ],
            "safety": _safety("false"),
        }

    # Load profile
    profile, profile_err = load_profile()

    if profile_err == "insecure profile permissions (expected 0600)":
        return {
            "ok": False,
            "home_status": "blocked_profile_permission",
            "profile": {
                "status": "insecure",
                "zone_name": None,
                "nodes": [],
                "api_env_configured": False,
                "api_env_path_printed": False,
                "profile_path_printed": False,
            },
            "explanation": {
                "summary_title": "Profile permission issue",
                "plain_status": "The setup profile file has insecure permissions.",
                "completed": [],
                "not_done": [
                    "Profile not read due to insecure permissions",
                    "No DNS check performed",
                ],
                "why_blocked": [
                    "NanoBK requires profile file permissions of 0600.",
                ],
                "next_actions": [
                    {
                        "label": "Fix profile permissions",
                        "command": "chmod 600 <profile-file>",
                        "safe": True,
                    },
                ],
                "fix_hints": [
                    "Set profile file permissions to 0600.",
                    "Do not share your profile file.",
                ],
                "safety": {
                    "dns_changed": False,
                    "records_created": False,
                    "records_modified": False,
                    "records_deleted": False,
                    "production_apply_enabled": False,
                },
            },
            "next_actions": [
                {
                    "label": "Fix profile permissions",
                    "command": "chmod 600 <profile-file>",
                    "safe": True,
                },
            ],
            "safety": _safety("false"),
        }

    if profile_err:
        return {
            "ok": False,
            "home_status": "blocked_malformed_profile",
            "profile": {
                "status": "malformed",
                "zone_name": None,
                "nodes": [],
                "api_env_configured": False,
                "api_env_path_printed": False,
                "profile_path_printed": False,
            },
            "explanation": {
                "summary_title": "Malformed profile",
                "plain_status": "The setup profile could not be read.",
                "completed": [],
                "not_done": [
                    "Profile not read due to format error",
                    "No DNS check performed",
                ],
                "why_blocked": [
                    "The profile file appears to be corrupted or has invalid JSON.",
                ],
                "next_actions": [
                    {
                        "label": "Clear and recreate profile",
                        "command": "nanobk setup profile clear && nanobk setup wizard",
                        "safe": True,
                    },
                ],
                "fix_hints": [
                    "Clear the corrupted profile and run the setup wizard again.",
                ],
                "safety": {
                    "dns_changed": False,
                    "records_created": False,
                    "records_modified": False,
                    "records_deleted": False,
                    "production_apply_enabled": False,
                },
            },
            "next_actions": [
                {
                    "label": "Clear and recreate profile",
                    "command": "nanobk setup profile clear && nanobk setup wizard",
                    "safe": True,
                },
            ],
            "safety": _safety("false"),
        }

    # Profile loaded successfully
    zone = profile.get("zone_name", "")
    nodes_list = profile.get("nodes", ["proxy", "web"])
    api_env = profile.get("api_env_path", "")
    nodes_str = ",".join(nodes_list)

    # Run setup assistant
    try:
        setup_result = run_setup(zone, api_env, nodes_str)
    except Exception as e:
        return {
            "ok": False,
            "home_status": "unknown",
            "profile": {
                "status": "configured",
                "zone_name": zone,
                "nodes": nodes_list,
                "api_env_configured": bool(api_env),
                "api_env_path_printed": False,
                "profile_path_printed": False,
            },
            "explanation": {
                "summary_title": "Setup check failed",
                "plain_status": "An error occurred during setup check.",
                "completed": ["Loaded saved profile"],
                "not_done": ["Setup check failed"],
                "why_blocked": ["Setup assistant encountered an error."],
                "next_actions": [
                    {"label": "Re-run setup wizard", "command": "nanobk setup wizard", "safe": True},
                ],
                "fix_hints": ["Run 'nanobk doctor' for diagnostics."],
                "safety": {"dns_changed": False, "records_created": False, "records_modified": False, "records_deleted": False, "production_apply_enabled": False},
            },
            "next_actions": [
                {"label": "Re-run setup wizard", "command": "nanobk setup wizard", "safe": True},
            ],
            "safety": _safety("read_only"),
        }

    # Add explanation
    setup_result = explain_setup_result(setup_result, zone)
    explanation = setup_result.get("explanation", {})
    setup_status = setup_result.get("setup_status", "unknown")

    return {
        "ok": setup_result.get("ok", False),
        "home_status": setup_status,
        "profile": {
            "status": "configured",
            "zone_name": zone,
            "nodes": nodes_list,
            "api_env_configured": bool(api_env),
            "api_env_path_printed": False,
            "profile_path_printed": False,
        },
        "setup": {
            "setup_status": setup_status,
            "ip_detection": setup_result.get("ip_detection", {}),
            "nodes": setup_result.get("nodes", []),
        },
        "explanation": explanation,
        "next_actions": explanation.get("next_actions", []),
        "safety": _safety("read_only"),
    }


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable home summary."""
    profile = result.get("profile", {})
    explanation = result.get("explanation", {})
    safety = result.get("safety", {})
    status = result.get("home_status", "unknown")

    print()
    print("  NanoBK Home")
    print()

    print("  Profile:")
    print("    Status: {}".format(profile.get("status", "unknown")))
    if profile.get("status") == "configured":
        print("    Zone: {}".format(profile.get("zone_name", "***")))
        print("    Nodes: {}".format(", ".join(profile.get("nodes", []))))
        print("    API env: {}".format("configured" if profile.get("api_env_configured") else "not configured"))
    print()

    if status != "no_profile" and status != "blocked_profile_permission" and status != "blocked_malformed_profile":
        print("  Setup:")
        print("    Status: {}".format(status))
        print("    DNS changed: {}".format(str(safety.get("dns_changed", False)).lower()))
        print("    Production apply enabled: {}".format(str(safety.get("production_apply_enabled", False)).lower()))
        print()

    # Print explanation
    if explanation:
        print(format_explanation_text(explanation))

    print("  Safety:")
    print("    Cloudflare touched: {}".format(safety.get("cloudflare_touched", "false")))
    print("    DNS changed: {}".format(str(safety.get("dns_changed", False)).lower()))
    print("    Records created: {}".format(str(safety.get("records_created", False)).lower()))
    print("    Records modified: {}".format(str(safety.get("records_modified", False)).lower()))
    print("    Records deleted: {}".format(str(safety.get("records_deleted", False)).lower()))
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "home_status": "blocked", "error": message, "safety": _safety()}
        print(json.dumps(result, indent=2))
    else:
        print("  Error: {}".format(message), file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Unified Setup Status / CLI Home"
    )
    sub = parser.add_subparsers(dest="command")

    home_parser = sub.add_parser("home", help="Show home status overview")
    home_parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.command != "home":
        parser.print_help()
        sys.exit(1)

    result = run_home()

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)

    if not result.get("ok", False):
        sys.exit(1)


if __name__ == "__main__":
    main()
