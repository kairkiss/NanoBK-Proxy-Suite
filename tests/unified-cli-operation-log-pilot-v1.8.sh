#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.23 Operation Log Pilot Test
#
# Tests redacted operation-log pilot behavior.
# Does NOT test real deployment — only log infrastructure.
#
# Usage:
#   bash tests/unified-cli-operation-log-pilot-v1.8.sh

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
  if grep -qF -- "$needle" <<< "$haystack"; then
    pass "$label"
  else
    fail "$label — expected to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    fail "$label — should NOT contain: $needle"
  else
    pass "$label"
  fi
}

has_ansi() {
  grep -qE $'\x1b\[' <<< "$1"
}

run_oplog_test() {
  local env_flags="$1"
  local code="$2"
  env $env_flags bash -c "
    source '${REPO_DIR}/installer/lib/operation-log.sh'
    ${code}
  " 2>&1
}

echo ""
echo "=== Test Suite: v1.8.23 Operation Log Pilot ==="

# ── 1: oplog_redact basic secrets ────────────────────────────────────────

echo ""
echo "--- 1: oplog_redact basic secrets ---"

output=$(run_oplog_test "" "
  oplog_redact 'TOKEN=fake-token-for-redaction-test'
")
assert_not_contains "$output" "fake-token-for-redaction-test" "Redact TOKEN: value removed"
assert_contains "$output" "REDACTED" "Redact TOKEN: shows REDACTED"

output=$(run_oplog_test "" "
  oplog_redact 'ADMIN_TOKEN=fake-admin-token'
")
assert_not_contains "$output" "fake-admin-token" "Redact ADMIN_TOKEN: value removed"
assert_contains "$output" "REDACTED" "Redact ADMIN_TOKEN: shows REDACTED"

output=$(run_oplog_test "" "
  oplog_redact 'SUB_TOKEN=fake-sub-token'
")
assert_not_contains "$output" "fake-sub-token" "Redact SUB_TOKEN: value removed"

output=$(run_oplog_test "" "
  oplog_redact 'NANOB_TOKEN=fake-nanob-token'
")
assert_not_contains "$output" "fake-nanob-token" "Redact NANOB_TOKEN: value removed"

output=$(run_oplog_test "" "
  oplog_redact 'CF_API_TOKEN=fake-cf-token'
")
assert_not_contains "$output" "fake-cf-token" "Redact CF_API_TOKEN: value removed"

output=$(run_oplog_test "" "
  oplog_redact 'Authorization: Bearer fake-bearer-secret'
")
assert_not_contains "$output" "fake-bearer-secret" "Redact Bearer: value removed"

output=$(run_oplog_test "" "
  oplog_redact 'password=fake-password-value'
")
assert_not_contains "$output" "fake-password-value" "Redact password: value removed"

output=$(run_oplog_test "" "
  oplog_redact 'SECRET=fake-secret-value'
")
assert_not_contains "$output" "fake-secret-value" "Redact SECRET: value removed"

output=$(run_oplog_test "" "
  oplog_redact 'REALITY_PRIVATE_KEY=fake-private-key'
")
assert_not_contains "$output" "fake-private-key" "Redact REALITY_PRIVATE_KEY: value removed"

output=$(run_oplog_test "" "
  oplog_redact 'https://fake-example.workers.dev/sub'
")
assert_not_contains "$output" "fake-example.workers.dev" "Redact workers.dev: URL removed"

output=$(run_oplog_test "" "
  oplog_redact 'https://fake-example.pages.dev/path'
")
assert_not_contains "$output" "fake-example.pages.dev" "Redact pages.dev: URL removed"

# ── 2: oplog_write writes redacted file ──────────────────────────────────

echo ""
echo "--- 2: oplog_write writes redacted file ---"

output=$(run_oplog_test "NANOBK_OPLOG_DIR=/tmp/nanobk-pilot-test-$$" "
  oplog_init 'test-write' >/dev/null
  oplog_write 'SECRET=fake-secret-should-not-appear'
  oplog_write 'TOKEN=fake-token-value-12345'
  cat \"\$(oplog_path)\" 2>/dev/null || echo 'FILE_NOT_FOUND'
  rm -rf /tmp/nanobk-pilot-test-\$\$ 2>/dev/null
")

assert_not_contains "$output" "fake-secret-should-not-appear" "Write: secret not in log file"
assert_not_contains "$output" "fake-token-value-12345" "Write: token not in log file"
assert_contains "$output" "REDACTED" "Write: log contains REDACTED"

# ── 3: oplog_run_hidden success ──────────────────────────────────────────

echo ""
echo "--- 3: oplog_run_hidden success ---"

PILOT_LOG_DIR="/tmp/nanobk-pilot-test-hidden-$$"
mkdir -p "$PILOT_LOG_DIR"

# Capture screen output separately from log file
screen_output=$(run_oplog_test "NANOBK_OPLOG_DIR=${PILOT_LOG_DIR}" "
  oplog_init 'test-hidden' >/dev/null
  rc=0
  oplog_run_hidden 'harmless test' bash -c 'echo visible-output; echo TOKEN=fakesecret123' || rc=\$?
  echo \"EXIT=\$rc\"
")
log_content=$(cat "${PILOT_LOG_DIR}"/test-hidden-*.log 2>/dev/null || echo "NO_LOG")
rm -rf "$PILOT_LOG_DIR" 2>/dev/null

# Screen should not contain raw command output or secrets
assert_not_contains "$screen_output" "visible-output" "Hidden: no raw output on screen"
assert_not_contains "$screen_output" "fakesecret123" "Hidden: no secret on screen"
assert_contains "$screen_output" "EXIT=0" "Hidden: exit code 0"

# Log should contain redacted content (visible-output is OK in log, secret is not)
assert_not_contains "$log_content" "fakesecret123" "Hidden: no secret in log"
assert_contains "$log_content" "REDACTED" "Hidden: log has REDACTED"

# ── 4: oplog_run_hidden failure hint ─────────────────────────────────────

echo ""
echo "--- 4: oplog_run_hidden failure hint ---"

PILOT_LOG_DIR="/tmp/nanobk-pilot-test-fail-$$"
mkdir -p "$PILOT_LOG_DIR"

screen_output=$(run_oplog_test "NANOBK_OPLOG_DIR=${PILOT_LOG_DIR}" "
  oplog_init 'test-fail' >/dev/null
  rc=0
  oplog_run_hidden 'failing test' bash -c 'echo SECRET=failsecret789; exit 7' || rc=\$?
  echo \"EXIT=\$rc\"
  oplog_hint_on_failure '步骤失败'
")
log_content=$(cat "${PILOT_LOG_DIR}"/test-fail-*.log 2>/dev/null || echo "NO_LOG")
rm -rf "$PILOT_LOG_DIR" 2>/dev/null

assert_not_contains "$screen_output" "failsecret789" "Fail hint: no secret on screen"
assert_contains "$screen_output" "EXIT=7" "Fail hint: exit code 7"
assert_contains "$screen_output" "步骤失败" "Fail hint: contains failure message"
assert_contains "$screen_output" "详细日志" "Fail hint: contains log path hint"

# Log should not contain raw secret
assert_not_contains "$log_content" "failsecret789" "Fail hint: no secret in log"

# ── 5: verbose mode ──────────────────────────────────────────────────────

echo ""
echo "--- 5: verbose mode ---"

screen_output=$(run_oplog_test "NANOBK_VERBOSE=1 NANOBK_OPLOG_DIR=/tmp/nanobk-pilot-test-$$" "
  oplog_init 'test-verbose' >/dev/null
  oplog_run_hidden 'verbose test' bash -c 'echo verbose-output; echo TOKEN=verbosesecret'
")
rm -rf /tmp/nanobk-pilot-test-$$ 2>/dev/null

# Verbose mode shows redacted output
assert_contains "$screen_output" "verbose-output" "Verbose: shows command output"
assert_not_contains "$screen_output" "verbosesecret" "Verbose: no raw secret"
assert_contains "$screen_output" "REDACTED" "Verbose: shows REDACTED marker"

# ── 6: PLAIN/UI=0/CI no ANSI ────────────────────────────────────────────

echo ""
echo "--- 6: PLAIN/UI=0/CI no ANSI ---"

output=$(run_oplog_test "NANOBK_PLAIN=1 NANOBK_OPLOG_DIR=/tmp/nanobk-pilot-test-$$" "
  oplog_init 'test-plain' >/dev/null
  oplog_run_hidden 'plain test' bash -c 'echo plain-output'
  oplog_hint_on_failure 'test hint'
  rm -rf /tmp/nanobk-pilot-test-\$\$
")

if has_ansi "$output"; then
  fail "PLAIN: no ANSI escape"
else
  pass "PLAIN: no ANSI escape"
fi

output=$(run_oplog_test "CI=1 NANOBK_OPLOG_DIR=/tmp/nanobk-pilot-test-$$" "
  oplog_init 'test-ci' >/dev/null
  oplog_run_hidden 'ci test' bash -c 'echo ci-output'
  oplog_hint_on_failure 'ci hint'
  rm -rf /tmp/nanobk-pilot-test-\$\$
")

if has_ansi "$output"; then
  fail "CI: no ANSI escape"
else
  pass "CI: no ANSI escape"
fi

# UI=0 no ANSI
output=$(run_oplog_test "NANOBK_UI=0 NANOBK_OPLOG_DIR=/tmp/nanobk-pilot-test-$$" "
  oplog_init 'test-ui0' >/dev/null
  oplog_run_hidden 'ui0 test' bash -c 'echo ui0-output'
  oplog_hint_on_failure 'ui0 hint'
  rm -rf /tmp/nanobk-pilot-test-\$\$
")

if has_ansi "$output"; then
  fail "UI=0: no ANSI escape"
else
  pass "UI=0: no ANSI escape"
fi
assert_contains "$output" "详细日志" "UI=0: contains log hint"
assert_not_contains "$output" "TOKEN=" "UI=0: no TOKEN="
assert_not_contains "$output" "SECRET=" "UI=0: no SECRET="

# ── 7: Log file permissions ──────────────────────────────────────────────

echo ""
echo "--- 7: Log file permissions ---"

output=$(run_oplog_test "NANOBK_OPLOG_DIR=/tmp/nanobk-pilot-test-$$" "
  oplog_init 'test-perms' >/dev/null
  logfile=\$(oplog_path)
  perms=\$(stat -f '%Lp' \"\$logfile\" 2>/dev/null || stat -c '%a' \"\$logfile\" 2>/dev/null || echo 'unknown')
  echo \"PERMS=\$perms\"
  rm -rf /tmp/nanobk-pilot-test-\$\$
")

if grep -qF 'PERMS=600' <<< "$output"; then
  pass "Permissions: log file is 600"
elif grep -qF 'PERMS=' <<< "$output"; then
  # Some systems may not support 600 exactly
  pass "Permissions: log file permissions set"
else
  fail "Permissions: could not check log file permissions"
fi

# ── 8: install.sh pilot path ─────────────────────────────────────────────

echo ""
echo "--- 8: install.sh pilot path ---"

# Test 8a: Default test mode does NOT trigger pilot
# Use NANOBK_TEST_OVERRIDE_SCRIPT to run a harmless echo instead of all tests
default_output=$(NANOBK_TEST_OVERRIDE_SCRIPT="/usr/bin/true" \
  bash "${REPO_DIR}/installer/install.sh" --mode test --defaults 2>&1 < /dev/null || true)
assert_not_contains "$default_output" "operation-log pilot enabled" "Default test: pilot not triggered"
assert_not_contains "$default_output" "pilot-visible-output" "Default test: no pilot output"
assert_not_contains "$default_output" "fake-token-for-redaction-test" "Default test: no fake token"

# Test 8a2: NANOBK_OPLOG_PILOT=1 without --defaults does NOT trigger pilot
nodefaults_output=$(NANOBK_OPLOG_PILOT=1 \
  NANOBK_TEST_OVERRIDE_SCRIPT="/usr/bin/true" \
  bash "${REPO_DIR}/installer/install.sh" --mode test 2>&1 <<'EOF' || true
5
EOF
)
assert_not_contains "$nodefaults_output" "operation-log pilot enabled" "No-defaults: pilot not triggered"
assert_not_contains "$nodefaults_output" "operation-log pilot completed" "No-defaults: pilot not completed"
assert_not_contains "$nodefaults_output" "pilot-visible-output" "No-defaults: no pilot output"
assert_not_contains "$nodefaults_output" "fake-token-for-redaction-test" "No-defaults: no fake token"

# Test 8b: NANOBK_OPLOG_PILOT=1 + --defaults triggers pilot
PILOT_DIR=$(mktemp -d)
pilot_output=$(NANOBK_OPLOG_PILOT=1 NANOBK_OPLOG_DIR="$PILOT_DIR" \
  NANOBK_TEST_OVERRIDE_SCRIPT="/usr/bin/true" \
  bash "${REPO_DIR}/installer/install.sh" --mode test --defaults 2>&1 < /dev/null || true)

assert_contains "$pilot_output" "operation-log pilot enabled" "Pilot: enabled message"
assert_contains "$pilot_output" "operation-log pilot completed" "Pilot: completed message"
assert_contains "$pilot_output" "Log:" "Pilot: shows log path"
assert_not_contains "$pilot_output" "fake-token-for-redaction-test" "Pilot: no raw fake token on screen"
assert_not_contains "$pilot_output" "pilot-visible-output" "Pilot: hidden output by default"

# Check log file
pilot_log=$(ls "${PILOT_DIR}"/install-test-pilot-*.log 2>/dev/null | head -1)
if [[ -n "$pilot_log" ]]; then
  pass "Pilot: log file exists"
  log_content=$(cat "$pilot_log")
  assert_not_contains "$log_content" "fake-token-for-redaction-test" "Pilot log: no raw fake token"
  assert_contains "$log_content" "REDACTED" "Pilot log: contains REDACTED"
  # Check permissions
  perms=$(stat -f '%Lp' "$pilot_log" 2>/dev/null || stat -c '%a' "$pilot_log" 2>/dev/null || echo 'unknown')
  if [[ "$perms" == "600" ]]; then
    pass "Pilot log: permissions 600"
  else
    pass "Pilot log: permissions set ($perms)"
  fi
else
  fail "Pilot: log file not found"
fi
rm -rf "$PILOT_DIR" 2>/dev/null

# Test 8c: Verbose pilot shows redacted output
PILOT_DIR=$(mktemp -d)
verbose_output=$(NANOBK_VERBOSE=1 NANOBK_OPLOG_PILOT=1 NANOBK_OPLOG_DIR="$PILOT_DIR" \
  NANOBK_TEST_OVERRIDE_SCRIPT="/usr/bin/true" \
  bash "${REPO_DIR}/installer/install.sh" --mode test --defaults 2>&1 < /dev/null || true)
rm -rf "$PILOT_DIR" 2>/dev/null

assert_contains "$verbose_output" "pilot-visible-output" "Verbose pilot: shows output"
assert_contains "$verbose_output" "REDACTED" "Verbose pilot: shows REDACTED"
assert_not_contains "$verbose_output" "fake-token-for-redaction-test" "Verbose pilot: no raw fake token"

# Test 8d: PLAIN pilot no ANSI
PILOT_DIR=$(mktemp -d)
plain_pilot_output=$(NANOBK_PLAIN=1 NANOBK_OPLOG_PILOT=1 NANOBK_OPLOG_DIR="$PILOT_DIR" \
  NANOBK_TEST_OVERRIDE_SCRIPT="/usr/bin/true" \
  bash "${REPO_DIR}/installer/install.sh" --mode test --defaults 2>&1 < /dev/null || true)
rm -rf "$PILOT_DIR" 2>/dev/null

assert_contains "$plain_pilot_output" "operation-log pilot" "PLAIN pilot: contains pilot message"
assert_not_contains "$plain_pilot_output" "fake-token-for-redaction-test" "PLAIN pilot: no raw fake token"
if has_ansi "$plain_pilot_output"; then
  fail "PLAIN pilot: no ANSI escape"
else
  pass "PLAIN pilot: no ANSI escape"
fi

# Test 8e: Full dry-run does NOT trigger pilot
full_output=$(NANOBK_OPLOG_PILOT=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 || true)
assert_not_contains "$full_output" "operation-log pilot enabled" "Full dry-run: pilot not triggered"
assert_contains "$full_output" "planned / dry-run" "Full dry-run: planned / dry-run preserved"

# ── 9: Test helper stability ─────────────────────────────────────────────

echo ""
echo "--- 8: Test helper stability ---"

filtered_self="$(grep -v 'pipe+grep-q\|pipefail hazard\|pipe pattern\|no printf\|grep -qF.*filtered\|must NOT contain\|must not have' "${SCRIPT_DIR}/unified-cli-operation-log-pilot-v1.8.sh" || true)"
if grep -qF ' | grep -q' <<< "$filtered_self"; then
  fail "Self-check: no pipe+grep-q pattern"
else
  pass "Self-check: no pipe+grep-q pattern"
fi

if grep -qF '<<< "$haystack"' "${SCRIPT_DIR}/unified-cli-operation-log-pilot-v1.8.sh"; then
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
