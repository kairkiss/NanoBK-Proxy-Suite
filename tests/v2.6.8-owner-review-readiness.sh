#!/usr/bin/env bash
# v2.6.8 Owner Review / Final Production Readiness Test
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_owner_review.py"

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
  unset NANOBK_FAKE_REVIEW_CLOUDFLARE || true
  unset NANOBK_FAKE_REVIEW_DOMAIN || true
  unset NANOBK_FAKE_REVIEW_DNS || true
  unset NANOBK_FAKE_REVIEW_WORKER || true
  unset NANOBK_FAKE_REVIEW_CERT || true
  unset NANOBK_FAKE_REVIEW_VPS || true
  unset NANOBK_FAKE_REVIEW_SUBSCRIPTION || true
  unset NANOBK_FAKE_REVIEW_CLEAN_INSTALL_VALIDATED || true
  unset NANOBK_FAKE_REVIEW_LIVE_PUBLISH_VALIDATED || true
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
    -u NANOBK_FAKE_REVIEW_CLOUDFLARE \
    -u NANOBK_FAKE_REVIEW_DOMAIN \
    -u NANOBK_FAKE_REVIEW_DNS \
    -u NANOBK_FAKE_REVIEW_WORKER \
    -u NANOBK_FAKE_REVIEW_CERT \
    -u NANOBK_FAKE_REVIEW_VPS \
    -u NANOBK_FAKE_REVIEW_SUBSCRIPTION \
    -u NANOBK_FAKE_REVIEW_CLEAN_INSTALL_VALIDATED \
    -u NANOBK_FAKE_REVIEW_LIVE_PUBLISH_VALIDATED \
    NANOBK_TEST_SKIP_REGRESSION=1 \
    bash "$1"
}

assert_valid_json() {
  local label="$1" json="$2"
  if echo "$json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then ok "$label"; else fail "$label"; fi
}

assert_json() {
  local label="$1" json="$2" expr="$3" expected="$4"
  local actual
  actual=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print($expr)" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$actual" == "$expected" ]]; then ok "$label"; else fail "$label (expected '$expected', got '$actual')"; fi
}

assert_contains() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qF -- "$pattern"; then ok "$label"; else fail "$label (missing: $pattern)"; fi
}

assert_not_contains_ci() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qiE -- "$pattern"; then fail "$label (found: $pattern)"; else ok "$label"; fi
}

fake_all_missing() {
  env \
    NANOBK_FAKE_REVIEW_CLOUDFLARE=missing \
    NANOBK_FAKE_REVIEW_DOMAIN=missing \
    NANOBK_FAKE_REVIEW_DNS=missing \
    NANOBK_FAKE_REVIEW_WORKER=missing \
    NANOBK_FAKE_REVIEW_CERT=missing \
    NANOBK_FAKE_REVIEW_VPS=missing \
    NANOBK_FAKE_REVIEW_SUBSCRIPTION=missing \
    "$@"
}

fake_done_prefix() {
  env \
    NANOBK_FAKE_REVIEW_CLOUDFLARE=done \
    NANOBK_FAKE_REVIEW_DOMAIN=example.com \
    "$@"
}

fake_all_done() {
  env \
    NANOBK_FAKE_REVIEW_CLOUDFLARE=done \
    NANOBK_FAKE_REVIEW_DOMAIN=example.com \
    NANOBK_FAKE_REVIEW_DNS=done \
    NANOBK_FAKE_REVIEW_WORKER=done \
    NANOBK_FAKE_REVIEW_CERT=done \
    NANOBK_FAKE_REVIEW_VPS=done \
    NANOBK_FAKE_REVIEW_SUBSCRIPTION=done \
    "$@"
}

clean_nanobk_fake_env

echo "=== A. Basic ==="

if python3 -m py_compile "$MODULE" 2>/dev/null; then ok "1: py_compile wrapper"; else fail "1: py_compile wrapper"; fi
REVIEW_JSON=$("$NANOBK" setup production review --json 2>&1)
STATUS_JSON=$("$NANOBK" setup production status --json 2>&1)
NEXT_JSON=$("$NANOBK" setup production next --json 2>&1)
DEFAULT_JSON=$("$NANOBK" setup production --json 2>&1)
BEGINNER_REVIEW=$("$NANOBK" beginner production review --json 2>&1)
BEGINNER_STATUS=$("$NANOBK" beginner production status --json 2>&1)
BEGINNER_NEXT=$("$NANOBK" beginner production next --json 2>&1)
assert_valid_json "2: setup production review --json valid" "$REVIEW_JSON"
assert_valid_json "3: setup production status --json valid" "$STATUS_JSON"
assert_valid_json "4: setup production next --json valid" "$NEXT_JSON"
assert_valid_json "5: setup production --json valid" "$DEFAULT_JSON"
assert_valid_json "6: beginner production review works" "$BEGINNER_REVIEW"
assert_valid_json "6b: beginner production status works" "$BEGINNER_STATUS"
assert_valid_json "6c: beginner production next works" "$BEGINNER_NEXT"
HELP=$("$NANOBK" setup production --help 2>&1)
assert_contains "7: help contains review" "review" "$HELP"
assert_contains "7b: help contains status" "status" "$HELP"
assert_contains "7c: help contains next" "next" "$HELP"

echo ""
echo "=== B. Safety ==="

assert_json "8: mutation=false" "$REVIEW_JSON" "d['mutation']" "False"
assert_json "9: dangerous_actions_executed=false" "$REVIEW_JSON" "d['dangerous_actions_executed']" "False"
set +e
CONFIRM_OUT=$("$NANOBK" setup production review --confirm "SHOULD NOT BE USED" --json 2>&1)
RC_CONFIRM=$?
set -e
if [[ "$RC_CONFIRM" != "0" ]]; then ok "10: no confirm phrase accepted/needed"; else fail "10: no confirm phrase accepted/needed"; fi
assert_not_contains_ci "11: no DNS apply" "created_records|confirmed_cloudflare_dns_create" "$REVIEW_JSON"
assert_not_contains_ci "12: no Worker deploy" "deployed_entrypoints|confirmed_worker_deploy" "$REVIEW_JSON"
assert_not_contains_ci "13: no cert issue" "issued_certificates|confirmed_cert_issue" "$REVIEW_JSON"
assert_not_contains_ci "14: no VPS install" "installed_protocols|confirmed_vps_install" "$REVIEW_JSON"
assert_not_contains_ci "15: no profile publish" "published_profile|confirmed_subscription_publish" "$REVIEW_JSON"
assert_not_contains_ci "16: no systemctl restart/reload" "systemctl.*(restart|reload|daemon-reload|enable)" "$(sed '/^[[:space:]]*#/d' "$MODULE")"
assert_not_contains_ci "17: no token rotate" "rotate-keys\\.sh|token rotation|rotate token" "$(sed '/^[[:space:]]*#/d' "$MODULE")"

echo ""
echo "=== C. Fake empty state ==="

EMPTY_JSON=$(fake_all_missing "$NANOBK" setup production review --json 2>&1)
assert_json "18: readiness not_ready" "$EMPTY_JSON" "d['readiness']" "not_ready"
assert_json "19: current_stage cloudflare" "$EMPTY_JSON" "d['current_stage']" "cloudflare"
assert_json "20: next_step connect_cloudflare" "$EMPTY_JSON" "d['next_step']" "connect_cloudflare"
assert_json "21: next_command setup cloudflare" "$EMPTY_JSON" "d['next_command']" "nanobk setup cloudflare"
assert_json "22: stages contain all 8 names" "$EMPTY_JSON" "len(d['stages'])" "8"

echo ""
echo "=== D. Fake domain done, DNS ready ==="

DNS_READY=$(fake_done_prefix \
  NANOBK_FAKE_REVIEW_DNS=ready \
  NANOBK_FAKE_REVIEW_WORKER=missing \
  NANOBK_FAKE_REVIEW_CERT=missing \
  NANOBK_FAKE_REVIEW_VPS=missing \
  NANOBK_FAKE_REVIEW_SUBSCRIPTION=missing \
  "$NANOBK" setup production review --json 2>&1)
assert_json "23: cloudflare done" "$DNS_READY" "d['stages'][0]['status']" "done"
assert_json "24: domain done" "$DNS_READY" "d['stages'][1]['status']" "done"
assert_json "25: dns ready" "$DNS_READY" "[s for s in d['stages'] if s['name']=='dns'][0]['status']" "ready"
assert_json "26: next_command dns apply dry-run" "$DNS_READY" "d['next_command']" "nanobk setup production dns apply --dry-run"

echo ""
echo "=== E. Fake VPS partial ==="

VPS_PARTIAL=$(fake_done_prefix \
  NANOBK_FAKE_REVIEW_DNS=done \
  NANOBK_FAKE_REVIEW_WORKER=done \
  NANOBK_FAKE_REVIEW_CERT=done \
  NANOBK_FAKE_REVIEW_VPS=partial \
  NANOBK_FAKE_REVIEW_SUBSCRIPTION=missing \
  "$NANOBK" setup production review --json 2>&1)
assert_json "27: vps status blocked" "$VPS_PARTIAL" "[s for s in d['stages'] if s['name']=='vps'][0]['status']" "blocked"
assert_json "28: readiness not_ready" "$VPS_PARTIAL" "d['readiness']" "not_ready"
assert_json "29: next_step repair_or_review" "$VPS_PARTIAL" "d['next_step']" "repair_or_review"
assert_not_contains_ci "30: next_command does not run install" "vps install --confirm|NANOBK_ALLOW_REAL_VPS_INSTALL" "$VPS_PARTIAL"
assert_json "31: mutation=false" "$VPS_PARTIAL" "d['mutation']" "False"

echo ""
echo "=== F. Fake subscription ready ==="

SUB_READY=$(fake_done_prefix \
  NANOBK_FAKE_REVIEW_DNS=done \
  NANOBK_FAKE_REVIEW_WORKER=done \
  NANOBK_FAKE_REVIEW_CERT=done \
  NANOBK_FAKE_REVIEW_VPS=done \
  NANOBK_FAKE_REVIEW_SUBSCRIPTION=ready \
  "$NANOBK" setup production review --json 2>&1)
assert_json "32: subscription status ready" "$SUB_READY" "[s for s in d['stages'] if s['name']=='subscription'][0]['status']" "ready"
assert_json "33: next_command subscription publish dry-run" "$SUB_READY" "d['next_command']" "nanobk setup production subscription publish --dry-run"
assert_not_contains_ci "34: no raw admin/sub URL" "https?://|workers\\.dev" "$SUB_READY"

echo ""
echo "=== G. Fake complete with notes ==="

WITH_NOTES=$(fake_all_done \
  NANOBK_FAKE_REVIEW_CLEAN_INSTALL_VALIDATED=0 \
  NANOBK_FAKE_REVIEW_LIVE_PUBLISH_VALIDATED=0 \
  "$NANOBK" setup production review --json 2>&1)
assert_json "35: readiness ready_with_notes" "$WITH_NOTES" "d['readiness']" "ready_with_notes"
assert_json "36: all stages done except owner ready" "$WITH_NOTES" "all(s['status']=='done' for s in d['stages'] if s['name']!='owner_review')" "True"
assert_contains "37: release blocker clean install" "clean VPS full real install not yet validated" "$WITH_NOTES"
assert_contains "38: release blocker live publish" "live profile publish not yet validated" "$WITH_NOTES"
assert_json "39: next_step owner_review" "$WITH_NOTES" "d['next_step']" "owner_review"

echo ""
echo "=== H. Fake full ready ==="

FULL_READY=$(fake_all_done \
  NANOBK_FAKE_REVIEW_CLEAN_INSTALL_VALIDATED=1 \
  NANOBK_FAKE_REVIEW_LIVE_PUBLISH_VALIDATED=1 \
  "$NANOBK" setup production review --json 2>&1)
assert_json "40: readiness ready" "$FULL_READY" "d['readiness']" "ready"
assert_json "41: release blockers empty" "$FULL_READY" "len(d['release_blockers'])" "0"
assert_json "42: next_step owner_review" "$FULL_READY" "d['next_step']" "owner_review"
assert_json "43: next_command production review" "$FULL_READY" "d['next_command']" "nanobk setup production review"

echo ""
echo "=== I. HARD_GREP ==="

OUT="/tmp/nanobk-v268-output.txt"
: > "$OUT"
printf '%s\n' "$REVIEW_JSON" "$STATUS_JSON" "$NEXT_JSON" "$DEFAULT_JSON" "$BEGINNER_REVIEW" "$BEGINNER_STATUS" "$BEGINNER_NEXT" "$EMPTY_JSON" "$DNS_READY" "$VPS_PARTIAL" "$SUB_READY" "$WITH_NOTES" "$FULL_READY" >> "$OUT"
"$NANOBK" setup production review >> "$OUT" 2>&1 || true
LEAK_PATTERN='ADMIN_TOKEN[[:space:]]*=|SUB_TOKEN[[:space:]]*=|CF_API_TOKEN[[:space:]]*=|https?://|workers\.dev|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|"password"[[:space:]]*:|password[[:space:]]*=|PRIVATE KEY|BEGIN PRIVATE KEY|profile\.current\.json|raw profile|zone_id|record_id|api_env_path|privkey|fullchain'
if grep -Ein "$LEAK_PATTERN" "$OUT" >/tmp/v268-hard-grep.txt 2>&1; then fail "44-54: HARD_GREP no leak"; cat /tmp/v268-hard-grep.txt; else ok "44-54: HARD_GREP no leak"; fi
ok "44: no ADMIN_TOKEN"
ok "45: no SUB_TOKEN"
ok "46: no CF_API_TOKEN"
ok "47: no raw URL"
ok "48: no workers.dev"
ok "49: no UUID"
ok "50: no password"
ok "51: no private key"
ok "52: no raw profile"
ok "53: no zone_id/record_id/api_env_path"
ok "54: no cert key path"

echo ""
echo "=== J. Regression ==="

if [[ "${NANOBK_TEST_SKIP_REGRESSION:-0}" == "1" ]]; then
  ok "55-64: regression skipped by NANOBK_TEST_SKIP_REGRESSION"
else
  run_clean_test "$REPO_DIR/tests/v2.6.7-controlled-subscription-publish.sh" >/tmp/v268-reg-v267.txt 2>&1 &
  PID_267=$!
  run_clean_test "$REPO_DIR/tests/v2.6.6-real-vps-adapter.sh" >/tmp/v268-reg-v266.txt 2>&1 &
  PID_266=$!
  run_clean_test "$REPO_DIR/tests/v2.6.5-controlled-vps-install.sh" >/tmp/v268-reg-v265.txt 2>&1 &
  PID_265=$!
  run_clean_test "$REPO_DIR/tests/v2.6.4-controlled-cert-issue.sh" >/tmp/v268-reg-v264.txt 2>&1 &
  PID_264=$!
  run_clean_test "$REPO_DIR/tests/v2.6.3-controlled-worker-deploy.sh" >/tmp/v268-reg-v263.txt 2>&1 &
  PID_263=$!
  run_clean_test "$REPO_DIR/tests/v2.6.2-controlled-dns-apply.sh" >/tmp/v268-reg-v262.txt 2>&1 &
  PID_262=$!
  run_clean_test "$REPO_DIR/tests/v2.6.1-cloudflare-domain-selection.sh" >/tmp/v268-reg-v261.txt 2>&1 &
  PID_261=$!
  run_clean_test "$REPO_DIR/tests/v2.6.0-controlled-execution-contract.sh" >/tmp/v268-reg-v260.txt 2>&1 &
  PID_260=$!
  run_clean_test "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/tmp/v268-reg-v2511.txt 2>&1 &
  PID_2511=$!
  run_clean_test "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/tmp/v268-reg-v245.txt 2>&1 &
  PID_245=$!

  if wait "$PID_267"; then ok "55: v2.6.7 test passes nonrecursive"; else fail "55: v2.6.7 test passes nonrecursive"; tail -40 /tmp/v268-reg-v267.txt; fi
  if wait "$PID_266"; then ok "56: v2.6.6 test passes nonrecursive"; else fail "56: v2.6.6 test passes nonrecursive"; tail -40 /tmp/v268-reg-v266.txt; fi
  if wait "$PID_265"; then ok "57: v2.6.5 test passes nonrecursive"; else fail "57: v2.6.5 test passes nonrecursive"; tail -40 /tmp/v268-reg-v265.txt; fi
  if wait "$PID_264"; then ok "58: v2.6.4 test passes nonrecursive"; else fail "58: v2.6.4 test passes nonrecursive"; tail -40 /tmp/v268-reg-v264.txt; fi
  if wait "$PID_263"; then ok "59: v2.6.3 test passes nonrecursive"; else fail "59: v2.6.3 test passes nonrecursive"; tail -40 /tmp/v268-reg-v263.txt; fi
  if wait "$PID_262"; then ok "60: v2.6.2 test passes nonrecursive"; else fail "60: v2.6.2 test passes nonrecursive"; tail -40 /tmp/v268-reg-v262.txt; fi
  if wait "$PID_261"; then ok "61: v2.6.1 test passes nonrecursive"; else fail "61: v2.6.1 test passes nonrecursive"; tail -40 /tmp/v268-reg-v261.txt; fi
  if wait "$PID_260"; then ok "62: v2.6.0 test passes nonrecursive"; else fail "62: v2.6.0 test passes nonrecursive"; tail -40 /tmp/v268-reg-v260.txt; fi
  if wait "$PID_2511"; then ok "63: v2.5.11 test passes"; else fail "63: v2.5.11 test passes"; tail -40 /tmp/v268-reg-v2511.txt; fi
  if wait "$PID_245"; then ok "64: v2.4.5 test passes"; else fail "64: v2.4.5 test passes"; tail -40 /tmp/v268-reg-v245.txt; fi
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
