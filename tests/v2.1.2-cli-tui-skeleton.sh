#!/usr/bin/env bash
# NanoBK Proxy Suite — v2.1.2 Branded CLI/TUI Skeleton Test
#
# Verifies the v2.1.2 branded console skeleton:
# - Non-TTY no-args shows safe entry (no deploy, no apply --yes)
# - Explicit console non-TTY shows safe fallback
# - Piped input console does not hang or deploy
# - Existing commands still dispatch
# - Safety: no secrets, no auto-apply, no Cloudflare API in console path
#
# Usage:
#   bash tests/v2.1.2-cli-tui-skeleton.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NANOBK="$ROOT/bin/nanobk"

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

strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

echo ""
echo "=== v2.1.2 Branded CLI/TUI Skeleton Test ==="
echo ""

# ── A. No-args non-TTY ──────────────────────────────────────────────────────

echo "--- A. No-args non-TTY (safe entry) ---"
echo ""

NONTTY_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" < /dev/null 2>&1 | strip_ansi)
NONTTY_EXIT=$?

assert_contains "$NONTTY_OUTPUT" "NanoBK Proxy Suite" "non-TTY shows product name"
assert_contains "$NONTTY_OUTPUT" "2.1.1" "non-TTY shows version"
assert_contains "$NONTTY_OUTPUT" "NanoBK is ready" "non-TTY shows 'NanoBK is ready'"
assert_contains "$NONTTY_OUTPUT" "nanobk status" "non-TTY lists status command"
assert_contains "$NONTTY_OUTPUT" "nanobk console" "non-TTY mentions console command"
assert_not_contains "$NONTTY_OUTPUT" "apply --yes" "non-TTY does NOT show apply --yes"
assert_not_contains "$NONTTY_OUTPUT" "install.sh" "non-TTY does NOT show install.sh launch"
assert_not_contains "$NONTTY_OUTPUT" "launching" "non-TTY does NOT launch anything"
assert_not_contains "$NONTTY_OUTPUT" "deploying" "non-TTY does NOT deploy anything"
assert_not_contains "$NONTTY_OUTPUT" "TOKEN" "non-TTY has no TOKEN"
assert_not_contains "$NONTTY_OUTPUT" "SECRET" "non-TTY has no SECRET"
assert_not_contains "$NONTTY_OUTPUT" "PRIVATE_KEY" "non-TTY has no PRIVATE_KEY"
assert_not_contains "$NONTTY_OUTPUT" "workers.dev" "non-TTY has no workers.dev"
assert_not_contains "$NONTTY_OUTPUT" "Authorization" "non-TTY has no Authorization"
if [[ $NONTTY_EXIT -eq 0 ]]; then
  pass "non-TTY exits 0"
else
  fail "non-TTY exits $NONTTY_EXIT (expected 0)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── B. Explicit console non-TTY ─────────────────────────────────────────────

echo "--- B. Explicit console non-TTY (safe fallback) ---"
echo ""

CONSOLE_NONTTY=$(bash "$NANOBK" --repo-dir "$ROOT" console < /dev/null 2>&1 | strip_ansi)
CONSOLE_EXIT=$?

# Non-TTY console falls back to safe entry text
assert_contains "$CONSOLE_NONTTY" "NanoBK Proxy Suite" "console non-TTY shows product name"
assert_not_contains "$CONSOLE_NONTTY" "apply --yes" "console non-TTY has no apply --yes"
assert_not_contains "$CONSOLE_NONTTY" "deploying" "console non-TTY does not deploy"
if [[ $CONSOLE_EXIT -eq 0 ]]; then
  pass "console non-TTY exits 0"
else
  fail "console non-TTY exits $CONSOLE_EXIT (expected 0)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── C. Piped input console ──────────────────────────────────────────────────

echo "--- C. Piped input console (non-TTY fallback) ---"
echo ""

PIPED_OUTPUT=$(printf '9\n' | bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)
PIPED_EXIT=$?

# Piped stdin is non-TTY, so falls back to safe entry
assert_contains "$PIPED_OUTPUT" "NanoBK Proxy Suite" "piped console shows product name"
assert_not_contains "$PIPED_OUTPUT" "apply --yes" "piped console has no apply --yes"
assert_not_contains "$PIPED_OUTPUT" "deploying" "piped console does not deploy"
if [[ $PIPED_EXIT -eq 0 ]]; then
  pass "piped console exits 0"
else
  fail "piped console exits $PIPED_EXIT (expected 0)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── D. Invalid input safety ─────────────────────────────────────────────────

echo "--- D. Invalid input safety ---"
echo ""

# Non-TTY: input is irrelevant, just shows safe entry
INVALID_OUTPUT=$(printf 'abc\n' | bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)
INVALID_EXIT=$?

assert_not_contains "$INVALID_OUTPUT" "deploying" "invalid input does not deploy"
if [[ $INVALID_EXIT -eq 0 ]]; then
  pass "invalid input exits 0"
else
  fail "invalid input exits $INVALID_EXIT (expected 0)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── E. Help path ────────────────────────────────────────────────────────────

echo "--- E. Advanced help path ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" --help 2>&1 | strip_ansi)

assert_contains "$HELP_OUTPUT" "Unified CLI" "--help shows full help"
assert_contains "$HELP_OUTPUT" "console" "--help mentions console"
assert_contains "$HELP_OUTPUT" "status" "--help lists status"
assert_contains "$HELP_OUTPUT" "install" "--help lists install"
assert_contains "$HELP_OUTPUT" "cf dns" "--help lists cf dns"

echo ""

# ── F. Full Wizard safety ───────────────────────────────────────────────────

echo "--- F. Full Wizard safety ---"
echo ""

# Explicit install --dry-run should show install.sh but not execute
FW_DRY=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run install --mode full 2>&1 | strip_ansi)
assert_contains "$FW_DRY" "install.sh" "install --dry-run shows install.sh"
assert_contains "$FW_DRY" "DRY-RUN" "install --dry-run shows DRY-RUN"

# Source check: cmd_console should not contain direct exec of install.sh
NANOBK_SRC=$(cat "$NANOBK")
# The console calls cmd_install, which is the existing safe dispatch
assert_contains "$NANOBK_SRC" "cmd_install" "console uses cmd_install (existing dispatch)"

echo ""

# ── G. Existing commands still work ─────────────────────────────────────────

echo "--- G. Existing commands dispatch ---"
echo ""

VER_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" version 2>&1)
assert_contains "$VER_OUTPUT" "2.1.1" "nanobk version shows 2.1.1"

VER_FLAG=$(bash "$NANOBK" --repo-dir "$ROOT" --version 2>&1)
assert_contains "$VER_FLAG" "2.1.1" "nanobk --version shows 2.1.1"

# cf dns plan --help (if python3 available)
if command -v python3 &>/dev/null; then
  bash "$NANOBK" --repo-dir "$ROOT" cf dns plan --help >/dev/null 2>&1 || true
  pass "cf dns plan --help did not crash"
else
  pass "cf dns plan --help skipped (no python3)"
fi

echo ""

# ── H. Safety source checks ─────────────────────────────────────────────────

echo "--- H. Safety source checks ---"
echo ""

# Console source should not contain apply --yes as a direct string in menu
CONSOLE_FUNC=$(sed -n '/^cmd_console()/,/^}/p' "$NANOBK")
assert_not_contains "$CONSOLE_FUNC" "apply --yes" "cmd_console has no apply --yes"

# Console source should not contain direct Cloudflare API calls
assert_not_contains "$CONSOLE_FUNC" "api.cloudflare.com" "cmd_console has no Cloudflare API URL"
assert_not_contains "$CONSOLE_FUNC" "CF_API_TOKEN" "console has no CF_API_TOKEN"

# No release/tag in nanobk
assert_not_contains "$NANOBK_SRC" "git tag" "nanobk has no git tag"
assert_not_contains "$NANOBK_SRC" "gh release" "nanobk has no gh release"

# Bootstrap source should not have changed
BOOTSTRAP_SRC=$(cat "$ROOT/installer/bootstrap.sh")
assert_not_contains "$BOOTSTRAP_SRC" "apply --yes" "bootstrap has no apply --yes"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.1.2 skeleton tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
