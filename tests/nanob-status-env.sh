#!/usr/bin/env bash
# NanoBK Proxy Suite — nanob status env field test
#
# Tests that nanobk status correctly reads .nanob.local.env
# and that verify status updates are reflected.
#
# Usage:
#   bash tests/nanob-status-env.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nanobk-status-env-test-$$"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== nanob Status Env Field Test ==="
echo ""

rm -rf "$TMP"
mkdir -p "$TMP"

# ── Test 1: verify=pending shows pending ────────────────────────────────────

echo "--- verify=pending ---"
echo ""

cat > "$TMP/.nanob.local.env" <<'EOF'
NANOB_WORKER_NAME="nanob"
NANOB_ROUTE_URL="https://nanob.example.workers.dev"
NANOB_TOKEN="fake-token-for-test"
NANOB_PATH="/jb"
NANOB_DEPLOY_STATUS="deployed"
NANOB_VERIFY_STATUS="pending"
NANOB_GEO_KV_NAMESPACE_ID="fake-geo-kv"
EDGE_HOST=""
EOF
chmod 600 "$TMP/.nanob.local.env"

# Create a fake repo structure for nanobk to find .nanob.local.env
mkdir -p "$TMP/repo/bin"
cp "$ROOT/bin/nanobk" "$TMP/repo/bin/nanobk"
ln -sf "$TMP/.nanob.local.env" "$TMP/repo/.nanob.local.env"

OUTPUT=$(bash "$TMP/repo/bin/nanobk" --repo-dir "$TMP/repo" --json status --config-dir "$TMP" 2>&1 || true)

if echo "$OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['cloudflare']['nanob']['verifyStatus']=='pending'" 2>/dev/null; then
  pass "nanob verify shows pending"
else
  fail "nanob verify should show pending"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 2: verify=verified shows verified ──────────────────────────────────

echo ""
echo "--- verify=verified ---"
echo ""

sed -i.bak 's/NANOB_VERIFY_STATUS="pending"/NANOB_VERIFY_STATUS="verified"/' "$TMP/.nanob.local.env"
rm -f "$TMP/.nanob.local.env.bak"

OUTPUT2=$(bash "$TMP/repo/bin/nanobk" --repo-dir "$TMP/repo" --json status --config-dir "$TMP" 2>&1 || true)

if echo "$OUTPUT2" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['cloudflare']['nanob']['verifyStatus']=='verified'" 2>/dev/null; then
  pass "nanob verify shows verified"
else
  fail "nanob verify should show verified"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 3: token not in output ─────────────────────────────────────────────

echo ""
echo "--- token safety ---"
echo ""

if echo "$OUTPUT2" | grep -q "fake-token-for-test"; then
  fail "nanob token leaked in JSON output"
  ERRORS=$((ERRORS + 1))
else
  pass "nanob token not in JSON output"
fi

if echo "$OUTPUT2" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['cloudflare']['nanob']['tokenPresent']==True" 2>/dev/null; then
  pass "nanob tokenPresent=true"
else
  fail "nanob tokenPresent should be true"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 4: env file permissions ────────────────────────────────────────────

echo ""
echo "--- permissions ---"
echo ""

PERMS=$(stat -c '%a' "$TMP/.nanob.local.env" 2>/dev/null || stat -f '%Lp' "$TMP/.nanob.local.env" 2>/dev/null || echo "unknown")
if [[ "$PERMS" == "600" ]]; then
  pass ".nanob.local.env permissions: 600"
else
  fail ".nanob.local.env permissions: ${PERMS}"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 5: text output shows verify status ─────────────────────────────────

echo ""
echo "--- text output ---"
echo ""

TEXT_OUTPUT=$(bash "$TMP/repo/bin/nanobk" --repo-dir "$TMP/repo" status --config-dir "$TMP" 2>&1 || true)

if echo "$TEXT_OUTPUT" | grep -q "verified\|pending"; then
  pass "text output shows verify status"
else
  fail "text output missing verify status"
  ERRORS=$((ERRORS + 1))
fi

if echo "$TEXT_OUTPUT" | grep -q "fake-token-for-test"; then
  fail "token leaked in text output"
  ERRORS=$((ERRORS + 1))
else
  pass "token not in text output"
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -rf "$TMP"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All nanob status env tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
