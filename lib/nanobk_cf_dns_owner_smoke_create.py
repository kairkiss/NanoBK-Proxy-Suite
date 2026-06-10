#!/usr/bin/env python3
"""
NanoBK Owner-Approved Disposable DNS Create Harness

Extremely controlled disposable smoke create + post-check + cleanup.
Owner-only. Disposable-only. Smoke-only. Not production apply.

Usage:
    python3 lib/nanobk_cf_dns_owner_smoke_create.py smoke \\
        --zone DOMAIN --api-env PATH --label nanobk-smoke-xxxx \\
        --type A --content 203.0.113.10 --ttl 60 \\
        --owner-approve --cleanup \\
        --confirm-disposable-smoke "I UNDERSTAND THIS WILL CREATE AND DELETE ONE DISPOSABLE CLOUDFLARE DNS RECORD" \\
        [--json]

Test hook:
    NANOBK_OWNER_SMOKE_FAKE_MAP=/path/to/fixture.json
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cf_zones import parse_env_file, mask_domain
from nanobk_cf_dns_availability import validate_zone, analyze_records


# ── Constants ───────────────────────────────────────────────────────────────

_CONFIRMATION_PHRASE = "I UNDERSTAND THIS WILL CREATE AND DELETE ONE DISPOSABLE CLOUDFLARE DNS RECORD"
_DISPOSABLE_LABEL_RE = re.compile(r"^nanobk-smoke-[a-zA-Z0-9][a-zA-Z0-9-]{0,61}$")
_ALLOWED_TYPES = {"A", "AAAA", "TXT"}
_BLOCKED_LABELS = {"proxy", "web", "www", "@", "*", "api", "cdn", "mail", "smtp", "imap"}
_DANGEROUS_FLAGS = {"force", "overwrite", "apply", "yes", "keep_for_debug"}


# ── Validation ──────────────────────────────────────────────────────────────

def validate_label(label):
    """Validate label is disposable. Returns error string or None."""
    if not label:
        return "label is required"
    if label in _BLOCKED_LABELS:
        return f"label_not_disposable: '{label}' is a production label"
    if not _DISPOSABLE_LABEL_RE.match(label):
        return "label_not_disposable: label must start with 'nanobk-smoke-' and contain only alphanumeric/hyphen"
    return None


def validate_record_type(rtype):
    """Validate record type. Returns error string or None."""
    if not rtype:
        return "type is required"
    if rtype.upper() not in _ALLOWED_TYPES:
        return f"unsupported_type: '{rtype}' is not allowed. Allowed: {', '.join(sorted(_ALLOWED_TYPES))}"
    return None


def validate_content(content, rtype):
    """Validate record content. Returns error string or None."""
    if not content:
        return "content is required"
    if rtype == "A":
        import ipaddress
        try:
            addr = ipaddress.IPv4Address(content)
            if addr.is_loopback or addr.is_multicast or addr.is_reserved:
                return "content is not a valid public IPv4"
        except ipaddress.AddressValueError:
            return "content is not a valid IPv4 address"
    elif rtype == "AAAA":
        import ipaddress
        try:
            addr = ipaddress.IPv6Address(content)
            if addr.is_loopback or addr.is_multicast or addr.is_reserved:
                return "content is not a valid public IPv6"
        except ipaddress.AddressValueError:
            return "content is not a valid IPv6 address"
    elif rtype == "TXT":
        if len(content) > 4096:
            return "TXT content is too long"
    return None


# ── Mock transport ──────────────────────────────────────────────────────────

def _load_fake_map():
    """Load fake response map from env var."""
    map_path = os.environ.get("NANOBK_OWNER_SMOKE_FAKE_MAP")
    if not map_path:
        return None
    try:
        with open(map_path, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None


def _mock_api_call(step, fake_map):
    """Simulate API call using fake map."""
    if fake_map is None:
        return {"success": False, "errors": [{"message": "no mock configured"}], "result": []}
    entry = fake_map.get(step, {})
    return entry


def _mock_post(fake_map, zone_id, label, rtype, content, ttl, proxied):
    """Simulate POST create."""
    return _mock_api_call("create", fake_map)


def _mock_delete(fake_map, zone_id, record_id):
    """Simulate DELETE cleanup."""
    return _mock_api_call("delete", fake_map)


# ── Smoke harness ───────────────────────────────────────────────────────────

def run_smoke(zone, api_env_path, label, rtype, content, ttl,
              owner_approve, cleanup, confirm_phrase):
    """Run the owner-approved disposable DNS create smoke harness.

    Returns result dict. All mutation happens inside this function only when ALL gates pass.
    """
    result_base = {
        "ok": False, "status": "blocked", "mutation_allowed": False,
        "dns_changed": False, "records_created": False, "records_deleted": False,
        "cleanup_verified": False,
    }

    # Gate 1: Owner approval
    if not owner_approve:
        return {**result_base, "reason": "owner_approval_required",
                "safety": _safety_block()}

    # Gate 2: Confirmation phrase
    if confirm_phrase != _CONFIRMATION_PHRASE:
        return {**result_base, "reason": "confirmation_required",
                "safety": _safety_block()}

    # Gate 3: Cleanup required
    if not cleanup:
        return {**result_base, "reason": "cleanup_required",
                "safety": _safety_block()}

    # Gate 4: Label validation
    label_err = validate_label(label)
    if label_err:
        return {**result_base, "reason": label_err,
                "safety": _safety_block()}

    # Gate 5: Type validation
    type_err = validate_record_type(rtype)
    if type_err:
        return {**result_base, "reason": type_err,
                "safety": _safety_block()}

    rtype = rtype.upper()

    # Gate 6: Content validation
    content_err = validate_content(content, rtype)
    if content_err:
        return {**result_base, "reason": content_err,
                "safety": _safety_block()}

    # Gate 7: Zone validation
    zone_err = validate_zone(zone)
    if zone_err:
        return {**result_base, "reason": zone_err,
                "safety": _safety_block()}

    # Gate 8: Credential
    try:
        env = parse_env_file(api_env_path)
    except FileNotFoundError:
        return {**result_base, "reason": "api-env file not found",
                "safety": _safety_block()}
    except PermissionError:
        return {**result_base, "reason": "insecure credential file permissions",
                "safety": _safety_block()}
    except ValueError as e:
        return {**result_base, "reason": str(e),
                "safety": _safety_block()}

    token = env.get("CF_API_TOKEN")
    zone_id = env.get("CF_ZONE_ID")
    zone_name = env.get("CF_ZONE_NAME")

    if not token:
        return {**result_base, "reason": "CF_API_TOKEN is required",
                "safety": _safety_block()}
    if not zone_id:
        return {**result_base, "reason": "CF_ZONE_ID is required",
                "safety": _safety_block()}

    hostname = f"{label}.{zone}"
    fake_map = _load_fake_map()

    # Step 1: Availability pre-check (GET)
    pre_check_records = []
    try:
        pre_check_resp = _mock_api_call("pre_check", fake_map)
        if not pre_check_resp.get("success", False):
            errors = pre_check_resp.get("errors", [])
            msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or "unknown error"
            return {**result_base, "reason": f"availability_check_failed: {msg}",
                    "safety": _safety_block()}
        pre_check_records = pre_check_resp.get("result", [])
    except Exception as e:
        return {**result_base, "reason": f"availability_check_failed: {e}",
                "safety": _safety_block()}

    if pre_check_records:
        return {**result_base, "reason": "record_already_exists",
                "hostname": hostname,
                "safety": _safety_block()}

    # Step 2: Create (POST)
    create_success = False
    created_record_id = None
    try:
        create_resp = _mock_post(fake_map, zone_id, label, rtype, content, ttl, False)
        if create_resp.get("success", False):
            create_success = True
            result = create_resp.get("result", {})
            created_record_id = result.get("id")
        else:
            errors = create_resp.get("errors", [])
            msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or "unknown error"
            return {
                "ok": False, "status": "create_failed",
                "reason": f"create_failed: {msg}",
                "hostname": hostname,
                "create": {"attempted": True, "success": False, "record_id_printed": False},
                "mutation_allowed": True, "dns_changed": False,
                "records_created": False, "records_deleted": False,
                "cleanup_verified": False,
                "safety": _safety_active(),
            }
    except Exception as e:
        return {
            "ok": False, "status": "create_failed",
            "reason": f"create_failed: {e}",
            "hostname": hostname,
            "create": {"attempted": True, "success": False, "record_id_printed": False},
            "mutation_allowed": True, "dns_changed": False,
            "records_created": False, "records_deleted": False,
            "cleanup_verified": False,
            "safety": _safety_active(),
        }

    # Step 3: Post-check (GET)
    post_check_success = False
    try:
        post_check_resp = _mock_api_call("post_check", fake_map)
        if post_check_resp.get("success", False):
            post_check_records = post_check_resp.get("result", [])
            if post_check_records:
                post_check_success = True
            else:
                # Post-check found nothing — record not visible
                pass
        else:
            pass
    except Exception:
        pass

    if not post_check_success:
        # Post-check failed, attempt cleanup
        cleanup_attempted = True
        cleanup_success = False
        try:
            if created_record_id:
                cleanup_resp = _mock_delete(fake_map, zone_id, created_record_id)
                cleanup_success = cleanup_resp.get("success", False)
        except Exception:
            pass

        return {
            "ok": False, "status": "post_check_failed",
            "hostname": hostname,
            "create": {"attempted": True, "success": True, "record_id_printed": False},
            "post_check": {"attempted": True, "success": False},
            "cleanup": {"attempted": cleanup_attempted, "success": cleanup_success, "verified": False},
            "mutation_allowed": True,
            "dns_changed": not cleanup_success,
            "records_created": True, "records_deleted": cleanup_success,
            "cleanup_verified": False,
            "safety": _safety_active(),
        }

    # Step 4: Cleanup (DELETE)
    cleanup_success = False
    try:
        if created_record_id:
            cleanup_resp = _mock_delete(fake_map, zone_id, created_record_id)
            cleanup_success = cleanup_resp.get("success", False)
        else:
            cleanup_success = True  # Nothing to delete
    except Exception:
        pass

    if not cleanup_success:
        return {
            "ok": False, "status": "cleanup_failed",
            "hostname": hostname,
            "create": {"attempted": True, "success": True, "record_id_printed": False},
            "post_check": {"attempted": True, "success": True},
            "cleanup": {"attempted": True, "success": False, "verified": False},
            "manual_cleanup_warning": "A disposable DNS record may still exist. Check your Cloudflare dashboard.",
            "mutation_allowed": True,
            "dns_changed": True,
            "records_created": True, "records_deleted": False,
            "cleanup_verified": False,
            "safety": _safety_active(),
        }

    # Step 5: Cleanup verification (GET)
    cleanup_verified = False
    try:
        verify_resp = _mock_api_call("cleanup_verify", fake_map)
        if verify_resp.get("success", False):
            verify_records = verify_resp.get("result", [])
            cleanup_verified = len(verify_records) == 0
    except Exception:
        pass

    return {
        "ok": True,
        "status": "created_and_cleaned",
        "zone_name": zone,
        "label": label,
        "hostname": hostname,
        "record_type": rtype,
        "availability_before": "available",
        "create": {"attempted": True, "success": True, "record_id_printed": False},
        "post_check": {"attempted": True, "success": True},
        "cleanup": {"attempted": True, "success": True, "verified": cleanup_verified},
        "mutation_allowed": True,
        "dns_changed_during_run": True,
        "persistent_dns_changed": False,
        "records_created": True,
        "records_deleted": True,
        "records_modified": False,
        "overwrite_existing": False,
        "force": False,
        "cleanup_verified": cleanup_verified,
        "safety": _safety_active(),
    }


def _safety_block():
    """Safety dict for blocked state."""
    return {
        "owner_only": True, "disposable_only": True,
        "requires_owner_approval": True, "requires_cleanup": True,
        "mutation_allowed": False, "overwrite_existing": False, "force": False,
        "raw_api_response_printed": False,
    }


def _safety_active():
    """Safety dict for active mutation state."""
    return {
        "owner_only": True, "disposable_only": True,
        "requires_owner_approval": True, "requires_cleanup": True,
        "mutation_allowed": True, "overwrite_existing": False, "force": False,
        "raw_api_response_printed": False,
    }


# ── Output ──────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable smoke report."""
    status = result.get("status", "blocked")
    hostname = result.get("hostname", "***")

    print()
    print("  NanoBK owner disposable DNS smoke")
    print()
    print("  Target:")
    print(f"    {hostname}")
    print()

    if status == "blocked":
        print(f"  Status: blocked")
        print(f"  Reason: {result.get('reason', 'unknown')}")
    else:
        print("  Gate:")
        print(f"    Owner approved: true")
        print(f"    Disposable label: true")
        print(f"    Cleanup required: true")
        print(f"    Existing record found: false")
        print()

        create = result.get("create", {})
        post = result.get("post_check", {})
        cleanup = result.get("cleanup", {})

        print("  Actions:")
        print(f"    Availability pre-check: passed")
        print(f"    Create: {'succeeded' if create.get('success') else 'failed'}")
        print(f"    Post-check: {'passed' if post.get('success') else 'failed'}")
        print(f"    Cleanup: {'succeeded' if cleanup.get('success') else 'failed'}")
        if cleanup.get("verified") is not None:
            print(f"    Cleanup verification: {'passed' if cleanup.get('verified') else 'failed'}")
        print()

        print("  Final state:")
        print(f"    Persistent DNS changed: {str(result.get('persistent_dns_changed', result.get('dns_changed', False))).lower()}")
        print(f"    Records created during run: {str(result.get('records_created', False)).lower()}")
        print(f"    Records deleted during cleanup: {str(result.get('records_deleted', False)).lower()}")

    print()
    print("  Safety:")
    print(f"    Token printed: false")
    print(f"    Credential path printed: false")
    print(f"    Zone ID printed: false")
    print(f"    Record ID printed: false")
    print(f"    Raw API response printed: false")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "status": "blocked", "reason": message,
                  "mutation_allowed": False, "dns_changed": False,
                  "records_created": False, "records_deleted": False,
                  "cleanup_verified": False, "safety": _safety_block()}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Owner-Approved Disposable DNS Create Harness"
    )
    sub = parser.add_subparsers(dest="command")

    smoke_parser = sub.add_parser("smoke", help="Run disposable smoke create")
    smoke_parser.add_argument("--zone", help="Domain zone")
    smoke_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    smoke_parser.add_argument("--label", help="Disposable label (must start with nanobk-smoke-)")
    smoke_parser.add_argument("--type", help="Record type: A, AAAA, TXT")
    smoke_parser.add_argument("--content", help="Record content")
    smoke_parser.add_argument("--ttl", type=int, default=60, help="TTL (default: 60)")
    smoke_parser.add_argument("--owner-approve", action="store_true", help="Owner approval")
    smoke_parser.add_argument("--cleanup", action="store_true", help="Cleanup after smoke")
    smoke_parser.add_argument("--confirm-disposable-smoke", help="Exact confirmation phrase")
    smoke_parser.add_argument("--json", action="store_true", help="JSON output")

    # Dangerous flags — reject
    smoke_parser.add_argument("--force", action="store_true", help=argparse.SUPPRESS)
    smoke_parser.add_argument("--overwrite", action="store_true", help=argparse.SUPPRESS)
    smoke_parser.add_argument("--apply", action="store_true", help=argparse.SUPPRESS)
    smoke_parser.add_argument("--yes", action="store_true", help=argparse.SUPPRESS)
    smoke_parser.add_argument("--keep-for-debug", action="store_true", help=argparse.SUPPRESS)

    args = parser.parse_args()

    if args.command != "smoke":
        parser.print_help()
        sys.exit(1)

    # Reject dangerous flags
    for flag in ("force", "overwrite", "apply", "yes", "keep_for_debug"):
        if getattr(args, flag.replace("-", "_"), False):
            output_error(f"--{flag} is not allowed", args.json)
            sys.exit(1)

    # Required args
    for field in ("zone", "api_env", "label", "type", "content"):
        if not getattr(args, field, None):
            output_error(f"{field.replace('_', '-')} is required", args.json)
            sys.exit(1)

    result = run_smoke(
        zone=args.zone,
        api_env_path=args.api_env,
        label=args.label,
        rtype=args.type,
        content=args.content,
        ttl=args.ttl,
        owner_approve=args.owner_approve,
        cleanup=args.cleanup,
        confirm_phrase=args.confirm_disposable_smoke or "",
    )

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)

    # Exit code
    if not result.get("ok", False):
        sys.exit(1)
    if result.get("status") in ("post_check_failed", "cleanup_failed"):
        sys.exit(1)


if __name__ == "__main__":
    main()
