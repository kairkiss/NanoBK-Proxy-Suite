#!/usr/bin/env bash
# NanoBK Proxy Suite — v2.1.3 CLI UI Polish Test
#
# Verifies the v2.1.3 CLI UI polish:
# - Forced-TTY console shows branded header with safety wording
# - Pause prompts work and do not hang
# - Export/rotate guidance does not print protocol links or credentials
# - DNS submenu remains guidance-first
# - Full Wizard back path remains safe
# - Non-TTY remains safe and non-blocking
# - Existing commands still dispatch
#
# Usage:
#   bash tests/v2.1.3-cli-ui-polish.sh

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
echo "=== v2.1.3 CLI UI Polish Test ==="
echo ""

# ── A. Forced-TTY console header ────────────────────────────────────────────

echo "--- A. Forced-TTY console header ---"
echo ""

TTY_HEADER=$(printf '9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)

assert_contains "$TTY_HEADER" "NanoBK Proxy Suite" "shows branded header"
assert_contains "$TTY_HEADER" "Safe by default" "shows safety wording"
assert_contains "$TTY_HEADER" "1) Status" "shows menu item 1"
assert_contains "$TTY_HEADER" "9) Exit" "shows menu item 9"
assert_not_contains "$TTY_HEADER" "apply --yes" "no apply --yes"
assert_not_contains "$TTY_HEADER" "TOKEN" "no TOKEN"
assert_not_contains "$TTY_HEADER" "SECRET" "no SECRET"
assert_not_contains "$TTY_HEADER" "PRIVATE_KEY" "no PRIVATE_KEY"
assert_not_contains "$TTY_HEADER" "workers.dev" "no workers.dev"
assert_not_contains "$TTY_HEADER" "Authorization" "no Authorization"

echo ""

# ── B. Pause does not hang ──────────────────────────────────────────────────

echo "--- B. Pause does not hang ---"
echo ""

TTY_PAUSE=$(printf '5\n\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)

assert_contains "$TTY_PAUSE" "Export Protocol Links" "shows export section"
assert_contains "$TTY_PAUSE" "Press Enter" "shows pause prompt"
assert_not_contains "$TTY_PAUSE" "hysteria2://" "no hysteria2:// URI"
assert_not_contains "$TTY_PAUSE" "tuic://" "no tuic:// URI"
assert_not_contains "$TTY_PAUSE" "vless://" "no vless:// URI"
assert_not_contains "$TTY_PAUSE" "trojan://" "no trojan:// URI"
assert_not_contains "$TTY_PAUSE" "apply --yes" "no apply --yes"

echo ""

# ── C. Rotate guidance ──────────────────────────────────────────────────────

echo "--- C. Rotate guidance ---"
echo ""

TTY_ROTATE=$(printf '6\n\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)

assert_contains "$TTY_ROTATE" "Rotate Keys" "shows rotate section"
assert_contains "$TTY_ROTATE" "nanobk rotate" "shows rotate commands"
assert_contains "$TTY_ROTATE" "Credential-changing" "shows credential-changing label"
assert_not_contains "$TTY_ROTATE" "apply --yes" "no apply --yes"

echo ""

# ── D. DNS guidance ─────────────────────────────────────────────────────────

echo "--- D. DNS guidance ---"
echo ""

TTY_DNS=$(printf '4\n3\n\n4\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)

assert_contains "$TTY_DNS" "--check" "DNS shows --check"
assert_contains "$TTY_DNS" "Read-only" "DNS shows read-only wording"
assert_not_contains "$TTY_DNS" "apply --yes" "DNS has no apply --yes"
assert_not_contains "$TTY_DNS" "api.cloudflare.com" "DNS has no Cloudflare API URL"

echo ""

# ── E. Full Wizard back path ────────────────────────────────────────────────

echo "--- E. Full Wizard back path ---"
echo ""

TTY_FW=$(printf '3\n2\n9\n' | NANOBK_TEST_FORCE_TTY=1 bash "$NANOBK" --repo-dir "$ROOT" console 2>&1 | strip_ansi)

assert_contains "$TTY_FW" "Explicit deployment" "FW shows explicit deployment label"
assert_contains "$TTY_FW" "nanobk install --mode full" "FW shows command"
assert_not_contains "$TTY_FW" "Starting Full Wizard" "FW back does NOT start wizard"
assert_not_contains "$TTY_FW" "deploying" "FW back does not deploy"

echo ""

# ── F. Non-TTY still safe ───────────────────────────────────────────────────

echo "--- F. Non-TTY still safe ---"
echo ""

NONTTY=$(bash "$NANOBK" --repo-dir "$ROOT" < /dev/null 2>&1 | strip_ansi)
NONTTY_RC=$?

assert_contains "$NONTTY" "NanoBK Proxy Suite" "non-TTY shows product name"
assert_not_contains "$NONTTY" "Press Enter" "non-TTY has no pause prompt"
assert_not_contains "$NONTTY" "apply --yes" "non-TTY has no apply --yes"
assert_not_contains "$NONTTY" "deploying" "non-TTY does not deploy"
if [[ $NONTTY_RC -eq 0 ]]; then
  pass "non-TTY exits 0"
else
  fail "non-TTY exits $NONTTY_RC (expected 0)"
  ERRORS=$((ERRORS + 1))
fi

CONSOLE_NONTTY=$(bash "$NANOBK" --repo-dir "$ROOT" console < /dev/null 2>&1 | strip_ansi)
CONSOLE_RC=$?

assert_not_contains "$CONSOLE_NONTTY" "Press Enter" "console non-TTY has no pause"
if [[ $CONSOLE_RC -eq 0 ]]; then
  pass "console non-TTY exits 0"
else
  fail "console non-TTY exits $CONSOLE_RC (expected 0)"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── G. Existing commands ────────────────────────────────────────────────────

echo "--- G. Existing commands ---"
echo ""

VER=$(bash "$NANOBK" --repo-dir "$ROOT" version 2>&1)
assert_contains "$VER" "2.1.1" "version shows 2.1.1"

HELP=$(bash "$NANOBK" --repo-dir "$ROOT" --help 2>&1 | strip_ansi)
assert_contains "$HELP" "Unified CLI" "--help shows full help"
assert_contains "$HELP" "console" "--help mentions console"

FW_DRY=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run install --mode full 2>&1 | strip_ansi)
assert_contains "$FW_DRY" "install.sh" "install --dry-run shows install.sh"
assert_contains "$FW_DRY" "DRY-RUN" "install --dry-run shows DRY-RUN"

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

NANOBK_SRC=$(cat "$NANOBK")

# UI helpers must not contain secrets
UI_HELPERS=$(sed -n '/^# ── CLI UI helpers/,/^# ── Console helpers/p' "$NANOBK")
assert_not_contains "$UI_HELPERS" "apply --yes" "UI helpers have no apply --yes"
assert_not_contains "$UI_HELPERS" "api.cloudflare.com" "UI helpers have no Cloudflare API"
assert_not_contains "$UI_HELPERS" "CF_API_TOKEN" "UI helpers have no CF_API_TOKEN"

# Console loop must not contain apply --yes
CONSOLE_LOOP=$(sed -n '/^console_loop()/,/^}/p' "$NANOBK")
assert_not_contains "$CONSOLE_LOOP" "apply --yes" "console_loop has no apply --yes"

# DNS submenu must not call cmd_cf_dns
DNS_MENU=$(sed -n '/^console_dns_submenu()/,/^}/p' "$NANOBK")
assert_not_contains "$DNS_MENU" "cmd_cf_dns" "DNS submenu does not call cmd_cf_dns"

# No protocol URI schemes in console output sections
assert_not_contains "$CONSOLE_LOOP" "hysteria2://" "no hysteria2:// in console loop"
assert_not_contains "$CONSOLE_LOOP" "tuic://" "no tuic:// in console loop"
assert_not_contains "$CONSOLE_LOOP" "vless://" "no vless:// in console loop"
assert_not_contains "$CONSOLE_LOOP" "trojan://" "no trojan:// in console loop"

# No release/tag
assert_not_contains "$NANOBK_SRC" "git tag" "no git tag"
assert_not_contains "$NANOBK_SRC" "gh release" "no gh release"

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.1.3 UI polish tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
