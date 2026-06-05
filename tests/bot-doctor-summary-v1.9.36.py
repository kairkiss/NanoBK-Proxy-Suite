#!/usr/bin/env python3
"""
Test: Bot Doctor Summary Minimal Implementation (v1.9.36)

Verifies:
- build_doctor_summary() conforms to v1.9.35 contract
- format_doctor_summary() produces safe output
- /doctor uses --json status for summary
- Advanced mode gates full diagnostics
- i18n keys exist for en/zh
- No raw secrets in output
- No Web files changed
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

# Import bot module
import bot.nanobk_bot as bot

# Read source
with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()

# Read fixtures
FIXTURES_DIR = os.path.join(REPO_DIR, "tests", "fixtures", "doctor-summary-v1.9.35")

def load_fixture(name):
    with open(os.path.join(FIXTURES_DIR, name)) as f:
        return json.load(f)

def load_text_fixture(name):
    with open(os.path.join(FIXTURES_DIR, name)) as f:
        return f.read()

print("=== Bot Doctor Summary Test (v1.9.36) ===\n")

# ══════════════════════════════════════════════════════════════════════════════
# 1. build_doctor_summary with fixtures
# ══════════════════════════════════════════════════════════════════════════════

print("--- build_doctor_summary with fixtures ---\n")

# Healthy
healthy_input = load_fixture("healthy-status.json")
healthy_expected = load_fixture("expected-healthy-summary.json")
healthy_actual = bot.build_doctor_summary(healthy_input)
check("healthy: overall matches", healthy_actual["overall"] == healthy_expected["overall"])
check("healthy: control_plane matches", healthy_actual["control_plane"] == healthy_expected["control_plane"])
check("healthy: cli matches", healthy_actual["cli"] == healthy_expected["cli"])
check("healthy: profile matches", healthy_actual["profile"] == healthy_expected["profile"])
check("healthy: config matches", healthy_actual["config"] == healthy_expected["config"])
check("healthy: services match", healthy_actual["services"] == healthy_expected["services"])
check("healthy: cloudflare matches", healthy_actual["cloudflare"] == healthy_expected["cloudflare"])
check("healthy: subscription matches", healthy_actual["subscription"] == healthy_expected["subscription"])
check("healthy: security matches", healthy_actual["security"] == healthy_expected["security"])
check("healthy: next_step matches", healthy_actual["next_step"] == healthy_expected["next_step"])
check("healthy: display_policy matches", healthy_actual["display_policy"] == healthy_expected["display_policy"])

# Partial services
partial_input = load_fixture("partial-services-status.json")
partial_expected = load_fixture("expected-partial-services-summary.json")
partial_actual = bot.build_doctor_summary(partial_input)
check("partial: overall matches", partial_actual["overall"] == partial_expected["overall"])
check("partial: tuic matches", partial_actual["services"]["tuic"] == partial_expected["services"]["tuic"])
check("partial: trojan matches", partial_actual["services"]["trojan"] == partial_expected["services"]["trojan"])
check("partial: next_step matches", partial_actual["next_step"] == partial_expected["next_step"])

# Missing config
missing_input = load_fixture("missing-config-status.json")
missing_expected = load_fixture("expected-missing-config-summary.json")
missing_actual = bot.build_doctor_summary(missing_input)
check("missing: overall matches", missing_actual["overall"] == missing_expected["overall"])
check("missing: config matches", missing_actual["config"] == missing_expected["config"])
check("missing: profile matches", missing_actual["profile"] == missing_expected["profile"])
check("missing: next_step matches", missing_actual["next_step"] == missing_expected["next_step"])

# Cloudflare missing
cf_input = load_fixture("cloudflare-missing-status.json")
cf_expected = load_fixture("expected-cloudflare-missing-summary.json")
cf_actual = bot.build_doctor_summary(cf_input)
check("cf_missing: overall matches", cf_actual["overall"] == cf_expected["overall"])
check("cf_missing: cloudflare matches", cf_actual["cloudflare"] == cf_expected["cloudflare"])
check("cf_missing: next_step matches", cf_actual["next_step"] == cf_expected["next_step"])

# Unknown/empty
unknown_expected = load_fixture("expected-unknown-summary.json")
unknown_actual = bot.build_doctor_summary({})
check("unknown: overall matches", unknown_actual["overall"] == unknown_expected["overall"])
check("unknown: all services unknown", all(v == "unknown" for v in unknown_actual["services"].values()))
check("unknown: next_step matches", unknown_actual["next_step"] == unknown_expected["next_step"])

# None input
none_actual = bot.build_doctor_summary(None)
check("none input: overall == unknown", none_actual["overall"] == "unknown")

# ══════════════════════════════════════════════════════════════════════════════
# 2. format_doctor_summary safety
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- format_doctor_summary safety ---\n")

FORBIDDEN = ["192.0.2.", "198.51.100.", "203.0.113.", "2001:db8:",
             "example.invalid", "http://", "https://", "workers.dev",
             "TEST_TOKEN", "TEST_SECRET", "TEST_PRIVATE_KEY", "/sub/"]

formatted_en = bot.format_doctor_summary(healthy_actual, lang="en")
formatted_zh = bot.format_doctor_summary(healthy_actual, lang="zh")

for pattern in FORBIDDEN:
    check(f"en summary: no '{pattern}'", pattern not in formatted_en)
    check(f"zh summary: no '{pattern}'", pattern not in formatted_zh)

check("en summary has title", "Doctor Summary" in formatted_en)
check("en summary has overall", "Overall:" in formatted_en)
check("en summary has services", "HY2:" in formatted_en)
check("en summary has next step", "Next step:" in formatted_en)
check("zh summary has title", "诊断摘要" in formatted_zh)
check("zh summary has overall", "总览" in formatted_zh)
check("zh summary has services", "HY2:" in formatted_zh)

# ══════════════════════════════════════════════════════════════════════════════
# 3. Display policy always true
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Display policy ---\n")

for name, summary in [("healthy", healthy_actual), ("partial", partial_actual),
                       ("missing", missing_actual), ("cf_missing", cf_actual),
                       ("unknown", unknown_actual)]:
    dp = summary.get("display_policy", {})
    check(f"{name}: beginner_safe == True", dp.get("beginner_safe") is True)
    check(f"{name}: full_output_advanced_only == True", dp.get("full_output_advanced_only") is True)
    check(f"{name}: redaction_required == True", dp.get("redaction_required") is True)

# ══════════════════════════════════════════════════════════════════════════════
# 4. /doctor source behavior
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- /doctor source behavior ---\n")

# cmd_doctor uses --json status for summary
doctor_section = bot_source.split("async def cmd_doctor")[1].split("async def")[0] if "async def cmd_doctor" in bot_source else ""
check("cmd_doctor uses --json status", '"--json", "status"' in doctor_section)
check("cmd_doctor uses build_doctor_summary", "build_doctor_summary" in doctor_section)
check("cmd_doctor uses format_doctor_summary", "format_doctor_summary" in doctor_section)

# Advanced OFF does not run nanobk doctor before gate
# The full doctor call should only happen inside the advanced mode check
check("cmd_doctor checks advanced mode", "is_advanced_mode_enabled" in doctor_section)
# The nanobk doctor call should be inside the advanced block
adv_section = doctor_section.split("is_advanced_mode_enabled")[1] if "is_advanced_mode_enabled" in doctor_section else ""
check("full doctor call is after advanced gate", '["doctor"]' in adv_section)

# Advanced ON path uses safe_output
check("advanced path uses safe_output", "safe_output" in adv_section)

# Owner-only remains
check("cmd_doctor checks is_owner", "is_owner" in doctor_section)

# ══════════════════════════════════════════════════════════════════════════════
# 5. i18n keys
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- i18n keys ---\n")

doctor_keys = [
    "doctor_summary_title", "doctor_label_overall", "doctor_label_control_plane",
    "doctor_label_cli", "doctor_label_profile", "doctor_label_config",
    "doctor_label_services", "doctor_label_cloudflare", "doctor_label_subscription",
    "doctor_label_security", "doctor_label_next_step", "doctor_label_errors",
    "doctor_label_warnings", "doctor_next_no_action", "doctor_next_check_failed",
    "doctor_next_complete_config", "doctor_next_configure_cf", "doctor_next_use_advanced",
    "doctor_next_unknown", "doctor_full_note", "doctor_full_warning",
    "doctor_status_parse_error", "doctor_full_unavailable",
]

for key in doctor_keys:
    check(f"BOT_TEXT has {key}", key in bot.BOT_TEXT)
    if key in bot.BOT_TEXT:
        check(f"{key} has en", "en" in bot.BOT_TEXT[key])
        check(f"{key} has zh", "zh" in bot.BOT_TEXT[key])

# ══════════════════════════════════════════════════════════════════════════════
# 6. Slash command unchanged
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Slash command unchanged ---\n")

check("CommandHandler doctor registered", 'CommandHandler("doctor"' in bot_source)
check("cmd_doctor function exists", "async def cmd_doctor" in bot_source)

# ══════════════════════════════════════════════════════════════════════════════
# 7. Safety checks
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Safety ---\n")

check("no shell=True in bot", "shell=True" not in bot_source)
check("no os.system in bot", "os.system" not in bot_source)
check("shared redaction import", "from lib.nanobk_redaction import" in bot_source)
check("run_nanobk present", "def run_nanobk" in bot_source)
check("safe_output present", "def safe_output" in bot_source)

# ══════════════════════════════════════════════════════════════════════════════
# 8. No Web changes
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- No Web changes ---\n")

with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()
check("web /api/status still exists", '"/api/status"' in web_source)
check("web login route still exists", '"/login"' in web_source)
check("web validate_csrf still exists", "def validate_csrf" in web_source)

# ══════════════════════════════════════════════════════════════════════════════
# 9. Honesty rules
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Honesty rules ---\n")

# Unknown stays unknown
unk = bot.build_doctor_summary({})
check("honesty: unknown overall stays unknown", unk["overall"] == "unknown")
check("honesty: unknown services stay unknown", all(v == "unknown" for v in unk["services"].values()))

# Missing config not healthy
miss = bot.build_doctor_summary({"ok": None, "warnings": ["Config directory not found"]})
check("honesty: missing config not healthy", miss["overall"] != "healthy")

# Partial not healthy
part = bot.build_doctor_summary({"ok": False, "services": {"hy2": "active", "tuic": "failed", "reality": "active", "trojan": "active"}})
check("honesty: partial not healthy", part["overall"] != "healthy")

# CF missing not verified
cf_miss = bot.build_doctor_summary({"ok": True, "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"}, "cloudflare": {"nanok": {"envExists": False}, "nanob": {"envExists": False}}})
check("honesty: cf missing not verified", cf_miss["cloudflare"] != "verified")

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mTest FAIL.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mTest PASS: Bot Doctor Summary implementation is correct and safe.\033[0m")
