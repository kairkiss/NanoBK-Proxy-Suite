#!/usr/bin/env bash
# NanoBK Proxy Suite — CLI Version Display Test (v2.0.21)
#
# Verifies that the CLI version display is honest and consistent.
#
# Usage:
#   bash tests/cli-version-display-v1.9.58.sh
#   (kept filename for git history; content validates v2.0.21)

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NANOBK="$ROOT/bin/nanobk"

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
  local desc="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$desc"
  else
    fail "$desc (expected '$needle' in output)"
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
    fail "$desc (unexpected '$needle' in output)"
    ERRORS=$((ERRORS + 1))
  fi
}

echo ""
echo "=== CLI Version Display Test (v2.0.21) ==="
echo ""

# ── 1. Version output ─────────────────────────────────────────────────────

echo "--- Version output ---"
echo ""

VERSION_OUTPUT=$(bash "$NANOBK" --version 2>&1)
assert_contains "$VERSION_OUTPUT" "nanobk" "version output contains 'nanobk'"
assert_contains "$VERSION_OUTPUT" "2.0.21" "version output contains '2.0.21'"
assert_not_contains "$VERSION_OUTPUT" "1.9.58" "version output does not contain stale '1.9.58'"

# Also test 'nanobk version' subcommand
VERSION_SUBCMD=$(bash "$NANOBK" version 2>&1)
assert_contains "$VERSION_SUBCMD" "2.0.21" "version subcommand contains '2.0.21'"
assert_not_contains "$VERSION_SUBCMD" "1.9.58" "version subcommand does not contain stale '1.9.58'"

echo ""

# ── 2. Version consistency ────────────────────────────────────────────────

echo "--- Version consistency across files ---"
echo ""

# bin/nanobk NANOBK_VERSION
NANOBK_VER=$(grep '^NANOBK_VERSION=' "$NANOBK" | head -1 | cut -d'"' -f2)
assert_contains "$NANOBK_VER" "2.0.21" "bin/nanobk NANOBK_VERSION is 2.0.21"

# installer/install.sh VERSION
INSTALL_VER=$(grep '^VERSION=' "$ROOT/installer/install.sh" | head -1 | cut -d'"' -f2)
assert_contains "$INSTALL_VER" "2.0.21" "install.sh VERSION is 2.0.21"

# installer/bootstrap.sh BOOTSTRAP_VERSION
BOOTSTRAP_VER=$(grep '^BOOTSTRAP_VERSION=' "$ROOT/installer/bootstrap.sh" | head -1 | cut -d'"' -f2)
assert_contains "$BOOTSTRAP_VER" "2.0.21" "bootstrap.sh BOOTSTRAP_VERSION is 2.0.21"

# All three should match
if [[ "$NANOBK_VER" == "$INSTALL_VER" ]] && [[ "$INSTALL_VER" == "$BOOTSTRAP_VER" ]]; then
  pass "All three version constants match: $NANOBK_VER"
else
  fail "Version mismatch: nanobk=$NANOBK_VER install=$INSTALL_VER bootstrap=$BOOTSTRAP_VER"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 3. Version command safety ─────────────────────────────────────────────

echo "--- Version command safety ---"
echo ""

# Version command should not read env files
check "bin/nanobk exists" test -f "$NANOBK"
check "bin/nanobk is executable or runnable" bash -n "$NANOBK"

# Check that version command doesn't contain status/doctor/install calls
NANOBK_SRC=$(cat "$NANOBK")
# The cmd_version function should be simple
VERSION_FUNC=$(sed -n '/^cmd_version()/,/^}/p' "$NANOBK")
assert_not_contains "$VERSION_FUNC" "cmd_status" "cmd_version does not call cmd_status"
assert_not_contains "$VERSION_FUNC" "cmd_doctor" "cmd_version does not call cmd_doctor"
assert_not_contains "$VERSION_FUNC" "cmd_install" "cmd_version does not call cmd_install"
assert_not_contains "$VERSION_FUNC" "cmd_rotate" "cmd_version does not call cmd_rotate"
assert_not_contains "$VERSION_FUNC" "run_script" "cmd_version does not call run_script"

echo ""

# ── 4. Help text uses version ─────────────────────────────────────────────

echo "--- Help text version ---"
echo ""

HELP_OUTPUT=$(bash "$NANOBK" --help 2>&1)
assert_contains "$HELP_OUTPUT" "2.0.21" "help text contains version 2.0.21"
assert_not_contains "$HELP_OUTPUT" "1.9.58" "help text does not contain stale 1.9.58"

echo ""

# ── 5. Protected commands still present ───────────────────────────────────

echo "--- Protected commands still present ---"
echo ""

assert_contains "$NANOBK_SRC" "cmd_status" "bin/nanobk has cmd_status"
assert_contains "$NANOBK_SRC" "cmd_doctor" "bin/nanobk has cmd_doctor"
assert_contains "$NANOBK_SRC" "cmd_install" "bin/nanobk has cmd_install"
assert_contains "$NANOBK_SRC" "cmd_rotate" "bin/nanobk has cmd_rotate"
assert_contains "$NANOBK_SRC" "cmd_cf_deploy" "bin/nanobk has cmd_cf_deploy"
assert_contains "$NANOBK_SRC" "cmd_install_cli" "bin/nanobk has cmd_install_cli"
assert_contains "$NANOBK_SRC" "resolve_repo_dir" "bin/nanobk has resolve_repo_dir"
assert_contains "$NANOBK_SRC" "read_env_value" "bin/nanobk has read_env_value"

echo ""

# ── 6. No secrets in version output ──────────────────────────────────────

echo "--- No secrets in version output ---"
echo ""

assert_not_contains "$VERSION_OUTPUT" "TOKEN" "no TOKEN in version output"
assert_not_contains "$VERSION_OUTPUT" "SECRET" "no SECRET in version output"
assert_not_contains "$VERSION_OUTPUT" "PRIVATE_KEY" "no PRIVATE_KEY in version output"
assert_not_contains "$VERSION_OUTPUT" "workers.dev" "no workers.dev in version output"

echo ""

# ── Summary ───────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All CLI version display tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
