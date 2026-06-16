#!/usr/bin/env python3
"""
NanoBK Production VPS Install (v2.6.5)

Productized, exact-gated wrapper for the legacy four-protocol VPS installer.
Default behavior is read-only. Automated tests use fake install hooks only.
The real installer adapter is intentionally safe-refused until VPS acceptance
connects it.
"""

import argparse
import json
import os
import platform
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_domain_selection import load_selected_domain
from nanobk_setup_profile import load_profile


VERSION = "2.6.5"
MODE = "production_vps_install_v2_6"
EXACT_PHRASE_VPS = "I UNDERSTAND NANOBK WILL INSTALL VPS PROXY SERVICES"

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


def _preflight(dry_run):
    domain = _selected_domain()
    if not domain:
        return _refusal("还没有选择你的域名，请先运行 nanobk setup domain", "select_domain", dry_run)
    if not _safe_domain(domain):
        return _refusal("你的域名格式不正确，请重新选择域名。", "select_domain", dry_run)

    if not _has_fake_context():
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


def build_plan(dry_run=True):
    return _preflight(dry_run=dry_run)


def install_vps(confirm_phrase):
    if confirm_phrase != EXACT_PHRASE_VPS:
        return _refusal("需要完整输入安全确认短语。", "confirm_vps_install", False)

    plan = _preflight(dry_run=False)
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

    return _refusal(
        "真实安装代理服务的受控执行器尚未接入；当前不会安装或重启服务。",
        "connect_vps_install_adapter",
        False,
        confirmed=True,
    )


def public_result(result):
    return {key: value for key, value in result.items() if not key.startswith("_")}


def output_text(result):
    result = public_result(result)
    lines = [""]

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
            lines.append("  正在安装代理服务……")
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
    elif next_step == "confirm_vps_install":
        lines.append(f'  请使用：--confirm "{EXACT_PHRASE_VPS}"')
    elif next_step == "connect_vps_install_adapter":
        lines.append("  当前版本不会真正安装或重启服务。")
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
    parser.add_argument("--confirm", help="Exact safety confirmation phrase")
    args = parser.parse_args(argv)

    if args.dry_run:
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
