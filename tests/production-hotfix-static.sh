#!/usr/bin/env bash
# NanoBK Proxy Suite — Production Hotfix Static Tests
#
# Validates production hotfixes without accessing network or system:
#   - TUIC template compatibility
#   - Reality x25519 parser robustness
#   - Download pattern matching
#
# Usage:
#   bash tests/production-hotfix-static.sh

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
echo "=== Production Hotfix Static Tests ==="
echo ""

# ── TUIC template compatibility ─────────────────────────────────────────────

echo "--- TUIC template compatibility ---"
echo ""

TUIC_TPL="$ROOT/vps/templates/tuic-v5.config.json.tpl"

# Must NOT contain removed fields
if grep -q 'udp_relay_mode' "$TUIC_TPL" 2>/dev/null; then
  fail "TUIC template still contains udp_relay_mode"
  ERRORS=$((ERRORS + 1))
else
  pass "TUIC template: no udp_relay_mode"
fi

if grep -q 'gc_interval' "$TUIC_TPL" 2>/dev/null; then
  fail "TUIC template still contains gc_interval"
  ERRORS=$((ERRORS + 1))
else
  pass "TUIC template: no gc_interval"
fi

if grep -q 'gc_lifetime' "$TUIC_TPL" 2>/dev/null; then
  fail "TUIC template still contains gc_lifetime"
  ERRORS=$((ERRORS + 1))
else
  pass "TUIC template: no gc_lifetime"
fi

if grep -q 'congestion_control' "$TUIC_TPL" 2>/dev/null; then
  fail "TUIC template still contains congestion_control"
  ERRORS=$((ERRORS + 1))
else
  pass "TUIC template: no congestion_control"
fi

# Must contain required fields
check "TUIC template: has server"       grep -q '"server"' "$TUIC_TPL"
check "TUIC template: has users"        grep -q '"users"' "$TUIC_TPL"
check "TUIC template: has certificate"  grep -q '"certificate"' "$TUIC_TPL"
check "TUIC template: has private_key"  grep -q '"private_key"' "$TUIC_TPL"
check "TUIC template: has alpn"         grep -q '"alpn"' "$TUIC_TPL"
check "TUIC template: has log_level"    grep -q '"log_level"' "$TUIC_TPL"

# Template must be valid JSON when placeholders are replaced
TUIC_RENDERED=$(sed 's/__TUIC_PORT__/9443/g; s/__TUIC_UUID__/test-uuid/g; s/__TUIC_PASSWORD__/test-pw/g; s/__CERT_FILE__/\/tmp\/cert.pem/g; s/__KEY_FILE__/\/tmp\/key.pem/g' "$TUIC_TPL")
if echo "$TUIC_RENDERED" | python3 -m json.tool >/dev/null 2>&1; then
  pass "TUIC template: rendered JSON is valid"
else
  fail "TUIC template: rendered JSON is invalid"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Reality x25519 parser ──────────────────────────────────────────────────

echo "--- Reality x25519 parser robustness (via shared parser) ---"
echo ""

# Source the shared parser
NANOBK_DRY_RUN=1
NANOBK_RENDER_ONLY=0
source "$ROOT/vps/lib/common.sh" 2>/dev/null || true
source "$ROOT/vps/lib/profile.sh" 2>/dev/null || true

test_x25519_parse() {
  local input="$1"
  local expected_priv="$2"
  local expected_pub="$3"
  local label="$4"

  REALITY_PRIVATE_KEY=""
  REALITY_PUBLIC_KEY=""

  if parse_xray_x25519_output "$input" 2>/dev/null; then
    if [[ "$REALITY_PRIVATE_KEY" == "$expected_priv" ]] && [[ "$REALITY_PUBLIC_KEY" == "$expected_pub" ]]; then
      pass "x25519 parser: ${label}"
    else
      fail "x25519 parser: ${label}"
      echo "    Expected priv: ${expected_priv}" >&2
      echo "    Got priv:      ${REALITY_PRIVATE_KEY}" >&2
      echo "    Expected pub:  ${expected_pub}" >&2
      echo "    Got pub:       ${REALITY_PUBLIC_KEY}" >&2
      ERRORS=$((ERRORS + 1))
    fi
  else
    fail "x25519 parser: ${label} (parser failed)"
    ERRORS=$((ERRORS + 1))
  fi
}

# Standard format
test_x25519_parse \
  "Private key: abc123
Public key: def456" \
  "abc123" "def456" \
  "standard Private key / Public key"

# No space after colon
test_x25519_parse \
  "PrivateKey:abc123
PublicKey:def456" \
  "abc123" "def456" \
  "PrivateKey / PublicKey (no space)"

# Lowercase
test_x25519_parse \
  "private key: abc123
public key: def456" \
  "abc123" "def456" \
  "lowercase private key / public key"

# Mixed case with extra spaces
test_x25519_parse \
  "  Private Key : abc123
  Public Key : def456" \
  "abc123" "def456" \
  "mixed case with extra spaces"

# New Xray format: Password (PublicKey)
test_x25519_parse \
  "PrivateKey: abc123
Password (PublicKey): def456
Hash32: hash123" \
  "abc123" "def456" \
  "new Xray format Password (PublicKey)"

# Private-key / Public-key with dashes
test_x25519_parse \
  "Private-key: abc123
Public-key: def456" \
  "abc123" "def456" \
  "Private-key / Public-key with dashes"

# Uppercase
test_x25519_parse \
  "PRIVATE KEY: abc123
PUBLIC KEY: def456" \
  "abc123" "def456" \
  "uppercase PRIVATE KEY / PUBLIC KEY"

echo ""

# ── Download pattern matching ──────────────────────────────────────────────

echo "--- Download pattern matching (static) ---"
echo ""

# Test pattern matching logic (simulated)
test_asset_match() {
  local pattern="$1"
  local asset_name="$2"
  local should_match="$3"
  local label="$4"

  if grep -iE -- "$pattern" <<< "$asset_name" >/dev/null 2>&1; then
    if [[ "$should_match" == "yes" ]]; then
      pass "pattern match: ${label}"
    else
      fail "pattern match: ${label} (should NOT match)"
      ERRORS=$((ERRORS + 1))
    fi
  else
    if [[ "$should_match" == "no" ]]; then
      pass "pattern no-match: ${label}"
    else
      fail "pattern match: ${label} (should match)"
      ERRORS=$((ERRORS + 1))
    fi
  fi
}

# Hysteria patterns (bare binary)
HY_PATTERN="hysteria-linux-amd64$"

test_asset_match "$HY_PATTERN" "hysteria-linux-amd64" "yes" "hysteria bare binary amd64"
test_asset_match "$HY_PATTERN" "hysteria-linux-arm64" "no" "hysteria arm64 (wrong arch)"
test_asset_match "$HY_PATTERN" "hysteria-linux-amd64-avx" "no" "hysteria avx variant (not preferred)"
test_asset_match "$HY_PATTERN" "hysteria-windows-amd64.exe" "no" "hysteria windows"
test_asset_match "$HY_PATTERN" "hysteria-darwin-amd64" "no" "hysteria darwin"
test_asset_match "$HY_PATTERN" "hashes.txt" "no" "hysteria hashes.txt"

# TUIC patterns (bare binary)
TUIC_PATTERN="tuic-server.*x86_64-unknown-linux-gnu$"

test_asset_match "$TUIC_PATTERN" "tuic-server-1.0.0-x86_64-unknown-linux-gnu" "yes" "tuic bare binary x86_64"
test_asset_match "$TUIC_PATTERN" "tuic-server-1.0.0-aarch64-unknown-linux-gnu" "no" "tuic aarch64 (wrong arch)"
test_asset_match "$TUIC_PATTERN" "tuic-server-1.0.0-x86_64-unknown-linux-gnu.sha256sum" "no" "tuic sha256sum"
test_asset_match "$TUIC_PATTERN" "tuic-server-1.0.0-x86_64-pc-windows-msvc.exe" "no" "tuic windows"
test_asset_match "$TUIC_PATTERN" "tuic-server-1.0.0-x86_64-apple-darwin" "no" "tuic darwin"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All production hotfix tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
