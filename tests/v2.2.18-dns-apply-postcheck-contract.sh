#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Apply Post-check Contract Test
#
# Validates docs/planning-v2.2.18-dns-apply-postcheck-contract.md
# for required status semantics, post-check fields, forbidden output
# classes, stop-on-first-failure policy, and no dangerous public instructions.
#
# Does NOT call Cloudflare. Does NOT call helper. Does NOT perform DNS mutation.
#
# Usage:
#   bash tests/v2.2.18-dns-apply-postcheck-contract.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/docs/planning-v2.2.18-dns-apply-postcheck-contract.md"

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
echo "=== DNS Apply Post-check Contract Test ==="
echo ""

# ── Load doc ─────────────────────────────────────────────────────────────────

if [[ ! -f "$DOC" ]]; then
  fail "DOC: planning doc does not exist"
  ERRORS=$((ERRORS + 1))
  echo ""
  echo "=== Test Summary ==="
  echo ""
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi

DOC_SOURCE=$(cat "$DOC")

# ══════════════════════════════════════════════════════════════════════════════
# A. Scope checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Scope checks ---"
echo ""

assert_contains "$DOC_SOURCE" "docs/mock-only" "A1: says docs/mock-only"
assert_contains "$DOC_SOURCE" "No real Cloudflare" "A2: says no real Cloudflare"
assert_contains "$DOC_SOURCE" "No real DNS mutation" "A3: says no real DNS mutation"
assert_contains "$DOC_SOURCE" "No public CLI" "A4: says no public CLI"
assert_contains "$DOC_SOURCE" "No Bot" "A5: says no Bot"
assert_contains "$DOC_SOURCE" "No Web" "A5: says no Web"
assert_contains "$DOC_SOURCE" "installer" "A5: mentions installer"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Status semantics checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Status semantics checks ---"
echo ""

assert_contains "$DOC_SOURCE" "verified must require post-check" "B1: verified requires post-check"
assert_contains "$DOC_SOURCE" "applied must not mean" "B2: applied must not mean verified"
assert_contains "$DOC_SOURCE" "fake_only must never claim live verified" "B3: fake_only never claims live verified"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Required status buckets
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Required status buckets ---"
echo ""

assert_contains "$DOC_SOURCE" "ready" "C1: has ready"
assert_contains "$DOC_SOURCE" "applied" "C2: has applied"
assert_contains "$DOC_SOURCE" "verified" "C3: has verified"
assert_contains "$DOC_SOURCE" "partial" "C4: has partial"
assert_contains "$DOC_SOURCE" "conflict" "C5: has conflict"
assert_contains "$DOC_SOURCE" "failed" "C6: has failed"
assert_contains "$DOC_SOURCE" "uncertain" "C7: has uncertain"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Post-check fields
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Post-check fields ---"
echo ""

assert_contains "$DOC_SOURCE" "record exists" "D1: has record exists"
assert_contains "$DOC_SOURCE" "content matches expected" "D2: has content matches expected"
assert_contains "$DOC_SOURCE" "proxied" "D3: mentions proxied"
assert_contains "$DOC_SOURCE" "no CNAME conflict" "D4: has no CNAME conflict"
assert_contains "$DOC_SOURCE" "A and AAAA independently verified" "D5: A and AAAA independently verified"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Stop-on-first-failure
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Stop-on-first-failure ---"
echo ""

assert_contains "$DOC_SOURCE" "stop on first mutation failure" "E1: has stop on first mutation failure"
assert_contains "$DOC_SOURCE" "Continue-and-report-partial" "E2: has Continue-and-report-partial"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Forbidden output classes
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Forbidden output classes ---"
echo ""

assert_contains "$DOC_SOURCE" "raw domain" "F1: has raw domain"
assert_contains "$DOC_SOURCE" "raw hostname" "F2: has raw hostname"
assert_contains "$DOC_SOURCE" "raw IP" "F3: has raw IP"
assert_contains "$DOC_SOURCE" "record ID" "F4: has record ID"
assert_contains "$DOC_SOURCE" "zone ID" "F5: has zone ID"
assert_contains "$DOC_SOURCE" "account ID" "F6: has account ID"
assert_contains "$DOC_SOURCE" "Authorization" "F7: has Authorization"
assert_contains "$DOC_SOURCE" "workers.dev" "F8: has workers.dev"
assert_contains "$DOC_SOURCE" "subscription URL" "F9: has subscription URL"
assert_contains "$DOC_SOURCE" "protocol URI" "F10: has protocol URI"
assert_contains "$DOC_SOURCE" "private key" "F11: has private key"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. No dangerous public instructions
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. No dangerous public instructions ---"
echo ""

# The doc should not contain "apply --yes" as a user instruction.
# It may appear in the forbidden-output list (telling users NOT to show it),
# but should not appear as an instruction to the user.
# We check that if it appears, it is in a forbidden/dangerous context.
if echo "$DOC_SOURCE" | grep -q 'apply --yes'; then
  # Check if every occurrence is in a forbidden context
  FORBIDDEN_CONTEXT=$(echo "$DOC_SOURCE" | grep -c 'must not.*apply --yes\|forbidden.*apply --yes\|Do not.*apply --yes\|not.*show.*apply --yes\|`apply --yes`.*forbidden\|`apply --yes`.*must not\|not.*include.*apply --yes\|not.*show.*apply --yes' || true)
  DANGEROUS_CONTEXT=$(echo "$DOC_SOURCE" | grep -c 'run.*apply --yes\|execute.*apply --yes\|use.*apply --yes\|nanobk cf dns apply --yes' || true)
  if [[ "$DANGEROUS_CONTEXT" -gt 0 ]]; then
    fail "G1: doc contains dangerous apply --yes instruction"
    ERRORS=$((ERRORS + 1))
  else
    pass "G1: apply --yes only appears in forbidden context"
  fi
else
  pass "G1: no apply --yes instruction in doc"
fi

# Check for raw nanobk cf dns apply --yes as instruction
assert_not_contains "$DOC_SOURCE" "nanobk cf dns apply --yes" "G2: no nanobk cf dns apply --yes instruction"

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
  "v2.2.17-dns-apply-safe-integration-mock.sh"; do
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
  echo -e "  ${GREEN}All v2.2.18 DNS Apply Post-check Contract tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
