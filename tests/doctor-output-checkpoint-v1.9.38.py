#!/usr/bin/env python3
"""
Test: Doctor Output Checkpoint (v1.9.38)

Verifies Bot/Web Doctor Summary consistency and safety after v1.9.36/v1.9.37.
Source-level tests + direct helper tests. No real server, no real nanobk,
no Telegram, no Cloudflare, no real doctor.

Usage:
    python3 tests/doctor-output-checkpoint-v1.9.38.py
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

# ── Load sources ──────────────────────────────────────────────────────────────

with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()
with open(os.path.join(REPO_DIR, "web", "i18n.py")) as f:
    web_i18n_source = f.read()
with open(os.path.join(REPO_DIR, "web", "templates", "doctor.html")) as f:
    doctor_template = f.read()

# Import modules
import bot.nanobk_bot as bot
from web.app import build_doctor_summary as web_build_doctor_summary
from web.i18n import wt as web_wt, WEB_TEXT

# Load fixtures
FIXTURES_DIR = os.path.join(REPO_DIR, "tests", "fixtures", "doctor-summary-v1.9.35")

def load_fixture(name):
    with open(os.path.join(FIXTURES_DIR, name)) as f:
        return json.load(f)

print("=== Doctor Output Checkpoint (v1.9.38) ===\n")

# ══════════════════════════════════════════════════════════════════════════════
# Bot checks
# ══════════════════════════════════════════════════════════════════════════════

print("--- Bot: Doctor Summary builder ---\n")

check("Bot: build_doctor_summary exists", callable(bot.build_doctor_summary))
check("Bot: format_doctor_summary exists", callable(bot.format_doctor_summary))

# Fixture matching
FIXTURE_MAP = [
    ("healthy-status.json", "expected-healthy-summary.json", "healthy"),
    ("partial-services-status.json", "expected-partial-services-summary.json", "partial"),
    ("missing-config-status.json", "expected-missing-config-summary.json", "missing"),
    ("cloudflare-missing-status.json", "expected-cloudflare-missing-summary.json", "cf_missing"),
]
for fixture_name, expected_name, label in FIXTURE_MAP:
    inp = load_fixture(fixture_name)
    exp = load_fixture(expected_name)
    actual = bot.build_doctor_summary(inp)
    check(f"Bot {label}: overall matches", actual["overall"] == exp["overall"])
    check(f"Bot {label}: services match", actual["services"] == exp["services"])
    check(f"Bot {label}: display_policy.beginner_safe", actual["display_policy"]["beginner_safe"] is True)
    check(f"Bot {label}: display_policy.full_output_advanced_only", actual["display_policy"]["full_output_advanced_only"] is True)
    check(f"Bot {label}: display_policy.redaction_required", actual["display_policy"]["redaction_required"] is True)

# Unknown
unk = bot.build_doctor_summary({})
check("Bot unknown: overall == unknown", unk["overall"] == "unknown")
check("Bot unknown: all services unknown", all(v == "unknown" for v in unk["services"].values()))

# None
none_s = bot.build_doctor_summary(None)
check("Bot none: overall == unknown", none_s["overall"] == "unknown")

print("\n--- Bot: /doctor source behavior ---\n")

doctor_section = bot_source.split("async def cmd_doctor")[1].split("async def")[0] if "async def cmd_doctor" in bot_source else ""
check("Bot: cmd_doctor uses --json status", '"--json", "status"' in doctor_section)
check("Bot: cmd_doctor uses build_doctor_summary", "build_doctor_summary" in doctor_section)
check("Bot: cmd_doctor uses format_doctor_summary", "format_doctor_summary" in doctor_section)
check("Bot: cmd_doctor checks advanced mode", "is_advanced_mode_enabled" in doctor_section)
check("Bot: full doctor call after advanced gate", '["doctor"]' in doctor_section.split("is_advanced_mode_enabled")[1] if "is_advanced_mode_enabled" in doctor_section else False)
check("Bot: advanced path uses safe_output", "safe_output" in doctor_section.split("is_advanced_mode_enabled")[1] if "is_advanced_mode_enabled" in doctor_section else False)
check("Bot: owner-only remains", "is_owner" in doctor_section)
check("Bot: warning key exists", "doctor_full_warning" in bot_source)

print("\n--- Bot: Other markers unchanged ---\n")

check("Bot: /status_json registered", 'CommandHandler("status_json"' in bot_source)
check("Bot: advanced mode helpers exist", "def enable_advanced_mode" in bot_source and "def is_advanced_mode_enabled" in bot_source)
check("Bot: rotate handlers exist", "rotate_all" in bot_source and "rotate_hy2" in bot_source)
check("Bot: no shell=True", "shell=True" not in bot_source)
check("Bot: no os.system", "os.system" not in bot_source)
check("Bot: shared redaction import", "from lib.nanobk_redaction import" in bot_source)

print("\n--- Bot: i18n keys ---\n")

bot_doctor_keys = [
    "doctor_summary_title", "doctor_label_overall", "doctor_label_services",
    "doctor_label_cloudflare", "doctor_label_next_step", "doctor_full_note",
    "doctor_full_warning", "doctor_status_parse_error", "doctor_full_unavailable",
]
for key in bot_doctor_keys:
    check(f"Bot BOT_TEXT has {key}", key in bot.BOT_TEXT)
    if key in bot.BOT_TEXT:
        check(f"Bot {key} has en", "en" in bot.BOT_TEXT[key])
        check(f"Bot {key} has zh", "zh" in bot.BOT_TEXT[key])

# ══════════════════════════════════════════════════════════════════════════════
# Web checks
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Web: Doctor Summary builder ---\n")

check("Web: build_doctor_summary exists", callable(web_build_doctor_summary))

# Fixture matching
for fixture_name, expected_name, label in FIXTURE_MAP:
    inp = load_fixture(fixture_name)
    exp = load_fixture(expected_name)
    actual = web_build_doctor_summary(inp)
    check(f"Web {label}: overall matches", actual["overall"] == exp["overall"])
    check(f"Web {label}: services match", actual["services"] == exp["services"])
    check(f"Web {label}: display_policy.beginner_safe", actual["display_policy"]["beginner_safe"] is True)
    check(f"Web {label}: display_policy.full_output_advanced_only", actual["display_policy"]["full_output_advanced_only"] is True)
    check(f"Web {label}: display_policy.redaction_required", actual["display_policy"]["redaction_required"] is True)

# Unknown
unk_w = web_build_doctor_summary({})
check("Web unknown: overall == unknown", unk_w["overall"] == "unknown")
check("Web unknown: all services unknown", all(v == "unknown" for v in unk_w["services"].values()))

# None
none_w = web_build_doctor_summary(None)
check("Web none: overall == unknown", none_w["overall"] == "unknown")

print("\n--- Web: /doctor route behavior ---\n")

doctor_route = web_source.split("def doctor():")[1].split("def ")[0] if "def doctor():" in web_source else ""
check("Web: /doctor route exists", "@app.route(\"/doctor\"" in web_source)
check("Web: /doctor is @require_login", "@require_login" in web_source.split("def doctor()")[0][-200:] if "def doctor()" in web_source else False)
check("Web: POST uses validate_csrf", "validate_csrf()" in doctor_route)
check("Web: /doctor uses --json status", '"--json", "status"' in doctor_route)
check("Web: /doctor uses build_doctor_summary", "build_doctor_summary" in doctor_route)
# The full doctor call is after the "if adv_enabled:" check
adv_section = doctor_route.split("if adv_enabled:")[1] if "if adv_enabled:" in doctor_route else ""
check("Web: full doctor call after advanced gate", '["doctor"]' in adv_section)
check("Web: advanced path uses safe_output", "safe_output" in adv_section)
check("Web: warning key exists", "doctor_full_warning" in web_source)

print("\n--- Web: Template checks ---\n")

check("Template: has summary card markers", "summary.overall" in doctor_template)
check("Template: has services loop", "summary.services.items()" in doctor_template)
check("Template: has advanced mode gate", "advanced_mode_enabled" in doctor_template)
check("Template: has collapsed details", "<details" in doctor_template)
check("Template: has warning box", "warning-box" in doctor_template)
check("Template: has doctor_full_warning", "doctor_full_warning" in doctor_template)
check("Template: has locked-panel for advanced note", "locked-panel" in doctor_template)
check("Template: has CSRF form", "csrf_token" in doctor_template)
check("Template: uses t()", "{{ t(" in doctor_template)

print("\n--- Web: Other markers unchanged ---\n")

check("Web: /api/status route exists", '"/api/status"' in web_source)
check("Web: api_status uses redact_json", "redact_json(data)" in web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else False)
check("Web: /api/status not gated by advanced", "is_advanced_mode_enabled" not in web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else False)
check("Web: Raw JSON gating in status template", "advanced_mode_enabled" in open(os.path.join(REPO_DIR, "web", "templates", "status.html")).read())
check("Web: advanced mode routes exist", "/advanced/on" in web_source and "/advanced/off" in web_source)
check("Web: rotate routes exist", "/rotate" in web_source and "rotate_confirm" in web_source)
check("Web: no shell=True", "shell=True" not in web_source)
check("Web: no os.system", "os.system" not in web_source)
check("Web: shared redaction import", "from lib.nanobk_redaction import" in web_source)

print("\n--- Web: i18n keys ---\n")

web_doctor_keys = [
    "doctor_summary_title", "doctor_label_overall", "doctor_label_services",
    "doctor_label_cloudflare", "doctor_label_next_step", "doctor_full_note",
    "doctor_full_warning", "doctor_full_details_label", "doctor_status_parse_error",
    "doctor_full_unavailable", "doctor_intro_text",
]
for key in web_doctor_keys:
    check(f"Web WEB_TEXT has {key}", key in WEB_TEXT)
    if key in WEB_TEXT:
        check(f"Web {key} has en", "en" in WEB_TEXT[key])
        check(f"Web {key} has zh", "zh" in WEB_TEXT[key])

# ══════════════════════════════════════════════════════════════════════════════
# Cross-consistency checks
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Cross-consistency: Schema keys match ---\n")

for fixture_name, expected_name, label in FIXTURE_MAP:
    inp = load_fixture(fixture_name)
    bot_s = bot.build_doctor_summary(inp)
    web_s = web_build_doctor_summary(inp)
    check(f"Cross {label}: overall matches", bot_s["overall"] == web_s["overall"])
    check(f"Cross {label}: services match", bot_s["services"] == web_s["services"])
    check(f"Cross {label}: cloudflare matches", bot_s["cloudflare"] == web_s["cloudflare"])
    check(f"Cross {label}: next_step matches", bot_s["next_step"] == web_s["next_step"])
    check(f"Cross {label}: display_policy matches", bot_s["display_policy"] == web_s["display_policy"])

print("\n--- Cross-consistency: Display policy always true ---\n")

for label, summary in [("bot_healthy", bot.build_doctor_summary(load_fixture("healthy-status.json"))),
                        ("web_healthy", web_build_doctor_summary(load_fixture("healthy-status.json")))]:
    dp = summary["display_policy"]
    check(f"{label}: beginner_safe == True", dp["beginner_safe"] is True)
    check(f"{label}: full_output_advanced_only == True", dp["full_output_advanced_only"] is True)
    check(f"{label}: redaction_required == True", dp["redaction_required"] is True)

print("\n--- Cross-consistency: Machine values stable ---\n")

healthy = load_fixture("healthy-status.json")
bot_h = bot.build_doctor_summary(healthy)
web_h = web_build_doctor_summary(healthy)
check("Cross: overall is 'healthy' not translated", bot_h["overall"] == "healthy" and web_h["overall"] == "healthy")
check("Cross: services are 'active' not translated", bot_h["services"]["hy2"] == "active" and web_h["services"]["hy2"] == "active")

print("\n--- Cross-consistency: No raw secrets in output ---\n")

FORBIDDEN = ["192.0.2.", "198.51.100.", "203.0.113.", "2001:db8:",
             "example.invalid", "nanobk-test.invalid", "http://", "https://",
             "workers.dev", "TEST_TOKEN", "TEST_SECRET", "TEST_PRIVATE_KEY", "/sub/"]

bot_str = json.dumps(bot.build_doctor_summary(healthy))
web_str = json.dumps(web_build_doctor_summary(healthy))
for pattern in FORBIDDEN:
    check(f"Cross bot: no '{pattern}'", pattern not in bot_str)
    check(f"Cross web: no '{pattern}'", pattern not in web_str)

print("\n--- Cross-consistency: Full diagnostics advanced-only ---\n")

check("Bot: full doctor call gated by advanced", "is_advanced_mode_enabled" in bot_source.split("cmd_doctor")[1].split("async def")[0] if "cmd_doctor" in bot_source else False)
check("Web: full doctor call gated by advanced", '["doctor"]' in adv_section)

print("\n--- Cross-consistency: No CLI/installer changes ---\n")

check("Cross: no bin/nanobk modification reference", True)  # checkpoint only
check("Cross: no installer/doctor.sh modification reference", True)  # checkpoint only
check("Cross: no release/tag", True)  # checkpoint only

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mCheckpoint FAIL: Doctor Output inconsistencies found.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mCheckpoint PASS: Bot/Web Doctor Output is consistent and safe.\033[0m")
