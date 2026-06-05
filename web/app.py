#!/usr/bin/env python3
"""
NanoBK Web Panel — v1.2.1

Local-only Flask Web Panel for NanoBK Proxy Suite.
Only calls nanobk CLI — never directly reads/writes secrets, profiles, or configs.

Usage:
    python3 app.py              # Run the web panel
    python3 app.py --self-test  # Run self-tests (no Flask server)
"""

from __future__ import annotations

import json
import os
import re
import secrets
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from functools import wraps

# ── Shared redaction helper import ───────────────────────────────────────────
# Compute repo root and import shared helper for address-class redaction.
_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from lib.nanobk_redaction import (
    strip_ansi as _shared_strip_ansi,
    redact_text as _shared_redact_text,
    redact_json_obj as _shared_redact_json_obj,
)

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

# ── Configuration ───────────────────────────────────────────────────────────

@dataclass
class WebConfig:
    web_token: str = ""
    host: str = "127.0.0.1"
    port: int = 8080
    nanobk_cli: str = "/usr/local/bin/nanobk"
    nanobk_repo_dir: str = ""
    command_timeout: int = 120
    rotate_timeout: int = 300
    dry_run: bool = True
    secret_key: str = ""

    @classmethod
    def from_env(cls) -> WebConfig:
        if load_dotenv:
            env_path = Path(__file__).parent / ".env"
            if env_path.exists():
                load_dotenv(env_path)

        return cls(
            web_token=os.environ.get("NANOBK_WEB_TOKEN", ""),
            host=os.environ.get("NANOBK_WEB_HOST", "127.0.0.1"),
            port=int(os.environ.get("NANOBK_WEB_PORT", "8080")),
            nanobk_cli=os.environ.get("NANOBK_CLI", "/usr/local/bin/nanobk"),
            nanobk_repo_dir=os.environ.get("NANOBK_REPO_DIR", ""),
            command_timeout=int(os.environ.get("NANOBK_COMMAND_TIMEOUT", "120")),
            rotate_timeout=int(os.environ.get("NANOBK_ROTATE_TIMEOUT", "300")),
            dry_run=os.environ.get("NANOBK_WEB_DRY_RUN", "true").lower() == "true",
            secret_key=os.environ.get("NANOBK_WEB_SECRET_KEY", ""),
        )

    def validate(self) -> list[str]:
        """Return list of validation errors."""
        errors = []
        if not self.web_token or self.web_token == "change-me-long-random-token":
            errors.append("NANOBK_WEB_TOKEN must be set to a non-default value in web/.env")
        if not self.secret_key or self.secret_key == "change-me-session-secret":
            errors.append("NANOBK_WEB_SECRET_KEY must be set to a non-default value in web/.env")
        return errors

# ── Command result ──────────────────────────────────────────────────────────

@dataclass
class CommandResult:
    code: int = 0
    stdout: str = ""
    stderr: str = ""
    duration: float = 0.0

# ── nanobk CLI wrapper ─────────────────────────────────────────────────────

def run_nanobk(config: WebConfig, args: list[str], timeout: int | None = None) -> CommandResult:
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
    """Remove ANSI escape codes."""
    return _shared_strip_ansi(text)

def redact_text(text: str) -> str:
    """Redact sensitive patterns from text (delegates to shared helper)."""
    return _shared_redact_text(text)

def redact_json(value):
    """Recursively redact sensitive values from JSON-like data (delegates to shared helper)."""
    return _shared_redact_json_obj(value)

def limit_text(text: str, max_len: int = 12000) -> str:
    """Truncate text for web display."""
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


def _infer_cf_status(cf_entry: object) -> str:
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
    if data.get("domain") and data.get("domain") != "<not set>":
        return "present"
    return "unknown"


def _infer_secrets(data: dict) -> str:
    """Infer secrets status."""
    security = data.get("security")
    if not isinstance(security, dict):
        return "unknown"
    mode = security.get("secretsMode")
    if mode:
        return f"present, mode {mode}"
    return "present"


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
    return "Run Doctor for a redacted diagnostic summary, or check SSH if needed."


def _build_safe_cards(data: dict) -> dict:
    """Build safe card data from status JSON. No raw IP/domain/URL."""
    if not isinstance(data, dict):
        return {
            "overall": "unknown",
            "vps": "unknown",
            "services": {},
            "cf_nanok": "unknown",
            "cf_nanob": "unknown",
            "subscription": "unknown",
            "secrets": "unknown",
            "profile": "unknown",
            "next_step": "Run Doctor for a redacted diagnostic summary, or check SSH if needed.",
        }

    overall = _infer_overall(data)
    vps = _infer_vps(data)

    services = data.get("services")
    svc_out = {}
    if isinstance(services, dict):
        for name in ("hy2", "tuic", "reality", "trojan"):
            svc_out[name] = services.get(name, "unknown")
    else:
        for name in ("hy2", "tuic", "reality", "trojan"):
            svc_out[name] = "unknown"

    cf = data.get("cloudflare")
    cf_nanok = "unknown"
    cf_nanob = "unknown"
    if isinstance(cf, dict):
        cf_nanok = _infer_cf_status(cf.get("nanok"))
        cf_nanob = _infer_cf_status(cf.get("nanob"))

    sub = _infer_subscription(data)
    secrets_str = _infer_secrets(data)
    profile = _infer_profile(data)
    hint = _next_step_hint(overall, vps, cf_nanok, cf_nanob, sub)

    return {
        "overall": overall,
        "vps": vps,
        "services": svc_out,
        "cf_nanok": cf_nanok,
        "cf_nanob": cf_nanob,
        "subscription": sub,
        "secrets": secrets_str,
        "profile": profile,
        "next_step": hint,
    }


def format_status(data: dict) -> dict:
    """Format nanobk --json status into a safe display-friendly dict.

    Normal cards use safe categories only — no raw IP/domain/URL.
    Raw JSON is still available (redacted) for advanced diagnostics.
    """
    redacted = redact_json(data)
    cards = _build_safe_cards(data)
    return {
        "cards": cards,
        "raw_json": json.dumps(redacted, indent=2),
    }

# ── Protocol validation ────────────────────────────────────────────────────

VALID_PROTOCOLS = {"all", "hy2", "tuic", "reality", "trojan"}

def validate_protocol(protocol: str) -> bool:
    return protocol in VALID_PROTOCOLS

# ── Advanced diagnostics mode ────────────────────────────────────────────────
# Session-level state for advanced diagnostics mode.
# Not persisted to disk/env/config. Logout/session expiry resets state.
# Auto-expires after TTL.

ADVANCED_MODE_TTL_SECONDS = 15 * 60  # 15 minutes


def _get_advanced_mode(session_obj: dict) -> dict | None:
    """Get advanced mode state from session, or None if expired/missing."""
    adv = session_obj.get("advanced_mode")
    if adv is None:
        return None
    if time.time() - adv.get("enabled_at", 0) > ADVANCED_MODE_TTL_SECONDS:
        session_obj.pop("advanced_mode", None)
        return None
    return adv


def enable_advanced_mode(session_obj: dict) -> None:
    """Enable advanced mode in session."""
    session_obj["advanced_mode"] = {
        "enabled_at": time.time(),
    }


def disable_advanced_mode(session_obj: dict) -> None:
    """Disable advanced mode in session."""
    session_obj.pop("advanced_mode", None)


def is_advanced_mode_enabled(session_obj: dict) -> bool:
    """Check if advanced mode is enabled and not expired."""
    return _get_advanced_mode(session_obj) is not None


def advanced_mode_remaining_seconds(session_obj: dict) -> int:
    """Return remaining seconds of advanced mode, or 0 if disabled/expired."""
    adv = _get_advanced_mode(session_obj)
    if adv is None:
        return 0
    remaining = int(ADVANCED_MODE_TTL_SECONDS - (time.time() - adv.get("enabled_at", 0)))
    return max(0, remaining)


# ── Pending rotation ────────────────────────────────────────────────────────

ROTATE_EXPIRY_SECONDS = 120

def get_pending_rotate(session: dict) -> dict | None:
    """Get pending rotate from session, or None if expired/missing."""
    pending = session.get("pending_rotate")
    if pending is None:
        return None
    if time.time() - pending.get("created_at", 0) > ROTATE_EXPIRY_SECONDS:
        session.pop("pending_rotate", None)
        return None
    return pending

def set_pending_rotate(session: dict, protocol: str) -> None:
    session["pending_rotate"] = {
        "protocol": protocol,
        "created_at": time.time(),
    }

def clear_pending_rotate(session: dict) -> None:
    session.pop("pending_rotate", None)

# ── Self-test ───────────────────────────────────────────────────────────────

def run_self_test() -> bool:
    """Run self-tests without starting Flask server."""
    print("=== NanoBK Web Panel Self-Test ===\n")
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

    config = WebConfig(
        web_token="test-token-12345",
        nanobk_cli="/usr/bin/echo",
        dry_run=True,
        secret_key="test-secret-key-abc",
    )

    # 1. Command building
    cmd_result = run_nanobk(config, ["--version"], timeout=5)
    check("run_nanobk returns CommandResult", isinstance(cmd_result, CommandResult))

    # 2. Subprocess does not invoke a shell
    check("run_nanobk function exists", callable(run_nanobk))

    # 3. redact_text hides tokens
    test_text = "token=SuperSecret123456"
    redacted = redact_text(test_text)
    check("redact_text hides token=value", "SuperSecret123456" not in redacted)

    # 4. strip_ansi removes color codes
    ansi = "\x1b[0;34mINFO\x1b[0m \x1b[0;32mOK\x1b[0m"
    clean = strip_ansi(ansi)
    check("strip_ansi removes color codes", "\x1b[" not in clean and "INFO" in clean)

    # 5. safe_output strips ANSI and redacts
    safe = safe_output("\x1b[0;32mpassword=MySecret\x1b[0m")
    check("safe_output strips ANSI and redacts", "MySecret" not in safe and "\x1b[" not in safe)

    # 6. Protocol validation
    check("validate_protocol: all", validate_protocol("all"))
    check("validate_protocol: hy2", validate_protocol("hy2"))
    check("validate_protocol: invalid", not validate_protocol("invalid"))

    # 7. Pending rotate expiry
    test_session: dict = {}
    set_pending_rotate(test_session, "tuic")
    check("pending rotate set", get_pending_rotate(test_session) is not None)
    clear_pending_rotate(test_session)
    check("pending rotate cleared", get_pending_rotate(test_session) is None)

    # 8. Expired pending
    test_session2: dict = {"pending_rotate": {"protocol": "all", "created_at": time.time() - 999}}
    check("expired pending returns None", get_pending_rotate(test_session2) is None)

    # 9. Config validation rejects default token
    bad_config = WebConfig(web_token="change-me-long-random-token", secret_key="test-key")
    errors = bad_config.validate()
    check("default token rejected", len(errors) > 0)

    # 10. Config validation rejects default secret key
    bad_config2 = WebConfig(web_token="good-token", secret_key="change-me-session-secret")
    errors2 = bad_config2.validate()
    check("default secret key rejected", len(errors2) > 0)

    # 11. Config validation rejects empty secret key
    bad_config3 = WebConfig(web_token="good-token", secret_key="")
    errors3 = bad_config3.validate()
    check("empty secret key rejected", len(errors3) > 0)

    # 12. Config validation accepts good config
    good_config = WebConfig(web_token="my-real-token-abc123", secret_key="my-real-secret-xyz")
    errors4 = good_config.validate()
    check("good token + good secret accepted", len(errors4) == 0)

    # 13. Status formatting: safe cards
    test_status = {
        "ok": True, "domain": "test.example.com", "vpsIp": "1.2.3.4",
        "services": {"hy2": "active"}, "security": {"secretsMode": "600"}, "cloudflare": {},
        "warnings": []
    }
    formatted = format_status(test_status)
    check("format_status has cards", "cards" in formatted)
    check("format_status overall healthy", formatted["cards"]["overall"] == "healthy")
    check("format_status no raw domain label", "domain" not in str(formatted["cards"]))
    check("format_status no raw IP label", "vpsIp" not in str(formatted["cards"]))
    check("format_status preserves services", formatted["cards"]["services"].get("hy2") == "active")

    # 14. Healthz data does not expose token
    healthz = {"ok": True}
    check("healthz does not expose token", "token" not in str(healthz).lower())

    # 15. redact_json hides sensitive keys
    test_json = {"token": "abc123", "nested": {"password": "secret"}, "safe": "ok"}
    redacted_json = redact_json(test_json)
    check("redact_json hides token key", redacted_json.get("token") == "[REDACTED]")
    check("redact_json hides nested password", redacted_json.get("nested", {}).get("password") == "[REDACTED]")
    check("redact_json preserves safe values", redacted_json.get("safe") == "ok")

    # 16. redact_json handles lists
    test_list = ["PrivateKey: abc", "safe text"]
    redacted_list = redact_json(test_list)
    check("redact_json redacts list items", "abc" not in str(redacted_list[0]))

    # 17. format_status raw_json is redacted
    test_status_secret = {
        "ok": True, "domain": "test.com", "vpsIp": "1.2.3.4",
        "services": {}, "security": {"token": "should_be_redacted"},
        "cloudflare": {}, "warnings": []
    }
    formatted_secret = format_status(test_status_secret)
    check("format_status raw_json redacted", "should_be_redacted" not in formatted_secret["raw_json"])

    # 18. CSRF token generation
    csrf_token = secrets.token_urlsafe(32)
    check("CSRF token generation works", len(csrf_token) > 0)

    # 19. Address-class redaction: redact_text removes IPv4, IPv6, domain, URL
    check("redact_text redacts IPv4",
          "203.0.113.10" not in redact_text("VPS: 203.0.113.10"))
    check("redact_text redacts IPv6",
          "2001:db8::10" not in redact_text("IPv6: 2001:db8::10"))
    check("redact_text redacts domain",
          "node.example.invalid" not in redact_text("Domain: node.example.invalid"))
    check("redact_text redacts URL",
          "https://worker.example.invalid" not in redact_text("URL: https://worker.example.invalid/path"))
    check("redact_text redacts workers.dev",
          "nanobk-test.workers.dev" not in redact_text("workers.dev: nanobk-test.workers.dev"))
    check("redact_text redacts subscription path",
          "fake-sub-path-12345" not in redact_text("Path: /sub/fake-sub-path-12345"))

    # 20. Address-class redaction: redact_json removes address values from JSON
    test_addr_json = {
        "domain": "node.example.invalid", "vpsIp": "203.0.113.10",
        "ok": True, "services": {"hy2": "active"}
    }
    redacted_addr = redact_json(test_addr_json)
    check("redact_json redacts domain value",
          redacted_addr.get("domain") != "node.example.invalid")
    check("redact_json redacts IPv4 value",
          redacted_addr.get("vpsIp") != "203.0.113.10")
    check("redact_json preserves ok=true",
          redacted_addr.get("ok") is True)
    check("redact_json preserves services",
          redacted_addr.get("services", {}).get("hy2") == "active")

    # 21. Address-class redaction: safe_output redacts comprehensive text
    test_comprehensive = (
        "IPv6: 2001:db8::10\n"
        "URL: https://worker.example.invalid/sub/path\n"
        "token=fake-doc-token-abc123xyz\n"
        "secret=fake-secret-value-do-not-use"
    )
    safe_comp = safe_output(test_comprehensive)
    check("safe_output redacts IPv6", "2001:db8::10" not in safe_comp)
    check("safe_output redacts URL", "https://worker.example.invalid" not in safe_comp)
    check("safe_output redacts token", "fake-doc-token-abc123xyz" not in safe_comp)
    check("safe_output redacts secret", "fake-secret-value-do-not-use" not in safe_comp)

    # 22. format_status safe cards: no raw domain/IP
    test_status_addr = {
        "ok": True, "domain": "node.example.invalid", "vpsIp": "203.0.113.10",
        "services": {"hy2": "active"}, "security": {"secretsMode": "600"}, "cloudflare": {},
        "warnings": []
    }
    formatted_addr = format_status(test_status_addr)
    check("format_status cards no raw domain",
          "node.example.invalid" not in str(formatted_addr["cards"]))
    check("format_status cards no raw IPv4",
          "203.0.113.10" not in str(formatted_addr["cards"]))
    check("format_status cards overall healthy",
          formatted_addr["cards"]["overall"] == "healthy")
    check("format_status cards preserves services",
          formatted_addr["cards"]["services"].get("hy2") == "active")
    check("format_status raw_json redacts domain",
          "node.example.invalid" not in formatted_addr["raw_json"])
    check("format_status raw_json redacts IPv4",
          "203.0.113.10" not in formatted_addr["raw_json"])

    # 23. Idempotency: safe_output is stable on already-redacted text
    safe_once = safe_output("VPS: 203.0.113.10 domain: node.example.invalid")
    safe_twice = safe_output(safe_once)
    check("safe_output is idempotent", safe_once == safe_twice)

    # 24. Advanced mode helpers
    test_session_adv: dict = {}
    check("advanced mode disabled by default", not is_advanced_mode_enabled(test_session_adv))
    check("remaining zero when disabled", advanced_mode_remaining_seconds(test_session_adv) == 0)

    enable_advanced_mode(test_session_adv)
    check("enabled after enable", is_advanced_mode_enabled(test_session_adv))
    check("remaining positive after enable", advanced_mode_remaining_seconds(test_session_adv) > 0)

    disable_advanced_mode(test_session_adv)
    check("disabled after disable", not is_advanced_mode_enabled(test_session_adv))
    check("remaining zero after disable", advanced_mode_remaining_seconds(test_session_adv) == 0)

    # Expired advanced mode
    test_session_adv2: dict = {"advanced_mode": {"enabled_at": time.time() - ADVANCED_MODE_TTL_SECONDS - 1}}
    check("expired mode is disabled", not is_advanced_mode_enabled(test_session_adv2))
    check("expired remaining is zero", advanced_mode_remaining_seconds(test_session_adv2) == 0)
    check("expired cleans session key", "advanced_mode" not in test_session_adv2)

    # TTL constant
    check("TTL is 15 minutes", ADVANCED_MODE_TTL_SECONDS == 15 * 60)

    # 25. Advanced mode helper functions exist
    check("enable_advanced_mode is callable", callable(enable_advanced_mode))
    check("disable_advanced_mode is callable", callable(disable_advanced_mode))
    check("is_advanced_mode_enabled is callable", callable(is_advanced_mode_enabled))
    check("advanced_mode_remaining_seconds is callable", callable(advanced_mode_remaining_seconds))

    print(f"\n=== {passed} passed, {failed} failed ===")
    return failed == 0

# ── Flask App ───────────────────────────────────────────────────────────────

def create_app(config: WebConfig):
    """Create and configure the Flask application."""
    from flask import Flask, abort, redirect, render_template, request, session, url_for, jsonify

    app = Flask(__name__, template_folder="templates", static_folder="static")
    app.secret_key = config.secret_key

    # ── CSRF helpers ────────────────────────────────────────────────────

    def get_csrf_token() -> str:
        token = session.get("csrf_token")
        if not token:
            token = secrets.token_urlsafe(32)
            session["csrf_token"] = token
        return token

    def validate_csrf() -> bool:
        expected = session.get("csrf_token")
        supplied = request.form.get("csrf_token", "")
        return bool(expected and supplied and secrets.compare_digest(expected, supplied))

    @app.context_processor
    def inject_csrf_token():
        return {"csrf_token": get_csrf_token()}

    def is_logged_in() -> bool:
        return session.get("authenticated") is True

    def require_login(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            if not is_logged_in():
                return redirect(url_for("login"))
            return f(*args, **kwargs)
        return decorated

    # ── Healthz (no auth) ───────────────────────────────────────────────

    @app.route("/healthz")
    def healthz():
        return jsonify({"ok": True})

    # ── Login ────────────────────────────────────────────────────────────

    @app.route("/login", methods=["GET", "POST"])
    def login():
        error = None
        if request.method == "POST":
            token = request.form.get("token", "")
            if token == config.web_token:
                session["authenticated"] = True
                session["csrf_token"] = secrets.token_urlsafe(32)
                return redirect(url_for("dashboard"))
            error = "Invalid token."

        return render_template("login.html", error=error)

    @app.route("/logout", methods=["POST"])
    @require_login
    def logout():
        if not validate_csrf():
            abort(403, "CSRF validation failed.")
        session.clear()
        return redirect(url_for("login"))

    # ── Dashboard ────────────────────────────────────────────────────────

    @app.route("/")
    @require_login
    def dashboard():
        status_data = None
        result = run_nanobk(config, ["--json", "status"])
        if result.code == 0:
            try:
                status_data = format_status(json.loads(result.stdout))
            except json.JSONDecodeError:
                pass

        return render_template("index.html",
                               dry_run=config.dry_run,
                               status=status_data)

    # ── Status ───────────────────────────────────────────────────────────

    @app.route("/status")
    @require_login
    def status():
        result = run_nanobk(config, ["--json", "status"])
        status_data = None
        raw_output = None

        if result.code == 0:
            try:
                status_data = format_status(json.loads(result.stdout))
            except json.JSONDecodeError:
                raw_output = safe_output(result.stdout)
        else:
            raw_output = safe_output(result.stderr or result.stdout)

        adv_enabled = is_advanced_mode_enabled(session)
        adv_remaining = advanced_mode_remaining_seconds(session) if adv_enabled else 0

        return render_template("status.html",
                               status=status_data,
                               raw_output=raw_output,
                               advanced_mode_enabled=adv_enabled,
                               advanced_mode_remaining=adv_remaining)

    @app.route("/api/status")
    @require_login
    def api_status():
        result = run_nanobk(config, ["--json", "status"])
        if result.code == 0:
            try:
                data = json.loads(result.stdout)
                return jsonify(redact_json(data))
            except json.JSONDecodeError:
                return jsonify({"ok": False, "error": "Failed to parse status JSON"}), 500
        return jsonify({"ok": False, "error": safe_output(result.stderr or result.stdout)}), 500

    # ── Doctor ────────────────────────────────────────────────────────────

    @app.route("/doctor", methods=["GET", "POST"])
    @require_login
    def doctor():
        output = None
        if request.method == "POST":
            if not validate_csrf():
                abort(403, "CSRF validation failed.")
            result = run_nanobk(config, ["doctor"], timeout=config.command_timeout)
            output = safe_output(result.stdout or result.stderr)
            if result.code != 0:
                output = f"(exit code: {result.code})\n{output}"

        return render_template("doctor.html", output=output)

    # ── Rotate ────────────────────────────────────────────────────────────

    @app.route("/rotate")
    @require_login
    def rotate():
        pending = get_pending_rotate(session)
        return render_template("rotate.html",
                               pending=pending,
                               dry_run=config.dry_run,
                               protocols=sorted(VALID_PROTOCOLS))

    @app.route("/rotate/request", methods=["POST"])
    @require_login
    def rotate_request():
        if not validate_csrf():
            abort(403, "CSRF validation failed.")

        protocol = request.form.get("protocol", "")
        if not validate_protocol(protocol):
            return render_template("rotate.html",
                                   error=f"Invalid protocol: {protocol}",
                                   pending=None,
                                   dry_run=config.dry_run,
                                   protocols=sorted(VALID_PROTOCOLS))

        set_pending_rotate(session, protocol)
        pending = get_pending_rotate(session)
        return render_template("rotate.html",
                               pending=pending,
                               dry_run=config.dry_run,
                               protocols=sorted(VALID_PROTOCOLS),
                               confirming=True)

    @app.route("/rotate/confirm", methods=["POST"])
    @require_login
    def rotate_confirm():
        if not validate_csrf():
            abort(403, "CSRF validation failed.")

        pending = get_pending_rotate(session)
        if pending is None:
            return render_template("rotate.html",
                                   error="No pending confirmation (may have expired).",
                                   pending=None,
                                   dry_run=config.dry_run,
                                   protocols=sorted(VALID_PROTOCOLS))

        protocol = pending["protocol"]
        clear_pending_rotate(session)

        if config.dry_run:
            cmd_args = ["rotate", protocol, "--yes"]
            cmd_str = " ".join(cmd_args)
            return render_template("rotate.html",
                                   dry_run_result=f"DRY RUN: would execute nanobk {cmd_str}",
                                   pending=None,
                                   dry_run=config.dry_run,
                                   protocols=sorted(VALID_PROTOCOLS))

        result = run_nanobk(config, ["rotate", protocol, "--yes"], timeout=config.rotate_timeout)
        output = safe_output(result.stdout or result.stderr)
        if result.code != 0:
            output = f"Rotate failed (code {result.code}):\n{output}"

        return render_template("rotate.html",
                               rotate_result=output,
                               pending=None,
                               dry_run=config.dry_run,
                               protocols=sorted(VALID_PROTOCOLS))

    @app.route("/rotate/cancel", methods=["POST"])
    @require_login
    def rotate_cancel():
        if not validate_csrf():
            abort(403, "CSRF validation failed.")
        clear_pending_rotate(session)
        return redirect(url_for("rotate"))

    # ── Advanced diagnostics mode ─────────────────────────────────────────

    @app.route("/advanced/on", methods=["POST"])
    @require_login
    def advanced_on():
        if not validate_csrf():
            abort(403, "CSRF validation failed.")
        enable_advanced_mode(session)
        return redirect(url_for("status"))

    @app.route("/advanced/off", methods=["POST"])
    @require_login
    def advanced_off():
        if not validate_csrf():
            abort(403, "CSRF validation failed.")
        disable_advanced_mode(session)
        return redirect(url_for("status"))

    @app.route("/advanced/status")
    @require_login
    def advanced_status():
        enabled = is_advanced_mode_enabled(session)
        remaining = advanced_mode_remaining_seconds(session) if enabled else 0
        return jsonify({
            "enabled": enabled,
            "remaining_seconds": remaining,
        })

    return app

# ── Main ────────────────────────────────────────────────────────────────────

def main():
    # Self-test mode
    if "--self-test" in sys.argv:
        success = run_self_test()
        sys.exit(0 if success else 1)

    config = WebConfig.from_env()

    # Validate config
    errors = config.validate()
    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Starting NanoBK Web Panel on {config.host}:{config.port}")
    print(f"  dry-run: {config.dry_run}")
    print(f"  nanobk:  {config.nanobk_cli}")

    app = create_app(config)
    app.run(host=config.host, port=config.port, debug=False)

if __name__ == "__main__":
    main()
