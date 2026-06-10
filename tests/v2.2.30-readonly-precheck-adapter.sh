#!/usr/bin/env bash
# NanoBK Proxy Suite — Read-only Precheck Adapter Test
#
# Tests read-only precheck plan adapter in the dryrun wrapper.
# Does NOT call Cloudflare. Does NOT mutate DNS.
#
# Usage:
#   bash tests/v2.2.30-readonly-precheck-adapter.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/dev/nanobk-cf-dns-dryrun-wrapper"
FIXTURES="$ROOT/tests/fixtures/v2.2.30"

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
echo "=== Read-only Precheck Adapter Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Runner exists
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Runner file checks ---"
echo ""

if [[ -x "$RUNNER" ]]; then
  pass "A1: runner exists and executable"
else
  fail "A1: runner does NOT exist or is NOT executable"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Precheck ready
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Precheck ready ---"
echo ""

B_OUT=$("$RUNNER" --plan "$FIXTURES/runner_readonly_precheck_ready.json" --precheck-only 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: precheck ready exits 0"
else
  fail "B1: precheck ready should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "Status: dryrun_preview_ready" "B2: dryrun_preview_ready"
assert_contains "$B_OUT" "Can apply: no" "B3: can apply no"
assert_contains "$B_OUT" "Mutation allowed: no" "B4: mutation allowed no"
assert_contains "$B_OUT" "Public apply allowed: no" "B5: public apply no"
assert_contains "$B_OUT" "Can query: no" "B6: can query no"
assert_contains "$B_OUT" "Cloudflare GET called: no" "B7: cf get called no"
assert_contains "$B_OUT" "API response printed: no" "B8: raw api response no"
assert_contains "$B_OUT" "Read-only precheck plan present: yes" "B9: precheck plan present"
assert_contains "$B_OUT" "Safe zone category: yes" "B10: safe zone yes"
assert_contains "$B_OUT" "Safe record category: yes" "B11: safe record yes"
assert_contains "$B_OUT" "Delete planned: no" "B12: delete planned no"
assert_contains "$B_OUT" "Overwrite planned: no" "B13: overwrite planned no"
assert_contains "$B_OUT" "Raw values present: no" "B14: raw values no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Blocked cases
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Blocked cases ---"
echo ""

# C1. Raw values present
C1_OUT=$("$RUNNER" --plan "$FIXTURES/runner_blocked_raw_values_present.json" --precheck-only 2>&1) && C1_RC=0 || C1_RC=$?
if [[ "$C1_RC" == "2" ]]; then
  pass "C1: raw values exits 2"
else
  fail "C1: raw values should exit 2, got $C1_RC"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$C1_OUT" "Status: blocked" "C1b: blocked status"
assert_contains "$C1_OUT" "First failed gate: read_only_precheck_gate" "C1c: first failed gate"
assert_contains "$C1_OUT" "raw values present" "C1d: raw values reason"

# C2. Delete planned
C2_OUT=$("$RUNNER" --plan "$FIXTURES/runner_blocked_delete_planned.json" --precheck-only 2>&1) && C2_RC=0 || C2_RC=$?
if [[ "$C2_RC" == "2" ]]; then
  pass "C2: delete planned exits 2"
else
  fail "C2: delete planned should exit 2, got $C2_RC"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$C2_OUT" "delete planned" "C2b: delete planned reason"

# C3. Overwrite planned
C3_OUT=$("$RUNNER" --plan "$FIXTURES/runner_blocked_overwrite_planned.json" --precheck-only 2>&1) && C3_RC=0 || C3_RC=$?
if [[ "$C3_RC" == "2" ]]; then
  pass "C3: overwrite planned exits 2"
else
  fail "C3: overwrite planned should exit 2, got $C3_RC"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$C3_OUT" "overwrite planned" "C3b: overwrite planned reason"

# C4. Existing unmanaged record
C4_OUT=$("$RUNNER" --plan "$FIXTURES/runner_blocked_existing_unmanaged_record.json" --precheck-only 2>&1) && C4_RC=0 || C4_RC=$?
if [[ "$C4_RC" == "2" ]]; then
  pass "C4: existing unmanaged exits 2"
else
  fail "C4: existing unmanaged should exit 2, got $C4_RC"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$C4_OUT" "existing unmanaged record present" "C4b: unmanaged reason"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Uncertain case
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Uncertain case ---"
echo ""

D_OUT=$("$RUNNER" --plan "$FIXTURES/runner_uncertain_cname_unknown.json" --precheck-only 2>&1) && D_RC=0 || D_RC=$?

# CNAME unknown should be blocked or uncertain (not 0)
if [[ "$D_RC" != "0" ]]; then
  pass "D1: cname unknown exits non-zero ($D_RC)"
else
  fail "D1: cname unknown should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Safety scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Safety scan ---"
echo ""

ALL_OUTPUTS="$B_OUT $C1_OUT $C2_OUT $C3_OUT $C4_OUT $D_OUT"

assert_not_contains "$ALL_OUTPUTS" "example.com" "E1: no example.com"
assert_not_contains "$ALL_OUTPUTS" "203.0.113" "E2: no IPv4"
assert_not_contains "$ALL_OUTPUTS" "2001:db8" "E3: no IPv6"
assert_not_contains "$ALL_OUTPUTS" "recordId" "E4: no recordId"
assert_not_contains "$ALL_OUTPUTS" "Zone ID" "E5: no Zone ID"
assert_not_contains "$ALL_OUTPUTS" "Account ID" "E6: no Account ID"
assert_not_contains "$ALL_OUTPUTS" "Authorization" "E7: no Authorization"
assert_not_contains "$ALL_OUTPUTS" "CF_API_TOKEN" "E8: no CF_API_TOKEN"
assert_not_contains "$ALL_OUTPUTS" "workers.dev" "E9: no workers.dev"
assert_not_contains "$ALL_OUTPUTS" "vless://" "E10: no vless://"
assert_not_contains "$ALL_OUTPUTS" "PRIVATE KEY" "E11: no PRIVATE KEY"
assert_not_contains "$ALL_OUTPUTS" "apply --yes" "E12: no apply --yes"

if echo "$ALL_OUTPUTS" | grep -qE '[a-f0-9]{64}'; then
  fail "E13: no 64-char hex"
  ERRORS=$((ERRORS + 1))
else
  pass "E13: no 64-char hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. No public references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. No public references ---"
echo ""

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk_cf_dns_apply_dryrun_wrapper\|nanobk-cf-dns-dryrun-wrapper' "$loc" 2>/dev/null; then
    fail "F1: $loc references runner/module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "F1: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Compatibility
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Compatibility ---"
echo ""

if bash "$ROOT/tests/v2.2.29-local-credential-precheck.sh" > /dev/null 2>&1; then
  pass "G1: v2.2.29 test passes"
else
  fail "G1: v2.2.29 test fails"
  ERRORS=$((ERRORS + 1))
fi

if bash "$ROOT/tests/v2.2.28-local-dryrun-runner.sh" > /dev/null 2>&1; then
  pass "G2: v2.2.28 test passes"
else
  fail "G2: v2.2.28 test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.30 Read-only Precheck Adapter tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
