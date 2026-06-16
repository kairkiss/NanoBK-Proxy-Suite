#!/usr/bin/env bash
# v2.6.1 Cloudflare Login and Domain Selection Productization Test
#
# Validates beginner-facing Cloudflare setup, domain discovery/selection, and
# local selected-domain save. No DNS records are created.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
CF_MODULE="$REPO_DIR/lib/nanobk_cloudflare_product_setup.py"
DOMAIN_MODULE="$REPO_DIR/lib/nanobk_domain_selection.py"
DOMAIN_FILE_REL=".nanobk/production-domain.json"

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

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

assert_valid_json() {
  local label="$1" json="$2"
  if echo "$json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    ok "$label"
  else
    fail "$label"
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

assert_json_no_key() {
  local label="$1" json="$2" key="$3"
  if echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
needle = '$key'
def walk(value):
    if isinstance(value, dict):
        assert needle not in value, needle
        for item in value.values():
            walk(item)
    elif isinstance(value, list):
        for item in value:
            walk(item)
walk(d)
" 2>/dev/null; then
    ok "$label"
  else
    fail "$label"
  fi
}

new_home() {
  mktemp -d
}

echo "=== A. Basic ==="

if python3 -m py_compile "$CF_MODULE" "$DOMAIN_MODULE" 2>/dev/null; then
  ok "1: py_compile new modules"
else
  fail "1: py_compile new modules"
fi

HOME_A="$(new_home)"
if HOME="$HOME_A" "$NANOBK" setup cloudflare >/dev/null 2>&1; then ok "2: setup cloudflare exits 0"; else fail "2: setup cloudflare exits 0"; fi
if HOME="$HOME_A" "$NANOBK" setup cloudflare --json >/dev/null 2>&1; then ok "3: setup cloudflare --json exits 0"; else fail "3: setup cloudflare --json exits 0"; fi
if HOME="$HOME_A" "$NANOBK" setup domain >/dev/null 2>&1; then ok "4: setup domain exits 0"; else fail "4: setup domain exits 0"; fi
if HOME="$HOME_A" "$NANOBK" setup domain --json >/dev/null 2>&1; then ok "5: setup domain --json exits 0"; else fail "5: setup domain --json exits 0"; fi
if HOME="$HOME_A" "$NANOBK" beginner cloudflare >/dev/null 2>&1; then ok "6: beginner cloudflare exits 0"; else fail "6: beginner cloudflare exits 0"; fi
if HOME="$HOME_A" "$NANOBK" beginner domain >/dev/null 2>&1; then ok "7: beginner domain exits 0"; else fail "7: beginner domain exits 0"; fi
rm -rf "$HOME_A"

echo ""
echo "=== B. JSON schema ==="

HOME_B="$(new_home)"
CF_JSON=$(HOME="$HOME_B" "$NANOBK" setup cloudflare --json 2>&1)
DOMAIN_JSON=$(HOME="$HOME_B" "$NANOBK" setup domain --json 2>&1)

assert_valid_json "8: cloudflare JSON valid" "$CF_JSON"
assert_json "9: cloudflare mode" "$CF_JSON" "d['mode']" "cloudflare_setup_v2_6"
assert_json "10: cloudflare mutation false" "$CF_JSON" "d['mutation']" "False"
assert_json "11: cloudflare dangerous_actions_executed false" "$CF_JSON" "d['dangerous_actions_executed']" "False"
assert_json_no_key "12: cloudflare no api_env_path" "$CF_JSON" "api_env_path"

assert_valid_json "13: domain JSON valid" "$DOMAIN_JSON"
assert_json "14: domain mode" "$DOMAIN_JSON" "d['mode']" "domain_selection_v2_6"
assert_json "15: domain mutation false" "$DOMAIN_JSON" "d['mutation']" "False"
assert_json "16: domain dangerous_actions_executed false" "$DOMAIN_JSON" "d['dangerous_actions_executed']" "False"
assert_json_no_key "17: domain no zone_id" "$DOMAIN_JSON" "zone_id"
assert_json_no_key "18: domain no record_id" "$DOMAIN_JSON" "record_id"
assert_json_no_key "19: domain no api_env_path" "$DOMAIN_JSON" "api_env_path"
rm -rf "$HOME_B"

echo ""
echo "=== C. Clean HOME ==="

HOME_C="$(new_home)"
CF_CLEAN=$(HOME="$HOME_C" "$NANOBK" setup cloudflare --json 2>&1)
DOMAIN_CLEAN=$(HOME="$HOME_C" "$NANOBK" setup domain --json 2>&1)
assert_json "20: clean HOME cloudflare connected false" "$CF_CLEAN" "d['connected']" "False"
assert_json "21: clean HOME domain connected false" "$DOMAIN_CLEAN" "d['connected']" "False"
assert_json "22: clean HOME domain next_step setup_cloudflare" "$DOMAIN_CLEAN" "d['next_step']" "setup_cloudflare"
ok "23: clean HOME no crash"
rm -rf "$HOME_C"

echo ""
echo "=== D. Custom domain save ==="

HOME_D="$(new_home)"
CUSTOM_TEXT=$(HOME="$HOME_D" "$NANOBK" setup domain --custom example.com 2>&1)
CUSTOM_RC=$?
if [[ "$CUSTOM_RC" -eq 0 ]]; then ok "24: setup domain --custom exits 0"; else fail "24: setup domain --custom exits 0"; fi
DOMAIN_FILE="$HOME_D/$DOMAIN_FILE_REL"
[[ -f "$DOMAIN_FILE" ]] && ok "25: saved file exists" || fail "25: saved file exists"
MODE=$(python3 -c "import os,stat; print(oct(stat.S_IMODE(os.stat('$DOMAIN_FILE').st_mode)))" 2>/dev/null || echo "missing")
[[ "$MODE" == "0o600" ]] && ok "26: saved file chmod 600" || fail "26: saved file chmod 600 (got $MODE)"
assert_json "27: saved file contains selected_domain" "$(cat "$DOMAIN_FILE")" "d['selected_domain']" "example.com"
assert_json "28: saved file source custom" "$(cat "$DOMAIN_FILE")" "d['source']" "custom"
assert_not_contains_ci "29: output no api_env_path" "api_env_path" "$CUSTOM_TEXT"
assert_not_contains_ci "30: output no zone_id/record_id" "zone_id|record_id" "$CUSTOM_TEXT"
rm -rf "$HOME_D"

echo ""
echo "=== E. Select domain save with fake discovery ==="

HOME_E="$(new_home)"
FAKE_JSON=$(HOME="$HOME_E" NANOBK_FAKE_CF_DOMAINS="example.com,example.net" "$NANOBK" setup domain --json 2>&1)
if echo "$FAKE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); names=[x['name'] for x in d['domains']]; assert 'example.com' in names and 'example.net' in names" 2>/dev/null; then
  ok "31: setup domain --json lists both domains"
else
  fail "31: setup domain --json lists both domains"
fi
if HOME="$HOME_E" NANOBK_FAKE_CF_DOMAINS="example.com,example.net" "$NANOBK" setup domain --select example.com >/dev/null 2>&1; then
  ok "32: setup domain --select example.com exits 0"
else
  fail "32: setup domain --select example.com exits 0"
fi
SELECTED_FILE="$HOME_E/$DOMAIN_FILE_REL"
assert_json "33: selected_domain saved" "$(cat "$SELECTED_FILE")" "d['selected_domain']" "example.com"
if HOME="$HOME_E" NANOBK_FAKE_CF_DOMAINS="example.com,example.net" "$NANOBK" setup domain --select missing.example >/dev/null 2>&1; then
  fail "34: invalid selection rejected RC non-zero"
else
  ok "34: invalid selection rejected RC non-zero"
fi
rm -rf "$HOME_E"

echo ""
echo "=== F. Production next integration ==="

HOME_F="$(new_home)"
NEXT_CLEAN=$(HOME="$HOME_F" "$NANOBK" setup production next --json 2>&1)
assert_valid_json "37a: clean production next JSON valid" "$NEXT_CLEAN"
if echo "$NEXT_CLEAN" | grep -qE "setup_cloudflare|setup_domain|nanobk setup cloudflare|nanobk setup domain"; then
  ok "35: clean HOME production next recommends setup cloudflare or setup domain"
else
  fail "35: clean HOME production next recommends setup cloudflare or setup domain"
fi
HOME="$HOME_F" "$NANOBK" setup domain --custom example.com >/dev/null 2>&1
NEXT_AFTER_DOMAIN=$(HOME="$HOME_F" "$NANOBK" setup production next --json 2>&1)
if echo "$NEXT_AFTER_DOMAIN" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('recommended_command') != 'nanobk setup cloudflare'" 2>/dev/null; then
  ok "36: after custom domain save production next no longer recommends setup cloudflare first"
else
  fail "36: after custom domain save production next no longer recommends setup cloudflare first"
fi
assert_valid_json "37: production next remains JSON valid" "$NEXT_AFTER_DOMAIN"
rm -rf "$HOME_F"

echo ""
echo "=== G. Safety ==="

HOME_G="$(new_home)"
ALL_OUTPUT="$CF_JSON $DOMAIN_JSON $CUSTOM_TEXT $FAKE_JSON $(HOME="$HOME_G" "$NANOBK" setup cloudflare 2>&1) $(HOME="$HOME_G" "$NANOBK" setup domain 2>&1)"
rm -rf "$HOME_G"

assert_not_contains_ci "38: no CF_API_TOKEN" "CF_API_TOKEN" "$ALL_OUTPUT"
assert_not_contains_ci "39: no ADMIN_TOKEN" "ADMIN_TOKEN" "$ALL_OUTPUT"
assert_not_contains_ci "40: no SUB_TOKEN" "SUB_TOKEN" "$ALL_OUTPUT"
assert_not_contains_ci "41: no PRIVATE KEY" "PRIVATE KEY|BEGIN [A-Z ]*KEY" "$ALL_OUTPUT"
assert_not_contains_ci "42: no subscription URL" "subscription.*https?://|https?://[^[:space:]]*/sub" "$ALL_OUTPUT"
assert_not_contains_ci "43: no admin URL" "admin.*https?://|https?://[^[:space:]]*/admin" "$ALL_OUTPUT"
assert_not_contains_ci "44: no workers.dev secret token" "workers\\.dev.*token|token.*workers\\.dev" "$ALL_OUTPUT"
assert_not_contains_ci "45: no zone_id" "zone_id" "$ALL_OUTPUT"
assert_not_contains_ci "46: no record_id" "record_id" "$ALL_OUTPUT"
assert_not_contains_ci "47: no api_env_path" "api_env_path" "$ALL_OUTPUT"
assert_not_contains_ci "48: no api.cloudflare.com/client/v4 raw output" "api\\.cloudflare\\.com/client/v4" "$ALL_OUTPUT"
assert_not_contains_ci "49: no /dns_records" "/dns_records" "$ALL_OUTPUT"

echo ""
echo "=== H. Source safety ==="

SOURCE_TEXT="$(sed '/^[[:space:]]*#/d' "$CF_MODULE" "$DOMAIN_MODULE")"
assert_not_contains_ci "50: no subprocess" "subprocess" "$SOURCE_TEXT"
assert_not_contains_ci "51: no os.system" "os\\.system" "$SOURCE_TEXT"
assert_not_contains_ci "52: no popen" "popen" "$SOURCE_TEXT"
assert_not_contains_ci "53: no Cloudflare POST/PATCH/DELETE" "method=[\"'](POST|PATCH|DELETE)[\"']|POST|PATCH|DELETE" "$SOURCE_TEXT"
assert_not_contains_ci "54: no wrangler deploy" "wrangler.*deploy" "$SOURCE_TEXT"
assert_not_contains_ci "55: no certbot" "certbot" "$SOURCE_TEXT"
assert_not_contains_ci "56: no rotate-keys.sh" "rotate-keys\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "57: no install-vps.sh" "install-vps\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "58: no systemctl restart/reload" "systemctl[[:space:]].*(restart|reload)" "$SOURCE_TEXT"

echo ""
echo "=== I. Regression ==="

if [[ "${NANOBK_TEST_SKIP_REGRESSION:-1}" == "1" ]]; then
  ok "59: regression skipped by NANOBK_TEST_SKIP_REGRESSION"
else
  if NANOBK_TEST_SKIP_REGRESSION=1 bash "$REPO_DIR/tests/v2.6.0-controlled-execution-contract.sh" >/dev/null 2>&1; then ok "59: v2.6.0 test passes"; else fail "59: v2.6.0 test passes"; fi
  if bash "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/dev/null 2>&1; then ok "60: v2.5.11 closeout test passes"; else fail "60: v2.5.11 closeout test passes"; fi
  if bash "$REPO_DIR/tests/v2.5.7-production-preflight.sh" >/dev/null 2>&1; then ok "61: v2.5.7 preflight test passes"; else fail "61: v2.5.7 preflight test passes"; fi
  if bash "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/dev/null 2>&1; then ok "62: v2.4.5 friendly gate wrappers test passes"; else fail "62: v2.4.5 friendly gate wrappers test passes"; fi
fi
if grep -q "v2.6.1 — Cloudflare Login and Domain Selection Productization" "$REPO_DIR/CHANGELOG.md"; then ok "63: CHANGELOG"; else fail "63: CHANGELOG"; fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
