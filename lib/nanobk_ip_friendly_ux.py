#!/usr/bin/env python3
"""
NanoBK IPv4/IPv6 Friendly UX (v2.4.4)

Beginner-friendly IP detection status renderer.
Read-only. No DNS mutation. No Cloudflare mutation.
No curl/wrangler/certbot calls. No service reload/restart.

Supports safe fixture input for testing without network access.

Usage:
    python3 lib/nanobk_ip_friendly_ux.py [--json]
    python3 lib/nanobk_ip_friendly_ux.py status [--json]
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_profile import load_profile, default_profile_path


# ── IP masking ─────────────────────────────────────────────────────────────

def _mask_ipv4(addr):
    """Mask IPv4 address for display. Keep first two octets."""
    if not addr:
        return "未检测到"
    parts = addr.split(".")
    if len(parts) == 4:
        return f"{parts[0]}.{parts[1]}.xxx.xxx"
    return "未知格式"


def _mask_ipv6(addr):
    """Mask IPv6 address for display. Keep first two groups."""
    if not addr:
        return "未检测到"
    parts = addr.split(":")
    if len(parts) >= 2:
        return f"{parts[0]}:{parts[1]}:xxxx::"
    return "未知格式"


def _is_fixture_addr(addr, family):
    """Check if an address is a documentation/test fixture address."""
    if not addr:
        return False
    if family == "ipv4":
        # RFC 5737 documentation addresses: 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24
        return (addr.startswith("192.0.2.") or
                addr.startswith("198.51.100.") or
                addr.startswith("203.0.113."))
    if family == "ipv6":
        # RFC 3849 documentation address: 2001:db8::/32
        return addr.startswith("2001:db8:")
    return False


# ── Core logic ─────────────────────────────────────────────────────────────

def plan_ip_status(ipv4=None, ipv6=None, manual_ipv4=None, manual_ipv6=None, detection_error=None):
    """Plan IP status with beginner-friendly output.

    Args:
        ipv4: Detected IPv4 address (or None)
        ipv6: Detected IPv6 address (or None)
        manual_ipv4: Manually provided IPv4 (or None)
        manual_ipv6: Manually provided IPv6 (or None)
        detection_error: Error message if detection failed (or None)

    Returns:
        Safe IP status dict with no raw IPs for non-fixture addresses.
    """
    # Handle manual input first
    if manual_ipv4 or manual_ipv6:
        ipv4_status = "manual" if manual_ipv4 else "unknown"
        ipv6_status = "manual" if manual_ipv6 else "unknown"

        # Mask non-fixture addresses
        ipv4_display = "手动填写" if manual_ipv4 else "未检测到"
        ipv6_display = "手动填写" if manual_ipv6 else "未检测到"

        if manual_ipv4 and _is_fixture_addr(manual_ipv4, "ipv4"):
            ipv4_display = manual_ipv4
        elif manual_ipv4:
            ipv4_display = _mask_ipv4(manual_ipv4)

        if manual_ipv6 and _is_fixture_addr(manual_ipv6, "ipv6"):
            ipv6_display = manual_ipv6
        elif manual_ipv6:
            ipv6_display = _mask_ipv6(manual_ipv6)

        ip_mode = "manual"
        next_step = "review_subdomain_plan"

        return {
            "ok": True,
            "ip_mode": ip_mode,
            "ipv4": {"status": ipv4_status, "display": ipv4_display},
            "ipv6": {"status": ipv6_status, "display": ipv6_display},
            "next_step": next_step,
            "safety": "read_only",
        }

    # Handle detection results
    ipv4_detected = ipv4 is not None and ipv4
    ipv6_detected = ipv6 is not None and ipv6

    if ipv4_detected and ipv6_detected:
        # Dual stack
        ipv4_display = ipv4 if _is_fixture_addr(ipv4, "ipv4") else _mask_ipv4(ipv4)
        ipv6_display = ipv6 if _is_fixture_addr(ipv6, "ipv6") else _mask_ipv6(ipv6)
        return {
            "ok": True,
            "ip_mode": "dual_stack",
            "ipv4": {"status": "detected", "display": ipv4_display},
            "ipv6": {"status": "detected", "display": ipv6_display},
            "next_step": "review_subdomain_plan",
            "safety": "read_only",
        }
    elif ipv4_detected:
        # IPv4 only
        ipv4_display = ipv4 if _is_fixture_addr(ipv4, "ipv4") else _mask_ipv4(ipv4)
        return {
            "ok": True,
            "ip_mode": "ipv4_only",
            "ipv4": {"status": "detected", "display": ipv4_display},
            "ipv6": {"status": "missing", "display": "未检测到"},
            "next_step": "review_subdomain_plan",
            "safety": "read_only",
        }
    elif ipv6_detected:
        # IPv6 only
        ipv6_display = ipv6 if _is_fixture_addr(ipv6, "ipv6") else _mask_ipv6(ipv6)
        return {
            "ok": True,
            "ip_mode": "ipv6_only",
            "ipv4": {"status": "missing", "display": "未检测到"},
            "ipv6": {"status": "detected", "display": ipv6_display},
            "next_step": "review_subdomain_plan",
            "safety": "read_only",
        }
    elif detection_error or (ipv4 is None and ipv6 is None):
        # Detection failed
        return {
            "ok": True,
            "ip_mode": "failed",
            "ipv4": {"status": "failed", "display": "未检测到"},
            "ipv6": {"status": "failed", "display": "未检测到"},
            "next_step": "manual_ip_input",
            "safety": "read_only",
        }
    else:
        # Unknown state
        return {
            "ok": True,
            "ip_mode": "unknown",
            "ipv4": {"status": "unknown", "display": "未知"},
            "ipv6": {"status": "unknown", "display": "未知"},
            "next_step": "check_network",
            "safety": "read_only",
        }


# ── Text renderer ──────────────────────────────────────────────────────────

def render_ip_text(status):
    """Render IP status as beginner-friendly Chinese text."""
    lines = []
    ip_mode = status.get("ip_mode", "unknown")
    ipv4 = status.get("ipv4", {})
    ipv6 = status.get("ipv6", {})

    lines.append("")
    lines.append("  ┌─ VPS IP 检测 ──────────────────────────────────┐")

    if ip_mode == "dual_stack":
        lines.append("  │ ✓ 已检测到 IPv4 和 IPv6")
        lines.append(f"  │   IPv4: {ipv4.get('display', '未知')}")
        lines.append(f"  │   IPv6: {ipv6.get('display', '未知')}")
        lines.append("  │")
        lines.append("  │ 下一步：查看域名指向计划")
    elif ip_mode == "ipv4_only":
        lines.append("  │ ✓ 已检测到 IPv4")
        lines.append(f"  │   IPv4: {ipv4.get('display', '未知')}")
        lines.append("  │   没有检测到 IPv6，不影响继续使用 IPv4")
        lines.append("  │")
        lines.append("  │ 下一步：查看域名指向计划")
    elif ip_mode == "ipv6_only":
        lines.append("  │ ✓ 已检测到 IPv6")
        lines.append(f"  │   IPv6: {ipv6.get('display', '未知')}")
        lines.append("  │   没有检测到 IPv4，请确认你的使用环境是否支持 IPv6")
        lines.append("  │")
        lines.append("  │ 下一步：查看域名指向计划")
    elif ip_mode == "manual":
        lines.append("  │ ✓ 手动填写的 IP 地址")
        if ipv4.get("status") == "manual":
            lines.append(f"  │   IPv4: {ipv4.get('display', '未知')}")
        if ipv6.get("status") == "manual":
            lines.append(f"  │   IPv6: {ipv6.get('display', '未知')}")
        lines.append("  │")
        lines.append("  │ 下一步：查看域名指向计划")
    elif ip_mode == "failed":
        lines.append("  │ ✗ 没有自动检测到 VPS 公网 IP")
        lines.append("  │   你可以稍后重试，或手动填写服务器 IP")
        lines.append("  │")
        lines.append("  │ 下一步：手动填写 IP 或检查网络")
    else:
        lines.append("  │ ? IP 状态未知")
        lines.append("  │   请检查 VPS 网络配置")
        lines.append("  │")
        lines.append("  │ 下一步：检查网络")

    lines.append("  └──────────────────────────────────────────────┘")
    lines.append("")

    return "\n".join(lines)


# ── Main ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK IPv4/IPv6 Friendly UX"
    )
    sub = subparsers = parser.add_subparsers(dest="command")

    # status subcommand
    status_parser = sub.add_parser("status", help="Show IP status")
    status_parser.add_argument("--json", action="store_true", help="JSON output")
    status_parser.add_argument("--ipv4", help="Detected IPv4 address")
    status_parser.add_argument("--ipv6", help="Detected IPv6 address")
    status_parser.add_argument("--manual-ipv4", help="Manual IPv4 address")
    status_parser.add_argument("--manual-ipv6", help="Manual IPv6 address")

    # Also accept --json at top level
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--ipv4", help="Detected IPv4 address")
    parser.add_argument("--ipv6", help="Detected IPv6 address")
    parser.add_argument("--manual-ipv4", help="Manual IPv4 address")
    parser.add_argument("--manual-ipv6", help="Manual IPv6 address")

    args = parser.parse_args()

    command = args.command or "status"
    use_json = getattr(args, "json", False)

    if command == "status":
        ipv4 = getattr(args, "ipv4", None)
        ipv6 = getattr(args, "ipv6", None)
        manual_ipv4 = getattr(args, "manual_ipv4", None)
        manual_ipv6 = getattr(args, "manual_ipv6", None)

        status = plan_ip_status(
            ipv4=ipv4,
            ipv6=ipv6,
            manual_ipv4=manual_ipv4,
            manual_ipv6=manual_ipv6,
        )

        if use_json:
            print(json.dumps(status, indent=2, ensure_ascii=False))
        else:
            print(render_ip_text(status))
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
