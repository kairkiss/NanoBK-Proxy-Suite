#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.42 Status JSON Sanitized Fixture Test
#
# Validates the sanitized status JSON fixture for JSON validity,
# redaction policy, operation-log capture, hidden output, verbose,
# PLAIN/UI=0/CI boundaries, and failure propagation.
#
# Does NOT run real bin/nanobk --json status.
#
# Usage:
#   bash tests/unified-cli-status-json-sanitized-fixture-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

trap cleanup_temp EXIT

FIXTURE="${REPO_DIR}/tests/fixtures/status-json-sanitized-v1.8.json"

echo ""
echo "=== Test Suite: v1.8.42 Status JSON Sanitized Fixture ==="

# ── Test 1: fixture exists ────────────────────────────────────────────────

echo ""
echo "--- 1: fixture exists ---"

if [[ -f "$FIXTURE" ]]; then
  pass "1a: fixture file exists"
else
  fail "1a: fixture file not found: $FIXTURE"
fi

# ── Test 2: raw fixture JSON valid ────────────────────────────────────────

echo ""
echo "--- 2: raw fixture JSON valid ---"

if [[ -f "$FIXTURE" ]]; then
  json_errors=$(python3 -c "import json; json.load(open('$FIXTURE'))" 2>&1) && json_rc=0 || json_rc=$?
  if [[ "$json_rc" -eq 0 ]]; then
    pass "2a: fixture is valid JSON"
  else
    fail "2a: fixture is NOT valid JSON: $json_errors"
  fi

  # Check top-level keys
  fixture_content=$(cat "$FIXTURE")
  assert_contains "$fixture_content" '"ok"' "2b: has 'ok' field"
  assert_contains "$fixture_content" '"profile"' "2c: has 'profile' field"
  assert_contains "$fixture_content" '"services"' "2d: has 'services' field"
  assert_contains "$fixture_content" '"cloudflare"' "2e: has 'cloudflare' field"
  assert_contains "$fixture_content" '"warnings"' "2f: has 'warnings' field"
fi

# ── Test 3: fixture contains expected sanitized placeholders ──────────────

echo ""
echo "--- 3: fixture contains expected sanitized placeholders ---"

if [[ -f "$FIXTURE" ]]; then
  assert_contains "$fixture_content" "[REDACTED_IP]" "3a: has [REDACTED_IP]"
  assert_contains "$fixture_content" "[REDACTED_DOMAIN]" "3b: has [REDACTED_DOMAIN]"
  assert_contains "$fixture_content" "[REDACTED_URL]" "3c: has [REDACTED_URL]"
  assert_contains "$fixture_content" "[REDACTED_FINGERPRINT]" "3d: has [REDACTED_FINGERPRINT]"
fi

# ── Test 4: fixture forbidden pattern checks ─────────────────────────────

echo ""
echo "--- 4: fixture forbidden pattern checks ---"

if [[ -f "$FIXTURE" ]]; then
  forbidden_patterns=(
    "TOKEN="
    "SECRET="
    "ADMIN_TOKEN"
    "SUB_TOKEN"
    "NANOB_TOKEN"
    "workers.dev"
    "pages.dev"
    "http://"
    "https://"
    "/etc/nanobk"
    "/root/"
    "sha256:"
  )

  for pat in "${forbidden_patterns[@]}"; do
    if grep -Fq "$pat" "$FIXTURE"; then
      fail "4: fixture must NOT contain '$pat'"
    else
      pass "4: fixture does not contain '$pat'"
    fi
  done

  # IPv4 pattern: ([0-9]{1,3}\.){3}[0-9]{1,3}
  if grep -qE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$FIXTURE"; then
    fail "4: fixture must NOT contain raw IPv4 pattern"
  else
    pass "4: fixture does not contain raw IPv4 pattern"
  fi
fi

# ── Test 5: operation-log hidden capture ──────────────────────────────────

echo ""
echo "--- 5: operation-log hidden capture ---"

if [[ -f "$FIXTURE" ]]; then
  # Reset oplog state for clean test
  _NANOBK_OPLOG_LOADED=""
  _oplog_current_file=""
  _oplog_dir=""

  tmpdir5=$(mktemp -d)
  register_cleanup "$tmpdir5"

  export NANOBK_OPLOG_DIR="$tmpdir5"
  export NANOBK_VERBOSE=""
  export NANOBK_PLAIN=""
  export NANOBK_UI=""
  unset CI || true
  unset NO_COLOR || true

  # Source operation-log fresh
  source "${REPO_DIR}/installer/lib/operation-log.sh"

  oplog_init "status-json-fixture" >/dev/null

  # Capture screen output from oplog_run_hidden
  screen_output=$(oplog_run_hidden "status json sanitized fixture" cat "$FIXTURE" 2>&1) && hidden_rc=0 || hidden_rc=$?

  log_file="$_oplog_current_file"

  # Default mode: screen should NOT contain JSON content
  assert_not_contains "$screen_output" '"ok"' "5a: screen does not contain 'ok'"
  assert_not_contains "$screen_output" '"cloudflare"' "5b: screen does not contain 'cloudflare'"
  assert_not_contains "$screen_output" "[REDACTED_IP]" "5c: screen does not contain [REDACTED_IP]"

  # Log file should exist
  if [[ -f "$log_file" ]]; then
    pass "5d: log file exists"
  else
    fail "5d: log file not found: $log_file"
  fi

  # Log file should have restrictive permissions
  if [[ -f "$log_file" ]]; then
    log_perms=$(stat -f '%Lp' "$log_file" 2>/dev/null || stat -c '%a' "$log_file" 2>/dev/null || echo "unknown")
    if [[ "$log_perms" == "600" ]]; then
      pass "5e: log file has chmod 600"
    else
      fail "5e: log file permissions are $log_perms, expected 600"
    fi
  fi

  # Log file should contain JSON content
  if [[ -f "$log_file" ]]; then
    if grep -Fq '"ok"' "$log_file"; then
      pass "5f: log file contains JSON content"
    else
      fail "5f: log file does NOT contain JSON content"
    fi

    # Extract JSON block from log (skip header lines starting with #)
    log_json_block=$(awk '/^\{/{found=1} found{print} /^\}/{if(found)exit}' "$log_file")
    if [[ -n "$log_json_block" ]]; then
      echo "$log_json_block" | python3 -m json.tool > /dev/null 2>&1 && log_json_valid=0 || log_json_valid=$?
      if [[ "$log_json_valid" -eq 0 ]]; then
        pass "5g: log contains valid JSON"
      else
        fail "5g: log JSON block is NOT valid JSON"
      fi

      # Check log JSON for forbidden patterns
      for pat in "${forbidden_patterns[@]}"; do
        if grep -Fq "$pat" <<< "$log_json_block"; then
          fail "5: log JSON must NOT contain '$pat'"
        else
          pass "5: log JSON does not contain '$pat'"
        fi
      done

      # Check log JSON for placeholders
      if grep -Fq "[REDACTED_IP]" <<< "$log_json_block"; then
        pass "5h: log JSON contains [REDACTED_IP]"
      else
        fail "5h: log JSON missing [REDACTED_IP]"
      fi
    else
      fail "5g: could not extract JSON block from log"
    fi
  fi
fi

# ── Test 6: verbose mode ─────────────────────────────────────────────────

echo ""
echo "--- 6: verbose mode ---"

if [[ -f "$FIXTURE" ]]; then
  # Reset oplog state
  _NANOBK_OPLOG_LOADED=""
  _oplog_current_file=""
  _oplog_dir=""

  tmpdir6=$(mktemp -d)
  register_cleanup "$tmpdir6"

  export NANOBK_OPLOG_DIR="$tmpdir6"
  export NANOBK_VERBOSE=1
  export NANOBK_PLAIN=""
  export NANOBK_UI=""
  unset CI || true
  unset NO_COLOR || true

  source "${REPO_DIR}/installer/lib/operation-log.sh"

  oplog_init "status-json-fixture-verbose" >/dev/null

  verbose_screen=$(oplog_run_hidden "status json verbose fixture" cat "$FIXTURE" 2>&1) && verbose_rc=0 || verbose_rc=$?

  # Verbose: screen SHOULD contain JSON content
  assert_contains "$verbose_screen" '"ok"' "6a: verbose screen contains 'ok'"
  assert_contains "$verbose_screen" '"cloudflare"' "6b: verbose screen contains 'cloudflare'"
  assert_contains "$verbose_screen" "[REDACTED_IP]" "6c: verbose screen contains [REDACTED_IP]"

  # Verbose screen should NOT contain forbidden patterns
  assert_not_contains "$verbose_screen" "TOKEN=" "6d: verbose screen no TOKEN="
  assert_not_contains "$verbose_screen" "SECRET=" "6e: verbose screen no SECRET="

  # Log should still be valid JSON
  log_file6="$_oplog_current_file"
  if [[ -f "$log_file6" ]]; then
    log_json_block6=$(awk '/^\{/{found=1} found{print} /^\}/{if(found)exit}' "$log_file6")
    if [[ -n "$log_json_block6" ]]; then
      echo "$log_json_block6" | python3 -m json.tool > /dev/null 2>&1 && log6_valid=0 || log6_valid=$?
      if [[ "$log6_valid" -eq 0 ]]; then
        pass "6f: verbose log contains valid JSON"
      else
        fail "6f: verbose log JSON is NOT valid"
      fi
    fi
  fi

  # Reset verbose
  export NANOBK_VERBOSE=""
fi

# ── Test 7: PLAIN / UI=0 / CI no ANSI ───────────────────────────────────

echo ""
echo "--- 7: PLAIN / UI=0 / CI no ANSI ---"

if [[ -f "$FIXTURE" ]]; then
  for mode_label in "NANOBK_PLAIN=1" "NANOBK_UI=0" "CI=1"; do
    # Reset oplog state
    _NANOBK_OPLOG_LOADED=""
    _oplog_current_file=""
    _oplog_dir=""

    tmpdir7=$(mktemp -d)
    register_cleanup "$tmpdir7"

    export NANOBK_OPLOG_DIR="$tmpdir7"
    export NANOBK_VERBOSE=""
    export NANOBK_PLAIN=""
    export NANOBK_UI=""
    unset CI || true
    unset NO_COLOR || true

    # Set the specific mode
    eval "export $mode_label"

    source "${REPO_DIR}/installer/lib/operation-log.sh"

    oplog_init "status-json-fixture-${mode_label%%=*}" >/dev/null

    mode_screen=$(oplog_run_hidden "status json mode fixture" cat "$FIXTURE" 2>&1) && mode_rc=0 || mode_rc=$?

    # No ANSI escape sequences in output
    if has_ansi "$mode_screen"; then
      fail "7: $mode_label screen must NOT contain ANSI escapes"
    else
      pass "7: $mode_label screen has no ANSI escapes"
    fi

    # Log exists and is valid JSON
    log_file7="$_oplog_current_file"
    if [[ -f "$log_file7" ]]; then
      pass "7: $mode_label log exists"
    else
      fail "7: $mode_label log not found"
    fi

    if [[ -f "$log_file7" ]]; then
      log_json_block7=$(awk '/^\{/{found=1} found{print} /^\}/{if(found)exit}' "$log_file7")
      if [[ -n "$log_json_block7" ]]; then
        echo "$log_json_block7" | python3 -m json.tool > /dev/null 2>&1 && log7_valid=0 || log7_valid=$?
        if [[ "$log7_valid" -eq 0 ]]; then
          pass "7: $mode_label log contains valid JSON"
        else
          fail "7: $mode_label log JSON is NOT valid"
        fi

        # No forbidden patterns
        if grep -Fq "TOKEN=" <<< "$log_json_block7"; then
          fail "7: $mode_label log must NOT contain TOKEN="
        else
          pass "7: $mode_label log no TOKEN="
        fi
        if grep -Fq "SECRET=" <<< "$log_json_block7"; then
          fail "7: $mode_label log must NOT contain SECRET="
        else
          pass "7: $mode_label log no SECRET="
        fi
      fi
    fi

    # Reset for next iteration
    eval "unset ${mode_label%%=*}" 2>/dev/null || true
  done
fi

# ── Test 8: failure propagation ──────────────────────────────────────────

echo ""
echo "--- 8: failure propagation ---"

# Reset oplog state
_NANOBK_OPLOG_LOADED=""
_oplog_current_file=""
_oplog_dir=""

tmpdir8=$(mktemp -d)
register_cleanup "$tmpdir8"

export NANOBK_OPLOG_DIR="$tmpdir8"
export NANOBK_VERBOSE=""
export NANOBK_PLAIN=""
export NANOBK_UI=""
unset CI || true
unset NO_COLOR || true

source "${REPO_DIR}/installer/lib/operation-log.sh"

oplog_init "status-json-fixture-fail" >/dev/null

# Create a failing command that prints a fake secret
fail_script="$tmpdir8/fail_cmd.sh"
cat > "$fail_script" << 'FAILCMD'
#!/usr/bin/env bash
echo "SECRET=status-fixture-failure-secret"
echo "some failure output"
exit 12
FAILCMD
chmod +x "$fail_script"

fail_screen=$(oplog_run_hidden "failing fixture command" bash "$fail_script" 2>&1) && fail_rc=0 || fail_rc=$?

# Failure should propagate non-zero exit code
if [[ "$fail_rc" -ne 0 ]]; then
  pass "8a: failure propagates non-zero exit code (got $fail_rc)"
else
  fail "8a: failure must propagate non-zero exit code, got 0"
fi

# Screen should NOT contain raw secret
assert_not_contains "$fail_screen" "status-fixture-failure-secret" "8b: screen does not contain raw secret"

# Log should NOT contain raw secret
log_file8="$_oplog_current_file"
if [[ -f "$log_file8" ]]; then
  assert_not_contains "$(cat "$log_file8")" "status-fixture-failure-secret" "8c: log does not contain raw secret"

  # Log should contain REDACTED
  if grep -Fq "REDACTED" "$log_file8"; then
    pass "8d: log contains REDACTED"
  else
    fail "8d: log must contain REDACTED after redaction"
  fi

  # Failure should not be hidden (exit code should be in log)
  if grep -Fq "Exit code: 12" "$log_file8"; then
    pass "8e: log records failure exit code"
  else
    fail "8e: log must record failure exit code"
  fi
fi

# Exit code should be non-zero (no fake success)
if [[ "$fail_rc" -ne 0 ]]; then
  pass "8f: no fake success (rc=$fail_rc)"
else
  fail "8f: got fake success (rc=0)"
fi

# ── Test 9: do not run real status ───────────────────────────────────────

echo ""
echo "--- 9: do not run real status ---"

# Source code guard: this test must not enable the status pilot or execute real status.
# Read only the test body (before this guard section) to avoid self-referencing.
test_body=$(sed -n '1,/^# ── Test 9:/p' "$0")

# Check for status pilot enable (should never appear as assignment in test body)
if grep -qF 'NANOBK_OPLOG_STATUS_PILOT=1' <<< "$test_body"; then
  fail "9a: test must NOT enable NANOBK_OPLOG_STATUS_PILOT"
else
  pass "9a: test does not enable NANOBK_OPLOG_STATUS_PILOT"
fi

# Check for executable bin/nanobk --json status in test body (not comments or labels)
executable_lines=$(grep -n 'bin/nanobk.*--json.*status' <<< "$test_body" \
  | grep -v '^[0-9]*:[[:space:]]*#' \
  | grep -v 'assert_' \
  | grep -v 'echo' \
  | grep -v 'fail ' \
  | grep -v 'pass ' \
  || true)
if [[ -n "$executable_lines" ]]; then
  fail "9b: test must NOT execute bin/nanobk --json status"
else
  pass "9b: test does not execute bin/nanobk --json status"
fi

# ── Results ──────────────────────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED"
  exit 1
fi

echo "PASSED"
