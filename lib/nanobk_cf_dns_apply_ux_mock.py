#!/usr/bin/env python3
"""
NanoBK DNS Apply UX Mock — Fake-transport-only test helper.

Hidden/test-only UX wrapper that validates beginner-safe DNS apply output,
redaction, confirmation, post-check, and partial/failure states.

NOT imported by bin/nanobk. NOT public CLI. NOT real DNS apply.
Requires NANOBK_CF_DNS_FAKE_TRANSPORT. Fails closed if missing.
Never calls Cloudflare. Never performs real DNS mutation.

Usage:
    NANOBK_CF_DNS_FAKE_TRANSPORT=/path/to/fixture.json \
      python3 lib/nanobk_cf_dns_apply_ux_mock.py --scenario summary

Scenarios:
    summary             Render beginner Summary only (no mutation)
    success             Simulate applied state (requires confirm phrase)
    postcheck-failure   Simulate post-check failure (requires confirm phrase)
    partial-failure     Simulate partial failure (requires confirm phrase)
    missing-confirmation  Show confirmation instructions (no apply)
    bad-confirmation    Wrong phrase, fail closed
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys

# ── Constants ────────────────────────────────────────────────────────────────

REQUIRED_CONFIRM_PHRASE = "apply dns records"

MASKED_DOMAIN = "ex***e.com"
MASKED_HOSTNAME = "pr***y.ex***e.com"
MASKED_IPV4 = "203.0.113.xxx"
MASKED_IPV6 = "2001:db8:…"

FAKE_TRANSPORT_ENV = "NANOBK_CF_DNS_FAKE_TRANSPORT"


# ── Fake transport guard ─────────────────────────────────────────────────────

_SAFE_ERROR_MSG = (
    "NanoBK DNS Apply UX mock is fake-transport-only.\n"
    "A valid local fake transport fixture is required.\n"
    "No DNS changes were made."
)


def check_fake_transport() -> bool:
    """Validate fake transport env var and fixture file. Returns True if safe.

    Requirements:
    1. NANOBK_CF_DNS_FAKE_TRANSPORT is set and non-empty.
    2. Path exists.
    3. Path is a regular file (not a directory).
    4. Path content is valid JSON.

    Error messages are safe: no raw path, no JSON content, no env values.
    """
    val = os.environ.get(FAKE_TRANSPORT_ENV, "")
    if not val:
        print(_SAFE_ERROR_MSG, file=sys.stderr)
        return False

    path = Path(val)

    if not path.exists():
        print(_SAFE_ERROR_MSG, file=sys.stderr)
        return False

    if not path.is_file():
        print(_SAFE_ERROR_MSG, file=sys.stderr)
        return False

    try:
        with open(path, "r", encoding="utf-8") as f:
            json.load(f)
    except (json.JSONDecodeError, OSError):
        print(_SAFE_ERROR_MSG, file=sys.stderr)
        return False

    return True


# ── Confirmation guard ───────────────────────────────────────────────────────

def check_confirmation(provided: str | None) -> bool:
    """Check that the required confirmation phrase was provided."""
    if not provided:
        return False
    return provided.strip().lower() == REQUIRED_CONFIRM_PHRASE


# ── Output renderers ─────────────────────────────────────────────────────────

def render_summary() -> str:
    """Render beginner Summary (no mutation)."""
    return (
        "NanoBK DNS Apply — Summary\n"
        "Status: ready for confirmation\n"
        "\n"
        "Planned changes:\n"
        "  Create: 1\n"
        "  Update: 1\n"
        "  No change: 0\n"
        "  Conflict: 0\n"
        "\n"
        "Target:\n"
        f"  Domain: {MASKED_DOMAIN}\n"
        f"  Hostname: {MASKED_HOSTNAME}\n"
        f"  IPv4: {MASKED_IPV4}\n"
        f"  IPv6: {MASKED_IPV6}\n"
        "\n"
        "What will happen:\n"
        "  NanoBK will create or update DNS records after confirmation.\n"
        "\n"
        "What will NOT happen:\n"
        "  No records will be deleted.\n"
        "  No unowned records will be overwritten.\n"
        "  No proxied records will be converted.\n"
        "  No Cloudflare Tunnel, Access, DNS-01, certificate, Worker, Bot, or Web Panel settings will be changed.\n"
        "\n"
        "Cloudflare DNS will be changed only after confirmation.\n"
    )


def render_confirmation() -> str:
    """Render confirmation instructions."""
    return (
        "Apply DNS records?\n"
        "  1) Apply now\n"
        "  2) Review summary again\n"
        "  3) Cancel\n"
        "\n"
        "To continue, type exactly:\n"
        f"  {REQUIRED_CONFIRM_PHRASE}\n"
    )


def render_success() -> str:
    """Render applied state (simulated post-check)."""
    return (
        "NanoBK DNS Apply — Final Summary\n"
        "Status: applied\n"
        "\n"
        "Changes:\n"
        "  Created: 1\n"
        "  Updated: 1\n"
        "  No change: 0\n"
        "  Failed: 0\n"
        "\n"
        "Post-check:\n"
        "  A record: verified\n"
        "  AAAA record: verified\n"
        "  Proxied mode: DNS-only verified\n"
        "  Ownership marker: verified\n"
        "\n"
        "Simulated DNS create/update flow completed under fake transport.\n"
        "No records were deleted.\n"
        "\n"
        "Test mode: fake transport only.\n"
        "No live Cloudflare verification was performed.\n"
    )


def render_postcheck_failure() -> str:
    """Render post-check failure state (simulated)."""
    return (
        "NanoBK DNS Apply — Final Summary\n"
        "Status: uncertain\n"
        "\n"
        "Changes:\n"
        "  Created: 1\n"
        "  Updated: 1\n"
        "  No change: 0\n"
        "  Failed: 0\n"
        "\n"
        "Post-check:\n"
        "  A record: verified\n"
        "  AAAA record: mismatch\n"
        "  Proxied mode: needs review\n"
        "  Ownership marker: needs review\n"
        "\n"
        "Post-check did not verify the final state.\n"
        "This is not reported as success.\n"
        "\n"
        "Test mode: fake transport only.\n"
        "This is simulated post-check output, not live Cloudflare verification.\n"
        "\n"
        "Recovery:\n"
        "  Do not retry blindly.\n"
        "  Review the current DNS records in Cloudflare.\n"
        "  Run a read-only check before any next action.\n"
    )


def render_partial_failure() -> str:
    """Render partial failure state (simulated)."""
    return (
        "NanoBK DNS Apply — Final Summary\n"
        "Status: partial\n"
        "\n"
        "Changes:\n"
        "  Created: 1\n"
        "  Updated: 0\n"
        "  No change: 0\n"
        "  Failed: 1\n"
        "\n"
        "Post-check:\n"
        "  Some records could not be verified.\n"
        "\n"
        "This is not reported as success.\n"
        "\n"
        "Test mode: fake transport only.\n"
        "This is simulated partial failure output, not live Cloudflare verification.\n"
        "\n"
        "Recovery:\n"
        "  Do not retry blindly.\n"
        "  Review Cloudflare DNS manually.\n"
        "  Run a read-only check before any next action.\n"
    )


# ── Scenario handlers ────────────────────────────────────────────────────────

def handle_summary(_phrase: str | None = None) -> int:
    """Handle summary scenario (no confirmation needed)."""
    print(render_summary())
    return 0


def handle_missing_confirmation(_phrase: str | None = None) -> int:
    """Handle missing confirmation scenario."""
    print(render_confirmation())
    print("\nConfirmation required. No DNS changes were made.")
    return 1


def handle_bad_confirmation(phrase: str | None) -> int:
    """Handle bad confirmation scenario."""
    print(render_confirmation())
    print("\nConfirmation phrase did not match. No DNS changes were made.")
    return 1


def handle_success(phrase: str | None) -> int:
    """Handle success scenario (requires confirmation)."""
    if not check_confirmation(phrase):
        print(render_confirmation())
        print("\nConfirmation required. No DNS changes were made.")
        return 1
    print(render_success())
    return 0


def handle_postcheck_failure(phrase: str | None) -> int:
    """Handle post-check failure scenario (requires confirmation)."""
    if not check_confirmation(phrase):
        print(render_confirmation())
        print("\nConfirmation required. No DNS changes were made.")
        return 1
    print(render_postcheck_failure())
    return 0


def handle_partial_failure(phrase: str | None) -> int:
    """Handle partial failure scenario (requires confirmation)."""
    if not check_confirmation(phrase):
        print(render_confirmation())
        print("\nConfirmation required. No DNS changes were made.")
        return 1
    print(render_partial_failure())
    return 0


# ── Main ─────────────────────────────────────────────────────────────────────

SCENARIOS = {
    "summary": handle_summary,
    "success": handle_success,
    "postcheck-failure": handle_postcheck_failure,
    "partial-failure": handle_partial_failure,
    "missing-confirmation": handle_missing_confirmation,
    "bad-confirmation": handle_bad_confirmation,
}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="NanoBK DNS Apply UX Mock (fake-transport-only, test helper)"
    )
    parser.add_argument(
        "--scenario",
        required=True,
        choices=list(SCENARIOS.keys()),
        help="Scenario to simulate",
    )
    parser.add_argument(
        "--confirm-phrase",
        default=None,
        help="Confirmation phrase (required for success/postcheck-failure/partial-failure)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Reserved for future use",
    )
    args = parser.parse_args()

    # Fake transport guard — fail closed if missing
    if not check_fake_transport():
        return 1

    # Dispatch scenario
    handler = SCENARIOS[args.scenario]
    return handler(args.confirm_phrase)


if __name__ == "__main__":
    sys.exit(main())
