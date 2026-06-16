#!/usr/bin/env python3
"""
NanoBK Production Guided Flow (v2.6.9)

Beginner-facing, read-only production guide. It derives readiness from the
owner review layer and never bypasses the controlled stage wrappers.
"""

import argparse
import json
import os
import shlex
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from nanobk_production_owner_review import build_review, output_text as review_text


VERSION = "2.6.9"
MODE = "production_guided_flow_v2_6"

SAFE_AUTO_DRY_RUN = {
    "dns": "nanobk setup production dns apply --dry-run --json",
    "worker": "nanobk setup production worker deploy --dry-run --json",
    "cert": "nanobk setup production cert issue --dry-run --json",
    "vps": "nanobk setup production vps install --dry-run --json",
    "subscription": "nanobk setup production subscription publish --dry-run --json",
}

ACTION_LABELS = {
    "cloudflare": "setup_first",
    "domain": "setup_first",
    "dns": "dry_run_first",
    "worker": "dry_run_first",
    "cert": "dry_run_first",
    "vps": "dry_run_first",
    "subscription": "dry_run_first",
    "owner_review": "none",
}


def _guide_action(review):
    if review.get("next_step") == "repair_or_review":
        return "repair_or_review"
    if review.get("current_stage") == "owner_review" or review.get("readiness") in {"ready", "ready_with_notes"}:
        return "owner_review"
    command = review.get("next_command", "")
    if "--dry-run" in command:
        return "run_next_dry_run"
    return "run_next_dry_run"


def _guided_steps(review):
    steps = []
    for stage in review.get("stages", []):
        command = stage.get("next_command", "")
        action = "none"
        if stage.get("status") != "done":
            action = ACTION_LABELS.get(stage.get("name"), "none")
        steps.append(
            {
                "stage": stage.get("name"),
                "status": stage.get("status"),
                "command": command,
                "action": action,
                "dangerous": bool(stage.get("dangerous")),
            }
        )
    return steps


def _safe_command_for_stage(stage_name):
    return SAFE_AUTO_DRY_RUN.get(stage_name, "")


def _fake_auto_result(stage_name, command):
    mode = os.environ.get("NANOBK_FAKE_GUIDE_AUTO_DRY_RUN", "")
    if mode not in {"success", "blocked", "failure"}:
        return None
    if not command:
        return None
    if mode == "success":
        return {
            "stage": stage_name,
            "command": command,
            "exit_code": 0,
            "ok": True,
            "summary": "redacted",
        }
    if mode == "blocked":
        return {
            "stage": stage_name,
            "command": command,
            "exit_code": 1,
            "ok": False,
            "summary": "redacted blocked",
        }
    return {
        "stage": stage_name,
        "command": command,
        "exit_code": 1,
        "ok": False,
        "summary": "redacted failure",
    }


def _auto_dry_run(review):
    stage = review.get("current_stage", "")
    command = _safe_command_for_stage(stage)
    fake = _fake_auto_result(stage, command)
    if fake:
        return [fake]
    if not command:
        return []

    argv = shlex.split(command)
    if argv[:3] != ["nanobk", "setup", "production"]:
        return []
    if "--dry-run" not in argv or "--json" not in argv:
        return []

    repo_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    argv[0] = os.path.join(repo_dir, "bin", "nanobk")
    try:
        completed = subprocess.run(
            argv,
            cwd=repo_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return [
            {
                "stage": stage,
                "command": command,
                "exit_code": 124,
                "ok": False,
                "summary": "redacted timeout",
            }
        ]

    ok_value = False
    try:
        parsed = json.loads(completed.stdout)
        ok_value = bool(parsed.get("ok"))
    except json.JSONDecodeError:
        ok_value = completed.returncode == 0

    return [
        {
            "stage": stage,
            "command": command,
            "exit_code": completed.returncode,
            "ok": ok_value,
            "summary": "redacted",
        }
    ]


def build_guide(step="all", auto_dry_run=False):
    review = build_review()
    steps = _guided_steps(review)
    if step == "next":
        steps = [item for item in steps if item["stage"] == review.get("current_stage")]
    result = {
        "ok": True,
        "mode": MODE,
        "version": VERSION,
        "mutation": False,
        "dangerous_actions_executed": False,
        "readiness": review.get("readiness"),
        "current_stage": review.get("current_stage"),
        "next_step": review.get("next_step"),
        "next_command": review.get("next_command"),
        "guide_action": _guide_action(review),
        "guided_steps": steps,
        "auto_dry_run_results": [],
        "release_blockers": list(review.get("release_blockers", [])),
        "safety": "read_only",
    }
    if auto_dry_run:
        result["auto_dry_run_results"] = _auto_dry_run(review)
    return result


def _status_text(status):
    return {
        "done": "已完成",
        "ready": "待确认",
        "missing": "未完成",
        "blocked": "暂停项",
        "unknown": "状态未知",
    }.get(status, "状态未知")


def output_text(result):
    lines = [
        "",
        "  NanoBK 生产配置向导",
        "  ─────────────────────────────────────────────",
        "  当前状态：",
    ]
    for step in result.get("guided_steps", []):
        label = {
            "cloudflare": "Cloudflare",
            "domain": "域名",
            "dns": "DNS",
            "worker": "Worker",
            "cert": "证书",
            "vps": "VPS 四协议",
            "subscription": "订阅配置",
            "owner_review": "最终确认",
        }.get(step["stage"], step["stage"])
        lines.append(f"  {label}：{_status_text(step['status'])}")

    lines.extend(
        [
            f"  当前卡在：{result.get('current_stage')}",
            "  下一步先运行：",
            f"  {result.get('next_command')}",
            "",
            "  重要：",
            "  我不会自动执行真实写入。",
            "  真实操作需要你输入对应阶段的安全确认短语，并按该阶段要求设置环境保护开关。",
        ]
    )

    if result.get("auto_dry_run_results"):
        lines.append("")
        lines.append("  自动检查结果：")
        for item in result["auto_dry_run_results"]:
            state = "通过" if item.get("ok") else "未通过"
            lines.append(f"  {item.get('stage')}：{state}")

    if result.get("release_blockers"):
        lines.append("")
        lines.append("  仍需最终验证：")
        for blocker in result["release_blockers"]:
            lines.append(f"  - {blocker}")

    lines.append("")
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description="NanoBK guided production flow")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--auto-dry-run", action="store_true")
    parser.add_argument("--step", choices=["next", "all"], default="all")
    args = parser.parse_args(sys.argv[1:] if argv is None else argv)

    result = build_guide(step=args.step, auto_dry_run=args.auto_dry_run)
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False, sort_keys=True))
    else:
        print(output_text(result))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
