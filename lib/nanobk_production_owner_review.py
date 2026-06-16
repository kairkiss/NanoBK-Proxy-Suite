#!/usr/bin/env python3
"""
NanoBK Production Owner Review (v2.6.8)

Read-only owner review/status/next layer across the v2.6 production flow.
It never executes deployment, publish, rotation, or service commands.
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


VERSION = "2.6.8"
MODE = "production_owner_review_v2_6"

CLEAN_INSTALL_BLOCKER = "clean VPS full real install not yet validated"
LIVE_PUBLISH_BLOCKER = "live profile publish not yet validated"

STAGE_ORDER = [
    "cloudflare",
    "domain",
    "dns",
    "worker",
    "cert",
    "vps",
    "subscription",
    "owner_review",
]

LABELS = {
    "cloudflare": "Cloudflare",
    "domain": "域名",
    "dns": "DNS 解析",
    "worker": "订阅服务入口",
    "cert": "HTTPS 安全证书",
    "vps": "VPS 四协议",
    "subscription": "订阅配置",
    "owner_review": "最终确认",
}

NEXT_COMMANDS = {
    "cloudflare": "nanobk setup cloudflare",
    "domain": "nanobk setup domain",
    "dns": "nanobk setup production dns apply --dry-run",
    "worker": "nanobk setup production worker deploy --dry-run",
    "cert": "nanobk setup production cert issue --dry-run",
    "vps": "nanobk setup production vps install --dry-run",
    "subscription": "nanobk setup production subscription publish --dry-run",
    "owner_review": "nanobk setup production review",
    "repair_or_review": "nanobk setup production review",
}

DOMAIN_RE = re.compile(
    r"^(?=.{1,253}$)(?!-)[A-Za-z0-9-]{1,63}(?<!-)"
    r"(\.(?!-)[A-Za-z0-9-]{1,63}(?<!-))+$"
)


def _safe_domain(value):
    candidate = (value or "").strip().lower().rstrip(".")
    if not candidate or not DOMAIN_RE.match(candidate):
        return None
    return candidate


def _selected_domain_real():
    selected, _err = load_selected_domain()
    if selected and selected.get("selected_domain"):
        safe = _safe_domain(selected.get("selected_domain"))
        if safe:
            return safe

    profile, err = load_profile()
    if not err and isinstance(profile, dict):
        return _safe_domain(profile.get("zone_name", ""))

    return None


def _admin_env_present():
    try:
        from nanobk_production_subscription_publish import _admin_summary

        admin = _admin_summary()
        return bool(
            admin.get("env_present")
            and admin.get("update_endpoint_present")
            and admin.get("current_endpoint_present")
            and admin.get("admin_token_present")
        )
    except Exception:
        return False


def _fake_enabled():
    return any(key.startswith("NANOBK_FAKE_REVIEW_") for key in os.environ)


def _fake_state(name, default="missing"):
    return os.environ.get(f"NANOBK_FAKE_REVIEW_{name.upper()}", default)


def _stage(name, status, next_command="", note=""):
    dangerous = name in {"dns", "worker", "cert", "vps", "subscription"}
    mutation_required = dangerous
    return {
        "name": name,
        "label": LABELS[name],
        "status": status,
        "mutation_required": mutation_required,
        "dangerous": dangerous,
        "next_command": next_command,
        "note": note,
    }


def _release_blockers():
    blockers = []
    if os.environ.get("NANOBK_FAKE_REVIEW_CLEAN_INSTALL_VALIDATED") != "1":
        blockers.append(CLEAN_INSTALL_BLOCKER)
    if os.environ.get("NANOBK_FAKE_REVIEW_LIVE_PUBLISH_VALIDATED") != "1":
        blockers.append(LIVE_PUBLISH_BLOCKER)
    return blockers


def _fake_stages():
    cloudflare_raw = _fake_state("cloudflare", "missing")
    cloudflare_status = "done" if cloudflare_raw == "done" else "missing"

    domain_raw = _fake_state("domain", "missing")
    domain = _safe_domain(domain_raw)
    domain_status = "done" if domain else "missing"

    dns_status = _normalize_fake_status(_fake_state("dns", "missing"))
    worker_status = _normalize_fake_status(_fake_state("worker", "missing"))
    cert_status = _normalize_fake_status(_fake_state("cert", "missing"))
    vps_raw = _fake_state("vps", "missing")
    vps_status = "blocked" if vps_raw == "partial" else _normalize_fake_status(vps_raw)
    subscription_status = _normalize_fake_status(_fake_state("subscription", "missing"))

    stages = [
        _stage(
            "cloudflare",
            cloudflare_status,
            "" if cloudflare_status == "done" else NEXT_COMMANDS["cloudflare"],
            "已连接" if cloudflare_status == "done" else "未连接",
        ),
        _stage(
            "domain",
            domain_status,
            "" if domain_status == "done" else NEXT_COMMANDS["domain"],
            f"已选择 {domain}" if domain else "未选择",
        ),
        _stage(
            "dns",
            dns_status,
            "" if dns_status == "done" else NEXT_COMMANDS["dns"],
            _note_for_status(dns_status),
        ),
        _stage(
            "worker",
            worker_status,
            "" if worker_status == "done" else NEXT_COMMANDS["worker"],
            _note_for_status(worker_status),
        ),
        _stage(
            "cert",
            cert_status,
            "" if cert_status == "done" else NEXT_COMMANDS["cert"],
            _note_for_status(cert_status),
        ),
        _stage(
            "vps",
            vps_status,
            NEXT_COMMANDS["repair_or_review"] if vps_status == "blocked" else ("" if vps_status == "done" else NEXT_COMMANDS["vps"]),
            "检测到部分安装，请先人工检查。" if vps_status == "blocked" else _note_for_status(vps_status),
        ),
        _stage(
            "subscription",
            subscription_status,
            "" if subscription_status == "done" else NEXT_COMMANDS["subscription"],
            _note_for_status(subscription_status),
        ),
    ]

    blockers = _release_blockers()
    prior_done = all(item["status"] == "done" for item in stages)
    if prior_done and not blockers:
        owner_status = "done"
        note = "最终确认已完成。"
    elif prior_done:
        owner_status = "ready"
        note = "仍有上线验证说明需要确认。"
    else:
        owner_status = "missing"
        note = "前置步骤未完成。"
    stages.append(_stage("owner_review", owner_status, NEXT_COMMANDS["owner_review"], note))
    return stages, blockers


def _normalize_fake_status(value):
    if value in {"done", "ready", "missing", "blocked", "unknown"}:
        return value
    return "missing"


def _note_for_status(status):
    return {
        "done": "已完成",
        "ready": "待确认",
        "missing": "未完成",
        "blocked": "暂停项",
        "unknown": "状态未知",
    }.get(status, "状态未知")


def _call_plan(func, fallback):
    try:
        return func(dry_run=True)
    except Exception:
        return fallback


def _real_stages():
    connected = bool(detect_cloudflare_connection().get("connected"))
    domain = _selected_domain_real()

    stages = [
        _stage(
            "cloudflare",
            "done" if connected else "missing",
            "" if connected else NEXT_COMMANDS["cloudflare"],
            "已连接" if connected else "未连接",
        ),
        _stage(
            "domain",
            "done" if domain else "missing",
            "" if domain else NEXT_COMMANDS["domain"],
            f"已选择 {domain}" if domain else "未选择",
        ),
    ]

    dns_status = "ready" if domain and connected else "missing"
    stages.append(_stage("dns", dns_status, "" if dns_status == "done" else NEXT_COMMANDS["dns"], _note_for_status(dns_status)))

    worker_status = "done" if _admin_env_present() else ("ready" if domain and connected else "missing")
    stages.append(_stage("worker", worker_status, "" if worker_status == "done" else NEXT_COMMANDS["worker"], _note_for_status(worker_status)))

    cert_status = "ready" if domain and connected else "missing"
    try:
        from nanobk_production_cert_issue import build_plan as cert_plan

        cert = _call_plan(cert_plan, {})
        if cert.get("ok") and cert.get("existing_certificate"):
            cert_status = "done"
        elif not cert.get("ok"):
            cert_status = "missing"
    except Exception:
        pass
    stages.append(_stage("cert", cert_status, "" if cert_status == "done" else NEXT_COMMANDS["cert"], _note_for_status(cert_status)))

    vps_status = "missing"
    vps_command = NEXT_COMMANDS["vps"]
    vps_note = "未完成"
    try:
        from nanobk_production_vps_install import build_plan as vps_plan

        vps = _call_plan(vps_plan, {})
        if vps.get("ok") and vps.get("existing_install"):
            vps_status = "done"
            vps_command = ""
            vps_note = "已安装"
        elif not vps.get("ok") and vps.get("next_step") == "repair_or_review":
            vps_status = "blocked"
            vps_command = NEXT_COMMANDS["repair_or_review"]
            vps_note = "检测到部分安装，请先人工检查。"
        elif vps.get("ok"):
            vps_status = "ready"
            vps_note = "待安装"
    except Exception:
        pass
    stages.append(_stage("vps", vps_status, vps_command, vps_note))

    subscription_status = "missing"
    subscription_command = NEXT_COMMANDS["subscription"]
    subscription_note = "未完成"
    try:
        from nanobk_production_subscription_publish import build_plan as subscription_plan

        sub = _call_plan(subscription_plan, {})
        if sub.get("ok") and sub.get("existing_publish"):
            subscription_status = "done"
            subscription_command = ""
            subscription_note = "已发布"
        elif sub.get("ok"):
            subscription_status = "ready"
            subscription_note = "待发布"
        elif sub.get("next_step") == "repair_or_review":
            subscription_status = "blocked"
            subscription_command = NEXT_COMMANDS["repair_or_review"]
            subscription_note = "代理配置档案需要检查。"
    except Exception:
        pass
    stages.append(_stage("subscription", subscription_status, subscription_command, subscription_note))

    blockers = _release_blockers()
    prior_done = all(item["status"] == "done" for item in stages)
    if prior_done and not blockers:
        owner_status = "done"
        owner_note = "最终确认已完成。"
    elif prior_done:
        owner_status = "ready"
        owner_note = "仍有上线验证说明需要确认。"
    else:
        owner_status = "missing"
        owner_note = "前置步骤未完成。"
    stages.append(_stage("owner_review", owner_status, NEXT_COMMANDS["owner_review"], owner_note))
    return stages, blockers


def _first_action(stages):
    for stage in stages:
        if stage["status"] == "blocked":
            return stage["name"], "repair_or_review", stage["next_command"] or NEXT_COMMANDS["repair_or_review"]
        if stage["status"] != "done":
            return stage["name"], _next_step_for_stage(stage["name"]), stage["next_command"] or NEXT_COMMANDS[stage["name"]]
    return "owner_review", "owner_review", NEXT_COMMANDS["owner_review"]


def _next_step_for_stage(name):
    return {
        "cloudflare": "connect_cloudflare",
        "domain": "select_domain",
        "dns": "dns_apply",
        "worker": "worker_deploy",
        "cert": "cert_issue",
        "vps": "vps_install",
        "subscription": "subscription_publish",
        "owner_review": "owner_review",
    }[name]


def _readiness(stages, blockers):
    prior = [item for item in stages if item["name"] != "owner_review"]
    if all(item["status"] == "done" for item in prior):
        return "ready" if not blockers else "ready_with_notes"
    return "not_ready"


def build_review():
    stages, blockers = _fake_stages() if _fake_enabled() else _real_stages()
    current_stage, next_step, next_command = _first_action(stages)
    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "readiness": _readiness(stages, blockers),
        "current_stage": current_stage,
        "next_step": next_step,
        "next_command": next_command,
        "stages": stages,
        "release_blockers": blockers,
        "safety": "read_only",
    }


def _status_text(status):
    return {
        "done": "已完成",
        "ready": "待确认",
        "missing": "未完成",
        "blocked": "暂停项",
        "unknown": "状态未知",
    }.get(status, "状态未知")


def output_text(result):
    by_name = {stage["name"]: stage for stage in result["stages"]}
    lines = [
        "",
        "  NanoBK 生产环境总检查",
        "  ─────────────────────────────────────────────",
        "",
        f"  Cloudflare：{_status_text(by_name['cloudflare']['status'])}",
        f"  域名：{by_name['domain']['note']}",
        f"  DNS：{_status_text(by_name['dns']['status'])}",
        f"  Worker：{_status_text(by_name['worker']['status'])}",
        f"  证书：{_status_text(by_name['cert']['status'])}",
        f"  VPS 四协议：{_status_text(by_name['vps']['status'])}",
        f"  订阅配置：{_status_text(by_name['subscription']['status'])}",
        f"  最终确认：{_status_text(by_name['owner_review']['status'])}",
        "",
    ]

    if result.get("release_blockers"):
        lines.append("  注意项：")
        for blocker in result["release_blockers"]:
            lines.append(f"  - {blocker}")
        lines.append("")

    lines.extend(
        [
            "  下一步：",
            f"  {result['next_command']}",
            "",
            "  安全说明：",
            "  当前只是检查，不会修改 DNS、Worker、证书、VPS 或订阅。",
            "",
        ]
    )
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description="NanoBK production owner review")
    parser.add_argument("command", nargs="?", choices=["review", "status", "next"], default="review")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(sys.argv[1:] if argv is None else argv)

    result = build_review()
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False, sort_keys=True))
    else:
        print(output_text(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
