#!/usr/bin/env python3
"""
NanoBK DNS Apply Post-check Classifier Mock — Pure mock classifier.

Consumes safe structured post-check fixture dicts and classifies the result
into a beginner-safe status bucket: ready, applied, verified, partial,
conflict, failed, or uncertain.

NOT imported by bin/nanobk. NOT a user-facing command. NOT real DNS apply.
Does not call Cloudflare. Does not call helper. Does not mutate DNS.
Does not expose raw domains, IPs, record IDs, zone/account IDs, tokens,
API responses, or private keys.

Classification rules follow v2.2.18 post-check contract:
- verified requires post-check (mode=live_applied + postcheck_available=true).
- applied must not mean verified.
- fake_only must never return verified.
- conflict takes precedence over all other statuses.

Usage:
    from nanobk_cf_dns_apply_postcheck_classifier_mock import classify_postcheck
    model = classify_postcheck(fixture_dict)
"""

from __future__ import annotations

import re
from typing import Any

# ── Constants ────────────────────────────────────────────────────────────────

_STATUS_READY = "ready"
_STATUS_APPLIED = "applied"
_STATUS_VERIFIED = "verified"
_STATUS_PARTIAL = "partial"
_STATUS_CONFLICT = "conflict"
_STATUS_FAILED = "failed"
_STATUS_UNCERTAIN = "uncertain"

_ALLOWED_STATUSES = {
    _STATUS_READY, _STATUS_APPLIED, _STATUS_VERIFIED,
    _STATUS_PARTIAL, _STATUS_CONFLICT, _STATUS_FAILED, _STATUS_UNCERTAIN,
}

_ALLOWED_MODES = {"fake_only", "dry_run", "check_only", "live_pending", "live_applied"}
_ALLOWED_RECORD_TYPES = {"A", "AAAA"}
_ALLOWED_ACTIONS = {"create", "update", "noop", "conflict", "skip"}
_ALLOWED_RESULT_ACTIONS = {"create", "update", "noop", "skipped"}
_ALLOWED_TARGET_CLASSES = {"ipv4", "ipv6", "unknown"}

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

# ── Safe error ───────────────────────────────────────────────────────────────

_CLASSIFIER_SAFE_ERROR_MSG = (
    "NanoBK DNS Apply post-check classifier mock is fixture-only.\n"
    "A valid safe post-check fixture is required.\n"
    "No DNS changes were made."
)

# ── Recovery text ────────────────────────────────────────────────────────────

_RECOVERY_CONFLICT = "Existing records need manual resolution. Do not retry blindly."
_RECOVERY_FAILED = "Apply failed. Do not retry blindly."
_RECOVERY_PARTIAL = "Some records could not be verified. Do not retry blindly. Review Cloudflare DNS manually."
_RECOVERY_APPLIED = "Applied does not mean verified. Review Cloudflare DNS manually."
_RECOVERY_VERIFIED = "Verified by post-check. No further action needed."
_RECOVERY_READY = "Review the plan and confirm when ready."
_RECOVERY_UNCERTAIN = "The current state could not be determined. Do not retry blindly. Review Cloudflare DNS manually."

# ── Classifier ───────────────────────────────────────────────────────────────


def classify_postcheck(data: dict) -> dict:
    """Classify post-check input into a safe status model.

    Classification priority (highest to lowest):
    1. conflict — any planned conflict means no mutation should happen.
    2. failed — all mutations failed or all post-checks show missing/wrong.
    3. verified — live_applied + postcheck + all records verified.
    4. partial — some verified, some failed/missing/unknown.
    5. uncertain — any mutation result has unknown success.
    6. applied — mutations succeeded but no post-check proof.
    7. ready — dry_run/check_only with no mutation.
    8. uncertain — ambiguous or malformed data (fallback).

    Raises RuntimeError on invalid input.
    """
    if not isinstance(data, dict):
        raise RuntimeError(_CLASSIFIER_SAFE_ERROR_MSG)

    mode = data.get("mode", "")
    if mode not in _ALLOWED_MODES:
        mode = "fake_only"

    planned = data.get("planned_records", [])
    results = data.get("apply_results", [])
    observed = data.get("observed_records", [])
    postcheck_available = data.get("postcheck_available", False)

    if not isinstance(planned, list):
        planned = []
    if not isinstance(results, list):
        results = []
    if not isinstance(observed, list):
        observed = []

    # Count planned records by type
    record_type_counts: dict[str, int] = {"A": 0, "AAAA": 0}
    has_conflict = False
    for rec in planned:
        if not isinstance(rec, dict):
            continue
        rtype = rec.get("record_type", "")
        if rtype in record_type_counts:
            record_type_counts[rtype] += 1
        if rec.get("action") == "conflict":
            has_conflict = True

    planned_count = sum(record_type_counts.values())

    # Count apply results
    applied_success = 0
    applied_failed = 0
    all_mutations_failed = True
    has_any_mutation = False
    has_unknown_mutation = False
    for res in results:
        if not isinstance(res, dict):
            continue
        action = res.get("action", "")
        success = res.get("success")
        if action in ("create", "update"):
            has_any_mutation = True
            if success is True:
                applied_success += 1
                all_mutations_failed = False
            elif success is False:
                applied_failed += 1
            else:
                # unknown success — cannot prove safety
                has_unknown_mutation = True
                all_mutations_failed = False

    # Count observed records
    verified_count = 0
    postcheck_failed = 0
    unknown_count = 0
    all_verified = True
    any_verified = False
    for obs in observed:
        if not isinstance(obs, dict):
            continue
        exists = obs.get("exists")
        matches = obs.get("content_matches_expected")
        dns_only = obs.get("proxied_is_dns_only")
        if exists is True and matches is True and dns_only is True:
            verified_count += 1
            any_verified = True
        elif exists is False or matches is False or dns_only is False:
            postcheck_failed += 1
            all_verified = False
        else:
            unknown_count += 1
            all_verified = False

    # ── Classification ──────────────────────────────────────────────────────

    # 1. conflict — highest priority
    if has_conflict:
        status = _STATUS_CONFLICT
        recovery = [_RECOVERY_CONFLICT]

    # 2. failed — all mutations failed or all post-checks show wrong
    elif has_any_mutation and all_mutations_failed:
        status = _STATUS_FAILED
        recovery = [_RECOVERY_FAILED]

    elif (postcheck_available and observed
          and postcheck_failed > 0 and verified_count == 0):
        status = _STATUS_FAILED
        recovery = [_RECOVERY_FAILED]

    # 3. verified — requires live_applied + postcheck + all verified
    elif (mode == "live_applied"
          and postcheck_available
          and observed
          and all_verified
          and verified_count > 0):
        status = _STATUS_VERIFIED
        recovery = [_RECOVERY_VERIFIED]

    # 4. partial — some verified, some failed/missing/unknown
    elif any_verified and (postcheck_failed > 0 or unknown_count > 0):
        status = _STATUS_PARTIAL
        recovery = [_RECOVERY_PARTIAL]

    # 5. uncertain — any mutation result has unknown success
    # (cannot prove safety; must not be classified as applied or verified)
    elif has_unknown_mutation:
        status = _STATUS_UNCERTAIN
        recovery = [_RECOVERY_UNCERTAIN]

    # 6. applied — mutations succeeded but no post-check proof
    elif has_any_mutation and applied_success > 0:
        status = _STATUS_APPLIED
        recovery = [_RECOVERY_APPLIED]

    elif mode in ("fake_only", "live_pending") and has_any_mutation:
        status = _STATUS_APPLIED
        recovery = [_RECOVERY_APPLIED]

    # 7. ready — dry_run/check_only with no mutation
    elif mode in ("dry_run", "check_only"):
        status = _STATUS_READY
        recovery = [_RECOVERY_READY]

    # 8. uncertain — fallback
    else:
        status = _STATUS_UNCERTAIN
        recovery = [_RECOVERY_UNCERTAIN]

    return {
        "status": status,
        "mode": mode,
        "counts": {
            "planned": planned_count,
            "applied_success": applied_success,
            "applied_failed": applied_failed,
            "verified": verified_count,
            "postcheck_failed": postcheck_failed,
            "unknown": unknown_count,
        },
        "record_type_counts": record_type_counts,
        "safety": {
            "postcheck_required_for_verified": "yes",
            "fake_only_live_verified": "no",
            "deletes_supported": "no",
        },
        "recovery": recovery,
    }


# ── Safe renderer ────────────────────────────────────────────────────────────


def render_postcheck_summary(model: dict) -> str:
    """Render beginner-safe post-check summary from classified model."""
    status = model.get("status", "unknown")
    mode = model.get("mode", "unknown")
    counts = model.get("counts", {})
    rtc = model.get("record_type_counts", {})
    safety = model.get("safety", {})
    recovery = model.get("recovery", [])

    lines = [
        "NanoBK DNS Apply — Post-check Summary",
        f"Status: {status}",
        f"Mode: {mode}",
        "",
        "Counts:",
        f"  Planned: {counts.get('planned', 0)}",
        f"  Applied success: {counts.get('applied_success', 0)}",
        f"  Applied failed: {counts.get('applied_failed', 0)}",
        f"  Verified: {counts.get('verified', 0)}",
        f"  Post-check failed: {counts.get('postcheck_failed', 0)}",
        f"  Unknown: {counts.get('unknown', 0)}",
        "",
        "Record types:",
        f"  A: {rtc.get('A', 0)}",
        f"  AAAA: {rtc.get('AAAA', 0)}",
        "",
        "Safety:",
        f"  Verified requires post-check: {safety.get('postcheck_required_for_verified', 'yes')}",
        f"  Fake-only live verified: {safety.get('fake_only_live_verified', 'no')}",
        f"  Deletes supported: {safety.get('deletes_supported', 'no')}",
    ]

    # Mode-specific notices
    if mode == "fake_only":
        lines.append("")
        lines.append("Fake mode: no live Cloudflare verification was performed.")

    if status == _STATUS_APPLIED:
        lines.append("")
        lines.append("Applied does not mean verified.")

    if status == _STATUS_VERIFIED:
        lines.append("")
        lines.append("Verified by post-check.")

    # Recovery
    if recovery:
        lines.append("")
        lines.append("Next:")
        for tip in recovery:
            lines.append(f"  {tip}")

    return "\n".join(lines) + "\n"


# ── Output safety gate ───────────────────────────────────────────────────────


class UnsafePostcheckOutputError(Exception):
    """Raised when rendered post-check output contains forbidden patterns."""
    pass


def assert_safe_postcheck_output(text: str) -> None:
    """Fail closed if rendered output contains forbidden patterns.

    Raises UnsafePostcheckOutputError if any forbidden pattern is found.
    Does not print the unsafe output.
    """
    for pattern in _FORBIDDEN_PATTERNS:
        if pattern.search(text):
            raise UnsafePostcheckOutputError(
                "Post-check output contains forbidden pattern."
            )
