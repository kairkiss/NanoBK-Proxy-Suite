#!/usr/bin/env python3
"""
NanoBK Production DNS Readiness Flow (v2.5.2)

Read-only Cloudflare domain/DNS readiness check that:
1. Reads Cloudflare zones (GET-only)
2. Detects VPS IPv4/IPv6
3. Checks proxy/web subdomain availability
4. Produces DNS readiness summary with planned records
5. Optionally saves local setup profile

Read-only. No DNS mutation. No Cloudflare POST/PATCH/DELETE.
No curl/wrangler/certbot calls. No service reload/restart.

Usage:
    python3 lib/nanobk_production_dns_readiness.py [--json]
    python3 lib/nanobk_production_dns_readiness.py --zone DOMAIN [--json]
    python3 lib/nanobk_production_dns_readiness.py save --zone DOMAIN [--proxy-subdomain NAME] [--web-subdomain NAME]

Test hooks (from reused modules):
    NANOBK_CF_ZONES_FAKE_RESPONSE=/path/to/zones.json
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP=/path/to/map.json
    NANOBK_TEST_DETECTED_IPV4=203.0.113.10
    NANOBK_TEST_DETECTED_IPV6=2001:db8::10
    NANOBK_TEST_DETECT_IPV4_FAIL=1
    NANOBK_TEST_DETECT_IPV6_FAIL=1
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_ip_detect import run_detect, mask_ipv4, mask_ipv6
from nanobk_cf_zones import fetch_zones, parse_env_file
from nanobk_cf_dns_availability import load_fake_map, fetch_records_for_node, analyze_records
from nanobk_setup_profile import load_profile, save_profile


# ── Masking helpers ─────────────────────────────────────────────────────────

def mask_ip(addr, family):
    """Mask IP address for safe display."""
    if family == "ipv4":
        return mask_ipv4(addr)
    elif family == "ipv6":
        return mask_ipv6(addr)
    return "***"


# ── Cloudflare zone discovery ───────────────────────────────────────────────

def discover_zones(api_env_path):
    """Discover Cloudflare zones from api-env file.

    Returns (zones_list, error_string).
    zones_list is a list of plain domain name strings.
    Never exposes zone_id, token, or api_env_path.
    """
    try:
        env = parse_env_file(api_env_path)
    except FileNotFoundError:
        return None, "api-env 文件不存在"
    except PermissionError as e:
        return None, str(e)
    except ValueError as e:
        return None, str(e)

    token = env.get("CF_API_TOKEN")
    if not token:
        return None, "api-env 文件中缺少 CF_API_TOKEN"

    try:
        zones_raw = fetch_zones(token)
    except RuntimeError as e:
        return None, str(e)

    zones = sorted(set(z.get("name", "") for z in zones_raw if z.get("name")))
    return zones, None


# ── Readiness check ─────────────────────────────────────────────────────────

def run_readiness(zone=None, api_env=None, proxy_subdomain="proxy", web_subdomain="web"):
    """Run the full DNS readiness check. Returns result dict.

    Safe JSON only. Never includes:
    - CF_API_TOKEN, zone_id, record_id, api_env_path, raw API response
    """
    # Step 1: Resolve inputs from profile or overrides
    profile_zone = None
    profile_api_env = None
    profile, profile_err = load_profile()
    if not profile_err:
        profile_zone = profile.get("zone_name", "")
        profile_api_env = profile.get("api_env_path", "")

    zone_name = zone or profile_zone
    api_env_path = api_env or profile_api_env

    # Step 2: Cloudflare zone discovery
    cf_status = "missing"
    zones_list = []
    zones_count = 0

    if api_env_path and os.path.isfile(api_env_path):
        zones, cf_err = discover_zones(api_env_path)
        if cf_err:
            cf_status = "error"
            # If we have a zone name from profile/override, continue with limited info
            if not zone_name:
                return {
                    "ok": True,
                    "mode": "production_dns_readiness_v2_5",
                    "version": "2.5.2",
                    "mutation": False,
                    "cloudflare": {"status": "error", "zones_count": 0, "zones": []},
                    "selected_domain": None,
                    "vps_ip": {"ipv4": {"status": "unknown", "masked": None}, "ipv6": {"status": "unknown", "masked": None}},
                    "subdomains": {},
                    "planned_records": [],
                    "blocked": True,
                    "next_step": "connect_cloudflare",
                    "safety": "read_only",
                    "profile_saved": False,
                    "error": cf_err,
                }
        else:
            cf_status = "connected"
            zones_list = zones or []
            zones_count = len(zones_list)

    if cf_status == "missing" and not zone_name:
        return {
            "ok": True,
            "mode": "production_dns_readiness_v2_5",
            "version": "2.5.2",
            "mutation": False,
            "cloudflare": {"status": "missing", "zones_count": 0, "zones": []},
            "selected_domain": None,
            "vps_ip": {"ipv4": {"status": "unknown", "masked": None}, "ipv6": {"status": "unknown", "masked": None}},
            "subdomains": {},
            "planned_records": [],
            "blocked": True,
            "next_step": "connect_cloudflare",
            "safety": "read_only",
            "profile_saved": False,
        }

    # Step 3: Zone selection
    if not zone_name:
        # Suggest zones if available
        if zones_count == 1:
            zone_name = zones_list[0]
        elif zones_count > 1:
            return {
                "ok": True,
                "mode": "production_dns_readiness_v2_5",
                "version": "2.5.2",
                "mutation": False,
                "cloudflare": {"status": cf_status, "zones_count": zones_count, "zones": zones_list},
                "selected_domain": None,
                "vps_ip": {"ipv4": {"status": "unknown", "masked": None}, "ipv6": {"status": "unknown", "masked": None}},
                "subdomains": {},
                "planned_records": [],
                "blocked": True,
                "next_step": "select_zone",
                "safety": "read_only",
                "profile_saved": False,
            }

    # Step 4: IP detection
    try:
        ip_result = run_detect()
    except Exception:
        ip_result = {"ipv4": {"status": "not_detected", "address": None}, "ipv6": {"status": "not_detected", "address": None}}

    ipv4 = ip_result.get("ipv4", {})
    ipv6 = ip_result.get("ipv6", {})
    ipv4_status = ipv4.get("status", "not_detected")
    ipv6_status = ipv6.get("status", "not_detected")
    ipv4_addr = ipv4.get("address")
    ipv6_addr = ipv6.get("address")

    # Map status for output
    def map_ip_status(status):
        if status == "detected":
            return "detected"
        elif status == "not_detected":
            return "failed"
        elif status == "not_usable":
            return "failed"
        return "unknown"

    ipv4_out = {"status": map_ip_status(ipv4_status), "masked": mask_ip(ipv4_addr, "ipv4") if ipv4_addr else None}
    ipv6_out = {"status": map_ip_status(ipv6_status), "masked": mask_ip(ipv6_addr, "ipv6") if ipv6_addr else None}

    # Step 5: Subdomain availability check
    subdomains = {}
    planned_records = []
    blocked = False
    next_step = "review_dns_gate"
    any_conflict = False

    nodes = [
        {"role": "proxy", "prefix": proxy_subdomain},
        {"role": "web", "prefix": web_subdomain},
    ]

    # Load fake map for testing
    try:
        fake_map = load_fake_map()
    except RuntimeError:
        fake_map = None

    # If we have api_env and zone_id, do real availability check
    zone_id = None
    token = None
    if api_env_path and os.path.isfile(api_env_path):
        try:
            env = parse_env_file(api_env_path)
            token = env.get("CF_API_TOKEN")
            zone_id = env.get("CF_ZONE_ID")
        except (FileNotFoundError, PermissionError, ValueError):
            pass

    for node in nodes:
        prefix = node["prefix"]
        hostname = f"{prefix}.{zone_name}"
        avail_status = "unknown"

        if fake_map is not None:
            # Use fake map for testing
            if prefix in fake_map:
                try:
                    records = fetch_records_for_node(prefix, zone_name, zone_id or "fake", token or "fake", fake_map)
                    analysis = analyze_records(records, zone_name)
                    avail_status = "available" if analysis.get("available") else "occupied"
                except RuntimeError:
                    avail_status = "unknown"
            else:
                # Node not in fake map — treat as available (no records found)
                avail_status = "available"
        elif token and zone_id:
            # Real Cloudflare API check
            try:
                records = fetch_records_for_node(prefix, zone_name, zone_id, token, None)
                analysis = analyze_records(records, zone_name)
                avail_status = "available" if analysis.get("available") else "occupied"
            except RuntimeError:
                avail_status = "unknown"

        subdomains[prefix] = {"name": hostname, "status": avail_status}

        if avail_status == "available":
            # Plan DNS records
            if ipv4_status == "detected" and ipv4_addr:
                planned_records.append({
                    "name": hostname,
                    "type": "A",
                    "content_masked": mask_ip(ipv4_addr, "ipv4"),
                })
            if ipv6_status == "detected" and ipv6_addr:
                planned_records.append({
                    "name": hostname,
                    "type": "AAAA",
                    "content_masked": mask_ip(ipv6_addr, "ipv6"),
                })
        elif avail_status == "occupied":
            any_conflict = True

    # Step 6: Determine blocked state and next step
    if any_conflict:
        blocked = True
        next_step = "custom_subdomain"
    elif ipv4_status != "detected" and ipv6_status != "detected":
        next_step = "manual_ip_input"

    return {
        "ok": True,
        "mode": "production_dns_readiness_v2_5",
        "version": "2.5.2",
        "mutation": False,
        "cloudflare": {"status": cf_status, "zones_count": zones_count, "zones": zones_list},
        "selected_domain": zone_name,
        "vps_ip": {"ipv4": ipv4_out, "ipv6": ipv6_out},
        "subdomains": subdomains,
        "planned_records": planned_records,
        "blocked": blocked,
        "next_step": next_step,
        "safety": "read_only",
        "profile_saved": False,
    }


# ── Save profile ────────────────────────────────────────────────────────────

def run_save(zone, api_env=None, proxy_subdomain="proxy", web_subdomain="web"):
    """Save local setup profile. Returns result dict.

    Only writes to local ~/.nanobk/setup-profile.json.
    Never writes to Cloudflare.
    """
    if not zone:
        return {"ok": False, "error": "zone is required", "mutation": False}

    # Resolve api_env from profile if not provided
    if not api_env:
        profile, profile_err = load_profile()
        if not profile_err:
            api_env = profile.get("api_env_path", "")
        if not api_env:
            return {"ok": False, "error": "api-env path is required. Use --api-env or run nanobk cf connect first.", "mutation": False}

    nodes = [proxy_subdomain, web_subdomain]
    result = save_profile(zone, api_env, nodes)

    if result.get("ok"):
        result["message"] = "已保存本地设置，下次会继续使用这个域名和子域名。"
        result["mutation"] = False
        result["zone_name"] = zone
        result["proxy_subdomain"] = proxy_subdomain
        result["web_subdomain"] = web_subdomain
        # Never expose api_env_path in output
        result.pop("api_env_path_printed", None)
        result.pop("profile_path_printed", None)

    return result


# ── Text output ─────────────────────────────────────────────────────────────

def output_text(result):
    """Print beginner-friendly readiness summary in Chinese."""
    print()
    print("  NanoBK 域名与 DNS 准备")
    print("  ─────────────────────────────────────────────")
    print()
    print("  当前不会创建 DNS，不会修改 Cloudflare。")
    print()

    # Cloudflare status
    cf = result.get("cloudflare", {})
    cf_status = cf.get("status", "unknown")
    cf_zones = cf.get("zones", [])
    cf_count = cf.get("zones_count", 0)

    print("  Cloudflare:")
    if cf_status == "connected":
        print(f"    状态：已连接")
        if cf_count > 0:
            print(f"    可用域名：{', '.join(cf_zones)}")
        else:
            print("    可用域名：无")
    elif cf_status == "missing":
        print("    状态：未连接")
        print("    请先运行：nanobk cf connect")
    elif cf_status == "error":
        print("    状态：连接错误")
    print()

    # Selected domain
    domain = result.get("selected_domain")
    if domain:
        print(f"  选定域名：{domain}")
    elif cf_count > 1:
        print("  请用 --zone 选择一个域名：")
        for z in cf_zones:
            print(f"    * {z}")
    print()

    # VPS IP
    vps_ip = result.get("vps_ip", {})
    ipv4 = vps_ip.get("ipv4", {})
    ipv6 = vps_ip.get("ipv6", {})

    print("  服务器 IP：")
    if ipv4.get("status") == "detected":
        print(f"    IPv4：{ipv4.get('masked', '***')}")
    else:
        print("    IPv4：未检测到")
    if ipv6.get("status") == "detected":
        print(f"    IPv6：{ipv6.get('masked', '***')}")
    else:
        print("    IPv6：未检测到")
    print()

    # Subdomains
    subdomains = result.get("subdomains", {})
    if subdomains:
        print("  准备使用：")
        for prefix, info in subdomains.items():
            print(f"    {info.get('name', '***')}")
        print()

        print("  检查结果：")
        for prefix, info in subdomains.items():
            name = info.get("name", "***")
            status = info.get("status", "unknown")
            if status == "available":
                print(f"    {name} 可以使用")
            elif status == "occupied":
                print(f"    {name} 这个名字已经被用了")
                print(f"    不会覆盖，也不会删除已有配置")
                print(f"    请换一个名字，例如：{prefix}2")
            else:
                print(f"    {name} 需要手动检查")
        print()

    # Planned records
    records = result.get("planned_records", [])
    if records:
        print("  DNS 计划：")
        for rec in records:
            print(f"    创建 {rec['type']} 记录 {rec['name']} -> {rec['content_masked']}")
        print()

    # Next step
    next_step = result.get("next_step", "")
    print("  下一步：")
    if next_step == "review_dns_gate":
        print("    nanobk beginner gate dns")
    elif next_step == "custom_subdomain":
        print("    请换一个子域名名字，然后重新检查")
    elif next_step == "connect_cloudflare":
        print("    nanobk cf connect")
    elif next_step == "select_zone":
        print("    nanobk setup production dns --zone your-domain.com")
    elif next_step == "manual_ip_input":
        print("    nanobk beginner ip")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "error": message, "mode": "production_dns_readiness_v2_5",
                  "version": "2.5.2", "mutation": False}
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(f"  错误：{message}", file=sys.stderr)


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Production DNS Readiness Flow"
    )
    sub = parser.add_subparsers(dest="command")

    # readiness (default)
    readiness_parser = sub.add_parser("readiness", help="Check DNS readiness (default)")
    readiness_parser.add_argument("--zone", help="Domain zone to use")
    readiness_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    readiness_parser.add_argument("--proxy-subdomain", default="proxy", help="Proxy subdomain prefix (default: proxy)")
    readiness_parser.add_argument("--web-subdomain", default="web", help="Web subdomain prefix (default: web)")
    readiness_parser.add_argument("--json", action="store_true", help="JSON output")

    # save
    save_parser = sub.add_parser("save", help="Save local setup profile")
    save_parser.add_argument("--zone", required=True, help="Domain zone to save")
    save_parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    save_parser.add_argument("--proxy-subdomain", default="proxy", help="Proxy subdomain prefix (default: proxy)")
    save_parser.add_argument("--web-subdomain", default="web", help="Web subdomain prefix (default: web)")
    save_parser.add_argument("--json", action="store_true", help="JSON output")

    # Top-level flags (for when no subcommand is given)
    parser.add_argument("--zone", help="Domain zone to use")
    parser.add_argument("--api-env", help="Path to Cloudflare api-env file")
    parser.add_argument("--proxy-subdomain", default="proxy", help="Proxy subdomain prefix (default: proxy)")
    parser.add_argument("--web-subdomain", default="web", help="Web subdomain prefix (default: web)")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    command = args.command or "readiness"
    use_json = getattr(args, "json", False)

    if command == "save":
        result = run_save(
            zone=args.zone,
            api_env=getattr(args, "api_env", None),
            proxy_subdomain=getattr(args, "proxy_subdomain", "proxy"),
            web_subdomain=getattr(args, "web_subdomain", "web"),
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

    elif command == "readiness":
        result = run_readiness(
            zone=getattr(args, "zone", None),
            api_env=getattr(args, "api_env", None),
            proxy_subdomain=getattr(args, "proxy_subdomain", "proxy"),
            web_subdomain=getattr(args, "web_subdomain", "web"),
        )
        if use_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            if result.get("ok"):
                output_text(result)
            else:
                output_error(result.get("error", "unknown error"), False)
                sys.exit(1)

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
