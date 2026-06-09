#!/usr/bin/env python3
"""
NanoBK DNS Apply Controlled Live Wrapper Mock — Pure mock wrapper contract.

Uses safe placeholder fixture dictionaries only. Evaluates the full
wrapper gate sequence: repo, credential, identity, precheck, preview,
approval, helper capture, helper JSON, postcheck, classifier, renderer,
final redaction, public UX.

NOT imported by bin/nanobk. NOT a user-facing command. NOT real DNS apply.
Does not call Cloudflare. Does not call helper. Does not read real env files.
Does not mutate DNS. Does not expose raw domains, IPs, record IDs, tokens,
env paths, API responses, helper stdout/stderr, or private keys.

mock_verified does NOT mean live verified.
live_cloudflare_called is always "no".
real_dns_mutation_performed is always "no".
real_env_read is always "no".
public_apply_allowed is always "no".

Usage:
    from nanobk_cf_dns_apply_controlled_live_wrapper_mock import run_controlled_live_wrapper_mock
    model = run_controlled_live_wrapper_mock(fixture_dict)
"""

from __future__ import annotations

import re
from typing import Any

# ── Constants ────────────────────────────────────────────────────────────────

_STATUS_MOCK_VERIFIED = "mock_verified"
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

_WRAPPER_SAFE_ERROR_MSG = (
    "NanoBK DNS Apply controlled live wrapper mock is fixture-only.\n"
    "A valid safe wrapper fixture is required.\n"
    "No DNS changes were made."
)

# ── Blocked reason categories (safe generic) ─────────────────────────────────

_REASON_REPO = "repo gate failed"
_REASON_CREDENTIAL = "credential gate failed"
_REASON_IDENTITY = "identity gate failed"
_REASON_PRECHECK = "pre-check gate failed"
_REASON_PREVIEW = "preview gate failed"
_REASON_APPROVAL = "owner approval gate failed"
_REASON_HELPER_CAPTURE = "helper capture gate failed"
_REASON_HELPER_JSON = "helper JSON gate failed"
_REASON_POSTCHECK = "post-check gate failed"
_REASON_CLASSIFIER = "classifier gate failed"
_REASON_RENDERER = "renderer gate failed"
_REASON_REDACTION = "final redaction gate failed"
_REASON_PUBLIC_UX = "public UX gate failed"

# ── Gate evaluation order ────────────────────────────────────────────────────

_GATE_ORDER = [
    ("repo_gate", _REASON_REPO),
    ("credential_gate", _REASON_CREDENTIAL),
    ("identity_gate", _REASON_IDENTITY),
    ("precheck_gate", _REASON_PRECHECK),
    ("preview_gate", _REASON_PREVIEW),
    ("approval_gate", _REASON_APPROVAL),
    ("helper_capture", _REASON_HELPER_CAPTURE),
    ("helper_json_gate", _REASON_HELPER_JSON),
    ("postcheck_gate", _REASON_POSTCHECK),
    ("classifier_gate", _REASON_CLASSIFIER),
    ("renderer_gate", _REASON_RENDERER),
    ("final_redaction_gate", _REASON_REDACTION),
    ("public_ux_gate", _REASON_PUBLIC_UX),
]


# ── Individual gate evaluators ───────────────────────────────────────────────


def _eval_repo_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("clean") is True
        and gate.get("head_expected") is True
    )


def _eval_credential_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("path_was_input_only") is True
        and gate.get("path_printed") is False
        and gate.get("permission_600") is True
        and gate.get("cat_source_eval_used") is False
        and gate.get("token_printed") is False
    )


def _eval_identity_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("disposable_category") is True
        and gate.get("raw_identity_printed") is False
        and gate.get("production_name_detected") is False
        and gate.get("subscription_proxy_web_bot_worker_name") is False
    )


def _eval_precheck_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("available") is True
        and gate.get("absent_or_managed_test_only") is True
        and gate.get("same_name_cname_absent") is True
        and gate.get("no_unmanaged_existing_record") is True
        and gate.get("no_delete") is True
        and gate.get("no_overwrite") is True
    )


def _eval_preview_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("generated") is True
        and gate.get("rendered_safe") is True
        and gate.get("redaction_passed") is True
    )


def _eval_approval_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("rollback_shown") is True
        and gate.get("postcheck_explained") is True
        and gate.get("exact_phrase_matched") is True
    )


def _eval_helper_capture(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("simulated") is True
        and gate.get("stdout_captured") is True
        and gate.get("stderr_captured") is True
        and gate.get("raw_output_printed") is False
    )


def _eval_helper_json_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("parse_ok") is True
        and gate.get("schema_ok") is True
        and gate.get("allowed_fields_only") is True
    )


def _eval_postcheck_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("available") is True
        and gate.get("api_acceptance_required") is True
        and gate.get("get_observes_record_required") is True
        and gate.get("record_exists") is True
        and gate.get("type_matches") is True
        and gate.get("content_matches_internally") is True
        and gate.get("proxied_false") is True
        and gate.get("same_name_cname_absent") is True
        and gate.get("count_matches") is True
        and gate.get("no_unexpected_delete") is True
        and gate.get("verified_only_after_postcheck") is True
    )


def _eval_classifier_gate(gate: dict) -> bool:
    # Classifier gate passes if status is a known safe value and not ambiguous.
    # "verified" and "uncertain" are both valid classifier outcomes.
    # "blocked" or unknown would fail the gate.
    return (
        isinstance(gate, dict)
        and gate.get("status") in ("verified", "uncertain")
        and gate.get("ambiguous") is False
    )


def _eval_renderer_gate(gate: dict) -> bool:
    return (
        isinstance(gate, dict)
        and gate.get("safe_summary_generated") is True
        and gate.get("raw_fields_removed") is True
    )


def _eval_final_redaction_gate(gate: dict) -> bool:
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
    )


_GATE_EVALUATORS = {
    "repo_gate": _eval_repo_gate,
    "credential_gate": _eval_credential_gate,
    "identity_gate": _eval_identity_gate,
    "precheck_gate": _eval_precheck_gate,
    "preview_gate": _eval_preview_gate,
    "approval_gate": _eval_approval_gate,
    "helper_capture": _eval_helper_capture,
    "helper_json_gate": _eval_helper_json_gate,
    "postcheck_gate": _eval_postcheck_gate,
    "classifier_gate": _eval_classifier_gate,
    "renderer_gate": _eval_renderer_gate,
    "final_redaction_gate": _eval_final_redaction_gate,
    "public_ux_gate": _eval_public_ux_gate,
}


# ── Wrapper evaluator ────────────────────────────────────────────────────────


def run_controlled_live_wrapper_mock(data: dict) -> dict:
    """Run controlled live wrapper mock evaluation from safe fixture dict.

    Evaluates gates in strict order. Stops recording blocked reasons at
    first failure but continues to evaluate all gates for diagnostic steps.

    Returns safe model with status, blocked_reasons, steps, summary, safety.

    Raises RuntimeError on invalid input.
    """
    if not isinstance(data, dict):
        raise RuntimeError(_WRAPPER_SAFE_ERROR_MSG)

    steps: dict[str, str] = {}
    blocked_reasons: list[str] = []

    # Extract safe record type and action from identity gate
    identity = data.get("identity_gate", {})
    safe_record_type = "unknown"
    safe_action_category = "unknown"
    if isinstance(identity, dict):
        safe_record_type = identity.get("safe_record_type", "unknown")
        safe_action_category = identity.get("safe_action_category", "unknown")

    # Evaluate all gates in order
    for gate_key, reason in _GATE_ORDER:
        gate_data = data.get(gate_key, {})
        evaluator = _GATE_EVALUATORS.get(gate_key)
        if evaluator and evaluator(gate_data):
            steps[gate_key] = "pass"
        else:
            steps[gate_key] = "fail"
            blocked_reasons.append(reason)

    # Extract classifier and postcheck status for summary
    classifier = data.get("classifier_gate", {})
    classifier_status = "unknown"
    if isinstance(classifier, dict):
        classifier_status = classifier.get("status", "unknown")

    postcheck = data.get("postcheck_gate", {})
    postcheck_result = "uncertain"
    if isinstance(postcheck, dict):
        if postcheck.get("available") is True and postcheck.get("record_exists") is True:
            postcheck_result = "verified"
        elif postcheck.get("available") is False:
            postcheck_result = "blocked"

    # Determine overall status
    all_pass = all(v == "pass" for v in steps.values())

    if all_pass and classifier_status == "verified":
        status = _STATUS_MOCK_VERIFIED
    elif blocked_reasons:
        status = _STATUS_BLOCKED
    else:
        status = _STATUS_UNCERTAIN

    # Count summary
    planned = 1 if safe_action_category in ("create", "update") else 0
    verified = 1 if (status == _STATUS_MOCK_VERIFIED and postcheck_result == "verified") else 0
    blocked_count = 1 if status == _STATUS_BLOCKED else 0
    unknown_count = 1 if status == _STATUS_UNCERTAIN else 0

    return {
        "status": status,
        "mode": "placeholder_only",
        "blocked_reasons": blocked_reasons,
        "steps": steps,
        "summary": {
            "safe_record_type": safe_record_type,
            "safe_action_category": safe_action_category,
            "counts": {
                "planned": planned,
                "verified": verified,
                "blocked": blocked_count,
                "unknown": unknown_count,
            },
            "postcheck_result": postcheck_result,
        },
        "safety": {
            "live_cloudflare_called": "no",
            "real_dns_mutation_performed": "no",
            "real_env_read": "no",
            "public_apply_allowed": "no",
            "requires_owner_approved_future_live_test": "yes",
        },
    }


# ── Safe renderer ────────────────────────────────────────────────────────────


def render_controlled_live_wrapper_summary(model: dict) -> str:
    """Render beginner-safe controlled live wrapper summary from evaluated model."""
    status = model.get("status", "unknown")
    mode = model.get("mode", "unknown")
    blocked_reasons = model.get("blocked_reasons", [])
    steps = model.get("steps", {})
    summary = model.get("summary", {})
    counts = summary.get("counts", {})
    safety = model.get("safety", {})

    lines = [
        "NanoBK DNS Apply — Controlled Live Wrapper Mock Summary",
        f"Status: {status}",
        f"Mode: {mode}",
        "",
        "Steps:",
        f"  Repo gate: {steps.get('repo_gate', 'unknown')}",
        f"  Credential gate: {steps.get('credential_gate', 'unknown')}",
        f"  Identity gate: {steps.get('identity_gate', 'unknown')}",
        f"  Pre-check gate: {steps.get('precheck_gate', 'unknown')}",
        f"  Preview gate: {steps.get('preview_gate', 'unknown')}",
        f"  Owner approval gate: {steps.get('approval_gate', 'unknown')}",
        f"  Helper capture gate: {steps.get('helper_capture', 'unknown')}",
        f"  Helper JSON gate: {steps.get('helper_json_gate', 'unknown')}",
        f"  Post-check gate: {steps.get('postcheck_gate', 'unknown')}",
        f"  Classifier gate: {steps.get('classifier_gate', 'unknown')}",
        f"  Renderer gate: {steps.get('renderer_gate', 'unknown')}",
        f"  Final redaction gate: {steps.get('final_redaction_gate', 'unknown')}",
        f"  Public UX gate: {steps.get('public_ux_gate', 'unknown')}",
        "",
        "Safe summary:",
        f"  Record type: {summary.get('safe_record_type', 'unknown')}",
        f"  Action: {summary.get('safe_action_category', 'unknown')}",
        f"  Planned: {counts.get('planned', 0)}",
        f"  Verified: {counts.get('verified', 0)}",
        f"  Blocked: {counts.get('blocked', 0)}",
        f"  Unknown: {counts.get('unknown', 0)}",
        f"  Post-check result: {summary.get('postcheck_result', 'uncertain')}",
        "",
        "Safety:",
        f"  Live Cloudflare called: {safety.get('live_cloudflare_called', 'no')}",
        f"  Real DNS mutation performed: {safety.get('real_dns_mutation_performed', 'no')}",
        f"  Real env read: {safety.get('real_env_read', 'no')}",
        f"  Public apply allowed: {safety.get('public_apply_allowed', 'no')}",
        f"  Requires owner-approved future live test: {safety.get('requires_owner_approved_future_live_test', 'yes')}",
    ]

    if status == _STATUS_MOCK_VERIFIED:
        lines.append("")
        lines.append("Mock verified only.")
        lines.append("No live Cloudflare call was made.")
        lines.append("No real DNS mutation was performed.")

    if blocked_reasons:
        lines.append("")
        lines.append("Blocked reasons:")
        for reason in blocked_reasons:
            lines.append(f"  - {reason}")

    lines.append("")
    if status == _STATUS_MOCK_VERIFIED:
        lines.append("Next: All mock gates pass. Ready for future owner-approved live test.")
        lines.append("Live mutation is still not allowed in this version.")
    elif status == _STATUS_BLOCKED:
        lines.append("Next: Resolve blocked conditions before proceeding.")
        lines.append("Live mutation is not allowed.")
    else:
        lines.append("Next: Review uncertain conditions. Live mutation is not allowed.")

    return "\n".join(lines) + "\n"


# ── Output safety gate ───────────────────────────────────────────────────────


class UnsafeControlledLiveWrapperOutputError(Exception):
    """Raised when rendered wrapper output contains forbidden patterns."""
    pass


def assert_safe_controlled_live_wrapper_output(text: str) -> None:
    """Fail closed if rendered output contains forbidden patterns.

    Raises UnsafeControlledLiveWrapperOutputError if any forbidden pattern is found.
    """
    for pattern in _FORBIDDEN_PATTERNS:
        if pattern.search(text):
            raise UnsafeControlledLiveWrapperOutputError(
                "Controlled live wrapper output contains forbidden pattern."
            )
