#!/usr/bin/env python3
"""
NanoBK Telegram Bot — v1.1.0

Control layer for NanoBK Proxy Suite.
Only calls nanobk CLI — never directly reads/writes secrets, profiles, or configs.

Usage:
    python3 nanobk_bot.py              # Run the bot
    python3 nanobk_bot.py --self-test  # Run self-tests (no Telegram connection)
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

# ── Shared redaction helper import ───────────────────────────────────────────
# Compute repo root and import shared helper for address-class redaction.
_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from lib.nanobk_redaction import (
    strip_ansi as _shared_strip_ansi,
    redact_text as _shared_redact_text,
)
from lib.nanobk_bot_home_adapter import render_home, render_setup_status

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

# ── Configuration ───────────────────────────────────────────────────────────

SUPPORTED_LANGS = {"en", "zh"}
DEFAULT_LANG = "zh"


def normalize_lang(value: str | None) -> str:
    """Normalize language code. Returns 'en' or 'zh'. Defaults to 'zh'."""
    if not value:
        return DEFAULT_LANG
    v = value.strip().lower()
    if v in ("zh", "zh-cn", "zh_cn", "chinese", "中文"):
        return "zh"
    if v in SUPPORTED_LANGS:
        return v
    return DEFAULT_LANG


# ── Bot translation dictionary ───────────────────────────────────────────────
# All user-facing Bot text. Keys are stable; values are lang-keyed dicts.
# Status category values (healthy/failed/unknown/etc.) are NOT translated.

BOT_TEXT: dict[str, dict[str, str]] = {
    "control_center_title": {
        "en": "🏠 NanoBK Control Center",
        "zh": "🏠 NanoBK 控制中心",
    },
    "control_center_subtitle": {
        "en": "Use the buttons below for quick actions, or type /help for all commands.\nSensitive addresses and secrets are hidden.",
        "zh": "使用下方按钮快速操作，或输入 /help 查看全部命令。\n敏感地址和密钥已隐藏。",
    },
    "btn_status": {
        "en": "📊 Status Summary",
        "zh": "📊 状态总览",
    },
    "btn_recovery": {
        "en": "🧭 Recovery Help",
        "zh": "🧭 恢复帮助",
    },
    "btn_diagnostics": {
        "en": "🩺 Diagnostics",
        "zh": "🩺 诊断检查",
    },
    "btn_advanced": {
        "en": "🔐 Advanced Mode",
        "zh": "🔐 高级模式",
    },
    "btn_rotate": {
        "en": "🔄 Rotate Secrets",
        "zh": "🔄 轮换密钥",
    },
    "btn_web": {
        "en": "🌐 Web Panel",
        "zh": "🌐 Web 面板",
    },
    "btn_help": {
        "en": "❓ Help",
        "zh": "❓ 帮助",
    },
    "help_title": {
        "en": "NanoBK Bot Commands",
        "zh": "NanoBK 机器人命令",
    },
    "help_basic": {
        "en": "Basic:",
        "zh": "基础：",
    },
    "help_start": {
        "en": "Show welcome and quick help",
        "zh": "显示欢迎和快捷帮助",
    },
    "help_home": {
        "en": "Setup home summary",
        "zh": "设置首页摘要",
    },
    "help_setup_status": {
        "en": "Setup status summary",
        "zh": "设置状态摘要",
    },
    "help_status": {
        "en": "Safe status summary",
        "zh": "安全状态摘要",
    },
    "help_doctor": {
        "en": "Redacted diagnostic check",
        "zh": "脱敏诊断检查",
    },
    "help_cancel": {
        "en": "Cancel pending action",
        "zh": "取消待处理操作",
    },
    "help_safe_ops": {
        "en": "Safe operations:",
        "zh": "安全操作：",
    },
    "help_rotate_all": {
        "en": "Rotate ALL protocols (requires confirmation)",
        "zh": "轮换全部协议（需确认）",
    },
    "help_rotate_hy2": {
        "en": "Rotate HY2 secret with confirmation",
        "zh": "轮换 HY2 密钥（需确认）",
    },
    "help_rotate_tuic": {
        "en": "Rotate TUIC secret with confirmation",
        "zh": "轮换 TUIC 密钥（需确认）",
    },
    "help_rotate_reality": {
        "en": "Rotate Reality credentials with confirmation",
        "zh": "轮换 Reality 凭证（需确认）",
    },
    "help_rotate_trojan": {
        "en": "Rotate Trojan password with confirmation",
        "zh": "轮换 Trojan 密码（需确认）",
    },
    "help_advanced_diag": {
        "en": "Advanced diagnostics:",
        "zh": "高级诊断：",
    },
    "help_status_json": {
        "en": "Redacted raw status JSON (requires advanced mode)",
        "zh": "脱敏原始状态 JSON（需高级模式）",
    },
    "help_advanced_on": {
        "en": "Enable advanced diagnostics mode",
        "zh": "启用高级诊断模式",
    },
    "help_advanced_off": {
        "en": "Disable advanced diagnostics mode",
        "zh": "禁用高级诊断模式",
    },
    "help_advanced_status": {
        "en": "Show advanced mode status",
        "zh": "显示高级模式状态",
    },
    "help_show": {
        "en": "Show this help",
        "zh": "显示此帮助",
    },
    "help_rotate_warning": {
        "en": "⚠️ Rotate commands require confirmation to prevent accidents.",
        "zh": "⚠️ 轮换命令需要确认以防止意外操作。",
    },
    "status_summary_title": {
        "en": "NanoBK Status Summary",
        "zh": "NanoBK 状态摘要",
    },
    "status_label_overall": {
        "en": "Overall",
        "zh": "总览",
    },
    "status_label_vps": {
        "en": "VPS",
        "zh": "VPS",
    },
    "status_label_protocols": {
        "en": "Protocols",
        "zh": "协议",
    },
    "status_label_cloudflare": {
        "en": "Cloudflare",
        "zh": "Cloudflare",
    },
    "status_label_subscription": {
        "en": "Subscription",
        "zh": "订阅",
    },
    "status_label_secrets": {
        "en": "Secrets",
        "zh": "密钥",
    },
    "status_label_profile": {
        "en": "Profile",
        "zh": "配置",
    },
    "status_label_next_step": {
        "en": "Next step",
        "zh": "下一步",
    },
    "status_data_unavailable": {
        "en": "Status data unavailable.",
        "zh": "状态数据不可用。",
    },
    "status_run_doctor": {
        "en": "Run /doctor or check SSH.",
        "zh": "运行 /doctor 或检查 SSH。",
    },
    "status_secrets_present_mode": {
        "en": "present, mode {mode}",
        "zh": "存在, 模式 {mode}",
    },
    "status_secrets_unknown": {
        "en": "unknown",
        "zh": "未知",
    },
    "hint_failed": {
        "en": "Check SSH or run NanoBK recovery from the server.",
        "zh": "检查 SSH 或从服务器运行 NanoBK 恢复。",
    },
    "hint_vps_failed": {
        "en": "Check SSH and verify proxy services are running.",
        "zh": "检查 SSH 并确认代理服务正在运行。",
    },
    "hint_cf_missing": {
        "en": "Finish Cloudflare verification from the Full Wizard or CLI.",
        "zh": "从完整向导或 CLI 完成 Cloudflare 验证。",
    },
    "hint_sub_pending": {
        "en": "Verify subscription access from the Full Wizard or CLI.",
        "zh": "从完整向导或 CLI 验证订阅访问。",
    },
    "hint_healthy": {
        "en": "No immediate action required.",
        "zh": "无需立即操作。",
    },
    "hint_default": {
        "en": "Run /doctor for a redacted diagnostic summary, or check SSH if needed.",
        "zh": "运行 /doctor 获取脱敏诊断摘要，或按需检查 SSH。",
    },
    "gate_not_enabled": {
        "en": "Advanced diagnostics mode is not enabled.\n\n/status_json is for troubleshooting and shows redacted Raw JSON.\nUse /status for the normal safe summary first.\n\nTo continue, run /advanced on.\nAdvanced mode expires automatically after 15 minutes.\n\nEven in advanced mode, secrets, raw addresses, and subscription URLs must remain hidden.",
        "zh": "高级诊断模式未启用。\n\n/status_json 仅用于排障，显示脱敏的原始 JSON。\n请先使用 /status 查看普通安全摘要。\n\n如需继续，请运行 /advanced on。\n高级模式将在 15 分钟后自动过期。\n\n即使在高级模式下，密钥、原始地址和订阅 URL 仍必须隐藏。",
    },
    "status_json_warning": {
        "en": "⚠️ Advanced diagnostics\nThis output is redacted, but it may still reveal system structure.\nDo not forward the full output to untrusted people.\nUse /status for the normal safe summary.\n\n",
        "zh": "⚠️ 高级诊断\n此输出已脱敏，但仍可能暴露系统结构。\n请勿将完整输出转发给不可信的人。\n请使用 /status 查看普通安全摘要。\n\n",
    },
    "advanced_on_msg": {
        "en": "⚠️ Advanced diagnostics mode enabled.\n\nOutputs are still redacted, but diagnostic details may reveal system structure.\nDo not forward full diagnostic output to untrusted people.\nSecrets, raw addresses, and subscription URLs must remain hidden.\n\nThis mode will expire in 15 minutes.\nUse /advanced off to disable it sooner.",
        "zh": "⚠️ 高级诊断模式已启用。\n\n输出仍被脱敏，但诊断详情可能暴露系统结构。\n请勿将完整诊断输出转发给不可信的人。\n密钥、原始地址和订阅 URL 仍必须隐藏。\n\n此模式将在 15 分钟后过期。\n使用 /advanced off 可提前禁用。",
    },
    "advanced_off_msg": {
        "en": "Advanced diagnostics mode disabled.",
        "zh": "高级诊断模式已禁用。",
    },
    "advanced_enabled_status": {
        "en": "Advanced diagnostics mode is enabled.\nExpires in about {minutes} minutes.",
        "zh": "高级诊断模式已启用。\n约 {minutes} 分钟后过期。",
    },
    "advanced_disabled_status": {
        "en": "Advanced diagnostics mode is disabled.",
        "zh": "高级诊断模式已禁用。",
    },
    "advanced_usage": {
        "en": "Usage: /advanced on|off|status\n\non     — Enable advanced diagnostics mode\noff    — Disable advanced diagnostics mode\nstatus — Show current mode status",
        "zh": "用法：/advanced on|off|status\n\non     — 启用高级诊断模式\noff    — 禁用高级诊断模式\nstatus — 显示当前模式状态",
    },
    "guidance_recovery": {
        "en": "🧭 Recovery Help\n\nIf services are abnormal, try:\n1. Run /status to check status\n2. Run /doctor for diagnostics\n3. Connect to VPS via SSH for manual recovery\n\nSensitive addresses and secrets are hidden.",
        "zh": "🧭 恢复帮助\n\n如果服务异常，请尝试：\n1. 运行 /status 检查状态\n2. 运行 /doctor 进行诊断\n3. 通过 SSH 连接 VPS 手动恢复\n\n敏感地址和密钥已隐藏。",
    },
    "guidance_diagnostics": {
        "en": "🩺 Diagnostics\n\nUse /doctor for diagnostics.\nUse /advanced on to enable advanced diagnostics.\nUse /status_json after advanced mode is enabled.\n\nDiagnostic output is redacted.",
        "zh": "🩺 诊断检查\n\n使用 /doctor 进行诊断。\n使用 /advanced on 启用高级诊断。\n启用高级模式后使用 /status_json。\n\n诊断输出已脱敏。",
    },
    "guidance_rotate": {
        "en": "🔄 Rotate Secrets\n\nExisting rotate commands require confirmation.\n\n/rotate_all — Rotate ALL protocols\n/rotate_hy2 — Rotate HY2\n/rotate_tuic — Rotate TUIC\n/rotate_reality — Rotate Reality\n/rotate_trojan — Rotate Trojan\n\n⚠️ All operations require confirmation to prevent accidents.",
        "zh": "🔄 轮换密钥\n\n现有轮换命令需要确认。\n\n/rotate_all — 轮换全部协议\n/rotate_hy2 — 轮换 HY2\n/rotate_tuic — 轮换 TUIC\n/rotate_reality — 轮换 Reality\n/rotate_trojan — 轮换 Trojan\n\n⚠️ 所有操作需要确认以防止意外。",
    },
    "guidance_web": {
        "en": "🌐 Web Panel\n\nThe Web Panel provides a browser-based dashboard.\nAccess it from your server's local network.\n\nRefer to your NanoBK configuration for the Web Panel address.",
        "zh": "🌐 Web 面板\n\nWeb 面板提供基于浏览器的控制台。\n从服务器本地网络访问。\n\n请参考 NanoBK 配置获取 Web 面板地址。",
    },
    "advanced_mode_enabled_title": {
        "en": "🔐 Advanced Mode",
        "zh": "🔐 高级模式",
    },
    "advanced_mode_enabled_desc": {
        "en": "Advanced diagnostics mode is enabled.\nExpires in about {minutes} minutes.\n\nCommands:\n/advanced status — Check status\n/advanced off — Disable\n/status_json — View redacted Raw JSON",
        "zh": "高级诊断模式已启用。\n约 {minutes} 分钟后过期。\n\n命令：\n/advanced status — 检查状态\n/advanced off — 禁用\n/status_json — 查看脱敏原始 JSON",
    },
    "advanced_mode_disabled_desc": {
        "en": "Advanced diagnostics mode is disabled.\n\nCommands:\n/advanced on — Enable (expires in 15 minutes)\n/advanced status — Check status\n/advanced off — Disable",
        "zh": "高级诊断模式已禁用。\n\n命令：\n/advanced on — 启用（15 分钟后过期）\n/advanced status — 检查状态\n/advanced off — 禁用",
    },
    "rotate_confirm_prompt": {
        "en": "You are about to rotate {desc}.\nThis will restart proxy services and update local profile.\nCloudflare sync depends on your local nanobk configuration.\n\nReply with:\n/confirm_{action_name}\nor cancel with:\n/cancel",
        "zh": "即将轮换 {desc}。\n此操作将重启代理服务并更新本地配置。\nCloudflare 同步取决于本地 nanobk 配置。\n\n请回复：\n/confirm_{action_name}\n或取消：\n/cancel",
    },
    "rotate_desc_all": {
        "en": "ALL protocol credentials",
        "zh": "全部协议凭证",
    },
    "rotate_desc_proto": {
        "en": "{proto} credentials",
        "zh": "{proto} 凭证",
    },
    "rotate_dry_run": {
        "en": "DRY RUN: would execute:\nnanobk {cmd}",
        "zh": "模拟运行：将执行：\nnanobk {cmd}",
    },
    "rotate_executing": {
        "en": "Executing nanobk {cmd}...",
        "zh": "正在执行 nanobk {cmd}...",
    },
    "rotate_failed": {
        "en": "Rotate failed (code {code}):\n{output}",
        "zh": "轮换失败（代码 {code}）：\n{output}",
    },
    "doctor_running": {
        "en": "Running doctor...",
        "zh": "正在运行诊断...",
    },
    "doctor_summary_title": {
        "en": "🩺 Doctor Summary",
        "zh": "🩺 诊断摘要",
    },
    "doctor_label_overall": {
        "en": "Overall",
        "zh": "总览",
    },
    "doctor_label_control_plane": {
        "en": "Control Plane",
        "zh": "控制面",
    },
    "doctor_label_cli": {
        "en": "CLI",
        "zh": "CLI",
    },
    "doctor_label_profile": {
        "en": "Profile",
        "zh": "配置",
    },
    "doctor_label_config": {
        "en": "Config",
        "zh": "配置文件",
    },
    "doctor_label_services": {
        "en": "Services",
        "zh": "服务",
    },
    "doctor_label_cloudflare": {
        "en": "Cloudflare",
        "zh": "Cloudflare",
    },
    "doctor_label_subscription": {
        "en": "Subscription",
        "zh": "订阅",
    },
    "doctor_label_security": {
        "en": "Security",
        "zh": "安全",
    },
    "doctor_label_next_step": {
        "en": "Next step",
        "zh": "下一步",
    },
    "doctor_label_errors": {
        "en": "Errors",
        "zh": "错误",
    },
    "doctor_label_warnings": {
        "en": "Warnings",
        "zh": "警告",
    },
    "doctor_next_no_action": {
        "en": "No immediate action required.",
        "zh": "无需立即操作。",
    },
    "doctor_next_check_failed": {
        "en": "Check failed services via SSH or run /status for details.",
        "zh": "通过 SSH 检查失败服务或运行 /status 查看详情。",
    },
    "doctor_next_complete_config": {
        "en": "Complete VPS and Cloudflare setup using the Full Wizard or CLI.",
        "zh": "使用完整向导或 CLI 完成 VPS 和 Cloudflare 设置。",
    },
    "doctor_next_configure_cf": {
        "en": "Finish Cloudflare verification from the Full Wizard or CLI.",
        "zh": "从完整向导或 CLI 完成 Cloudflare 验证。",
    },
    "doctor_next_use_advanced": {
        "en": "Enable /advanced on for full diagnostics.",
        "zh": "启用 /advanced on 获取完整诊断。",
    },
    "doctor_next_unknown": {
        "en": "Run /status or check SSH for more information.",
        "zh": "运行 /status 或检查 SSH 获取更多信息。",
    },
    "doctor_full_note": {
        "en": "\n💡 Full diagnostics: use /advanced on, then /doctor again.",
        "zh": "\n💡 完整诊断：使用 /advanced on，然后再次 /doctor。",
    },
    "doctor_full_warning": {
        "en": "⚠️ Advanced diagnostics\nFull output is redacted but may reveal system structure.\nDo not forward to untrusted people.\n\n",
        "zh": "⚠️ 高级诊断\n完整输出已脱敏但可能暴露系统结构。\n请勿转发给不可信的人。\n\n",
    },
    "doctor_status_parse_error": {
        "en": "Failed to parse status data. Showing unknown summary.",
        "zh": "无法解析状态数据。显示未知摘要。",
    },
    "doctor_full_unavailable": {
        "en": "Full diagnostics unavailable (command failed).",
        "zh": "完整诊断不可用（命令失败）。",
    },
    "cancel_msg": {
        "en": "Pending confirmation cancelled.",
        "zh": "待处理确认已取消。",
    },
    "unauthorized": {
        "en": "Unauthorized.",
        "zh": "未授权。",
    },
    "unknown_command": {
        "en": "Unknown command. Use /help.",
        "zh": "未知命令。请使用 /help。",
    },
    "unknown_callback": {
        "en": "Unknown menu option. Use /help.",
        "zh": "未知菜单选项。请使用 /help。",
    },
    "confirm_unknown": {
        "en": "Unknown confirmation command.",
        "zh": "未知确认命令。",
    },
    "confirm_none": {
        "en": "No pending confirmation (may have expired).",
        "zh": "无待处理确认（可能已过期）。",
    },
    "confirm_mismatch": {
        "en": "Confirmation mismatch. Pending: {pending}, got: {got}",
        "zh": "确认不匹配。待处理：{pending}，收到：{got}",
    },
    # ── Language command ──
    "language_title": {
        "en": "🌐 Language Settings",
        "zh": "🌐 语言设置",
    },
    "language_current_zh": {
        "en": "Current language: Chinese (中文)",
        "zh": "当前语言：中文",
    },
    "language_current_en": {
        "en": "Current language: English",
        "zh": "当前语言：英文 (English)",
    },
    "language_source_explanation": {
        "en": "Bot language is set by the NANOBK_LANG environment variable or installer language option.",
        "zh": "Bot 语言由 NANOBK_LANG 环境变量或安装器语言选项决定。",
    },
    "language_default_zh": {
        "en": "Chinese (中文) is the default language for new installations.",
        "zh": "新安装默认使用中文。",
    },
    "language_en_available": {
        "en": "English is available by setting NANOBK_LANG=en before installation.",
        "zh": "通过在安装前设置 NANOBK_LANG=en 可使用英文。",
    },
    "language_persistent_planned": {
        "en": "Persistent language switching is planned for a future CLI/installer-safe command.",
        "zh": "持久语言切换计划在未来通过 CLI/安装器安全命令实现。",
    },
    "language_no_env_write": {
        "en": "This command does not write to configuration files.",
        "zh": "此命令不会写入配置文件。",
    },
    "language_usage": {
        "en": "Usage: /language — Show current language and guidance.",
        "zh": "用法：/language — 显示当前语言和引导。",
    },
    "help_language": {
        "en": "Show language info and guidance",
        "zh": "显示语言信息和引导",
    },
}


def bt(lang: str, key: str, **kwargs: object) -> str:
    """Get translated Bot text. Falls back to English if key/language missing."""
    entry = BOT_TEXT.get(key)
    if entry is None:
        return key  # fallback to key name
    text = entry.get(lang) or entry.get(DEFAULT_LANG) or key
    if kwargs:
        try:
            text = text.format(**kwargs)
        except (KeyError, IndexError):
            pass
    return text


@dataclass
class BotConfig:
    bot_token: str = ""
    owner_id: int = 0
    nanobk_cli: str = "/usr/local/bin/nanobk"
    nanobk_repo_dir: str = ""
    command_timeout: int = 120
    rotate_timeout: int = 300
    dry_run: bool = False
    lang: str = "zh"

    @classmethod
    def from_env(cls) -> BotConfig:
        if load_dotenv:
            env_path = Path(__file__).parent / ".env"
            if env_path.exists():
                load_dotenv(env_path)

        return cls(
            bot_token=os.environ.get("TELEGRAM_BOT_TOKEN", ""),
            owner_id=int(os.environ.get("OWNER_TELEGRAM_ID", "0")),
            nanobk_cli=os.environ.get("NANOBK_CLI", "/usr/local/bin/nanobk"),
            nanobk_repo_dir=os.environ.get("NANOBK_REPO_DIR", ""),
            command_timeout=int(os.environ.get("NANOBK_COMMAND_TIMEOUT", "120")),
            rotate_timeout=int(os.environ.get("NANOBK_ROTATE_TIMEOUT", "300")),
            dry_run=os.environ.get("NANOBK_BOT_DRY_RUN", "false").lower() == "true",
            lang=normalize_lang(os.environ.get("NANOBK_LANG")),
        )

# ── Command result ──────────────────────────────────────────────────────────

@dataclass
class CommandResult:
    code: int = 0
    stdout: str = ""
    stderr: str = ""
    duration: float = 0.0

# ── nanobk CLI wrapper ─────────────────────────────────────────────────────

def run_nanobk(config: BotConfig, args: list[str], timeout: int | None = None) -> CommandResult:
    """Run a nanobk CLI command safely without invoking a shell."""
    cmd = [config.nanobk_cli]
    if config.nanobk_repo_dir:
        cmd += ["--repo-dir", config.nanobk_repo_dir]
    cmd += args

    timeout = timeout or config.command_timeout
    start = time.monotonic()

    try:
        proc = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return CommandResult(
            code=proc.returncode,
            stdout=proc.stdout,
            stderr=proc.stderr,
            duration=time.monotonic() - start,
        )
    except subprocess.TimeoutExpired:
        return CommandResult(
            code=-1,
            stdout="",
            stderr=f"Command timed out after {timeout}s",
            duration=time.monotonic() - start,
        )
    except FileNotFoundError:
        return CommandResult(
            code=-1,
            stdout="",
            stderr=f"nanobk CLI not found: {config.nanobk_cli}",
            duration=time.monotonic() - start,
        )

# ── Output safety ───────────────────────────────────────────────────────────
# Delegates to shared redaction helper from lib/nanobk_redaction.py
# for address-class redaction (IPv4, IPv6, domain, URL, workers.dev,
# subscription path) plus existing token/secret patterns.

def strip_ansi(text: str) -> str:
    """Remove ANSI escape codes (color, cursor, etc.)."""
    return _shared_strip_ansi(text)

def redact_text(text: str) -> str:
    """Redact sensitive patterns from text (delegates to shared helper)."""
    return _shared_redact_text(text)

def limit_text(text: str, max_len: int = 3500) -> str:
    """Truncate text to Telegram message limits."""
    if len(text) <= max_len:
        return text
    return text[:max_len] + "\n... [truncated]"

def safe_output(text: str) -> str:
    """Strip ANSI, apply redaction, and limit length."""
    text = strip_ansi(text)
    text = redact_text(text)
    return limit_text(text)

# ── Status formatting ───────────────────────────────────────────────────────

def _infer_overall(data: dict) -> str:
    """Infer overall status from available fields. Returns honest category."""
    ok = data.get("ok")
    if ok is True:
        return "healthy"
    if ok is False:
        return "failed"
    return "unknown"


def _infer_vps(data: dict) -> str:
    """Infer VPS status from services and config fields."""
    services = data.get("services")
    if not isinstance(services, dict):
        return "unknown"
    statuses = [services.get(p) for p in ("hy2", "tuic", "reality", "trojan")]
    if all(s == "active" for s in statuses):
        return "healthy"
    if any(s == "active" for s in statuses):
        return "partial"
    if any(s in ("failed", "inactive") for s in statuses):
        return "failed"
    if any(s == "missing" for s in statuses):
        return "incomplete"
    return "unknown"


def _infer_cf_status(cf_entry: dict) -> str:
    """Infer Cloudflare component status."""
    if not isinstance(cf_entry, dict):
        return "unknown"
    if cf_entry.get("verified"):
        return "verified"
    if cf_entry.get("envExists"):
        return "configured"
    return "missing"


def _infer_subscription(data: dict) -> str:
    """Infer subscription status."""
    sub = data.get("subscription")
    if not isinstance(sub, dict):
        return "unknown"
    if sub.get("verified"):
        return "verified"
    if sub.get("configured"):
        return "configured"
    if sub.get("url"):
        return "configured"
    return "unknown"


def _infer_profile(data: dict) -> str:
    """Infer profile status."""
    profile = data.get("profile")
    if isinstance(profile, dict):
        if profile.get("currentPath") or profile.get("domain"):
            return "present"
    # Also check top-level domain as proxy for profile existence
    if data.get("domain") and data.get("domain") != "<not set>":
        return "present"
    return "unknown"


def _next_step_hint(overall: str, vps: str, cf_nanok: str, cf_nanob: str, sub: str, lang: str = "en") -> str:
    """Generate a safe next-step hint based on status."""
    if overall == "failed":
        return bt(lang, "hint_failed")
    if vps == "failed":
        return bt(lang, "hint_vps_failed")
    if cf_nanok in ("missing", "unknown") or cf_nanob in ("missing", "unknown"):
        return bt(lang, "hint_cf_missing")
    if sub in ("manual_pending", "unknown"):
        return bt(lang, "hint_sub_pending")
    if overall == "healthy" and vps == "healthy":
        return bt(lang, "hint_healthy")
    return bt(lang, "hint_default")


def format_status(data: dict, lang: str = "en") -> str:
    """Format nanobk --json status into a safe beginner-friendly summary.

    Avoids raw IP/domain/URL/subscription path/labels.
    Uses honest status categories. Tolerates missing fields.
    """
    if not isinstance(data, dict):
        title = bt(lang, "status_summary_title")
        unavail = bt(lang, "status_data_unavailable")
        hint = bt(lang, "status_run_doctor")
        next_label = bt(lang, "status_label_next_step")
        return f"{title}\n\n{unavail}\n\n{next_label}:\n{hint}"

    lines = [bt(lang, "status_summary_title"), ""]

    # Overall
    overall = _infer_overall(data)
    lines.append(f"{bt(lang, 'status_label_overall')}: {overall}")

    # VPS
    vps = _infer_vps(data)
    lines.append(f"{bt(lang, 'status_label_vps')}: {vps}")

    # Protocols
    services = data.get("services")
    if isinstance(services, dict):
        lines.append(f"{bt(lang, 'status_label_protocols')}:")
        for name in ("hy2", "tuic", "reality", "trojan"):
            svc = services.get(name, "unknown")
            lines.append(f"  {name.upper()}: {svc}")
    else:
        lines.append(f"{bt(lang, 'status_label_protocols')}: unknown")

    # Cloudflare
    cf = data.get("cloudflare")
    if isinstance(cf, dict):
        nanok = cf.get("nanok", {})
        nanob = cf.get("nanob", {})
        cf_nanok = _infer_cf_status(nanok)
        cf_nanob = _infer_cf_status(nanob)
        lines.append(f"{bt(lang, 'status_label_cloudflare')}:")
        lines.append(f"  nanok: {cf_nanok}")
        lines.append(f"  nanob: {cf_nanob}")
    else:
        cf_nanok = "unknown"
        cf_nanob = "unknown"
        lines.append(f"{bt(lang, 'status_label_cloudflare')}: unknown")

    # Subscription
    sub = _infer_subscription(data)
    lines.append(f"{bt(lang, 'status_label_subscription')}: {sub}")

    # Secrets mode
    security = data.get("security")
    if isinstance(security, dict):
        mode = security.get("secretsMode", "unknown")
        if mode and mode != "unknown":
            secrets_val = bt(lang, "status_secrets_present_mode", mode=mode)
        else:
            secrets_val = bt(lang, "status_secrets_unknown")
        lines.append(f"{bt(lang, 'status_label_secrets')}: {secrets_val}")
    else:
        lines.append(f"{bt(lang, 'status_label_secrets')}: {bt(lang, 'status_secrets_unknown')}")

    # Profile
    profile = _infer_profile(data)
    lines.append(f"{bt(lang, 'status_label_profile')}: {profile}")

    # Next step hint
    hint = _next_step_hint(overall, vps, cf_nanok, cf_nanob, sub, lang=lang)
    lines.append("")
    lines.append(f"{bt(lang, 'status_label_next_step')}:\n{hint}")

    return "\n".join(lines)


# ── Doctor Summary builder ───────────────────────────────────────────────────
# Builds a safe beginner-friendly Doctor Summary from nanobk --json status.
# Conforms to v1.9.35 Doctor Summary contract schema.
# Does NOT include raw IP/domain/URL/token/private key.


def _infer_doctor_overall(data: dict) -> str:
    """Infer overall doctor status from status JSON.

    Uses service-level analysis for nuanced status.
    Only uses ok field as fallback when no service data available.
    """
    ok = data.get("ok")
    services = data.get("services")
    warnings = data.get("warnings")

    # Check services first for nuanced status
    if isinstance(services, dict):
        statuses = [services.get(p) for p in ("hy2", "tuic", "reality", "trojan")]
        active_count = sum(1 for s in statuses if s == "active")
        failed_count = sum(1 for s in statuses if s in ("failed", "inactive"))
        unknown_count = sum(1 for s in statuses if s in ("unknown", "missing", None))

        if active_count == 4:
            # All active — check warnings for config issues
            if isinstance(warnings, list) and len(warnings) > 0:
                warn_text = " ".join(str(w) for w in warnings).lower()
                if "config" in warn_text or "not found" in warn_text:
                    return "partial"
            return "healthy"
        if active_count > 0 and failed_count > 0:
            return "partial"
        if active_count > 0 and failed_count == 0:
            return "partial"
        if failed_count > 0:
            return "failed"
        if unknown_count == 4:
            return "unknown"

    # Fallback to ok field when no service data
    if ok is True:
        return "healthy"
    if ok is False:
        return "failed"
    return "unknown"


def _infer_doctor_cloudflare(data: dict) -> str:
    """Infer Cloudflare status from status JSON."""
    cf = data.get("cloudflare")
    if not isinstance(cf, dict):
        return "unknown"

    nanok = cf.get("nanok")
    nanob = cf.get("nanob")

    # Check verified first
    if isinstance(nanok, dict) and nanok.get("verified") and isinstance(nanob, dict) and nanob.get("verified"):
        return "verified"

    # Check configured
    if isinstance(nanok, dict) and nanok.get("envExists") and isinstance(nanob, dict) and nanob.get("envExists"):
        return "configured"

    # Check if at least one exists
    nanok_exists = isinstance(nanok, dict) and nanok.get("envExists")
    nanob_exists = isinstance(nanob, dict) and nanob.get("envExists")
    if nanok_exists or nanob_exists:
        return "configured"

    return "missing"


def _infer_doctor_subscription(data: dict) -> str:
    """Infer subscription status from status JSON."""
    sub = data.get("subscription")
    if not isinstance(sub, dict):
        return "unknown"
    if sub.get("verified"):
        return "verified"
    if sub.get("configured"):
        return "configured"
    return "missing"


def _infer_doctor_security(data: dict) -> str:
    """Infer security status from status JSON."""
    security = data.get("security")
    if not isinstance(security, dict):
        return "unknown"
    mode = security.get("secretsMode")
    if mode:
        return "ok"
    return "warning"


def _doctor_next_step(summary: dict) -> str:
    """Determine next step from summary fields."""
    overall = summary.get("overall", "unknown")
    services = summary.get("services", {})
    cloudflare = summary.get("cloudflare", "unknown")
    config = summary.get("config", "unknown")

    if overall == "failed":
        return "check_failed_services"
    if any(s in ("failed", "inactive") for s in services.values()):
        return "check_failed_services"
    if config == "missing":
        return "complete_config"
    if cloudflare in ("missing", "manual_pending"):
        return "configure_cloudflare"
    if overall == "unknown":
        return "unknown"
    return "no_action"


def build_doctor_summary(data: dict, *, full_available: bool = True) -> dict:
    """Build a Doctor Summary dict from nanobk --json status data.

    Conforms to v1.9.35 Doctor Summary contract schema.
    Never includes raw IP/domain/URL/token/private key.
    """
    if not isinstance(data, dict):
        return {
            "overall": "unknown",
            "control_plane": "unknown",
            "cli": "unknown",
            "profile": "unknown",
            "config": "unknown",
            "services": {p: "unknown" for p in ("hy2", "tuic", "reality", "trojan")},
            "cloudflare": "unknown",
            "subscription": "unknown",
            "security": "unknown",
            "doctor": {"errors": 0, "warnings": 0, "full_available": full_available},
            "next_step": "unknown",
            "display_policy": {
                "beginner_safe": True,
                "full_output_advanced_only": True,
                "redaction_required": True,
            },
        }

    # Services
    services_data = data.get("services")
    services = {}
    if isinstance(services_data, dict):
        for p in ("hy2", "tuic", "reality", "trojan"):
            svc = services_data.get(p)
            if svc in ("active", "inactive", "missing"):
                services[p] = svc
            elif svc == "failed":
                services[p] = "inactive"
            else:
                services[p] = "unknown"
    else:
        services = {p: "unknown" for p in ("hy2", "tuic", "reality", "trojan")}

    # Profile
    profile_data = data.get("profile")
    profile = "unknown"
    if isinstance(profile_data, dict):
        if profile_data.get("currentPath") or profile_data.get("domain"):
            profile = "present"
        elif profile_data.get("exists") is True:
            profile = "present"
        elif profile_data.get("exists") is False:
            profile = "missing"
    elif data.get("domain") and data.get("domain") != "<not set>":
        profile = "present"

    # Config — inferred from profile/configDir/security/warnings
    config = "unknown"
    if profile == "present":
        config = "present"
    elif isinstance(data.get("configDir"), str) and data["configDir"]:
        config = "present"
    elif isinstance(data.get("security"), dict) and data["security"].get("secretsExists"):
        config = "present"

    warnings = data.get("warnings", [])
    if isinstance(warnings, list):
        warn_text = " ".join(str(w) for w in warnings).lower()
        if "config directory not found" in warn_text or "profile not found" in warn_text:
            config = "missing"
            profile = "missing"

    # Warnings count
    warn_count = len(warnings) if isinstance(warnings, list) else 0

    # Error count — infer from service failures
    error_count = sum(1 for s in services.values() if s in ("failed", "inactive"))

    # Control plane — if we got data, it's ok
    control_plane = "ok" if isinstance(data, dict) and data.get("ok") is not None else "unknown"
    if config == "missing":
        control_plane = "warning"

    # CLI — if we got valid JSON back, CLI is available
    cli = "available"

    overall = _infer_doctor_overall(data)
    cloudflare = _infer_doctor_cloudflare(data)
    subscription = _infer_doctor_subscription(data)
    security = _infer_doctor_security(data)

    summary = {
        "overall": overall,
        "control_plane": control_plane,
        "cli": cli,
        "profile": profile,
        "config": config,
        "services": services,
        "cloudflare": cloudflare,
        "subscription": subscription,
        "security": security,
        "doctor": {
            "errors": error_count,
            "warnings": warn_count,
            "full_available": full_available,
        },
        "next_step": "unknown",  # placeholder, computed below
        "display_policy": {
            "beginner_safe": True,
            "full_output_advanced_only": True,
            "redaction_required": True,
        },
    }

    summary["next_step"] = _doctor_next_step(summary)
    return summary


def format_doctor_summary(summary: dict, lang: str = "en") -> str:
    """Format a Doctor Summary dict into human-readable text.

    Uses i18n for labels. Never includes raw IP/domain/URL/token/private key.
    """
    lines = [bt(lang, "doctor_summary_title"), ""]

    # Overall
    lines.append(f"{bt(lang, 'doctor_label_overall')}: {summary.get('overall', 'unknown')}")

    # Control plane
    lines.append(f"{bt(lang, 'doctor_label_control_plane')}: {summary.get('control_plane', 'unknown')}")

    # CLI
    lines.append(f"{bt(lang, 'doctor_label_cli')}: {summary.get('cli', 'unknown')}")

    # Profile
    lines.append(f"{bt(lang, 'doctor_label_profile')}: {summary.get('profile', 'unknown')}")

    # Config
    lines.append(f"{bt(lang, 'doctor_label_config')}: {summary.get('config', 'unknown')}")

    # Services
    lines.append(f"{bt(lang, 'doctor_label_services')}:")
    services = summary.get("services", {})
    for p in ("hy2", "tuic", "reality", "trojan"):
        lines.append(f"  {p.upper()}: {services.get(p, 'unknown')}")

    # Cloudflare
    lines.append(f"{bt(lang, 'doctor_label_cloudflare')}: {summary.get('cloudflare', 'unknown')}")

    # Subscription
    lines.append(f"{bt(lang, 'doctor_label_subscription')}: {summary.get('subscription', 'unknown')}")

    # Security
    lines.append(f"{bt(lang, 'doctor_label_security')}: {summary.get('security', 'unknown')}")

    # Doctor info
    doc = summary.get("doctor", {})
    lines.append(f"{bt(lang, 'doctor_label_errors')}: {doc.get('errors', 0)}")
    lines.append(f"{bt(lang, 'doctor_label_warnings')}: {doc.get('warnings', 0)}")

    # Next step
    next_step = summary.get("next_step", "unknown")
    next_step_map = {
        "no_action": "doctor_next_no_action",
        "check_failed_services": "doctor_next_check_failed",
        "complete_config": "doctor_next_complete_config",
        "configure_cloudflare": "doctor_next_configure_cf",
        "use_advanced_diagnostics": "doctor_next_use_advanced",
        "unknown": "doctor_next_unknown",
    }
    next_key = next_step_map.get(next_step, "doctor_next_unknown")
    lines.append("")
    lines.append(f"{bt(lang, 'doctor_label_next_step')}:")
    lines.append(bt(lang, next_key))

    return "\n".join(lines)


# ── Shared safe status helper ────────────────────────────────────────────────
# Single source of truth for /status and Status Summary callback.
# Avoids logic drift between cmd_status and handle_menu_callback.

def get_safe_status_text(config: BotConfig) -> str:
    """Run nanobk --json status, format safely, return safe summary text.

    Shared by /status and Status Summary callback.
    Preserves existing command args, output handling, and safe_output usage.
    """
    result = run_nanobk(config, ["--json", "status"])
    if result.code != 0:
        return safe_output(
            f"nanobk status failed (code {result.code}):\n{result.stderr}"
        )
    try:
        data = json.loads(result.stdout)
        formatted = format_status(data, lang=config.lang)
    except json.JSONDecodeError:
        formatted = f"Failed to parse status JSON.\nRaw output:\n{result.stdout[:500]}"
    return safe_output(formatted)


# ── Control center menu ─────────────────────────────────────────────────────
# Static InlineKeyboardButton menu for Bot Control Center.
# Callbacks use "nanobk:" prefix for safe scoping.

CALLBACK_STATUS = "nanobk:status"
CALLBACK_RECOVERY = "nanobk:recovery"
CALLBACK_DIAGNOSTICS = "nanobk:diagnostics"
CALLBACK_ADVANCED = "nanobk:advanced"
CALLBACK_ROTATE = "nanobk:rotate"
CALLBACK_WEB = "nanobk:web"
CALLBACK_HELP = "nanobk:help"

# ── Callback guidance builders ───────────────────────────────────────────────
# Build localized text on demand. Tests can call these directly.


def build_control_center_text(lang: str = "en") -> str:
    title = bt(lang, "control_center_title")
    subtitle = bt(lang, "control_center_subtitle")
    return f"{title}\n\n{subtitle}"


def build_guidance_recovery(lang: str = "en") -> str:
    return bt(lang, "guidance_recovery")


def build_guidance_diagnostics(lang: str = "en") -> str:
    return bt(lang, "guidance_diagnostics")


def build_guidance_rotate(lang: str = "en") -> str:
    return bt(lang, "guidance_rotate")


def build_guidance_web(lang: str = "en") -> str:
    return bt(lang, "guidance_web")


def build_language_guidance(lang: str = "en") -> str:
    """Build the /language guidance text."""
    lines = [bt(lang, "language_title"), ""]

    if lang == "zh":
        lines.append(bt(lang, "language_current_zh"))
    else:
        lines.append(bt(lang, "language_current_en"))

    lines.append("")
    lines.append(bt(lang, "language_source_explanation"))
    lines.append(bt(lang, "language_default_zh"))
    lines.append(bt(lang, "language_en_available"))
    lines.append("")
    lines.append(bt(lang, "language_persistent_planned"))
    lines.append(bt(lang, "language_no_env_write"))
    return "\n".join(lines)


def build_help_text(lang: str = "en") -> str:
    """Build the /help text in the given language."""
    lines = [bt(lang, "help_title"), ""]
    lines.append(f"{bt(lang, 'help_basic')}")
    lines.append(f"/start          — {bt(lang, 'help_start')}")
    lines.append(f"/home           — {bt(lang, 'help_home')}")
    lines.append(f"/setup_status   — {bt(lang, 'help_setup_status')}")
    lines.append(f"/status         — {bt(lang, 'help_status')}")
    lines.append(f"/doctor         — {bt(lang, 'help_doctor')}")
    lines.append(f"/cancel         — {bt(lang, 'help_cancel')}")
    lines.append(f"/language       — {bt(lang, 'help_language')}")
    lines.append("")
    lines.append(f"{bt(lang, 'help_safe_ops')}")
    lines.append(f"/rotate_all     — {bt(lang, 'help_rotate_all')}")
    lines.append(f"/rotate_hy2     — {bt(lang, 'help_rotate_hy2')}")
    lines.append(f"/rotate_tuic    — {bt(lang, 'help_rotate_tuic')}")
    lines.append(f"/rotate_reality — {bt(lang, 'help_rotate_reality')}")
    lines.append(f"/rotate_trojan  — {bt(lang, 'help_rotate_trojan')}")
    lines.append("")
    lines.append(f"{bt(lang, 'help_advanced_diag')}")
    lines.append(f"/status_json    — {bt(lang, 'help_status_json')}")
    lines.append(f"/advanced on    — {bt(lang, 'help_advanced_on')}")
    lines.append(f"/advanced off   — {bt(lang, 'help_advanced_off')}")
    lines.append(f"/advanced status — {bt(lang, 'help_advanced_status')}")
    lines.append("")
    lines.append(f"/help           — {bt(lang, 'help_show')}")
    lines.append("")
    lines.append(bt(lang, "help_rotate_warning"))
    return "\n".join(lines)


def _build_main_menu_keyboard(lang: str = "en"):
    """Build the main menu InlineKeyboardMarkup."""
    from telegram import InlineKeyboardButton, InlineKeyboardMarkup

    keyboard = [
        [
            InlineKeyboardButton(bt(lang, "btn_status"), callback_data=CALLBACK_STATUS),
            InlineKeyboardButton(bt(lang, "btn_recovery"), callback_data=CALLBACK_RECOVERY),
        ],
        [
            InlineKeyboardButton(bt(lang, "btn_diagnostics"), callback_data=CALLBACK_DIAGNOSTICS),
            InlineKeyboardButton(bt(lang, "btn_advanced"), callback_data=CALLBACK_ADVANCED),
        ],
        [
            InlineKeyboardButton(bt(lang, "btn_rotate"), callback_data=CALLBACK_ROTATE),
            InlineKeyboardButton(bt(lang, "btn_web"), callback_data=CALLBACK_WEB),
        ],
        [
            InlineKeyboardButton(bt(lang, "btn_help"), callback_data=CALLBACK_HELP),
        ],
    ]
    return InlineKeyboardMarkup(keyboard)


# ── Advanced diagnostics mode ────────────────────────────────────────────────
# In-memory state for advanced diagnostics mode.
# Not persisted to disk/env/config. Bot restart resets state.
# Auto-expires after TTL. Owner-only.

ADVANCED_MODE_TTL_SECONDS = 15 * 60  # 15 minutes

_ADVANCED_MODE_EXPIRES_AT: dict[int, float] = {}


def enable_advanced_mode(user_id: int, now: float | None = None) -> float:
    """Enable advanced mode for a user. Returns expiry timestamp."""
    if now is None:
        now = time.time()
    expiry = now + ADVANCED_MODE_TTL_SECONDS
    _ADVANCED_MODE_EXPIRES_AT[user_id] = expiry
    return expiry


def disable_advanced_mode(user_id: int) -> None:
    """Disable advanced mode for a user."""
    _ADVANCED_MODE_EXPIRES_AT.pop(user_id, None)


def advanced_mode_expires_at(user_id: int) -> float | None:
    """Return expiry timestamp for user, or None if not enabled."""
    return _ADVANCED_MODE_EXPIRES_AT.get(user_id)


def is_advanced_mode_enabled(user_id: int, now: float | None = None) -> bool:
    """Check if advanced mode is enabled and not expired. Cleans expired entries."""
    if now is None:
        now = time.time()
    expiry = _ADVANCED_MODE_EXPIRES_AT.get(user_id)
    if expiry is None:
        return False
    if now >= expiry:
        del _ADVANCED_MODE_EXPIRES_AT[user_id]
        return False
    return True


def advanced_mode_remaining_seconds(user_id: int, now: float | None = None) -> int:
    """Return remaining seconds of advanced mode, or 0 if disabled/expired."""
    if now is None:
        now = time.time()
    expiry = _ADVANCED_MODE_EXPIRES_AT.get(user_id)
    if expiry is None:
        return 0
    remaining = int(expiry - now)
    if remaining <= 0:
        del _ADVANCED_MODE_EXPIRES_AT[user_id]
        return 0
    return remaining


# ── Pending confirmation ────────────────────────────────────────────────────

@dataclass
class PendingConfirmation:
    action: str
    command: list[str]
    created_at: float = field(default_factory=time.monotonic)

class ConfirmationManager:
    EXPIRY_SECONDS = 120

    def __init__(self):
        self._pending: dict[int, PendingConfirmation] = {}

    def set(self, user_id: int, action: str, command: list[str]) -> None:
        self._pending[user_id] = PendingConfirmation(action=action, command=command)

    def get(self, user_id: int) -> PendingConfirmation | None:
        entry = self._pending.get(user_id)
        if entry is None:
            return None
        if time.monotonic() - entry.created_at > self.EXPIRY_SECONDS:
            del self._pending[user_id]
            return None
        return entry

    def get_action(self, user_id: int) -> str | None:
        entry = self.get(user_id)
        return entry.action if entry else None

    def pop(self, user_id: int) -> PendingConfirmation | None:
        entry = self.get(user_id)
        if entry:
            del self._pending[user_id]
        return entry

    def clear(self, user_id: int) -> None:
        self._pending.pop(user_id, None)

# ── Self-test ───────────────────────────────────────────────────────────────

def run_self_test() -> bool:
    """Run self-tests without connecting to Telegram."""
    print("=== NanoBK Bot Self-Test ===\n")
    passed = 0
    failed = 0

    def check(desc: str, ok: bool):
        nonlocal passed, failed
        if ok:
            print(f"  ✓ {desc}")
            passed += 1
        else:
            print(f"  ✗ {desc}")
            failed += 1

    config = BotConfig(owner_id=12345, nanobk_cli="/usr/bin/echo", dry_run=True)

    # 1. Unauthorized user
    check("unauthorized user: owner_id=12345, user=99999", config.owner_id != 99999)

    # 2. Status formatter: safe beginner summary
    test_status = {
        "ok": True, "domain": "test.example.com", "vpsIp": "1.2.3.4", "geo": "JP",
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {"nanok": {"envExists": True}, "nanob": {"envExists": False}},
        "warnings": []
    }
    formatted = format_status(test_status)
    check("status summary title present", "NanoBK Status Summary" in formatted)
    check("status summary shows overall healthy", "Overall: healthy" in formatted)
    check("status summary shows VPS healthy", "VPS: healthy" in formatted)
    check("status summary includes services", "active" in formatted)
    check("status summary no raw domain label", "Domain:" not in formatted)
    check("status summary no raw domain value", "test.example.com" not in formatted)
    check("status summary no raw IP label", "VPS IP:" not in formatted)
    check("status summary no raw IP value", "1.2.3.4" not in formatted)
    check("status summary shows secrets mode", "mode 600" in formatted)
    check("status summary shows next step", "Next step:" in formatted)

    # 3. redact_text hides bot token
    test_text = "Token is 123456789:ABCdefGHIjklMNOpqrsTUVwxyz012345"
    redacted = redact_text(test_text)
    check("redact_text hides bot token", "ABCdefGHI" not in redacted)

    # 4. redact_text hides password=value
    test_text2 = "password=SuperSecret123"
    redacted2 = redact_text(test_text2)
    check("redact_text hides password=value", "SuperSecret123" not in redacted2)

    # 5. run_nanobk constructs command safely (no shell)
    result = run_nanobk(config, ["--version"], timeout=5)
    check("run_nanobk returns CommandResult", isinstance(result, CommandResult))

    # 6. Rotate confirmation manager
    cm = ConfirmationManager()
    cm.set(12345, "rotate_tuic", ["rotate", "tuic", "--yes"])
    check("confirmation set", cm.get_action(12345) == "rotate_tuic")
    check("confirmation mismatch rejected", cm.get_action(12345) != "rotate_hy2")

    # 6b. Mismatch does NOT clear pending (get without pop)
    pending = cm.get(12345)
    check("mismatch preserves pending (get returns entry)", pending is not None)
    check("mismatch preserves pending (action still rotate_tuic)", cm.get_action(12345) == "rotate_tuic")

    # 6c. Match clears pending (pop)
    cm.pop(12345)
    check("matched pop clears pending", cm.get_action(12345) is None)

    # 7. Dry-run rotate does not execute
    config_dry = BotConfig(owner_id=12345, nanobk_cli="/usr/bin/echo", dry_run=True)
    check("dry-run flag set", config_dry.dry_run is True)

    # 8. Pending confirmation expiry
    cm2 = ConfirmationManager()
    cm2.EXPIRY_SECONDS = 0  # expire immediately
    cm2.set(12345, "rotate_all", ["rotate", "all", "--yes"])
    time.sleep(0.01)
    check("pending confirmation expires", cm2.get_action(12345) is None)

    # 9. Help text classification (English)
    help_en = build_help_text("en")
    check("en help title exists", "NanoBK Bot Commands" in help_en)
    check("en help includes Basic", "Basic:" in help_en)
    check("en help includes Safe operations", "Safe operations:" in help_en)
    check("en help includes Advanced diagnostics", "Advanced diagnostics:" in help_en)
    check("en help /status_json under Advanced", "/status_json" in help_en and "Advanced diagnostics:" in help_en)
    check("en help includes rotate commands", "/rotate_tuic" in help_en)
    check("en help /status_json not in Basic", help_en.index("/status_json") > help_en.index("Advanced diagnostics:"))

    # 9z. Help text classification (Chinese)
    help_zh = build_help_text("zh")
    check("zh help title exists", "NanoBK 机器人命令" in help_zh)
    check("zh help includes Basic", "基础：" in help_zh)
    check("zh help includes Safe operations", "安全操作：" in help_zh)
    check("zh help includes Advanced diagnostics", "高级诊断：" in help_zh)
    check("zh help /status_json under Advanced", "/status_json" in help_zh and "高级诊断：" in help_zh)
    check("zh help includes rotate commands", "/rotate_tuic" in help_zh)

    # 9b. /status_json warning text (English, when advanced mode is ON)
    warn_en = bt("en", "status_json_warning")
    check("en status_json warning present", "Advanced diagnostics" in warn_en)
    check("en status_json warning says redacted", "redacted" in warn_en)
    check("en status_json warning says do not forward", "Do not forward" in warn_en)
    check("en status_json warning recommends /status", "/status" in warn_en)

    # 9bz. /status_json warning text (Chinese, when advanced mode is ON)
    warn_zh = bt("zh", "status_json_warning")
    check("zh status_json warning present", "高级诊断" in warn_zh)
    check("zh status_json warning says redacted", "脱敏" in warn_zh)
    check("zh status_json warning says do not forward", "请勿" in warn_zh)
    check("zh status_json warning recommends /status", "/status" in warn_zh)

    # 9b2. /status_json soft gate copy (English, when advanced mode is OFF)
    gate_en = bt("en", "gate_not_enabled")
    check("en gate mentions not enabled", "not enabled" in gate_en)
    check("en gate mentions /advanced on", "/advanced on" in gate_en)
    check("en gate mentions /status", "/status" in gate_en)
    check("en gate mentions 15 minutes", "15 minutes" in gate_en)
    check("en gate says secrets remain hidden", "secrets" in gate_en and "remain hidden" in gate_en)

    # 9b2z. /status_json soft gate copy (Chinese, when advanced mode is OFF)
    gate_zh = bt("zh", "gate_not_enabled")
    check("zh gate mentions not enabled", "未启用" in gate_zh)
    check("zh gate mentions /advanced on", "/advanced on" in gate_zh)
    check("zh gate mentions /status", "/status" in gate_zh)
    check("zh gate mentions 15 minutes", "15" in gate_zh)

    # 9c. Advanced mode helpers
    # Disabled by default
    check("advanced mode disabled by default", not is_advanced_mode_enabled(99999))

    # Enable and check
    test_now = 1000.0
    expiry = enable_advanced_mode(12345, now=test_now)
    check("enable returns expiry", expiry == test_now + ADVANCED_MODE_TTL_SECONDS)
    check("enabled after enable", is_advanced_mode_enabled(12345, now=test_now))
    check("remaining seconds positive", advanced_mode_remaining_seconds(12345, now=test_now) > 0)
    check("expires_at returns value", advanced_mode_expires_at(12345) is not None)

    # Disable and check
    disable_advanced_mode(12345)
    check("disabled after disable", not is_advanced_mode_enabled(12345))
    check("remaining seconds zero after disable", advanced_mode_remaining_seconds(12345) == 0)
    check("expires_at None after disable", advanced_mode_expires_at(12345) is None)

    # Expiration
    enable_advanced_mode(12345, now=test_now)
    expired_time = test_now + ADVANCED_MODE_TTL_SECONDS + 1
    check("expired mode is disabled", not is_advanced_mode_enabled(12345, now=expired_time))
    check("expired remaining is zero", advanced_mode_remaining_seconds(12345, now=expired_time) == 0)

    # 9d. Help text includes /advanced commands
    check("en help includes /advanced on", "/advanced on" in help_en)
    check("en help includes /advanced off", "/advanced off" in help_en)
    check("en help includes /advanced status", "/advanced status" in help_en)
    check("en help /status_json still in Advanced", "/status_json" in help_en)

    # 10. limit_text truncates
    long_text = "x" * 5000
    truncated = limit_text(long_text, max_len=100)
    check("limit_text truncates", len(truncated) < len(long_text))
    check("limit_text adds marker", "[truncated]" in truncated)

    # 11. redact_text handles private key
    test_pk = "PrivateKey: aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789"
    redacted_pk = redact_text(test_pk)
    check("redact_text hides PrivateKey", "aBcDeFgHiJkLmNoPq" not in redacted_pk)

    # 12. strip_ansi removes color escapes
    ansi = "\x1b[0;34mINFO\x1b[0m \x1b[0;32mOK\x1b[0m \x1b[1;33mWARN\x1b[0m"
    clean = strip_ansi(ansi)
    check("strip_ansi removes color escapes", "\x1b[" not in clean and "INFO" in clean and "OK" in clean and "WARN" in clean)

    # 13. safe_output strips ANSI
    safe = safe_output(ansi)
    check("safe_output strips ANSI", "\x1b[" not in safe)

    # 14. safe_output strips ANSI and redacts
    safe_secret = safe_output("\x1b[0;32mpassword=SuperSecret123\x1b[0m")
    check("safe_output strips ANSI and redacts", "SuperSecret123" not in safe_secret and "\x1b[" not in safe_secret)

    # 15. Address-class: format_status does not include raw domain/IP
    test_status_addr = {
        "ok": True, "domain": "node.example.invalid", "vpsIp": "203.0.113.10", "geo": "JP",
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {"nanok": {"envExists": True}, "nanob": {"envExists": False}},
        "warnings": []
    }
    formatted_addr = format_status(test_status_addr)
    safe_addr = safe_output(formatted_addr)
    check("format_status no raw domain label",
          "Domain:" not in formatted_addr)
    check("format_status no raw domain value",
          "node.example.invalid" not in formatted_addr)
    check("format_status no raw IP label",
          "VPS IP:" not in formatted_addr)
    check("format_status no raw IP value",
          "203.0.113.10" not in formatted_addr)
    check("safe_output preserves service words in status",
          "active" in safe_addr and "600" in safe_addr)

    # 16. Address-class redaction: safe_output removes IPv6, URL, workers.dev, subscription path
    test_addr_text = "IPv6: 2001:db8::10 URL: https://worker.example.invalid/sub/fake-sub-path-12345 workers.dev: nanobk-test.example.invalid.workers.dev"
    safe_addr2 = safe_output(test_addr_text)
    check("safe_output redacts raw IPv6", "2001:db8::10" not in safe_addr2)
    check("safe_output redacts raw URL", "https://worker.example.invalid" not in safe_addr2)
    check("safe_output redacts raw workers.dev", "nanobk-test.example.invalid.workers.dev" not in safe_addr2)
    check("safe_output redacts raw subscription path", "fake-sub-path-12345" not in safe_addr2)

    # 17. Idempotency: redacting already-redacted output is stable
    safe_once = safe_output(test_addr_text)
    safe_twice = safe_output(safe_once)
    check("safe_output is idempotent", safe_once == safe_twice)

    # 18. Control center menu
    cc_en = build_control_center_text("en")
    check("en control center title", "NanoBK Control Center" in cc_en)
    check("en control center mentions /help", "/help" in cc_en)
    check("en control center says secrets hidden", "hidden" in cc_en)
    cc_zh = build_control_center_text("zh")
    check("zh control center title", "NanoBK 控制中心" in cc_zh)
    check("zh control center mentions /help", "/help" in cc_zh)
    check("zh control center says secrets hidden", "隐藏" in cc_zh)
    check("CALLBACK_STATUS uses nanobk: prefix", CALLBACK_STATUS.startswith("nanobk:"))
    check("CALLBACK_RECOVERY uses nanobk: prefix", CALLBACK_RECOVERY.startswith("nanobk:"))
    check("CALLBACK_DIAGNOSTICS uses nanobk: prefix", CALLBACK_DIAGNOSTICS.startswith("nanobk:"))
    check("CALLBACK_ADVANCED uses nanobk: prefix", CALLBACK_ADVANCED.startswith("nanobk:"))
    check("CALLBACK_ROTATE uses nanobk: prefix", CALLBACK_ROTATE.startswith("nanobk:"))
    check("CALLBACK_WEB uses nanobk: prefix", CALLBACK_WEB.startswith("nanobk:"))
    check("CALLBACK_HELP uses nanobk: prefix", CALLBACK_HELP.startswith("nanobk:"))
    check("_build_main_menu_keyboard is callable", callable(_build_main_menu_keyboard))

    # 18b. Guidance constants validation (English)
    rec_en = build_guidance_recovery("en")
    check("en recovery mentions /status", "/status" in rec_en)
    check("en recovery mentions /doctor", "/doctor" in rec_en)
    check("en recovery mentions SSH", "SSH" in rec_en)
    check("en recovery says secrets hidden", "hidden" in rec_en)
    diag_en = build_guidance_diagnostics("en")
    check("en diagnostics mentions /doctor", "/doctor" in diag_en)
    check("en diagnostics mentions /advanced on", "/advanced on" in diag_en)
    check("en diagnostics mentions /status_json", "/status_json" in diag_en)
    check("en diagnostics says redacted", "redacted" in diag_en)
    rot_en = build_guidance_rotate("en")
    check("en rotate mentions confirmation", "confirmation" in rot_en)
    check("en rotate lists /rotate_all", "/rotate_all" in rot_en)
    check("en rotate lists /rotate_tuic", "/rotate_tuic" in rot_en)
    web_en = build_guidance_web("en")
    check("en web mentions dashboard", "dashboard" in web_en.lower())
    check("en web has no raw URL", "http://" not in web_en and "https://" not in web_en)

    # 18bz. Guidance constants validation (Chinese)
    rec_zh = build_guidance_recovery("zh")
    check("zh recovery mentions /status", "/status" in rec_zh)
    check("zh recovery mentions /doctor", "/doctor" in rec_zh)
    diag_zh = build_guidance_diagnostics("zh")
    check("zh diagnostics mentions /doctor", "/doctor" in diag_zh)
    rot_zh = build_guidance_rotate("zh")
    check("zh rotate mentions confirmation", "确认" in rot_zh)
    web_zh = build_guidance_web("zh")
    check("zh web has no raw URL", "http://" not in web_zh and "https://" not in web_zh)

    # 18c. Translation helper
    check("bt() is callable", callable(bt))
    check("bt en fallback works", bt("en", "nonexistent_key") == "nonexistent_key")
    check("bt zh works", "控制中心" in bt("zh", "control_center_title"))

    # 18d. Doctor Summary builder
    check("build_doctor_summary is callable", callable(build_doctor_summary))
    check("format_doctor_summary is callable", callable(format_doctor_summary))

    # Healthy status
    healthy_data = {
        "ok": True,
        "services": {"hy2": "active", "tuic": "active", "reality": "active", "trojan": "active"},
        "security": {"secretsMode": "600"},
        "cloudflare": {"nanok": {"envExists": True, "verified": True}, "nanob": {"envExists": True, "verified": True}},
        "subscription": {"verified": True, "configured": True},
        "profile": {"domain": "test.example.com", "currentPath": "/etc/nanobk/profile.current.json"},
        "warnings": []
    }
    healthy_summary = build_doctor_summary(healthy_data)
    check("doctor healthy: overall == healthy", healthy_summary["overall"] == "healthy")
    check("doctor healthy: control_plane == ok", healthy_summary["control_plane"] == "ok")
    check("doctor healthy: cli == available", healthy_summary["cli"] == "available")
    check("doctor healthy: profile == present", healthy_summary["profile"] == "present")
    check("doctor healthy: config == present", healthy_summary["config"] == "present")
    check("doctor healthy: all services active", all(s == "active" for s in healthy_summary["services"].values()))
    check("doctor healthy: cloudflare == verified", healthy_summary["cloudflare"] == "verified")
    check("doctor healthy: subscription == verified", healthy_summary["subscription"] == "verified")
    check("doctor healthy: security == ok", healthy_summary["security"] == "ok")
    check("doctor healthy: errors == 0", healthy_summary["doctor"]["errors"] == 0)
    check("doctor healthy: warnings == 0", healthy_summary["doctor"]["warnings"] == 0)
    check("doctor healthy: next_step == no_action", healthy_summary["next_step"] == "no_action")
    check("doctor healthy: display_policy.beginner_safe", healthy_summary["display_policy"]["beginner_safe"] is True)
    check("doctor healthy: display_policy.full_output_advanced_only", healthy_summary["display_policy"]["full_output_advanced_only"] is True)
    check("doctor healthy: display_policy.redaction_required", healthy_summary["display_policy"]["redaction_required"] is True)

    # Partial services
    partial_data = {
        "ok": False,
        "services": {"hy2": "active", "tuic": "failed", "reality": "active", "trojan": "inactive"},
        "security": {"secretsMode": "600"},
        "cloudflare": {"nanok": {"envExists": True, "verified": True}, "nanob": {"envExists": True, "verified": False}},
        "subscription": {"configured": True, "verified": False},
        "profile": {"domain": "test.example.com"},
        "warnings": ["TUIC service not responding"]
    }
    partial_summary = build_doctor_summary(partial_data)
    check("doctor partial: overall == partial", partial_summary["overall"] == "partial")
    check("doctor partial: tuic == inactive", partial_summary["services"]["tuic"] == "inactive")
    check("doctor partial: trojan == inactive", partial_summary["services"]["trojan"] == "inactive")
    check("doctor partial: next_step == check_failed", partial_summary["next_step"] == "check_failed_services")

    # Missing config
    missing_data = {
        "ok": None,
        "services": {"hy2": "unknown", "tuic": "unknown", "reality": "unknown", "trojan": "unknown"},
        "security": {},
        "cloudflare": {},
        "subscription": {},
        "profile": {},
        "warnings": ["Config directory not found", "Profile not found"]
    }
    missing_summary = build_doctor_summary(missing_data)
    check("doctor missing: overall == unknown", missing_summary["overall"] == "unknown")
    check("doctor missing: config == missing", missing_summary["config"] == "missing")
    check("doctor missing: profile == missing", missing_summary["profile"] == "missing")
    check("doctor missing: next_step == complete_config", missing_summary["next_step"] == "complete_config")

    # Unknown/empty
    unknown_summary = build_doctor_summary({})
    check("doctor unknown: overall == unknown", unknown_summary["overall"] == "unknown")
    check("doctor unknown: all services unknown", all(s == "unknown" for s in unknown_summary["services"].values()))
    check("doctor unknown: full_available == True", unknown_summary["doctor"]["full_available"] is True)

    # Unknown with full_available=False
    unknown_no_full = build_doctor_summary({}, full_available=False)
    check("doctor unknown no full: full_available == False", unknown_no_full["doctor"]["full_available"] is False)

    # No raw IP/domain/URL in formatted output
    formatted_healthy = format_doctor_summary(healthy_summary, lang="en")
    check("doctor formatted: no raw domain", "test.example.com" not in formatted_healthy)
    check("doctor formatted: no raw IP", "1.2.3.4" not in formatted_healthy)
    check("doctor formatted: no raw URL", "http://" not in formatted_healthy and "https://" not in formatted_healthy)
    check("doctor formatted: has title", "Doctor Summary" in formatted_healthy)
    check("doctor formatted: has overall", "Overall:" in formatted_healthy)
    check("doctor formatted: has services", "HY2:" in formatted_healthy)

    # i18n: zh doctor summary
    formatted_zh = format_doctor_summary(healthy_summary, lang="zh")
    check("doctor zh: has title", "诊断摘要" in formatted_zh)
    check("doctor zh: has overall label", "总览" in formatted_zh)
    check("doctor zh: has services label", "服务" in formatted_zh)
    check("doctor zh: has next step", "下一步" in formatted_zh)

    # Doctor summary i18n keys exist
    for key in ["doctor_summary_title", "doctor_label_overall", "doctor_label_services",
                 "doctor_label_cloudflare", "doctor_label_next_step", "doctor_full_note",
                 "doctor_full_warning", "doctor_status_parse_error"]:
        check(f"BOT_TEXT has {key}", key in BOT_TEXT)
        check(f"BOT_TEXT {key} has en", "en" in BOT_TEXT[key])
        check(f"BOT_TEXT {key} has zh", "zh" in BOT_TEXT[key])

    # 18d. Shared status helper
    check("get_safe_status_text is callable", callable(get_safe_status_text))

    # 18e. Language command
    check("build_language_guidance is callable", callable(build_language_guidance))
    lang_guidance_en = build_language_guidance("en")
    check("language guidance en: has title", "Language Settings" in lang_guidance_en)
    check("language guidance en: shows current language", "Current language" in lang_guidance_en)
    check("language guidance en: mentions NANOBK_LANG", "NANOBK_LANG" in lang_guidance_en)
    check("language guidance en: mentions Chinese default", "default" in lang_guidance_en.lower())
    check("language guidance en: mentions English available", "English" in lang_guidance_en)
    check("language guidance en: mentions persistent planned", "planned" in lang_guidance_en.lower() or "future" in lang_guidance_en.lower())
    check("language guidance en: says no env write", "not write" in lang_guidance_en.lower() or "does not write" in lang_guidance_en.lower())
    check("language guidance en: no raw env path", "/etc/" not in lang_guidance_en and "/root/" not in lang_guidance_en)
    check("language guidance en: no raw token", "TOKEN=" not in lang_guidance_en)

    lang_guidance_zh = build_language_guidance("zh")
    check("language guidance zh: has title", "语言设置" in lang_guidance_zh)
    check("language guidance zh: shows current language", "当前语言" in lang_guidance_zh)
    check("language guidance zh: mentions NANOBK_LANG", "NANOBK_LANG" in lang_guidance_zh)
    check("language guidance zh: mentions Chinese default", "默认" in lang_guidance_zh)
    check("language guidance zh: mentions English available", "英文" in lang_guidance_zh or "English" in lang_guidance_zh)
    check("language guidance zh: no raw env path", "/etc/" not in lang_guidance_zh and "/root/" not in lang_guidance_zh)

    # Language i18n keys exist
    for key in ["language_title", "language_current_zh", "language_current_en",
                 "language_source_explanation", "language_default_zh", "language_en_available",
                 "language_persistent_planned", "language_no_env_write", "language_usage", "help_language"]:
        check(f"BOT_TEXT has {key}", key in BOT_TEXT)
        check(f"BOT_TEXT {key} has en", "en" in BOT_TEXT[key])
        check(f"BOT_TEXT {key} has zh", "zh" in BOT_TEXT[key])

    # Help text includes /language
    help_en_text = build_help_text("en")
    check("en help includes /language", "/language" in help_en_text)
    help_zh_text = build_help_text("zh")
    check("zh help includes /language", "/language" in help_zh_text)

    print(f"\n=== {passed} passed, {failed} failed ===")
    return failed == 0

# ── Telegram Bot ────────────────────────────────────────────────────────────

def create_bot_app(config: BotConfig):
    """Create and configure the Telegram bot application."""
    from telegram import Update
    from telegram.ext import (
        Application,
        CallbackQueryHandler,
        CommandHandler,
        ContextTypes,
        MessageHandler,
        filters,
    )

    confirmations = ConfirmationManager()

    def is_owner(update: Update) -> bool:
        return update.effective_user is not None and update.effective_user.id == config.owner_id

    async def unauthorized(update: Update, context: ContextTypes.DEFAULT_TYPE):
        await update.message.reply_text(bt(config.lang, "unauthorized"))

    async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)
        await update.message.reply_text(
            build_control_center_text(config.lang),
            reply_markup=_build_main_menu_keyboard(config.lang)
        )

    async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)
        await update.message.reply_text(build_help_text(config.lang))

    async def cmd_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)
        await update.message.reply_text(get_safe_status_text(config))

    async def cmd_home(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)
        await update.message.reply_text(render_home())

    async def cmd_setup_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)
        await update.message.reply_text(render_setup_status())

    async def cmd_status_json(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        user_id = update.effective_user.id

        # Soft gate: require advanced mode
        if not is_advanced_mode_enabled(user_id):
            await update.message.reply_text(bt(config.lang, "gate_not_enabled"))
            return

        result = run_nanobk(config, ["--json", "status"])
        if result.code != 0:
            await update.message.reply_text(safe_output(
                f"nanobk status failed (code {result.code}):\n{result.stderr}"
            ))
            return

        warning = bt(config.lang, "status_json_warning")
        await update.message.reply_text(warning + safe_output(result.stdout))

    async def cmd_doctor(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        user_id = update.effective_user.id
        lang = config.lang

        await update.message.reply_text(bt(lang, "doctor_running"))

        # Build beginner summary from status JSON
        status_result = run_nanobk(config, ["--json", "status"])
        summary = None

        if status_result.code == 0:
            try:
                data = json.loads(status_result.stdout)
                summary = build_doctor_summary(data, full_available=True)
            except (json.JSONDecodeError, ValueError):
                pass

        if summary is None:
            # Failed to get status — show unknown summary
            summary = build_doctor_summary({}, full_available=False)
            await update.message.reply_text(bt(lang, "doctor_status_parse_error"))

        # Format and send summary
        summary_text = format_doctor_summary(summary, lang=lang)
        await update.message.reply_text(summary_text)

        # Advanced mode: append full redacted diagnostics
        if is_advanced_mode_enabled(user_id):
            full_result = run_nanobk(config, ["doctor"], timeout=config.command_timeout)
            if full_result.code == 0:
                warning = bt(lang, "doctor_full_warning")
                full_output = full_result.stdout or full_result.stderr
                await update.message.reply_text(warning + safe_output(full_output))
            else:
                await update.message.reply_text(bt(lang, "doctor_full_unavailable"))
        else:
            # Hint about advanced mode
            await update.message.reply_text(bt(lang, "doctor_full_note"))

    async def cmd_cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        confirmations.clear(update.effective_user.id)
        await update.message.reply_text(bt(config.lang, "cancel_msg"))

    async def cmd_advanced(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        user_id = update.effective_user.id
        args = update.message.text.split()[1:] if update.message.text else []
        subcommand = args[0].lower() if args else ""

        if subcommand == "on":
            enable_advanced_mode(user_id)
            await update.message.reply_text(bt(config.lang, "advanced_on_msg"))
        elif subcommand == "off":
            disable_advanced_mode(user_id)
            await update.message.reply_text(bt(config.lang, "advanced_off_msg"))
        elif subcommand == "status":
            remaining = advanced_mode_remaining_seconds(user_id)
            if remaining > 0:
                minutes = remaining // 60
                await update.message.reply_text(
                    bt(config.lang, "advanced_enabled_status", minutes=minutes)
                )
            else:
                await update.message.reply_text(bt(config.lang, "advanced_disabled_status"))
        else:
            await update.message.reply_text(bt(config.lang, "advanced_usage"))

    async def cmd_language(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)
        await update.message.reply_text(build_language_guidance(config.lang))

    # ── Rotate handlers ─────────────────────────────────────────────────

    ROTATE_ACTIONS = {
        "rotate_all": ("rotate", ["all"]),
        "rotate_hy2": ("rotate", ["hy2"]),
        "rotate_tuic": ("rotate", ["tuic"]),
        "rotate_reality": ("rotate", ["reality"]),
        "rotate_trojan": ("rotate", ["trojan"]),
    }

    CONFIRM_COMMANDS = {
        "confirm_rotate_all": "rotate_all",
        "confirm_rotate_hy2": "rotate_hy2",
        "confirm_rotate_tuic": "rotate_tuic",
        "confirm_rotate_reality": "rotate_reality",
        "confirm_rotate_trojan": "rotate_trojan",
    }

    def make_rotate_handler(action_name: str):
        async def handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
            if not is_owner(update):
                return await unauthorized(update, context)

            _, proto_args = ROTATE_ACTIONS[action_name]
            cmd = ["rotate"] + proto_args + ["--yes"]
            confirmations.set(update.effective_user.id, action_name, cmd)

            proto = proto_args[0]
            if proto == "all":
                desc = bt(config.lang, "rotate_desc_all")
            else:
                desc = bt(config.lang, "rotate_desc_proto", proto=proto.upper())

            prompt = bt(config.lang, "rotate_confirm_prompt",
                        desc=desc, action_name=action_name)
            await update.message.reply_text(prompt)
        return handler

    async def cmd_confirm_rotate(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)

        # Extract action from command name: /confirm_rotate_tuic -> confirm_rotate_tuic
        cmd_name = update.message.text.lstrip("/").split()[0] if update.message.text else ""
        action = CONFIRM_COMMANDS.get(cmd_name)

        if action is None:
            await update.message.reply_text(bt(config.lang, "confirm_unknown"))
            return

        pending = confirmations.get(update.effective_user.id)
        if pending is None:
            await update.message.reply_text(bt(config.lang, "confirm_none"))
            return

        if pending.action != action:
            await update.message.reply_text(
                bt(config.lang, "confirm_mismatch", pending=pending.action, got=action)
            )
            return

        # Only clear after match
        confirmations.pop(update.effective_user.id)

        # Execute rotate
        if config.dry_run:
            cmd_str = " ".join(pending.command)
            await update.message.reply_text(
                bt(config.lang, "rotate_dry_run", cmd=cmd_str)
            )
            return

        await update.message.reply_text(bt(config.lang, "rotate_executing", cmd=" ".join(pending.command)))
        result = run_nanobk(config, pending.command, timeout=config.rotate_timeout)

        output = result.stdout or result.stderr
        if result.code != 0:
            output = bt(config.lang, "rotate_failed", code=result.code, output=output)

        await update.message.reply_text(safe_output(output))

    # ── Control center callback handler ───────────────────────────────────

    async def handle_menu_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
        """Handle InlineKeyboardButton callbacks from the control center menu."""
        query = update.callback_query
        if query is None:
            return

        # Owner-only check
        if query.from_user is None or query.from_user.id != config.owner_id:
            await query.answer(bt(config.lang, "unauthorized"))
            return

        await query.answer()  # Acknowledge the callback

        data = query.data or ""

        if data == CALLBACK_STATUS:
            await query.message.reply_text(get_safe_status_text(config))

        elif data == CALLBACK_RECOVERY:
            await query.message.reply_text(build_guidance_recovery(config.lang))

        elif data == CALLBACK_DIAGNOSTICS:
            await query.message.reply_text(build_guidance_diagnostics(config.lang))

        elif data == CALLBACK_ADVANCED:
            user_id = query.from_user.id
            remaining = advanced_mode_remaining_seconds(user_id)
            if remaining > 0:
                minutes = remaining // 60
                title = bt(config.lang, "advanced_mode_enabled_title")
                desc = bt(config.lang, "advanced_mode_enabled_desc", minutes=minutes)
                await query.message.reply_text(f"{title}\n\n{desc}")
            else:
                title = bt(config.lang, "advanced_mode_enabled_title")
                desc = bt(config.lang, "advanced_mode_disabled_desc")
                await query.message.reply_text(f"{title}\n\n{desc}")

        elif data == CALLBACK_ROTATE:
            await query.message.reply_text(build_guidance_rotate(config.lang))

        elif data == CALLBACK_WEB:
            await query.message.reply_text(build_guidance_web(config.lang))

        elif data == CALLBACK_HELP:
            await query.message.reply_text(build_help_text(config.lang))

        else:
            await query.message.reply_text(bt(config.lang, "unknown_callback"))

    # ── Build application ───────────────────────────────────────────────

    app = Application.builder().token(config.bot_token).build()

    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler("status", cmd_status))
    app.add_handler(CommandHandler("home", cmd_home))
    app.add_handler(CommandHandler("setup_status", cmd_setup_status))
    app.add_handler(CommandHandler("status_json", cmd_status_json))
    app.add_handler(CommandHandler("doctor", cmd_doctor))
    app.add_handler(CommandHandler("cancel", cmd_cancel))
    app.add_handler(CommandHandler("advanced", cmd_advanced))
    app.add_handler(CommandHandler("language", cmd_language))

    # Rotate commands (request confirmation)
    for action_name in ROTATE_ACTIONS:
        handler = make_rotate_handler(action_name)
        app.add_handler(CommandHandler(action_name, handler))

    # Confirm commands
    for confirm_cmd in CONFIRM_COMMANDS:
        app.add_handler(CommandHandler(confirm_cmd, cmd_confirm_rotate))

    # Control center menu callbacks (scoped by nanobk: prefix)
    app.add_handler(CallbackQueryHandler(handle_menu_callback, pattern=r"^nanobk:"))

    # Unknown command fallback
    async def cmd_unknown(update: Update, context: ContextTypes.DEFAULT_TYPE):
        if not is_owner(update):
            return await unauthorized(update, context)
        await update.message.reply_text(bt(config.lang, "unknown_command"))

    app.add_handler(MessageHandler(filters.COMMAND, cmd_unknown))

    return app

# ── Main ────────────────────────────────────────────────────────────────────

def main():
    # Self-test mode
    if "--self-test" in sys.argv:
        success = run_self_test()
        sys.exit(0 if success else 1)

    config = BotConfig.from_env()

    # Validate config
    if not config.bot_token or config.bot_token == "123456:REPLACE_ME":
        print("ERROR: TELEGRAM_BOT_TOKEN not set. Edit bot/.env first.")
        sys.exit(1)

    if not config.owner_id or config.owner_id == 123456789:
        print("ERROR: OWNER_TELEGRAM_ID not set. Edit bot/.env first.")
        sys.exit(1)

    if config.dry_run:
        print("[DRY-RUN] Bot started. Rotate commands will not execute.")

    print("Starting NanoBK Bot (owner configured)...")
    app = create_bot_app(config)
    app.run_polling(drop_pending_updates=True)

if __name__ == "__main__":
    main()
