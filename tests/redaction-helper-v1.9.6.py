#!/usr/bin/env python3
"""
NanoBK Proxy Suite — Shared Redaction Helper Tests (v1.9.6)

Tests the shared redaction helper module against v1.9.5 fixtures.
This is a production-helper test, NOT a test-local contract demo.

Usage:
    python3 tests/redaction-helper-v1.9.6.py
"""

import json
import os
import sys

# Ensure repo root is on path
REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO_DIR)

from lib.nanobk_redaction import (
    redact_text,
    redact_json_obj,
    redact_json_text,
    strip_ansi,
    REDACTED_IPV4,
    REDACTED_IPV6,
    REDACTED_DOMAIN,
    REDACTED_URL,
    REDACTED_WORKERS_DEV,
    REDACTED_SUBSCRIPTION_PATH,
    REDACTED,
)

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


FIXTURE_DIR = os.path.join(REPO_DIR, "tests", "fixtures", "redaction-v1.9.5")


def load_fixture(name: str) -> str:
    path = os.path.join(FIXTURE_DIR, name)
    with open(path) as f:
        return f.read()


# ── JSON fixture tests ──────────────────────────────────────────────────────

def test_json_fixture() -> None:
    print("\n--- JSON fixture contract tests ---\n")

    input_text = load_fixture("sample-status-input.json")
    expected_text = load_fixture("sample-status-expected-redacted.json")

    input_data = json.loads(input_text)
    expected_data = json.loads(expected_text)

    # Redact using shared helper
    actual_data = redact_json_obj(input_data)
    actual_text = json.dumps(actual_data, indent=2, sort_keys=False, ensure_ascii=False)

    # Check: raw values absent
    check("No raw IPv4 in JSON output",
          "203.0.113.10" not in actual_text)
    check("No raw IPv6 in JSON output",
          "2001:db8::10" not in actual_text)
    check("No raw domain in JSON output",
          "node.example.invalid" not in actual_text)
    check("No raw URL in JSON output",
          "https://worker.example.invalid" not in actual_text)
    check("No raw workers.dev in JSON output",
          "nanobk-test.example.invalid.workers.dev" not in actual_text)
    check("No raw subscription path in JSON output",
          "fake-sub-path-12345" not in actual_text)
    check("No raw token in JSON output",
          "fake-doc-token-abc123xyz" not in actual_text)
    check("No raw secret in JSON output",
          "fake-secret-value-do-not-use" not in actual_text)

    # Check: replacement tokens present
    check(f"Contains {REDACTED_IPV4}",
          REDACTED_IPV4 in actual_text)
    check(f"Contains {REDACTED_IPV6}",
          REDACTED_IPV6 in actual_text)
    check(f"Contains {REDACTED_DOMAIN}",
          REDACTED_DOMAIN in actual_text)
    check(f"Contains {REDACTED_URL}",
          REDACTED_URL in actual_text)
    check(f"Contains {REDACTED_WORKERS_DEV}",
          REDACTED_WORKERS_DEV in actual_text)
    check(f"Contains {REDACTED_SUBSCRIPTION_PATH}",
          REDACTED_SUBSCRIPTION_PATH in actual_text)
    check(f"Contains {REDACTED}",
          REDACTED in actual_text)

    # Check: JSON is valid
    try:
        json.loads(actual_text)
        check("Redacted output is valid JSON", True)
    except json.JSONDecodeError:
        check("Redacted output is valid JSON", False)

    # Check: boolean/state fields preserved
    check("ok=true preserved", actual_data.get("ok") is True)
    check("geo=JP preserved", actual_data.get("geo") == "JP")
    check("services.hy2=active preserved",
          actual_data.get("services", {}).get("hy2") == "active")
    check("services.tuic=active preserved",
          actual_data.get("services", {}).get("tuic") == "active")
    check("services.reality=active preserved",
          actual_data.get("services", {}).get("reality") == "active")
    check("services.trojan=active preserved",
          actual_data.get("services", {}).get("trojan") == "active")
    check("cloudflare.nanok.envExists=true preserved",
          actual_data.get("cloudflare", {}).get("nanok", {}).get("envExists") is True)
    check("cloudflare.nanob.envExists=false preserved",
          actual_data.get("cloudflare", {}).get("nanob", {}).get("envExists") is False)
    check("subscription.configured=true preserved",
          actual_data.get("subscription", {}).get("configured") is True)
    check("security.secretsMode=600 preserved",
          actual_data.get("security", {}).get("secretsMode") == "600")

    # Check: non-sensitive string values preserved
    check("profile.currentPath preserved",
          actual_data.get("profile", {}).get("currentPath") == "/etc/nanobk/profile.current.json")
    check("warnings list preserved",
          isinstance(actual_data.get("warnings"), list))

    # Check: empty strings stay empty
    check("Empty route stays empty",
          actual_data.get("cloudflare", {}).get("nanob", {}).get("route") == "")
    check("Empty workersDev stays empty",
          actual_data.get("cloudflare", {}).get("nanob", {}).get("workersDev") == "")

    # Check: structural comparison with expected fixture
    # (may differ slightly in formatting, so compare parsed objects)
    check("domain field matches expected",
          actual_data.get("domain") == expected_data.get("domain"))
    check("vpsIp field matches expected",
          actual_data.get("vpsIp") == expected_data.get("vpsIp"))
    check("profile.ipv6 field matches expected",
          actual_data.get("profile", {}).get("ipv6") == expected_data.get("profile", {}).get("ipv6"))
    check("security.token field matches expected",
          actual_data.get("security", {}).get("token") == expected_data.get("security", {}).get("token"))


# ── Text fixture tests ──────────────────────────────────────────────────────

def test_text_fixture() -> None:
    print("\n--- Text fixture contract tests ---\n")

    input_text = load_fixture("sample-cli-output-input.txt")
    expected_text = load_fixture("sample-cli-output-expected-redacted.txt")

    actual = redact_text(input_text)

    # Check: raw values absent
    check("No raw IPv4 in text output",
          "203.0.113.10" not in actual)
    check("No raw IPv6 in text output",
          "2001:db8::10" not in actual)
    check("No raw domain in text output",
          "node.example.invalid" not in actual)
    check("No raw URL in text output",
          "https://worker.example.invalid" not in actual)
    check("No raw workers.dev in text output",
          "nanobk-test.example.invalid.workers.dev" not in actual)
    check("No raw subscription path in text output",
          "fake-sub-path-12345" not in actual)
    check("No raw token in text output",
          "fake-doc-token-abc123xyz" not in actual)
    check("No raw secret in text output",
          "fake-secret-value-do-not-use" not in actual)
    check("No raw private key in text output",
          "FAKE_PRIVATE_KEY_DO_NOT_USE" not in actual)
    check("No raw admin token in text output",
          "fake-cf-admin-token-do-not-use" not in actual)

    # Check: replacement tokens present
    check(f"Text contains {REDACTED_IPV4}",
          REDACTED_IPV4 in actual)
    check(f"Text contains {REDACTED_IPV6}",
          REDACTED_IPV6 in actual)
    check(f"Text contains {REDACTED_DOMAIN}",
          REDACTED_DOMAIN in actual)
    check(f"Text contains {REDACTED_URL}",
          REDACTED_URL in actual)
    check(f"Text contains {REDACTED_WORKERS_DEV}",
          REDACTED_WORKERS_DEV in actual)
    check(f"Text contains {REDACTED_SUBSCRIPTION_PATH}",
          REDACTED_SUBSCRIPTION_PATH in actual)
    check(f"Text contains {REDACTED}",
          REDACTED in actual)

    # Check: non-sensitive content preserved
    check("Preserves 'NanoBK Status Report'",
          "NanoBK Status Report" in actual)
    check("Preserves 'Region: JP'",
          "Region: JP" in actual)
    check("Preserves 'Services:'",
          "Services:" in actual)
    check("Preserves 'HY2: active'",
          "HY2: active" in actual)
    check("Preserves 'TUIC: active'",
          "TUIC: active" in actual)
    check("Preserves 'Reality: active'",
          "Reality: active" in actual)
    check("Preserves 'Trojan: active'",
          "Trojan: active" in actual)
    check("Preserves '/etc/nanobk/profile.current.json'",
          "/etc/nanobk/profile.current.json" in actual)

    # Check: line-by-line comparison with expected fixture
    actual_lines = actual.strip().splitlines()
    expected_lines = expected_text.strip().splitlines()
    check(f"Line count matches expected ({len(actual_lines)} vs {len(expected_lines)})",
          len(actual_lines) == len(expected_lines))

    if len(actual_lines) == len(expected_lines):
        mismatches = []
        for i, (a, e) in enumerate(zip(actual_lines, expected_lines)):
            if a != e:
                mismatches.append(f"  Line {i+1}: got {a!r}, expected {e!r}")
        if mismatches:
            check("All lines match expected fixture", False)
            for m in mismatches[:5]:
                print(m)
        else:
            check("All lines match expected fixture", True)


# ── Idempotency tests ───────────────────────────────────────────────────────

def test_idempotency() -> None:
    print("\n--- Idempotency tests ---\n")

    # Text idempotency
    input_text = load_fixture("sample-cli-output-input.txt")
    once = redact_text(input_text)
    twice = redact_text(once)
    check("Text redaction is idempotent",
          once == twice)

    # JSON idempotency
    input_json = load_fixture("sample-status-input.json")
    data = json.loads(input_json)
    once_json = redact_json_obj(data)
    twice_json = redact_json_obj(once_json)
    check("JSON redaction is idempotent",
          once_json == twice_json)

    # Verify no raw values leak through idempotency
    twice_text = json.dumps(twice_json, indent=2, ensure_ascii=False)
    check("Idempotent JSON has no raw IPv4",
          "203.0.113.10" not in twice_text)
    check("Idempotent JSON has no raw domain",
          "node.example.invalid" not in twice_text)


# ── Edge case tests ─────────────────────────────────────────────────────────

def test_edge_cases() -> None:
    print("\n--- Edge case tests ---\n")

    # Empty strings
    check("Empty string stays empty", redact_text("") == "")

    # Plain text with no sensitive data
    plain = "Service hy2 is active on port 443"
    check("Plain text preserved",
          redact_text(plain) == plain)

    # Boolean preservation in JSON
    data = {"ok": True, "active": False, "count": 42}
    redacted = redact_json_obj(data)
    check("Boolean true preserved in JSON", redacted["ok"] is True)
    check("Boolean false preserved in JSON", redacted["active"] is False)
    check("Number preserved in JSON", redacted["count"] == 42)

    # Invalid JSON text fallback
    invalid_json = "not json at all with 203.0.113.10"
    result = redact_json_text(invalid_json)
    check("Invalid JSON falls back to redact_text",
          "203.0.113.10" not in result)
    check("Invalid JSON fallback contains replacement",
          REDACTED_IPV4 in result)

    # Valid JSON text
    valid_json = '{"ip": "203.0.113.10", "ok": true}'
    result = redact_json_text(valid_json)
    parsed = json.loads(result)
    check("Valid JSON text redacted correctly",
          parsed["ip"] == REDACTED_IPV4)
    check("Valid JSON text preserves boolean",
          parsed["ok"] is True)

    # ANSI stripping
    ansi_text = "\x1b[0;32mINFO\x1b[0m 203.0.113.10"
    result = redact_text(ansi_text)
    check("ANSI codes stripped",
          "\x1b[" not in result)
    check("IPv4 redacted after ANSI strip",
          "203.0.113.10" not in result)

    # Geo field not redacted
    check("Geo field preserved",
          redact_text("Region: JP") == "Region: JP")

    # Port numbers not over-redacted
    check("Port number preserved",
          "443" in redact_text("HY2: active on port 443"))

    # Non-sensitive key values preserved
    data2 = {"name": "test", "status": "healthy"}
    r2 = redact_json_obj(data2)
    check("Non-sensitive key values preserved",
          r2["name"] == "test" and r2["status"] == "healthy")


# ── ANSI stripping tests ────────────────────────────────────────────────────

def test_ansi() -> None:
    print("\n--- ANSI stripping tests ---\n")

    check("Strip simple ANSI",
          strip_ansi("\x1b[0;34mINFO\x1b[0m") == "INFO")
    check("Strip ANSI with codes",
          strip_ansi("\x1b[1;33mWARN\x1b[0m") == "WARN")
    check("No ANSI in plain text",
          strip_ansi("hello") == "hello")


# ── Main ────────────────────────────────────────────────────────────────────

def main() -> int:
    print("")
    print("=== NanoBK Shared Redaction Helper Tests (v1.9.6) ===")
    print("")
    print("Purpose: Verify shared redaction helper against v1.9.5 fixtures.")
    print("Scope:   Production helper module, NOT test-local contract.")
    print("")

    test_json_fixture()
    test_text_fixture()
    test_idempotency()
    test_edge_cases()
    test_ansi()

    print("")
    print("=== Test Summary ===")
    print("")
    print(f"  \033[32m{PASSED} passed\033[0m, \033[31m{FAILED} failed\033[0m")
    print("")

    if FAILED == 0:
        print("  \033[32mAll redaction helper tests passed!\033[0m")
        print("")
        print("  Shared helper satisfies v1.9.5 fixture contract.")
        print("  Helper is NOT yet wired into Bot/Web runtime.")
        return 0
    else:
        print(f"  \033[31m{FAILED} test(s) failed.\033[0m")
        print("")
        print("  Review failures above.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
