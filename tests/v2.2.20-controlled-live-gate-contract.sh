#!/usr/bin/env bash
# NanoBK Proxy Suite — Controlled Live Gate Contract Test
#
# Validates docs/validation/dns-apply-controlled-live-test-plan-v2.2.20.md
# for required safety gate semantics, owner approval, credential handling,
# pre/post-check requirements, stop conditions, redacted output, and no
# public integration.
#
# Does NOT call Cloudflare. Does NOT call helper. Does NOT perform DNS mutation.
#
# Usage:
#   bash tests/v2.2.20-controlled-live-gate-contract.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/docs/validation/dns-apply-controlled-live-test-plan-v2.2.20.md"

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
echo "=== Controlled Live Gate Contract Test ==="
echo ""

# ── Load doc ─────────────────────────────────────────────────────────────────

if [[ ! -f "$DOC" ]]; then
  fail "DOC: validation doc does not exist"
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

assert_contains "$DOC_SOURCE" "docs/gate-only" "A1: says docs/gate-only"
assert_contains "$DOC_SOURCE" "No real Cloudflare" "A2: says no real Cloudflare"
assert_contains "$DOC_SOURCE" "No DNS mutation" "A3: says no DNS mutation"
assert_contains "$DOC_SOURCE" "No helper invocation" "A4: says no helper invocation"
assert_contains "$DOC_SOURCE" "No public CLI" "A5: says no public CLI"
assert_contains "$DOC_SOURCE" "No Bot" "A5: says no Bot"
assert_contains "$DOC_SOURCE" "No Web" "A5: says no Web"
assert_contains "$DOC_SOURCE" "No installer" "A5: says no installer"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Owner approval gate
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Owner approval gate ---"
echo ""

assert_contains "$DOC_SOURCE" "I UNDERSTAND THIS WILL CHANGE CLOUDFLARE DNS FOR A TEST RECORD" "B1: has exact approval phrase"
assert_contains "$DOC_SOURCE" "safe/redacted test record identity" "B2: has safe/redacted test record identity"
assert_contains "$DOC_SOURCE" "planned action category" "B3: has planned action category"
assert_contains "$DOC_SOURCE" "no-delete policy" "B4: has no-delete policy"
assert_contains "$DOC_SOURCE" "manual rollback instruction" "B5: has manual rollback instruction"
assert_contains "$DOC_SOURCE" "post-check requirement" "B6: has post-check requirement"
assert_contains "$DOC_SOURCE" "redacted output policy" "B7: has redacted output policy"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Minimum scope
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Minimum scope ---"
echo ""

assert_contains "$DOC_SOURCE" "one disposable test record only" "C1: one disposable test record only"
assert_contains "$DOC_SOURCE" "owner-controlled zone" "C2: owner-controlled zone"
assert_contains "$DOC_SOURCE" "single record type first" "C3: single record type first"
assert_contains "$DOC_SOURCE" "create-only first" "C4: create-only first"
assert_contains "$DOC_SOURCE" "no production" "C5: no production"
assert_contains "$DOC_SOURCE" "no delete" "C6: no delete"
assert_contains "$DOC_SOURCE" "no overwrite of unmanaged records" "C7: no overwrite of unmanaged records"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Credential handling
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Credential handling ---"
echo ""

assert_contains "$DOC_SOURCE" "never cat/source/eval real env" "D1: never cat/source/eval real env"
assert_contains "$DOC_SOURCE" "never echo token" "D2: never echo token"
assert_contains "$DOC_SOURCE" "chmod 600" "D3: chmod 600"
assert_contains "$DOC_SOURCE" "raw helper stdout/stderr captured internally" "D4: raw helper captured"
assert_contains "$DOC_SOURCE" "redaction scan before output" "D5: redaction scan before output"
assert_contains "$DOC_SOURCE" "only safe summary printed" "D6: only safe summary printed"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Pre-check and post-check
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Pre-check and post-check ---"
echo ""

assert_contains "$DOC_SOURCE" "test record is absent or managed-test-only" "E1: test record absent or managed"
assert_contains "$DOC_SOURCE" "same-name CNAME conflict is absent" "E2: CNAME conflict absent"
assert_contains "$DOC_SOURCE" "dry-run/preview before live" "E3: dry-run/preview before live"
assert_contains "$DOC_SOURCE" "owner approval after preview" "E4: owner approval after preview"
assert_contains "$DOC_SOURCE" "GET observes record" "E5: GET observes record"
assert_contains "$DOC_SOURCE" "record exists" "E6: record exists"
assert_contains "$DOC_SOURCE" "type matches" "E7: type matches"
assert_contains "$DOC_SOURCE" "content matches internally" "E8: content matches internally"
assert_contains "$DOC_SOURCE" "proxied is false" "E9: proxied is false"
assert_contains "$DOC_SOURCE" "verified only after post-check" "E10: verified only after post-check"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Stop conditions
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Stop conditions ---"
echo ""

assert_contains "$DOC_SOURCE" "repo dirty" "F1: repo dirty"
assert_contains "$DOC_SOURCE" "unexpected HEAD" "F2: unexpected HEAD"
assert_contains "$DOC_SOURCE" "credential file permission not 600" "F3: credential permission not 600"
assert_contains "$DOC_SOURCE" "pre-check sees unmanaged existing record" "F4: pre-check sees unmanaged"
assert_contains "$DOC_SOURCE" "CNAME conflict exists" "F5: CNAME conflict exists"
assert_contains "$DOC_SOURCE" "owner phrase missing" "F6: owner phrase missing"
assert_contains "$DOC_SOURCE" "redaction scan fails" "F7: redaction scan fails"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Forbidden output classes
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Forbidden output classes ---"
echo ""

assert_contains "$DOC_SOURCE" "raw domain" "G1: has raw domain"
assert_contains "$DOC_SOURCE" "raw hostname" "G2: has raw hostname"
assert_contains "$DOC_SOURCE" "raw IP" "G3: has raw IP"
assert_contains "$DOC_SOURCE" "record ID" "G4: has record ID"
assert_contains "$DOC_SOURCE" "zone ID" "G5: has zone ID"
assert_contains "$DOC_SOURCE" "account ID" "G6: has account ID"
assert_contains "$DOC_SOURCE" "Authorization" "G7: has Authorization"
assert_contains "$DOC_SOURCE" "workers.dev" "G8: has workers.dev"
assert_contains "$DOC_SOURCE" "subscription URL" "G9: has subscription URL"
assert_contains "$DOC_SOURCE" "protocol URI" "G10: has protocol URI"
assert_contains "$DOC_SOURCE" "private key" "G11: has private key"
assert_contains "$DOC_SOURCE" "Reality private key" "G12: has Reality private key"
assert_contains "$DOC_SOURCE" "full sha256-like hex hash" "G13: has full hash"
assert_contains "$DOC_SOURCE" "raw mutation command" "G14: has raw mutation command"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Dangerous instruction absence
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Dangerous instruction absence ---"
echo ""

# apply --yes may appear only as a forbidden-output class
if echo "$DOC_SOURCE" | grep -q 'apply --yes'; then
  FORBIDDEN_ONLY=$(echo "$DOC_SOURCE" | grep -c 'must not.*apply --yes\|forbidden.*apply --yes\|Do not.*apply --yes\|not.*show.*apply --yes\|`apply --yes`.*forbidden\|`apply --yes`.*must not\|not.*include.*apply --yes\|forbidden output.*apply --yes\|never.*apply --yes\|raw CLI.*apply --yes\|raw.*apply --yes' || true)
  DANGEROUS=$(echo "$DOC_SOURCE" | grep -c 'run.*apply --yes\|execute.*apply --yes\|nanobk cf dns apply --yes' || true)
  if [[ "$DANGEROUS" -gt 0 ]]; then
    fail "H1: doc contains dangerous apply --yes instruction"
    ERRORS=$((ERRORS + 1))
  else
    pass "H1: apply --yes only in forbidden context"
  fi
else
  pass "H1: no apply --yes in doc"
fi

assert_not_contains "$DOC_SOURCE" "nanobk cf dns apply --yes" "H2: no nanobk cf dns apply --yes"
assert_not_contains "$DOC_SOURCE" "curl " "H3: no curl instruction"
assert_not_contains "$DOC_SOURCE" "wrangler " "H4: no wrangler instruction"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. No public references / no implementation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. No public references / no implementation ---"
echo ""

# I1. Check git diff only has expected files
CHANGED_FILES=$(git -C "$ROOT" diff --name-only 2>/dev/null || true)
UNEXPECTED=$(echo "$CHANGED_FILES" | grep -E '^(lib/|bin/|installer/|bot/|web/|tests/fixtures/|tests/v2.2.8|tests/v2.2.10|tests/v2.2.11|tests/v2.2.15|tests/v2.2.16|tests/v2.2.17|tests/v2.2.18|tests/v2.2.19)' || true)
if [[ -z "$UNEXPECTED" ]]; then
  pass "I1: no forbidden files changed"
else
  fail "I1: forbidden files changed: $UNEXPECTED"
  ERRORS=$((ERRORS + 1))
fi

# I2. No references in lib/bin/installer/bot/web
REFS=$(grep -RIn 'controlled-live-test-plan-v2.2.20\|v2.2.20-controlled-live-gate' "$ROOT/lib" "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web" 2>/dev/null || true)
if [[ -z "$REFS" ]]; then
  pass "I2: no references in lib/bin/installer/bot/web"
else
  fail "I2: references found: $REFS"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Existing tests still pass
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Existing tests still pass ---"
echo ""

for test_file in \
  "v2.2.15-dns-apply-helper-boundary-mock.sh" \
  "v2.2.16-dns-apply-safe-renderer.sh" \
  "v2.2.17-dns-apply-safe-integration-mock.sh" \
  "v2.2.18-dns-apply-postcheck-contract.sh" \
  "v2.2.19-dns-apply-postcheck-classifier-mock.sh"; do
  if bash "$ROOT/tests/$test_file" > /dev/null 2>&1; then
    pass "J: $test_file passes"
  else
    fail "J: $test_file fails"
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
  echo -e "  ${GREEN}All v2.2.20 Controlled Live Gate Contract tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
