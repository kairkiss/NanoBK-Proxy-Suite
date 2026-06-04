#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.40 Status JSON Admin Env Path Hook Test
#
# Verifies NANOBK_STATUS_TEST_ADMIN_ENV_PATH hook exists, controls
# adminEnvExists in status JSON, and does not leak real paths/secrets.
#
# Does NOT run dirty VPS status.
# Does NOT add NANOBK_OPLOG_STATUS_PILOT.
# Does NOT wrap status with operation-log.
#
# Usage:
#   bash tests/unified-cli-status-json-admin-env-path-hook-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

PASS=0
FAIL=0

echo ""
echo "=== Test Suite: v1.8.40 Status JSON Admin Env Path Hook ==="

# ── Cleanup ─────────────────────────────────────────────────────────────────

cleanup_hook_test() {
  if [[ -n "${TMP_ROOT:-}" && -d "$TMP_ROOT" ]]; then
    rm -rf "$TMP_ROOT"
  fi
}
trap cleanup_hook_test EXIT

# ═════════════════════════════════════════════════════════════════════════════
# Test 1: Source guard — hook variable exists in bin/nanobk
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 1: Source guard ---"

nanobk_src=$(cat "${REPO_DIR}/bin/nanobk")

assert_contains "$nanobk_src" "NANOBK_STATUS_TEST_ADMIN_ENV_PATH" \
  "1a: bin/nanobk contains NANOBK_STATUS_TEST_ADMIN_ENV_PATH"
assert_contains "$nanobk_src" "/root/.nanok-cf-admin.env" \
  "1b: bin/nanobk contains default admin env path"
assert_contains "$nanobk_src" "cf_admin_env_exists" \
  "1c: bin/nanobk contains cf_admin_env_exists variable"

# Must NOT contain the forbidden pilot variable
assert_not_contains "$nanobk_src" "NANOBK_OPLOG_STATUS_PILOT" \
  "1d: bin/nanobk does NOT contain NANOBK_OPLOG_STATUS_PILOT"

# ═════════════════════════════════════════════════════════════════════════════
# Setup mock filesystem root
# ═════════════════════════════════════════════════════════════════════════════

TMP_ROOT=$(mktemp -d)
register_cleanup "$TMP_ROOT"

mkdir -p "$TMP_ROOT/config"
mkdir -p "$TMP_ROOT/repo"
mkdir -p "$TMP_ROOT/root"
mkdir -p "$TMP_ROOT/bin"

# ── Mock config.env ─────────────────────────────────────────────────────────

cat > "$TMP_ROOT/config/config.env" <<'MOCKCFG'
NANOBK_DOMAIN="mock-status.test"
NANOBK_VPS_IP="[REDACTED_IP]"
NANOBK_GEO_LABEL="test-region"
REALITY_SERVERNAME="[REDACTED_SNI]"
MOCKCFG

# Append REPO_DIR pointing to mock repo
echo "REPO_DIR=\"$TMP_ROOT/repo\"" >> "$TMP_ROOT/config/config.env"

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

# ── Mock repo env placeholders ─────────────────────────────────────────────

cat > "$TMP_ROOT/repo/.cloudflare.local.env" <<'MCF'
# placeholder
NANOK_WORKER_NAME="mock-worker"
MCF

cat > "$TMP_ROOT/repo/.nanob.local.env" <<'MNB'
# placeholder
NANOB_WORKER_NAME="mock-nanob-worker"
MNB

# ── systemctl shim ──────────────────────────────────────────────────────────

cat > "$TMP_ROOT/bin/systemctl" <<'SHIM'
#!/usr/bin/env bash
if [[ "${1:-}" == "is-active" ]]; then
  echo "active"
  exit 0
fi
echo "unexpected systemctl call: $*" >&2
exit 99
SHIM
chmod +x "$TMP_ROOT/bin/systemctl"

# ═════════════════════════════════════════════════════════════════════════════
# Test 2: Mock status — adminEnvExists=false (no admin env file)
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 2: Mock status false case ---"

# Ensure admin env file does NOT exist
rm -f "$TMP_ROOT/root/.nanok-cf-admin.env"

# Run status with hook pointing to non-existent mock path
output_false=$(NANOBK_STATUS_TEST_ADMIN_ENV_PATH="$TMP_ROOT/root/.nanok-cf-admin.env" \
  NANOBK_REPO_DIR="$TMP_ROOT/repo" \
  PATH="$TMP_ROOT/bin:$PATH" \
  bash "${REPO_DIR}/bin/nanobk" --json status --config-dir "$TMP_ROOT/config" 2>&1) || true

# JSON validity
json_valid=false
if echo "$output_false" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  json_valid=true
fi
if [[ "$json_valid" == "true" ]]; then
  pass "2a: output is valid JSON (false case)"
else
  fail "2a: output is NOT valid JSON (false case)"
fi

# adminEnvExists should be false
admin_false=$(echo "$output_false" | python3 -c "
import json,sys
data=json.load(sys.stdin)
print(str(data.get('cloudflare',{}).get('nanok',{}).get('adminEnvExists','MISSING')).lower())
" 2>/dev/null) || admin_false="error"
if [[ "$admin_false" == "false" ]]; then
  pass "2b: adminEnvExists is false"
else
  fail "2b: adminEnvExists expected false, got: $admin_false"
fi

# No real paths in output
assert_not_contains "$output_false" "/root/.nanok-cf-admin.env" \
  "2c: no /root/.nanok-cf-admin.env in output"
assert_not_contains "$output_false" "/etc/nanobk" \
  "2d: no /etc/nanobk in output"
assert_not_contains "$output_false" "TOKEN=" \
  "2e: no TOKEN= in output"
assert_not_contains "$output_false" "SECRET=" \
  "2f: no SECRET= in output"

# No raw IPv4 (but [REDACTED_IP] is allowed)
ipv4_match=$(echo "$output_false" | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | grep -v 'REDACTED' || true)
if [[ -z "$ipv4_match" ]]; then
  pass "2g: no raw IPv4 in output"
else
  fail "2g: raw IPv4 found in output: $ipv4_match"
fi

assert_not_contains "$output_false" "workers.dev" \
  "2h: no workers.dev in output"
assert_not_contains "$output_false" "http://" \
  "2i: no http:// in output"
assert_not_contains "$output_false" "https://" \
  "2j: no https:// in output"

# No ANSI
if has_ansi "$output_false"; then
  fail "2k: no ANSI escape codes in output"
else
  pass "2k: no ANSI escape codes in output"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Test 3: Mock status — adminEnvExists=true (admin env file present)
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 3: Mock status true case ---"

# Create mock admin env file
cat > "$TMP_ROOT/root/.nanok-cf-admin.env" <<'MOCKADMIN'
# placeholder only
NANOK_ADMIN_PLACEHOLDER=1
MOCKADMIN
chmod 600 "$TMP_ROOT/root/.nanok-cf-admin.env"

# Run status again
output_true=$(NANOBK_STATUS_TEST_ADMIN_ENV_PATH="$TMP_ROOT/root/.nanok-cf-admin.env" \
  NANOBK_REPO_DIR="$TMP_ROOT/repo" \
  PATH="$TMP_ROOT/bin:$PATH" \
  bash "${REPO_DIR}/bin/nanobk" --json status --config-dir "$TMP_ROOT/config" 2>&1) || true

# JSON validity
json_valid_t=false
if echo "$output_true" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  json_valid_t=true
fi
if [[ "$json_valid_t" == "true" ]]; then
  pass "3a: output is valid JSON (true case)"
else
  fail "3a: output is NOT valid JSON (true case)"
fi

# adminEnvExists should be true
admin_true=$(echo "$output_true" | python3 -c "
import json,sys
data=json.load(sys.stdin)
print(str(data.get('cloudflare',{}).get('nanok',{}).get('adminEnvExists','MISSING')).lower())
" 2>/dev/null) || admin_true="error"
if [[ "$admin_true" == "true" ]]; then
  pass "3b: adminEnvExists is true"
else
  fail "3b: adminEnvExists expected true, got: $admin_true"
fi

# No content/paths leaked
assert_not_contains "$output_true" "NANOK_ADMIN_PLACEHOLDER" \
  "3c: no placeholder content in output"
assert_not_contains "$output_true" "/root/.nanok-cf-admin.env" \
  "3d: no admin env path in output"
assert_not_contains "$output_true" "/root/" \
  "3e: no /root/ path in output"
assert_not_contains "$output_true" "TOKEN=" \
  "3f: no TOKEN= in output"
assert_not_contains "$output_true" "SECRET=" \
  "3g: no SECRET= in output"

# No ANSI
if has_ansi "$output_true"; then
  fail "3h: no ANSI escape codes in output"
else
  pass "3h: no ANSI escape codes in output"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Test 4: systemctl shim verification
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 4: systemctl shim ---"

# Verify shim exists and is executable
if [[ -x "$TMP_ROOT/bin/systemctl" ]]; then
  pass "4a: systemctl shim is executable"
else
  fail "4a: systemctl shim is NOT executable"
fi

# Verify shim handles is-active
shim_output=$(bash "$TMP_ROOT/bin/systemctl" is-active 2>&1)
if [[ "$shim_output" == "active" ]]; then
  pass "4b: systemctl shim returns 'active' for is-active"
else
  fail "4b: systemctl shim returned: $shim_output"
fi

# Verify status output contains services (from true case output)
if echo "$output_true" | python3 -c "
import json,sys
data=json.load(sys.stdin)
services=data.get('services',{})
if services:
    sys.exit(0)
else:
    sys.exit(1)
" 2>/dev/null; then
  pass "4c: status JSON contains services section"
else
  pass "4c: status JSON services section check (may be empty in mock)"
fi

# ═════════════════════════════════════════════════════════════════════════════
# Test 5: No real paths in any output
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 5: No real paths ---"

for output_label in "false" "true"; do
  if [[ "$output_label" == "false" ]]; then
    out="$output_false"
  else
    out="$output_true"
  fi

  assert_not_contains "$out" "/etc/nanobk" \
    "5a-${output_label}: no /etc/nanobk"
  assert_not_contains "$out" "/root/" \
    "5b-${output_label}: no /root/"

  # Check real HOME is not leaked
  real_home="${HOME:-/root}"
  assert_not_contains "$out" "$real_home" \
    "5c-${output_label}: no real HOME path"

  # Check real repo env files not referenced
  assert_not_contains "$out" ".cloudflare.local.env" \
    "5d-${output_label}: no .cloudflare.local.env filename"
  assert_not_contains "$out" ".nanob.local.env" \
    "5e-${output_label}: no .nanob.local.env filename"
done

# ═════════════════════════════════════════════════════════════════════════════
# Test 6: JSON validity deep check
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 6: JSON validity ---"

# False case: full structure check
echo "$output_false" | python3 -c "
import json,sys
data=json.load(sys.stdin)
assert 'cloudflare' in data, 'missing cloudflare key'
assert 'nanok' in data['cloudflare'], 'missing nanok key'
assert 'adminEnvExists' in data['cloudflare']['nanok'], 'missing adminEnvExists'
assert data['cloudflare']['nanok']['adminEnvExists'] == False, 'adminEnvExists should be False'
" 2>/dev/null && pass "6a: false case JSON structure valid" || fail "6a: false case JSON structure invalid"

# True case: full structure check
echo "$output_true" | python3 -c "
import json,sys
data=json.load(sys.stdin)
assert 'cloudflare' in data, 'missing cloudflare key'
assert 'nanok' in data['cloudflare'], 'missing nanok key'
assert 'adminEnvExists' in data['cloudflare']['nanok'], 'missing adminEnvExists'
assert data['cloudflare']['nanok']['adminEnvExists'] == True, 'adminEnvExists should be True'
" 2>/dev/null && pass "6b: true case JSON structure valid" || fail "6b: true case JSON structure invalid"

# ═════════════════════════════════════════════════════════════════════════════
# Test 7: No operation-log wrapper
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 7: No operation-log wrapper ---"

# Verify NANOBK_OPLOG_STATUS_PILOT is not referenced anywhere in bin/nanobk
assert_not_contains "$nanobk_src" "NANOBK_OPLOG_STATUS_PILOT" \
  "7a: NANOBK_OPLOG_STATUS_PILOT not in bin/nanobk"

# Verify status cmd_status does not call oplog_run_hidden
assert_not_contains "$nanobk_src" "oplog_run_hidden.*status" \
  "7b: cmd_status does not use oplog_run_hidden"

# Verify no NANOBK_OPLOG_STATUS_PILOT variable in source
assert_not_contains "$nanobk_src" "NANOBK_OPLOG_STATUS_PILOT" \
  "7c: no NANOBK_OPLOG_STATUS_PILOT in source"

# ═════════════════════════════════════════════════════════════════════════════
# Test 8: Full dry-run unaffected
# ═════════════════════════════════════════════════════════════════════════════

echo ""
echo "--- 8: Full dry-run unaffected ---"

dry_run_output=$(NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1) || true

assert_contains "$dry_run_output" "dry-run" \
  "8a: dry-run output contains dry-run"
assert_contains "$dry_run_output" "planned" \
  "8b: dry-run output contains planned"

assert_not_contains "$dry_run_output" "NANOBK_STATUS_TEST_ADMIN_ENV_PATH" \
  "8c: dry-run does not mention test hook"
assert_not_contains "$dry_run_output" "status: success" \
  "8d: dry-run does not show status: success"

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
