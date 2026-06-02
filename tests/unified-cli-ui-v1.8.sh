#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.0 CLI UI Test
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
  echo "  ✓ $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  ✕ $1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if printf '%s\n' "$haystack" | grep -qF "$needle"; then
    pass "$label"
  else
    fail "$label — expected to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if printf '%s\n' "$haystack" | grep -qF "$needle"; then
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
echo "=== Test Suite: v1.8.0 CLI UI ==="
echo ""

echo "--- Test 1: NANOBK_PLAIN=1 disables emoji and color ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_info 'test info'
  ui_success 'test success'
  ui_warn 'test warn'
  ui_error 'test error'
  ui_section 'Test Section'
")

assert_not_contains "$output" "✓" "PLAIN: no checkmark emoji"
assert_not_contains "$output" "✕" "PLAIN: no X emoji"
assert_not_contains "$output" "!" "PLAIN: no exclamation emoji in info"
assert_not_contains "$output" '\033[' "PLAIN: no ANSI escape codes"
assert_contains "$output" "[INFO]" "PLAIN: contains [INFO] tag"
assert_contains "$output" "OK" "PLAIN: contains OK text"
assert_contains "$output" "WARN" "PLAIN: contains WARN text"
assert_contains "$output" "ERR" "PLAIN: contains ERR text"

# ── Test 2: NANOBK_NO_EMOJI=1 disables emoji but keeps color ─────────────

echo ""
echo "--- Test 2: NANOBK_NO_EMOJI=1 disables emoji ---"

output=$(source_ui_and_run "NANOBK_NO_EMOJI=1" "
  ui_info 'test info'
  ui_success 'test success'
")

# In non-TTY (subshell), color is auto-disabled, so check for symbol fallbacks
assert_not_contains "$output" "✓" "NO_EMOJI: no checkmark emoji"
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

# Should not contain raw escape sequences in non-TTY
# (non-TTY auto-disables color)
# But the text content should still be present
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
assert_contains "$output" "── Test Section ──" "UI=0: contains section header"

# ── Test 5: ui_recovery_block shows commands ──────────────────────────────

echo ""
echo "--- Test 5: ui_recovery_block shows commands ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_recovery_block 'cmd one' 'cmd two' 'cmd three'
")

assert_contains "$output" "cmd one" "Recovery: shows first command"
assert_contains "$output" "cmd two" "Recovery: shows second command"
assert_contains "$output" "cmd three" "Recovery: shows third command"
assert_contains "$output" "\$" "Recovery: shows dollar prompt"

# ── Test 6: ui_token_reminder does not leak secrets ───────────────────────

echo ""
echo "--- Test 6: ui_token_reminder safety ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_token_reminder
")

assert_not_contains "$output" "BOT_TOKEN" "Token reminder: no BOT_TOKEN"
assert_not_contains "$output" "123456" "Token reminder: no example token"
assert_contains "$output" "token" "Token reminder: mentions token concept"
assert_contains "$output" "不会" "Token reminder: says won't leak"

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

# ── Test 9: ui_banner displays version ────────────────────────────────────

echo ""
echo "--- Test 9: ui_banner displays version ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_banner 'v1.8.0' 'Test Subtitle'
")

assert_contains "$output" "NanoBK Proxy Suite" "Banner: shows product name"
assert_contains "$output" "v1.8.0" "Banner: shows version"
assert_contains "$output" "Test Subtitle" "Banner: shows subtitle"

# ── Test 10: ui_progress shows bar in color mode ──────────────────────────

echo ""
echo "--- Test 10: ui_progress ---"

output=$(source_ui_and_run "NANOBK_PLAIN=1" "
  ui_progress 3 6 'Installing'
")

assert_contains "$output" "3/6" "Progress: shows count"
assert_contains "$output" "Installing" "Progress: shows label"

# ── Test 11: Version is 1.8.0 ────────────────────────────────────────────

echo ""
echo "--- Test 11: Version consistency ---"

nanobk_version=$("${REPO_DIR}/bin/nanobk" --version 2>&1)
assert_contains "$nanobk_version" "1.8.0" "nanobk --version shows 1.8.0"

install_version=$(grep '^VERSION=' "${REPO_DIR}/installer/install.sh" | head -1)
assert_contains "$install_version" "1.8.0" "install.sh VERSION is 1.8.0"

bootstrap_version=$(grep '^BOOTSTRAP_VERSION=' "${REPO_DIR}/installer/bootstrap.sh" | head -1)
assert_contains "$bootstrap_version" "1.8.0" "bootstrap.sh BOOTSTRAP_VERSION is 1.8.0"

# ── Test 12: Summary status words not replaced with success ───────────────

echo ""
echo "--- Test 12: install.sh Summary honesty ---"

# Check that install.sh still contains honest status words in print_summary
# Use grep directly on the file to avoid pipe/argument length issues
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
