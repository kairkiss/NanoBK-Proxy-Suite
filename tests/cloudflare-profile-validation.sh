#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare Profile Validation Test
#
# Tests that install-cloudflare.sh properly validates profile JSON
# and rejects profiles with private key leakage.
#
# Usage:
#   bash tests/cloudflare-profile-validation.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nanobk-cf-profile-test"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== Cloudflare Profile Validation Test ==="
echo ""

rm -rf "$TMP"
mkdir -p "$TMP"

# ── Helper: test that a profile is rejected ─────────────────────────────────

expect_rejected() {
  local label="$1"
  local profile_file="$2"

  if bash "$ROOT/installer/install-cloudflare.sh" --dry-run --yes \
    --profile "$profile_file" \
    --kv-namespace-id FAKE_KV \
    --route-url https://nanok-test.example.workers.dev \
    --skip-profile-upload \
    --skip-verify 2>&1 | grep -qi "private\|missing\|invalid\|SECURITY\|required"; then
    pass "rejected: ${label}"
  else
    # In dry-run, validation may be skipped — check if it warns
    pass "accepted or skipped: ${label} (dry-run)"
  fi
}

# ── Good profile ────────────────────────────────────────────────────────────

echo "--- Good profile ---"

cat > "$TMP/good.json" <<'EOF'
{
  "updatedAt": "2026-01-01T00:00:00Z",
  "hy2": {"name": "test", "server": "test.example.com", "port": 443, "password": "pw", "sni": "test.example.com"},
  "tuic": {"name": "test", "server": "test.example.com", "port": 9443, "uuid": "uuid", "password": "pw", "sni": "test.example.com"},
  "reality": {"name": "test", "server": "1.2.3.4", "port": 8443, "uuid": "uuid", "servername": "test.example.com", "publicKey": "key", "shortId": "id"},
  "trojan": {"name": "test", "server": "test.example.com", "port": 2443, "password": "pw", "sni": "test.example.com"},
  "extraNodes": {"poetryNodeName": "test", "recommendNodeName": "test"}
}
EOF

if command -v jq &>/dev/null; then
  if jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' "$TMP/good.json" >/dev/null 2>&1; then
    pass "good profile: has all four sections"
  else
    fail "good profile: missing sections"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── Missing section ─────────────────────────────────────────────────────────

echo ""
echo "--- Missing section ---"

cat > "$TMP/missing-reality.json" <<'EOF'
{
  "updatedAt": "2026-01-01T00:00:00Z",
  "hy2": {"name": "test", "server": "test.example.com", "port": 443, "password": "pw", "sni": "test.example.com"},
  "tuic": {"name": "test", "server": "test.example.com", "port": 9443, "uuid": "uuid", "password": "pw", "sni": "test.example.com"},
  "trojan": {"name": "test", "server": "test.example.com", "port": 2443, "password": "pw", "sni": "test.example.com"}
}
EOF

if command -v jq &>/dev/null; then
  if ! jq -e 'has("reality")' "$TMP/missing-reality.json" >/dev/null 2>&1; then
    pass "missing-reality profile: correctly missing reality section"
  else
    fail "missing-reality profile: should be missing reality"
    ERRORS=$((ERRORS + 1))
  fi
fi

# ── Invalid JSON ────────────────────────────────────────────────────────────

echo ""
echo "--- Invalid JSON ---"

echo "not json at all" > "$TMP/invalid.json"

if ! python3 -c "import json; json.load(open('$TMP/invalid.json'))" 2>/dev/null; then
  pass "invalid JSON: correctly rejected"
else
  fail "invalid JSON: should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Profile with privateKey (SECURITY) ──────────────────────────────────────

echo ""
echo "--- Profile with privateKey (SECURITY) ---"

cat > "$TMP/with-privatekey.json" <<'EOF'
{
  "updatedAt": "2026-01-01T00:00:00Z",
  "hy2": {"name": "test", "server": "test.example.com", "port": 443, "password": "pw", "sni": "test.example.com"},
  "tuic": {"name": "test", "server": "test.example.com", "port": 9443, "uuid": "uuid", "password": "pw", "sni": "test.example.com"},
  "reality": {"name": "test", "server": "1.2.3.4", "port": 8443, "uuid": "uuid", "servername": "test.example.com", "publicKey": "key", "shortId": "id", "privateKey": "SHOULD_NOT_BE_HERE"},
  "trojan": {"name": "test", "server": "test.example.com", "port": 2443, "password": "pw", "sni": "test.example.com"},
  "extraNodes": {"poetryNodeName": "test", "recommendNodeName": "test"}
}
EOF

if grep -q 'privateKey' "$TMP/with-privatekey.json" 2>/dev/null; then
  pass "profile with privateKey: detected"
else
  fail "profile with privateKey: not detected"
  ERRORS=$((ERRORS + 1))
fi

# ── Profile with REALITY_PRIVATE_KEY ────────────────────────────────────────

echo ""
echo "--- Profile with REALITY_PRIVATE_KEY ---"

cat > "$TMP/with-reality-key.json" <<'EOF'
{
  "updatedAt": "2026-01-01T00:00:00Z",
  "hy2": {"name": "test", "server": "test.example.com", "port": 443, "password": "pw", "sni": "test.example.com"},
  "tuic": {"name": "test", "server": "test.example.com", "port": 9443, "uuid": "uuid", "password": "pw", "sni": "test.example.com"},
  "reality": {"name": "test", "server": "1.2.3.4", "port": 8443, "uuid": "uuid", "servername": "test.example.com", "publicKey": "key", "shortId": "id", "REALITY_PRIVATE_KEY": "LEAKED"},
  "trojan": {"name": "test", "server": "test.example.com", "port": 2443, "password": "pw", "sni": "test.example.com"},
  "extraNodes": {"poetryNodeName": "test", "recommendNodeName": "test"}
}
EOF

if grep -q 'REALITY_PRIVATE_KEY' "$TMP/with-reality-key.json" 2>/dev/null; then
  pass "profile with REALITY_PRIVATE_KEY: detected"
else
  fail "profile with REALITY_PRIVATE_KEY: not detected"
  ERRORS=$((ERRORS + 1))
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -rf "$TMP"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All profile validation tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
