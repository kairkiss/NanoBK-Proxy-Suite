#!/usr/bin/env bash
# NanoBK Proxy Suite — Controlled Live Wrapper Skeleton Fake Test
#
# Tests lib/nanobk_cf_dns_apply_controlled_live_wrapper_skeleton_fake.py
# with safe placeholder fixtures. Does NOT call Cloudflare. Does NOT call helper.
#
# Usage:
#   bash tests/v2.2.25-controlled-live-wrapper-skeleton-fake.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_apply_controlled_live_wrapper_skeleton_fake.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.25"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local desc="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (expected '$needle')"
    ERRORS=$((ERRORS + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local desc="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (unexpected '$needle')"
    ERRORS=$((ERRORS + 1))
  fi
}

echo ""
echo "=== Controlled Live Wrapper Skeleton Fake Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. File/scope checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. File/scope checks ---"
echo ""

if [[ -f "$MODULE" ]]; then
  pass "A1: module exists"
else
  fail "A1: module does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

MODULE_SOURCE=$(cat "$MODULE")

if [[ -d "$FIXTURES" ]]; then
  pass "A2: fixture directory exists"
else
  fail "A2: fixture directory does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$MODULE_SOURCE" "fake transport only" "A3: says fake transport only"
assert_contains "$MODULE_SOURCE" "Does not call Cloudflare" "A4: no Cloudflare"
assert_contains "$MODULE_SOURCE" "Does not call real helper" "A4: no real helper"
assert_contains "$MODULE_SOURCE" "Does not read real env" "A4: no env reading"
assert_contains "$MODULE_SOURCE" "Does not mutate DNS" "A4: no DNS mutation"
assert_not_contains "$MODULE_SOURCE" "public CLI" "A5: no public CLI wording"

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_controlled_live_wrapper_skeleton_fake' "$loc" 2>/dev/null; then
    fail "A6: $loc references module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "A6: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Fixture safety
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Fixture safety ---"
echo ""

for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  content=$(cat "$fixture_file")

  assert_not_contains "$content" "example.com" "B: $fname no example.com"
  assert_not_contains "$content" "203.0.113" "B: $fname no IPv4"
  assert_not_contains "$content" "2001:db8" "B: $fname no IPv6"
  assert_not_contains "$content" "recordId" "B: $fname no recordId"
  assert_not_contains "$content" "Zone ID" "B: $fname no Zone ID"
  assert_not_contains "$content" "Account ID" "B: $fname no Account ID"
  assert_not_contains "$content" "Authorization" "B: $fname no Authorization"
  assert_not_contains "$content" "CF_API_TOKEN" "B: $fname no token"
  assert_not_contains "$content" "workers.dev" "B: $fname no workers.dev"
  assert_not_contains "$content" "vless://" "B: $fname no vless://"
  assert_not_contains "$content" "PRIVATE KEY" "B: $fname no PRIVATE KEY"
  assert_not_contains "$content" "apply --yes" "B: $fname no apply --yes"

  if echo "$content" | grep -qE '[a-f0-9]{64}'; then
    fail "B: $fname has 64-char hex"
    ERRORS=$((ERRORS + 1))
  else
    pass "B: $fname no 64-char hex"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Skeleton validator cases
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Skeleton validator cases ---"
echo ""

validate_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_controlled_live_wrapper_skeleton_fake import run_controlled_live_wrapper_skeleton_fake
with open('$fixture') as f:
    data = json.load(f)
model = run_controlled_live_wrapper_skeleton_fake(data)
print(json.dumps(model))
" 2>&1
}

render_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_controlled_live_wrapper_skeleton_fake import run_controlled_live_wrapper_skeleton_fake, render_controlled_live_wrapper_skeleton_fake_summary
with open('$fixture') as f:
    data = json.load(f)
model = run_controlled_live_wrapper_skeleton_fake(data)
print(render_controlled_live_wrapper_skeleton_fake_summary(model))
" 2>&1
}

# Test cases: (fixture, expected_status, expected_first_gate)
declare -A TEST_CASES=(
  ["fake_verified_happy_path"]="fake_transport_verified none"
  ["ready_for_future_live_plan"]="ready_for_owner_approved_future_live_plan none"
  ["blocked_repo_gate"]="blocked repo_gate"
  ["blocked_placeholder_validator"]="blocked placeholder_validator_gate"
  ["blocked_credential_reference_policy"]="blocked credential_reference_gate"
  ["blocked_record_identity_policy"]="blocked record_identity_gate"
  ["blocked_precheck_policy"]="blocked precheck_gate"
  ["blocked_preview_policy"]="blocked preview_gate"
  ["blocked_missing_approval"]="blocked approval_gate"
  ["blocked_fake_helper_capture"]="blocked fake_helper_capture_gate"
  ["blocked_fake_helper_schema"]="blocked fake_helper_json_gate"
  ["blocked_fake_postcheck"]="blocked fake_postcheck_gate"
  ["blocked_redaction_failure"]="blocked redaction_gate"
  ["blocked_public_ux_enabled"]="blocked public_ux_gate"
)

CI=1
for fixture_name in "${!TEST_CASES[@]}"; do
  read -r expected_status expected_gate <<< "${TEST_CASES[$fixture_name]}"
  RESULT=$(validate_fixture "$FIXTURES/${fixture_name}.json")
  STATUS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  GATE=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
  if [[ "$STATUS" == "$expected_status" ]] && [[ "$GATE" == "$expected_gate" ]]; then
    pass "C${CI}: ${fixture_name} -> ${status} + ${gate}"
  else
    fail "C${CI}: ${fixture_name} expected ${expected_status}+${expected_gate}, got ${STATUS}+${GATE}"
    ERRORS=$((ERRORS + 1))
  fi
  CI=$((CI + 1))
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. First-failure semantics
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. First-failure semantics ---"
echo ""

D1=$(validate_fixture "$FIXTURES/blocked_multi_gate_first_failure.json")
D1_STATUS=$(echo "$D1" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
D1_GATE=$(echo "$D1" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
D1_REASON=$(echo "$D1" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_blocked_reason'])")
D1_BLOCKED=$(echo "$D1" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['blocked_reasons']))")
D1_DIAG=$(echo "$D1" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['diagnostic_blocked_reasons']))")

if [[ "$D1_STATUS" == "blocked" ]] && [[ "$D1_GATE" == "repo_gate" ]] && [[ "$D1_REASON" == "repo gate failed" ]]; then
  pass "D1: multi-gate -> blocked + repo_gate + repo gate failed"
else
  fail "D1: expected blocked + repo_gate + repo gate failed, got '$D1_STATUS' '$D1_GATE' '$D1_REASON'"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$D1_BLOCKED" == "1" ]]; then
  pass "D2: blocked_reasons length = 1"
else
  fail "D2: blocked_reasons should be 1, got $D1_BLOCKED"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$D1_DIAG" -gt 1 ]]; then
  pass "D3: diagnostic_blocked_reasons length > 1 ($D1_DIAG)"
else
  fail "D3: diagnostic should be > 1, got $D1_DIAG"
  ERRORS=$((ERRORS + 1))
fi

# Rendered output should not print later diagnostic reasons
D4_OUT=$(render_fixture "$FIXTURES/blocked_multi_gate_first_failure.json")
assert_not_contains "$D4_OUT" "credential reference gate failed" "D4: no credential reason in output"
assert_not_contains "$D4_OUT" "placeholder validator gate failed" "D5: no placeholder reason in output"
assert_not_contains "$D4_OUT" "owner approval gate failed" "D6: no approval reason in output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Fake transport honesty
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Fake transport honesty ---"
echo ""

E1_OUT=$(render_fixture "$FIXTURES/fake_verified_happy_path.json")
assert_contains "$E1_OUT" "Status: fake_transport_verified" "E1: fake verified status"
assert_contains "$E1_OUT" "Mode: fake_transport_only" "E2: fake transport only mode"
assert_contains "$E1_OUT" "Fake transport verified only" "E3: fake transport verified only"
assert_contains "$E1_OUT" "Live Cloudflare called: no" "E4: live cloudflare called: no"
assert_contains "$E1_OUT" "Real helper called: no" "E5: real helper called: no"
assert_contains "$E1_OUT" "Real DNS mutation performed: no" "E6: real dns mutation: no"
assert_contains "$E1_OUT" "Real env read: no" "E7: real env read: no"
assert_contains "$E1_OUT" "Public apply allowed: no" "E8: public apply allowed: no"
assert_contains "$E1_OUT" "Actual live test allowed: no" "E9: actual live test allowed: no"
assert_contains "$E1_OUT" "Requires later owner approval: yes" "E10: requires later owner approval"
assert_not_contains "$E1_OUT" "live verified" "E11: no live verified"
assert_not_contains "$E1_OUT" "allowed: yes" "E12: no allowed: yes"
assert_not_contains "$E1_OUT" "real DNS mutation performed: yes" "E13: no mutation yes"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Uncertain semantics
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Uncertain semantics ---"
echo ""

# F1-F4. Malformed input
F1=$(validate_fixture "$FIXTURES/uncertain_malformed_input.json")
F1_STATUS=$(echo "$F1" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
F1_BLOCKED=$(echo "$F1" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['blocked_reasons']))")
if [[ "$F1_STATUS" == "uncertain" ]]; then
  pass "F1: malformed input -> uncertain"
else
  fail "F1: expected uncertain, got '$F1_STATUS'"
  ERRORS=$((ERRORS + 1))
fi
if [[ "$F1_BLOCKED" == "0" ]]; then
  pass "F2: malformed blocked_reasons length = 0"
else
  fail "F2: malformed blocked_reasons should be 0, got $F1_BLOCKED"
  ERRORS=$((ERRORS + 1))
fi

F3_OUT=$(render_fixture "$FIXTURES/uncertain_malformed_input.json")
assert_contains "$F3_OUT" "Status: uncertain" "F3: uncertain status in output"
assert_contains "$F3_OUT" "Actual live test is not allowed" "F4: live test not allowed"
assert_not_contains "$F3_OUT" "ready_for_future_owner_approved_live_plan" "F4b: no ready status"
assert_not_contains "$F3_OUT" "fake_transport_verified" "F4c: no fake verified status"

# F5-F7. Classifier ambiguous
F5=$(validate_fixture "$FIXTURES/uncertain_classifier_ambiguous.json")
F5_STATUS=$(echo "$F5" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
if [[ "$F5_STATUS" == "blocked" ]]; then
  pass "F5: classifier ambiguous -> blocked (gate fail)"
else
  fail "F5: expected blocked for ambiguous classifier, got '$F5_STATUS'"
  ERRORS=$((ERRORS + 1))
fi

F6_OUT=$(render_fixture "$FIXTURES/uncertain_classifier_ambiguous.json")
assert_not_contains "$F6_OUT" "fake_transport_verified" "F6: no fake verified in ambiguous output"
assert_not_contains "$F6_OUT" "ready_for_future_owner_approved_live_plan" "F7: no ready in ambiguous output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Output safety
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Output safety ---"
echo ""

for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  out=$(render_fixture "$fixture_file")

  assert_not_contains "$out" "example.com" "G: $fname no example.com"
  assert_not_contains "$out" "203.0.113" "G: $fname no IPv4"
  assert_not_contains "$out" "2001:db8" "G: $fname no IPv6"
  assert_not_contains "$out" "recordId" "G: $fname no recordId"
  assert_not_contains "$out" "Zone ID" "G: $fname no Zone ID"
  assert_not_contains "$out" "Account ID" "G: $fname no Account ID"
  assert_not_contains "$out" "Authorization" "G: $fname no Authorization"
  assert_not_contains "$out" "CF_API_TOKEN" "G: $fname no token"
  assert_not_contains "$out" "workers.dev" "G: $fname no workers.dev"
  assert_not_contains "$out" "vless://" "G: $fname no vless://"
  assert_not_contains "$out" "PRIVATE KEY" "G: $fname no PRIVATE KEY"
  assert_not_contains "$out" "apply --yes" "G: $fname no apply --yes"

  if echo "$out" | grep -qE '[a-f0-9]{64}'; then
    fail "G: $fname has 64-char hex"
    ERRORS=$((ERRORS + 1))
  else
    pass "G: $fname no 64-char hex"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. No network / no public integration
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. No network / no public integration ---"
echo ""

assert_not_contains "$MODULE_SOURCE" "import requests" "H1: no requests"
assert_not_contains "$MODULE_SOURCE" "import urllib" "H1: no urllib"
assert_not_contains "$MODULE_SOURCE" "import http.client" "H1: no http.client"
assert_not_contains "$MODULE_SOURCE" "import socket" "H1: no socket"
assert_not_contains "$MODULE_SOURCE" "import subprocess" "H1: no subprocess"
assert_not_contains "$MODULE_SOURCE" "import os" "H1: no os"
assert_not_contains "$MODULE_SOURCE" "import pathlib" "H1: no pathlib"
assert_not_contains "$MODULE_SOURCE" "import curl" "H1: no curl"
assert_not_contains "$MODULE_SOURCE" "import wrangler" "H1: no wrangler"
assert_not_contains "$MODULE_SOURCE" "import nanobk_cf_dns_apply" "H1: no real helper import"

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_controlled_live_wrapper_skeleton_fake' "$loc" 2>/dev/null; then
    fail "H2: $loc references module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "H2: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Existing safe tests
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Existing safe tests ---"
echo ""

for test_file in \
  "v2.2.18-dns-apply-postcheck-contract.sh" \
  "v2.2.19-dns-apply-postcheck-classifier-mock.sh" \
  "v2.2.20-controlled-live-gate-contract.sh" \
  "v2.2.21-controlled-live-gate-placeholder-mock.sh" \
  "v2.2.24-one-record-live-runbook-validator-mock.sh"; do
  if bash "$ROOT/tests/$test_file" > /dev/null 2>&1; then
    pass "I: $test_file passes"
  else
    fail "I: $test_file fails"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.25 Controlled Live Wrapper Skeleton Fake tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
