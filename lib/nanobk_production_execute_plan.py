#!/usr/bin/env python3
"""
NanoBK Production Execute Plan (v2.6.0)

Preview-only controlled execution contract for the v2.6 production setup flow.
It imports existing v2.5 deploy-plan/gate data in-process where available and
does not run external commands.
"""

import argparse
import json
import sys

VERSION = "2.6.0"
MODE = "production_execute_plan_v2_6"
TOP_POLICY = "preview_only"

ACTION_TYPES = (
    "read_only",
    "local_write",
    "cloudflare_mutation",
    "cert_issue",
    "worker_deploy",
    "vps_install",
    "token_rotate",
    "protocol_rotate",
    "service_reload",
)

EXECUTION_POLICIES = (
    "preview_only",
    "manual_only",
    "confirm_required",
    "exact_gate_required",
)

_DANGEROUS_ARGS = {
    "--execute",
    "--yes",
    "--apply",
    "--issue",
    "--rotate",
    "--deploy",
    "--confirm",
}


def _load_v2_5_context():
    """Read existing v2.5 deploy-plan/gate structures in-process."""
    context = {
        "deploy_cards_available": False,
        "gate_summary_available": False,
        "deploy_card_ids": [],
    }
    try:
        from nanobk_production_preflight import gather_deploy_plan, gather_gates

        deploy_plan = gather_deploy_plan()
        gates = gather_gates()
        context["deploy_cards_available"] = bool(deploy_plan.get("cards"))
        context["gate_summary_available"] = bool(gates.get("gates"))
        context["deploy_card_ids"] = [
            card.get("id")
            for card in deploy_plan.get("cards", [])
            if card.get("id")
        ]
    except Exception:
        pass
    return context


def _action(action_id, title, action_type, execution_policy):
    return {
        "id": action_id,
        "title": title,
        "action_type": action_type,
        "execution_policy": execution_policy,
        "available_in_v2_6": True,
        "implemented_now": False,
        "manual_only": True,
        "will_modify": True,
    }


def build_actions():
    return [
        _action("dns_apply", "域名指向", "cloudflare_mutation", "exact_gate_required"),
        _action("worker_deploy", "订阅服务入口", "worker_deploy", "confirm_required"),
        _action("cert_issue", "HTTPS 安全证书", "cert_issue", "exact_gate_required"),
        _action("vps_install", "代理服务安装", "vps_install", "confirm_required"),
        _action("token_rotate", "重新生成订阅密钥", "token_rotate", "exact_gate_required"),
        _action("protocol_rotate", "更新代理通道密钥", "protocol_rotate", "confirm_required"),
    ]


def build_command_cards(actions):
    cards = []
    for action in actions:
        cards.append({
            "id": action["id"],
            "title": action["title"],
            "status": "即将接入",
            "safety_requirement": "需要确认",
            "execution_policy": action["execution_policy"],
            "preview_command": "nanobk setup production execute-plan",
            "future_execution_enabled": False,
            "manual_only": True,
            "will_modify": True,
        })
    return cards


def gather_execute_plan():
    actions = build_actions()
    return {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "execution_enabled": False,
        "policy": TOP_POLICY,
        "actions": actions,
        "command_cards": build_command_cards(actions),
        "supported_action_types": list(ACTION_TYPES),
        "supported_execution_policies": list(EXECUTION_POLICIES),
        "v2_5_context": _load_v2_5_context(),
        "safety": "read_only",
    }


def output_text(result):
    lines = [
        "",
        "  NanoBK 真实执行计划",
        "  ─────────────────────────────────────────────",
        "",
        "  当前版本只显示执行计划，不会真的修改任何东西。",
        "",
        "  后续 v2.6 会逐步接入：",
        "",
    ]

    for index, action in enumerate(result.get("actions", []), 1):
        lines.append(f"  {index}. {action['title']}")
        lines.append("      状态：即将接入")
        lines.append("      安全要求：需要确认")
        lines.append("")

    lines.append("  当前不会执行 DNS、证书、Worker、VPS 安装、密钥轮换或服务重启。")
    lines.append("")
    return "\n".join(lines)


def _reject_dangerous(argv):
    for arg in argv:
        if arg in _DANGEROUS_ARGS:
            return "此命令只显示执行计划，不会执行真实修改。"
    return None


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    error = _reject_dangerous(argv)
    json_requested = "--json" in argv
    if error:
        if json_requested:
            print(json.dumps({
                "ok": False,
                "error": error,
                "mode": MODE,
                "version": VERSION,
                "mutation": False,
                "dangerous_actions_executed": False,
                "execution_enabled": False,
                "policy": TOP_POLICY,
                "safety": "read_only",
            }, indent=2, ensure_ascii=False))
        else:
            print(f"  错误：{error}", file=sys.stderr)
        return 1

    parser = argparse.ArgumentParser(
        description="NanoBK production execute plan preview"
    )
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args(argv)

    result = gather_execute_plan()
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(output_text(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
