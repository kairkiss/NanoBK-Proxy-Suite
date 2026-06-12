#!/usr/bin/env python3
"""
NanoBK DNS Apply Engine with Confirmation

Gated DNS creation engine. By default, shows plan-only.
Real DNS mutation requires explicit --apply and exact confirmation phrase.

Read-only plan by default. Mutation only with --apply + exact confirm.

Usage:
    python3 lib/nanobk_dns_apply_engine.py [--zone DOMAIN] [--api-env PATH] [--json]
    python3 lib/nanobk_dns_apply_engine.py --apply --confirm "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS" [--zone DOMAIN] [--api-env PATH] [--json]

Test hooks:
    NANOBK_CF_ZONES_FAKE_RESPONSE=/path/to/zones.json
    NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP=/path/to/map.json
    NANOBK_DNS_APPLY_FAKE_PREFLIGHT_RESPONSE=/path/to/preflight.json
    NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE=/path/to/create.json
    NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE=/path/to/verify.json
    NANOBK_DNS_APPLY_FAKE_CAPTURE_PAYLOAD=/tmp/payload.jsonl
    NANOBK_TEST_DETECTED_IPV4=203.0.113.10
    NANOBK_TEST_DETECTED_IPV6=2001:db8::10
"""

import argparse
import ipaddress
import json
import os
import sys
import urllib.request
import urllib.error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cf_zones import parse_env_file, fetch_zones, mask_domain
from nanobk_cf_dns_availability import (
    validate_zone, load_fake_map, fetch_records_for_node, analyze_records,
)
from nanobk_ip_detect import mask_ipv4, mask_ipv6, run_detect
from nanobk_domain_planner import run_plan, lookup_zone_id, mask_ip


# ── Constants ────────────────────────────────────────────────────────────────

_CONFIRM_PHRASE = "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"
_ALLOWED_HOSTNAMES = {"proxy", "web"}
_ALLOWED_TYPES = {"A", "AAAA"}
_DANGEROUS_HOSTNAMES = {
    "", "www", "api", "mail", "cdn", "ns", "mx", "ftp", "smtp",
    "pop", "imap", "ssh", "rdp", "admin", "test", "staging",
}
_NANOBK_MARKER = "managed-by=nanobk"


# ── IP validation ────────────────────────────────────────────────────────────

def is_valid_ipv4(addr):
    """Check if string is a valid IPv4 address."""
    if not addr:
        return False
    try:
        ipaddress.IPv4Address(addr)
        return True
    except (ipaddress.AddressValueError, ValueError):
        return False


def is_valid_ipv6(addr):
    """Check if string is a valid IPv6 address."""
    if not addr:
        return False
    try:
        ipaddress.IPv6Address(addr)
        return True
    except (ipaddress.AddressValueError, ValueError):
        return False


# ── Safety validation ────────────────────────────────────────────────────────

def validate_apply_target(record):
    """Validate that a record is safe to create. Returns (ok, error)."""
    name = record.get("name", "")
    rec_type = record.get("type", "")
    zone = record.get("zone_name", "")

    if not zone:
        return False, "missing zone_name"

    # Extract hostname prefix
    suffix = "." + zone
    if name == zone:
        return False, f"不允许创建根域名记录: {name}"
    if not name.endswith(suffix):
        return False, f"hostname 不属于 zone: {name}"

    hostname = name[:-len(suffix)]
    if not hostname:
        return False, f"不允许创建根域名记录: {name}"

    # Check dangerous hostnames
    if hostname in _DANGEROUS_HOSTNAMES:
        return False, f"不允许创建危险 hostname: {hostname}"

    # Check allowed hostnames
    if hostname not in _ALLOWED_HOSTNAMES:
        return False, f"只允许创建 proxy 或 web 子域名: {hostname}"

    # Check record type
    if rec_type not in _ALLOWED_TYPES:
        return False, f"只允许 A 或 AAAA 记录: {rec_type}"

    return True, None


# ── Resolve real content from IP detection ───────────────────────────────────

def resolve_content(rec_type):
    """Resolve real DNS record content from IP detection. Returns (content, error)."""
    try:
        ip_result = run_detect()
    except Exception as e:
        return None, f"IP 检测失败: {e}"

    ipv4 = ip_result.get("ipv4", {})
    ipv6 = ip_result.get("ipv6", {})

    if rec_type == "A":
        if ipv4.get("status") == "detected" and ipv4.get("address"):
            addr = ipv4["address"]
            if is_valid_ipv4(addr):
                return addr, None
            return None, f"检测到的 IPv4 地址无效: {addr}"
        return None, "未检测到可用的 IPv4 地址"

    elif rec_type == "AAAA":
        if ipv6.get("status") == "detected" and ipv6.get("address"):
            addr = ipv6["address"]
            if is_valid_ipv6(addr):
                return addr, None
            return None, f"检测到的 IPv6 地址无效: {addr}"
        return None, "未检测到可用的 IPv6 地址"

    return None, f"不支持的记录类型: {rec_type}"


# ── Payload capture ──────────────────────────────────────────────────────────

def capture_payload(payload_dict):
    """Write payload to capture file if hook is set. Test-only."""
    capture_path = os.environ.get("NANOBK_DNS_APPLY_FAKE_CAPTURE_PAYLOAD")
    if not capture_path:
        return
    try:
        with open(capture_path, "a") as f:
            f.write(json.dumps(payload_dict) + "\n")
    except OSError:
        pass


# ── Cloudflare DNS create ────────────────────────────────────────────────────

def create_dns_record_real(token, zone_id, name, rec_type, content, ttl=1):
    """Create a DNS record via Cloudflare API. Returns (result_dict, error)."""
    url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records"
    payload = json.dumps({
        "type": rec_type,
        "name": name,
        "content": content,
        "ttl": ttl,
        "comment": _NANOBK_MARKER,
    }).encode("utf-8")

    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        try:
            data = json.loads(body)
            errors = data.get("errors", [])
            msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or f"HTTP {e.code}"
            return None, f"Cloudflare API error: {msg}"
        except json.JSONDecodeError:
            return None, f"Cloudflare API error: HTTP {e.code}"
    except urllib.error.URLError as e:
        return None, f"Cloudflare API connection error: {e.reason}"

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return None, "Cloudflare API returned invalid JSON"

    if not data.get("success", False):
        errors = data.get("errors", [])
        msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or "unknown error"
        return None, f"Cloudflare API error: {msg}"

    return data.get("result", {}), None


def create_dns_record_fake(fake_path):
    """Load fake create response."""
    try:
        with open(fake_path, "r") as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError) as e:
        return None, f"Cannot read fake create response: {e}"

    if not data.get("success", False):
        errors = data.get("errors", [])
        msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or "unknown error"
        return None, f"Cloudflare API error: {msg}"

    return data.get("result", {}), None


def create_dns_record(token, zone_id, name, rec_type, content, ttl=1):
    """Create DNS record using real or fake transport. Captures payload for testing."""
    # Capture payload for test verification
    capture_payload({
        "name": name,
        "type": rec_type,
        "content": content,
        "ttl": ttl,
        "comment": _NANOBK_MARKER,
    })

    fake_path = os.environ.get("NANOBK_DNS_APPLY_FAKE_CREATE_RESPONSE")
    if fake_path:
        return create_dns_record_fake(fake_path)
    return create_dns_record_real(token, zone_id, name, rec_type, content, ttl)


# ── Cloudflare DNS verify ────────────────────────────────────────────────────

def verify_dns_record_real(token, zone_id, hostname):
    """Verify a DNS record exists with NanoBK marker. Returns (found, error)."""
    url = f"https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records?name={hostname}&per_page=100"
    req = urllib.request.Request(url, method="GET")
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return False, f"Cloudflare API error: HTTP {e.code}"
    except urllib.error.URLError as e:
        return False, f"Cloudflare API connection error: {e.reason}"

    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        return False, "Cloudflare API returned invalid JSON"

    if not data.get("success", False):
        errors = data.get("errors", [])
        msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or "unknown error"
        return False, f"Cloudflare API error: {msg}"

    records = data.get("result", [])
    for rec in records:
        comment = rec.get("comment", "") or ""
        if _NANOBK_MARKER in comment:
            return True, None

    return False, None


def verify_dns_record_fake(fake_path):
    """Load fake verify response."""
    try:
        with open(fake_path, "r") as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError) as e:
        return False, f"Cannot read fake verify response: {e}"

    if not data.get("success", False):
        return False, "verify failed"

    records = data.get("result", [])
    for rec in records:
        comment = rec.get("comment", "") or ""
        if _NANOBK_MARKER in comment:
            return True, None

    return False, None


def verify_dns_record(token, zone_id, hostname):
    """Verify DNS record using real or fake transport."""
    fake_path = os.environ.get("NANOBK_DNS_APPLY_FAKE_VERIFY_RESPONSE")
    if fake_path:
        return verify_dns_record_fake(fake_path)
    return verify_dns_record_real(token, zone_id, hostname)


# ── Preflight recheck ────────────────────────────────────────────────────────

def preflight_recheck(token, zone_id, zone_name, node, fake_map=None):
    """Re-check availability before creation. Returns (available, error).

    Supports NANOBK_DNS_APPLY_FAKE_PREFLIGHT_RESPONSE for testing.
    """
    preflight_fake = os.environ.get("NANOBK_DNS_APPLY_FAKE_PREFLIGHT_RESPONSE")
    if preflight_fake:
        return _preflight_recheck_fake(preflight_fake, node)

    try:
        records = fetch_records_for_node(node, zone_name, zone_id, token, fake_map)
        analysis = analyze_records(records, zone_name)
        return analysis.get("available", False), None
    except RuntimeError as e:
        return False, f"预检失败: {e}"


def _preflight_recheck_fake(fake_path, node):
    """Load fake preflight response. Expects JSON with node->result mapping."""
    try:
        with open(fake_path, "r") as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError) as e:
        return False, f"Cannot read fake preflight response: {e}"

    node_data = data.get(node)
    if node_data is None:
        return False, f"Node '{node}' not found in fake preflight response"

    if not node_data.get("success", False):
        errors = node_data.get("errors", [])
        msg = "; ".join(str(e.get("message", "unknown")) for e in errors) or "unknown error"
        return False, f"Preflight API error: {msg}"

    records = node_data.get("result", [])
    if records:
        # Records exist => not available
        return False, None

    return True, None


# ── Main apply engine ────────────────────────────────────────────────────────

def run_apply_engine(zone_override=None, api_env_override=None,
                     apply_mode=False, confirm_phrase=None, json_mode=False):
    """Run the DNS apply engine. Returns result dict."""

    # Step 1: Get plan from planner
    plan = run_plan(zone_override=zone_override, api_env_override=api_env_override)

    if not plan.get("ok"):
        return {
            "ok": False,
            "mode": "blocked",
            "apply_executed": False,
            "attempted_create": False,
            "mutation": False,
            "error": plan.get("error", "planning failed"),
        }

    zone_name = plan.get("zone_name", "")
    plan_records = plan.get("records", [])

    # Step 2: Filter to safe-to-create records
    safe_records = []
    for rec in plan_records:
        rec["zone_name"] = zone_name
        ok, err = validate_apply_target(rec)
        if ok and rec.get("available") and rec.get("planned"):
            safe_records.append(rec)

    # Step 3: Plan-only mode
    if not apply_mode:
        return _build_plan_only_result(zone_name, safe_records, plan)

    # Step 4: Apply mode — check confirmation
    if confirm_phrase != _CONFIRM_PHRASE:
        return {
            "ok": False,
            "mode": "blocked",
            "apply_executed": False,
            "attempted_create": False,
            "mutation": False,
            "blocked_reason": "missing exact confirmation",
            "hint": f'需要输入: --confirm "{_CONFIRM_PHRASE}"',
        }

    # Step 5: Parse env for token/zone_id
    api_env_path = api_env_override
    if not api_env_path:
        from nanobk_setup_profile import load_profile
        profile, _ = load_profile()
        if profile:
            api_env_path = profile.get("api_env_path")

    if not api_env_path:
        return {"ok": False, "mode": "blocked", "apply_executed": False, "attempted_create": False,
                "mutation": False, "error": "未找到 API 配置"}

    try:
        env = parse_env_file(api_env_path)
    except (FileNotFoundError, PermissionError, ValueError) as e:
        return {"ok": False, "mode": "blocked", "apply_executed": False, "attempted_create": False,
                "mutation": False, "error": str(e)}

    token = env.get("CF_API_TOKEN")
    if not token:
        return {"ok": False, "mode": "blocked", "apply_executed": False, "attempted_create": False,
                "mutation": False, "error": "CF_API_TOKEN not found"}

    # Look up zone_id
    zone_id, zone_err = lookup_zone_id(token, zone_name)
    if zone_err:
        return {"ok": False, "mode": "blocked", "apply_executed": False, "attempted_create": False,
                "mutation": False, "error": zone_err}

    # Step 6: Load fake map for preflight
    try:
        fake_map = load_fake_map()
    except RuntimeError as e:
        return {"ok": False, "mode": "blocked", "apply_executed": False, "attempted_create": False,
                "mutation": False, "error": str(e)}

    # Step 7: Resolve real content for each safe record
    content_map = {}
    for rec in safe_records:
        rec_type = rec.get("type", "A")
        content, content_err = resolve_content(rec_type)
        if content_err:
            return {
                "ok": False,
                "mode": "blocked",
                "apply_executed": False,
                "attempted_create": False,
                "mutation": False,
                "error": f"无法解析 {rec.get('name', '?')} 的 DNS 内容: {content_err}",
            }
        content_map[rec.get("name", "")] = content

    # Step 8: Preflight recheck + create + verify
    created_records = []
    created_count = 0
    verified_count = 0
    any_mutation = False
    any_attempted = False

    for rec in safe_records:
        hostname = rec.get("name", "")
        rec_type = rec.get("type", "A")
        content = content_map.get(hostname, "")
        node = rec.get("role", "")

        # Preflight recheck
        available, preflight_err = preflight_recheck(token, zone_id, zone_name, node, fake_map)
        if not available:
            created_records.append({
                "name": hostname,
                "type": rec_type,
                "content_masked": rec.get("content_masked", "***"),
                "created": False,
                "verified": False,
                "error": preflight_err or "子域名在预检时已不可用（可能已被占用）",
            })
            continue

        # Validate content is non-empty and valid
        if not content:
            created_records.append({
                "name": hostname,
                "type": rec_type,
                "content_masked": rec.get("content_masked", "***"),
                "created": False,
                "verified": False,
                "error": "DNS 内容为空，无法创建",
            })
            continue

        if rec_type == "A" and not is_valid_ipv4(content):
            created_records.append({
                "name": hostname,
                "type": rec_type,
                "content_masked": rec.get("content_masked", "***"),
                "created": False,
                "verified": False,
                "error": f"IPv4 地址无效: {content}",
            })
            continue

        if rec_type == "AAAA" and not is_valid_ipv6(content):
            created_records.append({
                "name": hostname,
                "type": rec_type,
                "content_masked": rec.get("content_masked", "***"),
                "created": False,
                "verified": False,
                "error": f"IPv6 地址无效: {content}",
            })
            continue

        # Create
        any_attempted = True
        result, create_err = create_dns_record(token, zone_id, hostname, rec_type, content)
        any_mutation = True

        if create_err:
            created_records.append({
                "name": hostname,
                "type": rec_type,
                "content_masked": rec.get("content_masked", "***"),
                "created": False,
                "verified": False,
                "error": create_err,
            })
            continue

        created_count += 1

        # Verify
        verified, verify_err = verify_dns_record(token, zone_id, hostname)
        if verified:
            verified_count += 1

        created_records.append({
            "name": hostname,
            "type": rec_type,
            "content_masked": rec.get("content_masked", "***"),
            "created": True,
            "verified": verified,
            "record_id_printed": False,
        })

    # Determine overall status
    all_verified = verified_count == len(safe_records) and len(safe_records) > 0

    if all_verified:
        ok = True
        mode = "applied"
    elif created_count > 0:
        ok = False
        mode = "partial"
    elif any_attempted:
        ok = False
        mode = "failed"
    else:
        ok = False
        mode = "failed"

    return {
        "ok": ok,
        "mode": mode,
        "apply_executed": True,
        "attempted_create": any_attempted,
        "mutation": any_mutation,
        "created_count": created_count,
        "verified_count": verified_count,
        "records": created_records,
    }


def _build_plan_only_result(zone_name, safe_records, plan):
    """Build plan-only result dict."""
    records = []
    for rec in safe_records:
        records.append({
            "name": rec.get("name", ""),
            "type": rec.get("type", "A"),
            "content_masked": rec.get("content_masked", "***"),
            "available": True,
            "planned": True,
            "safe_to_create": True,
        })

    return {
        "ok": True,
        "mode": "plan",
        "apply_executed": False,
        "attempted_create": False,
        "mutation": False,
        "zone_name": zone_name,
        "records": records,
        "next_command": f'nanobk setup dns apply --apply --confirm "{_CONFIRM_PHRASE}"',
    }


# ── Output ───────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable result."""
    mode = result.get("mode", "unknown")

    if mode == "plan":
        _output_plan_text(result)
    elif mode == "applied":
        _output_applied_text(result)
    elif mode == "partial":
        _output_partial_text(result)
    elif mode == "blocked":
        _output_blocked_text(result)
    else:
        _output_failed_text(result)


def _output_plan_text(result):
    print()
    print("  NanoBK DNS 创建预案")
    print()
    records = result.get("records", [])
    if records:
        print("  将要创建：")
        for r in records:
            print(f"    * {r.get('name', '***')} {r.get('type', 'A')} -> {r.get('content_masked', '***')}")
    else:
        print("  没有可以安全创建的 DNS 记录。")
    print()
    print("  安全检查：")
    print("    * 已确认子域名可用")
    print("    * 不会覆盖已有记录")
    print("    * 不会删除任何记录")
    print("    * 当前只是预案，未创建 DNS")
    print()
    print("  真正创建请执行：")
    print(f'    nanobk setup dns apply --apply --confirm "{_CONFIRM_PHRASE}"')
    print()


def _output_applied_text(result):
    print()
    print("  NanoBK DNS 创建完成")
    print()
    records = result.get("records", [])
    if records:
        print("  已创建：")
        for r in records:
            if r.get("created"):
                print(f"    * {r.get('name', '***')} {r.get('type', 'A')} -> {r.get('content_masked', '***')}")
    print()
    print("  已完成验证：")
    for r in records:
        if r.get("verified"):
            print(f"    * {r.get('name', '***')}：NanoBK 记录存在")
        elif r.get("created"):
            print(f"    * {r.get('name', '***')}：创建成功但验证未通过，请手动检查")
        else:
            print(f"    * {r.get('name', '***')}：创建失败 — {r.get('error', '未知错误')}")
    print()
    print("  下一步：")
    print("    v2.3.5 将进入证书自动化。")
    print()


def _output_partial_text(result):
    print()
    print("  NanoBK DNS 创建部分完成")
    print()
    records = result.get("records", [])
    for r in records:
        status = "✓" if r.get("created") else "✗"
        print(f"    {status} {r.get('name', '***')}：{r.get('error', '已创建') if not r.get('created') else '已创建'}")
    print()
    print("  部分记录创建失败，请手动检查后重试。")
    print()


def _output_blocked_text(result):
    print()
    print("  DNS 创建被阻止")
    print()
    reason = result.get("blocked_reason") or result.get("error", "未知原因")
    print(f"  原因：{reason}")
    hint = result.get("hint", "")
    if hint:
        print(f"  提示：{hint}")
    print()


def _output_failed_text(result):
    print()
    print("  DNS 创建失败")
    print()
    print(f"  错误：{result.get('error', '未知错误')}")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {"ok": False, "mode": "blocked", "apply_executed": False,
                  "attempted_create": False, "mutation": False, "error": message}
        print(json.dumps(result, indent=2))
    else:
        print(f"  错误：{message}", file=sys.stderr)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK DNS Apply Engine with Confirmation"
    )
    parser.add_argument("--zone", help="Domain zone (overrides profile)")
    parser.add_argument("--api-env", help="Path to Cloudflare env file (overrides profile)")
    parser.add_argument("--apply", action="store_true", help="Actually create DNS records")
    parser.add_argument("--confirm", help="Exact confirmation phrase")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    result = run_apply_engine(
        zone_override=args.zone,
        api_env_override=args.api_env,
        apply_mode=args.apply,
        confirm_phrase=args.confirm,
        json_mode=args.json,
    )

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)

    if not result.get("ok"):
        sys.exit(1)


if __name__ == "__main__":
    main()
