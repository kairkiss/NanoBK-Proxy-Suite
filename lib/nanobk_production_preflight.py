#!/usr/bin/env python3
"""
NanoBK Production Preflight and Controlled Gate Wrapper (v2.5.7)

Read-only preflight check that aggregates all readiness flows and generates
a deployment checklist with exact-gated command cards.

This is the "gate before execution" — it does NOT execute anything.

Read-only. No DNS mutation. No Cloudflare mutation.
No curl/wrangler/certbot calls. No service reload/restart.
No installer execution. No certificate request. No token rotation.

Usage:
    python3 lib/nanobk_production_preflight.py preflight [--json]
    python3 lib/nanobk_production_preflight.py deploy-plan [--json]
    python3 lib/nanobk_production_preflight.py gates [--json]
"""

import argparse
import json
import sys

VERSION = "2.5.7"

# ── Exact confirmation phrases (v2.3 authority) ──────────────────────────────

EXACT_PHRASE_DNS   = "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"
EXACT_PHRASE_CERT  = "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"
EXACT_PHRASE_TOKEN = "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"


# ── Dangerous args that must be rejected ─────────────────────────────────────

_DANGEROUS_ARGS = {
    "--execute", "--yes", "--apply", "--issue",
    "--rotate", "--deploy", "--confirm",
}


# ── Overview loader ──────────────────────────────────────────────────────────

def _load_overview():
    """Load overview from the overview module. Returns safe dict on failure."""
    try:
        from nanobk_production_overview import gather_overview
        return gather_overview()
    except Exception:
        return {
            "ok": True,
            "sections": {
                "dns": {"status": "unknown", "blocked": True, "next_step": "unknown"},
                "worker": {"status": "unknown", "blocked": True, "next_step": "unknown"},
                "cert": {"status": "unknown", "blocked": True, "next_step": "unknown"},
                "rotation": {"status": "unknown", "blocked": True, "next_step": "unknown"},
            },
            "overall": {
                "status": "unknown",
                "next_step": "unknown",
                "recommended_command": "nanobk setup production overview",
                "reason": "无法加载生产部署总览。",
            },
        }


def _load_next():
    """Load next-step from the overview module. Returns safe dict on failure."""
    try:
        from nanobk_production_overview import gather_next
        return gather_next()
    except Exception:
        return {
            "ok": True,
            "next_step": "unknown",
            "recommended_command": "nanobk setup production overview",
            "reason": "无法加载下一步建议。",
        }


# ── Readiness level determination ───────────────────────────────────────────

def _determine_readiness_level(overview):
    """Determine overall readiness level from overview sections.

    Rules:
    - DNS not ready -> blocked
    - Worker not ready -> partial
    - Cert not ready -> partial
    - Rotation not ready -> partial
    - All ready -> ready_for_manual_execution
    """
    sections = overview.get("sections", {})
    dns = sections.get("dns", {})
    worker = sections.get("worker", {})
    cert = sections.get("cert", {})
    rotation = sections.get("rotation", {})

    dns_ready = dns.get("status") == "ready" and not dns.get("blocked", True)
    worker_ready = worker.get("status") == "ready" and not worker.get("blocked", True)
    cert_ready = cert.get("status") == "ready" and not cert.get("blocked", True)
    rotation_ready = rotation.get("status") == "ready" and not rotation.get("blocked", True)

    if not dns_ready:
        return "blocked"
    if not (worker_ready and cert_ready and rotation_ready):
        return "partial"
    return "ready_for_manual_execution"


def _build_blocks(overview):
    """Build the blocks array from overview sections."""
    sections = overview.get("sections", {})
    blocks = []
    for key in ("dns", "worker", "cert", "rotation"):
        section = sections.get(key, {})
        status = section.get("status", "unknown")
        blocked = section.get("blocked", True)
        if blocked or status != "ready":
            label = {
                "dns": "域名与 DNS",
                "worker": "Worker 订阅入口",
                "cert": "HTTPS 安全证书",
                "rotation": "订阅密钥与代理密钥",
            }.get(key, key)
            blocks.append({
                "id": key,
                "status": status,
                "blocked": blocked,
                "message": f"{label}尚未准备就绪" if blocked else f"{label}状态: {status}",
            })
        else:
            blocks.append({
                "id": key,
                "status": "ready",
                "blocked": False,
                "message": "已准备",
            })
    return blocks


# ── Preflight ────────────────────────────────────────────────────────────────

def gather_preflight():
    """Gather preflight result. Returns safe JSON dict."""
    overview = _load_overview()
    next_info = _load_next()
    readiness_level = _determine_readiness_level(overview)
    blocks = _build_blocks(overview)
    overall = overview.get("overall", {})

    return {
        "ok": True,
        "mode": "production_preflight_v2_5",
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "readiness_level": readiness_level,
        "overview_status": overall.get("status", "unknown"),
        "next_step": next_info.get("next_step", overall.get("next_step", "unknown")),
        "recommended_command": next_info.get("recommended_command", overall.get("recommended_command", "")),
        "blocks": blocks,
        "safety": "read_only",
    }


# ── Deploy plan ──────────────────────────────────────────────────────────────

def _build_deploy_cards():
    """Build the deployment command cards.

    Three categories:
    A. Read-only review commands
    B. Dangerous exact-gate commands (manual_only)
    C. Interactive legacy commands (manual_only)
    """
    cards = []

    # A. Read-only review
    review_commands = [
        ("overview", "生产部署总览", "nanobk setup production overview"),
        ("next_step", "推荐下一步", "nanobk setup production next"),
        ("dns_readiness", "DNS 准备检查", "nanobk setup production dns"),
        ("worker_readiness", "Worker 准备检查", "nanobk setup production worker"),
        ("cert_readiness", "证书准备检查", "nanobk setup production cert"),
        ("rotation_readiness", "密钥轮换预案", "nanobk setup production rotate"),
    ]
    for cid, title, cmd in review_commands:
        cards.append({
            "id": cid,
            "title": title,
            "kind": "read_only",
            "command_display": cmd,
            "will_modify": False,
            "requires_exact_phrase": False,
            "exact_phrase_label": None,
            "manual_only": False,
        })

    # B. Dangerous exact gates
    cards.append({
        "id": "dns_apply",
        "title": "域名指向",
        "kind": "dangerous_exact_gate",
        "command_display": f'nanobk setup dns apply --apply --confirm "{EXACT_PHRASE_DNS}"',
        "will_modify": True,
        "requires_exact_phrase": True,
        "exact_phrase_label": EXACT_PHRASE_DNS,
        "manual_only": True,
    })
    cards.append({
        "id": "cert_issue",
        "title": "HTTPS 安全证书",
        "kind": "dangerous_exact_gate",
        "command_display": f'nanobk setup cert issue --issue --confirm "{EXACT_PHRASE_CERT}"',
        "will_modify": True,
        "requires_exact_phrase": True,
        "exact_phrase_label": EXACT_PHRASE_CERT,
        "manual_only": True,
    })
    cards.append({
        "id": "token_rotate",
        "title": "订阅密钥",
        "kind": "dangerous_exact_gate",
        "command_display": f'nanobk setup token rotate --rotate --confirm "{EXACT_PHRASE_TOKEN}"',
        "will_modify": True,
        "requires_exact_phrase": True,
        "exact_phrase_label": EXACT_PHRASE_TOKEN,
        "manual_only": True,
    })

    # C. Interactive legacy
    cards.append({
        "id": "vps_install",
        "title": "VPS 四协议",
        "kind": "interactive_manual",
        "command_display": "nanobk install --mode vps",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "manual_only": True,
    })
    cards.append({
        "id": "worker_install",
        "title": "Worker 订阅入口",
        "kind": "interactive_manual",
        "command_display": "nanobk install --mode cloudflare",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "manual_only": True,
    })
    cards.append({
        "id": "protocol_rotate",
        "title": "协议密钥轮换",
        "kind": "interactive_manual",
        "command_display": "nanobk rotate all",
        "will_modify": True,
        "requires_exact_phrase": False,
        "exact_phrase_label": None,
        "manual_only": True,
    })

    return cards


def gather_deploy_plan():
    """Gather deploy plan. Returns safe JSON dict."""
    cards = _build_deploy_cards()
    return {
        "ok": True,
        "mode": "production_deploy_plan_v2_5",
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "execute_policy": "manual_only",
        "cards": cards,
        "safety": "read_only",
    }


# ── Gates ────────────────────────────────────────────────────────────────────

def gather_gates():
    """Gather the three exact-gate summaries. Returns safe JSON dict."""
    return {
        "ok": True,
        "mode": "production_gates_v2_5",
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "gates": {
            "dns": {
                "exact_phrase": EXACT_PHRASE_DNS,
                "command_display": f'nanobk setup dns apply --apply --confirm "{EXACT_PHRASE_DNS}"',
            },
            "cert": {
                "exact_phrase": EXACT_PHRASE_CERT,
                "command_display": f'nanobk setup cert issue --issue --confirm "{EXACT_PHRASE_CERT}"',
            },
            "token": {
                "exact_phrase": EXACT_PHRASE_TOKEN,
                "command_display": f'nanobk setup token rotate --rotate --confirm "{EXACT_PHRASE_TOKEN}"',
            },
        },
        "safety": "read_only",
    }


# ── Text renderers ───────────────────────────────────────────────────────────

_READINESS_LABELS = {
    "ready": "已准备",
    "ready_for_manual_execution": "已准备（需手动执行）",
    "partial": "部分准备",
    "blocked": "需要处理",
    "needs_input": "需要输入",
    "needs_tools": "缺少工具",
    "needs_token": "需要设置密钥",
    "unknown": "未知",
}


def output_preflight_text(result):
    """Render preflight result as Chinese text."""
    lines = []
    lines.append("")
    lines.append("  NanoBK 真实部署前检查")
    lines.append("  ─────────────────────────────────────────────")
    lines.append("")
    lines.append("  当前不会执行任何真实修改。")
    lines.append("")

    level = result.get("readiness_level", "unknown")
    level_label = _READINESS_LABELS.get(level, level)
    lines.append("  总体状态:")
    lines.append(f"    {level_label}")
    lines.append("")

    blocks = result.get("blocks", [])
    if blocks:
        lines.append("  检查结果:")
        for block in blocks:
            label = {
                "dns": "DNS",
                "worker": "Worker",
                "cert": "HTTPS 证书",
                "rotation": "订阅密钥与代理密钥",
            }.get(block["id"], block["id"])
            status_label = _READINESS_LABELS.get(block.get("status", "unknown"), block.get("status", "unknown"))
            lines.append(f"    {label}: {status_label}")
        lines.append("")

    cmd = result.get("recommended_command", "")
    if cmd:
        lines.append("  推荐下一步:")
        lines.append(f"    {cmd}")
        lines.append("")

    return "\n".join(lines)


def output_deploy_plan_text(result):
    """Render deploy plan as Chinese text."""
    lines = []
    lines.append("")
    lines.append("  NanoBK 真实部署命令清单")
    lines.append("  ─────────────────────────────────────────────")
    lines.append("")
    lines.append("  当前只显示命令，不会执行。")
    lines.append("")

    cards = result.get("cards", [])

    # Separate by kind
    dangerous = [c for c in cards if c["kind"] == "dangerous_exact_gate"]
    interactive = [c for c in cards if c["kind"] == "interactive_manual"]
    readonly = [c for c in cards if c["kind"] == "read_only"]

    if dangerous:
        lines.append("  危险操作需要你手动确认：")
        lines.append("")
        for i, card in enumerate(dangerous, 1):
            lines.append(f"  {i}. {card['title']}")
            lines.append(f"     命令:")
            lines.append(f"     {card['command_display']}")
            if card.get("will_modify"):
                lines.append(f"     说明: 会修改系统或 Cloudflare 配置。")
            lines.append("")

    if interactive:
        offset = len(dangerous)
        lines.append("  交互部署：")
        lines.append("")
        for i, card in enumerate(interactive, offset + 1):
            lines.append(f"  {i}. {card['title']}")
            lines.append(f"     {card['command_display']}")
        lines.append("")

    lines.append("  安全说明:")
    lines.append("    这些命令不会自动执行。")
    lines.append("    你需要自己复制并确认。")
    lines.append("")

    return "\n".join(lines)


def output_gates_text(result):
    """Render gates summary as Chinese text."""
    lines = []
    lines.append("")
    lines.append("  NanoBK 安全确认短语")
    lines.append("  ─────────────────────────────────────────────")
    lines.append("")

    gates = result.get("gates", {})
    for key, label in [("dns", "DNS"), ("cert", "Cert"), ("token", "Token")]:
        gate = gates.get(key, {})
        lines.append(f"  {label}:")
        lines.append(f"    {gate.get('exact_phrase', 'N/A')}")
        lines.append("")

    return "\n".join(lines)


# ── CLI ──────────────────────────────────────────────────────────────────────

def _reject_dangerous(args_list):
    """Check for dangerous args and return error message if found."""
    for arg in args_list:
        if arg in _DANGEROUS_ARGS:
            return f"选项 {arg} 不支持。此命令仅用于预览，不会执行真实修改。"
    return None


def main():
    # Pre-check dangerous args before argparse
    error_msg = _reject_dangerous(sys.argv[1:])
    if error_msg:
        # Check if --json was also passed
        use_json = "--json" in sys.argv
        if use_json:
            print(json.dumps({
                "ok": False,
                "error": error_msg,
                "mode": "production_preflight_v2_5",
                "version": VERSION,
                "mutation": False,
            }, indent=2, ensure_ascii=False))
        else:
            print(f"  错误：{error_msg}", file=sys.stderr)
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="NanoBK Production Preflight and Controlled Gate Wrapper"
    )
    sub = parser.add_subparsers(dest="command")

    preflight_parser = sub.add_parser("preflight", help="Run preflight check")
    preflight_parser.add_argument("--json", action="store_true", help="JSON output")

    deploy_parser = sub.add_parser("deploy-plan", help="Show deployment plan")
    deploy_parser.add_argument("--json", action="store_true", help="JSON output")

    gates_parser = sub.add_parser("gates", help="Show exact-gate phrases")
    gates_parser.add_argument("--json", action="store_true", help="JSON output")

    # Accept --json at top level too
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()
    command = args.command or "preflight"
    use_json = getattr(args, "json", False)

    if command == "preflight":
        result = gather_preflight()
        if use_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(output_preflight_text(result))
    elif command == "deploy-plan":
        result = gather_deploy_plan()
        if use_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(output_deploy_plan_text(result))
    elif command == "gates":
        result = gather_gates()
        if use_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(output_gates_text(result))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
