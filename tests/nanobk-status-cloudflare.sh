#!/usr/bin/env bash
# NanoBK Proxy Suite — nanobk status Cloudflare Test
#
# Tests that nanobk status correctly reads Cloudflare env files
# and produces valid JSON without leaking secrets.
#
# Usage:
#   bash tests/nanobk-status-cloudflare.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

check() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass "$desc"
  else
    fail "$desc"
    ERRORS=$((ERRORS + 1))
  fi
}

echo ""
echo "=== nanobk status Cloudflare Test ==="
echo ""

# ── Setup ───────────────────────────────────────────────────────────────────

TMP="${TMPDIR:-/tmp}/nanobk-cf-status-test-$$"
mkdir -p "$TMP/etc/nanobk"

# Fake tokens (should NOT appear in output)
FAKE_SUB="FAKE_SUB_TOKEN_SHOULD_NOT_LEAK"
FAKE_ADMIN="FAKE_ADMIN_TOKEN_SHOULD_NOT_LEAK"
FAKE_NANOB="FAKE_NANOB_TOKEN_SHOULD_NOT_LEAK"

# Create fake .cloudflare.local.env in repo root
cat > "$ROOT/.cloudflare.local.env" <<EOF
NANOK_WORKER_NAME="nanok"
NANOK_ROUTE_URL="https://nanok.example.workers.dev"
SUB_TOKEN="${FAKE_SUB}"
ADMIN_TOKEN="${FAKE_ADMIN}"
SUB_STORE_KV_NAMESPACE_ID="abc123"
SUB_PATH="/jb"
ADMIN_PATH="/admin/update"
ADMIN_CURRENT_PATH="/admin/current"
NANOBK_DEPLOY_STATUS="deployed"
NANOBK_PROFILE_UPLOAD_STATUS="uploaded"
NANOBK_VERIFY_STATUS="verified"
EOF
chmod 600 "$ROOT/.cloudflare.local.env"

# Create fake .nanob.local.env in repo root
cat > "$ROOT/.nanob.local.env" <<EOF
NANOB_WORKER_NAME="nanob"
NANOB_ROUTE_URL="https://nanob.example.workers.dev"
NANOB_TOKEN="${FAKE_NANOB}"
NANOB_PATH="/jb"
NANOK_ORIGIN="https://nanok.example.workers.dev"
NANOB_GEO_KV_NAMESPACE_ID="geo456"
EDGE_HOST="edge.example.com"
NANOB_DEPLOY_STATUS="deployed"
NANOB_VERIFY_STATUS="verified"
EOF
chmod 600 "$ROOT/.nanob.local.env"

# ── JSON output test ────────────────────────────────────────────────────────

echo "--- JSON output ---"
echo ""

JSON_OUTPUT=$(bash "$ROOT/bin/nanobk" --repo-dir "$ROOT" --json status --config-dir "$TMP/etc/nanobk" 2>&1)

# Valid JSON
if echo "$JSON_OUTPUT" | python3 -m json.tool >/dev/null 2>&1; then
  pass "JSON is valid"
else
  fail "JSON is NOT valid"
  ERRORS=$((ERRORS + 1))
  echo "  Raw: $JSON_OUTPUT" >&2
fi

# ok should be false (no config.env)
if echo "$JSON_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['ok'] == False" 2>/dev/null; then
  pass "ok=false (no config.env)"
else
  fail "ok should be false"
  ERRORS=$((ERRORS + 1))
fi

# Cloudflare nanok envExists
if echo "$JSON_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['cloudflare']['nanok']['envExists'] == True" 2>/dev/null; then
  pass "cloudflare.nanok.envExists=true"
else
  fail "cloudflare.nanok.envExists should be true"
  ERRORS=$((ERRORS + 1))
fi

# Cloudflare nanok subTokenPresent
if echo "$JSON_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['cloudflare']['nanok']['subTokenPresent'] == True" 2>/dev/null; then
  pass "cloudflare.nanok.subTokenPresent=true"
else
  fail "cloudflare.nanok.subTokenPresent should be true"
  ERRORS=$((ERRORS + 1))
fi

# subTokenFingerprint exists and is not empty
if echo "$JSON_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); fp=d['cloudflare']['nanok']['subTokenFingerprint']; assert len(fp) > 0" 2>/dev/null; then
  pass "cloudflare.nanok.subTokenFingerprint present"
else
  fail "subTokenFingerprint should be present"
  ERRORS=$((ERRORS + 1))
fi

# Cloudflare nanob envExists
if echo "$JSON_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['cloudflare']['nanob']['envExists'] == True" 2>/dev/null; then
  pass "cloudflare.nanob.envExists=true"
else
  fail "cloudflare.nanob.envExists should be true"
  ERRORS=$((ERRORS + 1))
fi

# Cloudflare nanob edgeHostConfigured
if echo "$JSON_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['cloudflare']['nanob']['edgeHostConfigured'] == True" 2>/dev/null; then
  pass "cloudflare.nanob.edgeHostConfigured=true"
else
  fail "edgeHostConfigured should be true"
  ERRORS=$((ERRORS + 1))
fi

# ── No secret leakage ───────────────────────────────────────────────────────

echo ""
echo "--- Secret leakage check ---"
echo ""

if echo "$JSON_OUTPUT" | grep -q "$FAKE_SUB"; then
  fail "SUB_TOKEN leaked in JSON output!"
  ERRORS=$((ERRORS + 1))
else
  pass "SUB_TOKEN not in JSON output"
fi

if echo "$JSON_OUTPUT" | grep -q "$FAKE_ADMIN"; then
  fail "ADMIN_TOKEN leaked in JSON output!"
  ERRORS=$((ERRORS + 1))
else
  pass "ADMIN_TOKEN not in JSON output"
fi

if echo "$JSON_OUTPUT" | grep -q "$FAKE_NANOB"; then
  fail "NANOB_TOKEN leaked in JSON output!"
  ERRORS=$((ERRORS + 1))
else
  pass "NANOB_TOKEN not in JSON output"
fi

# ── Text output test ────────────────────────────────────────────────────────

echo ""
echo "--- Text output ---"
echo ""

TEXT_OUTPUT=$(bash "$ROOT/bin/nanobk" --repo-dir "$ROOT" status --config-dir "$TMP/etc/nanobk" 2>&1)

if echo "$TEXT_OUTPUT" | grep -q "Cloudflare:"; then
  pass "Text output has Cloudflare section"
else
  fail "Text output missing Cloudflare section"
  ERRORS=$((ERRORS + 1))
fi

if echo "$TEXT_OUTPUT" | grep -q "Aggregator:"; then
  pass "Text output has Aggregator section"
else
  fail "Text output missing Aggregator section"
  ERRORS=$((ERRORS + 1))
fi

if echo "$TEXT_OUTPUT" | grep -q "$FAKE_SUB"; then
  fail "SUB_TOKEN leaked in text output!"
  ERRORS=$((ERRORS + 1))
else
  pass "SUB_TOKEN not in text output"
fi

if echo "$TEXT_OUTPUT" | grep -q "$FAKE_NANOB"; then
  fail "NANOB_TOKEN leaked in text output!"
  ERRORS=$((ERRORS + 1))
else
  pass "NANOB_TOKEN not in text output"
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -rf "$TMP"
rm -f "$ROOT/.cloudflare.local.env" "$ROOT/.nanob.local.env"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
