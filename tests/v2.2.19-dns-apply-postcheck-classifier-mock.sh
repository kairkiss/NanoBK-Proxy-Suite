#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Apply Post-check Classifier Mock Test
#
# Tests lib/nanobk_cf_dns_apply_postcheck_classifier_mock.py with
# static safe fixtures. Does NOT call Cloudflare. Does NOT call helper.
#
# Usage:
#   bash tests/v2.2.19-dns-apply-postcheck-classifier-mock.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_dns_apply_postcheck_classifier_mock.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.19"

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
echo "=== DNS Apply Post-check Classifier Mock Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. File/scope checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. File/scope checks ---"
echo ""

# A1. Module exists
if [[ -f "$MODULE" ]]; then
  pass "A1: classifier module exists"
else
  fail "A1: classifier module does NOT exist"
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

# A4. Module says no Cloudflare/helper/DNS mutation
assert_contains "$MODULE_SOURCE" "Does not call Cloudflare" "A4: says no Cloudflare"
assert_contains "$MODULE_SOURCE" "Does not call helper" "A4: says no helper"
assert_contains "$MODULE_SOURCE" "Does not mutate DNS" "A4: says no DNS mutation"

# A5. No public integration
assert_not_contains "$MODULE_SOURCE" "public CLI" "A5: no public CLI wording"

# A6. No reference in bin/nanobk, installer, bot, web
for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_postcheck_classifier_mock' "$loc" 2>/dev/null; then
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

  assert_not_contains "$content" "example.com" "B: $fname has no example.com"
  assert_not_contains "$content" "203.0.113" "B: $fname has no IPv4"
  assert_not_contains "$content" "2001:db8" "B: $fname has no IPv6"
  assert_not_contains "$content" "recordId" "B: $fname has no recordId"
  assert_not_contains "$content" "Zone ID" "B: $fname has no Zone ID"
  assert_not_contains "$content" "Account ID" "B: $fname has no Account ID"
  assert_not_contains "$content" "Authorization" "B: $fname has no Authorization"
  assert_not_contains "$content" "CF_API_TOKEN" "B: $fname has no token"
  assert_not_contains "$content" "workers.dev" "B: $fname has no workers.dev"
  assert_not_contains "$content" "vless://" "B: $fname has no vless://"
  assert_not_contains "$content" "PRIVATE KEY" "B: $fname has no PRIVATE KEY"

  # Check for 64-char hex
  if echo "$content" | grep -qE '[a-f0-9]{64}'; then
    fail "B: $fname has 64-char hex"
    ERRORS=$((ERRORS + 1))
  else
    pass "B: $fname has no 64-char hex"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Classification cases
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Classification cases ---"
echo ""

classify_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_postcheck_classifier_mock import classify_postcheck
with open('$fixture') as f:
    data = json.load(f)
model = classify_postcheck(data)
print(model['status'])
" 2>&1
}

render_fixture() {
  local fixture="$1"
  python3 -c "
import sys, json
sys.path.insert(0, '$ROOT/lib')
from nanobk_cf_dns_apply_postcheck_classifier_mock import classify_postcheck, render_postcheck_summary
with open('$fixture') as f:
    data = json.load(f)
model = classify_postcheck(data)
print(render_postcheck_summary(model))
" 2>&1
}

# C1. ready.json -> ready
C1=$(classify_fixture "$FIXTURES/ready.json")
if [[ "$C1" == "ready" ]]; then
  pass "C1: ready.json -> ready"
else
  fail "C1: ready.json -> expected ready, got '$C1'"
  ERRORS=$((ERRORS + 1))
fi

# C2. applied_fake_only.json -> applied
C2=$(classify_fixture "$FIXTURES/applied_fake_only.json")
if [[ "$C2" == "applied" ]]; then
  pass "C2: applied_fake_only.json -> applied"
else
  fail "C2: applied_fake_only.json -> expected applied, got '$C2'"
  ERRORS=$((ERRORS + 1))
fi

# C3. verified_live.json -> verified
C3=$(classify_fixture "$FIXTURES/verified_live.json")
if [[ "$C3" == "verified" ]]; then
  pass "C3: verified_live.json -> verified"
else
  fail "C3: verified_live.json -> expected verified, got '$C3'"
  ERRORS=$((ERRORS + 1))
fi

# C4. partial_live.json -> partial
C4=$(classify_fixture "$FIXTURES/partial_live.json")
if [[ "$C4" == "partial" ]]; then
  pass "C4: partial_live.json -> partial"
else
  fail "C4: partial_live.json -> expected partial, got '$C4'"
  ERRORS=$((ERRORS + 1))
fi

# C5. conflict.json -> conflict
C5=$(classify_fixture "$FIXTURES/conflict.json")
if [[ "$C5" == "conflict" ]]; then
  pass "C5: conflict.json -> conflict"
else
  fail "C5: conflict.json -> expected conflict, got '$C5'"
  ERRORS=$((ERRORS + 1))
fi

# C6. failed_all_mutations.json -> failed
C6=$(classify_fixture "$FIXTURES/failed_all_mutations.json")
if [[ "$C6" == "failed" ]]; then
  pass "C6: failed_all_mutations.json -> failed"
else
  fail "C6: failed_all_mutations.json -> expected failed, got '$C6'"
  ERRORS=$((ERRORS + 1))
fi

# C7. uncertain_unknown.json -> uncertain
C7=$(classify_fixture "$FIXTURES/uncertain_unknown.json")
if [[ "$C7" == "uncertain" ]]; then
  pass "C7: uncertain_unknown.json -> uncertain"
else
  fail "C7: uncertain_unknown.json -> expected uncertain, got '$C7'"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Semantic locks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Semantic locks ---"
echo ""

# D1. fake_only fixture never returns verified
D1_STATUS=$(classify_fixture "$FIXTURES/applied_fake_only.json")
if [[ "$D1_STATUS" != "verified" ]]; then
  pass "D1: fake_only never returns verified (got '$D1_STATUS')"
else
  fail "D1: fake_only returned verified"
  ERRORS=$((ERRORS + 1))
fi

# D2. applied output contains "Applied does not mean verified"
D2_OUT=$(render_fixture "$FIXTURES/applied_fake_only.json")
assert_contains "$D2_OUT" "Applied does not mean verified" "D2: applied output has honesty statement"

# D3. verified output contains "Verified by post-check"
D3_OUT=$(render_fixture "$FIXTURES/verified_live.json")
assert_contains "$D3_OUT" "Verified by post-check" "D3: verified output has post-check statement"

# D4. fake_only output contains no live verification
assert_contains "$D2_OUT" "no live Cloudflare verification was performed" "D4: fake_only output says no live verification"

# D5. Every output contains safety statements
for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  out=$(render_fixture "$fixture_file")
  assert_contains "$out" "Verified requires post-check: yes" "D5: $fname has postcheck required"
  assert_contains "$out" "Fake-only live verified: no" "D5: $fname has fake_only_live_verified=no"
  assert_contains "$out" "Deletes supported: no" "D5: $fname has deletes_supported=no"
done

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

  # Check for 64-char hex
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

# F1. No network imports
assert_not_contains "$MODULE_SOURCE" "import requests" "F1: no requests"
assert_not_contains "$MODULE_SOURCE" "import urllib" "F1: no urllib"
assert_not_contains "$MODULE_SOURCE" "import http.client" "F1: no http.client"
assert_not_contains "$MODULE_SOURCE" "import socket" "F1: no socket"
assert_not_contains "$MODULE_SOURCE" "import subprocess" "F1: no subprocess"
assert_not_contains "$MODULE_SOURCE" "import curl" "F1: no curl"
assert_not_contains "$MODULE_SOURCE" "import wrangler" "F1: no wrangler"

# F2. No references in bin/installer/bot/web
for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_postcheck_classifier_mock' "$loc" 2>/dev/null; then
    fail "F2: $loc references module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "F2: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Contract doc consistency
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Contract doc consistency ---"
echo ""

if bash "$ROOT/tests/v2.2.18-dns-apply-postcheck-contract.sh" > /dev/null 2>&1; then
  pass "G: v2.2.18 contract test passes"
else
  fail "G: v2.2.18 contract test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Existing tests still pass
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Existing tests still pass ---"
echo ""

for test_file in \
  "v2.2.8-dns-apply-beginner-ux-mock.sh" \
  "v2.2.10-dns-apply-ux-fake-wrapper.sh" \
  "v2.2.11-dns-apply-ux-wrapper-hardening.sh" \
  "v2.2.15-dns-apply-helper-boundary-mock.sh" \
  "v2.2.16-dns-apply-safe-renderer.sh" \
  "v2.2.17-dns-apply-safe-integration-mock.sh" \
  "v2.2.18-dns-apply-postcheck-contract.sh"; do
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
  echo -e "  ${GREEN}All v2.2.19 DNS Apply Post-check Classifier Mock tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
