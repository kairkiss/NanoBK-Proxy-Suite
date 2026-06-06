#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare DNS Dry-Run Plan Test
#
# Tests `nanobk cf dns plan` and `nanobk cf dns validate-profile` commands.
# All values are safe documentation-only examples.
#
# Usage:
#   bash tests/cf-dns-plan.sh

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

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    pass "$label"
  else
    fail "$label — expected to contain: $needle"
    ERRORS=$((ERRORS + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    fail "$label — should NOT contain: $needle"
    ERRORS=$((ERRORS + 1))
  else
    pass "$label"
  fi
}

echo ""
echo "=== Cloudflare DNS Dry-Run Plan Test ==="
echo ""

FIXTURE="$ROOT/tests/fixtures/cf-dns-profile.example.json"
NANOBK="$ROOT/bin/nanobk"

# ── Fixture exists ─────────────────────────────────────────────────────────

echo "--- Fixture ---"
echo ""

check "fixture profile exists" test -f "$FIXTURE"

# ── Validate profile ──────────────────────────────────────────────────────

echo ""
echo "--- Validate profile ---"
echo ""

check "validate-profile exits 0" bash "$NANOBK" cf dns validate-profile --profile "$FIXTURE"

VALIDATE_OUTPUT=$(bash "$NANOBK" cf dns validate-profile --profile "$FIXTURE" 2>&1)
assert_contains "$VALIDATE_OUTPUT" "valid" "validate-profile output says valid"

# ── Direct arg plan ───────────────────────────────────────────────────────

echo ""
echo "--- Direct arg plan ---"
echo ""

DIRECT_OUTPUT=$(bash "$NANOBK" cf dns plan --zone example.com --node node --ipv4 203.0.113.10 --ipv6 2001:db8::10 2>&1)

check "direct arg plan exits 0" bash "$NANOBK" cf dns plan --zone example.com --node node --ipv4 203.0.113.10 --ipv6 2001:db8::10

assert_contains "$DIRECT_OUTPUT" "Cloudflare DNS dry-run plan" "output has dry-run plan header"
assert_contains "$DIRECT_OUTPUT" "node.example.com" "output has node hostname"
assert_contains "$DIRECT_OUTPUT" "203.0.113.10" "output has IPv4"
assert_contains "$DIRECT_OUTPUT" "2001:db8::10" "output has IPv6"
assert_contains "$DIRECT_OUTPUT" "proxied=false" "output says proxied=false"
assert_contains "$DIRECT_OUTPUT" "no mutation performed" "output says no mutation"
assert_contains "$DIRECT_OUTPUT" "no Cloudflare API call" "output says no API call"
assert_contains "$DIRECT_OUTPUT" "panel.example.com" "output has panel reserved"
assert_contains "$DIRECT_OUTPUT" "nanok.example.com" "output has nanok reserved"
assert_contains "$DIRECT_OUTPUT" "nanob.example.com" "output has nanob reserved"

# ── Profile plan ──────────────────────────────────────────────────────────

echo ""
echo "--- Profile plan ---"
echo ""

PROFILE_OUTPUT=$(bash "$NANOBK" cf dns plan --profile "$FIXTURE" 2>&1)

check "profile plan exits 0" bash "$NANOBK" cf dns plan --profile "$FIXTURE"

assert_contains "$PROFILE_OUTPUT" "Cloudflare DNS dry-run plan" "profile plan has header"
assert_contains "$PROFILE_OUTPUT" "node.example.com" "profile plan has node hostname"
assert_contains "$PROFILE_OUTPUT" "proxied=false" "profile plan says proxied=false"
assert_contains "$PROFILE_OUTPUT" "no mutation performed" "profile plan says no mutation"

# ── JSON output ───────────────────────────────────────────────────────────

echo ""
echo "--- JSON output ---"
echo ""

JSON_OUTPUT=$(bash "$NANOBK" cf dns plan --profile "$FIXTURE" --json 2>&1)

check "profile plan --json exits 0" bash "$NANOBK" cf dns plan --profile "$FIXTURE" --json

if echo "$JSON_OUTPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] is True, 'ok should be True'
assert d['noMutation'] is True, 'noMutation should be True'
assert d['zone'] == 'example.com', 'zone mismatch'
assert d['nodeHostname'] == 'node.example.com', 'hostname mismatch'
assert len(d['plannedRecords']) == 2, 'expected 2 planned records'
a_rec = [r for r in d['plannedRecords'] if r['type'] == 'A'][0]
assert a_rec['content'] == '203.0.113.10', 'A record content mismatch'
assert a_rec['proxied'] is False, 'A record must not be proxied'
aaaa_rec = [r for r in d['plannedRecords'] if r['type'] == 'AAAA'][0]
assert aaaa_rec['content'] == '2001:db8::10', 'AAAA record content mismatch'
assert aaaa_rec['proxied'] is False, 'AAAA record must not be proxied'
assert 'panel' in d['reservedHostnames'], 'missing panel reserved'
assert 'nanok' in d['reservedHostnames'], 'missing nanok reserved'
assert 'nanob' in d['reservedHostnames'], 'missing nanob reserved'
assert 'no mutation performed' in d['notes'], 'missing no mutation note'
" 2>&1; then
  pass "JSON output parses and has correct structure"
else
  fail "JSON output parsing failed"
  ERRORS=$((ERRORS + 1))
fi

# ── JSON output security: no secrets ──────────────────────────────────────

echo ""
echo "--- JSON output security ---"
echo ""

for forbidden in "CF_API_TOKEN" "workers.dev" "subscription" "hysteria2://" "tuic://" "vless://" "trojan://" "private_key" "privateKey" "secret" "password"; do
  if echo "$JSON_OUTPUT" | grep -qi "$forbidden"; then
    fail "JSON output contains forbidden string: $forbidden"
    ERRORS=$((ERRORS + 1))
  else
    pass "JSON output does not contain: $forbidden"
  fi
done

# ── Text output security: no secrets ──────────────────────────────────────

echo ""
echo "--- Text output security ---"
echo ""

ALL_TEXT="${DIRECT_OUTPUT}
${PROFILE_OUTPUT}"

for forbidden in "CF_API_TOKEN" "workers.dev" "subscription" "hysteria2://" "tuic://" "vless://" "trojan://" "private_key" "privateKey" "secret" "password"; do
  if echo "$ALL_TEXT" | grep -qi "$forbidden"; then
    fail "text output contains forbidden string: $forbidden"
    ERRORS=$((ERRORS + 1))
  else
    pass "text output does not contain: $forbidden"
  fi
done

# ── Error handling: bad zone ──────────────────────────────────────────────

echo ""
echo "--- Error handling ---"
echo ""

BAD_ZONE=$(bash "$NANOBK" cf dns plan --zone "not-a-valid-zone" --node node --ipv4 203.0.113.10 2>&1 || true)
if echo "$BAD_ZONE" | grep -qi "error\|invalid\|zone"; then
  pass "bad zone rejected"
else
  fail "bad zone should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Error handling: bad node prefix ───────────────────────────────────────

BAD_NODE=$(bash "$NANOBK" cf dns plan --zone example.com --node "not valid!" --ipv4 203.0.113.10 2>&1 || true)
if echo "$BAD_NODE" | grep -qi "error\|invalid\|node"; then
  pass "bad node prefix rejected"
else
  fail "bad node prefix should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Error handling: invalid IPv4 ──────────────────────────────────────────

BAD_IPV4=$(bash "$NANOBK" cf dns plan --zone example.com --node node --ipv4 "999.999.999.999" 2>&1 || true)
if echo "$BAD_IPV4" | grep -qi "error\|invalid\|ipv4"; then
  pass "invalid IPv4 rejected"
else
  fail "invalid IPv4 should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Error handling: invalid IPv6 ──────────────────────────────────────────

BAD_IPV6=$(bash "$NANOBK" cf dns plan --zone example.com --node node --ipv6 "not-an-ipv6" 2>&1 || true)
if echo "$BAD_IPV6" | grep -qi "error\|invalid\|ipv6"; then
  pass "invalid IPv6 rejected"
else
  fail "invalid IPv6 should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Error handling: defaultProxied=true ───────────────────────────────────

TMPDIR_TESTS=$(mktemp -d)
trap 'rm -rf "$TMPDIR_TESTS"' EXIT

cat > "$TMPDIR_TESTS/proxied-true.json" <<'EOF'
{
  "zoneName": "example.com",
  "nodePrefix": "node",
  "ipv4": "203.0.113.10",
  "defaultProxied": true
}
EOF

PROXIED_ERR=$(bash "$NANOBK" cf dns plan --profile "$TMPDIR_TESTS/proxied-true.json" 2>&1 || true)
if echo "$PROXIED_ERR" | grep -qi "proxied\|DNS-only"; then
  pass "defaultProxied=true rejected"
else
  fail "defaultProxied=true should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Error handling: missing ipv4 and ipv6 ─────────────────────────────────

cat > "$TMPDIR_TESTS/no-ip.json" <<'EOF'
{
  "zoneName": "example.com",
  "nodePrefix": "node"
}
EOF

NO_IP_ERR=$(bash "$NANOBK" cf dns plan --profile "$TMPDIR_TESTS/no-ip.json" 2>&1 || true)
if echo "$NO_IP_ERR" | grep -qi "ipv4\|ipv6\|at least"; then
  pass "missing ipv4 and ipv6 rejected"
else
  fail "missing ipv4 and ipv6 should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Error handling: missing zone ──────────────────────────────────────────

cat > "$TMPDIR_TESTS/no-zone.json" <<'EOF'
{
  "nodePrefix": "node",
  "ipv4": "203.0.113.10"
}
EOF

NO_ZONE_ERR=$(bash "$NANOBK" cf dns plan --profile "$TMPDIR_TESTS/no-zone.json" 2>&1 || true)
if echo "$NO_ZONE_ERR" | grep -qi "zoneName\|missing\|error"; then
  pass "missing zone rejected"
else
  fail "missing zone should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Error handling: secret-like profile key ───────────────────────────────

cat > "$TMPDIR_TESTS/secret-key.json" <<'EOF'
{
  "zoneName": "example.com",
  "nodePrefix": "node",
  "ipv4": "203.0.113.10",
  "apiKey": "should-not-be-here"
}
EOF

SECRET_ERR=$(bash "$NANOBK" cf dns plan --profile "$TMPDIR_TESTS/secret-key.json" 2>&1 || true)
if echo "$SECRET_ERR" | grep -qi "secret\|forbidden\|apiKey\|key"; then
  pass "secret-like profile key rejected"
else
  fail "secret-like profile key should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Error handling: secret-like key in nested object ──────────────────────

cat > "$TMPDIR_TESTS/secret-nested.json" <<'EOF'
{
  "zoneName": "example.com",
  "nodePrefix": "node",
  "ipv4": "203.0.113.10",
  "reserved": {
    "panelPrefix": "panel",
    "secretKey": "bad"
  }
}
EOF

SECRET_NESTED_ERR=$(bash "$NANOBK" cf dns plan --profile "$TMPDIR_TESTS/secret-nested.json" 2>&1 || true)
if echo "$SECRET_NESTED_ERR" | grep -qi "secret\|forbidden"; then
  pass "secret-like nested key rejected"
else
  fail "secret-like nested key should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Error handling: publicKey rejected (not in DNS profile context) ───────

cat > "$TMPDIR_TESTS/pubkey.json" <<'EOF'
{
  "zoneName": "example.com",
  "nodePrefix": "node",
  "ipv4": "203.0.113.10",
  "publicKey": "should-not-be-in-dns-profile"
}
EOF

PUBKEY_ERR=$(bash "$NANOBK" cf dns plan --profile "$TMPDIR_TESTS/pubkey.json" 2>&1 || true)
if echo "$PUBKEY_ERR" | grep -qi "key\|forbidden\|publicKey"; then
  pass "publicKey in DNS profile rejected"
else
  fail "publicKey in DNS profile should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── Error handling: invalid JSON ──────────────────────────────────────────

echo "not json at all" > "$TMPDIR_TESTS/bad.json"

BAD_JSON_ERR=$(bash "$NANOBK" cf dns plan --profile "$TMPDIR_TESTS/bad.json" 2>&1 || true)
if echo "$BAD_JSON_ERR" | grep -qi "JSON\|invalid\|error"; then
  pass "invalid JSON rejected"
else
  fail "invalid JSON should be rejected"
  ERRORS=$((ERRORS + 1))
fi

# ── CLI help mentions new commands ────────────────────────────────────────

echo ""
echo "--- Help output ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --help 2>&1)
if echo "$HELP_OUTPUT" | grep -q "cf dns"; then
  pass "help mentions cf dns commands"
else
  fail "help should mention cf dns commands"
  ERRORS=$((ERRORS + 1))
fi

# ── Existing cf commands still work ───────────────────────────────────────

echo ""
echo "--- Existing cf commands preserved ---"
echo ""

CF_HELP=$(bash "$NANOBK" cf 2>&1 || true)
if echo "$CF_HELP" | grep -q "deploy\|verify"; then
  pass "existing cf subcommands still mentioned"
else
  fail "existing cf subcommands should still work"
  ERRORS=$((ERRORS + 1))
fi

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
if [[ $ERRORS -eq 0 ]]; then
  echo -e "${GREEN}All cf-dns-plan tests passed${NC}"
else
  echo -e "${RED}${ERRORS} cf-dns-plan test(s) failed${NC}"
fi
echo ""

exit $ERRORS
