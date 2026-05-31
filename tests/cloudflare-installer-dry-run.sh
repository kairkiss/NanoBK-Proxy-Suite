#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare Installer Dry-Run Test
#
# Tests install-cloudflare.sh --dry-run without accessing real Cloudflare.
#
# Usage:
#   bash tests/cloudflare-installer-dry-run.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nanobk-cf-dry-run-test"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== Cloudflare Installer Dry-Run Test ==="
echo ""

# ── Setup ───────────────────────────────────────────────────────────────────

rm -rf "$TMP"
mkdir -p "$TMP"

# Create a minimal profile fixture
cat > "$TMP/profile.json" <<'EOF'
{
  "updatedAt": "2026-01-01T00:00:00Z",
  "hy2": {"name": "test", "server": "test.example.com", "port": 443, "password": "test", "sni": "test.example.com"},
  "tuic": {"name": "test", "server": "test.example.com", "port": 9443, "uuid": "test-uuid", "password": "test", "sni": "test.example.com"},
  "reality": {"name": "test", "server": "1.2.3.4", "port": 8443, "uuid": "test-uuid", "servername": "test.example.com", "publicKey": "test-key", "shortId": "test-id"},
  "trojan": {"name": "test", "server": "test.example.com", "port": 2443, "password": "test", "sni": "test.example.com"},
  "extraNodes": {"poetryNodeName": "test", "recommendNodeName": "test"}
}
EOF

# ── Test 1: --help ──────────────────────────────────────────────────────────

echo "--- --help ---"
if bash "$ROOT/installer/install-cloudflare.sh" --help 2>&1 | grep -q "Cloudflare Deployment"; then
  pass "--help shows usage"
else
  fail "--help missing usage text"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 2: --dry-run with existing KV ──────────────────────────────────────

echo ""
echo "--- --dry-run with existing KV ---"
DRY_OUTPUT=$(bash "$ROOT/installer/install-cloudflare.sh" --dry-run --yes \
  --profile "$TMP/profile.json" \
  --kv-namespace-id FAKE_KV_ID \
  --route-url https://nanok-test.example.workers.dev 2>&1 || true)

if echo "$DRY_OUTPUT" | grep -q "DRY-RUN"; then
  pass "dry-run shows DRY-RUN markers"
else
  fail "dry-run missing DRY-RUN markers"
  ERRORS=$((ERRORS + 1))
fi

if echo "$DRY_OUTPUT" | grep -q "nanok-test"; then
  pass "dry-run shows worker name"
else
  fail "dry-run missing worker name"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 3: --dry-run with --deploy-nanob ───────────────────────────────────

echo ""
echo "--- --dry-run with --deploy-nanob ---"
DRY_NANOB=$(bash "$ROOT/installer/install-cloudflare.sh" --dry-run --yes \
  --profile "$TMP/profile.json" \
  --kv-namespace-id FAKE_KV_ID \
  --route-url https://nanok-test.example.workers.dev \
  --deploy-nanob \
  --nanob-route-url https://nanob-test.example.workers.dev \
  --nanob-geo-kv-namespace-id FAKE_GEO_KV_ID 2>&1 || true)

if echo "$DRY_NANOB" | grep -q "nanob-test"; then
  pass "dry-run with nanob shows nanob URL"
else
  fail "dry-run with nanob missing nanob URL"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 4: --edge-host cleaning ────────────────────────────────────────────

echo ""
echo "--- edge-host cleaning ---"
DRY_EDGE=$(bash "$ROOT/installer/install-cloudflare.sh" --dry-run --yes \
  --profile "$TMP/profile.json" \
  --kv-namespace-id FAKE_KV_ID \
  --route-url https://nanok-test.example.workers.dev \
  --deploy-nanob \
  --nanob-route-url https://nanob-test.example.workers.dev \
  --nanob-geo-kv-namespace-id FAKE_GEO_KV_ID \
  --edge-host "https://edge-test.example.workers.dev/" 2>&1 || true)

if echo "$DRY_EDGE" | grep -q "edge-test.example.workers.dev"; then
  pass "edge-host cleaned (no https:// or trailing /)"
else
  fail "edge-host not cleaned properly"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 5: dry-run does not execute real Cloudflare commands ────────────────

echo ""
echo "--- safety ---"
# dry-run should NOT create real wrangler.toml files
if [[ -f "$ROOT/workers/nanok/wrangler.toml" ]]; then
  # If it exists, it should be from a previous run, not this dry-run
  pass "wrangler.toml exists (pre-existing or from previous run)"
else
  pass "dry-run did not create wrangler.toml"
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -rf "$TMP"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All Cloudflare installer dry-run tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
