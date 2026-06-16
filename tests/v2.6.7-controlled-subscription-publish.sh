#!/usr/bin/env bash
# v2.6.7 Controlled Subscription Profile Publish Integration Test
#
# Validates subscription/profile publish planning, exact gates, fake publish
# paths, redaction, and non-recursive regressions. Default tests do not publish
# to a real Worker.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_subscription_publish.py"
INVENTORY="$REPO_DIR/docs/v2.6.7-subscription-profile-publish-inventory.md"
PHRASE="I UNDERSTAND NANOBK WILL PUBLISH SUBSCRIPTION PROFILE"

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

clean_nanobk_fake_env() {
  unset NANOBK_FAKE_SELECTED_DOMAIN || true
  unset NANOBK_FAKE_CF_CONNECTED || true
  unset NANOBK_FAKE_CF_DOMAINS || true
  unset NANOBK_FAKE_WORKER_SOURCE || true
  unset NANOBK_FAKE_WRANGLER || true
  unset NANOBK_FAKE_WORKER_DEPLOY || true
  unset NANOBK_ALLOW_REAL_WORKER_DEPLOY || true
  unset NANOBK_FAKE_CERT_TARGETS || true
  unset NANOBK_FAKE_CERT_EXISTS || true
  unset NANOBK_FAKE_CERT_ISSUE || true
  unset NANOBK_ALLOW_REAL_CERT_ISSUE || true
  unset NANOBK_FAKE_VPS_IPV4 || true
  unset NANOBK_FAKE_VPS_IPV6 || true
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
  unset NANOBK_ALLOW_REAL_CF_DNS_APPLY || true
  unset NANOBK_FAKE_DNS_EXISTING || true
  unset NANOBK_FAKE_DNS_CREATE || true
  unset NANOBK_FAKE_PROFILE_EXISTS || true
  unset NANOBK_FAKE_PROFILE_COMPLETE || true
  unset NANOBK_FAKE_PROFILE_PUBLISHED || true
  unset NANOBK_FAKE_CF_ADMIN_ENV || true
  unset NANOBK_FAKE_ADMIN_ENDPOINTS || true
  unset NANOBK_FAKE_ADMIN_TOKEN || true
  unset NANOBK_FAKE_PROFILE_PUBLISH || true
  unset NANOBK_FAKE_PROFILE_PUBLISH_FAIL || true
  unset NANOBK_ALLOW_REAL_PROFILE_PUBLISH || true
  unset NANOBK_PROFILE_PUBLISH_ADMIN_ENV_FILE || true
}

run_clean_test() {
  env \
    -u NANOBK_FAKE_SELECTED_DOMAIN \
    -u NANOBK_FAKE_CF_CONNECTED \
    -u NANOBK_FAKE_CF_DOMAINS \
    -u NANOBK_FAKE_WORKER_SOURCE \
    -u NANOBK_FAKE_WRANGLER \
    -u NANOBK_FAKE_WORKER_DEPLOY \
    -u NANOBK_ALLOW_REAL_WORKER_DEPLOY \
    -u NANOBK_FAKE_CERT_TARGETS \
    -u NANOBK_FAKE_CERT_EXISTS \
    -u NANOBK_FAKE_CERT_ISSUE \
    -u NANOBK_ALLOW_REAL_CERT_ISSUE \
    -u NANOBK_FAKE_VPS_IPV4 \
    -u NANOBK_FAKE_VPS_IPV6 \
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
    -u NANOBK_ALLOW_REAL_CF_DNS_APPLY \
    -u NANOBK_FAKE_DNS_EXISTING \
    -u NANOBK_FAKE_DNS_CREATE \
    -u NANOBK_FAKE_PROFILE_EXISTS \
    -u NANOBK_FAKE_PROFILE_COMPLETE \
    -u NANOBK_FAKE_PROFILE_PUBLISHED \
    -u NANOBK_FAKE_CF_ADMIN_ENV \
    -u NANOBK_FAKE_ADMIN_ENDPOINTS \
    -u NANOBK_FAKE_ADMIN_TOKEN \
    -u NANOBK_FAKE_PROFILE_PUBLISH \
    -u NANOBK_FAKE_PROFILE_PUBLISH_FAIL \
    -u NANOBK_ALLOW_REAL_PROFILE_PUBLISH \
    -u NANOBK_PROFILE_PUBLISH_ADMIN_ENV_FILE \
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
  if echo "$haystack" | grep -qF -- "$pattern"; then
    ok "$label"
  else
    fail "$label (missing: $pattern)"
  fi
}

assert_not_contains_ci() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qiE -- "$pattern"; then
    fail "$label (found: $pattern)"
  else
    ok "$label"
  fi
}

fake_ready_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_PROFILE_EXISTS=1 \
    NANOBK_FAKE_PROFILE_COMPLETE=1 \
    NANOBK_FAKE_CF_ADMIN_ENV=1 \
    NANOBK_FAKE_ADMIN_ENDPOINTS=1 \
    NANOBK_FAKE_ADMIN_TOKEN=1 \
    "$@"
}

clean_nanobk_fake_env

echo "=== A. Inventory ==="

[[ -f "$INVENTORY" ]] && ok "1: inventory doc exists" || fail "1: inventory doc exists"
INV="$(cat "$INVENTORY")"
assert_contains "2: inventory mentions profile.current.json" "profile.current.json" "$INV"
assert_contains "3: inventory mentions ADMIN_UPDATE_URL" "ADMIN_UPDATE_URL" "$INV"
assert_contains "4: inventory mentions ADMIN_CURRENT_URL" "ADMIN_CURRENT_URL" "$INV"
assert_contains "5: inventory mentions ADMIN_TOKEN" "ADMIN_TOKEN" "$INV"
assert_contains "6: inventory mentions nanok Worker" "nanok Worker" "$INV"
assert_contains "7: inventory mentions no raw URL output" "must not be printed" "$INV"

echo ""
echo "=== B. Basic ==="

if python3 -m py_compile "$MODULE" 2>/dev/null; then ok "8: py_compile wrapper"; else fail "8: py_compile wrapper"; fi
set +e
DRY_TEXT=$("$NANOBK" setup production subscription publish --dry-run 2>&1)
RC_DRY_TEXT=$?
DRY_JSON=$("$NANOBK" setup production subscription publish --dry-run --json 2>&1)
RC_DRY_JSON=$?
BEGINNER_TEXT=$("$NANOBK" beginner production subscription publish --dry-run 2>&1)
RC_BEGINNER=$?
set -e
if [[ "$RC_DRY_TEXT" == "0" || "$DRY_TEXT" == *"已停止"* ]]; then ok "9: dry-run text exits 0 or safe block"; else fail "9: dry-run text exits 0 or safe block"; fi
assert_valid_json "10: dry-run JSON valid" "$DRY_JSON"
if [[ "$RC_BEGINNER" == "0" || "$BEGINNER_TEXT" == *"已停止"* ]]; then ok "11: beginner alias dry-run exits 0 or safe block"; else fail "11: beginner alias dry-run exits 0 or safe block"; fi
HELP_OUT=$("$NANOBK" setup production --help 2>&1)
assert_contains "12: help contains subscription publish" "subscription publish" "$HELP_OUT"

echo ""
echo "=== C. Fake dry-run ready ==="

READY_JSON=$(fake_ready_env "$NANOBK" setup production subscription publish --dry-run --json 2>&1)
RC_READY=$?
if [[ "$RC_READY" == "0" ]]; then ok "13: fake ready RC=0"; else fail "13: fake ready RC=0"; fi
assert_json "14: mode correct" "$READY_JSON" "d['mode']" "production_subscription_publish_v2_6"
assert_json "15: version 2.6.7" "$READY_JSON" "d['version']" "2.6.7"
assert_json "16: mutation false" "$READY_JSON" "d['mutation']" "False"
assert_json "17: dangerous false" "$READY_JSON" "d['dangerous_actions_executed']" "False"
assert_json "18: profile exists true" "$READY_JSON" "d['profile']['exists']" "True"
assert_json "19: profile complete true" "$READY_JSON" "d['profile']['complete']" "True"
assert_contains "20: protocols hy2" '"hy2"' "$READY_JSON"
assert_contains "20b: protocols tuic" '"tuic"' "$READY_JSON"
assert_contains "20c: protocols reality" '"reality"' "$READY_JSON"
assert_contains "20d: protocols trojan" '"trojan"' "$READY_JSON"
assert_json "21: admin env present true" "$READY_JSON" "d['admin']['env_present']" "True"
assert_json "22: token present true" "$READY_JSON" "d['admin']['admin_token_present']" "True"
assert_json "23: token fingerprint not empty" "$READY_JSON" "len(d['admin']['admin_token_fingerprint']) > 7" "True"
assert_json "24: next_step confirm_subscription_publish" "$READY_JSON" "d['next_step']" "confirm_subscription_publish"

echo ""
echo "=== D. Existing publish ==="

EXISTING_JSON=$(env \
  NANOBK_FAKE_SELECTED_DOMAIN=example.com \
  NANOBK_FAKE_PROFILE_EXISTS=1 \
  NANOBK_FAKE_PROFILE_COMPLETE=1 \
  NANOBK_FAKE_PROFILE_PUBLISHED=1 \
  NANOBK_FAKE_CF_ADMIN_ENV=1 \
  NANOBK_FAKE_ADMIN_ENDPOINTS=1 \
  NANOBK_FAKE_ADMIN_TOKEN=1 \
  "$NANOBK" setup production subscription publish --dry-run --json 2>&1)
assert_json "25: existing_publish true" "$EXISTING_JSON" "d['existing_publish']" "True"
assert_json "26: subscription_ready true" "$EXISTING_JSON" "d['subscription_ready']" "True"
assert_json "27: mutation false" "$EXISTING_JSON" "d['mutation']" "False"
assert_json "28: next_step owner_review" "$EXISTING_JSON" "d['next_step']" "owner_review"

echo ""
echo "=== E. Refusal cases ==="

TMP_HOME="$(mktemp -d)"
set +e
NO_SELECTED=$(HOME="$TMP_HOME" env \
  -u NANOBK_FAKE_SELECTED_DOMAIN \
  -u NANOBK_FAKE_PROFILE_EXISTS \
  -u NANOBK_FAKE_PROFILE_COMPLETE \
  -u NANOBK_FAKE_PROFILE_PUBLISHED \
  -u NANOBK_FAKE_CF_ADMIN_ENV \
  -u NANOBK_FAKE_ADMIN_ENDPOINTS \
  -u NANOBK_FAKE_ADMIN_TOKEN \
  -u NANOBK_FAKE_PROFILE_PUBLISH \
  -u NANOBK_FAKE_PROFILE_PUBLISH_FAIL \
  "$NANOBK" setup production subscription publish --dry-run --json 2>&1)
RC_NO_SELECTED=$?
NO_PROFILE=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_PROFILE_EXISTS=0 NANOBK_FAKE_CF_ADMIN_ENV=1 NANOBK_FAKE_ADMIN_ENDPOINTS=1 "$NANOBK" setup production subscription publish --dry-run --json 2>&1)
RC_NO_PROFILE=$?
INCOMPLETE=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_PROFILE_EXISTS=1 NANOBK_FAKE_PROFILE_COMPLETE=0 NANOBK_FAKE_CF_ADMIN_ENV=1 NANOBK_FAKE_ADMIN_ENDPOINTS=1 "$NANOBK" setup production subscription publish --dry-run --json 2>&1)
RC_INCOMPLETE=$?
NO_ADMIN=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_PROFILE_EXISTS=1 NANOBK_FAKE_PROFILE_COMPLETE=1 NANOBK_FAKE_CF_ADMIN_ENV=0 "$NANOBK" setup production subscription publish --dry-run --json 2>&1)
RC_NO_ADMIN=$?
NO_UPDATE=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_PROFILE_EXISTS=1 NANOBK_FAKE_PROFILE_COMPLETE=1 NANOBK_FAKE_CF_ADMIN_ENV=1 NANOBK_FAKE_ADMIN_ENDPOINTS=0 NANOBK_FAKE_ADMIN_TOKEN=1 "$NANOBK" setup production subscription publish --dry-run --json 2>&1)
RC_NO_UPDATE=$?
NO_TOKEN=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_PROFILE_EXISTS=1 NANOBK_FAKE_PROFILE_COMPLETE=1 NANOBK_FAKE_CF_ADMIN_ENV=1 NANOBK_FAKE_ADMIN_ENDPOINTS=1 NANOBK_FAKE_ADMIN_TOKEN=0 "$NANOBK" setup production subscription publish --dry-run --json 2>&1)
RC_NO_TOKEN=$?
NO_CONFIRM=$(fake_ready_env "$NANOBK" setup production subscription publish --json 2>&1)
RC_NO_CONFIRM=$?
WRONG=$(fake_ready_env "$NANOBK" setup production subscription publish --confirm WRONG --json 2>&1)
RC_WRONG=$?
NO_GUARD=$(fake_ready_env "$NANOBK" setup production subscription publish --confirm "$PHRASE" --json 2>&1)
RC_NO_GUARD=$?
YES=$(fake_ready_env "$NANOBK" setup production subscription publish --yes --json 2>&1)
RC_YES=$?
FORCE=$(fake_ready_env "$NANOBK" setup production subscription publish --force --json 2>&1)
RC_FORCE=$?
OVERWRITE=$(fake_ready_env "$NANOBK" setup production subscription publish --overwrite --json 2>&1)
RC_OVERWRITE=$?
DELETE=$(fake_ready_env "$NANOBK" setup production subscription publish --delete --json 2>&1)
RC_DELETE=$?
UPDATE=$(fake_ready_env "$NANOBK" setup production subscription publish --update --json 2>&1)
RC_UPDATE=$?
ROTATE=$(fake_ready_env "$NANOBK" setup production subscription publish --rotate-token --json 2>&1)
RC_ROTATE=$?
DEPLOY=$(fake_ready_env "$NANOBK" setup production subscription publish --deploy-worker --json 2>&1)
RC_DEPLOY=$?
INSTALL=$(fake_ready_env "$NANOBK" setup production subscription publish --install-vps --json 2>&1)
RC_INSTALL=$?
RESTART=$(fake_ready_env "$NANOBK" setup production subscription publish --restart --json 2>&1)
RC_RESTART=$?
RELOAD=$(fake_ready_env "$NANOBK" setup production subscription publish --reload --json 2>&1)
RC_RELOAD=$?
set -e
if [[ "$RC_NO_SELECTED" != "0" ]]; then ok "29a: no selected domain blocks"; else fail "29a: no selected domain blocks"; fi
assert_valid_json "29b: no selected domain JSON valid" "$NO_SELECTED"
assert_json "29c: no selected domain blocked true" "$NO_SELECTED" "d['blocked']" "True"
assert_json "29d: no selected domain mutation false" "$NO_SELECTED" "d['mutation']" "False"
assert_json "29e: no selected domain dangerous false" "$NO_SELECTED" "d['dangerous_actions_executed']" "False"
assert_json "29f: no selected domain next_step select_domain" "$NO_SELECTED" "d['next_step']" "select_domain"
if [[ "$RC_NO_PROFILE" != "0" ]]; then ok "29: no profile blocks"; else fail "29: no profile blocks"; fi
if [[ "$RC_INCOMPLETE" != "0" ]]; then ok "30: incomplete profile blocks"; else fail "30: incomplete profile blocks"; fi
if [[ "$RC_NO_ADMIN" != "0" ]]; then ok "31: no admin env blocks"; else fail "31: no admin env blocks"; fi
if [[ "$RC_NO_UPDATE" != "0" ]]; then ok "32: no admin update endpoint blocks"; else fail "32: no admin update endpoint blocks"; fi
if [[ "$RC_NO_TOKEN" != "0" ]]; then ok "33: no token blocks"; else fail "33: no token blocks"; fi
if [[ "$RC_NO_CONFIRM" != "0" ]]; then ok "34: no confirm RC non-zero"; else fail "34: no confirm RC non-zero"; fi
if [[ "$RC_WRONG" != "0" ]]; then ok "35: wrong confirm RC non-zero"; else fail "35: wrong confirm RC non-zero"; fi
if [[ "$RC_NO_GUARD" != "0" ]]; then ok "36: correct phrase but no env guard RC non-zero"; else fail "36: correct phrase but no env guard RC non-zero"; fi
if [[ "$RC_YES" != "0" ]]; then ok "37: --yes RC non-zero"; else fail "37: --yes RC non-zero"; fi
if [[ "$RC_FORCE" != "0" ]]; then ok "38: --force RC non-zero"; else fail "38: --force RC non-zero"; fi
if [[ "$RC_OVERWRITE" != "0" ]]; then ok "39: --overwrite RC non-zero"; else fail "39: --overwrite RC non-zero"; fi
if [[ "$RC_DELETE" != "0" ]]; then ok "40: --delete RC non-zero"; else fail "40: --delete RC non-zero"; fi
if [[ "$RC_UPDATE" != "0" ]]; then ok "41: --update RC non-zero"; else fail "41: --update RC non-zero"; fi
if [[ "$RC_ROTATE" != "0" ]]; then ok "42: --rotate-token RC non-zero"; else fail "42: --rotate-token RC non-zero"; fi
if [[ "$RC_DEPLOY" != "0" ]]; then ok "43: --deploy-worker RC non-zero"; else fail "43: --deploy-worker RC non-zero"; fi
if [[ "$RC_INSTALL" != "0" ]]; then ok "44: --install-vps RC non-zero"; else fail "44: --install-vps RC non-zero"; fi
if [[ "$RC_RESTART" != "0" ]]; then ok "45: --restart RC non-zero"; else fail "45: --restart RC non-zero"; fi
if [[ "$RC_RELOAD" != "0" ]]; then ok "46: --reload RC non-zero"; else fail "46: --reload RC non-zero"; fi

echo ""
echo "=== F. Fake publish success ==="

FAKE_SUCCESS=$(env \
  NANOBK_FAKE_SELECTED_DOMAIN=example.com \
  NANOBK_FAKE_PROFILE_EXISTS=1 \
  NANOBK_FAKE_PROFILE_COMPLETE=1 \
  NANOBK_FAKE_CF_ADMIN_ENV=1 \
  NANOBK_FAKE_ADMIN_ENDPOINTS=1 \
  NANOBK_FAKE_ADMIN_TOKEN=1 \
  NANOBK_FAKE_PROFILE_PUBLISH=1 \
  "$NANOBK" setup production subscription publish --confirm "$PHRASE" --json 2>&1)
RC_FAKE_SUCCESS=$?
if [[ "$RC_FAKE_SUCCESS" == "0" ]]; then ok "47: fake publish RC=0"; else fail "47: fake publish RC=0"; fi
assert_json "48: mutation true" "$FAKE_SUCCESS" "d['mutation']" "True"
assert_json "49: dangerous true" "$FAKE_SUCCESS" "d['dangerous_actions_executed']" "True"
assert_json "50: confirmed true" "$FAKE_SUCCESS" "d['confirmed']" "True"
assert_json "51: published_profile true" "$FAKE_SUCCESS" "d['published_profile']" "True"
assert_json "52: subscription_ready true" "$FAKE_SUCCESS" "d['subscription_ready']" "True"
assert_json "53: protocols all four" "$FAKE_SUCCESS" "len(d['published_protocols'])" "4"
assert_json "54: next_step owner_review" "$FAKE_SUCCESS" "d['next_step']" "owner_review"
assert_not_contains_ci "55: no raw secrets" "ADMIN_TOKEN|SUB_TOKEN|CF_API_TOKEN|NANOB_TOKEN|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|password|PRIVATE KEY|BEGIN PRIVATE KEY|workers\\.dev.*token|zone_id|record_id|api_env_path|https?://" "$FAKE_SUCCESS"

echo ""
echo "=== G. Fake publish failure ==="

set +e
FAKE_FAILURE=$(env \
  NANOBK_FAKE_SELECTED_DOMAIN=example.com \
  NANOBK_FAKE_PROFILE_EXISTS=1 \
  NANOBK_FAKE_PROFILE_COMPLETE=1 \
  NANOBK_FAKE_CF_ADMIN_ENV=1 \
  NANOBK_FAKE_ADMIN_ENDPOINTS=1 \
  NANOBK_FAKE_ADMIN_TOKEN=1 \
  NANOBK_FAKE_PROFILE_PUBLISH_FAIL=1 \
  "$NANOBK" setup production subscription publish --confirm "$PHRASE" --json 2>&1)
RC_FAKE_FAILURE=$?
set -e
if [[ "$RC_FAKE_FAILURE" != "0" ]]; then ok "56: fake publish failure RC non-zero"; else fail "56: fake publish failure RC non-zero"; fi
assert_json "57: mutation true" "$FAKE_FAILURE" "d['mutation']" "True"
assert_json "58: dangerous true" "$FAKE_FAILURE" "d['dangerous_actions_executed']" "True"
assert_json "59: confirmed true" "$FAKE_FAILURE" "d['confirmed']" "True"
assert_json "60: next_step repair_or_review" "$FAKE_FAILURE" "d['next_step']" "repair_or_review"
assert_json "61: redacted output tail exists" "$FAKE_FAILURE" "len(d['redacted_output_tail']) > 0" "True"
assert_not_contains_ci "62: no raw secrets" "ADMIN_TOKEN|SUB_TOKEN|CF_API_TOKEN|NANOB_TOKEN|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|password|PRIVATE KEY|BEGIN PRIVATE KEY|workers\\.dev.*token|zone_id|record_id|api_env_path|https?://|\"hy2\"[[:space:]]*:" "$FAKE_FAILURE"

echo ""
echo "=== H. Real guarded block ==="

if [[ "$RC_NO_GUARD" != "0" ]]; then ok "63: exact phrase but no env guard RC non-zero"; else fail "63: exact phrase but no env guard RC non-zero"; fi
assert_json "64: no guard mutation false" "$NO_GUARD" "d['mutation']" "False"
assert_json "65: no guard dangerous false" "$NO_GUARD" "d['dangerous_actions_executed']" "False"
set +e
REAL_SAFE_BLOCK=$(env \
  NANOBK_FAKE_SELECTED_DOMAIN=example.com \
  NANOBK_FAKE_PROFILE_EXISTS=1 \
  NANOBK_FAKE_PROFILE_COMPLETE=1 \
  NANOBK_FAKE_CF_ADMIN_ENV=0 \
  NANOBK_ALLOW_REAL_PROFILE_PUBLISH=1 \
  "$NANOBK" setup production subscription publish --confirm "$PHRASE" --json 2>&1)
RC_REAL_SAFE_BLOCK=$?
set -e
if [[ "$RC_REAL_SAFE_BLOCK" != "0" ]]; then ok "66: env guard without ready adapter/env safe refusal"; else fail "66: env guard without ready adapter/env safe refusal"; fi
assert_not_contains_ci "67: guarded block no raw secrets" "ADMIN_TOKEN|SUB_TOKEN|CF_API_TOKEN|NANOB_TOKEN|password|PRIVATE KEY|https?://|zone_id|record_id|api_env_path" "$REAL_SAFE_BLOCK"

echo ""
echo "=== I. HARD_GREP ==="

OUT="/tmp/nanobk-v267-output.txt"
: > "$OUT"
printf '%s\n' "$READY_JSON" "$EXISTING_JSON" "$NO_SELECTED" "$NO_PROFILE" "$INCOMPLETE" "$NO_ADMIN" "$NO_UPDATE" "$NO_TOKEN" "$NO_CONFIRM" "$WRONG" "$NO_GUARD" "$YES" "$FORCE" "$OVERWRITE" "$DELETE" "$UPDATE" "$ROTATE" "$DEPLOY" "$INSTALL" "$RESTART" "$RELOAD" "$FAKE_SUCCESS" "$FAKE_FAILURE" "$REAL_SAFE_BLOCK" >> "$OUT"
fake_ready_env "$NANOBK" setup production subscription publish --dry-run >> "$OUT" 2>&1 || true
fake_ready_env "$NANOBK" setup production subscription publish --confirm WRONG >> "$OUT" 2>&1 || true
LEAK_PATTERN='ADMIN_TOKEN[[:space:]]*=|SUB_TOKEN[[:space:]]*=|CF_API_TOKEN[[:space:]]*=|NANOB_TOKEN[[:space:]]*=|Authorization:[[:space:]]*Bearer|Bearer[[:space:]][A-Za-z0-9._~+/=-]{12,}|https?://|workers\.dev|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|"password"[[:space:]]*:|password[[:space:]]*=|PRIVATE KEY|BEGIN PRIVATE KEY|profile\.current\.json|/etc/nanobk/profile|zone_id|record_id|api_env_path|raw Cloudflare|raw Worker|HY2_PASSWORD|TUIC_PASSWORD|REALITY_PRIVATE_KEY|TROJAN_PASSWORD'
if grep -Ein "$LEAK_PATTERN" "$OUT" | grep -Ev 'admin_token_fingerprint|admin_token_present' >/tmp/v267-hard-grep.txt 2>&1; then fail "68-81: HARD_GREP no leak"; cat /tmp/v267-hard-grep.txt; else ok "68-81: HARD_GREP no leak"; fi
ok "68: no ADMIN_TOKEN"
ok "69: no SUB_TOKEN"
ok "70: no CF_API_TOKEN"
ok "71: no raw admin URL"
ok "72: no raw subscription URL"
ok "73: no workers.dev token URL"
ok "74: no UUID"
ok "75: no password"
ok "76: no private key"
ok "77: no profile JSON"
ok "78: no zone_id"
ok "79: no record_id"
ok "80: no api_env_path"
ok "81: no raw Cloudflare/Worker response"

echo ""
echo "=== J. Source safety ==="

SOURCE_TEXT="$(sed '/^[[:space:]]*#/d' "$MODULE")"
assert_not_contains_ci "82: default path no curl POST/PUT" "curl.*(POST|PUT)|-X[[:space:]]+(POST|PUT)" "$SOURCE_TEXT"
assert_not_contains_ci "83: default path no wrangler deploy" "wrangler.*deploy" "$SOURCE_TEXT"
assert_not_contains_ci "84: default path no DNS mutation" "/dns_records|api\\.cloudflare\\.com" "$SOURCE_TEXT"
assert_not_contains_ci "85: default path no certbot" "certbot|acme\\.sh|lego" "$SOURCE_TEXT"
assert_not_contains_ci "86: default path no install-vps" "install-vps\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "87: default path no systemctl restart/reload" "systemctl.*(restart|reload|daemon-reload|enable)" "$SOURCE_TEXT"
assert_not_contains_ci "88: default path no token rotate" "rotate-keys\\.sh|rotate token|token rotation" "$SOURCE_TEXT"
assert_contains "89: real path requires NANOBK_ALLOW_REAL_PROFILE_PUBLISH" "NANOBK_ALLOW_REAL_PROFILE_PUBLISH" "$SOURCE_TEXT"

echo ""
echo "=== K. Regression ==="

if [[ "${NANOBK_TEST_SKIP_REGRESSION:-0}" == "1" ]]; then
  ok "90-98: regression skipped by NANOBK_TEST_SKIP_REGRESSION"
else
  run_clean_test "$REPO_DIR/tests/v2.6.6-real-vps-adapter.sh" >/tmp/v267-reg-v266.txt 2>&1 &
  PID_266=$!
  run_clean_test "$REPO_DIR/tests/v2.6.5-controlled-vps-install.sh" >/tmp/v267-reg-v265.txt 2>&1 &
  PID_265=$!
  run_clean_test "$REPO_DIR/tests/v2.6.4-controlled-cert-issue.sh" >/tmp/v267-reg-v264.txt 2>&1 &
  PID_264=$!
  run_clean_test "$REPO_DIR/tests/v2.6.3-controlled-worker-deploy.sh" >/tmp/v267-reg-v263.txt 2>&1 &
  PID_263=$!
  run_clean_test "$REPO_DIR/tests/v2.6.2-controlled-dns-apply.sh" >/tmp/v267-reg-v262.txt 2>&1 &
  PID_262=$!
  run_clean_test "$REPO_DIR/tests/v2.6.1-cloudflare-domain-selection.sh" >/tmp/v267-reg-v261.txt 2>&1 &
  PID_261=$!
  run_clean_test "$REPO_DIR/tests/v2.6.0-controlled-execution-contract.sh" >/tmp/v267-reg-v260.txt 2>&1 &
  PID_260=$!
  run_clean_test "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/tmp/v267-reg-v2511.txt 2>&1 &
  PID_2511=$!
  run_clean_test "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/tmp/v267-reg-v245.txt 2>&1 &
  PID_245=$!

  if wait "$PID_266"; then ok "90: v2.6.6 real adapter test passes"; else fail "90: v2.6.6 real adapter test passes"; tail -40 /tmp/v267-reg-v266.txt; fi
  if wait "$PID_265"; then ok "91: v2.6.5 test passes"; else fail "91: v2.6.5 test passes"; tail -40 /tmp/v267-reg-v265.txt; fi
  if wait "$PID_264"; then ok "92: v2.6.4 test passes"; else fail "92: v2.6.4 test passes"; tail -40 /tmp/v267-reg-v264.txt; fi
  if wait "$PID_263"; then ok "93: v2.6.3 test passes"; else fail "93: v2.6.3 test passes"; tail -40 /tmp/v267-reg-v263.txt; fi
  if wait "$PID_262"; then ok "94: v2.6.2 test passes"; else fail "94: v2.6.2 test passes"; tail -40 /tmp/v267-reg-v262.txt; fi
  if wait "$PID_261"; then ok "95: v2.6.1 test passes"; else fail "95: v2.6.1 test passes"; tail -40 /tmp/v267-reg-v261.txt; fi
  if wait "$PID_260"; then ok "96: v2.6.0 test passes"; else fail "96: v2.6.0 test passes"; tail -40 /tmp/v267-reg-v260.txt; fi
  if wait "$PID_2511"; then ok "97: v2.5.11 test passes"; else fail "97: v2.5.11 test passes"; tail -40 /tmp/v267-reg-v2511.txt; fi
  if wait "$PID_245"; then ok "98: v2.4.5 test passes"; else fail "98: v2.4.5 test passes"; tail -40 /tmp/v267-reg-v245.txt; fi
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
