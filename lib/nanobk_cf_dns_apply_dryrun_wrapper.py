#!/usr/bin/env python3
"""
NanoBK DNS Apply Dry-run Wrapper — Non-public dry-run-only wrapper.

Validates local input structure, credential reference permissions, and
generates redacted preview summary. Can call the existing helper's safe
--dry-run path (no API calls, no mutation). If no safe helper dry-run path
is available, generates wrapper-level preview only.

NOT imported by bin/nanobk. NOT a user-facing command. NOT public CLI.
Default mode is dry-run/read-only.
A non-public owner-approved one-record live create path exists behind
explicit local flags and exact approval phrase.
No public apply path exists.
Update/delete/overwrite remain blocked.
Does not print real domain, hostname, IP, token, API response, env path,
subscription URL, workers.dev URL, protocol URI, private key, Authorization
header, record ID, zone ID, account ID.
Does not cat/source/eval real env files.
Does not echo tokens.
Does not print raw helper stdout/stderr.

can_apply is always "no" in public/beginner semantics.
mutation_allowed is always "no" outside the internal owner-approved live create gate.
public_apply_allowed is always "no".

Usage:
    from nanobk_cf_dns_apply_dryrun_wrapper import run_dns_apply_dryrun_wrapper
    model = run_dns_apply_dryrun_wrapper(fixture_dict)
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

# ── Constants ────────────────────────────────────────────────────────────────

_STATUS_DRYRUN_READY = "dryrun_preview_ready"
_STATUS_BLOCKED = "blocked"
_STATUS_UNCERTAIN = "uncertain"

# ── Forbidden output patterns ────────────────────────────────────────────────

_FORBIDDEN_PATTERNS: list[re.Pattern] = [
    re.compile(r"example\.com", re.IGNORECASE),
    re.compile(r"203\.0\.113\.10"),
    re.compile(r"2001:db8::10", re.IGNORECASE),
    re.compile(r"rec-new-001"),
    re.compile(r"recordId", re.IGNORECASE),
    re.compile(r"record ID", re.IGNORECASE),
    re.compile(r"Zone ID", re.IGNORECASE),
    re.compile(r"Account ID", re.IGNORECASE),
    re.compile(r"CF_API_TOKEN", re.IGNORECASE),
    re.compile(r"Authorization", re.IGNORECASE),
    re.compile(r"api-env", re.IGNORECASE),
    re.compile(r"cloudflare-api\.env", re.IGNORECASE),
    re.compile(r"raw API request", re.IGNORECASE),
    re.compile(r"raw API response", re.IGNORECASE),
    re.compile(r"/zones/", re.IGNORECASE),
    re.compile(r"dns_records", re.IGNORECASE),
    re.compile(r"workers\.dev", re.IGNORECASE),
    re.compile(r"subscription URL", re.IGNORECASE),
    re.compile(r"vless://", re.IGNORECASE),
    re.compile(r"trojan://", re.IGNORECASE),
    re.compile(r"hysteria2://", re.IGNORECASE),
    re.compile(r"tuic://", re.IGNORECASE),
    re.compile(r"PRIVATE KEY", re.IGNORECASE),
    re.compile(r"Reality private key", re.IGNORECASE),
    re.compile(r"apply --yes", re.IGNORECASE),
    re.compile(r"[a-f0-9]{64}"),  # full sha256-like hex
]

_DRYRUN_SAFE_ERROR_MSG = (
    "NanoBK DNS Apply dry-run wrapper requires a valid fixture dict.\n"
    "No DNS changes were changed."
)

_CREDENTIAL_SAFE_MODES = {0o400, 0o600}

_CREDENTIAL_REASON_MISSING = "credential reference missing"
_CREDENTIAL_REASON_NOT_REGULAR = "credential reference is not a regular file"
_CREDENTIAL_REASON_PERMISSION = "credential permission not restricted"
_CREDENTIAL_REASON_UNAVAILABLE = "credential metadata unavailable"

_REASON_MALFORMED = "malformed dryrun input"

# ── Read-only precheck plan reasons ──────────────────────────────────────────

_READONLY_REASON_MISSING = "readonly precheck plan missing"
_READONLY_REASON_UNSAFE_ZONE = "unsafe zone category"
_READONLY_REASON_UNSAFE_RECORD = "unsafe record category"
_READONLY_REASON_UNSAFE_TYPE = "unsafe record type"
_READONLY_REASON_UNSAFE_CONTENT = "unsafe expected content category"
_READONLY_REASON_CNAME = "same-name CNAME not cleared"
_READONLY_REASON_UNMANAGED = "existing unmanaged record present"
_READONLY_REASON_DELETE = "delete planned"
_READONLY_REASON_OVERWRITE = "overwrite planned"
_READONLY_REASON_RAW_VALUES = "raw values present"
_READONLY_REASON_UNCERTAIN = "readonly precheck uncertain"

# ── Blocked reason categories (safe generic) ─────────────────────────────────

_REASON_REPO = "repo gate failed"
_REASON_CREDENTIAL = "credential reference gate failed"
_REASON_RECORD = "record identity gate failed"
_REASON_PRECHECK = "read-only pre-check gate failed"
_REASON_PREVIEW = "dry-run preview gate failed"
_REASON_HELPER = "helper dry-run gate failed"
_REASON_REDACTION = "redaction gate failed"
_REASON_PUBLIC_UX = "public UX gate failed"

# ── Gate evaluation order ────────────────────────────────────────────────────

_GATE_ORDER = [
    ("repo_gate", _REASON_REPO),
    ("credential_reference_gate", _REASON_CREDENTIAL),
    ("record_identity_gate", _REASON_RECORD),
    ("read_only_precheck_gate", _REASON_PRECHECK),
    ("dryrun_preview_gate", _REASON_PREVIEW),
    ("helper_dryrun_gate", _REASON_HELPER),
    ("redaction_gate", _REASON_REDACTION),
    ("public_ux_gate", _REASON_PUBLIC_UX),
]


# ── Local credential reference evaluator ─────────────────────────────────────


def evaluate_local_credential_reference(ref: dict) -> dict:
    """Evaluate local credential reference metadata without reading contents.

    Only performs stat/metadata checks. Never reads file contents.
    Never prints the path. Returns safe result dict.
    """
    result = {
        "credential_reference_present": "no",
        "credential_is_regular_file": "no",
        "credential_permission_restricted": "no",
        "credential_contents_read": "no",
        "credential_path_printed": "no",
        "status": "fail",
        "reason": _CREDENTIAL_REASON_MISSING,
    }

    local_path = ref.get("local_path")
    if not local_path or not isinstance(local_path, str):
        result["reason"] = _CREDENTIAL_REASON_MISSING
        return result

    p = Path(local_path)
    if not p.exists():
        result["reason"] = _CREDENTIAL_REASON_MISSING
        return result

    result["credential_reference_present"] = "yes"

    if not p.is_file():
        result["credential_is_regular_file"] = "no"
        result["reason"] = _CREDENTIAL_REASON_NOT_REGULAR
        return result

    result["credential_is_regular_file"] = "yes"

    # Check permissions — owner-readable, not group/world accessible
    try:
        st = p.stat()
        mode = st.st_mode & 0o7777
        # Check group/other bits: any group/other read/write/execute = not restricted
        group_other = mode & 0o077
        if group_other != 0:
            result["credential_permission_restricted"] = "no"
            result["reason"] = _CREDENTIAL_REASON_PERMISSION
            return result
        # Owner must have read (0o400 or 0o600)
        owner_bits = mode & 0o700
        if owner_bits not in (0o400, 0o600):
            result["credential_permission_restricted"] = "no"
            result["reason"] = _CREDENTIAL_REASON_PERMISSION
            return result
        result["credential_permission_restricted"] = "yes"
    except OSError:
        result["reason"] = _CREDENTIAL_REASON_UNAVAILABLE
        return result

    result["status"] = "pass"
    result["reason"] = "credential reference valid"
    return result


# ── Read-only precheck plan adapter ──────────────────────────────────────────


def build_readonly_precheck_plan(plan: dict) -> dict:
    """Build safe read-only precheck metadata from plan.

    Consumes safe fields from plan.readonly_precheck_plan.
    Returns safe metadata only — no real values.
    """
    result = {
        "readonly_precheck_plan_present": "no",
        "safe_zone_category": "no",
        "safe_record_category": "no",
        "safe_record_type": "no",
        "safe_expected_content_category": "no",
        "same_name_cname_absent": "unknown",
        "existing_unmanaged_record_absent": "unknown",
        "delete_planned": "unknown",
        "overwrite_planned": "unknown",
        "raw_values_present": "unknown",
        "status": "fail",
        "reason": _READONLY_REASON_MISSING,
    }

    ro = plan.get("readonly_precheck_plan")
    if not isinstance(ro, dict):
        result["reason"] = _READONLY_REASON_MISSING
        return result

    result["readonly_precheck_plan_present"] = "yes"

    # Check safe zone category
    zone = ro.get("safe_zone_category", "")
    if not isinstance(zone, str) or not zone:
        result["reason"] = _READONLY_REASON_UNSAFE_ZONE
        return result
    result["safe_zone_category"] = "yes"

    # Check safe record category
    record_cat = ro.get("safe_record_category", "")
    if not isinstance(record_cat, str) or not record_cat:
        result["reason"] = _READONLY_REASON_UNSAFE_RECORD
        return result
    result["safe_record_category"] = "yes"

    # Check safe record type
    rtype = ro.get("record_type", "")
    if rtype not in ("A", "AAAA"):
        result["reason"] = _READONLY_REASON_UNSAFE_TYPE
        return result
    result["safe_record_type"] = "yes"

    # Check safe expected content category
    content_cat = ro.get("expected_content_category", "")
    if not isinstance(content_cat, str) or not content_cat:
        result["reason"] = _READONLY_REASON_UNSAFE_CONTENT
        return result
    result["safe_expected_content_category"] = "yes"

    # Check same-name CNAME absent
    cname = ro.get("same_name_cname_absent")
    if cname is True:
        result["same_name_cname_absent"] = "yes"
    elif cname is False:
        result["same_name_cname_absent"] = "no"
        result["reason"] = _READONLY_REASON_CNAME
        return result
    else:
        result["same_name_cname_absent"] = "unknown"
        result["reason"] = _READONLY_REASON_UNCERTAIN
        return result

    # Check existing unmanaged record absent
    unmanaged = ro.get("existing_unmanaged_record_absent")
    if unmanaged is True:
        result["existing_unmanaged_record_absent"] = "yes"
    elif unmanaged is False:
        result["existing_unmanaged_record_absent"] = "no"
        result["reason"] = _READONLY_REASON_UNMANAGED
        return result
    else:
        result["existing_unmanaged_record_absent"] = "unknown"
        result["reason"] = _READONLY_REASON_UNCERTAIN
        return result

    # Check delete planned
    delete = ro.get("delete_planned")
    if delete is False:
        result["delete_planned"] = "no"
    elif delete is True:
        result["delete_planned"] = "yes"
        result["reason"] = _READONLY_REASON_DELETE
        return result
    else:
        result["delete_planned"] = "unknown"
        result["reason"] = _READONLY_REASON_UNCERTAIN
        return result

    # Check overwrite planned
    overwrite = ro.get("overwrite_planned")
    if overwrite is False:
        result["overwrite_planned"] = "no"
    elif overwrite is True:
        result["overwrite_planned"] = "yes"
        result["reason"] = _READONLY_REASON_OVERWRITE
        return result
    else:
        result["overwrite_planned"] = "unknown"
        result["reason"] = _READONLY_REASON_UNCERTAIN
        return result

    # Check raw values present
    raw = ro.get("raw_values_present")
    if raw is False:
        result["raw_values_present"] = "no"
    elif raw is True:
        result["raw_values_present"] = "yes"
        result["reason"] = _READONLY_REASON_RAW_VALUES
        return result
    else:
        result["raw_values_present"] = "unknown"
        result["reason"] = _READONLY_REASON_UNCERTAIN
        return result

    result["status"] = "pass"
    result["reason"] = "readonly precheck plan valid"
    return result


# ── Read-only Cloudflare token loading ───────────────────────────────────────


def load_readonly_cloudflare_token_from_reference(ref: dict) -> dict:
    """Load Cloudflare token from local credential reference.

    Only called when --allow-readonly-probe is present and credential gate passed.
    May open/read the credential file internally.
    Never prints path or token. Returns safe metadata only.
    """
    result = {
        "token_loaded": "no",
        "token_source": "credential_reference",
        "token_printed": "no",
        "credential_path_printed": "no",
        "status": "fail",
        "reason": "token key missing",
        "_token": None,  # internal only, never rendered
    }

    local_path = ref.get("local_path")
    if not local_path or not isinstance(local_path, str):
        result["reason"] = "token key missing"
        return result

    p = Path(local_path)
    if not p.exists() or not p.is_file():
        result["reason"] = "credential read failed"
        return result

    try:
        content = p.read_text(encoding="utf-8")
    except OSError:
        result["reason"] = "credential read failed"
        return result

    # Reject multiline or obviously malformed env
    lines = content.strip().splitlines()
    if len(lines) > 10:
        result["reason"] = "credential parse failed"
        return result

    # Parse safe key-value pairs
    token = None
    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip("\"'")
        if key in ("CLOUDFLARE_API_TOKEN", "CF_API_TOKEN"):
            token = value
            break

    if token is None:
        result["reason"] = "token key missing"
        return result

    if not token:
        result["reason"] = "token empty"
        return result

    result["token_loaded"] = "yes"
    result["_token"] = token
    result["status"] = "pass"
    result["reason"] = "token loaded"
    return result


# ── DNS record read-only precheck ────────────────────────────────────────────


def run_cloudflare_dns_record_readonly_precheck(
    plan: dict, token: str | None, *, allow_probe: bool
) -> dict:
    """Run a read-only Cloudflare DNS record GET precheck.

    If allow_probe is false, returns immediately with dns_record_get_called=no.
    If token is missing, returns blocked/uncertain.
    Only GET is allowed. No POST/PATCH/PUT/DELETE.
    Never prints raw URL, response, zone_id, record name, IP, or record ID.
    """
    result = {
        "dns_record_precheck_enabled": "no",
        "dns_record_get_called": "no",
        "dns_record_get_succeeded": "unknown",
        "same_name_cname_absent": "unknown",
        "existing_unmanaged_record_absent": "unknown",
        "existing_managed_test_record": "unknown",
        "create_only_first_safe": "unknown",
        "record_count_category": "unknown",
        "raw_dns_values_printed": "no",
        "raw_api_response_printed": "no",
        "record_id_printed": "no",
        "status": "fail",
        "reason": "dns record precheck not enabled",
    }

    if not allow_probe:
        result["reason"] = "dns record precheck not enabled"
        return result

    if not token:
        result["reason"] = "token unavailable"
        return result

    # Check readonly_dns_record_precheck plan
    precheck_plan = plan.get("readonly_dns_record_precheck", {})
    if not isinstance(precheck_plan, dict) or not precheck_plan.get("enabled"):
        result["reason"] = "dns record precheck not enabled"
        return result

    result["dns_record_precheck_enabled"] = "yes"

    # Get local-only values (never rendered)
    zone_id = precheck_plan.get("zone_id_local", "")
    record_name = precheck_plan.get("record_name_local", "")
    record_type = precheck_plan.get("record_type_local", "A")
    managed_marker = precheck_plan.get("managed_marker", "nanobk-test")
    allow_existing_managed = precheck_plan.get("allow_existing_managed_test_record", False)
    cname_must_be_absent = precheck_plan.get("same_name_cname_must_be_absent", True)
    unmanaged_must_be_absent = precheck_plan.get("existing_unmanaged_must_be_absent", True)

    if not zone_id or not record_name:
        result["reason"] = "dns record precheck not enabled"
        return result

    # Get base URL from readonly_probe plan
    probe_plan = plan.get("readonly_probe", {})
    base_url = probe_plan.get("base_url", "https://api.cloudflare.com/client/v4")

    # Perform GET request
    import urllib.request
    import urllib.error
    import urllib.parse

    # Build query URL — never printed
    params = urllib.parse.urlencode({"name": record_name, "type": record_type})
    url = f"{base_url}/zones/{zone_id}/dns_records?{params}"

    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            result["dns_record_get_called"] = "yes"
            if resp.status == 200:
                raw_body = resp.read().decode("utf-8")
                try:
                    body = json.loads(raw_body)
                except (json.JSONDecodeError, ValueError):
                    result["dns_record_get_succeeded"] = "no"
                    result["status"] = "fail"
                    result["reason"] = "dns record GET failed"
                    return result

                result["dns_record_get_succeeded"] = "yes"
                records = body.get("result", [])

                # Classify records
                cname_records = [r for r in records if r.get("type") == "CNAME"]
                matching_records = [r for r in records if r.get("type") == record_type]

                # Check CNAME conflict
                if cname_must_be_absent and cname_records:
                    result["same_name_cname_absent"] = "no"
                    result["create_only_first_safe"] = "no"
                    result["status"] = "fail"
                    result["reason"] = "same-name CNAME present"
                    return result
                result["same_name_cname_absent"] = "yes"

                # Check record count
                count = len(matching_records)
                if count == 0:
                    result["record_count_category"] = "zero"
                    result["existing_unmanaged_record_absent"] = "yes"
                    result["existing_managed_test_record"] = "no"
                    result["create_only_first_safe"] = "yes"
                    result["status"] = "pass"
                    result["reason"] = "create-only-first safe"
                elif count == 1:
                    rec = matching_records[0]
                    comment = rec.get("comment", "") or ""
                    is_managed = managed_marker in comment
                    result["record_count_category"] = "one"

                    if is_managed:
                        result["existing_managed_test_record"] = "yes"
                        result["existing_unmanaged_record_absent"] = "yes"
                        result["create_only_first_safe"] = "no"
                        result["status"] = "fail"
                        result["reason"] = "managed test record present"
                    else:
                        result["existing_managed_test_record"] = "no"
                        result["existing_unmanaged_record_absent"] = "no"
                        result["create_only_first_safe"] = "no"
                        result["status"] = "fail"
                        result["reason"] = "existing unmanaged record present"
                else:
                    result["record_count_category"] = "multiple"
                    result["existing_unmanaged_record_absent"] = "no"
                    result["existing_managed_test_record"] = "no"
                    result["create_only_first_safe"] = "no"
                    result["status"] = "fail"
                    result["reason"] = "multiple matching records"

            else:
                result["dns_record_get_succeeded"] = "no"
                result["status"] = "fail"
                result["reason"] = "dns record GET failed"

    except urllib.error.URLError:
        result["dns_record_get_called"] = "yes"
        result["dns_record_get_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "dns record GET failed"
    except TimeoutError:
        result["dns_record_get_called"] = "yes"
        result["dns_record_get_succeeded"] = "no"
        result["status"] = "uncertain"
        result["reason"] = "dns record GET timed out"
    except Exception:
        result["dns_record_get_called"] = "yes"
        result["dns_record_get_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "dns record GET failed"

    return result


# ── Read-only Cloudflare GET probe ───────────────────────────────────────────


def run_cloudflare_readonly_get_probe(
    plan: dict, token: str | None, *, allow_probe: bool
) -> dict:
    """Run a read-only Cloudflare GET probe.

    If allow_probe is false, returns immediately with cloudflare_get_called=no.
    If token is missing, returns blocked/uncertain.
    Only GET is allowed. No POST/PATCH/PUT/DELETE.
    Never prints raw response, URL with real values, or token.
    """
    result = {
        "readonly_probe_allowed": "yes" if allow_probe else "no",
        "cloudflare_get_called": "no",
        "cloudflare_get_succeeded": "unknown",
        "raw_api_response_printed": "no",
        "mutation_method_used": "no",
        "status": "fail",
        "reason": "readonly probe not allowed",
    }

    if not allow_probe:
        result["reason"] = "readonly probe not allowed"
        return result

    if not token:
        result["reason"] = "token unavailable"
        return result

    # Check readonly_probe plan
    probe_plan = plan.get("readonly_probe", {})
    if not isinstance(probe_plan, dict) or not probe_plan.get("enabled"):
        result["reason"] = "readonly probe not enabled"
        return result

    # Check mutation methods blocked
    if not probe_plan.get("mutation_methods_blocked", True):
        result["reason"] = "readonly GET unsafe endpoint blocked"
        return result

    # Check method allowlist — normalize and block anything other than GET
    allowed_methods = [str(m).upper() for m in probe_plan.get("method_allowlist", ["GET"])]
    if any(m != "GET" for m in allowed_methods):
        result["reason"] = "readonly GET unsafe endpoint blocked"
        return result

    base_url = probe_plan.get("base_url", "https://api.cloudflare.com/client/v4")
    endpoint = "/user/tokens/verify"

    # Perform GET request
    import urllib.request
    import urllib.error

    url = f"{base_url}{endpoint}"
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            result["cloudflare_get_called"] = "yes"
            if resp.status == 200:
                result["cloudflare_get_succeeded"] = "yes"
                result["status"] = "pass"
                result["reason"] = "readonly GET succeeded"
            else:
                result["cloudflare_get_succeeded"] = "no"
                result["status"] = "fail"
                result["reason"] = "readonly GET failed"
    except urllib.error.URLError:
        result["cloudflare_get_called"] = "yes"
        result["cloudflare_get_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "readonly GET failed"
    except TimeoutError:
        result["cloudflare_get_called"] = "yes"
        result["cloudflare_get_succeeded"] = "no"
        result["status"] = "uncertain"
        result["reason"] = "readonly GET timed out"
    except Exception:
        result["cloudflare_get_called"] = "yes"
        result["cloudflare_get_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "readonly GET failed"

    return result


# ── Individual gate evaluators ───────────────────────────────────────────────


def _eval_repo_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("clean") is True
        and gate.get("expected_head") is True
        and gate.get("no_public_integration") is True
    )


def _eval_credential_reference_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("reference_present") is True
        and gate.get("permission_restricted") is True
        and gate.get("contents_not_read") is True
        and gate.get("path_not_printed") is True
        and gate.get("token_not_echoed") is True
    )


def _eval_record_identity_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("one_record_only") is True
        and gate.get("disposable_test_record") is True
        and gate.get("dns_only") is True
        and gate.get("create_only_first") is True
        and gate.get("no_delete") is True
        and gate.get("no_overwrite") is True
        and gate.get("no_production_name") is True
        and gate.get("same_name_cname_absent") is True
    )


def _eval_read_only_precheck_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("read_only") is True
        and gate.get("safe_record_category") is True
        and gate.get("no_existing_unmanaged_record") is True
        and gate.get("no_delete_planned") is True
        and gate.get("no_overwrite_planned") is True
    )


def _eval_dryrun_preview_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("preview_generated") is True
        and gate.get("preview_redacted") is True
        and gate.get("raw_mutation_command_printed") is False
    )


def _eval_helper_dryrun_gate(gate: dict) -> bool:
    if not isinstance(gate, dict):
        return False
    # If helper dry-run is available, it must have been called successfully
    if gate.get("helper_dryrun_available") is True:
        return (
            gate.get("helper_called_in_dryrun_only") is True
            and gate.get("returncode") == 0
            and gate.get("stdout_captured") is True
            and gate.get("stderr_captured") is True
            and gate.get("raw_output_printed") is False
        )
    # If helper dry-run is not available, wrapper preview must be generated
    if gate.get("helper_dryrun_available") is False:
        return gate.get("wrapper_preview_generated") is True
    return False


def _eval_redaction_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("redaction_passed") is True
        and gate.get("no_secret_or_address") is True
        and gate.get("no_raw_api") is True
        and gate.get("no_raw_helper_output") is True
    )


def _eval_public_ux_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("bin_integration") is False
        and gate.get("bot_apply") is False
        and gate.get("web_apply") is False
        and gate.get("installer_apply") is False
    )


_GATE_EVALUATORS = {
    "repo_gate": _eval_repo_gate,
    "credential_reference_gate": _eval_credential_reference_gate,
    "record_identity_gate": _eval_record_identity_gate,
    "read_only_precheck_gate": _eval_read_only_precheck_gate,
    "dryrun_preview_gate": _eval_dryrun_preview_gate,
    "helper_dryrun_gate": _eval_helper_dryrun_gate,
    "redaction_gate": _eval_redaction_gate,
    "public_ux_gate": _eval_public_ux_gate,
}


# ── Dry-run wrapper evaluator ────────────────────────────────────────────────


def run_dns_apply_dryrun_wrapper(data: dict) -> dict:
    """Run dry-run wrapper evaluation from safe fixture dict.

    Evaluates all gates for diagnostic step visibility, but exposes only the
    first failed gate/reason to beginner-safe output.

    Returns safe model with status, can_preview, can_apply, redacted_preview.

    Raises RuntimeError on invalid input.
    """
    if not isinstance(data, dict):
        raise RuntimeError(_DRYRUN_SAFE_ERROR_MSG)

    mode = data.get("mode", "dryrun_only")
    if mode != "dryrun_only":
        mode = "dryrun_only"

    checks: dict[str, str] = {}
    diagnostic_blocked_reasons: list[str] = []
    first_failed_gate = "none"
    first_blocked_reason = "none"
    has_missing_gate = False
    has_known_policy_failure = False

    # Evaluate local credential reference if present (real local check)
    local_cred_ref = data.get("credential_reference")
    local_cred_result: dict | None = None
    if isinstance(local_cred_ref, dict):
        # credential_reference key exists — use real local evaluation
        local_cred_result = evaluate_local_credential_reference(local_cred_ref)

    # Evaluate read-only precheck plan if present
    readonly_precheck_result: dict | None = None
    if "readonly_precheck_plan" in data:
        readonly_precheck_result = build_readonly_precheck_plan(data)

    # Evaluate all gates in order
    for gate_key, reason in _GATE_ORDER:
        # Special handling for credential_reference_gate with local path
        if gate_key == "credential_reference_gate" and local_cred_result is not None:
            if local_cred_result["status"] == "pass":
                checks[gate_key] = "pass"
            else:
                checks[gate_key] = "fail"
                has_known_policy_failure = True
                cred_reason = local_cred_result.get("reason", reason)
                diagnostic_blocked_reasons.append(cred_reason)
                if first_failed_gate == "none":
                    first_failed_gate = gate_key
                    first_blocked_reason = cred_reason
            continue

        # Special handling for read_only_precheck_gate with readonly_precheck_plan
        if gate_key == "read_only_precheck_gate" and readonly_precheck_result is not None:
            ro_status = readonly_precheck_result.get("status", "fail")
            if ro_status == "pass":
                checks[gate_key] = "pass"
            elif ro_status == "uncertain":
                checks[gate_key] = "fail"
                has_missing_gate = True
                ro_reason = readonly_precheck_result.get("reason", _READONLY_REASON_UNCERTAIN)
                diagnostic_blocked_reasons.append(ro_reason)
                if first_failed_gate == "none":
                    first_failed_gate = gate_key
                    first_blocked_reason = ro_reason
            else:
                checks[gate_key] = "fail"
                has_known_policy_failure = True
                ro_reason = readonly_precheck_result.get("reason", reason)
                diagnostic_blocked_reasons.append(ro_reason)
                if first_failed_gate == "none":
                    first_failed_gate = gate_key
                    first_blocked_reason = ro_reason
            continue

        gate_data = data.get(gate_key)
        if gate_data is None:
            checks[gate_key] = "fail"
            has_missing_gate = True
            diagnostic_blocked_reasons.append(_REASON_MALFORMED)
            if first_failed_gate == "none":
                first_failed_gate = gate_key
                first_blocked_reason = _REASON_MALFORMED
            continue

        evaluator = _GATE_EVALUATORS.get(gate_key)
        if evaluator and evaluator(gate_data):
            checks[gate_key] = "pass"
        else:
            checks[gate_key] = "fail"
            has_known_policy_failure = True
            diagnostic_blocked_reasons.append(reason)
            if first_failed_gate == "none":
                first_failed_gate = gate_key
                first_blocked_reason = reason

    # blocked_reasons contains only first known policy failure (beginner-facing)
    blocked_reasons: list[str] = []
    if has_known_policy_failure and not has_missing_gate:
        for gate_key, reason in _GATE_ORDER:
            if checks.get(gate_key) == "fail" and data.get(gate_key) is not None:
                blocked_reasons.append(reason)
                break

    # Extract helper dryrun availability for summary
    helper_gate = data.get("helper_dryrun_gate", {})
    helper_dryrun_available = False
    if isinstance(helper_gate, dict):
        helper_dryrun_available = helper_gate.get("helper_dryrun_available", False)

    # Determine overall status
    all_pass = all(v == "pass" for v in checks.values())

    if all_pass:
        status = _STATUS_DRYRUN_READY
        can_preview = "yes"
    elif has_missing_gate:
        status = _STATUS_UNCERTAIN
        can_preview = "no"
    elif has_known_policy_failure:
        status = _STATUS_BLOCKED
        can_preview = "no"
    else:
        status = _STATUS_UNCERTAIN
        can_preview = "no"

    # Build redacted preview (safe categories only)
    record_plan = data.get("record_plan", {})
    preview: dict[str, Any] = {
        "safe_record_category": "unknown",
        "safe_action_category": "unknown",
        "record_type": "unknown",
        "dns_only": "unknown",
        "helper_dryrun_available": "yes" if helper_dryrun_available else "no",
    }
    if isinstance(record_plan, dict):
        preview["safe_record_category"] = record_plan.get("safe_record_category", "unknown")
        preview["safe_action_category"] = record_plan.get("safe_action_category", "unknown")
        preview["record_type"] = record_plan.get("record_type", "unknown")
        preview["dns_only"] = record_plan.get("dns_only", "unknown")

    # Build safe credential reference metadata (no path, no contents)
    if local_cred_result is not None:
        cred_meta = {
            "credential_reference_present": local_cred_result["credential_reference_present"],
            "credential_is_regular_file": local_cred_result["credential_is_regular_file"],
            "credential_permission_restricted": local_cred_result["credential_permission_restricted"],
            "credential_contents_read": "no",
            "credential_path_printed": "no",
        }
    else:
        cred_meta = {
            "credential_reference_present": "no",
            "credential_is_regular_file": "no",
            "credential_permission_restricted": "no",
            "credential_contents_read": "no",
            "credential_path_printed": "no",
        }

    # Build readonly precheck metadata (safe categories only)
    if readonly_precheck_result is not None:
        ro_meta = {
            "readonly_precheck_plan_present": readonly_precheck_result["readonly_precheck_plan_present"],
            "safe_zone_category": readonly_precheck_result["safe_zone_category"],
            "safe_record_category": readonly_precheck_result["safe_record_category"],
            "safe_record_type": readonly_precheck_result["safe_record_type"],
            "safe_expected_content_category": readonly_precheck_result["safe_expected_content_category"],
            "same_name_cname_absent": readonly_precheck_result["same_name_cname_absent"],
            "existing_unmanaged_record_absent": readonly_precheck_result["existing_unmanaged_record_absent"],
            "delete_planned": readonly_precheck_result["delete_planned"],
            "overwrite_planned": readonly_precheck_result["overwrite_planned"],
            "raw_values_present": readonly_precheck_result["raw_values_present"],
        }
    else:
        ro_meta = {
            "readonly_precheck_plan_present": "no",
            "safe_zone_category": "no",
            "safe_record_category": "no",
            "safe_record_type": "no",
            "safe_expected_content_category": "no",
            "same_name_cname_absent": "unknown",
            "existing_unmanaged_record_absent": "unknown",
            "delete_planned": "unknown",
            "overwrite_planned": "unknown",
            "raw_values_present": "unknown",
        }

    return {
        "status": status,
        "mode": mode,
        "can_preview": can_preview,
        "can_apply": "no",
        "mutation_allowed": "no",
        "public_apply_allowed": "no",
        "live_cloudflare_called": "no",
        "real_dns_mutation_performed": "no",
        "real_env_printed": "no",
        "raw_helper_output_printed": "no",
        "can_query": "no",
        "readonly_probe_allowed": "no",
        "cloudflare_get_called": "no",
        "raw_api_response_printed": "no",
        "first_failed_gate": first_failed_gate,
        "first_blocked_reason": first_blocked_reason,
        "blocked_reasons": blocked_reasons,
        "diagnostic_blocked_reasons": diagnostic_blocked_reasons,
        "redacted_preview": preview,
        "local_credential_reference": cred_meta,
        "readonly_precheck": ro_meta,
        "dns_record_precheck": {
            "dns_record_precheck_enabled": "no",
            "dns_record_get_called": "no",
            "dns_record_get_succeeded": "unknown",
            "same_name_cname_absent": "unknown",
            "existing_unmanaged_record_absent": "unknown",
            "existing_managed_test_record": "unknown",
            "create_only_first_safe": "unknown",
            "record_count_category": "unknown",
            "raw_dns_values_printed": "no",
            "raw_api_response_printed": "no",
            "record_id_printed": "no",
        },
    }


# ── Safe renderer ────────────────────────────────────────────────────────────


def render_dns_apply_dryrun_summary(model: dict) -> str:
    """Render beginner-safe dry-run summary from evaluated model."""
    status = model.get("status", "unknown")
    mode = model.get("mode", "unknown")
    can_preview = model.get("can_preview", "no")
    can_apply = model.get("can_apply", "no")
    mutation_allowed = model.get("mutation_allowed", "no")
    public_apply_allowed = model.get("public_apply_allowed", "no")
    live_cf = model.get("live_cloudflare_called", "no")
    real_mutation = model.get("real_dns_mutation_performed", "no")
    real_env = model.get("real_env_printed", "no")
    raw_helper = model.get("raw_helper_output_printed", "no")
    first_failed_gate = model.get("first_failed_gate", "none")
    first_blocked_reason = model.get("first_blocked_reason", "none")
    preview = model.get("redacted_preview", {})
    cred = model.get("local_credential_reference", {})
    ro = model.get("readonly_precheck", {})
    tok = model.get("token_metadata", {})
    dns = model.get("dns_record_precheck", {})
    lc = model.get("live_create", {})
    lcp = model.get("live_create_postcheck", {})
    lcl = model.get("live_cleanup_precheck", {})
    lcl2 = model.get("live_cleanup", {})

    lines = [
        "NanoBK DNS Apply — Non-Public Dry-run Wrapper Summary",
        f"Status: {status}",
        f"Mode: {mode}",
        f"Can preview: {can_preview}",
        f"Can apply: {can_apply}",
        f"Mutation allowed: {mutation_allowed}",
        f"Public apply allowed: {public_apply_allowed}",
        f"Live Cloudflare called: {live_cf}",
        f"Real DNS mutation performed: {real_mutation}",
        f"Real env printed: {real_env}",
        f"Raw helper output printed: {raw_helper}",
        f"Token loaded: {tok.get('token_loaded', 'no')}",
        f"Token printed: {tok.get('token_printed', 'no')}",
        f"Can query: {model.get('can_query', 'no')}",
        f"Read-only probe allowed: {model.get('readonly_probe_allowed', 'no')}",
        f"Cloudflare GET called: {model.get('cloudflare_get_called', 'no')}",
        f"Cloudflare GET succeeded: {model.get('cloudflare_get_succeeded', 'unknown')}",
        f"API response printed: {model.get('raw_api_response_printed', 'no')}",
        f"Mutation method used: {model.get('mutation_method_used', 'no')}",
        f"Credential reference present: {cred.get('credential_reference_present', 'no')}",
        f"Credential is regular file: {cred.get('credential_is_regular_file', 'no')}",
        f"Credential permission restricted: {cred.get('credential_permission_restricted', 'no')}",
        f"Credential contents read: {cred.get('credential_contents_read', 'no')}",
        f"Credential path printed: {cred.get('credential_path_printed', 'no')}",
        f"Read-only precheck plan present: {ro.get('readonly_precheck_plan_present', 'no')}",
        f"Safe zone category: {ro.get('safe_zone_category', 'no')}",
        f"Safe record category: {ro.get('safe_record_category', 'no')}",
        f"Safe record type: {ro.get('safe_record_type', 'no')}",
        f"Safe expected content category: {ro.get('safe_expected_content_category', 'no')}",
        f"Same-name CNAME absent: {ro.get('same_name_cname_absent', 'unknown')}",
        f"Existing unmanaged record absent: {ro.get('existing_unmanaged_record_absent', 'unknown')}",
        f"Delete planned: {ro.get('delete_planned', 'unknown')}",
        f"Overwrite planned: {ro.get('overwrite_planned', 'unknown')}",
        f"Raw values present: {ro.get('raw_values_present', 'unknown')}",
        f"DNS record precheck enabled: {dns.get('dns_record_precheck_enabled', 'no')}",
        f"DNS record GET called: {dns.get('dns_record_get_called', 'no')}",
        f"DNS record GET succeeded: {dns.get('dns_record_get_succeeded', 'unknown')}",
        f"Same-name CNAME absent: {dns.get('same_name_cname_absent', 'unknown')}",
        f"Existing unmanaged record absent: {dns.get('existing_unmanaged_record_absent', 'unknown')}",
        f"Existing managed test record: {dns.get('existing_managed_test_record', 'unknown')}",
        f"Create-only-first safe: {dns.get('create_only_first_safe', 'unknown')}",
        f"Record count category: {dns.get('record_count_category', 'unknown')}",
        f"Raw DNS values printed: {dns.get('raw_dns_values_printed', 'no')}",
        f"DNS identifier printed: {dns.get('record_id_printed', 'no')}",
        f"Owner approval present: {lc.get('owner_approval_present', 'no')}",
        f"Live create prerequisites passed: {lc.get('live_create_prerequisites_passed', 'no')}",
        f"Live create allowed: {lc.get('live_create_allowed', 'no')}",
        f"Live create called: {lc.get('live_create_called', 'no')}",
        f"Live create succeeded: {lc.get('live_create_succeeded', 'unknown')}",
        f"Created record category: {lc.get('created_record_category', 'none')}",
        f"Live create proxied: {lc.get('proxied', 'unknown')}",
        f"Live mutation method used: {lc.get('mutation_method_used', 'no')}",
        f"Delete called: {lc.get('delete_called', 'no')}",
        f"Update called: {lc.get('update_called', 'no')}",
        f"Live create post-check called: {lcp.get('postcheck_called', 'no')}",
        f"Live create post-check succeeded: {lcp.get('postcheck_succeeded', 'unknown')}",
        f"Created record found: {lcp.get('created_record_found', 'unknown')}",
        f"Created record type match: {lcp.get('created_record_type_match', 'unknown')}",
        f"Created record DNS-only: {lcp.get('created_record_dns_only', 'unknown')}",
        f"Created record managed: {lcp.get('created_record_managed', 'unknown')}",
        f"Post-check record count category: {lcp.get('record_count_category', 'unknown')}",
        f"Post-check raw DNS values printed: {lcp.get('raw_dns_values_printed', 'no')}",
        f"Post-check DNS identifier printed: {lcp.get('record_id_printed', 'no')}",
        f"Cleanup approval present: {lcl2.get('cleanup_approval_present', 'no')}",
        f"Cleanup precheck called: {lcl.get('cleanup_precheck_called', 'no')}",
        f"Cleanup precheck succeeded: {lcl.get('cleanup_precheck_succeeded', 'unknown')}",
        f"Cleanup record found: {lcl.get('cleanup_record_found', 'unknown')}",
        f"Cleanup record single match: {lcl.get('cleanup_record_single_match', 'unknown')}",
        f"Cleanup record managed: {lcl.get('cleanup_record_managed', 'unknown')}",
        f"Cleanup record DNS-only: {lcl.get('cleanup_record_dns_only', 'unknown')}",
        f"Cleanup safe: {lcl.get('cleanup_safe', 'unknown')}",
        f"Cleanup prerequisites passed: {lcl2.get('cleanup_prerequisites_passed', 'no')}",
        f"Cleanup allowed: {lcl2.get('cleanup_allowed', 'no')}",
        f"Cleanup called: {lcl2.get('cleanup_called', 'no')}",
        f"Cleanup succeeded: {lcl2.get('cleanup_succeeded', 'unknown')}",
        f"Deleted record category: {lcl2.get('deleted_record_category', 'none')}",
        f"Cleanup mutation method used: {lcl2.get('cleanup_mutation_method_used', 'no')}",
        f"Cleanup DNS identifier printed: {lcl2.get('record_id_printed', 'no')}",
        f"Cleanup API response printed: {lcl2.get('raw_api_response_printed', 'no')}",
        f"Cleanup update called: {lcl2.get('update_called', 'no')}",
        f"Cleanup create called: {lcl2.get('create_called', 'no')}",
    ]

    if status == _STATUS_DRYRUN_READY:
        lines.append("")
        lines.append("Dry-run preview is ready.")
        lines.append("This is not a live mutation.")
        lines.append("No DNS record was created, updated, or deleted.")
        lines.append("")
        lines.append("Redacted preview:")
        lines.append(f"  Record category: {preview.get('safe_record_category', 'unknown')}")
        lines.append(f"  Action category: {preview.get('safe_action_category', 'unknown')}")
        lines.append(f"  Record type: {preview.get('record_type', 'unknown')}")
        lines.append(f"  DNS-only: {preview.get('dns_only', 'unknown')}")
        lines.append(f"  Helper dry-run available: {preview.get('helper_dryrun_available', 'unknown')}")

    if status in (_STATUS_BLOCKED, _STATUS_UNCERTAIN) and first_failed_gate != "none":
        lines.append("")
        lines.append(f"First failed gate: {first_failed_gate}")
        lines.append(f"First blocked reason: {first_blocked_reason}")

    return "\n".join(lines) + "\n"


# ── Output safety gate ───────────────────────────────────────────────────────


class UnsafeDnsApplyDryrunOutputError(Exception):
    """Raised when rendered dry-run output contains forbidden patterns."""
    pass


def assert_safe_dns_apply_dryrun_output(text: str) -> None:
    """Fail closed if rendered output contains forbidden patterns.

    Raises UnsafeDnsApplyDryrunOutputError if any forbidden pattern is found.
    """
    for pattern in _FORBIDDEN_PATTERNS:
        if pattern.search(text):
            raise UnsafeDnsApplyDryrunOutputError(
                "DNS apply dry-run wrapper output contains forbidden pattern."
            )


# ── Helper dry-run detection ─────────────────────────────────────────────────


def detect_helper_dryrun_support(helper_path: str | None = None) -> dict:
    """Detect whether a safe helper dry-run path exists.

    Only inspects help/static capability if safe.
    Does not pass credentials. Does not call Cloudflare. Does not call mutation.

    Returns dict with helper_dryrun_available and reason.
    """
    if helper_path is None:
        return {
            "helper_dryrun_available": "no",
            "reason": "helper dry-run support not safely detected",
        }

    # Only check if the helper file exists and has --dry-run in its help
    try:
        import subprocess as _sp
        result = _sp.run(
            [sys.executable, helper_path, "--help"],
            capture_output=True, text=True, timeout=5,
            env={"PATH": "/usr/bin:/bin", "LANG": "C"},
        )
        if "--dry-run" in result.stdout:
            return {
                "helper_dryrun_available": "yes",
                "reason": "helper exposes --dry-run flag",
            }
    except Exception:
        pass

    return {
        "helper_dryrun_available": "no",
        "reason": "helper dry-run support not safely detected",
    }


# ── Probe prerequisites check ────────────────────────────────────────────────


def _probe_prerequisites_passed(model: dict) -> bool:
    """Check if all prerequisites are met before reading token or calling GET.

    Requires:
    - model status is dryrun_preview_ready
    - can_apply is no
    - mutation_allowed is no
    - public_apply_allowed is no
    - real_dns_mutation_performed is no
    - credential metadata all pass
    - readonly precheck metadata all pass (if present)
    """
    if model.get("status") != _STATUS_DRYRUN_READY:
        return False
    if model.get("can_apply") != "no":
        return False
    if model.get("mutation_allowed") != "no":
        return False
    if model.get("public_apply_allowed") != "no":
        return False
    if model.get("real_dns_mutation_performed") != "no":
        return False

    # Credential metadata must all pass
    cred = model.get("local_credential_reference", {})
    if cred.get("credential_reference_present") != "yes":
        return False
    if cred.get("credential_is_regular_file") != "yes":
        return False
    if cred.get("credential_permission_restricted") != "yes":
        return False
    if cred.get("credential_contents_read") != "no":
        return False
    if cred.get("credential_path_printed") != "no":
        return False

    # Readonly precheck metadata must all pass (if present)
    ro = model.get("readonly_precheck", {})
    if ro.get("readonly_precheck_plan_present") == "yes":
        if ro.get("safe_zone_category") != "yes":
            return False
        if ro.get("safe_record_category") != "yes":
            return False
        if ro.get("safe_record_type") != "yes":
            return False
        if ro.get("safe_expected_content_category") != "yes":
            return False
        if ro.get("same_name_cname_absent") != "yes":
            return False
        if ro.get("existing_unmanaged_record_absent") != "yes":
            return False
        if ro.get("delete_planned") != "no":
            return False
        if ro.get("overwrite_planned") != "no":
            return False
        if ro.get("raw_values_present") != "no":
            return False

    return True


# ── Live create prerequisites ────────────────────────────────────────────────

_LIVE_CREATE_APPROVAL_PHRASE = "I UNDERSTAND THIS WILL CREATE ONE CLOUDFLARE DNS TEST RECORD"


def evaluate_live_create_prerequisites(
    model: dict, plan: dict, approval: str | None
) -> dict:
    """Evaluate whether all prerequisites for live create are met.

    Requires exact owner approval phrase, all readonly prechecks passed,
    create_only_first_safe, and safe live_create_plan.
    """
    result = {
        "live_create_prerequisites_passed": "no",
        "owner_approval_present": "no",
        "one_record_only": "no",
        "create_only_first": "no",
        "dns_only": "no",
        "delete_allowed": "no",
        "update_allowed": "no",
        "overwrite_allowed": "no",
        "status": "fail",
        "reason": "owner approval missing",
    }

    # Check approval phrase
    if approval != _LIVE_CREATE_APPROVAL_PHRASE:
        result["reason"] = "owner approval missing"
        return result
    result["owner_approval_present"] = "yes"

    # Check model status
    if model.get("status") != _STATUS_DRYRUN_READY:
        result["reason"] = "readonly precheck not passed"
        return result

    # Check token and probe
    tok = model.get("token_metadata", {})
    if tok.get("token_loaded") != "yes":
        result["reason"] = "readonly precheck not passed"
        return result

    if model.get("cloudflare_get_succeeded") != "yes":
        result["reason"] = "readonly precheck not passed"
        return result

    # Check DNS record precheck
    dns = model.get("dns_record_precheck", {})
    if dns.get("dns_record_get_succeeded") != "yes":
        result["reason"] = "readonly precheck not passed"
        return result
    if dns.get("create_only_first_safe") != "yes":
        result["reason"] = "not create-only-first safe"
        return result
    if dns.get("record_count_category") != "zero":
        result["reason"] = "not create-only-first safe"
        return result
    if dns.get("same_name_cname_absent") != "yes":
        result["reason"] = "not create-only-first safe"
        return result
    if dns.get("existing_unmanaged_record_absent") != "yes":
        result["reason"] = "not create-only-first safe"
        return result
    if dns.get("existing_managed_test_record") != "no":
        result["reason"] = "not create-only-first safe"
        return result

    # Check safety fields
    if model.get("can_apply") != "no":
        result["reason"] = "readonly precheck not passed"
        return result
    if model.get("mutation_allowed") != "no":
        result["reason"] = "readonly precheck not passed"
        return result
    if model.get("public_apply_allowed") != "no":
        result["reason"] = "readonly precheck not passed"
        return result

    # Check live_create_plan
    live_plan = plan.get("live_create_plan", {})
    if not isinstance(live_plan, dict) or not live_plan.get("enabled"):
        result["reason"] = "live create plan missing"
        return result

    if live_plan.get("one_record_only") is not True:
        result["reason"] = "live create plan unsafe"
        return result
    result["one_record_only"] = "yes"

    if live_plan.get("create_only_first") is not True:
        result["reason"] = "live create plan unsafe"
        return result
    result["create_only_first"] = "yes"

    if live_plan.get("proxied") is not False:
        result["reason"] = "live create plan unsafe"
        return result
    result["dns_only"] = "yes"

    if live_plan.get("delete_allowed") is not False:
        result["reason"] = "live create plan unsafe"
        return result
    result["delete_allowed"] = "no"

    if live_plan.get("update_allowed") is not False:
        result["reason"] = "live create plan unsafe"
        return result
    result["update_allowed"] = "no"

    if live_plan.get("overwrite_allowed") is not False:
        result["reason"] = "live create plan unsafe"
        return result
    result["overwrite_allowed"] = "no"

    result["live_create_prerequisites_passed"] = "yes"
    result["status"] = "pass"
    result["reason"] = "live create prerequisites passed"
    return result


# ── Live create call ─────────────────────────────────────────────────────────


def run_cloudflare_one_record_live_create(
    plan: dict, token: str | None, *, allow_live_create: bool,
    approval: str | None, model: dict
) -> dict:
    """Run a one-record live create via Cloudflare POST.

    Only POST is allowed. No PUT/PATCH/DELETE.
    Never prints request URL, JSON body, raw response, or record ID.
    """
    result = {
        "live_create_allowed": "no",
        "live_create_called": "no",
        "live_create_succeeded": "unknown",
        "created_record_category": "none",
        "proxied": "unknown",
        "raw_dns_values_printed": "no",
        "raw_api_response_printed": "no",
        "record_id_printed": "no",
        "mutation_method_used": "no",
        "delete_called": "no",
        "update_called": "no",
        "status": "fail",
        "reason": "live create not allowed",
    }

    if not allow_live_create:
        result["reason"] = "live create not allowed"
        return result

    if approval != _LIVE_CREATE_APPROVAL_PHRASE:
        result["reason"] = "owner approval missing"
        return result

    if not token:
        result["reason"] = "live create prerequisites failed"
        return result

    # Evaluate prerequisites
    prereq = evaluate_live_create_prerequisites(model, plan, approval)
    if prereq["status"] != "pass":
        result["reason"] = prereq.get("reason", "live create prerequisites failed")
        return result

    result["live_create_allowed"] = "yes"

    # Get live create plan
    live_plan = plan.get("live_create_plan", {})
    if not isinstance(live_plan, dict):
        result["reason"] = "live create plan missing"
        return result

    zone_id = live_plan.get("zone_id_local", "")
    record_name = live_plan.get("record_name_local", "")
    record_type = live_plan.get("record_type_local", "A")
    content = live_plan.get("content_local", "")
    ttl = live_plan.get("ttl", 60)
    comment = live_plan.get("comment", "nanobk-test managed disposable record")

    if not zone_id or not record_name or not content:
        result["reason"] = "live create prerequisites failed"
        return result

    # Get base URL from readonly_probe plan
    probe_plan = plan.get("readonly_probe", {})
    base_url = probe_plan.get("base_url", "https://api.cloudflare.com/client/v4")

    # Build POST request
    import urllib.request
    import urllib.error

    url = f"{base_url}/zones/{zone_id}/dns_records"
    body = json.dumps({
        "type": record_type,
        "name": record_name,
        "content": content,
        "ttl": ttl,
        "proxied": False,
        "comment": comment,
    }).encode("utf-8")

    req = urllib.request.Request(url, data=body, method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            result["live_create_called"] = "yes"
            result["mutation_method_used"] = "POST"
            if resp.status in (200, 201):
                result["live_create_succeeded"] = "yes"
                result["created_record_category"] = "one_disposable_test_record"
                result["proxied"] = "false"
                result["status"] = "pass"
                result["reason"] = "live create succeeded"
            else:
                result["live_create_succeeded"] = "no"
                result["status"] = "fail"
                result["reason"] = "live create failed"
    except urllib.error.URLError:
        result["live_create_called"] = "yes"
        result["mutation_method_used"] = "POST"
        result["live_create_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "live create failed"
    except TimeoutError:
        result["live_create_called"] = "yes"
        result["mutation_method_used"] = "POST"
        result["live_create_succeeded"] = "no"
        result["status"] = "uncertain"
        result["reason"] = "live create timed out"
    except Exception:
        result["live_create_called"] = "yes"
        result["mutation_method_used"] = "POST"
        result["live_create_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "live create failed"

    return result


# ── Live create post-check ───────────────────────────────────────────────────


def run_cloudflare_live_create_postcheck(
    plan: dict, token: str | None, *, allow_postcheck: bool
) -> dict:
    """Run a read-only post-check after live create succeeds.

    Only GET is allowed. No POST/PATCH/PUT/DELETE.
    Never prints URL, response, zone_id, record name, IP, or record ID.
    """
    result = {
        "postcheck_called": "no",
        "postcheck_succeeded": "unknown",
        "created_record_found": "unknown",
        "created_record_type_match": "unknown",
        "created_record_dns_only": "unknown",
        "created_record_managed": "unknown",
        "record_count_category": "unknown",
        "raw_dns_values_printed": "no",
        "raw_api_response_printed": "no",
        "record_id_printed": "no",
        "status": "fail",
        "reason": "postcheck not called",
    }

    if not allow_postcheck:
        result["reason"] = "postcheck not called"
        return result

    if not token:
        result["reason"] = "postcheck not called"
        return result

    # Get live create plan for local-only values
    live_plan = plan.get("live_create_plan", {})
    if not isinstance(live_plan, dict):
        result["reason"] = "postcheck not called"
        return result

    zone_id = live_plan.get("zone_id_local", "")
    record_name = live_plan.get("record_name_local", "")
    record_type = live_plan.get("record_type_local", "A")
    managed_marker = live_plan.get("comment", "nanobk-test")

    if not zone_id or not record_name:
        result["reason"] = "postcheck not called"
        return result

    # Get base URL from readonly_probe plan
    probe_plan = plan.get("readonly_probe", {})
    base_url = probe_plan.get("base_url", "https://api.cloudflare.com/client/v4")

    # Perform GET request
    import urllib.request
    import urllib.error
    import urllib.parse

    params = urllib.parse.urlencode({"name": record_name, "type": record_type})
    url = f"{base_url}/zones/{zone_id}/dns_records?{params}"

    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            result["postcheck_called"] = "yes"
            if resp.status == 200:
                raw_body = resp.read().decode("utf-8")
                try:
                    body = json.loads(raw_body)
                except (json.JSONDecodeError, ValueError):
                    result["postcheck_succeeded"] = "no"
                    result["status"] = "fail"
                    result["reason"] = "postcheck GET failed"
                    return result

                records = body.get("result", [])
                matching = [r for r in records if r.get("type") == record_type]

                count = len(matching)
                if count == 0:
                    result["postcheck_succeeded"] = "no"
                    result["record_count_category"] = "zero"
                    result["created_record_found"] = "no"
                    result["status"] = "fail"
                    result["reason"] = "created record not found"
                elif count == 1:
                    rec = matching[0]
                    result["record_count_category"] = "one"
                    result["created_record_found"] = "yes"

                    # Check type match
                    if rec.get("type") == record_type:
                        result["created_record_type_match"] = "yes"
                    else:
                        result["postcheck_succeeded"] = "no"
                        result["created_record_type_match"] = "no"
                        result["status"] = "fail"
                        result["reason"] = "created record type mismatch"
                        return result

                    # Check DNS-only (proxied=false)
                    if rec.get("proxied") is False:
                        result["created_record_dns_only"] = "yes"
                    else:
                        result["postcheck_succeeded"] = "no"
                        result["created_record_dns_only"] = "no"
                        result["status"] = "fail"
                        result["reason"] = "created record not DNS-only"
                        return result

                    # Check managed marker
                    comment = rec.get("comment", "") or ""
                    if managed_marker and managed_marker in comment:
                        result["created_record_managed"] = "yes"
                    else:
                        result["postcheck_succeeded"] = "no"
                        result["created_record_managed"] = "no"
                        result["status"] = "fail"
                        result["reason"] = "created record not managed"
                        return result

                    # All checks passed
                    result["postcheck_succeeded"] = "yes"
                    result["status"] = "pass"
                    result["reason"] = "postcheck succeeded"
                else:
                    result["postcheck_succeeded"] = "no"
                    result["record_count_category"] = "multiple"
                    result["created_record_found"] = "yes"
                    result["status"] = "fail"
                    result["reason"] = "multiple matching records"
            else:
                result["postcheck_succeeded"] = "no"
                result["status"] = "fail"
                result["reason"] = "postcheck GET failed"

    except urllib.error.URLError:
        result["postcheck_called"] = "yes"
        result["postcheck_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "postcheck GET failed"
    except TimeoutError:
        result["postcheck_called"] = "yes"
        result["postcheck_succeeded"] = "no"
        result["status"] = "uncertain"
        result["reason"] = "postcheck GET timed out"
    except Exception:
        result["postcheck_called"] = "yes"
        result["postcheck_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "postcheck GET failed"

    return result


# ── Cleanup read-only precheck ───────────────────────────────────────────────


def run_cloudflare_cleanup_readonly_precheck(
    plan: dict, token: str | None, *, allow_probe: bool
) -> dict:
    """Run a read-only cleanup precheck before DELETE.

    Only GET is allowed. No DELETE inside this function.
    Never prints URL, response, zone_id, record name, IP, or record ID.
    Stores internal record_id as _record_id but never renders it.
    """
    result = {
        "cleanup_precheck_called": "no",
        "cleanup_precheck_succeeded": "unknown",
        "cleanup_record_found": "unknown",
        "cleanup_record_single_match": "unknown",
        "cleanup_record_managed": "unknown",
        "cleanup_record_dns_only": "unknown",
        "cleanup_safe": "unknown",
        "record_id_printed": "no",
        "raw_dns_values_printed": "no",
        "raw_api_response_printed": "no",
        "status": "fail",
        "reason": "cleanup precheck not called",
        "_record_id": None,
    }

    if not allow_probe:
        result["reason"] = "cleanup precheck not called"
        return result

    if not token:
        result["reason"] = "cleanup precheck not called"
        return result

    # Get cleanup plan
    cleanup_plan = plan.get("live_cleanup_plan", {})
    if not isinstance(cleanup_plan, dict) or not cleanup_plan.get("enabled"):
        result["reason"] = "cleanup precheck not called"
        return result

    zone_id = cleanup_plan.get("zone_id_local", "")
    record_name = cleanup_plan.get("record_name_local", "")
    record_type = cleanup_plan.get("record_type_local", "A")
    managed_marker = cleanup_plan.get("managed_marker", "nanobk-test")

    if not zone_id or not record_name:
        result["reason"] = "cleanup precheck not called"
        return result

    # Get base URL from readonly_probe plan
    probe_plan = plan.get("readonly_probe", {})
    base_url = probe_plan.get("base_url", "https://api.cloudflare.com/client/v4")

    # Perform GET request
    import urllib.request
    import urllib.error
    import urllib.parse

    params = urllib.parse.urlencode({"name": record_name, "type": record_type})
    url = f"{base_url}/zones/{zone_id}/dns_records?{params}"

    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            result["cleanup_precheck_called"] = "yes"
            if resp.status == 200:
                raw_body = resp.read().decode("utf-8")
                try:
                    body = json.loads(raw_body)
                except (json.JSONDecodeError, ValueError):
                    result["cleanup_precheck_succeeded"] = "no"
                    result["status"] = "fail"
                    result["reason"] = "cleanup GET failed"
                    return result

                records = body.get("result", [])
                matching = [r for r in records if r.get("type") == record_type]

                count = len(matching)
                if count == 0:
                    result["cleanup_precheck_succeeded"] = "no"
                    result["cleanup_record_found"] = "no"
                    result["cleanup_record_single_match"] = "no"
                    result["status"] = "fail"
                    result["reason"] = "cleanup record not found"
                    return result

                if count > 1:
                    result["cleanup_precheck_succeeded"] = "no"
                    result["cleanup_record_found"] = "yes"
                    result["cleanup_record_single_match"] = "no"
                    result["status"] = "fail"
                    result["reason"] = "cleanup record not single match"
                    return result

                # Exactly one matching record
                rec = matching[0]
                result["cleanup_record_found"] = "yes"
                result["cleanup_record_single_match"] = "yes"

                # Check managed marker
                comment = rec.get("comment", "") or ""
                if managed_marker and managed_marker in comment:
                    result["cleanup_record_managed"] = "yes"
                else:
                    result["cleanup_precheck_succeeded"] = "no"
                    result["cleanup_record_managed"] = "no"
                    result["status"] = "fail"
                    result["reason"] = "cleanup record not managed"
                    return result

                # Check DNS-only (proxied=false)
                if rec.get("proxied") is False:
                    result["cleanup_record_dns_only"] = "yes"
                else:
                    result["cleanup_precheck_succeeded"] = "no"
                    result["cleanup_record_dns_only"] = "no"
                    result["status"] = "fail"
                    result["reason"] = "cleanup record not DNS-only"
                    return result

                # All checks passed — store record_id internally
                result["cleanup_precheck_succeeded"] = "yes"
                result["cleanup_safe"] = "yes"
                result["_record_id"] = rec.get("id")
                result["status"] = "pass"
                result["reason"] = "cleanup precheck succeeded"
            else:
                result["cleanup_precheck_succeeded"] = "no"
                result["status"] = "fail"
                result["reason"] = "cleanup GET failed"

    except urllib.error.URLError:
        result["cleanup_precheck_called"] = "yes"
        result["cleanup_precheck_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "cleanup GET failed"
    except TimeoutError:
        result["cleanup_precheck_called"] = "yes"
        result["cleanup_precheck_succeeded"] = "no"
        result["status"] = "uncertain"
        result["reason"] = "cleanup GET timed out"
    except Exception:
        result["cleanup_precheck_called"] = "yes"
        result["cleanup_precheck_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "cleanup GET failed"

    return result


# ── Cleanup prerequisites ────────────────────────────────────────────────────

_CLEANUP_APPROVAL_PHRASE = "I UNDERSTAND THIS WILL DELETE ONE CLOUDFLARE DNS TEST RECORD"


def evaluate_live_cleanup_prerequisites(
    model: dict, plan: dict, approval: str | None
) -> dict:
    """Evaluate whether all prerequisites for live cleanup are met.

    Requires exact cleanup approval phrase, token loaded, probe succeeded,
    cleanup precheck passed, and safe live_cleanup_plan.
    """
    result = {
        "cleanup_prerequisites_passed": "no",
        "cleanup_approval_present": "no",
        "cleanup_one_record_only": "no",
        "delete_only_if_managed": "no",
        "delete_only_if_dns_only": "no",
        "delete_only_if_single_match": "no",
        "status": "fail",
        "reason": "cleanup approval missing",
    }

    # Check approval phrase
    if approval != _CLEANUP_APPROVAL_PHRASE:
        result["reason"] = "cleanup approval missing"
        return result
    result["cleanup_approval_present"] = "yes"

    # Check token and probe
    tok = model.get("token_metadata", {})
    if tok.get("token_loaded") != "yes":
        result["reason"] = "cleanup precheck not passed"
        return result

    if model.get("cloudflare_get_succeeded") != "yes":
        result["reason"] = "cleanup precheck not passed"
        return result

    # Check cleanup precheck
    cleanup_precheck = model.get("live_cleanup_precheck", {})
    if cleanup_precheck.get("cleanup_precheck_succeeded") != "yes":
        result["reason"] = "cleanup precheck not passed"
        return result
    if cleanup_precheck.get("cleanup_safe") != "yes":
        result["reason"] = "cleanup precheck not passed"
        return result
    if cleanup_precheck.get("cleanup_record_single_match") != "yes":
        result["reason"] = "cleanup precheck not passed"
        return result
    if cleanup_precheck.get("cleanup_record_managed") != "yes":
        result["reason"] = "cleanup precheck not passed"
        return result
    if cleanup_precheck.get("cleanup_record_dns_only") != "yes":
        result["reason"] = "cleanup precheck not passed"
        return result

    # Check live_cleanup_plan
    cleanup_plan = plan.get("live_cleanup_plan", {})
    if not isinstance(cleanup_plan, dict) or not cleanup_plan.get("enabled"):
        result["reason"] = "cleanup plan missing"
        return result

    if cleanup_plan.get("one_record_only") is not True:
        result["reason"] = "cleanup plan unsafe"
        return result
    result["cleanup_one_record_only"] = "yes"

    if cleanup_plan.get("delete_only_if_managed") is not True:
        result["reason"] = "cleanup plan unsafe"
        return result
    result["delete_only_if_managed"] = "yes"

    if cleanup_plan.get("delete_only_if_dns_only") is not True:
        result["reason"] = "cleanup plan unsafe"
        return result
    result["delete_only_if_dns_only"] = "yes"

    if cleanup_plan.get("delete_only_if_single_match") is not True:
        result["reason"] = "cleanup plan unsafe"
        return result
    result["delete_only_if_single_match"] = "yes"

    result["cleanup_prerequisites_passed"] = "yes"
    result["status"] = "pass"
    result["reason"] = "cleanup prerequisites passed"
    return result


# ── Live cleanup DELETE ──────────────────────────────────────────────────────


def run_cloudflare_one_record_live_cleanup(
    plan: dict, token: str | None, *, allow_live_cleanup: bool,
    approval: str | None, model: dict, record_id: str | None
) -> dict:
    """Run a one-record live cleanup via Cloudflare DELETE.

    Only DELETE is allowed. No POST/PUT/PATCH.
    Never prints URL, record ID, or raw API response.
    """
    result = {
        "cleanup_allowed": "no",
        "cleanup_called": "no",
        "cleanup_succeeded": "unknown",
        "deleted_record_category": "none",
        "cleanup_mutation_method_used": "no",
        "record_id_printed": "no",
        "raw_api_response_printed": "no",
        "delete_called": "no",
        "update_called": "no",
        "create_called": "no",
        "status": "fail",
        "reason": "cleanup not allowed",
    }

    if not allow_live_cleanup:
        result["reason"] = "cleanup not allowed"
        return result

    if approval != _CLEANUP_APPROVAL_PHRASE:
        result["reason"] = "cleanup approval missing"
        return result

    if not token:
        result["reason"] = "cleanup prerequisites failed"
        return result

    if not record_id:
        result["reason"] = "cleanup record id unavailable"
        return result

    # Evaluate prerequisites
    prereq = evaluate_live_cleanup_prerequisites(model, plan, approval)
    if prereq["status"] != "pass":
        result["reason"] = prereq.get("reason", "cleanup prerequisites failed")
        return result

    result["cleanup_allowed"] = "yes"

    # Get cleanup plan
    cleanup_plan = plan.get("live_cleanup_plan", {})
    if not isinstance(cleanup_plan, dict):
        result["reason"] = "cleanup plan missing"
        return result

    zone_id = cleanup_plan.get("zone_id_local", "")
    if not zone_id:
        result["reason"] = "cleanup prerequisites failed"
        return result

    # Get base URL from readonly_probe plan
    probe_plan = plan.get("readonly_probe", {})
    base_url = probe_plan.get("base_url", "https://api.cloudflare.com/client/v4")

    # Build DELETE request
    import urllib.request
    import urllib.error

    url = f"{base_url}/zones/{zone_id}/dns_records/{record_id}"

    req = urllib.request.Request(url, method="DELETE")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            result["cleanup_called"] = "yes"
            result["cleanup_mutation_method_used"] = "DELETE"
            result["delete_called"] = "yes"
            if resp.status in (200, 204):
                result["cleanup_succeeded"] = "yes"
                result["deleted_record_category"] = "one_disposable_test_record"
                result["status"] = "pass"
                result["reason"] = "cleanup succeeded"
            else:
                result["cleanup_succeeded"] = "no"
                result["status"] = "fail"
                result["reason"] = "cleanup failed"
    except urllib.error.URLError:
        result["cleanup_called"] = "yes"
        result["cleanup_mutation_method_used"] = "DELETE"
        result["delete_called"] = "yes"
        result["cleanup_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "cleanup failed"
    except TimeoutError:
        result["cleanup_called"] = "yes"
        result["cleanup_mutation_method_used"] = "DELETE"
        result["delete_called"] = "yes"
        result["cleanup_succeeded"] = "no"
        result["status"] = "uncertain"
        result["reason"] = "cleanup timed out"
    except Exception:
        result["cleanup_called"] = "yes"
        result["cleanup_mutation_method_used"] = "DELETE"
        result["delete_called"] = "yes"
        result["cleanup_succeeded"] = "no"
        result["status"] = "fail"
        result["reason"] = "cleanup failed"

    return result


# ── CLI entry point ──────────────────────────────────────────────────────────

_USAGE = """\
usage: nanobk-cf-dns-dryrun-wrapper --plan PATH [--precheck-only] [--allow-readonly-probe] [--allow-live-create] [--owner-approval TEXT] [--allow-live-cleanup] [--owner-cleanup-approval TEXT]

Non-public local dry-run runner for safe plan files.
Dry-run only by default. Live create/cleanup require explicit flags and approval.

Options:
  --plan PATH                    Path to a safe JSON plan file (required)
  --precheck-only                Run read-only precheck only
  --allow-readonly-probe         Allow read-only probe
  --allow-live-create            Allow one-record live create (requires --owner-approval)
  --owner-approval TEXT          Exact owner approval phrase for live create
  --allow-live-cleanup           Allow one-record live cleanup (requires --owner-cleanup-approval)
  --owner-cleanup-approval TEXT  Exact owner approval phrase for cleanup

Exit codes:
  0  dryrun_preview_ready or live create/cleanup succeeded
  2  blocked
  3  uncertain
  4  invalid input / unsafe output
"""


def main(argv: list[str] | None = None) -> int:
    """CLI entry point for dry-run wrapper.

    Reads a safe JSON plan file, runs the dry-run wrapper, renders a safe
    summary, and prints it. Exits non-zero for blocked/uncertain/invalid.
    """
    if argv is None:
        argv = sys.argv[1:]

    # --help / -h -> stdout usage -> exit 0
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(_USAGE)
        return 0

    # No args -> stderr usage -> exit 4
    if not argv:
        sys.stderr.write("Error: --plan is required.\n")
        sys.stderr.write(_USAGE)
        return 4

    # Parse flags
    plan_path = None
    precheck_only = False
    allow_readonly_probe = False
    allow_live_create = False
    owner_approval = None
    allow_live_cleanup = False
    owner_cleanup_approval = None
    i = 0
    while i < len(argv):
        if argv[i] == "--plan" and i + 1 < len(argv):
            plan_path = argv[i + 1]
            i += 2
        elif argv[i] == "--precheck-only":
            precheck_only = True
            i += 1
        elif argv[i] == "--allow-readonly-probe":
            allow_readonly_probe = True
            i += 1
        elif argv[i] == "--allow-live-create":
            allow_live_create = True
            i += 1
        elif argv[i] == "--owner-approval" and i + 1 < len(argv):
            owner_approval = argv[i + 1]
            i += 2
        elif argv[i] == "--allow-live-cleanup":
            allow_live_cleanup = True
            i += 1
        elif argv[i] == "--owner-cleanup-approval" and i + 1 < len(argv):
            owner_cleanup_approval = argv[i + 1]
            i += 2
        else:
            i += 1

    if plan_path is None:
        sys.stderr.write("Error: --plan is required.\n")
        sys.stderr.write(_USAGE)
        return 4

    # Read plan file
    plan_path_obj = Path(plan_path)
    if not plan_path_obj.exists():
        sys.stderr.write("Error: plan file not found.\n")
        return 4

    try:
        with open(plan_path_obj, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        sys.stderr.write("Error: plan file is not valid JSON.\n")
        return 4

    if not isinstance(data, dict):
        sys.stderr.write("Error: plan file must be a JSON object.\n")
        return 4

    # Run dry-run wrapper
    try:
        model = run_dns_apply_dryrun_wrapper(data)
    except RuntimeError:
        sys.stderr.write("Error: invalid plan structure.\n")
        return 4

    # Apply --allow-readonly-probe flag
    if allow_readonly_probe:
        # Gate: only read token and probe if all prerequisites pass
        if not _probe_prerequisites_passed(model):
            # Do NOT read token. Do NOT call GET.
            model["readonly_probe_allowed"] = "no"
            model["can_query"] = "no"
            model["cloudflare_get_called"] = "no"
            model["cloudflare_get_succeeded"] = "unknown"
            model["raw_api_response_printed"] = "no"
            model["mutation_method_used"] = "no"
            model["token_metadata"] = {
                "token_loaded": "no",
                "token_source": "credential_reference",
                "token_printed": "no",
                "credential_path_printed": "no",
            }
            # Preserve existing blocked/uncertain status and first_failed_gate
        else:
            model["readonly_probe_allowed"] = "yes"

            # Load token from credential reference
            cred_ref = data.get("credential_reference", {})
            token_result = load_readonly_cloudflare_token_from_reference(cred_ref)
            model["token_metadata"] = {
                "token_loaded": token_result["token_loaded"],
                "token_source": token_result["token_source"],
                "token_printed": "no",
                "credential_path_printed": "no",
            }

            # Run read-only GET probe if token loaded
            if token_result["token_loaded"] == "yes" and token_result.get("_token"):
                probe_result = run_cloudflare_readonly_get_probe(
                    data, token_result["_token"], allow_probe=True
                )
            else:
                probe_result = run_cloudflare_readonly_get_probe(
                    data, None, allow_probe=True
                )

            # can_query=yes only if GET succeeded
            if probe_result.get("cloudflare_get_succeeded") == "yes":
                model["can_query"] = "yes"
            else:
                model["can_query"] = "no"

            model["cloudflare_get_called"] = probe_result.get("cloudflare_get_called", "no")
            model["cloudflare_get_succeeded"] = probe_result.get("cloudflare_get_succeeded", "unknown")
            model["raw_api_response_printed"] = "no"
            model["mutation_method_used"] = "no"

            # Run DNS record read-only precheck only if requested in plan
            dns_precheck_plan = data.get("readonly_dns_record_precheck", {})
            if isinstance(dns_precheck_plan, dict) and dns_precheck_plan.get("enabled"):
                if (token_result["token_loaded"] == "yes"
                        and token_result.get("_token")
                        and probe_result.get("cloudflare_get_succeeded") == "yes"):
                    dns_precheck_result = run_cloudflare_dns_record_readonly_precheck(
                        data, token_result["_token"], allow_probe=True
                    )
                else:
                    dns_precheck_result = run_cloudflare_dns_record_readonly_precheck(
                        data, None, allow_probe=True
                    )
            else:
                dns_precheck_result = {
                    "dns_record_precheck_enabled": "no",
                    "dns_record_get_called": "no",
                    "dns_record_get_succeeded": "unknown",
                    "same_name_cname_absent": "unknown",
                    "existing_unmanaged_record_absent": "unknown",
                    "existing_managed_test_record": "unknown",
                    "create_only_first_safe": "unknown",
                    "record_count_category": "unknown",
                    "raw_dns_values_printed": "no",
                    "raw_api_response_printed": "no",
                    "record_id_printed": "no",
                    "status": "pass",
                    "reason": "dns record precheck not enabled",
                }

            model["dns_record_precheck"] = {
                "dns_record_precheck_enabled": dns_precheck_result.get("dns_record_precheck_enabled", "no"),
                "dns_record_get_called": dns_precheck_result.get("dns_record_get_called", "no"),
                "dns_record_get_succeeded": dns_precheck_result.get("dns_record_get_succeeded", "unknown"),
                "same_name_cname_absent": dns_precheck_result.get("same_name_cname_absent", "unknown"),
                "existing_unmanaged_record_absent": dns_precheck_result.get("existing_unmanaged_record_absent", "unknown"),
                "existing_managed_test_record": dns_precheck_result.get("existing_managed_test_record", "unknown"),
                "create_only_first_safe": dns_precheck_result.get("create_only_first_safe", "unknown"),
                "record_count_category": dns_precheck_result.get("record_count_category", "unknown"),
                "raw_dns_values_printed": "no",
                "raw_api_response_printed": "no",
                "record_id_printed": "no",
            }

            # If DNS precheck failed and model is still ready, update status
            if dns_precheck_result.get("status") == "fail" and model.get("status") == _STATUS_DRYRUN_READY:
                model["status"] = _STATUS_BLOCKED
                model["first_failed_gate"] = "dns_record_precheck"
                model["first_blocked_reason"] = dns_precheck_result.get("reason", "dns record precheck failed")
            elif dns_precheck_result.get("status") == "uncertain":
                model["status"] = _STATUS_UNCERTAIN
                model["first_failed_gate"] = "dns_record_precheck"
                model["first_blocked_reason"] = dns_precheck_result.get("reason", "dns record GET timed out")

            # If token verify probe failed and model is still ready, update status
            if probe_result.get("status") == "fail" and model.get("status") == _STATUS_DRYRUN_READY:
                model["status"] = _STATUS_BLOCKED
                model["first_failed_gate"] = "readonly_probe"
                model["first_blocked_reason"] = probe_result.get("reason", "readonly GET failed")
            elif probe_result.get("status") == "uncertain":
                model["status"] = _STATUS_UNCERTAIN
                model["first_failed_gate"] = "readonly_probe"
                model["first_blocked_reason"] = probe_result.get("reason", "readonly GET timed out")

            # Run live create if requested
            if allow_live_create:
                prereq = evaluate_live_create_prerequisites(model, data, owner_approval)
                model["live_create"] = {
                    "owner_approval_present": prereq["owner_approval_present"],
                    "live_create_prerequisites_passed": prereq["live_create_prerequisites_passed"],
                    "one_record_only": prereq["one_record_only"],
                    "create_only_first": prereq["create_only_first"],
                    "dns_only": prereq["dns_only"],
                    "delete_allowed": prereq["delete_allowed"],
                    "update_allowed": prereq["update_allowed"],
                    "overwrite_allowed": prereq["overwrite_allowed"],
                }

                if prereq["status"] == "pass" and token_result["token_loaded"] == "yes" and token_result.get("_token"):
                    create_result = run_cloudflare_one_record_live_create(
                        data, token_result["_token"],
                        allow_live_create=True,
                        approval=owner_approval,
                        model=model,
                    )
                else:
                    create_result = run_cloudflare_one_record_live_create(
                        data, None,
                        allow_live_create=True,
                        approval=owner_approval,
                        model=model,
                    )

                model["live_create"].update({
                    "live_create_allowed": create_result.get("live_create_allowed", "no"),
                    "live_create_called": create_result.get("live_create_called", "no"),
                    "live_create_succeeded": create_result.get("live_create_succeeded", "unknown"),
                    "created_record_category": create_result.get("created_record_category", "none"),
                    "proxied": create_result.get("proxied", "unknown"),
                    "raw_dns_values_printed": "no",
                    "raw_api_response_printed": "no",
                    "record_id_printed": "no",
                    "mutation_method_used": create_result.get("mutation_method_used", "no"),
                    "delete_called": "no",
                    "update_called": "no",
                })

                # Update model status if live create failed
                if create_result.get("status") == "fail" and model.get("status") == _STATUS_DRYRUN_READY:
                    model["status"] = _STATUS_BLOCKED
                    model["first_failed_gate"] = "live_create"
                    model["first_blocked_reason"] = create_result.get("reason", "live create failed")
                elif create_result.get("status") == "uncertain":
                    model["status"] = _STATUS_UNCERTAIN
                    model["first_failed_gate"] = "live_create"
                    model["first_blocked_reason"] = create_result.get("reason", "live create timed out")
                elif create_result.get("status") == "pass":
                    # Live create succeeded — run post-check
                    model["real_dns_mutation_performed"] = "yes"
                    model["live_cloudflare_called"] = "yes"

                    # Run post-check
                    if token_result["token_loaded"] == "yes" and token_result.get("_token"):
                        postcheck_result = run_cloudflare_live_create_postcheck(
                            data, token_result["_token"], allow_postcheck=True
                        )
                    else:
                        postcheck_result = run_cloudflare_live_create_postcheck(
                            data, None, allow_postcheck=True
                        )

                    model["live_create_postcheck"] = {
                        "postcheck_called": postcheck_result.get("postcheck_called", "no"),
                        "postcheck_succeeded": postcheck_result.get("postcheck_succeeded", "unknown"),
                        "created_record_found": postcheck_result.get("created_record_found", "unknown"),
                        "created_record_type_match": postcheck_result.get("created_record_type_match", "unknown"),
                        "created_record_dns_only": postcheck_result.get("created_record_dns_only", "unknown"),
                        "created_record_managed": postcheck_result.get("created_record_managed", "unknown"),
                        "record_count_category": postcheck_result.get("record_count_category", "unknown"),
                        "raw_dns_values_printed": "no",
                        "raw_api_response_printed": "no",
                        "record_id_printed": "no",
                    }

                    if postcheck_result.get("status") == "pass":
                        model["status"] = "live_create_verified"
                    else:
                        # Mutation happened but verification failed
                        model["status"] = _STATUS_UNCERTAIN
                        model["first_failed_gate"] = "live_create_postcheck"
                        model["first_blocked_reason"] = postcheck_result.get("reason", "postcheck failed")

                # Ensure public safety locks remain
                model["can_apply"] = "no"
                model["mutation_allowed"] = "no"
                model["public_apply_allowed"] = "no"
            else:
                model["live_create"] = {
                    "owner_approval_present": "no",
                    "live_create_prerequisites_passed": "no",
                    "one_record_only": "no",
                    "create_only_first": "no",
                    "dns_only": "no",
                    "delete_allowed": "no",
                    "update_allowed": "no",
                    "overwrite_allowed": "no",
                    "live_create_allowed": "no",
                    "live_create_called": "no",
                    "live_create_succeeded": "unknown",
                    "created_record_category": "none",
                    "proxied": "unknown",
                    "raw_dns_values_printed": "no",
                    "raw_api_response_printed": "no",
                    "record_id_printed": "no",
                    "mutation_method_used": "no",
                    "delete_called": "no",
                    "update_called": "no",
                }
                model["live_create_postcheck"] = {
                    "postcheck_called": "no",
                    "postcheck_succeeded": "unknown",
                    "created_record_found": "unknown",
                    "created_record_type_match": "unknown",
                    "created_record_dns_only": "unknown",
                    "created_record_managed": "unknown",
                    "record_count_category": "unknown",
                    "raw_dns_values_printed": "no",
                    "raw_api_response_printed": "no",
                    "record_id_printed": "no",
                }
    else:
        model["token_metadata"] = {
            "token_loaded": "no",
            "token_source": "credential_reference",
            "token_printed": "no",
            "credential_path_printed": "no",
        }
        model["dns_record_precheck"] = {
            "dns_record_precheck_enabled": "no",
            "dns_record_get_called": "no",
            "dns_record_get_succeeded": "unknown",
            "same_name_cname_absent": "unknown",
            "existing_unmanaged_record_absent": "unknown",
            "existing_managed_test_record": "unknown",
            "create_only_first_safe": "unknown",
            "record_count_category": "unknown",
            "raw_dns_values_printed": "no",
            "raw_api_response_printed": "no",
            "record_id_printed": "no",
        }
        model["live_create_postcheck"] = {
            "postcheck_called": "no",
            "postcheck_succeeded": "unknown",
            "created_record_found": "unknown",
            "created_record_type_match": "unknown",
            "created_record_dns_only": "unknown",
            "created_record_managed": "unknown",
            "record_count_category": "unknown",
            "raw_dns_values_printed": "no",
            "raw_api_response_printed": "no",
            "record_id_printed": "no",
        }

    # Run cleanup if requested (independent of live create)
    if allow_live_cleanup and allow_readonly_probe:
        # Run cleanup readonly precheck
        cleanup_precheck_result = run_cloudflare_cleanup_readonly_precheck(
            data,
            token_result.get("_token") if token_result.get("token_loaded") == "yes" else None,
            allow_probe=True,
        )
        model["live_cleanup_precheck"] = {
            "cleanup_precheck_called": cleanup_precheck_result.get("cleanup_precheck_called", "no"),
            "cleanup_precheck_succeeded": cleanup_precheck_result.get("cleanup_precheck_succeeded", "unknown"),
            "cleanup_record_found": cleanup_precheck_result.get("cleanup_record_found", "unknown"),
            "cleanup_record_single_match": cleanup_precheck_result.get("cleanup_record_single_match", "unknown"),
            "cleanup_record_managed": cleanup_precheck_result.get("cleanup_record_managed", "unknown"),
            "cleanup_record_dns_only": cleanup_precheck_result.get("cleanup_record_dns_only", "unknown"),
            "cleanup_safe": cleanup_precheck_result.get("cleanup_safe", "unknown"),
            "record_id_printed": "no",
            "raw_dns_values_printed": "no",
            "raw_api_response_printed": "no",
        }

        # Evaluate cleanup prerequisites
        cleanup_prereq = evaluate_live_cleanup_prerequisites(model, data, owner_cleanup_approval)
        model["live_cleanup"] = {
            "cleanup_approval_present": cleanup_prereq["cleanup_approval_present"],
            "cleanup_prerequisites_passed": cleanup_prereq["cleanup_prerequisites_passed"],
            "cleanup_one_record_only": cleanup_prereq["cleanup_one_record_only"],
            "delete_only_if_managed": cleanup_prereq["delete_only_if_managed"],
            "delete_only_if_dns_only": cleanup_prereq["delete_only_if_dns_only"],
            "delete_only_if_single_match": cleanup_prereq["delete_only_if_single_match"],
            "cleanup_allowed": "no",
            "cleanup_called": "no",
            "cleanup_succeeded": "unknown",
            "deleted_record_category": "none",
            "cleanup_mutation_method_used": "no",
            "record_id_printed": "no",
            "raw_api_response_printed": "no",
            "delete_called": "no",
            "update_called": "no",
            "create_called": "no",
        }

        # Run cleanup if prerequisites pass
        internal_record_id = cleanup_precheck_result.get("_record_id")
        if cleanup_prereq["status"] == "pass" and internal_record_id:
            cleanup_result = run_cloudflare_one_record_live_cleanup(
                data,
                token_result.get("_token") if token_result.get("token_loaded") == "yes" else None,
                allow_live_cleanup=True,
                approval=owner_cleanup_approval,
                model=model,
                record_id=internal_record_id,
            )
        else:
            cleanup_result = run_cloudflare_one_record_live_cleanup(
                data, None,
                allow_live_cleanup=True,
                approval=owner_cleanup_approval,
                model=model,
                record_id=None,
            )

        model["live_cleanup"].update({
            "cleanup_allowed": cleanup_result.get("cleanup_allowed", "no"),
            "cleanup_called": cleanup_result.get("cleanup_called", "no"),
            "cleanup_succeeded": cleanup_result.get("cleanup_succeeded", "unknown"),
            "deleted_record_category": cleanup_result.get("deleted_record_category", "none"),
            "cleanup_mutation_method_used": cleanup_result.get("cleanup_mutation_method_used", "no"),
            "delete_called": cleanup_result.get("delete_called", "no"),
        })

        # Update model status if cleanup failed
        if cleanup_result.get("status") == "fail":
            model["status"] = _STATUS_BLOCKED
            model["first_failed_gate"] = "live_cleanup"
            model["first_blocked_reason"] = cleanup_result.get("reason", "cleanup failed")
        elif cleanup_result.get("status") == "uncertain":
            model["status"] = _STATUS_UNCERTAIN
            model["first_failed_gate"] = "live_cleanup"
            model["first_blocked_reason"] = cleanup_result.get("reason", "cleanup timed out")
        elif cleanup_result.get("status") == "pass":
            model["status"] = "live_cleanup_succeeded"
            model["live_cloudflare_called"] = "yes"

        # Ensure public safety locks remain
        model["can_apply"] = "no"
        model["mutation_allowed"] = "no"
        model["public_apply_allowed"] = "no"
    else:
        model["live_cleanup_precheck"] = {
            "cleanup_precheck_called": "no",
            "cleanup_precheck_succeeded": "unknown",
            "cleanup_record_found": "unknown",
            "cleanup_record_single_match": "unknown",
            "cleanup_record_managed": "unknown",
            "cleanup_record_dns_only": "unknown",
            "cleanup_safe": "unknown",
            "record_id_printed": "no",
            "raw_dns_values_printed": "no",
            "raw_api_response_printed": "no",
        }
        model["live_cleanup"] = {
            "cleanup_approval_present": "no",
            "cleanup_prerequisites_passed": "no",
            "cleanup_one_record_only": "no",
            "delete_only_if_managed": "no",
            "delete_only_if_dns_only": "no",
            "delete_only_if_single_match": "no",
            "cleanup_allowed": "no",
            "cleanup_called": "no",
            "cleanup_succeeded": "unknown",
            "deleted_record_category": "none",
            "cleanup_mutation_method_used": "no",
            "record_id_printed": "no",
            "raw_api_response_printed": "no",
            "delete_called": "no",
            "update_called": "no",
            "create_called": "no",
        }

    # Render safe summary
    try:
        text = render_dns_apply_dryrun_summary(model)
    except Exception:
        sys.stderr.write("Error: could not render summary.\n")
        return 4

    # Assert output safety
    try:
        assert_safe_dns_apply_dryrun_output(text)
    except UnsafeDnsApplyDryrunOutputError:
        sys.stderr.write("Error: output contains forbidden patterns.\n")
        return 4

    # Print safe summary
    sys.stdout.write(text)

    # Exit code based on status
    status = model.get("status", "uncertain")
    if status in ("dryrun_preview_ready", "live_create_verified", "live_cleanup_succeeded"):
        return 0
    elif status == "blocked":
        return 2
    elif status == "uncertain":
        return 3
    else:
        return 4
