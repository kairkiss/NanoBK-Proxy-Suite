#!/usr/bin/env python3
"""
NanoBK Cloudflare Product Setup (v2.6.1)

Beginner-facing Cloudflare setup status. This command detects whether NanoBK
already has Cloudflare login information and points users to the existing
connect flow when needed. It never prints credential paths or secrets.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_profile import load_profile
from nanobk_cf_onboarding import default_env_path, validate_env_permissions
from nanobk_cf_zones import parse_env_file


VERSION = "2.6.1"
MODE = "cloudflare_setup_v2_6"


def _candidate_sources():
    sources = []

    profile, err = load_profile()
    if not err and isinstance(profile, dict):
        env_file = profile.get("api_env_path", "")
        if env_file:
            sources.append(("existing_profile", env_file))

    default_file = default_env_path()
    if os.path.isfile(default_file):
        sources.append(("existing_env_file", default_file))

    return sources


def detect_cloudflare_connection():
    """Return a safe connection summary without exposing secret locations."""
    for source, env_file in _candidate_sources():
        ok, _err = validate_env_permissions(env_file)
        if not ok:
            continue
        try:
            parse_env_file(env_file)
        except (FileNotFoundError, PermissionError, ValueError):
            continue
        return {
            "connected": True,
            "source": source,
        }

    return {
        "connected": False,
        "source": None,
    }


def gather_cloudflare_setup():
    status = detect_cloudflare_connection()
    connected = bool(status.get("connected"))
    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "connected": connected,
        "next_step": "setup_domain" if connected else "connect_cloudflare",
        "safety": "read_only",
    }


def output_text(result):
    lines = [
        "",
        "  NanoBK Cloudflare 设置",
        "  ─────────────────────────────────────────────",
        "",
        "  我需要连接你的 Cloudflare，用来识别你的域名。",
        "  本步骤不会创建 DNS，不会修改 Cloudflare。",
        "  如果你已经配置过，我会自动检测。",
        "",
    ]

    if result.get("connected"):
        lines.append("  状态：已检测到 Cloudflare 登录信息。")
        lines.append("  下一步：nanobk setup domain")
    else:
        lines.append("  状态：还没有检测到 Cloudflare 登录信息。")
        lines.append("  下一步：请运行 nanobk cf connect")
        lines.append("  说明：这里说的 Cloudflare 登录信息就是现有连接流程保存的信息。")

    lines.append("")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description="NanoBK Cloudflare product setup")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args(sys.argv[1:] if argv is None else argv)

    result = gather_cloudflare_setup()
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(output_text(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
