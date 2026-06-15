#!/usr/bin/env python3
"""
NanoBK Production Certificate Issue (v2.6.4)

Productized, exact-gated certificate issue wrapper for production proxy/web
hostnames. Dry-run is read-only. Automated tests use fake issue hooks only.
The real certificate adapter is intentionally safe-refused until connected.
"""

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_cloudflare_product_setup import detect_cloudflare_connection
from nanobk_domain_selection import load_selected_domain
from nanobk_setup_profile import load_profile


VERSION = "2.6.4"
MODE = "production_cert_issue_v2_6"
EXACT_PHRASE_CERT = "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"

BLOCKED_ARGS = {
    "--yes",
    "--force",
    "--overwrite",
    "--delete",
    "--update",
    "--renew-force",
}

LABEL_RE = re.compile(r"^(?!-)[A-Za-z0-9-]{1,63}(?<!-)$")


def _refusal(message, next_step, dry_run=False):
    return {
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


def _safe_domain():
    fake = os.environ.get("NANOBK_FAKE_SELECTED_DOMAIN", "").strip().lower().rstrip(".")
    if fake:
        return fake

    selected, _err = load_selected_domain()
    if selected and selected.get("selected_domain"):
        return selected.get("selected_domain")

    profile, err = load_profile()
    if not err and profile and profile.get("zone_name"):
        return profile.get("zone_name")

    return None


def _cloudflare_connected():
    fake = os.environ.get("NANOBK_FAKE_CF_CONNECTED")
    if fake == "1":
        return True
    if fake == "0":
        return False
    return bool(detect_cloudflare_connection().get("connected"))


def _safe_label(label):
    value = (label or "").strip().lower().rstrip(".")
    if not value or "." in value or not LABEL_RE.match(value):
        return None
    return value


def _target_labels():
    raw = os.environ.get("NANOBK_FAKE_CERT_TARGETS")
    if raw is None:
        labels = ["proxy", "web"]
    else:
        labels = [item.strip() for item in raw.split(",") if item.strip()]

    safe = []
    for label in labels:
        value = _safe_label(label)
        if not value:
            return None
        if value not in safe:
            safe.append(value)

    if not safe:
        return None
    return safe


def _purpose(label):
    if label == "proxy":
        return "proxy_tls"
    if label == "web":
        return "web_https"
    return "custom_tls"


def _cert_targets(domain):
    labels = _target_labels()
    if labels is None:
        return None
    return [
        {"name": f"{label}.{domain}", "purpose": _purpose(label)}
        for label in labels
    ]


def _existing_certificate():
    fake = os.environ.get("NANOBK_FAKE_CERT_EXISTS")
    if fake == "1":
        return True
    if fake == "0":
        return False
    return False


def build_plan(dry_run=True):
    domain = _safe_domain()
    if not domain:
        return _refusal("还没有选择你的域名，请先运行 nanobk setup domain", "select_domain", dry_run)

    if not _cloudflare_connected():
        return _refusal("还没有连接 Cloudflare，请先运行 nanobk setup cloudflare", "setup_cloudflare", dry_run)

    targets = _cert_targets(domain)
    if targets is None:
        return _refusal("HTTPS 安全证书目标格式不正确，请使用安全的单段名称", "cert_targets", dry_run)

    existing = _existing_certificate()
    next_step = "setup_vps" if existing else "confirm_cert_issue"

    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "dry_run": bool(dry_run),
        "mutation": False,
        "dangerous_actions_executed": False,
        "selected_domain": domain,
        "cert_targets": targets,
        "existing_certificate": existing,
        "blocked": False,
        "next_step": next_step,
        "safety": "read_only",
    }


def issue_certificates(confirm_phrase):
    if confirm_phrase != EXACT_PHRASE_CERT:
        return _refusal("需要完整输入安全确认短语。", "confirm_cert_issue", False)

    plan = build_plan(dry_run=False)
    if not plan.get("ok"):
        return plan

    if plan.get("existing_certificate"):
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": False,
            "dangerous_actions_executed": False,
            "confirmed": True,
            "existing_certificate": True,
            "cert_targets": plan.get("cert_targets", []),
            "blocked": False,
            "next_step": "setup_vps",
            "safety": "read_only",
        }

    if os.environ.get("NANOBK_FAKE_CERT_ISSUE") == "1":
        return {
            "ok": True,
            "mode": MODE,
            "version": VERSION,
            "dry_run": False,
            "mutation": True,
            "dangerous_actions_executed": True,
            "confirmed": True,
            "issued_certificates": plan.get("cert_targets", []),
            "blocked": False,
            "next_step": "setup_vps",
            "safety": "confirmed_cert_issue",
        }

    if os.environ.get("NANOBK_ALLOW_REAL_CERT_ISSUE") != "1":
        return _refusal(
            "真实申请 HTTPS 安全证书需要先设置 NANOBK_ALLOW_REAL_CERT_ISSUE=1。",
            "confirm_cert_issue",
            False,
        )

    return _refusal(
        "真实申请 HTTPS 安全证书的受控执行器尚未接入；当前不会申请证书。",
        "connect_cert_issue_adapter",
        False,
    )


def public_result(result):
    cleaned = {}
    for key, value in result.items():
        if key.startswith("_"):
            continue
        cleaned[key] = value
    return cleaned


def output_text(result):
    result = public_result(result)
    lines = [""]

    if result.get("ok") and result.get("dry_run"):
        lines.extend([
            "  NanoBK HTTPS 安全证书检查",
            "  ─────────────────────────────────────────────",
            "",
            "  当前不会申请 HTTPS 安全证书。",
            "",
            "  我将准备：",
            "",
        ])
        for item in result.get("cert_targets", []):
            lines.append(f"  {item['name']} -> HTTPS 安全证书")
        lines.append("")
        if result.get("existing_certificate"):
            lines.extend([
                "  状态：已检测到 HTTPS 安全证书。",
                "",
                "  下一步：",
                "  nanobk setup production vps",
                "",
            ])
        else:
            lines.extend([
                "  如果确认无误，再运行：",
                f'  nanobk setup production cert issue --confirm "{EXACT_PHRASE_CERT}"',
                "",
            ])
        return "\n".join(lines)

    if result.get("ok") and not result.get("dry_run"):
        lines.extend([
            "  NanoBK HTTPS 安全证书",
            "  ─────────────────────────────────────────────",
            "",
            "  已通过安全确认。",
        ])
        if result.get("existing_certificate"):
            lines.append("  已检测到 HTTPS 安全证书，当前不需要重新申请。")
        else:
            lines.append("  正在申请 HTTPS 安全证书……")
            lines.append("")
            lines.append("  完成：")
            for item in result.get("issued_certificates", []):
                lines.append(f"  {item['name']}")
        lines.extend([
            "",
            "  下一步：",
            "  nanobk setup production vps",
            "",
        ])
        return "\n".join(lines)

    lines.extend([
        "  NanoBK HTTPS 安全证书",
        "  ─────────────────────────────────────────────",
        "",
        f"  暂时不能继续：{result.get('error', '未知原因')}",
    ])
    next_step = result.get("next_step")
    if next_step == "select_domain":
        lines.append("  请先运行：nanobk setup domain")
    elif next_step == "setup_cloudflare":
        lines.append("  请先运行：nanobk setup cloudflare")
    elif next_step == "cert_targets":
        lines.append("  请检查证书目标域名。")
    elif next_step == "confirm_cert_issue":
        lines.append(f'  请使用：--confirm "{EXACT_PHRASE_CERT}"')
    lines.append("")
    return "\n".join(lines)


def _has_blocked_arg(argv):
    for arg in argv:
        if arg in BLOCKED_ARGS:
            return arg
    return None


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    blocked = _has_blocked_arg(argv)
    json_requested = "--json" in argv
    if blocked:
        result = _refusal(f"{blocked} 不适用于这个受控命令。", "confirm_cert_issue", "--dry-run" in argv)
        if json_requested:
            print(json.dumps(public_result(result), indent=2, ensure_ascii=False))
        else:
            print(output_text(result), file=sys.stderr)
        return 1

    parser = argparse.ArgumentParser(description="NanoBK production certificate issue")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--dry-run", action="store_true", help="Show plan only")
    parser.add_argument("--confirm", help="Exact safety confirmation phrase")
    args = parser.parse_args(argv)

    if args.dry_run:
        result = build_plan(dry_run=True)
    else:
        result = issue_certificates(args.confirm)

    if args.json:
        print(json.dumps(public_result(result), indent=2, ensure_ascii=False))
    else:
        stream = sys.stdout if result.get("ok") else sys.stderr
        print(output_text(result), file=stream)

    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
