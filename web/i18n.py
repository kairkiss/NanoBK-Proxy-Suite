"""
NanoBK Web Panel — Internationalization (i18n) support.

Minimal zh/en translation layer for Web Panel UI text.
No external dependencies. Safe fallback to English.
"""

from __future__ import annotations

SUPPORTED_LANGS = {"en", "zh"}
DEFAULT_LANG = "en"


def normalize_lang(value: str | None) -> str:
    """Normalize language code. Returns 'en' or 'zh'. Defaults to 'en'."""
    if not value:
        return DEFAULT_LANG
    v = value.strip().lower()
    if v in ("zh", "zh-cn", "zh_cn", "chinese", "中文"):
        return "zh"
    if v in SUPPORTED_LANGS:
        return v
    return DEFAULT_LANG


# ── Web translation dictionary ───────────────────────────────────────────────
# Keys are stable identifiers. Values are lang-keyed dicts.
# Status category values (healthy/failed/unknown/etc.) are NOT translated.

WEB_TEXT: dict[str, dict[str, str]] = {
    # ── Login ──
    "login_title": {
        "en": "NanoBK Web Panel",
        "zh": "NanoBK Web 面板",
    },
    "login_token_label": {
        "en": "Access Token",
        "zh": "访问令牌",
    },
    "login_token_placeholder": {
        "en": "Enter token",
        "zh": "请输入令牌",
    },
    "login_button": {
        "en": "Login",
        "zh": "登录",
    },
    "login_error_invalid": {
        "en": "Invalid token.",
        "zh": "令牌无效。",
    },

    # ── Navigation ──
    "nav_dashboard": {
        "en": "Dashboard",
        "zh": "控制台",
    },
    "nav_status": {
        "en": "Status",
        "zh": "状态",
    },
    "nav_doctor": {
        "en": "Doctor",
        "zh": "诊断",
    },
    "nav_rotate": {
        "en": "Rotate",
        "zh": "轮换",
    },
    "nav_logout": {
        "en": "Logout",
        "zh": "退出",
    },

    # ── Dashboard ──
    "dashboard_title": {
        "en": "NanoBK Dashboard",
        "zh": "NanoBK 控制台",
    },
    "dashboard_dry_run": {
        "en": "DRY-RUN MODE",
        "zh": "模拟运行模式",
    },
    "dashboard_load_error": {
        "en": "Could not load status.",
        "zh": "无法加载状态。",
    },
    "dashboard_try_status": {
        "en": "Try Status page",
        "zh": "请尝试状态页面",
    },
    "dashboard_quick_actions": {
        "en": "Quick Actions",
        "zh": "快捷操作",
    },
    "dashboard_full_status": {
        "en": "Full Status",
        "zh": "完整状态",
    },
    "dashboard_doctor": {
        "en": "Doctor",
        "zh": "诊断",
    },
    "dashboard_rotate_keys": {
        "en": "Rotate Keys",
        "zh": "轮换密钥",
    },

    # ── Status cards ──
    "status_overall": {
        "en": "Overall Status",
        "zh": "总体状态",
    },
    "status_label_overall": {
        "en": "Overall",
        "zh": "总览",
    },
    "status_label_vps": {
        "en": "VPS",
        "zh": "VPS",
    },
    "status_protocols": {
        "en": "Protocols",
        "zh": "协议",
    },
    "status_cloudflare": {
        "en": "Cloudflare",
        "zh": "Cloudflare",
    },
    "status_other": {
        "en": "Other",
        "zh": "其他",
    },
    "status_subscription": {
        "en": "Subscription",
        "zh": "订阅",
    },
    "status_secrets": {
        "en": "Secrets",
        "zh": "密钥",
    },
    "status_profile": {
        "en": "Profile",
        "zh": "配置",
    },
    "status_next_step": {
        "en": "Next step",
        "zh": "下一步",
    },
    "status_footer": {
        "en": "Status from nanobk CLI. Sensitive addresses are hidden.",
        "zh": "状态来自 nanobk CLI。敏感地址已隐藏。",
    },
    "status_no_data": {
        "en": "No status data available.",
        "zh": "暂无状态数据。",
    },

    # ── Raw JSON locked panel ──
    "raw_json_locked_title": {
        "en": "🔒 Raw JSON (Advanced Diagnostics)",
        "zh": "🔒 原始 JSON（高级诊断）",
    },
    "raw_json_locked_desc": {
        "en": "Raw JSON belongs to advanced diagnostics and is currently locked.",
        "zh": "原始 JSON 属于高级诊断，当前已锁定。",
    },
    "raw_json_locked_use_cards": {
        "en": "Use the status cards above for the normal safe summary.",
        "zh": "请使用上方状态卡片查看普通安全摘要。",
    },
    "raw_json_locked_enable_hint": {
        "en": "Enable advanced diagnostics mode to view redacted Raw JSON. This mode expires automatically after 15 minutes.",
        "zh": "启用高级诊断模式可查看脱敏原始 JSON。该模式将在 15 分钟后自动过期。",
    },
    "raw_json_locked_secrets_note": {
        "en": "Even in advanced mode, secrets, raw addresses, and subscription URLs must remain hidden.",
        "zh": "即使在高级模式下，密钥、原始地址和订阅 URL 仍必须隐藏。",
    },

    # ── Raw JSON warning (when visible) ──
    "raw_json_warning_title": {
        "en": "⚠️ Advanced diagnostics",
        "zh": "⚠️ 高级诊断",
    },
    "raw_json_warning_text": {
        "en": "Raw JSON is redacted and intended for troubleshooting only.\nIt is not the normal status view and should not be shared as subscription information.\nUse the status cards above for the normal safe summary.",
        "zh": "原始 JSON 已脱敏，仅用于故障排查。\n它不是普通状态视图，不应作为订阅信息分享。\n请使用上方状态卡片查看普通安全摘要。",
    },
    "raw_json_details_label": {
        "en": "Raw JSON (advanced diagnostics)",
        "zh": "原始 JSON（高级诊断）",
    },

    # ── Advanced mode controls ──
    "advanced_title": {
        "en": "Advanced Diagnostics",
        "zh": "高级诊断",
    },
    "advanced_enabled_badge": {
        "en": "Enabled — expires in ~{minutes} minutes",
        "zh": "已启用 — 约 {minutes} 分钟后过期",
    },
    "advanced_disabled_note": {
        "en": "Advanced diagnostics mode is disabled.",
        "zh": "高级诊断模式已禁用。",
    },
    "advanced_enable_warning_title": {
        "en": "⚠️ Enable advanced diagnostics?",
        "zh": "⚠️ 启用高级诊断？",
    },
    "advanced_enable_warning_text": {
        "en": "Advanced diagnostics remain redacted, but may reveal system structure.\nDo not share full diagnostic output with untrusted people.\nSecrets, raw addresses, and subscription URLs must remain hidden.\nThis mode expires in 15 minutes.",
        "zh": "高级诊断仍被脱敏，但可能暴露系统结构。\n请勿将完整诊断输出分享给不可信的人。\n密钥、原始地址和订阅 URL 仍必须隐藏。\n此模式将在 15 分钟后过期。",
    },
    "advanced_enable_button": {
        "en": "Enable advanced mode",
        "zh": "启用高级模式",
    },
    "advanced_disable_button": {
        "en": "Disable advanced mode",
        "zh": "禁用高级模式",
    },

    # ── Doctor ──
    "doctor_title": {
        "en": "Doctor",
        "zh": "诊断",
    },
    "doctor_run_button": {
        "en": "Run Doctor",
        "zh": "运行诊断",
    },
    "doctor_output_title": {
        "en": "Output",
        "zh": "输出",
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
        "en": "Enable advanced mode for full diagnostics.",
        "zh": "启用高级模式获取完整诊断。",
    },
    "doctor_next_unknown": {
        "en": "Run /status or check SSH for more information.",
        "zh": "运行 /status 或检查 SSH 获取更多信息。",
    },
    "doctor_full_note": {
        "en": "💡 Full diagnostics are available in advanced mode. Enable advanced mode from the Status page, then run Doctor again.",
        "zh": "💡 完整诊断仅在高级模式下可用。请从状态页面启用高级模式，然后再次运行诊断。",
    },
    "doctor_full_warning": {
        "en": "⚠️ Advanced diagnostics\nFull output is redacted but may reveal system structure.\nDo not share with untrusted people.",
        "zh": "⚠️ 高级诊断\n完整输出已脱敏但可能暴露系统结构。\n请勿分享给不可信的人。",
    },
    "doctor_full_details_label": {
        "en": "Full Diagnostics (advanced, redacted)",
        "zh": "完整诊断（高级，已脱敏）",
    },
    "doctor_status_parse_error": {
        "en": "Failed to parse status data. Showing unknown summary.",
        "zh": "无法解析状态数据。显示未知摘要。",
    },
    "doctor_full_unavailable": {
        "en": "Full diagnostics unavailable (command failed).",
        "zh": "完整诊断不可用（命令失败）。",
    },
    "doctor_intro_text": {
        "en": "Click \"Run Doctor\" to check your NanoBK environment. A safe summary will be shown below.",
        "zh": "点击\"运行诊断\"检查您的 NanoBK 环境。安全摘要将显示在下方。",
    },

    # ── Rotate ──
    "rotate_title": {
        "en": "Rotate Keys",
        "zh": "轮换密钥",
    },
    "rotate_dry_run_badge": {
        "en": "DRY-RUN MODE — rotate will show command but not execute",
        "zh": "模拟运行模式 — 轮换将显示命令但不执行",
    },
    "rotate_confirm_title": {
        "en": "Confirm Rotation",
        "zh": "确认轮换",
    },
    "rotate_confirm_desc": {
        "en": "You are about to rotate {protocol} credentials.",
        "zh": "即将轮换 {protocol} 凭证。",
    },
    "rotate_confirm_restart_note": {
        "en": "This will restart proxy services and update local profile.",
        "zh": "此操作将重启代理服务并更新本地配置。",
    },
    "rotate_confirm_cf_note": {
        "en": "Cloudflare sync depends on your local nanobk configuration.",
        "zh": "Cloudflare 同步取决于本地 nanobk 配置。",
    },
    "rotate_confirm_button": {
        "en": "Confirm Rotate {protocol}",
        "zh": "确认轮换 {protocol}",
    },
    "rotate_cancel_button": {
        "en": "Cancel",
        "zh": "取消",
    },
    "rotate_pending_note": {
        "en": "Pending: {protocol} (will expire in ~120s)",
        "zh": "待处理：{protocol}（约 120 秒后过期）",
    },
    "rotate_confirm_short": {
        "en": "Confirm",
        "zh": "确认",
    },
    "rotate_dry_run_result_title": {
        "en": "Dry-Run Result",
        "zh": "模拟运行结果",
    },
    "rotate_result_title": {
        "en": "Rotation Result",
        "zh": "轮换结果",
    },
    "rotate_select_title": {
        "en": "Select Protocol",
        "zh": "选择协议",
    },
    "rotate_select_desc": {
        "en": "Choose which protocol to rotate. Confirmation required.",
        "zh": "请选择要轮换的协议。需要确认。",
    },
    "rotate_button_label": {
        "en": "Rotate {protocol}",
        "zh": "轮换 {protocol}",
    },
    "rotate_expired_error": {
        "en": "No pending confirmation (may have expired).",
        "zh": "无待处理确认（可能已过期）。",
    },
    "rotate_invalid_protocol": {
        "en": "Invalid protocol: {protocol}",
        "zh": "无效协议：{protocol}",
    },
    "rotate_failed": {
        "en": "Rotate failed (code {code}):",
        "zh": "轮换失败（代码 {code}）：",
    },

    # ── Error pages ──
    "csrf_error": {
        "en": "CSRF validation failed.",
        "zh": "CSRF 验证失败。",
    },
    "unauthorized": {
        "en": "Unauthorized.",
        "zh": "未授权。",
    },

    # ── General ──
    "nanobk_web_panel": {
        "en": "NanoBK Web Panel",
        "zh": "NanoBK Web 面板",
    },
}


def wt(lang: str, key: str, **kwargs: object) -> str:
    """Get translated Web text. Falls back to English if key/language missing."""
    entry = WEB_TEXT.get(key)
    if entry is None:
        return key  # fallback to key name
    text = entry.get(lang) or entry.get(DEFAULT_LANG) or key
    if kwargs:
        try:
            text = text.format(**kwargs)
        except (KeyError, IndexError):
            pass
    return text
