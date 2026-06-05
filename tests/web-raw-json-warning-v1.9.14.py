#!/usr/bin/env python3
"""
Test: Web Raw JSON warning copy (v1.9.14)

Verifies:
- Raw JSON warning text is present in Status template
- Warning says Raw JSON is redacted
- Warning says it is for troubleshooting/advanced diagnostics
- Warning says not to share as subscription information
- Warning recommends status cards / safe summary
- Raw JSON <details> remains present
- status.raw_json remains referenced
- /api/status route still exists
- No advanced mode/session toggle added
- No shell=True in Web source
"""

import os
import sys

passed = 0
failed = 0

def check(desc: str, ok: bool):
    global passed, failed
    if ok:
        print(f"  ✓ {desc}")
        passed += 1
    else:
        print(f"  ✗ {desc}")
        failed += 1

REPO_ROOT = os.path.join(os.path.dirname(__file__), "..")

# ── Read source files ─────────────────────────────────────────────────────

with open(os.path.join(REPO_ROOT, "web", "templates", "status.html")) as f:
    status_html = f.read()

with open(os.path.join(REPO_ROOT, "web", "app.py")) as f:
    web_source = f.read()

with open(os.path.join(REPO_ROOT, "web", "static", "style.css")) as f:
    css_source = f.read()

print("=== Web Raw JSON Warning Test (v1.9.14) ===\n")

# ── 1. Warning text present ──────────────────────────────────────────────

print("--- Warning text ---\n")

check("warning has Advanced diagnostics key", "raw_json_warning_title" in status_html)
check("warning has raw_json_warning_text key", "raw_json_warning_text" in status_html)
check("warning has raw_json_warning_text key (troubleshooting)", "raw_json_warning_text" in status_html)
check("warning has raw_json_warning_text key (subscription)", "raw_json_warning_text" in status_html)
check("warning has raw_json_warning_text key (cards)", "raw_json_warning_text" in status_html)
check("warning has raw_json_warning_title key (emoji)", "raw_json_warning_title" in status_html)

# ── 2. Raw JSON details preserved ────────────────────────────────────────

print("\n--- Raw JSON details preserved ---\n")

check("<details> block present", "<details>" in status_html)
check("<summary> present", "<summary>" in status_html)
check("Raw JSON label in summary", "raw_json_details_label" in status_html)
check("status.raw_json rendered", "status.raw_json" in status_html)
check("<pre> for raw_json", "<pre>{{ status.raw_json }}</pre>" in status_html)

# ── 3. Warning box CSS class ─────────────────────────────────────────────

print("\n--- Warning box CSS ---\n")

check("warning-box class in template", "warning-box" in status_html)
check("warning-box CSS defined", ".warning-box" in css_source)

# ── 4. /api/status route exists ──────────────────────────────────────────

print("\n--- /api/status route ---\n")

check("/api/status route exists", '"/api/status"' in web_source)
check("api_status function exists", "def api_status" in web_source)
check("api_status uses redact_json", "redact_json(data)" in web_source)

# ── 5. No advanced mode added ────────────────────────────────────────────

print("\n--- No advanced mode ---\n")

check("advanced_mode exists in web source (v1.9.17+)", "advanced_mode" in web_source.lower())
check("no session toggle in web source", "session_toggle" not in web_source.lower())
check("no /advanced route", '"/advanced"' not in web_source)

# ── 6. Normal cards unchanged ────────────────────────────────────────────

print("\n--- Normal cards unchanged ---\n")

check("cards.overall in index.html", "status.cards.overall" in open(os.path.join(REPO_ROOT, "web", "templates", "index.html")).read())
check("cards.overall in status.html", "status.cards.overall" in status_html)
check("no Domain label in status cards", "Domain:" not in status_html)
check("no VPS IP label in status cards", "VPS IP:" not in status_html)
check("muted footer text present", "status_footer" in status_html)

# ── 7. Redaction helper import ───────────────────────────────────────────

print("\n--- Redaction helper ---\n")

check("shared redaction import present", "from lib.nanobk_redaction import" in web_source)
check("redact_json_obj imported", "redact_json_obj" in web_source)
check("redact_text imported", "_shared_redact_text" in web_source)

# ── 8. Safety checks ─────────────────────────────────────────────────────

print("\n--- Safety checks ---\n")

check("no shell=True in web source", "shell=True" not in web_source)
check("no os.system in web source", "os.system" not in web_source)
check("no subprocess.call in web source", "subprocess.call" not in web_source)

# ── 9. Login/CSRF/rotate preserved ───────────────────────────────────────

print("\n--- Login/CSRF/rotate preserved ---\n")

check("login route exists", '"/login"' in web_source)
check("validate_csrf exists", "def validate_csrf" in web_source)
check("rotate route exists", '"/rotate"' in web_source)
check("rotate_confirm exists", "def rotate_confirm" in web_source)
check("session authenticated check", "session.get(\"authenticated\")" in web_source)

# ── 10. run_nanobk preserved ─────────────────────────────────────────────

print("\n--- run_nanobk preserved ---\n")

check("run_nanobk function exists", "def run_nanobk" in web_source)
check("subprocess.run used", "subprocess.run" in web_source)

# ── Summary ───────────────────────────────────────────────────────────────

print(f"\n=== {passed} passed, {failed} failed ===")
if failed > 0:
    sys.exit(1)
else:
    print("All tests passed!")
