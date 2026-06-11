#!/usr/bin/env python3
"""
NanoBK Domain/IP/Subdomain Planner

Beginner-friendly read-only planner that:
1. Loads zone and Cloudflare env from setup profile
2. Detects VPS public IPv4/IPv6
3. Suggests proxy/web subdomains
4. Checks subdomain availability
5. Produces human-readable and JSON planning output

Read-only. No DNS mutation. No Cloudflare POST/PATCH/DELETE.

Usage:
    python3 lib/nanobk_domain_planner.py plan [--zone DOMAIN] [--api-env PATH] [--json]

Test hooks (from reused modules):
    NANOBK_TEST_DETECTED_IPV4=203.0.113.10
    NANOBK_TEST_DETECTED_IPV6=2001:db8::10
    NANOBK_TEST_DETECT_IPV4_FAIL=1
    NANOBK_TEST_DETECT_IPV6_FAIL=1
    NANOBK_CF_ZONES_FAKE_RESPONSE=/path/to/zones.json
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP=/path/to/map.json
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_ip_detect import run_detect, mask_ipv4, mask_ipv6
from nanobk_cf_zones import fetch_zones
from nanobk_cf_zones import parse_env_file
from nanobk_cf_dns_availability import (
    validate_zone, run_summary, parse_nodes, load_fake_map, fetch_records_for_node, analyze_records
)
from nanobk_setup_profile import load_profile


# ── Zone ID lookup ───────────────────────────────────────────────────────────

def lookup_zone_id(token, zone_name):
    """Look up zone ID from zone name using Cloudflare API. Returns (zone_id, error)."""
    try:
        zones = fetch_zones(token)
    except RuntimeError as e:
        return None, str(e)

    for z in zones:
        if z.get("name", "").lower() == zone_name.lower():
            return z.get("id"), None

    return None, f"域名 '{zone_name}' 未在 Cloudflare 账户中找到。请先在 Cloudflare 添加域名。"


# ── Masking ──────────────────────────────────────────────────────────────────

def mask_ip(addr, family):
    """Mask IP address for safe display."""
    if family == "ipv4":
        return mask_ipv4(addr)
    elif family == "ipv6":
        return mask_ipv6(addr)
    return "***"


# ── Plan generation ──────────────────────────────────────────────────────────

def run_plan(zone_override=None, api_env_override=None):
    """Run the domain planner. Returns result dict."""

    # Step 1: Load profile or use overrides
    zone_name = zone_override
    api_env_path = api_env_override

    if not zone_name or not api_env_path:
        profile, err = load_profile()
        if err:
            if not zone_name and not api_env_path:
                return {
                    "ok": False,
                    "error": f"未找到 setup profile。请先运行：nanobk cf connect",
                    "mutation": False,
                }
            # Partial override
            if not zone_name:
                zone_name = profile.get("zone_name") if profile else None
            if not api_env_path:
                api_env_path = profile.get("api_env_path") if profile else None
        else:
            if not zone_name:
                zone_name = profile.get("zone_name")
            if not api_env_path:
                api_env_path = profile.get("api_env_path")

    if not zone_name:
        return {"ok": False, "error": "未指定域名。请先运行 nanobk cf connect 或使用 --zone。", "mutation": False}
    if not api_env_path:
        return {"ok": False, "error": "未指定 Cloudflare API 配置。请先运行 nanobk cf connect 或使用 --api-env。", "mutation": False}

    # Step 2: Validate zone
    zone_err = validate_zone(zone_name)
    if zone_err:
        return {"ok": False, "error": zone_err, "mutation": False}

    # Step 3: Parse env and get token
    try:
        env = parse_env_file(api_env_path)
    except (FileNotFoundError, PermissionError, ValueError) as e:
        return {"ok": False, "error": str(e), "mutation": False}

    token = env.get("CF_API_TOKEN")
    if not token:
        return {"ok": False, "error": "CF_API_TOKEN not found in env file", "mutation": False}

    # Step 4: Look up zone ID
    zone_id, zone_err = lookup_zone_id(token, zone_name)
    if zone_err:
        return {"ok": False, "error": zone_err, "mutation": False}

    # Step 5: Detect IP
    try:
        ip_result = run_detect()
    except Exception as e:
        return {"ok": False, "error": f"IP 检测失败: {e}", "mutation": False}

    ipv4 = ip_result.get("ipv4", {})
    ipv6 = ip_result.get("ipv6", {})
    ipv4_detected = ipv4.get("status") == "detected"
    ipv6_detected = ipv6.get("status") == "detected"
    ipv4_addr = ipv4.get("address")
    ipv6_addr = ipv6.get("address")

    # Step 6: Check availability for proxy and web
    nodes_list = ["proxy", "web"]

    try:
        fake_map = load_fake_map()
    except RuntimeError as e:
        return {"ok": False, "error": str(e), "mutation": False}

    records_data = []
    for node in nodes_list:
        try:
            records = fetch_records_for_node(node, zone_name, zone_id, token, fake_map)
            analysis = analyze_records(records, zone_name)
            records_data.append({
                "node": node,
                "hostname": f"{node}.{zone_name}",
                "available": analysis.get("available", False),
                "status": analysis.get("status", "unknown"),
                "records_found": analysis.get("records_found", 0),
            })
        except RuntimeError as e:
            records_data.append({
                "node": node,
                "hostname": f"{node}.{zone_name}",
                "available": False,
                "status": "error",
                "records_found": 0,
                "error": str(e),
            })

    # Step 7: Build plan
    plan_records = []
    for rd in records_data:
        node = rd["node"]
        avail = rd.get("available", False)
        status = rd.get("status", "unknown")

        if avail and ipv4_detected:
            rec_type = "A"
            content_masked = mask_ip(ipv4_addr, "ipv4") if ipv4_addr else "***"
            planned = True
        elif avail and ipv6_detected:
            rec_type = "AAAA"
            content_masked = mask_ip(ipv6_addr, "ipv6") if ipv6_addr else "***"
            planned = True
        else:
            rec_type = "A"
            content_masked = "***"
            planned = False

        plan_records.append({
            "name": rd["hostname"],
            "role": node,
            "available": avail,
            "status": status,
            "planned": planned,
            "type": rec_type if planned else "A",
            "content_masked": content_masked if planned else "***",
            "records_found": rd.get("records_found", 0),
        })

    all_available = all(r["available"] for r in plan_records)
    any_planned = any(r["planned"] for r in plan_records)

    return {
        "ok": True,
        "zone_name": zone_name,
        "profile_loaded": True,
        "ip_detected": ipv4_detected or ipv6_detected,
        "ipv4_detected": ipv4_detected,
        "ipv6_detected": ipv6_detected,
        "ipv4_masked": mask_ip(ipv4_addr, "ipv4") if ipv4_addr else None,
        "ipv6_masked": mask_ip(ipv6_addr, "ipv6") if ipv6_addr else None,
        "records": plan_records,
        "all_available": all_available,
        "any_planned": any_planned,
        "mutation": False,
        "apply_ready": False,
        "next_step": "v2.3.4 dns apply engine",
    }


# ── Output ───────────────────────────────────────────────────────────────────

def output_text(result):
    """Print beginner-friendly plan summary."""
    print()
    print("  NanoBK 域名规划")
    print()

    zone = result.get("zone_name", "***")
    print(f"  当前域名：{zone}")
    print()

    # IP detection
    ipv4_detected = result.get("ipv4_detected", False)
    ipv6_detected = result.get("ipv6_detected", False)
    ipv4_masked = result.get("ipv4_masked")
    ipv6_masked = result.get("ipv6_masked")

    print("  VPS IP：")
    if ipv4_detected:
        print(f"    * IPv4：已检测到 ({ipv4_masked})")
    else:
        print("    * IPv4：未检测到")
    if ipv6_detected:
        print(f"    * IPv6：已检测到 ({ipv6_masked})")
    else:
        print("    * IPv6：未检测到")
    print()

    # Recommended subdomains
    records = result.get("records", [])
    print("  推荐子域名：")
    for r in records:
        print(f"    * {r.get('name', '***')}")
    print()

    # Check results
    print("  检查结果：")
    for r in records:
        name = r.get("name", "***")
        avail = r.get("available", False)
        status = r.get("status", "unknown")
        if avail:
            print(f"    * {name}：可用")
        elif status == "conflict":
            print(f"    * {name}：已被占用（不会覆盖已有记录）")
        elif status == "nanobk_owned":
            print(f"    * {name}：已被 NanoBK 管理")
        else:
            print(f"    * {name}：需要手动检查")
    print()

    # Recommended plan
    print("  推荐计划：")
    for r in records:
        name = r.get("name", "***")
        planned = r.get("planned", False)
        rec_type = r.get("type", "A")
        content = r.get("content_masked", "***")
        if planned:
            print(f"    * 创建 {rec_type} 记录 {name} -> {content}")
        else:
            print(f"    * {name}：暂不可创建（子域名不可用或未检测到 IP）")

    if ipv6_detected and ipv4_detected:
        print("    * 如有 IPv6，可选创建 AAAA 记录")
    print()

    # Safety
    print("  安全说明：")
    print("    本步骤只检查和规划，不会创建 DNS，不会修改 Cloudflare。")
    print()

    # Next step
    print("  下一步：")
    print("    v2.3.4 将加入确认后创建 DNS 的 apply engine。")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mutation": False}
        print(json.dumps(result, indent=2))
    else:
        print(f"  错误：{message}", file=sys.stderr)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Domain/IP/Subdomain Planner (read-only)"
    )
    parser.add_argument("--zone", help="Domain zone (overrides profile)")
    parser.add_argument("--api-env", help="Path to Cloudflare env file (overrides profile)")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    result = run_plan(
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
