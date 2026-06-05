#!/usr/bin/env python3
"""
NanoBK Proxy Suite — Redaction Integration Checkpoint Test (v1.9.9)

Verifies Bot and Web redaction behavior is consistent against the shared helper.
Uses fake documentation-safe values only (RFC 5737/3849/2606).

Usage:
    python3 tests/redaction-integration-checkpoint-v1.9.9.py
"""

import json
import os
import sys

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
    strip_ansi as shared_strip_ansi,
    redact_text as shared_redact_text,
    redact_json_obj as shared_redact_json_obj,
    REDACTED_IPV4,
    REDACTED_IPV6,
    REDACTED_DOMAIN,
    REDACTED_URL,
    REDACTED_WORKERS_DEV,
    REDACTED_SUBSCRIPTION_PATH,
    REDACTED,
)

# ── Bot helper functions (replicate bot behavior) ───────────────────────────

def bot_limit_text(text: str, max_len: int = 3500) -> str:
    if len(text) <= max_len:
        return text
    return text[:max_len] + "\n... [truncated]"

def bot_safe_output(text: str) -> str:
    text = shared_strip_ansi(text)
    text = shared_redact_text(text)
    return bot_limit_text(text)

def bot_format_status(data: dict) -> str:
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

# ── Web helper functions (replicate web behavior) ───────────────────────────

def web_limit_text(text: str, max_len: int = 12000) -> str:
    if len(text) <= max_len:
        return text
    return text[:max_len] + "\n... [truncated]"

def web_safe_output(text: str) -> str:
    text = shared_strip_ansi(text)
    text = shared_redact_text(text)
    return web_limit_text(text)

def web_redact_json(value):
    return shared_redact_json_obj(value)

def web_format_status(data: dict) -> dict:
    redacted = web_redact_json(data)
    return {
        "ok": redacted.get("ok", False),
        "domain": redacted.get("domain", "<not set>"),
        "vps_ip": redacted.get("vpsIp", "<not set>"),
        "geo": redacted.get("geo", "<not set>"),
        "services": redacted.get("services", {}),
        "security": redacted.get("security", {}),
        "cloudflare": redacted.get("cloudflare", {}),
        "warnings": redacted.get("warnings", []),
        "raw_json": json.dumps(redacted, indent=2),
    }


# ── Fake test data ──────────────────────────────────────────────────────────

FAKE_IPV4 = "203.0.113.10"
FAKE_IPV6 = "2001:db8::10"
FAKE_DOMAIN = "node.example.invalid"
FAKE_URL = "https://worker.example.invalid/sub/REDACTED_EXAMPLE"
FAKE_WORKERS_DEV = "nanobk-test.example.invalid.workers.dev"
FAKE_SUB_PATH = "/sub/fake-sub-path-12345"
FAKE_TOKEN = "fake-doc-token-abc123xyz"
FAKE_SECRET = "fake-secret-value-do-not-use"
FAKE_PRIVATE_KEY = "FAKE_PRIVATE_KEY_DO_NOT_USE_abc123def456"
FAKE_ADMIN_TOKEN = "fake-cf-admin-token-do-not-use"

COMPREHENSIVE_TEXT = (
    f"VPS: {FAKE_IPV4} ({FAKE_DOMAIN})\n"
    f"IPv6: {FAKE_IPV6}\n"
    f"URL: {FAKE_URL}\n"
    f"workers.dev: {FAKE_WORKERS_DEV}\n"
    f"Path: {FAKE_SUB_PATH}\n"
    f"token={FAKE_TOKEN}\n"
    f"secret={FAKE_SECRET}\n"
    f"PrivateKey={FAKE_PRIVATE_KEY}\n"
    f"admin_token={FAKE_ADMIN_TOKEN}"
)

STATUS_DICT = {
    "ok": True,
    "domain": FAKE_DOMAIN,
    "vpsIp": FAKE_IPV4,
    "geo": "JP",
    "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
    "security": {"secretsMode": "600", "token": FAKE_TOKEN, "privateKey": FAKE_PRIVATE_KEY},
    "cloudflare": {
        "nanok": {"envExists": True, "route": FAKE_URL, "workersDev": FAKE_WORKERS_DEV},
        "nanob": {"envExists": False},
        "adminToken": FAKE_ADMIN_TOKEN,
    },
    "subscription": {"url": f"https://{FAKE_DOMAIN}{FAKE_SUB_PATH}", "path": FAKE_SUB_PATH, "configured": True},
    "profile": {"domain": FAKE_DOMAIN, "vpsIp": FAKE_IPV4, "ipv6": FAKE_IPV6},
    "warnings": ["Service hy2 may need restart"],
}


# ── Tests ───────────────────────────────────────────────────────────────────

def test_source_delegation() -> None:
    print("\n--- Source delegation verification ---\n")

    bot_src = open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")).read()
    web_src = open(os.path.join(REPO_DIR, "web", "app.py")).read()

    # Both import shared helper
    check("Bot imports lib.nanobk_redaction", "from lib.nanobk_redaction import" in bot_src)
    check("Web imports lib.nanobk_redaction", "from lib.nanobk_redaction import" in web_src)

    # Neither has old local patterns
    check("Bot has no _REDACT_PATTERNS", "_REDACT_PATTERNS" not in bot_src)
    check("Web has no _REDACT_PATTERNS", "_REDACT_PATTERNS" not in web_src)
    check("Bot has no _ANSI_RE", "_ANSI_RE" not in bot_src)
    check("Web has no _ANSI_RE", "_ANSI_RE" not in web_src)
    check("Bot has no _SENSITIVE_KEY_SUBSTRINGS", "_SENSITIVE_KEY_SUBSTRINGS" not in bot_src)
    check("Web has no _SENSITIVE_KEY_SUBSTRINGS", "_SENSITIVE_KEY_SUBSTRINGS" not in web_src)

    # Both delegate
    check("Bot strip_ansi delegates", "return _shared_strip_ansi(text)" in bot_src)
    check("Web strip_ansi delegates", "return _shared_strip_ansi(text)" in web_src)
    check("Bot redact_text delegates", "return _shared_redact_text(text)" in bot_src)
    check("Web redact_text delegates", "return _shared_redact_text(text)" in web_src)
    check("Web redact_json delegates", "return _shared_redact_json_obj(value)" in web_src)

    # No shell=True
    check("Bot has no shell=True", "shell=True" not in bot_src)
    check("Web has no shell=True", "shell=True" not in web_src)


def test_consistency_address_class() -> None:
    print("\n--- Bot/Web address-class consistency ---\n")

    # Both produce same redacted output for same text
    bot_out = bot_safe_output(COMPREHENSIVE_TEXT)
    web_out = web_safe_output(COMPREHENSIVE_TEXT)

    check("Bot and Web safe_output identical on same input", bot_out == web_out)

    # Verify raw values removed by both
    for label, value in [
        ("IPv4", FAKE_IPV4),
        ("IPv6", FAKE_IPV6),
        ("domain", FAKE_DOMAIN),
        ("URL prefix", "https://worker.example.invalid"),
        ("workers.dev", FAKE_WORKERS_DEV),
        ("subscription path", "fake-sub-path-12345"),
        ("token", FAKE_TOKEN),
        ("secret", FAKE_SECRET),
        ("private key", FAKE_PRIVATE_KEY),
        ("admin token", FAKE_ADMIN_TOKEN),
    ]:
        check(f"Bot safe_output removes {label}", value not in bot_out)
        check(f"Web safe_output removes {label}", value not in web_out)


def test_consistency_preserves_safe() -> None:
    print("\n--- Bot/Web preserve safe status words ---\n")

    safe_text = "HY2: active TUIC: active Region: JP secrets mode: 600 configured missing unknown"
    bot_out = bot_safe_output(safe_text)
    web_out = web_safe_output(safe_text)

    for word in ["active", "JP", "600", "configured", "missing", "unknown"]:
        check(f"Bot preserves '{word}'", word in bot_out)
        check(f"Web preserves '{word}'", word in web_out)


def test_json_redaction_consistency() -> None:
    print("\n--- JSON redaction consistency ---\n")

    web_json = web_redact_json(STATUS_DICT)
    shared_json = shared_redact_json_obj(STATUS_DICT)

    check("Web redact_json == shared redact_json_obj", web_json == shared_json)

    web_text = json.dumps(web_json, indent=2)
    shared_text = json.dumps(shared_json, indent=2)

    for label, value in [
        ("domain", FAKE_DOMAIN),
        ("IPv4", FAKE_IPV4),
        ("IPv6", FAKE_IPV6),
        ("URL", "https://worker.example.invalid"),
        ("workers.dev", FAKE_WORKERS_DEV),
        ("subscription path", "fake-sub-path-12345"),
        ("token value", FAKE_TOKEN),
        ("secret value", FAKE_SECRET),
        ("private key", FAKE_PRIVATE_KEY),
        ("admin token", FAKE_ADMIN_TOKEN),
    ]:
        check(f"JSON redaction removes {label} (web)", value not in web_text)
        check(f"JSON redaction removes {label} (shared)", value not in shared_text)

    # Preserves safe values
    check("JSON preserves ok=true", web_json.get("ok") is True)
    check("JSON preserves geo", web_json.get("geo") == "JP")
    check("JSON preserves services", web_json.get("services", {}).get("hy2") == "active")
    check("JSON preserves secretsMode", web_json.get("security", {}).get("secretsMode") == "600")
    check("JSON preserves envExists", web_json.get("cloudflare", {}).get("nanok", {}).get("envExists") is True)
    check("JSON preserves configured", web_json.get("subscription", {}).get("configured") is True)


def test_format_status_no_leak() -> None:
    print("\n--- format_status no raw leak ---\n")

    # Bot format_status + safe_output
    bot_formatted = bot_format_status(STATUS_DICT)
    bot_safe = bot_safe_output(bot_formatted)

    check("Bot format_status+safe: no raw domain", FAKE_DOMAIN not in bot_safe)
    check("Bot format_status+safe: no raw IPv4", FAKE_IPV4 not in bot_safe)
    check("Bot format_status+safe: preserves 'active'", "active" in bot_safe)
    check("Bot format_status+safe: preserves 'JP'", "JP" in bot_safe)
    check("Bot format_status+safe: preserves '600'", "600" in bot_safe)

    # Web format_status
    web_formatted = web_format_status(STATUS_DICT)

    check("Web format_status: domain redacted", web_formatted["domain"] != FAKE_DOMAIN)
    check("Web format_status: vps_ip redacted", web_formatted["vps_ip"] != FAKE_IPV4)
    check("Web format_status: raw_json no domain", FAKE_DOMAIN not in web_formatted["raw_json"])
    check("Web format_status: raw_json no IPv4", FAKE_IPV4 not in web_formatted["raw_json"])
    check("Web format_status: preserves services", web_formatted["services"].get("hy2") == "active")
    check("Web format_status: preserves geo", web_formatted["geo"] == "JP")
    check("Web format_status: preserves secretsMode", web_formatted["security"].get("secretsMode") == "600")


def test_idempotency() -> None:
    print("\n--- Idempotency ---\n")

    bot_once = bot_safe_output(COMPREHENSIVE_TEXT)
    bot_twice = bot_safe_output(bot_once)
    check("Bot safe_output idempotent", bot_once == bot_twice)

    web_once = web_safe_output(COMPREHENSIVE_TEXT)
    web_twice = web_safe_output(web_once)
    check("Web safe_output idempotent", web_once == web_twice)

    check("Bot == Web on idempotent output", bot_twice == web_twice)

    json_once = shared_redact_json_obj(STATUS_DICT)
    json_twice = shared_redact_json_obj(json_once)
    check("JSON redact idempotent", json_once == json_twice)


def test_ansi_handling() -> None:
    print("\n--- ANSI handling ---\n")

    ansi_text = "\x1b[0;32mVPS: 203.0.113.10\x1b[0m"
    check("Shared strip_ansi works", "\x1b[" not in shared_strip_ansi(ansi_text))
    check("Bot safe_output strips ANSI", "\x1b[" not in bot_safe_output(ansi_text))
    check("Web safe_output strips ANSI", "\x1b[" not in web_safe_output(ansi_text))


# ── Main ────────────────────────────────────────────────────────────────────

def main() -> int:
    print("")
    print("=== NanoBK Redaction Integration Checkpoint (v1.9.9) ===")
    print("")
    print("Purpose: Verify Bot/Web redaction consistency against shared helper.")
    print("Scope:   Checkpoint test. Fake values only. No real nanobk/Telegram/Web.")
    print("")

    test_source_delegation()
    test_consistency_address_class()
    test_consistency_preserves_safe()
    test_json_redaction_consistency()
    test_format_status_no_leak()
    test_idempotency()
    test_ansi_handling()

    print("")
    print("=== Test Summary ===")
    print("")
    print(f"  \033[32m{PASSED} passed\033[0m, \033[31m{FAILED} failed\033[0m")
    print("")

    if FAILED == 0:
        print("  \033[32mCheckpoint PASS: Bot/Web redaction is consistent.\033[0m")
        return 0
    else:
        print(f"  \033[31mCheckpoint FAIL: {FAILED} inconsistency found.\033[0m")
        return 1


if __name__ == "__main__":
    sys.exit(main())
