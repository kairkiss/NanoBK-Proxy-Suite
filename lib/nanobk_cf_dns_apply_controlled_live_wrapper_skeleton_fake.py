#!/usr/bin/env python3
"""
NanoBK DNS Apply Controlled Live Wrapper Skeleton Fake — Fake-transport-only skeleton.

Non-public fake-transport-only controlled live wrapper skeleton.
Consumes safe placeholder fixture dictionaries only.
Organizes v2.2.20-v2.2.24 gates into a structure closer to future real wrapper.

NOT imported by bin/nanobk. NOT a user-facing command. NOT real DNS apply.
Does not call Cloudflare. Does not call real helper. Does not read real env files.
Does not mutate DNS. Does not expose raw domains, IPs, record IDs, tokens,
env paths, API responses, helper stdout/stderr, or private keys.

fake_transport_verified does NOT mean live verified.
ready_for_owner_approved_future_live_plan does NOT allow live mutation.
actual_live_test_allowed is always "no".
public_apply_allowed is always "no".
live_cloudflare_called is always "no".
real_helper_called is always "no".
real_dns_mutation_performed is always "no".
real_env_read is always "no".

Usage:
    from nanobk_cf_dns_apply_controlled_live_wrapper_skeleton_fake import run_controlled_live_wrapper_skeleton_fake
    model = run_controlled_live_wrapper_skeleton_fake(fixture_dict)
"""

from __future__ import annotations

import re
from typing import Any

# ── Constants ────────────────────────────────────────────────────────────────

_STATUS_FAKE_VERIFIED = "fake_transport_verified"
_STATUS_READY = "ready_for_owner_approved_future_live_plan"
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

_SKELETON_SAFE_ERROR_MSG = (
    "NanoBK DNS Apply controlled live wrapper skeleton fake is fixture-only.\n"
    "A valid safe skeleton fixture is required.\n"
    "No DNS changes were made."
)

_REASON_MALFORMED = "malformed skeleton input"

# ── Blocked reason categories (safe generic) ─────────────────────────────────

_REASON_REPO = "repo gate failed"
_REASON_PLACEHOLDER = "placeholder validator gate failed"
_REASON_CREDENTIAL = "credential reference gate failed"
_REASON_RECORD = "record identity gate failed"
_REASON_PRECHECK = "pre-check gate failed"
_REASON_PREVIEW = "preview gate failed"
_REASON_APPROVAL = "owner approval gate failed"
_REASON_HELPER_CAPTURE = "fake helper capture gate failed"
_REASON_HELPER_JSON = "fake helper JSON gate failed"
_REASON_POSTCHECK = "fake post-check gate failed"
_REASON_CLASSIFIER = "classifier gate failed"
_REASON_CLASSIFIER_AMBIGUOUS = "classifier ambiguous"
_REASON_RENDERER = "safe renderer gate failed"
_REASON_REDACTION = "redaction gate failed"
_REASON_PUBLIC_UX = "public UX gate failed"

# ── Gate evaluation order ────────────────────────────────────────────────────

_GATE_ORDER = [
    ("repo_gate", _REASON_REPO),
    ("placeholder_validator_gate", _REASON_PLACEHOLDER),
    ("credential_reference_gate", _REASON_CREDENTIAL),
    ("record_identity_gate", _REASON_RECORD),
    ("precheck_gate", _REASON_PRECHECK),
    ("preview_gate", _REASON_PREVIEW),
    ("approval_gate", _REASON_APPROVAL),
    ("fake_helper_capture_gate", _REASON_HELPER_CAPTURE),
    ("fake_helper_json_gate", _REASON_HELPER_JSON),
    ("fake_postcheck_gate", _REASON_POSTCHECK),
    ("classifier_gate", _REASON_CLASSIFIER),
    ("safe_renderer_gate", _REASON_RENDERER),
    ("redaction_gate", _REASON_REDACTION),
    ("public_ux_gate", _REASON_PUBLIC_UX),
]


# ── Individual gate evaluators ───────────────────────────────────────────────


def _eval_repo_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("clean") is True
        and gate.get("expected_head") is True
        and gate.get("no_release_tag") is True
        and gate.get("no_public_integration") is True
    )


def _eval_placeholder_validator_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("status") == "ready_for_future_owner_approved_live_plan"
        and gate.get("actual_live_test_allowed") == "no"
        and gate.get("public_apply_allowed") == "no"
        and gate.get("real_env_read") == "no"
        and gate.get("real_dns_mutation_performed") == "no"
    )


def _eval_credential_reference_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("reference_input_only") is True
        and gate.get("reference_printed") is False
        and gate.get("chmod_600_required") is True
        and gate.get("cat_source_eval_forbidden") is True
        and gate.get("token_echo_forbidden") is True
        and gate.get("raw_api_output_forbidden") is True
    )


def _eval_record_identity_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("one_record_only") is True
        and gate.get("disposable_test_record_only") is True
        and gate.get("create_only_first") is True
        and gate.get("dns_only") is True
        and gate.get("no_delete") is True
        and gate.get("no_overwrite") is True
        and gate.get("no_production_names") is True
        and gate.get("no_service_hostnames") is True
        and gate.get("same_name_cname_absent") is True
    )


def _eval_precheck_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("available") is True
        and gate.get("placeholder_complete") is True
        and gate.get("safe_record_category") is True
        and gate.get("absent_or_managed_test_only") is True
        and gate.get("same_name_cname_absent") is True
        and gate.get("no_unmanaged_overwrite") is True
        and gate.get("no_delete") is True
    )


def _eval_preview_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("generated") is True
        and gate.get("safe_only") is True
        and gate.get("redaction_passed") is True
        and gate.get("raw_mutation_command_shown") is False
    )


def _eval_approval_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("exact_phrase_matched") is True
        and gate.get("after_preview") is True
        and gate.get("after_rollback") is True
        and gate.get("after_postcheck_explanation") is True
        and gate.get("before_mutation") is True
    )


def _eval_fake_helper_capture_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("fake_transport_only") is True
        and gate.get("real_helper_called") is False
        and gate.get("stdout_captured") is True
        and gate.get("stderr_captured") is True
        and gate.get("raw_output_printed") is False
        and gate.get("returncode") == 0
    )


def _eval_fake_helper_json_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("parse_ok") is True
        and gate.get("schema_ok") is True
        and gate.get("allowed_fields_only") is True
        and gate.get("raw_fields_removed") is True
    )


def _eval_fake_postcheck_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("fake_postcheck_only") is True
        and gate.get("record_exists") is True
        and gate.get("type_matches") is True
        and gate.get("content_matches_internally") is True
        and gate.get("proxied_false") is True
        and gate.get("same_name_cname_absent") is True
        and gate.get("no_unexpected_delete") is True
        and gate.get("verified_only_after_postcheck") is True
    )


def _eval_classifier_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("status") in ("fake_verified", "ready_for_future_owner_approved_live_plan")
        and gate.get("ambiguous") is False
    )


def _eval_safe_renderer_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("safe_summary_generated") is True
        and gate.get("fake_live_honesty") is True
        and gate.get("raw_values_removed") is True
    )


def _eval_redaction_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("passed") is True
        and gate.get("secret_or_address_printed") is False
        and gate.get("raw_command_printed") is False
        and gate.get("raw_api_printed") is False
    )


def _eval_public_ux_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("bin_integration") is False
        and gate.get("bot_apply") is False
        and gate.get("web_apply") is False
        and gate.get("installer_apply") is False
        and gate.get("tag_release") is False
    )


_GATE_EVALUATORS = {
    "repo_gate": _eval_repo_gate,
    "placeholder_validator_gate": _eval_placeholder_validator_gate,
    "credential_reference_gate": _eval_credential_reference_gate,
    "record_identity_gate": _eval_record_identity_gate,
    "precheck_gate": _eval_precheck_gate,
    "preview_gate": _eval_preview_gate,
    "approval_gate": _eval_approval_gate,
    "fake_helper_capture_gate": _eval_fake_helper_capture_gate,
    "fake_helper_json_gate": _eval_fake_helper_json_gate,
    "fake_postcheck_gate": _eval_fake_postcheck_gate,
    "classifier_gate": _eval_classifier_gate,
    "safe_renderer_gate": _eval_safe_renderer_gate,
    "redaction_gate": _eval_redaction_gate,
    "public_ux_gate": _eval_public_ux_gate,
}


# ── Skeleton evaluator ───────────────────────────────────────────────────────


def run_controlled_live_wrapper_skeleton_fake(data: dict) -> dict:
    """Run controlled live wrapper skeleton fake evaluation from safe fixture dict.

    Evaluates all gates for diagnostic step visibility, but exposes only the
    first failed gate/reason to beginner-safe output.

    Returns safe model with status, checks, first_failed_gate, safety.

    Raises RuntimeError on invalid input.
    """
    if not isinstance(data, dict):
        raise RuntimeError(_SKELETON_SAFE_ERROR_MSG)

    checks: dict[str, str] = {}
    diagnostic_blocked_reasons: list[str] = []
    first_failed_gate = "none"
    first_blocked_reason = "none"
    has_missing_gate = False
    has_known_policy_failure = False
    has_ambiguous_classifier = False

    # Evaluate all gates in order
    for gate_key, reason in _GATE_ORDER:
        gate_data = data.get(gate_key)
        if gate_data is None:
            # Missing gate section is malformed/ambiguous -> uncertain
            checks[gate_key] = "fail"
            has_missing_gate = True
            diagnostic_blocked_reasons.append(_REASON_MALFORMED)
            if first_failed_gate == "none":
                first_failed_gate = gate_key
                first_blocked_reason = _REASON_MALFORMED
            continue

        # Special handling for classifier_gate: ambiguous -> uncertain, not blocked
        if gate_key == "classifier_gate" and isinstance(gate_data, dict) and gate_data.get("ambiguous") is True:
            checks[gate_key] = "fail"
            has_ambiguous_classifier = True
            diagnostic_blocked_reasons.append(_REASON_CLASSIFIER_AMBIGUOUS)
            if first_failed_gate == "none":
                first_failed_gate = gate_key
                first_blocked_reason = _REASON_CLASSIFIER_AMBIGUOUS
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

    # blocked_reasons contains only known policy failures (beginner-facing)
    # Missing gates and ambiguous classifier are uncertain, not blocked
    blocked_reasons: list[str] = []
    if has_known_policy_failure and not has_missing_gate and not has_ambiguous_classifier:
        # Find the first known policy failure
        for gate_key, reason in _GATE_ORDER:
            if checks.get(gate_key) == "fail" and data.get(gate_key) is not None:
                blocked_reasons.append(reason)
                break

    # Extract classifier status for summary
    classifier = data.get("classifier_gate", {})
    classifier_status = "unknown"
    if isinstance(classifier, dict):
        classifier_status = classifier.get("status", "unknown")

    # Determine overall status
    all_pass = all(v == "pass" for v in checks.values())

    if all_pass and classifier_status == "fake_verified":
        status = _STATUS_FAKE_VERIFIED
        postcheck_result = "fake_verified"
        fake_transport = "verified"
        ready_category = "future_owner_approved_plan_only"
    elif all_pass and classifier_status == "ready_for_future_owner_approved_live_plan":
        status = _STATUS_READY
        postcheck_result = "fake_verified"
        fake_transport = "verified"
        ready_category = "future_owner_approved_plan_only"
    elif has_missing_gate or has_ambiguous_classifier:
        status = _STATUS_UNCERTAIN
        postcheck_result = "uncertain"
        fake_transport = "unknown"
        ready_category = "not_ready"
    elif has_known_policy_failure:
        status = _STATUS_BLOCKED
        postcheck_result = "blocked"
        fake_transport = "not_verified"
        ready_category = "not_ready"
    else:
        status = _STATUS_UNCERTAIN
        postcheck_result = "uncertain"
        fake_transport = "unknown"
        ready_category = "not_ready"

    return {
        "status": status,
        "mode": "fake_transport_only",
        "first_failed_gate": first_failed_gate,
        "first_blocked_reason": first_blocked_reason,
        "blocked_reasons": blocked_reasons,
        "diagnostic_blocked_reasons": diagnostic_blocked_reasons,
        "checks": checks,
        "summary": {
            "fake_transport": fake_transport,
            "postcheck": postcheck_result,
            "ready_category": ready_category,
        },
        "safety": {
            "live_cloudflare_called": "no",
            "real_helper_called": "no",
            "real_dns_mutation_performed": "no",
            "real_env_read": "no",
            "public_apply_allowed": "no",
            "actual_live_test_allowed": "no",
            "requires_later_owner_approval": "yes",
        },
    }


# ── Safe renderer ────────────────────────────────────────────────────────────


def render_controlled_live_wrapper_skeleton_fake_summary(model: dict) -> str:
    """Render beginner-safe skeleton summary from evaluated model.

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
        "NanoBK DNS Apply — Controlled Live Wrapper Skeleton Fake Summary",
        f"Status: {status}",
        f"Mode: {mode}",
        "",
        "Checks:",
        f"  Repo gate: {checks.get('repo_gate', 'unknown')}",
        f"  Placeholder validator gate: {checks.get('placeholder_validator_gate', 'unknown')}",
        f"  Credential reference gate: {checks.get('credential_reference_gate', 'unknown')}",
        f"  Record identity gate: {checks.get('record_identity_gate', 'unknown')}",
        f"  Pre-check gate: {checks.get('precheck_gate', 'unknown')}",
        f"  Preview gate: {checks.get('preview_gate', 'unknown')}",
        f"  Owner approval gate: {checks.get('approval_gate', 'unknown')}",
        f"  Fake helper capture gate: {checks.get('fake_helper_capture_gate', 'unknown')}",
        f"  Fake helper JSON gate: {checks.get('fake_helper_json_gate', 'unknown')}",
        f"  Fake post-check gate: {checks.get('fake_postcheck_gate', 'unknown')}",
        f"  Classifier gate: {checks.get('classifier_gate', 'unknown')}",
        f"  Safe renderer gate: {checks.get('safe_renderer_gate', 'unknown')}",
        f"  Redaction gate: {checks.get('redaction_gate', 'unknown')}",
        f"  Public UX gate: {checks.get('public_ux_gate', 'unknown')}",
        "",
        "Safety:",
        f"  Live Cloudflare called: {safety.get('live_cloudflare_called', 'no')}",
        f"  Real helper called: {safety.get('real_helper_called', 'no')}",
        f"  Real DNS mutation performed: {safety.get('real_dns_mutation_performed', 'no')}",
        f"  Real env read: {safety.get('real_env_read', 'no')}",
        f"  Public apply allowed: {safety.get('public_apply_allowed', 'no')}",
        f"  Actual live test allowed: {safety.get('actual_live_test_allowed', 'no')}",
        f"  Requires later owner approval: {safety.get('requires_later_owner_approval', 'yes')}",
    ]

    if status == _STATUS_FAKE_VERIFIED:
        lines.append("")
        lines.append("Fake transport verified only.")
        lines.append("No live Cloudflare call was made.")
        lines.append("No real helper was called.")
        lines.append("No real DNS mutation was performed.")
        lines.append("Actual live test is still not allowed.")

    if status == _STATUS_READY:
        lines.append("")
        lines.append("Ready for future owner-approved live plan.")
        lines.append("Actual live test is still not allowed.")

    if status in (_STATUS_BLOCKED, _STATUS_UNCERTAIN) and first_failed_gate != "none":
        lines.append("")
        lines.append(f"First failed gate: {first_failed_gate}")
        lines.append(f"First blocked reason: {first_blocked_reason}")

    lines.append("")
    if status == _STATUS_FAKE_VERIFIED:
        lines.append("Next: Fake transport gates pass. Ready for future owner-approved live plan.")
        lines.append("Actual live test is still not allowed.")
    elif status == _STATUS_READY:
        lines.append("Next: All gates pass. Ready for future owner-approved live plan.")
        lines.append("Actual live test is still not allowed.")
    elif status == _STATUS_BLOCKED:
        lines.append("Next: Resolve blocked conditions before proceeding.")
        lines.append("Actual live test is not allowed.")
    else:
        lines.append("Next: Review uncertain conditions. Actual live test is not allowed.")

    return "\n".join(lines) + "\n"


# ── Output safety gate ───────────────────────────────────────────────────────


class UnsafeControlledLiveWrapperSkeletonFakeOutputError(Exception):
    """Raised when rendered skeleton output contains forbidden patterns."""
    pass


def assert_safe_controlled_live_wrapper_skeleton_fake_output(text: str) -> None:
    """Fail closed if rendered output contains forbidden patterns.

    Raises UnsafeControlledLiveWrapperSkeletonFakeOutputError if any forbidden pattern is found.
    """
    for pattern in _FORBIDDEN_PATTERNS:
        if pattern.search(text):
            raise UnsafeControlledLiveWrapperSkeletonFakeOutputError(
                "Controlled live wrapper skeleton fake output contains forbidden pattern."
            )
