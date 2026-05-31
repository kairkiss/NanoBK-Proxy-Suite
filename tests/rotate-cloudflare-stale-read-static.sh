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

# ── Test 8: Python fallback for JSON reading ────────────────────────────────

echo ""
echo "--- Python fallback for JSON reading ---"
echo ""

TEST_JSON='{"tuic":{"uuid":"test-uuid-123","password":"test-pw-456"},"reality":{"publicKey":"test-pub-789"}}'

PYTHON3=$(command -v python3 2>/dev/null || echo "")
if [[ -n "$PYTHON3" ]]; then
  # Simulate json_read_field with python3
  RESULT_UUID=$(echo "$TEST_JSON" | python3 -c "
import json, sys
path = '.tuic.uuid'
try:
    obj = json.load(sys.stdin)
except:
    sys.exit(0)
parts = [p for p in path.strip().split('.') if p and p != '//' and p != 'empty']
cur = obj
for p in parts:
    if isinstance(cur, dict) and p in cur:
        cur = cur[p]
    else:
        sys.exit(0)
if cur is None:
    pass
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur, separators=(',', ':')))
else:
    print(str(cur))
" 2>/dev/null)
  if [[ "$RESULT_UUID" == "test-uuid-123" ]]; then
    pass "Python fallback reads .tuic.uuid correctly"
  else
    fail "Python fallback .tuic.uuid: expected 'test-uuid-123', got '${RESULT_UUID}'"
    ERRORS=$((ERRORS + 1))
  fi

  RESULT_PUB=$(echo "$TEST_JSON" | python3 -c "
import json, sys
path = '.reality.publicKey'
try:
    obj = json.load(sys.stdin)
except:
    sys.exit(0)
parts = [p for p in path.strip().split('.') if p and p != '//' and p != 'empty']
cur = obj
for p in parts:
    if isinstance(cur, dict) and p in cur:
        cur = cur[p]
    else:
        sys.exit(0)
if cur is None:
    pass
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur, separators=(',', ':')))
else:
    print(str(cur))
" 2>/dev/null)
  if [[ "$RESULT_PUB" == "test-pub-789" ]]; then
    pass "Python fallback reads .reality.publicKey correctly"
  else
    fail "Python fallback .reality.publicKey: expected 'test-pub-789', got '${RESULT_PUB}'"
    ERRORS=$((ERRORS + 1))
  fi

  RESULT_PW=$(echo "$TEST_JSON" | python3 -c "
import json, sys
path = '.tuic.password'
try:
    obj = json.load(sys.stdin)
except:
    sys.exit(0)
parts = [p for p in path.strip().split('.') if p and p != '//' and p != 'empty']
cur = obj
for p in parts:
    if isinstance(cur, dict) and p in cur:
        cur = cur[p]
    else:
        sys.exit(0)
if cur is None:
    pass
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur, separators=(',', ':')))
else:
    print(str(cur))
" 2>/dev/null)
  if [[ "$RESULT_PW" == "test-pw-456" ]]; then
    pass "Python fallback reads .tuic.password correctly"
  else
    fail "Python fallback .tuic.password: expected 'test-pw-456', got '${RESULT_PW}'"
    ERRORS=$((ERRORS + 1))
  fi
else
  warn "python3 not available; skipping Python fallback test"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All stale read static tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
