#!/usr/bin/env python3
"""
NanoBK DNS Apply Controlled Live Gate Mock — Pure mock gate checker.

Consumes safe placeholder fixture dicts and evaluates whether all gate
conditions are satisfied for a controlled live Cloudflare DNS test.

NOT imported by bin/nanobk. NOT a user-facing command. NOT real DNS apply.
Does not call Cloudflare. Does not call helper. Does not read real env files.
Does not mutate DNS. Does not expose raw domains, IPs, record IDs, tokens,
env paths, API responses, or private keys.

Even when status is ready_for_owner_approved_live_test_plan:
- live_mutation_allowed remains "no"
- public_apply_allowed remains "no"

Usage:
    from nanobk_cf_dns_apply_controlled_live_gate_mock import evaluate_controlled_live_gate
    model = evaluate_controlled_live_gate(fixture_dict)
"""

from __future__ import annotations

import re
from typing import Any

# ── Constants ────────────────────────────────────────────────────────────────

_STATUS_READY = "ready_for_owner_approved_live_test_plan"
_STATUS_BLOCKED = "blocked"

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

_GATE_SAFE_ERROR_MSG = (
    "NanoBK DNS Apply controlled live gate mock is fixture-only.\n"
    "A valid safe gate fixture is required.\n"
    "No DNS changes were made."
)

# ── Blocked reason categories (safe generic) ─────────────────────────────────

_REASON_REPO = "repo gate failed"
_REASON_SCOPE = "scope gate failed"
_REASON_APPROVAL = "owner approval gate failed"
_REASON_CREDENTIALS = "credential handling gate failed"
_REASON_PRECHECK = "pre-check gate failed"
_REASON_MUTATION = "mutation safety gate failed"
_REASON_POSTCHECK = "post-check gate failed"
_REASON_ROLLBACK = "rollback gate failed"
_REASON_REDACTION = "redaction gate failed"
_REASON_PUBLIC_UX = "public UX gate failed"

# ── Gate evaluator ───────────────────────────────────────────────────────────


def evaluate_controlled_live_gate(data: dict) -> dict:
    """Evaluate controlled live gate from safe placeholder fixture dict.

    Returns a safe model with status, blocked_reasons, checks, and safety.
    Status is ready_for_owner_approved_live_test_plan only if ALL gates pass.
    Otherwise status is blocked.

    Raises RuntimeError on invalid input.
    """
    if not isinstance(data, dict):
        raise RuntimeError(_GATE_SAFE_ERROR_MSG)

    blocked_reasons: list[str] = []
    checks: dict[str, str] = {}

    # ── Repo gate ────────────────────────────────────────────────────────
    repo = data.get("repo", {})
    repo_pass = (
        isinstance(repo, dict)
        and repo.get("clean") is True
        and repo.get("head_expected") is True
    )
    checks["repo"] = "pass" if repo_pass else "fail"
    if not repo_pass:
        blocked_reasons.append(_REASON_REPO)

    # ── Scope gate ───────────────────────────────────────────────────────
    scope = data.get("scope", {})
    scope_required = [
        "disposable_test_record", "owner_controlled_zone", "single_record",
        "single_record_type_first", "create_only_first", "no_production_hostname",
        "no_delete", "no_unmanaged_overwrite", "no_public_ux",
    ]
    scope_pass = isinstance(scope, dict) and all(
        scope.get(k) is True for k in scope_required
    )
    checks["scope"] = "pass" if scope_pass else "fail"
    if not scope_pass:
        blocked_reasons.append(_REASON_SCOPE)

    # ── Approval gate ────────────────────────────────────────────────────
    approval = data.get("approval", {})
    approval_required = [
        "phrase_present", "exact_phrase_matched", "shown_safe_identity",
        "shown_planned_action_category", "shown_no_delete_policy",
        "shown_manual_rollback", "shown_postcheck_requirement",
        "shown_redacted_output_policy",
    ]
    approval_pass = isinstance(approval, dict) and all(
        approval.get(k) is True for k in approval_required
    )
    checks["approval"] = "pass" if approval_pass else "fail"
    if not approval_pass:
        blocked_reasons.append(_REASON_APPROVAL)

    # ── Credentials gate ─────────────────────────────────────────────────
    creds = data.get("credentials", {})
    creds_pass = (
        isinstance(creds, dict)
        and creds.get("permission_600") is True
        and creds.get("env_path_printed") is False
        and creds.get("token_printed") is False
        and creds.get("cat_source_eval_used") is False
    )
    checks["credentials"] = "pass" if creds_pass else "fail"
    if not creds_pass:
        blocked_reasons.append(_REASON_CREDENTIALS)

    # ── Pre-check gate ───────────────────────────────────────────────────
    precheck = data.get("precheck", {})
    precheck_required = [
        "absent_or_managed_test_only", "same_name_cname_absent",
        "record_type_expected", "no_unmanaged_existing_record",
        "preview_generated", "owner_approval_after_preview",
    ]
    precheck_pass = isinstance(precheck, dict) and all(
        precheck.get(k) is True for k in precheck_required
    )
    checks["precheck"] = "pass" if precheck_pass else "fail"
    if not precheck_pass:
        blocked_reasons.append(_REASON_PRECHECK)

    # ── Mutation gate ────────────────────────────────────────────────────
    mutation = data.get("mutation_gate", {})
    mutation_required = [
        "actual_live_mutation_blocked_in_this_version",
        "future_create_only", "future_single_record", "future_no_delete",
        "future_no_overwrite", "future_stop_on_first_failure",
        "future_raw_output_captured", "future_safe_summary_only",
    ]
    mutation_pass = isinstance(mutation, dict) and all(
        mutation.get(k) is True for k in mutation_required
    )
    checks["mutation_gate"] = "pass" if mutation_pass else "fail"
    if not mutation_pass:
        blocked_reasons.append(_REASON_MUTATION)

    # ── Post-check gate ──────────────────────────────────────────────────
    postcheck = data.get("postcheck", {})
    postcheck_required = [
        "planned", "api_acceptance_required", "get_observes_record_required",
        "record_exists_required", "type_matches_required",
        "content_matches_internally_required", "proxied_false_required",
        "no_cname_conflict_required", "count_matches_required",
        "no_unexpected_delete_required", "verified_only_after_postcheck",
    ]
    postcheck_pass = isinstance(postcheck, dict) and all(
        postcheck.get(k) is True for k in postcheck_required
    )
    checks["postcheck"] = "pass" if postcheck_pass else "fail"
    if not postcheck_pass:
        blocked_reasons.append(_REASON_POSTCHECK)

    # ── Rollback gate ────────────────────────────────────────────────────
    rollback = data.get("rollback", {})
    rollback_required = [
        "manual_instruction_exists", "automatic_delete_disabled",
        "manual_dashboard_revert_required", "no_blind_retry",
    ]
    rollback_pass = isinstance(rollback, dict) and all(
        rollback.get(k) is True for k in rollback_required
    )
    checks["rollback"] = "pass" if rollback_pass else "fail"
    if not rollback_pass:
        blocked_reasons.append(_REASON_ROLLBACK)

    # ── Redaction gate ───────────────────────────────────────────────────
    redaction = data.get("redaction", {})
    redaction_pass = (
        isinstance(redaction, dict)
        and redaction.get("scan_before_output") is True
        and redaction.get("safe_summary_only") is True
        and redaction.get("raw_mutation_command_printed") is False
        and redaction.get("raw_api_printed") is False
        and redaction.get("secret_or_address_printed") is False
    )
    checks["redaction"] = "pass" if redaction_pass else "fail"
    if not redaction_pass:
        blocked_reasons.append(_REASON_REDACTION)

    # ── Public UX gate ───────────────────────────────────────────────────
    public_ux = data.get("public_ux", {})
    public_ux_pass = (
        isinstance(public_ux, dict)
        and public_ux.get("bin_integration") is False
        and public_ux.get("bot_apply") is False
        and public_ux.get("web_apply") is False
        and public_ux.get("installer_apply") is False
        and public_ux.get("separate_review_required") is True
    )
    checks["public_ux"] = "pass" if public_ux_pass else "fail"
    if not public_ux_pass:
        blocked_reasons.append(_REASON_PUBLIC_UX)

    # ── Final status ─────────────────────────────────────────────────────
    all_pass = all(v == "pass" for v in checks.values())
    status = _STATUS_READY if all_pass else _STATUS_BLOCKED

    return {
        "status": status,
        "blocked_reasons": blocked_reasons,
        "checks": checks,
        "safety": {
            "live_mutation_allowed": "no",
            "public_apply_allowed": "no",
            "requires_future_owner_approved_test": "yes",
        },
    }


# ── Safe renderer ────────────────────────────────────────────────────────────


def render_controlled_live_gate_summary(model: dict) -> str:
    """Render beginner-safe controlled live gate summary from evaluated model."""
    status = model.get("status", "unknown")
    blocked_reasons = model.get("blocked_reasons", [])
    checks = model.get("checks", {})
    safety = model.get("safety", {})

    lines = [
        "NanoBK DNS Apply — Controlled Live Gate Summary",
        f"Status: {status}",
        "",
        "Checks:",
        f"  Repo: {checks.get('repo', 'unknown')}",
        f"  Scope: {checks.get('scope', 'unknown')}",
        f"  Owner approval: {checks.get('approval', 'unknown')}",
        f"  Credentials: {checks.get('credentials', 'unknown')}",
        f"  Pre-check: {checks.get('precheck', 'unknown')}",
        f"  Mutation gate: {checks.get('mutation_gate', 'unknown')}",
        f"  Post-check: {checks.get('postcheck', 'unknown')}",
        f"  Rollback: {checks.get('rollback', 'unknown')}",
        f"  Redaction: {checks.get('redaction', 'unknown')}",
        f"  Public UX: {checks.get('public_ux', 'unknown')}",
        "",
        "Safety:",
        f"  Live mutation allowed: {safety.get('live_mutation_allowed', 'no')}",
        f"  Public apply allowed: {safety.get('public_apply_allowed', 'no')}",
        f"  Requires future owner-approved test: {safety.get('requires_future_owner_approved_test', 'yes')}",
    ]

    if blocked_reasons:
        lines.append("")
        lines.append("Blocked reasons:")
        for reason in blocked_reasons:
            lines.append(f"  - {reason}")

    lines.append("")
    if status == _STATUS_READY:
        lines.append("Next: All mock gates pass. Ready for future owner-approved controlled live test plan.")
        lines.append("Live mutation is still not allowed in this version.")
    else:
        lines.append("Next: Resolve blocked conditions before proceeding.")
        lines.append("Live mutation is not allowed.")

    return "\n".join(lines) + "\n"


# ── Output safety gate ───────────────────────────────────────────────────────


class UnsafeControlledLiveGateOutputError(Exception):
    """Raised when rendered gate output contains forbidden patterns."""
    pass


def assert_safe_controlled_live_gate_output(text: str) -> None:
    """Fail closed if rendered output contains forbidden patterns.

    Raises UnsafeControlledLiveGateOutputError if any forbidden pattern is found.
    """
    for pattern in _FORBIDDEN_PATTERNS:
        if pattern.search(text):
            raise UnsafeControlledLiveGateOutputError(
                "Controlled live gate output contains forbidden pattern."
            )
