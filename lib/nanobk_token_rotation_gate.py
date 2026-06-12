#!/usr/bin/env python3
"""
NanoBK Subscription Token Rotation Gate

Gated subscription token rotation engine. By default, shows rotation plan only.
Real token rotation requires explicit --rotate and exact confirmation phrase.

Read-only plan by default. Rotate only with --rotate + exact confirm.

Usage:
    python3 lib/nanobk_token_rotation_gate.py [--worker-name NAME] [--api-env PATH] [--token-kind both] [--json]
    python3 lib/nanobk_token_rotation_gate.py --rotate --worker-name NAME --confirm "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS" [--api-env PATH] [--token-kind both] [--json]

Test hooks:
    NANOBK_TOKEN_ROTATE_FAKE_RUN=1
    NANOBK_TOKEN_ROTATE_FAKE_RESULT=/path/to/result.json
    NANOBK_TOKEN_ROTATE_FAKE_CAPTURE=/tmp/nanobk-token-rotate.jsonl
"""

import argparse
import json
import os
import secrets
import string
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cf_zones import parse_env_file


# ── Constants ────────────────────────────────────────────────────────────────

_CONFIRM_PHRASE = "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"
_PRODUCTION_WORKER_NAMES = {"nanok", "nanob"}
_PRODUCTION_DOMAIN_MARKERS = {"nanok.biankai314.uk", "nanob.biankai314.uk"}
_TOKEN_LENGTH = 43


# ── Token generation ─────────────────────────────────────────────────────────

def generate_token(length=_TOKEN_LENGTH):
    """Generate a cryptographically secure token."""
    alphabet = string.ascii_letters + string.digits + "-_"
    return secrets.token_urlsafe(length)[:length]


def mask_token(token):
    """Mask a token for safe display."""
    if not token:
        return "[redacted:empty]"
    if len(token) <= 6:
        return "[redacted]"
    return f"{token[:3]}...{token[-3:]}"


# ── Safety checks ────────────────────────────────────────────────────────────

def is_production_worker(worker_name, api_env_path=None):
    """Check if worker name is a production worker."""
    if not worker_name:
        return True, "worker name 未指定"
    if worker_name.lower() in _PRODUCTION_WORKER_NAMES:
        return True, f"worker name '{worker_name}' 是生产 Worker，不允许默认轮换"
    # Check api_env for production domain markers
    if api_env_path and os.path.isfile(api_env_path):
        try:
            with open(api_env_path, "r") as f:
                content = f.read()
            for marker in _PRODUCTION_DOMAIN_MARKERS:
                if marker in content:
                    return True, f"api-env 包含生产域名 {marker}"
        except OSError:
            pass
    return False, None


# ── Command capture (test hook) ──────────────────────────────────────────────

def capture_rotation(payload_dict):
    """Write rotation payload to capture file if hook is set. Test-only."""
    capture_path = os.environ.get("NANOBK_TOKEN_ROTATE_FAKE_CAPTURE")
    if not capture_path:
        return
    try:
        with open(capture_path, "a") as f:
            f.write(json.dumps(payload_dict) + "\n")
    except OSError:
        pass


# ── Fake rotation runner ─────────────────────────────────────────────────────

def run_rotation_fake(fake_result_path, worker_name, token_kind,
                      sub_token_masked, admin_token_masked, api_env_path):
    """Run fake token rotation. Returns result dict."""
    try:
        with open(fake_result_path, "r") as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError, OSError) as e:
        return {
            "ok": False,
            "mode": "failed",
            "rotation_executed": True,
            "mutation": False,
            "error": f"无法读取 fake rotation 结果: {e}",
        }

    # Capture the command
    capture_rotation({
        "worker_name": worker_name,
        "token_kind": token_kind,
        "sub_token_masked": sub_token_masked,
        "admin_token_masked": admin_token_masked,
        "raw_tokens_printed": False,
        "raw_worker_script_printed": False,
        "contains_production_worker": False,
    })

    if data.get("success"):
        return {
            "ok": True,
            "mode": "rotated",
            "rotation_executed": True,
            "mutation": True,
            "worker_name": worker_name,
            "token_kind": token_kind,
            "worker_updated": data.get("worker_updated", True),
            "version": data.get("version", ""),
            "raw_tokens_printed": False,
            "raw_worker_script_printed": False,
        }
    else:
        return {
            "ok": False,
            "mode": "failed",
            "rotation_executed": True,
            "mutation": False,
            "error": data.get("error", "token rotation failed"),
        }


# ── Main rotation gate ───────────────────────────────────────────────────────

def run_rotation_gate(worker_name=None, api_env_override=None,
                      token_kind="both", rotate_mode=False, confirm_phrase=None):
    """Run the token rotation gate. Returns result dict."""

    # Step 1: Validate api-env
    api_env_path = api_env_override
    if not api_env_path:
        # Try default path
        default_path = os.path.expanduser("~/.nanobk/cloudflare.env")
        if os.path.isfile(default_path):
            api_env_path = default_path

    if not api_env_path or not os.path.isfile(api_env_path):
        return {
            "ok": False,
            "mode": "blocked",
            "rotation_executed": False,
            "mutation": False,
            "blocked_reason": "未找到 API 配置文件，请先运行 nanobk cf connect",
        }

    # Step 2: Parse env
    try:
        env = parse_env_file(api_env_path)
    except (FileNotFoundError, PermissionError, ValueError) as e:
        return {
            "ok": False,
            "mode": "blocked",
            "rotation_executed": False,
            "mutation": False,
            "blocked_reason": f"API 配置读取失败: {e}",
        }

    cf_token = env.get("CF_API_TOKEN")
    if not cf_token:
        return {
            "ok": False,
            "mode": "blocked",
            "rotation_executed": False,
            "mutation": False,
            "blocked_reason": "CF_API_TOKEN not found in API config",
        }

    # Step 3: Validate worker name
    if not worker_name:
        if not rotate_mode:
            # Plan-only can proceed without worker name
            worker_name = "(未指定)"
        else:
            return {
                "ok": False,
                "mode": "blocked",
                "rotation_executed": False,
                "mutation": False,
                "blocked_reason": "worker name 未指定，请使用 --worker-name",
            }

    # Step 4: Check production worker (only in rotate mode)
    if rotate_mode and worker_name != "(未指定)":
        is_prod, prod_reason = is_production_worker(worker_name, api_env_path)
        if is_prod:
            return {
                "ok": False,
                "mode": "blocked",
                "rotation_executed": False,
                "mutation": False,
                "blocked_reason": prod_reason,
            }

    # Step 5: Generate new tokens (for plan preview and potential rotation)
    sub_token_new = None
    admin_token_new = None
    sub_token_masked = "[redacted:length=43]"
    admin_token_masked = "[redacted:length=43]"

    if token_kind in ("sub", "both"):
        sub_token_new = generate_token()
        sub_token_masked = mask_token(sub_token_new)
    if token_kind in ("admin", "both"):
        admin_token_new = generate_token()
        admin_token_masked = mask_token(admin_token_new)

    # Step 6: Plan-only mode
    if not rotate_mode:
        # Check production worker even in plan-only mode
        is_prod = False
        prod_reason = None
        if worker_name != "(未指定)":
            is_prod, prod_reason = is_production_worker(worker_name, api_env_path)

        ready = worker_name != "(未指定)" and not is_prod
        safety_warning = None
        next_cmd = None
        if is_prod:
            safety_warning = prod_reason
        elif worker_name == "(未指定)":
            safety_warning = "worker name 未指定，请使用 --worker-name"
        else:
            next_cmd = f'nanobk setup token rotate --rotate --worker-name {worker_name} --confirm "{_CONFIRM_PHRASE}"'

        return {
            "ok": True,
            "mode": "token_rotation_plan",
            "rotation_executed": False,
            "mutation": False,
            "worker_name": worker_name,
            "token_kind": token_kind,
            "new_tokens_generated": True,
            "sub_token_masked": sub_token_masked if token_kind in ("sub", "both") else None,
            "admin_token_masked": admin_token_masked if token_kind in ("admin", "both") else None,
            "ready_to_rotate": ready,
            "safety_warning": safety_warning,
            "next_command": next_cmd,
        }

    # Step 7: Rotate mode — check confirmation
    if confirm_phrase != _CONFIRM_PHRASE:
        return {
            "ok": False,
            "mode": "blocked",
            "rotation_executed": False,
            "mutation": False,
            "blocked_reason": "missing exact confirmation",
            "hint": f'需要输入: --confirm "{_CONFIRM_PHRASE}"',
        }

    # Step 8: Final safety check — worker name
    if worker_name == "(未指定)":
        return {
            "ok": False,
            "mode": "blocked",
            "rotation_executed": False,
            "mutation": False,
            "blocked_reason": "worker name 未指定",
        }

    is_prod, prod_reason = is_production_worker(worker_name, api_env_path)
    if is_prod:
        return {
            "ok": False,
            "mode": "blocked",
            "rotation_executed": False,
            "mutation": False,
            "blocked_reason": prod_reason,
        }

    # Step 9: Execute rotation (fake or real)
    fake_run = os.environ.get("NANOBK_TOKEN_ROTATE_FAKE_RUN")
    fake_result_path = os.environ.get("NANOBK_TOKEN_ROTATE_FAKE_RESULT")

    if fake_run and fake_result_path:
        return run_rotation_fake(
            fake_result_path, worker_name, token_kind,
            sub_token_masked, admin_token_masked, api_env_path,
        )

    # Real rotation — not implemented yet (gated)
    return {
        "ok": False,
        "mode": "blocked",
        "rotation_executed": False,
        "mutation": False,
        "blocked_reason": "真实 Token 轮换尚未实现，请使用 fake hook 测试",
    }


# ── Output ───────────────────────────────────────────────────────────────────

def output_text(result):
    """Print human-readable result."""
    mode = result.get("mode", "unknown")

    if mode == "token_rotation_plan":
        _output_plan_text(result)
    elif mode == "rotated":
        _output_rotated_text(result)
    elif mode == "blocked":
        _output_blocked_text(result)
    else:
        _output_failed_text(result)


def _output_plan_text(result):
    print()
    print("  NanoBK 订阅 Token 轮换预案")
    print()

    worker = result.get("worker_name", "(未指定)")
    kind = result.get("token_kind", "both")
    ready = result.get("ready_to_rotate", False)
    safety_warning = result.get("safety_warning")

    print(f"  Worker: {worker}")
    print(f"  Token 类型: {kind}")

    sub_masked = result.get("sub_token_masked")
    admin_masked = result.get("admin_token_masked")
    if sub_masked:
        print(f"  新 SUB_TOKEN: {sub_masked}")
    if admin_masked:
        print(f"  新 ADMIN_TOKEN: {admin_masked}")
    print()

    if safety_warning:
        print(f"  ⚠ 警告: {safety_warning}")
        print()
        print("  生产 Worker 受保护，不允许通过此命令轮换。")
    elif ready:
        print("  真正轮换 Token 请执行：")
        print(f'    nanobk setup token rotate --rotate --worker-name {worker} --confirm "{_CONFIRM_PHRASE}"')
    else:
        print("  当前条件不满足轮换要求，请先指定 worker name。")
    print()

    print("  安全说明：")
    print("    本步骤只显示预案，不会轮换 Token，不会修改 Worker。")
    print()


def _output_rotated_text(result):
    print()
    print("  NanoBK Token 轮换完成")
    print()

    worker = result.get("worker_name", "")
    kind = result.get("token_kind", "both")
    version = result.get("version", "")

    print(f"  Worker: {worker}")
    print(f"  Token 类型: {kind}")
    if version:
        print(f"  Worker 版本: {version}")
    print()

    print("  安全说明：")
    print("    * 新 Token 已生效")
    print("    * 旧 Token 已失效")
    print("    * 请更新客户端配置")
    print()


def _output_blocked_text(result):
    print()
    print("  Token 轮换被阻止")
    print()
    reason = result.get("blocked_reason") or result.get("error", "未知原因")
    print(f"  原因: {reason}")
    hint = result.get("hint", "")
    if hint:
        print(f"  提示: {hint}")
    print()


def _output_failed_text(result):
    print()
    print("  Token 轮换失败")
    print()
    print(f"  错误: {result.get('error', '未知错误')}")
    print()


def output_error(message, json_mode=False):
    """Print error message."""
    if json_mode:
        result = {
            "ok": False,
            "mode": "blocked",
            "rotation_executed": False,
            "mutation": False,
            "blocked_reason": message,
        }
        print(json.dumps(result, indent=2))
    else:
        print(f"  Error: {message}", file=sys.stderr)


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="NanoBK Subscription Token Rotation Gate"
    )
    parser.add_argument("--worker-name", help="Cloudflare Worker name")
    parser.add_argument("--api-env", help="Path to Cloudflare env file")
    parser.add_argument("--token-kind", choices=["sub", "admin", "both"], default="both",
                        help="Which tokens to rotate (default: both)")
    parser.add_argument("--rotate", action="store_true", help="Actually rotate tokens")
    parser.add_argument("--confirm", help="Exact confirmation phrase")
    parser.add_argument("--json", action="store_true", help="JSON output")

    args = parser.parse_args()

    result = run_rotation_gate(
        worker_name=args.worker_name,
        api_env_override=args.api_env,
        token_kind=args.token_kind,
        rotate_mode=args.rotate,
        confirm_phrase=args.confirm,
    )

    if args.json:
        print(json.dumps(result, indent=2))
    else:
        output_text(result)

    if not result.get("ok"):
        sys.exit(1)


if __name__ == "__main__":
    main()
