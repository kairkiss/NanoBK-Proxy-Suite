#!/usr/bin/env python3
"""
Test: Web Session Language Switch (v1.9.51)

Verifies:
- get_current_lang() priority: session > config > default zh
- POST /language route: login, CSRF, valid/invalid inputs
- session storage and logout clearing
- layout language switch form
- no env writes, no shell=True, no os.system
- /api/status unchanged
- Raw JSON gating unchanged

Usage:
    python3 tests/web-language-switch-v1.9.51.py
"""

import os
import sys
import secrets

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


# Read sources
with open(os.path.join(REPO_DIR, "web", "app.py")) as f:
    web_source = f.read()
with open(os.path.join(REPO_DIR, "web", "i18n.py")) as f:
    i18n_source = f.read()
with open(os.path.join(REPO_DIR, "web", "templates", "layout.html")) as f:
    layout_source = f.read()

# Import modules
from web.i18n import normalize_lang, wt, WEB_TEXT, SUPPORTED_LANGS, DEFAULT_LANG
from web.app import WebConfig, create_app

print("=== Web Language Switch Test (v1.9.51) ===\n")

# ── 1. i18n keys ─────────────────────────────────────────────────────────────

print("--- i18n keys ---\n")

for key in ["lang_switch_to_en", "lang_switch_to_zh", "lang_changed", "lang_invalid"]:
    check(f"WEB_TEXT has {key}", key in WEB_TEXT)

check("lang_switch_to_en EN", wt("en", "lang_switch_to_en") == "EN")
check("lang_switch_to_en zh", wt("zh", "lang_switch_to_en") == "EN")
check("lang_switch_to_zh EN", wt("en", "lang_switch_to_zh") == "中文")
check("lang_switch_to_zh zh", wt("zh", "lang_switch_to_zh") == "中文")
check("lang_changed en", "Language changed" in wt("en", "lang_changed"))
check("lang_changed zh", "语言已切换" in wt("zh", "lang_changed"))
check("lang_invalid en", "Invalid" in wt("en", "lang_invalid"))
check("lang_invalid zh", "无效" in wt("zh", "lang_invalid"))

# ── 2. get_current_lang helper ────────────────────────────────────────────────

print("\n--- get_current_lang helper ---\n")

check("get_current_lang defined", "def get_current_lang" in web_source)
check("get_current_lang checks session", 'session.get("lang")' in web_source)
check("get_current_lang validates zh/en", '"zh", "en"' in web_source)
check("get_current_lang falls back to config.lang", "config.lang" in web_source.split("def get_current_lang")[1].split("def ")[0])

# ── 3. Context processor uses get_current_lang ───────────────────────────────

print("\n--- Context processor ---\n")

inject_section = web_source.split("def inject_i18n")[1].split("def ")[0] if "def inject_i18n" in web_source else ""
check("inject_i18n uses get_current_lang", "get_current_lang()" in inject_section)
check("inject_i18n returns lang", '"lang"' in inject_section)

# ── 4. Language route ─────────────────────────────────────────────────────────

print("\n--- Language route ---\n")

check("/language route defined", '"/language"' in web_source)
# The language function is defined inside create_app — check decorators + body
# Get the decorator line + function body
lang_decorator_area = web_source.split("def language(")[0][-200:] if "def language(" in web_source else ""
lang_body = web_source.split("def language(")[1].split("\n    def ")[0] if "def language(" in web_source else ""
check("/language is POST only", "POST" in lang_decorator_area)
check("/language requires login", "require_login" in lang_decorator_area)
check("/language validates CSRF", "validate_csrf" in lang_body)
check("/language accepts lang form field", 'request.form.get("lang"' in lang_body)
check("/language stores valid lang", 'session["lang"]' in lang_body)
check("/language only accepts zh/en", '"zh", "en"' in lang_body)
check("/language redirects safely", "redirect" in lang_body)

# ── 5. Logout clears session ──────────────────────────────────────────────────

print("\n--- Logout clears session ---\n")

logout_section = web_source.split("def logout")[1].split("def ")[0] if "def logout" in web_source else ""
check("logout calls session.clear()", "session.clear()" in logout_section)
check("logout validates CSRF", "validate_csrf" in logout_section)

# ── 6. Layout language switch form ────────────────────────────────────────────

print("\n--- Layout language switch form ---\n")

check("layout has /language form", 'action="/language"' in layout_source)
# The /language form block in layout — extract between /language form and next </form>
if 'action="/language"' in layout_source:
    lang_form_block = layout_source.split('action="/language"')[1].split("</form>")[0]
else:
    lang_form_block = ""
check("layout /language uses POST", 'method="POST"' in layout_source.split('action="/language"')[0][-100:] if 'action="/language"' in layout_source else False)
check("layout /language has CSRF", "csrf_token" in lang_form_block)
check("layout /language has lang field", 'name="lang"' in lang_form_block)
check("layout /language has button", "<button" in lang_form_block)
check("layout preserves logout form", 'action="/logout"' in layout_source)
check("layout preserves dashboard link", 'href="/"' in layout_source)
check("layout preserves status link", 'href="/status"' in layout_source)
check("layout preserves doctor link", 'href="/doctor"' in layout_source)
check("layout preserves rotate link", 'href="/rotate"' in layout_source)

# ── 7. No env writes ─────────────────────────────────────────────────────────

print("\n--- No env writes ---\n")

check("no open web/.env", 'open("web/.env"' not in web_source and "open('web/.env'" not in web_source)
check("no Path web/.env write", 'Path("web/.env")' not in web_source or ".write" not in web_source)
check("no open bot/.env", 'open("bot/.env"' not in web_source and "open('bot/.env'" not in web_source)

# ── 8. Safety checks ─────────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True", "shell=True" not in web_source)
check("no os.system", "os.system" not in web_source)
check("shared redaction import", "from lib.nanobk_redaction import" in web_source)

# ── 9. /api/status unchanged ─────────────────────────────────────────────────

print("\n--- /api/status unchanged ---\n")

check("/api/status route exists", '"/api/status"' in web_source)
check("api_status uses redact_json", "redact_json" in web_source.split("def api_status")[1].split("def ")[0] if "def api_status" in web_source else False)

# ── 10. Raw JSON gating unchanged ────────────────────────────────────────────

print("\n--- Raw JSON gating unchanged ---\n")

check("Raw JSON gating template exists", "advanced_mode_enabled" in open(os.path.join(REPO_DIR, "web", "templates", "status.html")).read())
check("locked-panel exists", "locked-panel" in open(os.path.join(REPO_DIR, "web", "templates", "status.html")).read())

# ── 11. Flask app integration ────────────────────────────────────────────────

print("\n--- Flask app integration ---\n")

try:
    from flask import Flask
    flask_available = True
except ImportError:
    flask_available = False
    print("  (Flask not installed — skipping integration tests)\n")

if flask_available:
    config = WebConfig(
        web_token="test-token-12345",
        nanobk_cli="/usr/bin/echo",
        dry_run=True,
        secret_key="test-secret-key-abc",
    )
    app = create_app(config)

    with app.test_client() as client:
        # Login first
        with client.session_transaction() as sess:
            sess["authenticated"] = True
            sess["csrf_token"] = "test-csrf-token"

        # GET /language should 405 (POST only)
        resp = client.get("/language")
        check("GET /language returns 405", resp.status_code == 405)

        # POST /language without CSRF should 403
        resp = client.post("/language", data={"lang": "en"})
        check("POST /language without CSRF returns 403", resp.status_code == 403)

        # POST /language with valid CSRF and lang=en
        resp = client.post("/language", data={"lang": "en", "csrf_token": "test-csrf-token"}, follow_redirects=False)
        check("POST /language lang=en redirects", resp.status_code in (302, 303))
        with client.session_transaction() as sess:
            check("session stores lang=en", sess.get("lang") == "en")

        # POST /language with valid CSRF and lang=zh
        resp = client.post("/language", data={"lang": "zh", "csrf_token": "test-csrf-token"}, follow_redirects=False)
        check("POST /language lang=zh redirects", resp.status_code in (302, 303))
        with client.session_transaction() as sess:
            check("session stores lang=zh", sess.get("lang") == "zh")

        # POST /language with invalid lang=fr
        with client.session_transaction() as sess:
            sess.pop("lang", None)
        resp = client.post("/language", data={"lang": "fr", "csrf_token": "test-csrf-token"}, follow_redirects=False)
        check("POST /language lang=fr redirects", resp.status_code in (302, 303))
        with client.session_transaction() as sess:
            check("invalid lang=fr not stored", sess.get("lang") is None)

        # POST /language with empty lang
        resp = client.post("/language", data={"lang": "", "csrf_token": "test-csrf-token"}, follow_redirects=False)
        check("POST /language empty lang redirects", resp.status_code in (302, 303))
        with client.session_transaction() as sess:
            check("empty lang not stored", sess.get("lang") is None)

        # POST /language without login
        with client.session_transaction() as sess:
            sess.clear()
        resp = client.post("/language", data={"lang": "en", "csrf_token": "test-csrf-token"}, follow_redirects=False)
        check("POST /language without login redirects to login", resp.status_code in (302, 303) and "/login" in (resp.headers.get("Location", "") or ""))

        # Logout clears lang
        with client.session_transaction() as sess:
            sess["authenticated"] = True
            sess["csrf_token"] = "test-csrf-token"
            sess["lang"] = "en"
        resp = client.post("/logout", data={"csrf_token": "test-csrf-token"}, follow_redirects=False)
        check("logout redirects", resp.status_code in (302, 303))
        with client.session_transaction() as sess:
            check("logout clears lang", sess.get("lang") is None)

        # Language switch affects rendered text
        with client.session_transaction() as sess:
            sess["authenticated"] = True
            sess["csrf_token"] = "test-csrf-token"
            sess["lang"] = "en"
        resp = client.get("/")
        check("en dashboard renders English", b"NanoBK Dashboard" in resp.data)

        with client.session_transaction() as sess:
            sess["lang"] = "zh"
        resp = client.get("/")
        check("zh dashboard renders Chinese", "控制台".encode() in resp.data)

# ── 12. Existing tests still pass ────────────────────────────────────────────

print("\n--- Existing functionality preserved ---\n")

test_config = WebConfig(
    web_token="test-token-12345",
    nanobk_cli="/usr/bin/echo",
    dry_run=True,
    secret_key="test-secret-key-abc",
)
check("WebConfig has lang field", hasattr(test_config, "lang"))
check("WebConfig default lang is zh", test_config.lang == "zh")
check("normalize_lang exists", callable(normalize_lang))
check("normalize_lang(None) == zh", normalize_lang(None) == "zh")
check("normalize_lang('en') == en", normalize_lang("en") == "en")
check("normalize_lang('zh') == zh", normalize_lang("zh") == "zh")
check("wt() exists", callable(wt))
check("SUPPORTED_LANGS is correct", SUPPORTED_LANGS == {"en", "zh"})
check("DEFAULT_LANG is zh", DEFAULT_LANG == "zh")

# ── Summary ──────────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    print("\n\033[31mFAIL: Web language switch has issues.\033[0m")
    sys.exit(1)
else:
    print("\n\033[32mPASS: Web language switch is correct.\033[0m")
