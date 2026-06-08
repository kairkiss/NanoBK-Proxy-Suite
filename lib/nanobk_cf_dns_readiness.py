#!/usr/bin/env python3
"""
NanoBK Cloudflare DNS Readiness Check

Read-only readiness report for Cloudflare DNS preparation.
Checks api-env, zone discovery, DNS profile, and local plan metadata.

No DNS mutation. No POST/PATCH/DELETE. No apply --yes.

Usage:
    python3 lib/nanobk_cf_dns_readiness.py [--api-env PATH] [--profile PATH] [--json]
"""

import argparse
import json
import os
import sys

# Reuse zones helper
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nanobk_cf_zones import (
    parse_env_file,
    fetch_zones,
    mask_domain,
    redact_id,
)

# Reuse DNS profile validation
from nanobk_cf_dns import validate_profile, _plan_from_profile, _build_planned_records


# ── Check statuses ──────────────────────────────────────────────────────────

STATUS_OK = "ok"
STATUS_WARNING = "warning"
STATUS_FAILED = "failed"
STATUS_SKIPPED = "skipped"
STATUS_MANUAL = "manual_pending"


def _check(name, status, message=None, **extra):
    """Build a check result dict."""
    result = {"name": name, "status": status}
    if message:
        result["message"] = message
    result.update(extra)
    return result


# ── Readiness logic ─────────────────────────────────────────────────────────

def compute_ready(checks):
    """Compute overall readiness from checks.

    ready=True only if all required checks are ok and none are
    failed, warning, manual_pending, or blocking skipped.

    dns_apply_status is excluded (always manual_pending).
    dns_check_available=manual_pending blocks readiness (zone binding required).
    """
    blocking = {"failed", "warning", "manual_pending"}
    for check in checks:
        name = check["name"]
        status = check["status"]
        # dns_apply_status is always manual — it doesn't block readiness
        if name == "dns_apply_status":
            continue
        if status in blocking:
            return False
        if status == "skipped":
            # Skipped checks that are prerequisites block readiness
            if name in ("api_env_permissions", "api_env_parse", "zone_discovery",
                        "dns_profile_validate", "dns_plan"):
                return False
    return True


def run_readiness(api_env_path=None, profile_path=None):
    """Run all readiness checks. Returns (checks, next_steps, ok, error)."""
    checks = []
    next_steps = []
    all_ok = True

    # ── 1. api-env present ──
    if not api_env_path:
        checks.append(_check("api_env_present", STATUS_MANUAL,
                             "no --api-env provided"))
        next_steps.append(
            "nanobk cf zones list --api-env /etc/nanobk/cloudflare-api.env"
        )
        # Skip all api-env dependent checks
        checks.append(_check("api_env_permissions", STATUS_SKIPPED))
        checks.append(_check("api_env_parse", STATUS_SKIPPED))
        checks.append(_check("zone_discovery", STATUS_SKIPPED))
    else:
        # File exists?
        if not os.path.isfile(api_env_path):
            checks.append(_check("api_env_present", STATUS_FAILED,
                                 f"file not found: {api_env_path}"))
            checks.append(_check("api_env_permissions", STATUS_SKIPPED))
            checks.append(_check("api_env_parse", STATUS_SKIPPED))
            checks.append(_check("api_env_parse", STATUS_SKIPPED))
            checks.append(_check("zone_discovery", STATUS_SKIPPED))
            all_ok = False
        else:
            checks.append(_check("api_env_present", STATUS_OK))

            # Permissions
            try:
                env = parse_env_file(api_env_path)
                checks.append(_check("api_env_permissions", STATUS_OK))
            except PermissionError as e:
                checks.append(_check("api_env_permissions", STATUS_FAILED,
                                     str(e)))
                checks.append(_check("api_env_parse", STATUS_SKIPPED))
                checks.append(_check("zone_discovery", STATUS_SKIPPED))
                all_ok = False
                env = None
            except ValueError as e:
                err_msg = str(e)
                # Don't leak values — only show key names
                checks.append(_check("api_env_permissions", STATUS_OK))
                checks.append(_check("api_env_parse", STATUS_FAILED, err_msg))
                checks.append(_check("zone_discovery", STATUS_SKIPPED))
                all_ok = False
                env = None

            if env is not None:
                checks.append(_check("api_env_parse", STATUS_OK))

                # Zone discovery
                try:
                    zones = fetch_zones(env["CF_API_TOKEN"])
                    checks.append(_check("zone_discovery", STATUS_OK,
                                         f"{len(zones)} zones found",
                                         count=len(zones),
                                         zones=[mask_domain(z.get("name", "")) for z in zones]))
                except RuntimeError as e:
                    checks.append(_check("zone_discovery", STATUS_FAILED,
                                         str(e)))
                    all_ok = False

                # DNS check availability
                has_zone_id = "CF_ZONE_ID" in env
                has_zone_name = "CF_ZONE_NAME" in env
                if has_zone_id and has_zone_name:
                    checks.append(_check("dns_check_available", STATUS_OK,
                                         "zone ID and zone name present"))
                else:
                    missing = []
                    if not has_zone_id:
                        missing.append("CF_ZONE_ID")
                    if not has_zone_name:
                        missing.append("CF_ZONE_NAME")
                    checks.append(_check("dns_check_available", STATUS_MANUAL,
                                         f"missing: {', '.join(missing)}"))

    # ── 2. DNS profile ──
    if not profile_path:
        checks.append(_check("dns_profile_present", STATUS_MANUAL,
                             "no --profile provided"))
        next_steps.append(
            "nanobk cf dns plan --profile /etc/nanobk/cloudflare-dns-profile.json"
        )
        checks.append(_check("dns_profile_validate", STATUS_SKIPPED))
        checks.append(_check("dns_plan", STATUS_SKIPPED))
    else:
        if not os.path.isfile(profile_path):
            checks.append(_check("dns_profile_present", STATUS_FAILED,
                                 f"file not found: {profile_path}"))
            checks.append(_check("dns_profile_validate", STATUS_SKIPPED))
            checks.append(_check("dns_plan", STATUS_SKIPPED))
            all_ok = False
        else:
            checks.append(_check("dns_profile_present", STATUS_OK))

            # Load and validate profile
            try:
                with open(profile_path, "r", encoding="utf-8") as f:
                    profile = json.load(f)
            except json.JSONDecodeError:
                checks.append(_check("dns_profile_validate", STATUS_FAILED,
                                     "invalid JSON"))
                checks.append(_check("dns_plan", STATUS_SKIPPED))
                all_ok = False
                profile = None
            except PermissionError:
                checks.append(_check("dns_profile_validate", STATUS_FAILED,
                                     "cannot read file"))
                checks.append(_check("dns_plan", STATUS_SKIPPED))
                all_ok = False
                profile = None

            if profile is not None:
                errors = validate_profile(profile)
                if errors:
                    checks.append(_check("dns_profile_validate", STATUS_FAILED,
                                         "; ".join(errors)))
                    checks.append(_check("dns_plan", STATUS_SKIPPED))
                    all_ok = False
                else:
                    checks.append(_check("dns_profile_validate", STATUS_OK))

                    # Build plan metadata
                    try:
                        plan = _plan_from_profile(profile)
                        records = _build_planned_records(plan)
                        record_types = [r["type"] for r in records]
                        checks.append(_check("dns_plan", STATUS_OK,
                                             f"{len(records)} record(s) planned",
                                             record_count=len(records),
                                             record_types=record_types,
                                             proxied=False))
                    except Exception:
                        checks.append(_check("dns_plan", STATUS_FAILED,
                                             "failed to build plan"))
                        all_ok = False

    # ── 3. Apply status ──
    # Always manual_apply_pending — readiness is read-only
    checks.append(_check("dns_apply_status", STATUS_MANUAL,
                         "manual_apply_pending"))

    # ── 4. Next steps if none yet ──
    if not next_steps:
        next_steps.append(
            "Review the readiness report before any Cloudflare record check."
        )

    return checks, next_steps, all_ok


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(checks, next_steps, ready):
    """Print human-readable readiness report."""
    print()
    print("  NanoBK DNS readiness")
    print()

    # Group: Cloudflare access
    print("  Cloudflare access:")
    for name in ("api_env_present", "api_env_permissions", "api_env_parse", "zone_discovery"):
        check = next((c for c in checks if c["name"] == name), None)
        if check:
            status = check["status"]
            msg = check.get("message", "")
            if status == STATUS_SKIPPED:
                print(f"    {name}: skipped")
            elif status == STATUS_MANUAL:
                print(f"    {name}: manual_pending — {msg}")
            else:
                extra = ""
                if "count" in check:
                    extra = f" — {check['count']} zones found"
                print(f"    {name}: {status}{extra or (' — ' + msg if msg else '')}")

    # Group: DNS profile
    print()
    print("  DNS profile:")
    for name in ("dns_profile_present", "dns_profile_validate", "dns_plan"):
        check = next((c for c in checks if c["name"] == name), None)
        if check:
            status = check["status"]
            msg = check.get("message", "")
            if status == STATUS_SKIPPED:
                print(f"    {name}: skipped")
            elif status == STATUS_MANUAL:
                print(f"    {name}: manual_pending — {msg}")
            else:
                extra = ""
                if "record_count" in check:
                    extra = f" — {check['record_count']} record(s) planned"
                print(f"    {name}: {status}{extra or (' — ' + msg if msg else '')}")

    # Apply status
    apply_check = next((c for c in checks if c["name"] == "dns_apply_status"), None)
    if apply_check:
        print(f"\n  apply status: {apply_check['message']}")

    # Overall
    print()
    if ready:
        print("  Overall: ready for the next explicit read-only check")
    else:
        print("  Overall: not ready — manual steps are still required")

    # Next steps
    if next_steps:
        print()
        print("  Next safe step:")
        for step in next_steps:
            print(f"    {step}")

    print()
    print("  No DNS records were created, updated, or deleted.")
    print()


def output_json(checks, next_steps, ok, ready):
    """Print sanitized JSON readiness report."""
    # Sanitize: remove any raw values that shouldn't be exposed
    sanitized = []
    for check in checks:
        sc = {"name": check["name"], "status": check["status"]}
        if "message" in check:
            sc["message"] = check["message"]
        if "count" in check:
            sc["count"] = check["count"]
        if "zones" in check:
            sc["zones"] = check["zones"]
        if "record_count" in check:
            sc["record_count"] = check["record_count"]
        if "record_types" in check:
            sc["record_types"] = check["record_types"]
        if "proxied" in check:
            sc["proxied"] = check["proxied"]
        sanitized.append(sc)

    result = {
        "ok": ok,
        "ready": ready,
        "mutation": False,
        "profile_write": False,
        "checks": sanitized,
        "dns_apply_status": "manual_apply_pending",
        "next_steps": next_steps,
    }
    print(json.dumps(result, indent=2))


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "ready": False, "error": message, "mutation": False,
                  "profile_write": False, "checks": [], "dns_apply_status": "unknown", "next_steps": []}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Cloudflare DNS Readiness Check (read-only)"
    )
    parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    parser.add_argument("--profile", help="Path to DNS profile JSON file")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    try:
        checks, next_steps, ok = run_readiness(args.api_env, args.profile)
    except Exception as e:
        output_error(str(e), args.json)
        sys.exit(1)

    ready = compute_ready(checks)

    if args.json:
        output_json(checks, next_steps, ok, ready)
    else:
        output_text(checks, next_steps, ready)


if __name__ == "__main__":
    main()
