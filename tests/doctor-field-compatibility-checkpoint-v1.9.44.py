#!/usr/bin/env python3
"""
Test: Doctor Summary Field Compatibility Checkpoint (v1.9.44)

Verifies Bot and Web Doctor Summary field compatibility after v1.9.43 fix.
No real nanobk. No real doctor. No Telegram. No Web server. No Cloudflare.

Usage:
    python3 tests/doctor-field-compatibility-checkpoint-v1.9.44.py
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

# Read sources
with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()

FIXTURES_DIR = os.path.join(REPO_DIR, "tests", "fixtures", "doctor-field-compatibility-v1.9.42")

def load_fixture(name):
    with open(os.path.join(FIXTURES_DIR, name)) as f:
        return json.load(f)

print("=== Doctor Summary Field Compatibility Checkpoint (v1.9.44) ===\n")

# ── A. Fixture/runtime consistency ──────────────────────────────────────────

print("--- A. Fixture/runtime consistency ---\n")

FIXTURE_PAIRS = [
    ("realistic-status.json", "expected-realistic-summary.json", "realistic"),
    ("profile-exists-no-domain.json", "expected-profile-exists-no-domain-summary.json", "profile_exists_no_domain"),
    ("profile-missing-explicit.json", "expected-profile-missing-explicit-summary.json", "profile_missing_explicit"),
    ("security-missing-secrets.json", "expected-security-missing-secrets-summary.json", "security_missing_secrets"),
    ("profile-present-services-missing.json", "expected-profile-present-services-missing-summary.json", "profile_present_services_missing"),
    ("dashboard-compatible-shape.json", "expected-dashboard-compatible-summary.json", "dashboard_compatible"),
]

for input_name, expected_name, label in FIXTURE_PAIRS:
    inp = load_fixture(input_name)
    exp = load_fixture(expected_name)
    bot_s = bot.build_doctor_summary(inp)
    web_s = web_build_doctor_summary(inp)

    # Bot matches expected
    check(f"Bot {label}: overall == {exp['overall']}", bot_s["overall"] == exp["overall"])
    check(f"Bot {label}: profile == {exp['profile']}", bot_s["profile"] == exp["profile"])
    check(f"Bot {label}: config == {exp['config']}", bot_s["config"] == exp["config"])
    check(f"Bot {label}: security == {exp['security']}", bot_s["security"] == exp["security"])

    # Web matches expected
    check(f"Web {label}: overall == {exp['overall']}", web_s["overall"] == exp["overall"])
    check(f"Web {label}: profile == {exp['profile']}", web_s["profile"] == exp["profile"])
    check(f"Web {label}: config == {exp['config']}", web_s["config"] == exp["config"])
    check(f"Web {label}: security == {exp['security']}", web_s["security"] == exp["security"])

    # Bot/Web match each other
    check(f"Cross {label}: overall", bot_s["overall"] == web_s["overall"])
    check(f"Cross {label}: profile", bot_s["profile"] == web_s["profile"])
    check(f"Cross {label}: config", bot_s["config"] == web_s["config"])

# ── B. Mapping checks ──────────────────────────────────────────────────────

print("\n--- B. Mapping checks ---\n")

r = load_fixture("expected-realistic-summary.json")
check("realistic: profile == present", r["profile"] == "present")
check("realistic: config == present", r["config"] == "present")

pnd = load_fixture("expected-profile-exists-no-domain-summary.json")
check("profile_exists_no_domain: profile == present", pnd["profile"] == "present")

pme = load_fixture("expected-profile-missing-explicit-summary.json")
check("profile_missing_explicit: profile == missing", pme["profile"] == "missing")

sms = load_fixture("expected-security-missing-secrets-summary.json")
check("security_missing_secrets: security != ok", sms["security"] != "ok")

ppsm = load_fixture("expected-profile-present-services-missing-summary.json")
check("profile_present_services_missing: overall != healthy", ppsm["overall"] != "healthy")

dc = load_fixture("expected-dashboard-compatible-summary.json")
check("dashboard_compatible: profile == present", dc["profile"] == "present")
check("dashboard_compatible: config == present", dc["config"] == "present")

# ── C. Safety checks ───────────────────────────────────────────────────────

print("\n--- C. Safety checks ---\n")

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

# ── D. Boundary checks ─────────────────────────────────────────────────────

print("\n--- D. Boundary checks ---\n")

# Source markers
check("Bot: doctor handler uses --json status", '"--json", "status"' in bot_source.split("async def cmd_doctor")[1].split("async def")[0] if "async def cmd_doctor" in bot_source else False)
check("Web: doctor handler uses --json status", '"--json", "status"' in web_source.split("def doctor():")[1].split("def ")[0] if "def doctor():" in web_source else False)
check("Bot: safe_output for full diagnostics", "safe_output" in bot_source)
check("Web: safe_output for full diagnostics", "safe_output" in web_source)
check("Bot: no shell=True", "shell=True" not in bot_source)
check("Web: no shell=True", "shell=True" not in web_source)
check("Bot: no direct .env reads added in build_doctor_summary", ".env" not in bot_source.split("def build_doctor_summary")[1].split("def ")[0] if "def build_doctor_summary" in bot_source else True)
check("Web: no direct .env reads added in build_doctor_summary", ".env" not in web_source.split("def build_doctor_summary")[1].split("def ")[0] if "def build_doctor_summary" in web_source else True)
check("Bot: no production status wrapper marker", "production_status_wrapper" not in bot_source)
check("Web: no production status wrapper marker", "production_status_wrapper" not in web_source)
check("Bot: no dirty VPS status wrapping marker", "dirty_vps" not in bot_source.lower())
check("Web: no dirty VPS status wrapping marker", "dirty_vps" not in web_source.lower())

# ── Summary ────────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mCheckpoint FAIL.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mCheckpoint PASS: Doctor Summary field compatibility verified.\033[0m")
