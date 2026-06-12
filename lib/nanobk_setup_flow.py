#!/usr/bin/env python3
"""
NanoBK Full CLI Setup Flow

Read-only orchestration across all setup stages:
1. Cloudflare connect / zone selection
2. Domain planning (proxy/web subdomains)
3. DNS apply plan
4. DNS apply command prompt (manual confirm)
5. Certificate preflight
6. Certificate issue plan (manual confirm)
7. Token rotation plan (manual confirm)
8. Final status summary

No automatic DNS creation. No automatic certificate request.
No automatic token rotation. No Worker mutation.
Dangerous actions only shown as copy-paste commands with exact confirmation phrases.

Usage:
    python3 lib/nanobk_setup_flow.py [--zone DOMAIN] [--api-env PATH] [--worker-name NAME] [--json]

Test hooks (inherited from sub-modules):
    NANOBK_CF_ZONES_FAKE_RESPONSE
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP
    NANOBK_CERT_PREFLIGHT_FAKE_TOOLS
    NANOBK_CERT_PREFLIGHT_FAKE_PORTS
    NANOBK_TOKEN_ROTATE_FAKE_RUN
    NANOBK_TOKEN_ROTATE_FAKE_RESULT
    NANOBK_TEST_DETECTED_IPV4
    NANOBK_TEST_DETECTED_IPV6
    NANOBK_TEST_DETECT_IPV4_FAIL
    NANOBK_TEST_DETECT_IPV6_FAIL
    NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL
    NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cf_zones import parse_env_file
from nanobk_setup_profile import load_profile
from nanobk_domain_planner import run_plan
from nanobk_dns_apply_engine import run_apply_engine
from nanobk_cert_preflight import run_preflight
from nanobk_cert_issue_gate import run_issue_gate
from nanobk_token_rotation_gate import run_rotation_gate


# ── Constants ────────────────────────────────────────────────────────────────

DNS_APPLY_CONFIRM = "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"
CERT_ISSUE_CONFIRM = "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"
TOKEN_ROTATE_CONFIRM = "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"


# ── Step builders ────────────────────────────────────────────────────────────

def _step_cf_connect(profile_loaded, zone_name, api_env_path):
    """Step 1: Cloudflare connect status."""
    if profile_loaded and zone_name and api_env_path:
        return {
            "id": "cf_connect",
            "title": "连接 Cloudflare / 选择域名",
            "status": "ready",
            "detail": f"已连接，域名: {zone_name}",
            "command": "nanobk cf connect",
        }
    return {
        "id": "cf_connect",
        "title": "连接 Cloudflare / 选择域名",
        "status": "missing_input",
        "detail": "未找到 setup profile，请先连接 Cloudflare",
        "command": "nanobk cf connect",
    }


def _step_domain_plan(plan_result):
    """Step 2: Domain planning."""
    if not plan_result.get("ok"):
        return {
            "id": "domain_plan",
            "title": "规划 proxy/web 子域名",
            "status": "blocked",
            "detail": plan_result.get("error", "规划失败"),
            "command": "nanobk setup plan",
        }
    records = plan_result.get("records", [])
    available = [r for r in records if r.get("available")]
    status = "ready" if len(available) == len(records) and records else "partial"
    return {
        "id": "domain_plan",
        "title": "规划 proxy/web 子域名",
        "status": status,
        "detail": f"{len(available)}/{len(records)} 子域名可用",
        "command": "nanobk setup plan",
    }


def _step_dns_apply_plan(apply_result):
    """Step 3: DNS apply plan (read-only)."""
    if not apply_result.get("ok"):
        return {
            "id": "dns_apply_plan",
            "title": "DNS 创建预案",
            "status": "blocked",
            "detail": apply_result.get("error", "预案生成失败"),
            "command": "nanobk setup dns apply",
        }
    mode = apply_result.get("mode", "unknown")
    if mode == "plan":
        return {
            "id": "dns_apply_plan",
            "title": "DNS 创建预案",
            "status": "ready",
            "detail": "DNS 创建预案已生成",
            "command": "nanobk setup dns apply",
        }
    return {
        "id": "dns_apply_plan",
        "title": "DNS 创建预案",
        "status": "blocked",
        "detail": f"预期 plan 模式，实际: {mode}",
        "command": "nanobk setup dns apply",
    }


def _step_dns_apply_execute(zone_name):
    """Step 4: DNS apply execute (manual confirm required)."""
    return {
        "id": "dns_apply_execute",
        "title": "真正创建 DNS",
        "status": "manual_confirm_required",
        "detail": "需要手动复制命令并输入确认短语",
        "command": f'nanobk setup dns apply --apply --zone {zone_name} --confirm "{DNS_APPLY_CONFIRM}"',
    }


def _step_cert_preflight(preflight_result):
    """Step 5: Certificate preflight."""
    if not preflight_result.get("ok"):
        return {
            "id": "cert_preflight",
            "title": "证书自动化预检",
            "status": "blocked",
            "detail": preflight_result.get("error", "预检失败"),
            "command": "nanobk setup cert plan",
        }
    return {
        "id": "cert_preflight",
        "title": "证书自动化预检",
        "status": "ready",
        "detail": f"推荐方式: {preflight_result.get('recommended_method', 'unknown')}",
        "command": "nanobk setup cert plan",
    }


def _step_cert_issue_execute(zone_name):
    """Step 6: Certificate issue (manual confirm required)."""
    return {
        "id": "cert_issue_execute",
        "title": "真正申请证书",
        "status": "manual_confirm_required",
        "detail": "需要手动复制命令并输入确认短语",
        "command": f'nanobk setup cert issue --issue --zone {zone_name} --confirm "{CERT_ISSUE_CONFIRM}"',
    }


def _step_token_rotation(rotation_result, worker_name):
    """Step 7: Token rotation plan."""
    if not rotation_result.get("ok"):
        return {
            "id": "token_rotation_plan",
            "title": "Token 轮换预案",
            "status": "blocked",
            "detail": rotation_result.get("blocked_reason") or rotation_result.get("error", "预案失败"),
            "command": f"nanobk setup token rotate --worker-name {worker_name}",
        }
    ready = rotation_result.get("ready_to_rotate", False)
    safety_warning = rotation_result.get("safety_warning")
    if safety_warning:
        return {
            "id": "token_rotation_plan",
            "title": "Token 轮换预案",
            "status": "blocked",
            "detail": safety_warning,
            "command": None,
        }
    if ready:
        return {
            "id": "token_rotation_plan",
            "title": "Token 轮换预案",
            "status": "ready",
            "detail": "Token 轮换预案已生成",
            "command": f'nanobk setup token rotate --rotate --worker-name {worker_name} --confirm "{TOKEN_ROTATE_CONFIRM}"',
        }
    return {
        "id": "token_rotation_plan",
        "title": "Token 轮换预案",
        "status": "missing_input",
        "detail": "需要指定 worker-name",
        "command": f"nanobk setup token rotate --worker-name <name>",
    }


# ── Main flow ────────────────────────────────────────────────────────────────

def run_setup_flow(zone_override=None, api_env_override=None, worker_name=None):
    """Run the full setup flow. Returns result dict. Read-only."""

    # Step 1: Load profile
    zone_name = zone_override
    api_env_path = api_env_override
    profile_loaded = False

    if not zone_name or not api_env_path:
        profile, err = load_profile()
        if profile:
            profile_loaded = True
            if not zone_name:
                zone_name = profile.get("zone_name")
            if not api_env_path:
                api_env_path = profile.get("api_env_path")

    steps = []

    # Step 1: CF connect
    steps.append(_step_cf_connect(profile_loaded, zone_name, api_env_path))

    # Step 2: Domain plan (only if we have zone + api_env)
    plan_result = None
    if zone_name and api_env_path:
        try:
            plan_result = run_plan(zone_override=zone_name, api_env_override=api_env_path)
            steps.append(_step_domain_plan(plan_result))
        except Exception as e:
            steps.append({
                "id": "domain_plan",
                "title": "规划 proxy/web 子域名",
                "status": "error",
                "detail": str(e),
                "command": "nanobk setup plan",
            })
    else:
        steps.append({
            "id": "domain_plan",
            "title": "规划 proxy/web 子域名",
            "status": "missing_input",
            "detail": "需要先连接 Cloudflare",
            "command": "nanobk setup plan",
        })

    # Step 3: DNS apply plan (read-only)
    if zone_name and api_env_path:
        try:
            apply_result = run_apply_engine(zone_override=zone_name, api_env_override=api_env_path)
            steps.append(_step_dns_apply_plan(apply_result))
        except Exception as e:
            steps.append({
                "id": "dns_apply_plan",
                "title": "DNS 创建预案",
                "status": "error",
                "detail": str(e),
                "command": "nanobk setup dns apply",
            })
    else:
        steps.append({
            "id": "dns_apply_plan",
            "title": "DNS 创建预案",
            "status": "missing_input",
            "detail": "需要先连接 Cloudflare",
            "command": "nanobk setup dns apply",
        })

    # Step 4: DNS apply execute (always manual)
    steps.append(_step_dns_apply_execute(zone_name or "(未指定)"))

    # Step 5: Certificate preflight
    if zone_name and api_env_path:
        try:
            preflight_result = run_preflight(zone_override=zone_name, api_env_override=api_env_path)
            steps.append(_step_cert_preflight(preflight_result))
        except Exception as e:
            steps.append({
                "id": "cert_preflight",
                "title": "证书自动化预检",
                "status": "error",
                "detail": str(e),
                "command": "nanobk setup cert plan",
            })
    else:
        steps.append({
            "id": "cert_preflight",
            "title": "证书自动化预检",
            "status": "missing_input",
            "detail": "需要先连接 Cloudflare",
            "command": "nanobk setup cert plan",
        })

    # Step 6: Certificate issue (always manual)
    steps.append(_step_cert_issue_execute(zone_name or "(未指定)"))

    # Step 7: Token rotation plan
    if api_env_path:
        try:
            rotation_result = run_rotation_gate(
                worker_name=worker_name,
                api_env_override=api_env_path,
                token_kind="both",
                rotate_mode=False,
            )
            steps.append(_step_token_rotation(rotation_result, worker_name or "(未指定)"))
        except Exception as e:
            steps.append({
                "id": "token_rotation_plan",
                "title": "Token 轮换预案",
                "status": "error",
                "detail": str(e),
                "command": "nanobk setup token rotate",
            })
    else:
        steps.append({
            "id": "token_rotation_plan",
            "title": "Token 轮换预案",
            "status": "missing_input",
            "detail": "需要先连接 Cloudflare",
            "command": "nanobk setup token rotate",
        })

    # Compute summary
    manual_steps = [s for s in steps if s["status"] == "manual_confirm_required"]
    blocked_steps = [s for s in steps if s["status"] == "blocked"]
    ready_steps = [s for s in steps if s["status"] == "ready"]

    # Find next recommended step
    next_step = None
    for s in steps:
        if s["status"] in ("missing_input", "blocked"):
            next_step = s.get("command")
            break
        if s["status"] == "manual_confirm_required":
            next_step = s.get("command")
            break

    return {
        "ok": True,
        "mode": "setup_flow",
        "mutation": False,
        "dangerous_actions_executed": False,
        "steps": steps,
        "manual_confirm_steps": len(manual_steps),
        "blocked_steps": len(blocked_steps),
        "ready_steps": len(ready_steps),
        "setup_complete": False,
        "next_recommended_step": next_step,
    }


# ── Output ───────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable setup flow summary."""
    print()
    print("  NanoBK 一键设置流程")
    print()

    steps = result.get("steps", [])

    # Status summary
    print("  当前状态：")
    for s in steps:
        status = s.get("status", "unknown")
        detail = s.get("detail", "")
        title = s.get("title", "")
        status_icons = {
            "ready": "✅",
            "missing_input": "⬜",
            "blocked": "🚫",
            "manual_confirm_required": "⚠️ ",
            "partial": "🟡",
            "error": "❌",
        }
        icon = status_icons.get(status, "❓")
        print(f"    {icon} {title}: {detail}")
    print()

    # Manual confirm steps
    manual_steps = [s for s in steps if s["status"] == "manual_confirm_required"]
    if manual_steps:
        print("  危险动作需要你手动复制命令确认：")
        for s in manual_steps:
            print(f"    * {s.get('title', '')}")
            cmd = s.get("command")
            if cmd:
                print(f"      {cmd}")
        print()

    # Next step
    next_step = result.get("next_recommended_step")
    if next_step:
        print("  接下来建议：")
        print(f"    {next_step}")
        print()

    print("  本流程没有执行任何危险动作。")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {
            "ok": False,
            "mode": "setup_flow",
            "error": message,
            "mutation": False,
            "dangerous_actions_executed": False,
        }
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Full CLI Setup Flow (read-only)"
    )
    parser.add_argument("--zone", help="Domain zone (overrides profile)")
    parser.add_argument("--api-env", help="Path to Cloudflare env file (overrides profile)")
    parser.add_argument("--worker-name", help="Cloudflare Worker name for token rotation")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    result = run_setup_flow(
        zone_override=args.zone,
        api_env_override=args.api_env,
        worker_name=args.worker_name,
    )

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)

    if not result.get("ok"):
        sys.exit(1)


if __name__ == "__main__":
    main()
