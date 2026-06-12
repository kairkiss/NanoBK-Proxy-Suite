#!/usr/bin/env python3
"""
NanoBK Cloudflare Account and Zone Onboarding

Beginner-friendly flow to connect a Cloudflare account and select a domain.
Safely stores API token locally, validates it, lists zones, and saves profile.

Read-only zone discovery. No DNS mutation. No POST/PATCH/DELETE.

Usage:
    python3 lib/nanobk_cf_onboarding.py connect [--api-token TOKEN] [--api-env PATH] [--yes] [--json]

Test hooks:
    NANOBK_CF_ZONES_FAKE_RESPONSE=/path/to/fixture.json
"""

import argparse
import getpass
import json
import os
import stat
import sys

# Reuse zone discovery from nanobk_cf_zones
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from nanobk_cf_zones import parse_env_file, fetch_zones, output_error
from nanobk_setup_profile import save_profile, ensure_profile_dir


# ── Constants ────────────────────────────────────────────────────────────────

_ENV_DIR_NAME = ".nanobk"
_ENV_FILE_NAME = "cloudflare.env"


# ── Path helpers ─────────────────────────────────────────────────────────────

def default_env_dir():
    return os.path.join(os.path.expanduser("~"), _ENV_DIR_NAME)


def default_env_path():
    return os.path.join(default_env_dir(), _ENV_FILE_NAME)


# ── Token storage ────────────────────────────────────────────────────────────

def save_token_env(token, env_path=None):
    """Save Cloudflare API token to local env file with 0600 permissions."""
    if not token:
        return {"ok": False, "error": "token is required"}

    target = env_path or default_env_path()
    target_dir = os.path.dirname(target)

    try:
        os.makedirs(target_dir, mode=0o700, exist_ok=True)
        try:
            os.chmod(target_dir, 0o700)
        except OSError:
            pass
    except OSError as e:
        return {"ok": False, "error": "failed to create config directory"}

    content = f'CF_API_TOKEN="{token}"\n'

    try:
        with open(target, "w", encoding="utf-8") as f:
            f.write(content)
        os.chmod(target, 0o600)
    except OSError:
        return {"ok": False, "error": "failed to write token file"}

    return {"ok": True, "env_path": target}


def validate_env_permissions(env_path):
    """Check that env file has secure permissions."""
    if not os.path.isfile(env_path):
        return False, "credential file not found"
    try:
        st = os.stat(env_path)
        mode = stat.S_IMODE(st.st_mode)
        if mode & 0o077:
            return False, f"insecure file permissions: {oct(mode)}"
        return True, None
    except OSError:
        return False, "cannot read file permissions"


# ── Zone selection ───────────────────────────────────────────────────────────

def select_zone(zones, auto_select=False):
    """Select a zone from the list. Returns (zone, error_message)."""
    if not zones:
        return None, "no_zones"

    if len(zones) == 1:
        return zones[0], None

    if auto_select:
        return zones[0], None

    # Interactive selection
    print()
    print("  发现以下域名：")
    print()
    for i, zone in enumerate(zones, 1):
        name = zone.get("name", "unknown")
        print(f"  {i}. {name}")
    print()

    while True:
        try:
            choice = input(f"  选择域名 [1-{len(zones)}]: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return None, "cancelled"
        if not choice:
            continue
        try:
            idx = int(choice)
            if 1 <= idx <= len(zones):
                return zones[idx - 1], None
        except ValueError:
            pass
        print(f"  无效输入，请输入 1-{len(zones)} 之间的数字。")


# ── Onboarding flow ─────────────────────────────────────────────────────────

def prompt_for_token():
    """Interactively prompt user for Cloudflare API token. Returns token or None."""
    # Test hook: NANOBK_TEST_FORCE_INTERACTIVE=1 bypasses TTY check
    # and uses stdin instead of /dev/tty (which would hang in CI/background)
    force_interactive = os.environ.get("NANOBK_TEST_FORCE_INTERACTIVE")
    if not force_interactive and not sys.stdin.isatty():
        return None
    print()
    print("  请粘贴 Cloudflare API token")
    print("  我只会读取你的域名列表，不会创建 DNS，不会修改 Cloudflare。")
    print()
    try:
        if force_interactive:
            # In test mode, read from stdin (pipe) instead of /dev/tty
            token = input("  API token: ")
        else:
            token = getpass.getpass("  API token: ")
    except (EOFError, KeyboardInterrupt):
        print()
        return None
    token = token.strip()
    if not token:
        print()
        print("  错误：token 不能为空。")
        return None
    return token


def run_onboarding(api_token=None, api_env_path=None, auto_select=False, json_mode=False):
    """Run the full Cloudflare onboarding flow. Returns result dict."""

    # Step 1: Determine or create env file
    env_path = api_env_path

    if api_token and not env_path:
        # Save token to default location
        result = save_token_env(api_token)
        if not result["ok"]:
            return result
        env_path = result["env_path"]
    elif not env_path:
        # Check if default env exists
        default = default_env_path()
        if os.path.isfile(default):
            ok, err = validate_env_permissions(default)
            if not ok:
                return {"ok": False, "error": err}
            env_path = default
        elif not json_mode:
            # Interactive prompt for TTY users
            token = prompt_for_token()
            if not token:
                return {
                    "ok": False,
                    "error": "未提供 Cloudflare API token。请使用 --api-token 或从菜单选择此选项。",
                }
            result = save_token_env(token)
            if not result["ok"]:
                return result
            env_path = result["env_path"]
        else:
            return {
                "ok": False,
                "error": "no Cloudflare API token provided. Use --api-token or --api-env.",
            }

    # Step 2: Validate env file
    ok, err = validate_env_permissions(env_path)
    if not ok:
        return {"ok": False, "error": err}

    # Step 3: Parse env and get token
    try:
        env = parse_env_file(env_path)
    except (FileNotFoundError, PermissionError, ValueError) as e:
        return {"ok": False, "error": str(e)}

    token = env.get("CF_API_TOKEN", "")
    if not token:
        return {"ok": False, "error": "CF_API_TOKEN not found in env file"}

    # Step 4: Fetch zones
    try:
        zones = fetch_zones(token)
    except RuntimeError as e:
        error_msg = str(e)
        if "401" in error_msg or "Invalid" in error_msg or "authentication" in error_msg.lower():
            return {
                "ok": False,
                "error": "Cloudflare 授权失败，请重新复制 API token。",
                "status": "auth_failed",
                "mutation": False,
            }
        return {"ok": False, "error": error_msg, "mutation": False}

    if not zones:
        return {
            "ok": False,
            "error": "Cloudflare 账户下没有可用域名，请先把域名添加到 Cloudflare。",
            "status": "no_zones",
            "mutation": False,
        }

    # Step 5: Select zone
    zone, err = select_zone(zones, auto_select=auto_select)
    if err:
        if err == "cancelled":
            return {"ok": False, "error": "用户取消选择", "mutation": False}
        if err == "no_zones":
            return {
                "ok": False,
                "error": "Cloudflare 账户下没有可用域名。",
                "status": "no_zones",
                "mutation": False,
            }
        return {"ok": False, "error": err, "mutation": False}

    zone_name = zone.get("name", "")

    # Step 6: Save to setup profile
    profile_result = save_profile(zone_name, env_path, ["proxy", "web"])
    if not profile_result.get("ok"):
        return {"ok": False, "error": profile_result.get("error", "failed to save profile"), "mutation": False}

    return {
        "ok": True,
        "status": "connected",
        "zone_name": zone_name,
        "api_env_configured": True,
        "token_printed": False,
        "zone_id_printed": False,
        "mutation": False,
    }


# ── Output ───────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable result."""
    if result.get("ok"):
        print()
        print("  Cloudflare 连接成功！")
        print(f"  域名：{result.get('zone_name', '***')}")
        print("  API 配置：已保存")
        print("  下一步：可以继续设置 DNS。")
        print()
    else:
        error = result.get("error", "unknown error")
        print()
        print(f"  错误：{error}")
        print()


def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Cloudflare Account and Zone Onboarding"
    )
    parser.add_argument("--api-token", help="Cloudflare API token")
    parser.add_argument("--api-env", help="Path to existing Cloudflare env file")
    parser.add_argument("--yes", action="store_true", help="Auto-select first zone")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    result = run_onboarding(
        api_token=args.api_token,
        api_env_path=args.api_env,
        auto_select=args.yes,
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
