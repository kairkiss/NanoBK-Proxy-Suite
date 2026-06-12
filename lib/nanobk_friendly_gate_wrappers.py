#!/usr/bin/env python3
"""
NanoBK Friendly Gate Wrappers (v2.4.5)

Preview-only beginner-friendly wrappers for v2.3 gate commands.
Shows what each gate will do, why it's dangerous, and what confirmation is needed.

Read-only. No DNS mutation. No Cloudflare mutation.
No curl/wrangler/certbot calls. No service reload/restart.
No subprocess. No requests. No urlopen.

Usage:
    python3 lib/nanobk_friendly_gate_wrappers.py dns [--json]
    python3 lib/nanobk_friendly_gate_wrappers.py cert [--json]
    python3 lib/nanobk_friendly_gate_wrappers.py token [--json]
"""

import argparse
import json
import sys


# ── Exact confirmation phrases (from v2.3 gates) ──────────────────────────

DNS_CONFIRM_PHRASE = "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"
CERT_CONFIRM_PHRASE = "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"
TOKEN_CONFIRM_PHRASE = "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"


# ── Gate preview data ─────────────────────────────────────────────────────

_GATE_DATA = {
    "dns": {
        "gate": "dns",
        "title": "DNS 域名指向",
        "will_do": [
            "将把 proxy 和 web 子域名指向你的 VPS 服务器",
            "这会在 Cloudflare 中创建 A 或 AAAA DNS 记录",
            "创建后，你的域名将指向服务器 IP 地址",
        ],
        "why_dangerous": [
            "如果填错了 IP 地址，你的域名将无法正常访问",
            "这会修改 Cloudflare DNS 配置",
            "如果已有同名记录，可能会被覆盖",
        ],
        "exact_phrase_label": DNS_CONFIRM_PHRASE,
        "next_step": "请使用 v2.3 原始 gate 命令，并手动输入完整确认短语：\n  nanobk setup dns apply",
    },
    "cert": {
        "gate": "cert",
        "title": "HTTPS 安全证书",
        "will_do": [
            "将为你的域名申请 HTTPS 安全证书",
            "这会访问证书签发流程（如 Let's Encrypt）",
            "申请成功后，你的网站将支持 HTTPS 加密访问",
        ],
        "why_dangerous": [
            "证书申请可能需要 DNS 验证",
            "如果域名指向不正确，证书申请会失败",
            "频繁申请可能触发签发机构的速率限制",
        ],
        "exact_phrase_label": CERT_CONFIRM_PHRASE,
        "next_step": "请使用 v2.3 原始 gate 命令，并手动输入完整确认短语：\n  nanobk setup cert issue",
    },
    "token": {
        "gate": "token",
        "title": "订阅密钥",
        "will_do": [
            "将重新生成订阅密钥",
            "旧的订阅链接可能会失效",
            "生成后需要重新导出订阅链接",
        ],
        "why_dangerous": [
            "旧订阅链接将无法使用",
            "所有使用旧密钥的客户端都需要更新",
            "如果不及时更新，可能导致服务中断",
        ],
        "exact_phrase_label": TOKEN_CONFIRM_PHRASE,
        "next_step": "请使用 v2.3 原始 gate 命令，并手动输入完整确认短语：\n  nanobk setup token rotate",
    },
}

# Forbidden options that must be rejected
_FORBIDDEN_OPTIONS = {
    "dns": {"--apply", "--yes", "--confirm"},
    "cert": {"--issue", "--yes", "--confirm"},
    "token": {"--rotate", "--yes", "--confirm"},
}


# ── Core logic ─────────────────────────────────────────────────────────────

def get_gate_preview(gate):
    """Get preview data for a gate.

    Args:
        gate: "dns", "cert", or "token"

    Returns:
        Safe preview dict with no secrets.
    """
    if gate not in _GATE_DATA:
        return {
            "ok": False,
            "error": f"未知的 gate: {gate}",
            "safety": "preview_only",
        }

    data = _GATE_DATA[gate]
    return {
        "ok": True,
        "gate": data["gate"],
        "title": data["title"],
        "will_do": data["will_do"],
        "why_dangerous": data["why_dangerous"],
        "confirmation_required": True,
        "exact_phrase_label": data["exact_phrase_label"],
        "next_step": data["next_step"],
        "safety": "preview_only",
    }


def check_forbidden_options(gate, argv):
    """Check if any forbidden options are present.

    Args:
        gate: "dns", "cert", or "token"
        argv: list of command-line arguments

    Returns:
        (is_forbidden, message) tuple
    """
    forbidden = _FORBIDDEN_OPTIONS.get(gate, set())
    for arg in argv:
        if arg in forbidden:
            return True, f"这是预览命令，不会执行危险操作。请使用 v2.3 原始 gate 命令，并手动输入完整确认短语。"
    return False, ""


# ── Text renderer ──────────────────────────────────────────────────────────

def render_gate_text(preview):
    """Render gate preview as beginner-friendly Chinese text."""
    lines = []

    if not preview.get("ok"):
        lines.append(f"  错误：{preview.get('error', '未知错误')}")
        return "\n".join(lines)

    title = preview["title"]
    will_do = preview["will_do"]
    why_dangerous = preview["why_dangerous"]
    exact_phrase = preview["exact_phrase_label"]
    next_step = preview["next_step"]

    lines.append("")
    lines.append(f"  ┌─ {title} 预览 ──────────────────────────────────┐")
    lines.append("  │")
    lines.append("  │ 将要做什么：")
    for item in will_do:
        lines.append(f"  │   • {item}")
    lines.append("  │")
    lines.append("  │ 为什么需要确认：")
    for item in why_dangerous:
        lines.append(f"  │   • {item}")
    lines.append("  │")
    lines.append("  │ 不确认就不会执行任何操作。")
    lines.append("  │")
    lines.append(f"  │ 确认短语：")
    lines.append(f"  │   {exact_phrase}")
    lines.append("  │")
    lines.append("  │ 下一步：")
    for step_line in next_step.split("\n"):
        lines.append(f"  │   {step_line}")
    lines.append("  │")
    lines.append("  └──────────────────────────────────────────────┘")
    lines.append("")

    return "\n".join(lines)


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Friendly Gate Wrappers (preview only)"
    )
    sub = parser.add_subparsers(dest="gate")

    # dns subcommand
    dns_parser = sub.add_parser("dns", help="DNS gate preview")
    dns_parser.add_argument("--json", action="store_true", help="JSON output")
    # Accept but reject forbidden options
    dns_parser.add_argument("--apply", action="store_true", help=argparse.SUPPRESS)
    dns_parser.add_argument("--yes", action="store_true", help=argparse.SUPPRESS)
    dns_parser.add_argument("--confirm", help=argparse.SUPPRESS)

    # cert subcommand
    cert_parser = sub.add_parser("cert", help="Cert gate preview")
    cert_parser.add_argument("--json", action="store_true", help="JSON output")
    cert_parser.add_argument("--issue", action="store_true", help=argparse.SUPPRESS)
    cert_parser.add_argument("--yes", action="store_true", help=argparse.SUPPRESS)
    cert_parser.add_argument("--confirm", help=argparse.SUPPRESS)

    # token subcommand
    token_parser = sub.add_parser("token", help="Token gate preview")
    token_parser.add_argument("--json", action="store_true", help="JSON output")
    token_parser.add_argument("--rotate", action="store_true", help=argparse.SUPPRESS)
    token_parser.add_argument("--yes", action="store_true", help=argparse.SUPPRESS)
    token_parser.add_argument("--confirm", help=argparse.SUPPRESS)

    args = parser.parse_args()

    if not args.gate:
        parser.print_help()
        sys.exit(1)

    gate = args.gate
    use_json = getattr(args, "json", False)

    # Check for forbidden options
    if gate == "dns" and (args.apply or args.yes or args.confirm):
        print("这是预览命令，不会执行危险操作。", file=sys.stderr)
        print("请使用 v2.3 原始 gate 命令，并手动输入完整确认短语。", file=sys.stderr)
        sys.exit(1)
    elif gate == "cert" and (args.issue or args.yes or args.confirm):
        print("这是预览命令，不会执行危险操作。", file=sys.stderr)
        print("请使用 v2.3 原始 gate 命令，并手动输入完整确认短语。", file=sys.stderr)
        sys.exit(1)
    elif gate == "token" and (args.rotate or args.yes or args.confirm):
        print("这是预览命令，不会执行危险操作。", file=sys.stderr)
        print("请使用 v2.3 原始 gate 命令，并手动输入完整确认短语。", file=sys.stderr)
        sys.exit(1)

    preview = get_gate_preview(gate)

    if use_json:
        print(json.dumps(preview, indent=2, ensure_ascii=False))
    else:
        print(render_gate_text(preview))


if __name__ == "__main__":
    main()
