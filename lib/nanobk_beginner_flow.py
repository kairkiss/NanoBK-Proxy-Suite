#!/usr/bin/env python3
"""
NanoBK Beginner Flow Renderer (v2.4.2)

Read-only step-by-step Chinese-language setup flow renderer.
Translates v2.3 setup status into beginner-friendly flow pages.

Read-only. No DNS mutation. No Cloudflare mutation.
No curl/wrangler/certbot calls. No service reload/restart.

Usage:
    python3 lib/nanobk_beginner_flow.py [--json]
    python3 lib/nanobk_beginner_flow.py status [--json]
    python3 lib/nanobk_beginner_flow.py flow [--json]
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_profile import load_profile, default_profile_path


# ── NanoBK Logo ────────────────────────────────────────────────────────────

_LOGO = r"""
  ╔╗ ╔═╗╔╗╔╔╦╗╔╗╔╔═╗╦  ╦╔═╗
  ╠╩╗║╣ ║║║ ║║║║║╠═╣║  ║║ ║
  ╚═╝╚═╝╝╚╝═╩╝╝╚╝╩ ╩╩═╝╩╚═╝
"""


# ── Status gathering (profile-only, no network) ────────────────────────────

def _gather_flow_status(ip_fixture=None, dns_fixture=None, cert_fixture=None, token_fixture=None):
    """Gather flow status from profile and optional fixtures.

    Read-only. No network calls. No mutation.
    Fixtures allow tests to simulate various states.
    """
    profile_path = default_profile_path()
    has_profile = os.path.isfile(profile_path)

    if not has_profile:
        return {
            "stage": "no_profile",
            "cloudflare": "disconnected",
            "domain": "not_selected",
            "vps_ip": {"ipv4": "unknown", "ipv6": "unknown"},
            "dns": "not_configured",
            "certificate": "not_checked",
            "subscription_token": "not_checked",
            "safety": "read_only",
            "next_step": "connect_cloudflare",
        }

    profile, profile_err = load_profile()

    if profile_err:
        return {
            "stage": "cloudflare_connected",
            "cloudflare": "connected",
            "domain": "not_selected",
            "vps_ip": {"ipv4": "unknown", "ipv6": "unknown"},
            "dns": "not_configured",
            "certificate": "not_checked",
            "subscription_token": "not_checked",
            "safety": "waiting_confirmation",
            "next_step": "select_domain",
        }

    zone = profile.get("zone_name", "")
    domain = zone if zone else "not_selected"

    if domain == "not_selected":
        return {
            "stage": "cloudflare_connected",
            "cloudflare": "connected",
            "domain": "not_selected",
            "vps_ip": {"ipv4": "unknown", "ipv6": "unknown"},
            "dns": "not_configured",
            "certificate": "not_checked",
            "subscription_token": "not_checked",
            "safety": "waiting_confirmation",
            "next_step": "select_domain",
        }

    # Domain selected - derive further state from fixtures or defaults
    vps_ipv4 = "unknown"
    vps_ipv6 = "unknown"
    dns_status = "not_configured"
    cert_status = "not_checked"
    token_status = "not_checked"
    stage = "domain_selected"
    next_step = "detect_ip"
    safety = "waiting_confirmation"

    # Apply IP fixture if provided
    if ip_fixture:
        vps_ipv4 = ip_fixture.get("ipv4", "unknown")
        vps_ipv6 = ip_fixture.get("ipv6", "unknown")
        if vps_ipv4 != "unknown" or vps_ipv6 != "unknown":
            stage = "ip_ready"
            next_step = "review_dns_plan"

    # Apply DNS fixture if provided
    if dns_fixture:
        dns_status = dns_fixture.get("dns", "pending")
        if dns_status == "pending":
            stage = "dns_pending"
            next_step = "review_dns_plan"
        elif dns_status == "configured":
            next_step = "review_cert_plan"

    # Apply cert fixture if provided
    if cert_fixture:
        cert_status = cert_fixture.get("certificate", "not_checked")
        if cert_status == "pending":
            stage = "cert_pending"
            next_step = "review_cert_plan"

    # Apply token fixture if provided
    if token_fixture:
        token_status = token_fixture.get("subscription_token", "not_checked")
        if token_status == "pending":
            stage = "token_pending"
            next_step = "review_token_plan"

    # If everything looks configured
    if (dns_status == "configured" and cert_status == "ready"
            and token_status == "normal"):
        stage = "ready"
        next_step = "done"
        safety = "complete"

    return {
        "stage": stage,
        "cloudflare": "connected",
        "domain": domain,
        "vps_ip": {"ipv4": vps_ipv4, "ipv6": vps_ipv6},
        "dns": dns_status,
        "certificate": cert_status,
        "subscription_token": token_status,
        "safety": safety,
        "next_step": next_step,
    }


# ── Flow step builder ─────────────────────────────────────────────────────

def _build_steps(status):
    """Build a list of flow steps from the current status.

    Each step has: id, title, status, message
    Status: done, current, pending, blocked
    """
    stage = status["stage"]
    domain = status["domain"]
    vps_ip = status["vps_ip"]
    dns = status["dns"]
    cert = status["certificate"]
    token = status["subscription_token"]

    steps = []

    # 1. Welcome
    steps.append({
        "id": "welcome",
        "title": "欢迎使用 NanoBK",
        "status": "done",
        "message": "NanoBK 让 VPS 代理部署变简单。接下来我们会一步步帮你完成设置。",
    })

    # 2. Cloudflare connect
    cf_status = status["cloudflare"]
    if cf_status == "connected":
        steps.append({
            "id": "cloudflare_connect",
            "title": "连接 Cloudflare",
            "status": "done",
            "message": "已成功连接到你的 Cloudflare 账号。",
        })
    else:
        steps.append({
            "id": "cloudflare_connect",
            "title": "连接 Cloudflare",
            "status": "current" if stage == "no_profile" else "pending",
            "message": "需要连接你的 Cloudflare 账号来管理域名。运行 nanobk cf connect 开始。",
        })

    # 3. Domain selection
    if domain != "not_selected":
        steps.append({
            "id": "domain_select",
            "title": "选择你的域名",
            "status": "done",
            "message": f"已选择域名：{domain}",
        })
    elif cf_status == "connected":
        steps.append({
            "id": "domain_select",
            "title": "选择你的域名",
            "status": "current",
            "message": "请从你的 Cloudflare 域名中选择一个。",
        })
    else:
        steps.append({
            "id": "domain_select",
            "title": "选择你的域名",
            "status": "pending",
            "message": "需要先连接 Cloudflare 才能选择域名。",
        })

    # 4. VPS IP detection
    ipv4 = vps_ip.get("ipv4", "unknown")
    ipv6 = vps_ip.get("ipv6", "unknown")
    if ipv4 == "detected" or ipv6 == "detected":
        ip_parts = []
        if ipv4 == "detected":
            ip_parts.append("IPv4")
        if ipv6 == "detected":
            ip_parts.append("IPv6")
        steps.append({
            "id": "ip_detect",
            "title": "检测 VPS IP",
            "status": "done",
            "message": f"已检测到你的服务器 IP：{' + '.join(ip_parts)}",
        })
    elif ipv4 == "failed" and ipv6 == "failed":
        steps.append({
            "id": "ip_detect",
            "title": "检测 VPS IP",
            "status": "blocked",
            "message": "无法检测到你的服务器公网 IPv4 和 IPv6。请检查 VPS 网络配置。",
        })
    elif ipv4 == "failed":
        steps.append({
            "id": "ip_detect",
            "title": "检测 VPS IP",
            "status": "blocked",
            "message": "无法检测到你的服务器公网 IPv4。请检查 VPS 网络配置。",
        })
    elif ipv6 == "failed":
        steps.append({
            "id": "ip_detect",
            "title": "检测 VPS IP",
            "status": "blocked",
            "message": "无法检测到你的服务器公网 IPv6。请检查 VPS 网络配置。",
        })
    elif domain != "not_selected":
        steps.append({
            "id": "ip_detect",
            "title": "检测 VPS IP",
            "status": "current" if stage in ("domain_selected",) else "pending",
            "message": "将自动检测你的服务器公网 IPv4 和 IPv6 地址。",
        })
    else:
        steps.append({
            "id": "ip_detect",
            "title": "检测 VPS IP",
            "status": "pending",
            "message": "需要先选择域名。",
        })

    # 5. DNS plan
    if dns == "configured":
        steps.append({
            "id": "dns_plan",
            "title": "域名指向",
            "status": "done",
            "message": f"已将 proxy.{domain} 和 web.{domain} 指向你的服务器。",
        })
    elif dns == "pending":
        steps.append({
            "id": "dns_plan",
            "title": "域名指向",
            "status": "current",
            "message": (f"将把 proxy.{domain} 和 web.{domain} 指向你的服务器 IP。\n"
                        f"  需要安全确认，不确认就不会执行。"),
        })
    else:
        steps.append({
            "id": "dns_plan",
            "title": "域名指向",
            "status": "pending",
            "message": "需要先检测 VPS IP。",
        })

    # 6. Certificate
    if cert == "ready":
        steps.append({
            "id": "cert_plan",
            "title": "HTTPS 安全证书",
            "status": "done",
            "message": "HTTPS 安全证书已准备就绪。",
        })
    elif cert == "pending":
        steps.append({
            "id": "cert_plan",
            "title": "HTTPS 安全证书",
            "status": "current",
            "message": "将为你的域名准备 HTTPS 安全证书。\n  需要安全确认，不确认就不会执行。",
        })
    else:
        steps.append({
            "id": "cert_plan",
            "title": "HTTPS 安全证书",
            "status": "pending",
            "message": "需要先完成域名指向。",
        })

    # 7. Subscription token
    if token == "normal":
        steps.append({
            "id": "token_plan",
            "title": "订阅密钥",
            "status": "done",
            "message": "订阅密钥已正常。",
        })
    elif token == "pending":
        steps.append({
            "id": "token_plan",
            "title": "订阅密钥",
            "status": "current",
            "message": "将重新生成订阅密钥。\n  需要安全确认，不确认就不会执行。",
        })
    else:
        steps.append({
            "id": "token_plan",
            "title": "订阅密钥",
            "status": "pending",
            "message": "需要先完成 HTTPS 安全证书。",
        })

    return steps


# ── Text renderer ──────────────────────────────────────────────────────────

_STATUS_ICONS = {
    "done": "✓",
    "current": "▸",
    "pending": "○",
    "blocked": "✗",
}

_STATUS_LABELS = {
    "done": "已完成",
    "current": "进行中",
    "pending": "待处理",
    "blocked": "已阻断",
}


def render_flow_text(steps, status):
    """Render the beginner flow as Chinese text."""
    lines = []

    # Logo
    lines.append(_LOGO)
    lines.append("  NanoBK 新手设置流程")
    lines.append("")

    # Step-by-step flow
    lines.append("  ┌─ 设置流程 ──────────────────────────────────┐")
    for i, step in enumerate(steps):
        icon = _STATUS_ICONS.get(step["status"], "?")
        label = _STATUS_LABELS.get(step["status"], "")
        title = step["title"]

        if step["status"] == "current":
            lines.append(f"  │")
            lines.append(f"  │ {icon} {title}  [{label}]")
            # Indent multi-line messages
            for msg_line in step["message"].split("\n"):
                lines.append(f"  │   {msg_line}")
        elif step["status"] == "blocked":
            lines.append(f"  │")
            lines.append(f"  │ {icon} {title}  [{label}]")
            for msg_line in step["message"].split("\n"):
                lines.append(f"  │   {msg_line}")
        elif step["status"] == "done":
            # Show brief summary for done steps
            first_line = step["message"].split("\n")[0]
            lines.append(f"  │ {icon} {title} — {first_line}")
        else:
            lines.append(f"  │ {icon} {title}")

    lines.append("  │")
    lines.append("  └──────────────────────────────────────────────┘")
    lines.append("")

    # Safety notice
    safety = status.get("safety", "read_only")
    if safety == "read_only":
        lines.append("  安全提示：当前为只读模式，不会执行任何修改。")
        lines.append("  所有变更都需要安全确认才会执行。")
    elif safety == "waiting_confirmation":
        lines.append("  安全提示：以下操作需要安全确认才会执行。")
        lines.append("  不确认就不会执行任何修改。")
    elif safety == "complete":
        lines.append("  所有设置已完成！")
    lines.append("")

    return "\n".join(lines)


# ── JSON output ────────────────────────────────────────────────────────────

def gather_flow_json(ip_fixture=None, dns_fixture=None, cert_fixture=None, token_fixture=None):
    """Gather flow status as safe JSON dict.

    Never includes:
    - api_env_path, CF_API_TOKEN, token, private_key
    - subscription URL, zone_id, record_id
    - raw API URL, raw API response, env file path
    """
    status = _gather_flow_status(
        ip_fixture=ip_fixture,
        dns_fixture=dns_fixture,
        cert_fixture=cert_fixture,
        token_fixture=token_fixture,
    )
    steps = _build_steps(status)

    return {
        "ok": True,
        "stage": status["stage"],
        "steps": steps,
        "next_step": status["next_step"],
        "safety": status["safety"],
    }


def gather_status_json(ip_fixture=None, dns_fixture=None, cert_fixture=None, token_fixture=None):
    """Gather beginner status as safe JSON (same schema as nanobk_cli_home)."""
    status = _gather_flow_status(
        ip_fixture=ip_fixture,
        dns_fixture=dns_fixture,
        cert_fixture=cert_fixture,
        token_fixture=token_fixture,
    )
    return {
        "ok": True,
        "cloudflare": status["cloudflare"],
        "domain": status["domain"],
        "vps_ip": status["vps_ip"],
        "dns": status["dns"],
        "certificate": status["certificate"],
        "subscription_token": status["subscription_token"],
        "web_panel": "not_configured",
        "safety": status["safety"],
        "next_step": status["next_step"],
    }


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Beginner Flow Renderer"
    )
    sub = parser.add_subparsers(dest="command")

    # Default / status
    status_parser = sub.add_parser("status", help="Show beginner status")
    status_parser.add_argument("--json", action="store_true", help="JSON output")

    # Flow
    flow_parser = sub.add_parser("flow", help="Show setup flow")
    flow_parser.add_argument("--json", action="store_true", help="JSON output")

    # Also accept --json at top level (no subcommand = flow)
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    command = args.command or "flow"
    use_json = getattr(args, "json", False)

    if command == "status":
        if use_json:
            result = gather_status_json()
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            status = _gather_flow_status()
            steps = _build_steps(status)
            print(render_flow_text(steps, status))
    elif command == "flow":
        if use_json:
            result = gather_flow_json()
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            status = _gather_flow_status()
            steps = _build_steps(status)
            print(render_flow_text(steps, status))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
