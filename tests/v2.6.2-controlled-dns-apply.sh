#!/usr/bin/env bash
# v2.6.2 Controlled DNS Apply Productization Test
#
# Validates the productized DNS apply wrapper with fake Cloudflare hooks.
# Default tests do not run real Cloudflare mutation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MODULE="$REPO_DIR/lib/nanobk_production_dns_apply.py"
PHRASE="I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"

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

assert_not_contains_ci() {
  local label="$1" pattern="$2" haystack="$3"
  if echo "$haystack" | grep -qiE "$pattern"; then
    fail "$label (found: $pattern)"
  else
    ok "$label"
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

fake_env() {
  env \
    NANOBK_FAKE_SELECTED_DOMAIN=example.com \
    NANOBK_FAKE_CF_CONNECTED=1 \
    NANOBK_FAKE_VPS_IPV4=203.0.113.10 \
    NANOBK_FAKE_VPS_IPV6=2001:db8::10 \
    "$@"
}

clean_nanobk_fake_env

echo "=== A. Basic ==="

if python3 -m py_compile "$MODULE" 2>/dev/null; then
  ok "1: py_compile lib/nanobk_production_dns_apply.py"
else
  fail "1: py_compile lib/nanobk_production_dns_apply.py"
fi

if "$NANOBK" setup production dns apply --dry-run >/tmp/v262-basic-dry.txt 2>&1; then
  ok "2: setup production dns apply --dry-run exits 0"
else
  if grep -q "暂时不能继续" /tmp/v262-basic-dry.txt; then
    ok "2: setup production dns apply --dry-run safe blocked"
  else
    fail "2: setup production dns apply --dry-run exits 0 or safe blocked"
  fi
fi

DRY_BLOCKED_JSON=$("$NANOBK" setup production dns apply --dry-run --json 2>&1 || true)
assert_valid_json "3: setup production dns apply --dry-run --json valid" "$DRY_BLOCKED_JSON"

if "$NANOBK" beginner production dns apply --dry-run >/tmp/v262-beginner-dry.txt 2>&1; then
  ok "4: beginner alias dry-run exits 0"
else
  if grep -q "暂时不能继续" /tmp/v262-beginner-dry.txt; then
    ok "4: beginner alias dry-run safe blocked"
  else
    fail "4: beginner alias dry-run exits 0 or safe blocked"
  fi
fi

HELP_OUT=$("$NANOBK" setup production --help 2>&1)
assert_contains "5: help contains dns apply" "dns apply" "$HELP_OUT"

echo ""
echo "=== B. Dry-run JSON ==="

assert_json "6: mode production_dns_apply_v2_6" "$DRY_BLOCKED_JSON" "d['mode']" "production_dns_apply_v2_6"
assert_json "7: version 2.6.2" "$DRY_BLOCKED_JSON" "d['version']" "2.6.2"
assert_json "8: dry_run true" "$DRY_BLOCKED_JSON" "d['dry_run']" "True"
assert_json "9: mutation false" "$DRY_BLOCKED_JSON" "d['mutation']" "False"
assert_json "10: dangerous_actions_executed false" "$DRY_BLOCKED_JSON" "d['dangerous_actions_executed']" "False"
assert_json "11: safety read_only" "$DRY_BLOCKED_JSON" "d['safety']" "read_only"
assert_not_contains_ci "12: no zone_id" "zone_id" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "13: no record_id" "record_id" "$DRY_BLOCKED_JSON"
assert_not_contains_ci "14: no api_env_path" "api_env_path" "$DRY_BLOCKED_JSON"

echo ""
echo "=== C. Confirm rejection ==="

if fake_env "$NANOBK" setup production dns apply >/dev/null 2>&1; then fail "15: real apply without confirm RC non-zero"; else ok "15: real apply without confirm RC non-zero"; fi
if fake_env "$NANOBK" setup production dns apply --confirm WRONG >/dev/null 2>&1; then fail "16: wrong confirm RC non-zero"; else ok "16: wrong confirm RC non-zero"; fi
if fake_env "$NANOBK" setup production dns apply --yes >/dev/null 2>&1; then fail "17: --yes alone RC non-zero"; else ok "17: --yes alone RC non-zero"; fi
if fake_env "$NANOBK" setup production dns apply --force >/dev/null 2>&1; then fail "18: --force RC non-zero"; else ok "18: --force RC non-zero"; fi
if fake_env "$NANOBK" setup production dns apply --overwrite >/dev/null 2>&1; then fail "19: --overwrite RC non-zero"; else ok "19: --overwrite RC non-zero"; fi
if fake_env "$NANOBK" setup production dns apply --delete >/dev/null 2>&1; then fail "20: --delete RC non-zero"; else ok "20: --delete RC non-zero"; fi
if fake_env "$NANOBK" setup production dns apply --update >/dev/null 2>&1; then fail "21: --update RC non-zero"; else ok "21: --update RC non-zero"; fi

echo ""
echo "=== D. Fake dry run success ==="

FAKE_DRY_JSON=$(fake_env "$NANOBK" setup production dns apply --dry-run --json 2>&1)
FAKE_DRY_TEXT=$(fake_env "$NANOBK" setup production dns apply --dry-run 2>&1)
if [[ "$?" -eq 0 ]]; then ok "22: dry-run RC=0"; else fail "22: dry-run RC=0"; fi

if echo "$FAKE_DRY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert any(r['name']=='proxy.example.com' and r['type']=='A' for r in d['planned_records'])" 2>/dev/null; then ok "23: planned proxy A"; else fail "23: planned proxy A"; fi
if echo "$FAKE_DRY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert any(r['name']=='web.example.com' and r['type']=='A' for r in d['planned_records'])" 2>/dev/null; then ok "24: planned web A"; else fail "24: planned web A"; fi
if echo "$FAKE_DRY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert any(r['name']=='proxy.example.com' and r['type']=='AAAA' for r in d['planned_records'])" 2>/dev/null; then ok "25: planned proxy AAAA if IPv6 present"; else fail "25: planned proxy AAAA if IPv6 present"; fi
if echo "$FAKE_DRY_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert any(r['name']=='web.example.com' and r['type']=='AAAA' for r in d['planned_records'])" 2>/dev/null; then ok "26: planned web AAAA if IPv6 present"; else fail "26: planned web AAAA if IPv6 present"; fi
assert_contains "27: content masked" "203.0.113.xxx" "$FAKE_DRY_JSON"
assert_not_contains_ci "28: no raw IPv4 full output" "203\\.0\\.113\\.10" "$FAKE_DRY_JSON $FAKE_DRY_TEXT"
assert_not_contains_ci "29: no raw IPv6 full output" "2001:db8::10" "$FAKE_DRY_JSON $FAKE_DRY_TEXT"
clean_nanobk_fake_env

echo ""
echo "=== E. Occupied record refusal ==="

OCC_JSON=$(NANOBK_FAKE_DNS_EXISTING=proxy fake_env "$NANOBK" setup production dns apply --dry-run --json 2>&1 || true)
OCC_TEXT=$(NANOBK_FAKE_DNS_EXISTING=proxy fake_env "$NANOBK" setup production dns apply --dry-run 2>&1 || true)
assert_json "30: dry-run blocked true" "$OCC_JSON" "d['blocked']" "True"
assert_json "31: next_step custom_subdomain" "$OCC_JSON" "d['next_step']" "custom_subdomain"
assert_contains "32: text suggests custom subdomain" "自定义子域名" "$OCC_TEXT"
if NANOBK_FAKE_DNS_EXISTING=proxy fake_env "$NANOBK" setup production dns apply --confirm "$PHRASE" >/dev/null 2>&1; then fail "33: real apply refuses"; else ok "33: real apply refuses"; fi
clean_nanobk_fake_env

echo ""
echo "=== F. Fake real creation ==="

CREATE_JSON=$(NANOBK_FAKE_DNS_CREATE=1 fake_env "$NANOBK" setup production dns apply --confirm "$PHRASE" --json 2>&1)
CREATE_RC=$?
if [[ "$CREATE_RC" -eq 0 ]]; then ok "34: real apply RC=0"; else fail "34: real apply RC=0"; fi
assert_json "35: mutation true" "$CREATE_JSON" "d['mutation']" "True"
assert_json "36: dangerous_actions_executed true" "$CREATE_JSON" "d['dangerous_actions_executed']" "True"
assert_json "37: confirmed true" "$CREATE_JSON" "d['confirmed']" "True"
if echo "$CREATE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert any(r['name']=='proxy.example.com' for r in d['created_records'])" 2>/dev/null; then ok "38: created_records contains proxy"; else fail "38: created_records contains proxy"; fi
if echo "$CREATE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); assert any(r['name']=='web.example.com' for r in d['created_records'])" 2>/dev/null; then ok "39: created_records contains web"; else fail "39: created_records contains web"; fi
assert_not_contains_ci "40: no raw token" "CF_API_TOKEN|ADMIN_TOKEN|SUB_TOKEN|Bearer|fake-token" "$CREATE_JSON"
assert_not_contains_ci "41: no zone_id/record_id" "zone_id|record_id" "$CREATE_JSON"
assert_json "42: next_step setup_worker" "$CREATE_JSON" "d['next_step']" "setup_worker"
clean_nanobk_fake_env

echo ""
echo "=== G. Source safety ==="

SOURCE_TEXT="$(sed '/^[[:space:]]*#/d' "$MODULE")"
assert_not_contains_ci "43: no subprocess" "subprocess" "$SOURCE_TEXT"
assert_not_contains_ci "44: no os.system" "os\\.system" "$SOURCE_TEXT"
assert_not_contains_ci "45: no popen" "popen" "$SOURCE_TEXT"
assert_not_contains_ci "46: no certbot" "certbot" "$SOURCE_TEXT"
assert_not_contains_ci "47: no wrangler deploy" "wrangler.*deploy" "$SOURCE_TEXT"
assert_not_contains_ci "48: no rotate-keys.sh" "rotate-keys\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "49: no install-vps.sh" "install-vps\\.sh" "$SOURCE_TEXT"
assert_not_contains_ci "50: no systemctl restart/reload" "systemctl[[:space:]].*(restart|reload)" "$SOURCE_TEXT"
assert_not_contains_ci "51: no Cloudflare PATCH" "method=[\"']PATCH[\"']" "$SOURCE_TEXT"
assert_not_contains_ci "52: no Cloudflare DELETE" "method=[\"']DELETE[\"']" "$SOURCE_TEXT"
assert_not_contains_ci "53: no overwrite/delete/update logic" "overwrite_record|delete_record|update_record|method=[\"']PUT[\"']" "$SOURCE_TEXT"

echo ""
echo "=== H. Regression ==="

if run_clean_test "$REPO_DIR/tests/v2.6.1-cloudflare-domain-selection.sh" >/dev/null 2>&1; then ok "54: v2.6.1 test passes"; else fail "54: v2.6.1 test passes"; fi
if run_clean_test "$REPO_DIR/tests/v2.6.0-controlled-execution-contract.sh" >/dev/null 2>&1; then ok "55: v2.6.0 test passes"; else fail "55: v2.6.0 test passes"; fi
if run_clean_test "$REPO_DIR/tests/v2.5.11-closeout-manifest.sh" >/dev/null 2>&1; then ok "56: v2.5.11 closeout test passes"; else fail "56: v2.5.11 closeout test passes"; fi
if run_clean_test "$REPO_DIR/tests/v2.5.7-production-preflight.sh" >/dev/null 2>&1; then ok "57: v2.5.7 preflight test passes"; else fail "57: v2.5.7 preflight test passes"; fi
if run_clean_test "$REPO_DIR/tests/v2.4.5-friendly-gate-wrappers.sh" >/dev/null 2>&1; then ok "58: v2.4.5 friendly gate test passes"; else fail "58: v2.4.5 friendly gate test passes"; fi

echo ""
echo "Manual real Cloudflare guard (not run by this test):"
echo "  NANOBK_ALLOW_REAL_CF_DNS_APPLY=1 bin/nanobk setup production dns apply --confirm \"$PHRASE\""

echo ""
echo "PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  exit 0
fi
exit 1
