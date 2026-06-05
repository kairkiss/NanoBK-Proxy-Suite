#!/usr/bin/env python3
"""
NanoBK Proxy Suite — Web Redaction Helper Integration Test (v1.9.8)

Verifies that web/app.py correctly delegates to the shared redaction helper
from lib/nanobk_redaction.py. Tests the shared helper behavior that Web now
uses, plus verifies Web source code delegation.

All test values are fake and documentation-safe (RFC 5737/3849/2606).

Usage:
    python3 tests/web-redaction-helper-integration-v1.9.8.py
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
    redact_json_obj,
    redact_json_text,
    REDACTED_IPV4,
    REDACTED_IPV6,
    REDACTED_DOMAIN,
    REDACTED_URL,
    REDACTED_WORKERS_DEV,
    REDACTED_SUBSCRIPTION_PATH,
    REDACTED,
)

import json


# ── Web helper functions (replicate web/app.py behavior) ────────────────────

def limit_text(text: str, max_len: int = 12000) -> str:
    """Truncate text for web display (matches Web behavior)."""
    if len(text) <= max_len:
        return text
    return text[:max_len] + "\n... [truncated]"


def safe_output(text: str) -> str:
    """Strip ANSI, apply redaction, and limit length (matches Web behavior)."""
    text = strip_ansi(text)
    text = redact_text(text)
    return limit_text(text)


def format_status(data: dict) -> dict:
    """Format nanobk status (matches Web behavior)."""
    redacted = redact_json_obj(data)
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


# ── Verify Web source delegates to shared helper ───────────────────────────

def test_web_source_delegation() -> None:
    print("\n--- Web source delegation verification ---\n")

    web_src_path = os.path.join(REPO_DIR, "web", "app.py")
    with open(web_src_path) as f:
        web_src = f.read()

    check("Web imports from lib.nanobk_redaction",
          "from lib.nanobk_redaction import" in web_src)
    check("Web imports shared_strip_ansi",
          "strip_ansi as _shared_strip_ansi" in web_src)
    check("Web imports shared_redact_text",
          "redact_text as _shared_redact_text" in web_src)
    check("Web imports shared_redact_json_obj",
          "redact_json_obj as _shared_redact_json_obj" in web_src)
    check("Web strip_ansi delegates to shared",
          "return _shared_strip_ansi(text)" in web_src)
    check("Web redact_text delegates to shared",
          "return _shared_redact_text(text)" in web_src)
    check("Web redact_json delegates to shared",
          "return _shared_redact_json_obj(value)" in web_src)
    check("Web does NOT have local _REDACT_PATTERNS",
          "_REDACT_PATTERNS" not in web_src)
    check("Web does NOT have local _ANSI_RE",
          "_ANSI_RE" not in web_src)
    check("Web does NOT have local _SENSITIVE_KEY_SUBSTRINGS",
          "_SENSITIVE_KEY_SUBSTRINGS" not in web_src)
    check("Web computes _REPO_ROOT for import",
          "_REPO_ROOT" in web_src)


# ── Tests using shared helper (same as Web now uses) ────────────────────────

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

    check("Redacts token=value",
          "my-token-val" not in redact_text("token=my-token-val"))
    check("Redacts password=value",
          "SuperSecret123" not in redact_text("password=SuperSecret123"))
    check("Redacts secret=value",
          "my-secret-val" not in redact_text("secret=my-secret-val"))
    check("Redacts PrivateKey=value",
          "aBcDeFg" not in redact_text("PrivateKey: aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"))
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
          "nanobk-test.workers.dev" not in redact_text("workers.dev: nanobk-test.workers.dev"))
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


def test_redact_json_address_class() -> None:
    print("\n--- redact_json address-class tests ---\n")

    test_data = {
        "domain": "node.example.invalid",
        "vpsIp": "203.0.113.10",
        "ok": True,
        "geo": "JP",
        "services": {"hy2": "active", "tuic": "active"},
        "security": {"secretsMode": "600", "token": "fake-token-val"},
        "cloudflare": {
            "nanok": {"envExists": True, "workersDev": "nanobk-test.workers.dev"},
            "nanob": {"envExists": False}
        },
        "subscription": {"url": "https://node.example.invalid/sub/fake-sub-path-12345", "configured": True},
        "profile": {"domain": "node.example.invalid", "vpsIp": "203.0.113.10", "ipv6": "2001:db8::10"},
        "warnings": ["Service hy2 may need restart"]
    }

    redacted = redact_json_obj(test_data)
    redacted_text = json.dumps(redacted, indent=2)

    check("redact_json redacts domain",
          "node.example.invalid" not in redacted_text)
    check("redact_json redacts IPv4",
          "203.0.113.10" not in redacted_text)
    check("redact_json redacts IPv6",
          "2001:db8::10" not in redacted_text)
    check("redact_json redacts URL",
          "https://node.example.invalid" not in redacted_text)
    check("redact_json redacts workers.dev",
          "nanobk-test.workers.dev" not in redacted_text)
    check("redact_json redacts subscription path",
          "fake-sub-path-12345" not in redacted_text)
    check("redact_json redacts token key",
          redacted.get("security", {}).get("token") == "[REDACTED]")
    check("redact_json preserves ok=true",
          redacted.get("ok") is True)
    check("redact_json preserves geo",
          redacted.get("geo") == "JP")
    check("redact_json preserves services",
          redacted.get("services", {}).get("hy2") == "active")
    check("redact_json preserves secretsMode",
          redacted.get("security", {}).get("secretsMode") == "600")
    check("redact_json preserves configured",
          redacted.get("subscription", {}).get("configured") is True)
    check("redact_json preserves warnings",
          isinstance(redacted.get("warnings"), list))
    check("redact_json preserves envExists",
          redacted.get("cloudflare", {}).get("nanok", {}).get("envExists") is True)
    check("redact_json output is valid JSON",
          json.loads(json.dumps(redacted)) is not None)


def test_api_status_redaction() -> None:
    print("\n--- /api/status redaction tests ---\n")

    # Simulate what /api/status does: redact_json(data) then jsonify
    api_data = {
        "ok": True,
        "domain": "node.example.invalid",
        "vpsIp": "203.0.113.10",
        "services": {"hy2": "active"},
        "security": {"token": "fake-api-token"},
        "cloudflare": {},
        "warnings": []
    }

    redacted = redact_json_obj(api_data)
    api_json = json.dumps(redacted)

    check("API: no raw domain", "node.example.invalid" not in api_json)
    check("API: no raw IPv4", "203.0.113.10" not in api_json)
    check("API: token redacted", "fake-api-token" not in api_json)
    check("API: preserves ok", redacted.get("ok") is True)
    check("API: preserves services", redacted.get("services", {}).get("hy2") == "active")


def test_format_status_safe() -> None:
    print("\n--- format_status + redaction tests ---\n")

    test_status = {
        "ok": True,
        "domain": "node.example.invalid",
        "vpsIp": "203.0.113.10",
        "geo": "JP",
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {"nanok": {"envExists": True}, "nanob": {"envExists": False}},
        "warnings": []
    }

    formatted = format_status(test_status)

    check("format_status: domain redacted",
          formatted["domain"] != "node.example.invalid")
    check("format_status: vps_ip redacted",
          formatted["vps_ip"] != "203.0.113.10")
    check("format_status: raw_json no domain",
          "node.example.invalid" not in formatted["raw_json"])
    check("format_status: raw_json no IPv4",
          "203.0.113.10" not in formatted["raw_json"])
    check("format_status: preserves services",
          formatted["services"].get("hy2") == "active")
    check("format_status: preserves geo",
          formatted["geo"] == "JP")
    check("format_status: preserves secretsMode",
          formatted["security"].get("secretsMode") == "600")


def test_doctor_failure_output() -> None:
    print("\n--- doctor/failure output redaction tests ---\n")

    # Simulate doctor output with sensitive data
    doctor_output = (
        "Checking VPS at 203.0.113.10...\n"
        "Domain: node.example.invalid\n"
        "IPv6: 2001:db8::10\n"
        "Subscription: https://node.example.invalid/sub/fake-sub-path-12345\n"
        "Config: /etc/nanobk/config.json\n"
        "token=fake-doctor-token-val\n"
        "secret=fake-doctor-secret-val"
    )

    safe = safe_output(doctor_output)

    check("Doctor: no raw IPv4", "203.0.113.10" not in safe)
    check("Doctor: no raw domain", "node.example.invalid" not in safe)
    check("Doctor: no raw IPv6", "2001:db8::10" not in safe)
    check("Doctor: no raw URL", "https://node.example.invalid" not in safe)
    check("Doctor: no raw token", "fake-doctor-token-val" not in safe)
    check("Doctor: no raw secret", "fake-doctor-secret-val" not in safe)
    check("Doctor: preserves config path", "/etc/nanobk/config.json" in safe)

    # Simulate rotate failure output
    rotate_output = (
        "Rotate failed (code 1):\n"
        "Service at 203.0.113.10:443 unreachable\n"
        "Domain node.example.invalid DNS check failed"
    )
    safe_rotate = safe_output(rotate_output)
    check("Rotate failure: no raw IPv4", "203.0.113.10" not in safe_rotate)
    check("Rotate failure: no raw domain", "node.example.invalid" not in safe_rotate)


def test_raw_json_details() -> None:
    print("\n--- Raw JSON details redaction tests ---\n")

    # Simulate what format_status produces for raw_json
    test_data = {
        "ok": True, "domain": "node.example.invalid", "vpsIp": "203.0.113.10",
        "services": {"hy2": "active"}, "security": {"token": "fake-val"},
        "cloudflare": {}, "warnings": []
    }
    formatted = format_status(test_data)
    raw_json = formatted["raw_json"]

    check("Raw JSON: no raw domain", "node.example.invalid" not in raw_json)
    check("Raw JSON: no raw IPv4", "203.0.113.10" not in raw_json)
    check("Raw JSON: no raw token", "fake-val" not in raw_json)
    check("Raw JSON: preserves ok", "\"ok\": true" in raw_json)
    check("Raw JSON: preserves services", "\"hy2\": \"active\"" in raw_json)
    check("Raw JSON: is valid JSON", json.loads(raw_json) is not None)


def test_limit_text() -> None:
    print("\n--- limit_text tests ---\n")

    long_text = "x" * 15000
    truncated = limit_text(long_text, max_len=12000)
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

    # JSON idempotency
    data = {"domain": "node.example.invalid", "vpsIp": "203.0.113.10", "ok": True}
    once_json = redact_json_obj(data)
    twice_json = redact_json_obj(once_json)
    check("redact_json is idempotent",
          once_json == twice_json)


# ── Main ────────────────────────────────────────────────────────────────────

def main() -> int:
    print("")
    print("=== NanoBK Web Redaction Helper Integration Test (v1.9.8) ===")
    print("")
    print("Purpose: Verify Web uses shared redaction helper correctly.")
    print("Scope:   Web integration test. Fake values only.")
    print("")

    test_web_source_delegation()
    test_strip_ansi()
    test_redact_text_token_secret()
    test_redact_text_address_class()
    test_redact_text_preserves_safe()
    test_redact_json_address_class()
    test_api_status_redaction()
    test_format_status_safe()
    test_doctor_failure_output()
    test_raw_json_details()
    test_limit_text()
    test_idempotency()

    print("")
    print("=== Test Summary ===")
    print("")
    print(f"  \033[32m{PASSED} passed\033[0m, \033[31m{FAILED} failed\033[0m")
    print("")

    if FAILED == 0:
        print("  \033[32mAll Web redaction integration tests passed!\033[0m")
        print("")
        print("  Web correctly delegates to shared redaction helper.")
        print("  Address-class values are redacted from Web outputs.")
        return 0
    else:
        print(f"  \033[31m{FAILED} test(s) failed.\033[0m")
        print("")
        print("  Review failures above.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
