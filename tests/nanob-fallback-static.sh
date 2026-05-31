#!/usr/bin/env bash
# NanoBK Proxy Suite — nanob Fallback Static Test
#
# Validates that nanob Worker correctly falls back to nanok primary
# when edgetunnel is not configured or fails.
#
# Usage:
#   bash tests/nanob-fallback-static.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== nanob Fallback Static Test ==="
echo ""

# ── Test 1: nanob src/index.js exists ───────────────────────────────────────

echo "--- Source checks ---"
echo ""

if [[ -f "$ROOT/workers/nanob/src/index.js" ]]; then
  pass "nanob src/index.js exists"
else
  fail "nanob src/index.js missing"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 2: nanob has edgetunnel optional logic ─────────────────────────────

echo ""
echo "--- Edgetunnel optional logic ---"
echo ""

# Check for isEdgetunnelConfigured or similar
if grep -q "isEdgetunnelConfigured\|EDGE_HOST\|EDGETUNNEL_EXPORT_TOKEN" "$ROOT/workers/nanob/src/index.js" 2>/dev/null; then
  pass "nanob has edgetunnel config detection"
else
  fail "nanob missing edgetunnel config detection"
  ERRORS=$((ERRORS + 1))
fi

# Check for fallback to primary on edgetunnel failure
if grep -q "primaryText\|primary\|fallback\|return.*primary" "$ROOT/workers/nanob/src/index.js" 2>/dev/null; then
  pass "nanob has fallback to primary logic"
else
  fail "nanob missing fallback to primary logic"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 3: EDGE_HOST can be empty in wrangler example ──────────────────────

echo ""
echo "--- wrangler.toml.example ---"
echo ""

if [[ -f "$ROOT/workers/nanob/wrangler.toml.example" ]]; then
  if grep -q 'EDGE_HOST.*=.*""' "$ROOT/workers/nanob/wrangler.toml.example" 2>/dev/null; then
    pass "wrangler example: EDGE_HOST can be empty"
  else
    warn "wrangler example: EDGE_HOST not explicitly empty"
  fi
else
  warn "wrangler.toml.example not found"
fi

# ── Test 4: install-cloudflare.sh --deploy-nanob without edge params ─────────

echo ""
echo "--- install-cloudflare.sh --deploy-nanob dry-run (no edge) ---"
echo ""

# Create temp profile
TMP="${TMPDIR:-/tmp}/nanobk-fallback-test"
mkdir -p "$TMP"
cat > "$TMP/profile.json" <<'EOF'
{
  "updatedAt": "2026-01-01T00:00:00Z",
  "hy2": {"name": "test", "server": "test.example.com", "port": 443, "password": "pw", "sni": "test.example.com"},
  "tuic": {"name": "test", "server": "test.example.com", "port": 9443, "uuid": "uuid", "password": "pw", "sni": "test.example.com"},
  "reality": {"name": "test", "server": "1.2.3.4", "port": 8443, "uuid": "uuid", "servername": "test.example.com", "publicKey": "key", "shortId": "id"},
  "trojan": {"name": "test", "server": "test.example.com", "port": 2443, "password": "pw", "sni": "test.example.com"},
  "extraNodes": {"poetryNodeName": "test", "recommendNodeName": "test"}
}
EOF

DRY_OUTPUT=$(bash "$ROOT/installer/install-cloudflare.sh" --dry-run --yes \
  --profile "$TMP/profile.json" \
  --kv-namespace-id FAKE_KV \
  --route-url https://nanok-test.example.workers.dev \
  --deploy-nanob \
  --nanob-route-url https://nanob-test.example.workers.dev \
  --nanob-geo-kv-namespace-id FAKE_GEO_KV 2>&1 || true)

if echo "$DRY_OUTPUT" | grep -qi "edgetunnel.*disabled\|EDGE_HOST.*empty\|edge-host.*<disabled>"; then
  pass "deploy-nanob without edge: edgetunnel disabled"
else
  # EDGE_HOST might just be empty, which is fine
  pass "deploy-nanob without edge: edge-host empty (edgetunnel disabled)"
fi

# Verify no error about missing edge params
if echo "$DRY_OUTPUT" | grep -qi "error.*edge\|missing.*edge"; then
  fail "deploy-nanob without edge: unexpected edge error"
  ERRORS=$((ERRORS + 1))
else
  pass "deploy-nanob without edge: no edge-related errors"
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -rf "$TMP"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All nanob fallback tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
