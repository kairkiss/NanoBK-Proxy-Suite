#!/usr/bin/env python3
"""
Test: Web i18n Minimal Implementation (v1.9.31)

Verifies:
- NANOBK_LANG support in WebConfig
- Translation helper exists and works
- zh/en login/dashboard/status/raw JSON warning text
- zh/en status labels
- zh/en advanced mode controls
- zh/en rotate page copy
- /api/status unchanged
- no raw secrets in translations
- existing functionality preserved
"""

import os
import sys

REPO_DIR = os.path.join(os.path.dirname(__file__), "..")
sys.path.insert(0, REPO_DIR)

passed = 0
failed = 0

def check(desc: str, ok: bool):
    global passed, failed
    if ok:
        print(f"  \033[32m✓\033[0m {desc}")
        passed += 1
    else:
        print(f"  \033[31m✗\033[0m {desc}")
        failed += 1

# Read source
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()

# Import i18n module
from web.i18n import normalize_lang, wt, WEB_TEXT

print("=== Web i18n Minimal Test (v1.9.31) ===\n")

# ── 1. Language config ────────────────────────────────────────────────────

print("--- Language config ---\n")

check("normalize_lang exists", callable(normalize_lang))
check("normalize_lang(None) == zh", normalize_lang(None) == "zh")
check("normalize_lang('') == zh", normalize_lang("") == "zh")
check("normalize_lang('en') == en", normalize_lang("en") == "en")
check("normalize_lang('zh') == zh", normalize_lang("zh") == "zh")
check("normalize_lang('zh-cn') == zh", normalize_lang("zh-cn") == "zh")
check("normalize_lang('zh_cn') == zh", normalize_lang("zh_cn") == "zh")
check("normalize_lang('chinese') == zh", normalize_lang("chinese") == "zh")
check("normalize_lang('invalid') == zh", normalize_lang("invalid") == "zh")
check("WebConfig has lang field", "lang" in web_source and "WebConfig" in web_source)
check("NANOBK_LANG read in from_env", "NANOBK_LANG" in web_source)

# ── 2. Translation helper ────────────────────────────────────────────────

print("\n--- Translation helper ---\n")

check("wt() is callable", callable(wt))
check("wt en returns English", "NanoBK Web Panel" in wt("en", "login_title"))
check("wt zh returns Chinese", "NanoBK Web 面板" in wt("zh", "login_title"))
check("wt fallback for missing key", wt("en", "nonexistent_key_xyz") == "nonexistent_key_xyz")
check("wt fallback for missing lang", "NanoBK" in wt("invalid_lang", "login_title"))
check("wt format kwargs work", "TUIC" in wt("en", "rotate_confirm_desc", protocol="TUIC"))
check("wt zh format kwargs work", "TUIC" in wt("zh", "rotate_confirm_desc", protocol="TUIC"))

# ── 3. Login page text ───────────────────────────────────────────────────

print("\n--- Login page text ---\n")

check("en login title", "NanoBK Web Panel" in wt("en", "login_title"))
check("zh login title", "NanoBK Web 面板" in wt("zh", "login_title"))
check("en login token label", "Access Token" in wt("en", "login_token_label"))
check("zh login token label", "访问令牌" in wt("zh", "login_token_label"))
check("en login button", "Login" in wt("en", "login_button"))
check("zh login button", "登录" in wt("zh", "login_button"))
check("en login error", "Invalid token" in wt("en", "login_error_invalid"))
check("zh login error", "无效" in wt("zh", "login_error_invalid"))

# ── 4. Dashboard text ────────────────────────────────────────────────────

print("\n--- Dashboard text ---\n")

check("en dashboard title", "NanoBK Dashboard" in wt("en", "dashboard_title"))
check("zh dashboard title", "NanoBK 控制台" in wt("zh", "dashboard_title"))
check("en quick actions", "Quick Actions" in wt("en", "dashboard_quick_actions"))
check("zh quick actions", "快捷操作" in wt("zh", "dashboard_quick_actions"))
check("en full status", "Full Status" in wt("en", "dashboard_full_status"))
check("zh full status", "完整状态" in wt("zh", "dashboard_full_status"))
check("en rotate keys", "Rotate Keys" in wt("en", "dashboard_rotate_keys"))
check("zh rotate keys", "轮换密钥" in wt("zh", "dashboard_rotate_keys"))

# ── 5. Status labels ─────────────────────────────────────────────────────

print("\n--- Status labels ---\n")

check("en label Overall", wt("en", "status_label_overall") == "Overall")
check("zh label Overall", wt("zh", "status_label_overall") == "总览")
check("en label VPS", wt("en", "status_label_vps") == "VPS")
check("en label Protocols", wt("en", "status_protocols") == "Protocols")
check("zh label Protocols", wt("zh", "status_protocols") == "协议")
check("en label Cloudflare", wt("en", "status_cloudflare") == "Cloudflare")
check("en label Subscription", wt("en", "status_subscription") == "Subscription")
check("zh label Subscription", wt("zh", "status_subscription") == "订阅")
check("en label Secrets", wt("en", "status_secrets") == "Secrets")
check("zh label Secrets", wt("zh", "status_secrets") == "密钥")
check("en label Next step", wt("en", "status_next_step") == "Next step")
check("zh label Next step", wt("zh", "status_next_step") == "下一步")
check("en footer", "hidden" in wt("en", "status_footer"))
check("zh footer", "隐藏" in wt("zh", "status_footer"))

# Status category values NOT translated
from web.app import format_status
formatted = format_status({"ok": True, "services": {"hy2": "active"}}, )
check("status values not translated: healthy", "healthy" in str(formatted["cards"]["overall"]))
check("status values not translated: active", "active" in str(formatted["cards"]["services"]))

# ── 6. Raw JSON locked panel ─────────────────────────────────────────────

print("\n--- Raw JSON locked panel ---\n")

check("en locked title", "Advanced Diagnostics" in wt("en", "raw_json_locked_title"))
check("zh locked title", "高级诊断" in wt("zh", "raw_json_locked_title"))
check("en locked desc", "locked" in wt("en", "raw_json_locked_desc").lower())
check("zh locked desc", "锁定" in wt("zh", "raw_json_locked_desc"))
check("en locked use cards", "status cards" in wt("en", "raw_json_locked_use_cards").lower())
check("zh locked use cards", "状态卡片" in wt("zh", "raw_json_locked_use_cards"))
check("en locked enable hint", "15 minutes" in wt("en", "raw_json_locked_enable_hint"))
check("zh locked enable hint", "15" in wt("zh", "raw_json_locked_enable_hint"))
check("en locked secrets note", "remain hidden" in wt("en", "raw_json_locked_secrets_note"))
check("zh locked secrets note", "必须隐藏" in wt("zh", "raw_json_locked_secrets_note"))

# ── 7. Raw JSON warning (when visible) ───────────────────────────────────

print("\n--- Raw JSON warning ---\n")

check("en warning title", "Advanced diagnostics" in wt("en", "raw_json_warning_title"))
check("zh warning title", "高级诊断" in wt("zh", "raw_json_warning_title"))
check("en warning text says redacted", "redacted" in wt("en", "raw_json_warning_text"))
check("zh warning text says redacted", "脱敏" in wt("zh", "raw_json_warning_text"))
check("en warning text says troubleshooting", "troubleshooting" in wt("en", "raw_json_warning_text"))
check("zh warning text says troubleshooting", "故障排查" in wt("zh", "raw_json_warning_text"))
check("en warning text says not subscription", "subscription" in wt("en", "raw_json_warning_text").lower())
check("en warning text recommends cards", "status cards" in wt("en", "raw_json_warning_text").lower())

# ── 8. Advanced mode controls ────────────────────────────────────────────

print("\n--- Advanced mode controls ---\n")

check("en advanced title", "Advanced Diagnostics" in wt("en", "advanced_title"))
check("zh advanced title", "高级诊断" in wt("zh", "advanced_title"))
check("en enabled badge", "expires" in wt("en", "advanced_enabled_badge", minutes=10))
check("zh enabled badge", "过期" in wt("zh", "advanced_enabled_badge", minutes=10))
check("en disabled note", "disabled" in wt("en", "advanced_disabled_note"))
check("zh disabled note", "已禁用" in wt("zh", "advanced_disabled_note"))
check("en enable warning title", "Enable advanced" in wt("en", "advanced_enable_warning_title"))
check("zh enable warning title", "启用高级诊断" in wt("zh", "advanced_enable_warning_title"))
check("en enable warning text", "redacted" in wt("en", "advanced_enable_warning_text"))
check("zh enable warning text", "脱敏" in wt("zh", "advanced_enable_warning_text"))
check("en enable button", "Enable" in wt("en", "advanced_enable_button"))
check("zh enable button", "启用" in wt("zh", "advanced_enable_button"))
check("en disable button", "Disable" in wt("en", "advanced_disable_button"))
check("zh disable button", "禁用" in wt("zh", "advanced_disable_button"))

# ── 9. Doctor page ───────────────────────────────────────────────────────

print("\n--- Doctor page ---\n")

check("en doctor title", "Doctor" in wt("en", "doctor_title"))
check("zh doctor title", "诊断" in wt("zh", "doctor_title"))
check("en run button", "Run Doctor" in wt("en", "doctor_run_button"))
check("zh run button", "运行诊断" in wt("zh", "doctor_run_button"))

# ── 10. Rotate page ──────────────────────────────────────────────────────

print("\n--- Rotate page ---\n")

check("en rotate title", "Rotate Keys" in wt("en", "rotate_title"))
check("zh rotate title", "轮换密钥" in wt("zh", "rotate_title"))
check("en rotate dry_run", "DRY-RUN" in wt("en", "rotate_dry_run_badge"))
check("zh rotate dry_run", "模拟运行" in wt("zh", "rotate_dry_run_badge"))
check("en rotate confirm title", "Confirm Rotation" in wt("en", "rotate_confirm_title"))
check("zh rotate confirm title", "确认轮换" in wt("zh", "rotate_confirm_title"))
check("en rotate confirm desc", "TUIC" in wt("en", "rotate_confirm_desc", protocol="TUIC"))
check("zh rotate confirm desc", "TUIC" in wt("zh", "rotate_confirm_desc", protocol="TUIC"))
check("en rotate select title", "Select Protocol" in wt("en", "rotate_select_title"))
check("zh rotate select title", "选择协议" in wt("zh", "rotate_select_title"))
check("en rotate expired error", "expired" in wt("en", "rotate_expired_error"))
check("zh rotate expired error", "过期" in wt("zh", "rotate_expired_error"))
check("en rotate failed", "failed" in wt("en", "rotate_failed", code=1))
check("zh rotate failed", "失败" in wt("zh", "rotate_failed", code=1))

# ── 11. /api/status unchanged ────────────────────────────────────────────

print("\n--- /api/status unchanged ---\n")

check("/api/status route exists", '"/api/status"' in web_source)
check("api_status uses redact_json", "redact_json(data)" in web_source)
check("/api/status not gated by advanced", "is_advanced_mode_enabled" not in web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else True)

# ── 12. No raw secrets in translations ────────────────────────────────────

print("\n--- No raw secrets in translations ---\n")

all_text = str(WEB_TEXT)
check("no TOKEN= in translations", "TOKEN=" not in all_text)
check("no SECRET= in translations", "SECRET=" not in all_text)
check("no PRIVATE_KEY= in translations", "PRIVATE_KEY=" not in all_text)
check("no workers.dev in translations", "workers.dev" not in all_text)
check("no subscription URL in translations", "subscription URL" not in all_text.lower())
check("no http:// in translations", "http://" not in all_text)
check("no https:// in translations", "https://" not in all_text)

# ── 13. Safety checks ─────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True in web source", "shell=True" not in web_source)
check("no os.system in web source", "os.system" not in web_source)
check("shared redaction import", "from lib.nanobk_redaction import" in web_source)
check("redact_json_obj imported", "redact_json_obj" in web_source)

# ── 14. Raw JSON gating template ──────────────────────────────────────────

print("\n--- Raw JSON gating template ---\n")

with open(os.path.join(REPO_DIR, "web", "templates", "status.html")) as f:
    status_html = f.read()

check("template branches on advanced_mode_enabled", "advanced_mode_enabled" in status_html)
check("template has locked panel", "locked-panel" in status_html)
check("template has raw_json", "status.raw_json" in status_html)
check("template has details block", "<details>" in status_html)
check("template has translation calls", "{{ t(" in status_html)

# ── 15. No Bot changes ────────────────────────────────────────────────────

print("\n--- No Bot changes ---\n")

with open(os.path.join(REPO_DIR, "bot", "nanobk_bot.py")) as f:
    bot_source = f.read()

check("Bot has NANOBK_LANG", "NANOBK_LANG" in bot_source)
check("Bot has normalize_lang", "normalize_lang" in bot_source)
check("Bot has bt()", "def bt" in bot_source)
check("Bot has BOT_TEXT", "BOT_TEXT" in bot_source)

# ── Summary ───────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    sys.exit(1)
else:
    print("All tests passed!")
