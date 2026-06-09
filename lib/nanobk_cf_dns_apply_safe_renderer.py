#!/usr/bin/env python3
"""
NanoBK DNS Apply Safe Renderer — Beginner-safe mock renderer prototype.

Standalone renderer that normalizes low-level helper-style raw JSON into a
beginner-safe DNS Apply summary model. Does not invoke helper. Does not call
Cloudflare. Does not mutate DNS.

NOT imported by bin/nanobk. NOT public CLI. NOT real DNS apply.

Usage:
    from nanobk_cf_dns_apply_safe_renderer import render_from_helper_json
    output = render_from_helper_json(raw_dict, mode="fake_only")
"""

from __future__ import annotations

import re
from typing import Any

# ── Constants ────────────────────────────────────────────────────────────────

_STATUS_APPLIED = "applied"
_STATUS_UNCERTAIN = "uncertain"
_STATUS_PARTIAL = "partial"
_STATUS_CONFLICT = "conflict"
_STATUS_FAILED = "failed"
_STATUS_READY = "ready"

_MODE_FAKE_ONLY = "fake_only"
_MODE_DRY_RUN = "dry_run"
_MODE_CHECK_ONLY = "check_only"
_MODE_LIVE_PENDING = "live_pending"
_MODE_LIVE_APPLIED = "live_applied"

_ALLOWED_MODES = {
    _MODE_FAKE_ONLY, _MODE_DRY_RUN, _MODE_CHECK_ONLY,
    _MODE_LIVE_PENDING, _MODE_LIVE_APPLIED,
}

_ALLOWED_ACTIONS = {"noop", "create", "update", "fail_conflict", "skip"}
_ALLOWED_RECORD_TYPES = {"A", "AAAA"}

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
    re.compile(r"plannedContent", re.IGNORECASE),
    re.compile(r"existingContent", re.IGNORECASE),
]

# Raw fields that must never appear in normalized model
_RAW_FIELDS = {"name", "plannedContent", "existingContent", "recordId", "message"}


# ── Adapter: normalize raw helper JSON ───────────────────────────────────────

def normalize_helper_json(raw: dict, mode: str = _MODE_FAKE_ONLY) -> dict:
    """Normalize raw helper-style JSON into a safe model.

    Counts actions by action type and record type only.
    Does NOT copy raw name, plannedContent, existingContent, recordId, message.
    """
    if mode not in _ALLOWED_MODES:
        mode = _MODE_FAKE_ONLY

    actions = raw.get("actions", [])
    results = raw.get("results", [])
    raw_ok = raw.get("ok", True)

    # Count actions
    action_counts = {"create": 0, "update": 0, "no_change": 0, "conflict": 0, "failed": 0}
    record_type_counts = {"A": 0, "AAAA": 0}

    for action in actions:
        if not isinstance(action, dict):
            continue
        act = action.get("action", "unknown")
        if act == "noop":
            action_counts["no_change"] += 1
        elif act == "create":
            action_counts["create"] += 1
        elif act == "update":
            action_counts["update"] += 1
        elif act == "fail_conflict":
            action_counts["conflict"] += 1
        elif act == "skip":
            pass  # not counted
        rtype = action.get("recordType", "")
        if rtype in record_type_counts:
            record_type_counts[rtype] += 1

    # Count results
    result_success = 0
    result_failed = 0
    for result in results:
        if not isinstance(result, dict):
            continue
        if result.get("success"):
            result_success += 1
        else:
            result_failed += 1

    # Determine status
    has_conflicts = action_counts["conflict"] > 0
    has_failures = result_failed > 0
    has_mutations = action_counts["create"] > 0 or action_counts["update"] > 0
    has_successes = result_success > 0

    if has_conflicts:
        status = _STATUS_CONFLICT
    elif has_failures and has_successes:
        status = _STATUS_PARTIAL
    elif has_failures and not has_successes:
        status = _STATUS_FAILED
    elif not raw_ok and has_failures:
        status = _STATUS_FAILED
    elif has_mutations and has_successes:
        status = _STATUS_APPLIED
    elif has_mutations:
        status = _STATUS_UNCERTAIN
    elif mode in (_MODE_DRY_RUN, _MODE_CHECK_ONLY):
        status = _STATUS_READY
    else:
        status = _STATUS_READY

    # Safety
    dns_only = "yes"  # NanoBK always uses DNS-only (proxied=false)
    fake_transport_used = "yes" if mode == _MODE_FAKE_ONLY else "not_applicable"
    live_verified = "no"

    # Notices
    notices: list[str] = []
    if mode == _MODE_FAKE_ONLY:
        notices.append("Test mode: fake transport only.")
        notices.append("No live Cloudflare verification was performed.")
    notices.append("No DNS records were deleted.")

    # Recovery
    recovery: list[str] = []
    if status == _STATUS_CONFLICT:
        recovery.append("Existing records need manual resolution.")
        recovery.append("Do not retry blindly.")
    elif status == _STATUS_PARTIAL:
        recovery.append("Some records could not be verified.")
        recovery.append("Do not retry blindly.")
        recovery.append("Review Cloudflare DNS manually.")
    elif status == _STATUS_FAILED:
        recovery.append("Apply failed.")
        recovery.append("Do not retry blindly.")

    return {
        "status": status,
        "mode": mode,
        "action_counts": action_counts,
        "record_type_counts": record_type_counts,
        "safety": {
            "dns_only": dns_only,
            "fake_transport_used": fake_transport_used,
            "live_cloudflare_verified": live_verified,
            "deletes_supported": "no",
        },
        "notices": notices,
        "recovery": recovery,
    }


# ── Renderer ─────────────────────────────────────────────────────────────────

def render_safe_summary(model: dict) -> str:
    """Render beginner-safe summary from normalized model."""
    status = model.get("status", "unknown")
    mode = model.get("mode", "unknown")
    ac = model.get("action_counts", {})
    rtc = model.get("record_type_counts", {})
    safety = model.get("safety", {})
    notices = model.get("notices", [])
    recovery = model.get("recovery", [])

    lines = [
        "NanoBK DNS Apply — Safe Summary",
        f"Status: {status}",
        f"Mode: {mode}",
        "",
        "Actions:",
        f"  Create: {ac.get('create', 0)}",
        f"  Update: {ac.get('update', 0)}",
        f"  No change: {ac.get('no_change', 0)}",
        f"  Conflict: {ac.get('conflict', 0)}",
        f"  Failed: {ac.get('failed', 0)}",
        "",
        "Record types:",
        f"  A: {rtc.get('A', 0)}",
        f"  AAAA: {rtc.get('AAAA', 0)}",
        "",
        "Safety:",
        f"  DNS-only: {safety.get('dns_only', 'unknown')}",
        f"  Deletes supported: {safety.get('deletes_supported', 'no')}",
    ]

    for notice in notices:
        lines.append(notice)

    # Next step
    lines.append("")
    if status == _STATUS_APPLIED:
        lines.append("Next: No further action needed.")
    elif status == _STATUS_READY:
        lines.append("Next: Review the plan and confirm when ready.")
    elif status == _STATUS_CONFLICT:
        lines.append("Next: Resolve conflicts manually before applying.")
    elif status in (_STATUS_PARTIAL, _STATUS_FAILED):
        lines.append("Next: Review Cloudflare DNS manually.")
    else:
        lines.append("Next: Review the current state before proceeding.")

    return "\n".join(lines) + "\n"


# ── Output safety gate ───────────────────────────────────────────────────────

class UnsafeOutputError(Exception):
    """Raised when rendered output contains forbidden patterns."""
    pass


def assert_safe_output(text: str) -> None:
    """Fail closed if rendered output contains forbidden patterns.

    Raises UnsafeOutputError if any forbidden pattern is found.
    Does not print the unsafe output.
    """
    for pattern in _FORBIDDEN_PATTERNS:
        if pattern.search(text):
            raise UnsafeOutputError(
                "Rendered output contains forbidden pattern."
            )


# ── Convenience function ─────────────────────────────────────────────────────

def render_from_helper_json(raw: dict, mode: str = _MODE_FAKE_ONLY) -> str:
    """Normalize raw helper JSON, render safe summary, and verify output safety.

    Raises UnsafeOutputError if final output contains forbidden patterns.
    """
    model = normalize_helper_json(raw, mode)
    text = render_safe_summary(model)
    assert_safe_output(text)
    return text
