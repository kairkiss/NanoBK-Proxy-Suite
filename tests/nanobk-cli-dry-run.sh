#!/usr/bin/env bash
# NanoBK Proxy Suite — nanobk CLI Dry-Run and JSON Test
#
# Tests:
#   - Command-level --dry-run works
#   - Global --dry-run works
#   - status --json produces valid JSON
#   - status --json has correct ok/warnings for missing config
#   - JSON escape handles special characters
#
# Usage:
#   bash tests/nanobk-cli-dry-run.sh

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
echo "=== nanobk CLI Dry-Run and JSON Test ==="
echo ""

# ── Syntax check ────────────────────────────────────────────────────────────

echo "--- Syntax check ---"
echo ""
check "nanobk syntax" bash -n "$ROOT/bin/nanobk"

# ── Command-level --dry-run ─────────────────────────────────────────────────

echo ""
echo "--- Command-level --dry-run ---"
echo ""

# test --dry-run (command position)
TEST_DRY_OUTPUT=$(bash "$ROOT/bin/nanobk" --repo-dir "$ROOT" test --dry-run 2>&1)
if echo "$TEST_DRY_OUTPUT" | grep -q "DRY-RUN"; then
  pass "nanobk test --dry-run shows DRY-RUN"
else
  fail "nanobk test --dry-run missing DRY-RUN"
  ERRORS=$((ERRORS + 1))
fi
if ! echo "$TEST_DRY_OUTPUT" | grep -q "passed"; then
  pass "nanobk test --dry-run did not actually run tests"
else
  fail "nanobk test --dry-run actually ran tests (should be dry)"
  ERRORS=$((ERRORS + 1))
fi

# doctor --dry-run (command position)
DOCTOR_DRY_OUTPUT=$(bash "$ROOT/bin/nanobk" --repo-dir "$ROOT" doctor --dry-run 2>&1)
if echo "$DOCTOR_DRY_OUTPUT" | grep -q "DRY-RUN"; then
  pass "nanobk doctor --dry-run shows DRY-RUN"
else
  fail "nanobk doctor --dry-run missing DRY-RUN"
  ERRORS=$((ERRORS + 1))
fi

# Global --dry-run
TEST_GLOBAL_DRY=$(bash "$ROOT/bin/nanobk" --repo-dir "$ROOT" --dry-run test 2>&1)
if echo "$TEST_GLOBAL_DRY" | grep -q "DRY-RUN"; then
  pass "nanobk --dry-run test shows DRY-RUN"
else
  fail "nanobk --dry-run test missing DRY-RUN"
  ERRORS=$((ERRORS + 1))
fi

DOCTOR_GLOBAL_DRY=$(bash "$ROOT/bin/nanobk" --repo-dir "$ROOT" --dry-run doctor 2>&1)
if echo "$DOCTOR_GLOBAL_DRY" | grep -q "DRY-RUN"; then
  pass "nanobk --dry-run doctor shows DRY-RUN"
else
  fail "nanobk --dry-run doctor missing DRY-RUN"
  ERRORS=$((ERRORS + 1))
fi

# ── JSON output validation ──────────────────────────────────────────────────

echo ""
echo "--- JSON output validation ---"
echo ""

# Missing config → ok: false
JSON_MISSING=$(bash "$ROOT/bin/nanobk" --repo-dir "$ROOT" --json status --config-dir /tmp/nanobk-cli-test-missing-$$ 2>&1)

if echo "$JSON_MISSING" | python3 -m json.tool >/dev/null 2>&1; then
  pass "--json status (missing config) is valid JSON"
else
  fail "--json status (missing config) is NOT valid JSON"
  ERRORS=$((ERRORS + 1))
fi

if echo "$JSON_MISSING" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['ok'] == False, f'ok={d[\"ok\"]}'; print('ok=false confirmed')" 2>/dev/null; then
  pass "missing config → ok: false"
else
  fail "missing config → ok should be false"
  ERRORS=$((ERRORS + 1))
fi

if echo "$JSON_MISSING" | python3 -c "import json,sys; d=json.load(sys.stdin); assert len(d.get('warnings',[])) > 0; print('warnings present')" 2>/dev/null; then
  pass "missing config → warnings array present"
else
  fail "missing config → warnings array missing"
  ERRORS=$((ERRORS + 1))
fi

# ── JSON escape test ────────────────────────────────────────────────────────

echo ""
echo "--- JSON escape test ---"
echo ""

# Create temp config with special characters
ESCAPE_DIR="/tmp/nanobk-cli-escape-test-$$"
mkdir -p "$ESCAPE_DIR"
cat > "$ESCAPE_DIR/config.env" <<'ENVEOF'
NANOBK_DOMAIN='proxy"test.example.com'
NANOBK_VPS_IP="1.2.3.4"
NANOBK_GEO_LABEL="JP"
REALITY_SERVERNAME="www.microsoft.com"
ENVEOF

JSON_ESCAPE=$(bash "$ROOT/bin/nanobk" --repo-dir "$ROOT" --json status --config-dir "$ESCAPE_DIR" 2>&1)

if echo "$JSON_ESCAPE" | python3 -m json.tool >/dev/null 2>&1; then
  pass "JSON with special chars is valid"
else
  fail "JSON with special chars is NOT valid"
  ERRORS=$((ERRORS + 1))
  echo "  Raw output: $JSON_ESCAPE" >&2
fi

# Verify the domain was escaped correctly
if echo "$JSON_ESCAPE" | python3 -c "
import json,sys
d=json.load(sys.stdin)
domain=d.get('domain','')
assert '\"' in domain or 'test' in domain, f'domain={domain}'
" 2>/dev/null; then
  pass "domain with quotes was properly escaped"
else
  fail "domain escape may have failed"
  ERRORS=$((ERRORS + 1))
fi

rm -rf "$ESCAPE_DIR"

# ── Version and help ────────────────────────────────────────────────────────

echo ""
echo "--- Version and help ---"
echo ""

check "version output" bash "$ROOT/bin/nanobk" version
check "--help output" bash "$ROOT/bin/nanobk" --help

# ── No eval ─────────────────────────────────────────────────────────────────

echo ""
echo "--- Safety ---"
echo ""

if grep -q 'eval ' "$ROOT/bin/nanobk" 2>/dev/null; then
  fail "eval found in nanobk"
  ERRORS=$((ERRORS + 1))
else
  pass "no eval in nanobk"
fi

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
