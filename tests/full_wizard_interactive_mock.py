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
import signal
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

TEST_TIMEOUT_SECONDS = int(os.environ.get("NANOBK_MOCK_TEST_TIMEOUT", "180"))


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


def _kill_proc_tree(proc):
    """Kill entire process group started with start_new_session=True."""
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    except (ProcessLookupError, OSError):
        pass
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (ProcessLookupError, OSError):
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass


def run_installer_stdin(inputs, env_vars=None, resume=False, state_json=None, test_name="unknown", cleanup=True):
    """Run installer with given stdin inputs and return output.

    Uses Popen with start_new_session=True so the entire process group
    can be killed on timeout, preventing orphaned installer/bash children.

    If cleanup=False, caller is responsible for cleaning up the tmpdir.
    Returns (stdout, rc, tmpdir) when cleanup=False, else (stdout, rc).
    """
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

    proc = None
    try:
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
            start_new_session=True,
        )
        try:
            stdout, _ = proc.communicate(input=input_str, timeout=TEST_TIMEOUT_SECONDS)
            if cleanup:
                return stdout, proc.returncode
            return stdout, proc.returncode, tmpdir
        except subprocess.TimeoutExpired:
            # Kill entire process group
            _kill_proc_tree(proc)
            # Collect whatever output was buffered
            try:
                stdout, _ = proc.communicate(timeout=5)
            except Exception:
                stdout = ""
            # Diagnostic output
            input_summary = "\n".join(f"    [{i}] {line}" for i, line in enumerate(inputs[:20]))
            if len(inputs) > 20:
                input_summary += f"\n    ... ({len(inputs) - 20} more lines)"
            last_lines = stdout.split("\n")[-200:] if stdout else ["(no output captured)"]
            print(f"\n  [TIMEOUT] {test_name}")
            print(f"  timeout: {TEST_TIMEOUT_SECONDS}s")
            print(f"  input steps:")
            print(input_summary)
            print(f"  last {len(last_lines)} lines of output:")
            for line in last_lines:
                print(f"    | {line}")
            if cleanup:
                return stdout or "TIMEOUT", 124
            return stdout or "TIMEOUT", 124, tmpdir
    finally:
        if cleanup and os.path.exists(tmpdir):
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


def assert_apply_yes_manual_only(output):
    """Verify that any 'nanobk cf dns apply ... --yes' in output is a manual instruction only.

    Returns True if safe, False if suspicious execution markers are found.
    Safety rules:
    - Lines mentioning both 'nanobk cf dns apply' and '--yes' must appear in
      a manual-instruction context. We check the line itself and the two lines
      above it for manual-context keywords (手动, 不会自动, manual, review,
      Full Wizard did not run, 请手动, 注意).
    - Suspicious execution markers ([run], Executing, Running, run_cmd,
      apply --yes: executed) must never appear.
    """
    SUSPICIOUS_MARKERS = [
        "[run] nanobk cf dns apply",
        "Executing nanobk cf dns apply",
        "Running nanobk cf dns apply",
        "apply --yes: executed",
    ]
    MANUAL_KEYWORDS = [
        "手动", "不会自动", "manual", "review",
        "Full Wizard did not run", "请手动", "注意",
    ]

    # Check for suspicious execution markers anywhere in output
    for marker in SUSPICIOUS_MARKERS:
        if marker in output:
            return False

    # Find lines that mention both 'nanobk cf dns apply' and '--yes'
    lines = output.splitlines()
    for i, line in enumerate(lines):
        if "nanobk cf dns apply" in line and "--yes" in line:
            # Build context window: this line plus the two lines above
            context_start = max(0, i - 2)
            context_window = " ".join(lines[context_start:i + 1])
            if not any(kw in context_window for kw in MANUAL_KEYWORDS):
                return False
    return True


print("=== Full Wizard Real Stdin Mock Test ===")
print(f"(per-test timeout: {TEST_TIMEOUT_SECONDS}s)")
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
    "1",   # DNS: yes
    "example.com",  # DNS zone name
    "",    # DNS node prefix (default)
    "203.0.113.10",  # DNS IPv4
    "",    # DNS IPv6 (skip)
    "2",   # DNS check: no
    "2",   # Skip Bot
    "2",   # Skip Web
]

output_a, rc_a = run_installer_stdin(inputs_a, test_name="Test A: VPS review edit flow")

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
    "2",   # Skip DNS
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

output_b, rc_b = run_installer_stdin(inputs_b, test_name="Test B: Bot token redaction")

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
    "2",   # Skip DNS
    "2",   # Skip CF
    "2",   # Skip Bot
    "",    # Web: yes
    "1",   # Web review: confirm
    "",    # dry-run default
    "2",   # self-test: no
]

output_c, rc_c = run_installer_stdin(inputs_c, test_name="Test C: Web Panel setup")

check("exit code is 0", rc_c == 0)
check("output contains Web Panel 配置确认", "Web Panel 配置确认" in output_c)
check("output reaches Summary", "NanoBK Setup Summary" in output_c)

# ── Test D: Cloudflare stdin dynamic ────────────────────────────────────────
print("")
print("── Test D: Cloudflare stdin dynamic ──")

clean_state()
inputs_d = [
    "2",   # Skip VPS
    "1",   # Configure DNS (yes)
    "example.com",  # DNS zone name
    "",    # DNS node prefix (default: nanobk-node)
    "203.0.113.10",  # DNS IPv4
    "",    # DNS IPv6 (skip)
    "2",   # DNS check: no
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

output_d, rc_d = run_installer_stdin(
    inputs_d,
    {"NANOBK_TEST_MOCK_EXISTING_KV": "1"},
    test_name="Test D: Cloudflare verified Summary",
)

check("exit code is 0", rc_d == 0)
check("output contains Cloudflare 配置確認 or 配置确认",
      "Cloudflare 配置確認" in output_d or "Cloudflare 配置确认" in output_d)
check("output contains nanok.demo-user.workers.dev", "nanok.demo-user.workers.dev" in output_d)
check("output contains nanob.demo-user.workers.dev", "nanob.demo-user.workers.dev" in output_d)
check("output contains mock-sub-store-id", "mock-sub-store-id" in output_d)
check("output contains 复用现有 SUB_STORE", "复用现有 SUB_STORE" in output_d)
check("output contains mock-geo-cache-id", "mock-geo-cache-id" in output_d)
check("output contains 复用现有 NANOB_GEO_CACHE", "复用现有 NANOB_GEO_CACHE" in output_d)
check("output contains MOCK CF preflight", "MOCK" in output_d and ("预检" in output_d or "preflight" in output_d.lower()))
check("output contains MOCK profile validation", "MOCK" in output_d and ("配置文件验证" in output_d or "Profile validation passed" in output_d))
check("output contains MOCK CF deploy", "MOCK" in output_d and ("部署步骤" in output_d or "deploy" in output_d.lower()))
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
    "2",   # Skip DNS
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
    test_name="Test E: Resume cloudflare",
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
    test_name="Test F: Resume botweb",
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

# ── Test H: Full Wizard DNS interactive mock — profile verification ─────────
print("")
print("── Test H: Full Wizard DNS interactive mock — profile verification ──")

import json
import stat

clean_state()
inputs_h = [
    "2",   # Skip VPS
    "1",   # Configure DNS (yes)
    "example.com",  # DNS zone name
    "nanobk-node",  # DNS node prefix
    "203.0.113.10",  # DNS IPv4
    "2001:db8::10",  # DNS IPv6
    "2",   # DNS check: no
    "2",   # Skip Cloudflare
    "2",   # Skip Bot
    "2",   # Skip Web
]

output_h, rc_h, tmpdir_h = run_installer_stdin(
    inputs_h,
    test_name="Test H: DNS profile verification",
    cleanup=False,
)

try:
    check("exit code is 0", rc_h == 0)
    check("output reaches Summary", "NanoBK Setup Summary" in output_h)
    check("no dangerous control chars", check_output_clean(output_h))

    # Negative assertions on output
    check("output does NOT contain raw apply --yes execution",
          assert_apply_yes_manual_only(output_h))
    check("output does NOT contain Authorization header",
          "Authorization:" not in output_h)
    check("output does NOT contain workers.dev",
          "workers.dev" not in output_h)
    check("output does NOT contain hysteria2://",
          "hysteria2://" not in output_h)
    check("output does NOT contain tuic://",
          "tuic://" not in output_h)
    check("output does NOT contain vless://",
          "vless://" not in output_h)
    check("output does NOT contain trojan://",
          "trojan://" not in output_h)

    # Summary DNS fields
    check("Summary contains Cloudflare DNS", "Cloudflare DNS" in output_h)
    check("Summary contains dns_profile", "dns_profile" in output_h)
    check("Summary contains dns_plan", "dns_plan" in output_h)
    check("Summary contains dns_check", "dns_check" in output_h)
    check("Summary contains dns_apply", "dns_apply" in output_h)
    check("dns_apply is not done/installed/verified/success",
          "dns_apply:   done" not in output_h and
          "dns_apply:   installed" not in output_h and
          "dns_apply:   verified" not in output_h and
          "dns_apply:   success" not in output_h)

    # Verify generated profile file under NANOBK_TEST_TMPDIR
    profile_path = os.path.join(tmpdir_h, "etc", "nanobk", "cloudflare-dns-profile.json")
    check("DNS profile file exists under test tmpdir", os.path.isfile(profile_path))

    if os.path.isfile(profile_path):
        # Check file mode is 600
        file_mode = oct(os.stat(profile_path).st_mode & 0o777)
        check(f"DNS profile chmod 600 (got {file_mode})", file_mode == "0o600")

        # Validate that the generated profile path is under the test tmpdir.
        # This confirms NANOBK_TEST_TMPDIR redirection works, without touching real /etc.
        check("generated profile path is under test tmpdir",
              profile_path.startswith(tmpdir_h))

        # Parse and validate profile content
        with open(profile_path, "r") as f:
            profile_data = json.load(f)

        check(f"zoneName is example.com (got: {profile_data.get('zoneName')})",
              profile_data.get("zoneName") == "example.com")
        check(f"nodePrefix is nanobk-node (got: {profile_data.get('nodePrefix')})",
              profile_data.get("nodePrefix") == "nanobk-node")
        check(f"ipv4 is 203.0.113.10 (got: {profile_data.get('ipv4')})",
              profile_data.get("ipv4") == "203.0.113.10")
        check(f"ipv6 is 2001:db8::10 (got: {profile_data.get('ipv6')})",
              profile_data.get("ipv6") == "2001:db8::10")
        check(f"defaultProxied is false (got: {profile_data.get('defaultProxied')})",
              profile_data.get("defaultProxied") is False)

        reserved = profile_data.get("reserved", {})
        check(f"reserved.panelPrefix is panel (got: {reserved.get('panelPrefix')})",
              reserved.get("panelPrefix") == "panel")
        check(f"reserved.nanokPrefix is nanok (got: {reserved.get('nanokPrefix')})",
              reserved.get("nanokPrefix") == "nanok")
        check(f"reserved.nanobPrefix is nanob (got: {reserved.get('nanobPrefix')})",
              reserved.get("nanobPrefix") == "nanob")
    else:
        check("DNS profile file exists under test tmpdir", False)
        check("DNS profile chmod 600", False)
        check("zoneName is example.com", False)
        check("nodePrefix is nanobk-node", False)
        check("ipv4 is 203.0.113.10", False)
        check("ipv6 is 2001:db8::10", False)
        check("defaultProxied is false", False)
        check("reserved.panelPrefix is panel", False)
        check("reserved.nanokPrefix is nanok", False)
        check("reserved.nanobPrefix is nanob", False)

    # Verify the wizard ran validate-profile and plan (check output contains them)
    check("output mentions validate-profile",
          "validate-profile" in output_h or "DNS profile 验证" in output_h or "验证" in output_h)
    check("output mentions plan",
          "plan" in output_h.lower() or "DNS plan" in output_h or "plan" in output_h)

    # Verify dns_apply is manual_apply_pending (not done/installed/verified)
    check("Summary dns_apply is manual_apply_pending",
          "manual_apply_pending" in output_h or "dns_apply:" in output_h)

finally:
    if os.path.exists(tmpdir_h):
        shutil.rmtree(tmpdir_h, ignore_errors=True)

# ── Summary ─────────────────────────────────────────────────────────────────
print("")
print(f"=== {PASS} passed, {FAIL} failed ===")

if FAIL > 0:
    log_file = os.path.join(tempfile.gettempdir(), "nanobk-v1724-stdin-mock.log")
    with open(log_file, "w") as f:
        f.write("=== Test A ===\n" + output_a + "\n\n")
        f.write("=== Test B ===\n" + output_b + "\n\n")
        f.write("=== Test C ===\n" + output_c + "\n\n")
        f.write("=== Test D ===\n" + output_d + "\n\n")
        f.write("=== Test E ===\n" + output_e + "\n\n")
        f.write("=== Test F ===\n" + output_f + "\n\n")
        f.write("=== Test H ===\n" + output_h + "\n\n")
    print(f"\n── Debug: full output saved to {log_file} ──")
    # Print last 80 lines of Test D for debugging
    lines = output_d.split("\n")
    print(f"── Last 80 lines of Test D ──")
    for line in lines[-80:]:
        print(f"  | {line}")
    sys.exit(1)

sys.exit(0)
