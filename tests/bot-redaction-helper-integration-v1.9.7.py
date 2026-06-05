#!/usr/bin/env python3
"""
NanoBK Proxy Suite — Bot Redaction Helper Integration Test (v1.9.7)

Verifies that bot/nanobk_bot.py correctly delegates to the shared redaction
helper from lib/nanobk_redaction.py. Tests the shared helper behavior that
Bot now uses, plus verifies Bot source code delegation.

All test values are fake and documentation-safe (RFC 5737/3849/2606).

Usage:
    python3 tests/bot-redaction-helper-integration-v1.9.7.py
"""

import os
import sys

# Ensure repo root is on path
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO_DIR)

# ── Test infrastructure ─────────────────────────────────────────────────────

PASSED = 0
FAILED = 0


def check(desc: str, ok: bool) -> None:
    global PASSED, FAILED
    if ok:
        print(f"  \033[32m✓\033[0m {desc}")
        PASSED += 1
    else:
        print(f"  \033[31m✗\033[0m {desc}")
        FAILED += 1


# ── Import shared helper ────────────────────────────────────────────────────

from lib.nanobk_redaction import (
    strip_ansi,
    redact_text,
    redact_json_text,
    REDACTED_IPV4,
    REDACTED_IPV6,
    REDACTED_DOMAIN,
    REDACTED_URL,
    REDACTED_WORKERS_DEV,
    REDACTED_SUBSCRIPTION_PATH,
    REDACTED,
)


def limit_text(text: str, max_len: int = 3500) -> str:
    """Truncate text to Telegram message limits (matches Bot behavior)."""
    if len(text) <= max_len:
        return text
    return text[:max_len] + "\n... [truncated]"


def safe_output(text: str) -> str:
    """Strip ANSI, apply redaction, and limit length (matches Bot behavior)."""
    text = strip_ansi(text)
    text = redact_text(text)
    return limit_text(text)


def format_status(data: dict) -> str:
    """Format nanobk --json status into a readable summary (matches Bot behavior)."""
    lines = ["NanoBK Status", ""]

    lines.append(f"OK: {data.get('ok', False)}")
    lines.append(f"Domain: {data.get('domain', '<not set>')}")
    lines.append(f"VPS IP: {data.get('vpsIp', '<not set>')}")
    lines.append(f"Geo: {data.get('geo', '<not set>')}")

    services = data.get("services", {})
    if services:
        lines.append("Services:")
        for name in ("hy2", "tuic", "reality", "trojan"):
            lines.append(f"  - {name.upper()}: {services.get(name, 'unknown')}")

    security = data.get("security", {})
    if security:
        lines.append("Security:")
        lines.append(f"  - secrets mode: {security.get('secretsMode', 'unknown')}")

    cf = data.get("cloudflare", {})
    nanok = cf.get("nanok", {})
    nanob = cf.get("nanob", {})
    lines.append("Cloudflare:")
    lines.append(f"  - nanok: {'configured' if nanok.get('envExists') else 'missing'}")
    lines.append(f"  - nanob: {'configured' if nanob.get('envExists') else 'missing'}")

    warnings = data.get("warnings", [])
    if warnings:
        lines.append("Warnings:")
        for w in warnings:
            lines.append(f"  - {w}")

    return "\n".join(lines)


# ── Verify Bot source delegates to shared helper ───────────────────────────

def test_bot_source_delegation() -> None:
    print("\n--- Bot source delegation verification ---\n")

    bot_src_path = os.path.join(REPO_DIR, "bot", "nanobk_bot.py")
    with open(bot_src_path) as f:
        bot_src = f.read()

    check("Bot imports from lib.nanobk_redaction",
          "from lib.nanobk_redaction import" in bot_src)
    check("Bot imports shared_strip_ansi",
          "strip_ansi as _shared_strip_ansi" in bot_src)
    check("Bot imports shared_redact_text",
          "redact_text as _shared_redact_text" in bot_src)
    check("Bot strip_ansi delegates to shared",
          "return _shared_strip_ansi(text)" in bot_src)
    check("Bot redact_text delegates to shared",
          "return _shared_redact_text(text)" in bot_src)
    check("Bot does NOT have local _REDACT_PATTERNS",
          "_REDACT_PATTERNS" not in bot_src)
    check("Bot does NOT have local _ANSI_RE",
          "_ANSI_RE" not in bot_src)
    check("Bot computes _REPO_ROOT for import",
          "_REPO_ROOT" in bot_src)


# ── Tests using shared helper (same as Bot now uses) ────────────────────────

def test_strip_ansi() -> None:
    print("\n--- strip_ansi tests ---\n")

    check("Strip simple ANSI",
          strip_ansi("\x1b[0;34mINFO\x1b[0m") == "INFO")
    check("Strip ANSI with codes",
          strip_ansi("\x1b[1;33mWARN\x1b[0m") == "WARN")
    check("No ANSI in plain text",
          strip_ansi("hello") == "hello")
    check("Empty string",
          strip_ansi("") == "")


def test_redact_text_token_secret() -> None:
    print("\n--- redact_text token/secret tests ---\n")

    check("Redacts Telegram bot token",
          "ABCdefGHI" not in redact_text("Token is 123456789:ABCdefGHIjklMNOpqrsTUVwxyz012345"))
    check("Redacts password=value",
          "SuperSecret123" not in redact_text("password=SuperSecret123"))
    check("Redacts PrivateKey=value",
          "aBcDeFgHiJkLmNoPq" not in redact_text("PrivateKey: aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"))
    check("Redacts secret=value",
          "my-secret-val" not in redact_text("secret=my-secret-val"))
    check("Redacts token=value",
          "my-token-val" not in redact_text("token=my-token-val"))
    check("Redacts admin_token=value",
          "admin-val" not in redact_text("admin_token=admin-val"))


def test_redact_text_address_class() -> None:
    print("\n--- redact_text address-class tests ---\n")

    check("Redacts IPv4",
          "203.0.113.10" not in redact_text("VPS: 203.0.113.10"))
    check("Redacts IPv6",
          "2001:db8::10" not in redact_text("IPv6: 2001:db8::10"))
    check("Redacts domain",
          "node.example.invalid" not in redact_text("Domain: node.example.invalid"))
    check("Redacts URL",
          "https://worker.example.invalid" not in redact_text("URL: https://worker.example.invalid/sub/path"))
    check("Redacts workers.dev",
          "nanobk-test.example.invalid.workers.dev" not in redact_text("workers.dev: nanobk-test.example.invalid.workers.dev"))
    check("Redacts subscription path",
          "fake-sub-path-12345" not in redact_text("Path: /sub/fake-sub-path-12345"))
    check("Redacts fake token in text",
          "fake-doc-token-abc123xyz" not in redact_text("token=fake-doc-token-abc123xyz"))
    check("Redacts fake secret in text",
          "fake-secret-value" not in redact_text("secret=fake-secret-value"))


def test_redact_text_preserves_safe() -> None:
    print("\n--- redact_text preserves safe content ---\n")

    check("Preserves 'NanoBK Status'",
          "NanoBK Status" in redact_text("NanoBK Status"))
    check("Preserves 'Region: JP'",
          "Region: JP" in redact_text("Region: JP"))
    check("Preserves 'active'",
          "active" in redact_text("HY2: active"))
    check("Preserves '600'",
          "600" in redact_text("secrets mode: 600"))
    check("Preserves 'configured'",
          "configured" in redact_text("nanok: configured"))
    check("Preserves port numbers",
          "443" in redact_text("HY2: active on port 443"))
    check("Preserves /etc/nanobk/profile.current.json",
          "/etc/nanobk/profile.current.json" in redact_text("/etc/nanobk/profile.current.json"))


def test_safe_output_integration() -> None:
    print("\n--- safe_output integration tests ---\n")

    test = "\x1b[0;32mVPS: 203.0.113.10 (node.example.invalid)\x1b[0m"
    result = safe_output(test)

    check("safe_output strips ANSI",
          "\x1b[" not in result)
    check("safe_output redacts IPv4",
          "203.0.113.10" not in result)
    check("safe_output redacts domain",
          "node.example.invalid" not in result)

    comprehensive = (
        "IPv6: 2001:db8::10\n"
        "URL: https://worker.example.invalid/sub/REDACTED_EXAMPLE\n"
        "workers.dev: nanobk-test.example.invalid.workers.dev\n"
        "Path: /sub/fake-sub-path-12345\n"
        "token=fake-doc-token-abc123xyz\n"
        "secret=fake-secret-value-do-not-use\n"
        "PrivateKey=FAKE_PRIVATE_KEY_DO_NOT_USE_abc123def456\n"
        "admin_token=fake-cf-admin-token-do-not-use"
    )
    safe = safe_output(comprehensive)

    check("Comprehensive: no raw IPv6",
          "2001:db8::10" not in safe)
    check("Comprehensive: no raw URL",
          "https://worker.example.invalid" not in safe)
    check("Comprehensive: no raw workers.dev",
          "nanobk-test.example.invalid.workers.dev" not in safe)
    check("Comprehensive: no raw subscription path",
          "fake-sub-path-12345" not in safe)
    check("Comprehensive: no raw token",
          "fake-doc-token-abc123xyz" not in safe)
    check("Comprehensive: no raw secret",
          "fake-secret-value-do-not-use" not in safe)
    check("Comprehensive: no raw private key",
          "FAKE_PRIVATE_KEY_DO_NOT_USE" not in safe)
    check("Comprehensive: no raw admin token",
          "fake-cf-admin-token-do-not-use" not in safe)


def test_format_status_safe_output() -> None:
    print("\n--- format_status + safe_output tests ---\n")

    test_status = {
        "ok": True,
        "domain": "node.example.invalid",
        "vpsIp": "203.0.113.10",
        "geo": "JP",
        "services": {
            "hy2": "active", "tuic": "active",
            "reality": "active", "trojan": "active"
        },
        "security": {"secretsMode": "600"},
        "cloudflare": {
            "nanok": {"envExists": True},
            "nanob": {"envExists": False}
        },
        "warnings": []
    }

    formatted = format_status(test_status)
    safe = safe_output(formatted)

    check("format_status+safe: no raw domain",
          "node.example.invalid" not in safe)
    check("format_status+safe: no raw IPv4",
          "203.0.113.10" not in safe)
    check("format_status+safe: preserves 'active'",
          "active" in safe)
    check("format_status+safe: preserves 'JP'",
          "JP" in safe)
    check("format_status+safe: preserves '600'",
          "600" in safe)
    check("format_status+safe: preserves 'configured'",
          "configured" in safe)
    check("format_status+safe: preserves 'NanoBK Status'",
          "NanoBK Status" in safe)


def test_limit_text() -> None:
    print("\n--- limit_text tests ---\n")

    long_text = "x" * 5000
    truncated = limit_text(long_text, max_len=100)
    check("limit_text truncates long text",
          len(truncated) < len(long_text))
    check("limit_text adds marker",
          "[truncated]" in truncated)
    check("limit_text preserves short text",
          limit_text("hello") == "hello")


def test_idempotency() -> None:
    print("\n--- idempotency tests ---\n")

    test = "VPS: 203.0.113.10 (node.example.invalid) IPv6: 2001:db8::10"
    once = safe_output(test)
    twice = safe_output(once)
    check("safe_output is idempotent",
          once == twice)
    check("Idempotent output has no raw IPv4",
          "203.0.113.10" not in twice)
    check("Idempotent output has no raw domain",
          "node.example.invalid" not in twice)


# ── Main ────────────────────────────────────────────────────────────────────

def main() -> int:
    print("")
    print("=== NanoBK Bot Redaction Helper Integration Test (v1.9.7) ===")
    print("")
    print("Purpose: Verify Bot uses shared redaction helper correctly.")
    print("Scope:   Bot integration test. Fake values only.")
    print("")

    test_bot_source_delegation()
    test_strip_ansi()
    test_redact_text_token_secret()
    test_redact_text_address_class()
    test_redact_text_preserves_safe()
    test_safe_output_integration()
    test_format_status_safe_output()
    test_limit_text()
    test_idempotency()

    print("")
    print("=== Test Summary ===")
    print("")
    print(f"  \033[32m{PASSED} passed\033[0m, \033[31m{FAILED} failed\033[0m")
    print("")

    if FAILED == 0:
        print("  \033[32mAll Bot redaction integration tests passed!\033[0m")
        print("")
        print("  Bot correctly delegates to shared redaction helper.")
        print("  Address-class values are redacted from Bot outputs.")
        return 0
    else:
        print(f"  \033[31m{FAILED} test(s) failed.\033[0m")
        print("")
        print("  Review failures above.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
