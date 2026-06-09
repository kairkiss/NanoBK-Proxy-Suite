#!/usr/bin/env bash
# NanoBK Proxy Suite — One-Record Live Runbook Validator Mock Test
#
# Tests lib/nanobk_cf_dns_apply_one_record_live_runbook_validator_mock.py
# with safe placeholder fixtures. Does NOT call Cloudflare. Does NOT call helper.
#
# Usage:
#   bash tests/v2.2.24-one-record-live-runbook-validator-mock.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_apply_one_record_live_runbook_validator_mock.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.24"

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
echo "=== One-Record Live Runbook Validator Mock Test ==="
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

assert_contains "$MODULE_SOURCE" "Pure mock" "A3: module says pure mock"
assert_contains "$MODULE_SOURCE" "Does not call Cloudflare" "A4: no Cloudflare"
assert_contains "$MODULE_SOURCE" "Does not call helper" "A4: no helper"
assert_contains "$MODULE_SOURCE" "Does not read real env" "A4: no env reading"
assert_contains "$MODULE_SOURCE" "Does not mutate DNS" "A4: no DNS mutation"
assert_not_contains "$MODULE_SOURCE" "public CLI" "A5: no public CLI wording"

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_one_record_live_runbook_validator_mock' "$loc" 2>/dev/null; then
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
# C. Validator cases
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Validator cases ---"
echo ""

validate_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_one_record_live_runbook_validator_mock import validate_one_record_live_runbook_placeholders
with open('$fixture') as f:
    data = json.load(f)
model = validate_one_record_live_runbook_placeholders(data)
print(json.dumps(model))
" 2>&1
}

render_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_one_record_live_runbook_validator_mock import validate_one_record_live_runbook_placeholders, render_one_record_live_runbook_validation_summary
with open('$fixture') as f:
    data = json.load(f)
model = validate_one_record_live_runbook_placeholders(data)
print(render_one_record_live_runbook_validation_summary(model))
" 2>&1
}

# C1. ready_placeholder_validation -> ready
C1=$(validate_fixture "$FIXTURES/ready_placeholder_validation.json")
C1_STATUS=$(echo "$C1" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
if [[ "$C1_STATUS" == "ready_for_future_owner_approved_live_plan" ]]; then
  pass "C1: ready_placeholder_validation -> ready"
else
  fail "C1: expected ready, got '$C1_STATUS'"
  ERRORS=$((ERRORS + 1))
fi

# C2. blocked_missing_placeholder -> blocked + placeholders
C2=$(validate_fixture "$FIXTURES/blocked_missing_placeholder.json")
C2_STATUS=$(echo "$C2" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C2_GATE=$(echo "$C2" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$C2_STATUS" == "blocked" ]] && [[ "$C2_GATE" == "placeholders" ]]; then
  pass "C2: blocked_missing_placeholder -> blocked + placeholders"
else
  fail "C2: expected blocked + placeholders, got '$C2_STATUS' '$C2_GATE'"
  ERRORS=$((ERRORS + 1))
fi

# C3. blocked_bad_credential_policy -> blocked + credential_policy
C3=$(validate_fixture "$FIXTURES/blocked_bad_credential_policy.json")
C3_STATUS=$(echo "$C3" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C3_GATE=$(echo "$C3" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$C3_STATUS" == "blocked" ]] && [[ "$C3_GATE" == "credential_policy" ]]; then
  pass "C3: blocked_bad_credential_policy -> blocked + credential_policy"
else
  fail "C3: expected blocked + credential_policy, got '$C3_STATUS' '$C3_GATE'"
  ERRORS=$((ERRORS + 1))
fi

# C4. blocked_bad_record_policy -> blocked + record_policy
C4=$(validate_fixture "$FIXTURES/blocked_bad_record_policy.json")
C4_STATUS=$(echo "$C4" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C4_GATE=$(echo "$C4" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$C4_STATUS" == "blocked" ]] && [[ "$C4_GATE" == "record_policy" ]]; then
  pass "C4: blocked_bad_record_policy -> blocked + record_policy"
else
  fail "C4: expected blocked + record_policy, got '$C4_STATUS' '$C4_GATE'"
  ERRORS=$((ERRORS + 1))
fi

# C5. blocked_missing_approval_policy -> blocked + approval_policy
C5=$(validate_fixture "$FIXTURES/blocked_missing_approval_policy.json")
C5_STATUS=$(echo "$C5" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C5_GATE=$(echo "$C5" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$C5_STATUS" == "blocked" ]] && [[ "$C5_GATE" == "approval_policy" ]]; then
  pass "C5: blocked_missing_approval_policy -> blocked + approval_policy"
else
  fail "C5: expected blocked + approval_policy, got '$C5_STATUS' '$C5_GATE'"
  ERRORS=$((ERRORS + 1))
fi

# C6. blocked_precheck_policy -> blocked + precheck_policy
C6=$(validate_fixture "$FIXTURES/blocked_precheck_policy.json")
C6_STATUS=$(echo "$C6" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C6_GATE=$(echo "$C6" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$C6_STATUS" == "blocked" ]] && [[ "$C6_GATE" == "precheck_policy" ]]; then
  pass "C6: blocked_precheck_policy -> blocked + precheck_policy"
else
  fail "C6: expected blocked + precheck_policy, got '$C6_STATUS' '$C6_GATE'"
  ERRORS=$((ERRORS + 1))
fi

# C7. blocked_postcheck_policy -> blocked + postcheck_policy
C7=$(validate_fixture "$FIXTURES/blocked_postcheck_policy.json")
C7_STATUS=$(echo "$C7" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C7_GATE=$(echo "$C7" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$C7_STATUS" == "blocked" ]] && [[ "$C7_GATE" == "postcheck_policy" ]]; then
  pass "C7: blocked_postcheck_policy -> blocked + postcheck_policy"
else
  fail "C7: expected blocked + postcheck_policy, got '$C7_STATUS' '$C7_GATE'"
  ERRORS=$((ERRORS + 1))
fi

# C8. blocked_rollback_policy -> blocked + rollback_policy
C8=$(validate_fixture "$FIXTURES/blocked_rollback_policy.json")
C8_STATUS=$(echo "$C8" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C8_GATE=$(echo "$C8" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$C8_STATUS" == "blocked" ]] && [[ "$C8_GATE" == "rollback_policy" ]]; then
  pass "C8: blocked_rollback_policy -> blocked + rollback_policy"
else
  fail "C8: expected blocked + rollback_policy, got '$C8_STATUS' '$C8_GATE'"
  ERRORS=$((ERRORS + 1))
fi

# C9. blocked_public_ux_policy -> blocked + public_ux_policy
C9=$(validate_fixture "$FIXTURES/blocked_public_ux_policy.json")
C9_STATUS=$(echo "$C9" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C9_GATE=$(echo "$C9" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
if [[ "$C9_STATUS" == "blocked" ]] && [[ "$C9_GATE" == "public_ux_policy" ]]; then
  pass "C9: blocked_public_ux_policy -> blocked + public_ux_policy"
else
  fail "C9: expected blocked + public_ux_policy, got '$C9_STATUS' '$C9_GATE'"
  ERRORS=$((ERRORS + 1))
fi

# C10. blocked_multi_gate_first_failure -> blocked + placeholders (first)
C10=$(validate_fixture "$FIXTURES/blocked_multi_gate_first_failure.json")
C10_STATUS=$(echo "$C10" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C10_GATE=$(echo "$C10" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
C10_REASON=$(echo "$C10" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_blocked_reason'])")
C10_BLOCKED=$(echo "$C10" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['blocked_reasons']))")
C10_DIAG=$(echo "$C10" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('diagnostic_blocked_reasons',[])))")
if [[ "$C10_STATUS" == "blocked" ]] && [[ "$C10_GATE" == "placeholders" ]] && [[ "$C10_REASON" == "placeholder gate failed" ]]; then
  pass "C10: blocked_multi_gate_first_failure -> blocked + placeholders"
else
  fail "C10: expected blocked + placeholders, got '$C10_STATUS' '$C10_GATE' '$C10_REASON'"
  ERRORS=$((ERRORS + 1))
fi

# C11. blocked_reasons contains only first reason
if [[ "$C10_BLOCKED" == "1" ]]; then
  pass "C11: blocked_reasons contains only first reason (1 item)"
else
  fail "C11: blocked_reasons should contain only 1 reason, got $C10_BLOCKED"
  ERRORS=$((ERRORS + 1))
fi

# C12. diagnostic_blocked_reasons has multiple reasons
if [[ "$C10_DIAG" -gt 1 ]]; then
  pass "C12: diagnostic_blocked_reasons has $C10_DIAG reasons"
else
  fail "C12: diagnostic_blocked_reasons should have multiple reasons, got $C10_DIAG"
  ERRORS=$((ERRORS + 1))
fi

# C13. uncertain_malformed_input -> uncertain (missing public_ux_policy)
C13=$(validate_fixture "$FIXTURES/uncertain_malformed_input.json")
C13_STATUS=$(echo "$C13" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C13_GATE=$(echo "$C13" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
C13_REASON=$(echo "$C13" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_blocked_reason'])")
C13_BLOCKED=$(echo "$C13" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['blocked_reasons']))")
C13_DIAG=$(echo "$C13" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('diagnostic_blocked_reasons',[])))")
if [[ "$C13_STATUS" == "uncertain" ]] && [[ "$C13_GATE" == "public_ux_policy" ]] && [[ "$C13_REASON" == "malformed placeholder input" ]]; then
  pass "C13: uncertain_malformed_input -> uncertain + public_ux_policy + malformed"
else
  fail "C13: expected uncertain + public_ux_policy + malformed, got '$C13_STATUS' '$C13_GATE' '$C13_REASON'"
  ERRORS=$((ERRORS + 1))
fi

# C14. uncertain_malformed_input blocked_reasons is empty
if [[ "$C13_BLOCKED" == "0" ]]; then
  pass "C14: uncertain_malformed_input blocked_reasons is empty"
else
  fail "C14: uncertain_malformed_input blocked_reasons should be empty, got $C13_BLOCKED"
  ERRORS=$((ERRORS + 1))
fi

# C15. uncertain_malformed_input diagnostic_blocked_reasons has at least 1
if [[ "$C13_DIAG" -ge 1 ]]; then
  pass "C15: uncertain_malformed_input diagnostic has $C13_DIAG reasons"
else
  fail "C15: uncertain_malformed_input diagnostic should have >= 1 reason, got $C13_DIAG"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Semantic locks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Semantic locks ---"
echo ""

# D1-D10. Ready fixture output checks
D1_OUT=$(render_fixture "$FIXTURES/ready_placeholder_validation.json")
assert_contains "$D1_OUT" "Status: ready_for_future_owner_approved_live_plan" "D1: ready status"
assert_contains "$D1_OUT" "Mode: placeholder_validation_only" "D2: placeholder_validation_only mode"
assert_contains "$D1_OUT" "Placeholder validation only" "D3: placeholder validation only"
assert_contains "$D1_OUT" "Live Cloudflare called: no" "D4: live cloudflare called: no"
assert_contains "$D1_OUT" "Real DNS mutation performed: no" "D5: real dns mutation: no"
assert_contains "$D1_OUT" "Real env read: no" "D6: real env read: no"
assert_contains "$D1_OUT" "Public apply allowed: no" "D7: public apply allowed: no"
assert_contains "$D1_OUT" "Actual live test allowed: no" "D8: actual live test allowed: no"
assert_contains "$D1_OUT" "Requires later owner approval: yes" "D9: requires later owner approval: yes"
assert_not_contains "$D1_OUT" "allowed: yes" "D10: no allowed: yes in output"

# D11-D16. Multi-gate fixture output checks
D11_OUT=$(render_fixture "$FIXTURES/blocked_multi_gate_first_failure.json")
assert_contains "$D11_OUT" "Status: blocked" "D11: blocked status"
assert_contains "$D11_OUT" "First failed gate: placeholders" "D12: first failed gate shown"
assert_contains "$D11_OUT" "First blocked reason: placeholder gate failed" "D13: first blocked reason shown"
assert_not_contains "$D11_OUT" "credential policy gate failed" "D14: no credential reason in output"
assert_not_contains "$D11_OUT" "record identity policy gate failed" "D15: no record reason in output"
assert_not_contains "$D11_OUT" "public UX policy gate failed" "D16: no public UX reason in output"

# D17-D22. Uncertain malformed fixture output checks
D17_OUT=$(render_fixture "$FIXTURES/uncertain_malformed_input.json")
assert_contains "$D17_OUT" "Status: uncertain" "D17: uncertain status"
assert_contains "$D17_OUT" "First failed gate: public_ux_policy" "D18: first failed gate shown"
assert_contains "$D17_OUT" "First blocked reason: malformed placeholder input" "D19: malformed reason shown"
assert_contains "$D17_OUT" "Actual live test is not allowed" "D20: live test not allowed"
assert_not_contains "$D17_OUT" "Status: blocked" "D21: no blocked status in uncertain output"
assert_not_contains "$D17_OUT" "ready_for_future_owner_approved_live_plan" "D22: no ready status in uncertain output"
assert_not_contains "$D17_OUT" "public UX policy gate failed" "D23: no policy reason in uncertain output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Output safety
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Output safety ---"
echo ""

for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  out=$(render_fixture "$fixture_file")

  assert_not_contains "$out" "example.com" "E: $fname no example.com"
  assert_not_contains "$out" "203.0.113" "E: $fname no IPv4"
  assert_not_contains "$out" "2001:db8" "E: $fname no IPv6"
  assert_not_contains "$out" "recordId" "E: $fname no recordId"
  assert_not_contains "$out" "Zone ID" "E: $fname no Zone ID"
  assert_not_contains "$out" "Account ID" "E: $fname no Account ID"
  assert_not_contains "$out" "Authorization" "E: $fname no Authorization"
  assert_not_contains "$out" "CF_API_TOKEN" "E: $fname no token"
  assert_not_contains "$out" "workers.dev" "E: $fname no workers.dev"
  assert_not_contains "$out" "vless://" "E: $fname no vless://"
  assert_not_contains "$out" "PRIVATE KEY" "E: $fname no PRIVATE KEY"
  assert_not_contains "$out" "apply --yes" "E: $fname no apply --yes"

  if echo "$out" | grep -qE '[a-f0-9]{64}'; then
    fail "E: $fname has 64-char hex"
    ERRORS=$((ERRORS + 1))
  else
    pass "E: $fname no 64-char hex"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. No network / no public integration
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. No network / no public integration ---"
echo ""

assert_not_contains "$MODULE_SOURCE" "import requests" "F1: no requests"
assert_not_contains "$MODULE_SOURCE" "import urllib" "F1: no urllib"
assert_not_contains "$MODULE_SOURCE" "import http.client" "F1: no http.client"
assert_not_contains "$MODULE_SOURCE" "import socket" "F1: no socket"
assert_not_contains "$MODULE_SOURCE" "import subprocess" "F1: no subprocess"
assert_not_contains "$MODULE_SOURCE" "import os" "F1: no os"
assert_not_contains "$MODULE_SOURCE" "import pathlib" "F1: no pathlib"
assert_not_contains "$MODULE_SOURCE" "import curl" "F1: no curl"
assert_not_contains "$MODULE_SOURCE" "import wrangler" "F1: no wrangler"

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_one_record_live_runbook_validator_mock' "$loc" 2>/dev/null; then
    fail "F2: $loc references module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "F2: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Existing safe tests still pass
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Existing safe tests still pass ---"
echo ""

for test_file in \
  "v2.2.15-dns-apply-helper-boundary-mock.sh" \
  "v2.2.16-dns-apply-safe-renderer.sh" \
  "v2.2.17-dns-apply-safe-integration-mock.sh" \
  "v2.2.18-dns-apply-postcheck-contract.sh" \
  "v2.2.19-dns-apply-postcheck-classifier-mock.sh" \
  "v2.2.20-controlled-live-gate-contract.sh" \
  "v2.2.21-controlled-live-gate-placeholder-mock.sh" \
  "v2.2.22-controlled-live-wrapper-mock.sh" \
  "v2.2.23-owner-approved-live-runbook-contract.sh"; do
  if bash "$ROOT/tests/$test_file" > /dev/null 2>&1; then
    pass "G: $test_file passes"
  else
    fail "G: $test_file fails"
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
  echo -e "  ${GREEN}All v2.2.24 One-Record Live Runbook Validator Mock tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
