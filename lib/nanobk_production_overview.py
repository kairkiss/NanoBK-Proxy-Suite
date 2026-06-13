#!/usr/bin/env python3
"""
NanoBK Production Overview and Next-Step Navigator (v2.5.6)

Read-only production overview that aggregates all four readiness flows
(DNS, Worker, Cert, Rotation) and provides prioritized next-step recommendations.

Read-only. No DNS mutation. No Cloudflare mutation.
No curl/wrangler/certbot calls. No service reload/restart.
No installer execution. No certificate request. No token rotation.

Usage:
    python3 lib/nanobk_production_overview.py overview [--json]
    python3 lib/nanobk_production_overview.py next [--json]

Test hooks:
    NANOBK_PRODUCTION_OVERVIEW_FAKE_DNS_JSON=/path/to/dns.json
    NANOBK_PRODUCTION_OVERVIEW_FAKE_WORKER_JSON=/path/to/worker.json
    NANOBK_PRODUCTION_OVERVIEW_FAKE_CERT_JSON=/path/to/cert.json
    NANOBK_PRODUCTION_OVERVIEW_FAKE_ROTATION_JSON=/path/to/rotation.json
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

VERSION = "2.5.6"


# -- Safe readiness loaders ---------------------------------------------------

def _load_fake_or_real(env_key, module_name, func_name, **kwargs):
    """Load readiness from fake JSON file or by calling the real module.

    Returns a dict with at least 'ok', 'next_step', 'blocked' keys.
    On any failure, returns a safe unknown status.
    """
    fake_path = os.environ.get(env_key)
    if fake_path and os.path.isfile(fake_path):
        try:
            with open(fake_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass

    try:
        mod = __import__(module_name)
        func = getattr(mod, func_name)
        return func(**kwargs)
    except Exception:
        return {
            "ok": True,
            "blocked": True,
            "next_step": "unknown",
            "safety": "read_only",
        }


def _load_dns_readiness():
    return _load_fake_or_real(
        "NANOBK_PRODUCTION_OVERVIEW_FAKE_DNS_JSON",
        "nanobk_production_dns_readiness",
        "run_readiness",
    )


def _load_worker_readiness():
    return _load_fake_or_real(
        "NANOBK_PRODUCTION_OVERVIEW_FAKE_WORKER_JSON",
        "nanobk_production_worker_readiness",
        "run_readiness",
    )


def _load_cert_readiness():
    return _load_fake_or_real(
        "NANOBK_PRODUCTION_OVERVIEW_FAKE_CERT_JSON",
        "nanobk_production_cert_readiness",
        "run_readiness",
    )


def _load_rotation_readiness():
    return _load_fake_or_real(
        "NANOBK_PRODUCTION_OVERVIEW_FAKE_ROTATION_JSON",
        "nanobk_production_rotation_readiness",
        "run_readiness",
    )


# -- Section summarizers ------------------------------------------------------

def _summarize_dns(result):
    """Summarize DNS readiness into a compact section dict."""
    if not result or not result.get("ok"):
        return {"status": "unknown", "next_step": "production_dns", "blocked": True}

    blocked = result.get("blocked", False)
    next_step_raw = result.get("next_step", "")

    # Map DNS next_steps to our section status
    if next_step_raw in ("connect_cloudflare", "select_zone", "select_domain",
                         "manual_ip_input", "custom_subdomain"):
        return {"status": "needs_input", "next_step": next_step_raw, "blocked": True}
    elif blocked:
        return {"status": "blocked", "next_step": next_step_raw, "blocked": True}
    else:
        return {"status": "ready", "next_step": next_step_raw, "blocked": False}


def _summarize_worker(result):
    """Summarize Worker readiness into a compact section dict."""
    if not result or not result.get("ok"):
        return {"status": "unknown", "next_step": "production_worker", "blocked": True}

    blocked = result.get("blocked", False)
    next_step_raw = result.get("next_step", "")

    if next_step_raw in ("select_domain",):
        return {"status": "blocked", "next_step": next_step_raw, "blocked": True}
    elif next_step_raw in ("install_tools",):
        return {"status": "needs_tools", "next_step": next_step_raw, "blocked": True}
    elif blocked:
        return {"status": "blocked", "next_step": next_step_raw, "blocked": True}
    else:
        return {"status": "ready", "next_step": next_step_raw, "blocked": False}


def _summarize_cert(result):
    """Summarize Cert readiness into a compact section dict."""
    if not result or not result.get("ok"):
        return {"status": "unknown", "next_step": "production_cert", "blocked": True}

    blocked = result.get("blocked", False)
    next_step_raw = result.get("next_step", "")

    if next_step_raw in ("select_domain",):
        return {"status": "blocked", "next_step": next_step_raw, "blocked": True}
    elif next_step_raw in ("select_cert_mode", "configure_existing_cert"):
        return {"status": "needs_input", "next_step": next_step_raw, "blocked": True}
    elif blocked:
        return {"status": "blocked", "next_step": next_step_raw, "blocked": True}
    else:
        return {"status": "ready", "next_step": next_step_raw, "blocked": False}


def _summarize_rotation(result):
    """Summarize Rotation readiness into a compact section dict."""
    if not result or not result.get("ok"):
        return {"status": "unknown", "next_step": "production_rotate", "blocked": True}

    blocked = result.get("blocked", False)
    next_step_raw = result.get("next_step", "")

    if next_step_raw in ("choose_token_rotation",):
        return {"status": "needs_token", "next_step": next_step_raw, "blocked": True}
    elif blocked:
        return {"status": "blocked", "next_step": next_step_raw, "blocked": True}
    elif next_step_raw in ("review_token_gate",):
        # Token is auto-generated or custom — ready for gate review
        return {"status": "ready", "next_step": next_step_raw, "blocked": False}
    else:
        return {"status": "ready", "next_step": next_step_raw, "blocked": False}


# -- Priority logic -----------------------------------------------------------

def _determine_overall_next(sections):
    """Determine the overall next step based on priority order.

    Priority:
    1. DNS readiness (connect_cloudflare, select_zone, select_domain, manual_ip_input, custom_subdomain)
    2. Worker readiness (blocked)
    3. Cert readiness (needs mode/domain)
    4. Rotation readiness (needs token)
    5. All ready -> review_real_deploy
    """
    dns = sections.get("dns", {})
    worker = sections.get("worker", {})
    cert = sections.get("cert", {})
    rotation = sections.get("rotation", {})

    # Priority 1: DNS
    dns_next = dns.get("next_step", "")
    if dns_next in ("connect_cloudflare", "select_zone", "select_domain",
                     "manual_ip_input", "custom_subdomain") or dns.get("blocked"):
        return {
            "status": "incomplete",
            "next_step": "production_dns",
            "recommended_command": "nanobk setup production dns",
            "reason": "还没有完成 Cloudflare / 域名 / DNS 准备。",
        }

    # Priority 2: Worker
    if worker.get("blocked"):
        return {
            "status": "incomplete",
            "next_step": "production_worker",
            "recommended_command": "nanobk setup production worker",
            "reason": "Worker 订阅入口尚未准备就绪。",
        }

    # Priority 3: Cert
    if cert.get("blocked") or cert.get("status") in ("needs_input", "blocked", "unknown"):
        cert_next = cert.get("next_step", "")
        if cert_next in ("select_cert_mode", "configure_existing_cert", "select_domain"):
            return {
                "status": "incomplete",
                "next_step": "production_cert",
                "recommended_command": "nanobk setup production cert",
                "reason": "HTTPS 证书尚未配置。",
            }

    # Priority 4: Rotation
    if rotation.get("blocked") or rotation.get("status") in ("needs_token", "blocked", "unknown"):
        return {
            "status": "incomplete",
            "next_step": "production_rotate",
            "recommended_command": "nanobk setup production rotate",
            "reason": "建议先设置订阅密钥，再轮换协议密钥。",
        }

    # All ready
    return {
        "status": "ready",
        "next_step": "review_real_deploy",
        "recommended_command": "nanobk setup production actions",
        "reason": "所有准备工作已完成。准备进入真实部署前，请先逐项确认 DNS / Worker / 证书 / 订阅密钥。",
    }


# -- Main entry points --------------------------------------------------------

def gather_overview():
    """Gather full production overview. Returns safe JSON dict."""
    dns_result = _load_dns_readiness()
    worker_result = _load_worker_readiness()
    cert_result = _load_cert_readiness()
    rotation_result = _load_rotation_readiness()

    sections = {
        "dns": _summarize_dns(dns_result),
        "worker": _summarize_worker(worker_result),
        "cert": _summarize_cert(cert_result),
        "rotation": _summarize_rotation(rotation_result),
    }

    overall = _determine_overall_next(sections)

    return {
        "ok": True,
        "mode": "production_overview_v2_5",
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "sections": sections,
        "overall": overall,
        "safety": "read_only",
    }


def gather_next():
    """Gather next-step recommendation. Returns safe JSON dict."""
    overview = gather_overview()
    overall = overview.get("overall", {})

    return {
        "ok": True,
        "mode": "production_next_step_v2_5",
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "next_step": overall.get("next_step", "unknown"),
        "recommended_command": overall.get("recommended_command", ""),
        "reason": overall.get("reason", ""),
        "safety": "read_only",
    }


# -- Text renderers -----------------------------------------------------------

_SECTION_LABELS = {
    "dns": "域名与 DNS",
    "worker": "Worker 订阅入口",
    "cert": "HTTPS 安全证书",
    "rotation": "订阅密钥与代理密钥",
}

_STATUS_TEXT = {
    "ready": "已完成",
    "needs_input": "需要确认",
    "blocked": "等待前置条件",
    "needs_tools": "缺少工具",
    "needs_token": "建议先设置订阅密钥",
    "unknown": "未知",
}

_NEXT_COMMANDS = {
    "production_dns": "nanobk setup production dns",
    "production_worker": "nanobk setup production worker",
    "production_cert": "nanobk setup production cert",
    "production_rotate": "nanobk setup production rotate",
    "review_real_deploy": "nanobk setup production actions",
    "connect_cloudflare": "nanobk cf connect",
    "select_zone": "nanobk setup production dns",
    "select_domain": "nanobk setup production dns",
    "manual_ip_input": "nanobk setup production dns",
    "custom_subdomain": "nanobk setup production dns",
    "select_cert_mode": "nanobk setup production cert",
    "configure_existing_cert": "nanobk setup production cert",
    "choose_token_rotation": "nanobk setup production rotate",
    "install_tools": "nanobk setup production worker",
}


def output_overview_text(result):
    """Render production overview as Chinese text."""
    lines = []
    lines.append("")
    lines.append("  NanoBK 生产部署总览")
    lines.append("  ─────────────────────────────────────────────")
    lines.append("")
    lines.append("  当前不会执行任何真实修改。")
    lines.append("")

    sections = result.get("sections", {})
    overall = result.get("overall", {})

    section_order = ["dns", "worker", "cert", "rotation"]
    for i, key in enumerate(section_order, 1):
        section = sections.get(key, {})
        label = _SECTION_LABELS.get(key, key)
        status = _STATUS_TEXT.get(section.get("status", "unknown"), section.get("status", "unknown"))
        next_raw = section.get("next_step", "")
        cmd = _NEXT_COMMANDS.get(next_raw, "nanobk setup production")

        lines.append(f"  {i}. {label}")
        lines.append(f"     状态：{status}")
        lines.append(f"     下一步：{cmd}")
        lines.append("")

    lines.append("  推荐下一步：")
    lines.append(f"    {overall.get('recommended_command', 'nanobk setup production')}")
    lines.append("")
    lines.append(f"  原因：{overall.get('reason', '')}")
    lines.append("")
    lines.append("  安全说明：")
    lines.append("    这个命令只会检查和生成计划，不会执行任何真实修改。")
    lines.append("")
    return "\n".join(lines)


def output_next_text(result):
    """Render next-step recommendation as Chinese text."""
    lines = []
    lines.append("")
    lines.append("  NanoBK 下一步")
    lines.append("  ─────────────────────────────────────────────")
    lines.append("")
    lines.append("  建议现在执行：")
    lines.append(f"    {result.get('recommended_command', 'nanobk setup production')}")
    lines.append("")
    lines.append(f"  原因：")
    lines.append(f"    {result.get('reason', '')}")
    lines.append("")
    lines.append("  安全说明：")
    lines.append("    这个命令只会检查和生成计划，不会创建 DNS。")
    lines.append("")
    return "\n".join(lines)


# -- CLI main -----------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Production Overview and Next-Step Navigator"
    )
    sub = parser.add_subparsers(dest="command")

    overview_parser = sub.add_parser("overview", help="Show production overview")
    overview_parser.add_argument("--json", action="store_true", help="JSON output")

    next_parser = sub.add_parser("next", help="Show next recommended step")
    next_parser.add_argument("--json", action="store_true", help="JSON output")

    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()
    command = args.command or "overview"
    use_json = getattr(args, "json", False)

    if command == "overview":
        result = gather_overview()
        if use_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(output_overview_text(result))
    elif command == "next":
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
