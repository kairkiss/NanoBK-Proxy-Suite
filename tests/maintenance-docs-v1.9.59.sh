#!/usr/bin/env bash
# NanoBK Proxy Suite — Maintenance Docs Test (v1.9.59)
#
# Verifies that maintenance documentation exists and contains
# required safety guidance for future no-memory AI agents.
#
# Usage:
#   bash tests/maintenance-docs-v1.9.59.sh

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
echo "=== Maintenance Docs Test (v1.9.59) ==="
echo ""

# ── 1. Document existence ─────────────────────────────────────────────────

echo "--- Document existence ---"
echo ""

check "docs/maintenance-map.md exists" test -f "$ROOT/docs/maintenance-map.md"
check "docs/ai-handoff-template.md exists" test -f "$ROOT/docs/ai-handoff-template.md"
check "docs/stable-tag-gate-v1.9.md exists" test -f "$ROOT/docs/stable-tag-gate-v1.9.md"

echo ""

# ── 2. Maintenance map content ────────────────────────────────────────────

echo "--- Maintenance map: protected areas ---"
echo ""

MAP="$ROOT/docs/maintenance-map.md"

assert_contains "$MAP" "installer/install.sh" "mentions protected installer/install.sh"
assert_contains "$MAP" "vps/scripts" "mentions protected VPS scripts"
assert_contains "$MAP" "cloudflare" "mentions protected Cloudflare"
assert_contains "$MAP" "lib/nanobk_redaction.py" "mentions protected redaction"
assert_contains "$MAP" "bin/nanobk" "mentions CLI"

echo ""

# ── 3. Safety rules ───────────────────────────────────────────────────────

echo "--- Maintenance map: safety rules ---"
echo ""

assert_contains "$MAP" "cat bot/.env\|cat web/.env\|Never.*env" "mentions no env cat"
assert_contains "$MAP" "tag/release\|No tag\|Never.*tag" "mentions no tag/release without approval"
assert_contains "$MAP" "Bot.*Web.*must not\|Never directly" "mentions Bot/Web must not write configs directly"
assert_contains "$MAP" "test matrix\|Required tests\|Standard test" "mentions required test matrix"
assert_contains "$MAP" "redact\|Redact" "mentions redaction contract"

echo ""

# ── 4. Subsystem map ──────────────────────────────────────────────────────

echo "--- Maintenance map: subsystem coverage ---"
echo ""

assert_contains "$MAP" "Installer\|Full Wizard" "covers Installer subsystem"
assert_contains "$MAP" "CLI\|bin/nanobk" "covers CLI subsystem"
assert_contains "$MAP" "Telegram Bot\|Bot" "covers Bot subsystem"
assert_contains "$MAP" "Web Panel\|Web" "covers Web subsystem"
assert_contains "$MAP" "i18n" "covers i18n subsystem"
assert_contains "$MAP" "Doctor\|doctor" "covers Doctor subsystem"
assert_contains "$MAP" "Rotate\|rotate" "covers Rotate subsystem"

echo ""

# ── 5. Handoff template ───────────────────────────────────────────────────

echo "--- AI handoff template ---"
echo ""

TEMPLATE="$ROOT/docs/ai-handoff-template.md"

assert_contains "$TEMPLATE" "Current base commit" "has base commit field"
assert_contains "$TEMPLATE" "Scope" "has scope field"
assert_contains "$TEMPLATE" "Protected files" "has protected files field"
assert_contains "$TEMPLATE" "Required tests" "has required tests field"
assert_contains "$TEMPLATE" "Security rules" "has security rules field"
assert_contains "$TEMPLATE" "Stop conditions" "has stop conditions"
assert_contains "$TEMPLATE" "User approval" "has user approval field"
assert_contains "$TEMPLATE" "Secret" "has secret-handling reminder"
assert_contains "$TEMPLATE" "Stable tag\|tag/release" "has stable tag reminder"

echo ""

# ── 6. Stable tag gate ────────────────────────────────────────────────────

echo "--- Stable tag gate ---"
echo ""

GATE="$ROOT/docs/stable-tag-gate-v1.9.md"

assert_contains "$GATE" "No stable tag" "states no stable tag yet"
assert_contains "$GATE" "Completed\|Complete" "lists completed items"
assert_contains "$GATE" "Remaining\|Pending" "lists remaining items"
assert_contains "$GATE" "user approval" "requires user approval"
assert_contains "$GATE" "systemd\|Web production\|fingerprint" "lists items not required for v1.9"

echo ""

# ── 7. README links ───────────────────────────────────────────────────────

echo "--- README links ---"
echo ""

README="$ROOT/README.md"

assert_contains "$README" "maintenance-map" "README links to maintenance map"
assert_contains "$README" "ai-handoff-template" "README links to handoff template"
assert_contains "$README" "stable-tag-gate" "README links to stable tag gate"

echo ""

# ── Summary ───────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All maintenance docs tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
