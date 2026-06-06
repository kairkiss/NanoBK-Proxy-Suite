#!/usr/bin/env python3
"""
Test: Bot Language Command / Guidance (v1.9.52)

Verifies:
- /language command handler registered
- cmd_language exists
- command is owner-only
- command does not call run_nanobk
- command does not write env
- command does not read env files
- command guidance includes current language
- command guidance mentions Chinese default
- command guidance mentions English availability
- command guidance mentions future/persistent switching
- command guidance does not include raw env path or env content
- command guidance does not include token/secret/private key patterns
- /help includes /language
- slash command names remain unchanged
- NANOBK_LANG=en semantics remain handled by config.lang
- no Web files changed
- no installer files changed
- no shell=True
- no os.system

Usage:
    python3 tests/bot-language-command-v1.9.52.py
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

print("=== Bot Language Command Test (v1.9.52) ===\n")

# ── 1. Command registration ──────────────────────────────────────────────────

print("--- Command registration ---\n")

check("CommandHandler language registered", 'CommandHandler("language"' in bot_source)
check("cmd_language exists", "async def cmd_language" in bot_source)

# ── 2. Authorization ─────────────────────────────────────────────────────────

print("\n--- Authorization ---\n")

lang_section = bot_source.split("async def cmd_language")[1].split("async def")[0] if "async def cmd_language" in bot_source else ""
check("cmd_language checks is_owner", "is_owner" in lang_section)
check("cmd_language calls unauthorized", "unauthorized" in lang_section)

# ── 3. No nanobk CLI call ────────────────────────────────────────────────────

print("\n--- No nanobk CLI call ---\n")

check("cmd_language does NOT call run_nanobk", "run_nanobk" not in lang_section)
check("cmd_language does NOT call nanobk", "nanobk" not in lang_section.lower().split("build_language_guidance")[0] if "build_language_guidance" in lang_section else "nanobk" not in lang_section)

# ── 4. No env write/read ─────────────────────────────────────────────────────

print("\n--- No env write/read ---\n")

check("cmd_language does NOT open files", "open(" not in lang_section)
check("cmd_language does NOT write env", "write" not in lang_section.lower())
check("cmd_language does NOT read env", ".env" not in lang_section)

# ── 5. build_language_guidance function ──────────────────────────────────────

print("\n--- build_language_guidance function ---\n")

check("build_language_guidance exists", "def build_language_guidance" in bot_source)
check("build_language_guidance is callable", callable(bot.build_language_guidance))

# ── 6. English guidance content ──────────────────────────────────────────────

print("\n--- English guidance content ---\n")

lang_en = bot.build_language_guidance("en")
check("en: has title", "Language Settings" in lang_en)
check("en: shows current language", "Current language" in lang_en)
check("en: mentions NANOBK_LANG", "NANOBK_LANG" in lang_en)
check("en: mentions Chinese default", "default" in lang_en.lower())
check("en: mentions English available", "English" in lang_en)
check("en: mentions persistent planned", "planned" in lang_en.lower() or "future" in lang_en.lower())
check("en: says no env write", "not write" in lang_en.lower() or "does not write" in lang_en.lower())
check("en: no raw env path", "/etc/" not in lang_en and "/root/" not in lang_en and "/home/" not in lang_en)
check("en: no raw token", "TOKEN=" not in lang_en and "SECRET=" not in lang_en and "PRIVATE_KEY=" not in lang_en)
check("en: no raw IP", "1.2.3.4" not in lang_en and "203.0.113" not in lang_en)
check("en: no raw URL", "http://" not in lang_en and "https://" not in lang_en)
check("en: no workers.dev", "workers.dev" not in lang_en)

# ── 7. Chinese guidance content ──────────────────────────────────────────────

print("\n--- Chinese guidance content ---\n")

lang_zh = bot.build_language_guidance("zh")
check("zh: has title", "语言设置" in lang_zh)
check("zh: shows current language", "当前语言" in lang_zh)
check("zh: mentions NANOBK_LANG", "NANOBK_LANG" in lang_zh)
check("zh: mentions Chinese default", "默认" in lang_zh)
check("zh: mentions English available", "英文" in lang_zh or "English" in lang_zh)
check("zh: mentions persistent planned", "计划" in lang_zh or "未来" in lang_zh)
check("zh: no raw env path", "/etc/" not in lang_zh and "/root/" not in lang_zh and "/home/" not in lang_zh)
check("zh: no raw token", "TOKEN=" not in lang_zh and "SECRET=" not in lang_zh and "PRIVATE_KEY=" not in lang_zh)
check("zh: no raw IP", "1.2.3.4" not in lang_zh and "203.0.113" not in lang_zh)
check("zh: no raw URL", "http://" not in lang_zh and "https://" not in lang_zh)

# ── 8. i18n keys ─────────────────────────────────────────────────────────────

print("\n--- i18n keys ---\n")

for key in ["language_title", "language_current_zh", "language_current_en",
             "language_source_explanation", "language_default_zh", "language_en_available",
             "language_persistent_planned", "language_no_env_write", "language_usage", "help_language"]:
    check(f"BOT_TEXT has {key}", key in bot.BOT_TEXT)
    check(f"BOT_TEXT {key} has en", "en" in bot.BOT_TEXT[key])
    check(f"BOT_TEXT {key} has zh", "zh" in bot.BOT_TEXT[key])

# ── 9. Help text includes /language ──────────────────────────────────────────

print("\n--- Help text includes /language ---\n")

help_en = bot.build_help_text("en")
check("en help includes /language", "/language" in help_en)
check("en help /language has description", "language" in help_en.lower())

help_zh = bot.build_help_text("zh")
check("zh help includes /language", "/language" in help_zh)
check("zh help /language has description", "语言" in help_zh or "language" in help_zh.lower())

# ── 10. Slash commands unchanged ─────────────────────────────────────────────

print("\n--- Slash commands unchanged ---\n")

check("/start still registered", 'CommandHandler("start"' in bot_source)
check("/help still registered", 'CommandHandler("help"' in bot_source)
check("/status still registered", 'CommandHandler("status"' in bot_source)
check("/status_json still registered", 'CommandHandler("status_json"' in bot_source)
check("/doctor still registered", 'CommandHandler("doctor"' in bot_source)
check("/advanced still registered", 'CommandHandler("advanced"' in bot_source)
check("/cancel still registered", 'CommandHandler("cancel"' in bot_source)
check("rotate handlers still registered", "for action_name in ROTATE_ACTIONS" in bot_source)
check("CallbackQueryHandler still registered", "CallbackQueryHandler" in bot_source)

# ── 11. NANOBK_LANG=en semantics ────────────────────────────────────────────

print("\n--- NANOBK_LANG=en semantics ---\n")

check("normalize_lang('en') == en", bot.normalize_lang("en") == "en")
check("normalize_lang('zh') == zh", bot.normalize_lang("zh") == "zh")
check("DEFAULT_LANG is zh", bot.DEFAULT_LANG == "zh")
check("BotConfig has lang field", hasattr(bot.BotConfig(), "lang"))
check("BotConfig default lang is zh", bot.BotConfig().lang == "zh")

# ── 12. No Web changes ──────────────────────────────────────────────────────

print("\n--- No Web changes ---\n")

web_path = os.path.join(REPO_DIR, "web", "app.py")
with open(web_path) as f:
    web_source = f.read()
check("web /api/status still exists", '"/api/status"' in web_source)
check("web login route still exists", '"/login"' in web_source)
check("web validate_csrf still exists", "def validate_csrf" in web_source)
check("web has NANOBK_LANG support", "NANOBK_LANG" in web_source)

# ── 13. No installer changes ────────────────────────────────────────────────

print("\n--- No installer changes ---\n")

install_path = os.path.join(REPO_DIR, "installer", "install.sh")
if os.path.exists(install_path):
    with open(install_path) as f:
        install_source = f.read()
    check("installer still has select_language", "select_language" in install_source)
    check("installer still has LANG_CODE", "LANG_CODE" in install_source)

# ── 14. Safety checks ───────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True in bot source", "shell=True" not in bot_source)
check("no os.system in bot source", "os.system" not in bot_source)
check("shared redaction import preserved", "from lib.nanobk_redaction import" in bot_source)

# ── Summary ──────────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mFAIL: Bot language command has issues.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mPASS: Bot language command is correct.\033[0m")
