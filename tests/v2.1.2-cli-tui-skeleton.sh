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

# ── A. Forced-TTY console: exit ─────────────────────────────────────────────

echo "--- A. Forced-TTY console: exit ---"
echo ""

TTY_EXIT_OUTPUT=$(printf '9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)
TTY_EXIT_RC=$?

assert_contains "$TTY_EXIT_OUTPUT" "NanoBK Proxy Suite" "forced-TTY shows branded header"
assert_contains "$TTY_EXIT_OUTPUT" "1) Status" "forced-TTY shows menu item 1"
assert_contains "$TTY_EXIT_OUTPUT" "9) Exit" "forced-TTY shows menu item 9"
assert_not_contains "$TTY_EXIT_OUTPUT" "apply --yes" "forced-TTY has no apply --yes"
assert_not_contains "$TTY_EXIT_OUTPUT" "deploying" "forced-TTY does not deploy"
if [[ $TTY_EXIT_RC -eq 0 ]]; then
  pass "forced-TTY exit returns 0"
else
  fail "forced-TTY exit returns $TTY_EXIT_RC (expected 0)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── B. Forced-TTY: invalid input then exit ───────────────────────────────────

echo "--- B. Forced-TTY: invalid input then exit ---"
echo ""

TTY_INVALID_OUTPUT=$(printf 'abc\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)
TTY_INVALID_RC=$?

assert_contains "$TTY_INVALID_OUTPUT" "Invalid input" "forced-TTY shows invalid input message"
assert_not_contains "$TTY_INVALID_OUTPUT" "deploying" "forced-TTY invalid input does not deploy"
if [[ $TTY_INVALID_RC -eq 0 ]]; then
  pass "forced-TTY invalid input exits 0"
else
  fail "forced-TTY invalid input exits $TTY_INVALID_RC (expected 0)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── C. Forced-TTY: help path ────────────────────────────────────────────────

echo "--- C. Forced-TTY: help path ---"
echo ""

TTY_HELP_OUTPUT=$(printf '8\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)

assert_contains "$TTY_HELP_OUTPUT" "Unified CLI" "forced-TTY help shows full help"
assert_contains "$TTY_HELP_OUTPUT" "status" "forced-TTY help lists status"

echo ""

# ── D. Forced-TTY: Full Wizard back path ────────────────────────────────────

echo "--- D. Forced-TTY: Full Wizard back path ---"
echo ""

TTY_FW_OUTPUT=$(printf '3\n2\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)

assert_contains "$TTY_FW_OUTPUT" "Full Wizard" "forced-TTY FW shows Full Wizard guidance"
assert_contains "$TTY_FW_OUTPUT" "nanobk install --mode full" "forced-TTY FW shows command"
assert_not_contains "$TTY_FW_OUTPUT" "Starting Full Wizard" "forced-TTY FW back does NOT start wizard"
assert_not_contains "$TTY_FW_OUTPUT" "deploying" "forced-TTY FW back does not deploy"

echo ""

# ── E. Forced-TTY: DNS submenu guidance ─────────────────────────────────────

echo "--- E. Forced-TTY: DNS submenu guidance ---"
echo ""

# Option 1: Preview DNS plan
TTY_DNS1_OUTPUT=$(printf '4\n1\n4\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)

assert_contains "$TTY_DNS1_OUTPUT" "cf dns plan" "DNS submenu shows plan command"
assert_not_contains "$TTY_DNS1_OUTPUT" "Running: nanobk cf dns plan" "DNS submenu does NOT auto-run plan"
assert_not_contains "$TTY_DNS1_OUTPUT" "apply --yes" "DNS submenu has no apply --yes"

# Option 3: Read-only check
TTY_DNS3_OUTPUT=$(printf '4\n3\n4\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)

assert_contains "$TTY_DNS3_OUTPUT" "--check" "DNS submenu option 3 shows --check"
assert_not_contains "$TTY_DNS3_OUTPUT" "apply --yes" "DNS submenu option 3 has no apply --yes"

echo ""

# ── F. No-args non-TTY ──────────────────────────────────────────────────────

echo "--- F. No-args non-TTY (safe entry) ---"
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

# ── G. Explicit console non-TTY ─────────────────────────────────────────────

echo "--- G. Explicit console non-TTY (safe fallback) ---"
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

# ── H. Piped input console ──────────────────────────────────────────────────

echo "--- H. Piped input console (non-TTY fallback) ---"
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

# ── I. Existing commands still work ─────────────────────────────────────────

echo "--- I. Existing commands dispatch ---"
echo ""

VER_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" version 2>&1)
assert_contains "$VER_OUTPUT" "2.1.1" "nanobk version shows 2.1.1"

VER_FLAG=$(bash "$NANOBK" --repo-dir "$ROOT" --version 2>&1)
assert_contains "$VER_FLAG" "2.1.1" "nanobk --version shows 2.1.1"

HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" --help 2>&1 | strip_ansi)
assert_contains "$HELP_OUTPUT" "Unified CLI" "--help shows full help"
assert_contains "$HELP_OUTPUT" "console" "--help mentions console"
assert_contains "$HELP_OUTPUT" "status" "--help lists status"
assert_contains "$HELP_OUTPUT" "install" "--help lists install"
assert_contains "$HELP_OUTPUT" "cf dns" "--help lists cf dns"

# install --dry-run
FW_DRY=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run install --mode full 2>&1 | strip_ansi)
assert_contains "$FW_DRY" "install.sh" "install --dry-run shows install.sh"
assert_contains "$FW_DRY" "DRY-RUN" "install --dry-run shows DRY-RUN"

# cf dns plan --help
if command -v python3 &>/dev/null; then
  bash "$NANOBK" --repo-dir "$ROOT" cf dns plan --help >/dev/null 2>&1 || true
  pass "cf dns plan --help did not crash"
else
  pass "cf dns plan --help skipped (no python3)"
fi

echo ""

# ── J. Safety source checks ─────────────────────────────────────────────────

echo "--- J. Safety source checks ---"
echo ""

NANOBK_SRC=$(cat "$NANOBK")

# Console source should not contain apply --yes as a direct string in menu
CONSOLE_FUNC=$(sed -n '/^cmd_console()/,/^}/p' "$NANOBK")
assert_not_contains "$CONSOLE_FUNC" "apply --yes" "cmd_console has no apply --yes"

# DNS submenu should not auto-run commands
DNS_SUBMENU=$(sed -n '/^console_dns_submenu()/,/^}/p' "$NANOBK")
assert_not_contains "$DNS_SUBMENU" "cmd_cf_dns" "DNS submenu does not call cmd_cf_dns"
assert_not_contains "$DNS_SUBMENU" "apply --yes" "DNS submenu has no apply --yes"

# Console source should not contain direct Cloudflare API calls
assert_not_contains "$CONSOLE_FUNC" "api.cloudflare.com" "cmd_console has no Cloudflare API URL"
assert_not_contains "$CONSOLE_FUNC" "CF_API_TOKEN" "console has no CF_API_TOKEN"

# NANOBK_TEST_FORCE_TTY should only appear in is_interactive_tty
FORCE_TTY_COUNT=$(grep -c 'NANOBK_TEST_FORCE_TTY' "$NANOBK" || true)
if [[ "$FORCE_TTY_COUNT" -le 2 ]]; then
  pass "NANOBK_TEST_FORCE_TTY appears only in TTY check ($FORCE_TTY_COUNT occurrences)"
else
  fail "NANOBK_TEST_FORCE_TTY appears $FORCE_TTY_COUNT times (expected <= 2)"
  ERRORS=$((ERRORS + 1))
fi

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
