#!/usr/bin/env python3
"""
NanoBK Production VPS Install (v2.6.6)

Productized, exact-gated wrapper for the legacy four-protocol VPS installer.
Default behavior is read-only. Render-check uses the legacy installer's
render-only mode. Real install is available only behind exact confirmation,
explicit environment guard, certificate safety checks, and existing-install
protection.
"""

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_domain_selection import load_selected_domain
from nanobk_setup_profile import load_profile


VERSION = "2.6.6"
MODE = "production_vps_install_v2_6"
EXACT_PHRASE_VPS = "I UNDERSTAND NANOBK WILL INSTALL VPS PROXY SERVICES"

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LEGACY_INSTALLER = "installer/install-vps.sh"
LEGACY_INSTALLER_PATH = os.path.join(REPO_DIR, LEGACY_INSTALLER)
PROFILE_PATH = "/etc/nanobk/profile.current.json"

PROTOCOLS = [
    {"name": "hy2", "service": "hysteria-server.service"},
    {"name": "tuic", "service": "tuic-v5-9443.service"},
    {"name": "reality", "service": "xray-reality-8443.service"},
    {"name": "trojan", "service": "xray-trojan-2443.service"},
]

BLOCKED_ARGS = {
    "--yes",
    "--force",
    "--overwrite",
    "--delete",
    "--update",
    "--rotate",
    "--restart",
    "--reload",
}

DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)"
    r"(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))+$"
)
SENSITIVE_LINE_RE = re.compile(
    r"(password|uuid|private|token|secret|key|BEGIN .*KEY|SUB_TOKEN|ADMIN_TOKEN|"
    r"CF_API_TOKEN|secrets\.private\.env|profile\.current\.json|workers\.dev|"
    r"/admin|subscription|privkey|fullchain)",
    re.IGNORECASE,
)
UUID_RE = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")
PRIVATE_KEY_BLOCK_RE = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
    re.DOTALL,
)


def _refusal(message, next_step, dry_run=False, **extra):
    result = {
        "ok": False,
        "mode": MODE,
        "version": VERSION,
        "dry_run": bool(dry_run),
        "mutation": False,
        "dangerous_actions_executed": False,
        "blocked": True,
        "error": message,
        "next_step": next_step,
        "safety": "read_only",
    }
    result.update(extra)
    return result


def _safe_domain(value):
    candidate = (value or "").strip().lower().rstrip(".")
    if not candidate or not DOMAIN_RE.match(candidate):
        return None
    return candidate


def _selected_domain():
    fake = _safe_domain(os.environ.get("NANOBK_FAKE_SELECTED_DOMAIN", ""))
    if fake:
        return fake

    selected, _err = load_selected_domain()
    if selected and selected.get("selected_domain"):
        return _safe_domain(selected.get("selected_domain"))

    profile, err = load_profile()
    if not err and profile and profile.get("zone_name"):
        return _safe_domain(profile.get("zone_name"))

    return None


def _has_fake_context():
    for key in os.environ:
        if key.startswith("NANOBK_FAKE_VPS_"):
            return True
    return bool(os.environ.get("NANOBK_FAKE_SELECTED_DOMAIN"))


def _protocols(status="planned"):
    return [
        {"name": item["name"], "service": item["service"], "status": status}
        for item in PROTOCOLS
    ]


def _installed_protocols():
    return [
        {"name": item["name"], "service": item["service"]}
        for item in PROTOCOLS
    ]


def _profile_complete_real():
    if not os.path.isfile(PROFILE_PATH):
        return False
    try:
        with open(PROFILE_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return False
    return all(isinstance(data.get(item["name"]), dict) for item in PROTOCOLS)


def _systemctl_available():
    return shutil.which("systemctl") is not None


def _services_active_real():
    if not _systemctl_available():
        return False
    states = []
    for item in PROTOCOLS:
        try:
            completed = subprocess.run(
                ["systemctl", "is-active", item["service"]],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=5,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            states.append(False)
            continue
        states.append(completed.stdout.strip() == "active")
    return all(states)


def _fake_state():
    state = os.environ.get("NANOBK_FAKE_VPS_INSTALL_STATE")
    if state in {"none", "complete", "partial"}:
        return state

    profile = os.environ.get("NANOBK_FAKE_VPS_PROFILE_COMPLETE")
    services = os.environ.get("NANOBK_FAKE_VPS_SERVICES_ACTIVE")
    if profile == "1" and services == "1":
        return "complete"
    if profile == "1" or services == "1":
        return "partial"
    return "none"


def _install_state():
    if _has_fake_context():
        state = _fake_state()
        return {
            "state": state,
            "profile_complete": state == "complete",
            "services_active": state == "complete",
            "healthcheck": os.environ.get("NANOBK_FAKE_VPS_HEALTHCHECK", "not_run"),
        }

    profile_complete = _profile_complete_real()
    services_active = _services_active_real()
    if profile_complete and services_active:
        state = "complete"
    elif profile_complete or services_active:
        state = "partial"
    else:
        state = "none"

    return {
        "state": state,
        "profile_complete": profile_complete,
        "services_active": services_active,
        "healthcheck": "passed_or_not_run" if state == "complete" else "not_run",
    }


def _preflight(dry_run, require_linux=False):
    domain = _selected_domain()
    if not domain:
        return _refusal("还没有选择你的域名，请先运行 nanobk setup domain", "select_domain", dry_run)
    if not _safe_domain(domain):
        return _refusal("你的域名格式不正确，请重新选择域名。", "select_domain", dry_run)

    if require_linux and not _fake_adapter_enabled():
        if platform.system() != "Linux":
            return _refusal("安装代理服务需要在 Linux VPS 上运行。", "run_on_linux_vps", dry_run)
        if not _systemctl_available():
            return _refusal("没有检测到 systemctl，无法管理代理服务。", "install_systemd", dry_run)

    state = _install_state()
    if state["state"] == "partial":
        return _refusal(
            "检测到部分代理服务或配置已经存在，当前不会覆盖，请先人工检查。",
            "repair_or_review",
            dry_run,
            selected_domain=domain,
            protocols=_protocols("detected_or_missing"),
            existing_install=False,
            partial_install=True,
            profile_complete=state["profile_complete"],
            services_active=state["services_active"],
            healthcheck=state["healthcheck"],
        )

    if state["state"] == "complete":
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "dry_run": bool(dry_run),
            "mutation": False,
            "dangerous_actions_executed": False,
            "selected_domain": domain,
            "protocols": _protocols("active"),
            "existing_install": True,
            "partial_install": False,
            "profile_complete": True,
            "services_active": True,
            "healthcheck": state["healthcheck"] if state["healthcheck"] != "not_run" else "passed_or_not_run",
            "blocked": False,
            "next_step": "setup_subscription",
            "safety": "read_only",
        }

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "dry_run": bool(dry_run),
        "mutation": False,
        "dangerous_actions_executed": False,
        "selected_domain": domain,
        "protocols": _protocols("planned"),
        "existing_install": False,
        "partial_install": False,
        "healthcheck": "not_run",
        "blocked": False,
        "next_step": "confirm_vps_install",
        "safety": "read_only",
    }


def _fake_adapter_enabled():
    return os.environ.get("NANOBK_FAKE_VPS_LEGACY_ADAPTER") in {"success", "failure"}


def _vps_ip_for_render():
    return (
        os.environ.get("NANOBK_FAKE_VPS_IPV4")
        or os.environ.get("NANOBK_VPS_IP")
        or "198.51.100.10"
    )


def _vps_ip_for_real():
    return os.environ.get("NANOBK_VPS_IP") or os.environ.get("NANOBK_FAKE_VPS_IPV4")


def redact_output(text):
    if not text:
        return ""
    cleaned = PRIVATE_KEY_BLOCK_RE.sub("[redacted sensitive block]", text)
    redacted = []
    for raw_line in cleaned.splitlines():
        line = UUID_RE.sub("[redacted-id]", raw_line)
        if SENSITIVE_LINE_RE.search(line):
            redacted.append("[redacted sensitive line]")
        else:
            redacted.append(line)
    return "\n".join(redacted)


def _redacted_tail(text, max_lines=20):
    safe = redact_output(text)
    lines = [line for line in safe.splitlines() if line.strip()]
    return lines[-max_lines:]


def _legacy_summary(exit_code):
    if exit_code == 0:
        return "旧版安装器已完成，输出已脱敏。"
    return "旧版安装器未完成，输出已脱敏。"


def _run_command(command, timeout):
    completed = subprocess.run(
        command,
        cwd=REPO_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )
    return completed.returncode, f"{completed.stdout}\n{completed.stderr}"


def _render_command(domain, render_dir):
    return [
        "bash",
        LEGACY_INSTALLER_PATH,
        "--render-only",
        "--yes",
        "--config-dir",
        os.path.join(render_dir, "etc", "nanobk"),
        "--install-dir",
        os.path.join(render_dir, "opt", "nanobk"),
        "--domain",
        domain,
        "--vps-ip",
        _vps_ip_for_render(),
        "--cert-mode",
        "self-signed",
    ]


def run_render_check():
    plan = _preflight(dry_run=True, require_linux=False)
    if not plan.get("ok"):
        plan["render_check"] = True
        return plan

    if plan.get("existing_install"):
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "render_check": True,
            "mutation": False,
            "dangerous_actions_executed": False,
            "legacy_installer": LEGACY_INSTALLER,
            "rendered_protocols": [item["name"] for item in PROTOCOLS],
            "render_dir": "redacted",
            "existing_install": True,
            "next_step": "setup_subscription",
            "safety": "render_only",
        }

    fake_render = os.environ.get("NANOBK_FAKE_VPS_RENDER_CHECK")
    if fake_render == "failure":
        return _refusal(
            "旧版安装器渲染检查失败，当前不会安装代理服务。",
            "repair_or_review",
            False,
            render_check=True,
            legacy_installer=LEGACY_INSTALLER,
            redacted_output_tail=["[redacted sensitive line]"],
        )
    if fake_render == "success":
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "render_check": True,
            "mutation": False,
            "dangerous_actions_executed": False,
            "legacy_installer": LEGACY_INSTALLER,
            "rendered_protocols": [item["name"] for item in PROTOCOLS],
            "render_dir": "redacted",
            "next_step": "confirm_vps_install",
            "safety": "render_only",
        }

    if not os.path.isfile(LEGACY_INSTALLER_PATH):
        return _refusal(
            "没有找到旧版 VPS 安装器，当前不会安装代理服务。",
            "repair_or_review",
            False,
            render_check=True,
            legacy_installer=LEGACY_INSTALLER,
        )

    with tempfile.TemporaryDirectory(prefix="nanobk-vps-render-") as tmpdir:
        command = _render_command(plan["selected_domain"], tmpdir)
        try:
            exit_code, output = _run_command(command, timeout=180)
        except (OSError, subprocess.TimeoutExpired):
            return _refusal(
                "旧版安装器渲染检查超时或无法启动，当前不会安装代理服务。",
                "repair_or_review",
                False,
                render_check=True,
                legacy_installer=LEGACY_INSTALLER,
            )

    if exit_code != 0:
        return _refusal(
            "旧版安装器渲染检查失败，当前不会安装代理服务。",
            "repair_or_review",
            False,
            render_check=True,
            legacy_installer=LEGACY_INSTALLER,
            legacy_exit_code=exit_code,
            legacy_output_summary=_legacy_summary(exit_code),
            redacted_output_tail=_redacted_tail(output),
        )

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "render_check": True,
        "mutation": False,
        "dangerous_actions_executed": False,
        "legacy_installer": LEGACY_INSTALLER,
        "rendered_protocols": [item["name"] for item in PROTOCOLS],
        "render_dir": "redacted",
        "next_step": "confirm_vps_install",
        "safety": "render_only",
    }


def build_plan(dry_run=True):
    return _preflight(dry_run=dry_run, require_linux=False)


def _cert_options():
    mode = os.environ.get("NANOBK_VPS_CERT_MODE", "existing").strip()
    if mode not in {"existing", "self-signed", "none"}:
        return None, _refusal("证书模式不正确，请使用 existing、self-signed 或 none。", "cert_mode", False)

    if mode == "existing":
        cert_file = os.environ.get("NANOBK_VPS_CERT_FILE", "")
        key_file = os.environ.get("NANOBK_VPS_KEY_FILE", "")
        if not cert_file or not key_file:
            return None, _refusal("existing 证书模式需要提供证书文件和密钥文件。", "cert_files", False)
        if not os.path.isfile(cert_file) or not os.path.isfile(key_file):
            return None, _refusal("existing 证书模式需要可读取的证书文件和密钥文件。", "cert_files", False)
        return ["--cert-mode", "existing", "--cert-file", cert_file, "--key-file", key_file], None

    if mode == "self-signed":
        if os.environ.get("NANOBK_ALLOW_SELF_SIGNED_VPS_INSTALL") != "1":
            return None, _refusal("self-signed 证书只适合测试，需要显式允许。", "allow_self_signed", False)
        return ["--cert-mode", "self-signed"], None

    if os.environ.get("NANOBK_ALLOW_NO_CERT_VPS_INSTALL") != "1":
        return None, _refusal("无证书安装会导致部分代理通道不可用，需要显式允许。", "allow_no_cert", False)
    return ["--cert-mode", "none"], None


def _legacy_install_command(domain):
    cert_args, err = _cert_options()
    if err:
        return None, err

    command = [
        "bash",
        LEGACY_INSTALLER_PATH,
        "--yes",
        "--domain",
        domain,
        "--reality-servername",
        os.environ.get("NANOBK_VPS_REALITY_SERVERNAME", "www.microsoft.com"),
    ]

    vps_ip = _vps_ip_for_real()
    if vps_ip:
        command.extend(["--vps-ip", vps_ip])

    email = os.environ.get("NANOBK_VPS_EMAIL")
    if email:
        command.extend(["--email", email])

    command.extend(cert_args)

    if os.environ.get("NANOBK_VPS_OPEN_FIREWALL") == "1":
        command.append("--open-firewall")

    return command, None


def _run_healthcheck_if_available():
    path = "/opt/nanobk/bin/healthcheck.sh"
    if not os.path.isfile(path):
        return "passed_or_not_run"
    try:
        completed = subprocess.run(
            ["bash", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return "failed"
    return "passed" if completed.returncode == 0 else "failed"


def _fake_legacy_adapter(plan):
    mode = os.environ.get("NANOBK_FAKE_VPS_LEGACY_ADAPTER")
    if mode == "success":
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": True,
            "dangerous_actions_executed": True,
            "confirmed": True,
            "legacy_adapter": "connected",
            "legacy_installer": LEGACY_INSTALLER,
            "legacy_exit_code": 0,
            "legacy_output_summary": "旧版安装器已完成，输出已脱敏。",
            "installed_protocols": _installed_protocols(),
            "healthcheck": "passed_or_not_run",
            "blocked": False,
            "next_step": "setup_subscription",
            "safety": "confirmed_vps_install",
        }
    if mode == "failure":
        raw = "ADMIN_TOKEN=secret\nTUIC_UUID=00000000-0000-0000-0000-000000000000\ninstall failed"
        return {
            "ok": False,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": True,
            "dangerous_actions_executed": True,
            "confirmed": True,
            "legacy_adapter": "connected",
            "legacy_installer": LEGACY_INSTALLER,
            "legacy_exit_code": 1,
            "blocked": True,
            "error": "旧版安装器执行失败，请查看已脱敏摘要。",
            "legacy_output_summary": "旧版安装器未完成，输出已脱敏。",
            "redacted_output_tail": _redacted_tail(raw),
            "next_step": "repair_or_review",
            "safety": "confirmed_vps_install_failed",
        }
    return None


def install_vps(confirm_phrase):
    if confirm_phrase != EXACT_PHRASE_VPS:
        return _refusal("需要完整输入安全确认短语。", "confirm_vps_install", False)

    plan = _preflight(dry_run=False, require_linux=False)
    if not plan.get("ok"):
        plan["confirmed"] = True
        return plan

    if plan.get("existing_install"):
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": False,
            "dangerous_actions_executed": False,
            "confirmed": True,
            "existing_install": True,
            "partial_install": False,
            "profile_complete": True,
            "services_active": True,
            "healthcheck": plan.get("healthcheck", "passed_or_not_run"),
            "blocked": False,
            "next_step": "setup_subscription",
            "safety": "read_only",
        }

    if os.environ.get("NANOBK_FAKE_VPS_INSTALL") == "1":
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": True,
            "dangerous_actions_executed": True,
            "confirmed": True,
            "installed_protocols": _installed_protocols(),
            "healthcheck": "fake_passed",
            "blocked": False,
            "next_step": "setup_subscription",
            "safety": "confirmed_vps_install",
        }

    if os.environ.get("NANOBK_ALLOW_REAL_VPS_INSTALL") != "1":
        return _refusal(
            "真实安装代理服务需要先设置 NANOBK_ALLOW_REAL_VPS_INSTALL=1。",
            "confirm_vps_install",
            False,
        )

    if not _fake_adapter_enabled():
        if platform.system() != "Linux":
            return _refusal("安装代理服务需要在 Linux VPS 上运行。", "run_on_linux_vps", False, confirmed=True)
        if not _systemctl_available():
            return _refusal("没有检测到 systemctl，无法管理代理服务。", "install_systemd", False, confirmed=True)

    command, command_err = _legacy_install_command(plan["selected_domain"])
    if command_err:
        command_err["confirmed"] = True
        return command_err

    render = run_render_check()
    if not render.get("ok"):
        render["confirmed"] = True
        return render

    fake = _fake_legacy_adapter(plan)
    if fake:
        return fake

    try:
        exit_code, output = _run_command(command, timeout=900)
    except (OSError, subprocess.TimeoutExpired):
        return {
            "ok": False,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": True,
            "dangerous_actions_executed": True,
            "confirmed": True,
            "legacy_adapter": "connected",
            "legacy_installer": LEGACY_INSTALLER,
            "legacy_exit_code": 124,
            "blocked": True,
            "error": "旧版安装器执行超时或无法启动，请查看已脱敏摘要。",
            "redacted_output_tail": [],
            "next_step": "repair_or_review",
            "safety": "confirmed_vps_install_failed",
        }

    if exit_code != 0:
        return {
            "ok": False,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": True,
            "dangerous_actions_executed": True,
            "confirmed": True,
            "legacy_adapter": "connected",
            "legacy_installer": LEGACY_INSTALLER,
            "legacy_exit_code": exit_code,
            "blocked": True,
            "error": "旧版安装器执行失败，请查看已脱敏摘要。",
            "legacy_output_summary": _legacy_summary(exit_code),
            "redacted_output_tail": _redacted_tail(output),
            "next_step": "repair_or_review",
            "safety": "confirmed_vps_install_failed",
        }

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "dry_run": False,
        "mutation": True,
        "dangerous_actions_executed": True,
        "confirmed": True,
        "legacy_adapter": "connected",
        "legacy_installer": LEGACY_INSTALLER,
        "legacy_exit_code": 0,
        "legacy_output_summary": _legacy_summary(0),
        "installed_protocols": _installed_protocols(),
        "healthcheck": _run_healthcheck_if_available(),
        "blocked": False,
        "next_step": "setup_subscription",
        "safety": "confirmed_vps_install",
    }


def public_result(result):
    return {key: value for key, value in result.items() if not key.startswith("_")}


def output_text(result):
    result = public_result(result)
    lines = [""]

    if result.get("ok") and result.get("render_check"):
        lines.extend([
            "  NanoBK 代理服务渲染检查",
            "  ─────────────────────────────────────────────",
            "",
            "  已完成旧版安装器渲染检查。",
            "  当前不会安装代理服务，不会启动/刷新服务。",
            "",
            "  已验证：hy2、tuic、reality、trojan",
            "",
            "  下一步：",
            f'  nanobk setup production vps install --confirm "{EXACT_PHRASE_VPS}"',
            "",
        ])
        return "\n".join(lines)

    if result.get("ok") and result.get("dry_run"):
        lines.extend([
            "  NanoBK 安装代理服务检查",
            "  ─────────────────────────────────────────────",
            "",
            "  当前不会安装代理服务，不会启动/刷新服务。",
            "",
        ])
        if result.get("existing_install"):
            lines.extend([
                "  状态：已检测到四个代理通道。",
                "",
                "  下一步：",
                "  nanobk setup production worker deploy --dry-run",
                "",
            ])
            return "\n".join(lines)

        lines.extend([
            "  我将准备：",
            "",
        ])
        for item in result.get("protocols", []):
            lines.append(f"  {item['name']} -> 四个代理通道")
        lines.extend([
            "",
            "  如果确认无误，再运行：",
            f'  nanobk setup production vps install --confirm "{EXACT_PHRASE_VPS}"',
            "",
        ])
        return "\n".join(lines)

    if result.get("ok") and not result.get("dry_run"):
        lines.extend([
            "  NanoBK 安装代理服务",
            "  ─────────────────────────────────────────────",
            "",
            "  已通过安全确认。",
        ])
        if result.get("existing_install"):
            lines.append("  已检测到四个代理通道，当前不需要重新安装。")
        else:
            lines.append("  旧版安装器已完成。")
            lines.append("")
            lines.append("  完成：")
            for item in result.get("installed_protocols", []):
                lines.append(f"  {item['name']}")
        lines.extend([
            "",
            "  下一步：",
            "  nanobk setup production worker deploy --dry-run",
            "",
        ])
        return "\n".join(lines)

    lines.extend([
        "  NanoBK 安装代理服务",
        "  ─────────────────────────────────────────────",
        "",
        f"  暂时不能继续：{result.get('error', '未知原因')}",
    ])
    next_step = result.get("next_step")
    if next_step == "select_domain":
        lines.append("  请先运行：nanobk setup domain")
    elif next_step == "run_on_linux_vps":
        lines.append("  请在 Ubuntu/Linux VPS 上运行本命令。")
    elif next_step == "install_systemd":
        lines.append("  请确认 VPS 使用 systemd。")
    elif next_step == "repair_or_review":
        lines.append("  请先人工检查已有代理服务，再决定是否修复。")
    elif next_step == "cert_files":
        lines.append("  请提供 existing 证书文件和密钥文件。")
    elif next_step == "allow_self_signed":
        lines.append("  self-signed 仅适合测试 VPS，需要显式允许。")
    elif next_step == "allow_no_cert":
        lines.append("  无证书安装会导致部分代理通道不可用，需要显式允许。")
    elif next_step == "confirm_vps_install":
        lines.append(f'  请使用：--confirm "{EXACT_PHRASE_VPS}"')
    lines.append("")
    return "\n".join(lines)


def _has_blocked_arg(argv):
    for arg in argv:
        if arg in BLOCKED_ARGS:
            return arg
    return None


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    blocked = _has_blocked_arg(argv)
    json_requested = "--json" in argv
    if blocked:
        result = _refusal(f"{blocked} 不适用于这个受控命令。", "confirm_vps_install", "--dry-run" in argv)
        if json_requested:
            print(json.dumps(public_result(result), indent=2, ensure_ascii=False))
        else:
            print(output_text(result), file=sys.stderr)
        return 1

    parser = argparse.ArgumentParser(description="NanoBK production VPS install")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--dry-run", action="store_true", help="Show plan only")
    parser.add_argument("--render-check", action="store_true", help="Run legacy installer render-only check")
    parser.add_argument("--confirm", help="Exact safety confirmation phrase")
    args = parser.parse_args(argv)

    if args.render_check:
        result = run_render_check()
    elif args.dry_run:
        result = build_plan(dry_run=True)
    else:
        result = install_vps(args.confirm)

    if args.json:
        print(json.dumps(public_result(result), indent=2, ensure_ascii=False))
    else:
        stream = sys.stdout if result.get("ok") else sys.stderr
        print(output_text(result), file=stream)

    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
