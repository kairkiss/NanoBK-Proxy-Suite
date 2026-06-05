#!/usr/bin/env python3
"""
Test: Bot/Web i18n Checkpoint (v1.9.32)

Verifies Bot/Web i18n consistency and safety after v1.9.30/v1.9.31.
Source-level tests + direct helper tests. No real server, no real nanobk,
no Telegram, no Cloudflare.

Usage:
    python3 tests/i18n-checkpoint-v1.9.32.py
"""

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

# ── Read sources ──────────────────────────────────────────────────────────────

with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()
with open(os.path.join(REPO_DIR, "web", "i18n.py")) as f:
    web_i18n_source = f.read()
with open(os.path.join(REPO_DIR, "web", "templates", "status.html")) as f:
    status_tpl = f.read()
with open(os.path.join(REPO_DIR, "web", "templates", "layout.html")) as f:
    layout_tpl = f.read()
with open(os.path.join(REPO_DIR, "web", "templates", "login.html")) as f:
    login_tpl = f.read()
with open(os.path.join(REPO_DIR, "web", "templates", "index.html")) as f:
    index_tpl = f.read()
with open(os.path.join(REPO_DIR, "web", "templates", "doctor.html")) as f:
    doctor_tpl = f.read()
with open(os.path.join(REPO_DIR, "web", "templates", "rotate.html")) as f:
    rotate_tpl = f.read()
with open(os.path.join(REPO_DIR, "tests", "bot-i18n-minimal-v1.9.30.py")) as f:
    bot_i18n_test = f.read()
with open(os.path.join(REPO_DIR, "tests", "web-i18n-minimal-v1.9.31.py")) as f:
    web_i18n_test = f.read()

# Import modules for runtime checks
import bot.nanobk_bot as bot
from web.i18n import normalize_lang as web_normalize_lang, wt, WEB_TEXT

print("=== Bot/Web i18n Checkpoint (v1.9.32) ===\n")

# ══════════════════════════════════════════════════════════════════════════════
# Bot i18n checks
# ══════════════════════════════════════════════════════════════════════════════

print("--- Bot: Language config ---\n")

check("Bot: SUPPORTED_LANGS exists", hasattr(bot, "SUPPORTED_LANGS"))
check("Bot: SUPPORTED_LANGS == {en, zh}", bot.SUPPORTED_LANGS == {"en", "zh"})
check("Bot: DEFAULT_LANG == en", bot.DEFAULT_LANG == "en")
check("Bot: normalize_lang(None) == en", bot.normalize_lang(None) == "en")
check("Bot: normalize_lang('') == en", bot.normalize_lang("") == "en")
check("Bot: normalize_lang('invalid') == en", bot.normalize_lang("invalid") == "en")
check("Bot: normalize_lang('zh') == zh", bot.normalize_lang("zh") == "zh")
check("Bot: normalize_lang('zh-cn') == zh", bot.normalize_lang("zh-cn") == "zh")
check("Bot: normalize_lang('zh_cn') == zh", bot.normalize_lang("zh_cn") == "zh")
check("Bot: normalize_lang('chinese') == zh", bot.normalize_lang("chinese") == "zh")
check("Bot: normalize_lang('中文') == zh", bot.normalize_lang("中文") == "zh")
check("Bot: BotConfig has lang field", "lang" in bot_source and "BotConfig" in bot_source)
check("Bot: BotConfig reads NANOBK_LANG", "NANOBK_LANG" in bot_source)
check("Bot: BotConfig uses normalize_lang", "normalize_lang(os.environ.get(\"NANOBK_LANG\"))" in bot_source)

print("\n--- Bot: Translation helper ---\n")

check("Bot: BOT_TEXT exists", hasattr(bot, "BOT_TEXT"))
check("Bot: bt() exists", callable(bot.bt))
check("Bot: bt en returns English", "NanoBK" in bot.bt("en", "control_center_title"))
check("Bot: bt zh returns Chinese", "控制中心" in bot.bt("zh", "control_center_title"))
check("Bot: bt fallback for missing key", bot.bt("en", "nonexistent_xyz") == "nonexistent_xyz")
check("Bot: bt fallback for missing lang", "NanoBK" in bot.bt("invalid_lang", "control_center_title"))
check("Bot: bt format kwargs work", "15" in bot.bt("en", "advanced_enabled_status", minutes=15))

print("\n--- Bot: Translated areas ---\n")

check("Bot: control center title zh/en", "控制中心" in bot.bt("zh", "control_center_title") and "Control Center" in bot.bt("en", "control_center_title"))
check("Bot: button labels zh/en", "状态总览" in bot.bt("zh", "btn_status") and "Status Summary" in bot.bt("en", "btn_status"))
check("Bot: help title zh/en", "机器人命令" in bot.bt("zh", "help_title") and "Bot Commands" in bot.bt("en", "help_title"))
check("Bot: status labels zh/en", "总览" in bot.bt("zh", "status_label_overall") and "Overall" in bot.bt("en", "status_label_overall"))
check("Bot: status_json warning zh/en", "脱敏" in bot.bt("zh", "status_json_warning") and "redacted" in bot.bt("en", "status_json_warning"))
check("Bot: gate_not_enabled zh/en", "未启用" in bot.bt("zh", "gate_not_enabled") and "not enabled" in bot.bt("en", "gate_not_enabled"))
check("Bot: advanced_on_msg zh/en", "已启用" in bot.bt("zh", "advanced_on_msg") and "enabled" in bot.bt("en", "advanced_on_msg"))
check("Bot: guidance_recovery zh/en", "恢复" in bot.bt("zh", "guidance_recovery") and "Recovery" in bot.bt("en", "guidance_recovery"))
check("Bot: guidance_rotate zh/en", "轮换" in bot.bt("zh", "guidance_rotate") and "Rotate" in bot.bt("en", "guidance_rotate"))
check("Bot: guidance_web zh/en", "面板" in bot.bt("zh", "guidance_web") and "Web Panel" in bot.bt("en", "guidance_web"))

print("\n--- Bot: Slash commands unchanged ---\n")

check("Bot: /start registered", 'CommandHandler("start"' in bot_source)
check("Bot: /help registered", 'CommandHandler("help"' in bot_source)
check("Bot: /status registered", 'CommandHandler("status"' in bot_source)
check("Bot: /status_json registered", 'CommandHandler("status_json"' in bot_source)
check("Bot: /doctor registered", 'CommandHandler("doctor"' in bot_source)
check("Bot: /advanced registered", 'CommandHandler("advanced"' in bot_source)
check("Bot: /cancel registered", 'CommandHandler("cancel"' in bot_source)
check("Bot: rotate handlers loop", "for action_name in ROTATE_ACTIONS" in bot_source)
check("Bot: CallbackQueryHandler registered", "CallbackQueryHandler" in bot_source)

print("\n--- Bot: Status values stable ---\n")

check("Bot: format_status returns healthy for ok=True", "healthy" in bot.format_status({"ok": True, "services": {"hy2": "active"}}, lang="zh"))
check("Bot: format_status returns unknown for {}", "unknown" in bot.format_status({}, lang="en"))
check("Bot: format_status returns failed for ok=False", "failed" in bot.format_status({"ok": False}, lang="zh"))
check("Bot: status category values not translated (healthy)", "healthy" in bot.format_status({"ok": True}, lang="zh"))
check("Bot: status category values not translated (active)", "active" in bot.format_status({"ok": True, "services": {"hy2": "active"}}, lang="zh"))

print("\n--- Bot: /status_json gate unchanged ---\n")

status_json_section = bot_source.split("async def cmd_status_json")[1].split("async def")[0] if "async def cmd_status_json" in bot_source else ""
check("Bot: cmd_status_json checks is_advanced_mode_enabled", "is_advanced_mode_enabled" in status_json_section)
check("Bot: off-state guidance exists", "not is_advanced_mode_enabled" in status_json_section)
check("Bot: off-state calls run_nanobk only after gate", status_json_section.index("is_advanced_mode_enabled") < status_json_section.index("run_nanobk") if "run_nanobk" in status_json_section else False)

print("\n--- Bot: Advanced mode unchanged ---\n")

check("Bot: enable_advanced_mode exists", "def enable_advanced_mode" in bot_source)
check("Bot: disable_advanced_mode exists", "def disable_advanced_mode" in bot_source)
check("Bot: is_advanced_mode_enabled exists", "def is_advanced_mode_enabled" in bot_source)
check("Bot: ADVANCED_MODE_TTL_SECONDS is 900", "ADVANCED_MODE_TTL_SECONDS = 15 * 60" in bot_source)

print("\n--- Bot: Callbacks owner-only ---\n")

callback_func = bot_source.split("async def handle_menu_callback")[1].split("# ── Build application")[0] if "async def handle_menu_callback" in bot_source else ""
check("Bot: callback checks owner_id", "config.owner_id" in callback_func)
check("Bot: callback nanobk: prefix", 'pattern=r"^nanobk:"' in bot_source)

print("\n--- Bot: No raw URLs/secrets in BOT_TEXT ---\n")

bot_text_str = str(bot.BOT_TEXT)
check("Bot: no TOKEN= in BOT_TEXT", "TOKEN=" not in bot_text_str)
check("Bot: no SECRET= in BOT_TEXT", "SECRET=" not in bot_text_str)
check("Bot: no PRIVATE_KEY= in BOT_TEXT", "PRIVATE_KEY=" not in bot_text_str)
check("Bot: no workers.dev in BOT_TEXT", "workers.dev" not in bot_text_str)
check("Bot: no http:// in BOT_TEXT", "http://" not in bot_text_str)
check("Bot: no https:// in BOT_TEXT", "https://" not in bot_text_str)
check("Bot: no raw IP in BOT_TEXT", "203.0.113" not in bot_text_str)

print("\n--- Bot: Safety ---\n")

check("Bot: no shell=True", "shell=True" not in bot_source)
check("Bot: no os.system", "os.system" not in bot_source)
check("Bot: shared redaction import", "from lib.nanobk_redaction import" in bot_source)
check("Bot: run_nanobk present", "def run_nanobk" in bot_source)
check("Bot: ConfirmationManager present", "ConfirmationManager" in bot_source)

# ══════════════════════════════════════════════════════════════════════════════
# Web i18n checks
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Web: Language config ---\n")

check("Web: web/i18n.py exists", os.path.exists(os.path.join(REPO_DIR, "web", "i18n.py")))
check("Web: SUPPORTED_LANGS exists in i18n.py", "SUPPORTED_LANGS" in web_i18n_source)
check("Web: SUPPORTED_LANGS == {en, zh}", '{"en", "zh"}' in web_i18n_source)
check("Web: DEFAULT_LANG == en", '"en"' in web_i18n_source and "DEFAULT_LANG" in web_i18n_source)
check("Web: normalize_lang(None) == en", web_normalize_lang(None) == "en")
check("Web: normalize_lang('') == en", web_normalize_lang("") == "en")
check("Web: normalize_lang('invalid') == en", web_normalize_lang("invalid") == "en")
check("Web: normalize_lang('zh') == zh", web_normalize_lang("zh") == "zh")
check("Web: normalize_lang('zh-cn') == zh", web_normalize_lang("zh-cn") == "zh")
check("Web: normalize_lang('zh_cn') == zh", web_normalize_lang("zh_cn") == "zh")
check("Web: normalize_lang('chinese') == zh", web_normalize_lang("chinese") == "zh")
check("Web: normalize_lang('中文') == zh", web_normalize_lang("中文") == "zh")
check("Web: WebConfig has lang field", "lang" in web_source and "WebConfig" in web_source)
check("Web: WebConfig reads NANOBK_LANG", "NANOBK_LANG" in web_source)
check("Web: WebConfig uses normalize_lang", "normalize_lang(os.environ.get(\"NANOBK_LANG\"))" in web_source)

print("\n--- Web: Translation helper ---\n")

check("Web: WEB_TEXT exists in i18n.py", hasattr(WEB_TEXT, "get"))
check("Web: wt() exists", callable(wt))
check("Web: wt en returns English", "NanoBK Web Panel" in wt("en", "login_title"))
check("Web: wt zh returns Chinese", "NanoBK Web 面板" in wt("zh", "login_title"))
check("Web: wt fallback for missing key", wt("en", "nonexistent_xyz") == "nonexistent_xyz")
check("Web: wt fallback for missing lang", "NanoBK" in wt("invalid_lang", "login_title"))
check("Web: wt format kwargs work", "TUIC" in wt("en", "rotate_confirm_desc", protocol="TUIC"))

print("\n--- Web: Translated templates ---\n")

check("Web: app.py imports normalize_lang/wt", "from web.i18n import normalize_lang, wt" in web_source)
check("Web: context processor injects t()", "inject_i18n" in web_source)
check("Web: context processor returns t lambda", "lambda key" in web_source)
check("Web: context processor returns lang", '"lang": lang' in web_source or '"lang": config.lang' in web_source)
check("Web: layout.html uses t()", "{{ t(" in layout_tpl)
check("Web: login.html uses t()", "{{ t(" in login_tpl)
check("Web: index.html uses t()", "{{ t(" in index_tpl)
check("Web: status.html uses t()", "{{ t(" in status_tpl)
check("Web: doctor.html uses t()", "{{ t(" in doctor_tpl)
check("Web: rotate.html uses t()", "{{ t(" in rotate_tpl)

print("\n--- Web: /api/status unchanged ---\n")

api_section = web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else ""
check("Web: /api/status route exists", '"/api/status"' in web_source)
check("Web: api_status uses redact_json", "redact_json(data)" in api_section)
check("Web: /api/status not gated by advanced", "is_advanced_mode_enabled" not in api_section)
check("Web: /api/status returns jsonify", "jsonify" in api_section)

print("\n--- Web: Raw JSON gate unchanged ---\n")

check("Web: status.html branches on advanced_mode_enabled", "advanced_mode_enabled" in status_tpl)
check("Web: locked-panel class exists", "locked-panel" in status_tpl)
check("Web: raw_json rendered in advanced block", "status.raw_json" in status_tpl)
check("Web: details block present", "<details>" in status_tpl)

print("\n--- Web: Advanced mode unchanged ---\n")

check("Web: enable_advanced_mode exists", "def enable_advanced_mode" in web_source)
check("Web: disable_advanced_mode exists", "def disable_advanced_mode" in web_source)
check("Web: is_advanced_mode_enabled exists", "def is_advanced_mode_enabled" in web_source)
check("Web: ADVANCED_MODE_TTL_SECONDS is 900", "ADVANCED_MODE_TTL_SECONDS = 15 * 60" in web_source)
check("Web: /advanced/on route exists", '"/advanced/on"' in web_source)
check("Web: /advanced/off route exists", '"/advanced/off"' in web_source)

print("\n--- Web: Rotate behavior unchanged ---\n")

check("Web: /rotate route exists", '"/rotate"' in web_source)
check("Web: rotate_confirm exists", "def rotate_confirm" in web_source)
check("Web: rotate uses validate_csrf", "validate_csrf()" in web_source.split("def rotate_confirm")[1].split("def ")[0] if "def rotate_confirm" in web_source else "")
check("Web: pending rotate uses session", "get_pending_rotate" in web_source)

print("\n--- Web: Status values stable ---\n")

from web.app import format_status
check("Web: format_status returns healthy for ok=True", format_status({"ok": True, "services": {"hy2": "active"}})["cards"]["overall"] == "healthy")
check("Web: format_status returns unknown for {}", format_status({})["cards"]["overall"] == "unknown")
check("Web: format_status returns failed for ok=False", format_status({"ok": False})["cards"]["overall"] == "failed")
check("Web: status category values not translated", format_status({"ok": True}, )["cards"]["overall"] == "healthy")

print("\n--- Web: No raw URLs/secrets in WEB_TEXT ---\n")

web_text_str = str(WEB_TEXT)
check("Web: no TOKEN= in WEB_TEXT", "TOKEN=" not in web_text_str)
check("Web: no SECRET= in WEB_TEXT", "SECRET=" not in web_text_str)
check("Web: no PRIVATE_KEY= in WEB_TEXT", "PRIVATE_KEY=" not in web_text_str)
check("Web: no workers.dev in WEB_TEXT", "workers.dev" not in web_text_str)
check("Web: no http:// in WEB_TEXT", "http://" not in web_text_str)
check("Web: no https:// in WEB_TEXT", "https://" not in web_text_str)
check("Web: no raw IP in WEB_TEXT", "203.0.113" not in web_text_str)

print("\n--- Web: Redaction import preserved ---\n")

check("Web: shared redaction import", "from lib.nanobk_redaction import" in web_source)
check("Web: redact_json_obj imported", "redact_json_obj" in web_source)
check("Web: strip_ansi imported", "_shared_strip_ansi" in web_source)
check("Web: redact_text imported", "_shared_redact_text" in web_source)

print("\n--- Web: Safety ---\n")

check("Web: no shell=True", "shell=True" not in web_source)
check("Web: no os.system", "os.system" not in web_source)
check("Web: run_nanobk present", "def run_nanobk" in web_source)
check("Web: validate_csrf present", "def validate_csrf" in web_source)
check("Web: login route exists", '"/login"' in web_source)
check("Web: logout route exists", '"/logout"' in web_source)
check("Web: healthz route exists", '"/healthz"' in web_source)

# ══════════════════════════════════════════════════════════════════════════════
# Cross-consistency checks
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Cross: Bot/Web consistency ---\n")

check("Cross: both support zh/en", bot.SUPPORTED_LANGS == {"en", "zh"} and "en" in web_i18n_source and "zh" in web_i18n_source)
check("Cross: both default en", bot.DEFAULT_LANG == "en" and "DEFAULT_LANG" in web_i18n_source)
check("Cross: both have invalid fallback", bot.normalize_lang("invalid") == "en" and web_normalize_lang("invalid") == "en")
check("Cross: both preserve redaction", "from lib.nanobk_redaction import" in bot_source and "from lib.nanobk_redaction import" in web_source)
check("Cross: both preserve Raw JSON gating", "is_advanced_mode_enabled" in bot_source and "advanced_mode_enabled" in status_tpl)
check("Cross: both preserve advanced mode", "def enable_advanced_mode" in bot_source and "def enable_advanced_mode" in web_source)
check("Cross: both preserve rotate safety", "ConfirmationManager" in bot_source and "rotate_confirm" in web_source)
check("Cross: both have no shell=True", "shell=True" not in bot_source and "shell=True" not in web_source)
check("Cross: both have no os.system", "os.system" not in bot_source and "os.system" not in web_source)
check("Cross: neither introduces installer changes", "install.sh" not in bot_source and "install.sh" not in web_source)

print("\n--- Cross: Bot i18n test safety assertions ---\n")

check("Bot test: checks no TOKEN=", "no TOKEN= in translations" in bot_i18n_test)
check("Bot test: checks no SECRET=", "no SECRET= in translations" in bot_i18n_test)
check("Bot test: checks no PRIVATE_KEY=", "no PRIVATE_KEY= in translations" in bot_i18n_test)
check("Bot test: checks no workers.dev", "no workers.dev in translations" in bot_i18n_test)
check("Bot test: checks no http://", "no http:// in translations" in bot_i18n_test)
check("Bot test: checks no https://", "no https:// in translations" in bot_i18n_test)
check("Bot test: checks slash commands unchanged", "CommandHandler" in bot_i18n_test)
check("Bot test: checks no shell=True", "no shell=True" in bot_i18n_test)
check("Bot test: checks shared redaction import", "shared redaction import" in bot_i18n_test)
check("Bot test: checks status values not translated", "status values not translated" in bot_i18n_test)

print("\n--- Cross: Web i18n test safety assertions ---\n")

check("Web test: checks no TOKEN=", "no TOKEN= in translations" in web_i18n_test)
check("Web test: checks no SECRET=", "no SECRET= in translations" in web_i18n_test)
check("Web test: checks no PRIVATE_KEY=", "no PRIVATE_KEY= in translations" in web_i18n_test)
check("Web test: checks no workers.dev", "no workers.dev in translations" in web_i18n_test)
check("Web test: checks no http://", "no http:// in translations" in web_i18n_test)
check("Web test: checks /api/status unchanged", "/api/status unchanged" in web_i18n_test)
check("Web test: checks no shell=True", "no shell=True" in web_i18n_test)
check("Web test: checks shared redaction import", "shared redaction import" in web_i18n_test)
check("Web test: checks status values not translated", "status values not translated" in web_i18n_test)

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mCheckpoint FAIL: i18n inconsistencies found.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mCheckpoint PASS: Bot/Web i18n is consistent and safe.\033[0m")
