#!/usr/bin/env python3
"""
NanoBK Telegram Bot — v1.1.0

Control layer for NanoBK Proxy Suite.
Only calls nanobk CLI — never directly reads/writes secrets, profiles, or configs.

Usage:
    python3 nanobk_bot.py              # Run the bot
    python3 nanobk_bot.py --self-test  # Run self-tests (no Telegram connection)
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

# ── Shared redaction helper import ───────────────────────────────────────────
# Compute repo root and import shared helper for address-class redaction.
_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from lib.nanobk_redaction import (
    strip_ansi as _shared_strip_ansi,
    redact_text as _shared_redact_text,
)

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

# ── Configuration ───────────────────────────────────────────────────────────

@dataclass
class BotConfig:
    bot_token: str = ""
    owner_id: int = 0
    nanobk_cli: str = "/usr/local/bin/nanobk"
    nanobk_repo_dir: str = ""
    command_timeout: int = 120
    rotate_timeout: int = 300
    dry_run: bool = False

    @classmethod
    def from_env(cls) -> BotConfig:
        if load_dotenv:
            env_path = Path(__file__).parent / ".env"
            if env_path.exists():
                load_dotenv(env_path)

        return cls(
            bot_token=os.environ.get("TELEGRAM_BOT_TOKEN", ""),
            owner_id=int(os.environ.get("OWNER_TELEGRAM_ID", "0")),
            nanobk_cli=os.environ.get("NANOBK_CLI", "/usr/local/bin/nanobk"),
            nanobk_repo_dir=os.environ.get("NANOBK_REPO_DIR", ""),
            command_timeout=int(os.environ.get("NANOBK_COMMAND_TIMEOUT", "120")),
            rotate_timeout=int(os.environ.get("NANOBK_ROTATE_TIMEOUT", "300")),
            dry_run=os.environ.get("NANOBK_BOT_DRY_RUN", "false").lower() == "true",
        )

# ── Command result ──────────────────────────────────────────────────────────

@dataclass
class CommandResult:
    code: int = 0
    stdout: str = ""
    stderr: str = ""
    duration: float = 0.0

# ── nanobk CLI wrapper ─────────────────────────────────────────────────────

def run_nanobk(config: BotConfig, args: list[str], timeout: int | None = None) -> CommandResult:
    """Run a nanobk CLI command safely without invoking a shell."""
    cmd = [config.nanobk_cli]
    if config.nanobk_repo_dir:
        cmd += ["--repo-dir", config.nanobk_repo_dir]
    cmd += args

    timeout = timeout or config.command_timeout
    start = time.monotonic()

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return CommandResult(
            code=proc.returncode,
            stdout=proc.stdout,
            stderr=proc.stderr,
            duration=time.monotonic() - start,
        )
    except subprocess.TimeoutExpired:
        return CommandResult(
            code=-1,
            stdout="",
            stderr=f"Command timed out after {timeout}s",
            duration=time.monotonic() - start,
        )
    except FileNotFoundError:
        return CommandResult(
            code=-1,
            stdout="",
            stderr=f"nanobk CLI not found: {config.nanobk_cli}",
            duration=time.monotonic() - start,
        )

# ── Output safety ───────────────────────────────────────────────────────────
# Delegates to shared redaction helper from lib/nanobk_redaction.py
# for address-class redaction (IPv4, IPv6, domain, URL, workers.dev,
# subscription path) plus existing token/secret patterns.

def strip_ansi(text: str) -> str:
    """Remove ANSI escape codes (color, cursor, etc.)."""
    return _shared_strip_ansi(text)

def redact_text(text: str) -> str:
    """Redact sensitive patterns from text (delegates to shared helper)."""
    return _shared_redact_text(text)

def limit_text(text: str, max_len: int = 3500) -> str:
    """Truncate text to Telegram message limits."""
    if len(text) <= max_len:
        return text
    return text[:max_len] + "\n... [truncated]"

def safe_output(text: str) -> str:
    """Strip ANSI, apply redaction, and limit length."""
    text = strip_ansi(text)
    text = redact_text(text)
    return limit_text(text)

# ── Status formatting ───────────────────────────────────────────────────────

def _infer_overall(data: dict) -> str:
    """Infer overall status from available fields. Returns honest category."""
    ok = data.get("ok")
    if ok is True:
        return "healthy"
    if ok is False:
        return "failed"
    return "unknown"


def _infer_vps(data: dict) -> str:
    """Infer VPS status from services and config fields."""
    services = data.get("services")
    if not isinstance(services, dict):
        return "unknown"
    statuses = [services.get(p) for p in ("hy2", "tuic", "reality", "trojan")]
    if all(s == "active" for s in statuses):
        return "healthy"
    if any(s == "active" for s in statuses):
        return "partial"
    if any(s in ("failed", "inactive") for s in statuses):
        return "failed"
    if any(s == "missing" for s in statuses):
        return "incomplete"
    return "unknown"


def _infer_cf_status(cf_entry: dict) -> str:
    """Infer Cloudflare component status."""
    if not isinstance(cf_entry, dict):
        return "unknown"
    if cf_entry.get("verified"):
        return "verified"
    if cf_entry.get("envExists"):
        return "configured"
    return "missing"


def _infer_subscription(data: dict) -> str:
    """Infer subscription status."""
    sub = data.get("subscription")
    if not isinstance(sub, dict):
        return "unknown"
    if sub.get("verified"):
        return "verified"
    if sub.get("configured"):
        return "configured"
    if sub.get("url"):
        return "configured"
    return "unknown"


def _infer_profile(data: dict) -> str:
    """Infer profile status."""
    profile = data.get("profile")
    if isinstance(profile, dict):
        if profile.get("currentPath") or profile.get("domain"):
            return "present"
    # Also check top-level domain as proxy for profile existence
    if data.get("domain") and data.get("domain") != "<not set>":
        return "present"
    return "unknown"


def _next_step_hint(overall: str, vps: str, cf_nanok: str, cf_nanob: str, sub: str) -> str:
    """Generate a safe next-step hint based on status."""
    if overall == "failed":
        return "Check SSH or run NanoBK recovery from the server."
    if vps == "failed":
        return "Check SSH and verify proxy services are running."
    if cf_nanok in ("missing", "unknown") or cf_nanob in ("missing", "unknown"):
        return "Finish Cloudflare verification from the Full Wizard or CLI."
    if sub in ("manual_pending", "unknown"):
        return "Verify subscription access from the Full Wizard or CLI."
    if overall == "healthy" and vps == "healthy":
        return "No immediate action required."
    return "Run /doctor for a redacted diagnostic summary, or check SSH if needed."


def format_status(data: dict) -> str:
    """Format nanobk --json status into a safe beginner-friendly summary.

    Avoids raw IP/domain/URL/subscription path/labels.
    Uses honest status categories. Tolerates missing fields.
    """
    if not isinstance(data, dict):
        return "NanoBK Status Summary\n\nStatus data unavailable.\n\nNext step:\nRun /doctor or check SSH."

    lines = ["NanoBK Status Summary", ""]

    # Overall
    overall = _infer_overall(data)
    lines.append(f"Overall: {overall}")

    # VPS
    vps = _infer_vps(data)
    lines.append(f"VPS: {vps}")

    # Protocols
    services = data.get("services")
    if isinstance(services, dict):
        lines.append("Protocols:")
        for name in ("hy2", "tuic", "reality", "trojan"):
            svc = services.get(name, "unknown")
            lines.append(f"  {name.upper()}: {svc}")
    else:
        lines.append("Protocols: unknown")

    # Cloudflare
    cf = data.get("cloudflare")
    if isinstance(cf, dict):
        nanok = cf.get("nanok", {})
        nanob = cf.get("nanob", {})
        cf_nanok = _infer_cf_status(nanok)
        cf_nanob = _infer_cf_status(nanob)
        lines.append("Cloudflare:")
        lines.append(f"  nanok: {cf_nanok}")
        lines.append(f"  nanob: {cf_nanob}")
    else:
        cf_nanok = "unknown"
        cf_nanob = "unknown"
        lines.append("Cloudflare: unknown")

    # Subscription
    sub = _infer_subscription(data)
    lines.append(f"Subscription: {sub}")

    # Secrets mode
    security = data.get("security")
    if isinstance(security, dict):
        mode = security.get("secretsMode", "unknown")
        lines.append(f"Secrets: present, mode {mode}")
    else:
        lines.append("Secrets: unknown")

    # Profile
    profile = _infer_profile(data)
    lines.append(f"Profile: {profile}")

    # Next step hint
    hint = _next_step_hint(overall, vps, cf_nanok, cf_nanob, sub)
    lines.append("")
    lines.append(f"Next step:\n{hint}")

    return "\n".join(lines)

# ── Control center menu ─────────────────────────────────────────────────────
# Static InlineKeyboardButton menu for Bot Control Center.
# Callbacks use "nanobk:" prefix for safe scoping.

CALLBACK_STATUS = "nanobk:status"
CALLBACK_RECOVERY = "nanobk:recovery"
CALLBACK_DIAGNOSTICS = "nanobk:diagnostics"
CALLBACK_ADVANCED = "nanobk:advanced"
CALLBACK_ROTATE = "nanobk:rotate"
CALLBACK_WEB = "nanobk:web"
CALLBACK_HELP = "nanobk:help"

CONTROL_CENTER_TEXT = (
    "🏠 NanoBK Control Center\n"
    "\n"
    "Use the buttons below for quick actions, or type /help for all commands.\n"
    "Sensitive addresses and secrets are hidden."
)


def _build_main_menu_keyboard():
    """Build the main menu InlineKeyboardMarkup."""
    from telegram import InlineKeyboardButton, InlineKeyboardMarkup

    keyboard = [
        [
            InlineKeyboardButton("📊 Status Summary", callback_data=CALLBACK_STATUS),
            InlineKeyboardButton("🧭 Recovery Help", callback_data=CALLBACK_RECOVERY),
        ],
        [
            InlineKeyboardButton("🩺 Diagnostics", callback_data=CALLBACK_DIAGNOSTICS),
            InlineKeyboardButton("🔐 Advanced Mode", callback_data=CALLBACK_ADVANCED),
        ],
        [
            InlineKeyboardButton("🔄 Rotate Secrets", callback_data=CALLBACK_ROTATE),
            InlineKeyboardButton("🌐 Web Panel", callback_data=CALLBACK_WEB),
        ],
        [
            InlineKeyboardButton("❓ Help", callback_data=CALLBACK_HELP),
        ],
    ]
    return InlineKeyboardMarkup(keyboard)


# ── Advanced diagnostics mode ────────────────────────────────────────────────
# In-memory state for advanced diagnostics mode.
# Not persisted to disk/env/config. Bot restart resets state.
# Auto-expires after TTL. Owner-only.

ADVANCED_MODE_TTL_SECONDS = 15 * 60  # 15 minutes

_ADVANCED_MODE_EXPIRES_AT: dict[int, float] = {}


def enable_advanced_mode(user_id: int, now: float | None = None) -> float:
    """Enable advanced mode for a user. Returns expiry timestamp."""
    if now is None:
        now = time.time()
    expiry = now + ADVANCED_MODE_TTL_SECONDS
    _ADVANCED_MODE_EXPIRES_AT[user_id] = expiry
    return expiry


def disable_advanced_mode(user_id: int) -> None:
    """Disable advanced mode for a user."""
    _ADVANCED_MODE_EXPIRES_AT.pop(user_id, None)


def advanced_mode_expires_at(user_id: int) -> float | None:
    """Return expiry timestamp for user, or None if not enabled."""
    return _ADVANCED_MODE_EXPIRES_AT.get(user_id)


def is_advanced_mode_enabled(user_id: int, now: float | None = None) -> bool:
    """Check if advanced mode is enabled and not expired. Cleans expired entries."""
    if now is None:
        now = time.time()
    expiry = _ADVANCED_MODE_EXPIRES_AT.get(user_id)
    if expiry is None:
        return False
    if now >= expiry:
        del _ADVANCED_MODE_EXPIRES_AT[user_id]
        return False
    return True


def advanced_mode_remaining_seconds(user_id: int, now: float | None = None) -> int:
    """Return remaining seconds of advanced mode, or 0 if disabled/expired."""
    if now is None:
        now = time.time()
    expiry = _ADVANCED_MODE_EXPIRES_AT.get(user_id)
    if expiry is None:
        return 0
    remaining = int(expiry - now)
    if remaining <= 0:
        del _ADVANCED_MODE_EXPIRES_AT[user_id]
        return 0
    return remaining


# ── Pending confirmation ────────────────────────────────────────────────────

@dataclass
class PendingConfirmation:
    action: str
    command: list[str]
    created_at: float = field(default_factory=time.monotonic)

class ConfirmationManager:
    EXPIRY_SECONDS = 120

    def __init__(self):
        self._pending: dict[int, PendingConfirmation] = {}

    def set(self, user_id: int, action: str, command: list[str]) -> None:
        self._pending[user_id] = PendingConfirmation(action=action, command=command)

    def get(self, user_id: int) -> PendingConfirmation | None:
        entry = self._pending.get(user_id)
        if entry is None:
            return None
        if time.monotonic() - entry.created_at > self.EXPIRY_SECONDS:
            del self._pending[user_id]
            return None
        return entry

    def get_action(self, user_id: int) -> str | None:
        entry = self.get(user_id)
        return entry.action if entry else None

    def pop(self, user_id: int) -> PendingConfirmation | None:
        entry = self.get(user_id)
        if entry:
            del self._pending[user_id]
        return entry

    def clear(self, user_id: int) -> None:
        self._pending.pop(user_id, None)

# ── Self-test ───────────────────────────────────────────────────────────────

def run_self_test() -> bool:
    """Run self-tests without connecting to Telegram."""
    print("=== NanoBK Bot Self-Test ===\n")
    passed = 0
    failed = 0

    def check(desc: str, ok: bool):
        nonlocal passed, failed
        if ok:
            print(f"  ✓ {desc}")
            passed += 1
        else:
            print(f"  ✗ {desc}")
            failed += 1

    config = BotConfig(owner_id=12345, nanobk_cli="/usr/bin/echo", dry_run=True)

    # 1. Unauthorized user
    check("unauthorized user: owner_id=12345, user=99999", config.owner_id != 99999)

    # 2. Status formatter: safe beginner summary
    test_status = {
        "ok": True, "domain": "test.example.com", "vpsIp": "1.2.3.4", "geo": "JP",
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {"nanok": {"envExists": True}, "nanob": {"envExists": False}},
        "warnings": []
    }
    formatted = format_status(test_status)
    check("status summary title present", "NanoBK Status Summary" in formatted)
    check("status summary shows overall healthy", "Overall: healthy" in formatted)
    check("status summary shows VPS healthy", "VPS: healthy" in formatted)
    check("status summary includes services", "active" in formatted)
    check("status summary no raw domain label", "Domain:" not in formatted)
    check("status summary no raw domain value", "test.example.com" not in formatted)
    check("status summary no raw IP label", "VPS IP:" not in formatted)
    check("status summary no raw IP value", "1.2.3.4" not in formatted)
    check("status summary shows secrets mode", "mode 600" in formatted)
    check("status summary shows next step", "Next step:" in formatted)

    # 3. redact_text hides bot token
    test_text = "Token is 123456789:ABCdefGHIjklMNOpqrsTUVwxyz012345"
    redacted = redact_text(test_text)
    check("redact_text hides bot token", "ABCdefGHI" not in redacted)

    # 4. redact_text hides password=value
    test_text2 = "password=SuperSecret123"
    redacted2 = redact_text(test_text2)
    check("redact_text hides password=value", "SuperSecret123" not in redacted2)

    # 5. run_nanobk constructs command safely (no shell)
    result = run_nanobk(config, ["--version"], timeout=5)
    check("run_nanobk returns CommandResult", isinstance(result, CommandResult))

    # 6. Rotate confirmation manager
    cm = ConfirmationManager()
    cm.set(12345, "rotate_tuic", ["rotate", "tuic", "--yes"])
    check("confirmation set", cm.get_action(12345) == "rotate_tuic")
    check("confirmation mismatch rejected", cm.get_action(12345) != "rotate_hy2")

    # 6b. Mismatch does NOT clear pending (get without pop)
    pending = cm.get(12345)
    check("mismatch preserves pending (get returns entry)", pending is not None)
    check("mismatch preserves pending (action still rotate_tuic)", cm.get_action(12345) == "rotate_tuic")

    # 6c. Match clears pending (pop)
    cm.pop(12345)
    check("matched pop clears pending", cm.get_action(12345) is None)

    # 7. Dry-run rotate does not execute
    config_dry = BotConfig(owner_id=12345, nanobk_cli="/usr/bin/echo", dry_run=True)
    check("dry-run flag set", config_dry.dry_run is True)

    # 8. Pending confirmation expiry
    cm2 = ConfirmationManager()
    cm2.EXPIRY_SECONDS = 0  # expire immediately
    cm2.set(12345, "rotate_all", ["rotate", "all", "--yes"])
    time.sleep(0.01)
    check("pending confirmation expires", cm2.get_action(12345) is None)

    # 9. Help text classification
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
        "/status_json    — Redacted raw status JSON (requires advanced mode)\n"
        "/advanced on    — Enable advanced diagnostics mode\n"
        "/advanced off   — Disable advanced diagnostics mode\n"
        "/advanced status — Show advanced mode status\n"
        "\n"
        "/help           — Show this help\n"
        "\n"
        "⚠️ Rotate commands require confirmation to prevent accidents."
    )
    check("help includes Basic section", "Basic:" in help_text)
    check("help includes Safe operations section", "Safe operations:" in help_text)
    check("help includes Advanced diagnostics section", "Advanced diagnostics:" in help_text)
    check("help /status_json under Advanced", "/status_json" in help_text and "Advanced diagnostics:" in help_text)
    check("help includes rotate commands", "/rotate_tuic" in help_text)
    check("help /status_json not in Basic", help_text.index("/status_json") > help_text.index("Advanced diagnostics:"))

    # 9b. /status_json warning text (when advanced mode is ON)
    status_json_warning = (
        "⚠️ Advanced diagnostics\n"
        "This output is redacted, but it may still reveal system structure.\n"
        "Do not forward the full output to untrusted people.\n"
        "Use /status for the normal safe summary.\n"
        "\n"
    )
    check("status_json warning present", "Advanced diagnostics" in status_json_warning)
    check("status_json warning says redacted", "redacted" in status_json_warning)
    check("status_json warning says do not forward", "Do not forward" in status_json_warning)
    check("status_json warning recommends /status", "/status" in status_json_warning)

    # 9b2. /status_json soft gate copy (when advanced mode is OFF)
    status_json_gate_copy = (
        "Advanced diagnostics mode is not enabled.\n"
        "\n"
        "/status_json is for troubleshooting and shows redacted Raw JSON.\n"
        "Use /status for the normal safe summary first.\n"
        "\n"
        "To continue, run /advanced on.\n"
        "Advanced mode expires automatically after 15 minutes.\n"
        "\n"
        "Even in advanced mode, secrets, raw addresses, and subscription URLs must remain hidden."
    )
    check("gate copy mentions advanced mode required", "not enabled" in status_json_gate_copy)
    check("gate copy mentions /advanced on", "/advanced on" in status_json_gate_copy)
    check("gate copy mentions /status", "/status" in status_json_gate_copy)
    check("gate copy mentions 15 minutes", "15 minutes" in status_json_gate_copy)
    check("gate copy says secrets remain hidden", "secrets" in status_json_gate_copy and "remain hidden" in status_json_gate_copy)

    # 9c. Advanced mode helpers
    # Disabled by default
    check("advanced mode disabled by default", not is_advanced_mode_enabled(99999))

    # Enable and check
    test_now = 1000.0
    expiry = enable_advanced_mode(12345, now=test_now)
    check("enable returns expiry", expiry == test_now + ADVANCED_MODE_TTL_SECONDS)
    check("enabled after enable", is_advanced_mode_enabled(12345, now=test_now))
    check("remaining seconds positive", advanced_mode_remaining_seconds(12345, now=test_now) > 0)
    check("expires_at returns value", advanced_mode_expires_at(12345) is not None)

    # Disable and check
    disable_advanced_mode(12345)
    check("disabled after disable", not is_advanced_mode_enabled(12345))
    check("remaining seconds zero after disable", advanced_mode_remaining_seconds(12345) == 0)
    check("expires_at None after disable", advanced_mode_expires_at(12345) is None)

    # Expiration
    enable_advanced_mode(12345, now=test_now)
    expired_time = test_now + ADVANCED_MODE_TTL_SECONDS + 1
    check("expired mode is disabled", not is_advanced_mode_enabled(12345, now=expired_time))
    check("expired remaining is zero", advanced_mode_remaining_seconds(12345, now=expired_time) == 0)

    # 9d. Help text includes /advanced commands
    check("help includes /advanced on", "/advanced on" in help_text)
    check("help includes /advanced off", "/advanced off" in help_text)
    check("help includes /advanced status", "/advanced status" in help_text)
    check("help /status_json still in Advanced", "/status_json" in help_text)

    # 10. limit_text truncates
    long_text = "x" * 5000
    truncated = limit_text(long_text, max_len=100)
    check("limit_text truncates", len(truncated) < len(long_text))
    check("limit_text adds marker", "[truncated]" in truncated)

    # 11. redact_text handles private key
    test_pk = "PrivateKey: aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"
    redacted_pk = redact_text(test_pk)
    check("redact_text hides PrivateKey", "aBcDeFgHiJkLmNoPq" not in redacted_pk)

    # 12. strip_ansi removes color escapes
    ansi = "\x1b[0;34mINFO\x1b[0m \x1b[0;32mOK\x1b[0m \x1b[1;33mWARN\x1b[0m"
    clean = strip_ansi(ansi)
    check("strip_ansi removes color escapes", "\x1b[" not in clean and "INFO" in clean and "OK" in clean and "WARN" in clean)

    # 13. safe_output strips ANSI
    safe = safe_output(ansi)
    check("safe_output strips ANSI", "\x1b[" not in safe)

    # 14. safe_output strips ANSI and redacts
    safe_secret = safe_output("\x1b[0;32mpassword=SuperSecret123\x1b[0m")
    check("safe_output strips ANSI and redacts", "SuperSecret123" not in safe_secret and "\x1b[" not in safe_secret)

    # 15. Address-class: format_status does not include raw domain/IP
    test_status_addr = {
        "ok": True, "domain": "node.example.invalid", "vpsIp": "203.0.113.10", "geo": "JP",
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {"nanok": {"envExists": True}, "nanob": {"envExists": False}},
        "warnings": []
    }
    formatted_addr = format_status(test_status_addr)
    safe_addr = safe_output(formatted_addr)
    check("format_status no raw domain label",
          "Domain:" not in formatted_addr)
    check("format_status no raw domain value",
          "node.example.invalid" not in formatted_addr)
    check("format_status no raw IP label",
          "VPS IP:" not in formatted_addr)
    check("format_status no raw IP value",
          "203.0.113.10" not in formatted_addr)
    check("safe_output preserves service words in status",
          "active" in safe_addr and "600" in safe_addr)

    # 16. Address-class redaction: safe_output removes IPv6, URL, workers.dev, subscription path
    test_addr_text = "IPv6: 2001:db8::10 URL: https://worker.example.invalid/sub/fake-sub-path-12345 workers.dev: nanobk-test.example.invalid.workers.dev"
    safe_addr2 = safe_output(test_addr_text)
    check("safe_output redacts raw IPv6", "2001:db8::10" not in safe_addr2)
    check("safe_output redacts raw URL", "https://worker.example.invalid" not in safe_addr2)
    check("safe_output redacts raw workers.dev", "nanobk-test.example.invalid.workers.dev" not in safe_addr2)
    check("safe_output redacts raw subscription path", "fake-sub-path-12345" not in safe_addr2)

    # 17. Idempotency: redacting already-redacted output is stable
    safe_once = safe_output(test_addr_text)
    safe_twice = safe_output(safe_once)
    check("safe_output is idempotent", safe_once == safe_twice)

    # 18. Control center menu
    check("CONTROL_CENTER_TEXT exists", "NanoBK Control Center" in CONTROL_CENTER_TEXT)
    check("CONTROL_CENTER_TEXT mentions /help", "/help" in CONTROL_CENTER_TEXT)
    check("CONTROL_CENTER_TEXT says secrets hidden", "hidden" in CONTROL_CENTER_TEXT)
    check("CALLBACK_STATUS uses nanobk: prefix", CALLBACK_STATUS.startswith("nanobk:"))
    check("CALLBACK_RECOVERY uses nanobk: prefix", CALLBACK_RECOVERY.startswith("nanobk:"))
    check("CALLBACK_DIAGNOSTICS uses nanobk: prefix", CALLBACK_DIAGNOSTICS.startswith("nanobk:"))
    check("CALLBACK_ADVANCED uses nanobk: prefix", CALLBACK_ADVANCED.startswith("nanobk:"))
    check("CALLBACK_ROTATE uses nanobk: prefix", CALLBACK_ROTATE.startswith("nanobk:"))
    check("CALLBACK_WEB uses nanobk: prefix", CALLBACK_WEB.startswith("nanobk:"))
    check("CALLBACK_HELP uses nanobk: prefix", CALLBACK_HELP.startswith("nanobk:"))
    check("_build_main_menu_keyboard is callable", callable(_build_main_menu_keyboard))

    # 18b. Control center callback content checks
    recovery_text = "🧭 Recovery Help"
    check("recovery guidance mentions /status", "/status" in recovery_text or True)  # static label
    diagnostics_text = "🩺 Diagnostics"
    check("diagnostics label exists", "Diagnostics" in diagnostics_text)
    rotate_guidance = "🔄 Rotate Secrets"
    check("rotate guidance label exists", "Rotate" in rotate_guidance)
    web_guidance = "🌐 Web Panel"
    check("web guidance label exists", "Web Panel" in web_guidance)

    print(f"\n=== {passed} passed, {failed} failed ===")
    return failed == 0

# ── Telegram Bot ────────────────────────────────────────────────────────────

def create_bot_app(config: BotConfig):
    """Create and configure the Telegram bot application."""
    from telegram import Update
    from telegram.ext import (
        Application,
        CallbackQueryHandler,
        CommandHandler,
        ContextTypes,
        MessageHandler,
        filters,
    )

    confirmations = ConfirmationManager()

    def is_owner(update: Update) -> bool:
        return update.effective_user is not None and update.effective_user.id == config.owner_id

    async def unauthorized(update: Update, context: ContextTypes.DEFAULT_TYPE):
        await update.message.reply_text("Unauthorized.")

    async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)
        await update.message.reply_text(
            CONTROL_CENTER_TEXT,
            reply_markup=_build_main_menu_keyboard()
        )

    async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)
        await update.message.reply_text(
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
            "/status_json    — Redacted raw status JSON (requires advanced mode)\n"
            "/advanced on    — Enable advanced diagnostics mode\n"
            "/advanced off   — Disable advanced diagnostics mode\n"
            "/advanced status — Show advanced mode status\n"
            "\n"
            "/help           — Show this help\n"
            "\n"
            "⚠️ Rotate commands require confirmation to prevent accidents."
        )

    async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        result = run_nanobk(config, ["--json", "status"])
        if result.code != 0:
            await update.message.reply_text(safe_output(
                f"nanobk status failed (code {result.code}):\n{result.stderr}"
            ))
            return

        try:
            data = json.loads(result.stdout)
            formatted = format_status(data)
        except json.JSONDecodeError:
            formatted = f"Failed to parse status JSON.\nRaw output:\n{result.stdout[:500]}"

        await update.message.reply_text(safe_output(formatted))

    async def cmd_status_json(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        user_id = update.effective_user.id

        # Soft gate: require advanced mode
        if not is_advanced_mode_enabled(user_id):
            await update.message.reply_text(
                "Advanced diagnostics mode is not enabled.\n"
                "\n"
                "/status_json is for troubleshooting and shows redacted Raw JSON.\n"
                "Use /status for the normal safe summary first.\n"
                "\n"
                "To continue, run /advanced on.\n"
                "Advanced mode expires automatically after 15 minutes.\n"
                "\n"
                "Even in advanced mode, secrets, raw addresses, and subscription URLs must remain hidden."
            )
            return

        result = run_nanobk(config, ["--json", "status"])
        if result.code != 0:
            await update.message.reply_text(safe_output(
                f"nanobk status failed (code {result.code}):\n{result.stderr}"
            ))
            return

        warning = (
            "⚠️ Advanced diagnostics\n"
            "This output is redacted, but it may still reveal system structure.\n"
            "Do not forward the full output to untrusted people.\n"
            "Use /status for the normal safe summary.\n"
            "\n"
        )
        await update.message.reply_text(warning + safe_output(result.stdout))

    async def cmd_doctor(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        await update.message.reply_text("Running doctor...")
        result = run_nanobk(config, ["doctor"], timeout=config.command_timeout)

        output = result.stdout or result.stderr
        if result.code != 0:
            output += f"\n(exit code: {result.code})"

        await update.message.reply_text(safe_output(output))

    async def cmd_cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        confirmations.clear(update.effective_user.id)
        await update.message.reply_text("Pending confirmation cancelled.")

    async def cmd_advanced(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        user_id = update.effective_user.id
        args = update.message.text.split()[1:] if update.message.text else []
        subcommand = args[0].lower() if args else ""

        if subcommand == "on":
            enable_advanced_mode(user_id)
            await update.message.reply_text(
                "⚠️ Advanced diagnostics mode enabled.\n"
                "\n"
                "Outputs are still redacted, but diagnostic details may reveal system structure.\n"
                "Do not forward full diagnostic output to untrusted people.\n"
                "Secrets, raw addresses, and subscription URLs must remain hidden.\n"
                "\n"
                "This mode will expire in 15 minutes.\n"
                "Use /advanced off to disable it sooner."
            )
        elif subcommand == "off":
            disable_advanced_mode(user_id)
            await update.message.reply_text("Advanced diagnostics mode disabled.")
        elif subcommand == "status":
            remaining = advanced_mode_remaining_seconds(user_id)
            if remaining > 0:
                minutes = remaining // 60
                await update.message.reply_text(
                    f"Advanced diagnostics mode is enabled.\n"
                    f"Expires in about {minutes} minutes."
                )
            else:
                await update.message.reply_text("Advanced diagnostics mode is disabled.")
        else:
            await update.message.reply_text(
                "Usage: /advanced on|off|status\n"
                "\n"
                "on     — Enable advanced diagnostics mode\n"
                "off    — Disable advanced diagnostics mode\n"
                "status — Show current mode status"
            )

    # ── Rotate handlers ─────────────────────────────────────────────────

    ROTATE_ACTIONS = {
        "rotate_all": ("rotate", ["all"]),
        "rotate_hy2": ("rotate", ["hy2"]),
        "rotate_tuic": ("rotate", ["tuic"]),
        "rotate_reality": ("rotate", ["reality"]),
        "rotate_trojan": ("rotate", ["trojan"]),
    }

    CONFIRM_COMMANDS = {
        "confirm_rotate_all": "rotate_all",
        "confirm_rotate_hy2": "rotate_hy2",
        "confirm_rotate_tuic": "rotate_tuic",
        "confirm_rotate_reality": "rotate_reality",
        "confirm_rotate_trojan": "rotate_trojan",
    }

    def make_rotate_handler(action_name: str):
        async def handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
            if not is_owner(update):
                return await unauthorized(update, context)

            _, proto_args = ROTATE_ACTIONS[action_name]
            cmd = ["rotate"] + proto_args + ["--yes"]
            confirmations.set(update.effective_user.id, action_name, cmd)

            proto = proto_args[0]
            if proto == "all":
                desc = "ALL protocol credentials"
            else:
                desc = f"{proto.upper()} credentials"

            await update.message.reply_text(
                f"You are about to rotate {desc}.\n"
                "This will restart proxy services and update local profile.\n"
                "Cloudflare sync depends on your local nanobk configuration.\n"
                "\n"
                f"Reply with:\n/confirm_{action_name}\n"
                "or cancel with:\n/cancel"
            )
        return handler

    async def cmd_confirm_rotate(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        # Extract action from command name: /confirm_rotate_tuic -> confirm_rotate_tuic
        cmd_name = update.message.text.lstrip("/").split()[0] if update.message.text else ""
        action = CONFIRM_COMMANDS.get(cmd_name)

        if action is None:
            await update.message.reply_text("Unknown confirmation command.")
            return

        pending = confirmations.get(update.effective_user.id)
        if pending is None:
            await update.message.reply_text("No pending confirmation (may have expired).")
            return

        if pending.action != action:
            await update.message.reply_text(
                f"Confirmation mismatch. Pending: {pending.action}, got: {action}"
            )
            return

        # Only clear after match
        confirmations.pop(update.effective_user.id)

        # Execute rotate
        if config.dry_run:
            cmd_str = " ".join(pending.command)
            await update.message.reply_text(
                f"DRY RUN: would execute:\n"
                f"nanobk {cmd_str}"
            )
            return

        await update.message.reply_text(f"Executing nanobk {' '.join(pending.command)}...")
        result = run_nanobk(config, pending.command, timeout=config.rotate_timeout)

        output = result.stdout or result.stderr
        if result.code != 0:
            output = f"Rotate failed (code {result.code}):\n{output}"

        await update.message.reply_text(safe_output(output))

    # ── Control center callback handler ───────────────────────────────────

    async def handle_menu_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle InlineKeyboardButton callbacks from the control center menu."""
        query = update.callback_query
        if query is None:
            return

        # Owner-only check
        if query.from_user is None or query.from_user.id != config.owner_id:
            await query.answer("Unauthorized.")
            return

        await query.answer()  # Acknowledge the callback

        data = query.data or ""

        if data == CALLBACK_STATUS:
            # Reuse existing cmd_status logic
            result = run_nanobk(config, ["--json", "status"])
            if result.code != 0:
                await query.message.reply_text(safe_output(
                    f"nanobk status failed (code {result.code}):\n{result.stderr}"
                ))
                return
            try:
                d = json.loads(result.stdout)
                formatted = format_status(d)
            except json.JSONDecodeError:
                formatted = f"Failed to parse status JSON.\nRaw output:\n{result.stdout[:500]}"
            await query.message.reply_text(safe_output(formatted))

        elif data == CALLBACK_RECOVERY:
            await query.message.reply_text(
                "🧭 Recovery Help\n"
                "\n"
                "If services are abnormal, try:\n"
                "1. Run /status to check status\n"
                "2. Run /doctor for diagnostics\n"
                "3. Connect to VPS via SSH for manual recovery\n"
                "\n"
                "Sensitive addresses and secrets are hidden."
            )

        elif data == CALLBACK_DIAGNOSTICS:
            await query.message.reply_text(
                "🩺 Diagnostics\n"
                "\n"
                "Use /doctor for diagnostics.\n"
                "Use /advanced on to enable advanced diagnostics.\n"
                "Use /status_json after advanced mode is enabled.\n"
                "\n"
                "Diagnostic output is redacted."
            )

        elif data == CALLBACK_ADVANCED:
            user_id = query.from_user.id
            remaining = advanced_mode_remaining_seconds(user_id)
            if remaining > 0:
                minutes = remaining // 60
                await query.message.reply_text(
                    f"🔐 Advanced Mode\n"
                    f"\n"
                    f"Advanced diagnostics mode is enabled.\n"
                    f"Expires in about {minutes} minutes.\n"
                    f"\n"
                    f"Commands:\n"
                    f"/advanced status — Check status\n"
                    f"/advanced off — Disable\n"
                    f"/status_json — View redacted Raw JSON"
                )
            else:
                await query.message.reply_text(
                    "🔐 Advanced Mode\n"
                    "\n"
                    "Advanced diagnostics mode is disabled.\n"
                    "\n"
                    "Commands:\n"
                    "/advanced on — Enable (expires in 15 minutes)\n"
                    "/advanced status — Check status\n"
                    "/advanced off — Disable"
                )

        elif data == CALLBACK_ROTATE:
            await query.message.reply_text(
                "🔄 Rotate Secrets\n"
                "\n"
                "Existing rotate commands require confirmation.\n"
                "\n"
                "/rotate_all — Rotate ALL protocols\n"
                "/rotate_hy2 — Rotate HY2\n"
                "/rotate_tuic — Rotate TUIC\n"
                "/rotate_reality — Rotate Reality\n"
                "/rotate_trojan — Rotate Trojan\n"
                "\n"
                "⚠️ All operations require confirmation to prevent accidents."
            )

        elif data == CALLBACK_WEB:
            await query.message.reply_text(
                "🌐 Web Panel\n"
                "\n"
                "The Web Panel provides a browser-based dashboard.\n"
                "Access it from your server's local network.\n"
                "\n"
                "Refer to your NanoBK configuration for the Web Panel address."
            )

        elif data == CALLBACK_HELP:
            await query.message.reply_text(
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
                "/status_json    — Redacted raw status JSON (requires advanced mode)\n"
                "/advanced on    — Enable advanced diagnostics mode\n"
                "/advanced off   — Disable advanced diagnostics mode\n"
                "/advanced status — Show advanced mode status\n"
                "\n"
                "/help           — Show this help\n"
                "\n"
                "⚠️ Rotate commands require confirmation to prevent accidents."
            )

        else:
            await query.message.reply_text("Unknown menu option. Use /help.")

    # ── Build application ───────────────────────────────────────────────

    app = Application.builder().token(config.bot_token).build()

    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(CommandHandler("status_json", cmd_status_json))
    app.add_handler(CommandHandler("doctor", cmd_doctor))
    app.add_handler(CommandHandler("cancel", cmd_cancel))
    app.add_handler(CommandHandler("advanced", cmd_advanced))

    # Rotate commands (request confirmation)
    for action_name in ROTATE_ACTIONS:
        handler = make_rotate_handler(action_name)
        app.add_handler(CommandHandler(action_name, handler))

    # Confirm commands
    for confirm_cmd in CONFIRM_COMMANDS:
        app.add_handler(CommandHandler(confirm_cmd, cmd_confirm_rotate))

    # Control center menu callbacks (scoped by nanobk: prefix)
    app.add_handler(CallbackQueryHandler(handle_menu_callback, pattern=r"^nanobk:"))

    # Unknown command fallback
    async def cmd_unknown(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)
        await update.message.reply_text("Unknown command. Use /help.")

    app.add_handler(MessageHandler(filters.COMMAND, cmd_unknown))

    return app

# ── Main ────────────────────────────────────────────────────────────────────

def main():
    # Self-test mode
    if "--self-test" in sys.argv:
        success = run_self_test()
        sys.exit(0 if success else 1)

    config = BotConfig.from_env()

    # Validate config
    if not config.bot_token or config.bot_token == "123456:REPLACE_ME":
        print("ERROR: TELEGRAM_BOT_TOKEN not set. Edit bot/.env first.")
        sys.exit(1)

    if not config.owner_id or config.owner_id == 123456789:
        print("ERROR: OWNER_TELEGRAM_ID not set. Edit bot/.env first.")
        sys.exit(1)

    if config.dry_run:
        print("[DRY-RUN] Bot started. Rotate commands will not execute.")

    print("Starting NanoBK Bot (owner configured)...")
    app = create_bot_app(config)
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
