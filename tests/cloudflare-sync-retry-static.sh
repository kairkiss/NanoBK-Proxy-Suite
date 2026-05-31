#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare Sync Retry Static Test
#
# Validates that rotate-keys.sh has retry/backoff logic for Cloudflare sync
# and that install-cloudflare.sh has retry for profile upload and nanob verify.
#
# Does NOT access real Cloudflare.
#
# Usage:
#   bash tests/cloudflare-sync-retry-static.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== Cloudflare Sync Retry Static Test ==="
echo ""

# ── rotate-keys.sh retry logic ──────────────────────────────────────────────

echo "--- rotate-keys.sh: Cloudflare verify retry ---"
echo ""

if grep -q "CF_VERIFY_ATTEMPTS" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: CF_VERIFY_ATTEMPTS exists"
else
  fail "rotate: CF_VERIFY_ATTEMPTS missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "CF_VERIFY_SLEEP" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: CF_VERIFY_SLEEP exists"
else
  fail "rotate: CF_VERIFY_SLEEP missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "retrying in.*s\.\.\." "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: retry message exists"
else
  fail "rotate: retry message missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "stale profile" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: stale read handling exists"
else
  fail "rotate: stale read handling missing"
  ERRORS=$((ERRORS + 1))
fi

# ── rotate-keys.sh: Cloudflare rollback ─────────────────────────────────────

echo ""
echo "--- rotate-keys.sh: Cloudflare rollback ---"
echo ""

if grep -q "restore_cloudflare_profile" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: restore_cloudflare_profile function exists"
else
  fail "rotate: restore_cloudflare_profile missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "CF_PROFILE_UPDATED" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: CF_PROFILE_UPDATED flag exists"
else
  fail "rotate: CF_PROFILE_UPDATED flag missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "Cloudflare rollback failed. Local rollback will continue" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: split-brain warning exists"
else
  fail "rotate: split-brain warning missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "manually resync\|manual.*resync" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: manual resync guidance exists"
else
  fail "rotate: manual resync guidance missing"
  ERRORS=$((ERRORS + 1))
fi

# ── rotate-keys.sh: SHA output ──────────────────────────────────────────────

echo ""
echo "--- rotate-keys.sh: SHA output ---"
echo ""

if grep -q "json_sha16" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: json_sha16 function exists"
else
  fail "rotate: json_sha16 function missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "local sha16\|cloud sha16\|local_sha\|cloud_sha" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: SHA comparison output exists"
else
  fail "rotate: SHA comparison output missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "local updatedAt\|cloud updatedAt\|local_updated\|cloud_updated" "$ROOT/vps/scripts/rotate-keys.sh" 2>/dev/null; then
  pass "rotate: updatedAt comparison output exists"
else
  fail "rotate: updatedAt comparison output missing"
  ERRORS=$((ERRORS + 1))
fi

# ── install-cloudflare.sh: profile upload retry ─────────────────────────────

echo ""
echo "--- install-cloudflare.sh: profile upload retry ---"
echo ""

if grep -q "CF_UPLOAD_ATTEMPTS" "$ROOT/installer/install-cloudflare.sh" 2>/dev/null; then
  pass "installer: CF_UPLOAD_ATTEMPTS exists"
else
  fail "installer: CF_UPLOAD_ATTEMPTS missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "CF_UPLOAD_SLEEP" "$ROOT/installer/install-cloudflare.sh" 2>/dev/null; then
  pass "installer: CF_UPLOAD_SLEEP exists"
else
  fail "installer: CF_UPLOAD_SLEEP missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "propagating\|propagat" "$ROOT/installer/install-cloudflare.sh" 2>/dev/null; then
  pass "installer: Worker propagation delay message exists"
else
  fail "installer: Worker propagation delay message missing"
  ERRORS=$((ERRORS + 1))
fi

# ── install-cloudflare.sh: nanob verify retry ──────────────────────────────

echo ""
echo "--- install-cloudflare.sh: nanob verify retry ---"
echo ""

if grep -q "verify_attempt" "$ROOT/installer/install-cloudflare.sh" 2>/dev/null; then
  pass "installer: nanob verify retry loop exists"
else
  fail "installer: nanob verify retry loop missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q "subscription verified (attempt" "$ROOT/installer/install-cloudflare.sh" 2>/dev/null; then
  pass "installer: nanob verify success message with attempt"
else
  fail "installer: nanob verify success message missing"
  ERRORS=$((ERRORS + 1))
fi

# ── No debug artifacts ──────────────────────────────────────────────────────

echo ""
echo "--- Safety ---"
echo ""

if grep -q "__nanob_debug\|primaryPreview" "$ROOT/vps/scripts/rotate-keys.sh" "$ROOT/installer/install-cloudflare.sh" 2>/dev/null; then
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
  echo -e "  ${GREEN}All Cloudflare sync retry tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
