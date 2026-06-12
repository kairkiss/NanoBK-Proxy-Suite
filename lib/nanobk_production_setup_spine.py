#!/usr/bin/env python3
"""
NanoBK Production Setup Integration Spine (v2.5.0)

Read-only production setup state machine that maps legacy v1.9 capabilities
into the new nanobk beginner CLI entry point.

Read-only. No DNS mutation. No Cloudflare mutation.
No curl/wrangler/certbot calls. No service reload/restart.
No installer execution. No certificate request. No token rotation.

Usage:
    python3 lib/nanobk_production_setup_spine.py [--json]
    python3 lib/nanobk_production_setup_spine.py status [--json]
    python3 lib/nanobk_production_setup_spine.py plan [--json]
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_profile import load_profile, default_profile_path


# ── Production setup stages ────────────────────────────────────────────────

_STAGES = [
    {
        "id": "install_ready",
        "title": "安装就绪",
        "message": "NanoBK 仓库和 CLI 已安装，可以开始设置。",
        "command_hint": "nanobk install-cli",
        "safety": "read_only",
    },
    {
        "id": "cloudflare_login",
        "title": "连接 Cloudflare",
        "message": "连接你的 Cloudflare 账号，验证 API 授权。",
        "command_hint": "nanobk cf connect",
        "safety": "read_only",
    },
    {
        "id": "domain_select",
        "title": "选择你的域名",
        "message": "从你的 Cloudflare 域名中选择一个用于代理服务。",
        "command_hint": "nanobk cf connect",
        "safety": "read_only",
    },
    {
        "id": "vps_ip_detect",
        "title": "检测服务器 IP",
        "message": "自动检测你的 VPS 公网 IPv4 和 IPv6 地址。",
        "command_hint": "nanobk beginner ip",
        "safety": "read_only",
    },
    {
        "id": "subdomain_plan",
        "title": "规划子域名",
        "message": "规划 proxy 和 web 子域名，检查是否可用。",
        "command_hint": "nanobk beginner subdomain --domain your-domain.com",
        "safety": "read_only",
    },
    {
        "id": "dns_apply_gate",
        "title": "域名指向（DNS）",
        "message": "把域名指向你的服务器 IP。需要安全确认，不确认就不会执行。",
        "command_hint": "nanobk setup dns apply",
        "safety": "requires_confirmation",
    },
    {
        "id": "cert_issue_gate",
        "title": "HTTPS 安全证书",
        "message": "为你的域名申请 HTTPS 安全证书。需要安全确认，不确认就不会执行。",
        "command_hint": "nanobk setup cert issue",
        "safety": "requires_confirmation",
    },
    {
        "id": "vps_four_protocols",
        "title": "代理服务核心",
        "message": "部署四个代理通道：Reality、TUIC、HY2、Trojan。",
        "command_hint": "nanobk install --mode vps",
        "safety": "requires_confirmation",
    },
    {
        "id": "worker_nanok",
        "title": "订阅服务入口（nanok）",
        "message": "部署 Cloudflare nanok Worker，提供订阅链接服务。",
        "command_hint": "nanobk install --mode cloudflare",
        "safety": "requires_confirmation",
    },
    {
        "id": "worker_nanob",
        "title": "聚合服务入口（nanob）",
        "message": "部署 Cloudflare nanob Worker，提供节点聚合服务。",
        "command_hint": "nanobk install --mode cloudflare",
        "safety": "requires_confirmation",
    },
    {
        "id": "subscription_token",
        "title": "订阅密钥",
        "message": "生成或轮换订阅密钥，用于客户端连接。需要安全确认。",
        "command_hint": "nanobk setup token rotate",
        "safety": "requires_confirmation",
    },
    {
        "id": "protocol_key_rotation",
        "title": "代理密钥轮换",
        "message": "轮换四个代理通道的密钥，提升安全性。",
        "command_hint": "nanobk rotate all",
        "safety": "requires_confirmation",
    },
    {
        "id": "bot_web_optional",
        "title": "Bot 和 Web 面板（可选）",
        "message": "配置 Telegram Bot 和 Web 管理面板。可选步骤。",
        "command_hint": "nanobk install --mode full",
        "safety": "manual",
    },
    {
        "id": "final_status",
        "title": "完成",
        "message": "所有生产设置步骤完成。检查最终状态。",
        "command_hint": "nanobk home",
        "safety": "read_only",
    },
]


# ── Old capability mapping ─────────────────────────────────────────────────

_OLD_CAPABILITIES = [
    {
        "name": "VPS 四协议部署",
        "description": "部署 Reality、TUIC、HY2、Trojan 四个代理通道到你的 VPS。",
        "command": "nanobk install --mode vps",
        "stage": "vps_four_protocols",
    },
    {
        "name": "Cloudflare nanok/nanob 部署",
        "description": "部署 Cloudflare Workers（订阅服务和聚合服务）。",
        "command": "nanobk install --mode cloudflare",
        "stage": "worker_nanok",
    },
    {
        "name": "完整安装向导",
        "description": "一键完成 VPS + Cloudflare 全部部署。",
        "command": "nanobk install --mode full",
        "stage": "bot_web_optional",
    },
    {
        "name": "DNS 创建 gate",
        "description": "把域名指向你的服务器 IP。需要输入确认短语。",
        "command": "nanobk setup dns apply",
        "stage": "dns_apply_gate",
    },
    {
        "name": "证书签发 gate",
        "description": "为你的域名申请 HTTPS 安全证书。需要输入确认短语。",
        "command": "nanobk setup cert issue",
        "stage": "cert_issue_gate",
    },
    {
        "name": "订阅密钥轮换 gate",
        "description": "重新生成订阅密钥。需要输入确认短语。",
        "command": "nanobk setup token rotate",
        "stage": "subscription_token",
    },
    {
        "name": "协议密钥轮换（全部）",
        "description": "轮换所有四个代理通道的密钥。",
        "command": "nanobk rotate all",
        "stage": "protocol_key_rotation",
    },
    {
        "name": "协议密钥轮换（HY2）",
        "description": "单独轮换 HY2 代理通道的密钥。",
        "command": "nanobk rotate hy2",
        "stage": "protocol_key_rotation",
    },
    {
        "name": "协议密钥轮换（TUIC）",
        "description": "单独轮换 TUIC 代理通道的密钥。",
        "command": "nanobk rotate tuic",
        "stage": "protocol_key_rotation",
    },
    {
        "name": "协议密钥轮换（Reality）",
        "description": "单独轮换 Reality 代理通道的密钥。",
        "command": "nanobk rotate reality",
        "stage": "protocol_key_rotation",
    },
    {
        "name": "协议密钥轮换（Trojan）",
        "description": "单独轮换 Trojan 代理通道的密钥。",
        "command": "nanobk rotate trojan",
        "stage": "protocol_key_rotation",
    },
]


# ── Status gathering ───────────────────────────────────────────────────────

def _infer_stage_statuses():
    """Infer status for each stage based on profile/config hints.

    Read-only. No network calls. No mutation.
    Returns a dict mapping stage_id -> status string.
    """
    profile_path = default_profile_path()
    has_profile = os.path.isfile(profile_path)

    statuses = {}

    # install_ready: always done if we can run this module
    statuses["install_ready"] = "done"

    if not has_profile:
        statuses["cloudflare_login"] = "current"
        statuses["domain_select"] = "pending"
        statuses["vps_ip_detect"] = "pending"
        statuses["subdomain_plan"] = "pending"
        statuses["dns_apply_gate"] = "pending"
        statuses["cert_issue_gate"] = "pending"
        statuses["vps_four_protocols"] = "pending"
        statuses["worker_nanok"] = "pending"
        statuses["worker_nanob"] = "pending"
        statuses["subscription_token"] = "pending"
        statuses["protocol_key_rotation"] = "pending"
        statuses["bot_web_optional"] = "pending"
        statuses["final_status"] = "pending"
        return statuses

    profile, profile_err = load_profile()

    if profile_err:
        statuses["cloudflare_login"] = "done"
        statuses["domain_select"] = "current"
        statuses["vps_ip_detect"] = "pending"
        statuses["subdomain_plan"] = "pending"
        statuses["dns_apply_gate"] = "pending"
        statuses["cert_issue_gate"] = "pending"
        statuses["vps_four_protocols"] = "pending"
        statuses["worker_nanok"] = "pending"
        statuses["worker_nanob"] = "pending"
        statuses["subscription_token"] = "pending"
        statuses["protocol_key_rotation"] = "pending"
        statuses["bot_web_optional"] = "pending"
        statuses["final_status"] = "pending"
        return statuses

    # Profile loaded — cloudflare and domain are done
    statuses["cloudflare_login"] = "done"
    statuses["domain_select"] = "done"

    zone = profile.get("zone_name", "")
    if zone:
        statuses["vps_ip_detect"] = "current"
        statuses["subdomain_plan"] = "pending"
    else:
        statuses["vps_ip_detect"] = "pending"
        statuses["subdomain_plan"] = "pending"

    # Remaining stages are pending (read-only spine, no mutation state tracking)
    for stage_id in [
        "subdomain_plan", "dns_apply_gate", "cert_issue_gate",
        "vps_four_protocols", "worker_nanok", "worker_nanob",
        "subscription_token", "protocol_key_rotation",
        "bot_web_optional", "final_status",
    ]:
        if stage_id not in statuses:
            statuses[stage_id] = "pending"

    return statuses


def _build_stage_steps(statuses):
    """Build the full stage list with inferred statuses."""
    steps = []
    for stage_def in _STAGES:
        step = dict(stage_def)
        step["status"] = statuses.get(stage_def["id"], "pending")
        steps.append(step)
    return steps


def _find_current_stage(steps):
    """Find the current (first non-done) stage."""
    for step in steps:
        if step["status"] == "current":
            return step["id"]
    # If no 'current', find first 'pending'
    for step in steps:
        if step["status"] == "pending":
            return step["id"]
    return "final_status"


# ── Text renderer ──────────────────────────────────────────────────────────

_STATUS_ICONS = {
    "done": "✓",
    "current": "▸",
    "pending": "○",
    "blocked": "✗",
    "manual_confirm_required": "⚠",
    "manual": "○",
}

_STATUS_LABELS = {
    "done": "已完成",
    "current": "进行中",
    "pending": "待处理",
    "blocked": "已阻断",
    "manual_confirm_required": "需确认",
    "manual": "手动",
}

_SAFETY_LABELS = {
    "read_only": "只读",
    "preview_only": "仅预览",
    "requires_confirmation": "需确认",
    "manual": "手动",
}


def render_production_text(steps, current_stage):
    """Render the production setup spine as Chinese text."""
    lines = []

    lines.append("  NanoBK 生产设置主线")
    lines.append("  ─────────────────────────────────────────────")
    lines.append("")
    lines.append("  这是你的完整生产部署路线图。")
    lines.append("  每一步都对应一个旧能力入口，需要时可以单独运行。")
    lines.append("  当前不会自动执行任何操作。")
    lines.append("")

    lines.append("  ┌─ 生产部署流程 ────────────────────────────────┐")
    for step in steps:
        icon = _STATUS_ICONS.get(step["status"], "?")
        label = _STATUS_LABELS.get(step["status"], "")
        title = step["title"]

        if step["status"] == "current":
            lines.append(f"  │")
            lines.append(f"  │ {icon} {title}  [{label}]")
            lines.append(f"  │   {step['message']}")
            lines.append(f"  │   命令：{step['command_hint']}")
        elif step["status"] == "done":
            lines.append(f"  │ {icon} {title} — {step['message'][:40]}")
        else:
            safety_label = _SAFETY_LABELS.get(step["safety"], "")
            lines.append(f"  │ {icon} {title}  [{safety_label}]")

    lines.append("  │")
    lines.append("  └──────────────────────────────────────────────┘")
    lines.append("")

    # Old capability mapping
    lines.append("  ┌─ 旧能力入口 ────────────────────────────────┐")
    lines.append("  │  以下是已有的部署能力，都已挂接到上面的流程：  │")
    lines.append("  │                                              │")
    for cap in _OLD_CAPABILITIES:
        lines.append(f"  │  • {cap['command']}")
        lines.append(f"    {cap['description']}")
    lines.append("  │")
    lines.append("  └──────────────────────────────────────────────┘")
    lines.append("")

    lines.append("  安全提示：以上所有命令默认只显示预案。")
    lines.append("  真正执行需要你输入确认短语。")
    lines.append("  不确认就不会执行任何修改。")
    lines.append("")

    return "\n".join(lines)


# ── JSON output ────────────────────────────────────────────────────────────

def gather_production_json():
    """Gather production setup status as safe JSON dict.

    Never includes:
    - api_env_path, CF_API_TOKEN, ADMIN_TOKEN, SUB_TOKEN
    - private_key, subscription URL
    - zone_id, record_id
    - raw API URL, raw API response, env file path
    - workers.dev raw secret URL
    """
    statuses = _infer_stage_statuses()
    steps = _build_stage_steps(statuses)
    current_stage = _find_current_stage(steps)

    return {
        "ok": True,
        "mode": "production_setup_v2_5",
        "version": "2.5.0",
        "mutation": False,
        "dangerous_actions_executed": False,
        "stage": current_stage,
        "next_step": current_stage,
        "safety": "read_only",
        "steps": steps,
        "old_capabilities": _OLD_CAPABILITIES,
    }


def gather_production_status_json():
    """Alias for gather_production_json (status subcommand)."""
    return gather_production_json()


def gather_production_plan_json():
    """Alias for gather_production_json (plan subcommand)."""
    return gather_production_json()


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Production Setup Integration Spine"
    )
    sub = parser.add_subparsers(dest="command")

    # Default / status
    status_parser = sub.add_parser("status", help="Show production setup status")
    status_parser.add_argument("--json", action="store_true", help="JSON output")

    # Plan
    plan_parser = sub.add_parser("plan", help="Show production setup plan")
    plan_parser.add_argument("--json", action="store_true", help="JSON output")

    # Also accept --json at top level (no subcommand = status)
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    command = args.command or "status"
    use_json = getattr(args, "json", False)

    if command in ("status", "plan"):
        if use_json:
            result = gather_production_json()
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            statuses = _infer_stage_statuses()
            steps = _build_stage_steps(statuses)
            current_stage = _find_current_stage(steps)
            print(render_production_text(steps, current_stage))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
