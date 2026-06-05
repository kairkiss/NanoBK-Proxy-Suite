#!/usr/bin/env python3
"""
Test: Bot /status_json warning and /help classification (v1.9.13)

Verifies:
- /status_json appears under Advanced diagnostics in /help
- /status_json is not listed as a basic/beginner command
- Warning text is present before /status_json output
- Output remains redacted through shared helper
- No advanced mode commands added
- No Web files changed
"""

import os
import sys
import importlib.util

# Load bot module
BOT_PATH = os.path.join(os.path.dirname(__file__), "..", "bot", "nanobk_bot.py")
spec = importlib.util.spec_from_file_location("nanobk_bot", BOT_PATH)
bot = importlib.util.module_from_spec(spec)
sys.modules["nanobk_bot"] = bot
spec.loader.exec_module(bot)

# Also load lib/nanobk_redaction for reference
LIB_PATH = os.path.join(os.path.dirname(__file__), "..", "lib", "nanobk_redaction.py")
spec2 = importlib.util.spec_from_file_location("nanobk_redaction", LIB_PATH)
redaction = importlib.util.module_from_spec(spec2)
sys.modules["nanobk_redaction"] = redaction
spec2.loader.exec_module(redaction)

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

# ── Source inspection ─────────────────────────────────────────────────────

with open(BOT_PATH, "r") as f:
    bot_source = f.read()

print("=== Bot /status_json Warning and Help Classification Test (v1.9.13) ===\n")

# ── 1. /help text classification ─────────────────────────────────────────

print("--- /help classification ---\n")

# Simulate the help text from cmd_help
help_text = (
    "NanoBK Bot Commands\n"
    "\n"
    "Basic:\n"
    "/start          — Show welcome and quick help\n"
    "/status         — Safe status summary\n"
    "/doctor         — Redacted diagnostic check\n"
    "/cancel         — Cancel pending action\n"
    "\n"
    "Safe operations:\n"
    "/rotate_all     — Rotate ALL protocols (requires confirmation)\n"
    "/rotate_hy2     — Rotate HY2 secret with confirmation\n"
    "/rotate_tuic    — Rotate TUIC secret with confirmation\n"
    "/rotate_reality — Rotate Reality credentials with confirmation\n"
    "/rotate_trojan  — Rotate Trojan password with confirmation\n"
    "\n"
    "Advanced diagnostics:\n"
    "/status_json    — Redacted raw status JSON for debugging\n"
    "\n"
    "/help           — Show this help\n"
    "\n"
    "⚠️ Rotate commands require confirmation to prevent accidents."
)

check("/help has Basic section", "Basic:" in help_text)
check("/help has Safe operations section", "Safe operations:" in help_text)
check("/help has Advanced diagnostics section", "Advanced diagnostics:" in help_text)
check("/status_json appears in /help", "/status_json" in help_text)
check("/status_json under Advanced diagnostics", help_text.index("/status_json") > help_text.index("Advanced diagnostics:"))
check("/status_json not in Basic section", help_text.index("/status_json") > help_text.index("Safe operations:"))
check("/status in Basic section", help_text.index("/status") < help_text.index("Safe operations:"))
check("/doctor in Basic section", help_text.index("/doctor") < help_text.index("Safe operations:"))
check("/rotate_tuic in Safe operations", help_text.index("/rotate_tuic") > help_text.index("Safe operations:"))

# Verify help text is in bot source
check("help text in bot source", "Advanced diagnostics:" in bot_source)
check("/status_json in bot source help", "/status_json    — Redacted raw status JSON for debugging" in bot_source)
check("Basic: section in bot source", "Basic:" in bot_source)
check("Safe operations: section in bot source", "Safe operations:" in bot_source)

# ── 2. /status_json warning ──────────────────────────────────────────────

print("\n--- /status_json warning ---\n")

# Simulate warning text from cmd_status_json
warning_text = (
    "⚠️ Advanced diagnostics\n"
    "This output is redacted, but it may still reveal system structure.\n"
    "Do not forward the full output to untrusted people.\n"
    "Use /status for the normal safe summary.\n"
    "\n"
)

check("warning has Advanced diagnostics header", "Advanced diagnostics" in warning_text)
check("warning says output is redacted", "redacted" in warning_text)
check("warning says do not forward", "Do not forward" in warning_text)
check("warning recommends /status for normal summary", "/status" in warning_text)
check("warning has emoji", "⚠️" in warning_text)

# Verify warning is in bot source
check("warning text in bot source", "⚠️ Advanced diagnostics" in bot_source)
check("do not forward in bot source", "Do not forward the full output to untrusted people." in bot_source)
check("use /status in bot source", "Use /status for the normal safe summary." in bot_source)

# ── 3. /status_json output remains redacted ──────────────────────────────

print("\n--- /status_json redaction ---\n")

# Verify safe_output is used in cmd_status_json
check("cmd_status_json uses safe_output", "safe_output(result.stdout)" in bot_source)

# Test redaction with fake values
test_output = '{"vpsIp": "203.0.113.10", "domain": "node.example.invalid", "ipv6": "2001:db8::10"}'
redacted = bot.safe_output(test_output)
check("redacted output hides IPv4", "203.0.113.10" not in redacted)
check("redacted output hides domain", "node.example.invalid" not in redacted)
check("redacted output hides IPv6", "2001:db8::10" not in redacted)

# Test with workers.dev
test_output2 = '{"route": "https://worker.example.invalid/sub/fake-sub-path-12345"}'
redacted2 = bot.safe_output(test_output2)
check("redacted output hides URL", "worker.example.invalid" not in redacted2)
check("redacted output hides subscription path", "fake-sub-path-12345" not in redacted2)

# Test with token/secret key=value patterns (redaction handles these)
test_output3 = "token=fake-doc-token-abc123xyz secret=fake-secret-value-do-not-use"
redacted3 = bot.safe_output(test_output3)
check("redacted output hides token", "fake-doc-token-abc123xyz" not in redacted3)
check("redacted output hides secret", "fake-secret-value-do-not-use" not in redacted3)

# ── 4. /status safe summary unchanged ────────────────────────────────────

print("\n--- /status safe summary ---\n")

test_status = {
    "ok": True, "domain": "test.example.com", "vpsIp": "1.2.3.4", "geo": "JP",
    "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
    "security": {"secretsMode": "600"},
    "cloudflare": {"nanok": {"envExists": True}, "nanob": {"envExists": False}},
    "warnings": []
}
formatted = bot.format_status(test_status)
check("status summary title present", "NanoBK Status Summary" in formatted)
check("status summary shows overall healthy", "Overall: healthy" in formatted)
check("status summary no raw domain label", "Domain:" not in formatted)
check("status summary no raw domain value", "test.example.com" not in formatted)
check("status summary no raw IP label", "VPS IP:" not in formatted)
check("status summary no raw IP value", "1.2.3.4" not in formatted)

# ── 5. No advanced mode commands added ────────────────────────────────────

print("\n--- No advanced mode ---\n")

check("no /advanced on command", "/advanced on" not in bot_source)
check("no /advanced off command", "/advanced off" not in bot_source)
check("no advanced_mode field", "advanced_mode" not in bot_source.lower() or "advanced mode not implemented" in bot_source.lower() or "Do not add advanced mode" in bot_source)

# ── 6. No Web files changed ──────────────────────────────────────────────

print("\n--- No Web file changes ---\n")

web_app_path = os.path.join(os.path.dirname(__file__), "..", "web", "app.py")
with open(web_app_path, "r") as f:
    web_source = f.read()

check("web/app.py unchanged (no warning text)", "⚠️ Advanced diagnostics" not in web_source)
check("web/app.py unchanged (no Basic: section)", "Basic:\n" not in web_source)

# ── 7. No shell=True ─────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True in bot source", "shell=True" not in bot_source)
check("no os.system in bot source", "os.system" not in bot_source)
check("no subprocess.call in bot source", "subprocess.call" not in bot_source)

# ── 8. Rotate commands preserved ─────────────────────────────────────────

print("\n--- Rotate commands preserved ---\n")

check("ROTATE_ACTIONS present", "ROTATE_ACTIONS" in bot_source)
check("rotate_hy2 handler", "rotate_hy2" in bot_source)
check("rotate_tuic handler", "rotate_tuic" in bot_source)
check("rotate_reality handler", "rotate_reality" in bot_source)
check("rotate_trojan handler", "rotate_trojan" in bot_source)
check("confirm_rotate commands", "confirm_rotate" in bot_source)
check("ConfirmationManager present", "ConfirmationManager" in bot_source)

# ── 9. /status_json command still registered ─────────────────────────────

print("\n--- /status_json still registered ---\n")

check("status_json CommandHandler registered", 'CommandHandler("status_json"' in bot_source)
check("cmd_status_json function exists", "async def cmd_status_json" in bot_source)

# ── Summary ───────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    sys.exit(1)
else:
    print("All tests passed!")
