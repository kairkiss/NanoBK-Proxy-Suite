#!/usr/bin/env python3
"""
Test: Bot Control Center Static Menu (v1.9.24)

Verifies:
- /start shows control center message
- main menu buttons exist
- callback data uses nanobk: prefix
- callbacks are owner-only (source check)
- rotate callback does not call rotate handlers
- Web Panel callback does not expose raw URL
- diagnostics callback mentions /doctor, /advanced on, /status_json
- /status_json soft gate remains
- /advanced remains
- no shell=True
- no raw env reads
- no Web file changes
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

# Read source files
with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()

print("=== Bot Control Center Static Menu Test (v1.9.24) ===\n")

# ── 1. /start control center message ──────────────────────────────────────

print("--- /start control center message ---\n")

check("/start mentions NanoBK Control Center", "NanoBK Control Center" in bot_source)
check("/start mentions /help", "control_center_subtitle" in bot_source and "/help" in bot_source)
check("/start says secrets hidden", "control_center_subtitle" in bot_source and "hidden" in bot_source)
check("/start uses InlineKeyboardMarkup", "InlineKeyboardMarkup" in bot_source or "_build_main_menu_keyboard" in bot_source)

# ── 2. Menu labels ────────────────────────────────────────────────────────

print("\n--- Menu labels ---\n")

check("Status Summary label", "Status Summary" in bot_source)
check("Recovery Help label", "Recovery Help" in bot_source)
check("Diagnostics label", "Diagnostics" in bot_source)
check("Advanced Mode label", "Advanced Mode" in bot_source)
check("Rotate Secrets label", "Rotate Secrets" in bot_source)
check("Web Panel label", "Web Panel" in bot_source)
check("Help label", '"❓ Help"' in bot_source or 'Help' in bot_source)

# ── 3. Callback data prefix ───────────────────────────────────────────────

print("\n--- Callback data prefix ---\n")

check("CALLBACK_STATUS uses nanobk: prefix", 'CALLBACK_STATUS = "nanobk:status"' in bot_source)
check("CALLBACK_RECOVERY uses nanobk: prefix", 'CALLBACK_RECOVERY = "nanobk:recovery"' in bot_source)
check("CALLBACK_DIAGNOSTICS uses nanobk: prefix", 'CALLBACK_DIAGNOSTICS = "nanobk:diagnostics"' in bot_source)
check("CALLBACK_ADVANCED uses nanobk: prefix", 'CALLBACK_ADVANCED = "nanobk:advanced"' in bot_source)
check("CALLBACK_ROTATE uses nanobk: prefix", 'CALLBACK_ROTATE = "nanobk:rotate"' in bot_source)
check("CALLBACK_WEB uses nanobk: prefix", 'CALLBACK_WEB = "nanobk:web"' in bot_source)
check("CALLBACK_HELP uses nanobk: prefix", 'CALLBACK_HELP = "nanobk:help"' in bot_source)

# ── 4. Callback handler ───────────────────────────────────────────────────

print("\n--- Callback handler ---\n")

check("handle_menu_callback exists", "async def handle_menu_callback" in bot_source)
check("CallbackQueryHandler imported", "CallbackQueryHandler" in bot_source)
check("CallbackQueryHandler registered", "CallbackQueryHandler(handle_menu_callback" in bot_source)
check("Callback pattern scoped to nanobk:", 'pattern=r"^nanobk:"' in bot_source)

# ── 5. Authorization ──────────────────────────────────────────────────────

print("\n--- Authorization ---\n")

# Find the handle_menu_callback function body specifically
callback_func_start = bot_source.find("async def handle_menu_callback")
callback_func_end = bot_source.find("# ── Build application", callback_func_start)
callback_section = bot_source[callback_func_start:callback_func_end] if callback_func_start >= 0 else ""
check("callback checks owner", "is_owner" in callback_section or "config.owner_id" in callback_section)
check("callback denies unauthorized", "unauthorized" in callback_section.lower())

# ── 6. Rotate callback does NOT execute rotate ────────────────────────────

print("\n--- Rotate callback safety ---\n")

rotate_callback_section = callback_section.split("CALLBACK_ROTATE")[1].split("CALLBACK_WEB")[0] if "CALLBACK_ROTATE" in callback_section else ""
check("rotate callback shows guidance only", "build_guidance_rotate" in rotate_callback_section or "guidance_rotate" in rotate_callback_section)
check("rotate callback does NOT call run_nanobk", "run_nanobk" not in rotate_callback_section)
check("rotate callback does NOT call confirmations.set", "confirmations.set" not in rotate_callback_section)

# ── 7. Web Panel callback does NOT expose raw URL ─────────────────────────

print("\n--- Web Panel callback safety ---\n")

web_callback_section = callback_section.split("CALLBACK_WEB")[1].split("CALLBACK_HELP")[0] if "CALLBACK_WEB" in callback_section else ""
check("web callback does not expose raw URL", "http://" not in web_callback_section and "https://" not in web_callback_section)
check("web callback shows generic guidance", "build_guidance_web" in web_callback_section or "guidance_web" in web_callback_section)

# ── 8. Diagnostics callback ───────────────────────────────────────────────

print("\n--- Diagnostics callback ---\n")

diag_callback_section = callback_section.split("CALLBACK_DIAGNOSTICS")[1].split("CALLBACK_ADVANCED")[0] if "CALLBACK_DIAGNOSTICS" in callback_section else ""
check("diagnostics uses GUIDANCE_DIAGNOSTICS", "build_guidance_diagnostics" in diag_callback_section or "guidance_diagnostics" in diag_callback_section)
# Verify GUIDANCE_DIAGNOSTICS contains required content
check("diagnostics mentions /doctor", "/doctor" in bot_source.split("guidance_diagnostics")[1].split("guidance_rotate")[0] if "guidance_diagnostics" in bot_source else False)
check("diagnostics mentions /advanced on", "/advanced on" in bot_source.split("guidance_diagnostics")[1].split("guidance_rotate")[0] if "guidance_diagnostics" in bot_source else False)
check("diagnostics mentions /status_json", "/status_json" in bot_source.split("guidance_diagnostics")[1].split("guidance_rotate")[0] if "guidance_diagnostics" in bot_source else False)

# ── 9. Existing features preserved ────────────────────────────────────────

print("\n--- Existing features preserved ---\n")

check("/status_json soft gate present", "is_advanced_mode_enabled" in bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else False)
check("/advanced command present", "async def cmd_advanced" in bot_source)
check("/doctor command present", "async def cmd_doctor" in bot_source)
check("rotate handlers present", "ROTATE_ACTIONS" in bot_source)
check("ConfirmationManager present", "ConfirmationManager" in bot_source)
check("run_nanobk present", "def run_nanobk" in bot_source)
check("shared redaction import", "from lib.nanobk_redaction import" in bot_source)

# ── 10. Safety checks ─────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True in bot source", "shell=True" not in bot_source)
check("no os.system in bot source", "os.system" not in bot_source)
check("no direct env read in callback", "open(" not in callback_section)

# ── 11. No Web changes ────────────────────────────────────────────────────

print("\n--- No Web changes ---\n")

check("web /api/status still exists", '"/api/status"' in web_source)
check("web login route still exists", '"/login"' in web_source)
check("web validate_csrf still exists", "def validate_csrf" in web_source)
check("web rotate_confirm still exists", "def rotate_confirm" in web_source)

# ── Summary ───────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    sys.exit(1)
else:
    print("All tests passed!")
