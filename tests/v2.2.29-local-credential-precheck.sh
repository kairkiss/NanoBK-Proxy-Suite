#!/usr/bin/env bash
# NanoBK Proxy Suite — Local Credential Precheck Test
#
# Tests real local credential reference metadata checks in the dryrun wrapper.
# Does NOT read credential contents. Does NOT print credential paths.
# Does NOT call Cloudflare. Does NOT mutate DNS.
#
# Usage:
#   bash tests/v2.2.29-local-credential-precheck.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/dev/nanobk-cf-dns-dryrun-wrapper"
FIXTURES="$ROOT/tests/fixtures/v2.2.29"

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

echo ""
echo "=== Local Credential Precheck Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Runner exists and executable
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Runner file checks ---"
echo ""

if [[ -x "$RUNNER" ]]; then
  pass "A1: runner exists and executable"
else
  fail "A1: runner does NOT exist or is NOT executable"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Permission setup
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Permission setup ---"
echo ""

chmod 600 "$FIXTURES/safe_dummy_credential.env"
chmod 644 "$FIXTURES/unsafe_world_readable_credential.env"

# Portable file mode helper: GNU stat -c works on Linux, BSD stat -f on macOS.
# Try GNU first (clean error on BSD), then fall back to BSD.
nanobk_test_file_mode() {
  if stat -c '%a' "$1" 2>/dev/null; then
    return 0
  fi
  stat -f '%Lp' "$1"
}

SAFE_MODE=$(nanobk_test_file_mode "$FIXTURES/safe_dummy_credential.env")
UNSAFE_MODE=$(nanobk_test_file_mode "$FIXTURES/unsafe_world_readable_credential.env")

if [[ "$SAFE_MODE" == "600" ]]; then
  pass "B1: safe credential is 600"
else
  fail "B1: safe credential should be 600, got $SAFE_MODE"
  ERRORS=$((ERRORS + 1))
fi

if [[ "$UNSAFE_MODE" == "644" ]]; then
  pass "B2: unsafe credential is 644"
else
  fail "B2: unsafe credential should be 644, got $UNSAFE_MODE"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Valid credential reference
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Valid credential reference ---"
echo ""

C_OUT=$("$RUNNER" --plan "$FIXTURES/runner_valid_local_credential_reference.json" 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" == "0" ]]; then
  pass "C1: valid credential exits 0"
else
  fail "C1: valid credential should exit 0, got $C_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_OUT" "Status: dryrun_preview_ready" "C2: dryrun_preview_ready"
assert_contains "$C_OUT" "Credential reference present: yes" "C3: credential present"
assert_contains "$C_OUT" "Credential is regular file: yes" "C4: is regular file"
assert_contains "$C_OUT" "Credential permission restricted: yes" "C5: permission restricted"
assert_contains "$C_OUT" "Credential contents read: no" "C6: contents not read"
assert_contains "$C_OUT" "Credential path printed: no" "C7: path not printed"
assert_contains "$C_OUT" "Can apply: no" "C8: can apply no"
assert_contains "$C_OUT" "Mutation allowed: no" "C9: mutation allowed no"
assert_contains "$C_OUT" "Public apply allowed: no" "C10: public apply no"

assert_not_contains "$C_OUT" "safe_dummy_credential.env" "C11: no credential path in output"
assert_not_contains "$C_OUT" "DUMMY_PLACEHOLDER_ONLY" "C12: no credential content in output"
assert_not_contains "$C_OUT" "tests/fixtures" "C13: no fixtures path in output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Missing credential reference
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Missing credential reference ---"
echo ""

D_OUT=$("$RUNNER" --plan "$FIXTURES/runner_blocked_missing_credential_reference.json" 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" == "2" ]]; then
  pass "D1: missing credential exits 2"
else
  fail "D1: missing credential should exit 2, got $D_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_OUT" "Status: blocked" "D2: blocked status"
assert_contains "$D_OUT" "First failed gate: credential_reference_gate" "D3: first failed gate"
assert_contains "$D_OUT" "credential reference missing" "D4: credential reference missing reason"
assert_contains "$D_OUT" "Credential reference present: no" "D5: credential not present"
assert_contains "$D_OUT" "Can apply: no" "D6: can apply no"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Unsafe permission
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Unsafe permission ---"
echo ""

E_OUT=$("$RUNNER" --plan "$FIXTURES/runner_blocked_unsafe_permission.json" 2>&1) && E_RC=0 || E_RC=$?

if [[ "$E_RC" == "2" ]]; then
  pass "E1: unsafe permission exits 2"
else
  fail "E1: unsafe permission should exit 2, got $E_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$E_OUT" "Status: blocked" "E2: blocked status"
assert_contains "$E_OUT" "First failed gate: credential_reference_gate" "E3: first failed gate"
assert_contains "$E_OUT" "credential permission not restricted" "E4: permission not restricted reason"
assert_contains "$E_OUT" "Credential permission restricted: no" "E5: permission restricted no"
assert_contains "$E_OUT" "Can apply: no" "E6: can apply no"

assert_not_contains "$E_OUT" "unsafe_world_readable_credential.env" "E7: no unsafe path in output"
assert_not_contains "$E_OUT" "tests/fixtures" "E8: no fixtures path in output"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Compatibility with v2.2.27 and v2.2.28 fixtures
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Compatibility ---"
echo ""

F1_OUT=$("$RUNNER" --plan "$ROOT/tests/fixtures/v2.2.28/runner_valid_plan.json" 2>&1) && F1_RC=0 || F1_RC=$?
if [[ "$F1_RC" == "0" ]]; then
  pass "F1: v2.2.28 valid plan still exits 0"
else
  fail "F1: v2.2.28 valid plan should exit 0, got $F1_RC"
  ERRORS=$((ERRORS + 1))
fi

F2_OUT=$("$RUNNER" --plan "$ROOT/tests/fixtures/v2.2.27/dryrun_preview_ready.json" 2>&1) && F2_RC=0 || F2_RC=$?
if [[ "$F2_RC" == "0" ]]; then
  pass "F2: v2.2.27 valid plan still exits 0"
else
  fail "F2: v2.2.27 valid plan should exit 0, got $F2_RC"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Safety scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Safety scan ---"
echo ""

ALL_OUTPUTS="$C_OUT $D_OUT $E_OUT $F1_OUT $F2_OUT"

assert_not_contains "$ALL_OUTPUTS" "example.com" "G1: no example.com"
assert_not_contains "$ALL_OUTPUTS" "203.0.113" "G2: no IPv4"
assert_not_contains "$ALL_OUTPUTS" "2001:db8" "G3: no IPv6"
assert_not_contains "$ALL_OUTPUTS" "recordId" "G4: no recordId"
assert_not_contains "$ALL_OUTPUTS" "Zone ID" "G5: no Zone ID"
assert_not_contains "$ALL_OUTPUTS" "Account ID" "G6: no Account ID"
assert_not_contains "$ALL_OUTPUTS" "Authorization" "G7: no Authorization"
assert_not_contains "$ALL_OUTPUTS" "CF_API_TOKEN" "G8: no CF_API_TOKEN"
assert_not_contains "$ALL_OUTPUTS" "workers.dev" "G9: no workers.dev"
assert_not_contains "$ALL_OUTPUTS" "vless://" "G10: no vless://"
assert_not_contains "$ALL_OUTPUTS" "PRIVATE KEY" "G11: no PRIVATE KEY"
assert_not_contains "$ALL_OUTPUTS" "apply --yes" "G12: no apply --yes"
assert_not_contains "$ALL_OUTPUTS" "DUMMY_PLACEHOLDER_ONLY" "G13: no dummy credential content"
assert_not_contains "$ALL_OUTPUTS" "safe_dummy_credential.env" "G14: no safe credential path"
assert_not_contains "$ALL_OUTPUTS" "unsafe_world_readable_credential.env" "G15: no unsafe credential path"

if echo "$ALL_OUTPUTS" | grep -qE '[a-f0-9]{64}'; then
  fail "G16: no 64-char hex"
  ERRORS=$((ERRORS + 1))
else
  pass "G16: no 64-char hex"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# H. No public references
# ══════════════════════════════════════════════════════════════════════════════

echo "--- H. No public references ---"
echo ""

for loc in "$ROOT/bin/nanobk" "$ROOT/installer" "$ROOT/bot" "$ROOT/web"; do
  if [[ -e "$loc" ]] && grep -rq 'nanobk-cf-dns-dryrun-wrapper\|nanobk_cf_dns_apply_dryrun_wrapper' "$loc" 2>/dev/null; then
    fail "H1: $loc references runner/module"
    ERRORS=$((ERRORS + 1))
  fi
done
pass "H1: no references in bin/installer/bot/web"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.29 Local Credential Precheck tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
