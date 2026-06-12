#!/usr/bin/env python3
"""
NanoBK Certificate Automation Preflight

Read-only preflight check for certificate issuance readiness.
Checks DNS records, local ACME tools, and port availability.

No certificate request. No acme.sh issue. No certbot certonly.
No service reload/restart. No config mutation.

Usage:
    python3 lib/nanobk_cert_preflight.py [--zone DOMAIN] [--api-env PATH] [--json]

Test hooks:
    NANOBK_CERT_PREFLIGHT_FAKE_DNS_RESPONSE_MAP=/path/to/map.json
    NANOBK_CERT_PREFLIGHT_FAKE_TOOLS='{"acme_sh":false,"certbot":true}'
    NANOBK_CERT_PREFLIGHT_FAKE_PORTS='{"80":"free","443":"listening"}'
    NANOBK_CF_ZONES_FAKE_RESPONSE=/path/to/zones.json
"""

import argparse
import json
import os
import shutil
import socket
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cf_zones import parse_env_file, fetch_zones, mask_domain
from nanobk_cf_dns_availability import (
    validate_zone, load_fake_map, fetch_records_for_node, analyze_records, is_nanobk_owned,
)
from nanobk_setup_profile import load_profile


# ── Constants ────────────────────────────────────────────────────────────────

_DOMAINS = ["proxy", "web"]
_NANOBK_MARKER = "managed-by=nanobk"


# ── Zone ID lookup ───────────────────────────────────────────────────────────

def lookup_zone_id(token, zone_name):
    """Look up zone ID from zone name. Returns (zone_id, error)."""
    try:
        zones = fetch_zones(token)
    except RuntimeError as e:
        return None, str(e)
    for z in zones:
        if z.get("name", "").lower() == zone_name.lower():
            return z.get("id"), None
    return None, f"域名 '{zone_name}' 未在 Cloudflare 账户中找到。"


# ── DNS check ────────────────────────────────────────────────────────────────

def check_dns(token, zone_id, zone_name, fake_map=None):
    """Check DNS records for proxy/web domains. Returns list of domain results."""
    domains = []
    for prefix in _DOMAINS:
        hostname = f"{prefix}.{zone_name}"
        try:
            records = fetch_records_for_node(prefix, zone_name, zone_id, token, fake_map)
            analysis = analyze_records(records, zone_name)

            dns_present = analysis.get("records_found", 0) > 0
            status = analysis.get("status", "unknown")

            # Check NanoBK ownership
            nanobk_owned = False
            if status == "nanobk_owned":
                nanobk_owned = True
            elif dns_present:
                # Re-check ownership from raw records
                nanobk_owned = all(is_nanobk_owned(r) for r in records) if records else False

            domains.append({
                "name": hostname,
                "dns_present": dns_present,
                "nanobk_owned": nanobk_owned,
                "status": status,
            })
        except RuntimeError as e:
            domains.append({
                "name": hostname,
                "dns_present": False,
                "nanobk_owned": False,
                "status": "error",
                "error": str(e),
            })
    return domains


# ── Tool detection ───────────────────────────────────────────────────────────

def detect_tools():
    """Detect local ACME tools. Returns dict."""
    fake = os.environ.get("NANOBK_CERT_PREFLIGHT_FAKE_TOOLS")
    if fake:
        try:
            return json.loads(fake)
        except json.JSONDecodeError:
            pass

    return {
        "acme_sh": shutil.which("acme.sh") is not None,
        "certbot": shutil.which("certbot") is not None,
    }


# ── Port check ───────────────────────────────────────────────────────────────

def check_port(port):
    """Check if a port is listening. Returns 'listening' or 'free'."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(1)
        result = sock.connect_ex(("127.0.0.1", port))
        sock.close()
        return "listening" if result == 0 else "free"
    except (socket.error, OSError):
        return "unknown"


def check_ports():
    """Check ports 80 and 443. Returns dict."""
    fake = os.environ.get("NANOBK_CERT_PREFLIGHT_FAKE_PORTS")
    if fake:
        try:
            return json.loads(fake)
        except json.JSONDecodeError:
            pass

    return {
        "80": check_port(80),
        "443": check_port(443),
    }


# ── Recommendation ───────────────────────────────────────────────────────────

def recommend_method(tools, ports, domains):
    """Recommend certificate method. Returns (method, reason)."""
    # Check if DNS records are ready
    all_ready = all(d.get("dns_present") and d.get("nanobk_owned") for d in domains)
    if not all_ready:
        return "blocked", "DNS 记录尚未就绪，请先完成 DNS 创建。"

    has_cf_token = True  # We got this far, token is valid
    port_80_free = ports.get("80") == "free"

    # DNS-01 is preferred (doesn't depend on port 80)
    if has_cf_token:
        return "dns-01-cloudflare", "推荐 Cloudflare DNS-01（不依赖 80 端口）"

    # HTTP-01 fallback
    if port_80_free:
        return "http-01", "可选 HTTP-01（需要 80 端口可用）"

    return "manual", "需要手动配置证书。"


# ── Main preflight ───────────────────────────────────────────────────────────

def run_preflight(zone_override=None, api_env_override=None):
    """Run certificate preflight. Returns result dict."""

    # Step 1: Load profile or use overrides
    zone_name = zone_override
    api_env_path = api_env_override

    if not zone_name or not api_env_path:
        profile, err = load_profile()
        if err:
            if not zone_name and not api_env_path:
                return {
                    "ok": False,
                    "error": "未找到 setup profile。请先运行：nanobk cf connect",
                    "issue_executed": False,
                    "mutation": False,
                }
        else:
            if not zone_name:
                zone_name = profile.get("zone_name")
            if not api_env_path:
                api_env_path = profile.get("api_env_path")

    if not zone_name:
        return {"ok": False, "error": "未指定域名。请先运行 nanobk cf connect 或使用 --zone。",
                "issue_executed": False, "mutation": False}
    if not api_env_path:
        return {"ok": False, "error": "未指定 Cloudflare API 配置。请先运行 nanobk cf connect 或使用 --api-env。",
                "issue_executed": False, "mutation": False}

    # Step 2: Validate zone
    zone_err = validate_zone(zone_name)
    if zone_err:
        return {"ok": False, "error": zone_err, "issue_executed": False, "mutation": False}

    # Step 3: Parse env and get token
    try:
        env = parse_env_file(api_env_path)
    except (FileNotFoundError, PermissionError, ValueError) as e:
        return {"ok": False, "error": str(e), "issue_executed": False, "mutation": False}

    token = env.get("CF_API_TOKEN")
    if not token:
        return {"ok": False, "error": "CF_API_TOKEN not found in env file",
                "issue_executed": False, "mutation": False}

    # Step 4: Look up zone ID
    zone_id, zone_err = lookup_zone_id(token, zone_name)
    if zone_err:
        return {"ok": False, "error": zone_err, "issue_executed": False, "mutation": False}

    # Step 5: Load fake map for DNS check
    try:
        fake_map = load_fake_map()
    except RuntimeError as e:
        return {"ok": False, "error": str(e), "issue_executed": False, "mutation": False}

    # Step 6: Check DNS
    try:
        domains = check_dns(token, zone_id, zone_name, fake_map)
    except Exception as e:
        return {"ok": False, "error": f"DNS 检查失败: {e}",
                "issue_executed": False, "mutation": False}

    # Step 7: Detect tools and ports
    tools = detect_tools()
    ports = check_ports()

    # Step 8: Recommend method
    method, reason = recommend_method(tools, ports, domains)

    return {
        "ok": True,
        "mode": "cert_preflight",
        "zone_name": zone_name,
        "domains": domains,
        "tools": tools,
        "ports": ports,
        "recommended_method": method,
        "recommendation_reason": reason,
        "issue_executed": False,
        "mutation": False,
        "next_step": "v2.3.6 certificate issue gate",
    }


# ── Output ───────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable preflight report."""
    print()
    print("  NanoBK 证书自动化预检")
    print()

    # Domains
    domains = result.get("domains", [])
    if domains:
        print("  域名：")
        for d in domains:
            print(f"    * {d.get('name', '***')}")
        print()

    # DNS check
    print("  DNS 检查：")
    for d in domains:
        name = d.get("name", "***")
        present = d.get("dns_present", False)
        owned = d.get("nanobk_owned", False)
        if present and owned:
            print(f"    * {name}：已存在，NanoBK 管理")
        elif present:
            print(f"    * {name}：已存在，非 NanoBK 管理")
        else:
            print(f"    * {name}：未找到 DNS 记录")
    print()

    # Tools
    tools = result.get("tools", {})
    print("  本机工具：")
    print(f"    * acme.sh：{'已安装' if tools.get('acme_sh') else '未安装'}")
    print(f"    * certbot：{'已安装' if tools.get('certbot') else '未安装'}")
    print()

    # Ports
    ports = result.get("ports", {})
    print("  端口检查：")
    for port_num in ["80", "443"]:
        status = ports.get(port_num, "unknown")
        label = "已监听" if status == "listening" else "空闲" if status == "free" else "未知"
        print(f"    * {port_num}：{label}")
    print()

    # Recommendation
    method = result.get("recommended_method", "unknown")
    reason = result.get("recommendation_reason", "")
    print("  推荐方案：")
    method_labels = {
        "dns-01-cloudflare": "Cloudflare DNS-01",
        "http-01": "HTTP-01",
        "manual": "手动配置",
        "blocked": "暂不可用",
    }
    print(f"    * 推荐 {method_labels.get(method, method)}")
    if reason:
        print(f"    * {reason}")
    print("    * 下一阶段将自动安装/调用证书工具")
    print()

    # Safety
    print("  安全说明：")
    print("    本步骤只检查，不会申请证书，不会修改服务配置。")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "issue_executed": False, "mutation": False}
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Certificate Automation Preflight (read-only)"
    )
    parser.add_argument("--zone", help="Domain zone (overrides profile)")
    parser.add_argument("--api-env", help="Path to Cloudflare env file (overrides profile)")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    result = run_preflight(
        zone_override=args.zone,
        api_env_override=args.api_env,
    )

    if not result.get("ok"):
        output_error(result.get("error", "unknown error"), args.json)
        sys.exit(1)

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)


if __name__ == "__main__":
    main()
