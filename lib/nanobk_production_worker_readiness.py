#!/usr/bin/env python3
"""
NanoBK Production Worker Readiness Flow (v2.5.3)

Read-only Worker deployment readiness check that:
1. Reads local setup profile for domain
2. Plans nanok/nanob/web route mapping
3. Checks Worker source directory existence
4. Checks Node.js/npm/wrangler tool availability
5. Generates deployment command plan (preview only)
6. Optionally saves local Worker route plan

Read-only. No Worker deployment. No wrangler deploy.
No Cloudflare POST/PATCH/DELETE. No curl/wrangler/certbot calls.
No service reload/restart.

Usage:
    python3 lib/nanobk_production_worker_readiness.py [--json]
    python3 lib/nanobk_production_worker_readiness.py --zone DOMAIN [--json]
    python3 lib/nanobk_production_worker_readiness.py --save --zone DOMAIN [--json]

Test hooks:
    NANOBK_WORKER_READINESS_FAKE_TOOLS=/path/to/tools.json
    NANOBK_WORKER_READINESS_FAKE_SOURCES=/path/to/sources.json
"""

import argparse
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_profile import load_profile


# ── Constants ────────────────────────────────────────────────────────────────

VERSION = "2.5.3"
MODE = "production_worker_readiness_v2_5"
PLAN_FILE_NAME = "production-worker-plan.json"

DEFAULT_NANOK_SUBDOMAIN = "nanok"
DEFAULT_NANOB_SUBDOMAIN = "nanob"
DEFAULT_WEB_SUBDOMAIN = "web"

# Dangerous CLI args that must be rejected
_DANGEROUS_ARGS = {"--deploy", "--yes", "--apply"}


# ── Tool detection ───────────────────────────────────────────────────────────

def _check_tool(name):
    """Check if a tool is available on PATH. Returns 'present', 'missing', or 'unknown'."""
    # Test hook: fake tool status
    fake_tools_path = os.environ.get("NANOBK_WORKER_READINESS_FAKE_TOOLS")
    if fake_tools_path and os.path.isfile(fake_tools_path):
        try:
            with open(fake_tools_path) as f:
                fake = json.load(f)
            if name in fake:
                return fake[name]
        except (json.JSONDecodeError, OSError):
            pass

    result = shutil.which(name)
    if result:
        return "present"
    return "missing"


def check_tools():
    """Check availability of node, npm, wrangler."""
    return {
        "node": _check_tool("node"),
        "npm": _check_tool("npm"),
        "wrangler": _check_tool("wrangler"),
    }


# ── Source detection ─────────────────────────────────────────────────────────

def _repo_dir():
    """Resolve repo directory from environment or script location."""
    env_dir = os.environ.get("NANOBK_REPO_DIR")
    if env_dir and os.path.isdir(env_dir):
        return env_dir
    # Fallback: two levels up from this script
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def check_worker_sources():
    """Check if nanok/nanob worker source directories exist."""
    # Test hook: fake source status
    fake_sources_path = os.environ.get("NANOBK_WORKER_READINESS_FAKE_SOURCES")
    if fake_sources_path and os.path.isfile(fake_sources_path):
        try:
            with open(fake_sources_path) as f:
                fake = json.load(f)
            return {
                "nanok": fake.get("nanok", "unknown"),
                "nanob": fake.get("nanob", "unknown"),
                "installer": fake.get("installer", "unknown"),
            }
        except (json.JSONDecodeError, OSError):
            pass

    repo = _repo_dir()
    nanok_dir = os.path.join(repo, "workers", "nanok")
    nanob_dir = os.path.join(repo, "workers", "nanob")
    installer = os.path.join(repo, "installer", "install-cloudflare.sh")

    return {
        "nanok": "ready" if os.path.isdir(nanok_dir) else "missing",
        "nanob": "ready" if os.path.isdir(nanob_dir) else "missing",
        "installer": "ready" if os.path.isfile(installer) else "missing",
    }


# ── Route planning ───────────────────────────────────────────────────────────

def build_routes(zone, nanok_sub=DEFAULT_NANOK_SUBDOMAIN, nanob_sub=DEFAULT_NANOB_SUBDOMAIN, web_sub=DEFAULT_WEB_SUBDOMAIN):
    """Build route mapping for nanok/nanob/web."""
    return {
        "nanok": f"{nanok_sub}.{zone}",
        "nanob": f"{nanob_sub}.{zone}",
        "web": f"{web_sub}.{zone}",
    }


def build_plan_command(zone, nanok_sub=DEFAULT_NANOK_SUBDOMAIN, nanob_sub=DEFAULT_NANOB_SUBDOMAIN, web_sub=DEFAULT_WEB_SUBDOMAIN):
    """Build the plan-only deployment command string.

    This is a preview string only. It must never be executed.
    """
    nanok_url = f"https://{nanok_sub}.{zone}"
    nanob_url = f"https://{nanob_sub}.{zone}"
    return (
        f"bash installer/install-cloudflare.sh"
        f" --yes --create-kv --create-nanob-geo-kv"
        f" --profile /etc/nanobk/profile.current.json"
        f" --route-url {nanok_url}"
        f" --deploy-nanob"
        f" --nanob-route-url {nanob_url}"
    )


# ── Readiness check ──────────────────────────────────────────────────────────

def run_readiness(zone=None, nanok_subdomain=DEFAULT_NANOK_SUBDOMAIN,
                  nanob_subdomain=DEFAULT_NANOB_SUBDOMAIN,
                  web_subdomain=DEFAULT_WEB_SUBDOMAIN):
    """Run the full Worker readiness check. Returns result dict.

    Safe JSON only. Never includes:
    - CF_API_TOKEN, ADMIN_TOKEN, SUB_TOKEN
    - zone_id, record_id, api_env_path
    - raw Cloudflare response, workers.dev secret URL
    """
    # Step 1: Resolve zone from profile or override
    profile_zone = None
    profile, profile_err = load_profile()
    if not profile_err:
        profile_zone = profile.get("zone_name", "")

    # Also try to read web_subdomain from saved worker plan
    plan_path = os.path.join(os.path.expanduser("~"), ".nanobk", PLAN_FILE_NAME)
    if os.path.isfile(plan_path):
        try:
            with open(plan_path) as f:
                saved_plan = json.load(f)
            if not web_subdomain or web_subdomain == DEFAULT_WEB_SUBDOMAIN:
                saved_web = saved_plan.get("web_subdomain")
                if saved_web:
                    web_subdomain = saved_web
        except (json.JSONDecodeError, OSError):
            pass

    zone_name = zone or profile_zone

    if not zone_name:
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "mutation": False,
            "dangerous_actions_executed": False,
            "selected_domain": None,
            "routes": {},
            "worker_sources": {},
            "tools": {},
            "commands": {"recommended": None, "plan_only": None},
            "blocked": True,
            "next_step": "select_domain",
            "safety": "read_only",
            "profile_saved": False,
        }

    # Step 2: Build routes
    routes = build_routes(zone_name, nanok_subdomain, nanob_subdomain, web_subdomain)

    # Step 3: Check worker sources
    sources = check_worker_sources()

    # Step 4: Check tools
    tools = check_tools()

    # Step 5: Build commands
    recommended = "nanobk install --mode cloudflare"
    plan_only = build_plan_command(zone_name, nanok_subdomain, nanob_subdomain, web_subdomain)

    # Step 6: Determine blocked state
    blocked = False
    next_step = "review_worker_deploy"

    if sources.get("nanok") == "missing" and sources.get("nanob") == "missing":
        blocked = True
        next_step = "install_worker_sources"
    elif tools.get("node") == "missing" or tools.get("npm") == "missing":
        blocked = True
        next_step = "install_tools"

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "selected_domain": zone_name,
        "routes": routes,
        "worker_sources": {
            "nanok": sources.get("nanok", "unknown"),
            "nanob": sources.get("nanob", "unknown"),
            "installer": sources.get("installer", "unknown"),
        },
        "tools": tools,
        "commands": {
            "recommended": recommended,
            "plan_only": plan_only,
        },
        "blocked": blocked,
        "next_step": next_step,
        "safety": "read_only",
        "profile_saved": False,
    }


# ── Save profile ─────────────────────────────────────────────────────────────

def run_save(zone, nanok_subdomain=DEFAULT_NANOK_SUBDOMAIN,
             nanob_subdomain=DEFAULT_NANOB_SUBDOMAIN,
             web_subdomain=DEFAULT_WEB_SUBDOMAIN):
    """Save local Worker route plan. Returns result dict.

    Only writes to local ~/.nanobk/production-worker-plan.json.
    Never writes to Cloudflare. Never saves tokens.
    """
    if not zone:
        return {"ok": False, "error": "zone is required", "mutation": False}

    plan_dir = os.path.join(os.path.expanduser("~"), ".nanobk")
    plan_path = os.path.join(plan_dir, PLAN_FILE_NAME)

    plan = {
        "version": 1,
        "zone_name": zone,
        "nanok_subdomain": nanok_subdomain,
        "nanob_subdomain": nanob_subdomain,
        "web_subdomain": web_subdomain,
        "created_by": "nanobk setup production worker --save",
    }

    try:
        os.makedirs(plan_dir, mode=0o700, exist_ok=True)
        with open(plan_path, "w") as f:
            json.dump(plan, f, indent=2, ensure_ascii=False)
        os.chmod(plan_path, 0o600)
    except OSError as e:
        return {"ok": False, "error": f"Failed to save plan: {e}", "mutation": False}

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "zone_name": zone,
        "plan_path": plan_path,
        "profile_saved": True,
    }


# ── Text output ──────────────────────────────────────────────────────────────

_STATUS_LABELS = {
    "ready": "已找到",
    "present": "已安装",
    "missing": "未安装",
    "unknown": "未知",
}


def output_text(result):
    """Print beginner-friendly Worker readiness summary in Chinese."""
    print()
    print("  NanoBK Worker 准备")
    print("  ─────────────────────────────────────────────")
    print()
    print("  当前不会部署 Worker，不会修改 Cloudflare。")
    print()

    domain = result.get("selected_domain")
    routes = result.get("routes", {})

    if domain and routes:
        print("  准备使用：")
        if routes.get("nanok"):
            print(f"    主订阅入口：{routes['nanok']}")
        if routes.get("nanob"):
            print(f"    聚合入口：{routes['nanob']}")
        if routes.get("web"):
            print(f"    Web 面板入口：{routes['web']}")
        print()

    sources = result.get("worker_sources", {})
    tools = result.get("tools", {})

    if sources or tools:
        print("  本地检查：")
        if sources.get("nanok"):
            label = _STATUS_LABELS.get(sources["nanok"], sources["nanok"])
            print(f"    nanok 源码：{label}")
        if sources.get("nanob"):
            label = _STATUS_LABELS.get(sources["nanob"], sources["nanob"])
            print(f"    nanob 源码：{label}")
        if sources.get("installer"):
            label = _STATUS_LABELS.get(sources["installer"], sources["installer"])
            print(f"    安装脚本：{label}")
        if tools.get("node"):
            label = _STATUS_LABELS.get(tools["node"], tools["node"])
            print(f"    Node.js：{label}")
        if tools.get("npm"):
            label = _STATUS_LABELS.get(tools["npm"], tools["npm"])
            print(f"    npm：{label}")
        if tools.get("wrangler"):
            label = _STATUS_LABELS.get(tools["wrangler"], tools["wrangler"])
            print(f"    Wrangler：{label}")
        print()

    commands = result.get("commands", {})
    if commands.get("recommended"):
        print("  推荐下一步：")
        print(f"    {commands['recommended']}")
        print()

    blocked = result.get("blocked", False)
    next_step = result.get("next_step", "")

    if blocked:
        print("  状态：需要先完成前置准备")
        if next_step == "select_domain":
            print("  请先选择域名：nanobk setup production dns --zone your-domain.com")
        elif next_step == "install_worker_sources":
            print("  请先获取 Worker 源码")
        elif next_step == "install_tools":
            print("  请先安装 Node.js 和 npm")
    else:
        print("  状态：准备就绪（预览模式，不会自动部署）")

    print()
    print("  安全说明：")
    print("    这一步只生成计划，不会部署 Worker。")
    print("    真正部署时会进入交互安装器。")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {
            "ok": False,
            "error": message,
            "mode": MODE,
            "version": VERSION,
            "mutation": False,
        }
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(f"  错误：{message}", file=sys.stderr)


# ── CLI ──────────────────────────────────────────────────────────────────────

def main():
    # Check for dangerous args before argparse (so we can give a nice error)
    use_json = "--json" in sys.argv
    for arg in sys.argv[1:]:
        if arg in _DANGEROUS_ARGS:
            msg = f"选项 {arg} 不支持。此命令仅用于预览，不会执行部署。"
            output_error(msg, use_json)
            sys.exit(1)

    parser = argparse.ArgumentParser(
        description="NanoBK Production Worker Readiness Flow"
    )
    parser.add_argument("--zone", help="Domain zone to use")
    parser.add_argument("--nanok-subdomain", default=DEFAULT_NANOK_SUBDOMAIN,
                        help=f"nanok subdomain prefix (default: {DEFAULT_NANOK_SUBDOMAIN})")
    parser.add_argument("--nanob-subdomain", default=DEFAULT_NANOB_SUBDOMAIN,
                        help=f"nanob subdomain prefix (default: {DEFAULT_NANOB_SUBDOMAIN})")
    parser.add_argument("--web-subdomain", default=DEFAULT_WEB_SUBDOMAIN,
                        help=f"web subdomain prefix (default: {DEFAULT_WEB_SUBDOMAIN})")
    parser.add_argument("--save", action="store_true",
                        help="Save local Worker route plan")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.save:
        result = run_save(
            zone=args.zone,
            nanok_subdomain=args.nanok_subdomain,
            nanob_subdomain=args.nanob_subdomain,
            web_subdomain=args.web_subdomain,
        )
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            if result.get("ok"):
                print()
                print("  已保存 Worker 路由计划。")
                print(f"  域名：{result.get('zone_name', '***')}")
                print()
            else:
                output_error(result.get("error", "unknown error"), False)
                sys.exit(1)
    else:
        result = run_readiness(
            zone=args.zone,
            nanok_subdomain=args.nanok_subdomain,
            nanob_subdomain=args.nanob_subdomain,
            web_subdomain=args.web_subdomain,
        )
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            if result.get("ok"):
                output_text(result)
            else:
                output_error(result.get("error", "unknown error"), False)
                sys.exit(1)


if __name__ == "__main__":
    main()
