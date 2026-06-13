#!/usr/bin/env python3
"""
NanoBK Production DNS Apply (v2.6.2)

Productized, exact-gated DNS creation for proxy/web production hostnames.
Dry-run is read-only. Real Cloudflare record creation requires the exact
confirmation phrase and an explicit real-apply environment guard, or the
test-only fake create hook.
"""

import argparse
import ipaddress
import json
import os
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cf_dns_availability import (
    analyze_records,
    fetch_records_for_node,
    load_fake_map,
    validate_node,
)
from nanobk_cf_zones import fetch_zones, parse_env_file
from nanobk_domain_selection import load_selected_domain
from nanobk_ip_detect import mask_ipv4, mask_ipv6, run_detect
from nanobk_setup_profile import load_profile


VERSION = "2.6.2"
MODE = "production_dns_apply_v2_6"
EXACT_PHRASE_DNS = "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"
NANOBK_MARKER = "managed-by=nanobk"

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


def _api_env_path():
    profile, err = load_profile()
    if not err and profile and profile.get("api_env_path"):
        return profile.get("api_env_path")

    default_path = os.path.join(os.path.expanduser("~"), ".nanobk", "cloudflare.env")
    if os.path.isfile(default_path):
        return default_path

    return None


def _cloudflare_context():
    if os.environ.get("NANOBK_FAKE_CF_CONNECTED") == "1":
        return {
            "connected": True,
            "token": "fake-token",
            "zone_id": "fake-zone",
            "fake": True,
        }, None

    path = _api_env_path()
    if not path:
        return None, "还没有连接 Cloudflare，请先运行 nanobk setup cloudflare"

    try:
        env = parse_env_file(path)
    except (FileNotFoundError, PermissionError, ValueError):
        return None, "Cloudflare 登录信息不可用，请重新运行 nanobk setup cloudflare"

    token = env.get("CF_API_TOKEN")
    if not token:
        return None, "Cloudflare 登录信息不可用，请重新运行 nanobk setup cloudflare"

    return {
        "connected": True,
        "token": token,
        "zone_id": env.get("CF_ZONE_ID"),
        "fake": False,
    }, None


def _resolve_zone_id(ctx, domain):
    if ctx.get("fake"):
        return "fake-zone", None
    if ctx.get("zone_id"):
        return ctx.get("zone_id"), None

    try:
        zones = fetch_zones(ctx["token"])
    except RuntimeError:
        return None, "无法读取你的域名，请检查 Cloudflare 登录信息"

    for zone in zones:
        if zone.get("name") == domain:
            return zone.get("id"), None

    return None, "Cloudflare 中没有找到已选择的域名"


def _valid_ip(value, family):
    if not value:
        return None
    try:
        if family == "ipv4":
            return str(ipaddress.IPv4Address(value))
        return str(ipaddress.IPv6Address(value))
    except (ipaddress.AddressValueError, ValueError):
        return None


def _detect_ips():
    fake_v4 = _valid_ip(os.environ.get("NANOBK_FAKE_VPS_IPV4", ""), "ipv4")
    fake_v6 = _valid_ip(os.environ.get("NANOBK_FAKE_VPS_IPV6", ""), "ipv6")
    if fake_v4 or fake_v6:
        return fake_v4, fake_v6, None

    try:
        detected = run_detect()
    except Exception:
        return None, None, "无法检测你的服务器 IP，请检查 VPS 网络"

    ipv4 = None
    ipv6 = None
    if detected.get("ipv4", {}).get("status") == "detected":
        ipv4 = _valid_ip(detected.get("ipv4", {}).get("address"), "ipv4")
    if detected.get("ipv6", {}).get("status") == "detected":
        ipv6 = _valid_ip(detected.get("ipv6", {}).get("address"), "ipv6")

    if not ipv4 and not ipv6:
        return None, None, "没有检测到可用的服务器 IPv4 或 IPv6"
    return ipv4, ipv6, None


def _planned_records(domain, proxy_subdomain, web_subdomain, ipv4, ipv6):
    records = []
    for node in (proxy_subdomain, web_subdomain):
        hostname = f"{node}.{domain}"
        if ipv4:
            records.append({
                "name": hostname,
                "type": "A",
                "content": ipv4,
                "content_masked": mask_ipv4(ipv4),
                "node": node,
            })
        if ipv6:
            records.append({
                "name": hostname,
                "type": "AAAA",
                "content": ipv6,
                "content_masked": mask_ipv6(ipv6),
                "node": node,
            })
    return records


def _fake_existing_nodes():
    raw = os.environ.get("NANOBK_FAKE_DNS_EXISTING", "")
    return {item.strip().lower() for item in raw.split(",") if item.strip()}


def _occupied_nodes(domain, nodes, ctx, zone_id):
    fake_existing = _fake_existing_nodes()
    if fake_existing:
        return {node for node in nodes if node in fake_existing}, None

    if ctx.get("fake"):
        return set(), None

    try:
        fake_map = load_fake_map()
    except RuntimeError:
        fake_map = None

    occupied = set()
    for node in nodes:
        try:
            records = fetch_records_for_node(node, domain, zone_id, ctx["token"], fake_map)
            analysis = analyze_records(records, domain)
        except RuntimeError:
            return set(), "无法检查域名指向是否已存在"
        if not analysis.get("available"):
            occupied.add(node)
    return occupied, None


def _public_record(record):
    return {
        "name": record["name"],
        "type": record["type"],
        "content_masked": record["content_masked"],
    }


def _create_record_real(ctx, zone_id, record):
    if os.environ.get("NANOBK_ALLOW_REAL_CF_DNS_APPLY") != "1":
        return None, "真实 Cloudflare 创建需要先设置 NANOBK_ALLOW_REAL_CF_DNS_APPLY=1"

    url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records"
    payload = json.dumps({
        "type": record["type"],
        "name": record["name"],
        "content": record["content"],
        "ttl": 1,
        "comment": NANOBK_MARKER,
    }).encode("utf-8")
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Authorization", f"Bearer {ctx['token']}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        try:
            data = json.loads(exc.read().decode("utf-8", errors="replace"))
            errors = data.get("errors", [])
            msg = "; ".join(str(item.get("message", "unknown")) for item in errors) or f"HTTP {exc.code}"
        except json.JSONDecodeError:
            msg = f"HTTP {exc.code}"
        return None, f"Cloudflare 创建失败: {msg}"
    except urllib.error.URLError:
        return None, "Cloudflare 连接失败"

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return None, "Cloudflare 返回内容无法读取"

    if not data.get("success"):
        errors = data.get("errors", [])
        msg = "; ".join(str(item.get("message", "unknown")) for item in errors) or "unknown"
        return None, f"Cloudflare 创建失败: {msg}"

    return data.get("result", {}), None


def _create_record(ctx, zone_id, record):
    if os.environ.get("NANOBK_FAKE_DNS_CREATE") == "1":
        return {"name": record["name"], "type": record["type"]}, None
    return _create_record_real(ctx, zone_id, record)


def build_plan(proxy_subdomain="proxy", web_subdomain="web", dry_run=True):
    proxy_err = validate_node(proxy_subdomain)
    web_err = validate_node(web_subdomain)
    if proxy_err or web_err:
        return _refusal("子域名格式不正确，请使用安全的单段名称", "custom_subdomain", dry_run)

    domain = _safe_domain()
    if not domain:
        return _refusal("还没有选择你的域名，请先运行 nanobk setup domain", "select_domain", dry_run)

    ctx, cf_err = _cloudflare_context()
    if cf_err:
        return _refusal(cf_err, "setup_cloudflare", dry_run)

    ipv4, ipv6, ip_err = _detect_ips()
    if ip_err:
        return _refusal(ip_err, "fix_vps_network", dry_run)

    zone_id, zone_err = _resolve_zone_id(ctx, domain)
    if zone_err:
        return _refusal(zone_err, "setup_cloudflare", dry_run)

    nodes = [proxy_subdomain, web_subdomain]
    occupied, occupied_err = _occupied_nodes(domain, nodes, ctx, zone_id)
    if occupied_err:
        return _refusal(occupied_err, "check_cloudflare", dry_run)
    if occupied:
        names = ", ".join(f"{node}.{domain}" for node in sorted(occupied))
        return {
            **_refusal(f"这些域名指向已存在：{names}。请换一个自定义子域名。", "custom_subdomain", dry_run),
            "selected_domain": domain,
            "proxy_subdomain": proxy_subdomain,
            "web_subdomain": web_subdomain,
            "planned_records": [],
        }

    records = _planned_records(domain, proxy_subdomain, web_subdomain, ipv4, ipv6)
    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "dry_run": bool(dry_run),
        "mutation": False,
        "dangerous_actions_executed": False,
        "selected_domain": domain,
        "proxy_subdomain": proxy_subdomain,
        "web_subdomain": web_subdomain,
        "planned_records": [_public_record(record) for record in records],
        "_private_records": records,
        "_ctx": ctx,
        "_zone_id": zone_id,
        "blocked": False,
        "next_step": "confirm_dns_apply" if dry_run else "create_dns",
        "safety": "read_only",
    }


def apply_records(confirm_phrase, proxy_subdomain="proxy", web_subdomain="web"):
    if confirm_phrase != EXACT_PHRASE_DNS:
        return _refusal("需要完整输入安全确认短语。", "confirm_dns_apply", False)

    plan = build_plan(proxy_subdomain, web_subdomain, dry_run=False)
    if not plan.get("ok"):
        return plan

    created = []
    skipped = []
    for record in plan.get("_private_records", []):
        _result, err = _create_record(plan["_ctx"], plan["_zone_id"], record)
        if err:
            skipped.append({"name": record["name"], "type": record["type"], "reason": err})
            continue
        created.append({"name": record["name"], "type": record["type"]})

    if skipped:
        return {
            "ok": False,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": bool(created),
            "dangerous_actions_executed": bool(created),
            "confirmed": True,
            "created_records": created,
            "skipped_records": skipped,
            "blocked": True,
            "error": "部分域名指向没有创建成功。",
            "next_step": "check_cloudflare",
            "safety": "confirmed_cloudflare_dns_create" if created else "read_only",
        }

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "dry_run": False,
        "mutation": True,
        "dangerous_actions_executed": True,
        "confirmed": True,
        "created_records": created,
        "skipped_records": [],
        "blocked": False,
        "next_step": "setup_worker",
        "safety": "confirmed_cloudflare_dns_create",
    }


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
            "  NanoBK 域名指向检查",
            "  ─────────────────────────────────────────────",
            "",
            "  当前不会创建 DNS。",
            "",
            "  我将准备：",
            "",
        ])
        shown = []
        for item in result.get("planned_records", []):
            if item["name"] not in shown:
                lines.append(f"  {item['name']} -> 你的服务器 IP")
                shown.append(item["name"])
        lines.extend([
            "",
            "  如果确认无误，再运行：",
            f'  nanobk setup production dns apply --confirm "{EXACT_PHRASE_DNS}"',
            "",
        ])
        return "\n".join(lines)

    if result.get("ok") and not result.get("dry_run"):
        lines.extend([
            "  NanoBK 域名指向",
            "  ─────────────────────────────────────────────",
            "",
            "  已通过安全确认。",
            "  正在创建域名指向……",
            "",
            "  完成：",
        ])
        names = []
        for item in result.get("created_records", []):
            if item["name"] not in names:
                lines.append(f"  {item['name']}")
                names.append(item["name"])
        lines.extend([
            "",
            "  下一步：",
            "  nanobk setup production worker",
            "",
        ])
        return "\n".join(lines)

    lines.extend([
        "  NanoBK 域名指向",
        "  ─────────────────────────────────────────────",
        "",
        f"  暂时不能继续：{result.get('error', '未知原因')}",
    ])
    next_step = result.get("next_step")
    if next_step == "custom_subdomain":
        lines.append("  请换一个自定义子域名，例如 --proxy-subdomain proxy2。")
    elif next_step == "select_domain":
        lines.append("  请先运行：nanobk setup domain")
    elif next_step == "setup_cloudflare":
        lines.append("  请先运行：nanobk setup cloudflare")
    elif next_step == "confirm_dns_apply":
        lines.append(f'  请使用：--confirm "{EXACT_PHRASE_DNS}"')
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
        result = _refusal(f"{blocked} 不适用于这个受控命令。", "confirm_dns_apply", "--dry-run" in argv)
        if json_requested:
            print(json.dumps(public_result(result), indent=2, ensure_ascii=False))
        else:
            print(output_text(result), file=sys.stderr)
        return 1

    parser = argparse.ArgumentParser(description="NanoBK production DNS apply")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--dry-run", action="store_true", help="Show plan only")
    parser.add_argument("--confirm", help="Exact safety confirmation phrase")
    parser.add_argument("--proxy-subdomain", default="proxy", help="Proxy subdomain")
    parser.add_argument("--web-subdomain", default="web", help="Web subdomain")
    args = parser.parse_args(argv)

    if args.dry_run:
        result = build_plan(args.proxy_subdomain, args.web_subdomain, dry_run=True)
    else:
        result = apply_records(args.confirm, args.proxy_subdomain, args.web_subdomain)

    if args.json:
        print(json.dumps(public_result(result), indent=2, ensure_ascii=False))
    else:
        stream = sys.stdout if result.get("ok") else sys.stderr
        print(output_text(result), file=stream)

    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
