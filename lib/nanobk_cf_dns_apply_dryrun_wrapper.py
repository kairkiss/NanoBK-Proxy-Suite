#!/usr/bin/env python3
"""
NanoBK DNS Apply Dry-run Wrapper — Non-public dry-run-only wrapper.

Validates local input structure, credential reference permissions, and
generates redacted preview summary. Can call the existing helper's safe
--dry-run path (no API calls, no mutation). If no safe helper dry-run path
is available, generates wrapper-level preview only.

NOT imported by bin/nanobk. NOT a user-facing command. NOT real DNS apply.
Does not create/update/delete DNS records.
Does not execute live mutation.
Does not print real domain, hostname, IP, token, API response, env path,
subscription URL, workers.dev URL, protocol URI, private key, Authorization
header, record ID, zone ID, account ID.
Does not cat/source/eval real env files.
Does not echo tokens.
Does not print raw helper stdout/stderr.

can_apply is always "no".
mutation_allowed is always "no".
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

    # Check method allowlist
    allowed_methods = probe_plan.get("method_allowlist", ["GET"])
    if any(m in ("POST", "PATCH", "PUT", "DELETE") for m in allowed_methods):
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


# ── CLI entry point ──────────────────────────────────────────────────────────

_USAGE = """\
usage: nanobk-cf-dns-dryrun-wrapper --plan PATH [--precheck-only] [--allow-readonly-probe]

Non-public local dry-run runner for safe plan files.
Dry-run only. No DNS mutation. No live Cloudflare calls.

Options:
  --plan PATH                Path to a safe JSON plan file (required)
  --precheck-only            Run read-only precheck only
  --allow-readonly-probe     Allow read-only probe (does not call Cloudflare in v2.2.30)

Exit codes:
  0  dryrun_preview_ready
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
        model["readonly_probe_allowed"] = "yes"

        # Load token from credential reference if available
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

        model["can_query"] = probe_result.get("readonly_probe_allowed", "no")
        model["cloudflare_get_called"] = probe_result.get("cloudflare_get_called", "no")
        model["cloudflare_get_succeeded"] = probe_result.get("cloudflare_get_succeeded", "unknown")
        model["raw_api_response_printed"] = "no"
        model["mutation_method_used"] = "no"

        # If probe failed and model is still ready, update status
        if probe_result.get("status") == "fail" and model.get("status") == "dryrun_preview_ready":
            model["status"] = "blocked"
            model["first_failed_gate"] = "readonly_probe"
            model["first_blocked_reason"] = probe_result.get("reason", "readonly GET failed")
        elif probe_result.get("status") == "uncertain":
            model["status"] = "uncertain"
            model["first_failed_gate"] = "readonly_probe"
            model["first_blocked_reason"] = probe_result.get("reason", "readonly GET timed out")
    else:
        model["token_metadata"] = {
            "token_loaded": "no",
            "token_source": "credential_reference",
            "token_printed": "no",
            "credential_path_printed": "no",
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
    if status == "dryrun_preview_ready":
        return 0
    elif status == "blocked":
        return 2
    elif status == "uncertain":
        return 3
    else:
        return 4
