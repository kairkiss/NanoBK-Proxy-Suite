#!/usr/bin/env bash
# NanoBK Proxy Suite — Controlled Live Gate Placeholder Mock Test
#
# Tests lib/nanobk_cf_dns_apply_controlled_live_gate_mock.py with
# safe static fixtures. Does NOT call Cloudflare. Does NOT call helper.
#
# Usage:
#   bash tests/v2.2.21-controlled-live-gate-placeholder-mock.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_apply_controlled_live_gate_mock.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.21"

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
echo "=== Controlled Live Gate Placeholder Mock Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. File/scope checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. File/scope checks ---"
echo ""

# A1. Module exists
if [[ -f "$MODULE" ]]; then
  pass "A1: module exists"
else
  fail "A1: module does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

MODULE_SOURCE=$(cat "$MODULE")

# A2. Fixture directory exists
if [[ -d "$FIXTURES" ]]; then
  pass "A2: fixture directory exists"
else
  fail "A2: fixture directory does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

# A3. Module says pure mock
assert_contains "$MODULE_SOURCE" "Pure mock" "A3: module says pure mock"

# A4. Module says no Cloudflare/helper/DNS/env
assert_contains "$MODULE_SOURCE" "Does not call Cloudflare" "A4: no Cloudflare"
assert_contains "$MODULE_SOURCE" "Does not call helper" "A4: no helper"
assert_contains "$MODULE_SOURCE" "Does not read real env" "A4: no env reading"
assert_contains "$MODULE_SOURCE" "Does not mutate DNS" "A4: no DNS mutation"

# A5. No public integration
assert_not_contains "$MODULE_SOURCE" "public CLI" "A5: no public CLI wording"

# A6. No references in bin/installer/bot/web
for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_controlled_live_gate_mock' "$loc" 2>/dev/null; then
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
# C. Gate evaluation cases
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Gate evaluation cases ---"
echo ""

evaluate_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_controlled_live_gate_mock import evaluate_controlled_live_gate
with open('$fixture') as f:
    data = json.load(f)
model = evaluate_controlled_live_gate(data)
print(json.dumps(model))
" 2>&1
}

render_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_controlled_live_gate_mock import evaluate_controlled_live_gate, render_controlled_live_gate_summary
with open('$fixture') as f:
    data = json.load(f)
model = evaluate_controlled_live_gate(data)
print(render_controlled_live_gate_summary(model))
" 2>&1
}

# C1. ready_gate_placeholder.json -> ready_for_owner_approved_live_test_plan
C1=$(evaluate_fixture "$FIXTURES/ready_gate_placeholder.json")
C1_STATUS=$(echo "$C1" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
if [[ "$C1_STATUS" == "ready_for_owner_approved_live_test_plan" ]]; then
  pass "C1: ready_gate_placeholder -> ready_for_owner_approved_live_test_plan"
else
  fail "C1: expected ready_for_owner_approved_live_test_plan, got '$C1_STATUS'"
  ERRORS=$((ERRORS + 1))
fi

# C2. blocked_missing_approval.json -> blocked + owner approval gate failed
C2=$(evaluate_fixture "$FIXTURES/blocked_missing_approval.json")
C2_STATUS=$(echo "$C2" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C2_REASONS=$(echo "$C2" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C2_STATUS" == "blocked" ]] && [[ "$C2_REASONS" == *"owner approval gate failed"* ]]; then
  pass "C2: blocked_missing_approval -> blocked + owner approval gate failed"
else
  fail "C2: expected blocked + owner approval gate failed, got '$C2_STATUS' '$C2_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C3. blocked_bad_credential_permission.json -> blocked + credential handling gate failed
C3=$(evaluate_fixture "$FIXTURES/blocked_bad_credential_permission.json")
C3_STATUS=$(echo "$C3" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C3_REASONS=$(echo "$C3" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C3_STATUS" == "blocked" ]] && [[ "$C3_REASONS" == *"credential handling gate failed"* ]]; then
  pass "C3: blocked_bad_credential_permission -> blocked + credential handling gate failed"
else
  fail "C3: expected blocked + credential handling gate failed, got '$C3_STATUS' '$C3_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C4. blocked_unmanaged_existing_record.json -> blocked + pre-check gate failed
C4=$(evaluate_fixture "$FIXTURES/blocked_unmanaged_existing_record.json")
C4_STATUS=$(echo "$C4" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C4_REASONS=$(echo "$C4" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C4_STATUS" == "blocked" ]] && [[ "$C4_REASONS" == *"pre-check gate failed"* ]]; then
  pass "C4: blocked_unmanaged_existing_record -> blocked + pre-check gate failed"
else
  fail "C4: expected blocked + pre-check gate failed, got '$C4_STATUS' '$C4_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C5. blocked_cname_conflict.json -> blocked + pre-check gate failed
C5=$(evaluate_fixture "$FIXTURES/blocked_cname_conflict.json")
C5_STATUS=$(echo "$C5" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C5_REASONS=$(echo "$C5" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C5_STATUS" == "blocked" ]] && [[ "$C5_REASONS" == *"pre-check gate failed"* ]]; then
  pass "C5: blocked_cname_conflict -> blocked + pre-check gate failed"
else
  fail "C5: expected blocked + pre-check gate failed, got '$C5_STATUS' '$C5_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C6. blocked_redaction_failure.json -> blocked + redaction gate failed
C6=$(evaluate_fixture "$FIXTURES/blocked_redaction_failure.json")
C6_STATUS=$(echo "$C6" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C6_REASONS=$(echo "$C6" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C6_STATUS" == "blocked" ]] && [[ "$C6_REASONS" == *"redaction gate failed"* ]]; then
  pass "C6: blocked_redaction_failure -> blocked + redaction gate failed"
else
  fail "C6: expected blocked + redaction gate failed, got '$C6_STATUS' '$C6_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C7. blocked_public_ux_enabled.json -> blocked + public UX gate failed
C7=$(evaluate_fixture "$FIXTURES/blocked_public_ux_enabled.json")
C7_STATUS=$(echo "$C7" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C7_REASONS=$(echo "$C7" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C7_STATUS" == "blocked" ]] && [[ "$C7_REASONS" == *"public UX gate failed"* ]]; then
  pass "C7: blocked_public_ux_enabled -> blocked + public UX gate failed"
else
  fail "C7: expected blocked + public UX gate failed, got '$C7_STATUS' '$C7_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

# C8. blocked_live_mutation_not_blocked.json -> blocked + mutation safety gate failed
C8=$(evaluate_fixture "$FIXTURES/blocked_live_mutation_not_blocked.json")
C8_STATUS=$(echo "$C8" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C8_REASONS=$(echo "$C8" | python3 -c "import sys,json; r=json.load(sys.stdin)['blocked_reasons']; print(' '.join(r))")
if [[ "$C8_STATUS" == "blocked" ]] && [[ "$C8_REASONS" == *"mutation safety gate failed"* ]]; then
  pass "C8: blocked_live_mutation_not_blocked -> blocked + mutation safety gate failed"
else
  fail "C8: expected blocked + mutation safety gate failed, got '$C8_STATUS' '$C8_REASONS'"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Semantic locks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Semantic locks ---"
echo ""

# D1-D3. Ready fixture output checks
D1_OUT=$(render_fixture "$FIXTURES/ready_gate_placeholder.json")
assert_contains "$D1_OUT" "Live mutation allowed: no" "D1: live mutation allowed: no"
assert_contains "$D1_OUT" "Public apply allowed: no" "D2: public apply allowed: no"
assert_contains "$D1_OUT" "Requires future owner-approved test: yes" "D3: requires future owner-approved test: yes"
assert_not_contains "$D1_OUT" "live mutation allowed: yes" "D4: no live mutation allowed: yes"
assert_not_contains "$D1_OUT" "public apply allowed: yes" "D5: no public apply allowed: yes"

# D6-D7. Blocked fixture output checks
D6_OUT=$(render_fixture "$FIXTURES/blocked_missing_approval.json")
assert_contains "$D6_OUT" "Status: blocked" "D6: blocked status"
assert_contains "$D6_OUT" "owner approval gate failed" "D7: safe generic reason"
assert_not_contains "$D6_OUT" "exact_phrase_matched" "D8: no raw data in output"

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
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_controlled_live_gate_mock' "$loc" 2>/dev/null; then
    fail "F2: $loc references module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "F2: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. v2.2.20 contract consistency
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. v2.2.20 contract consistency ---"
echo ""

if bash "$ROOT/tests/v2.2.20-controlled-live-gate-contract.sh" > /dev/null 2>&1; then
  pass "G: v2.2.20 contract test passes"
else
  fail "G: v2.2.20 contract test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Existing tests still pass
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Existing tests still pass ---"
echo ""

for test_file in \
  "v2.2.15-dns-apply-helper-boundary-mock.sh" \
  "v2.2.16-dns-apply-safe-renderer.sh" \
  "v2.2.17-dns-apply-safe-integration-mock.sh" \
  "v2.2.18-dns-apply-postcheck-contract.sh" \
  "v2.2.19-dns-apply-postcheck-classifier-mock.sh" \
  "v2.2.20-controlled-live-gate-contract.sh"; do
  if bash "$ROOT/tests/$test_file" > /dev/null 2>&1; then
    pass "H: $test_file passes"
  else
    fail "H: $test_file fails"
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
  echo -e "  ${GREEN}All v2.2.21 Controlled Live Gate Placeholder Mock tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
