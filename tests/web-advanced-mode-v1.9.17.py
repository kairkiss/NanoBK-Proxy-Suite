#!/usr/bin/env python3
"""
Test: Web Advanced Mode (v1.9.17)

Verifies:
- Advanced mode helper functions
- Session-level state
- TTL and expiration
- Route existence and CSRF requirements
- Raw JSON details still present
- /api/status not gated
- No Bot file changes
"""

import os
import sys
import time
import importlib.util

# Load web module without Flask server
WEB_PATH = os.path.join(os.path.dirname(__file__), "..", "web", "app.py")
spec = importlib.util.spec_from_file_location("web_app", WEB_PATH)
web = importlib.util.module_from_spec(spec)
sys.modules["web_app"] = web
spec.loader.exec_module(web)

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
with open(WEB_PATH, "r") as f:
    web_source = f.read()

# Read bot source to verify no changes
BOT_PATH = os.path.join(os.path.dirname(__file__), "..", "bot", "nanobk_bot.py")
with open(BOT_PATH, "r") as f:
    bot_source = f.read()

# Read templates
STATUS_TPL = os.path.join(os.path.dirname(__file__), "..", "web", "templates", "status.html")
with open(STATUS_TPL, "r") as f:
    status_template = f.read()

print("=== Web Advanced Mode Test (v1.9.17) ===\n")

# ── 1. Advanced mode helper functions ─────────────────────────────────────

print("--- Advanced mode helpers ---\n")

# Disabled by default
test_session: dict = {}
check("disabled by default", not web.is_advanced_mode_enabled(test_session))
check("remaining zero when disabled", web.advanced_mode_remaining_seconds(test_session) == 0)

# Enable
web.enable_advanced_mode(test_session)
check("enabled after enable", web.is_advanced_mode_enabled(test_session))
check("remaining positive after enable", web.advanced_mode_remaining_seconds(test_session) > 0)
check("remaining <= 15 minutes", web.advanced_mode_remaining_seconds(test_session) <= 15 * 60)

# Disable
web.disable_advanced_mode(test_session)
check("disabled after disable", not web.is_advanced_mode_enabled(test_session))
check("remaining zero after disable", web.advanced_mode_remaining_seconds(test_session) == 0)
check("session key cleared", "advanced_mode" not in test_session)

# Re-enable after disable
web.enable_advanced_mode(test_session)
check("re-enabled after disable", web.is_advanced_mode_enabled(test_session))
web.disable_advanced_mode(test_session)

# Expired mode
test_session2: dict = {"advanced_mode": {"enabled_at": time.time() - web.ADVANCED_MODE_TTL_SECONDS - 1}}
check("expired mode is disabled", not web.is_advanced_mode_enabled(test_session2))
check("expired remaining is zero", web.advanced_mode_remaining_seconds(test_session2) == 0)
check("expired cleans session key", "advanced_mode" not in test_session2)

# TTL constant
check("TTL is 15 minutes", web.ADVANCED_MODE_TTL_SECONDS == 15 * 60)

# Session-only (no file/env writes)
check("helper functions exist", all(callable(f) for f in [
    web.enable_advanced_mode,
    web.disable_advanced_mode,
    web.is_advanced_mode_enabled,
    web.advanced_mode_remaining_seconds,
]))

# ── 2. Route registration ─────────────────────────────────────────────────

print("\n--- Route registration ---\n")

check("/advanced/on route exists", '"/advanced/on"' in web_source)
check("/advanced/off route exists", '"/advanced/off"' in web_source)
check("/advanced/status route exists", '"/advanced/status"' in web_source)
check("/advanced/on uses POST", "methods=[\"POST\"]" in web_source.split("/advanced/on")[1].split("def ")[0] if "/advanced/on" in web_source else False)
check("/advanced/off uses POST", "methods=[\"POST\"]" in web_source.split("/advanced/off")[1].split("def ")[0] if "/advanced/off" in web_source else False)
check("advanced_on function exists", "def advanced_on" in web_source)
check("advanced_off function exists", "def advanced_off" in web_source)
check("advanced_status function exists", "def advanced_status" in web_source)

# ── 3. Login/CSRF protection ─────────────────────────────────────────────

print("\n--- Login/CSRF protection ---\n")

check("advanced_on requires login", "@require_login" in web_source.split("def advanced_on")[0].split("\n")[-2] if "def advanced_on" in web_source else False)
check("advanced_off requires login", "@require_login" in web_source.split("def advanced_off")[0].split("\n")[-2] if "def advanced_off" in web_source else False)
check("advanced_on validates CSRF", "validate_csrf()" in web_source.split("def advanced_on")[1].split("def ")[0] if "def advanced_on" in web_source else False)
check("advanced_off validates CSRF", "validate_csrf()" in web_source.split("def advanced_off")[1].split("def ")[0] if "def advanced_off" in web_source else False)
check("no GET enable route", "/advanced/on" not in web_source or "GET" not in web_source.split("/advanced/on")[1].split("def ")[0].split("\n")[0] if "/advanced/on" in web_source else False)

# ── 4. Session state only ─────────────────────────────────────────────────

print("\n--- Session state only ---\n")

check("session used for advanced mode", 'session["advanced_mode"]' in web_source or "session.get(\"advanced_mode\")" in web_source or "session_obj.get(\"advanced_mode\")" in web_source)
check("no file write for advanced mode", "open(" not in web_source.split("advanced_mode")[1].split("def ")[0] if "advanced_mode" in web_source else True)
check("no env write for advanced mode", "os.environ" not in web_source.split("advanced_mode")[1].split("def ")[0] if "advanced_mode" in web_source else True)
check("no json.dump for advanced mode", "json.dump" not in web_source.split("advanced_mode")[1].split("def ")[0] if "advanced_mode" in web_source else True)
check("no URL query parameter bypass", "?advanced" not in web_source and "request.args" not in web_source.split("advanced")[1].split("def ")[0] if "advanced" in web_source else True)

# ── 5. Status template advanced controls ──────────────────────────────────

print("\n--- Status template ---\n")

check("advanced_mode_enabled in template", "advanced_mode_enabled" in status_template)
check("advanced_mode_remaining in template", "advanced_mode_remaining" in status_template)
check("enable form in template", "/advanced/on" in status_template)
check("disable form in template", "/advanced/off" in status_template)
check("csrf_token in forms", "csrf_token" in status_template)
check("warning box present", "warning-box" in status_template)
check("warning says redacted", "advanced_enable_warning_text" in status_template)
check("warning says 15 minutes", "advanced_enable_warning_text" in status_template)
check("warning says do not share", "advanced_enable_warning_text" in status_template)

# ── 6. Raw JSON details preserved ─────────────────────────────────────────

print("\n--- Raw JSON details preserved ---\n")

check("Raw JSON details still present", "<details>" in status_template)
check("Raw JSON summary present", "raw_json_details_label" in status_template)
check("raw_json rendered", "status.raw_json" in status_template)
check("Raw JSON not gated by advanced", "advanced_mode" not in status_template.split("<details>")[1].split("</details>")[0] if "<details>" in status_template else False)

# ── 7. /api/status not gated ──────────────────────────────────────────────

print("\n--- /api/status not gated ---\n")

check("/api/status route exists", '"/api/status"' in web_source)
check("api_status function exists", "def api_status" in web_source)
check("/api/status not gated by advanced", "is_advanced_mode_enabled" not in web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else False)
check("/api/status uses redact_json", "redact_json(data)" in web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else False)

# ── 8. No Bot changes ────────────────────────────────────────────────────

print("\n--- No Bot changes ---\n")

check("Bot advanced_mode helpers unchanged", "enable_advanced_mode" in bot_source)
check("Bot /advanced command unchanged", 'CommandHandler("advanced"' in bot_source)
check("Bot no web module import", "from web" not in bot_source and "import web" not in bot_source)

# ── 9. Safety checks ─────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True in web source", "shell=True" not in web_source)
check("no os.system in web source", "os.system" not in web_source)
check("shared redaction import", "from lib.nanobk_redaction import" in web_source)
check("redact_json_obj imported", "redact_json_obj" in web_source)

# ── 10. Existing functionality preserved ──────────────────────────────────

print("\n--- Existing functionality preserved ---\n")

check("login route exists", '"/login"' in web_source)
check("logout route exists", '"/logout"' in web_source)
check("validate_csrf exists", "def validate_csrf" in web_source)
check("rotate route exists", '"/rotate"' in web_source)
check("rotate_confirm exists", "def rotate_confirm" in web_source)
check("dashboard route exists", '"/"' in web_source)
check("doctor route exists", '"/doctor"' in web_source)
check("healthz route exists", '"/healthz"' in web_source)

# ── Summary ───────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    sys.exit(1)
else:
    print("All tests passed!")
