#!/usr/bin/env python3
"""
NanoBK Production Subscription Publish (v2.6.7)

Productized, exact-gated wrapper for publishing the local VPS profile to the
existing nanok Worker admin update endpoint. Defaults are read-only and all
outputs are intentionally redacted.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_domain_selection import load_selected_domain
from nanobk_setup_profile import load_profile


VERSION = "2.6.7"
MODE = "production_subscription_publish_v2_6"
EXACT_PHRASE = "I UNDERSTAND NANOBK WILL PUBLISH SUBSCRIPTION PROFILE"

REPO_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PROFILE_PATH = "/etc/nanobk/profile.current.json"
ADMIN_ENV_CANDIDATES = [
    "/root/.nanok-cf-admin.env",
    os.path.join(REPO_DIR, ".cloudflare.local.env"),
    os.path.join(REPO_DIR, ".nanob.local.env"),
]
PROTOCOLS = ["hy2", "tuic", "reality", "trojan"]

BLOCKED_ARGS = {
    "--yes",
    "--force",
    "--overwrite",
    "--delete",
    "--update",
    "--rotate-token",
    "--deploy-worker",
    "--install-vps",
    "--restart",
    "--reload",
}

DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)"
    r"(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))+$"
)
URL_RE = re.compile(r"https?://[^\s\"']+", re.IGNORECASE)
UUID_RE = re.compile(
    r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"
)
PRIVATE_KEY_BLOCK_RE = re.compile(
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----",
    re.DOTALL,
)
SENSITIVE_LINE_RE = re.compile(
    r"(ADMIN_TOKEN|SUB_TOKEN|CF_API_TOKEN|NANOB_TOKEN|token|password|private|secret|"
    r"uuid|profile\.current\.json|workers\.dev|/admin|subscription|privkey|fullchain|"
    r"zone_id|record_id|api_env_path|raw Cloudflare|raw Worker)",
    re.IGNORECASE,
)


def _safe_domain(value):
    candidate = (value or "").strip().lower().rstrip(".")
    if not candidate or not DOMAIN_RE.match(candidate):
        return None
    return candidate


def _selected_domain():
    fake = _safe_domain(os.environ.get("NANOBK_FAKE_SELECTED_DOMAIN", ""))
    if fake:
        return fake

    selected, _err = load_selected_domain()
    if selected and selected.get("selected_domain"):
        return _safe_domain(selected.get("selected_domain"))

    profile, err = load_profile()
    if not err and isinstance(profile, dict):
        return _safe_domain(profile.get("zone_name", ""))

    return None


def _fingerprint(value):
    if not value:
        return ""
    digest = hashlib.sha256(value.encode("utf-8")).hexdigest()[:8]
    return f"sha256:{digest}"


def _refusal(message, next_step, dry_run=False, **extra):
    result = {
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
    result.update(extra)
    return result


def _parse_env_file(path):
    values = {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            for raw in handle:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                if (value.startswith('"') and value.endswith('"')) or (
                    value.startswith("'") and value.endswith("'")
                ):
                    value = value[1:-1]
                values[key] = value
    except OSError:
        return {}
    return values


def _fake_profile_summary():
    exists = os.environ.get("NANOBK_FAKE_PROFILE_EXISTS")
    complete = os.environ.get("NANOBK_FAKE_PROFILE_COMPLETE")
    if exists is None and complete is None:
        return None

    exists_ok = exists != "0"
    complete_ok = complete == "1" if complete is not None else exists_ok
    protocols = list(PROTOCOLS) if complete_ok else []
    if exists_ok and not complete_ok:
        protocols = ["hy2"]

    return {
        "exists": exists_ok,
        "complete": complete_ok,
        "protocols": protocols,
        "_profile": _fake_profile_payload() if exists_ok and complete_ok else None,
        "_error": None,
    }


def _fake_profile_payload():
    payload = {"updatedAt": "2026-01-01T00:00:00Z"}
    for name in PROTOCOLS:
        payload[name] = {"enabled": True}
    return payload


def _profile_summary():
    fake = _fake_profile_summary()
    if fake is not None:
        return fake

    if not os.path.isfile(PROFILE_PATH):
        return {"exists": False, "complete": False, "protocols": [], "_profile": None, "_error": None}

    try:
        with open(PROFILE_PATH, "r", encoding="utf-8") as handle:
            profile = json.load(handle)
    except json.JSONDecodeError:
        return {
            "exists": True,
            "complete": False,
            "protocols": [],
            "_profile": None,
            "_error": "invalid_json",
        }
    except OSError:
        return {
            "exists": False,
            "complete": False,
            "protocols": [],
            "_profile": None,
            "_error": "unreadable",
        }

    if not isinstance(profile, dict):
        return {
            "exists": True,
            "complete": False,
            "protocols": [],
            "_profile": None,
            "_error": "invalid_json",
        }

    protocols = [name for name in PROTOCOLS if isinstance(profile.get(name), dict)]
    return {
        "exists": True,
        "complete": len(protocols) == len(PROTOCOLS),
        "protocols": protocols,
        "_profile": profile if len(protocols) == len(PROTOCOLS) else None,
        "_error": None,
    }


def _fake_admin_summary():
    if (
        "NANOBK_FAKE_CF_ADMIN_ENV" not in os.environ
        and "NANOBK_FAKE_ADMIN_ENDPOINTS" not in os.environ
        and "NANOBK_FAKE_ADMIN_TOKEN" not in os.environ
    ):
        return None

    env_present = os.environ.get("NANOBK_FAKE_CF_ADMIN_ENV", "1") == "1"
    endpoints_present = os.environ.get("NANOBK_FAKE_ADMIN_ENDPOINTS", "1") == "1"
    token_present = os.environ.get("NANOBK_FAKE_ADMIN_TOKEN", "1") == "1"
    token = "fake-profile-publish-admin-token" if env_present and token_present else ""
    return {
        "env_present": env_present,
        "update_endpoint_present": bool(env_present and endpoints_present),
        "current_endpoint_present": bool(env_present and endpoints_present),
        "admin_token_present": bool(env_present and token_present),
        "admin_token_fingerprint": _fingerprint(token) if token else "",
        "_update_url": "https://example.invalid/admin/update" if env_present and endpoints_present else "",
        "_current_url": "https://example.invalid/admin/current" if env_present and endpoints_present else "",
        "_token": token,
        "_fake": True,
    }


def _admin_summary():
    fake = _fake_admin_summary()
    if fake is not None:
        return fake

    override = os.environ.get("NANOBK_PROFILE_PUBLISH_ADMIN_ENV_FILE")
    candidates = [override] if override else ADMIN_ENV_CANDIDATES
    values = {}
    for path in candidates:
        if path and os.path.isfile(path):
            values = _parse_env_file(path)
            break

    update_url = values.get("ADMIN_UPDATE_URL", "")
    current_url = values.get("ADMIN_CURRENT_URL", "")
    token = values.get("ADMIN_TOKEN", "")
    return {
        "env_present": bool(values),
        "update_endpoint_present": bool(update_url),
        "current_endpoint_present": bool(current_url),
        "admin_token_present": bool(token),
        "admin_token_fingerprint": _fingerprint(token) if token else "",
        "_update_url": update_url,
        "_current_url": current_url,
        "_token": token,
        "_fake": False,
    }


def _public_profile(profile):
    return {
        "exists": bool(profile.get("exists")),
        "complete": bool(profile.get("complete")),
        "protocols": list(profile.get("protocols", [])),
    }


def _public_admin(admin):
    return {
        "env_present": bool(admin.get("env_present")),
        "update_endpoint_present": bool(admin.get("update_endpoint_present")),
        "current_endpoint_present": bool(admin.get("current_endpoint_present")),
        "admin_token_present": bool(admin.get("admin_token_present")),
        "admin_token_fingerprint": admin.get("admin_token_fingerprint", ""),
    }


def _existing_publish():
    return os.environ.get("NANOBK_FAKE_PROFILE_PUBLISHED") == "1"


def build_plan(dry_run=True):
    domain = _selected_domain()
    if not domain:
        return _refusal("还没有选择你的域名，请先运行 nanobk setup domain。", "select_domain", dry_run)

    profile = _profile_summary()
    if profile.get("_error") == "invalid_json":
        return _refusal("代理配置档案不是有效 JSON，请先修复本机配置档案。", "repair_or_review", dry_run)
    if not profile.get("exists"):
        return _refusal("还没有找到代理配置档案，请先完成代理服务安装。", "setup_vps", dry_run)
    if not profile.get("complete"):
        return _refusal("代理配置档案不完整，请先检查四个代理通道。", "repair_or_review", dry_run)

    admin = _admin_summary()
    if not admin.get("env_present"):
        return _refusal("还没有找到订阅服务管理入口，请先完成 Worker 管理入口配置。", "setup_worker", dry_run)
    if not admin.get("update_endpoint_present"):
        return _refusal("订阅服务管理入口缺少发布地址，当前不会发布。", "setup_worker", dry_run)
    if not admin.get("admin_token_present"):
        return _refusal("订阅服务管理入口缺少本机安全凭据，当前不会发布。", "setup_worker", dry_run)

    if _existing_publish():
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "dry_run": True,
            "mutation": False,
            "dangerous_actions_executed": False,
            "selected_domain": domain,
            "profile": _public_profile(profile),
            "admin": _public_admin(admin),
            "existing_publish": True,
            "subscription_ready": True,
            "blocked": False,
            "next_step": "owner_review",
            "safety": "read_only",
            "_profile": profile.get("_profile"),
            "_admin": admin,
        }

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "dry_run": bool(dry_run),
        "mutation": False,
        "dangerous_actions_executed": False,
        "selected_domain": domain,
        "profile": _public_profile(profile),
        "admin": _public_admin(admin),
        "existing_publish": False,
        "blocked": False,
        "next_step": "confirm_subscription_publish",
        "safety": "read_only",
        "_profile": profile.get("_profile"),
        "_admin": admin,
    }


def redact_output(text):
    if not text:
        return ""
    cleaned = PRIVATE_KEY_BLOCK_RE.sub("[redacted sensitive block]", text)
    cleaned = URL_RE.sub("[redacted-url]", cleaned)
    cleaned = UUID_RE.sub("[redacted-id]", cleaned)
    lines = []
    for raw in cleaned.splitlines():
        line = raw.strip()
        if not line:
            continue
        if SENSITIVE_LINE_RE.search(line):
            lines.append("[redacted sensitive line]")
        elif line.startswith("{") or line.startswith("["):
            lines.append("[redacted response]")
        else:
            lines.append(line)
    return "\n".join(lines)


def _redacted_tail(text, max_lines=20):
    lines = [line for line in redact_output(text).splitlines() if line.strip()]
    return lines[-max_lines:]


def _fake_publish_result(plan):
    if os.environ.get("NANOBK_FAKE_PROFILE_PUBLISH_FAIL") == "1":
        raw = "ADMIN_TOKEN=secret\n{\"hy2\":{\"password\":\"secret\"}}\nprofile publish failed"
        return {
            "ok": False,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": True,
            "dangerous_actions_executed": True,
            "confirmed": True,
            "blocked": True,
            "error": "订阅配置发布失败，请查看已脱敏摘要。",
            "publish_exit_code": 1,
            "redacted_output_tail": _redacted_tail(raw),
            "next_step": "repair_or_review",
            "safety": "confirmed_subscription_publish_failed",
        }

    if os.environ.get("NANOBK_FAKE_PROFILE_PUBLISH") == "1":
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": True,
            "dangerous_actions_executed": True,
            "confirmed": True,
            "published_profile": True,
            "published_protocols": list(PROTOCOLS),
            "subscription_ready": True,
            "blocked": False,
            "next_step": "owner_review",
            "safety": "confirmed_subscription_publish",
        }

    return None


def _real_publish(plan):
    admin = plan.get("_admin") or {}
    if admin.get("_fake"):
        return _refusal("测试用管理入口不能用于真实发布。", "setup_worker", False, confirmed=True)

    profile = plan.get("_profile")
    payload = json.dumps(profile, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(
        admin.get("_update_url", ""),
        data=payload,
        method="POST",
        headers={
            "Authorization": f"Bearer {admin.get('_token', '')}",
            "Content-Type": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read(8192).decode("utf-8", errors="replace")
            status = int(getattr(response, "status", 200))
    except urllib.error.HTTPError as exc:
        body = exc.read(8192).decode("utf-8", errors="replace")
        return _publish_failure(getattr(exc, "code", 1) or 1, body)
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        return _publish_failure(1, str(exc))

    if status < 200 or status >= 300:
        return _publish_failure(status, body)

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "dry_run": False,
        "mutation": True,
        "dangerous_actions_executed": True,
        "confirmed": True,
        "published_profile": True,
        "published_protocols": list(PROTOCOLS),
        "subscription_ready": True,
        "blocked": False,
        "next_step": "owner_review",
        "safety": "confirmed_subscription_publish",
    }


def _publish_failure(exit_code, output):
    return {
        "ok": False,
        "mode": MODE,
        "version": VERSION,
        "dry_run": False,
        "mutation": True,
        "dangerous_actions_executed": True,
        "confirmed": True,
        "blocked": True,
        "error": "订阅配置发布失败，请查看已脱敏摘要。",
        "publish_exit_code": int(exit_code) if isinstance(exit_code, int) else 1,
        "redacted_output_tail": _redacted_tail(output),
        "next_step": "repair_or_review",
        "safety": "confirmed_subscription_publish_failed",
    }


def publish(confirm_phrase):
    if confirm_phrase != EXACT_PHRASE:
        return _refusal("需要完整输入安全确认短语。", "confirm_subscription_publish", False)

    plan = build_plan(dry_run=False)
    if not plan.get("ok"):
        plan["confirmed"] = True
        return plan

    if plan.get("existing_publish"):
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": False,
            "dangerous_actions_executed": False,
            "confirmed": True,
            "existing_publish": True,
            "subscription_ready": True,
            "blocked": False,
            "next_step": "owner_review",
            "safety": "read_only",
        }

    fake = _fake_publish_result(plan)
    if fake:
        return fake

    if os.environ.get("NANOBK_ALLOW_REAL_PROFILE_PUBLISH") != "1":
        return _refusal(
            "真实发布订阅配置需要先设置 NANOBK_ALLOW_REAL_PROFILE_PUBLISH=1。",
            "confirm_subscription_publish",
            False,
            confirmed=True,
        )

    return _real_publish(plan)


def public_result(result):
    return {key: value for key, value in result.items() if not key.startswith("_")}


def output_text(result):
    result = public_result(result)
    lines = [""]

    if result.get("ok") and result.get("dry_run"):
        lines.extend(
            [
                "  NanoBK 发布订阅配置检查",
                "  ─────────────────────────────────────────────",
                "",
                "  当前不会发布订阅配置，不会修改 Cloudflare 或 Worker。",
                "",
            ]
        )
        if result.get("existing_publish"):
            lines.extend(
                [
                    "  状态：订阅配置已发布。",
                    "",
                    "  下一步：",
                    "  owner review",
                    "",
                ]
            )
            return "\n".join(lines)

        lines.extend(
            [
                "  我已检查：",
                "  代理配置档案：已找到",
                "  四个代理通道：hy2、tuic、reality、trojan",
                "  订阅服务管理入口：已找到",
                "",
                "  如果确认无误，再运行：",
                f'  nanobk setup production subscription publish --confirm "{EXACT_PHRASE}"',
                "",
            ]
        )
        return "\n".join(lines)

    if result.get("ok") and not result.get("dry_run"):
        lines.extend(
            [
                "  NanoBK 发布订阅配置",
                "  ─────────────────────────────────────────────",
                "",
                "  已通过安全确认。",
                "  订阅配置已发布。",
                "",
                "  下一步：",
                "  owner review",
                "",
            ]
        )
        return "\n".join(lines)

    lines.extend(
        [
            "  NanoBK 发布订阅配置",
            "  ─────────────────────────────────────────────",
            "",
            f"  已停止：{result.get('error', '当前不会发布订阅配置。')}",
            "",
            "  当前不会发布订阅配置，不会部署 Worker，不会修改 DNS，不会重启服务。",
            "",
        ]
    )
    return "\n".join(lines)


def parse_args(argv):
    parser = argparse.ArgumentParser(
        prog="nanobk setup production subscription publish",
        description="Controlled subscription profile publish wrapper.",
    )
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--confirm")
    for flag in sorted(BLOCKED_ARGS):
        parser.add_argument(flag, action="store_true", dest=f"blocked_{flag[2:].replace('-', '_')}")
    return parser.parse_args(argv)


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    args = parse_args(argv)

    dangerous = [flag for flag in BLOCKED_ARGS if flag in argv]
    if dangerous:
        result = _refusal("这个参数会扩大执行范围，当前命令不会使用它。", "confirm_subscription_publish", False)
    elif args.dry_run:
        result = build_plan(dry_run=True)
    else:
        result = publish(args.confirm or "")

    if args.json:
        print(json.dumps(public_result(result), ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(output_text(result))

    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
