#!/usr/bin/env python3
"""
NanoBK Production Worker Deploy (v2.6.3)

Productized, exact-gated Worker deploy wrapper for nanok/nanob production
entrypoints. Dry-run is read-only. Automated tests use fake deploy hooks only.
Real Worker deployment is guarded and intentionally not attempted unless a safe
deploy adapter is connected behind the explicit guard.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cloudflare_product_setup import detect_cloudflare_connection
from nanobk_domain_selection import load_selected_domain
from nanobk_production_worker_readiness import check_tools, check_worker_sources
from nanobk_setup_profile import load_profile


VERSION = "2.6.3"
MODE = "production_worker_deploy_v2_6"
EXACT_PHRASE_WORKER = "I UNDERSTAND NANOBK WILL DEPLOY CLOUDFLARE WORKERS"

BLOCKED_ARGS = {
    "--yes",
    "--force",
    "--overwrite",
    "--delete",
    "--update",
}


def _refusal(message, next_step, dry_run=False):
    return {
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


def _safe_domain():
    fake = os.environ.get("NANOBK_FAKE_SELECTED_DOMAIN", "").strip().lower().rstrip(".")
    if fake:
        return fake

    selected, _err = load_selected_domain()
    if selected and selected.get("selected_domain"):
        return selected.get("selected_domain")

    profile, err = load_profile()
    if not err and profile and profile.get("zone_name"):
        return profile.get("zone_name")

    return None


def _cloudflare_connected():
    fake = os.environ.get("NANOBK_FAKE_CF_CONNECTED")
    if fake == "1":
        return True
    if fake == "0":
        return False
    return bool(detect_cloudflare_connection().get("connected"))


def _worker_source_ready():
    fake = os.environ.get("NANOBK_FAKE_WORKER_SOURCE")
    if fake == "1":
        return True
    if fake == "0":
        return False

    sources = check_worker_sources()
    return sources.get("nanok") == "ready" and sources.get("nanob") == "ready"


def _deploy_tool_ready():
    fake = os.environ.get("NANOBK_FAKE_WRANGLER")
    if fake == "1":
        return True
    if fake == "0":
        return False

    tools = check_tools()
    return tools.get("wrangler") == "present"


def _planned_entrypoints(domain):
    return [
        {"name": f"nanok.{domain}", "kind": "worker_route"},
        {"name": f"nanob.{domain}", "kind": "worker_route"},
    ]


def build_plan(dry_run=True):
    domain = _safe_domain()
    if not domain:
        return _refusal("还没有选择你的域名，请先运行 nanobk setup domain", "select_domain", dry_run)

    if not _cloudflare_connected():
        return _refusal("还没有连接 Cloudflare，请先运行 nanobk setup cloudflare", "setup_cloudflare", dry_run)

    if not _worker_source_ready():
        return _refusal("没有找到订阅服务入口源码，请先确认 Worker 源码完整", "install_worker_sources", dry_run)

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "dry_run": bool(dry_run),
        "mutation": False,
        "dangerous_actions_executed": False,
        "selected_domain": domain,
        "planned_entrypoints": _planned_entrypoints(domain),
        "blocked": False,
        "next_step": "confirm_worker_deploy" if dry_run else "deploy_worker",
        "safety": "read_only",
    }


def deploy_worker(confirm_phrase):
    if confirm_phrase != EXACT_PHRASE_WORKER:
        return _refusal("需要完整输入安全确认短语。", "confirm_worker_deploy", False)

    plan = build_plan(dry_run=False)
    if not plan.get("ok"):
        return plan

    if not _deploy_tool_ready():
        return _refusal("没有检测到发布订阅服务入口所需工具，请先安装 Wrangler。", "install_worker_tools", False)

    if os.environ.get("NANOBK_FAKE_WORKER_DEPLOY") == "1":
        domain = plan["selected_domain"]
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": True,
            "dangerous_actions_executed": True,
            "confirmed": True,
            "deployed_entrypoints": _planned_entrypoints(domain),
            "blocked": False,
            "next_step": "setup_cert",
            "safety": "confirmed_worker_deploy",
        }

    if os.environ.get("NANOBK_ALLOW_REAL_WORKER_DEPLOY") != "1":
        return _refusal(
            "真实发布订阅服务入口需要先设置 NANOBK_ALLOW_REAL_WORKER_DEPLOY=1。",
            "confirm_worker_deploy",
            False,
        )

    return _refusal(
        "真实发布订阅服务入口的受控执行器尚未接入；当前不会发布 Worker。",
        "connect_worker_deploy_adapter",
        False,
    )


def public_result(result):
    cleaned = {}
    for key, value in result.items():
        if key.startswith("_"):
            continue
        cleaned[key] = value
    return cleaned


def output_text(result):
    result = public_result(result)
    lines = [""]

    if result.get("ok") and result.get("dry_run"):
        lines.extend([
            "  NanoBK 订阅服务入口检查",
            "  ─────────────────────────────────────────────",
            "",
            "  当前不会发布订阅服务入口。",
            "",
            "  我将准备：",
            "",
        ])
        for item in result.get("planned_entrypoints", []):
            lines.append(f"  {item['name']} -> 入口域名")
        lines.extend([
            "",
            "  如果确认无误，再运行：",
            f'  nanobk setup production worker deploy --confirm "{EXACT_PHRASE_WORKER}"',
            "",
        ])
        return "\n".join(lines)

    if result.get("ok") and not result.get("dry_run"):
        lines.extend([
            "  NanoBK 订阅服务入口",
            "  ─────────────────────────────────────────────",
            "",
            "  已通过安全确认。",
            "  正在发布订阅服务入口……",
            "",
            "  完成：",
        ])
        for item in result.get("deployed_entrypoints", []):
            lines.append(f"  {item['name']}")
        lines.extend([
            "",
            "  下一步：",
            "  nanobk setup production cert",
            "",
        ])
        return "\n".join(lines)

    lines.extend([
        "  NanoBK 订阅服务入口",
        "  ─────────────────────────────────────────────",
        "",
        f"  暂时不能继续：{result.get('error', '未知原因')}",
    ])
    next_step = result.get("next_step")
    if next_step == "select_domain":
        lines.append("  请先运行：nanobk setup domain")
    elif next_step == "setup_cloudflare":
        lines.append("  请先运行：nanobk setup cloudflare")
    elif next_step == "install_worker_sources":
        lines.append("  请先确认 nanok/nanob Worker 源码完整。")
    elif next_step == "install_worker_tools":
        lines.append("  请先安装 Wrangler 后再发布订阅服务入口。")
    elif next_step == "confirm_worker_deploy":
        lines.append(f'  请使用：--confirm "{EXACT_PHRASE_WORKER}"')
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
        result = _refusal(f"{blocked} 不适用于这个受控命令。", "confirm_worker_deploy", "--dry-run" in argv)
        if json_requested:
            print(json.dumps(public_result(result), indent=2, ensure_ascii=False))
        else:
            print(output_text(result), file=sys.stderr)
        return 1

    parser = argparse.ArgumentParser(description="NanoBK production Worker deploy")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--dry-run", action="store_true", help="Show plan only")
    parser.add_argument("--confirm", help="Exact safety confirmation phrase")
    args = parser.parse_args(argv)

    if args.dry_run:
        result = build_plan(dry_run=True)
    else:
        result = deploy_worker(args.confirm)

    if args.json:
        print(json.dumps(public_result(result), indent=2, ensure_ascii=False))
    else:
        stream = sys.stdout if result.get("ok") else sys.stderr
        print(output_text(result), file=stream)

    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
