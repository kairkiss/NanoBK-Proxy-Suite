#!/usr/bin/env bash
# v2.6.4 Controlled Certificate Issue Productization Test
#
# Validates the productized certificate issue wrapper with fake issue hooks.
# Default tests do not run real certificate requests.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_cert_issue.py"
PHRASE="I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"

TIMEOUT_BIN_DIR="$(mktemp -d)"
cat > "$TIMEOUT_BIN_DIR/timeout" <<'PY'
#!/usr/bin/env python3
import subprocess
import sys

if len(sys.argv) < 3:
    sys.exit(125)

try:
    seconds = float(sys.argv[1])
except ValueError:
    sys.exit(125)

try:
    completed = subprocess.run(sys.argv[2:], timeout=seconds)
except subprocess.TimeoutExpired:
    sys.exit(124)
except KeyboardInterrupt:
    sys.exit(130)

sys.exit(completed.returncode)
PY
chmod +x "$TIMEOUT_BIN_DIR/timeout"
export PATH="$TIMEOUT_BIN_DIR:$PATH"

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

clean_nanobk_fake_env() {
  unset NANOBK_FAKE_SELECTED_DOMAIN || true
  unset NANOBK_FAKE_CF_CONNECTED || true
  unset NANOBK_FAKE_WORKER_SOURCE || true
  unset NANOBK_FAKE_WRANGLER || true
  unset NANOBK_FAKE_WORKER_DEPLOY || true
  unset NANOBK_ALLOW_REAL_WORKER_DEPLOY || true
  unset NANOBK_FAKE_VPS_IPV4 || true
  unset NANOBK_FAKE_VPS_IPV6 || true
  unset NANOBK_FAKE_DNS_EXISTING || true
  unset NANOBK_FAKE_DNS_CREATE || true
  unset NANOBK_ALLOW_REAL_CF_DNS_APPLY || true
  unset NANOBK_FAKE_CERT_TARGETS || true
  unset NANOBK_FAKE_CERT_EXISTS || true
  unset NANOBK_FAKE_CERT_ISSUE || true
  unset NANOBK_ALLOW_REAL_CERT_ISSUE || true
  unset NANOBK_CERT_ISSUE_FAKE_RUN || true
  unset NANOBK_CERT_ISSUE_FAKE_RESULT || true
  unset NANOBK_FAKE_VPS_INSTALL_STATE || true
  unset NANOBK_FAKE_VPS_PROFILE_COMPLETE || true
  unset NANOBK_FAKE_VPS_SERVICES_ACTIVE || true
  unset NANOBK_FAKE_VPS_HEALTHCHECK || true
  unset NANOBK_FAKE_VPS_INSTALL || true
  unset NANOBK_FAKE_VPS_RENDER_CHECK || true
  unset NANOBK_FAKE_VPS_LEGACY_ADAPTER || true
  unset NANOBK_ALLOW_REAL_VPS_INSTALL || true
  unset NANOBK_VPS_CERT_MODE || true
  unset NANOBK_VPS_CERT_FILE || true
  unset NANOBK_VPS_KEY_FILE || true
  unset NANOBK_ALLOW_SELF_SIGNED_VPS_INSTALL || true
  unset NANOBK_ALLOW_NO_CERT_VPS_INSTALL || true
  unset NANOBK_VPS_OPEN_FIREWALL || true
}

run_clean_test() {
  env \
    -u NANOBK_FAKE_SELECTED_DOMAIN \
    -u NANOBK_FAKE_CF_CONNECTED \
    -u NANOBK_FAKE_WORKER_SOURCE \
    -u NANOBK_FAKE_WRANGLER \
    -u NANOBK_FAKE_WORKER_DEPLOY \
    -u NANOBK_ALLOW_REAL_WORKER_DEPLOY \
    -u NANOBK_FAKE_VPS_IPV4 \
    -u NANOBK_FAKE_VPS_IPV6 \
    -u NANOBK_FAKE_DNS_EXISTING \
    -u NANOBK_FAKE_DNS_CREATE \
    -u NANOBK_ALLOW_REAL_CF_DNS_APPLY \
    -u NANOBK_FAKE_CERT_TARGETS \
    -u NANOBK_FAKE_CERT_EXISTS \
    -u NANOBK_FAKE_CERT_ISSUE \
    -u NANOBK_ALLOW_REAL_CERT_ISSUE \
    -u NANOBK_CERT_ISSUE_FAKE_RUN \
    -u NANOBK_CERT_ISSUE_FAKE_RESULT \
    -u NANOBK_FAKE_VPS_INSTALL_STATE \
    -u NANOBK_FAKE_VPS_PROFILE_COMPLETE \
    -u NANOBK_FAKE_VPS_SERVICES_ACTIVE \
    -u NANOBK_FAKE_VPS_HEALTHCHECK \
    -u NANOBK_FAKE_VPS_INSTALL \
    -u NANOBK_FAKE_VPS_RENDER_CHECK \
    -u NANOBK_FAKE_VPS_LEGACY_ADAPTER \
    -u NANOBK_ALLOW_REAL_VPS_INSTALL \
    -u NANOBK_VPS_CERT_MODE \
    -u NANOBK_VPS_CERT_FILE \
    -u NANOBK_VPS_KEY_FILE \
    -u NANOBK_ALLOW_SELF_SIGNED_VPS_INSTALL \
    -u NANOBK_ALLOW_NO_CERT_VPS_INSTALL \
    -u NANOBK_VPS_OPEN_FIREWALL \
    NANOBK_TEST_SKIP_REGRESSION=1 \
    bash "$1"
}

assert_valid_json() {
  local label="$1" json="$2"
  if echo "$json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    ok "$label"
  else
    fail "$label"
  fi
}

assert_json() {
  local label="$1" json="$2" expr="$3" expected="$4"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print($expr)" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$actual" == "$expected" ]]; then
    ok "$label"
  else
    fail "$label (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$pattern"; then
    ok "$label"
  else
    fail "$label (missing: $pattern)"
  fi
}

assert_not_contains_ci() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qiE "$pattern"; then
    fail "$label (found: $pattern)"
  else
    ok "$label"
  fi
}

fake_cert_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_CF_CONNECTED=1 \
    NANOBK_FAKE_CERT_TARGETS=proxy,web \
    NANOBK_FAKE_CERT_EXISTS=0 \
    "$@"
}

fake_existing_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_CF_CONNECTED=1 \
    NANOBK_FAKE_CERT_TARGETS=proxy,web \
    NANOBK_FAKE_CERT_EXISTS=1 \
    "$@"
}

fake_issue_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_CF_CONNECTED=1 \
    NANOBK_FAKE_CERT_TARGETS=proxy,web \
    NANOBK_FAKE_CERT_EXISTS=0 \
    NANOBK_FAKE_CERT_ISSUE=1 \
    "$@"
}

clean_nanobk_fake_env

echo "=== A. Basic ==="

if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "1: py_compile lib/nanobk_production_cert_issue.py"
else
  fail "1: py_compile lib/nanobk_production_cert_issue.py"
fi

if "$NANOBK" setup production cert issue --dry-run >/tmp/v264-basic-dry.txt 2>&1; then
  ok "2: setup production cert issue --dry-run exits 0"
else
  if grep -q "暂时不能继续" /tmp/v264-basic-dry.txt; then
    ok "2: setup production cert issue --dry-run safe blocked"
  else
    fail "2: setup production cert issue --dry-run exits 0 or safe blocked"
  fi
fi

DRY_BLOCKED_JSON=$("$NANOBK" setup production cert issue --dry-run --json 2>&1 || true)
assert_valid_json "3: setup production cert issue --dry-run --json valid" "$DRY_BLOCKED_JSON"

if "$NANOBK" beginner production cert issue --dry-run >/tmp/v264-beginner-dry.txt 2>&1; then
  ok "4: beginner alias dry-run exits 0"
else
  if grep -q "暂时不能继续" /tmp/v264-beginner-dry.txt; then
    ok "4: beginner alias dry-run safe blocked"
  else
    fail "4: beginner alias dry-run exits 0 or safe blocked"
  fi
fi

HELP_OUT=$("$NANOBK" setup production --help 2>&1)
assert_contains "5: help contains cert issue" "cert issue" "$HELP_OUT"

echo ""
echo "=== B. Dry-run JSON ==="

assert_json "6: mode production_cert_issue_v2_6" "$DRY_BLOCKED_JSON" "d['mode']" "production_cert_issue_v2_6"
assert_json "7: version 2.6.4" "$DRY_BLOCKED_JSON" "d['version']" "2.6.4"
assert_json "8: dry_run true" "$DRY_BLOCKED_JSON" "d['dry_run']" "True"
assert_json "9: mutation false" "$DRY_BLOCKED_JSON" "d['mutation']" "False"
assert_json "10: dangerous_actions_executed false" "$DRY_BLOCKED_JSON" "d['dangerous_actions_executed']" "False"
assert_json "11: safety read_only" "$DRY_BLOCKED_JSON" "d['safety']" "read_only"
assert_not_contains_ci "12: no private key" "private key|certificate private key" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "13: no cert key path" "cert key path|key_path|key-file|key_file" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "14: no raw cert PEM" "BEGIN CERTIFICATE|END CERTIFICATE" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "15: no raw certbot output" "raw certbot|certbot output" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "16: no zone_id" "zone_id" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "17: no record_id" "record_id" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "18: no api_env_path" "api_env_path" "$DRY_BLOCKED_JSON"

echo ""
echo "=== C. Confirm rejection ==="

if fake_cert_env "$NANOBK" setup production cert issue >/dev/null 2>&1; then fail "19: real issue without confirm RC non-zero"; else ok "19: real issue without confirm RC non-zero"; fi
if fake_cert_env "$NANOBK" setup production cert issue --confirm WRONG >/dev/null 2>&1; then fail "20: wrong confirm RC non-zero"; else ok "20: wrong confirm RC non-zero"; fi
if fake_cert_env "$NANOBK" setup production cert issue --confirm "$PHRASE" >/dev/null 2>&1; then fail "21: correct confirm but no env guard RC non-zero"; else ok "21: correct confirm but no env guard RC non-zero"; fi
if fake_cert_env "$NANOBK" setup production cert issue --yes >/dev/null 2>&1; then fail "22: --yes alone RC non-zero"; else ok "22: --yes alone RC non-zero"; fi
if fake_cert_env "$NANOBK" setup production cert issue --force >/dev/null 2>&1; then fail "23: --force RC non-zero"; else ok "23: --force RC non-zero"; fi
if fake_cert_env "$NANOBK" setup production cert issue --overwrite >/dev/null 2>&1; then fail "24: --overwrite RC non-zero"; else ok "24: --overwrite RC non-zero"; fi
if fake_cert_env "$NANOBK" setup production cert issue --delete >/dev/null 2>&1; then fail "25: --delete RC non-zero"; else ok "25: --delete RC non-zero"; fi
if fake_cert_env "$NANOBK" setup production cert issue --update >/dev/null 2>&1; then fail "26: --update RC non-zero"; else ok "26: --update RC non-zero"; fi
if fake_cert_env "$NANOBK" setup production cert issue --renew-force >/dev/null 2>&1; then fail "27: --renew-force RC non-zero"; else ok "27: --renew-force RC non-zero"; fi

echo ""
echo "=== D. Fake dry run success ==="

FAKE_DRY_JSON=$(fake_cert_env "$NANOBK" setup production cert issue --dry-run --json 2>&1)
FAKE_DRY_RC=$?
if [[ "$FAKE_DRY_RC" -eq 0 ]]; then ok "28: dry-run RC=0"; else fail "28: dry-run RC=0"; fi
assert_contains "29: planned proxy.example.com" "proxy.example.com" "$FAKE_DRY_JSON"
assert_contains "30: planned web.example.com" "web.example.com" "$FAKE_DRY_JSON"
assert_json "31: mutation false" "$FAKE_DRY_JSON" "d['mutation']" "False"
assert_json "32: dangerous false" "$FAKE_DRY_JSON" "d['dangerous_actions_executed']" "False"
assert_json "33: next_step confirm_cert_issue" "$FAKE_DRY_JSON" "d['next_step']" "confirm_cert_issue"
clean_nanobk_fake_env

echo ""
echo "=== E. Fake existing cert ==="

EXISTING_JSON=$(fake_existing_env "$NANOBK" setup production cert issue --dry-run --json 2>&1)
EXISTING_RC=$?
if [[ "$EXISTING_RC" -eq 0 ]]; then ok "34: dry-run RC=0"; else fail "34: dry-run RC=0"; fi
assert_json "35: existing_certificate true" "$EXISTING_JSON" "d['existing_certificate']" "True"
assert_json "36: mutation false" "$EXISTING_JSON" "d['mutation']" "False"
assert_json "37: dangerous false" "$EXISTING_JSON" "d['dangerous_actions_executed']" "False"
assert_json "38: next_step setup_vps" "$EXISTING_JSON" "d['next_step']" "setup_vps"
clean_nanobk_fake_env

echo ""
echo "=== F. Fake issue success ==="

ISSUE_JSON=$(fake_issue_env "$NANOBK" setup production cert issue --confirm "$PHRASE" --json 2>&1)
ISSUE_RC=$?
if [[ "$ISSUE_RC" -eq 0 ]]; then ok "39: fake issue RC=0"; else fail "39: fake issue RC=0"; fi
assert_json "40: mutation true" "$ISSUE_JSON" "d['mutation']" "True"
assert_json "41: dangerous_actions_executed true" "$ISSUE_JSON" "d['dangerous_actions_executed']" "True"
assert_json "42: confirmed true" "$ISSUE_JSON" "d['confirmed']" "True"
assert_contains "43: issued proxy.example.com" "proxy.example.com" "$ISSUE_JSON"
assert_contains "44: issued web.example.com" "web.example.com" "$ISSUE_JSON"
assert_json "45: next_step setup_vps" "$ISSUE_JSON" "d['next_step']" "setup_vps"
assert_not_contains_ci "46: no raw secret output" "CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|PRIVATE KEY|BEGIN PRIVATE KEY|Bearer|secret|token=" "$ISSUE_JSON"
clean_nanobk_fake_env

echo ""
echo "=== G. Missing dependency blocks ==="

TMP_HOME="$(mktemp -d)"
NO_DOMAIN_JSON=$(HOME="$TMP_HOME" "$NANOBK" setup production cert issue --dry-run --json 2>&1 || true)
assert_json "47: no selected domain blocks" "$NO_DOMAIN_JSON" "d['next_step']" "select_domain"

NO_CF_JSON=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_CF_CONNECTED=0 NANOBK_FAKE_CERT_TARGETS=proxy,web "$NANOBK" setup production cert issue --dry-run --json 2>&1 || true)
assert_json "48: no Cloudflare connection blocks" "$NO_CF_JSON" "d['next_step']" "setup_cloudflare"

BAD_TARGET_JSON=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_CF_CONNECTED=1 NANOBK_FAKE_CERT_TARGETS='bad.name' "$NANOBK" setup production cert issue --dry-run --json 2>&1 || true)
assert_json "49: invalid cert target blocks" "$BAD_TARGET_JSON" "d['next_step']" "cert_targets"
clean_nanobk_fake_env

echo ""
echo "=== H. Guarded real refusal ==="

GUARDED_JSON=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_CF_CONNECTED=1 NANOBK_FAKE_CERT_TARGETS=proxy,web NANOBK_ALLOW_REAL_CERT_ISSUE=1 "$NANOBK" setup production cert issue --confirm "$PHRASE" --json 2>&1 || true)
if env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_CF_CONNECTED=1 NANOBK_FAKE_CERT_TARGETS=proxy,web NANOBK_ALLOW_REAL_CERT_ISSUE=1 "$NANOBK" setup production cert issue --confirm "$PHRASE" >/dev/null 2>&1; then fail "50: RC non-zero"; else ok "50: RC non-zero"; fi
assert_json "51: mutation false" "$GUARDED_JSON" "d['mutation']" "False"
assert_json "52: dangerous false" "$GUARDED_JSON" "d['dangerous_actions_executed']" "False"
assert_contains "53: safe refusal" "当前不会申请证书" "$GUARDED_JSON"
clean_nanobk_fake_env

echo ""
echo "=== I. HARD_GREP ==="

OUT="/tmp/v264-cert-output.txt"
: > "$OUT"
printf '%s\n' "$DRY_BLOCKED_JSON" "$FAKE_DRY_JSON" "$EXISTING_JSON" "$ISSUE_JSON" "$NO_DOMAIN_JSON" "$NO_CF_JSON" "$BAD_TARGET_JSON" "$GUARDED_JSON" >> "$OUT"
fake_cert_env "$NANOBK" setup production cert issue --dry-run >> "$OUT" 2>&1 || true
fake_cert_env "$NANOBK" setup production cert issue --confirm WRONG >> "$OUT" 2>&1 || true

assert_not_contains_ci "54: no CF_API_TOKEN" "CF_API_TOKEN" "$(cat "$OUT")"
assert_not_contains_ci "55: no ADMIN_TOKEN" "ADMIN_TOKEN" "$(cat "$OUT")"
assert_not_contains_ci "56: no SUB_TOKEN" "SUB_TOKEN" "$(cat "$OUT")"
assert_not_contains_ci "57: no PRIVATE KEY" "PRIVATE KEY" "$(cat "$OUT")"
assert_not_contains_ci "58: no BEGIN PRIVATE KEY" "BEGIN PRIVATE KEY" "$(cat "$OUT")"
assert_not_contains_ci "59: no cert key path" "cert key path|key_path|key-file|key_file" "$(cat "$OUT")"
assert_not_contains_ci "60: no raw cert PEM" "BEGIN CERTIFICATE|END CERTIFICATE" "$(cat "$OUT")"
assert_not_contains_ci "61: no raw certbot output" "raw certbot|certbot output" "$(cat "$OUT")"
assert_not_contains_ci "62: no subscription URL" "subscription URL" "$(cat "$OUT")"
assert_not_contains_ci "63: no admin URL" "admin URL" "$(cat "$OUT")"
assert_not_contains_ci "64: no workers.dev secret token" "workers\\.dev.*token|workers\\.dev.*secret" "$(cat "$OUT")"
assert_not_contains_ci "65: no zone_id" "zone_id" "$(cat "$OUT")"
assert_not_contains_ci "66: no record_id" "record_id" "$(cat "$OUT")"
assert_not_contains_ci "67: no api_env_path" "api_env_path" "$(cat "$OUT")"
assert_not_contains_ci "68: no raw Cloudflare" "raw Cloudflare|api\\.cloudflare\\.com/client/v4" "$(cat "$OUT")"

echo ""
echo "=== J. Source safety ==="

SOURCE_TEXT="$(sed '/^[[:space:]]*#/d' "$MODULE")"
assert_not_contains_ci "69: default path no certbot execution" "certbot" "$SOURCE_TEXT"
assert_not_contains_ci "70: default path no acme.sh execution" "acme\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "71: no wrangler deploy" "wrangler.*deploy" "$SOURCE_TEXT"
assert_not_contains_ci "72: no rotate-keys.sh" "rotate-keys\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "73: no install-vps.sh" "install-vps\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "74: no systemctl restart/reload" "systemctl[[:space:]].*(restart|reload)" "$SOURCE_TEXT"
assert_not_contains_ci "75: no Cloudflare PATCH/DELETE" "method=[\"'](PATCH|DELETE)[\"']" "$SOURCE_TEXT"
if env | grep -q '^NANOBK_ALLOW_REAL_CERT_ISSUE=1$'; then fail "76: default tests do not set NANOBK_ALLOW_REAL_CERT_ISSUE"; else ok "76: default tests do not set NANOBK_ALLOW_REAL_CERT_ISSUE"; fi

echo ""
echo "=== K. Regression ==="

if [[ "${NANOBK_TEST_SKIP_REGRESSION:-1}" == "1" ]]; then
  ok "77: regression skipped by NANOBK_TEST_SKIP_REGRESSION"
else
  if run_clean_test "$REPO_DIR/tests/v2.6.3-controlled-worker-deploy.sh" >/dev/null 2>&1; then ok "77: v2.6.3 Worker deploy test passes"; else fail "77: v2.6.3 Worker deploy test passes"; fi
  if run_clean_test "$REPO_DIR/tests/v2.6.2-controlled-dns-apply.sh" >/dev/null 2>&1; then ok "78: v2.6.2 DNS apply test passes"; else fail "78: v2.6.2 DNS apply test passes"; fi
  if run_clean_test "$REPO_DIR/tests/v2.6.1-cloudflare-domain-selection.sh" >/dev/null 2>&1; then ok "79: v2.6.1 domain selection test passes"; else fail "79: v2.6.1 domain selection test passes"; fi
  if run_clean_test "$REPO_DIR/tests/v2.6.0-controlled-execution-contract.sh" >/dev/null 2>&1; then ok "80: v2.6.0 execution contract test passes"; else fail "80: v2.6.0 execution contract test passes"; fi
  if run_clean_test "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/dev/null 2>&1; then ok "81: v2.5.11 closeout test passes"; else fail "81: v2.5.11 closeout test passes"; fi
  if run_clean_test "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/dev/null 2>&1; then ok "82: v2.4.5 friendly gate wrappers test passes"; else fail "82: v2.4.5 friendly gate wrappers test passes"; fi
fi

echo ""
echo "Manual real certificate guard (not run by this test):"
echo "  NANOBK_ALLOW_REAL_CERT_ISSUE=1 bin/nanobk setup production cert issue --confirm \"$PHRASE\""

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
