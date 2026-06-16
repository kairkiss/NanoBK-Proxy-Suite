#!/usr/bin/env bash
# v2.6.6 Real Legacy VPS Installer Adapter Test
#
# Validates render-only proving, guarded real-adapter command behavior, redaction,
# and regressions. Default tests do not run a real VPS install.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_vps_install.py"
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
  unset NANOBK_VPS_REALITY_SERVERNAME || true
  unset NANOBK_VPS_EMAIL || true
  unset NANOBK_VPS_IP || true
  unset NANOBK_VPS_OPEN_FIREWALL || true
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
    -u NANOBK_VPS_REALITY_SERVERNAME \
    -u NANOBK_VPS_EMAIL \
    -u NANOBK_VPS_IP \
    -u NANOBK_VPS_OPEN_FIREWALL \
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

fake_none_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_VPS_IPV4=203.0.113.10 \
    NANOBK_FAKE_VPS_INSTALL_STATE=none \
    "$@"
}

clean_nanobk_fake_env

echo "=== A. Basic ==="

if python3 -m py_compile "$MODULE" 2>/dev/null; then ok "1: py_compile lib/nanobk_production_vps_install.py"; else fail "1: py_compile lib/nanobk_production_vps_install.py"; fi
HELP_OUT=$("$NANOBK" setup production --help 2>&1)
assert_contains "2: help contains --render-check" "--render-check" "$HELP_OUT"
RENDER_JSON=$(fake_none_env "$NANOBK" setup production vps install --render-check --json 2>&1)
RC_RENDER=$?
assert_valid_json "3: render-check JSON valid" "$RENDER_JSON"
assert_json "4: version 2.6.6" "$RENDER_JSON" "d['version']" "2.6.6"
assert_json "5: mode production_vps_install_v2_6" "$RENDER_JSON" "d['mode']" "production_vps_install_v2_6"

echo ""
echo "=== B. Render-only adapter ==="

if [[ "$RC_RENDER" == "0" ]]; then ok "6: render-check RC=0"; else fail "6: render-check RC=0"; fi
assert_json "7: mutation false" "$RENDER_JSON" "d['mutation']" "False"
assert_json "8: dangerous false" "$RENDER_JSON" "d['dangerous_actions_executed']" "False"
assert_json "9: render_check true" "$RENDER_JSON" "d['render_check']" "True"
assert_contains "10: rendered hy2" '"hy2"' "$RENDER_JSON"
assert_contains "11: rendered tuic" '"tuic"' "$RENDER_JSON"
assert_contains "12: rendered reality" '"reality"' "$RENDER_JSON"
assert_contains "13: rendered trojan" '"trojan"' "$RENDER_JSON"
assert_json "14: render_dir redacted" "$RENDER_JSON" "d['render_dir']" "redacted"
assert_not_contains_ci "15: no systemctl restart/reload" "systemctl.*(restart|reload)|daemon-reload|enable --now" "$RENDER_JSON"
assert_not_contains_ci "16: no /etc mutation path output" "/etc/nanobk|/etc/hysteria|/etc/proxy-stack|/opt/nanobk" "$RENDER_JSON"
assert_not_contains_ci "17: no raw secrets in output" "CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|PRIVATE KEY|BEGIN PRIVATE KEY|uuid|password|token|secret|api_env_path" "$RENDER_JSON"

echo ""
echo "=== C. Real install blocked cases ==="

set +e
NO_GUARD=$(fake_none_env "$NANOBK" setup production vps install --confirm "$PHRASE" --json 2>&1)
RC_NO_GUARD=$?
NO_CERT=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_VPS_INSTALL_STATE=none NANOBK_FAKE_VPS_LEGACY_ADAPTER=success NANOBK_ALLOW_REAL_VPS_INSTALL=1 "$NANOBK" setup production vps install --confirm "$PHRASE" --json 2>&1)
RC_NO_CERT=$?
SELF_SIGNED_BLOCK=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_VPS_INSTALL_STATE=none NANOBK_FAKE_VPS_LEGACY_ADAPTER=success NANOBK_ALLOW_REAL_VPS_INSTALL=1 NANOBK_VPS_CERT_MODE=self-signed "$NANOBK" setup production vps install --confirm "$PHRASE" --json 2>&1)
RC_SELF_SIGNED_BLOCK=$?
NO_CERT_MODE_BLOCK=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_VPS_INSTALL_STATE=none NANOBK_FAKE_VPS_LEGACY_ADAPTER=success NANOBK_ALLOW_REAL_VPS_INSTALL=1 NANOBK_VPS_CERT_MODE=none "$NANOBK" setup production vps install --confirm "$PHRASE" --json 2>&1)
RC_NO_CERT_MODE_BLOCK=$?
PARTIAL=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_VPS_INSTALL_STATE=partial "$NANOBK" setup production vps install --confirm "$PHRASE" --json 2>&1)
RC_PARTIAL=$?
COMPLETE=$(env NANOBK_FAKE_SELECTED_DOMAIN=example.com NANOBK_FAKE_VPS_INSTALL_STATE=complete "$NANOBK" setup production vps install --confirm "$PHRASE" --json 2>&1)
RC_COMPLETE=$?
WRONG=$(fake_none_env "$NANOBK" setup production vps install --confirm WRONG --json 2>&1)
RC_WRONG=$?
NO_PHRASE=$(fake_none_env "$NANOBK" setup production vps install --json 2>&1)
RC_NO_PHRASE=$?
set -e
if [[ "$RC_NO_GUARD" != "0" ]]; then ok "18: exact phrase but no env guard blocks"; else fail "18: exact phrase but no env guard blocks"; fi
if [[ "$RC_NO_CERT" != "0" ]]; then ok "19: env guard but no cert files blocks"; else fail "19: env guard but no cert files blocks"; fi
if [[ "$RC_SELF_SIGNED_BLOCK" != "0" ]]; then ok "20: cert-mode self-signed without allow blocks"; else fail "20: cert-mode self-signed without allow blocks"; fi
if [[ "$RC_NO_CERT_MODE_BLOCK" != "0" ]]; then ok "21: cert-mode none without allow blocks"; else fail "21: cert-mode none without allow blocks"; fi
if [[ "$RC_PARTIAL" != "0" ]]; then ok "22: partial install blocks"; else fail "22: partial install blocks"; fi
if [[ "$RC_COMPLETE" == "0" ]]; then ok "23: existing complete returns mutation=false"; else fail "23: existing complete returns mutation=false"; fi
assert_json "23b: existing complete mutation false" "$COMPLETE" "d['mutation']" "False"
if [[ "$RC_WRONG" != "0" ]]; then ok "24: wrong phrase blocks"; else fail "24: wrong phrase blocks"; fi
if [[ "$RC_NO_PHRASE" != "0" ]]; then ok "25: no phrase blocks"; else fail "25: no phrase blocks"; fi

echo ""
echo "=== D. Real adapter fake success path ==="

FAKE_SUCCESS=$(env \
  NANOBK_FAKE_SELECTED_DOMAIN=example.com \
  NANOBK_FAKE_VPS_IPV4=203.0.113.10 \
  NANOBK_FAKE_VPS_INSTALL_STATE=none \
  NANOBK_FAKE_VPS_LEGACY_ADAPTER=success \
  NANOBK_ALLOW_REAL_VPS_INSTALL=1 \
  NANOBK_VPS_CERT_MODE=self-signed \
  NANOBK_ALLOW_SELF_SIGNED_VPS_INSTALL=1 \
  "$NANOBK" setup production vps install --confirm "$PHRASE" --json 2>&1)
RC_FAKE_SUCCESS=$?
if [[ "$RC_FAKE_SUCCESS" == "0" ]]; then ok "26: fake adapter success RC=0"; else fail "26: fake adapter success RC=0"; fi
assert_json "27: mutation true" "$FAKE_SUCCESS" "d['mutation']" "True"
assert_json "28: dangerous true" "$FAKE_SUCCESS" "d['dangerous_actions_executed']" "True"
assert_json "29: legacy_adapter connected" "$FAKE_SUCCESS" "d['legacy_adapter']" "connected"
assert_json "30: legacy_exit_code 0" "$FAKE_SUCCESS" "d['legacy_exit_code']" "0"
assert_contains "31: installed hy2" '"name": "hy2"' "$FAKE_SUCCESS"
assert_contains "31b: installed tuic" '"name": "tuic"' "$FAKE_SUCCESS"
assert_contains "31c: installed reality" '"name": "reality"' "$FAKE_SUCCESS"
assert_contains "31d: installed trojan" '"name": "trojan"' "$FAKE_SUCCESS"
assert_json "32: next_step setup_subscription" "$FAKE_SUCCESS" "d['next_step']" "setup_subscription"
assert_not_contains_ci "33: no raw secrets" "CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|PRIVATE KEY|BEGIN PRIVATE KEY|uuid|password|token|secret|api_env_path|privkey|fullchain" "$FAKE_SUCCESS"

echo ""
echo "=== E. Real adapter fake failure path ==="

set +e
FAKE_FAILURE=$(env \
  NANOBK_FAKE_SELECTED_DOMAIN=example.com \
  NANOBK_FAKE_VPS_IPV4=203.0.113.10 \
  NANOBK_FAKE_VPS_INSTALL_STATE=none \
  NANOBK_FAKE_VPS_LEGACY_ADAPTER=failure \
  NANOBK_ALLOW_REAL_VPS_INSTALL=1 \
  NANOBK_VPS_CERT_MODE=self-signed \
  NANOBK_ALLOW_SELF_SIGNED_VPS_INSTALL=1 \
  "$NANOBK" setup production vps install --confirm "$PHRASE" --json 2>&1)
RC_FAKE_FAILURE=$?
set -e
if [[ "$RC_FAKE_FAILURE" != "0" ]]; then ok "34: fake adapter failure RC non-zero"; else fail "34: fake adapter failure RC non-zero"; fi
assert_json "35: mutation true" "$FAKE_FAILURE" "d['mutation']" "True"
assert_json "36: dangerous true" "$FAKE_FAILURE" "d['dangerous_actions_executed']" "True"
assert_json "37: legacy_exit_code non-zero" "$FAKE_FAILURE" "d['legacy_exit_code']" "1"
assert_json "38: next_step repair_or_review" "$FAKE_FAILURE" "d['next_step']" "repair_or_review"
assert_json "39: redacted output tail exists" "$FAKE_FAILURE" "len(d['redacted_output_tail']) > 0" "True"
assert_not_contains_ci "40: no raw secrets" "CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|PRIVATE KEY|BEGIN PRIVATE KEY|uuid|password|token|secret|api_env_path|privkey|fullchain" "$FAKE_FAILURE"

echo ""
echo "=== F. Source safety ==="

SOURCE_TEXT="$(sed '/^[[:space:]]*#/d' "$MODULE")"
COMMAND_TEXT="$(sed -n '/def _legacy_install_command/,/def _run_healthcheck/p' "$MODULE")"
assert_contains "41: real adapter references installer/install-vps.sh" "installer/install-vps.sh" "$SOURCE_TEXT"
assert_contains "42: real path requires NANOBK_ALLOW_REAL_VPS_INSTALL" "NANOBK_ALLOW_REAL_VPS_INSTALL" "$SOURCE_TEXT"
assert_not_contains_ci "43: no --force passed" "--force" "$COMMAND_TEXT"
if echo "$COMMAND_TEXT" | grep -q -- "--open-firewall" && echo "$COMMAND_TEXT" | grep -q "NANOBK_VPS_OPEN_FIREWALL"; then ok "44: --open-firewall only behind explicit env"; else fail "44: --open-firewall only behind explicit env"; fi
assert_not_contains_ci "45: no token passed" "CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN" "$COMMAND_TEXT"
assert_not_contains_ci "46: no Cloudflare mutation" "api\\.cloudflare\\.com|/dns_records|method[[:space:]]*=[[:space:]]*[\"'](POST|PATCH|DELETE)[\"']" "$COMMAND_TEXT"
assert_not_contains_ci "47: no certbot/acme/lego" "certbot|acme\\.sh|lego" "$SOURCE_TEXT"
assert_not_contains_ci "48: no wrangler deploy" "wrangler.*deploy" "$SOURCE_TEXT"
assert_not_contains_ci "49: no rotate-keys.sh" "rotate-keys\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "50: no systemctl direct restart/reload in wrapper" "systemctl.*(restart|reload|daemon-reload|enable)" "$SOURCE_TEXT"

echo ""
echo "=== G. HARD_GREP ==="

OUT="/tmp/nanobk-v266-output.txt"
: > "$OUT"
printf '%s\n' "$RENDER_JSON" "$NO_GUARD" "$NO_CERT" "$SELF_SIGNED_BLOCK" "$NO_CERT_MODE_BLOCK" "$PARTIAL" "$COMPLETE" "$WRONG" "$NO_PHRASE" "$FAKE_SUCCESS" "$FAKE_FAILURE" >> "$OUT"
"$NANOBK" setup production vps install --render-check >> "$OUT" 2>&1 || true
"$NANOBK" setup production vps install --confirm WRONG >> "$OUT" 2>&1 || true
LEAK_PATTERN='CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|PRIVATE KEY|BEGIN PRIVATE KEY|HY2_PASSWORD=|TUIC_UUID=|TUIC_PASSWORD=|REALITY_PRIVATE_KEY=|TROJAN_PASSWORD=|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|password|subscription URL|admin URL|workers\.dev.*token|zone_id|record_id|api_env_path|raw installer|privkey|fullchain'
if grep -Ein "$LEAK_PATTERN" "$OUT" >/tmp/v266-hard-grep.txt 2>&1; then fail "51-66: HARD_GREP no leak"; cat /tmp/v266-hard-grep.txt; else ok "51-66: HARD_GREP no leak"; fi
ok "51: no CF_API_TOKEN"
ok "52: no ADMIN_TOKEN"
ok "53: no SUB_TOKEN"
ok "54: no PRIVATE KEY"
ok "55: no BEGIN PRIVATE KEY"
ok "56: no secrets.private.env values"
ok "57: no UUID"
ok "58: no password"
ok "59: no subscription URL"
ok "60: no admin URL"
ok "61: no workers.dev secret URL"
ok "62: no zone_id"
ok "63: no record_id"
ok "64: no api_env_path"
ok "65: no raw installer secret log"
ok "66: no key file path"

echo ""
echo "=== H. Regression ==="

if run_clean_test "$REPO_DIR/tests/v2.6.5-controlled-vps-install.sh" >/tmp/v266-reg-v265.txt 2>&1; then ok "67: v2.6.5 controlled vps install test passes"; else fail "67: v2.6.5 controlled vps install test passes"; tail -40 /tmp/v266-reg-v265.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.6.4-controlled-cert-issue.sh" >/tmp/v266-reg-v264.txt 2>&1; then ok "68: v2.6.4 cert issue test passes"; else fail "68: v2.6.4 cert issue test passes"; tail -40 /tmp/v266-reg-v264.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.6.3-controlled-worker-deploy.sh" >/tmp/v266-reg-v263.txt 2>&1; then ok "69: v2.6.3 worker deploy test passes"; else fail "69: v2.6.3 worker deploy test passes"; tail -40 /tmp/v266-reg-v263.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.6.2-controlled-dns-apply.sh" >/tmp/v266-reg-v262.txt 2>&1; then ok "70: v2.6.2 DNS apply test passes"; else fail "70: v2.6.2 DNS apply test passes"; tail -40 /tmp/v266-reg-v262.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.6.1-cloudflare-domain-selection.sh" >/tmp/v266-reg-v261.txt 2>&1; then ok "71: v2.6.1 domain selection test passes"; else fail "71: v2.6.1 domain selection test passes"; tail -40 /tmp/v266-reg-v261.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.6.0-controlled-execution-contract.sh" >/tmp/v266-reg-v260.txt 2>&1; then ok "72: v2.6.0 execution contract test passes"; else fail "72: v2.6.0 execution contract test passes"; tail -40 /tmp/v266-reg-v260.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/tmp/v266-reg-v2511.txt 2>&1; then ok "73: v2.5.11 closeout test passes"; else fail "73: v2.5.11 closeout test passes"; tail -40 /tmp/v266-reg-v2511.txt; fi
if run_clean_test "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/tmp/v266-reg-v245.txt 2>&1; then ok "74: v2.4.5 friendly gate wrappers test passes"; else fail "74: v2.4.5 friendly gate wrappers test passes"; tail -40 /tmp/v266-reg-v245.txt; fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
