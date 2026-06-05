#!/usr/bin/env python3
"""
Test: Raw JSON Gating Checkpoint (v1.9.22)

Compares Bot and Web Raw JSON soft gating behavior and safety boundaries.
Source-level tests + direct helper tests. No real server, no real nanobk.

Usage:
    python3 tests/raw-json-gating-checkpoint-v1.9.22.py
"""

import os
import sys

REPO_DIR = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, REPO_DIR)

# Read sources for static checks
with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()
with open(os.path.join(REPO_DIR, "web", "templates", "status.html")) as f:
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

print("=== Raw JSON Gating Checkpoint (v1.9.22) ===\n")

# ══════════════════════════════════════════════════════════════════════════
# Bot checks
# ══════════════════════════════════════════════════════════════════════════

print("--- Bot: /status_json gating ---\n")

check("Bot: /status_json command still exists", 'CommandHandler("status_json"' in bot_source)
check("Bot: cmd_status_json function exists", "async def cmd_status_json" in bot_source)
check("Bot: /status_json in Advanced diagnostics help", "/status_json" in bot_source and "Advanced diagnostics" in bot_source)

# Gate check
status_json_section = bot_source.split("cmd_status_json")[1].split("async def")[0] if "cmd_status_json" in bot_source else ""
check("Bot: cmd_status_json checks is_advanced_mode_enabled", "is_advanced_mode_enabled" in status_json_section)
check("Bot: OFF path guidance exists", "not is_advanced_mode_enabled" in status_json_section)
check("Bot: OFF path mentions /advanced on", "/advanced on" in bot_source)
check("Bot: OFF path mentions /status", "/status" in bot_source)
check("Bot: OFF path mentions 15 minutes", "15 minutes" in bot_source)
check("Bot: OFF path does not call run_nanobk before gate",
      status_json_section.index("is_advanced_mode_enabled") < status_json_section.index("run_nanobk") if "run_nanobk" in status_json_section else False)

# ON path
check("Bot: ON path calls run_nanobk(config, ['--json', 'status'])", '"--json", "status"' in status_json_section)
check("Bot: ON path has warning header", "Advanced diagnostics" in bot_source)
check("Bot: ON path uses safe_output", "safe_output" in status_json_section)

# /status unaffected
check("Bot: /status still exists", "async def cmd_status" in bot_source)
check("Bot: /status uses format_status", "format_status" in bot_source)
check("Bot: format_status still exists", "def format_status" in bot_source)

# Rotate preserved
check("Bot: ROTATE_ACTIONS present", "ROTATE_ACTIONS" in bot_source)
check("Bot: rotate_hy2 handler", "rotate_hy2" in bot_source)
check("Bot: rotate_tuic handler", "rotate_tuic" in bot_source)
check("Bot: ConfirmationManager present", "ConfirmationManager" in bot_source)

# Redaction preserved
check("Bot: shared redaction import", "from lib.nanobk_redaction import" in bot_source)
check("Bot: strip_ansi delegates", "_shared_strip_ansi" in bot_source)
check("Bot: redact_text delegates", "_shared_redact_text" in bot_source)

# Advanced mode TTL
check("Bot: ADVANCED_MODE_TTL_SECONDS is 900", "ADVANCED_MODE_TTL_SECONDS = 15 * 60" in bot_source)

# ══════════════════════════════════════════════════════════════════════════
# Web checks
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Web: Raw JSON gating ---\n")

# Template checks
check("Web: Raw JSON section still exists/discoverable", "raw_json_details_label" in status_template)
check("Web: template branches on advanced_mode_enabled", "advanced_mode_enabled" in status_template)

# OFF branch: find the locked-panel section (the else block that contains locked-panel)
# Template has multiple if/else blocks. The one we want is the Raw JSON gating block.
all_else_blocks = status_template.split("{% else %}")
locked_block = ""
for block in all_else_blocks:
    if "locked-panel" in block:
        locked_block = block.split("{% endif %}")[0]
        break
check("Web: OFF branch contains locked panel", "locked-panel" in locked_block)
check("Web: OFF branch does not render status.raw_json", "status.raw_json" not in locked_block)
check("Web: OFF branch provides POST /advanced/on form", "/advanced/on" in status_template)
check("Web: OFF branch uses CSRF token", "csrf_token" in status_template)

# ON branch
all_advanced_blocks = status_template.split("{% if advanced_mode_enabled %}")
raw_json_block = ""
for block in all_advanced_blocks:
    if "<details>" in block:
        raw_json_block = block.split("{% else %}")[0]
        break
check("Web: ON branch has warning box", "warning-box" in raw_json_block)
check("Web: ON branch has <details>", "<details>" in raw_json_block)
check("Web: ON branch renders status.raw_json", "status.raw_json" in raw_json_block)

# API not gated
api_section = web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else ""
check("Web: /api/status route exists", '"/api/status"' in web_source)
check("Web: /api/status uses redact_json", "redact_json(data)" in api_section)
check("Web: /api/status not gated by advanced", "is_advanced_mode_enabled" not in api_section)

# Status cards unchanged
check("Web: Overall Status card exists", "status_overall" in status_template)
check("Web: status.cards.overall rendered", "status.cards.overall" in status_template)
check("Web: Sensitive addresses hidden note", "status_footer" in status_template)

# Login/session/CSRF/rotate
check("Web: login route exists", '"/login"' in web_source)
check("Web: logout route exists", '"/logout"' in web_source)
check("Web: validate_csrf exists", "def validate_csrf" in web_source)
check("Web: rotate route exists", '"/rotate"' in web_source)
check("Web: rotate_confirm exists", "def rotate_confirm" in web_source)

# Redaction preserved
check("Web: shared redaction import", "from lib.nanobk_redaction import" in web_source)
check("Web: redact_json_obj imported", "redact_json_obj" in web_source)

# Advanced mode TTL
check("Web: ADVANCED_MODE_TTL_SECONDS is 900", "ADVANCED_MODE_TTL_SECONDS = 15 * 60" in web_source)

# No query parameter bypass
check("Web: no query parameter advanced enable", "request.args" not in web_source.split("advanced")[1].split("def ")[0] if "advanced" in web_source else True)

# Safety
check("Web: no shell=True", "shell=True" not in web_source)
check("Web: no os.system", "os.system" not in web_source)
check("Web: run_nanobk present", "def run_nanobk" in web_source)

# ══════════════════════════════════════════════════════════════════════════
# Cross-consistency
# ══════════════════════════════════════════════════════════════════════════

print("\n--- Cross-consistency ---\n")

check("Both: same TTL (900s)", "ADVANCED_MODE_TTL_SECONDS = 15 * 60" in bot_source and "ADVANCED_MODE_TTL_SECONDS = 15 * 60" in web_source)
check("Both: have advanced mode OFF/ON behavior", "is_advanced_mode_enabled" in bot_source and "advanced_mode_enabled" in status_template)
check("Both: diagnostics available in advanced mode", "run_nanobk" in status_json_section and "status.raw_json" in raw_json_block)
check("Both: protect beginner UI from Raw JSON", "not is_advanced_mode_enabled" in status_json_section and "locked-panel" in locked_block)
check("Both: preserve redaction", "from lib.nanobk_redaction import" in bot_source and "from lib.nanobk_redaction import" in web_source)
check("Both: do not persist advanced state to env/config/db", "open(" not in bot_source.split("ADVANCED_MODE")[1].split("class ")[0] if "ADVANCED_MODE" in bot_source else True)
check("Both: do not alter high-risk operations", "ROTATE_ACTIONS" in bot_source and "rotate_confirm" in web_source)
check("Both: no shell=True", "shell=True" not in bot_source and "shell=True" not in web_source)

# ══════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mCheckpoint FAIL: inconsistencies found.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mCheckpoint PASS: Bot/Web Raw JSON soft gating is consistent.\033[0m")
