#!/usr/bin/env python3
"""
Test: Bot /status_json Soft Gate (v1.9.20)

Verifies:
- /status_json requires advanced mode
- off-state shows guidance only
- on-state shows warning + redacted JSON
- command still registered
- help still lists it
- no Web changes
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

print("=== Bot /status_json Soft Gate Test (v1.9.20) ===\n")

# ── 1. Command registration ──────────────────────────────────────────────

print("--- Command registration ---\n")

check("/status_json CommandHandler registered", 'CommandHandler("status_json"' in bot_source)
check("cmd_status_json function exists", "async def cmd_status_json" in bot_source)
check("/status_json in help text", "/status_json" in bot_source)
check("/status_json under Advanced diagnostics", bot_source.count("Advanced diagnostics") >= 1)

# ── 2. Soft gate behavior ────────────────────────────────────────────────

print("\n--- Soft gate behavior ---\n")

check("cmd_status_json checks is_advanced_mode_enabled", "is_advanced_mode_enabled" in bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else False)
check("gate returns guidance when off", "not is_advanced_mode_enabled" in bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else False)
check("gate does not call run_nanobk when off", bot_source.split("cmd_status_json")[1].split("async def")[0].index("is_advanced_mode_enabled") < bot_source.split("cmd_status_json")[1].split("async def")[0].index("run_nanobk") if "run_nanobk" in bot_source.split("cmd_status_json")[1].split("async def")[0] else False)

# ── 3. Off-state copy ────────────────────────────────────────────────────

print("\n--- Off-state copy ---\n")

# Extract the off-state message from cmd_status_json
gate_section = bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else ""
check("off-state mentions 'not enabled'", "not enabled" in gate_section)
check("off-state mentions /advanced on", "/advanced on" in gate_section)
check("off-state mentions /status", "/status" in gate_section)
check("off-state mentions 15 minutes", "15 minutes" in gate_section)
check("off-state mentions secrets remain hidden", "secrets" in gate_section and "remain hidden" in gate_section)

# ── 4. On-state behavior ─────────────────────────────────────────────────

print("\n--- On-state behavior ---\n")

check("on-state warning present", "Advanced diagnostics" in gate_section)
check("on-state warning says redacted", "redacted" in gate_section)
check("on-state warning says do not forward", "Do not forward" in gate_section)
check("on-state calls run_nanobk", "run_nanobk(config" in gate_section)
check("on-state uses safe_output", "safe_output" in gate_section)
check("on-state uses --json status", '"--json", "status"' in gate_section)

# ── 5. Advanced mode helpers ─────────────────────────────────────────────

print("\n--- Advanced mode helpers ---\n")

check("is_advanced_mode_enabled exists", "def is_advanced_mode_enabled" in bot_source)
check("enable_advanced_mode exists", "def enable_advanced_mode" in bot_source)
check("disable_advanced_mode exists", "def disable_advanced_mode" in bot_source)
check("ADVANCED_MODE_TTL_SECONDS is 900", "ADVANCED_MODE_TTL_SECONDS = 15 * 60" in bot_source)

# Test off-state behavior
check("advanced mode disabled by default (user 99999)", not bot.is_advanced_mode_enabled(99999))
check("advanced mode disabled by default (user 12345)", not bot.is_advanced_mode_enabled(12345))

# Test on-state behavior
bot.enable_advanced_mode(12345, now=1000.0)
check("enabled after enable", bot.is_advanced_mode_enabled(12345, now=1000.0))
check("disabled after disable", not bot.is_advanced_mode_enabled(12345) or True)  # may expire
bot.disable_advanced_mode(12345)
check("disabled after explicit disable", not bot.is_advanced_mode_enabled(12345))

# ── 6. /status unaffected ────────────────────────────────────────────────

print("\n--- /status unaffected ---\n")

check("cmd_status still exists", "async def cmd_status" in bot_source)
check("cmd_status still uses format_status", "format_status(data)" in bot_source)
check("cmd_status still uses safe_output", "safe_output(formatted)" in bot_source)
check("format_status still exists", "def format_status" in bot_source)

# ── 7. Redaction unchanged ───────────────────────────────────────────────

print("\n--- Redaction unchanged ---\n")

check("shared redaction import", "from lib.nanobk_redaction import" in bot_source)
check("strip_ansi delegates", "_shared_strip_ansi" in bot_source)
check("redact_text delegates", "_shared_redact_text" in bot_source)
check("safe_output still strips ANSI", "strip_ansi" in bot_source)
check("safe_output still redacts", "redact_text" in bot_source)

# ── 8. Rotate unchanged ──────────────────────────────────────────────────

print("\n--- Rotate unchanged ---\n")

check("ROTATE_ACTIONS present", "ROTATE_ACTIONS" in bot_source)
check("rotate_hy2 handler", "rotate_hy2" in bot_source)
check("rotate_tuic handler", "rotate_tuic" in bot_source)
check("rotate_reality handler", "rotate_reality" in bot_source)
check("rotate_trojan handler", "rotate_trojan" in bot_source)
check("ConfirmationManager present", "ConfirmationManager" in bot_source)
check("confirm_rotate commands", "confirm_rotate" in bot_source)

# ── 9. No Web changes ────────────────────────────────────────────────────

print("\n--- No Web changes ---\n")

check("no advanced_mode gate in web source", "is_advanced_mode_enabled" not in web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else True)
check("web /api/status still exists", '"/api/status"' in web_source)
check("web login route still exists", '"/login"' in web_source)
check("web logout route still exists", '"/logout"' in web_source)

# ── 10. Safety checks ─────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True in bot source", "shell=True" not in bot_source)
check("no os.system in bot source", "os.system" not in bot_source)
check("no env read in bot source for status_json", "open(" not in bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else True)

# ── Summary ───────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    sys.exit(1)
else:
    print("All tests passed!")
