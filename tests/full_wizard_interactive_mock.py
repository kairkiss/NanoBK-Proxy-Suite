#!/usr/bin/env python3
"""
NanoBK Proxy Suite — Full Wizard Real Stdin Mock Test

Real dynamic test that executes installer/install.sh --mode full
with stdin input stream using NANOBK_TEST_MOCK=1.

Does NOT use --defaults.
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


def run_installer_stdin(inputs, env_vars=None, resume=False):
    """Run installer with given stdin inputs and return output."""
    env = os.environ.copy()
    env["NANOBK_TEST_MOCK"] = "1"
    tmpdir = tempfile.mkdtemp(prefix="nanobk-mock-")
    env["NANOBK_TEST_TMPDIR"] = tmpdir
    if env_vars:
        env.update(env_vars)

    input_str = "\n".join(inputs) + "\n"

    cmd = ["bash", INSTALLER, "--mode", "full", "--lang", "zh"]
    if resume:
        cmd.insert(3, "--resume")

    try:
        result = subprocess.run(
            cmd,
            input=input_str,
            capture_output=True,
            text=True,
            timeout=180,
            env=env,
        )
        output = result.stdout + result.stderr
        return output, result.returncode
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


# Clean any leftover state file
state_file = os.path.join(REPO_DIR, ".nanobk-wizard-state.json")
if os.path.exists(state_file):
    os.remove(state_file)

print("=== Full Wizard Real Stdin Mock Test ===")
print("")

# ── Test A: Invalid input + VPS review edit + Summary ───────────────────────
print("── Test A: Invalid input + VPS review edit + Summary ──")

inputs_a = [
    "t",  # invalid input
    "1",  # valid: configure VPS
    "alpha.example-user.test",  # domain
    "1",  # cert: self-signed
    "",   # reality: default
    "2",  # VPS review: modify domain
    "beta.example-user.test",  # new domain
    "1",  # VPS review: confirm
    "1",  # VPS deploy: execute
    # Skip Cloudflare (profile missing)
    # Skip Bot
    "2",
    # Skip Web
    "2",
]

output_a, rc_a = run_installer_stdin(inputs_a)

check("exit code not 124 (timeout)", rc_a != 124)
check("output contains 无效输入", "无效输入" in output_a)
check("output contains alpha.example-user.test", "alpha.example-user.test" in output_a)
check("output contains beta.example-user.test", "beta.example-user.test" in output_a)
check("VPS review shown at least twice", output_a.count("VPS 配置确认") >= 2)
check("output contains MOCK VPS deploy", "MOCK" in output_a and "VPS" in output_a)
check("output reaches Summary", "NanoBK Setup Summary" in output_a)
check("Summary contains VPS:", "VPS:" in output_a)
check("Summary contains Cloudflare:", "Cloudflare:" in output_a)
check("no dangerous control chars", check_output_clean(output_a))

# ── Test B: Bot token redaction ─────────────────────────────────────────────
print("")
print("── Test B: Bot token redaction ──")

# Clean state file from previous test
if os.path.exists(state_file):
    os.remove(state_file)

inputs_b = [
    "2",  # Skip VPS
    # Skip Cloudflare
    "2",
    # Bot: yes
    "",
    "123456:SECRET_TEST_BOT_TOKEN",
    "123456789",
    "1",  # Bot review: confirm
    "",   # dry-run default
    "2",  # self-test: no
    "2",  # launch: no
    "2",  # Skip Web
]

output_b, rc_b = run_installer_stdin(inputs_b)

check("exit code not 124 (timeout)", rc_b != 124)
check("output contains Telegram Bot 配置确认", "Telegram Bot 配置确认" in output_b)
check("output shows Bot Token 已填写", "已填写" in output_b)
check("output does NOT contain raw token", "SECRET_TEST_BOT_TOKEN" not in output_b)
check("output reaches Summary", "NanoBK Setup Summary" in output_b)

# ── Test C: Web port modification ───────────────────────────────────────────
print("")
print("── Test C: Web port modification ──")

# Clean state file from previous test
if os.path.exists(state_file):
    os.remove(state_file)

inputs_c = [
    "2",  # Skip VPS
    "2",  # Skip Cloudflare
    "2",  # Skip Bot
    "",   # Web: yes
    "3",  # Web review: modify port
    "9090",
    "1",  # Web review: confirm
    "",   # dry-run default
    "2",  # self-test: no
]

output_c, rc_c = run_installer_stdin(inputs_c)

check("exit code not 124 (timeout)", rc_c != 124)
check("output contains Web Panel 配置确认", "Web Panel 配置确认" in output_c)
check("output reaches Summary", "NanoBK Setup Summary" in output_c)

# ── Test D: Worker URL recommendation (static) ─────────────────────────────
print("")
print("── Test D: Worker URL recommendation (static) ──")

installer_src = open(INSTALLER).read()
check("has Workers 子域 prompt", "Workers 子域" in installer_src)
check("has recommended URL display", "推荐地址" in installer_src)
check("has nanok URL template", "nanok" in installer_src)
check("has nanob URL template", "nanob" in installer_src)
check("has SUB_STORE reuse", "复用现有 SUB_STORE" in installer_src)
check("has NANOB_GEO_CACHE reuse", "复用现有 NANOB_GEO_CACHE" in installer_src)
check("has mock-sub-store-id", "mock-sub-store-id" in installer_src)
check("has mock-geo-cache-id", "mock-geo-cache-id" in installer_src)

# ── Test E: No dangerous control chars ───────────────────────────────────────
print("")
print("── Test E: No dangerous control chars ──")

check("no dangerous control chars in output B", check_output_clean(output_b))
check("no dangerous control chars in output C", check_output_clean(output_c))

# ── Summary ─────────────────────────────────────────────────────────────────
print("")
print(f"=== {PASS} passed, {FAIL} failed ===")

if FAIL > 0:
    log_file = os.path.join(tempfile.gettempdir(), "nanobk-v1712-stdin-mock.log")
    with open(log_file, "w") as f:
        f.write("=== Test A output ===\n" + output_a + "\n\n")
        f.write("=== Test B output ===\n" + output_b + "\n\n")
        f.write("=== Test C output ===\n" + output_c + "\n\n")
    print(f"\n── Debug: full output saved to {log_file} ──")
    lines = output_a.split("\n")
    print(f"── Last 80 lines of Test A ──")
    for line in lines[-80:]:
        print(f"  | {line}")
    sys.exit(1)

sys.exit(0)
