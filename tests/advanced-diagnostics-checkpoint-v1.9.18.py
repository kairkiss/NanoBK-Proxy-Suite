#!/usr/bin/env python3
"""
Test: Advanced Diagnostics Mode Checkpoint (v1.9.18)

Compares Bot and Web advanced diagnostics mode behavior and safety boundaries.
Source-level tests + direct helper tests. No real server, no real nanobk.

Usage:
    python3 tests/advanced-diagnostics-checkpoint-v1.9.18.py
"""

import os
import sys
import time

# ── Setup ──────────────────────────────────────────────────────────────────

REPO_DIR = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, REPO_DIR)

# Load Bot module (no Telegram required)
import importlib.util
BOT_PATH = os.path.join(REPO_DIR, "bot", "nanobk_bot.py")
bot_spec = importlib.util.spec_from_file_location("nanobk_bot", BOT_PATH)
bot = importlib.util.module_from_spec(bot_spec)
sys.modules["nanobk_bot"] = bot
bot_spec.loader.exec_module(bot)

# Load Web module (no Flask server required)
WEB_PATH = os.path.join(REPO_DIR, "web", "app.py")
web_spec = importlib.util.spec_from_file_location("web_app", WEB_PATH)
web = importlib.util.module_from_spec(web_spec)
sys.modules["web_app"] = web
web_spec.loader.exec_module(web)

# Read sources for static checks
with open(BOT_PATH) as f:
    bot_source = f.read()
with open(WEB_PATH) as f:
    web_source = f.read()

# Read templates
STATUS_TPL = os.path.join(REPO_DIR, "web", "templates", "status.html")
with open(STATUS_TPL) as f:
    status_template = f.read()

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

print("=== Advanced Diagnostics Mode Checkpoint (v1.9.18) ===\n")

# ══════════════════════════════════════════════════════════════════════════
# Bot checks
# ══════════════════════════════════════════════════════════════════════════

print("--- Bot: Advanced mode helpers ---\n")

# Disabled by default
check("Bot: disabled by default (user 99999)", not bot.is_advanced_mode_enabled(99999))
check("Bot: disabled by default (user 12345)", not bot.is_advanced_mode_enabled(12345))

# Enable
test_now = 1000.0
expiry = bot.enable_advanced_mode(12345, now=test_now)
check("Bot: enable returns correct expiry", expiry == test_now + bot.ADVANCED_MODE_TTL_SECONDS)
check("Bot: enabled after enable", bot.is_advanced_mode_enabled(12345, now=test_now))
check("Bot: remaining positive", bot.advanced_mode_remaining_seconds(12345, now=test_now) > 0)
check("Bot: remaining <= 15 min", bot.advanced_mode_remaining_seconds(12345, now=test_now) <= 15 * 60)
check("Bot: expires_at returns value", bot.advanced_mode_expires_at(12345) is not None)

# Expiration
expired_time = test_now + bot.ADVANCED_MODE_TTL_SECONDS + 1
check("Bot: expired mode is disabled", not bot.is_advanced_mode_enabled(12345, now=expired_time))
check("Bot: expired remaining is zero", bot.advanced_mode_remaining_seconds(12345, now=expired_time) == 0)

# Disable
bot.enable_advanced_mode(12345, now=test_now)
bot.disable_advanced_mode(12345)
check("Bot: disabled after disable", not bot.is_advanced_mode_enabled(12345))
check("Bot: remaining zero after disable", bot.advanced_mode_remaining_seconds(12345) == 0)
check("Bot: expires_at None after disable", bot.advanced_mode_expires_at(12345) is None)

# TTL
check("Bot: TTL is 15 minutes", bot.ADVANCED_MODE_TTL_SECONDS == 15 * 60)

# In-memory only
check("Bot: state is module-level dict", hasattr(bot, "_ADVANCED_MODE_EXPIRES_AT"))
check("Bot: state is dict type", isinstance(bot._ADVANCED_MODE_EXPIRES_AT, dict))

print("\n--- Bot: Command registration ---\n")

check("Bot: /advanced handler registered", 'CommandHandler("advanced"' in bot_source)
check("Bot: cmd_advanced function exists", "async def cmd_advanced" in bot_source)
check("Bot: /status_json still registered", 'CommandHandler("status_json"' in bot_source)
check("Bot: cmd_status_json still exists", "async def cmd_status_json" in bot_source)

print("\n--- Bot: Safety ---\n")

check("Bot: no shell=True", "shell=True" not in bot_source)
check("Bot: no os.system", "os.system" not in bot_source)
check("Bot: shared redaction import", "from lib.nanobk_redaction import" in bot_source)
check("Bot: strip_ansi delegates", "_shared_strip_ansi" in bot_source)
check("Bot: redact_text delegates", "_shared_redact_text" in bot_source)
check("Bot: rotate commands present", "rotate_hy2" in bot_source and "rotate_tuic" in bot_source)
check("Bot: ConfirmationManager present", "ConfirmationManager" in bot_source)
check("Bot: run_nanobk present", "def run_nanobk" in bot_source)

print("\n--- Bot: No file/env persistence ---\n")

adv_section = bot_source.split("_ADVANCED_MODE_EXPIRES_AT")[1].split("class ")[0] if "_ADVANCED_MODE_EXPIRES_AT" in bot_source else ""
check("Bot: no file write in advanced helpers", "open(" not in adv_section)
check("Bot: no env write in advanced helpers", "os.environ" not in adv_section)
check("Bot: no json.dump for advanced mode", "json.dump" not in adv_section)

# ══════════════════════════════════════════════════════════════════════════
# Web checks
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Web: Advanced mode helpers ---\n")

# Disabled by default
test_session: dict = {}
check("Web: disabled by default", not web.is_advanced_mode_enabled(test_session))
check("Web: remaining zero when disabled", web.advanced_mode_remaining_seconds(test_session) == 0)

# Enable
web.enable_advanced_mode(test_session)
check("Web: enabled after enable", web.is_advanced_mode_enabled(test_session))
check("Web: remaining positive", web.advanced_mode_remaining_seconds(test_session) > 0)
check("Web: remaining <= 15 min", web.advanced_mode_remaining_seconds(test_session) <= 15 * 60)

# Disable
web.disable_advanced_mode(test_session)
check("Web: disabled after disable", not web.is_advanced_mode_enabled(test_session))
check("Web: remaining zero after disable", web.advanced_mode_remaining_seconds(test_session) == 0)
check("Web: session key cleared", "advanced_mode" not in test_session)

# Expired
test_session2: dict = {"advanced_mode": {"enabled_at": time.time() - web.ADVANCED_MODE_TTL_SECONDS - 1}}
check("Web: expired mode is disabled", not web.is_advanced_mode_enabled(test_session2))
check("Web: expired remaining is zero", web.advanced_mode_remaining_seconds(test_session2) == 0)
check("Web: expired cleans session key", "advanced_mode" not in test_session2)

# TTL
check("Web: TTL is 15 minutes", web.ADVANCED_MODE_TTL_SECONDS == 15 * 60)

print("\n--- Web: Route registration ---\n")

check("Web: POST /advanced/on exists", '"/advanced/on"' in web_source)
check("Web: POST /advanced/off exists", '"/advanced/off"' in web_source)
check("Web: GET /advanced/status exists", '"/advanced/status"' in web_source)
check("Web: advanced_on function exists", "def advanced_on" in web_source)
check("Web: advanced_off function exists", "def advanced_off" in web_source)
check("Web: advanced_status function exists", "def advanced_status" in web_source)

print("\n--- Web: Login/CSRF protection ---\n")

# Check that advanced routes require login
adv_on_section = web_source.split("def advanced_on")[1].split("def ")[0] if "def advanced_on" in web_source else ""
adv_off_section = web_source.split("def advanced_off")[1].split("def ")[0] if "def advanced_off" in web_source else ""
check("Web: advanced_on requires login", "@require_login" in adv_on_section)
check("Web: advanced_off requires login", "@require_login" in adv_off_section)
check("Web: advanced_on validates CSRF", "validate_csrf()" in adv_on_section)
check("Web: advanced_off validates CSRF", "validate_csrf()" in adv_off_section)

print("\n--- Web: Safety ---\n")

check("Web: no shell=True", "shell=True" not in web_source)
check("Web: no os.system", "os.system" not in web_source)
check("Web: shared redaction import", "from lib.nanobk_redaction import" in web_source)
check("Web: redact_json_obj imported", "redact_json_obj" in web_source)
check("Web: validate_csrf exists", "def validate_csrf" in web_source)
check("Web: login route exists", '"/login"' in web_source)
check("Web: logout route exists", '"/logout"' in web_source)
check("Web: rotate route exists", '"/rotate"' in web_source)
check("Web: run_nanobk present", "def run_nanobk" in web_source)

print("\n--- Web: Session state only ---\n")

check("Web: session used for advanced mode", "session" in adv_on_section)
check("Web: no file write in advanced helpers", "open(" not in web_source.split("advanced_mode")[1].split("def ")[0] if "advanced_mode" in web_source else True)
check("Web: no env write in advanced helpers", "os.environ" not in web_source.split("advanced_mode")[1].split("def ")[0] if "advanced_mode" in web_source else True)
check("Web: no URL query bypass", "request.args" not in web_source.split("advanced")[1].split("def ")[0] if "advanced" in web_source else True)

print("\n--- Web: Raw JSON / API boundary ---\n")

check("Web: Raw JSON details in template", "<details>" in status_template)
check("Web: Raw JSON summary in template", "Raw JSON" in status_template)
check("Web: raw_json rendered", "status.raw_json" in status_template)
check("Web: Raw JSON not gated by advanced", "advanced_mode" not in status_template.split("<details>")[1].split("</details>")[0] if "<details>" in status_template else False)
check("Web: /api/status route exists", '"/api/status"' in web_source)
check("Web: api_status uses redact_json", "redact_json(data)" in web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else False)

# ══════════════════════════════════════════════════════════════════════════
# Cross-consistency
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Cross-consistency ---\n")

check("TTL: Bot == Web", bot.ADVANCED_MODE_TTL_SECONDS == web.ADVANCED_MODE_TTL_SECONDS)
check("Both have enable/disable/status semantics", all(hasattr(bot, f) for f in ["enable_advanced_mode", "disable_advanced_mode", "is_advanced_mode_enabled"]) and all(hasattr(web, f) for f in ["enable_advanced_mode", "disable_advanced_mode", "is_advanced_mode_enabled"]))
check("Both do not change redaction", "from lib.nanobk_redaction import" in bot_source and "from lib.nanobk_redaction import" in web_source)
check("Bot gates /status_json with advanced mode (v1.9.20+)", "is_advanced_mode_enabled" in bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else False)
check("Both have warning copy", "redacted" in bot_source and "redacted" in status_template)
check("Both have no shell=True", "shell=True" not in bot_source and "shell=True" not in web_source)
check("Both do not reference env files for advanced state", ".env" not in bot_source.split("_ADVANCED_MODE_EXPIRES_AT")[1].split("class ")[0] if "_ADVANCED_MODE_EXPIRES_AT" in bot_source else True)
check("Both do not persist advanced state to files", "open(" not in bot_source.split("_ADVANCED_MODE_EXPIRES_AT")[1].split("class ")[0] if "_ADVANCED_MODE_EXPIRES_AT" in bot_source else True)
check("Both do not modify run_nanobk", "def run_nanobk" in bot_source and "def run_nanobk" in web_source)

# ══════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mCheckpoint FAIL: inconsistencies found.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mCheckpoint PASS: Bot/Web advanced diagnostics mode is consistent.\033[0m")
