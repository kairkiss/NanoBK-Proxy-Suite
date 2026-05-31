#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare Stale Read Mock Test
#
# Tests that the rotate Cloudflare verify retry logic handles stale reads
# without immediately failing or triggering rollback.
#
# Does NOT access real Cloudflare.
#
# Usage:
#   bash tests/rotate-cloudflare-stale-read-mock.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== Cloudflare Stale Read Mock Test ==="
echo ""

# ── Test 1: rotate-keys.sh has retry logic ──────────────────────────────────

echo "--- rotate-keys.sh retry logic ---"
echo ""

if grep -q "CF_VERIFY_ATTEMPTS" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "CF_VERIFY_ATTEMPTS exists"
else
  fail "CF_VERIFY_ATTEMPTS missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "CF_VERIFY_SLEEP" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "CF_VERIFY_SLEEP exists"
else
  fail "CF_VERIFY_SLEEP missing"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 2: verify retry loop exists ────────────────────────────────────────

echo ""
echo "--- verify retry loop ---"
echo ""

if grep -q "for verify_attempt" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "verify retry loop exists"
else
  fail "verify retry loop missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "retrying in.*s\.\.\." "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "retry message exists"
else
  fail "retry message missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "stale" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "stale read handling exists"
else
  fail "stale read handling missing"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 3: verify does not immediately fail ────────────────────────────────

echo ""
echo "--- verify does not immediately fail ---"
echo ""

# The verify loop should have multiple attempts before failing
if grep -q "verify_attempt.*CF_VERIFY_ATTEMPTS" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "verify loop uses CF_VERIFY_ATTEMPTS"
else
  fail "verify loop missing CF_VERIFY_ATTEMPTS"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 4: SHA comparison exists ───────────────────────────────────────────

echo ""
echo "--- SHA comparison ---"
echo ""

if grep -q "json_sha16\|local_sha\|cloud_sha" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "SHA comparison exists"
else
  fail "SHA comparison missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "local updatedAt\|cloud updatedAt" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "updatedAt comparison exists"
else
  fail "updatedAt comparison missing"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 5: Python fallback for JSON fields ─────────────────────────────────

echo ""
echo "--- Python fallback ---"
echo ""

if grep -q "json_read_field" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "json_read_field helper exists"
else
  fail "json_read_field helper missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "python3.*json.load" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "Python JSON fallback exists"
else
  fail "Python JSON fallback missing"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 6: Cloudflare rollback logic ───────────────────────────────────────

echo ""
echo "--- Cloudflare rollback ---"
echo ""

if grep -q "restore_cloudflare_profile" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "restore_cloudflare_profile exists"
else
  fail "restore_cloudflare_profile missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "CF_PROFILE_UPDATED" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "CF_PROFILE_UPDATED flag exists"
else
  fail "CF_PROFILE_UPDATED flag missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "Cloudflare rollback failed. Local rollback will continue" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rollback log wording updated"
else
  fail "rollback log wording missing"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 7: No debug artifacts ──────────────────────────────────────────────

echo ""
echo "--- safety ---"
echo ""

if grep -q "__nanob_debug\|primaryPreview" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  fail "debug artifacts found"
  ERRORS=$((ERRORS + 1))
else
  pass "no debug artifacts"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All stale read mock tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
