#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare Zone Discovery Read-only Test
#
# Tests the read-only Cloudflare zone discovery helper.
# Uses NANOBK_CF_ZONES_FAKE_RESPONSE for mock API. Does NOT call real Cloudflare.
#
# Usage:
#   bash tests/v2.2.40-cloudflare-zone-discovery-readonly.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="$ROOT/lib/nanobk_cf_zones.py"
FIXTURES="$ROOT/tests/fixtures/v2.2.40"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local desc="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (expected '$needle')"
    ERRORS=$((ERRORS + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local desc="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (unexpected '$needle')"
    ERRORS=$((ERRORS + 1))
  fi
}

# Portable file mode helper (matches v2.2.29 convention)
nanobk_test_file_mode() {
  if stat -c '%a' "$1" 2>/dev/null; then
    return 0
  fi
  stat -f '%Lp' "$1"
}

# Helper: create temp credential env with given mode
make_cred() {
  local mode="$1"
  local content="${2:-CF_API_TOKEN=DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN}"
  local tmpf=$(mktemp)
  echo "$content" > "$tmpf"
  chmod "$mode" "$tmpf"
  echo "$tmpf"
}

echo ""
echo "=== Cloudflare Zone Discovery Read-only Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Module exists
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Module exists ---"
echo ""

if [[ -f "$MODULE" ]]; then
  pass "A1: module exists"
else
  fail "A1: module does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Success: two zones
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Success: two zones ---"
echo ""

chmod 600 "$FIXTURES/safe_credential.env"
CRED_MODE=$(nanobk_test_file_mode "$FIXTURES/safe_credential.env")
if [[ "$CRED_MODE" != "600" ]]; then
  fail "B-pre: safe credential should be 600, got $CRED_MODE"
  ERRORS=$((ERRORS + 1))
fi

B_OUT=$(NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/cf_zones_success_two.json" \
  python3 "$MODULE" list --api-env "$FIXTURES/safe_credential.env" 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: two zones exits 0"
else
  fail "B1: two zones should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "example.com" "B2: shows example.com"
assert_contains "$B_OUT" "example.net" "B3: shows example.net"
assert_contains "$B_OUT" "Count: 2" "B4: count is 2"
assert_contains "$B_OUT" "Read-only: yes" "B5: read-only yes"
assert_contains "$B_OUT" "Mutation allowed: no" "B6: mutation no"
assert_contains "$B_OUT" "Token printed: no" "B7: token printed no"
assert_contains "$B_OUT" "Credential path printed: no" "B8: cred path no"
assert_contains "$B_OUT" "Zone IDs printed: no" "B9: zone ids no"

assert_not_contains "$B_OUT" "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "B10: no token value"
assert_not_contains "$B_OUT" "safe_credential.env" "B11: no credential path"
assert_not_contains "$B_OUT" "fake-zone-id" "B12: no zone id"
assert_not_contains "$B_OUT" "CF_API_TOKEN" "B13: no CF_API_TOKEN"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Empty zones
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Empty zones ---"
echo ""

C_OUT=$(NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/cf_zones_empty.json" \
  python3 "$MODULE" list --api-env "$FIXTURES/safe_credential.env" 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: empty zones exits 0"
else
  fail "C1: empty zones should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_OUT" "Count: 0" "C2: count is 0"
assert_contains "$C_OUT" "No zones found" "C3: friendly message"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Missing credential
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Missing credential ---"
echo ""

D_OUT=$(NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/cf_zones_success_two.json" \
  python3 "$MODULE" list 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" != "0" ]]; then
  pass "D1: missing credential exits non-zero ($D_RC)"
else
  fail "D1: missing credential should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_OUT" "api-env is required" "D2: api-env required message"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Missing credential file
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Missing credential file ---"
echo ""

E_OUT=$(NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/cf_zones_success_two.json" \
  python3 "$MODULE" list --api-env "/nonexistent/path.env" 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" != "0" ]]; then
  pass "E1: missing file exits non-zero ($E_RC)"
else
  fail "E1: missing file should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_OUT" "not found" "E2: not found message"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Unsafe credential permission (0644)
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Unsafe credential permission ---"
echo ""

chmod 644 "$FIXTURES/unsafe_world_readable_credential.env"
UNSAFE_MODE=$(nanobk_test_file_mode "$FIXTURES/unsafe_world_readable_credential.env")
if [[ "$UNSAFE_MODE" != "644" ]]; then
  fail "F-pre: unsafe credential should be 644, got $UNSAFE_MODE"
  ERRORS=$((ERRORS + 1))
fi

F_OUT=$(NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/cf_zones_success_two.json" \
  python3 "$MODULE" list --api-env "$FIXTURES/unsafe_world_readable_credential.env" 2>&1) && F_RC=0 || F_RC=$?

if [[ "$F_RC" != "0" ]]; then
  pass "F1: unsafe credential exits non-zero ($F_RC)"
else
  fail "F1: unsafe credential should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$F_OUT" "Insecure file permissions" "F2: insecure permissions message"
assert_not_contains "$F_OUT" "example.com" "F3: no zone output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Malformed response (API error)
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Malformed response ---"
echo ""

G_OUT=$(NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/cf_zones_malformed.json" \
  python3 "$MODULE" list --api-env "$FIXTURES/safe_credential.env" 2>&1) && G_RC=0 || G_RC=$?

if [[ "$G_RC" != "0" ]]; then
  pass "G1: malformed response exits non-zero ($G_RC)"
else
  fail "G1: malformed response should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$G_OUT" "Authentication error" "G2: error message"
assert_not_contains "$G_OUT" "example.com" "G3: no zone output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. Mutation method blocked (verify module has no POST/PATCH/PUT/DELETE)
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. Mutation method blocked ---"
echo ""

H_SRC=$(cat "$MODULE")
for method in "POST" "PATCH" "PUT" "DELETE"; do
  if echo "$H_SRC" | grep -q "\"$method\"" || echo "$H_SRC" | grep -q "method=\"$method\""; then
    fail "H: module contains $method method reference"
    ERRORS=$((ERRORS + 1))
  else
    pass "H: no $method method in module"
  fi
done

# Also verify only GET is used
if echo "$H_SRC" | grep -q 'method="GET"'; then
  pass "H: module uses GET method only"
else
  fail "H: module should use GET method"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# I. Token/path redaction in all outputs
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. Token/path redaction ---"
echo ""

ALL_OUTPUTS="$B_OUT $C_OUT $D_OUT $E_OUT $F_OUT $G_OUT"

assert_not_contains "$ALL_OUTPUTS" "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "I1: no token value"
assert_not_contains "$ALL_OUTPUTS" "safe_credential.env" "I2: no safe credential path"
assert_not_contains "$ALL_OUTPUTS" "unsafe_world_readable_credential.env" "I3: no unsafe credential path"
assert_not_contains "$ALL_OUTPUTS" "CF_API_TOKEN=" "I4: no CF_API_TOKEN assignment"

if echo "$ALL_OUTPUTS" | grep -qE '[a-f0-9]{64}'; then
  fail "I5: no 64-char hex"
  ERRORS=$((ERRORS + 1))
else
  pass "I5: no 64-char hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. JSON output mode
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. JSON output mode ---"
echo ""

J_OUT=$(NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/cf_zones_success_two.json" \
  python3 "$MODULE" list --api-env "$FIXTURES/safe_credential.env" --json 2>&1) && J_RC=0 || J_RC=$?

if [[ "$J_RC" == "0" ]]; then
  pass "J1: JSON mode exits 0"
else
  fail "J1: JSON mode should exit 0, got $J_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$J_OUT" '"ok": true' "J2: JSON ok true"
assert_contains "$J_OUT" '"count": 2' "J3: JSON count 2"
assert_contains "$J_OUT" '"mutation": false' "J4: JSON mutation false"

assert_not_contains "$J_OUT" "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "J5: no token in JSON"
assert_not_contains "$J_OUT" "safe_credential.env" "J6: no cred path in JSON"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. CLI integration via nanobk cf zones list
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. CLI integration ---"
echo ""

K_OUT=$(NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/cf_zones_success_two.json" \
  "$ROOT/bin/nanobk" cf zones list --api-env "$FIXTURES/safe_credential.env" 2>&1) && K_RC=0 || K_RC=$?

if [[ "$K_RC" == "0" ]]; then
  pass "K1: CLI exits 0"
else
  fail "K1: CLI should exit 0, got $K_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$K_OUT" "example.com" "K2: CLI shows example.com"
assert_contains "$K_OUT" "example.net" "K3: CLI shows example.net"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. Safety scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. Safety scan ---"
echo ""

ALL_OUTPUTS="$B_OUT $C_OUT $F_OUT $G_OUT $J_OUT $K_OUT"

assert_not_contains "$ALL_OUTPUTS" "DUMMY_PLACEHOLDER_NOT_A_REAL_TOKEN" "L1: no token"
assert_not_contains "$ALL_OUTPUTS" "CLOUDFLARE_API_TOKEN" "L2: no CLOUDFLARE_API_TOKEN"
assert_not_contains "$ALL_OUTPUTS" "Authorization" "L3: no Authorization"
assert_not_contains "$ALL_OUTPUTS" "Bearer" "L4: no Bearer"
assert_not_contains "$ALL_OUTPUTS" "safe_credential.env" "L5: no credential path"
assert_not_contains "$ALL_OUTPUTS" "fake-zone-id" "L6: no zone id"
assert_not_contains "$ALL_OUTPUTS" "api.cloudflare.com" "L7: no API URL"
assert_not_contains "$ALL_OUTPUTS" "workers.dev" "L8: no workers.dev"
assert_not_contains "$ALL_OUTPUTS" "PRIVATE KEY" "L9: no PRIVATE KEY"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.40 Cloudflare Zone Discovery Read-only tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
