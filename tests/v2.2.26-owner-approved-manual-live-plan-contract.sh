#!/usr/bin/env bash
# NanoBK Proxy Suite — Owner-Approved Manual Live Plan Contract Test
#
# Validates docs/validation/dns-apply-owner-approved-manual-one-record-live-test-plan-v2.2.26.md
# for required sections, placeholders, approval timing, three-layer separation,
# credential handling, one-record policy, pre-check, preview, post-check,
# redacted evidence, rollback, stop conditions, success/failure criteria,
# public UX block, and forbidden raw value patterns.
#
# Does NOT call Cloudflare. Does NOT call helper. Does NOT read real env.
#
# Usage:
#   bash tests/v2.2.26-owner-approved-manual-live-plan-contract.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/docs/validation/dns-apply-owner-approved-manual-one-record-live-test-plan-v2.2.26.md"

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
echo "=== Owner-Approved Manual Live Plan Contract Test ==="
echo ""

# ── Load doc ─────────────────────────────────────────────────────────────────

if [[ ! -f "$DOC" ]]; then
  fail "DOC: plan document does not exist"
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
assert_contains "$DOC_SOURCE" "does not permit live mutation" "A2: does not permit live mutation"
assert_contains "$DOC_SOURCE" "does not implement a live wrapper" "A3: does not implement live wrapper"
assert_contains "$DOC_SOURCE" "does not call Cloudflare" "A4: does not call Cloudflare"
assert_contains "$DOC_SOURCE" "does not read real env" "A5: does not read real env"
assert_contains "$DOC_SOURCE" "does not expose public CLI" "A6: does not expose public CLI"
assert_contains "$DOC_SOURCE" "Actual live mutation remains blocked" "A7: live mutation remains blocked"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Required sections
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Required sections ---"
echo ""

assert_contains "$DOC_SOURCE" "## 1. Scope and non-goals" "B1: Scope and non-goals"
assert_contains "$DOC_SOURCE" "## 2. Absolute safety boundaries" "B2: Absolute safety boundaries"
assert_contains "$DOC_SOURCE" "## 3. Required owner-only placeholders" "B3: Required placeholders"
assert_contains "$DOC_SOURCE" "## 4. Three-layer separation model" "B4: Three-layer separation"
assert_contains "$DOC_SOURCE" "## 5. Owner-only local preparation" "B5: Owner-only local preparation"
assert_contains "$DOC_SOURCE" "## 6. Credential file handling" "B6: Credential file handling"
assert_contains "$DOC_SOURCE" "## 7. One-record identity policy" "B7: One-record identity policy"
assert_contains "$DOC_SOURCE" "## 8. Pre-check checklist" "B8: Pre-check checklist"
assert_contains "$DOC_SOURCE" "## 9. Safe preview checklist" "B9: Safe preview checklist"
assert_contains "$DOC_SOURCE" "## 10. Owner approval phrase" "B10: Owner approval phrase"
assert_contains "$DOC_SOURCE" "## 11. Manual execution boundary" "B11: Manual execution boundary"
assert_contains "$DOC_SOURCE" "## 12. Post-check checklist" "B12: Post-check checklist"
assert_contains "$DOC_SOURCE" "## 13. Redacted evidence checklist" "B13: Redacted evidence"
assert_contains "$DOC_SOURCE" "## 14. Manual rollback checklist" "B14: Manual rollback"
assert_contains "$DOC_SOURCE" "## 15. Stop conditions" "B15: Stop conditions"
assert_contains "$DOC_SOURCE" "## 16. Success criteria" "B16: Success criteria"
assert_contains "$DOC_SOURCE" "## 17. Failure and uncertain criteria" "B17: Failure criteria"
assert_contains "$DOC_SOURCE" "## 18. What must never be pasted" "B18: Never pasted"
assert_contains "$DOC_SOURCE" "## 19. Public UX block" "B19: Public UX block"
assert_contains "$DOC_SOURCE" "## 20. Not allowed by this version" "B20: Not allowed"
assert_contains "$DOC_SOURCE" "## 21. Future transition criteria" "B21: Future transition"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Required placeholders/categories
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Required placeholders/categories ---"
echo ""

assert_contains "$DOC_SOURCE" "SAFE_ZONE_CATEGORY" "C1: SAFE_ZONE_CATEGORY"
assert_contains "$DOC_SOURCE" "SAFE_TEST_RECORD_CATEGORY" "C2: SAFE_TEST_RECORD_CATEGORY"
assert_contains "$DOC_SOURCE" "SAFE_RECORD_TYPE" "C3: SAFE_RECORD_TYPE"
assert_contains "$DOC_SOURCE" "SAFE_EXPECTED_CONTENT_CATEGORY" "C4: SAFE_EXPECTED_CONTENT_CATEGORY"
assert_contains "$DOC_SOURCE" "SAFE_CREDENTIAL_FILE_REFERENCE" "C5: SAFE_CREDENTIAL_FILE_REFERENCE"
assert_contains "$DOC_SOURCE" "SAFE_LOCAL_RUN_CONTEXT" "C6: SAFE_LOCAL_RUN_CONTEXT"
assert_contains "$DOC_SOURCE" "SAFE_ROLLBACK_CATEGORY" "C7: SAFE_ROLLBACK_CATEGORY"
assert_contains "$DOC_SOURCE" "OWNER_APPROVAL_PHRASE" "C8: OWNER_APPROVAL_PHRASE"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Owner approval phrase and timing
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Owner approval phrase and timing ---"
echo ""

assert_contains "$DOC_SOURCE" "I UNDERSTAND THIS WILL CHANGE CLOUDFLARE DNS FOR A TEST RECORD" "D1: exact approval phrase"
assert_contains "$DOC_SOURCE" "owner-only local preparation is complete" "D2: after local preparation"
assert_contains "$DOC_SOURCE" "credential handling is verified locally" "D3: after credential verification"
assert_contains "$DOC_SOURCE" "one-record identity policy passes" "D4: after identity policy"
assert_contains "$DOC_SOURCE" "pre-check passes" "D5: after pre-check"
assert_contains "$DOC_SOURCE" "safe preview is available" "D6: after preview"
assert_contains "$DOC_SOURCE" "rollback instructions are available" "D7: after rollback instructions"
assert_contains "$DOC_SOURCE" "post-check criteria are understood" "D8: after post-check understanding"
assert_contains "$DOC_SOURCE" "before any future mutation" "D9: before mutation"
assert_contains "$DOC_SOURCE" "must not be requested by public CLI" "D10: not requested by public"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Three-layer separation
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Three-layer separation ---"
echo ""

assert_contains "$DOC_SOURCE" "Human owner local preparation" "E1: human owner layer"
assert_contains "$DOC_SOURCE" "Future non-public controlled command execution" "E2: future command layer"
assert_contains "$DOC_SOURCE" "AI review layer" "E3: AI review layer"
assert_contains "$DOC_SOURCE" "owner keeps real values local" "E4: owner keeps real values local"
assert_contains "$DOC_SOURCE" "AI receives only safe categories" "E5: AI receives only safe categories"
assert_contains "$DOC_SOURCE" "AI never receives real token" "E6: AI never receives real token"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Credential handling
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Credential handling ---"
echo ""

assert_contains "$DOC_SOURCE" "Credential file contents must never be pasted" "F1: contents never pasted"
assert_contains "$DOC_SOURCE" "path must not be printed" "F2: path not printed"
assert_contains "$DOC_SOURCE" "chmod 600" "F3: chmod 600"
assert_contains "$DOC_SOURCE" "No" "F4: No cat/source/eval"
assert_contains "$DOC_SOURCE" "cat" "F4b: cat mentioned"
assert_contains "$DOC_SOURCE" "source" "F4c: source mentioned"
assert_contains "$DOC_SOURCE" "eval" "F4d: eval mentioned"
assert_contains "$DOC_SOURCE" "No token echo" "F5: No token echo"
assert_contains "$DOC_SOURCE" "captured internally" "F6: captured internally"
assert_contains "$DOC_SOURCE" "Redaction must happen before output" "F7: redaction before output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. One-record identity policy
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. One-record identity policy ---"
echo ""

assert_contains "$DOC_SOURCE" "Exactly one record" "G1: exactly one record"
assert_contains "$DOC_SOURCE" "Disposable test record" "G2: disposable test record"
assert_contains "$DOC_SOURCE" "Owner-controlled" "G3: owner-controlled"
assert_contains "$DOC_SOURCE" "Create-only-first" "G4: create-only-first"
assert_contains "$DOC_SOURCE" "DNS-only" "G5: DNS-only"
assert_contains "$DOC_SOURCE" "proxied false" "G5b: proxied false"
assert_contains "$DOC_SOURCE" "No delete" "G6: no delete"
assert_contains "$DOC_SOURCE" "No overwrite" "G7: no overwrite"
assert_contains "$DOC_SOURCE" "No production names" "G8: no production names"
assert_contains "$DOC_SOURCE" "No service hostnames" "G9: no service hostnames"
assert_contains "$DOC_SOURCE" "Same-name CNAME must be absent" "G10: CNAME absent"
assert_contains "$DOC_SOURCE" "unmanaged record means stop" "G11: unmanaged means stop"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Pre-check and preview
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Pre-check and preview ---"
echo ""

assert_contains "$DOC_SOURCE" "repo clean" "H1: repo clean"
assert_contains "$DOC_SOURCE" "expected HEAD" "H2: expected HEAD"
assert_contains "$DOC_SOURCE" "public integration absent" "H3: public integration absent"
assert_contains "$DOC_SOURCE" "credential reference present" "H4: credential reference present"
assert_contains "$DOC_SOURCE" "credential permission restricted" "H5: credential permission restricted"
assert_contains "$DOC_SOURCE" "same-name CNAME absent" "H6: CNAME absent"
assert_contains "$DOC_SOURCE" "record absent or managed-test-only" "H7: record absent or managed"
assert_contains "$DOC_SOURCE" "safe summary only" "H8: safe summary only"
assert_contains "$DOC_SOURCE" "no raw mutation command" "H9: no raw mutation command"
assert_contains "$DOC_SOURCE" "rollback instructions shown before approval" "H10: rollback before approval"
assert_contains "$DOC_SOURCE" "post-check criteria shown before approval" "H11: postcheck before approval"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Post-check and redacted evidence
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Post-check and redacted evidence ---"
echo ""

assert_contains "$DOC_SOURCE" "post-check GET observes" "I1: GET observes"
assert_contains "$DOC_SOURCE" "record exists" "I2: record exists"
assert_contains "$DOC_SOURCE" "record type matches" "I3: type matches"
assert_contains "$DOC_SOURCE" "content matches internally" "I4: content matches"
assert_contains "$DOC_SOURCE" "proxied false" "I5: proxied false"
assert_contains "$DOC_SOURCE" "expected count matches" "I6: count matches"
assert_contains "$DOC_SOURCE" "no unexpected delete" "I7: no unexpected delete"
assert_contains "$DOC_SOURCE" "verified only after post-check" "I8: verified after postcheck"
assert_contains "$DOC_SOURCE" "repo_gate_passed" "I9: repo_gate_passed evidence"
assert_contains "$DOC_SOURCE" "credential_gate_passed" "I10: credential_gate_passed"
assert_contains "$DOC_SOURCE" "precheck_passed" "I11: precheck_passed"
assert_contains "$DOC_SOURCE" "owner_approval_phrase_matched" "I12: approval matched"
assert_contains "$DOC_SOURCE" "postcheck_observed" "I13: postcheck observed"
assert_contains "$DOC_SOURCE" "No raw values" "I14: no raw values"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. Rollback and stop conditions
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. Rollback and stop conditions ---"
echo ""

assert_contains "$DOC_SOURCE" "manual dashboard rollback" "J1: manual dashboard rollback"
assert_contains "$DOC_SOURCE" "owner must perform rollback locally" "J2: owner performs rollback"
assert_contains "$DOC_SOURCE" "No automatic delete" "J3: no automatic delete"
assert_contains "$DOC_SOURCE" "Rollback unverified" "J4: rollback unverified"
assert_contains "$DOC_SOURCE" "Blind retry forbidden" "J5: blind retry forbidden"
assert_contains "$DOC_SOURCE" "repo dirty" "J6: repo dirty stop"
assert_contains "$DOC_SOURCE" "unexpected HEAD" "J7: unexpected HEAD stop"
assert_contains "$DOC_SOURCE" "public integration detected" "J8: public integration stop"
assert_contains "$DOC_SOURCE" "credential permission not restricted" "J9: credential permission stop"
assert_contains "$DOC_SOURCE" "credential value printed" "J10: credential value printed stop"
assert_contains "$DOC_SOURCE" "production zone" "J11: production zone stop"
assert_contains "$DOC_SOURCE" "same-name CNAME exists" "J12: CNAME exists stop"
assert_contains "$DOC_SOURCE" "unmanaged existing record" "J13: unmanaged record stop"
assert_contains "$DOC_SOURCE" "planned action includes delete" "J14: delete stop"
assert_contains "$DOC_SOURCE" "approval phrase missing" "J15: approval missing stop"
assert_contains "$DOC_SOURCE" "approval phrase mistimed" "J16: approval mistimed stop"
assert_contains "$DOC_SOURCE" "raw command displayed" "J17: raw command stop"
assert_contains "$DOC_SOURCE" "post-check unavailable" "J18: postcheck unavailable stop"
assert_contains "$DOC_SOURCE" "redaction failure" "J19: redaction failure stop"
assert_contains "$DOC_SOURCE" "uncertain state" "J20: uncertain state stop"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Success/failure/uncertain criteria
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. Success/failure/uncertain criteria ---"
echo ""

assert_contains "$DOC_SOURCE" "v2.2.26 itself cannot claim verified" "K1: v2.2.26 cannot claim verified"
assert_contains "$DOC_SOURCE" "approval_missing" "K2: approval_missing status"
assert_contains "$DOC_SOURCE" "approval_mistimed" "K3: approval_mistimed status"
assert_contains "$DOC_SOURCE" "precheck_failed" "K4: precheck_failed status"
assert_contains "$DOC_SOURCE" "preview_failed" "K5: preview_failed status"
assert_contains "$DOC_SOURCE" "mutation_failed" "K6: mutation_failed status"
assert_contains "$DOC_SOURCE" "postcheck_failed" "K7: postcheck_failed status"
assert_contains "$DOC_SOURCE" "redaction_failed" "K8: redaction_failed status"
assert_contains "$DOC_SOURCE" "rollback_unverified" "K9: rollback_unverified status"
assert_contains "$DOC_SOURCE" "manual_pending" "K10: manual_pending status"
assert_contains "$DOC_SOURCE" "uncertain" "K11: uncertain status"
assert_contains "$DOC_SOURCE" "No fake success" "K12: no fake success"
assert_contains "$DOC_SOURCE" "No partial success is reported as verified" "K13: no partial as verified"
assert_contains "$DOC_SOURCE" "No mutation-only result is reported as verified" "K14: no mutation-only as verified"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. Public UX block
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. Public UX block ---"
echo ""

assert_contains "$DOC_SOURCE" "Public CLI integration: blocked" "L1: CLI blocked"
assert_contains "$DOC_SOURCE" "Bot apply: blocked" "L2: Bot blocked"
assert_contains "$DOC_SOURCE" "Web apply: blocked" "L3: Web blocked"
assert_contains "$DOC_SOURCE" "Installer apply: blocked" "L4: Installer blocked"
assert_contains "$DOC_SOURCE" "Tag/release: blocked" "L5: Tag/release blocked"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# M. Forbidden raw value checks
# ══════════════════════════════════════════════════════════════════════════════

echo "--- M. Forbidden raw value checks ---"
echo ""

assert_not_contains "$DOC_SOURCE" "example.com" "M1: no example.com"
assert_not_contains "$DOC_SOURCE" "203.0.113" "M2: no IPv4"
assert_not_contains "$DOC_SOURCE" "2001:db8" "M3: no IPv6"
assert_not_contains "$DOC_SOURCE" "recordId" "M4: no recordId"
assert_not_contains "$DOC_SOURCE" "Zone ID" "M5: no Zone ID"
assert_not_contains "$DOC_SOURCE" "Account ID" "M6: no Account ID"
assert_not_contains "$DOC_SOURCE" "CF_API_TOKEN" "M7: no CF_API_TOKEN"
# These patterns may appear in the "never paste" section as category names.
# Check they don't appear as realistic raw examples outside that context.
# The "never paste" section (section 18) legitimately lists these categories.
NEVER_PASTE_SECTION=$(sed -n '/## 18\. What must never be pasted/,/## 19\./p' "$DOC")
REST_OF_DOC=$(sed '/## 18\. What must never be pasted/,/## 19\./d' "$DOC")

# Authorization, workers.dev, subscription URL, protocol URIs, private key,
# Reality private key, apply --yes may appear in section 18 as category names
# but must not appear as realistic raw examples elsewhere.
assert_not_contains "$REST_OF_DOC" "Authorization" "M8: no Authorization outside never-paste section"
assert_not_contains "$REST_OF_DOC" "workers.dev" "M9: no workers.dev outside never-paste section"
assert_not_contains "$REST_OF_DOC" "subscription URL" "M10: no subscription URL outside never-paste section"
assert_not_contains "$REST_OF_DOC" "vless://" "M11: no vless:// outside never-paste section"
assert_not_contains "$REST_OF_DOC" "trojan://" "M12: no trojan:// outside never-paste section"
assert_not_contains "$REST_OF_DOC" "hysteria2://" "M13: no hysteria2:// outside never-paste section"
assert_not_contains "$REST_OF_DOC" "tuic://" "M14: no tuic:// outside never-paste section"
assert_not_contains "$REST_OF_DOC" "PRIVATE KEY" "M15: no PRIVATE KEY outside never-paste section"
assert_not_contains "$REST_OF_DOC" "Reality private key" "M16: no Reality private key outside never-paste section"
assert_not_contains "$REST_OF_DOC" "apply --yes" "M17: no apply --yes outside never-paste section"
assert_not_contains "$DOC_SOURCE" "/zones/" "M18: no /zones/"
assert_not_contains "$DOC_SOURCE" "dns_records" "M19: no dns_records"

if echo "$DOC_SOURCE" | grep -qE '[a-f0-9]{64}'; then
  fail "M20: no 64-char hex"
  ERRORS=$((ERRORS + 1))
else
  pass "M20: no 64-char hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# N. No implementation/public integration references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- N. No implementation/public integration references ---"
echo ""

CHANGED_FILES=$(git -C "$ROOT" diff --name-only 2>/dev/null || true)
UNEXPECTED=$(echo "$CHANGED_FILES" | grep -E '^(lib/|bin/|installer/|bot/|web/|tests/fixtures/|tests/v2.2.15|tests/v2.2.16|tests/v2.2.17|tests/v2.2.18|tests/v2.2.19|tests/v2.2.20|tests/v2.2.21|tests/v2.2.22|tests/v2.2.23|tests/v2.2.24|tests/v2.2.25)' || true)
if [[ -z "$UNEXPECTED" ]]; then
  pass "N1: no forbidden files changed"
else
  fail "N1: forbidden files changed: $UNEXPECTED"
  ERRORS=$((ERRORS + 1))
fi

REFS=$(grep -RIn 'dns-apply-owner-approved-manual-one-record-live-test-plan-v2.2.26\|v2.2.26-owner-approved-manual-live-plan' "$ROOT/lib" "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web" 2>/dev/null || true)
if [[ -z "$REFS" ]]; then
  pass "N2: no references in lib/bin/installer/bot/web"
else
  fail "N2: references found: $REFS"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# O. Existing safe docs/tests awareness
# ══════════════════════════════════════════════════════════════════════════════

echo "--- O. Existing safe docs/tests awareness ---"
echo ""

for test_file in \
  "v2.2.23-owner-approved-live-runbook-contract.sh" \
  "v2.2.24-one-record-live-runbook-validator-mock.sh"; do
  if bash "$ROOT/tests/$test_file" > /dev/null 2>&1; then
    pass "O: $test_file passes"
  else
    fail "O: $test_file fails"
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
  echo -e "  ${GREEN}All v2.2.26 Owner-Approved Manual Live Plan Contract tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
