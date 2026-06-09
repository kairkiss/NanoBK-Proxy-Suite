#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Apply Dry-run Wrapper Test
#
# Tests lib/nanobk_cf_dns_apply_dryrun_wrapper.py with safe fixtures.
# Does NOT call Cloudflare. Does NOT call helper. Does NOT mutate DNS.
#
# Usage:
#   bash tests/v2.2.27-dns-apply-dryrun-wrapper.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_apply_dryrun_wrapper.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.27"

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
echo "=== DNS Apply Dry-run Wrapper Test ==="
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

assert_contains "$MODULE_SOURCE" "dry-run-only" "A3: says dry-run-only"
assert_contains "$MODULE_SOURCE" "Does not create/update/delete DNS" "A4: no DNS mutation"
assert_contains "$MODULE_SOURCE" "Does not execute live mutation" "A5: no live mutation"
assert_contains "$MODULE_SOURCE" "Does not print real domain" "A6: no real domain"
assert_contains "$MODULE_SOURCE" "Does not cat/source/eval real env" "A7: no env reading"
assert_not_contains "$MODULE_SOURCE" "public CLI" "A8: no public CLI wording"

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
# C. Status cases
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Status cases ---"
echo ""

evaluate_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_dryrun_wrapper import run_dns_apply_dryrun_wrapper
with open('$fixture') as f:
    data = json.load(f)
model = run_dns_apply_dryrun_wrapper(data)
print(json.dumps(model))
" 2>&1
}

render_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_dryrun_wrapper import run_dns_apply_dryrun_wrapper, render_dns_apply_dryrun_summary
with open('$fixture') as f:
    data = json.load(f)
model = run_dns_apply_dryrun_wrapper(data)
print(render_dns_apply_dryrun_summary(model))
" 2>&1
}

# C1. dryrun_preview_ready -> dryrun_preview_ready
C1=$(evaluate_fixture "$FIXTURES/dryrun_preview_ready.json")
C1_STATUS=$(echo "$C1" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C1_CAN=$(echo "$C1" | python3 -c "import sys,json; print(json.load(sys.stdin)['can_preview'])")
if [[ "$C1_STATUS" == "dryrun_preview_ready" ]] && [[ "$C1_CAN" == "yes" ]]; then
  pass "C1: dryrun_preview_ready -> dryrun_preview_ready, can_preview=yes"
else
  fail "C1: expected dryrun_preview_ready+yes, got '$C1_STATUS'+'$C1_CAN'"
  ERRORS=$((ERRORS + 1))
fi

# C2. dryrun_ready_without_helper_path -> dryrun_preview_ready
C2=$(evaluate_fixture "$FIXTURES/dryrun_ready_without_helper_path.json")
C2_STATUS=$(echo "$C2" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C2_HELPER=$(echo "$C2" | python3 -c "import sys,json; print(json.load(sys.stdin)['redacted_preview']['helper_dryrun_available'])")
if [[ "$C2_STATUS" == "dryrun_preview_ready" ]] && [[ "$C2_HELPER" == "no" ]]; then
  pass "C2: without helper path -> dryrun_preview_ready, helper=no"
else
  fail "C2: expected dryrun_preview_ready+no, got '$C2_STATUS'+'$C2_HELPER'"
  ERRORS=$((ERRORS + 1))
fi

# C3-C10. Blocked cases
declare -A BLOCKED_CASES=(
  ["blocked_repo_gate"]="repo_gate"
  ["blocked_credential_reference"]="credential_reference_gate"
  ["blocked_record_identity"]="record_identity_gate"
  ["blocked_read_only_precheck"]="read_only_precheck_gate"
  ["blocked_preview_redaction"]="dryrun_preview_gate"
  ["blocked_helper_dryrun"]="helper_dryrun_gate"
  ["blocked_public_ux"]="public_ux_gate"
)

CI=3
for fixture_name in "${!BLOCKED_CASES[@]}"; do
  expected_gate="${BLOCKED_CASES[$fixture_name]}"
  RESULT=$(evaluate_fixture "$FIXTURES/${fixture_name}.json")
  STATUS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
  GATE=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
  if [[ "$STATUS" == "blocked" ]] && [[ "$GATE" == "$expected_gate" ]]; then
    pass "C${CI}: ${fixture_name} -> blocked + ${expected_gate}"
  else
    fail "C${CI}: ${fixture_name} expected blocked+${expected_gate}, got ${STATUS}+${GATE}"
    ERRORS=$((ERRORS + 1))
  fi
  CI=$((CI + 1))
done

# C11. blocked_multi_gate_first_failure -> blocked + repo_gate
C11=$(evaluate_fixture "$FIXTURES/blocked_multi_gate_first_failure.json")
C11_STATUS=$(echo "$C11" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
C11_GATE=$(echo "$C11" | python3 -c "import sys,json; print(json.load(sys.stdin)['first_failed_gate'])")
C11_BLOCKED=$(echo "$C11" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['blocked_reasons']))")
C11_DIAG=$(echo "$C11" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['diagnostic_blocked_reasons']))")
if [[ "$C11_STATUS" == "blocked" ]] && [[ "$C11_GATE" == "repo_gate" ]]; then
  pass "C11: multi-gate -> blocked + repo_gate"
else
  fail "C11: expected blocked+repo_gate, got '$C11_STATUS'+'$C11_GATE'"
  ERRORS=$((ERRORS + 1))
fi

# C12. uncertain_malformed_input -> uncertain
C12=$(evaluate_fixture "$FIXTURES/uncertain_malformed_input.json")
C12_STATUS=$(echo "$C12" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
if [[ "$C12_STATUS" == "uncertain" ]]; then
  pass "C12: malformed input -> uncertain"
else
  fail "C12: expected uncertain, got '$C12_STATUS'"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. can_apply always no
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. can_apply always no ---"
echo ""

for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  CAN=$(evaluate_fixture "$fixture_file" | python3 -c "import sys,json; print(json.load(sys.stdin)['can_apply'])")
  if [[ "$CAN" == "no" ]]; then
    pass "D: $fname can_apply=no"
  else
    fail "D: $fname can_apply should be no, got '$CAN'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. mutation_allowed always no
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. mutation_allowed always no ---"
echo ""

for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  MUT=$(evaluate_fixture "$fixture_file" | python3 -c "import sys,json; print(json.load(sys.stdin)['mutation_allowed'])")
  if [[ "$MUT" == "no" ]]; then
    pass "E: $fname mutation_allowed=no"
  else
    fail "E: $fname mutation_allowed should be no, got '$MUT'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. public_apply_allowed always no
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. public_apply_allowed always no ---"
echo ""

for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  PUB=$(evaluate_fixture "$fixture_file" | python3 -c "import sys,json; print(json.load(sys.stdin)['public_apply_allowed'])")
  if [[ "$PUB" == "no" ]]; then
    pass "F: $fname public_apply_allowed=no"
  else
    fail "F: $fname public_apply_allowed should be no, got '$PUB'"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Helper dryrun/no-helper branch honesty
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Helper dryrun/no-helper branch honesty ---"
echo ""

# G1. With helper: helper_dryrun_available=yes
G1=$(evaluate_fixture "$FIXTURES/dryrun_preview_ready.json")
G1_HELPER=$(echo "$G1" | python3 -c "import sys,json; print(json.load(sys.stdin)['redacted_preview']['helper_dryrun_available'])")
if [[ "$G1_HELPER" == "yes" ]]; then
  pass "G1: with helper path -> helper_dryrun_available=yes"
else
  fail "G1: expected yes, got '$G1_HELPER'"
  ERRORS=$((ERRORS + 1))
fi

# G2. Without helper: helper_dryrun_available=no
G2=$(evaluate_fixture "$FIXTURES/dryrun_ready_without_helper_path.json")
G2_HELPER=$(echo "$G2" | python3 -c "import sys,json; print(json.load(sys.stdin)['redacted_preview']['helper_dryrun_available'])")
if [[ "$G2_HELPER" == "no" ]]; then
  pass "G2: without helper path -> helper_dryrun_available=no"
else
  fail "G2: expected no, got '$G2_HELPER'"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. First-failure semantics
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. First-failure semantics ---"
echo ""

# H1-H3. Multi-gate first failure
if [[ "$C11_BLOCKED" == "1" ]]; then
  pass "H1: multi-gate blocked_reasons length = 1"
else
  fail "H1: blocked_reasons should be 1, got $C11_BLOCKED"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$C11_DIAG" -gt 1 ]]; then
  pass "H2: multi-gate diagnostic_blocked_reasons > 1 ($C11_DIAG)"
else
  fail "H2: diagnostic should be > 1, got $C11_DIAG"
  ERRORS=$((ERRORS + 1))
fi

H3_OUT=$(render_fixture "$FIXTURES/blocked_multi_gate_first_failure.json")
assert_not_contains "$H3_OUT" "credential reference gate failed" "H3: no credential reason in output"
assert_not_contains "$H3_OUT" "record identity gate failed" "H4: no record reason in output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Rendered output safety
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Rendered output safety ---"
echo ""

for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  out=$(render_fixture "$fixture_file")

  assert_not_contains "$out" "example.com" "I: $fname no example.com"
  assert_not_contains "$out" "203.0.113" "I: $fname no IPv4"
  assert_not_contains "$out" "2001:db8" "I: $fname no IPv6"
  assert_not_contains "$out" "recordId" "I: $fname no recordId"
  assert_not_contains "$out" "Zone ID" "I: $fname no Zone ID"
  assert_not_contains "$out" "Account ID" "I: $fname no Account ID"
  assert_not_contains "$out" "Authorization" "I: $fname no Authorization"
  assert_not_contains "$out" "CF_API_TOKEN" "I: $fname no token"
  assert_not_contains "$out" "workers.dev" "I: $fname no workers.dev"
  assert_not_contains "$out" "vless://" "I: $fname no vless://"
  assert_not_contains "$out" "PRIVATE KEY" "I: $fname no PRIVATE KEY"
  assert_not_contains "$out" "apply --yes" "I: $fname no apply --yes"

  if echo "$out" | grep -qE '[a-f0-9]{64}'; then
    fail "I: $fname has 64-char hex"
    ERRORS=$((ERRORS + 1))
  else
    pass "I: $fname no 64-char hex"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. No public references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. No public references ---"
echo ""

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_dryrun_wrapper' "$loc" 2>/dev/null; then
    fail "J1: $loc references module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "J1: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. No forbidden imports
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. No forbidden imports ---"
echo ""

assert_not_contains "$MODULE_SOURCE" "import requests" "K1: no requests"
assert_not_contains "$MODULE_SOURCE" "import urllib" "K1: no urllib"
assert_not_contains "$MODULE_SOURCE" "import http.client" "K1: no http.client"
assert_not_contains "$MODULE_SOURCE" "import socket" "K1: no socket"
assert_not_contains "$MODULE_SOURCE" "import curl" "K1: no curl"
assert_not_contains "$MODULE_SOURCE" "import wrangler" "K1: no wrangler"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. No live helper mutation path
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. No live helper mutation path ---"
echo ""

assert_not_contains "$MODULE_SOURCE" "\"--yes\"" "L1: no --yes flag"
assert_not_contains "$MODULE_SOURCE" "'--yes'" "L1b: no --yes flag single quote"
assert_contains "$MODULE_SOURCE" "\"--dry-run\"" "L2: uses --dry-run flag"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# M. Existing safe tests
# ══════════════════════════════════════════════════════════════════════════════

echo "--- M. Existing safe tests ---"
echo ""

for test_file in \
  "v2.2.25-controlled-live-wrapper-skeleton-fake.sh" \
  "v2.2.26-owner-approved-manual-live-plan-contract.sh"; do
  if bash "$ROOT/tests/$test_file" > /dev/null 2>&1; then
    pass "M: $test_file passes"
  else
    fail "M: $test_file fails"
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
  echo -e "  ${GREEN}All v2.2.27 DNS Apply Dry-run Wrapper tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
