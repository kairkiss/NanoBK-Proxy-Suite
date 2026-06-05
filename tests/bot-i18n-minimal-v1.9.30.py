#!/usr/bin/env python3
"""
Test: Bot i18n Minimal Implementation (v1.9.30)

Verifies:
- NANOBK_LANG support in BotConfig
- Translation helper exists and works
- zh/en Control Center text
- zh/en button labels
- zh/en help text
- zh/en status labels
- zh/en advanced/status_json messages
- zh/en callback guidance
- slash commands unchanged
- no raw secrets in translations
- existing functionality preserved
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

# Read source
with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()

# Import bot module
import bot.nanobk_bot as bot

print("=== Bot i18n Minimal Test (v1.9.30) ===\n")

# ── 1. Language config ────────────────────────────────────────────────────

print("--- Language config ---\n")

check("normalize_lang exists", callable(bot.normalize_lang))
check("normalize_lang(None) == en", bot.normalize_lang(None) == "en")
check("normalize_lang('') == en", bot.normalize_lang("") == "en")
check("normalize_lang('en') == en", bot.normalize_lang("en") == "en")
check("normalize_lang('zh') == zh", bot.normalize_lang("zh") == "zh")
check("normalize_lang('zh-cn') == zh", bot.normalize_lang("zh-cn") == "zh")
check("normalize_lang('zh_cn') == zh", bot.normalize_lang("zh_cn") == "zh")
check("normalize_lang('invalid') == en", bot.normalize_lang("invalid") == "en")
check("SUPPORTED_LANGS contains en", "en" in bot.SUPPORTED_LANGS)
check("SUPPORTED_LANGS contains zh", "zh" in bot.SUPPORTED_LANGS)
check("DEFAULT_LANG is en", bot.DEFAULT_LANG == "en")
check("BotConfig has lang field", hasattr(bot.BotConfig(), "lang"))
check("BotConfig default lang is en", bot.BotConfig().lang == "en")

# ── 2. Translation helper ────────────────────────────────────────────────

print("\n--- Translation helper ---\n")

check("bt() is callable", callable(bot.bt))
check("bt en returns English", "NanoBK" in bot.bt("en", "control_center_title"))
check("bt zh returns Chinese", "控制中心" in bot.bt("zh", "control_center_title"))
check("bt fallback for missing key", bot.bt("en", "nonexistent_key_xyz") == "nonexistent_key_xyz")
check("bt fallback for missing lang", "NanoBK" in bot.bt("invalid_lang", "control_center_title"))
check("bt format kwargs work", "15" in bot.bt("en", "advanced_enabled_status", minutes=15))
check("bt zh format kwargs work", "15" in bot.bt("zh", "advanced_enabled_status", minutes=15))

# ── 3. Control Center text ────────────────────────────────────────────────

print("\n--- Control Center text ---\n")

cc_en = bot.build_control_center_text("en")
cc_zh = bot.build_control_center_text("zh")
check("en Control Center title", "NanoBK Control Center" in cc_en)
check("en Control Center mentions /help", "/help" in cc_en)
check("en Control Center says hidden", "hidden" in cc_en)
check("zh Control Center title", "NanoBK 控制中心" in cc_zh)
check("zh Control Center mentions /help", "/help" in cc_zh)
check("zh Control Center says hidden", "隐藏" in cc_zh)

# ── 4. Button labels ─────────────────────────────────────────────────────

print("\n--- Button labels ---\n")

check("en btn_status", "Status Summary" in bot.bt("en", "btn_status"))
check("zh btn_status", "状态总览" in bot.bt("zh", "btn_status"))
check("en btn_recovery", "Recovery" in bot.bt("en", "btn_recovery"))
check("zh btn_recovery", "恢复" in bot.bt("zh", "btn_recovery"))
check("en btn_diagnostics", "Diagnostics" in bot.bt("en", "btn_diagnostics"))
check("zh btn_diagnostics", "诊断" in bot.bt("zh", "btn_diagnostics"))
check("en btn_advanced", "Advanced" in bot.bt("en", "btn_advanced"))
check("zh btn_advanced", "高级" in bot.bt("zh", "btn_advanced"))
check("en btn_rotate", "Rotate" in bot.bt("en", "btn_rotate"))
check("zh btn_rotate", "轮换" in bot.bt("zh", "btn_rotate"))
check("en btn_web", "Web Panel" in bot.bt("en", "btn_web"))
check("zh btn_web", "Web 面板" in bot.bt("zh", "btn_web"))
check("en btn_help", "Help" in bot.bt("en", "btn_help"))
check("zh btn_help", "帮助" in bot.bt("zh", "btn_help"))

# ── 5. Help text ─────────────────────────────────────────────────────────

print("\n--- Help text ---\n")

help_en = bot.build_help_text("en")
help_zh = bot.build_help_text("zh")
check("en help title", "NanoBK Bot Commands" in help_en)
check("zh help title", "NanoBK 机器人命令" in help_zh)
check("en help Basic section", "Basic:" in help_en)
check("zh help Basic section", "基础：" in help_zh)
check("en help /status_json under Advanced", "/status_json" in help_en)
check("zh help /status_json under Advanced", "/status_json" in help_zh)
check("en help rotate warning", "confirmation" in help_en.lower())
check("zh help rotate warning", "确认" in help_zh)
check("slash commands unchanged in en", "/start" in help_en and "/status" in help_en and "/doctor" in help_en)
check("slash commands unchanged in zh", "/start" in help_zh and "/status" in help_zh and "/doctor" in help_zh)

# ── 6. Status labels ─────────────────────────────────────────────────────

print("\n--- Status labels ---\n")

check("en label Overall", bot.bt("en", "status_label_overall") == "Overall")
check("zh label Overall", bot.bt("zh", "status_label_overall") == "总览")
check("en label VPS", bot.bt("en", "status_label_vps") == "VPS")
check("en label Protocols", bot.bt("en", "status_label_protocols") == "Protocols")
check("zh label Protocols", bot.bt("zh", "status_label_protocols") == "协议")
check("en label Next step", bot.bt("en", "status_label_next_step") == "Next step")
check("zh label Next step", bot.bt("zh", "status_label_next_step") == "下一步")

# Status category values NOT translated
check("status values not translated: healthy", "healthy" in bot.format_status({"ok": True, "services": {"hy2": "active"}}, lang="zh"))
check("status values not translated: unknown", "unknown" in bot.format_status({}, lang="en"))
check("status values not translated: failed", "failed" in bot.format_status({"ok": False}, lang="zh"))

# ── 7. Advanced / status_json messages ────────────────────────────────────

print("\n--- Advanced / status_json messages ---\n")

check("en gate not enabled", "not enabled" in bot.bt("en", "gate_not_enabled"))
check("zh gate not enabled", "未启用" in bot.bt("zh", "gate_not_enabled"))
check("en gate mentions /advanced on", "/advanced on" in bot.bt("en", "gate_not_enabled"))
check("zh gate mentions /advanced on", "/advanced on" in bot.bt("zh", "gate_not_enabled"))
check("en gate mentions 15 minutes", "15 minutes" in bot.bt("en", "gate_not_enabled"))
check("zh gate mentions 15", "15" in bot.bt("zh", "gate_not_enabled"))
check("en gate says secrets hidden", "secrets" in bot.bt("en", "gate_not_enabled") and "remain hidden" in bot.bt("en", "gate_not_enabled"))
check("zh gate says hidden", "隐藏" in bot.bt("zh", "gate_not_enabled"))
check("en status_json warning says redacted", "redacted" in bot.bt("en", "status_json_warning"))
check("zh status_json warning says redacted", "脱敏" in bot.bt("zh", "status_json_warning"))
check("en advanced on msg", "enabled" in bot.bt("en", "advanced_on_msg"))
check("zh advanced on msg", "已启用" in bot.bt("zh", "advanced_on_msg"))
check("en advanced off msg", "disabled" in bot.bt("en", "advanced_off_msg").lower())
check("zh advanced off msg", "已禁用" in bot.bt("zh", "advanced_off_msg"))

# ── 8. Callback guidance ─────────────────────────────────────────────────

print("\n--- Callback guidance ---\n")

rec_en = bot.build_guidance_recovery("en")
rec_zh = bot.build_guidance_recovery("zh")
check("en recovery mentions /status", "/status" in rec_en)
check("zh recovery mentions /status", "/status" in rec_zh)
check("en recovery mentions SSH", "SSH" in rec_en)
check("zh recovery says hidden", "隐藏" in rec_zh)

diag_en = bot.build_guidance_diagnostics("en")
diag_zh = bot.build_guidance_diagnostics("zh")
check("en diagnostics mentions /doctor", "/doctor" in diag_en)
check("zh diagnostics mentions /doctor", "/doctor" in diag_zh)
check("en diagnostics mentions /advanced on", "/advanced on" in diag_en)
check("zh diagnostics says redacted", "脱敏" in diag_zh)

rot_en = bot.build_guidance_rotate("en")
rot_zh = bot.build_guidance_rotate("zh")
check("en rotate mentions confirmation", "confirmation" in rot_en)
check("zh rotate mentions confirmation", "确认" in rot_zh)
check("en rotate does not execute", "/rotate_all" in rot_en)
check("zh rotate does not execute", "/rotate_all" in rot_zh)

web_en = bot.build_guidance_web("en")
web_zh = bot.build_guidance_web("zh")
check("en web has no raw URL", "http://" not in web_en and "https://" not in web_en)
check("zh web has no raw URL", "http://" not in web_zh and "https://" not in web_zh)
check("en web mentions dashboard", "dashboard" in web_en.lower())
check("zh web mentions browser", "浏览器" in web_zh)

# ── 9. No raw secrets in translations ────────────────────────────────────

print("\n--- No raw secrets in translations ---\n")

all_text = str(bot.BOT_TEXT)
check("no TOKEN= in translations", "TOKEN=" not in all_text)
check("no SECRET= in translations", "SECRET=" not in all_text)
check("no PRIVATE_KEY= in translations", "PRIVATE_KEY=" not in all_text)
check("no workers.dev in translations", "workers.dev" not in all_text)
check("no subscription URL in translations", "subscription URL" not in all_text.lower())
check("no http:// in translations", "http://" not in all_text)
check("no https:// in translations", "https://" not in all_text)

# ── 10. Slash commands unchanged ──────────────────────────────────────────

print("\n--- Slash commands unchanged ---\n")

check("CommandHandler start registered", 'CommandHandler("start"' in bot_source)
check("CommandHandler status registered", 'CommandHandler("status"' in bot_source)
check("CommandHandler status_json registered", 'CommandHandler("status_json"' in bot_source)
check("CommandHandler doctor registered", 'CommandHandler("doctor"' in bot_source)
check("CommandHandler advanced registered", 'CommandHandler("advanced"' in bot_source)
check("CommandHandler cancel registered", 'CommandHandler("cancel"' in bot_source)
check("CallbackQueryHandler registered", "CallbackQueryHandler" in bot_source)

# ── 11. Existing functionality preserved ──────────────────────────────────

print("\n--- Existing functionality preserved ---\n")

check("run_nanobk present", "def run_nanobk" in bot_source)
check("safe_output present", "def safe_output" in bot_source)
check("format_status present", "def format_status" in bot_source)
check("get_safe_status_text present", "def get_safe_status_text" in bot_source)
check("is_advanced_mode_enabled present", "def is_advanced_mode_enabled" in bot_source)
check("ConfirmationManager present", "ConfirmationManager" in bot_source)
check("shared redaction import", "from lib.nanobk_redaction import" in bot_source)
check("no shell=True", "shell=True" not in bot_source)

# ── 12. No Web changes ────────────────────────────────────────────────────

print("\n--- No Web changes ---\n")

web_path = os.path.join(REPO_DIR, "web", "app.py")
with open(web_path) as f:
    web_source = f.read()
check("web /api/status still exists", '"/api/status"' in web_source)
check("web login route still exists", '"/login"' in web_source)
check("web validate_csrf still exists", "def validate_csrf" in web_source)
check("web has NANOBK_LANG support", "NANOBK_LANG" in web_source)

# ── Summary ───────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    sys.exit(1)
else:
    print("All tests passed!")
