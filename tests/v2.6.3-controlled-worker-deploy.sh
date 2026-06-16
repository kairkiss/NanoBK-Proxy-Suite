#!/usr/bin/env bash
# v2.6.3 Controlled Worker Deploy Productization Test
#
# Validates the productized Worker deploy wrapper with fake deploy hooks.
# Default tests do not run real Cloudflare Worker deployment.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_worker_deploy.py"
PHRASE="I UNDERSTAND NANOBK WILL DEPLOY CLOUDFLARE WORKERS"

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

fake_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_CF_CONNECTED=1 \
    NANOBK_FAKE_WORKER_SOURCE=1 \
    "$@"
}

fake_deploy_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_CF_CONNECTED=1 \
    NANOBK_FAKE_WORKER_SOURCE=1 \
    NANOBK_FAKE_WRANGLER=1 \
    NANOBK_FAKE_WORKER_DEPLOY=1 \
    "$@"
}

clean_nanobk_fake_env

echo "=== A. Basic ==="

if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "1: py_compile lib/nanobk_production_worker_deploy.py"
else
  fail "1: py_compile lib/nanobk_production_worker_deploy.py"
fi

if "$NANOBK" setup production worker deploy --dry-run >/tmp/v263-basic-dry.txt 2>&1; then
  ok "2: setup production worker deploy --dry-run exits 0"
else
  if grep -q "暂时不能继续" /tmp/v263-basic-dry.txt; then
    ok "2: setup production worker deploy --dry-run safe blocked"
  else
    fail "2: setup production worker deploy --dry-run exits 0 or safe blocked"
  fi
fi

DRY_BLOCKED_JSON=$("$NANOBK" setup production worker deploy --dry-run --json 2>&1 || true)
assert_valid_json "3: setup production worker deploy --dry-run --json valid" "$DRY_BLOCKED_JSON"

if "$NANOBK" beginner production worker deploy --dry-run >/tmp/v263-beginner-dry.txt 2>&1; then
  ok "4: beginner alias dry-run exits 0"
else
  if grep -q "暂时不能继续" /tmp/v263-beginner-dry.txt; then
    ok "4: beginner alias dry-run safe blocked"
  else
    fail "4: beginner alias dry-run exits 0 or safe blocked"
  fi
fi

HELP_OUT=$("$NANOBK" setup production --help 2>&1)
assert_contains "5: help contains worker deploy" "worker deploy" "$HELP_OUT"

echo ""
echo "=== B. Dry-run JSON ==="

assert_json "6: mode production_worker_deploy_v2_6" "$DRY_BLOCKED_JSON" "d['mode']" "production_worker_deploy_v2_6"
assert_json "7: version 2.6.3" "$DRY_BLOCKED_JSON" "d['version']" "2.6.3"
assert_json "8: dry_run true" "$DRY_BLOCKED_JSON" "d['dry_run']" "True"
assert_json "9: mutation false" "$DRY_BLOCKED_JSON" "d['mutation']" "False"
assert_json "10: dangerous_actions_executed false" "$DRY_BLOCKED_JSON" "d['dangerous_actions_executed']" "False"
assert_json "11: safety read_only" "$DRY_BLOCKED_JSON" "d['safety']" "read_only"
assert_not_contains_ci "12: no zone_id" "zone_id" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "13: no record_id" "record_id" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "14: no api_env_path" "api_env_path" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "15: no workers.dev secret URL" "workers\\.dev.*token|workers\\.dev.*secret" "$DRY_BLOCKED_JSON"

echo ""
echo "=== C. Confirm rejection ==="

if fake_env "$NANOBK" setup production worker deploy >/dev/null 2>&1; then fail "16: real deploy without confirm RC non-zero"; else ok "16: real deploy without confirm RC non-zero"; fi
if fake_env "$NANOBK" setup production worker deploy --confirm WRONG >/dev/null 2>&1; then fail "17: wrong confirm RC non-zero"; else ok "17: wrong confirm RC non-zero"; fi
if env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_CF_CONNECTED=1 NANOBK_FAKE_WORKER_SOURCE=1 NANOBK_FAKE_WRANGLER=1 "$NANOBK" setup production worker deploy --confirm "$PHRASE" >/dev/null 2>&1; then fail "18: correct confirm but no env guard RC non-zero"; else ok "18: correct confirm but no env guard RC non-zero"; fi
if fake_env "$NANOBK" setup production worker deploy --yes >/dev/null 2>&1; then fail "19: --yes alone RC non-zero"; else ok "19: --yes alone RC non-zero"; fi
if fake_env "$NANOBK" setup production worker deploy --force >/dev/null 2>&1; then fail "20: --force RC non-zero"; else ok "20: --force RC non-zero"; fi
if fake_env "$NANOBK" setup production worker deploy --overwrite >/dev/null 2>&1; then fail "21: --overwrite RC non-zero"; else ok "21: --overwrite RC non-zero"; fi
if fake_env "$NANOBK" setup production worker deploy --delete >/dev/null 2>&1; then fail "22: --delete RC non-zero"; else ok "22: --delete RC non-zero"; fi
if fake_env "$NANOBK" setup production worker deploy --update >/dev/null 2>&1; then fail "23: --update RC non-zero"; else ok "23: --update RC non-zero"; fi

echo ""
echo "=== D. Fake dry run success ==="

FAKE_DRY_JSON=$(fake_env "$NANOBK" setup production worker deploy --dry-run --json 2>&1)
FAKE_DRY_RC=$?
if [[ "$FAKE_DRY_RC" -eq 0 ]]; then ok "24: dry-run RC=0"; else fail "24: dry-run RC=0"; fi
assert_contains "25: planned nanok.example.com" "nanok.example.com" "$FAKE_DRY_JSON"
assert_contains "26: planned nanob.example.com" "nanob.example.com" "$FAKE_DRY_JSON"
assert_json "27: mutation false" "$FAKE_DRY_JSON" "d['mutation']" "False"
assert_json "28: dangerous false" "$FAKE_DRY_JSON" "d['dangerous_actions_executed']" "False"
clean_nanobk_fake_env

echo ""
echo "=== E. Fake deploy success ==="

CREATE_JSON=$(fake_deploy_env "$NANOBK" setup production worker deploy --confirm "$PHRASE" --json 2>&1)
CREATE_RC=$?
if [[ "$CREATE_RC" -eq 0 ]]; then ok "29: fake deploy RC=0"; else fail "29: fake deploy RC=0"; fi
assert_json "30: mutation true" "$CREATE_JSON" "d['mutation']" "True"
assert_json "31: dangerous_actions_executed true" "$CREATE_JSON" "d['dangerous_actions_executed']" "True"
assert_json "32: confirmed true" "$CREATE_JSON" "d['confirmed']" "True"
assert_contains "33: deployed nanok.example.com" "nanok.example.com" "$CREATE_JSON"
assert_contains "34: deployed nanob.example.com" "nanob.example.com" "$CREATE_JSON"
assert_json "35: next_step setup_cert" "$CREATE_JSON" "d['next_step']" "setup_cert"
assert_not_contains_ci "36: no raw secret output" "CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|PRIVATE KEY|BEGIN PRIVATE KEY|Bearer|secret|token=" "$CREATE_JSON"
clean_nanobk_fake_env

echo ""
echo "=== F. Missing dependency blocks ==="

NO_SOURCE_JSON=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_CF_CONNECTED=1 NANOBK_FAKE_WORKER_SOURCE=0 "$NANOBK" setup production worker deploy --dry-run --json 2>&1 || true)
assert_json "37: fake no Worker source blocks" "$NO_SOURCE_JSON" "d['blocked']" "True"

NO_TOOL_JSON=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_CF_CONNECTED=1 NANOBK_FAKE_WORKER_SOURCE=1 NANOBK_FAKE_WRANGLER=0 "$NANOBK" setup production worker deploy --confirm "$PHRASE" --json 2>&1 || true)
assert_json "38: fake no wrangler/tool blocks if real deploy attempted" "$NO_TOOL_JSON" "d['next_step']" "install_worker_tools"

clean_nanobk_fake_env
TMP_HOME="$(mktemp -d)"
NO_DOMAIN_JSON=$(HOME="$TMP_HOME" "$NANOBK" setup production worker deploy --dry-run --json 2>&1 || true)
assert_json "39: no selected domain blocks" "$NO_DOMAIN_JSON" "d['next_step']" "select_domain"

NO_CF_JSON=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_CF_CONNECTED=0 NANOBK_FAKE_WORKER_SOURCE=1 "$NANOBK" setup production worker deploy --dry-run --json 2>&1 || true)
assert_json "40: no Cloudflare connection blocks" "$NO_CF_JSON" "d['next_step']" "setup_cloudflare"
clean_nanobk_fake_env

echo ""
echo "=== G. HARD_GREP ==="

OUT="/tmp/v263-worker-output.txt"
: > "$OUT"
printf '%s\n' "$DRY_BLOCKED_JSON" "$FAKE_DRY_JSON" "$CREATE_JSON" "$NO_SOURCE_JSON" "$NO_TOOL_JSON" "$NO_DOMAIN_JSON" "$NO_CF_JSON" >> "$OUT"
fake_env "$NANOBK" setup production worker deploy --dry-run >> "$OUT" 2>&1 || true
fake_env "$NANOBK" setup production worker deploy --confirm WRONG >> "$OUT" 2>&1 || true

assert_not_contains_ci "41: no CF_API_TOKEN" "CF_API_TOKEN" "$(cat "$OUT")"
assert_not_contains_ci "42: no ADMIN_TOKEN" "ADMIN_TOKEN" "$(cat "$OUT")"
assert_not_contains_ci "43: no SUB_TOKEN" "SUB_TOKEN" "$(cat "$OUT")"
assert_not_contains_ci "44: no PRIVATE KEY" "PRIVATE KEY|BEGIN PRIVATE KEY" "$(cat "$OUT")"
assert_not_contains_ci "45: no subscription URL" "subscription URL" "$(cat "$OUT")"
assert_not_contains_ci "46: no admin URL" "admin URL" "$(cat "$OUT")"
assert_not_contains_ci "47: no workers.dev secret token" "workers\\.dev.*token|workers\\.dev.*secret" "$(cat "$OUT")"
assert_not_contains_ci "48: no zone_id" "zone_id" "$(cat "$OUT")"
assert_not_contains_ci "49: no record_id" "record_id" "$(cat "$OUT")"
assert_not_contains_ci "50: no api_env_path" "api_env_path" "$(cat "$OUT")"
assert_not_contains_ci "51: no raw Cloudflare" "raw Cloudflare|api\\.cloudflare\\.com/client/v4" "$(cat "$OUT")"
assert_not_contains_ci "52: no raw wrangler secret output" "wrangler.*secret|wrangler.*token|raw wrangler" "$(cat "$OUT")"

echo ""
echo "=== H. Source safety ==="

SOURCE_TEXT="$(sed '/^[[:space:]]*#/d' "$MODULE")"
assert_not_contains_ci "53: no certbot" "certbot" "$SOURCE_TEXT"
assert_not_contains_ci "54: no rotate-keys.sh" "rotate-keys\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "55: no install-vps.sh" "install-vps\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "56: no systemctl restart/reload" "systemctl[[:space:]].*(restart|reload)" "$SOURCE_TEXT"
assert_not_contains_ci "57: no DNS overwrite/delete/update" "overwrite_record|delete_record|update_record|method=[\"'](PUT|PATCH|DELETE)[\"']" "$SOURCE_TEXT"
if env | grep -q '^NANOBK_ALLOW_REAL_WORKER_DEPLOY=1$'; then fail "58: default tests do not set NANOBK_ALLOW_REAL_WORKER_DEPLOY"; else ok "58: default tests do not set NANOBK_ALLOW_REAL_WORKER_DEPLOY"; fi

echo ""
echo "=== I. Regression ==="

if [[ "${NANOBK_TEST_SKIP_REGRESSION:-1}" == "1" ]]; then
  ok "59: regression skipped by NANOBK_TEST_SKIP_REGRESSION"
else
  if run_clean_test "$REPO_DIR/tests/v2.6.2-controlled-dns-apply.sh" >/dev/null 2>&1; then ok "59: v2.6.2 DNS apply test passes"; else fail "59: v2.6.2 DNS apply test passes"; fi
  if run_clean_test "$REPO_DIR/tests/v2.6.1-cloudflare-domain-selection.sh" >/dev/null 2>&1; then ok "60: v2.6.1 domain selection test passes"; else fail "60: v2.6.1 domain selection test passes"; fi
  if run_clean_test "$REPO_DIR/tests/v2.6.0-controlled-execution-contract.sh" >/dev/null 2>&1; then ok "61: v2.6.0 execution contract test passes"; else fail "61: v2.6.0 execution contract test passes"; fi
  if run_clean_test "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/dev/null 2>&1; then ok "62: v2.5.11 closeout test passes"; else fail "62: v2.5.11 closeout test passes"; fi
  if run_clean_test "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/dev/null 2>&1; then ok "63: v2.4.5 friendly gate wrappers test passes"; else fail "63: v2.4.5 friendly gate wrappers test passes"; fi
fi

echo ""
echo "Manual real Worker deploy guard (not run by this test):"
echo "  NANOBK_ALLOW_REAL_WORKER_DEPLOY=1 bin/nanobk setup production worker deploy --confirm \"$PHRASE\""

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
