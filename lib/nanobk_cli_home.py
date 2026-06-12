#!/usr/bin/env python3
"""
NanoBK Beginner-Friendly CLI Home (v2.4.1)

Shows a Chinese-language home screen with:
- NanoBK logo
- Status dashboard (beginner-friendly labels)
- Chinese main menu
- Safe JSON output (no tokens/secrets/paths)

Read-only. No DNS mutation. No Cloudflare mutation.
No curl/wrangler/certbot calls. No service reload/restart.

Usage:
    python3 lib/nanobk_cli_home.py home [--json]
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


# ── Status gathering ───────────────────────────────────────────────────────

def _gather_status():
    """Gather home status from profile only.

    Returns a beginner-friendly status dict.
    Read-only. No network calls. No mutation. No curl.
    """
    profile_path = default_profile_path()
    has_profile = os.path.isfile(profile_path)

    if not has_profile:
        return {
            "cloudflare": "disconnected",
            "domain": "not_selected",
            "vps_ip": {"ipv4": "unknown", "ipv6": "unknown"},
            "dns": "not_configured",
            "certificate": "not_checked",
            "subscription_token": "not_checked",
            "web_panel": "not_configured",
            "safety": "read_only",
            "next_step": "connect_cloudflare",
        }

    # Try loading profile
    profile, profile_err = load_profile()

    if profile_err:
        # Profile exists but has issues
        return {
            "cloudflare": "connected",
            "domain": "not_selected",
            "vps_ip": {"ipv4": "unknown", "ipv6": "unknown"},
            "dns": "not_configured",
            "certificate": "not_checked",
            "subscription_token": "not_checked",
            "web_panel": "not_configured",
            "safety": "waiting_confirmation",
            "next_step": "run_beginner_setup",
        }

    # Profile loaded successfully
    zone = profile.get("zone_name", "")
    domain = zone if zone else "not_selected"

    # Derive status from profile data only (no network calls)
    if domain != "not_selected":
        cloudflare = "connected"
        dns_status = "pending"
        safety = "waiting_confirmation"
        next_step = "run_beginner_setup"
    else:
        cloudflare = "disconnected"
        dns_status = "not_configured"
        safety = "read_only"
        next_step = "connect_cloudflare"

    return {
        "cloudflare": cloudflare,
        "domain": domain,
        "vps_ip": {"ipv4": "unknown", "ipv6": "unknown"},
        "dns": dns_status,
        "certificate": "not_checked",
        "subscription_token": "not_checked",
        "web_panel": "not_configured",
        "safety": safety,
        "next_step": next_step,
    }


# ── Text renderer ──────────────────────────────────────────────────────────

def _status_icon(value, good_values):
    """Return a visual indicator for a status value."""
    if value in good_values:
        return "✓"
    elif value in ("not_configured", "not_selected", "not_checked", "unknown"):
        return "○"
    else:
        return "…"


def _map_next_step(step):
    """Map next_step code to Chinese description."""
    mapping = {
        "connect_cloudflare": "连接 Cloudflare 账号",
        "run_beginner_setup": "运行新手设置向导",
        "review_status": "检查当前配置状态",
    }
    return mapping.get(step, step)


def render_home_text(status):
    """Render beginner-friendly Chinese home screen text."""
    lines = []

    # Logo
    lines.append(_LOGO)
    lines.append("  NanoBK 让 VPS 代理部署变简单")
    lines.append("")

    # Status card
    lines.append("  ┌─ 当前状态 ──────────────────────────────────┐")

    # Cloudflare
    cf = status["cloudflare"]
    cf_icon = _status_icon(cf, ("connected",))
    cf_label = "已连接" if cf == "connected" else "未连接"
    lines.append("  │ Cloudflare：{} {}".format(cf_icon, cf_label))

    # Domain
    domain = status["domain"]
    if domain == "not_selected":
        domain_label = "未选择"
    else:
        domain_label = domain
    lines.append("  │ 域名：      {} {}".format(
        _status_icon(domain, ("connected",)), domain_label))

    # VPS IP
    ipv4 = status["vps_ip"]["ipv4"]
    ipv6 = status["vps_ip"]["ipv6"]
    ipv4_label = "已检测" if ipv4 == "detected" else "未检测"
    ipv6_label = "已检测" if ipv6 == "detected" else "未检测"
    lines.append("  │ VPS IP：    IPv4 {} / IPv6 {}".format(ipv4_label, ipv6_label))

    # DNS
    dns = status["dns"]
    dns_map = {
        "not_configured": "未配置",
        "pending": "待确认",
        "configured": "已配置",
    }
    dns_label = dns_map.get(dns, dns)
    lines.append("  │ DNS：       {} {}".format(_status_icon(dns, ("configured",)), dns_label))

    # Certificate
    cert = status["certificate"]
    cert_map = {
        "not_checked": "未检测",
        "pending": "待申请",
        "ready": "已准备",
    }
    cert_label = cert_map.get(cert, cert)
    lines.append("  │ 证书：      {} {}".format(_status_icon(cert, ("ready",)), cert_label))

    # Subscription token
    token = status["subscription_token"]
    token_map = {
        "not_checked": "未检查",
        "pending": "待轮换",
        "normal": "正常",
    }
    token_label = token_map.get(token, token)
    lines.append("  │ 订阅密钥：  {} {}".format(_status_icon(token, ("normal",)), token_label))

    # Web panel
    web = status["web_panel"]
    web_map = {
        "not_configured": "未配置",
        "configured": "已配置",
    }
    web_label = web_map.get(web, web)
    lines.append("  │ Web 面板：  {} {}".format(_status_icon(web, ("configured",)), web_label))

    # Safety
    safety = status["safety"]
    safety_map = {
        "read_only": "只读（安全）",
        "waiting_confirmation": "等待确认",
        "complete": "已完成",
    }
    safety_label = safety_map.get(safety, safety)
    lines.append("  │ 当前状态：  {}".format(safety_label))

    # Next step
    next_step = _map_next_step(status["next_step"])
    lines.append("  │")
    lines.append("  │ 下一步：    {}".format(next_step))

    lines.append("  └──────────────────────────────────────────────┘")
    lines.append("")

    return "\n".join(lines)


def render_menu():
    """Render the beginner Chinese menu."""
    lines = []
    lines.append("  ┌─ 主菜单 ────────────────────────────────────┐")
    lines.append("  │                                              │")
    lines.append("  │  1) 开始新手设置                             │")
    lines.append("  │  2) 查看当前状态                             │")
    lines.append("  │  3) 修复问题                                 │")
    lines.append("  │  4) 高级选项                                 │")
    lines.append("  │  5) 退出                                     │")
    lines.append("  │                                              │")
    lines.append("  └──────────────────────────────────────────────┘")
    lines.append("")
    return "\n".join(lines)


def render_home_full():
    """Render complete home screen (logo + status + menu)."""
    status = _gather_status()
    text = render_home_text(status)
    menu = render_menu()
    return text + "\n" + menu


# ── JSON output ────────────────────────────────────────────────────────────

def gather_home_json():
    """Gather home status as safe JSON dict.

    Never includes:
    - api_env_path, CF_API_TOKEN, token, private_key
    - subscription URL, zone_id, record_id
    - raw API URL, raw API response, env file path
    """
    status = _gather_status()
    return {
        "ok": True,
        "cloudflare": status["cloudflare"],
        "domain": status["domain"],
        "vps_ip": status["vps_ip"],
        "dns": status["dns"],
        "certificate": status["certificate"],
        "subscription_token": status["subscription_token"],
        "web_panel": status["web_panel"],
        "safety": status["safety"],
        "next_step": status["next_step"],
    }


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Beginner-Friendly CLI Home"
    )
    sub = parser.add_subparsers(dest="command")

    home_parser = sub.add_parser("home", help="Show beginner home screen")
    home_parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.command != "home":
        parser.print_help()
        sys.exit(1)

    if args.json:
        result = gather_home_json()
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(render_home_full())


if __name__ == "__main__":
    main()
