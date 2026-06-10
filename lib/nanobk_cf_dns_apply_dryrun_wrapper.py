#!/usr/bin/env python3
"""
NanoBK DNS Apply Dry-run Wrapper — Non-public dry-run-only wrapper.

Validates local input structure, credential reference permissions, and
generates redacted preview summary. Can call the existing helper's safe
--dry-run path (no API calls, no mutation). If no safe helper dry-run path
is available, generates wrapper-level preview only.

NOT imported by bin/nanobk. NOT public CLI. NOT real DNS apply.
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
        "first_failed_gate": first_failed_gate,
        "first_blocked_reason": first_blocked_reason,
        "blocked_reasons": blocked_reasons,
        "diagnostic_blocked_reasons": diagnostic_blocked_reasons,
        "redacted_preview": preview,
        "local_credential_reference": cred_meta,
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
        f"Credential reference present: {cred.get('credential_reference_present', 'no')}",
        f"Credential is regular file: {cred.get('credential_is_regular_file', 'no')}",
        f"Credential permission restricted: {cred.get('credential_permission_restricted', 'no')}",
        f"Credential contents read: {cred.get('credential_contents_read', 'no')}",
        f"Credential path printed: {cred.get('credential_path_printed', 'no')}",
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
usage: nanobk-cf-dns-dryrun-wrapper --plan PATH

Non-public local dry-run runner for safe plan files.
Dry-run only. No DNS mutation. No live Cloudflare calls.

Options:
  --plan PATH   Path to a safe JSON plan file (required)

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

    # Parse --plan
    plan_path = None
    i = 0
    while i < len(argv):
        if argv[i] == "--plan" and i + 1 < len(argv):
            plan_path = argv[i + 1]
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
