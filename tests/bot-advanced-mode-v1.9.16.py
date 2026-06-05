#!/usr/bin/env python3
"""
Test: Bot Advanced Mode (v1.9.16)

Verifies:
- Advanced mode helper functions
- /advanced command registration
- /help contains /advanced commands
- /status_json remains available
- No Web files changed
- No shell=True in Bot source
"""

import os
import sys
import importlib.util

# Load bot module without Telegram
BOT_PATH = os.path.join(os.path.dirname(__file__), "..", "bot", "nanobk_bot.py")
spec = importlib.util.spec_from_file_location("nanobk_bot", BOT_PATH)
bot = importlib.util.module_from_spec(spec)
sys.modules["nanobk_bot"] = bot
spec.loader.exec_module(bot)

passed = 0
failed = 0

def check(desc: str, ok: bool):
    global passed, failed
    if ok:
        print(f"  ✓ {desc}")
        passed += 1
    else:
        print(f"  ✗ {desc}")
        failed += 1

# Read source for static checks
with open(BOT_PATH, "r") as f:
    bot_source = f.read()

# Read web source to verify no changes
WEB_PATH = os.path.join(os.path.dirname(__file__), "..", "web", "app.py")
with open(WEB_PATH, "r") as f:
    web_source = f.read()

print("=== Bot Advanced Mode Test (v1.9.16) ===\n")

# ── 1. Advanced mode helper functions ─────────────────────────────────────

print("--- Advanced mode helpers ---\n")

# Disabled by default
check("disabled by default (user 99999)", not bot.is_advanced_mode_enabled(99999))
check("disabled by default (user 12345)", not bot.is_advanced_mode_enabled(12345))

# Enable
test_now = 1000.0
expiry = bot.enable_advanced_mode(12345, now=test_now)
check("enable returns correct expiry", expiry == test_now + bot.ADVANCED_MODE_TTL_SECONDS)
check("enabled after enable", bot.is_advanced_mode_enabled(12345, now=test_now))
check("remaining seconds positive", bot.advanced_mode_remaining_seconds(12345, now=test_now) > 0)
check("expires_at returns value", bot.advanced_mode_expires_at(12345) is not None)
check("expires_at matches", bot.advanced_mode_expires_at(12345) == expiry)

# Still enabled shortly before expiry
just_before = test_now + bot.ADVANCED_MODE_TTL_SECONDS - 1
check("still enabled just before expiry", bot.is_advanced_mode_enabled(12345, now=just_before))
check("remaining ~1s before expiry", bot.advanced_mode_remaining_seconds(12345, now=just_before) == 1)

# Expired
expired_time = test_now + bot.ADVANCED_MODE_TTL_SECONDS + 1
check("expired mode is disabled", not bot.is_advanced_mode_enabled(12345, now=expired_time))
check("expired remaining is zero", bot.advanced_mode_remaining_seconds(12345, now=expired_time) == 0)
check("expired cleans entry", bot.advanced_mode_expires_at(12345) is None)

# Disable
bot.enable_advanced_mode(12345, now=test_now)
bot.disable_advanced_mode(12345)
check("disabled after disable", not bot.is_advanced_mode_enabled(12345))
check("remaining zero after disable", bot.advanced_mode_remaining_seconds(12345) == 0)
check("expires_at None after disable", bot.advanced_mode_expires_at(12345) is None)

# Re-enable after disable
bot.enable_advanced_mode(12345, now=test_now)
check("re-enabled after disable", bot.is_advanced_mode_enabled(12345, now=test_now))
bot.disable_advanced_mode(12345)

# Multiple users
bot.enable_advanced_mode(111, now=test_now)
bot.enable_advanced_mode(222, now=test_now)
check("user 111 enabled", bot.is_advanced_mode_enabled(111, now=test_now))
check("user 222 enabled", bot.is_advanced_mode_enabled(222, now=test_now))
check("user 333 not enabled", not bot.is_advanced_mode_enabled(333, now=test_now))
bot.disable_advanced_mode(111)
check("user 111 disabled", not bot.is_advanced_mode_enabled(111, now=test_now))
check("user 222 still enabled", bot.is_advanced_mode_enabled(222, now=test_now))
bot.disable_advanced_mode(222)

# TTL constant
check("TTL is 15 minutes", bot.ADVANCED_MODE_TTL_SECONDS == 15 * 60)

# In-memory dict only
check("state is module-level dict", hasattr(bot, "_ADVANCED_MODE_EXPIRES_AT"))
check("state is dict type", isinstance(bot._ADVANCED_MODE_EXPIRES_AT, dict))

# ── 2. Command registration ──────────────────────────────────────────────

print("\n--- Command registration ---\n")

check("/advanced handler registered", 'CommandHandler("advanced"' in bot_source)
check("cmd_advanced function exists", "async def cmd_advanced" in bot_source)
check("/advanced on in handler", '"on"' in bot_source)
check("/advanced off in handler", '"off"' in bot_source)
check("/advanced status in handler", '"status"' in bot_source)

# ── 3. /help text ────────────────────────────────────────────────────────

print("\n--- /help text ---\n")

check("/advanced on in help", "/advanced on" in bot_source)
check("/advanced off in help", "/advanced off" in bot_source)
check("/advanced status in help", "/advanced status" in bot_source)
check("/status_json still in help", "/status_json" in bot_source)
check("Advanced diagnostics section in help", "Advanced diagnostics:" in bot_source)

# ── 4. Warning copy ──────────────────────────────────────────────────────

print("\n--- Warning copy ---\n")

check("warning says redacted", "redacted" in bot_source)
check("warning says system structure", "system structure" in bot_source)
check("warning says do not forward", "Do not forward" in bot_source)
check("warning says secrets hidden", "Secrets" in bot_source and "hidden" in bot_source)
check("warning says 15 minutes", "15 minutes" in bot_source)
check("warning says /advanced off", "/advanced off" in bot_source)

# ── 5. /status_json boundary ─────────────────────────────────────────────

print("\n--- /status_json boundary ---\n")

check("/status_json still registered", 'CommandHandler("status_json"' in bot_source)
check("cmd_status_json still exists", "async def cmd_status_json" in bot_source)
check("/status_json gated by advanced (v1.9.20+)", "is_advanced_mode_enabled" in bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else False)
check("/status_json warning still present", "Advanced diagnostics" in bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else False)

# ── 6. No Web changes ────────────────────────────────────────────────────

print("\n--- No Web changes ---\n")

check("advanced_mode exists in web source (v1.9.17+)", "advanced_mode" in web_source.lower())
check("no /advanced route in web source", '"/advanced"' not in web_source)
check("enable_advanced_mode exists in web source (v1.9.17+)", "enable_advanced_mode" in web_source)

# ── 7. Safety checks ─────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True in bot source", "shell=True" not in bot_source)
check("no os.system in bot source", "os.system" not in bot_source)
check("no subprocess.call in bot source", "subprocess.call" not in bot_source)
check("no file write for advanced mode", "open(" not in bot_source.split("advanced")[0].split("def ")[-1] if "advanced" in bot_source else True)

# ── 8. Rotate preserved ──────────────────────────────────────────────────

print("\n--- Rotate preserved ---\n")

check("ROTATE_ACTIONS present", "ROTATE_ACTIONS" in bot_source)
check("rotate_hy2 handler", "rotate_hy2" in bot_source)
check("rotate_tuic handler", "rotate_tuic" in bot_source)
check("rotate_reality handler", "rotate_reality" in bot_source)
check("rotate_trojan handler", "rotate_trojan" in bot_source)
check("ConfirmationManager present", "ConfirmationManager" in bot_source)
check("confirm_rotate commands", "confirm_rotate" in bot_source)

# ── 9. Redaction unchanged ───────────────────────────────────────────────

print("\n--- Redaction unchanged ---\n")

check("shared redaction import", "from lib.nanobk_redaction import" in bot_source)
check("strip_ansi delegates", "_shared_strip_ansi" in bot_source)
check("redact_text delegates", "_shared_redact_text" in bot_source)
check("safe_output function", "def safe_output" in bot_source)

# ── 10. No env/config persistence ────────────────────────────────────────

print("\n--- No persistence ---\n")

check("no file write in advanced helpers", "open(" not in bot_source.split("_ADVANCED_MODE_EXPIRES_AT")[1].split("class ")[0] if "_ADVANCED_MODE_EXPIRES_AT" in bot_source else True)
check("no env write in advanced helpers", "os.environ" not in bot_source.split("_ADVANCED_MODE_EXPIRES_AT")[1].split("class ")[0] if "_ADVANCED_MODE_EXPIRES_AT" in bot_source else True)
check("no json.dump for advanced mode", "json.dump" not in bot_source.split("_ADVANCED_MODE_EXPIRES_AT")[1].split("class ")[0] if "_ADVANCED_MODE_EXPIRES_AT" in bot_source else True)

# ── Summary ───────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    sys.exit(1)
else:
    print("All tests passed!")
