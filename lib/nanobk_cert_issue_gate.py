#!/usr/bin/env python3
"""
NanoBK Certificate Issue Gate

Gated certificate issuance engine. By default, shows issue plan only.
Real certificate request requires explicit --issue and exact confirmation phrase.

Read-only plan by default. Issue only with --issue + exact confirm.

Usage:
    python3 lib/nanobk_cert_issue_gate.py [--zone DOMAIN] [--api-env PATH] [--json]
    python3 lib/nanobk_cert_issue_gate.py --issue --confirm "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES" [--zone DOMAIN] [--api-env PATH] [--json]

Test hooks:
    NANOBK_CERT_ISSUE_FAKE_RUN=1
    NANOBK_CERT_ISSUE_FAKE_RESULT=/path/to/result.json
    NANOBK_CERT_ISSUE_FAKE_CAPTURE_COMMAND=/tmp/cert_issue_command.jsonl
    NANOBK_CF_ZONES_FAKE_RESPONSE=/path/to/zones.json
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP=/path/to/map.json
    NANOBK_CERT_PREFLIGHT_FAKE_TOOLS='{"acme_sh":true,"certbot":false}'
    NANOBK_CERT_PREFLIGHT_FAKE_PORTS='{"80":"free","443":"listening"}'
"""

import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cert_preflight import run_preflight
from nanobk_cf_zones import parse_env_file


# ── Constants ────────────────────────────────────────────────────────────────

_CONFIRM_PHRASE = "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"


# ── Command capture (test hook) ──────────────────────────────────────────────

def capture_command(payload_dict):
    """Write command payload to capture file if hook is set. Test-only."""
    capture_path = os.environ.get("NANOBK_CERT_ISSUE_FAKE_CAPTURE_COMMAND")
    if not capture_path:
        return
    try:
        with open(capture_path, "a") as f:
            f.write(json.dumps(payload_dict) + "\n")
    except OSError:
        pass


# ── Fake issue runner ────────────────────────────────────────────────────────

def run_issue_fake(fake_result_path, domains, method, api_env_path):
    """Run fake issue. Returns result dict."""
    try:
        with open(fake_result_path, "r") as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError) as e:
        return {
            "ok": False,
            "mode": "failed",
            "issue_executed": True,
            "mutation": False,
            "error": f"无法读取 fake issue 结果: {e}",
        }

    # Capture the command that would have been run
    capture_command({
        "tool": "acme.sh",
        "args": ["--issue", "--dns", "dns_cf"] + [f"-d {d}" for d in domains],
        "domains": domains,
        "method": method,
        "contains_reload": False,
        "contains_installcert": False,
    })

    if data.get("success"):
        return {
            "ok": True,
            "mode": "issued",
            "issue_executed": True,
            "mutation": True,
            "domains": domains,
            "method": method,
            "tool": "acme.sh",
            "cert_path": data.get("cert_path", ""),
            "key_path_present": bool(data.get("key_path")),
            "private_key_printed": False,
            "service_reloaded": False,
            "config_modified": False,
        }
    else:
        return {
            "ok": False,
            "mode": "failed",
            "issue_executed": True,
            "mutation": False,
            "error": data.get("error", "证书签发失败"),
        }


# ── Real issue runner ────────────────────────────────────────────────────────

def run_issue_real(domains, method, api_env_path):
    """Run real acme.sh issue. Returns result dict.

    SAFETY: Only runs acme.sh --issue --dns dns_cf.
    Does NOT run --install-cert, --reloadcmd, or any service restart.
    """
    # Parse env for CF_API_TOKEN
    try:
        env = parse_env_file(api_env_path)
    except (FileNotFoundError, PermissionError, ValueError) as e:
        return {
            "ok": False,
            "mode": "failed",
            "issue_executed": False,
            "mutation": False,
            "error": str(e),
        }

    cf_token = env.get("CF_API_TOKEN")
    if not cf_token:
        return {
            "ok": False,
            "mode": "failed",
            "issue_executed": False,
            "mutation": False,
            "error": "CF_API_TOKEN not found",
        }

    # Build acme.sh command — SAFE: no --install-cert, no --reloadcmd
    cmd = ["acme.sh", "--issue", "--dns", "dns_cf"]
    for d in domains:
        cmd.extend(["-d", d])

    # Capture the command (without token)
    capture_command({
        "tool": "acme.sh",
        "args": cmd,
        "domains": domains,
        "method": method,
        "contains_reload": False,
        "contains_installcert": False,
    })

    # Set CF_CF_TOKEN for acme.sh dns_cf plugin
    env_copy = os.environ.copy()
    env_copy["CF_Token"] = cf_token
    env_copy["CF_Zone_ID"] = env.get("CF_ZONE_ID", "")

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=300,
            env=env_copy,
        )
    except FileNotFoundError:
        return {
            "ok": False,
            "mode": "failed",
            "issue_executed": True,
            "mutation": False,
            "error": "acme.sh 未安装或不在 PATH 中",
        }
    except subprocess.TimeoutExpired:
        return {
            "ok": False,
            "mode": "failed",
            "issue_executed": True,
            "mutation": True,
            "error": "acme.sh 执行超时（300秒）",
        }
    except OSError as e:
        return {
            "ok": False,
            "mode": "failed",
            "issue_executed": True,
            "mutation": False,
            "error": f"acme.sh 执行失败: {e}",
        }

    if result.returncode != 0:
        # Sanitize stderr — don't leak token
        stderr = result.stderr
        if cf_token in stderr:
            stderr = stderr.replace(cf_token, "[REDACTED]")
        return {
            "ok": False,
            "mode": "failed",
            "issue_executed": True,
            "mutation": True,
            "error": f"acme.sh 退出码 {result.returncode}",
        }

    # Parse output for cert paths
    stdout = result.stdout
    cert_path = ""
    key_path = ""
    for line in stdout.splitlines():
        if "Your cert is in" in line or "fullchain.cer" in line:
            cert_path = line.split()[-1] if line.split() else ""
        if "Your key is in" in line or ".key" in line:
            key_path = line.split()[-1] if line.split() else ""

    return {
        "ok": True,
        "mode": "issued",
        "issue_executed": True,
        "mutation": True,
        "domains": domains,
        "method": method,
        "tool": "acme.sh",
        "cert_path": cert_path or "(见 acme.sh 输出)",
        "key_path_present": bool(key_path),
        "private_key_printed": False,
        "service_reloaded": False,
        "config_modified": False,
    }


# ── Main issue gate ──────────────────────────────────────────────────────────

def run_issue_gate(zone_override=None, api_env_override=None,
                   issue_mode=False, confirm_phrase=None):
    """Run the certificate issue gate. Returns result dict."""

    # Step 1: Run preflight
    preflight = run_preflight(
        zone_override=zone_override,
        api_env_override=api_env_override,
    )

    if not preflight.get("ok"):
        return {
            "ok": False,
            "mode": "blocked",
            "issue_executed": False,
            "mutation": False,
            "blocked_reason": preflight.get("error", "preflight failed"),
        }

    zone_name = preflight.get("zone_name", "")
    domains_info = preflight.get("domains", [])
    recommended_method = preflight.get("recommended_method", "blocked")
    tools = preflight.get("tools", {})

    # Extract domain names
    domains = [d.get("name", "") for d in domains_info]

    # Step 2: Check if ready to issue
    all_dns_ready = all(
        d.get("dns_present") and d.get("nanobk_owned")
        for d in domains_info
    )
    has_acme = tools.get("acme_sh", False)

    ready_to_issue = (
        all_dns_ready
        and has_acme
        and recommended_method == "dns-01-cloudflare"
    )

    # Step 3: Plan-only mode
    if not issue_mode:
        return {
            "ok": True,
            "mode": "cert_issue_plan",
            "issue_executed": False,
            "mutation": False,
            "zone_name": zone_name,
            "domains": domains,
            "method": recommended_method,
            "tool": "acme.sh" if has_acme else "none",
            "ready_to_issue": ready_to_issue,
            "next_command": f'nanobk setup cert issue --issue --confirm "{_CONFIRM_PHRASE}"',
        }

    # Step 4: Issue mode — check confirmation
    if confirm_phrase != _CONFIRM_PHRASE:
        return {
            "ok": False,
            "mode": "blocked",
            "issue_executed": False,
            "mutation": False,
            "blocked_reason": "missing exact confirmation",
            "hint": f'需要输入: --confirm "{_CONFIRM_PHRASE}"',
        }

    # Step 5: Validate all gate conditions
    if not all_dns_ready:
        return {
            "ok": False,
            "mode": "blocked",
            "issue_executed": False,
            "mutation": False,
            "blocked_reason": "DNS 记录尚未就绪",
        }

    if not has_acme:
        return {
            "ok": False,
            "mode": "blocked",
            "issue_executed": False,
            "mutation": False,
            "blocked_reason": "acme.sh 未安装",
        }

    if recommended_method != "dns-01-cloudflare":
        return {
            "ok": False,
            "mode": "blocked",
            "issue_executed": False,
            "mutation": False,
            "blocked_reason": f"推荐方法不是 dns-01-cloudflare: {recommended_method}",
        }

    # Step 6: Get api_env_path
    api_env_path = api_env_override
    if not api_env_path:
        from nanobk_setup_profile import load_profile
        profile, _ = load_profile()
        if profile:
            api_env_path = profile.get("api_env_path")

    if not api_env_path:
        return {
            "ok": False,
            "mode": "blocked",
            "issue_executed": False,
            "mutation": False,
            "blocked_reason": "未找到 API 配置",
        }

    # Step 7: Execute issue (fake or real)
    fake_run = os.environ.get("NANOBK_CERT_ISSUE_FAKE_RUN")
    fake_result_path = os.environ.get("NANOBK_CERT_ISSUE_FAKE_RESULT")

    if fake_run and fake_result_path:
        return run_issue_fake(fake_result_path, domains, recommended_method, api_env_path)

    return run_issue_real(domains, recommended_method, api_env_path)


# ── Output ───────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable result."""
    mode = result.get("mode", "unknown")

    if mode == "cert_issue_plan":
        _output_plan_text(result)
    elif mode == "issued":
        _output_issued_text(result)
    elif mode == "blocked":
        _output_blocked_text(result)
    elif mode == "failed":
        _output_failed_text(result)
    else:
        _output_failed_text(result)


def _output_plan_text(result):
    print()
    print("  NanoBK 证书签发预案")
    print()

    domains = result.get("domains", [])
    method = result.get("method", "unknown")
    tool = result.get("tool", "none")
    ready = result.get("ready_to_issue", False)

    if domains:
        print("  域名：")
        for d in domains:
            print(f"    * {d}")
        print()

    method_labels = {
        "dns-01-cloudflare": "Cloudflare DNS-01",
        "http-01": "HTTP-01",
        "manual": "手动配置",
        "blocked": "暂不可用",
    }
    print(f"  签发方式：{method_labels.get(method, method)}")
    print(f"  工具：{tool}")
    print(f"  就绪状态：{'就绪' if ready else '未就绪'}")
    print()

    if ready:
        print("  真正申请证书请执行：")
        print(f'    nanobk setup cert issue --issue --confirm "{_CONFIRM_PHRASE}"')
    else:
        print("  当前条件不满足签发要求，请先完成前置步骤。")
    print()

    print("  安全说明：")
    print("    本步骤只显示预案，不会申请证书，不会修改服务配置。")
    print()


def _output_issued_text(result):
    print()
    print("  NanoBK 证书签发完成")
    print()

    domains = result.get("domains", [])
    cert_path = result.get("cert_path", "")

    if domains:
        print("  域名：")
        for d in domains:
            print(f"    * {d}")
        print()

    if cert_path:
        print(f"  证书路径：{cert_path}")
        print()

    print("  安全说明：")
    print("    * 未修改服务配置")
    print("    * 未 reload 服务")
    print("    * 未安装自动续期")
    print()


def _output_blocked_text(result):
    print()
    print("  证书签发被阻止")
    print()
    reason = result.get("blocked_reason") or result.get("error", "未知原因")
    print(f"  原因：{reason}")
    hint = result.get("hint", "")
    if hint:
        print(f"  提示：{hint}")
    print()


def _output_failed_text(result):
    print()
    print("  证书签发失败")
    print()
    print(f"  错误：{result.get('error', '未知错误')}")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {
            "ok": False,
            "mode": "blocked",
            "issue_executed": False,
            "mutation": False,
            "blocked_reason": message,
        }
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Certificate Issue Gate"
    )
    parser.add_argument("--zone", help="Domain zone (overrides profile)")
    parser.add_argument("--api-env", help="Path to Cloudflare env file (overrides profile)")
    parser.add_argument("--issue", action="store_true", help="Actually request certificate")
    parser.add_argument("--confirm", help="Exact confirmation phrase")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    result = run_issue_gate(
        zone_override=args.zone,
        api_env_override=args.api_env,
        issue_mode=args.issue,
        confirm_phrase=args.confirm,
    )

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)

    if not result.get("ok"):
        sys.exit(1)


if __name__ == "__main__":
    main()
