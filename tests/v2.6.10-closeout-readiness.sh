#!/usr/bin/env bash
# v2.6.10 Closeout / Release Candidate Preparation Test
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
CLOSEOUT="$REPO_DIR/docs/v2.6-closeout-production-readiness.md"
PLAN="$REPO_DIR/docs/v2.7-real-beginner-acceptance-plan.md"
MAP="$REPO_DIR/docs/production-command-map.md"

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

assert_file() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then ok "$label"; else fail "$label"; fi
}

assert_contains_file() {
  local label="$1" pattern="$2" path="$3"
  if grep -qF -- "$pattern" "$path"; then ok "$label"; else fail "$label (missing: $pattern)"; fi
}

assert_contains_text() {
  local label="$1" pattern="$2" text="$3"
  if printf '%s\n' "$text" | grep -qF -- "$pattern"; then ok "$label"; else fail "$label (missing: $pattern)"; fi
}

assert_valid_json() {
  local label="$1" json="$2"
  if printf '%s\n' "$json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then ok "$label"; else fail "$label"; fi
}

assert_json() {
  local label="$1" json="$2" expr="$3" expected="$4"
  local actual
  actual=$(printf '%s\n' "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print($expr)" 2>/dev/null || echo "PARSE_ERROR")
  if [[ "$actual" == "$expected" ]]; then ok "$label"; else fail "$label (expected '$expected', got '$actual')"; fi
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

echo "=== A. Docs exist ==="
assert_file "1: closeout doc exists" "$CLOSEOUT"
assert_file "2: v2.7 acceptance plan exists" "$PLAN"
assert_file "3: production command map exists" "$MAP"

echo ""
echo "=== B. Docs contain required status matrix ==="
assert_contains_file "4: v2.6.0 PASS" "v2.6.0 | Execution contract | PASS" "$CLOSEOUT"
assert_contains_file "5: v2.6.1 PASS" "v2.6.1 | Cloudflare/domain | PASS" "$CLOSEOUT"
assert_contains_file "6: v2.6.2 PASS WITH NOTE" "v2.6.2 | DNS apply | PASS WITH NOTE" "$CLOSEOUT"
assert_contains_file "7: v2.6.3 PASS WITH NOTE" "v2.6.3 | Worker deploy | PASS WITH NOTE" "$CLOSEOUT"
assert_contains_file "8: v2.6.4 PASS WITH NOTE" "v2.6.4 | Cert issue | PASS WITH NOTE" "$CLOSEOUT"
assert_contains_file "9: v2.6.5 PASS WITH NOTE" "v2.6.5 | VPS install wrapper | PASS WITH NOTE" "$CLOSEOUT"
assert_contains_file "10: v2.6.6 PASS WITH NOTE" "v2.6.6 | Real legacy VPS installer adapter | PASS WITH NOTE" "$CLOSEOUT"
assert_contains_file "11: v2.6.7 PASS WITH NOTE" "v2.6.7 | Subscription profile publish | PASS WITH NOTE" "$CLOSEOUT"
assert_contains_file "12: v2.6.8 PASS WITH NOTE" "v2.6.8 | Owner review/readiness | PASS WITH NOTE" "$CLOSEOUT"
assert_contains_file "13: v2.6.9 PASS WITH NOTE" "v2.6.9 | Guided one-command flow | PASS WITH NOTE" "$CLOSEOUT"

echo ""
echo "=== C. Release blockers remain visible ==="
assert_contains_file "14: clean VPS blocker visible" "clean VPS full real install not yet validated" "$CLOSEOUT"
assert_contains_file "15: live profile publish blocker visible" "live profile publish not yet validated" "$CLOSEOUT"

echo ""
echo "=== D. v2.7 plan contains required tests ==="
assert_contains_file "16: T29-CLEAN" "T29-CLEAN" "$PLAN"
assert_contains_file "17: T30-LIVE" "T30-LIVE" "$PLAN"
assert_contains_file "18: T33-BEGINNER" "T33-BEGINNER" "$PLAN"
assert_contains_file "19: T34-FAILURE" "T34-FAILURE" "$PLAN"
assert_contains_file "20: T35-LEAK" "T35-LEAK" "$PLAN"
assert_contains_file "21: T36-DOCS" "T36-DOCS" "$PLAN"

echo ""
echo "=== E. Command map contains key commands ==="
assert_contains_file "22: nanobk beginner production" "nanobk beginner production" "$MAP"
assert_contains_file "23: nanobk setup production guide" "nanobk setup production guide" "$MAP"
assert_contains_file "24: nanobk setup production review" "nanobk setup production review" "$MAP"
assert_contains_file "25: dns apply dry-run" "nanobk setup production dns apply --dry-run" "$MAP"
assert_contains_file "26: worker deploy dry-run" "nanobk setup production worker deploy --dry-run" "$MAP"
assert_contains_file "27: cert issue dry-run" "nanobk setup production cert issue --dry-run" "$MAP"
assert_contains_file "28: vps install dry-run" "nanobk setup production vps install --dry-run" "$MAP"
assert_contains_file "29: subscription publish dry-run" "nanobk setup production subscription publish --dry-run" "$MAP"

echo ""
echo "=== F. CLI smoke ==="
HELP=$("$NANOBK" --help 2>&1)
assert_contains_text "30: help contains beginner production" "beginner production" "$HELP"
assert_contains_text "31: help contains setup production guide" "setup production guide" "$HELP"
SETUP_JSON=$("$NANOBK" setup production --json 2>&1)
BEGINNER_JSON=$("$NANOBK" beginner production --json 2>&1)
REVIEW_JSON=$("$NANOBK" setup production review --json 2>&1)
assert_valid_json "32: setup production --json valid" "$SETUP_JSON"
assert_valid_json "33: beginner production --json valid" "$BEGINNER_JSON"
assert_json "34a: setup production guided flow" "$SETUP_JSON" "d['mode']" "production_guided_flow_v2_6"
assert_json "34b: beginner production guided flow" "$BEGINNER_JSON" "d['mode']" "production_guided_flow_v2_6"
assert_json "34c: setup production version 2.6.9" "$SETUP_JSON" "d['version']" "2.6.9"
assert_json "34d: beginner production version 2.6.9" "$BEGINNER_JSON" "d['version']" "2.6.9"
assert_valid_json "35: setup production review --json valid" "$REVIEW_JSON"
assert_json "36a: review owner mode" "$REVIEW_JSON" "d['mode']" "production_owner_review_v2_6"
assert_json "36b: review version 2.6.8" "$REVIEW_JSON" "d['version']" "2.6.8"

echo ""
echo "=== G. Safety grep ==="
OUT="/tmp/nanobk-v2610-doc-help-output.txt"
: > "$OUT"
cat "$CLOSEOUT" "$PLAN" "$MAP" >> "$OUT"
printf '%s\n' "$HELP" "$SETUP_JSON" "$BEGINNER_JSON" "$REVIEW_JSON" >> "$OUT"
LEAK_PATTERN='ADMIN_TOKEN[[:space:]]*=|SUB_TOKEN[[:space:]]*=|CF_API_TOKEN[[:space:]]*=|NANOB_TOKEN[[:space:]]*=|Authorization:[[:space:]]*Bearer|Bearer[[:space:]][A-Za-z0-9._~+/=-]{12,}|workers\.dev|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|"password"[[:space:]]*:|password[[:space:]]*=|PRIVATE KEY|BEGIN PRIVATE KEY|privkey|fullchain|zone_id|record_id|api_env_path|raw Cloudflare|raw Worker|raw installer|HY2_PASSWORD|TUIC_PASSWORD|REALITY_PRIVATE_KEY|TROJAN_PASSWORD'
if grep -Ein "$LEAK_PATTERN" "$OUT" >/tmp/v2610-hard-grep.txt 2>&1; then fail "37-42: docs/help HARD_GREP clean"; cat /tmp/v2610-hard-grep.txt; else ok "37-42: docs/help HARD_GREP clean"; fi

echo ""
echo "=== H. Regression ==="
if run_clean_test "$REPO_DIR/tests/v2.6.9-guided-production-flow.sh" >/tmp/v2610-v269.log 2>&1; then ok "43: v2.6.9 test passes nonrecursive"; else fail "43: v2.6.9 test passes nonrecursive"; tail -40 /tmp/v2610-v269.log; fi
if run_clean_test "$REPO_DIR/tests/v2.6.8-owner-review-readiness.sh" >/tmp/v2610-v268.log 2>&1; then ok "44: v2.6.8 test passes nonrecursive"; else fail "44: v2.6.8 test passes nonrecursive"; tail -40 /tmp/v2610-v268.log; fi
if run_clean_test "$REPO_DIR/tests/v2.6.7-controlled-subscription-publish.sh" >/tmp/v2610-v267.log 2>&1; then ok "45: v2.6.7 test passes nonrecursive"; else fail "45: v2.6.7 test passes nonrecursive"; tail -40 /tmp/v2610-v267.log; fi
if run_clean_test "$REPO_DIR/tests/v2.6.6-real-vps-adapter.sh" >/tmp/v2610-v266.log 2>&1; then ok "46: v2.6.6 test passes nonrecursive"; else fail "46: v2.6.6 test passes nonrecursive"; tail -40 /tmp/v2610-v266.log; fi
if run_clean_test "$REPO_DIR/tests/v2.6.5-controlled-vps-install.sh" >/tmp/v2610-v265.log 2>&1; then ok "47: v2.6.5 test passes nonrecursive"; else fail "47: v2.6.5 test passes nonrecursive"; tail -40 /tmp/v2610-v265.log; fi
if run_clean_test "$REPO_DIR/tests/v2.6.4-controlled-cert-issue.sh" >/tmp/v2610-v264.log 2>&1; then ok "48: v2.6.4 test passes nonrecursive"; else fail "48: v2.6.4 test passes nonrecursive"; tail -40 /tmp/v2610-v264.log; fi
if run_clean_test "$REPO_DIR/tests/v2.6.3-controlled-worker-deploy.sh" >/tmp/v2610-v263.log 2>&1; then ok "49: v2.6.3 test passes nonrecursive"; else fail "49: v2.6.3 test passes nonrecursive"; tail -40 /tmp/v2610-v263.log; fi
if run_clean_test "$REPO_DIR/tests/v2.6.2-controlled-dns-apply.sh" >/tmp/v2610-v262.log 2>&1; then ok "50: v2.6.2 test passes nonrecursive"; else fail "50: v2.6.2 test passes nonrecursive"; tail -40 /tmp/v2610-v262.log; fi
if run_clean_test "$REPO_DIR/tests/v2.6.1-cloudflare-domain-selection.sh" >/tmp/v2610-v261.log 2>&1; then ok "51: v2.6.1 test passes nonrecursive"; else fail "51: v2.6.1 test passes nonrecursive"; tail -40 /tmp/v2610-v261.log; fi
if run_clean_test "$REPO_DIR/tests/v2.6.0-controlled-execution-contract.sh" >/tmp/v2610-v260.log 2>&1; then ok "52: v2.6.0 test passes nonrecursive"; else fail "52: v2.6.0 test passes nonrecursive"; tail -40 /tmp/v2610-v260.log; fi
if run_clean_test "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/tmp/v2610-v2511.log 2>&1; then ok "53: v2.5.11 test passes"; else fail "53: v2.5.11 test passes"; tail -40 /tmp/v2610-v2511.log; fi
if run_clean_test "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/tmp/v2610-v245.log 2>&1; then ok "54: v2.4.5 test passes"; else fail "54: v2.4.5 test passes"; tail -40 /tmp/v2610-v245.log; fi

echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
