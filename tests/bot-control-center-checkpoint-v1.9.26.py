#!/usr/bin/env python3
"""
Test: Bot Control Center Checkpoint (v1.9.26)

Verifies Bot Control Center is safe, owner-only, additive, and does not bypass
existing slash command safety, Raw JSON gating, advanced mode, rotate confirmation,
redaction, or run_nanobk boundaries.

Source-level tests. No real Telegram, no real nanobk, no real Cloudflare.

Usage:
    python3 tests/bot-control-center-checkpoint-v1.9.26.py
"""

import os
import sys

REPO_DIR = os.path.join(os.path.dirname(__file__), "..")

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
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()

print("=== Bot Control Center Checkpoint (v1.9.26) ===\n")

# ══════════════════════════════════════════════════════════════════════════
# /start control center
# ══════════════════════════════════════════════════════════════════════════

print("--- /start control center ---\n")

check("CONTROL_CENTER_TEXT exists", "NanoBK Control Center" in bot_source)
check("CONTROL_CENTER_TEXT mentions /help", "/help" in bot_source.split("CONTROL_CENTER_TEXT")[1].split(")")[0] if "CONTROL_CENTER_TEXT" in bot_source else "")
check("CONTROL_CENTER_TEXT says secrets hidden", "hidden" in bot_source.split("CONTROL_CENTER_TEXT")[1].split(")")[0] if "CONTROL_CENTER_TEXT" in bot_source else "")
check("menu labels: Status Summary", "Status Summary" in bot_source)
check("menu labels: Recovery Help", "Recovery Help" in bot_source)
check("menu labels: Diagnostics", "Diagnostics" in bot_source)
check("menu labels: Advanced Mode", "Advanced Mode" in bot_source)
check("menu labels: Rotate Secrets", "Rotate Secrets" in bot_source)
check("menu labels: Web Panel", "Web Panel" in bot_source)
check("menu labels: Help", "Help" in bot_source)

# ══════════════════════════════════════════════════════════════════════════
# Callback data prefix
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Callback data prefix ---\n")

for name in ["CALLBACK_STATUS", "CALLBACK_RECOVERY", "CALLBACK_DIAGNOSTICS",
             "CALLBACK_ADVANCED", "CALLBACK_ROTATE", "CALLBACK_WEB", "CALLBACK_HELP"]:
    check(f"{name} uses nanobk: prefix", f'{name} = "nanobk:' in bot_source)

check("CallbackQueryHandler pattern scoped", 'pattern=r"^nanobk:"' in bot_source)

# ══════════════════════════════════════════════════════════════════════════
# Authorization
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Authorization ---\n")

callback_func = bot_source.split("async def handle_menu_callback")[1].split("# ── Build application")[0] if "async def handle_menu_callback" in bot_source else ""
check("callback checks owner (config.owner_id)", "config.owner_id" in callback_func)
check("callback denies unauthorized", "Unauthorized" in callback_func)
check("slash commands preserved: /start", 'CommandHandler("start"' in bot_source)
check("slash commands preserved: /status", 'CommandHandler("status"' in bot_source)
check("slash commands preserved: /status_json", 'CommandHandler("status_json"' in bot_source)
check("slash commands preserved: /doctor", 'CommandHandler("doctor"' in bot_source)
check("slash commands preserved: /advanced", 'CommandHandler("advanced"' in bot_source)
check("slash commands preserved: rotate handlers loop", "for action_name in ROTATE_ACTIONS" in bot_source)
check("slash commands preserved: /help", 'CommandHandler("help"' in bot_source)

# ══════════════════════════════════════════════════════════════════════════
# /status_json soft gate preserved
# ══════════════════════════════════════════════════════════════════════════

print("\n--- /status_json soft gate ---\n")

status_json_section = bot_source.split("async def cmd_status_json")[1].split("async def")[0] if "async def cmd_status_json" in bot_source else ""
check("status_json checks is_advanced_mode_enabled", "is_advanced_mode_enabled" in status_json_section)
check("status_json off-state guidance exists", "not is_advanced_mode_enabled" in status_json_section)
check("status_json off-state mentions /advanced on", "/advanced on" in status_json_section)
check("status_json off-state mentions /status", "/status" in status_json_section)

# ══════════════════════════════════════════════════════════════════════════
# Advanced mode helpers preserved
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Advanced mode helpers ---\n")

check("enable_advanced_mode exists", "def enable_advanced_mode" in bot_source)
check("disable_advanced_mode exists", "def disable_advanced_mode" in bot_source)
check("is_advanced_mode_enabled exists", "def is_advanced_mode_enabled" in bot_source)
check("advanced_mode_remaining_seconds exists", "def advanced_mode_remaining_seconds" in bot_source)
check("ADVANCED_MODE_TTL_SECONDS is 900", "ADVANCED_MODE_TTL_SECONDS = 15 * 60" in bot_source)

# ══════════════════════════════════════════════════════════════════════════
# Shared status helper
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Shared status helper ---\n")

check("get_safe_status_text exists", "def get_safe_status_text" in bot_source)
safe_section = bot_source.split("def get_safe_status_text")[1].split("def ")[0] if "def get_safe_status_text" in bot_source else ""
check("uses run_nanobk(config, ['--json', 'status'])", '"--json", "status"' in safe_section)
check("uses format_status", "format_status(data)" in safe_section)
check("uses safe_output", "safe_output(formatted)" in safe_section)
check("cmd_status uses get_safe_status_text", "get_safe_status_text(config)" in bot_source.split("async def cmd_status")[1].split("async def")[0] if "async def cmd_status" in bot_source else False)
check("Status callback uses get_safe_status_text", "get_safe_status_text(config)" in callback_func)

# ══════════════════════════════════════════════════════════════════════════
# Callback behavior: rotate guidance-only
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Rotate callback safety ---\n")

rotate_cb = callback_func.split("CALLBACK_ROTATE")[1].split("elif")[0] if "CALLBACK_ROTATE" in callback_func else ""
check("rotate callback uses GUIDANCE_ROTATE", "GUIDANCE_ROTATE" in rotate_cb)
check("rotate callback does NOT call make_rotate_handler", "make_rotate_handler" not in rotate_cb)
check("rotate callback does NOT call confirmations.set", "confirmations.set" not in rotate_cb)
check("rotate callback does NOT call run_nanobk", "run_nanobk" not in rotate_cb)

# ══════════════════════════════════════════════════════════════════════════
# Web callback safety
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Web callback safety ---\n")

web_cb = callback_func.split("CALLBACK_WEB")[1].split("elif")[0] if "CALLBACK_WEB" in callback_func else ""
check("Web callback uses GUIDANCE_WEB", "GUIDANCE_WEB" in web_cb)
check("GUIDANCE_WEB has no http://", "http://" not in bot_source.split("GUIDANCE_WEB")[1].split("HELP_TEXT")[0] if "GUIDANCE_WEB" in bot_source else "")
check("GUIDANCE_WEB has no https://", "https://" not in bot_source.split("GUIDANCE_WEB")[1].split("HELP_TEXT")[0] if "GUIDANCE_WEB" in bot_source else "")
check("GUIDANCE_WEB has no workers.dev", "workers.dev" not in bot_source.split("GUIDANCE_WEB")[1].split("HELP_TEXT")[0] if "GUIDANCE_WEB" in bot_source else "")

# ══════════════════════════════════════════════════════════════════════════
# Guidance constants content
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Guidance constants ---\n")

diag_section = bot_source.split("GUIDANCE_DIAGNOSTICS")[1].split("GUIDANCE_ROTATE")[0] if "GUIDANCE_DIAGNOSTICS" in bot_source else ""
check("GUIDANCE_DIAGNOSTICS mentions /doctor", "/doctor" in diag_section)
check("GUIDANCE_DIAGNOSTICS mentions /advanced on", "/advanced on" in diag_section)
check("GUIDANCE_DIAGNOSTICS mentions /status_json", "/status_json" in diag_section)

recovery_section = bot_source.split("GUIDANCE_RECOVERY")[1].split("GUIDANCE_DIAGNOSTICS")[0] if "GUIDANCE_RECOVERY" in bot_source else ""
check("GUIDANCE_RECOVERY mentions /status", "/status" in recovery_section)
check("GUIDANCE_RECOVERY mentions /doctor", "/doctor" in recovery_section)

check("HELP_TEXT remains present", "HELP_TEXT" in bot_source)

# ══════════════════════════════════════════════════════════════════════════
# Safety checks
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Safety checks ---\n")

check("no shell=True in bot source", "shell=True" not in bot_source)
check("no os.system in bot source", "os.system" not in bot_source)
check("shared redaction import", "from lib.nanobk_redaction import" in bot_source)
check("run_nanobk present", "def run_nanobk" in bot_source)
check("ConfirmationManager present", "ConfirmationManager" in bot_source)
check("no subscription delivery", "subscription" not in bot_source or "configured" in bot_source)

# ══════════════════════════════════════════════════════════════════════════
# No Web changes
# ══════════════════════════════════════════════════════════════════════════

print("\n--- No Web changes ---\n")

check("web /api/status still exists", '"/api/status"' in web_source)
check("web login route still exists", '"/login"' in web_source)
check("web validate_csrf still exists", "def validate_csrf" in web_source)
check("web rotate_confirm still exists", "def rotate_confirm" in web_source)

# ══════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mCheckpoint FAIL: inconsistencies found.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mCheckpoint PASS: Bot Control Center is consistent and safe.\033[0m")
