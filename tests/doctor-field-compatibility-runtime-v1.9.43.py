#!/usr/bin/env python3
"""
Test: Doctor Summary Field Compatibility Runtime (v1.9.43)

Verifies Bot and Web build_doctor_summary() consume v1.9.42 fixtures.
No real nanobk. No real doctor. No Telegram. No Web server. No Cloudflare.

Usage:
    python3 tests/doctor-field-compatibility-runtime-v1.9.43.py
"""

import json
import os
import sys

REPO_DIR = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, REPO_DIR)

passed = 0
failed = 0

def check(desc: str, ok: bool):
    global passed, failed
    if ok:
        print(f"  \033[32m✓\033[0m {desc}")
        passed += 1
    else:
        print(f"  \033[31m✗\033[0m {desc}")
        failed += 1

# Import builders
import bot.nanobk_bot as bot
from web.app import build_doctor_summary as web_build_doctor_summary

FIXTURES_DIR = os.path.join(REPO_DIR, "tests", "fixtures", "doctor-field-compatibility-v1.9.42")

def load_fixture(name):
    with open(os.path.join(FIXTURES_DIR, name)) as f:
        return json.load(f)

print("=== Doctor Summary Field Compatibility Runtime Test (v1.9.43) ===\n")

# ── Fixture pairs ────────────────────────────────────────────────────────────

FIXTURE_PAIRS = [
    ("realistic-status.json", "expected-realistic-summary.json", "realistic"),
    ("profile-exists-no-domain.json", "expected-profile-exists-no-domain-summary.json", "profile_exists_no_domain"),
    ("profile-missing-explicit.json", "expected-profile-missing-explicit-summary.json", "profile_missing_explicit"),
    ("security-missing-secrets.json", "expected-security-missing-secrets-summary.json", "security_missing_secrets"),
    ("profile-present-services-missing.json", "expected-profile-present-services-missing-summary.json", "profile_present_services_missing"),
    ("dashboard-compatible-shape.json", "expected-dashboard-compatible-summary.json", "dashboard_compatible"),
]

# ══════════════════════════════════════════════════════════════════════════════
# Bot builder against v1.9.42 fixtures
# ══════════════════════════════════════════════════════════════════════════════

print("--- Bot builder: v1.9.42 fixtures ---\n")

for input_name, expected_name, label in FIXTURE_PAIRS:
    inp = load_fixture(input_name)
    exp = load_fixture(expected_name)
    actual = bot.build_doctor_summary(inp)

    check(f"Bot {label}: overall == {exp['overall']}", actual["overall"] == exp["overall"])
    check(f"Bot {label}: profile == {exp['profile']}", actual["profile"] == exp["profile"])
    check(f"Bot {label}: config == {exp['config']}", actual["config"] == exp["config"])
    check(f"Bot {label}: security == {exp['security']}", actual["security"] == exp["security"])
    check(f"Bot {label}: services match", actual["services"] == exp["services"])
    check(f"Bot {label}: display_policy matches", actual["display_policy"] == exp["display_policy"])

# ══════════════════════════════════════════════════════════════════════════════
# Web builder against v1.9.42 fixtures
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Web builder: v1.9.42 fixtures ---\n")

for input_name, expected_name, label in FIXTURE_PAIRS:
    inp = load_fixture(input_name)
    exp = load_fixture(expected_name)
    actual = web_build_doctor_summary(inp)

    check(f"Web {label}: overall == {exp['overall']}", actual["overall"] == exp["overall"])
    check(f"Web {label}: profile == {exp['profile']}", actual["profile"] == exp["profile"])
    check(f"Web {label}: config == {exp['config']}", actual["config"] == exp["config"])
    check(f"Web {label}: security == {exp['security']}", actual["security"] == exp["security"])
    check(f"Web {label}: services match", actual["services"] == exp["services"])
    check(f"Web {label}: display_policy matches", actual["display_policy"] == exp["display_policy"])

# ══════════════════════════════════════════════════════════════════════════════
# Bot/Web consistency
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Bot/Web consistency ---\n")

for input_name, expected_name, label in FIXTURE_PAIRS:
    inp = load_fixture(input_name)
    bot_s = bot.build_doctor_summary(inp)
    web_s = web_build_doctor_summary(inp)

    check(f"Cross {label}: overall matches", bot_s["overall"] == web_s["overall"])
    check(f"Cross {label}: profile matches", bot_s["profile"] == web_s["profile"])
    check(f"Cross {label}: config matches", bot_s["config"] == web_s["config"])
    check(f"Cross {label}: security matches", bot_s["security"] == web_s["security"])
    check(f"Cross {label}: services match", bot_s["services"] == web_s["services"])

# ══════════════════════════════════════════════════════════════════════════════
# Safety: no raw paths in formatted output
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Safety: no raw paths/IP/domain ---\n")

FORBIDDEN = [
    "/tmp/nanobk-test-config",
    "/etc/nanobk",
    "192.0.2.",
    "198.51.100.",
    "203.0.113.",
    "2001:db8:",
    "example.invalid",
    "http://",
    "https://",
    "workers.dev",
    "TEST_TOKEN",
    "TEST_SECRET",
    "TEST_PRIVATE_KEY",
]

for input_name, expected_name, label in FIXTURE_PAIRS:
    inp = load_fixture(input_name)
    bot_s = bot.build_doctor_summary(inp)
    web_s = web_build_doctor_summary(inp)
    bot_str = json.dumps(bot_s)
    web_str = json.dumps(web_s)

    for pattern in FORBIDDEN:
        check(f"Bot {label}: no '{pattern}'", pattern not in bot_str)
        check(f"Web {label}: no '{pattern}'", pattern not in web_str)

# ══════════════════════════════════════════════════════════════════════════════
# v1.9.35 fixtures still pass
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- v1.9.35 backward compatibility ---\n")

V1935_PAIRS = [
    ("healthy-status.json", "expected-healthy-summary.json", "healthy"),
    ("partial-services-status.json", "expected-partial-services-summary.json", "partial"),
    ("missing-config-status.json", "expected-missing-config-summary.json", "missing"),
    ("cloudflare-missing-status.json", "expected-cloudflare-missing-summary.json", "cloudflare_missing"),
]

V1935_DIR = os.path.join(REPO_DIR, "tests", "fixtures", "doctor-summary-v1.9.35")

def load_v1935(name):
    with open(os.path.join(V1935_DIR, name)) as f:
        return json.load(f)

for input_name, expected_name, label in V1935_PAIRS:
    inp = load_v1935(input_name)
    exp = load_v1935(expected_name)
    bot_s = bot.build_doctor_summary(inp)
    web_s = web_build_doctor_summary(inp)

    check(f"v1.9.35 Bot {label}: overall matches", bot_s["overall"] == exp["overall"])
    check(f"v1.9.35 Bot {label}: profile matches", bot_s["profile"] == exp["profile"])
    check(f"v1.9.35 Bot {label}: config matches", bot_s["config"] == exp["config"])
    check(f"v1.9.35 Web {label}: overall matches", web_s["overall"] == exp["overall"])
    check(f"v1.9.35 Web {label}: profile matches", web_s["profile"] == exp["profile"])
    check(f"v1.9.35 Web {label}: config matches", web_s["config"] == exp["config"])

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mTest FAIL.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mTest PASS: Bot/Web Doctor Summary field compatibility verified.\033[0m")
