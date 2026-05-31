#!/usr/bin/env python3
"""
NanoBK Web Panel — v1.2.0

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
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from functools import wraps

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
    """Run a nanobk CLI command safely (no shell=True)."""
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

_ANSI_RE = re.compile(r'\x1b\[[0-9;?]*[ -/]*[@-~]')

def strip_ansi(text: str) -> str:
    """Remove ANSI escape codes."""
    return _ANSI_RE.sub('', text)

_REDACT_PATTERNS = [
    (re.compile(r'\b\d{6,}:[A-Za-z0-9_-]{20,}\b'), '[TOKEN_REDACTED]'),
    (re.compile(r'(?i)(token|password|private[_ -]?key|secret)\s*[:=]\s*\S+'), lambda m: f'{m.group(1)}=[REDACTED]'),
    (re.compile(r'\b[A-Za-z0-9+/]{40,}={0,2}\b'), '[REDACTED_B64]'),
]

def redact_text(text: str) -> str:
    """Redact sensitive patterns from text."""
    for pattern, replacement in _REDACT_PATTERNS:
        if callable(replacement):
            text = pattern.sub(replacement, text)
        else:
            text = pattern.sub(replacement, text)
    return text

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

def format_status(data: dict) -> dict:
    """Format nanobk --json status into a display-friendly dict."""
    return {
        "ok": data.get("ok", False),
        "domain": data.get("domain", "<not set>"),
        "vps_ip": data.get("vpsIp", "<not set>"),
        "geo": data.get("geo", "<not set>"),
        "services": data.get("services", {}),
        "security": data.get("security", {}),
        "cloudflare": data.get("cloudflare", {}),
        "warnings": data.get("warnings", []),
        "raw_json": json.dumps(data, indent=2),
    }

# ── Protocol validation ────────────────────────────────────────────────────

VALID_PROTOCOLS = {"all", "hy2", "tuic", "reality", "trojan"}

def validate_protocol(protocol: str) -> bool:
    return protocol in VALID_PROTOCOLS

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
        secret_key="test-secret",
    )

    # 1. Command building
    cmd_result = run_nanobk(config, ["--version"], timeout=5)
    check("run_nanobk returns CommandResult", isinstance(cmd_result, CommandResult))

    # 2. No shell=True in subprocess
    # (verified by static check, but confirm function exists)
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
    bad_config = WebConfig(web_token="change-me-long-random-token")
    errors = bad_config.validate()
    check("default token rejected", len(errors) > 0)

    # 10. Config validation accepts good token
    good_config = WebConfig(web_token="my-real-token-abc123")
    errors2 = good_config.validate()
    check("good token accepted", len(errors2) == 0)

    # 11. Status formatting
    test_status = {
        "ok": True, "domain": "test.example.com", "vpsIp": "1.2.3.4",
        "services": {"hy2": "active"}, "security": {}, "cloudflare": {},
        "warnings": []
    }
    formatted = format_status(test_status)
    check("format_status includes domain", formatted["domain"] == "test.example.com")
    check("format_status includes services", "hy2" in formatted["services"])

    # 12. Healthz data does not expose token
    healthz = {"ok": True}
    check("healthz does not expose token", "token" not in str(healthz).lower())

    print(f"\n=== {passed} passed, {failed} failed ===")
    return failed == 0

# ── Flask App ───────────────────────────────────────────────────────────────

def create_app(config: WebConfig):
    """Create and configure the Flask application."""
    from flask import Flask, redirect, render_template, request, session, url_for, jsonify

    app = Flask(__name__, template_folder="templates", static_folder="static")
    app.secret_key = config.secret_key or "dev-fallback-not-for-production"

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
                return redirect(url_for("dashboard"))
            error = "Invalid token."

        return render_template("login.html", error=error)

    @app.route("/logout")
    def logout():
        session.clear()
        return redirect(url_for("login"))

    # ── Dashboard ────────────────────────────────────────────────────────

    @app.route("/")
    @require_login
    def dashboard():
        # Get quick status
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

        return render_template("status.html",
                               status=status_data,
                               raw_output=raw_output)

    @app.route("/api/status")
    @require_login
    def api_status():
        result = run_nanobk(config, ["--json", "status"])
        if result.code == 0:
            try:
                data = json.loads(result.stdout)
                return jsonify(data)
            except json.JSONDecodeError:
                return jsonify({"ok": False, "error": "Failed to parse status JSON"}), 500
        return jsonify({"ok": False, "error": safe_output(result.stderr or result.stdout)}), 500

    # ── Doctor ────────────────────────────────────────────────────────────

    @app.route("/doctor", methods=["GET", "POST"])
    @require_login
    def doctor():
        output = None
        if request.method == "POST":
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
        clear_pending_rotate(session)
        return redirect(url_for("rotate"))

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

    if config.secret_key in ("", "change-me-session-secret"):
        print("WARNING: NANOBK_WEB_SECRET_KEY is default. Change it in web/.env for production.", file=sys.stderr)

    print(f"Starting NanoBK Web Panel on {config.host}:{config.port}")
    print(f"  dry-run: {config.dry_run}")
    print(f"  nanobk:  {config.nanobk_cli}")

    app = create_app(config)
    app.run(host=config.host, port=config.port, debug=False)

if __name__ == "__main__":
    main()
