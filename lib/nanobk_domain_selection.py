#!/usr/bin/env python3
"""
NanoBK Domain Selection (v2.6.1)

Beginner-facing domain discovery and local selection. It lists domain names
only, saves the chosen domain locally, and never prints Cloudflare internal IDs,
credential paths, secrets, or raw provider responses.
"""

import argparse
import json
import os
import re
import stat
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cloudflare_product_setup import detect_cloudflare_connection
from nanobk_cf_onboarding import default_env_path
from nanobk_cf_zones import fetch_zones, parse_env_file
from nanobk_setup_profile import load_profile


VERSION = "2.6.1"
MODE = "domain_selection_v2_6"
_DOMAIN_FILE_NAME = "production-domain.json"
_DOMAIN_RE = re.compile(r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))+$")


def default_domain_dir():
    return os.path.join(os.path.expanduser("~"), ".nanobk")


def default_domain_path():
    return os.path.join(default_domain_dir(), _DOMAIN_FILE_NAME)


def ensure_domain_dir():
    path = default_domain_dir()
    os.makedirs(path, mode=0o700, exist_ok=True)
    try:
        os.chmod(path, 0o700)
    except OSError:
        pass
    return path


def _safe_domain(value):
    candidate = (value or "").strip().lower().rstrip(".")
    if not candidate or not _DOMAIN_RE.match(candidate):
        return None
    return candidate


def save_selected_domain(domain, source, verification_status):
    safe = _safe_domain(domain)
    if not safe:
        return {"ok": False, "error": "域名格式不正确。"}

    ensure_domain_dir()
    target = default_domain_path()
    payload = {
        "version": 1,
        "selected_domain": safe,
        "zone_name": safe,
        "source": source,
        "verification_status": verification_status,
        "created_by": "nanobk setup domain",
    }

    try:
        with open(target, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.chmod(target, 0o600)
    except OSError:
        return {"ok": False, "error": "保存域名失败。"}

    return {
        "ok": True,
        "selected_domain": safe,
        "saved": True,
        "source": source,
        "verification_status": verification_status,
    }


def load_selected_domain():
    target = default_domain_path()
    if os.path.isfile(target):
        try:
            mode = stat.S_IMODE(os.stat(target).st_mode)
            if mode & 0o077:
                return None, "insecure_permissions"
            with open(target, "r", encoding="utf-8") as f:
                data = json.load(f)
            selected = _safe_domain(data.get("selected_domain") or data.get("zone_name"))
            if selected:
                return {
                    "selected_domain": selected,
                    "source": data.get("source", "local_profile"),
                    "verification_status": data.get("verification_status", "unknown"),
                }, None
        except (OSError, json.JSONDecodeError):
            return None, "malformed_profile"

    profile, err = load_profile()
    if not err and isinstance(profile, dict):
        selected = _safe_domain(profile.get("zone_name", ""))
        if selected:
            return {
                "selected_domain": selected,
                "source": "existing_profile",
                "verification_status": "profile_selected_domain",
            }, None

    return None, "not_found"


def _fake_domains():
    raw = os.environ.get("NANOBK_FAKE_CF_DOMAINS", "")
    if not raw:
        return None
    domains = []
    for item in raw.split(","):
        safe = _safe_domain(item)
        if safe and safe not in domains:
            domains.append(safe)
    return domains


def _credential_env_file():
    profile, err = load_profile()
    if not err and isinstance(profile, dict):
        env_file = profile.get("api_env_path", "")
        if env_file and os.path.isfile(env_file):
            return env_file

    default_file = default_env_path()
    if os.path.isfile(default_file):
        return default_file

    return None


def discover_domains():
    fake = _fake_domains()
    if fake is not None:
        return {
            "connected": True,
            "domains": fake,
            "discovery_error": None,
        }

    connection = detect_cloudflare_connection()
    if not connection.get("connected"):
        return {
            "connected": False,
            "domains": [],
            "discovery_error": None,
        }

    env_file = _credential_env_file()
    if not env_file:
        return {
            "connected": True,
            "domains": [],
            "discovery_error": "无法读取 Cloudflare 登录信息。",
        }

    try:
        env = parse_env_file(env_file)
        zones = fetch_zones(env.get("CF_API_TOKEN", ""))
    except (FileNotFoundError, PermissionError, ValueError, RuntimeError):
        return {
            "connected": True,
            "domains": [],
            "discovery_error": "无法读取你的域名，请稍后重试，或使用 --custom 手动填写。",
        }

    domains = sorted(set(_safe_domain(z.get("name", "")) for z in zones if _safe_domain(z.get("name", ""))))
    return {
        "connected": True,
        "domains": domains,
        "discovery_error": None,
    }


def _domain_items(names):
    return [{"name": name, "source": "cloudflare"} for name in names]


def _base_result(discovery, selected=None):
    domain_profile, _err = load_selected_domain()
    selected_domain = selected
    if not selected_domain and domain_profile:
        selected_domain = domain_profile.get("selected_domain")

    connected = bool(discovery.get("connected"))
    domains = discovery.get("domains", [])
    if not connected:
        next_step = "setup_cloudflare"
    elif selected_domain:
        next_step = "review_dns"
    elif domains:
        next_step = "select_domain"
    else:
        next_step = "select_domain"

    result = {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "connected": connected,
        "domains": _domain_items(domains),
        "selected_domain": selected_domain,
        "next_step": next_step,
        "safety": "read_only",
    }
    if discovery.get("discovery_error"):
        result["discovery_status"] = "failed"
        result["message"] = discovery.get("discovery_error")
    return result


def gather_domain_selection(select_domain=None, custom_domain=None, save_single=False):
    if custom_domain:
        saved = save_selected_domain(custom_domain, "custom", "unverified_custom_domain")
        if not saved.get("ok"):
            return {
                "ok": False,
                "mode": MODE,
                "version": VERSION,
                "mutation": False,
                "dangerous_actions_executed": False,
                "error": saved.get("error", "保存域名失败。"),
                "safety": "read_only",
            }
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "mutation": False,
            "dangerous_actions_executed": False,
            "connected": False,
            "domains": [],
            "selected_domain": saved["selected_domain"],
            "saved": True,
            "source": "custom",
            "verification_status": "unverified_custom_domain",
            "next_step": "review_dns",
            "safety": "read_only",
        }

    discovery = discover_domains()
    domains = discovery.get("domains", [])

    if select_domain:
        selected = _safe_domain(select_domain)
        if not selected:
            return _error("域名格式不正确。")
        if not discovery.get("connected"):
            return _error("还没有连接 Cloudflare，请先运行 nanobk setup cloudflare")
        if selected not in domains:
            return _error("请选择已发现的域名，或使用 --custom 手动保存。")
        saved = save_selected_domain(selected, "cloudflare_discovered", "cloudflare_discovered")
        if not saved.get("ok"):
            return _error(saved.get("error", "保存域名失败。"))
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "mutation": False,
            "dangerous_actions_executed": False,
            "selected_domain": selected,
            "saved": True,
            "next_step": "review_dns",
            "safety": "read_only",
        }

    if save_single and len(domains) == 1:
        saved = save_selected_domain(domains[0], "cloudflare_discovered", "cloudflare_discovered")
        if not saved.get("ok"):
            return _error(saved.get("error", "保存域名失败。"))
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "mutation": False,
            "dangerous_actions_executed": False,
            "selected_domain": domains[0],
            "saved": True,
            "next_step": "review_dns",
            "safety": "read_only",
        }

    return _base_result(discovery)


def _error(message):
    return {
        "ok": False,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "error": message,
        "safety": "read_only",
    }


def output_text(result):
    lines = [
        "",
        "  NanoBK 选择你的域名",
        "  ─────────────────────────────────────────────",
        "",
    ]

    if not result.get("ok"):
        lines.append(f"  错误：{result.get('error', '未知错误')}")
        lines.append("")
        return "\n".join(lines)

    if result.get("saved"):
        lines.append(f"  已保存你的域名：{result.get('selected_domain')}")
        if result.get("verification_status") == "unverified_custom_domain":
            lines.append("  状态：手动填写，后续还会检查。")
        lines.append("  下一步：nanobk setup production dns")
        lines.append("")
        return "\n".join(lines)

    if not result.get("connected"):
        lines.append("  还没有连接 Cloudflare，请先运行 nanobk setup cloudflare")
        lines.append("")
        return "\n".join(lines)

    if result.get("discovery_status") == "failed":
        lines.append(f"  {result.get('message')}")
        lines.append("  你也可以运行：nanobk setup domain --custom example.com")
        lines.append("")
        return "\n".join(lines)

    domains = result.get("domains", [])
    if len(domains) == 1:
        name = domains[0]["name"]
        lines.append(f"  我发现了你的域名：{name}")
        lines.append(f"  如需使用它，请运行：nanobk setup domain --select {name}")
    elif len(domains) > 1:
        lines.append("  我发现了这些域名：")
        lines.append("")
        for idx, item in enumerate(domains, 1):
            lines.append(f"  {idx}. {item['name']}")
        lines.append("")
        lines.append("  请选择一个，例如：nanobk setup domain --select example.com")
    else:
        lines.append("  没有发现可用域名。")
        lines.append("  你也可以运行：nanobk setup domain --custom example.com")

    selected = result.get("selected_domain")
    if selected:
        lines.append("")
        lines.append(f"  当前已保存：{selected}")
    lines.append("")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description="NanoBK domain selection")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--select", help="Select a discovered domain")
    parser.add_argument("--custom", help="Save a custom domain without discovery")
    parser.add_argument("--save", action="store_true", help="Save the only discovered domain")
    args = parser.parse_args(sys.argv[1:] if argv is None else argv)

    if args.select and args.custom:
        result = _error("--select 和 --custom 不能同时使用。")
    else:
        result = gather_domain_selection(
            select_domain=args.select,
            custom_domain=args.custom,
            save_single=args.save,
        )

    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(output_text(result))

    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
