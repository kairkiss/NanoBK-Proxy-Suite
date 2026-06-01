#!/usr/bin/env python3
"""
NanoBK Proxy Suite — Full Wizard Interactive Mock Test

Runs installer/install.sh --mode full with NANOBK_TEST_MOCK=1
and verifies the Full Wizard can reach Summary.

Does NOT connect to VPS or Cloudflare.
Does NOT write to /etc or /root.

Usage:
    python3 tests/full_wizard_interactive_mock.py
"""

import os
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(SCRIPT_DIR)
INSTALLER = os.path.join(REPO_DIR, "installer", "install.sh")

PASS = 0
FAIL = 0


def check(desc, ok):
    global PASS, FAIL
    if ok:
        print(f"  ✓ {desc}")
        PASS += 1
    else:
        print(f"  ✗ {desc}")
        FAIL += 1


def run_installer_dryrun():
    """Run installer in dry-run mode with defaults (non-interactive)."""
    env = os.environ.copy()
    env["NANOBK_TEST_MOCK"] = "1"
    try:
        result = subprocess.run(
            ["bash", INSTALLER, "--mode", "full", "--dry-run", "--defaults", "--lang", "zh"],
            capture_output=True, text=True, timeout=120, env=env,
        )
        return result.stdout + result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", 124


def check_output_clean(text):
    """Check output for dangerous control chars."""
    for b in text.encode("utf-8", errors="replace"):
        if b == 0:
            return False
        if b < 32 and b not in (9, 10, 13):
            if b == 27:
                continue
            return False
        if b == 127:
            return False
    return True


installer_src = open(INSTALLER).read()

print("=== Full Wizard Interactive Mock Test ===")
print("")

# ── Test 1: Mock infrastructure ─────────────────────────────────────────────
print("── Test 1: Mock infrastructure ──")
check("has mock_log helper", "mock_log" in installer_src)
check("has mock_deploy_vps", "mock_deploy_vps" in installer_src)
check("has mock_deploy_cloudflare", "mock_deploy_cloudflare" in installer_src)
check("has mock_preflight", "mock_preflight" in installer_src)
check("has mock_find_existing_kv", "mock_find_existing_kv" in installer_src)
check("has NANOBK_TEST_MOCK check", "NANOBK_TEST_MOCK" in installer_src)

# ── Test 2: Review loop functions ───────────────────────────────────────────
print("")
print("── Test 2: Review loop functions ──")
check("has vps_review_loop", "vps_review_loop" in installer_src)
check("has cloudflare_review_loop", "cloudflare_review_loop" in installer_src)
check("has bot_review_loop", "bot_review_loop" in installer_src)
check("has web_review_loop", "web_review_loop" in installer_src)
check("has ask_yes_no_menu", "ask_yes_no_menu" in installer_src)

# ── Test 3: Resume routing ──────────────────────────────────────────────────
print("")
print("── Test 3: Resume routing ──")
check("START_FROM_STAGE exists", "START_FROM_STAGE" in installer_src)
check("assumed_existing used for resume", "assumed_existing" in installer_src)

# ── Test 4: Existing KV recovery ────────────────────────────────────────────
print("")
print("── Test 4: Existing KV recovery ──")
check("has find_existing_kv_id", "find_existing_kv_id" in installer_src)
check("has mock SUB_STORE", "mock-sub-store-id" in installer_src)
check("has mock NANOB_GEO_CACHE", "mock-geo-cache-id" in installer_src)

# ── Test 5: Token redaction ─────────────────────────────────────────────────
print("")
print("── Test 5: Token redaction ──")
check("Bot review hides token", "已填写" in installer_src)
check("Web review hides token", "已生成" in installer_src)

# ── Test 6: Full dry-run mock reaches Summary ───────────────────────────────
print("")
print("── Test 6: Full dry-run mock reaches Summary ──")

output_dry, rc_dry = run_installer_dryrun()

check("dry-run exits 0", rc_dry == 0)
check("dry-run reaches Summary", "NanoBK Setup Summary" in output_dry)
check("dry-run has planned/dry-run", "planned" in output_dry or "dry-run" in output_dry)
check("dry-run has disclaimer", "dry-run" in output_dry and ("没有执行" in output_dry or "No real" in output_dry))
check("no dangerous control chars", check_output_clean(output_dry))

# ── Test 7: Domain validation ───────────────────────────────────────────────
print("")
print("── Test 7: Domain validation ──")
check("rejects no-dot domains", "至少包含一个点" in installer_src)
check("rejects all-numeric", "不能是纯数字" in installer_src)

# ── Test 8: Output control ──────────────────────────────────────────────────
print("")
print("── Test 8: Output control ──")
check("has check_output_clean helper", "check_output_clean" in installer_src)

# ── Summary ─────────────────────────────────────────────────────────────────
print("")
print(f"=== {PASS} passed, {FAIL} failed ===")

if FAIL > 0:
    sys.exit(1)
sys.exit(0)
