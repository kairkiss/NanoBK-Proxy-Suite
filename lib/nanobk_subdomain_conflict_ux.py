#!/usr/bin/env python3
"""
NanoBK Subdomain Conflict UX (v2.4.3)

Beginner-friendly proxy/web subdomain conflict handling.
Read-only. No DNS mutation. No Cloudflare mutation.
No curl/wrangler/certbot calls. No service reload/restart.

Supports safe fixture input for testing without network access.

Usage:
    python3 lib/nanobk_subdomain_conflict_ux.py [--json]
    python3 lib/nanobk_subdomain_conflict_ux.py check --domain DOMAIN [--json]
    python3 lib/nanobk_subdomain_conflict_ux.py retry --domain DOMAIN --role proxy --name custom [--json]
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_profile import load_profile, default_profile_path


# ── Constants ──────────────────────────────────────────────────────────────

DEFAULT_NODES = {
    "proxy": "proxy",
    "web": "web",
}

# ── Core logic ─────────────────────────────────────────────────────────────


def plan_subdomain(domain, desired=None, availability=None):
    """Plan subdomain records with conflict awareness.

    Args:
        domain: The base domain (e.g. "example.com")
        desired: Dict of role -> prefix, e.g. {"proxy": "proxy", "web": "web"}
        availability: Dict of hostname -> "available"|"occupied"
                      e.g. {"proxy.example.com": "available", "web.example.com": "occupied"}

    Returns:
        Safe plan dict with no secrets.
    """
    if not domain:
        return {
            "ok": False,
            "error": "未指定域名",
            "domain": None,
            "records": [],
            "blocked": True,
            "next_step": "exit_or_back",
            "safety": "read_only",
        }

    if desired is None:
        desired = dict(DEFAULT_NODES)

    if availability is None:
        availability = {}

    records = []
    any_occupied = False

    for role, prefix in desired.items():
        hostname = f"{prefix}.{domain}"
        status = availability.get(hostname, "unknown")

        if status == "available":
            action = "can_use"
        elif status == "occupied":
            action = "ask_custom_name"
            any_occupied = True
        else:
            action = "unknown"

        records.append({
            "role": role,
            "name": hostname,
            "status": status,
            "action": action,
        })

    blocked = any_occupied
    if blocked:
        next_step = "ask_custom_subdomain"
    else:
        next_step = "review_dns_plan"

    return {
        "ok": True,
        "domain": domain,
        "records": records,
        "blocked": blocked,
        "next_step": next_step,
        "safety": "read_only",
    }


def retry_subdomain(domain, role, custom_name, availability=None):
    """Check if a custom subdomain name is available.

    Args:
        domain: Base domain
        role: "proxy" or "web"
        custom_name: Custom prefix (e.g. "myproxy")
        availability: Dict of hostname -> "available"|"occupied"

    Returns:
        Safe plan dict for the custom name.
    """
    if not custom_name or not custom_name.strip():
        return {
            "ok": True,
            "domain": domain,
            "role": role,
            "custom_name": None,
            "hostname": None,
            "status": "empty",
            "action": "exit_or_back",
            "next_step": "exit_or_back",
            "safety": "read_only",
        }

    if availability is None:
        availability = {}

    hostname = f"{custom_name}.{domain}"
    status = availability.get(hostname, "unknown")

    if status == "available":
        action = "can_use"
        next_step = "review_dns_plan"
    elif status == "occupied":
        action = "still_occupied"
        next_step = "ask_custom_subdomain"
    else:
        action = "unknown"
        next_step = "ask_custom_subdomain"

    return {
        "ok": True,
        "domain": domain,
        "role": role,
        "custom_name": custom_name,
        "hostname": hostname,
        "status": status,
        "action": action,
        "next_step": next_step,
        "safety": "read_only",
    }


# ── Text renderer ──────────────────────────────────────────────────────────


def render_plan_text(plan):
    """Render subdomain plan as beginner-friendly Chinese text."""
    lines = []
    domain = plan.get("domain", "")
    records = plan.get("records", [])
    blocked = plan.get("blocked", False)

    lines.append("")
    lines.append("  ┌─ 子域名规划 ──────────────────────────────────┐")

    if not domain:
        lines.append("  │ 未指定域名")
        lines.append("  └──────────────────────────────────────────────┘")
        return "\n".join(lines)

    lines.append(f"  │ 域名：{domain}")
    lines.append("  │")

    for rec in records:
        name = rec.get("name", "")
        status = rec.get("status", "unknown")
        role = rec.get("role", "")

        if status == "available":
            lines.append(f"  │ ✓ {name} 可以使用")
        elif status == "occupied":
            lines.append(f"  │ ✗ {name} 这个名字已经被用了")
            lines.append(f"  │   不会覆盖，也不会删除已有配置")
            lines.append(f"  │   请换一个新的 {role} 子域名")
        else:
            lines.append(f"  │ ? {name} 状态未知")

    lines.append("  │")

    if blocked:
        lines.append("  │ 有子域名被占用，需要你选择新的名字。")
        lines.append("  │ 不会覆盖，也不会删除已有配置。")
    else:
        lines.append("  │ 所有子域名都可以使用！")
        lines.append("  │ 下一步：查看域名指向计划")

    lines.append("  └──────────────────────────────────────────────┘")
    lines.append("")

    return "\n".join(lines)


def render_retry_text(result):
    """Render retry result as beginner-friendly Chinese text."""
    lines = []
    hostname = result.get("hostname", "")
    status = result.get("status", "unknown")
    action = result.get("action", "unknown")
    role = result.get("role", "")

    lines.append("")

    if action == "exit_or_back":
        lines.append("  未输入新名字，返回上一步。")
    elif action == "can_use":
        lines.append(f"  ✓ {hostname} 可以使用！")
        lines.append("  下一步：查看域名指向计划")
    elif action == "still_occupied":
        lines.append(f"  ✗ {hostname} 这个名字也已经被用了")
        lines.append("  不会覆盖，也不会删除已有配置")
        lines.append(f"  请换一个新的 {role} 子域名")
    else:
        lines.append(f"  ? {hostname} 状态未知")

    lines.append("")

    return "\n".join(lines)


# ── Main ───────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Subdomain Conflict UX"
    )
    sub = parser.add_subparsers(dest="command")

    # check subcommand
    check_parser = sub.add_parser("check", help="Check subdomain availability")
    check_parser.add_argument("--domain", required=True, help="Base domain")
    check_parser.add_argument("--json", action="store_true", help="JSON output")

    # retry subcommand
    retry_parser = sub.add_parser("retry", help="Retry with custom subdomain")
    retry_parser.add_argument("--domain", required=True, help="Base domain")
    retry_parser.add_argument("--role", required=True, help="Role (proxy/web)")
    retry_parser.add_argument("--name", required=True, help="Custom subdomain name")
    retry_parser.add_argument("--json", action="store_true", help="JSON output")

    # Also accept --json at top level (no subcommand = check from profile)
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--domain", help="Base domain (for default check)")

    args = parser.parse_args()

    command = args.command or "check"
    use_json = getattr(args, "json", False)

    if command == "check":
        domain = getattr(args, "domain", None)

        # Try to get domain from profile if not specified
        if not domain:
            profile, _ = load_profile()
            if profile:
                domain = profile.get("zone_name", "")

        if not domain:
            if use_json:
                result = {
                    "ok": False,
                    "error": "未指定域名，请先连接 Cloudflare 并选择域名",
                    "domain": None,
                    "records": [],
                    "blocked": True,
                    "next_step": "exit_or_back",
                    "safety": "read_only",
                }
                print(json.dumps(result, indent=2, ensure_ascii=False))
            else:
                print("\n  未指定域名，请先连接 Cloudflare 并选择域名。\n")
            sys.exit(0)

        plan = plan_subdomain(domain)

        if use_json:
            print(json.dumps(plan, indent=2, ensure_ascii=False))
        else:
            print(render_plan_text(plan))

    elif command == "retry":
        domain = args.domain
        role = args.role
        name = args.name

        result = retry_subdomain(domain, role, name)

        if use_json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            print(render_retry_text(result))

    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
