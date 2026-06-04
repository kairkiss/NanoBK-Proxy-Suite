#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.43 Status JSON Mock Filesystem Operation-Log Prototype
#
# Uses operation-log to capture mock filesystem bin/nanobk --json status output.
# Proves: default hidden, verbose sanitized, log JSON valid, PLAIN/UI=0/CI no ANSI,
# systemctl shim, failure propagation, no real paths/secrets.
#
# This is a TEST PROTOTYPE, not a production status wrapper.
# Does NOT add NANOBK_OPLOG_STATUS_PILOT.
# Does NOT run dirty VPS status.
#
# Usage:
#   bash tests/unified-cli-status-json-mock-oplog-prototype-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

PASS=0
FAIL=0

echo ""
echo "=== Test Suite: v1.8.43 Status JSON Mock Oplog Prototype ==="

# ── Forbidden patterns helper ─────────────────────────────────────────────

FORBIDDEN_PATTERNS=(
  "/root/"
  "/etc/nanobk"
  "workers.dev"
  "pages.dev"
  "http://"
  "https://"
  "TOKEN="
  "SECRET="
  "ADMIN_TOKEN"
  "SUB_TOKEN"
  "NANOB_TOKEN"
  "REALITY_PRIVATE_KEY"
)

assert_no_forbidden_status_patterns() {
  local text="$1"
  local label="$2"
  for pat in "${FORBIDDEN_PATTERNS[@]}"; do
    if grep -Fq "$pat" <<< "$text"; then
      fail "${label}: must NOT contain '${pat}'"
    else
      pass "${label}: does not contain '${pat}'"
    fi
  done
  # IPv4 pattern
  local ipv4_match
  ipv4_match=$(grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' <<< "$text" | grep -v 'REDACTED' || true)
  if [[ -z "$ipv4_match" ]]; then
    pass "${label}: no raw IPv4"
  else
    fail "${label}: raw IPv4 found: $ipv4_match"
  fi
  # Real HOME
  if [[ -n "${HOME:-}" ]]; then
    if grep -qF "$HOME" <<< "$text"; then
      fail "${label}: must NOT contain real HOME ($HOME)"
    else
      pass "${label}: does not contain real HOME"
    fi
  fi
}

# ── Cleanup ─────────────────────────────────────────────────────────────────

TMP_ROOT=""
cleanup_oplog_proto() {
  if [[ -n "$TMP_ROOT" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup_oplog_proto EXIT

# ═════════════════════════════════════════════════════════════════════════════
# Test 1: Source guard
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 1: Source guard ---"

nanobk_src=$(cat "${REPO_DIR}/bin/nanobk")

assert_contains "$nanobk_src" "NANOBK_STATUS_TEST_ADMIN_ENV_PATH" \
  "1a: bin/nanobk contains NANOBK_STATUS_TEST_ADMIN_ENV_PATH"
assert_not_contains "$nanobk_src" "NANOBK_OPLOG_STATUS_PILOT" \
  "1b: bin/nanobk does NOT contain NANOBK_OPLOG_STATUS_PILOT"

# Verify this test file uses relative path for nanobk in oplog runners
test_self_src=$(cat "$0")
assert_contains "$test_self_src" 'bash bin/nanobk' \
  "1c: runner uses relative bash bin/nanobk"
# Verify cd into repo dir before oplog calls
assert_contains "$test_self_src" 'cd "${REPO_DIR}"' \
  "1d: runner cds into REPO_DIR before oplog"

# ═════════════════════════════════════════════════════════════════════════════
# Setup mock filesystem
# ═════════════════════════════════════════════════════════════════════════════

TMP_ROOT=$(mktemp -d)
register_cleanup "$TMP_ROOT"

mkdir -p "$TMP_ROOT/config" "$TMP_ROOT/repo" "$TMP_ROOT/root" "$TMP_ROOT/bin" "$TMP_ROOT/logs"

# ── Mock config.env ─────────────────────────────────────────────────────────

cat > "$TMP_ROOT/config/config.env" <<MOCKCFG
NANOBK_DOMAIN="mock-status.test"
NANOBK_VPS_IP="[REDACTED_IP]"
NANOBK_GEO_LABEL="test-region"
REALITY_SERVERNAME="[REDACTED_SNI]"
REPO_DIR="$TMP_ROOT/repo"
MOCKCFG

# ── Mock profile.current.json ───────────────────────────────────────────────

cat > "$TMP_ROOT/config/profile.current.json" <<'MOCKPROF'
{
  "updatedAt": "2026-01-01T00:00:00Z",
  "hy2": {
    "port": 12345,
    "password": "[REDACTED_HY2]"
  },
  "tuic": {
    "port": 12346,
    "password": "[REDACTED_TUIC]"
  },
  "reality": {
    "port": 12347,
    "shortId": "[REDACTED_SHORT_ID]",
    "publicKey": "[REDACTED_PUBKEY]"
  },
  "trojan": {
    "port": 12348,
    "password": "[REDACTED_TROJAN]"
  }
}
MOCKPROF

# ── Mock secrets.private.env ────────────────────────────────────────────────

cat > "$TMP_ROOT/config/secrets.private.env" <<'MOCKSEC'
# placeholder only
NANOBK_SECRETS_PLACEHOLDER=1
MOCKSEC
chmod 600 "$TMP_ROOT/config/secrets.private.env"

# ── Mock repo env ───────────────────────────────────────────────────────────

cat > "$TMP_ROOT/repo/.cloudflare.local.env" <<'MCF'
NANOK_WORKER_NAME="mock-worker"
NANOBK_DEPLOY_STATUS="deployed"
NANOBK_PROFILE_UPLOAD_STATUS="uploaded"
NANOBK_VERIFY_STATUS="verified"
SUB_STORE_KV_NAMESPACE_ID="mock-kv"
MCF

cat > "$TMP_ROOT/repo/.nanob.local.env" <<'MNB'
NANOB_WORKER_NAME="mock-nanob-worker"
NANOB_DEPLOY_STATUS="deployed"
NANOB_VERIFY_STATUS="verified"
NANOB_GEO_KV_NAMESPACE_ID="mock-geo-kv"
EDGE_HOST="mock-edge"
MNB

# ── Mock admin env ──────────────────────────────────────────────────────────

cat > "$TMP_ROOT/root/.nanok-cf-admin.env" <<'MOCKADMIN'
# placeholder only
NANOK_ADMIN_PLACEHOLDER=1
MOCKADMIN
chmod 600 "$TMP_ROOT/root/.nanok-cf-admin.env"

# ── systemctl shim (with logging) ───────────────────────────────────────────

cat > "$TMP_ROOT/bin/systemctl" <<SHIM
#!/usr/bin/env bash
echo "systemctl shim called: \$*" >> "$TMP_ROOT/systemctl-called.log"
if [[ "\${1:-}" == "is-active" ]]; then
  echo "active"
  exit 0
fi
echo "unexpected systemctl call: \$*" >&2
exit 99
SHIM
chmod +x "$TMP_ROOT/bin/systemctl"

# ── Operation-log runner script ─────────────────────────────────────────────

cat > "$TMP_ROOT/run_status_oplog.sh" <<RUNNER
#!/usr/bin/env bash
set -Eeuo pipefail

cd "${REPO_DIR}"

source installer/lib/operation-log.sh

export NANOBK_OPLOG_DIR="$TMP_ROOT/logs"
export NANOBK_REPO_DIR="$TMP_ROOT/repo"
export NANOBK_STATUS_TEST_ADMIN_ENV_PATH="$TMP_ROOT/root/.nanok-cf-admin.env"
export PATH="$TMP_ROOT/bin:\$PATH"

oplog_init "status-json-mock" >/dev/null

echo "Log: \$_oplog_current_file"

oplog_run_hidden "status json mock filesystem" \\
  bash bin/nanobk --json status --config-dir "$TMP_ROOT/config"
RUNNER
chmod +x "$TMP_ROOT/run_status_oplog.sh"

# ── Failure runner script ───────────────────────────────────────────────────

cat > "$TMP_ROOT/run_status_fail.sh" <<FAILRUNNER
#!/usr/bin/env bash
set -Eeuo pipefail

cd "${REPO_DIR}"

source installer/lib/operation-log.sh

export NANOBK_OPLOG_DIR="$TMP_ROOT/logs"
export NANOBK_REPO_DIR="$TMP_ROOT/repo"
export NANOBK_STATUS_TEST_ADMIN_ENV_PATH="$TMP_ROOT/root/.nanok-cf-admin.env"
export PATH="$TMP_ROOT/bin:\$PATH"

oplog_init "status-json-mock-fail" >/dev/null

echo "Log: \$_oplog_current_file"

oplog_run_hidden "status json mock failure" \\
  bash -c 'echo SECRET=status-mock-oplog-failure-secret; exit 17'
FAILRUNNER
chmod +x "$TMP_ROOT/run_status_fail.sh"

# ═════════════════════════════════════════════════════════════════════════════
# Test 2: Default hidden output
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 2: Default hidden output ---"

screen_output=$(bash "$TMP_ROOT/run_status_oplog.sh" 2>&1) && screen_rc=0 || screen_rc=$?

assert_contains "$screen_output" "Log:" "2a: screen contains Log:"

assert_not_contains "$screen_output" '"ok"' "2b: screen does not contain ok"
assert_not_contains "$screen_output" '"cloudflare"' "2c: screen does not contain cloudflare"
assert_not_contains "$screen_output" "adminEnvExists" "2d: screen does not contain adminEnvExists"
assert_not_contains "$screen_output" "[REDACTED_IP]" "2e: screen does not contain [REDACTED_IP]"

assert_no_forbidden_status_patterns "$screen_output" "2f: screen forbidden patterns"

if [[ "$screen_rc" -eq 0 ]]; then
  pass "2g: exit code 0"
else
  fail "2g: expected exit code 0, got $screen_rc"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Test 3: Log file
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 3: Log file ---"

# Extract log path from screen output
log_path=$(echo "$screen_output" | sed -n 's/^Log: //p' | head -1 || true)

if [[ -n "$log_path" && -f "$log_path" ]]; then
  pass "3a: log file exists"
else
  fail "3a: log file not found (path: ${log_path:-<empty>})"
fi

if [[ -f "$log_path" ]]; then
  log_perms=$(stat -f '%Lp' "$log_path" 2>/dev/null || stat -c '%a' "$log_path" 2>/dev/null || echo "unknown")
  if [[ "$log_perms" == "600" ]]; then
    pass "3b: log file chmod 600"
  else
    fail "3b: log file permissions are $log_perms, expected 600"
  fi

  log_content=$(cat "$log_path")

  # Extract JSON block from log
  log_json_block=$(awk '/^\{/{found=1} found{print} /^\}/{if(found)exit}' "$log_path")

  if [[ -n "$log_json_block" ]]; then
    pass "3c: log contains JSON block"

    # JSON validity
    if echo "$log_json_block" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
      pass "3d: log JSON is valid"
    else
      fail "3d: log JSON is NOT valid"
    fi

    # Check expected fields
    assert_contains "$log_json_block" '"adminEnvExists": true' "3e: log has adminEnvExists true"
    assert_contains "$log_json_block" '"services"' "3f: log has services"
    assert_contains "$log_json_block" '"cloudflare"' "3g: log has cloudflare"

    # Forbidden patterns in JSON block
    assert_no_forbidden_status_patterns "$log_json_block" "3h: log JSON forbidden patterns"

    # No mock placeholder content leaked
    assert_not_contains "$log_json_block" "NANOK_ADMIN_PLACEHOLDER" \
      "3i: log JSON does not contain placeholder content"
    assert_not_contains "$log_json_block" "NANOBK_SECRETS_PLACEHOLDER" \
      "3j: log JSON does not contain secrets placeholder"
  else
    fail "3c: could not extract JSON block from log"
  fi

  # Full log forbidden patterns
  for pat in "${FORBIDDEN_PATTERNS[@]}"; do
    if grep -Fq "$pat" <<< "$log_content"; then
      fail "3k: full log must NOT contain '${pat}'"
    else
      pass "3k: full log does not contain '${pat}'"
    fi
  done
  # IPv4 in full log
  ipv4_log=$(grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' <<< "$log_content" | grep -v 'REDACTED' || true)
  if [[ -z "$ipv4_log" ]]; then
    pass "3k: full log no raw IPv4"
  else
    fail "3k: full log raw IPv4: $ipv4_log"
  fi
  # Real HOME in full log
  if [[ -n "${HOME:-}" ]]; then
    if grep -qF "$HOME" <<< "$log_content"; then
      fail "3l: full log must NOT contain real HOME ($HOME)"
    else
      pass "3l: full log does not contain real HOME"
    fi
  fi
  # Real repo absolute path in full log
  if grep -qF "$REPO_DIR" <<< "$log_content"; then
    fail "3m: full log must NOT contain real repo path ($REPO_DIR)"
  else
    pass "3m: full log does not contain real repo path"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# Test 4: Verbose mode
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 4: Verbose mode ---"

# Reset oplog state
unset _NANOBK_OPLOG_LOADED || true
_oplog_current_file=""

verbose_output=$(NANOBK_VERBOSE=1 bash "$TMP_ROOT/run_status_oplog.sh" 2>&1) && verbose_rc=0 || verbose_rc=$?

assert_contains "$verbose_output" '"ok"' "4a: verbose screen contains ok"
assert_contains "$verbose_output" '"cloudflare"' "4b: verbose screen contains cloudflare"
assert_contains "$verbose_output" "adminEnvExists" "4c: verbose screen contains adminEnvExists"

assert_no_forbidden_status_patterns "$verbose_output" "4d: verbose forbidden patterns"

if [[ "$verbose_rc" -eq 0 ]]; then
  pass "4e: verbose exit code 0"
else
  fail "4e: expected exit code 0, got $verbose_rc"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Test 5: PLAIN/UI=0/CI no ANSI
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 5: PLAIN/UI=0/CI no ANSI ---"

for mode_label in "NANOBK_PLAIN=1" "NANOBK_UI=0" "CI=1"; do
  # Reset oplog state
  unset _NANOBK_OPLOG_LOADED || true
  _oplog_current_file=""

  mode_output=$(eval "export $mode_label; bash '$TMP_ROOT/run_status_oplog.sh'" 2>&1) && mode_rc=0 || mode_rc=$?

  if has_ansi "$mode_output"; then
    fail "5-${mode_label}: no ANSI in screen output"
  else
    pass "5-${mode_label}: no ANSI in screen output"
  fi

  assert_contains "$mode_output" "Log:" "5-${mode_label}: contains Log:"

  # Extract log path and check JSON
  mode_log_path=$(echo "$mode_output" | sed -n 's/^Log: //p' | head -1 || true)
  if [[ -n "$mode_log_path" && -f "$mode_log_path" ]]; then
    pass "5-${mode_label}: log exists"
    mode_json=$(awk '/^\{/{found=1} found{print} /^\}/{if(found)exit}' "$mode_log_path")
    if [[ -n "$mode_json" ]] && echo "$mode_json" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
      pass "5-${mode_label}: log JSON valid"
    else
      fail "5-${mode_label}: log JSON invalid"
    fi
    assert_no_forbidden_status_patterns "$mode_json" "5-${mode_label}: log forbidden patterns"
  else
    fail "5-${mode_label}: log not found"
  fi
done

# ═════════════════════════════════════════════════════════════════════════════
# Test 6: systemctl shim proof
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 6: systemctl shim proof ---"

if [[ -f "$TMP_ROOT/systemctl-called.log" ]]; then
  pass "6a: systemctl-called.log exists"
  shim_log=$(cat "$TMP_ROOT/systemctl-called.log")
  if grep -q "is-active" <<< "$shim_log"; then
    pass "6b: shim log contains is-active"
  else
    fail "6b: shim log missing is-active"
  fi
else
  fail "6a: systemctl-called.log not found"
fi

# Check services are "active" in the log JSON
if [[ -n "${log_json_block:-}" ]]; then
  if grep -Fq '"active"' <<< "$log_json_block"; then
    pass "6c: services show active in JSON"
  else
    fail "6c: services do not show active in JSON"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
# Test 7: Failure propagation
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 7: Failure propagation ---"

# Reset oplog state
unset _NANOBK_OPLOG_LOADED || true
_oplog_current_file=""

fail_output=$(bash "$TMP_ROOT/run_status_fail.sh" 2>&1) && fail_rc=0 || fail_rc=$?

if [[ "$fail_rc" -ne 0 ]]; then
  pass "7a: failure propagates non-zero exit code (got $fail_rc)"
else
  fail "7a: expected non-zero exit code, got 0"
fi

# Screen should not contain raw secret
assert_not_contains "$fail_output" "status-mock-oplog-failure-secret" \
  "7b: screen does not contain raw secret"

# Extract fail log path
fail_log_path=$(echo "$fail_output" | sed -n 's/^Log: //p' | head -1 || true)
if [[ -n "$fail_log_path" && -f "$fail_log_path" ]]; then
  fail_log_content=$(cat "$fail_log_path")

  assert_not_contains "$fail_log_content" "status-mock-oplog-failure-secret" \
    "7c: log does not contain raw secret"
  assert_contains "$fail_log_content" "REDACTED" \
    "7d: log contains REDACTED"
  assert_contains "$fail_log_content" "Exit code: 17" \
    "7e: log contains Exit code 17"
else
  fail "7: failure log not found"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Test 8: Full dry-run unaffected
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 8: Full dry-run unaffected ---"

dry_run_output=$(NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1) || true

assert_contains "$dry_run_output" "dry-run" "8a: dry-run output contains dry-run"
assert_contains "$dry_run_output" "planned" "8b: dry-run output contains planned"
assert_not_contains "$dry_run_output" "NANOBK_STATUS_TEST_ADMIN_ENV_PATH" \
  "8c: dry-run does not mention test hook"
assert_not_contains "$dry_run_output" "NANOBK_OPLOG_STATUS_PILOT" \
  "8d: dry-run does not mention status pilot"
assert_not_contains "$dry_run_output" "status: success" \
  "8e: dry-run does not show status: success"

# ═════════════════════════════════════════════════════════════════════════════
# Results
# ═════════════════════════════════════════════════════════════════════════════

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
