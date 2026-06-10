#!/usr/bin/env bash
# NanoBK Proxy Suite — Local Dry-run Runner Test
#
# Tests scripts/dev/nanobk-cf-dns-dryrun-wrapper with safe plan files.
# Does NOT call Cloudflare. Does NOT mutate DNS.
#
# Usage:
#   bash tests/v2.2.28-local-dryrun-runner.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/dev/nanobk-cf-dns-dryrun-wrapper"
FIXTURES="$ROOT/tests/fixtures/v2.2.28"
V227_FIXTURES="$ROOT/tests/fixtures/v2.2.27"

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
echo "=== Local Dry-run Runner Test ==="
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# A. Runner file exists and executable
# ══════════════════════════════════════════════════════════════════════════════

echo "--- A. Runner file checks ---"
echo ""

if [[ -f "$RUNNER" ]]; then
  pass "A1: runner file exists"
else
  fail "A1: runner file does NOT exist"
  ERRORS=$((ERRORS + 1))
fi

if [[ -x "$RUNNER" ]]; then
  pass "A2: runner is executable"
else
  fail "A2: runner is NOT executable"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# B. Valid plan exits 0
# ══════════════════════════════════════════════════════════════════════════════

echo "--- B. Valid plan exits 0 ---"
echo ""

B_OUT=$("$RUNNER" --plan "$FIXTURES/runner_valid_plan.json" 2>&1) && B_RC=0 || B_RC=$?

if [[ "$B_RC" == "0" ]]; then
  pass "B1: valid plan exits 0"
else
  fail "B1: valid plan should exit 0, got $B_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$B_OUT" "NanoBK DNS Apply — Non-Public Dry-run Wrapper Summary" "B2: has summary header"
assert_contains "$B_OUT" "Status: dryrun_preview_ready" "B3: has dryrun_preview_ready status"
assert_contains "$B_OUT" "Can preview: yes" "B4: can preview yes"
assert_contains "$B_OUT" "Can apply: no" "B5: can apply no"
assert_contains "$B_OUT" "Mutation allowed: no" "B6: mutation allowed no"
assert_contains "$B_OUT" "Public apply allowed: no" "B7: public apply no"
assert_contains "$B_OUT" "Live Cloudflare called: no" "B8: live CF no"
assert_contains "$B_OUT" "Real DNS mutation performed: no" "B9: real mutation no"
assert_contains "$B_OUT" "Dry-run preview is ready" "B10: preview ready message"
assert_contains "$B_OUT" "This is not a live mutation" "B11: not live mutation"
assert_contains "$B_OUT" "No DNS record was created" "B12: no DNS created"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# C. Blocked plan exits non-zero
# ══════════════════════════════════════════════════════════════════════════════

echo "--- C. Blocked plan exits non-zero ---"
echo ""

C_OUT=$("$RUNNER" --plan "$FIXTURES/runner_blocked_plan.json" 2>&1) && C_RC=0 || C_RC=$?

if [[ "$C_RC" != "0" ]]; then
  pass "C1: blocked plan exits non-zero ($C_RC)"
else
  fail "C1: blocked plan should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$C_OUT" "Status: blocked" "C2: blocked status"
assert_contains "$C_OUT" "First failed gate:" "C3: has first failed gate"
assert_contains "$C_OUT" "First blocked reason:" "C4: has first blocked reason"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# D. Uncertain plan exits non-zero
# ══════════════════════════════════════════════════════════════════════════════

echo "--- D. Uncertain plan exits non-zero ---"
echo ""

D_OUT=$("$RUNNER" --plan "$FIXTURES/runner_uncertain_plan.json" 2>&1) && D_RC=0 || D_RC=$?

if [[ "$D_RC" != "0" ]]; then
  pass "D1: uncertain plan exits non-zero ($D_RC)"
else
  fail "D1: uncertain plan should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$D_OUT" "Status: uncertain" "D2: uncertain status"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# E. Malformed JSON exits non-zero with safe error
# ══════════════════════════════════════════════════════════════════════════════

echo "--- E. Malformed JSON exits non-zero ---"
echo ""

E_STDERR=$("$RUNNER" --plan "$FIXTURES/runner_malformed.json" 2>&1 1>/dev/null) && E_RC=0 || E_RC=$?

if [[ "$E_RC" != "0" ]]; then
  pass "E1: malformed JSON exits non-zero ($E_RC)"
else
  fail "E1: malformed JSON should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

assert_not_contains "$E_STDERR" "Traceback" "E2: no traceback in stderr"
assert_not_contains "$E_STDERR" "example.com" "E3: no raw values in error"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# F. Missing --plan exits non-zero with safe usage
# ══════════════════════════════════════════════════════════════════════════════

echo "--- F. Missing --plan exits non-zero ---"
echo ""

F_STDERR=$("$RUNNER" 2>&1 1>/dev/null) && F_RC=0 || F_RC=$?

if [[ "$F_RC" == "4" ]]; then
  pass "F1: missing --plan exits 4"
else
  fail "F1: missing --plan should exit 4, got $F_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$F_STDERR" "--plan is required" "F2: says --plan is required"
assert_contains "$F_STDERR" "--plan PATH" "F3: shows --plan PATH in usage"
assert_not_contains "$F_STDERR" "Traceback" "F4: no traceback in missing --plan error"

# F5-F6. --help exits 0 with usage
HELP_OUT=$("$RUNNER" --help 2>&1) && HELP_RC=0 || HELP_RC=$?

if [[ "$HELP_RC" == "0" ]]; then
  pass "F5: --help exits 0"
else
  fail "F5: --help should exit 0, got $HELP_RC"
  ERRORS=$((ERRORS + 1))
fi

assert_contains "$HELP_OUT" "--plan PATH" "F6: --help shows --plan PATH"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# G. Output safety scan
# ══════════════════════════════════════════════════════════════════════════════

echo "--- G. Output safety scan ---"
echo ""

for fixture_file in "$FIXTURES"/*.json; do
  fname=$(basename "$fixture_file")
  if [[ "$fname" == "runner_malformed.json" ]]; then
    continue
  fi
  out=$("$RUNNER" --plan "$fixture_file" 2>&1) || true

  assert_not_contains "$out" "example.com" "G: $fname no example.com"
  assert_not_contains "$out" "203.0.113" "G: $fname no IPv4"
  assert_not_contains "$out" "2001:db8" "G: $fname no IPv6"
  assert_not_contains "$out" "recordId" "G: $fname no recordId"
  assert_not_contains "$out" "Zone ID" "G: $fname no Zone ID"
  assert_not_contains "$out" "Account ID" "G: $fname no Account ID"
  assert_not_contains "$out" "Authorization" "G: $fname no Authorization"
  assert_not_contains "$out" "CF_API_TOKEN" "G: $fname no token"
  assert_not_contains "$out" "workers.dev" "G: $fname no workers.dev"
  assert_not_contains "$out" "vless://" "G: $fname no vless://"
  assert_not_contains "$out" "PRIVATE KEY" "G: $fname no PRIVATE KEY"
  assert_not_contains "$out" "apply --yes" "G: $fname no apply --yes"

  if echo "$out" | grep -qE '[a-f0-9]{64}'; then
    fail "G: $fname has 64-char hex"
    ERRORS=$((ERRORS + 1))
  else
    pass "G: $fname no 64-char hex"
  fi
done

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
# I. No live mutation flags
# ══════════════════════════════════════════════════════════════════════════════

echo "--- I. No live mutation flags ---"
echo ""

RUNNER_SOURCE=$(cat "$RUNNER")
assert_not_contains "$RUNNER_SOURCE" "--yes" "I1: no --yes in runner"
assert_not_contains "$RUNNER_SOURCE" "mutation_allowed=yes" "I2: no mutation allowed yes"
assert_not_contains "$RUNNER_SOURCE" "public_apply_allowed=yes" "I3: no public apply allowed yes"
assert_not_contains "$RUNNER_SOURCE" "live mutation enabled" "I4: no live mutation enabled"
assert_not_contains "$RUNNER_SOURCE" "create/update/delete real DNS" "I5: no create/update/delete real DNS wording"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# J. No raw helper stdout/stderr printed
# ══════════════════════════════════════════════════════════════════════════════

echo "--- J. No raw helper output ---"
echo ""

J_OUT=$("$RUNNER" --plan "$FIXTURES/runner_valid_plan.json" 2>&1) || true
assert_not_contains "$J_OUT" "Traceback" "J1: no traceback"
assert_not_contains "$J_OUT" "Error:" "J2: no error text in valid output"
assert_not_contains "$J_OUT" "{\"ok\":" "J3: no raw JSON"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# K. Also works with v2.2.27 fixtures
# ══════════════════════════════════════════════════════════════════════════════

echo "--- K. v2.2.27 fixture compatibility ---"
echo ""

K_OUT=$("$RUNNER" --plan "$V227_FIXTURES/dryrun_preview_ready.json" 2>&1) && K_RC=0 || K_RC=$?
if [[ "$K_RC" == "0" ]]; then
  pass "K1: v2.2.27 dryrun_preview_ready exits 0"
else
  fail "K1: v2.2.27 dryrun_preview_ready should exit 0, got $K_RC"
  ERRORS=$((ERRORS + 1))
fi
assert_contains "$K_OUT" "Status: dryrun_preview_ready" "K2: v2.2.27 has correct status"

K2_OUT=$("$RUNNER" --plan "$V227_FIXTURES/blocked_repo_gate.json" 2>&1) && K2_RC=0 || K2_RC=$?
if [[ "$K2_RC" != "0" ]]; then
  pass "K3: v2.2.27 blocked_repo_gate exits non-zero ($K2_RC)"
else
  fail "K3: v2.2.27 blocked_repo_gate should exit non-zero"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# L. Existing v2.2.27 test still passes
# ══════════════════════════════════════════════════════════════════════════════

echo "--- L. Existing tests ---"
echo ""

if bash "$ROOT/tests/v2.2.27-dns-apply-dryrun-wrapper.sh" > /dev/null 2>&1; then
  pass "L1: v2.2.27 test passes"
else
  fail "L1: v2.2.27 test fails"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.2.28 Local Dry-run Runner tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
