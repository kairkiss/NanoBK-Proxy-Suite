#!/usr/bin/env bash
# NanoBK Proxy Suite — Export Links Test
#
# Tests `nanobk export link` and `nanobk export links` commands.
# Uses fixture profile with safe example values only.
#
# Usage:
#   bash tests/export-links.sh

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
echo "=== Export Links Test ==="
echo ""

FIXTURE="$ROOT/tests/fixtures/profile-export.example.json"
NANOBK="$ROOT/bin/nanobk"

# ── Fixture exists ─────────────────────────────────────────────────────────

echo "--- Fixture ---"
echo ""

check "fixture profile exists" test -f "$FIXTURE"

# ── Single protocol export ─────────────────────────────────────────────────

echo ""
echo "--- Single protocol export ---"
echo ""

HY2_OUTPUT=$(bash "$NANOBK" export link hy2 --profile "$FIXTURE" 2>&1)
if [[ "$HY2_OUTPUT" == hysteria2://* ]]; then
  pass "hy2 link starts with hysteria2://"
else
  fail "hy2 link does not start with hysteria2:// (got: ${HY2_OUTPUT:0:20}...)"
  ERRORS=$((ERRORS + 1))
fi

TUIC_OUTPUT=$(bash "$NANOBK" export link tuic --profile "$FIXTURE" 2>&1)
if [[ "$TUIC_OUTPUT" == tuic://* ]]; then
  pass "tuic link starts with tuic://"
else
  fail "tuic link does not start with tuic:// (got: ${TUIC_OUTPUT:0:20}...)"
  ERRORS=$((ERRORS + 1))
fi

REALITY_OUTPUT=$(bash "$NANOBK" export link reality --profile "$FIXTURE" 2>&1)
if [[ "$REALITY_OUTPUT" == vless://* ]]; then
  pass "reality link starts with vless://"
else
  fail "reality link does not start with vless:// (got: ${REALITY_OUTPUT:0:20}...)"
  ERRORS=$((ERRORS + 1))
fi

TROJAN_OUTPUT=$(bash "$NANOBK" export link trojan --profile "$FIXTURE" 2>&1)
if [[ "$TROJAN_OUTPUT" == trojan://* ]]; then
  pass "trojan link starts with trojan://"
else
  fail "trojan link does not start with trojan:// (got: ${TROJAN_OUTPUT:0:20}...)"
  ERRORS=$((ERRORS + 1))
fi

# ── Single protocol exit code ──────────────────────────────────────────────

echo ""
echo "--- Single protocol exit codes ---"
echo ""

check "export link hy2 exits 0" bash "$NANOBK" export link hy2 --profile "$FIXTURE"
check "export link tuic exits 0" bash "$NANOBK" export link tuic --profile "$FIXTURE"
check "export link reality exits 0" bash "$NANOBK" export link reality --profile "$FIXTURE"
check "export link trojan exits 0" bash "$NANOBK" export link trojan --profile "$FIXTURE"

# ── Export all links ───────────────────────────────────────────────────────

echo ""
echo "--- Export all links ---"
echo ""

ALL_OUTPUT=$(bash "$NANOBK" export links --profile "$FIXTURE" 2>&1)

if echo "$ALL_OUTPUT" | grep -q "hysteria2://"; then
  pass "export links includes hy2"
else
  fail "export links missing hy2"
  ERRORS=$((ERRORS + 1))
fi

if echo "$ALL_OUTPUT" | grep -q "tuic://"; then
  pass "export links includes tuic"
else
  fail "export links missing tuic"
  ERRORS=$((ERRORS + 1))
fi

if echo "$ALL_OUTPUT" | grep -q "vless://"; then
  pass "export links includes reality"
else
  fail "export links missing reality"
  ERRORS=$((ERRORS + 1))
fi

if echo "$ALL_OUTPUT" | grep -q "trojan://"; then
  pass "export links includes trojan"
else
  fail "export links missing trojan"
  ERRORS=$((ERRORS + 1))
fi

check "export links exits 0" bash "$NANOBK" export links --profile "$FIXTURE"

# ── JSON output ────────────────────────────────────────────────────────────

echo ""
echo "--- JSON output ---"
echo ""

HY2_JSON=$(bash "$NANOBK" export link hy2 --profile "$FIXTURE" --json 2>&1)
if echo "$HY2_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'hy2' in d and d['hy2'].startswith('hysteria2://')" 2>/dev/null; then
  pass "export link hy2 --json valid JSON with hy2 key"
else
  fail "export link hy2 --json invalid output"
  ERRORS=$((ERRORS + 1))
fi

ALL_JSON=$(bash "$NANOBK" export links --profile "$FIXTURE" --json 2>&1)
if echo "$ALL_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); assert set(d.keys()) == {'hy2','tuic','reality','trojan'}" 2>/dev/null; then
  pass "export links --json valid JSON with all 4 protocols"
else
  fail "export links --json invalid output"
  ERRORS=$((ERRORS + 1))
fi

# ── Missing profile ────────────────────────────────────────────────────────

echo ""
echo "--- Error handling ---"
echo ""

if bash "$NANOBK" export link hy2 --profile "/tmp/nonexistent-profile-12345.json" >/dev/null 2>&1; then
  fail "missing profile should return nonzero"
  ERRORS=$((ERRORS + 1))
else
  pass "missing profile returns nonzero"
fi

# ── Missing --profile value ───────────────────────────────────────────────

MISSING_PROFILE_ERR=$(bash "$NANOBK" export link hy2 --profile 2>&1 || true)
if echo "$MISSING_PROFILE_ERR" | grep -q "profile"; then
  pass "export link --profile without value shows clear error"
else
  fail "export link --profile without value missing error message"
  ERRORS=$((ERRORS + 1))
fi

MISSING_PROFILE_ERR2=$(bash "$NANOBK" export links --profile 2>&1 || true)
if echo "$MISSING_PROFILE_ERR2" | grep -q "profile"; then
  pass "export links --profile without value shows clear error"
else
  fail "export links --profile without value missing error message"
  ERRORS=$((ERRORS + 1))
fi

# ── Unknown protocol ───────────────────────────────────────────────────────

if bash "$NANOBK" export link wireguard --profile "$FIXTURE" >/dev/null 2>&1; then
  fail "unknown protocol should return nonzero"
  ERRORS=$((ERRORS + 1))
else
  pass "unknown protocol returns nonzero"
fi

# ── Missing required fields ───────────────────────────────────────────────

echo ""
echo "--- Required field validation ---"
echo ""

TMPDIR_TESTS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

# Missing HY2 password
cat > "$TMPDIR_TESTS/hy2-missing-password.json" <<'FIXTURE_EOF'
{
  "hy2": {
    "name": "[US] Test-HY2",
    "server": "node.example.com",
    "port": 443,
    "sni": "node.example.com"
  }
}
FIXTURE_EOF

HY2_ERR=$(bash "$NANOBK" export link hy2 --profile "$TMPDIR_TESTS/hy2-missing-password.json" 2>&1 || true)
if echo "$HY2_ERR" | grep -q "password"; then
  pass "missing HY2 password reports clear error"
else
  fail "missing HY2 password should report password error"
  ERRORS=$((ERRORS + 1))
fi
# Must NOT contain Python traceback
if echo "$HY2_ERR" | grep -q "Traceback"; then
  fail "missing HY2 password should not produce Python traceback"
  ERRORS=$((ERRORS + 1))
else
  pass "missing HY2 password has no traceback"
fi

# Missing Reality publicKey
cat > "$TMPDIR_TESTS/reality-missing-pubkey.json" <<'FIXTURE_EOF'
{
  "reality": {
    "name": "[US] Test-Reality",
    "server": "203.0.113.10",
    "port": 8443,
    "uuid": "11111111-1111-4111-8111-111111111111",
    "servername": "www.example.com",
    "shortId": "abcd1234efgh5678"
  }
}
FIXTURE_EOF

REALITY_ERR=$(bash "$NANOBK" export link reality --profile "$TMPDIR_TESTS/reality-missing-pubkey.json" 2>&1 || true)
if echo "$REALITY_ERR" | grep -q "publicKey"; then
  pass "missing Reality publicKey reports clear error"
else
  fail "missing Reality publicKey should report publicKey error"
  ERRORS=$((ERRORS + 1))
fi
if echo "$REALITY_ERR" | grep -q "Traceback"; then
  fail "missing Reality publicKey should not produce Python traceback"
  ERRORS=$((ERRORS + 1))
else
  pass "missing Reality publicKey has no traceback"
fi

# Missing TUIC uuid
cat > "$TMPDIR_TESTS/tuic-missing-uuid.json" <<'FIXTURE_EOF'
{
  "tuic": {
    "name": "[US] Test-TUIC",
    "server": "node.example.com",
    "port": 9443,
    "password": "example-password",
    "sni": "node.example.com"
  }
}
FIXTURE_EOF

TUIC_ERR=$(bash "$NANOBK" export link tuic --profile "$TMPDIR_TESTS/tuic-missing-uuid.json" 2>&1 || true)
if echo "$TUIC_ERR" | grep -q "uuid"; then
  pass "missing TUIC uuid reports clear error"
else
  fail "missing TUIC uuid should report uuid error"
  ERRORS=$((ERRORS + 1))
fi
if echo "$TUIC_ERR" | grep -q "Traceback"; then
  fail "missing TUIC uuid should not produce Python traceback"
  ERRORS=$((ERRORS + 1))
else
  pass "missing TUIC uuid has no traceback"
fi

# ── Status must not expose links ───────────────────────────────────────────

echo ""
echo "--- Status/Doctor safety ---"
echo ""

STATUS_HELP=$(bash "$NANOBK" --help 2>&1)
if echo "$STATUS_HELP" | grep -q "export"; then
  pass "help mentions export command"
else
  fail "help missing export command"
  ERRORS=$((ERRORS + 1))
fi

# Help output must not contain any protocol URI prefixes (links are secrets)
for proto_uri in "hysteria2://" "tuic://" "vless://" "trojan://"; do
  if echo "$STATUS_HELP" | grep -q "$proto_uri"; then
    fail "--help should not contain $proto_uri"
    ERRORS=$((ERRORS + 1))
  else
    pass "--help does not contain $proto_uri"
  fi
done

# ── Link content safety ────────────────────────────────────────────────────

echo ""
echo "--- Link content safety ---"
echo ""

# Verify fixture uses only safe example values
if grep -q "workers\.dev\|real-secret\|PRIVATE_KEY" "$FIXTURE" 2>/dev/null; then
  fail "fixture contains unsafe values"
  ERRORS=$((ERRORS + 1))
else
  pass "fixture uses only safe example values"
fi

# ── URI encoding check ─────────────────────────────────────────────────────

echo ""
echo "--- URI encoding ---"
echo ""

# Verify no raw spaces in links
if echo "$HY2_OUTPUT" | grep -q " "; then
  fail "hy2 link contains raw space"
  ERRORS=$((ERRORS + 1))
else
  pass "hy2 link has no raw spaces"
fi

if echo "$TUIC_OUTPUT" | grep -q " "; then
  fail "tuic link contains raw space"
  ERRORS=$((ERRORS + 1))
else
  pass "tuic link has no raw spaces"
fi

if echo "$REALITY_OUTPUT" | grep -q " "; then
  fail "reality link contains raw space"
  ERRORS=$((ERRORS + 1))
else
  pass "reality link has no raw spaces"
fi

if echo "$TROJAN_OUTPUT" | grep -q " "; then
  fail "trojan link contains raw space"
  ERRORS=$((ERRORS + 1))
else
  pass "trojan link has no raw spaces"
fi

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}All export-links tests passed${NC}"
else
  echo -e "${RED}${ERRORS} export-links test(s) failed${NC}"
fi
echo ""

exit $ERRORS
