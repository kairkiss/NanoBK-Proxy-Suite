#!/usr/bin/env bash
# NanoBK Proxy Suite — Stable Closeout Test (v1.9.60)
#
# Verifies that v1.9 stable closeout checkpoint docs exist and
# contain required safety guidance. Does NOT create a tag.
#
# Usage:
#   bash tests/stable-closeout-v1.9.60.sh

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
  local file="$1"
  local needle="$2"
  local desc="$3"
  if grep -q "$needle" "$file" 2>/dev/null; then
    pass "$desc"
  else
    fail "$desc (expected '$needle' in $file)"
    ERRORS=$((ERRORS + 1))
  fi
}

echo ""
echo "=== Stable Closeout Test (v1.9.60) ==="
echo ""

# ── 1. Required documents exist ───────────────────────────────────────────

echo "--- Required documents exist ---"
echo ""

check "docs/stable-tag-gate-v1.9.md exists" test -f "$ROOT/docs/stable-tag-gate-v1.9.md"
check "docs/validation-v1.9.60-stable-closeout-checkpoint.md exists" test -f "$ROOT/docs/validation-v1.9.60-stable-closeout-checkpoint.md"
check "docs/maintenance-map.md exists" test -f "$ROOT/docs/maintenance-map.md"
check "docs/ai-handoff-template.md exists" test -f "$ROOT/docs/ai-handoff-template.md"

echo ""

# ── 2. Version display ───────────────────────────────────────────────────

echo "--- Version display ---"
echo ""

VERSION_OUTPUT=$(bash "$ROOT/bin/nanobk" --version 2>&1)
check "bin/nanobk --version works" test -n "$VERSION_OUTPUT"
assert_contains <(echo "$VERSION_OUTPUT") "1.9.58" "version shows 1.9.58"
assert_contains <(echo "$VERSION_OUTPUT") "nanobk" "version shows nanobk"

echo ""

# ── 3. Stable gate: no tag yet ────────────────────────────────────────────

echo "--- Stable gate: no tag created ---"
echo ""

GATE="$ROOT/docs/stable-tag-gate-v1.9.md"

assert_contains "$GATE" "No stable tag\|not yet created\|NOT yet created\|not.*tag" "gate says no tag yet"
assert_contains "$GATE" "user approval\|User approval" "gate requires user approval"

echo ""

# ── 4. Closeout checkpoint content ────────────────────────────────────────

echo "--- Closeout checkpoint content ---"
echo ""

CHECKPOINT="$ROOT/docs/validation-v1.9.60-stable-closeout-checkpoint.md"

assert_contains "$CHECKPOINT" "READY FOR USER-APPROVED STABLE TAG" "checkpoint says READY"
assert_contains "$CHECKPOINT" "v1.7.27" "mentions protected baseline"
assert_contains "$CHECKPOINT" "v1.9.58" "mentions version display"
assert_contains "$CHECKPOINT" "user approval\|用户.*批准" "mentions user approval"
assert_contains "$CHECKPOINT" "v1.9.60\|tag" "mentions tag recommendation"

echo ""

# ── 5. Safety: no env cat ─────────────────────────────────────────────────

echo "--- Safety: no env cat instructions ---"
echo ""

assert_contains "$CHECKPOINT" "不读\|不能读\|Never\|no env\|env 文件" "checkpoint mentions env safety"

echo ""

# ── 6. Safety: no tag as executed ─────────────────────────────────────────

echo "--- Safety: no tag command as executed ---"
echo ""

# The checkpoint should recommend a tag but NOT claim it was executed
# Check that "git tag" is not presented as an executed instruction
if grep -q "git tag.*v1.9.60" "$CHECKPOINT" 2>/dev/null; then
  # It's OK to mention the tag name, but not as an executed command
  if grep -q "^\$\|已执行\|已创建\|tag created\|tagged" "$CHECKPOINT" 2>/dev/null; then
    fail "checkpoint claims tag was executed"
    ERRORS=$((ERRORS + 1))
  else
    pass "checkpoint mentions tag name but does not claim execution"
  fi
else
  pass "checkpoint does not contain git tag command"
fi

echo ""

# ── 7. Maintenance docs safety ────────────────────────────────────────────

echo "--- Maintenance docs safety ---"
echo ""

MAP="$ROOT/docs/maintenance-map.md"

assert_contains "$MAP" "cat bot/.env\|Never.*env\|不读" "maintenance map mentions no env cat"
assert_contains "$MAP" "tag/release\|No tag\|Never.*tag\|不.*tag" "maintenance map mentions no tag without approval"

echo ""

# ── Summary ───────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All stable closeout tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
