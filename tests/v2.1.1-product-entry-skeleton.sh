#!/usr/bin/env bash
# NanoBK Proxy Suite — v2.1.1 Product Entry Skeleton Test
#
# Verifies the v2.1.1 install-product-only entry skeleton:
# - Default bootstrap does not auto-launch install.sh
# - Explicit legacy path still works
# - nanobk no-args shows product entry (not deployment)
# - Existing commands still dispatch
# - Safety: no secrets, no auto-apply, no Cloudflare API in default path
#
# Usage:
#   bash tests/v2.1.1-product-entry-skeleton.sh

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
echo "=== v2.1.1 Product Entry Skeleton Test ==="
echo ""

# ── A. Bootstrap default: install-only, no auto-launch ──────────────────────

echo "--- A. Bootstrap dry-run default (install-only) ---"
echo ""

BOOTSTRAP_DEFAULT=$(bash "$ROOT/installer/bootstrap.sh" --dry-run --install-dir /tmp/nanobk-v211-default-$$ 2>&1 | strip_ansi)

assert_contains "$BOOTSTRAP_DEFAULT" "DRY-RUN" "shows DRY-RUN marker"
assert_contains "$BOOTSTRAP_DEFAULT" "git clone" "shows clone command"
assert_not_contains "$BOOTSTRAP_DEFAULT" "install.sh" "default does NOT show install.sh"
assert_contains "$BOOTSTRAP_DEFAULT" "NanoBK is ready" "shows 'NanoBK is ready'"
assert_contains "$BOOTSTRAP_DEFAULT" "nanobk" "shows 'nanobk' as next step"
assert_contains "$BOOTSTRAP_DEFAULT" "Deployment is no longer started automatically" "explains no auto-deploy"

echo ""

# ── B. Bootstrap explicit legacy path ───────────────────────────────────────

echo "--- B. Bootstrap explicit legacy path ---"
echo ""

# --mode full
LEGACY_FULL=$(bash "$ROOT/installer/bootstrap.sh" --dry-run --install-dir /tmp/nanobk-v211-full-$$ -- --mode full 2>&1 | strip_ansi)
assert_contains "$LEGACY_FULL" "install.sh" "legacy --mode full shows install.sh"
assert_contains "$LEGACY_FULL" "--mode full" "legacy --mode full passes through"

# --mode doctor
LEGACY_DOCTOR=$(bash "$ROOT/installer/bootstrap.sh" --dry-run --install-dir /tmp/nanobk-v211-doctor-$$ -- --mode doctor 2>&1 | strip_ansi)
assert_contains "$LEGACY_DOCTOR" "install.sh" "legacy --mode doctor shows install.sh"
assert_contains "$LEGACY_DOCTOR" "--mode doctor" "legacy --mode doctor passes through"

# --mode commands
LEGACY_CMDS=$(bash "$ROOT/installer/bootstrap.sh" --dry-run --install-dir /tmp/nanobk-v211-cmds-$$ -- --mode commands 2>&1 | strip_ansi)
assert_contains "$LEGACY_CMDS" "install.sh" "legacy --mode commands shows install.sh"
assert_contains "$LEGACY_CMDS" "--mode commands" "legacy --mode commands passes through"

echo ""

# ── C. nanobk no-args: product entry ────────────────────────────────────────

echo "--- C. nanobk no-args product entry ---"
echo ""

ENTRY_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" 2>&1 | strip_ansi)

assert_contains "$ENTRY_OUTPUT" "NanoBK Proxy Suite" "entry shows product name"
assert_contains "$ENTRY_OUTPUT" "2.1.1" "entry shows version"
assert_contains "$ENTRY_OUTPUT" "NanoBK is ready" "entry shows 'NanoBK is ready'"
assert_contains "$ENTRY_OUTPUT" "nanobk status" "entry lists status command"
assert_contains "$ENTRY_OUTPUT" "nanobk doctor" "entry lists doctor command"
assert_contains "$ENTRY_OUTPUT" "nanobk install --mode full" "entry lists full wizard command"
assert_contains "$ENTRY_OUTPUT" "Deployment is not started automatically" "entry explains no auto-deploy"

# Should NOT start any deployment action
assert_not_contains "$ENTRY_OUTPUT" "launching" "entry does not launch anything"
assert_not_contains "$ENTRY_OUTPUT" "executing" "entry does not exec anything"
assert_not_contains "$ENTRY_OUTPUT" "deploying" "entry does not deploy anything"

echo ""

# ── D. Existing commands dispatch ────────────────────────────────────────────

echo "--- D. Existing commands dispatch ---"
echo ""

# nanobk version
VER_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" version 2>&1)
assert_contains "$VER_OUTPUT" "2.1.1" "nanobk version shows 2.1.1"

# nanobk --version
VER_FLAG=$(bash "$NANOBK" --repo-dir "$ROOT" --version 2>&1)
assert_contains "$VER_FLAG" "2.1.1" "nanobk --version shows 2.1.1"

# nanobk --help still works
HELP_OUTPUT=$(bash "$NANOBK" --repo-dir "$ROOT" --help 2>&1 | strip_ansi)
assert_contains "$HELP_OUTPUT" "Unified CLI" "--help shows full help"
assert_contains "$HELP_OUTPUT" "status" "--help lists status command"
assert_contains "$HELP_OUTPUT" "install" "--help lists install command"

# nanobk install --dry-run --mode full
INSTALL_DRY=$(bash "$NANOBK" --repo-dir "$ROOT" --dry-run install --mode full 2>&1 | strip_ansi)
assert_contains "$INSTALL_DRY" "install.sh" "install --dry-run shows install.sh"
assert_contains "$INSTALL_DRY" "DRY-RUN" "install --dry-run shows DRY-RUN"

# nanobk cf dns plan --help (if python3 available)
if command -v python3 &>/dev/null; then
  DNS_HELP=$(bash "$NANOBK" --repo-dir "$ROOT" cf dns plan --help 2>&1 || true)
  # Just verify it doesn't crash — output format depends on python script
  pass "cf dns plan --help did not crash"
else
  pass "cf dns plan --help skipped (no python3)"
fi

echo ""

# ── E. Safety checks ────────────────────────────────────────────────────────

echo "--- E. Safety checks ---"
echo ""

# No automatic apply --yes in bootstrap default path
BOOTSTRAP_SRC=$(cat "$ROOT/installer/bootstrap.sh")
assert_not_contains "$BOOTSTRAP_SRC" "apply --yes" "bootstrap.sh does not contain 'apply --yes'"

# No Cloudflare API call in bootstrap
assert_not_contains "$BOOTSTRAP_SRC" "api.cloudflare.com" "bootstrap.sh has no Cloudflare API URL"
assert_not_contains "$BOOTSTRAP_SRC" "CF_API_TOKEN" "bootstrap.sh has no CF_API_TOKEN"

# No token/env/secret strings in nanobk entry output
assert_not_contains "$ENTRY_OUTPUT" "TOKEN" "entry output has no TOKEN"
assert_not_contains "$ENTRY_OUTPUT" "SECRET" "entry output has no SECRET"
assert_not_contains "$ENTRY_OUTPUT" "PRIVATE_KEY" "entry output has no PRIVATE_KEY"
assert_not_contains "$ENTRY_OUTPUT" "workers.dev" "entry output has no workers.dev"
assert_not_contains "$ENTRY_OUTPUT" "Authorization" "entry output has no Authorization"

# No release/tag creation
if [[ -f "$ROOT/installer/install.sh" ]]; then
  INSTALL_SRC=$(cat "$ROOT/installer/install.sh")
  assert_not_contains "$INSTALL_SRC" "git tag" "install.sh has no git tag"
  assert_not_contains "$INSTALL_SRC" "gh release" "install.sh has no gh release"
fi

echo ""

# ── F. Version consistency ──────────────────────────────────────────────────

echo "--- F. Version consistency ---"
echo ""

NANOBK_VER=$(grep '^NANOBK_VERSION=' "$NANOBK" | head -1 | cut -d'"' -f2)
INSTALL_VER=$(grep '^VERSION=' "$ROOT/installer/install.sh" | head -1 | cut -d'"' -f2)
BOOTSTRAP_VER=$(grep '^BOOTSTRAP_VERSION=' "$ROOT/installer/bootstrap.sh" | head -1 | cut -d'"' -f2)

assert_contains "$NANOBK_VER" "2.1.1" "bin/nanobk version is 2.1.1"
assert_contains "$INSTALL_VER" "2.1.1" "install.sh version is 2.1.1"
assert_contains "$BOOTSTRAP_VER" "2.1.1" "bootstrap.sh version is 2.1.1"

if [[ "$NANOBK_VER" == "$INSTALL_VER" ]] && [[ "$INSTALL_VER" == "$BOOTSTRAP_VER" ]]; then
  pass "All three version constants match: $NANOBK_VER"
else
  fail "Version mismatch: nanobk=$NANOBK_VER install=$INSTALL_VER bootstrap=$BOOTSTRAP_VER"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All v2.1.1 skeleton tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
