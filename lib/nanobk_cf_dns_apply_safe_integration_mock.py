#!/usr/bin/env python3
"""
NanoBK DNS Apply Safe Integration Mock — Fake-only test prototype.

Hidden/test-only prototype connecting the v2.2.15 fake helper boundary to the
v2.2.16 beginner-safe renderer. Validates fake transport, invokes helper via
boundary mock, parses final helper JSON, and renders safe output.

NOT imported by bin/nanobk. NOT a user-facing command. NOT real DNS apply.
Requires NANOBK_CF_DNS_FAKE_TRANSPORT. Fails closed if missing.
Never calls Cloudflare. Never performs real DNS mutation.

Usage:
    NANOBK_CF_DNS_FAKE_TRANSPORT=/path/to/fixture.json \
      python3 lib/nanobk_cf_dns_apply_safe_integration_mock.py
"""

from __future__ import annotations

import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

# Reuse boundary mock functions
from nanobk_cf_dns_apply_helper_boundary_mock import (
    validate_fake_transport,
    create_temp_fixtures,
    run_helper,
    parse_helper_json,
    validate_helper_schema,
    check_calls_artifact,
)

# Reuse safe renderer
from nanobk_cf_dns_apply_safe_renderer import (
    render_from_helper_json,
    UnsafeOutputError,
)

# ── Constants ────────────────────────────────────────────────────────────────

_INTEGRATION_SAFE_ERROR_MSG = (
    "NanoBK DNS Apply safe integration mock is fake-only.\n"
    "A valid fake transport and safe renderer output are required.\n"
    "No DNS changes were made."
)

# ── Integration-level forbidden output scan ──────────────────────────────────

_INTEGRATION_FORBIDDEN_PATTERNS: list[re.Pattern] = [
    re.compile(r"example\.com", re.IGNORECASE),
    re.compile(r"node\.example\.com", re.IGNORECASE),
    re.compile(r"proxy\.example\.com", re.IGNORECASE),
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


def _assert_integration_safe(text: str) -> bool:
    """Run integration-level forbidden output scan.

    Returns True if safe, False if any forbidden pattern found.
    Does not print the unsafe output.
    """
    for pattern in _INTEGRATION_FORBIDDEN_PATTERNS:
        if pattern.search(text):
            return False
    return True


# ── Main integration function ────────────────────────────────────────────────

def render_fake_helper_to_safe_summary() -> str:
    """Connect fake helper boundary output to beginner-safe renderer.

    Flow:
    1. Validate fake transport via boundary preflight.
    2. Create temp fake profile/api-env.
    3. Add _calls_file to temp fake transport copy.
    4. Invoke helper via boundary run_helper.
    5. Capture stdout/stderr internally.
    6. Fail closed on timeout, stderr, parse, schema, calls artifact,
       or unsafe output.  A nonzero helper exit is allowed only when
       stdout contains valid helper JSON that passes schema validation
       and fake calls artifact proof (e.g. conflict/partial scenarios).
    7. Parse final helper JSON.
    8. Validate helper schema.
    9. Check calls artifact proof.
    10. Pass parsed helper JSON to safe renderer.
    11. Append safe fake transport proof wording.
    12. Run integration-level forbidden output scan.
    13. Return safe output only.

    Raises RuntimeError on any failure (safe generic message only).
    """
    # 1. Validate fake transport
    fake_transport = validate_fake_transport()
    if fake_transport is None:
        raise RuntimeError(_INTEGRATION_SAFE_ERROR_MSG)

    # Find repo root
    repo_root = Path(__file__).resolve().parents[1]

    # 2-3. Create temp fixtures and calls file
    tmpdir = Path(tempfile.mkdtemp(prefix="nanobk-safe-integration-"))
    try:
        profile_path, api_env_path = create_temp_fixtures(tmpdir)

        # Add calls artifact to a copy of the fake transport
        calls_file = tmpdir / "fake-calls.json"
        try:
            with open(fake_transport, "r", encoding="utf-8") as f:
                transport_data = json.load(f)
            transport_data["_calls_file"] = str(calls_file)
            transport_with_calls = tmpdir / "transport-with-calls.json"
            with open(transport_with_calls, "w", encoding="utf-8") as f:
                json.dump(transport_data, f)
        except (json.JSONDecodeError, OSError):
            raise RuntimeError(_INTEGRATION_SAFE_ERROR_MSG)

        # 4. Invoke helper via boundary run_helper
        returncode, stdout, stderr = run_helper(
            repo_root, profile_path, api_env_path, transport_with_calls, tmpdir
        )

        # 5-6. Fail closed checks
        # Timeout always fails closed.
        # A nonzero helper exit is allowed only when stdout contains valid
        # helper JSON that passes schema validation and calls artifact proof
        # (conflict/partial scenarios return nonzero by design).
        if returncode == -1:
            raise RuntimeError(_INTEGRATION_SAFE_ERROR_MSG)

        # Strict stderr gate
        if stderr.strip():
            raise RuntimeError(_INTEGRATION_SAFE_ERROR_MSG)

        # 7. Parse final helper JSON
        helper_json = parse_helper_json(stdout)
        if helper_json is None:
            raise RuntimeError(_INTEGRATION_SAFE_ERROR_MSG)

        # 8. Validate helper schema
        if not validate_helper_schema(helper_json):
            raise RuntimeError(_INTEGRATION_SAFE_ERROR_MSG)

        # 9. Check calls artifact proof
        if not check_calls_artifact(transport_with_calls):
            raise RuntimeError(_INTEGRATION_SAFE_ERROR_MSG)

        # 10. Pass to safe renderer
        try:
            safe_output = render_from_helper_json(helper_json, mode="fake_only")
        except UnsafeOutputError:
            raise RuntimeError(_INTEGRATION_SAFE_ERROR_MSG)

        # 11. Append safe fake transport proof wording
        # (no calls file path, no raw transport path, no raw JSON,
        #  no method names/endpoints/record IDs)
        safe_output = safe_output.rstrip() + "\n\nFake transport:\n  Used: yes\n"

        # 12. Integration-level forbidden output scan
        if not _assert_integration_safe(safe_output):
            raise RuntimeError(_INTEGRATION_SAFE_ERROR_MSG)

        # 13. Return safe output
        return safe_output

    finally:
        # Cleanup temp dir
        shutil.rmtree(tmpdir, ignore_errors=True)


# ── CLI entry point (test-only) ──────────────────────────────────────────────

def main() -> int:
    """Run integration mock and print safe output. Hidden/test-only."""
    try:
        output = render_fake_helper_to_safe_summary()
        print(output, end="")
        return 0
    except RuntimeError:
        print(_INTEGRATION_SAFE_ERROR_MSG, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
