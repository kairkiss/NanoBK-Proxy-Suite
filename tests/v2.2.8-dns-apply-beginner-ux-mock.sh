#!/usr/bin/env bash
# NanoBK Proxy Suite — DNS Apply Beginner UX Mock and Redaction Static Test
#
# Inspects v2.2.8 mock fixture files for beginner copy safety,
# confirmation wording, redaction, post-check states, and mutation boundary.
# Does NOT call nanobk cf dns apply --yes. Does NOT call Cloudflare.
#
# Usage:
#   bash tests/v2.2.8-dns-apply-beginner-ux-mock.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/tests/fixtures/v2.2.8"

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

# ── Load fixtures ───────────────────────────────────────────────────────────

SUMMARY=$(cat "$FIXTURES/dns-apply-beginner-summary.txt")
ADVANCED=$(cat "$FIXTURES/dns-apply-advanced-details.txt")
CONFIRM=$(cat "$FIXTURES/dns-apply-confirmation.txt")
SUCCESS=$(cat "$FIXTURES/dns-apply-postcheck-success.txt")
FAILURE=$(cat "$FIXTURES/dns-apply-postcheck-failure.txt")
PARTIAL=$(cat "$FIXTURES/dns-apply-partial-failure.txt")
ALL="$SUMMARY
$ADVANCED
$CONFIRM
$SUCCESS
$FAILURE
$PARTIAL"

echo ""
echo "=== DNS Apply Beginner UX Mock and Redaction Static Test ==="
echo ""

# ── 1. All fixture files exist ──────────────────────────────────────────────

echo "--- 1. Fixture files exist ---"
echo ""

for f in dns-apply-beginner-summary.txt dns-apply-advanced-details.txt \
         dns-apply-confirmation.txt dns-apply-postcheck-success.txt \
         dns-apply-postcheck-failure.txt dns-apply-partial-failure.txt; do
  if [[ -f "$FIXTURES/$f" ]]; then
    pass "fixture exists: $f"
  else
    fail "fixture missing: $f"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ── 2. Beginner Summary masked values ───────────────────────────────────────

echo "--- 2. Beginner Summary masked values ---"
echo ""

assert_contains "$SUMMARY" "ex***e.com" "summary has masked domain"
assert_contains "$SUMMARY" "pr***y.ex***e.com" "summary has masked hostname"
assert_contains "$SUMMARY" "203.0.113.xxx" "summary has masked IPv4"
assert_contains "$SUMMARY" "2001:db8:…" "summary has masked IPv6"

echo ""

# ── 3. Beginner Summary action counts ───────────────────────────────────────

echo "--- 3. Beginner Summary action counts ---"
echo ""

assert_contains "$SUMMARY" "Create:" "summary has Create count"
assert_contains "$SUMMARY" "Update:" "summary has Update count"
assert_contains "$SUMMARY" "No change:" "summary has No change count"
assert_contains "$SUMMARY" "Conflict:" "summary has Conflict count"

echo ""

# ── 4. Beginner Summary confirmation wording ────────────────────────────────

echo "--- 4. Beginner Summary confirmation wording ---"
echo ""

assert_contains "$SUMMARY" "Cloudflare DNS will be changed only after confirmation" "summary says changes only after confirmation"

echo ""

# ── 5. Beginner Summary no-delete ────────────────────────────────────────────

echo "--- 5. Beginner Summary no-delete ---"
echo ""

assert_contains "$SUMMARY" "No records will be deleted" "summary says no delete"

echo ""

# ── 6. Beginner Summary no-unowned-overwrite ────────────────────────────────

echo "--- 6. Beginner Summary no-unowned-overwrite ---"
echo ""

assert_contains "$SUMMARY" "No unowned records will be overwritten" "summary says no unowned overwrite"

echo ""

# ── 7. Confirmation numbered menu ────────────────────────────────────────────

echo "--- 7. Confirmation numbered menu ---"
echo ""

assert_contains "$CONFIRM" "1) Apply now" "confirmation has option 1"
assert_contains "$CONFIRM" "2) Review summary again" "confirmation has option 2"
assert_contains "$CONFIRM" "3) Cancel" "confirmation has option 3"

echo ""

# ── 8. Confirmation typed phrase ─────────────────────────────────────────────

echo "--- 8. Confirmation typed phrase ---"
echo ""

assert_contains "$CONFIRM" "apply dns records" "confirmation requires typed phrase"

echo ""

# ── 9. Confirmation no [y/N] ────────────────────────────────────────────────

echo "--- 9. Confirmation no [y/N] ---"
echo ""

assert_not_contains "$CONFIRM" "[y/N]" "confirmation has no [y/N]"
assert_not_contains "$CONFIRM" "[Y/n]" "confirmation has no [Y/n]"

echo ""

# ── 10. Confirmation no apply --yes ──────────────────────────────────────────

echo "--- 10. Confirmation no apply --yes ---"
echo ""

assert_not_contains "$CONFIRM" "apply --yes" "confirmation has no apply --yes"

echo ""

# ── 11. Advanced GET/POST/PATCH counts ───────────────────────────────────────

echo "--- 11. Advanced GET/POST/PATCH counts ---"
echo ""

assert_contains "$ADVANCED" "GET count:" "advanced has GET count"
assert_contains "$ADVANCED" "POST count:" "advanced has POST count"
assert_contains "$ADVANCED" "PATCH count:" "advanced has PATCH count"

echo ""

# ── 12. Advanced DELETE count: 0 ─────────────────────────────────────────────

echo "--- 12. Advanced DELETE count ---"
echo ""

assert_contains "$ADVANCED" "DELETE count: 0" "advanced DELETE count is 0"

echo ""

# ── 13. Post-check success Status: applied ───────────────────────────────────

echo "--- 13. Post-check success status ---"
echo ""

assert_contains "$SUCCESS" "Status: applied" "success status is applied"

echo ""

# ── 14. Post-check failure Status: uncertain ─────────────────────────────────

echo "--- 14. Post-check failure status ---"
echo ""

assert_contains "$FAILURE" "Status: uncertain" "failure status is uncertain"

echo ""

# ── 15. Partial failure Status: partial ──────────────────────────────────────

echo "--- 15. Partial failure status ---"
echo ""

assert_contains "$PARTIAL" "Status: partial" "partial status is partial"

echo ""

# ── 16. Failure fixtures say not reported as success ─────────────────────────

echo "--- 16. Failure not reported as success ---"
echo ""

assert_contains "$FAILURE" "not reported as success" "post-check failure says not success"
assert_contains "$PARTIAL" "not reported as success" "partial failure says not success"

echo ""

# ── 17. Failure fixtures say do not retry blindly ────────────────────────────

echo "--- 17. Failure do not retry blindly ---"
echo ""

assert_contains "$FAILURE" "Do not retry blindly" "post-check failure says no blind retry"
assert_contains "$PARTIAL" "Do not retry blindly" "partial failure says no blind retry"

echo ""

# ── 18-21. No raw full domain/hostname/IP ────────────────────────────────────

echo "--- 18-21. No raw full values ---"
echo ""

assert_not_contains "$ALL" "example.com" "no raw full domain"
assert_not_contains "$ALL" "proxy.example.com" "no raw full hostname"
assert_not_contains "$ALL" "203.0.113.10" "no raw full IPv4"
assert_not_contains "$ALL" "2001:db8::10" "no raw full IPv6"

echo ""

# ── 22. No Zone ID / Account ID / record ID ──────────────────────────────────

echo "--- 22. No Zone/Account/record ID ---"
echo ""

# Beginner-facing fixtures must not mention these at all
assert_not_contains "$SUMMARY" "Zone ID" "beginner: no Zone ID"
assert_not_contains "$SUMMARY" "Account ID" "beginner: no Account ID"
assert_not_contains "$SUMMARY" "record ID" "beginner: no record ID"
assert_not_contains "$CONFIRM" "Zone ID" "confirmation: no Zone ID"
assert_not_contains "$CONFIRM" "Account ID" "confirmation: no Account ID"
assert_not_contains "$SUCCESS" "Zone ID" "success: no Zone ID"
assert_not_contains "$FAILURE" "Zone ID" "failure: no Zone ID"

echo ""

# ── 23. No API token / Authorization / raw env ──────────────────────────────

echo "--- 23. No API token / Authorization ---"
echo ""

assert_not_contains "$ALL" "CF_API_TOKEN" "no CF_API_TOKEN"
assert_not_contains "$SUMMARY" "Authorization" "beginner: no Authorization"
assert_not_contains "$ALL" "api-env" "no api-env path"
assert_not_contains "$ALL" "cloudflare-api.env" "no env file path"

echo ""

# ── 24. No raw API request / response ────────────────────────────────────────

echo "--- 24. No raw API request / response ---"
echo ""

# Beginner-facing fixtures must not mention raw API internals
assert_not_contains "$SUMMARY" "raw API request" "beginner: no raw API request"
assert_not_contains "$SUMMARY" "raw API response" "beginner: no raw API response"
assert_not_contains "$CONFIRM" "raw API request" "confirmation: no raw API request"
assert_not_contains "$SUCCESS" "raw API request" "success: no raw API request"
assert_not_contains "$FAILURE" "raw API request" "failure: no raw API request"

echo ""

# ── 25. No workers.dev / subscription URL / protocol link ────────────────────

echo "--- 25. No workers.dev / subscription / protocol ---"
echo ""

assert_not_contains "$ALL" "workers.dev" "no workers.dev"
assert_not_contains "$ALL" "subscription URL" "no subscription URL"
assert_not_contains "$ALL" "hysteria2://" "no hysteria2://"
assert_not_contains "$ALL" "tuic://" "no tuic://"
assert_not_contains "$ALL" "vless://" "no vless://"
assert_not_contains "$ALL" "trojan://" "no trojan://"

echo ""

# ── 26. No private key / Reality private key ─────────────────────────────────

echo "--- 26. No private key ---"
echo ""

assert_not_contains "$ALL" "PRIVATE KEY" "no PRIVATE KEY"
assert_not_contains "$ALL" "Reality private key" "no Reality private key"

echo ""

# ── 27. No full sha256 ──────────────────────────────────────────────────────

echo "--- 27. No full sha256 ---"
echo ""

# Check for 64-char hex (full sha256)
if echo "$ALL" | grep -qE '[a-f0-9]{64}'; then
  fail "no full sha256 in fixtures"
  ERRORS=$((ERRORS + 1))
else
  pass "no full sha256 in fixtures"
fi

echo ""

# ── 28. No protocol URIs ────────────────────────────────────────────────────

echo "--- 28. No protocol URIs ---"
echo ""

assert_not_contains "$ALL" "vless://" "no vless://"
assert_not_contains "$ALL" "trojan://" "no trojan://"
assert_not_contains "$ALL" "hysteria2://" "no hysteria2://"
assert_not_contains "$ALL" "tuic://" "no tuic://"

echo ""

# ── 29. No apply --yes ──────────────────────────────────────────────────────

echo "--- 29. No apply --yes ---"
echo ""

assert_not_contains "$ALL" "apply --yes" "no apply --yes in any fixture"

echo ""

# ── 30. Test does not call nanobk cf dns apply --yes ─────────────────────────

echo "--- 30. Test does not call apply ---"
echo ""

# This test inspects fixture files only.
# It does NOT execute: nanobk, python3, bash (for apply), curl, wrangler.
# It does NOT call Cloudflare API.
# It does NOT create/update/delete DNS records.
# Safe by design — no runtime invocation assertions needed.
pass "test inspects fixtures only (no runtime invocation)"
pass "test does not call Cloudflare API"
pass "test does not create/update/delete DNS records"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.8 DNS Apply UX Mock tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
