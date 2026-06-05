#!/usr/bin/env python3
"""
Test: Web Doctor Summary Minimal Implementation (v1.9.37)

Verifies:
- build_doctor_summary() conforms to v1.9.35 contract
- /doctor uses --json status for summary
- Advanced mode gates full diagnostics
- i18n keys exist for en/zh
- No raw secrets in output
- No Bot files changed
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

# Import web module
from web.app import build_doctor_summary, format_status, safe_output
from web.i18n import wt, WEB_TEXT

# Read source
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()

# Read fixtures
FIXTURES_DIR = os.path.join(REPO_DIR, "tests", "fixtures", "doctor-summary-v1.9.35")

def load_fixture(name):
    with open(os.path.join(FIXTURES_DIR, name)) as f:
        return json.load(f)

print("=== Web Doctor Summary Test (v1.9.37) ===\n")

# ══════════════════════════════════════════════════════════════════════════════
# 1. build_doctor_summary with fixtures
# ══════════════════════════════════════════════════════════════════════════════

print("--- build_doctor_summary with fixtures ---\n")

# Healthy
healthy_input = load_fixture("healthy-status.json")
healthy_expected = load_fixture("expected-healthy-summary.json")
healthy_actual = build_doctor_summary(healthy_input)
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
partial_actual = build_doctor_summary(partial_input)
check("partial: overall matches", partial_actual["overall"] == partial_expected["overall"])
check("partial: tuic matches", partial_actual["services"]["tuic"] == partial_expected["services"]["tuic"])
check("partial: trojan matches", partial_actual["services"]["trojan"] == partial_expected["services"]["trojan"])
check("partial: next_step matches", partial_actual["next_step"] == partial_expected["next_step"])

# Missing config
missing_input = load_fixture("missing-config-status.json")
missing_expected = load_fixture("expected-missing-config-summary.json")
missing_actual = build_doctor_summary(missing_input)
check("missing: overall matches", missing_actual["overall"] == missing_expected["overall"])
check("missing: config matches", missing_actual["config"] == missing_expected["config"])
check("missing: profile matches", missing_actual["profile"] == missing_expected["profile"])
check("missing: next_step matches", missing_actual["next_step"] == missing_expected["next_step"])

# Cloudflare missing
cf_input = load_fixture("cloudflare-missing-status.json")
cf_expected = load_fixture("expected-cloudflare-missing-summary.json")
cf_actual = build_doctor_summary(cf_input)
check("cf_missing: overall matches", cf_actual["overall"] == cf_expected["overall"])
check("cf_missing: cloudflare matches", cf_actual["cloudflare"] == cf_expected["cloudflare"])
check("cf_missing: next_step matches", cf_actual["next_step"] == cf_expected["next_step"])

# Unknown/empty
unknown_expected = load_fixture("expected-unknown-summary.json")
unknown_actual = build_doctor_summary({})
check("unknown: overall matches", unknown_actual["overall"] == unknown_expected["overall"])
check("unknown: all services unknown", all(v == "unknown" for v in unknown_actual["services"].values()))
check("unknown: next_step matches", unknown_actual["next_step"] == unknown_expected["next_step"])

# None input
none_actual = build_doctor_summary(None)
check("none input: overall == unknown", none_actual["overall"] == "unknown")

# ══════════════════════════════════════════════════════════════════════════════
# 2. Summary safety
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Summary safety ---\n")

FORBIDDEN = ["192.0.2.", "198.51.100.", "203.0.113.", "2001:db8:",
             "example.invalid", "http://", "https://", "workers.dev",
             "TEST_TOKEN", "TEST_SECRET", "TEST_PRIVATE_KEY", "/sub/"]

summary_str = json.dumps(healthy_actual)
for pattern in FORBIDDEN:
    check(f"summary: no '{pattern}'", pattern not in summary_str)

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

doctor_section = web_source.split("def doctor():")[1].split("def ")[0] if "def doctor():" in web_source else ""
check("doctor route uses --json status", '"--json", "status"' in doctor_section)
check("doctor route uses build_doctor_summary", "build_doctor_summary" in doctor_section)
check("doctor route checks advanced mode", "is_advanced_mode_enabled" in doctor_section)
check("doctor route uses safe_output for full output", "safe_output" in doctor_section)

# Advanced OFF does not run nanobk doctor before gate
# The full doctor call should only happen inside the advanced mode check
adv_section = doctor_section.split("if adv_enabled")[1] if "if adv_enabled" in doctor_section else ""
check("full doctor call is after advanced gate", '["doctor"]' in adv_section)

# Login required
check("doctor route has @require_login", "@require_login" in web_source.split("def doctor():")[0][-100:])

# CSRF required
check("doctor POST checks CSRF", "validate_csrf()" in doctor_section)

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
    "doctor_full_details_label", "doctor_status_parse_error", "doctor_full_unavailable",
    "doctor_intro_text",
]

for key in doctor_keys:
    check(f"WEB_TEXT has {key}", key in WEB_TEXT)
    if key in WEB_TEXT:
        check(f"{key} has en", "en" in WEB_TEXT[key])
        check(f"{key} has zh", "zh" in WEB_TEXT[key])

# ══════════════════════════════════════════════════════════════════════════════
# 6. Template checks
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Template ---\n")

with open(os.path.join(REPO_DIR, "web", "templates", "doctor.html")) as f:
    doctor_tpl = f.read()

check("template has summary title", "doctor_summary_title" in doctor_tpl)
check("template has summary cards", "summary.overall" in doctor_tpl)
check("template has services loop", "summary.services" in doctor_tpl)
check("template has advanced mode check", "advanced_mode_enabled" in doctor_tpl)
check("template has full output details", "full_output" in doctor_tpl)
check("template has details tag", "<details" in doctor_tpl)
check("template has warning box", "warning-box" in doctor_tpl or "doctor_full_warning" in doctor_tpl)
check("template has CSRF form", "csrf_token" in doctor_tpl)
check("template uses t()", "{{ t(" in doctor_tpl)
check("template has locked-panel for advanced note", "locked-panel" in doctor_tpl)

# ══════════════════════════════════════════════════════════════════════════════
# 7. /api/status unchanged
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- /api/status unchanged ---\n")

check("/api/status route exists", '"/api/status"' in web_source)
check("api_status uses redact_json", "redact_json(data)" in web_source)
api_section = web_source.split("def api_status():")[1].split("def ")[0] if "def api_status():" in web_source else ""
check("/api/status not gated by advanced", "is_advanced_mode_enabled" not in api_section)

# ══════════════════════════════════════════════════════════════════════════════
# 8. Raw JSON gating unchanged
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Raw JSON gating unchanged ---\n")

with open(os.path.join(REPO_DIR, "web", "templates", "status.html")) as f:
    status_tpl = f.read()

check("status template branches on advanced_mode_enabled", "advanced_mode_enabled" in status_tpl)
check("status template has locked panel", "locked-panel" in status_tpl)
check("status template has raw_json", "status.raw_json" in status_tpl)

# ══════════════════════════════════════════════════════════════════════════════
# 9. Safety checks
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Safety ---\n")

check("no shell=True in web", "shell=True" not in web_source)
check("no os.system in web", "os.system" not in web_source)
check("shared redaction import", "from lib.nanobk_redaction import" in web_source)
check("run_nanobk present", "def run_nanobk" in web_source)
check("safe_output present", "def safe_output" in web_source)

# ══════════════════════════════════════════════════════════════════════════════
# 10. No Bot changes
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- No Bot changes ---\n")

with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()
check("Bot has build_doctor_summary", "def build_doctor_summary" in bot_source)
check("Bot has format_doctor_summary", "def format_doctor_summary" in bot_source)
check("Bot /doctor registered", 'CommandHandler("doctor"' in bot_source)

# ══════════════════════════════════════════════════════════════════════════════
# 11. Honesty rules
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Honesty rules ---\n")

# Unknown stays unknown
unk = build_doctor_summary({})
check("honesty: unknown overall stays unknown", unk["overall"] == "unknown")
check("honesty: unknown services stay unknown", all(v == "unknown" for v in unk["services"].values()))

# Missing config not healthy
miss = build_doctor_summary({"ok": None, "warnings": ["Config directory not found"]})
check("honesty: missing config not healthy", miss["overall"] != "healthy")

# Partial not healthy
part = build_doctor_summary({"ok": False, "services": {"hy2": "active", "tuic": "failed", "reality": "active", "trojan": "active"}})
check("honesty: partial not healthy", part["overall"] != "healthy")

# CF missing not verified
cf_miss = build_doctor_summary({"ok": True, "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"}, "cloudflare": {"nanok": {"envExists": False}, "nanob": {"envExists": False}}})
check("honesty: cf missing not verified", cf_miss["cloudflare"] != "verified")

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mTest FAIL.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mTest PASS: Web Doctor Summary implementation is correct and safe.\033[0m")
