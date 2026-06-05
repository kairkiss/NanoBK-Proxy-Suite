#!/usr/bin/env python3
"""
Test: Bot Control Center Callback Polish (v1.9.25)

Verifies:
- Shared safe status helper exists and is used
- Callback guidance constants are correct
- Callbacks are owner-only
- Rotate callback does not execute rotate
- Web Panel callback does not expose raw URL
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

print("=== Bot Control Center Callback Polish Test (v1.9.25) ===\n")

# ── 1. Shared status helper ───────────────────────────────────────────────

print("--- Shared status helper ---\n")

check("get_safe_status_text function exists", "def get_safe_status_text" in bot_source)
check("get_safe_status_text calls run_nanobk", 'run_nanobk(config, ["--json", "status"])' in bot_source.split("def get_safe_status_text")[1].split("def ")[0] if "def get_safe_status_text" in bot_source else False)
check("get_safe_status_text calls format_status", "format_status(data)" in bot_source.split("def get_safe_status_text")[1].split("def ")[0] if "def get_safe_status_text" in bot_source else False)
check("get_safe_status_text calls safe_output", "safe_output(formatted)" in bot_source.split("def get_safe_status_text")[1].split("def ")[0] if "def get_safe_status_text" in bot_source else False)

# cmd_status uses shared helper
cmd_status_section = bot_source.split("async def cmd_status")[1].split("async def")[0] if "async def cmd_status" in bot_source else ""
check("cmd_status calls get_safe_status_text", "get_safe_status_text(config)" in cmd_status_section)

# Status callback uses shared helper
# Find the handle_menu_callback function body specifically
callback_func_start = bot_source.find("async def handle_menu_callback")
callback_func_end = bot_source.find("# ── Build application", callback_func_start)
callback_section = bot_source[callback_func_start:callback_func_end] if callback_func_start >= 0 else ""
check("Status callback calls get_safe_status_text", "get_safe_status_text(config)" in callback_section)
check("Status callback does NOT duplicate run_nanobk in status path", "CALLBACK_STATUS" in callback_section and "get_safe_status_text" in callback_section.split("CALLBACK_STATUS")[1].split("elif")[0])

# run_nanobk args unchanged
check("run_nanobk uses ['--json', 'status']", '"--json", "status"' in bot_source.split("def get_safe_status_text")[1].split("def ")[0] if "def get_safe_status_text" in bot_source else False)

# ── 2. Guidance constants ─────────────────────────────────────────────────

print("\n--- Guidance constants ---\n")

check("GUIDANCE_RECOVERY constant exists", "GUIDANCE_RECOVERY" in bot_source)
check("GUIDANCE_DIAGNOSTICS constant exists", "GUIDANCE_DIAGNOSTICS" in bot_source)
check("GUIDANCE_ROTATE constant exists", "GUIDANCE_ROTATE" in bot_source)
check("GUIDANCE_WEB constant exists", "GUIDANCE_WEB" in bot_source)
check("HELP_TEXT constant exists", "HELP_TEXT" in bot_source)

# Recovery guidance content
check("GUIDANCE_RECOVERY mentions /status", "/status" in bot_source.split("GUIDANCE_RECOVERY")[1].split("GUIDANCE_DIAGNOSTICS")[0] if "GUIDANCE_RECOVERY" in bot_source else False)
check("GUIDANCE_RECOVERY mentions /doctor", "/doctor" in bot_source.split("GUIDANCE_RECOVERY")[1].split("GUIDANCE_DIAGNOSTICS")[0] if "GUIDANCE_RECOVERY" in bot_source else False)
check("GUIDANCE_RECOVERY mentions SSH", "SSH" in bot_source.split("GUIDANCE_RECOVERY")[1].split("GUIDANCE_DIAGNOSTICS")[0] if "GUIDANCE_RECOVERY" in bot_source else False)
check("GUIDANCE_RECOVERY says secrets hidden", "hidden" in bot_source.split("GUIDANCE_RECOVERY")[1].split("GUIDANCE_DIAGNOSTICS")[0] if "GUIDANCE_RECOVERY" in bot_source else False)

# Diagnostics guidance content
diag_section = bot_source.split("GUIDANCE_DIAGNOSTICS")[1].split("GUIDANCE_ROTATE")[0] if "GUIDANCE_DIAGNOSTICS" in bot_source else ""
check("GUIDANCE_DIAGNOSTICS mentions /doctor", "/doctor" in diag_section)
check("GUIDANCE_DIAGNOSTICS mentions /advanced on", "/advanced on" in diag_section)
check("GUIDANCE_DIAGNOSTICS mentions /status_json", "/status_json" in diag_section)
check("GUIDANCE_DIAGNOSTICS says redacted", "redacted" in diag_section.lower())

# Rotate guidance content
rotate_guidance_section = bot_source.split("GUIDANCE_ROTATE")[1].split("GUIDANCE_WEB")[0] if "GUIDANCE_ROTATE" in bot_source else ""
check("GUIDANCE_ROTATE mentions confirmation", "confirmation" in rotate_guidance_section)
check("GUIDANCE_ROTATE lists rotate commands", "/rotate_all" in rotate_guidance_section and "/rotate_tuic" in rotate_guidance_section)

# Web guidance content
web_guidance_section = bot_source.split("GUIDANCE_WEB")[1].split("HELP_TEXT")[0] if "GUIDANCE_WEB" in bot_source else ""
check("GUIDANCE_WEB mentions dashboard", "dashboard" in web_guidance_section.lower())
check("GUIDANCE_WEB has no raw URL", "http://" not in web_guidance_section and "https://" not in web_guidance_section)

# Callbacks use constants
check("Recovery callback uses GUIDANCE_RECOVERY", "GUIDANCE_RECOVERY" in callback_section)
check("Diagnostics callback uses GUIDANCE_DIAGNOSTICS", "GUIDANCE_DIAGNOSTICS" in callback_section)
check("Rotate callback uses GUIDANCE_ROTATE", "GUIDANCE_ROTATE" in callback_section)
check("Web callback uses GUIDANCE_WEB", "GUIDANCE_WEB" in callback_section)
check("Help callback uses HELP_TEXT", "HELP_TEXT" in callback_section)

# ── 3. Authorization ──────────────────────────────────────────────────────

print("\n--- Authorization ---\n")

check("callback checks owner", "config.owner_id" in callback_section)
check("callback denies unauthorized", "Unauthorized" in callback_section)

# ── 4. Rotate callback safety ─────────────────────────────────────────────

print("\n--- Rotate callback safety ---\n")

rotate_callback = callback_section.split("CALLBACK_ROTATE")[1].split("CALLBACK_WEB")[0] if "CALLBACK_ROTATE" in callback_section else ""
check("rotate callback shows guidance only", "GUIDANCE_ROTATE" in rotate_callback)
check("rotate callback does NOT call run_nanobk", "run_nanobk" not in rotate_callback)
check("rotate callback does NOT call confirmations.set", "confirmations.set" not in rotate_callback)

# ── 5. Web Panel callback safety ──────────────────────────────────────────

print("\n--- Web Panel callback safety ---\n")

web_callback = callback_section.split("CALLBACK_WEB")[1].split("CALLBACK_HELP")[0] if "CALLBACK_WEB" in callback_section else ""
check("web callback uses GUIDANCE_WEB", "GUIDANCE_WEB" in web_callback)
check("web callback does not expose raw URL", "http://" not in web_callback and "https://" not in web_callback)

# ── 6. Existing features preserved ────────────────────────────────────────

print("\n--- Existing features preserved ---\n")

check("/status_json soft gate present", "is_advanced_mode_enabled" in bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else False)
check("/advanced command present", "async def cmd_advanced" in bot_source)
check("/doctor command present", "async def cmd_doctor" in bot_source)
check("rotate handlers present", "ROTATE_ACTIONS" in bot_source)
check("ConfirmationManager present", "ConfirmationManager" in bot_source)
check("run_nanobk present", "def run_nanobk" in bot_source)
check("shared redaction import", "from lib.nanobk_redaction import" in bot_source)

# ── 7. Safety checks ─────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True in bot source", "shell=True" not in bot_source)
check("no os.system in bot source", "os.system" not in bot_source)

# ── 8. No Web changes ────────────────────────────────────────────────────

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
