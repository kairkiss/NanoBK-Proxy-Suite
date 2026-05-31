#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare KV Parser Test
#
# Tests the KV namespace ID parser in install-cloudflare.sh
# against various Wrangler output formats.
#
# Usage:
#   bash tests/cloudflare-kv-parser.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nanobk-kv-parser-test"
INSTALLER="$ROOT/installer/install-cloudflare.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== Cloudflare KV Parser Test ==="
echo ""

rm -rf "$TMP"
mkdir -p "$TMP"

# Helper: test parser with given input
test_parse() {
  local label="$1"
  local binding="$2"
  local expected="$3"
  local content="$4"

  printf '%s\n' "$content" > "$TMP/test_input.json"

  local result
  result=$(bash "$INSTALLER" --test-parse-kv-id "$binding" "$TMP/test_input.json" 2>/dev/null) || true

  if [[ "$result" == "$expected" ]]; then
    pass "${label}"
  else
    fail "${label}"
    echo "    Expected: ${expected}" >&2
    echo "    Got:      ${result}" >&2
    ERRORS=$((ERRORS + 1))
  fi
}

# ── Test 1: Wrangler 4 JSON pretty ─────────────────────────────────────────

echo "--- Wrangler 4 JSON formats ---"
echo ""

test_parse "Wrangler 4 JSON pretty" "SUB_STORE" "0123456789abcdef0123456789abcdef" '{
  "kv_namespaces": [
    {
      "binding": "SUB_STORE",
      "id": "0123456789abcdef0123456789abcdef"
    }
  ]
}'

# ── Test 2: Wrangler 4 JSON compact ────────────────────────────────────────

test_parse "Wrangler 4 JSON compact" "SUB_STORE" "0123456789abcdef0123456789abcdef" \
  '{"kv_namespaces":[{"binding":"SUB_STORE","id":"0123456789abcdef0123456789abcdef"}]}'

# ── Test 3: JSON direct id ─────────────────────────────────────────────────

test_parse "JSON direct id" "SUB_STORE" "0123456789abcdef0123456789abcdef" \
  '{"id":"0123456789abcdef0123456789abcdef"}'

# ── Test 4: TOML style with spaces ─────────────────────────────────────────

test_parse "TOML id with spaces" "SUB_STORE" "0123456789abcdef0123456789abcdef" \
  'id = "0123456789abcdef0123456789abcdef"'

# ── Test 5: TOML style no spaces ───────────────────────────────────────────

test_parse "TOML id no spaces" "SUB_STORE" "0123456789abcdef0123456789abcdef" \
  'id="0123456789abcdef0123456789abcdef"'

# ── Test 6: Text id colon ──────────────────────────────────────────────────

test_parse "Text id colon" "SUB_STORE" "0123456789abcdef0123456789abcdef" \
  'id: 0123456789abcdef0123456789abcdef'

# ── Test 7: Mixed output with JSON ─────────────────────────────────────────

test_parse "Mixed output with JSON" "SUB_STORE" "0123456789abcdef0123456789abcdef" \
  'Some wrangler output before
{"kv_namespaces":[{"binding":"SUB_STORE","id":"0123456789abcdef0123456789abcdef"}]}
Some wrangler output after'

# ── Test 8: Missing id should fail ─────────────────────────────────────────

echo ""
echo "--- Failure cases ---"
echo ""

printf '%s\n' '{"kv_namespaces":[{"binding":"SUB_STORE"}]}' > "$TMP/test_input.json"
result=$(bash "$INSTALLER" --test-parse-kv-id "SUB_STORE" "$TMP/test_input.json" 2>/dev/null) || true
if [[ -z "$result" ]]; then
  pass "Missing id: returns empty"
else
  fail "Missing id: should return empty, got: ${result}"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 9: Binding-aware (multiple namespaces) ────────────────────────────

echo ""
echo "--- Binding awareness ---"
echo ""

test_parse "Binding-aware: picks correct namespace" "SUB_STORE" "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" '{
  "kv_namespaces": [
    {"binding": "OTHER_STORE", "id": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"},
    {"binding": "SUB_STORE", "id": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}
  ]
}'

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -rf "$TMP"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All KV parser tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
