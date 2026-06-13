#!/usr/bin/env python3
"""
NanoBK Production Setup Integration Spine (v2.5.3)

Read-only production setup state machine that maps legacy v1.9 capabilities
into the new nanobk beginner CLI entry point.
Includes action plan builder for clear command cards.

Read-only. No DNS mutation. No Cloudflare mutation.
No curl/wrangler/certbot calls. No service reload/restart.
No installer execution. No certificate request. No token rotation.

Usage:
    python3 lib/nanobk_production_setup_spine.py [--json]
    python3 lib/nanobk_production_setup_spine.py status [--json]
    python3 lib/nanobk_production_setup_spine.py plan [--json]
    python3 lib/nanobk_production_setup_spine.py actions [--json]
    python3 lib/nanobk_production_setup_spine.py dns [--json]
    python3 lib/nanobk_production_setup_spine.py worker [--json]
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


# ── Exact confirmation phrases ─────────────────────────────────────────────

EXACT_PHRASE_DNS = "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"
EXACT_PHRASE_CERT = "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"
EXACT_PHRASE_TOKEN = "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"


# ── Action plan definition ─────────────────────────────────────────────────

_ACTIONS = [
    {
        "id": "cloudflare_login",
        "title": "连接 Cloudflare",
        "kind": "interactive",
        "summary": "登录授权并读取你的域名列表",
        "command": "nanobk cf connect",
        "will_modify": False,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "domain_select",
        "title": "选择你的域名",
        "kind": "interactive",
        "summary": "从 Cloudflare 域名中选择一个用于代理服务",
        "command": "nanobk cf connect",
        "will_modify": False,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "vps_ip_detect",
        "title": "检测服务器 IP",
        "kind": "read_only",
        "summary": "自动检测 VPS 公网 IPv4 和 IPv6 地址",
        "command": "nanobk beginner ip",
        "will_modify": False,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": True,
    },
    {
        "id": "subdomain_plan",
        "title": "规划子域名",
        "kind": "read_only",
        "summary": "检查 proxy/web 子域名是否可用",
        "command": "nanobk beginner subdomain --domain your-domain.com",
        "will_modify": False,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": True,
    },
    {
        "id": "dns_apply_gate",
        "title": "域名指向（DNS）",
        "kind": "dangerous_gate",
        "summary": "把 proxy/web 子域名指向你的服务器 IP",
        "command": f"nanobk setup dns apply --apply --confirm \"{EXACT_PHRASE_DNS}\"",
        "will_modify": True,
        "requires_exact_phrase": True,
        "exact_phrase_label": EXACT_PHRASE_DNS,
        "safe_to_auto_run": False,
    },
    {
        "id": "cert_issue_gate",
        "title": "HTTPS 安全证书",
        "kind": "dangerous_gate",
        "summary": "为你的域名申请 HTTPS 安全证书",
        "command": f"nanobk setup cert issue --issue --confirm \"{EXACT_PHRASE_CERT}\"",
        "will_modify": True,
        "requires_exact_phrase": True,
        "exact_phrase_label": EXACT_PHRASE_CERT,
        "safe_to_auto_run": False,
    },
    {
        "id": "vps_four_protocols",
        "title": "代理服务核心（四协议部署）",
        "kind": "interactive",
        "summary": "部署 Reality、TUIC、HY2、Trojan 四个代理通道到 VPS",
        "command": "nanobk install --mode vps",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "worker_nanok",
        "title": "订阅服务入口（nanok Worker）",
        "kind": "interactive",
        "summary": "部署 Cloudflare nanok Worker，提供订阅链接服务",
        "command": "nanobk install --mode cloudflare",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "worker_nanob",
        "title": "聚合服务入口（nanob Worker）",
        "kind": "interactive",
        "summary": "部署 Cloudflare nanob Worker，提供节点聚合服务",
        "command": "nanobk install --mode cloudflare",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "subscription_token",
        "title": "订阅密钥轮换",
        "kind": "dangerous_gate",
        "summary": "重新生成订阅密钥，用于客户端连接",
        "command": f"nanobk setup token rotate --rotate --confirm \"{EXACT_PHRASE_TOKEN}\"",
        "will_modify": True,
        "requires_exact_phrase": True,
        "exact_phrase_label": EXACT_PHRASE_TOKEN,
        "safe_to_auto_run": False,
    },
    {
        "id": "protocol_key_rotation",
        "title": "代理密钥轮换",
        "kind": "interactive",
        "summary": "轮换四个代理通道的密钥，提升安全性。后续 v2.5.5 会和订阅 token 轮换联动。",
        "command": "nanobk rotate all",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "bot_web_optional",
        "title": "Bot 和 Web 面板（可选）",
        "kind": "interactive",
        "summary": "配置 Telegram Bot 和 Web 管理面板，可选步骤",
        "command": "nanobk install --mode full",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "protocol_hy2",
        "title": "轮换 HY2 密钥",
        "kind": "interactive",
        "summary": "单独轮换 HY2 代理通道的密钥",
        "command": "nanobk rotate hy2",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "protocol_tuic",
        "title": "轮换 TUIC 密钥",
        "kind": "interactive",
        "summary": "单独轮换 TUIC 代理通道的密钥",
        "command": "nanobk rotate tuic",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "protocol_reality",
        "title": "轮换 Reality 密钥",
        "kind": "interactive",
        "summary": "单独轮换 Reality 代理通道的密钥",
        "command": "nanobk rotate reality",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "protocol_trojan",
        "title": "轮换 Trojan 密钥",
        "kind": "interactive",
        "summary": "单独轮换 Trojan 代理通道的密钥",
        "command": "nanobk rotate trojan",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": False,
    },
    {
        "id": "final_status",
        "title": "检查最终状态",
        "kind": "read_only",
        "summary": "查看当前 NanoBK 生产部署状态",
        "command": "nanobk home",
        "will_modify": False,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "safe_to_auto_run": True,
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


# ── Action plan status inference ───────────────────────────────────────────

def _infer_action_statuses():
    """Infer status for each action based on profile/config hints.

    Read-only. No network calls. No mutation.
    Returns a dict mapping action_id -> status string.
    """
    profile_path = default_profile_path()
    has_profile = os.path.isfile(profile_path)

    statuses = {}

    if not has_profile:
        statuses["cloudflare_login"] = "available"
        statuses["domain_select"] = "blocked"
        statuses["vps_ip_detect"] = "blocked"
        statuses["subdomain_plan"] = "blocked"
        statuses["dns_apply_gate"] = "blocked"
        statuses["cert_issue_gate"] = "blocked"
        statuses["vps_four_protocols"] = "blocked"
        statuses["worker_nanok"] = "blocked"
        statuses["worker_nanob"] = "blocked"
        statuses["subscription_token"] = "blocked"
        statuses["protocol_key_rotation"] = "blocked"
        statuses["bot_web_optional"] = "blocked"
        statuses["protocol_hy2"] = "blocked"
        statuses["protocol_tuic"] = "blocked"
        statuses["protocol_reality"] = "blocked"
        statuses["protocol_trojan"] = "blocked"
        statuses["final_status"] = "blocked"
        return statuses

    profile, profile_err = load_profile()

    if profile_err:
        statuses["cloudflare_login"] = "available"
        statuses["domain_select"] = "available"
        statuses["vps_ip_detect"] = "blocked"
        statuses["subdomain_plan"] = "blocked"
        statuses["dns_apply_gate"] = "blocked"
        statuses["cert_issue_gate"] = "blocked"
        statuses["vps_four_protocols"] = "blocked"
        statuses["worker_nanok"] = "blocked"
        statuses["worker_nanob"] = "blocked"
        statuses["subscription_token"] = "blocked"
        statuses["protocol_key_rotation"] = "blocked"
        statuses["bot_web_optional"] = "blocked"
        statuses["protocol_hy2"] = "blocked"
        statuses["protocol_tuic"] = "blocked"
        statuses["protocol_reality"] = "blocked"
        statuses["protocol_trojan"] = "blocked"
        statuses["final_status"] = "blocked"
        return statuses

    zone = profile.get("zone_name", "")
    if zone:
        statuses["cloudflare_login"] = "available"
        statuses["domain_select"] = "available"
        statuses["vps_ip_detect"] = "available"
        statuses["subdomain_plan"] = "available"
        statuses["dns_apply_gate"] = "requires_confirmation"
        statuses["cert_issue_gate"] = "pending"
        statuses["vps_four_protocols"] = "pending"
        statuses["worker_nanok"] = "pending"
        statuses["worker_nanob"] = "pending"
        statuses["subscription_token"] = "pending"
        statuses["protocol_key_rotation"] = "pending"
        statuses["bot_web_optional"] = "pending"
        statuses["protocol_hy2"] = "pending"
        statuses["protocol_tuic"] = "pending"
        statuses["protocol_reality"] = "pending"
        statuses["protocol_trojan"] = "pending"
        statuses["final_status"] = "pending"
    else:
        statuses["cloudflare_login"] = "available"
        statuses["domain_select"] = "available"
        statuses["vps_ip_detect"] = "blocked"
        statuses["subdomain_plan"] = "blocked"
        statuses["dns_apply_gate"] = "blocked"
        statuses["cert_issue_gate"] = "blocked"
        statuses["vps_four_protocols"] = "blocked"
        statuses["worker_nanok"] = "blocked"
        statuses["worker_nanob"] = "blocked"
        statuses["subscription_token"] = "blocked"
        statuses["protocol_key_rotation"] = "blocked"
        statuses["bot_web_optional"] = "blocked"
        statuses["protocol_hy2"] = "blocked"
        statuses["protocol_tuic"] = "blocked"
        statuses["protocol_reality"] = "blocked"
        statuses["protocol_trojan"] = "blocked"
        statuses["final_status"] = "blocked"

    return statuses


def _build_action_steps(statuses):
    """Build the full action list with inferred statuses."""
    steps = []
    for action_def in _ACTIONS:
        step = dict(action_def)
        step["status"] = statuses.get(action_def["id"], "pending")
        step["next_step"] = _next_action_for(action_def["id"])
        steps.append(step)
    return steps


def _next_action_for(action_id):
    """Return the next action id after the given one."""
    ids = [a["id"] for a in _ACTIONS]
    try:
        idx = ids.index(action_id)
        if idx + 1 < len(ids):
            return ids[idx + 1]
    except ValueError:
        pass
    return None


# ── Action plan text renderer ─────────────────────────────────────────────

_ACTION_KIND_LABELS = {
    "read_only": "只读",
    "interactive": "交互",
    "dangerous_gate": "危险操作，需要安全确认",
    "legacy_installer": "安装器",
    "manual": "手动",
}


def render_actions_text(steps):
    """Render the action plan as Chinese text cards."""
    lines = []

    lines.append("  NanoBK 生产动作预案")
    lines.append("  ─────────────────────────────────────────────")
    lines.append("")
    lines.append("  当前不会自动执行任何操作。")
    lines.append("")

    for i, step in enumerate(steps, 1):
        kind_label = _ACTION_KIND_LABELS.get(step["kind"], step["kind"])
        lines.append(f"  {i}. {step['title']}")
        lines.append(f"     类型：{kind_label}")
        lines.append(f"     作用：{step['summary']}")
        lines.append(f"     命令：{step['command']}")
        if step["requires_exact_phrase"] and step["exact_phrase_label"]:
            lines.append(f"     确认短语：{step['exact_phrase_label']}")
        if step["will_modify"]:
            lines.append(f"     会修改系统/Cloudflare：是")
        else:
            lines.append(f"     会修改系统/Cloudflare：否")
        lines.append("")

    lines.append("  安全提示：以上所有命令默认只显示预案。")
    lines.append("  真正执行需要你输入确认短语。")
    lines.append("  不确认就不会执行任何修改。")
    lines.append("")

    return "\n".join(lines)


# ── Action plan JSON output ───────────────────────────────────────────────

def gather_actions_json():
    """Gather action plan as safe JSON dict.

    Never includes:
    - api_env_path, CF_API_TOKEN, ADMIN_TOKEN, SUB_TOKEN
    - private_key, subscription URL
    - zone_id, record_id
    - raw API URL, raw API response, env file path
    - workers.dev raw secret URL
    """
    statuses = _infer_action_statuses()
    steps = _build_action_steps(statuses)

    return {
        "ok": True,
        "mode": "production_actions_v2_5",
        "version": "2.5.1",
        "mutation": False,
        "dangerous_actions_executed": False,
        "safety": "read_only",
        "actions": steps,
    }


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

    # Actions
    actions_parser = sub.add_parser("actions", help="Show production action plan")
    actions_parser.add_argument("--json", action="store_true", help="JSON output")

    # DNS readiness
    dns_parser = sub.add_parser("dns", help="Check DNS readiness (read-only)")
    dns_parser.add_argument("--zone", help="Domain zone to use")
    dns_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    dns_parser.add_argument("--proxy-subdomain", default="proxy", help="Proxy subdomain prefix (default: proxy)")
    dns_parser.add_argument("--web-subdomain", default="web", help="Web subdomain prefix (default: web)")
    dns_parser.add_argument("--save", action="store_true", help="Save local setup profile after check")
    dns_parser.add_argument("--json", action="store_true", help="JSON output")

    # Worker readiness
    worker_parser = sub.add_parser("worker", help="Check Worker readiness (read-only)")
    worker_parser.add_argument("--zone", help="Domain zone to use")
    worker_parser.add_argument("--nanok-subdomain", default="nanok", help="nanok subdomain prefix (default: nanok)")
    worker_parser.add_argument("--nanob-subdomain", default="nanob", help="nanob subdomain prefix (default: nanob)")
    worker_parser.add_argument("--web-subdomain", default="web", help="web subdomain prefix (default: web)")
    worker_parser.add_argument("--save", action="store_true", help="Save local Worker route plan")
    worker_parser.add_argument("--json", action="store_true", help="JSON output")
    # Dangerous args — recognized but rejected
    worker_parser.add_argument("--deploy", action="store_true", help=argparse.SUPPRESS)
    worker_parser.add_argument("--yes", action="store_true", help=argparse.SUPPRESS)
    worker_parser.add_argument("--apply", action="store_true", help=argparse.SUPPRESS)

    # Certificate readiness
    cert_parser = sub.add_parser("cert", help="Check certificate readiness (read-only)")
    cert_parser.add_argument("--zone", help="Domain zone to use")
    cert_parser.add_argument("--domain", help="Full cert domain (e.g. proxy.example.com)")
    cert_parser.add_argument("--mode", choices=["existing", "self-signed", "letsencrypt"],
                             default="unknown", help="Certificate mode")
    cert_parser.add_argument("--cert-file", help="Path to existing certificate file")
    cert_parser.add_argument("--key-file", help="Path to existing private key file")
    cert_parser.add_argument("--save", action="store_true", help="Save local cert plan")
    cert_parser.add_argument("--json", action="store_true", help="JSON output")
    # Dangerous args — recognized but rejected
    cert_parser.add_argument("--issue", action="store_true", help=argparse.SUPPRESS)
    cert_parser.add_argument("--yes", action="store_true", help=argparse.SUPPRESS)
    cert_parser.add_argument("--apply", action="store_true", help=argparse.SUPPRESS)
    cert_parser.add_argument("--certbot", action="store_true", help=argparse.SUPPRESS)

    # Rotation readiness
    rotate_parser = sub.add_parser("rotate", help="Check rotation readiness (read-only)")
    rotate_parser.add_argument("--token", choices=["auto", "custom", "unchanged"],
                               default="auto", help="Token mode (default: auto)")
    rotate_parser.add_argument("--custom-token", help="Custom token value (only with --token custom)")
    rotate_parser.add_argument("--protocol", choices=["all", "hy2", "tuic", "reality", "trojan"],
                               default="all", help="Protocol target (default: all)")
    rotate_parser.add_argument("--save", action="store_true", help="Save local rotation plan")
    rotate_parser.add_argument("--json", action="store_true", help="JSON output")
    # Dangerous args — recognized but rejected
    rotate_parser.add_argument("--rotate", action="store_true", help=argparse.SUPPRESS)
    rotate_parser.add_argument("--yes", action="store_true", help=argparse.SUPPRESS)
    rotate_parser.add_argument("--apply", action="store_true", help=argparse.SUPPRESS)
    rotate_parser.add_argument("--execute", action="store_true", help=argparse.SUPPRESS)
    rotate_parser.add_argument("--confirm", action="store_true", help=argparse.SUPPRESS)

    # Overview
    overview_parser = sub.add_parser("overview", help="Show production overview")
    overview_parser.add_argument("--json", action="store_true", help="JSON output")

    # Next step
    next_parser = sub.add_parser("next", help="Show next recommended step")
    next_parser.add_argument("--json", action="store_true", help="JSON output")

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
    elif command == "actions":
        if use_json:
            result = gather_actions_json()
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            statuses = _infer_action_statuses()
            steps = _build_action_steps(statuses)
            print(render_actions_text(steps))
    elif command == "dns":
        from nanobk_production_dns_readiness import run_readiness, run_save, output_text, output_error
        if args.save:
            result = run_save(
                zone=args.zone,
                api_env=args.api_env,
                proxy_subdomain=args.proxy_subdomain,
                web_subdomain=args.web_subdomain,
            )
            if use_json:
                print(json.dumps(result, indent=2, ensure_ascii=False))
            else:
                if result.get("ok"):
                    print()
                    print(f"  {result.get('message', '已保存。')}")
                    print(f"  域名：{result.get('zone_name', '***')}")
                    print(f"  子域名：{result.get('proxy_subdomain', 'proxy')}, {result.get('web_subdomain', 'web')}")
                    print()
                else:
                    output_error(result.get("error", "unknown error"), False)
                    sys.exit(1)
        else:
            result = run_readiness(
                zone=args.zone,
                api_env=args.api_env,
                proxy_subdomain=args.proxy_subdomain,
                web_subdomain=args.web_subdomain,
            )
            if use_json:
                print(json.dumps(result, indent=2, ensure_ascii=False))
            else:
                if result.get("ok"):
                    output_text(result)
                else:
                    output_error(result.get("error", "unknown error"), False)
                    sys.exit(1)
    elif command == "worker":
        # Reject dangerous args
        if getattr(args, "deploy", False) or getattr(args, "yes", False) or getattr(args, "apply", False):
            msg = "此命令仅用于预览，不会执行部署。"
            if use_json:
                print(json.dumps({"ok": False, "error": msg, "mode": "production_worker_readiness_v2_5", "version": "2.5.3", "mutation": False}, indent=2, ensure_ascii=False))
            else:
                print(f"  错误：{msg}", file=sys.stderr)
            sys.exit(1)
        from nanobk_production_worker_readiness import (
            run_readiness as worker_readiness,
            run_save as worker_save,
            output_text as worker_text,
            output_error as worker_error,
        )
        if args.save:
            result = worker_save(
                zone=args.zone,
                nanok_subdomain=args.nanok_subdomain,
                nanob_subdomain=args.nanob_subdomain,
                web_subdomain=args.web_subdomain,
            )
            if use_json:
                print(json.dumps(result, indent=2, ensure_ascii=False))
            else:
                if result.get("ok"):
                    print()
                    print("  已保存 Worker 路由计划。")
                    print(f"  域名：{result.get('zone_name', '***')}")
                    print()
                else:
                    worker_error(result.get("error", "unknown error"), False)
                    sys.exit(1)
        else:
            result = worker_readiness(
                zone=args.zone,
                nanok_subdomain=args.nanok_subdomain,
                nanob_subdomain=args.nanob_subdomain,
                web_subdomain=args.web_subdomain,
            )
            if use_json:
                print(json.dumps(result, indent=2, ensure_ascii=False))
            else:
                if result.get("ok"):
                    worker_text(result)
                else:
                    worker_error(result.get("error", "unknown error"), False)
                    sys.exit(1)
    elif command == "cert":
        # Reject dangerous args
        if getattr(args, "issue", False) or getattr(args, "yes", False) or getattr(args, "apply", False) or getattr(args, "certbot", False):
            msg = "此命令仅用于预览，不会申请证书。"
            if use_json:
                print(json.dumps({"ok": False, "error": msg, "mode": "production_cert_readiness_v2_5", "version": "2.5.4", "mutation": False}, indent=2, ensure_ascii=False))
            else:
                print(f"  错误：{msg}", file=sys.stderr)
            sys.exit(1)
        from nanobk_production_cert_readiness import (
            run_readiness as cert_readiness,
            run_save as cert_save,
            output_text as cert_text,
            output_error as cert_error,
        )
        if args.save:
            result = cert_save(
                zone=args.zone,
                cert_domain=args.domain,
                cert_mode=args.mode,
                cert_file=args.cert_file,
                key_file=args.key_file,
            )
            if use_json:
                print(json.dumps(result, indent=2, ensure_ascii=False))
            else:
                if result.get("ok"):
                    print()
                    print("  已保存证书计划。")
                    print(f"  域名：{result.get('zone_name', '***')}")
                    print(f"  证书域名：{result.get('cert_domain', '***')}")
                    print(f"  模式：{result.get('cert_mode', '***')}")
                    print()
                else:
                    cert_error(result.get("error", "unknown error"), False)
                    sys.exit(1)
        else:
            result = cert_readiness(
                zone=args.zone,
                cert_domain=args.domain,
                cert_mode=args.mode,
                cert_file=args.cert_file,
                key_file=args.key_file,
            )
            if use_json:
                print(json.dumps(result, indent=2, ensure_ascii=False))
            else:
                if result.get("ok"):
                    cert_text(result)
                else:
                    cert_error(result.get("error", "unknown error"), False)
                    sys.exit(1)
    elif command == "rotate":
        # Reject dangerous args
        if getattr(args, "rotate", False) or getattr(args, "yes", False) or getattr(args, "apply", False) or getattr(args, "execute", False) or getattr(args, "confirm", False):
            msg = "此命令仅用于预览，不会执行轮换。"
            if use_json:
                print(json.dumps({"ok": False, "error": msg, "mode": "production_rotation_readiness_v2_5", "version": "2.5.5", "mutation": False}, indent=2, ensure_ascii=False))
            else:
                print(f"  错误：{msg}", file=sys.stderr)
            sys.exit(1)
        from nanobk_production_rotation_readiness import (
            run_readiness as rotation_readiness,
            run_save as rotation_save,
            output_text as rotation_text,
            output_error as rotation_error,
        )
        if args.save:
            result = rotation_save(
                token_mode=args.token,
                custom_token=args.custom_token,
                protocol=args.protocol,
            )
            if use_json:
                print(json.dumps(result, indent=2, ensure_ascii=False))
                if not result.get("ok"):
                    sys.exit(1)
            else:
                if result.get("ok"):
                    print()
                    print("  已保存轮换计划。")
                    print(f"  Token 模式：{result.get('token_mode', args.token)}")
                    print(f"  协议目标：{result.get('protocol', args.protocol).upper()}")
                    print()
                else:
                    rotation_error(result.get("error", "unknown error"), False)
                    sys.exit(1)
        else:
            result = rotation_readiness(
                token_mode=args.token,
                custom_token=args.custom_token,
                protocol=args.protocol,
            )
            if use_json:
                print(json.dumps(result, indent=2, ensure_ascii=False))
                if not result.get("ok"):
                    sys.exit(1)
            else:
                if result.get("ok"):
                    rotation_text(result)
                else:
                    rotation_error(result.get("error", "unknown error"), False)
                    sys.exit(1)
    elif command == "overview":
        from nanobk_production_overview import gather_overview, output_overview_text
        result = gather_overview()
        if use_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(output_overview_text(result))
    elif command == "next":
        from nanobk_production_overview import gather_next, output_next_text
        result = gather_next()
        if use_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(output_next_text(result))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
