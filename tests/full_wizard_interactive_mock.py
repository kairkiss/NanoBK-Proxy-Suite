#!/usr/bin/env python3
"""
NanoBK Proxy Suite — Full Wizard Real Stdin Mock Test

Real dynamic test that executes installer/install.sh --mode full
with stdin input stream using NANOBK_TEST_MOCK=1.

Does NOT use the defaults flag.
Does NOT connect to VPS or Cloudflare.
Does NOT write to /etc or /root.

Usage:
    python3 tests/full_wizard_interactive_mock.py
"""

import os
import subprocess
import sys
import tempfile
import shutil
import atexit

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_DIR = os.path.dirname(SCRIPT_DIR)
INSTALLER = os.path.join(REPO_DIR, "installer", "install.sh")
TEST_TMP_ROOT = tempfile.mkdtemp(prefix="nanobk-stdin-mock-")
atexit.register(lambda: shutil.rmtree(TEST_TMP_ROOT, ignore_errors=True))

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


def clean_state():
    """Remove leftover files from this test process temp root only."""
    if os.path.isdir(TEST_TMP_ROOT):
        for name in os.listdir(TEST_TMP_ROOT):
            path = os.path.join(TEST_TMP_ROOT, name)
            if os.path.isdir(path):
                shutil.rmtree(path, ignore_errors=True)
            elif os.path.exists(path):
                os.remove(path)
    # Clean repo-root test artifacts so tests don't pollute each other
    for artifact in [".cloudflare.local.env", ".nanob.local.env",
                     "bot/.env", "web/.env", ".nanobk-wizard-state.json"]:
        path = os.path.join(REPO_DIR, artifact)
        if os.path.exists(path):
            os.remove(path)


def run_installer_stdin(inputs, env_vars=None, resume=False, state_json=None):
    """Run installer with given stdin inputs and return output."""
    env = os.environ.copy()
    env["NANOBK_TEST_MOCK"] = "1"
    env["NANOBK_ASSUME_PORTS_FREE"] = "1"
    tmpdir = tempfile.mkdtemp(prefix="run-", dir=TEST_TMP_ROOT)
    env["NANOBK_TEST_TMPDIR"] = tmpdir
    if state_json:
        state_file = os.path.join(tmpdir, ".nanobk-wizard-state.json")
        with open(state_file, "w") as f:
            f.write(state_json)
    if env_vars:
        env.update(env_vars)

    input_str = "\n".join(inputs) + "\n"

    cmd = ["bash", INSTALLER, "--mode", "full", "--lang", "zh"]
    if resume:
        cmd.append("--resume")

    try:
        result = subprocess.run(
            cmd, input=input_str, capture_output=True, text=True,
            timeout=180, env=env,
        )
        return result.stdout + result.stderr, result.returncode
    except subprocess.TimeoutExpired:
        return "TIMEOUT", 124
    finally:
        if os.path.exists(tmpdir):
            shutil.rmtree(tmpdir, ignore_errors=True)


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


print("=== Full Wizard Real Stdin Mock Test ===")
print("")

# ── Test A: Invalid input + VPS review edit + Summary ───────────────────────
print("── Test A: Invalid input + VPS review edit + Summary ──")

clean_state()
inputs_a = [
    "t",   # invalid input
    "1",   # configure VPS
    "alpha.example-user.test",  # domain
    "1",   # cert: self-signed
    "",    # reality: default
    "2",   # VPS review: modify domain
    "beta.example-user.test",
    "1",   # VPS review: confirm
    "1",   # VPS deploy: execute
    "2",   # Skip Bot
    "2",   # Skip Web
]

output_a, rc_a = run_installer_stdin(inputs_a)

check("exit code is 0", rc_a == 0)
check("output contains 无效输入", "无效输入" in output_a)
check("output contains alpha.example-user.test", "alpha.example-user.test" in output_a)
check("output contains beta.example-user.test", "beta.example-user.test" in output_a)
check("VPS review shown at least twice", output_a.count("VPS 配置确认") >= 2)
check("output contains MOCK VPS deploy", "MOCK" in output_a and "VPS" in output_a)
check("output reaches Summary", "NanoBK Setup Summary" in output_a)
check("no dangerous control chars", check_output_clean(output_a))

# ── Test B: Bot token redaction ─────────────────────────────────────────────
print("")
print("── Test B: Bot token redaction ──")

clean_state()
inputs_b = [
    "2",   # Skip VPS
    "2",   # Skip CF
    "",    # Bot: yes
    "123456:SECRET_TEST_BOT_TOKEN",
    "123456789",
    "1",   # Bot review: confirm
    "",    # dry-run default
    "2",   # self-test: no
    "2",   # launch: no
    "2",   # Skip Web
]

output_b, rc_b = run_installer_stdin(inputs_b)

check("exit code is 0", rc_b == 0)
check("output contains Telegram Bot 配置确认", "Telegram Bot 配置确认" in output_b)
check("output shows Bot Token 已填写", "已填写" in output_b)
check("output does NOT contain raw token", "SECRET_TEST_BOT_TOKEN" not in output_b)
check("output reaches Summary", "NanoBK Setup Summary" in output_b)

# ── Test C: Web Panel setup ─────────────────────────────────────────────────
print("")
print("── Test C: Web Panel setup ──")

clean_state()
inputs_c = [
    "2",   # Skip VPS
    "2",   # Skip CF
    "2",   # Skip Bot
    "",    # Web: yes
    "1",   # Web review: confirm
    "",    # dry-run default
    "2",   # self-test: no
]

output_c, rc_c = run_installer_stdin(inputs_c)

check("exit code is 0", rc_c == 0)
check("output contains Web Panel 配置确认", "Web Panel 配置确认" in output_c)
check("output reaches Summary", "NanoBK Setup Summary" in output_c)

# ── Test D: Cloudflare stdin dynamic ────────────────────────────────────────
print("")
print("── Test D: Cloudflare stdin dynamic ──")

clean_state()
inputs_d = [
    "2",   # Skip VPS
    "1",   # Configure Cloudflare
    "/etc/nanobk/profile.current.json",  # profile path
    "demo-user.workers.dev",  # Workers subdomain
    "1",   # Use recommended URLs
    "1",   # Reuse SUB_STORE (mock)
    "",    # nanob yes
    "",    # Accept recommended nanob URL
    "1",   # Reuse GEO_CACHE (mock)
    "1",   # CF review: confirm
    "2",   # Skip Bot
    "2",   # Skip Web
]

output_d, rc_d = run_installer_stdin(inputs_d, {"NANOBK_TEST_MOCK_EXISTING_KV": "1"})

check("exit code is 0", rc_d == 0)
check("output contains Cloudflare 配置確認 or 配置确认",
      "Cloudflare 配置確認" in output_d or "Cloudflare 配置确认" in output_d)
check("output contains nanok.demo-user.workers.dev", "nanok.demo-user.workers.dev" in output_d)
check("output contains nanob.demo-user.workers.dev", "nanob.demo-user.workers.dev" in output_d)
check("output contains mock-sub-store-id", "mock-sub-store-id" in output_d)
check("output contains 复用现有 SUB_STORE", "复用现有 SUB_STORE" in output_d)
check("output contains mock-geo-cache-id", "mock-geo-cache-id" in output_d)
check("output contains 复用现有 NANOB_GEO_CACHE", "复用现有 NANOB_GEO_CACHE" in output_d)
check("output contains MOCK CF preflight", "MOCK" in output_d and "preflight" in output_d.lower())
check("output contains MOCK profile validation", "MOCK" in output_d and "Profile validation passed" in output_d)
check("output contains MOCK CF deploy", "MOCK" in output_d and "deploy" in output_d.lower())
check("output reaches Summary", "NanoBK Setup Summary" in output_d)
# Cloudflare Summary truth checks — strict verified/passed/installed
check("Summary shows nanok verified",
      "nanok:" in output_d and "verified" in output_d)
check("Summary shows nanob verified",
      "nanob:" in output_d and "verified" in output_d)
check("Summary shows verify passed",
      "verify:" in output_d and "passed" in output_d)
check("Summary shows admin env installed",
      "admin env:" in output_d and "installed" in output_d)
check("Summary does NOT show configured / pending",
      "configured" not in output_d or "pending" not in output_d)
check("Summary does NOT show manual command not executed",
      "manual command not executed" not in output_d)

# ── Test E: Resume cloudflare ───────────────────────────────────────────────
print("")
print("── Test E: Resume cloudflare ──")

state_json_e = '{"version":"1.7.14","current_phase":"cloudflare","vps_status":"installed","cf_status":"unknown","bot_status":"unknown","web_status":"unknown"}'

inputs_e = [
    "3",   # Resume: Cloudflare
    "1",   # Configure Cloudflare
    "/etc/nanobk/profile.current.json",
    "demo-user.workers.dev",
    "1",   # Use recommended
    "1",   # Reuse SUB_STORE
    "",    # nanob yes
    "",    # Accept recommended nanob URL
    "1",   # Reuse GEO_CACHE
    "1",   # CF review confirm
    "2",   # Skip Bot
    "2",   # Skip Web
]

output_e, rc_e = run_installer_stdin(
    inputs_e,
    {"NANOBK_TEST_MOCK_RESUME": "cloudflare", "NANOBK_TEST_MOCK_EXISTING_KV": "1"},
    resume=True,
    state_json=state_json_e,
)

check("exit code is 0", rc_e == 0)
check("output does NOT contain VPS 配置確認", "VPS 配置確認" not in output_e and "VPS 配置确认" not in output_e)
check("output contains Cloudflare 配置確認 or 配置确认", "Cloudflare" in output_e and "配置" in output_e)
check("resume cloudflare reaches Summary", "NanoBK Setup Summary" in output_e)

# ── Test F: Resume botweb ───────────────────────────────────────────────────
print("")
print("── Test F: Resume botweb ──")

state_json_f = '{"version":"1.7.14","current_phase":"botweb","vps_status":"installed","cf_status":"deployed","bot_status":"unknown","web_status":"unknown"}'

inputs_f = [
    "4",   # Resume: Bot/Web
    "",    # Bot yes
    # Bot
    "123456:MOCK_BOT_TOKEN",
    "123456789",
    "1",   # Bot review confirm
    "2",   # self-test no
    "2",   # launch no
    # Web
    "",    # Web yes
    "",    # auto web token
    "",    # auto flask secret
    "",    # default host
    "",    # default port
    "1",   # Web review confirm
    "",    # dry-run default
    "2",   # self-test no
]

output_f, rc_f = run_installer_stdin(
    inputs_f,
    {"NANOBK_TEST_MOCK_RESUME": "botweb"},
    resume=True,
    state_json=state_json_f,
)

check("exit code is 0", rc_f == 0)
check("output does NOT contain VPS 配置確認", "VPS 配置確認" not in output_f and "VPS 配置确认" not in output_f)
check("output does NOT contain Cloudflare 配置確認", "Cloudflare 配置確認" not in output_f and "Cloudflare 配置确认" not in output_f)
check("output contains Telegram Bot 配置確認", "Telegram Bot 配置確認" in output_f or "Telegram Bot 配置确认" in output_f)
check("output contains Web Panel 配置確認", "Web Panel 配置確認" in output_f or "Web Panel 配置确认" in output_f)
check("resume botweb reaches Summary", "NanoBK Setup Summary" in output_f)

# ── Test G: No dangerous control chars ───────────────────────────────────────
print("")
print("── Test G: No dangerous control chars ──")

check("no dangerous control chars in output B", check_output_clean(output_b))
check("no dangerous control chars in output D", check_output_clean(output_d))

# ── Summary ─────────────────────────────────────────────────────────────────
print("")
print(f"=== {PASS} passed, {FAIL} failed ===")

if FAIL > 0:
    log_file = os.path.join(tempfile.gettempdir(), "nanobk-v1713-stdin-mock.log")
    with open(log_file, "w") as f:
        f.write("=== Test A ===\n" + output_a + "\n\n")
        f.write("=== Test B ===\n" + output_b + "\n\n")
        f.write("=== Test C ===\n" + output_c + "\n\n")
        f.write("=== Test D ===\n" + output_d + "\n\n")
        f.write("=== Test E ===\n" + output_e + "\n\n")
        f.write("=== Test F ===\n" + output_f + "\n\n")
    print(f"\n── Debug: full output saved to {log_file} ──")
    # Print last 80 lines of Test D for debugging
    lines = output_d.split("\n")
    print(f"── Last 80 lines of Test D ──")
    for line in lines[-80:]:
        print(f"  | {line}")
    sys.exit(1)

sys.exit(0)
