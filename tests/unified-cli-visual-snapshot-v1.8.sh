#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.16 CLI Visual Snapshot Test
#
# Checks UI output shape without real deployment.
# Uses safe mock / dry-run / defaults only.
#
# Usage:
#   bash tests/unified-cli-visual-snapshot-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  echo "  OK $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL $1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF "$needle" <<< "$haystack"; then
    pass "$label"
  else
    fail "$label — expected to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF "$needle" <<< "$haystack"; then
    fail "$label — should NOT contain: $needle"
  else
    pass "$label"
  fi
}

# ANSI escape detection (macOS-compatible, no grep -P)
has_ansi() {
  grep -qE $'\x1b\[' <<< "$1"
}

source_ui_and_run() {
  local env_flags="$1"
  local code="$2"
  env $env_flags bash -c "
    source '${REPO_DIR}/installer/lib/ui.sh'
    ${code}
  " 2>&1
}

echo ""
echo "=== Test Suite: v1.8.16 CLI Visual Snapshot ==="

# ── Snapshot 1: Banner ────────────────────────────────────────────────────

echo ""
echo "--- Snapshot 1: ui_banner PLAIN ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_banner 'v1.8.16' 'Full Recommended — VPS + Cloudflare + Bot + Web Panel'
")

assert_contains "$output" "NanoBK Proxy Suite" "Banner: product name"
assert_contains "$output" "v1.8.16" "Banner: version"
assert_contains "$output" "Full Recommended" "Banner: subtitle"

if has_ansi "$output"; then
  fail "Banner PLAIN: no ANSI escape"
else
  pass "Banner PLAIN: no ANSI escape"
fi
assert_not_contains "$output" "✓" "Banner PLAIN: no emoji checkmark"
assert_not_contains "$output" "✕" "Banner PLAIN: no emoji X"
assert_not_contains "$output" "■" "Banner PLAIN: no Unicode filled bar"

# ── Snapshot 2: Section PLAIN ─────────────────────────────────────────────

echo ""
echo "--- Snapshot 2: ui_section PLAIN ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_section '阶段 1：VPS 部署' 1 5
")

assert_contains "$output" "Step 1/5" "Section PLAIN: Step N/M"
assert_contains "$output" "阶段 1" "Section PLAIN: title"
assert_contains "$output" "VPS" "Section PLAIN: VPS"

if has_ansi "$output"; then
  fail "Section PLAIN: no ANSI escape"
else
  pass "Section PLAIN: no ANSI escape"
fi
assert_not_contains "$output" "■" "Section PLAIN: no Unicode filled bar"
assert_not_contains "$output" "□" "Section PLAIN: no Unicode empty bar"
assert_not_contains "$output" "──" "Section PLAIN: no Unicode dash"

# ── Snapshot 3: Section default non-TTY ───────────────────────────────────

echo ""
echo "--- Snapshot 3: ui_section default non-TTY ---"

output=$(source_ui_and_run "" "
  ui_section '阶段 2：Cloudflare 部署' 2 5
")

assert_contains "$output" "阶段 2" "Section non-TTY: title"
assert_contains "$output" "Cloudflare" "Section non-TTY: Cloudflare"

# Non-TTY should have no ANSI
if has_ansi "$output"; then
  fail "Section non-TTY: no ANSI escape"
else
  pass "Section non-TTY: no ANSI escape"
fi

# ── Snapshot 4: Recovery block ────────────────────────────────────────────

echo ""
echo "--- Snapshot 4: ui_recovery_block ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_recovery_block 'bash installer/install.sh --mode vps --lang zh' 'bash bin/nanobk status'
")

assert_contains "$output" "可以稍后继续" "Recovery: contains continue-later label"
assert_contains "$output" "恢复或重新执行" "Recovery: contains recovery intro"
assert_contains "$output" "installer/install.sh" "Recovery: contains installer command"
assert_contains "$output" "nanobk status" "Recovery: contains nanobk command"

if has_ansi "$output"; then
  fail "Recovery PLAIN: no ANSI escape"
else
  pass "Recovery PLAIN: no ANSI escape"
fi

# Must not leak tokens
assert_not_contains "$output" "SECRET" "Recovery: no SECRET"
assert_not_contains "$output" "TOKEN=" "Recovery: no TOKEN="

# ── Snapshot 5: Token reminder ────────────────────────────────────────────

echo ""
echo "--- Snapshot 5: ui_token_reminder ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_token_reminder
")

assert_contains "$output" "不要截图" "Token: contains do-not-screenshot"
assert_contains "$output" "聊天、issue 或日志" "Token: contains do-not-share"
assert_contains "$output" "当作密码保管" "Token: contains treat-as-password"
assert_contains "$output" "隐藏敏感信息" "Token: contains hide-sensitive-info"
assert_contains "$output" "revoke" "Token: contains revoke"
assert_contains "$output" "regenerate" "Token: contains regenerate"
assert_not_contains "$output" "不会出现在屏幕或日志中" "Token: no absolute promise"

if has_ansi "$output"; then
  fail "Token PLAIN: no ANSI escape"
else
  pass "Token PLAIN: no ANSI escape"
fi

# ── Snapshot 6: Progress PLAIN ────────────────────────────────────────────

echo ""
echo "--- Snapshot 6: ui_progress PLAIN ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_progress 3 6 'Installing'
")

assert_contains "$output" "Step 3/6" "Progress PLAIN: Step N/M"
assert_contains "$output" "Installing" "Progress PLAIN: label"
assert_not_contains "$output" "■" "Progress PLAIN: no Unicode bar"
assert_not_contains "$output" "□" "Progress PLAIN: no Unicode bar"

if has_ansi "$output"; then
  fail "Progress PLAIN: no ANSI escape"
else
  pass "Progress PLAIN: no ANSI escape"
fi

# ── Snapshot 7: Divider PLAIN ─────────────────────────────────────────────

echo ""
echo "--- Snapshot 7: ui_divider PLAIN ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_divider
")

# Should contain ASCII dashes
assert_contains "$output" "-" "Divider PLAIN: ASCII dash"
assert_not_contains "$output" "─" "Divider PLAIN: no Unicode dash"

if has_ansi "$output"; then
  fail "Divider PLAIN: no ANSI escape"
else
  pass "Divider PLAIN: no ANSI escape"
fi

# ── Snapshot 8: Summary card PLAIN ────────────────────────────────────────

echo ""
echo "--- Snapshot 8: ui_summary_card PLAIN ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_summary_card 'Setup Summary' 'vps: installed' 'cf: verified' 'bot: dry-run' 'web: skipped'
")

assert_contains "$output" "Setup Summary" "Summary PLAIN: title"
assert_contains "$output" "installed" "Summary PLAIN: installed"
assert_contains "$output" "verified" "Summary PLAIN: verified"
assert_contains "$output" "dry-run" "Summary PLAIN: dry-run"
assert_contains "$output" "skipped" "Summary PLAIN: skipped"
assert_not_contains "$output" "success" "Summary PLAIN: no fake success"

if has_ansi "$output"; then
  fail "Summary PLAIN: no ANSI escape"
else
  pass "Summary PLAIN: no ANSI escape"
fi

# ── Snapshot 9: Full Wizard dry-run smoke ─────────────────────────────────

echo ""
echo "--- Snapshot 9: Full Wizard dry-run smoke ---"

wizard_output=$(env NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)

# Check key content is present
assert_contains "$wizard_output" "NanoBK" "Wizard: contains NanoBK"
assert_contains "$wizard_output" "planned / dry-run" "Wizard: contains planned / dry-run"

# Check honest status
assert_not_contains "$wizard_output" "status:  success" "Wizard: no fake success status"

# Check no secret leakage
assert_not_contains "$wizard_output" "SECRET_TEST_BOT_TOKEN" "Wizard: no test bot token"
assert_not_contains "$wizard_output" "TOKEN=" "Wizard: no TOKEN= in output"
assert_not_contains "$wizard_output" "SECRET=" "Wizard: no SECRET= in output"

# Check wizard output does not contain raw env file contents
assert_not_contains "$wizard_output" "NANOBK_CF_API_TOKEN" "Wizard: no raw CF token var"
assert_not_contains "$wizard_output" "ADMIN_TOKEN=" "Wizard: no raw ADMIN_TOKEN"

# Check control-plane wording preserved in install.sh
install_content=$(cat "${REPO_DIR}/installer/install.sh")
assert_contains "$install_content" "控制端配置" "install.sh: control-plane wording preserved"
assert_contains "$install_content" "不代表 VPS 节点或 Cloudflare 订阅已经可用" "install.sh: control-plane semantic preserved"

# ── Snapshot 10: Test helper stability ────────────────────────────────────

echo ""
echo "--- Snapshot 10: Test helper stability ---"

# This test file itself must not have pipe+grep-q patterns
# Filter out self-check block and comments referencing the pattern
filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have\|LC_ALL=C grep' "${SCRIPT_DIR}/unified-cli-visual-snapshot-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

# This test file must use here-string for assertions
if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-visual-snapshot-v1.8.sh"; then
  pass "Self-check: uses here-string"
else
  fail "Self-check: must use here-string"
fi

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED"
  exit 1
else
  echo "ALL PASSED"
  exit 0
fi
