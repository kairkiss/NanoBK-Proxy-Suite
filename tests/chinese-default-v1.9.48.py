#!/usr/bin/env python3
"""
Test: Chinese Default Minimal Implementation (v1.9.48)

Verifies:
- Bot and Web DEFAULT_LANG is now "zh"
- Missing/empty/invalid NANOBK_LANG falls back to Chinese
- Explicit NANOBK_LANG=en still returns English
- Bot/Web consistency on default language
- No raw secrets in translation dictionaries
- Slash command names unchanged
- Status machine values unchanged
- No installer changes in source

Usage:
    python3 tests/chinese-default-v1.9.48.py
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


# Import modules
import bot.nanobk_bot as bot
from web.i18n import normalize_lang as web_normalize_lang, wt, WEB_TEXT

# Read sources for static checks
with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()
with open(os.path.join(REPO_DIR, "web", "i18n.py")) as f:
    web_i18n_source = f.read()
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_app_source = f.read()

print("=== Chinese Default Test (v1.9.48) ===\n")

# ══════════════════════════════════════════════════════════════════════════════
# 1. Bot default language
# ══════════════════════════════════════════════════════════════════════════════

print("--- Bot: Default language ---\n")

check("Bot: DEFAULT_LANG == zh", bot.DEFAULT_LANG == "zh")
check("Bot: normalize_lang(None) == zh", bot.normalize_lang(None) == "zh")
check("Bot: normalize_lang('') == zh", bot.normalize_lang("") == "zh")
check("Bot: normalize_lang('invalid') == zh", bot.normalize_lang("invalid") == "zh")
check("Bot: normalize_lang('xyzzy') == zh", bot.normalize_lang("xyzzy") == "zh")

# Explicit zh aliases
check("Bot: normalize_lang('zh') == zh", bot.normalize_lang("zh") == "zh")
check("Bot: normalize_lang('zh-cn') == zh", bot.normalize_lang("zh-cn") == "zh")
check("Bot: normalize_lang('zh_cn') == zh", bot.normalize_lang("zh_cn") == "zh")
check("Bot: normalize_lang('chinese') == zh", bot.normalize_lang("chinese") == "zh")
check("Bot: normalize_lang('中文') == zh", bot.normalize_lang("中文") == "zh")

# Explicit English still works
check("Bot: normalize_lang('en') == en", bot.normalize_lang("en") == "en")

# BotConfig default
check("Bot: BotConfig().lang == zh", bot.BotConfig().lang == "zh")

# ══════════════════════════════════════════════════════════════════════════════
# 2. Web default language
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Web: Default language ---\n")

check("Web: DEFAULT_LANG == zh", web_normalize_lang(None) == "zh")
check("Web: normalize_lang(None) == zh", web_normalize_lang(None) == "zh")
check("Web: normalize_lang('') == zh", web_normalize_lang("") == "zh")
check("Web: normalize_lang('invalid') == zh", web_normalize_lang("invalid") == "zh")
check("Web: normalize_lang('xyzzy') == zh", web_normalize_lang("xyzzy") == "zh")

# Explicit zh aliases
check("Web: normalize_lang('zh') == zh", web_normalize_lang("zh") == "zh")
check("Web: normalize_lang('zh-cn') == zh", web_normalize_lang("zh-cn") == "zh")
check("Web: normalize_lang('zh_cn') == zh", web_normalize_lang("zh_cn") == "zh")
check("Web: normalize_lang('chinese') == zh", web_normalize_lang("chinese") == "zh")
check("Web: normalize_lang('中文') == zh", web_normalize_lang("中文") == "zh")

# Explicit English still works
check("Web: normalize_lang('en') == en", web_normalize_lang("en") == "en")

# ══════════════════════════════════════════════════════════════════════════════
# 3. Bot default generates Chinese text
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Bot: Default language generates Chinese text ---\n")

# Control center with default (zh) language
cc_default = bot.build_control_center_text(bot.DEFAULT_LANG)
check("Bot: default control center title is Chinese", "控制中心" in cc_default)
check("Bot: default control center has /help", "/help" in cc_default)

# Control center with explicit English
cc_en = bot.build_control_center_text("en")
check("Bot: explicit en control center is English", "Control Center" in cc_en)

# Help text with default (zh) language
help_default = bot.build_help_text(bot.DEFAULT_LANG)
check("Bot: default help title is Chinese", "机器人命令" in help_default)

# Status labels with default (zh) language
check("Bot: default status label Overall is Chinese", bot.bt(bot.DEFAULT_LANG, "status_label_overall") == "总览")
check("Bot: default status label Next step is Chinese", bot.bt(bot.DEFAULT_LANG, "status_label_next_step") == "下一步")

# Status labels with explicit English
check("Bot: explicit en status label Overall is English", bot.bt("en", "status_label_overall") == "Overall")
check("Bot: explicit en status label Next step is English", bot.bt("en", "status_label_next_step") == "Next step")

# ══════════════════════════════════════════════════════════════════════════════
# 4. Web default generates Chinese text
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Web: Default language generates Chinese text ---\n")

# Login with default (zh) language
check("Web: default login title is Chinese", "Web 面板" in wt(web_normalize_lang(None), "login_title"))

# Login with explicit English
check("Web: explicit en login title is English", "Web Panel" in wt("en", "login_title"))

# Status labels with default (zh)
check("Web: default status label Overall is Chinese", wt(web_normalize_lang(None), "status_label_overall") == "总览")
check("Web: default status label Next step is Chinese", wt(web_normalize_lang(None), "status_next_step") == "下一步")

# Status labels with explicit English
check("Web: explicit en status label Overall is English", wt("en", "status_label_overall") == "Overall")
check("Web: explicit en status label Next step is English", wt("en", "status_next_step") == "Next step")

# Dashboard with default (zh)
check("Web: default dashboard title is Chinese", "控制台" in wt(web_normalize_lang(None), "dashboard_title"))

# Navigation with default (zh)
check("Web: default nav Dashboard is Chinese", "控制台" in wt(web_normalize_lang(None), "nav_dashboard"))

# ══════════════════════════════════════════════════════════════════════════════
# 5. Bot/Web consistency
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Bot/Web consistency ---\n")

check("Both: DEFAULT_LANG == zh", bot.DEFAULT_LANG == "zh" and "DEFAULT_LANG" in web_i18n_source)
check("Both: normalize_lang(None) == zh", bot.normalize_lang(None) == "zh" and web_normalize_lang(None) == "zh")
check("Both: normalize_lang('invalid') == zh", bot.normalize_lang("invalid") == "zh" and web_normalize_lang("invalid") == "zh")
check("Both: normalize_lang('en') == en", bot.normalize_lang("en") == "en" and web_normalize_lang("en") == "en")
check("Both: normalize_lang('zh') == zh", bot.normalize_lang("zh") == "zh" and web_normalize_lang("zh") == "zh")

# ══════════════════════════════════════════════════════════════════════════════
# 6. Slash commands unchanged
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Slash commands unchanged ---\n")

check("Bot: /start registered", 'CommandHandler("start"' in bot_source)
check("Bot: /help registered", 'CommandHandler("help"' in bot_source)
check("Bot: /status registered", 'CommandHandler("status"' in bot_source)
check("Bot: /status_json registered", 'CommandHandler("status_json"' in bot_source)
check("Bot: /doctor registered", 'CommandHandler("doctor"' in bot_source)
check("Bot: /advanced registered", 'CommandHandler("advanced"' in bot_source)
check("Bot: /cancel registered", 'CommandHandler("cancel"' in bot_source)

# ══════════════════════════════════════════════════════════════════════════════
# 7. Status machine values unchanged
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Status machine values unchanged ---\n")

check("Bot: status 'healthy' preserved in zh", "healthy" in bot.format_status({"ok": True, "services": {"hy2": "active"}}, lang="zh"))
check("Bot: status 'failed' preserved in zh", "failed" in bot.format_status({"ok": False}, lang="zh"))
check("Bot: status 'unknown' preserved in zh", "unknown" in bot.format_status({}, lang="zh"))
check("Bot: status 'active' preserved in zh", "active" in bot.format_status({"ok": True, "services": {"hy2": "active"}}, lang="zh"))
check("Bot: status 'healthy' preserved in en", "healthy" in bot.format_status({"ok": True}, lang="en"))

# ══════════════════════════════════════════════════════════════════════════════
# 8. No raw secrets in translations
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- No raw secrets in translations ---\n")

bot_text_str = str(bot.BOT_TEXT)
check("Bot: no TOKEN= in BOT_TEXT", "TOKEN=" not in bot_text_str)
check("Bot: no SECRET= in BOT_TEXT", "SECRET=" not in bot_text_str)
check("Bot: no PRIVATE_KEY= in BOT_TEXT", "PRIVATE_KEY=" not in bot_text_str)
check("Bot: no workers.dev in BOT_TEXT", "workers.dev" not in bot_text_str)
check("Bot: no http:// in BOT_TEXT", "http://" not in bot_text_str)
check("Bot: no https:// in BOT_TEXT", "https://" not in bot_text_str)

web_text_str = str(WEB_TEXT)
check("Web: no TOKEN= in WEB_TEXT", "TOKEN=" not in web_text_str)
check("Web: no SECRET= in WEB_TEXT", "SECRET=" not in web_text_str)
check("Web: no PRIVATE_KEY= in WEB_TEXT", "PRIVATE_KEY=" not in web_text_str)
check("Web: no workers.dev in WEB_TEXT", "workers.dev" not in web_text_str)
check("Web: no http:// in WEB_TEXT", "http://" not in web_text_str)
check("Web: no https:// in WEB_TEXT", "https://" not in web_text_str)

# ══════════════════════════════════════════════════════════════════════════════
# 9. No installer changes
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- No installer changes ---\n")

check("Bot: no install.sh reference", "install.sh" not in bot_source)
check("Web i18n: no install.sh reference", "install.sh" not in web_i18n_source)

# ══════════════════════════════════════════════════════════════════════════════
# 10. Safety boundaries unchanged
# ══════════════════════════════════════════════════════════════════════════════

print("\n--- Safety boundaries unchanged ---\n")

check("Bot: no shell=True", "shell=True" not in bot_source)
check("Bot: shared redaction import", "from lib.nanobk_redaction import" in bot_source)
check("Web: no shell=True", "shell=True" not in web_app_source)
check("Web: shared redaction import", "from lib.nanobk_redaction import" in web_app_source)
check("Web: /api/status exists", '"/api/status"' in web_app_source)

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} ===")
if failed > 0:
    print("\n\033[31mFAIL: Chinese default implementation has issues.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mPASS: Bot/Web Chinese default is correct.\033[0m")
