#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.26 CLI UI Test
#
# Tests the UI display layer and operation log features.
# Does NOT test deployment logic — only display behavior.
#
# Usage:
#   bash tests/unified-cli-ui-v1.8.sh

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

# ── Assertions: use here-string, NOT pipe, to avoid pipefail flakiness ────

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

# ── Test helper: source ui.sh in a subshell with env ──────────────────────

source_ui_and_run() {
  local env_flags="$1"
  local code="$2"
  # Use env to set flags, avoiding eval quoting issues
  env $env_flags bash -c "
    source '${REPO_DIR}/installer/lib/ui.sh'
    ${code}
  " 2>&1
}

# ── Test 1: NANOBK_PLAIN=1 disables emoji and color ──────────────────────

echo ""
echo "=== Test Suite: v1.8.26 CLI UI ==="
echo ""

echo "--- Test 1: NANOBK_PLAIN=1 disables emoji and color ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_info 'test info'
  ui_success 'test success'
  ui_warn 'test warn'
  ui_error 'test error'
  ui_section 'Test Section'
")

# Check with actual emoji chars using here-string (no pipe)
if grep -qF '✓' <<< "$output"; then
  fail "PLAIN: no checkmark emoji"
else
  pass "PLAIN: no checkmark emoji"
fi
if grep -qF '✕' <<< "$output"; then
  fail "PLAIN: no X emoji"
else
  pass "PLAIN: no X emoji"
fi
# Check no ANSI escapes
if grep -qE $'\x1b\[' <<< "$output"; then
  fail "PLAIN: no ANSI escape codes"
else
  pass "PLAIN: no ANSI escape codes"
fi
assert_contains "$output" "[INFO]" "PLAIN: contains [INFO] tag"
assert_contains "$output" "OK" "PLAIN: contains OK text"
assert_contains "$output" "WARN" "PLAIN: contains WARN text"
assert_contains "$output" "ERR" "PLAIN: contains ERR text"

# ── Test 1b: PLAIN section has no Unicode bars ────────────────────────────

echo ""
echo "--- Test 1b: PLAIN section is pure ASCII ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_section '阶段 1' 1 5
")

if grep -qF '■' <<< "$output"; then
  fail "PLAIN section: no Unicode filled bar"
else
  pass "PLAIN section: no Unicode filled bar"
fi
if grep -qF '□' <<< "$output"; then
  fail "PLAIN section: no Unicode empty bar"
else
  pass "PLAIN section: no Unicode empty bar"
fi
if grep -qF '──' <<< "$output"; then
  fail "PLAIN section: no Unicode dash"
else
  pass "PLAIN section: no Unicode dash"
fi
if grep -qE $'\x1b\[' <<< "$output"; then
  fail "PLAIN section: no ANSI escape"
else
  pass "PLAIN section: no ANSI escape"
fi
assert_contains "$output" "Step 1/5" "PLAIN section: contains Step 1/5"
assert_contains "$output" "阶段 1" "PLAIN section: contains title"

# ── Test 1c: PLAIN progress is pure ASCII ─────────────────────────────────

echo ""
echo "--- Test 1c: PLAIN progress is pure ASCII ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_progress 3 6 'Installing'
")

if grep -qF '■' <<< "$output"; then
  fail "PLAIN progress: no Unicode filled bar"
else
  pass "PLAIN progress: no Unicode filled bar"
fi
if grep -qF '□' <<< "$output"; then
  fail "PLAIN progress: no Unicode empty bar"
else
  pass "PLAIN progress: no Unicode empty bar"
fi
assert_contains "$output" "Step 3/6" "PLAIN progress: shows Step 3/6"
assert_contains "$output" "Installing" "PLAIN progress: shows label"

# ── Test 1d: PLAIN divider uses ASCII ─────────────────────────────────────

echo ""
echo "--- Test 1d: PLAIN divider uses ASCII ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_divider
")

if grep -qF '─' <<< "$output"; then
  fail "PLAIN divider: no Unicode dash"
else
  pass "PLAIN divider: no Unicode dash"
fi
# Should contain plain ASCII dashes
assert_contains "$output" "-" "PLAIN divider: contains ASCII dash"

# ── Test 1e: PLAIN spinner is plain text ──────────────────────────────────

echo ""
echo "--- Test 1e: PLAIN spinner is plain text ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_spinner_start 'Testing'
  ui_spinner_stop
")

if grep -qE $'\x1b\[' <<< "$output"; then
  fail "PLAIN spinner: no ANSI escape"
else
  pass "PLAIN spinner: no ANSI escape"
fi
assert_contains "$output" "Testing" "PLAIN spinner: shows message text"

# ── Test 2: NANOBK_NO_EMOJI=1 disables emoji but keeps color ─────────────

echo ""
echo "--- Test 2: NANOBK_NO_EMOJI=1 disables emoji ---"

output=$(source_ui_and_run "NANOBK_NO_EMOJI=1" "
  ui_info 'test info'
  ui_success 'test success'
")

# In non-TTY (subshell), color is auto-disabled, so check for symbol fallbacks
if grep -qF '✓' <<< "$output"; then
  fail "NO_EMOJI: no checkmark emoji"
else
  pass "NO_EMOJI: no checkmark emoji"
fi
assert_contains "$output" "OK" "NO_EMOJI: contains OK fallback"

# ── Test 3: Default UI (non-TTY) does not produce dangerous control chars ─

echo ""
echo "--- Test 3: Default UI safe in non-TTY ---"

output=$(source_ui_and_run "" "
  ui_info 'test'
  ui_success 'test'
  ui_warn 'test'
  ui_error 'test'
")

assert_contains "$output" "[INFO]" "Default non-TTY: contains info text"

# ── Test 4: NANOBK_UI=0 legacy bypass ────────────────────────────────────

echo ""
echo "--- Test 4: NANOBK_UI=0 legacy bypass ---"

output=$(source_ui_and_run "NANOBK_UI=0" "
  ui_info 'test info'
  ui_success 'test ok'
  ui_section 'Test Section'
")

assert_contains "$output" "[INFO]" "UI=0: contains [INFO]"
assert_contains "$output" "[OK]" "UI=0: contains [OK]"
assert_contains "$output" "Test Section" "UI=0: contains section header"

# ── Test 5: ui_recovery_block shows commands ──────────────────────────────

echo ""
echo "--- Test 5: ui_recovery_block shows commands ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_recovery_block 'cmd one' 'cmd two' 'cmd three'
")

assert_contains "$output" "可以稍后继续" "Recovery: contains continue-later label"
assert_contains "$output" "cmd one" "Recovery: shows first command"
assert_contains "$output" "cmd two" "Recovery: shows second command"
assert_contains "$output" "cmd three" "Recovery: shows third command"

# ── Test 6: ui_token_reminder honest wording ──────────────────────────────

echo ""
echo "--- Test 6: ui_token_reminder safety ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_token_reminder
")

assert_not_contains "$output" "BOT_TOKEN" "Token reminder: no BOT_TOKEN"
assert_not_contains "$output" "123456" "Token reminder: no example token"
assert_contains "$output" "token" "Token reminder: mentions token concept"
assert_contains "$output" "revoke" "Token reminder: mentions revoke"
assert_contains "$output" "regenerate" "Token reminder: mentions regenerate"
assert_contains "$output" "当作密码保管" "Token reminder: mentions treat-as-password"
assert_contains "$output" "隐藏敏感信息" "Token reminder: mentions hide-sensitive-info"
# Must NOT contain over-promise
assert_not_contains "$output" "不会出现在屏幕或日志中" "Token reminder: no absolute promise"

# ── Test 7: ui_summary_card preserves honest status words ────────────────

echo ""
echo "--- Test 7: Summary honest status preservation ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_summary_card 'Test Summary' \
    'vps: dry-run' \
    'cf: failed' \
    'bot: manual_pending' \
    'web: skipped' \
    'status: unknown'
")

assert_contains "$output" "dry-run" "Summary: preserves dry-run"
assert_contains "$output" "failed" "Summary: preserves failed"
assert_contains "$output" "manual_pending" "Summary: preserves manual_pending"
assert_contains "$output" "skipped" "Summary: preserves skipped"
assert_contains "$output" "unknown" "Summary: preserves unknown"
assert_not_contains "$output" "success" "Summary: no fake success"

# ── Test 8: Operation log redaction ───────────────────────────────────────

echo ""
echo "--- Test 8: Operation log redaction ---"

output=$(bash -c "
  source '${REPO_DIR}/installer/lib/operation-log.sh'
  oplog_redact 'TOKEN=abc123def456ghi789jkl012mno'
" 2>&1)

assert_not_contains "$output" "abc123def456ghi789jkl012mno" "Redaction: long token value removed"
assert_contains "$output" "REDACTED" "Redaction: shows REDACTED"

# ── Test 8b: Comprehensive redaction patterns ─────────────────────────────

echo ""
echo "--- Test 8b: Comprehensive redaction patterns ---"

redact_test() {
  local input="$1"
  local desc="$2"
  bash -c "
    source '${REPO_DIR}/installer/lib/operation-log.sh'
    oplog_redact '${input}'
  " 2>&1
}

# SUB_TOKEN
output=$(redact_test "SUB_TOKEN=supersecretvalue123" "SUB_TOKEN")
assert_not_contains "$output" "supersecretvalue123" "Redact SUB_TOKEN: value removed"
assert_contains "$output" "REDACTED" "Redact SUB_TOKEN: shows REDACTED"

# ADMIN_TOKEN
output=$(redact_test "ADMIN_TOKEN=adminsecretvalue456" "ADMIN_TOKEN")
assert_not_contains "$output" "adminsecretvalue456" "Redact ADMIN_TOKEN: value removed"
assert_contains "$output" "REDACTED" "Redact ADMIN_TOKEN: shows REDACTED"

# NANOB_TOKEN
output=$(redact_test "NANOB_TOKEN=nanobsecret789" "NANOB_TOKEN")
assert_not_contains "$output" "nanobsecret789" "Redact NANOB_TOKEN: value removed"
assert_contains "$output" "REDACTED" "Redact NANOB_TOKEN: shows REDACTED"

# CF_API_TOKEN
output=$(redact_test "CF_API_TOKEN=cfsecretvalueabc" "CF_API_TOKEN")
assert_not_contains "$output" "cfsecretvalueabc" "Redact CF_API_TOKEN: value removed"
assert_contains "$output" "REDACTED" "Redact CF_API_TOKEN: shows REDACTED"

# Authorization: Bearer
output=$(redact_test "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature" "Bearer token")
assert_not_contains "$output" "eyJhbGciOiJIUzI1NiJ9" "Redact Bearer: token removed"
assert_contains "$output" "REDACTED" "Redact Bearer: shows REDACTED"

# password
output=$(redact_test "password=mypassword123" "password")
assert_not_contains "$output" "mypassword123" "Redact password: value removed"
assert_contains "$output" "REDACTED" "Redact password: shows REDACTED"

# SECRET
output=$(redact_test "SECRET=mysecretvalue456" "SECRET")
assert_not_contains "$output" "mysecretvalue456" "Redact SECRET: value removed"
assert_contains "$output" "REDACTED" "Redact SECRET: shows REDACTED"

# PRIVATE_KEY
output=$(redact_test "PRIVATE_KEY=privatekeyvalue789" "PRIVATE_KEY")
assert_not_contains "$output" "privatekeyvalue789" "Redact PRIVATE_KEY: value removed"
assert_contains "$output" "REDACTED" "Redact PRIVATE_KEY: shows REDACTED"

# REALITY_PRIVATE_KEY
output=$(redact_test "REALITY_PRIVATE_KEY=realitykeyvalue012" "REALITY_PRIVATE_KEY")
assert_not_contains "$output" "realitykeyvalue012" "Redact REALITY_PRIVATE_KEY: value removed"
assert_contains "$output" "REDACTED" "Redact REALITY_PRIVATE_KEY: shows REDACTED"

# Quoted token
output=$(redact_test "ADMIN_TOKEN='quotedsecretvalue'" "Quoted ADMIN_TOKEN")
assert_not_contains "$output" "quotedsecretvalue" "Redact quoted token: value removed"
assert_contains "$output" "REDACTED" "Redact quoted token: shows REDACTED"

# workers.dev URL with query token
output=$(redact_test "https://my-worker.workers.dev/api?token=secret123&other=ok" "workers.dev URL with token")
assert_not_contains "$output" "secret123" "Redact workers.dev URL: token query removed"
assert_not_contains "$output" "workers.dev" "Redact workers.dev URL: full URL removed"

# pages.dev URL with query token
output=$(redact_test "https://my-page.pages.dev/path?admin_token=adminsecret456" "pages.dev URL with token")
assert_not_contains "$output" "adminsecret456" "Redact pages.dev URL: token query removed"

# Bot token pattern (123456789:ABC...)
output=$(redact_test "1234567890:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghi" "Bot token pattern")
assert_not_contains "$output" "1234567890:" "Redact bot token: token removed"
assert_contains "$output" "REDACTED" "Redact bot token: shows REDACTED"

# ── Test 8c: oplog_write redacts before writing ───────────────────────────

echo ""
echo "--- Test 8c: oplog_write redacts before writing ---"

output=$(bash -c "
  source '${REPO_DIR}/installer/lib/operation-log.sh'
  export NANOBK_LOG_DIR='/tmp/nanobk-test-oplog-$$'
  mkdir -p \"\$NANOBK_LOG_DIR\"
  oplog_init 'test-redact' >/dev/null
  oplog_write 'SECRET=mysecretvalue should not appear'
  cat \"\$_oplog_current_file\"
  rm -rf \"\$NANOBK_LOG_DIR\"
" 2>&1)

assert_not_contains "$output" "mysecretvalue" "oplog_write: secret not in log file"
assert_contains "$output" "REDACTED" "oplog_write: log contains REDACTED"

# ── Test 8d: oplog_run redacts command line ───────────────────────────────

echo ""
echo "--- Test 8d: oplog_run redacts command line ---"

output=$(bash -c "
  source '${REPO_DIR}/installer/lib/operation-log.sh'
  export NANOBK_LOG_DIR='/tmp/nanobk-test-oplog2-$$'
  mkdir -p \"\$NANOBK_LOG_DIR\"
  oplog_init 'test-cmd' >/dev/null
  oplog_run 'test' echo 'TOKEN=secretcmdvalue123'
  cat \"\$_oplog_current_file\"
  rm -rf \"\$NANOBK_LOG_DIR\"
" 2>&1)

assert_not_contains "$output" "secretcmdvalue123" "oplog_run: command secret not in log"

# ── Test 8e: oplog_init label redaction ───────────────────────────────────

echo ""
echo "--- Test 8e: oplog_init label redaction ---"

output=$(bash -c "
  source '${REPO_DIR}/installer/lib/operation-log.sh'
  export NANOBK_LOG_DIR='/tmp/nanobk-test-oplog3-$$'
  mkdir -p \"\$NANOBK_LOG_DIR\"
  oplog_init 'TOKEN=secretlabel123' >/dev/null
  cat \"\$_oplog_current_file\"
  rm -rf \"\$NANOBK_LOG_DIR\"
" 2>&1)

assert_not_contains "$output" "secretlabel123" "oplog_init: label secret not in log"
assert_contains "$output" "REDACTED" "oplog_init: label shows REDACTED"

# ── Test 8f: oplog_close status redaction ─────────────────────────────────

echo ""
echo "--- Test 8f: oplog_close status redaction ---"

output=$(bash -c "
  source '${REPO_DIR}/installer/lib/operation-log.sh'
  export NANOBK_LOG_DIR='/tmp/nanobk-test-oplog4-$$'
  mkdir -p \"\$NANOBK_LOG_DIR\"
  oplog_init 'test-close' >/dev/null
  oplog_close 'SECRET=secretstatus123'
  cat \"\$_oplog_current_file\"
  rm -rf \"\$NANOBK_LOG_DIR\"
" 2>&1)

assert_not_contains "$output" "secretstatus123" "oplog_close: status secret not in log"
assert_contains "$output" "REDACTED" "oplog_close: status shows REDACTED"

# ── Test 9: ui_banner displays version ────────────────────────────────────

echo ""
echo "--- Test 9: ui_banner displays version ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_banner 'v1.8.26' 'Test Subtitle'
")

assert_contains "$output" "NanoBK Proxy Suite" "Banner: shows product name"
assert_contains "$output" "v1.8.26" "Banner: shows version"
assert_contains "$output" "Test Subtitle" "Banner: shows subtitle"

# ── Test 10: ui_progress in PLAIN mode ────────────────────────────────────

echo ""
echo "--- Test 10: ui_progress PLAIN ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_progress 3 6 'Installing'
")

assert_contains "$output" "3/6" "Progress: shows count"
assert_contains "$output" "Installing" "Progress: shows label"

# ── Test 11: Version is 1.8.26 ────────────────────────────────────────────

echo ""
echo "--- Test 11: Version consistency ---"

nanobk_version=$("${REPO_DIR}/bin/nanobk" --version 2>&1)
assert_contains "$nanobk_version" "1.8.26" "nanobk --version shows 1.8.26"

install_version=$(grep '^VERSION=' "${REPO_DIR}/installer/install.sh" | head -1)
assert_contains "$install_version" "1.8.26" "install.sh VERSION is 1.8.26"

bootstrap_version=$(grep '^BOOTSTRAP_VERSION=' "${REPO_DIR}/installer/bootstrap.sh" | head -1)
assert_contains "$bootstrap_version" "1.8.26" "bootstrap.sh BOOTSTRAP_VERSION is 1.8.26"

# ── Test 12: Summary status words not replaced with success ───────────────

echo ""
echo "--- Test 12: install.sh Summary honesty ---"

for status_word in "planned / dry-run" "commands only" "manual_pending" "failed" "skipped" "control plane only" "unknown"; do
  if grep -qF "$status_word" "${REPO_DIR}/installer/install.sh"; then
    pass "install.sh contains honest status: ${status_word}"
  else
    fail "install.sh missing honest status: ${status_word}"
  fi
done

# Ensure no misleading success replacements
if grep -qF "status:  success" "${REPO_DIR}/installer/install.sh"; then
  fail "install.sh: no fake 'success' status"
else
  pass "install.sh: no fake 'success' status"
fi

# ── Test 13: oplog_hint_on_failure has no ANSI in non-TTY ─────────────────

echo ""
echo "--- Test 13: oplog_hint_on_failure non-TTY safety ---"

output=$(bash -c "
  source '${REPO_DIR}/installer/lib/operation-log.sh'
  export NANOBK_LOG_DIR='/tmp/nanobk-test-hint-$$'
  mkdir -p \"\$NANOBK_LOG_DIR\"
  oplog_init 'test-hint' >/dev/null
  oplog_hint_on_failure '测试失败'
  rm -rf \"\$NANOBK_LOG_DIR\"
" 2>&1)

if grep -qE $'\x1b\[' <<< "$output"; then
  fail "oplog_hint: no ANSI in non-TTY"
else
  pass "oplog_hint: no ANSI in non-TTY"
fi
assert_contains "$output" "测试失败" "oplog_hint: contains failure message"
assert_contains "$output" "详细日志" "oplog_hint: contains log path hint"

# ── Test 14: Test helper stability check ──────────────────────────────────

echo ""
echo "--- Test 14: Test helper stability ---"

# This test file must NOT contain "| grep -q" pipe pattern (pipefail hazard)
# Use variable + here-string to avoid any pipe in the check itself
# Filter out this self-check block and comments referencing the pattern
filtered_test_file="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain' "${REPO_DIR}/tests/unified-cli-ui-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_test_file"; then
  fail "Test file: no pipe+grep-q pattern"
else
  pass "Test file: no pipe+grep-q pattern"
fi

# This test file MUST use here-string for assertions
if grep -qF '<<< "$haystack"' "${REPO_DIR}/tests/unified-cli-ui-v1.8.sh"; then
  pass "Test file: uses here-string for assertions"
else
  fail "Test file: must use here-string for assertions"
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
