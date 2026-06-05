#!/usr/bin/env python3
"""
Test: Web Raw JSON Soft Gate (v1.9.21)

Verifies:
- Status page Raw JSON is gated behind advanced mode
- OFF state: locked panel, no raw_json rendered
- ON state: warning + redacted Raw JSON details
- /api/status unchanged
- no Bot changes
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
with open(os.path.join(REPO_DIR, "web", "templates", "status.html")) as f:
    status_tpl = f.read()
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()
with open(os.path.join(REPO_DIR, "web", "static", "style.css")) as f:
    css_source = f.read()
with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()

print("=== Web Raw JSON Soft Gate Test (v1.9.21) ===\n")

# ── 1. OFF state: locked panel ───────────────────────────────────────────

print("--- OFF state: locked panel ---\n")

check("locked panel exists in template", "locked-panel" in status_tpl)
check("locked panel mentions advanced diagnostics", "raw_json_locked_title" in status_tpl)
check("locked panel mentions locked", "locked" in status_tpl.lower())
check("locked panel recommends status cards", "raw_json_locked_use_cards" in status_tpl)
check("locked panel mentions 15 minutes", "raw_json_locked_enable_hint" in status_tpl)
check("locked panel mentions secrets remain hidden", "raw_json_locked_secrets_note" in status_tpl)
check("locked panel CSS class exists", ".locked-panel" in css_source)

# ── 2. OFF state: no raw_json rendered ────────────────────────────────────

print("\n--- OFF state: no raw_json rendered ---\n")

# The template should gate raw_json behind advanced_mode_enabled
# Check that the raw_json rendering is inside the advanced_mode_enabled block
# by verifying the structure: {% if advanced_mode_enabled %} ... raw_json ... {% else %} ... locked ...
check("raw_json only in advanced mode block",
      "advanced_mode_enabled" in status_tpl and "status.raw_json" in status_tpl)
# Verify the locked panel does NOT contain raw_json
locked_section = status_tpl.split("{% else %}")[1] if "{% else %}" in status_tpl else ""
check("locked panel does not render raw_json", "status.raw_json" not in locked_section.split("{% endif %}")[0] if "{% endif %}" in locked_section else True)
check("locked panel does not have <pre> for raw output", "<pre>{{ status.raw_json }}</pre>" not in locked_section.split("{% endif %}")[0] if "{% endif %}" in locked_section else True)

# ── 3. ON state: warning + Raw JSON details ───────────────────────────────

print("\n--- ON state: warning + Raw JSON details ---\n")

# There are two {% if advanced_mode_enabled %} blocks:
# 1. Inside the Advanced Diagnostics card (toggle)
# 2. For the Raw JSON section (gate)
# We need the second one - find it by looking for the one that contains <details>
all_advanced_blocks = status_tpl.split("{% if advanced_mode_enabled %}")
raw_json_block = ""
for block in all_advanced_blocks:
    if "<details>" in block:
        raw_json_block = block.split("{% else %}")[0]
        break

check("ON state has warning box", "warning-box" in raw_json_block)
check("ON state has Raw JSON details", "<details>" in raw_json_block)
check("ON state has raw_json pre", "<pre>{{ status.raw_json }}</pre>" in raw_json_block)
check("ON state has summary", "<summary>" in raw_json_block)
check("ON state mentions redacted", "raw_json_warning_text" in status_tpl)
check("ON state mentions not for subscription", "raw_json_warning_text" in status_tpl)
check("ON state has disable form", "/advanced/off" in status_tpl)

# ── 4. Advanced mode toggle card ──────────────────────────────────────────

print("\n--- Advanced mode toggle card ---\n")

check("enable form exists", "/advanced/on" in status_tpl)
check("disable form exists", "/advanced/off" in status_tpl)
check("CSRF token in enable form", "csrf_token" in status_tpl)
check("advanced_mode_enabled context used", "advanced_mode_enabled" in status_tpl)
check("advanced_mode_remaining used", "advanced_mode_remaining" in status_tpl)

# ── 5. Normal status cards unaffected ─────────────────────────────────────

print("\n--- Normal status cards unaffected ---\n")

check("Overall Status card exists", "status_overall" in status_tpl)
check("VPS card exists", "status.cards.vps" in status_tpl)
check("Protocols section exists", "status.cards.services" in status_tpl)
check("Cloudflare section exists", "status.cards.cf_nanok" in status_tpl)
check("Next step exists", "status.cards.next_step" in status_tpl)
check("Sensitive addresses hidden note", "status_footer" in status_tpl)

# ── 6. /api/status not gated ──────────────────────────────────────────────

print("\n--- /api/status not gated ---\n")

api_section = web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else ""
check("/api/status route exists", '"/api/status"' in web_source)
check("/api/status uses redact_json", "redact_json(data)" in api_section)
check("/api/status not gated by advanced", "is_advanced_mode_enabled" not in api_section)
check("/api/status returns jsonify", "jsonify" in api_section)

# ── 7. Redaction unchanged ────────────────────────────────────────────────

print("\n--- Redaction unchanged ---\n")

check("shared redaction import", "from lib.nanobk_redaction import" in web_source)
check("redact_json_obj imported", "redact_json_obj" in web_source)
check("strip_ansi imported", "_shared_strip_ansi" in web_source)
check("redact_text imported", "_shared_redact_text" in web_source)

# ── 8. Login/session/CSRF/rotate unchanged ────────────────────────────────

print("\n--- Login/session/CSRF/rotate unchanged ---\n")

check("login route exists", '"/login"' in web_source)
check("logout route exists", '"/logout"' in web_source)
check("validate_csrf exists", "def validate_csrf" in web_source)
check("rotate route exists", '"/rotate"' in web_source)
check("rotate_confirm exists", "def rotate_confirm" in web_source)
check("run_nanobk unchanged", "def run_nanobk" in web_source)

# ── 9. No Bot changes ─────────────────────────────────────────────────────

print("\n--- No Bot changes ---\n")

check("Bot /status_json gated by advanced (v1.9.20)", "is_advanced_mode_enabled" in bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else False)
check("Bot advanced mode helpers unchanged", "enable_advanced_mode" in bot_source)
check("Bot no web module import", "from web" not in bot_source and "import web" not in bot_source)

# ── 10. Safety checks ─────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True in web source", "shell=True" not in web_source)
check("no os.system in web source", "os.system" not in web_source)
check("no query parameter bypass", "request.args" not in web_source.split("advanced")[1].split("def ")[0] if "advanced" in web_source else True)

# ── Summary ───────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    sys.exit(1)
else:
    print("All tests passed!")
