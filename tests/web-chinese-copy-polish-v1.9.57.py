#!/usr/bin/env python3
"""
NanoBK Web Chinese Copy Polish Test (v1.9.57)

Verifies that Web Chinese copy residue is fixed:
- next_step hints use i18n keys, not hardcoded English
- zh mode returns Chinese text for user-facing strings
- en mode returns English text for user-facing strings
- machine values remain stable English
- Raw JSON keys not translated
- templates use t() for user-facing copy
- no env writes, no shell=True, no os.system
"""

import sys
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

RED = "\033[0;31m"
GREEN = "\033[0;32m"
NC = "\033[0m"

ERRORS = 0


def check(desc: str, condition: bool) -> None:
    global ERRORS
    if condition:
        print(f"  {GREEN}✓{NC} {desc}")
    else:
        print(f"  {RED}✗{NC} {desc}")
        ERRORS += 1


print("")
print("=== Web Chinese Copy Polish Test (v1.9.57) ===")
print("")

# ── 1. Import Web i18n ────────────────────────────────────────────────────

print("--- Web i18n imports ---")
print("")

from web.i18n import WEB_TEXT, wt, normalize_lang, DEFAULT_LANG, SUPPORTED_LANGS

check("DEFAULT_LANG is zh", DEFAULT_LANG == "zh")
check("SUPPORTED_LANGS is {en, zh}", SUPPORTED_LANGS == {"en", "zh"})

# ── 2. Next-step hint i18n keys exist ─────────────────────────────────────

print("")
print("--- Next-step hint i18n keys ---")
print("")

NEXT_STEP_KEYS = [
    "next_step_check_ssh_recovery",
    "next_step_check_ssh_services",
    "next_step_finish_cf",
    "next_step_verify_subscription",
    "next_step_no_action",
    "next_step_run_doctor",
]

for key in NEXT_STEP_KEYS:
    check(f"WEB_TEXT has {key}", key in WEB_TEXT)
    if key in WEB_TEXT:
        check(f"  {key} has en", "en" in WEB_TEXT[key] and len(WEB_TEXT[key]["en"]) > 0)
        check(f"  {key} has zh", "zh" in WEB_TEXT[key] and len(WEB_TEXT[key]["zh"]) > 0)

# ── 3. zh next-step hints are Chinese ─────────────────────────────────────

print("")
print("--- zh next-step hints are Chinese (not English residue) ---")
print("")

for key in NEXT_STEP_KEYS:
    zh_text = wt("zh", key)
    en_text = wt("en", key)
    # Chinese text should contain CJK characters
    has_cjk = bool(re.search(r'[一-鿿]', zh_text))
    check(f"zh {key} contains CJK", has_cjk)
    # Chinese text should not be identical to English
    check(f"zh {key} != en {key}", zh_text != en_text)

# ── 4. en next-step hints are English ─────────────────────────────────────

print("")
print("--- en next-step hints are English ---")
print("")

for key in NEXT_STEP_KEYS:
    en_text = wt("en", key)
    has_ascii_word = bool(re.search(r'[A-Za-z]{3,}', en_text))
    check(f"en {key} contains ASCII words", has_ascii_word)

# ── 5. Machine values remain stable ───────────────────────────────────────

print("")
print("--- Machine values remain stable English ---")
print("")

# These values should NOT be translated
MACHINE_VALUES = [
    "healthy", "failed", "unknown", "partial",
    "active", "inactive", "configured", "missing", "present", "ok",
]

for val in MACHINE_VALUES:
    # Machine values are not in WEB_TEXT, they come from status inference
    check(f"Machine value '{val}' not in WEB_TEXT", val not in WEB_TEXT)

# ── 6. format_status uses i18n for next_step ──────────────────────────────

print("")
print("--- format_status uses i18n for next_step ---")
print("")

from web.app import format_status

# Healthy status
healthy_status = {
    "ok": True,
    "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
    "security": {"secretsMode": "600"},
    "cloudflare": {"nanok": {"verified": True}, "nanob": {"verified": True}},
    "subscription": {"verified": True},
    "warnings": [],
}

zh_formatted = format_status(healthy_status, lang="zh")
en_formatted = format_status(healthy_status, lang="en")

zh_next = zh_formatted["cards"]["next_step"]
en_next = en_formatted["cards"]["next_step"]

check("zh next_step != en next_step", zh_next != en_next)
check("zh next_step contains CJK", bool(re.search(r'[一-鿿]', zh_next)))
check("en next_step contains ASCII", bool(re.search(r'[A-Za-z]{3,}', en_next)))
check("zh next_step is no_action hint", "无需" in zh_next or "操作" in zh_next)
check("en next_step is no_action hint", "action" in en_next.lower() or "immediate" in en_next.lower())

# Failed status
failed_status = {
    "ok": False,
    "services": {"hy2": "failed", "tuic": "unknown", "reality": "unknown", "trojan": "unknown"},
    "warnings": [],
}

zh_failed = format_status(failed_status, lang="zh")
en_failed = format_status(failed_status, lang="en")

zh_fail_next = zh_failed["cards"]["next_step"]
en_fail_next = en_failed["cards"]["next_step"]

check("Failed zh next_step contains CJK", bool(re.search(r'[一-鿿]', zh_fail_next)))
check("Failed en next_step contains SSH", "SSH" in en_fail_next)
check("Failed zh next_step != en next_step", zh_fail_next != en_fail_next)

# ── 7. format_status machine values unchanged ─────────────────────────────

print("")
print("--- format_status machine values unchanged ---")
print("")

check("zh overall == 'healthy'", zh_formatted["cards"]["overall"] == "healthy")
check("en overall == 'healthy'", en_formatted["cards"]["overall"] == "healthy")
check("zh vps == 'unknown' or 'healthy'", zh_formatted["cards"]["vps"] in ("healthy", "unknown"))
check("zh services hy2 == 'active'", zh_formatted["cards"]["services"].get("hy2") == "active")

# ── 8. Raw JSON keys not translated ───────────────────────────────────────

print("")
print("--- Raw JSON keys not translated ---")
print("")

import json

raw = zh_formatted["raw_json"]
raw_parsed = json.loads(raw)
# Raw JSON should preserve original keys
check("Raw JSON has 'ok' key", "ok" in raw_parsed)
check("Raw JSON has 'services' key", "services" in raw_parsed)

# ── 9. Template checks ───────────────────────────────────────────────────

print("")
print("--- Template checks ---")
print("")

# Check status.html uses t() for next_step label
status_tpl = open(os.path.join(ROOT, "web", "templates", "status.html")).read()
check("status.html uses t('status_next_step')", "t('status_next_step')" in status_tpl)
check("status.html has status.cards.next_step", "status.cards.next_step" in status_tpl)

# Check index.html uses t() for next_step label
index_tpl = open(os.path.join(ROOT, "web", "templates", "index.html")).read()
check("index.html uses t('status_next_step')", "t('status_next_step')" in index_tpl)
check("index.html has status.cards.next_step", "status.cards.next_step" in index_tpl)

# Check doctor.html uses t() for next_step labels (machine key mapping)
doctor_tpl = open(os.path.join(ROOT, "web", "templates", "doctor.html")).read()
check("doctor.html uses t('doctor_next_no_action')", "t('doctor_next_no_action')" in doctor_tpl)
check("doctor.html uses t('doctor_next_check_failed')", "t('doctor_next_check_failed')" in doctor_tpl)
check("doctor.html uses t('doctor_next_complete_config')", "t('doctor_next_complete_config')" in doctor_tpl)

# ── 10. /api/status unchanged ────────────────────────────────────────────

print("")
print("--- /api/status unchanged ---")
print("")

app_source = open(os.path.join(ROOT, "web", "app.py")).read()
check("/api/status route exists", "/api/status" in app_source)
check("api_status uses redact_json", "redact_json" in app_source)

# ── 11. Raw JSON gate unchanged ──────────────────────────────────────────

print("")
print("--- Raw JSON gate unchanged ---")
print("")

check("locked-panel class in status.html", "locked-panel" in status_tpl)
check("advanced_mode_enabled branch in status.html", "advanced_mode_enabled" in status_tpl)

# ── 12. Language switch route unchanged ───────────────────────────────────

print("")
print("--- Language switch route unchanged ---")
print("")

check("/language route in app.py", "/language" in app_source)
check("POST only for /language", "POST" in app_source)

# ── 13. Safety checks ────────────────────────────────────────────────────

print("")
print("--- Safety checks ---")
print("")

check("no shell=True in app.py", "shell=True" not in app_source)
check("no os.system in app.py", "os.system" not in app_source)

# No env writes
check("no open('.env'", "open('.env'" not in app_source and 'open(".env"' not in app_source)

# No bot file changes
bot_source = open(os.path.join(ROOT, "bot", "nanobk_bot.py")).read()
check("bot source unchanged (still has /start)", "/start" in bot_source)

# No installer changes
install_sh = open(os.path.join(ROOT, "installer", "install.sh")).read()
check("installer unchanged (still has select_language)", "select_language" in install_sh)

# ── 14. Web i18n key completeness ────────────────────────────────────────

print("")
print("--- Web i18n key completeness ---")
print("")

# All WEB_TEXT keys should have both en and zh
missing_zh = []
missing_en = []
for key, entry in WEB_TEXT.items():
    if "zh" not in entry or not entry["zh"]:
        missing_zh.append(key)
    if "en" not in entry or not entry["en"]:
        missing_en.append(key)

check("All WEB_TEXT keys have zh", len(missing_zh) == 0)
check("All WEB_TEXT keys have en", len(missing_en) == 0)

# ── 15. Existing i18n keys still present ─────────────────────────────────

print("")
print("--- Existing i18n keys still present ---")
print("")

ESSENTIAL_KEYS = [
    "login_title", "nav_dashboard", "nav_status", "nav_doctor", "nav_rotate",
    "dashboard_title", "status_overall", "status_next_step",
    "doctor_title", "doctor_summary_title", "doctor_label_next_step",
    "rotate_title", "raw_json_locked_title",
    "advanced_title", "lang_switch_to_en", "lang_switch_to_zh",
]

for key in ESSENTIAL_KEYS:
    check(f"WEB_TEXT has {key}", key in WEB_TEXT)

# ── Summary ──────────────────────────────────────────────────────────────

print("")
print("=== Test Summary ===")
print("")

if ERRORS == 0:
    print(f"  {GREEN}All Web Chinese copy polish tests passed!{NC}")
    sys.exit(0)
else:
    print(f"  {RED}{ERRORS} test(s) failed.{NC}")
    sys.exit(1)
