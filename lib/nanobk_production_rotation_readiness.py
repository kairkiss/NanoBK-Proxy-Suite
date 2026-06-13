#!/usr/bin/env python3
"""
NanoBK Production Rotation Readiness Flow (v2.5.5)

Read-only subscription token and protocol key rotation readiness check that:
1. Plans subscription token rotation (auto/custom/unchanged)
2. Maps protocol key rotation targets (all/hy2/tuic/reality/trojan)
3. Enforces product rule: rotate token before protocol keys
4. Generates command plan (preview only)
5. Optionally saves local rotation plan

Read-only. No token rotation. No protocol key rotation.
No Worker mutation. No VPS service reload/restart.

Usage:
    python3 lib/nanobk_production_rotation_readiness.py [--json]
    python3 lib/nanobk_production_rotation_readiness.py --token auto --protocol all [--json]
    python3 lib/nanobk_production_rotation_readiness.py --save --token auto --protocol all [--json]
"""

import argparse
import hashlib
import json
import os
import secrets
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_setup_profile import load_profile, default_profile_path


# -- Constants ----------------------------------------------------------------

VERSION = "2.5.5"
MODE = "production_rotation_readiness_v2_5"
PLAN_FILE_NAME = "production-rotation-plan.json"
WORKER_PLAN_FILE_NAME = "production-worker-plan.json"

_VALID_TOKEN_MODES = {"auto", "custom", "unchanged"}
_VALID_PROTOCOLS = {"all", "hy2", "tuic", "reality", "trojan"}

# Dangerous CLI args that must be rejected
_DANGEROUS_ARGS = {"--rotate", "--yes", "--apply", "--execute", "--confirm"}

# Exact token confirmation phrase
EXACT_PHRASE_TOKEN = "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"


# -- Token masking -------------------------------------------------------------

def _mask_token(token):
    """Mask a token for safe display. Shows first 4 and last 4 hex chars."""
    if not token or len(token) < 8:
        return "****"
    return f"{token[:4]}…{token[-4:]}"


def _generate_token():
    """Generate a random hex token (32 bytes = 64 hex chars)."""
    return secrets.token_hex(32)


# -- Readiness checks ---------------------------------------------------------

def _check_profile():
    """Check if setup profile exists. Returns 'present', 'missing', or 'unknown'."""
    profile_path = default_profile_path()
    if os.path.isfile(profile_path):
        return "present"
    return "missing"


def _check_worker_plan():
    """Check if production worker plan exists. Returns 'present', 'missing', or 'unknown'."""
    plan_path = os.path.join(os.path.expanduser("~"), ".nanobk", WORKER_PLAN_FILE_NAME)
    if os.path.isfile(plan_path):
        return "present"
    return "missing"


def _check_admin_env():
    """Check if admin env hint exists (without reading content). Returns True/False/None."""
    candidates = [
        os.path.expanduser("~/.nanobk/admin.env"),
        "/root/.nanok-cf-admin.env",
    ]
    for path in candidates:
        if os.path.isfile(path):
            return True
    return None


# -- Readiness check ------------------------------------------------------------

def run_readiness(token_mode="auto", custom_token=None, protocol="all"):
    """Run the full rotation readiness check. Returns result dict.

    Safe JSON only. Never includes:
    - raw token, ADMIN_TOKEN, SUB_TOKEN, CF_API_TOKEN
    - subscription URL, admin URL, workers.dev secret URL
    - zone_id, record_id, api_env_path
    - raw protocol passwords
    """
    # Step 1: Validate inputs
    if token_mode not in _VALID_TOKEN_MODES:
        return {"ok": False, "error": f"Invalid token mode: {token_mode}. Use: {', '.join(sorted(_VALID_TOKEN_MODES))}",
                "mode": MODE, "version": VERSION, "mutation": False}

    if protocol not in _VALID_PROTOCOLS:
        return {"ok": False, "error": f"Invalid protocol: {protocol}. Use: {', '.join(sorted(_VALID_PROTOCOLS))}",
                "mode": MODE, "version": VERSION, "mutation": False}

    # Step 2: Handle token
    token_source = "unchanged"
    new_token_masked = None
    raw_token_output = False

    if token_mode == "auto":
        raw_token = _generate_token()
        new_token_masked = _mask_token(raw_token)
        token_source = "auto_generated"
        del raw_token  # Never keep raw token in memory longer than needed
    elif token_mode == "custom":
        if not custom_token:
            return {"ok": False, "error": "自定义 token 不能为空。请使用 --custom-token VALUE。",
                    "mode": MODE, "version": VERSION, "mutation": False}
        if len(custom_token) < 8:
            return {"ok": False, "error": "自定义 token 长度不能少于 8 个字符。",
                    "mode": MODE, "version": VERSION, "mutation": False}
        new_token_masked = _mask_token(custom_token)
        token_source = "custom"
    # unchanged: no new token

    # Step 3: Check readiness
    setup_profile = _check_profile()
    worker_plan = _check_worker_plan()
    admin_env = _check_admin_env()

    # Step 4: Determine blocked state
    token_rotation_ready = token_mode in ("auto", "custom")
    protocol_rotation_blocked = not token_rotation_ready

    if token_rotation_ready:
        next_step = "review_token_gate"
    else:
        next_step = "choose_token_rotation"

    # Step 5: Build commands
    token_gate = f'nanobk setup token rotate --rotate --confirm "{EXACT_PHRASE_TOKEN}"'

    protocol_map = {
        "all": "nanobk rotate all",
        "hy2": "nanobk rotate hy2",
        "tuic": "nanobk rotate tuic",
        "reality": "nanobk rotate reality",
        "trojan": "nanobk rotate trojan",
    }
    protocol_rotate = protocol_map.get(protocol, "nanobk rotate all")

    refresh_subscription = "nanobk export links"

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "token": {
            "mode": token_mode,
            "source": token_source,
            "new_token_masked": new_token_masked,
            "raw_token_output": raw_token_output,
        },
        "readiness": {
            "setup_profile": setup_profile,
            "worker_plan": worker_plan,
            "admin_env_configured": admin_env,
        },
        "protocol": {
            "target": protocol,
            "protocol_rotation_blocked": protocol_rotation_blocked,
        },
        "commands": {
            "token_gate": token_gate,
            "protocol_rotate": protocol_rotate,
            "refresh_subscription": refresh_subscription,
        },
        "order": [
            "rotate_subscription_token",
            "rotate_protocol_keys",
            "refresh_subscription",
        ],
        "blocked": protocol_rotation_blocked,
        "next_step": next_step,
        "safety": "read_only",
        "profile_saved": False,
    }


# -- Save profile ---------------------------------------------------------------

def run_save(token_mode="auto", custom_token=None, protocol="all"):
    """Save local rotation plan. Returns result dict.

    Only writes to local ~/.nanobk/production-rotation-plan.json.
    Never saves raw token. Never writes to Cloudflare.
    """
    # Run readiness to get masked token
    result = run_readiness(token_mode=token_mode, custom_token=custom_token, protocol=protocol)
    if not result.get("ok"):
        return result

    plan_dir = os.path.join(os.path.expanduser("~"), ".nanobk")
    plan_path = os.path.join(plan_dir, PLAN_FILE_NAME)

    plan = {
        "version": 1,
        "token_mode": token_mode,
        "token_source": result["token"]["source"],
        "new_token_masked": result["token"]["new_token_masked"],
        "raw_token_saved": False,
        "protocol": protocol,
        "created_by": "nanobk setup production rotate --save",
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
        "plan_path": plan_path,
        "profile_saved": True,
    }


# -- Text output ----------------------------------------------------------------

def output_text(result):
    """Print beginner-friendly rotation readiness summary in Chinese."""
    print()
    print("  NanoBK 订阅密钥与代理密钥轮换预案")
    print("  ─────────────────────────────────────────────")
    print()
    print("  当前不会轮换 token，不会修改 Worker，不会重启代理服务。")
    print()

    # Recommended order
    print("  推荐顺序：")
    print("    1. 重新生成订阅密钥")
    print("    2. 轮换代理通道密钥")
    print("    3. 刷新订阅")
    print()

    # Token info
    token_info = result.get("token", {})
    token_mode = token_info.get("mode", "unchanged")
    token_masked = token_info.get("new_token_masked")

    print("  订阅密钥：")
    mode_labels = {
        "auto": "自动生成",
        "custom": "自定义",
        "unchanged": "不更换",
    }
    print(f"    模式：{mode_labels.get(token_mode, token_mode)}")
    if token_masked:
        print(f"    新密钥预览：{token_masked}")
        print("    原始密钥不会显示")
    elif token_mode == "unchanged":
        print("    建议先轮换订阅密钥，再轮换协议密钥。")
    print()

    # Protocol info
    protocol_info = result.get("protocol", {})
    protocol_target = protocol_info.get("target", "all")
    protocol_blocked = protocol_info.get("protocol_rotation_blocked", False)

    print("  代理密钥：")
    print(f"    目标：{protocol_target.upper()}")
    protocol_map = {
        "all": "nanobk rotate all",
        "hy2": "nanobk rotate hy2",
        "tuic": "nanobk rotate tuic",
        "reality": "nanobk rotate reality",
        "trojan": "nanobk rotate trojan",
    }
    print(f"    命令：{protocol_map.get(protocol_target, 'nanobk rotate all')}")
    if protocol_blocked:
        print("    状态：需要先轮换订阅密钥")
    print()

    # Readiness
    readiness = result.get("readiness", {})
    print("  环境检查：")
    profile_status = readiness.get("setup_profile", "unknown")
    print(f"    设置档案：{'已存在' if profile_status == 'present' else '未找到'}")
    worker_status = readiness.get("worker_plan", "unknown")
    print(f"    Worker 计划：{'已存在' if worker_status == 'present' else '未找到'}")
    admin_status = readiness.get("admin_env_configured")
    if admin_status is True:
        print("    Admin 环境：已配置")
    elif admin_status is False:
        print("    Admin 环境：未配置")
    print()

    # Next step
    next_step = result.get("next_step", "")
    print("  下一步：")
    if next_step == "review_token_gate":
        print("    nanobk setup token rotate")
    elif next_step == "choose_token_rotation":
        print("    请选择 token 模式：--token auto 或 --token custom --custom-token VALUE")
    print()

    # Safety
    print("  安全说明：")
    print("    真实 token 轮换仍由 v2.3 token gate 控制。")
    print("    真实协议密钥轮换不会在本命令中执行。")
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


# -- CLI -------------------------------------------------------------------------

def main():
    # Check for dangerous args before argparse
    use_json = "--json" in sys.argv
    for arg in sys.argv[1:]:
        if arg in _DANGEROUS_ARGS:
            msg = f"选项 {arg} 不支持。此命令仅用于预览，不会执行轮换。"
            output_error(msg, use_json)
            sys.exit(1)

    parser = argparse.ArgumentParser(
        description="NanoBK Production Rotation Readiness Flow"
    )
    parser.add_argument("--token", choices=["auto", "custom", "unchanged"],
                        default="auto", help="Token mode (default: auto)")
    parser.add_argument("--custom-token", help="Custom token value (only with --token custom)")
    parser.add_argument("--protocol", choices=["all", "hy2", "tuic", "reality", "trojan"],
                        default="all", help="Protocol target (default: all)")
    parser.add_argument("--save", action="store_true", help="Save local rotation plan")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    if args.save:
        result = run_save(
            token_mode=args.token,
            custom_token=args.custom_token,
            protocol=args.protocol,
        )
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
            if not result.get("ok"):
                sys.exit(1)
        else:
            if result.get("ok"):
                print()
                print("  已保存轮换计划。")
                print(f"  Token 模式：{result.get('token_mode', args.token)}")
                print(f"  协议目标：{result.get('protocol', args.protocol).upper()}")
                print()
            else:
                output_error(result.get("error", "unknown error"), False)
                sys.exit(1)
    else:
        result = run_readiness(
            token_mode=args.token,
            custom_token=args.custom_token,
            protocol=args.protocol,
        )
        if args.json:
            print(json.dumps(result, indent=2, ensure_ascii=False))
            if not result.get("ok"):
                sys.exit(1)
        else:
            if result.get("ok"):
                output_text(result)
            else:
                output_error(result.get("error", "unknown error"), False)
                sys.exit(1)


if __name__ == "__main__":
    main()
