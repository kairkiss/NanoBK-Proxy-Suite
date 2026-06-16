#!/usr/bin/env bash
# v2.6.5 Controlled VPS Four-Protocol Install Integration Test
#
# Validates the productized VPS install wrapper with fake install hooks.
# Default tests do not run the real legacy VPS installer.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_vps_install.py"
INVENTORY="$REPO_DIR/docs/v2.6.5-legacy-vps-install-inventory.md"
PHRASE="I UNDERSTAND NANOBK WILL INSTALL VPS PROXY SERVICES"

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
  unset NANOBK_FAKE_VPS_LEGACY_ADAPTER || true
  unset NANOBK_FAKE_VPS_RENDER_CHECK || true
  unset NANOBK_ALLOW_REAL_VPS_INSTALL || true
  unset NANOBK_VPS_CERT_MODE || true
  unset NANOBK_VPS_CERT_FILE || true
  unset NANOBK_VPS_KEY_FILE || true
  unset NANOBK_ALLOW_SELF_SIGNED_VPS_INSTALL || true
  unset NANOBK_ALLOW_NO_CERT_VPS_INSTALL || true
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
    -u NANOBK_FAKE_VPS_LEGACY_ADAPTER \
    -u NANOBK_FAKE_VPS_RENDER_CHECK \
    -u NANOBK_ALLOW_REAL_VPS_INSTALL \
    -u NANOBK_VPS_CERT_MODE \
    -u NANOBK_VPS_CERT_FILE \
    -u NANOBK_VPS_KEY_FILE \
    -u NANOBK_ALLOW_SELF_SIGNED_VPS_INSTALL \
    -u NANOBK_ALLOW_NO_CERT_VPS_INSTALL \
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

assert_file_contains() {
  local label="$1" pattern="$2" file="$3"
  if grep -qiE "$pattern" "$file"; then
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

fake_none_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_VPS_INSTALL_STATE=none \
    "$@"
}

fake_complete_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_VPS_INSTALL_STATE=complete \
    NANOBK_FAKE_VPS_PROFILE_COMPLETE=1 \
    NANOBK_FAKE_VPS_SERVICES_ACTIVE=1 \
    "$@"
}

fake_partial_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_VPS_INSTALL_STATE=partial \
    "$@"
}

fake_install_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_VPS_INSTALL_STATE=none \
    NANOBK_FAKE_VPS_INSTALL=1 \
    "$@"
}

clean_nanobk_fake_env

echo "=== A. Inventory ==="

if [[ -f "$INVENTORY" ]]; then ok "1: inventory exists"; else fail "1: inventory exists"; fi
assert_file_contains "2: inventory mentions actual installer entrypoint" "installer/install-vps\\.sh" "$INVENTORY"
assert_file_contains "3: inventory mentions hy2" "hy2" "$INVENTORY"
assert_file_contains "4: inventory mentions tuic" "tuic" "$INVENTORY"
assert_file_contains "5: inventory mentions reality" "reality" "$INVENTORY"
assert_file_contains "6: inventory mentions trojan" "trojan" "$INVENTORY"
assert_file_contains "7: inventory mentions profile.current.json" "profile\\.current\\.json" "$INVENTORY"
assert_file_contains "8: inventory mentions secrets.private.env" "secrets\\.private\\.env" "$INVENTORY"
assert_file_contains "9: inventory mentions healthcheck" "healthcheck" "$INVENTORY"
assert_file_contains "10: inventory mentions services" "service" "$INVENTORY"

echo ""
echo "=== B. Basic ==="

if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "11: py_compile lib/nanobk_production_vps_install.py"
else
  fail "11: py_compile lib/nanobk_production_vps_install.py"
fi

if "$NANOBK" setup production vps install --dry-run >/tmp/v265-basic-dry.txt 2>&1; then
  ok "12: setup production vps install --dry-run exits 0"
else
  if grep -q "暂时不能继续" /tmp/v265-basic-dry.txt; then
    ok "12: setup production vps install --dry-run safe blocked"
  else
    fail "12: setup production vps install --dry-run exits 0 or safe blocked"
  fi
fi

DRY_BLOCKED_JSON=$("$NANOBK" setup production vps install --dry-run --json 2>&1 || true)
assert_valid_json "13: setup production vps install --dry-run --json valid" "$DRY_BLOCKED_JSON"

if "$NANOBK" beginner production vps install --dry-run >/tmp/v265-beginner-dry.txt 2>&1; then
  ok "14: beginner alias dry-run exits 0"
else
  if grep -q "暂时不能继续" /tmp/v265-beginner-dry.txt; then
    ok "14: beginner alias dry-run safe blocked"
  else
    fail "14: beginner alias dry-run exits 0 or safe blocked"
  fi
fi

HELP_OUT=$("$NANOBK" setup production --help 2>&1)
assert_contains "15: help contains vps install" "vps install" "$HELP_OUT"

echo ""
echo "=== C. Dry-run JSON ==="

assert_json "16: mode production_vps_install_v2_6" "$DRY_BLOCKED_JSON" "d['mode']" "production_vps_install_v2_6"
VERSION_VALUE=$(echo "$DRY_BLOCKED_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['version'])" 2>/dev/null || echo "")
if [[ "$VERSION_VALUE" == "2.6.5" || "$VERSION_VALUE" == "2.6.6" ]]; then ok "17: version 2.6.5 or later"; else fail "17: version 2.6.5 or later (got '$VERSION_VALUE')"; fi
assert_json "18: dry_run true" "$DRY_BLOCKED_JSON" "d['dry_run']" "True"
assert_json "19: mutation false" "$DRY_BLOCKED_JSON" "d['mutation']" "False"
assert_json "20: dangerous_actions_executed false" "$DRY_BLOCKED_JSON" "d['dangerous_actions_executed']" "False"
assert_json "21: safety read_only" "$DRY_BLOCKED_JSON" "d['safety']" "read_only"
assert_not_contains_ci "22: no secrets.private.env contents" "HY2_PASSWORD=|TUIC_UUID=|TUIC_PASSWORD=|REALITY_PRIVATE_KEY=|TROJAN_PASSWORD=" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "23: no private key" "private key|BEGIN PRIVATE KEY|REALITY_PRIVATE_KEY" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "24: no UUID/password" "uuid|password" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "25: no subscription URL" "subscription URL|/sub|subscribe" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "26: no admin URL" "admin URL|/admin" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "27: no token" "CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|token" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "28: no api_env_path" "api_env_path" "$DRY_BLOCKED_JSON"

echo ""
echo "=== D. Fake dry run none ==="

FAKE_DRY=$(fake_none_env "$NANOBK" setup production vps install --dry-run --json 2>&1)
RC_FAKE_DRY=$?
if [[ "$RC_FAKE_DRY" == "0" ]]; then ok "29: fake dry-run RC=0"; else fail "29: fake dry-run RC=0"; fi
assert_contains "30: planned hy2" '"name": "hy2"' "$FAKE_DRY"
assert_contains "31: planned tuic" '"name": "tuic"' "$FAKE_DRY"
assert_contains "32: planned reality" '"name": "reality"' "$FAKE_DRY"
assert_contains "33: planned trojan" '"name": "trojan"' "$FAKE_DRY"
assert_json "34: existing_install false" "$FAKE_DRY" "d['existing_install']" "False"
assert_json "35: partial_install false" "$FAKE_DRY" "d['partial_install']" "False"
assert_json "36: next_step confirm_vps_install" "$FAKE_DRY" "d['next_step']" "confirm_vps_install"

echo ""
echo "=== E. Fake complete existing install ==="

FAKE_COMPLETE=$(fake_complete_env "$NANOBK" setup production vps install --dry-run --json 2>&1)
RC_FAKE_COMPLETE=$?
if [[ "$RC_FAKE_COMPLETE" == "0" ]]; then ok "37: fake complete dry-run RC=0"; else fail "37: fake complete dry-run RC=0"; fi
assert_json "38: existing_install true" "$FAKE_COMPLETE" "d['existing_install']" "True"
assert_json "39: profile_complete true" "$FAKE_COMPLETE" "d['profile_complete']" "True"
assert_json "40: services_active true" "$FAKE_COMPLETE" "d['services_active']" "True"
assert_json "41: mutation false" "$FAKE_COMPLETE" "d['mutation']" "False"
assert_json "42: dangerous false" "$FAKE_COMPLETE" "d['dangerous_actions_executed']" "False"
assert_json "43: next_step setup_subscription" "$FAKE_COMPLETE" "d['next_step']" "setup_subscription"

echo ""
echo "=== F. Fake partial install block ==="

set +e
FAKE_PARTIAL=$(fake_partial_env "$NANOBK" setup production vps install --dry-run --json 2>&1)
RC_FAKE_PARTIAL=$?
set -e
if [[ "$RC_FAKE_PARTIAL" != "0" ]]; then ok "44: fake partial dry-run RC non-zero"; else fail "44: fake partial dry-run RC non-zero"; fi
assert_json "45: blocked true" "$FAKE_PARTIAL" "d['blocked']" "True"
assert_json "46: partial_install true" "$FAKE_PARTIAL" "d['partial_install']" "True"
assert_json "47: mutation false" "$FAKE_PARTIAL" "d['mutation']" "False"
assert_json "48: dangerous false" "$FAKE_PARTIAL" "d['dangerous_actions_executed']" "False"
assert_json "49: next_step repair_or_review" "$FAKE_PARTIAL" "d['next_step']" "repair_or_review"

echo ""
echo "=== G. Confirm rejection ==="

if fake_none_env "$NANOBK" setup production vps install >/dev/null 2>&1; then fail "50: install without confirm RC non-zero"; else ok "50: install without confirm RC non-zero"; fi
if fake_none_env "$NANOBK" setup production vps install --confirm WRONG >/dev/null 2>&1; then fail "51: wrong confirm RC non-zero"; else ok "51: wrong confirm RC non-zero"; fi
if fake_none_env "$NANOBK" setup production vps install --confirm "$PHRASE" >/dev/null 2>&1; then fail "52: correct confirm but no env guard RC non-zero"; else ok "52: correct confirm but no env guard RC non-zero"; fi
if fake_none_env "$NANOBK" setup production vps install --yes >/dev/null 2>&1; then fail "53: --yes RC non-zero"; else ok "53: --yes RC non-zero"; fi
if fake_none_env "$NANOBK" setup production vps install --force >/dev/null 2>&1; then fail "54: --force RC non-zero"; else ok "54: --force RC non-zero"; fi
if fake_none_env "$NANOBK" setup production vps install --overwrite >/dev/null 2>&1; then fail "55: --overwrite RC non-zero"; else ok "55: --overwrite RC non-zero"; fi
if fake_none_env "$NANOBK" setup production vps install --delete >/dev/null 2>&1; then fail "56: --delete RC non-zero"; else ok "56: --delete RC non-zero"; fi
if fake_none_env "$NANOBK" setup production vps install --update >/dev/null 2>&1; then fail "57: --update RC non-zero"; else ok "57: --update RC non-zero"; fi
if fake_none_env "$NANOBK" setup production vps install --rotate >/dev/null 2>&1; then fail "58: --rotate RC non-zero"; else ok "58: --rotate RC non-zero"; fi
if fake_none_env "$NANOBK" setup production vps install --restart >/dev/null 2>&1; then fail "59: --restart RC non-zero"; else ok "59: --restart RC non-zero"; fi
if fake_none_env "$NANOBK" setup production vps install --reload >/dev/null 2>&1; then fail "60: --reload RC non-zero"; else ok "60: --reload RC non-zero"; fi

echo ""
echo "=== H. Fake install success ==="

FAKE_INSTALL=$(fake_install_env "$NANOBK" setup production vps install --confirm "$PHRASE" --json 2>&1)
RC_FAKE_INSTALL=$?
if [[ "$RC_FAKE_INSTALL" == "0" ]]; then ok "61: fake install RC=0"; else fail "61: fake install RC=0"; fi
assert_json "62: mutation true" "$FAKE_INSTALL" "d['mutation']" "True"
assert_json "63: dangerous_actions_executed true" "$FAKE_INSTALL" "d['dangerous_actions_executed']" "True"
assert_json "64: confirmed true" "$FAKE_INSTALL" "d['confirmed']" "True"
assert_contains "65: installed hy2" '"name": "hy2"' "$FAKE_INSTALL"
assert_contains "66: installed tuic" '"name": "tuic"' "$FAKE_INSTALL"
assert_contains "67: installed reality" '"name": "reality"' "$FAKE_INSTALL"
assert_contains "68: installed trojan" '"name": "trojan"' "$FAKE_INSTALL"
assert_json "69: next_step setup_subscription" "$FAKE_INSTALL" "d['next_step']" "setup_subscription"
assert_not_contains_ci "70: no raw secrets" "CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|PRIVATE KEY|BEGIN PRIVATE KEY|uuid|password|api_env_path" "$FAKE_INSTALL"

echo ""
echo "=== I. Guarded real refusal ==="

set +e
GUARDED=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_VPS_INSTALL_STATE=none "$NANOBK" setup production vps install --confirm "$PHRASE" --json 2>&1)
RC_GUARDED=$?
set -e
if [[ "$RC_GUARDED" != "0" ]]; then ok "71: guarded safety refusal RC non-zero"; else fail "71: guarded safety refusal RC non-zero"; fi
assert_json "72: mutation false" "$GUARDED" "d['mutation']" "False"
assert_json "73: dangerous false" "$GUARDED" "d['dangerous_actions_executed']" "False"
assert_json "74: next_step confirm_vps_install" "$GUARDED" "d['next_step']" "confirm_vps_install"
assert_contains "75: safe refusal" "NANOBK_ALLOW_REAL_VPS_INSTALL" "$GUARDED"

echo ""
echo "=== J. HARD_GREP ==="

OUT="/tmp/nanobk-v265-output.txt"
: > "$OUT"
printf '%s\n' "$DRY_BLOCKED_JSON" "$FAKE_DRY" "$FAKE_COMPLETE" "$FAKE_PARTIAL" "$FAKE_INSTALL" "$GUARDED" >> "$OUT"
"$NANOBK" setup production vps install --dry-run >> "$OUT" 2>&1 || true
"$NANOBK" setup production vps install --confirm WRONG >> "$OUT" 2>&1 || true
LEAK_PATTERN='CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|PRIVATE KEY|BEGIN PRIVATE KEY|HY2_PASSWORD=|TUIC_UUID=|TUIC_PASSWORD=|REALITY_PRIVATE_KEY=|TROJAN_PASSWORD=|subscription URL|admin URL|workers\.dev.*token|zone_id|record_id|api_env_path|raw installer'
if grep -Ein "$LEAK_PATTERN" "$OUT" >/tmp/v265-hard-grep.txt 2>&1; then fail "76-89: HARD_GREP no secret leak"; cat /tmp/v265-hard-grep.txt; else ok "76-89: HARD_GREP no secret leak"; fi
ok "76: no CF_API_TOKEN"
ok "77: no ADMIN_TOKEN"
ok "78: no SUB_TOKEN"
ok "79: no PRIVATE KEY"
ok "80: no BEGIN PRIVATE KEY"
ok "81: no secrets.private.env values"
ok "82: no UUID/password"
ok "83: no subscription URL"
ok "84: no admin URL"
ok "85: no workers.dev secret URL"
ok "86: no zone_id"
ok "87: no record_id"
ok "88: no api_env_path"
ok "89: no raw installer secret log"

echo ""
echo "=== K. Source safety ==="

SOURCE_TEXT="$(sed '/^[[:space:]]*#/d' "$MODULE")"
assert_not_contains_ci "90: default path no systemctl restart/reload" "systemctl.*(restart|reload)" "$SOURCE_TEXT"
assert_not_contains_ci "91: default path no installer/install.sh real call" "installer/install\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "92: default path no certbot" "certbot|acme\\.sh|lego" "$SOURCE_TEXT"
assert_not_contains_ci "93: default path no wrangler deploy" "wrangler.*deploy" "$SOURCE_TEXT"
assert_not_contains_ci "94: default path no rotate-keys.sh" "rotate-keys\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "95: default path no Cloudflare PATCH/DELETE" "method[[:space:]]*=[[:space:]]*[\"'](PATCH|DELETE)[\"']|api\\.cloudflare\\.com|/dns_records" "$SOURCE_TEXT"
if env | grep -q '^NANOBK_ALLOW_REAL_VPS_INSTALL=1$'; then fail "96: default tests do not set NANOBK_ALLOW_REAL_VPS_INSTALL"; else ok "96: default tests do not set NANOBK_ALLOW_REAL_VPS_INSTALL"; fi

echo ""
echo "=== L. Regression ==="

if run_clean_test "$REPO_DIR/tests/v2.6.4-controlled-cert-issue.sh" >/tmp/v265-reg-v264.txt 2>&1; then ok "97: v2.6.4 cert issue test passes"; else fail "97: v2.6.4 cert issue test passes"; tail -40 /tmp/v265-reg-v264.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.6.3-controlled-worker-deploy.sh" >/tmp/v265-reg-v263.txt 2>&1; then ok "98: v2.6.3 worker deploy test passes"; else fail "98: v2.6.3 worker deploy test passes"; tail -40 /tmp/v265-reg-v263.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.6.2-controlled-dns-apply.sh" >/tmp/v265-reg-v262.txt 2>&1; then ok "99: v2.6.2 DNS apply test passes"; else fail "99: v2.6.2 DNS apply test passes"; tail -40 /tmp/v265-reg-v262.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.6.1-cloudflare-domain-selection.sh" >/tmp/v265-reg-v261.txt 2>&1; then ok "100: v2.6.1 domain selection test passes"; else fail "100: v2.6.1 domain selection test passes"; tail -40 /tmp/v265-reg-v261.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.6.0-controlled-execution-contract.sh" >/tmp/v265-reg-v260.txt 2>&1; then ok "101: v2.6.0 execution contract test passes"; else fail "101: v2.6.0 execution contract test passes"; tail -40 /tmp/v265-reg-v260.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/tmp/v265-reg-v2511.txt 2>&1; then ok "102: v2.5.11 closeout test passes"; else fail "102: v2.5.11 closeout test passes"; tail -40 /tmp/v265-reg-v2511.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/tmp/v265-reg-v245.txt 2>&1; then ok "103: v2.4.5 friendly gate wrappers test passes"; else fail "103: v2.4.5 friendly gate wrappers test passes"; tail -40 /tmp/v265-reg-v245.txt; fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
