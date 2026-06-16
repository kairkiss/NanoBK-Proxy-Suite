#!/usr/bin/env bash
# v2.6.9 Guided One-Command Production Flow Test
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_guided_flow.py"

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
  unset NANOBK_FAKE_GUIDE_AUTO_DRY_RUN || true
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
    -u NANOBK_FAKE_GUIDE_AUTO_DRY_RUN \
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

fake_missing() {
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

fake_prefix() {
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

if python3 -m py_compile "$MODULE" 2>/dev/null; then ok "1: py_compile guided flow module"; else fail "1: py_compile guided flow module"; fi
GUIDE_JSON=$("$NANOBK" setup production guide --json 2>&1)
DRY_JSON=$("$NANOBK" setup production guide --dry-run --json 2>&1)
NEXT_JSON=$("$NANOBK" setup production guide --step next --json 2>&1)
ALL_JSON=$("$NANOBK" setup production guide --step all --json 2>&1)
AUTO_JSON=$("$NANOBK" setup production guide --auto-dry-run --json 2>&1)
BEGINNER_JSON=$("$NANOBK" beginner production --json 2>&1)
BEGINNER_GUIDE_JSON=$("$NANOBK" beginner production guide --json 2>&1)
SETUP_DEFAULT_JSON=$("$NANOBK" setup production --json 2>&1)
BEGINNER_REVIEW_JSON=$("$NANOBK" beginner production review --json 2>&1)
SETUP_REVIEW_JSON=$("$NANOBK" setup production review --json 2>&1)
BEGINNER_TEXT=$("$NANOBK" beginner production 2>&1)
assert_valid_json "2: setup production guide --json valid" "$GUIDE_JSON"
assert_valid_json "3: setup production guide --dry-run --json valid" "$DRY_JSON"
assert_valid_json "4: setup production guide --step next --json valid" "$NEXT_JSON"
assert_valid_json "5: setup production guide --step all --json valid" "$ALL_JSON"
assert_valid_json "6: setup production guide --auto-dry-run --json valid" "$AUTO_JSON"
assert_valid_json "7: beginner production --json valid" "$BEGINNER_JSON"
assert_valid_json "8: beginner production guide --json valid" "$BEGINNER_GUIDE_JSON"
assert_valid_json "8a: setup production --json valid" "$SETUP_DEFAULT_JSON"
assert_valid_json "8b: beginner production review --json valid" "$BEGINNER_REVIEW_JSON"
assert_valid_json "8c: setup production review --json valid" "$SETUP_REVIEW_JSON"
HELP=$("$NANOBK" setup production --help 2>&1)
assert_contains "9: help contains guide" "guide" "$HELP"
assert_json "9a: setup guide mode guided" "$GUIDE_JSON" "d['mode']" "production_guided_flow_v2_6"
assert_json "9b: beginner guide mode guided" "$BEGINNER_GUIDE_JSON" "d['mode']" "production_guided_flow_v2_6"
assert_json "9c: beginner production mode guided" "$BEGINNER_JSON" "d['mode']" "production_guided_flow_v2_6"
assert_json "9d: setup production mode guided" "$SETUP_DEFAULT_JSON" "d['mode']" "production_guided_flow_v2_6"
assert_json "9e: setup guide version 2.6.9" "$GUIDE_JSON" "d['version']" "2.6.9"
assert_json "9f: beginner production version 2.6.9" "$BEGINNER_JSON" "d['version']" "2.6.9"
assert_json "9g: guided schema has guide_action" "$BEGINNER_JSON" "'guide_action' in d" "True"
assert_json "9h: guided schema has guided_steps" "$BEGINNER_JSON" "'guided_steps' in d" "True"
assert_json "9i: guided schema has release_blockers" "$BEGINNER_JSON" "'release_blockers' in d" "True"
assert_contains "9j: beginner text title" "NanoBK 生产配置向导" "$BEGINNER_TEXT"
assert_contains "9k: beginner text next step" "下一步" "$BEGINNER_TEXT"
assert_contains "9l: beginner text no auto mutation" "我不会自动执行真实写入" "$BEGINNER_TEXT"
assert_json "9m: beginner review mode owner review" "$BEGINNER_REVIEW_JSON" "d['mode']" "production_owner_review_v2_6"
assert_json "9n: setup review mode owner review" "$SETUP_REVIEW_JSON" "d['mode']" "production_owner_review_v2_6"
assert_json "9o: beginner review version 2.6.8" "$BEGINNER_REVIEW_JSON" "d['version']" "2.6.8"
assert_json "9p: setup review version 2.6.8" "$SETUP_REVIEW_JSON" "d['version']" "2.6.8"

echo ""
echo "=== B. Safety ==="

assert_json "10: mutation=false" "$GUIDE_JSON" "d['mutation']" "False"
assert_json "11: dangerous_actions_executed=false" "$GUIDE_JSON" "d['dangerous_actions_executed']" "False"
assert_json "12: safety=read_only" "$GUIDE_JSON" "d['safety']" "read_only"
assert_not_contains_ci "13: no real DNS apply" "created_records|confirmed_cloudflare_dns_create|--confirm" "$GUIDE_JSON"
assert_not_contains_ci "14: no Worker deploy" "deployed_entrypoints|confirmed_worker_deploy" "$GUIDE_JSON"
assert_not_contains_ci "15: no cert issue" "issued_certificates|confirmed_cert_issue" "$GUIDE_JSON"
assert_not_contains_ci "16: no VPS install" "installed_protocols|confirmed_vps_install" "$GUIDE_JSON"
assert_not_contains_ci "17: no profile publish" "published_profile|confirmed_subscription_publish" "$GUIDE_JSON"
assert_not_contains_ci "18: no token rotate" "rotate-keys\\.sh|token rotation|rotate token" "$(sed '/^[[:space:]]*#/d' "$MODULE")"
assert_not_contains_ci "19: no service restart/reload" "systemctl.*(restart|reload|daemon-reload|enable)" "$(sed '/^[[:space:]]*#/d' "$MODULE")"
SOURCE_TEXT="$(sed '/^[[:space:]]*#/d' "$MODULE")"
assert_not_contains_ci "19a: source no installer/install-vps.sh" "installer/install-vps\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "19b: source no installer/install-cloudflare.sh" "installer/install-cloudflare\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "19c: source no wrangler deploy" "wrangler.*deploy" "$SOURCE_TEXT"
assert_not_contains_ci "19d: source no certbot/acme/lego" "certbot|acme\\.sh|lego" "$SOURCE_TEXT"
assert_not_contains_ci "19e: source no Cloudflare mutation endpoint" "api\\.cloudflare\\.com|/dns_records" "$SOURCE_TEXT"
assert_not_contains_ci "19f: source no urllib POST/PUT" "urllib\\.request|method[[:space:]]*=[[:space:]]*[\"'](POST|PUT)[\"']" "$SOURCE_TEXT"
assert_not_contains_ci "19g: source no real env guards" "NANOBK_ALLOW_REAL_" "$SOURCE_TEXT"

echo ""
echo "=== C. Fake empty state ==="

EMPTY_JSON=$(fake_missing "$NANOBK" setup production guide --json 2>&1)
assert_json "20: readiness not_ready" "$EMPTY_JSON" "d['readiness']" "not_ready"
assert_json "21: current_stage cloudflare" "$EMPTY_JSON" "d['current_stage']" "cloudflare"
assert_json "22: next_command safe setup command" "$EMPTY_JSON" "d['next_command']" "nanobk setup cloudflare"
assert_json "23: guided_steps contains all 8 stages" "$EMPTY_JSON" "len(d['guided_steps'])" "8"
assert_json "24: no dangerous action executed" "$EMPTY_JSON" "d['dangerous_actions_executed']" "False"

echo ""
echo "=== D. Fake DNS ready ==="

DNS_READY=$(fake_prefix \
  NANOBK_FAKE_REVIEW_DNS=ready \
  NANOBK_FAKE_REVIEW_WORKER=missing \
  NANOBK_FAKE_REVIEW_CERT=missing \
  NANOBK_FAKE_REVIEW_VPS=missing \
  NANOBK_FAKE_REVIEW_SUBSCRIPTION=missing \
  "$NANOBK" setup production guide --json 2>&1)
assert_json "25: current_stage dns" "$DNS_READY" "d['current_stage']" "dns"
assert_json "26: next_command dns apply dry-run" "$DNS_READY" "d['next_command']" "nanobk setup production dns apply --dry-run"
assert_json "27: guide_action run_next_dry_run" "$DNS_READY" "d['guide_action'] in ['run_next_dry_run','manual_confirmation_required']" "True"
assert_contains "28: command contains --dry-run" "--dry-run" "$DNS_READY"
assert_not_contains_ci "29: command does not contain confirm phrase" "I UNDERSTAND NANOBK" "$DNS_READY"

echo ""
echo "=== E. Fake VPS partial ==="

VPS_PARTIAL=$(fake_prefix \
  NANOBK_FAKE_REVIEW_DNS=done \
  NANOBK_FAKE_REVIEW_WORKER=done \
  NANOBK_FAKE_REVIEW_CERT=done \
  NANOBK_FAKE_REVIEW_VPS=partial \
  NANOBK_FAKE_REVIEW_SUBSCRIPTION=missing \
  "$NANOBK" setup production guide --json 2>&1)
assert_json "30: current_stage vps" "$VPS_PARTIAL" "d['current_stage']" "vps"
assert_json "31: guide_action repair_or_review" "$VPS_PARTIAL" "d['guide_action']" "repair_or_review"
assert_json "32: next_command production review" "$VPS_PARTIAL" "d['next_command']" "nanobk setup production review"
assert_json "33: mutation=false" "$VPS_PARTIAL" "d['mutation']" "False"

echo ""
echo "=== F. Fake subscription ready ==="

SUB_READY=$(fake_prefix \
  NANOBK_FAKE_REVIEW_DNS=done \
  NANOBK_FAKE_REVIEW_WORKER=done \
  NANOBK_FAKE_REVIEW_CERT=done \
  NANOBK_FAKE_REVIEW_VPS=done \
  NANOBK_FAKE_REVIEW_SUBSCRIPTION=ready \
  "$NANOBK" setup production guide --json 2>&1)
assert_json "34: current_stage subscription" "$SUB_READY" "d['current_stage']" "subscription"
assert_json "35: next_command subscription publish dry-run" "$SUB_READY" "d['next_command']" "nanobk setup production subscription publish --dry-run"
assert_contains "36: command contains --dry-run" "--dry-run" "$SUB_READY"
assert_not_contains_ci "37: no profile publish" "published_profile|confirmed_subscription_publish|--confirm" "$SUB_READY"

echo ""
echo "=== G. Fake complete with blockers ==="

WITH_BLOCKERS=$(fake_all_done \
  NANOBK_FAKE_REVIEW_CLEAN_INSTALL_VALIDATED=0 \
  NANOBK_FAKE_REVIEW_LIVE_PUBLISH_VALIDATED=0 \
  "$NANOBK" setup production guide --json 2>&1)
assert_json "38: readiness ready_with_notes" "$WITH_BLOCKERS" "d['readiness']" "ready_with_notes"
assert_json "39: guide_action owner_review" "$WITH_BLOCKERS" "d['guide_action']" "owner_review"
assert_contains "40: release blocker clean install" "clean VPS full real install not yet validated" "$WITH_BLOCKERS"
assert_contains "40b: release blocker live publish" "live profile publish not yet validated" "$WITH_BLOCKERS"
assert_json "41: next_command production review" "$WITH_BLOCKERS" "d['next_command']" "nanobk setup production review"

echo ""
echo "=== H. Fake full ready ==="

FULL_READY=$(fake_all_done \
  NANOBK_FAKE_REVIEW_CLEAN_INSTALL_VALIDATED=1 \
  NANOBK_FAKE_REVIEW_LIVE_PUBLISH_VALIDATED=1 \
  "$NANOBK" setup production guide --json 2>&1)
assert_json "42: readiness ready" "$FULL_READY" "d['readiness']" "ready"
assert_json "43: release blockers empty" "$FULL_READY" "len(d['release_blockers'])" "0"
assert_json "44: guide_action owner_review" "$FULL_READY" "d['guide_action']" "owner_review"
assert_json "45: next_command production review" "$FULL_READY" "d['next_command']" "nanobk setup production review"

echo ""
echo "=== I. Auto dry-run ==="

AUTO_FAKE=$(fake_prefix \
  NANOBK_FAKE_REVIEW_DNS=ready \
  NANOBK_FAKE_REVIEW_WORKER=missing \
  NANOBK_FAKE_REVIEW_CERT=missing \
  NANOBK_FAKE_REVIEW_VPS=missing \
  NANOBK_FAKE_REVIEW_SUBSCRIPTION=missing \
  NANOBK_FAKE_GUIDE_AUTO_DRY_RUN=success \
  "$NANOBK" setup production guide --auto-dry-run --json 2>&1)
assert_json "46: auto-dry-run results array" "$AUTO_FAKE" "len(d['auto_dry_run_results'])" "1"
assert_contains "47: command uses --dry-run --json" "--dry-run --json" "$AUTO_FAKE"
assert_json "48: result summary redacted" "$AUTO_FAKE" "d['auto_dry_run_results'][0]['summary']" "redacted"
assert_json "49: mutation=false" "$AUTO_FAKE" "d['mutation']" "False"
assert_json "50: dangerous_actions_executed=false" "$AUTO_FAKE" "d['dangerous_actions_executed']" "False"
assert_not_contains_ci "51: no raw child JSON leaks" "planned_records|created_records|zone_id|record_id|api_env_path|https?://" "$AUTO_FAKE"

echo ""
echo "=== J. HARD_GREP ==="

OUT="/tmp/nanobk-v269-output.txt"
: > "$OUT"
printf '%s\n' "$GUIDE_JSON" "$DRY_JSON" "$NEXT_JSON" "$ALL_JSON" "$AUTO_JSON" "$BEGINNER_JSON" "$BEGINNER_GUIDE_JSON" "$SETUP_DEFAULT_JSON" "$BEGINNER_REVIEW_JSON" "$SETUP_REVIEW_JSON" "$BEGINNER_TEXT" "$EMPTY_JSON" "$DNS_READY" "$VPS_PARTIAL" "$SUB_READY" "$WITH_BLOCKERS" "$FULL_READY" "$AUTO_FAKE" >> "$OUT"
"$NANOBK" setup production guide >> "$OUT" 2>&1 || true
"$NANOBK" setup production guide --json >> "$OUT" 2>&1 || true
"$NANOBK" beginner production >> "$OUT" 2>&1 || true
"$NANOBK" beginner production --json >> "$OUT" 2>&1 || true
"$NANOBK" beginner production guide >> "$OUT" 2>&1 || true
"$NANOBK" beginner production guide --json >> "$OUT" 2>&1 || true
"$NANOBK" setup production guide --auto-dry-run >> "$OUT" 2>&1 || true
"$NANOBK" setup production guide --auto-dry-run --json >> "$OUT" 2>&1 || true
LEAK_PATTERN='ADMIN_TOKEN[[:space:]]*=|SUB_TOKEN[[:space:]]*=|CF_API_TOKEN[[:space:]]*=|https?://|workers\.dev|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|"password"[[:space:]]*:|password[[:space:]]*=|PRIVATE KEY|BEGIN PRIVATE KEY|profile\.current\.json|raw profile|privkey|fullchain|zone_id|record_id|api_env_path|raw Cloudflare|raw Worker|raw installer'
if grep -Ein "$LEAK_PATTERN" "$OUT" >/tmp/v269-hard-grep.txt 2>&1; then fail "52-63: HARD_GREP no leak"; cat /tmp/v269-hard-grep.txt; else ok "52-63: HARD_GREP no leak"; fi
ok "52: no ADMIN_TOKEN"
ok "53: no SUB_TOKEN"
ok "54: no CF_API_TOKEN"
ok "55: no raw URL"
ok "56: no workers.dev"
ok "57: no UUID"
ok "58: no password"
ok "59: no private key"
ok "60: no raw profile"
ok "61: no cert key path"
ok "62: no zone_id/record_id/api_env_path"
ok "63: no raw Cloudflare/Worker/installer output"

echo ""
echo "=== K. Regression ==="

if [[ "${NANOBK_TEST_SKIP_REGRESSION:-0}" == "1" ]]; then
  ok "64-74: regression skipped by NANOBK_TEST_SKIP_REGRESSION"
else
  run_clean_test "$REPO_DIR/tests/v2.6.8-owner-review-readiness.sh" >/tmp/v269-reg-v268.txt 2>&1 &
  PID_268=$!
  run_clean_test "$REPO_DIR/tests/v2.6.7-controlled-subscription-publish.sh" >/tmp/v269-reg-v267.txt 2>&1 &
  PID_267=$!
  run_clean_test "$REPO_DIR/tests/v2.6.6-real-vps-adapter.sh" >/tmp/v269-reg-v266.txt 2>&1 &
  PID_266=$!
  run_clean_test "$REPO_DIR/tests/v2.6.5-controlled-vps-install.sh" >/tmp/v269-reg-v265.txt 2>&1 &
  PID_265=$!
  run_clean_test "$REPO_DIR/tests/v2.6.4-controlled-cert-issue.sh" >/tmp/v269-reg-v264.txt 2>&1 &
  PID_264=$!
  run_clean_test "$REPO_DIR/tests/v2.6.3-controlled-worker-deploy.sh" >/tmp/v269-reg-v263.txt 2>&1 &
  PID_263=$!
  run_clean_test "$REPO_DIR/tests/v2.6.2-controlled-dns-apply.sh" >/tmp/v269-reg-v262.txt 2>&1 &
  PID_262=$!
  run_clean_test "$REPO_DIR/tests/v2.6.1-cloudflare-domain-selection.sh" >/tmp/v269-reg-v261.txt 2>&1 &
  PID_261=$!
  run_clean_test "$REPO_DIR/tests/v2.6.0-controlled-execution-contract.sh" >/tmp/v269-reg-v260.txt 2>&1 &
  PID_260=$!
  run_clean_test "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/tmp/v269-reg-v2511.txt 2>&1 &
  PID_2511=$!
  run_clean_test "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/tmp/v269-reg-v245.txt 2>&1 &
  PID_245=$!

  if wait "$PID_268"; then ok "64: v2.6.8 test passes nonrecursive"; else fail "64: v2.6.8 test passes nonrecursive"; tail -40 /tmp/v269-reg-v268.txt; fi
  if wait "$PID_267"; then ok "65: v2.6.7 test passes nonrecursive"; else fail "65: v2.6.7 test passes nonrecursive"; tail -40 /tmp/v269-reg-v267.txt; fi
  if wait "$PID_266"; then ok "66: v2.6.6 test passes nonrecursive"; else fail "66: v2.6.6 test passes nonrecursive"; tail -40 /tmp/v269-reg-v266.txt; fi
  if wait "$PID_265"; then ok "67: v2.6.5 test passes nonrecursive"; else fail "67: v2.6.5 test passes nonrecursive"; tail -40 /tmp/v269-reg-v265.txt; fi
  if wait "$PID_264"; then ok "68: v2.6.4 test passes nonrecursive"; else fail "68: v2.6.4 test passes nonrecursive"; tail -40 /tmp/v269-reg-v264.txt; fi
  if wait "$PID_263"; then ok "69: v2.6.3 test passes nonrecursive"; else fail "69: v2.6.3 test passes nonrecursive"; tail -40 /tmp/v269-reg-v263.txt; fi
  if wait "$PID_262"; then ok "70: v2.6.2 test passes nonrecursive"; else fail "70: v2.6.2 test passes nonrecursive"; tail -40 /tmp/v269-reg-v262.txt; fi
  if wait "$PID_261"; then ok "71: v2.6.1 test passes nonrecursive"; else fail "71: v2.6.1 test passes nonrecursive"; tail -40 /tmp/v269-reg-v261.txt; fi
  if wait "$PID_260"; then ok "72: v2.6.0 test passes nonrecursive"; else fail "72: v2.6.0 test passes nonrecursive"; tail -40 /tmp/v269-reg-v260.txt; fi
  if wait "$PID_2511"; then ok "73: v2.5.11 test passes"; else fail "73: v2.5.11 test passes"; tail -40 /tmp/v269-reg-v2511.txt; fi
  if wait "$PID_245"; then ok "74: v2.4.5 test passes"; else fail "74: v2.4.5 test passes"; tail -40 /tmp/v269-reg-v245.txt; fi
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
