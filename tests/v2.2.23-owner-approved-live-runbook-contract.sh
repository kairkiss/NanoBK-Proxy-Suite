#!/usr/bin/env bash
# NanoBK Proxy Suite — Owner-Approved Live Runbook Contract Test
#
# Validates docs/validation/dns-apply-owner-approved-one-record-live-runbook-v2.2.23.md
# for required sections, placeholders, approval timing, credential handling,
# identity policy, pre-check, post-check, rollback, stop conditions,
# redacted output, and no public integration.
#
# Does NOT call Cloudflare. Does NOT call helper. Does NOT read real env.
#
# Usage:
#   bash tests/v2.2.23-owner-approved-live-runbook-contract.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/docs/validation/dns-apply-owner-approved-one-record-live-runbook-v2.2.23.md"

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
echo "=== Owner-Approved Live Runbook Contract Test ==="
echo ""

# ── Load doc ─────────────────────────────────────────────────────────────────

if [[ ! -f "$DOC" ]]; then
  fail "DOC: runbook does not exist"
  ERRORS=$((ERRORS + 1))
  echo ""
  echo "=== Test Summary ==="
  echo ""
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi

DOC_SOURCE=$(cat "$DOC")

# ══════════════════════════════════════════════════════════════════════════════
# A. File/scope checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. File/scope checks ---"
echo ""

assert_contains "$DOC_SOURCE" "docs-only" "A1: says docs-only"
assert_contains "$DOC_SOURCE" "does not execute Cloudflare" "A2: no Cloudflare calls"
assert_contains "$DOC_SOURCE" "does not mutate DNS" "A3: no DNS mutation"
assert_contains "$DOC_SOURCE" "does not read real env" "A4: no real env files"
assert_contains "$DOC_SOURCE" "does not enable public CLI" "A5: no public CLI"
assert_contains "$DOC_SOURCE" "No Bot" "A5: no Bot"
assert_contains "$DOC_SOURCE" "No Web" "A5: no Web"
assert_contains "$DOC_SOURCE" "No installer" "A5: no installer"
assert_contains "$DOC_SOURCE" "Actual live mutation remains blocked" "A6: live mutation blocked"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Required sections
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Required sections ---"
echo ""

assert_contains "$DOC_SOURCE" "Scope and non-goals" "B1: Scope and non-goals"
assert_contains "$DOC_SOURCE" "Required human-provided placeholders" "B2: Required placeholders"
assert_contains "$DOC_SOURCE" "Owner approval phrase" "B3: Owner approval phrase"
assert_contains "$DOC_SOURCE" "Credential handling" "B4: Credential handling"
assert_contains "$DOC_SOURCE" "Repo state gate" "B5: Repo state gate"
assert_contains "$DOC_SOURCE" "Test record identity policy" "B6: Test record identity"
assert_contains "$DOC_SOURCE" "Pre-check steps" "B7: Pre-check steps"
assert_contains "$DOC_SOURCE" "Preview steps" "B8: Preview steps"
assert_contains "$DOC_SOURCE" "Mutation execution rules" "B9: Mutation execution rules"
assert_contains "$DOC_SOURCE" "Post-check steps" "B10: Post-check steps"
assert_contains "$DOC_SOURCE" "Success criteria" "B11: Success criteria"
assert_contains "$DOC_SOURCE" "Failure / uncertain criteria" "B12: Failure criteria"
assert_contains "$DOC_SOURCE" "Manual rollback / recovery" "B13: Manual rollback"
assert_contains "$DOC_SOURCE" "Stop conditions" "B14: Stop conditions"
assert_contains "$DOC_SOURCE" "Redacted output contract" "B15: Redacted output contract"
assert_contains "$DOC_SOURCE" "What not to do" "B16: What not to do"
assert_contains "$DOC_SOURCE" "Public UX block" "B17: Public UX block"
assert_contains "$DOC_SOURCE" "Future phase labels" "B18: Future phase labels"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Placeholders
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Placeholders ---"
echo ""

assert_contains "$DOC_SOURCE" "SAFE_ZONE_CATEGORY" "C1: SAFE_ZONE_CATEGORY"
assert_contains "$DOC_SOURCE" "SAFE_TEST_RECORD_CATEGORY" "C2: SAFE_TEST_RECORD_CATEGORY"
assert_contains "$DOC_SOURCE" "SAFE_RECORD_TYPE" "C3: SAFE_RECORD_TYPE"
assert_contains "$DOC_SOURCE" "SAFE_EXPECTED_CONTENT_CATEGORY" "C4: SAFE_EXPECTED_CONTENT_CATEGORY"
assert_contains "$DOC_SOURCE" "SAFE_CREDENTIAL_FILE_REFERENCE" "C5: SAFE_CREDENTIAL_FILE_REFERENCE"
assert_contains "$DOC_SOURCE" "OWNER_APPROVAL_PHRASE" "C6: OWNER_APPROVAL_PHRASE"
assert_contains "$DOC_SOURCE" "placeholders only" "C7: says placeholders only"
assert_contains "$DOC_SOURCE" "never be printed" "C8: real values never printed"
assert_contains "$DOC_SOURCE" "never be pasted to AI" "C9: never pasted to AI"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Approval phrase
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Approval phrase ---"
echo ""

assert_contains "$DOC_SOURCE" "I UNDERSTAND THIS WILL CHANGE CLOUDFLARE DNS FOR A TEST RECORD" "D1: exact approval phrase"
assert_contains "$DOC_SOURCE" "after safe preview" "D2: after safe preview"
assert_contains "$DOC_SOURCE" "after rollback instructions" "D3: after rollback instructions"
assert_contains "$DOC_SOURCE" "after post-check explanation" "D4: after post-check explanation"
assert_contains "$DOC_SOURCE" "before any mutation" "D5: before any mutation"
assert_contains "$DOC_SOURCE" "must not show a raw mutation command" "D6: no raw mutation command"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Credential handling
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Credential handling ---"
echo ""

assert_contains "$DOC_SOURCE" "chmod 600" "E1: chmod 600"
assert_contains "$DOC_SOURCE" "Never" "E2: Never cat/source/eval"
assert_contains "$DOC_SOURCE" "cat/source/eval" "E2: cat/source/eval mentioned"
assert_contains "$DOC_SOURCE" "Never echo token" "E3: Never echo token"
assert_contains "$DOC_SOURCE" "never printed" "E4: never printed"
assert_contains "$DOC_SOURCE" "No secret persistence" "E5: No secret persistence"
assert_contains "$DOC_SOURCE" "captured internally" "E6: captured internally"
assert_contains "$DOC_SOURCE" "Redaction scan" "E7: Redaction scan"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Identity / pre-check
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Identity / pre-check ---"
echo ""

assert_contains "$DOC_SOURCE" "one record only" "F1: one record only"
assert_contains "$DOC_SOURCE" "disposable test record only" "F2: disposable test record"
assert_contains "$DOC_SOURCE" "owner-controlled zone" "F3: owner-controlled zone"
assert_contains "$DOC_SOURCE" "create-only first" "F4: create-only first"
assert_contains "$DOC_SOURCE" "DNS-only only" "F5: DNS-only only"
assert_contains "$DOC_SOURCE" "no delete" "F6: no delete"
assert_contains "$DOC_SOURCE" "no overwrite" "F7: no overwrite"
assert_contains "$DOC_SOURCE" "no production" "F8: no production"
assert_contains "$DOC_SOURCE" "no subscription/proxy/web/Bot/Worker hostnames" "F9: no service hostnames"
assert_contains "$DOC_SOURCE" "absent or managed-test-only" "F10: absent or managed"
assert_contains "$DOC_SOURCE" "same-name CNAME absent" "F11: CNAME absent"
assert_contains "$DOC_SOURCE" "safe preview generated before approval" "F12: preview before approval"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Post-check and success
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Post-check and success ---"
echo ""

assert_contains "$DOC_SOURCE" "API accepted mutation" "G1: API accepted"
assert_contains "$DOC_SOURCE" "GET observes record" "G2: GET observes"
assert_contains "$DOC_SOURCE" "record exists" "G3: record exists"
assert_contains "$DOC_SOURCE" "type matches" "G4: type matches"
assert_contains "$DOC_SOURCE" "content matches internally" "G5: content matches"
assert_contains "$DOC_SOURCE" "proxied is false" "G6: proxied false"
assert_contains "$DOC_SOURCE" "expected safe subset count matches" "G7: count matches"
assert_contains "$DOC_SOURCE" "no unexpected delete" "G8: no unexpected delete"
assert_contains "$DOC_SOURCE" "verified only after post-check" "G9: verified after post-check"
assert_contains "$DOC_SOURCE" "must not be called success" "G10: failure not called success"
assert_contains "$DOC_SOURCE" "No fake success" "G11: No fake success"
assert_contains "$DOC_SOURCE" "No success without post-check verification" "G12: no success without postcheck"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Rollback / recovery
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Rollback / recovery ---"
echo ""

assert_contains "$DOC_SOURCE" "does not auto-delete" "H1: no auto-delete"
assert_contains "$DOC_SOURCE" "manual rollback instruction exists before mutation" "H2: rollback before mutation"
assert_contains "$DOC_SOURCE" "owner manually removes" "H3: owner manually removes"
assert_contains "$DOC_SOURCE" "rollback cannot be verified" "H4: rollback unverified"
assert_contains "$DOC_SOURCE" "uncertain or manual_pending" "H5: uncertain or manual_pending"
assert_contains "$DOC_SOURCE" "No blind retry" "H6: No blind retry"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Stop conditions
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Stop conditions ---"
echo ""

assert_contains "$DOC_SOURCE" "dirty repo" "I1: dirty repo"
assert_contains "$DOC_SOURCE" "unexpected HEAD" "I2: unexpected HEAD"
assert_contains "$DOC_SOURCE" "credential file permission not 600" "I3: credential permission"
assert_contains "$DOC_SOURCE" "placeholder missing" "I4: placeholder missing"
assert_contains "$DOC_SOURCE" "production category detected" "I5: production detected"
assert_contains "$DOC_SOURCE" "unmanaged existing record" "I6: unmanaged record"
assert_contains "$DOC_SOURCE" "CNAME conflict" "I7: CNAME conflict"
assert_contains "$DOC_SOURCE" "owner phrase missing" "I8: owner phrase missing"
assert_contains "$DOC_SOURCE" "redaction scan failure" "I9: redaction failure"
assert_contains "$DOC_SOURCE" "rollback instruction missing" "I10: rollback missing"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Redacted output contract
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Redacted output contract ---"
echo ""

assert_contains "$DOC_SOURCE" "raw domain" "J1: raw domain"
assert_contains "$DOC_SOURCE" "raw hostname" "J2: raw hostname"
assert_contains "$DOC_SOURCE" "raw IP" "J3: raw IP"
assert_contains "$DOC_SOURCE" "record ID" "J4: record ID"
assert_contains "$DOC_SOURCE" "zone ID" "J5: zone ID"
assert_contains "$DOC_SOURCE" "account ID" "J6: account ID"
assert_contains "$DOC_SOURCE" "Authorization" "J7: Authorization"
assert_contains "$DOC_SOURCE" "env path" "J8: env path"
assert_contains "$DOC_SOURCE" "API response body" "J9: API response body"
assert_contains "$DOC_SOURCE" "API endpoint" "J10: API endpoint"
assert_contains "$DOC_SOURCE" "workers.dev" "J11: workers.dev"
assert_contains "$DOC_SOURCE" "subscription URL" "J12: subscription URL"
assert_contains "$DOC_SOURCE" "protocol URI" "J13: protocol URI"
assert_contains "$DOC_SOURCE" "private key" "J14: private key"
assert_contains "$DOC_SOURCE" "Reality private key" "J15: Reality private key"
assert_contains "$DOC_SOURCE" "full sha256-like hex hash" "J16: full hash"
assert_contains "$DOC_SOURCE" "raw mutation command" "J17: raw mutation command"
assert_contains "$DOC_SOURCE" "raw helper stdout/stderr" "J18: raw helper output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Dangerous command absence
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. Dangerous command absence ---"
echo ""

if echo "$DOC_SOURCE" | grep -q 'apply --yes'; then
  FORBIDDEN_ONLY=$(echo "$DOC_SOURCE" | grep -c 'forbidden.*apply --yes\|must not.*apply --yes\|never.*apply --yes\|not.*show.*apply --yes\|forbidden output.*apply --yes\|raw CLI.*apply --yes' || true)
  DANGEROUS=$(echo "$DOC_SOURCE" | grep -c 'run.*apply --yes\|execute.*apply --yes\|nanobk cf dns apply --yes' || true)
  if [[ "$DANGEROUS" -gt 0 ]]; then
    fail "K1: doc contains dangerous apply --yes instruction"
    ERRORS=$((ERRORS + 1))
  else
    pass "K1: apply --yes only in forbidden context"
  fi
else
  pass "K1: no apply --yes in doc"
fi

assert_not_contains "$DOC_SOURCE" "nanobk cf dns apply --yes" "K2: no nanobk cf dns apply --yes"
assert_not_contains "$DOC_SOURCE" "curl " "K3: no curl instruction"
assert_not_contains "$DOC_SOURCE" "wrangler " "K4: no wrangler instruction"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. No implementation / no public references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. No implementation / no public references ---"
echo ""

# L1. Check git diff only has expected files
CHANGED_FILES=$(git -C "$ROOT" diff --name-only 2>/dev/null || true)
UNEXPECTED=$(echo "$CHANGED_FILES" | grep -E '^(lib/|bin/|installer/|bot/|web/|tests/fixtures/|tests/v2.2.8|tests/v2.2.10|tests/v2.2.11|tests/v2.2.15|tests/v2.2.16|tests/v2.2.17|tests/v2.2.18|tests/v2.2.19|tests/v2.2.20|tests/v2.2.21|tests/v2.2.22)' || true)
if [[ -z "$UNEXPECTED" ]]; then
  pass "L1: no forbidden files changed"
else
  fail "L1: forbidden files changed: $UNEXPECTED"
  ERRORS=$((ERRORS + 1))
fi

# L2. No references in lib/bin/installer/bot/web/tests/fixtures
REFS=$(grep -RIn 'dns-apply-owner-approved-one-record-live-runbook-v2.2.23\|v2.2.23-owner-approved-live-runbook' "$ROOT/lib" "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web" "$ROOT/tests/fixtures" 2>/dev/null || true)
if [[ -z "$REFS" ]]; then
  pass "L2: no references in lib/bin/installer/bot/web/tests/fixtures"
else
  fail "L2: references found: $REFS"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# M. Existing safe tests still pass
# ══════════════════════════════════════════════════════════════════════════════

echo "--- M. Existing safe tests still pass ---"
echo ""

for test_file in \
  "v2.2.15-dns-apply-helper-boundary-mock.sh" \
  "v2.2.16-dns-apply-safe-renderer.sh" \
  "v2.2.17-dns-apply-safe-integration-mock.sh" \
  "v2.2.18-dns-apply-postcheck-contract.sh" \
  "v2.2.19-dns-apply-postcheck-classifier-mock.sh" \
  "v2.2.20-controlled-live-gate-contract.sh" \
  "v2.2.21-controlled-live-gate-placeholder-mock.sh" \
  "v2.2.22-controlled-live-wrapper-mock.sh"; do
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
  echo -e "  ${GREEN}All v2.2.23 Owner-Approved Live Runbook Contract tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
