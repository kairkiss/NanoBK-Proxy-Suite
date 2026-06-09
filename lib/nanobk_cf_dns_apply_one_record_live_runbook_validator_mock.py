#!/usr/bin/env python3
"""
NanoBK DNS Apply One-Record Live Runbook Validator Mock — Pure mock validator.

Consumes safe placeholder fixture dictionaries only. Validates the v2.2.23
owner-approved one-record live runbook placeholder completeness, credential
policy, record identity policy, approval policy, pre-check policy, post-check
policy, rollback policy, and public UX block.

NOT imported by bin/nanobk. NOT a user-facing command. NOT real DNS apply.
Does not call Cloudflare. Does not call helper. Does not read real env files.
Does not mutate DNS. Does not expose raw domains, IPs, record IDs, tokens,
env paths, API responses, helper stdout/stderr, or private keys.

ready_for_future_owner_approved_live_plan does NOT mean live test may run now.
actual_live_test_allowed is always "no".
live_cloudflare_called is always "no".
real_dns_mutation_performed is always "no".
real_env_read is always "no".
public_apply_allowed is always "no".

Usage:
    from nanobk_cf_dns_apply_one_record_live_runbook_validator_mock import validate_one_record_live_runbook_placeholders
    model = validate_one_record_live_runbook_placeholders(fixture_dict)
"""

from __future__ import annotations

import re
from typing import Any

# ── Constants ────────────────────────────────────────────────────────────────

_STATUS_READY = "ready_for_future_owner_approved_live_plan"
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

_VALIDATOR_SAFE_ERROR_MSG = (
    "NanoBK DNS Apply one-record live runbook validator mock is fixture-only.\n"
    "A valid safe placeholder fixture is required.\n"
    "No DNS changes were made."
)

# ── Blocked reason categories (safe generic) ─────────────────────────────────

_REASON_PLACEHOLDERS = "placeholder gate failed"
_REASON_CREDENTIAL = "credential policy gate failed"
_REASON_RECORD = "record identity policy gate failed"
_REASON_APPROVAL = "owner approval policy gate failed"
_REASON_PRECHECK = "pre-check policy gate failed"
_REASON_POSTCHECK = "post-check policy gate failed"
_REASON_ROLLBACK = "rollback policy gate failed"
_REASON_PUBLIC_UX = "public UX policy gate failed"

# ── Gate evaluation order ────────────────────────────────────────────────────

_GATE_ORDER = [
    ("placeholders", _REASON_PLACEHOLDERS),
    ("credential_policy", _REASON_CREDENTIAL),
    ("record_policy", _REASON_RECORD),
    ("approval_policy", _REASON_APPROVAL),
    ("precheck_policy", _REASON_PRECHECK),
    ("postcheck_policy", _REASON_POSTCHECK),
    ("rollback_policy", _REASON_ROLLBACK),
    ("public_ux_policy", _REASON_PUBLIC_UX),
]


# ── Individual gate evaluators ───────────────────────────────────────────────


def _eval_placeholders(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("safe_zone_category_present") is True
        and gate.get("safe_test_record_category_present") is True
        and gate.get("safe_record_type_present") is True
        and gate.get("safe_expected_content_category_present") is True
        and gate.get("safe_credential_file_reference_present") is True
        and gate.get("owner_approval_phrase_present") is True
        and gate.get("raw_values_printed") is False
        and gate.get("real_env_pasted") is False
        and gate.get("real_token_pasted") is False
        and gate.get("raw_identifier_pasted") is False
    )


def _eval_credential_policy(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("reference_input_only") is True
        and gate.get("reference_printed") is False
        and gate.get("chmod_600_required") is True
        and gate.get("cat_source_eval_forbidden") is True
        and gate.get("token_echo_forbidden") is True
        and gate.get("raw_api_output_forbidden") is True
        and gate.get("stdout_stderr_capture_required") is True
        and gate.get("redaction_before_output_required") is True
        and gate.get("secret_persistence_forbidden") is True
    )


def _eval_record_policy(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("one_record_only") is True
        and gate.get("disposable_test_record_only") is True
        and gate.get("owner_controlled_zone") is True
        and gate.get("create_only_first") is True
        and gate.get("dns_only") is True
        and gate.get("no_delete") is True
        and gate.get("no_overwrite") is True
        and gate.get("no_production_names") is True
        and gate.get("no_service_hostnames") is True
        and gate.get("absent_or_managed_test_only") is True
        and gate.get("same_name_cname_absent") is True
        and gate.get("record_type_expected") is True
        and gate.get("preview_before_approval") is True
    )


def _eval_approval_policy(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("exact_phrase_matched") is True
        and gate.get("after_preview") is True
        and gate.get("after_rollback") is True
        and gate.get("after_postcheck_explanation") is True
        and gate.get("before_mutation") is True
        and gate.get("raw_mutation_command_shown") is False
    )


def _eval_precheck_policy(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("placeholder_completeness") is True
        and gate.get("safe_record_category") is True
        and gate.get("no_production_category") is True
        and gate.get("absent_or_managed_test_only") is True
        and gate.get("same_name_cname_absent") is True
        and gate.get("no_unmanaged_overwrite") is True
        and gate.get("no_delete") is True
        and gate.get("safe_preview_available") is True
    )


def _eval_postcheck_policy(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("api_acceptance_required") is True
        and gate.get("get_observes_record_required") is True
        and gate.get("record_exists_required") is True
        and gate.get("type_matches_required") is True
        and gate.get("content_matches_internally_required") is True
        and gate.get("proxied_false_required") is True
        and gate.get("same_name_cname_absent_required") is True
        and gate.get("expected_count_matches_required") is True
        and gate.get("no_unexpected_delete_required") is True
        and gate.get("verified_only_after_postcheck") is True
        and gate.get("redacted_output_required") is True
        and gate.get("rollback_instruction_available") is True
    )


def _eval_rollback_policy(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("auto_delete_disabled") is True
        and gate.get("manual_instruction_before_mutation") is True
        and gate.get("owner_manual_dashboard_revert") is True
        and gate.get("safe_category_only") is True
        and gate.get("unverified_is_uncertain_or_manual_pending") is True
        and gate.get("blind_retry_forbidden") is True
    )


def _eval_public_ux_policy(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("bin_apply_blocked") is True
        and gate.get("bot_apply_blocked") is True
        and gate.get("web_apply_blocked") is True
        and gate.get("installer_apply_blocked") is True
        and gate.get("tag_release_blocked") is True
        and gate.get("separate_public_review_required") is True
    )


_GATE_EVALUATORS = {
    "placeholders": _eval_placeholders,
    "credential_policy": _eval_credential_policy,
    "record_policy": _eval_record_policy,
    "approval_policy": _eval_approval_policy,
    "precheck_policy": _eval_precheck_policy,
    "postcheck_policy": _eval_postcheck_policy,
    "rollback_policy": _eval_rollback_policy,
    "public_ux_policy": _eval_public_ux_policy,
}


# ── Validator ────────────────────────────────────────────────────────────────


def validate_one_record_live_runbook_placeholders(data: dict) -> dict:
    """Validate one-record live runbook placeholder fixture dict.

    Evaluates all gates for diagnostic step visibility, but exposes only the
    first failed gate/reason to beginner-safe output.

    Returns safe model with status, checks, first_failed_gate, safety.

    Raises RuntimeError on invalid input.
    """
    if not isinstance(data, dict):
        raise RuntimeError(_VALIDATOR_SAFE_ERROR_MSG)

    checks: dict[str, str] = {}
    diagnostic_blocked_reasons: list[str] = []
    first_failed_gate = "none"
    first_blocked_reason = "none"

    # Evaluate all gates in order
    for gate_key, reason in _GATE_ORDER:
        gate_data = data.get(gate_key)
        if gate_data is None:
            # Missing gate section is treated as malformed -> uncertain
            checks[gate_key] = "fail"
            diagnostic_blocked_reasons.append(reason)
            if first_failed_gate == "none":
                first_failed_gate = gate_key
                first_blocked_reason = reason
            continue

        evaluator = _GATE_EVALUATORS.get(gate_key)
        if evaluator and evaluator(gate_data):
            checks[gate_key] = "pass"
        else:
            checks[gate_key] = "fail"
            diagnostic_blocked_reasons.append(reason)
            if first_failed_gate == "none":
                first_failed_gate = gate_key
                first_blocked_reason = reason

    # blocked_reasons contains only the first blocked reason (beginner-facing)
    blocked_reasons: list[str] = []
    if first_blocked_reason != "none":
        blocked_reasons.append(first_blocked_reason)

    # Determine overall status
    all_pass = all(v == "pass" for v in checks.values())

    if all_pass:
        status = _STATUS_READY
    elif blocked_reasons:
        status = _STATUS_BLOCKED
    else:
        status = _STATUS_UNCERTAIN

    return {
        "status": status,
        "mode": "placeholder_validation_only",
        "first_failed_gate": first_failed_gate,
        "first_blocked_reason": first_blocked_reason,
        "blocked_reasons": blocked_reasons,
        "diagnostic_blocked_reasons": diagnostic_blocked_reasons,
        "checks": checks,
        "safety": {
            "live_cloudflare_called": "no",
            "real_dns_mutation_performed": "no",
            "real_env_read": "no",
            "public_apply_allowed": "no",
            "actual_live_test_allowed": "no",
            "requires_later_owner_approval": "yes",
        },
    }


# ── Safe renderer ────────────────────────────────────────────────────────────


def render_one_record_live_runbook_validation_summary(model: dict) -> str:
    """Render beginner-safe runbook validation summary from evaluated model.

    Only the first failed gate/reason is shown to the beginner. Diagnostic
    full failure list exists in the model but is not printed.
    """
    status = model.get("status", "unknown")
    mode = model.get("mode", "unknown")
    first_failed_gate = model.get("first_failed_gate", "none")
    first_blocked_reason = model.get("first_blocked_reason", "none")
    checks = model.get("checks", {})
    safety = model.get("safety", {})

    lines = [
        "NanoBK DNS Apply — One-Record Live Runbook Validator Mock Summary",
        f"Status: {status}",
        f"Mode: {mode}",
        "",
        "Checks:",
        f"  Placeholders: {checks.get('placeholders', 'unknown')}",
        f"  Credential policy: {checks.get('credential_policy', 'unknown')}",
        f"  Record identity policy: {checks.get('record_policy', 'unknown')}",
        f"  Owner approval policy: {checks.get('approval_policy', 'unknown')}",
        f"  Pre-check policy: {checks.get('precheck_policy', 'unknown')}",
        f"  Post-check policy: {checks.get('postcheck_policy', 'unknown')}",
        f"  Rollback policy: {checks.get('rollback_policy', 'unknown')}",
        f"  Public UX policy: {checks.get('public_ux_policy', 'unknown')}",
        "",
        "Safety:",
        f"  Live Cloudflare called: {safety.get('live_cloudflare_called', 'no')}",
        f"  Real DNS mutation performed: {safety.get('real_dns_mutation_performed', 'no')}",
        f"  Real env read: {safety.get('real_env_read', 'no')}",
        f"  Public apply allowed: {safety.get('public_apply_allowed', 'no')}",
        f"  Actual live test allowed: {safety.get('actual_live_test_allowed', 'no')}",
        f"  Requires later owner approval: {safety.get('requires_later_owner_approval', 'yes')}",
    ]

    if status == _STATUS_READY:
        lines.append("")
        lines.append("Placeholder validation only.")
        lines.append("No live Cloudflare call was made.")
        lines.append("No real DNS mutation was performed.")
        lines.append("Actual live test is still not allowed by this version.")

    if status == _STATUS_BLOCKED and first_failed_gate != "none":
        lines.append("")
        lines.append(f"First failed gate: {first_failed_gate}")
        lines.append(f"First blocked reason: {first_blocked_reason}")

    lines.append("")
    if status == _STATUS_READY:
        lines.append("Next: All placeholder gates pass. Ready for future owner-approved live plan.")
        lines.append("Actual live test is still not allowed by this version.")
    elif status == _STATUS_BLOCKED:
        lines.append("Next: Resolve blocked conditions before proceeding.")
        lines.append("Actual live test is not allowed.")
    else:
        lines.append("Next: Review uncertain conditions. Actual live test is not allowed.")

    return "\n".join(lines) + "\n"


# ── Output safety gate ───────────────────────────────────────────────────────


class UnsafeOneRecordLiveRunbookOutputError(Exception):
    """Raised when rendered validator output contains forbidden patterns."""
    pass


def assert_safe_one_record_live_runbook_output(text: str) -> None:
    """Fail closed if rendered output contains forbidden patterns.

    Raises UnsafeOneRecordLiveRunbookOutputError if any forbidden pattern is found.
    """
    for pattern in _FORBIDDEN_PATTERNS:
        if pattern.search(text):
            raise UnsafeOneRecordLiveRunbookOutputError(
                "One-record live runbook validator output contains forbidden pattern."
            )
