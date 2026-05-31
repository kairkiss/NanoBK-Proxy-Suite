#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare Profile Validation Test
#
# Tests that install-cloudflare.sh --validate-profile-only properly
# validates profile JSON and rejects profiles with private key leakage.
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

if bash "$ROOT/installer/install-cloudflare.sh" --validate-profile-only --profile "$TMP/good.json" >/dev/null 2>&1; then
  pass "good profile: accepted (exit 0)"
else
  fail "good profile: rejected (should succeed)"
  ERRORS=$((ERRORS + 1))
fi

# ── Missing section ─────────────────────────────────────────────────────────

echo ""
echo "--- Missing reality section ---"

cat > "$TMP/missing-reality.json" <<'EOF'
{
  "updatedAt": "2026-01-01T00:00:00Z",
  "hy2": {"name": "test", "server": "test.example.com", "port": 443, "password": "pw", "sni": "test.example.com"},
  "tuic": {"name": "test", "server": "test.example.com", "port": 9443, "uuid": "uuid", "password": "pw", "sni": "test.example.com"},
  "trojan": {"name": "test", "server": "test.example.com", "port": 2443, "password": "pw", "sni": "test.example.com"}
}
EOF

if bash "$ROOT/installer/install-cloudflare.sh" --validate-profile-only --profile "$TMP/missing-reality.json" >/dev/null 2>&1; then
  fail "missing-reality: accepted (should fail)"
  ERRORS=$((ERRORS + 1))
else
  pass "missing-reality: rejected (exit non-zero)"
fi

# ── Invalid JSON ────────────────────────────────────────────────────────────

echo ""
echo "--- Invalid JSON ---"

echo "not json at all" > "$TMP/invalid.json"

if bash "$ROOT/installer/install-cloudflare.sh" --validate-profile-only --profile "$TMP/invalid.json" >/dev/null 2>&1; then
  fail "invalid JSON: accepted (should fail)"
  ERRORS=$((ERRORS + 1))
else
  pass "invalid JSON: rejected (exit non-zero)"
fi

# ── Profile with privateKey ─────────────────────────────────────────────────

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

if bash "$ROOT/installer/install-cloudflare.sh" --validate-profile-only --profile "$TMP/with-privatekey.json" >/dev/null 2>&1; then
  fail "profile with privateKey: accepted (should fail)"
  ERRORS=$((ERRORS + 1))
else
  pass "profile with privateKey: rejected (exit non-zero)"
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

if bash "$ROOT/installer/install-cloudflare.sh" --validate-profile-only --profile "$TMP/with-reality-key.json" >/dev/null 2>&1; then
  fail "profile with REALITY_PRIVATE_KEY: accepted (should fail)"
  ERRORS=$((ERRORS + 1))
else
  pass "profile with REALITY_PRIVATE_KEY: rejected (exit non-zero)"
fi

# ── Profile with private_key ────────────────────────────────────────────────

echo ""
echo "--- Profile with private_key ---"

cat > "$TMP/with-private-key.json" <<'EOF'
{
  "updatedAt": "2026-01-01T00:00:00Z",
  "hy2": {"name": "test", "server": "test.example.com", "port": 443, "password": "pw", "sni": "test.example.com"},
  "tuic": {"name": "test", "server": "test.example.com", "port": 9443, "uuid": "uuid", "password": "pw", "sni": "test.example.com"},
  "reality": {"name": "test", "server": "1.2.3.4", "port": 8443, "uuid": "uuid", "servername": "test.example.com", "publicKey": "key", "shortId": "id", "private_key": "LEAKED"},
  "trojan": {"name": "test", "server": "test.example.com", "port": 2443, "password": "pw", "sni": "test.example.com"},
  "extraNodes": {"poetryNodeName": "test", "recommendNodeName": "test"}
}
EOF

if bash "$ROOT/installer/install-cloudflare.sh" --validate-profile-only --profile "$TMP/with-private-key.json" >/dev/null 2>&1; then
  fail "profile with private_key: accepted (should fail)"
  ERRORS=$((ERRORS + 1))
else
  pass "profile with private_key: rejected (exit non-zero)"
fi

# ── Nonexistent profile ─────────────────────────────────────────────────────

echo ""
echo "--- Nonexistent profile ---"

if bash "$ROOT/installer/install-cloudflare.sh" --validate-profile-only --profile "$TMP/does-not-exist.json" >/dev/null 2>&1; then
  fail "nonexistent profile: accepted (should fail)"
  ERRORS=$((ERRORS + 1))
else
  pass "nonexistent profile: rejected (exit non-zero)"
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
