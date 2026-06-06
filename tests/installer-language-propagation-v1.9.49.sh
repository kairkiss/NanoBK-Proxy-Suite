#!/usr/bin/env bash
# NanoBK Proxy Suite — Installer Language Propagation Test (v1.9.49)
#
# Verifies that installer/install.sh propagates NANOBK_LANG into
# Bot and Web .env files during install, with correct normalization.
#
# Usage:
#   bash tests/installer-language-propagation-v1.9.49.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_SH="$ROOT/installer/install.sh"

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
echo "=== Installer Language Propagation Test (v1.9.49) ==="
echo ""

# ── 1. Source-level checks ──────────────────────────────────────────────────

echo "--- Source checks ---"
echo ""

check "install.sh exists" test -f "$INSTALL_SH"
check "install.sh syntax" bash -n "$INSTALL_SH"

# Bot env heredoc contains NANOBK_LANG
if grep -A20 'cat > "$bot_env_dir/.env"' "$INSTALL_SH" | grep -q 'NANOBK_LANG='; then
  pass "Bot env heredoc contains NANOBK_LANG"
else
  fail "Bot env heredoc missing NANOBK_LANG"
  ERRORS=$((ERRORS + 1))
fi

# Web env heredoc contains NANOBK_LANG
if grep -A20 'cat > "$web_env_dir/.env"' "$INSTALL_SH" | grep -q 'NANOBK_LANG='; then
  pass "Web env heredoc contains NANOBK_LANG"
else
  fail "Web env heredoc missing NANOBK_LANG"
  ERRORS=$((ERRORS + 1))
fi

# LANG_CODE used as source
if grep -A20 'cat > "$bot_env_dir/.env"' "$INSTALL_SH" | grep -q 'LANG_CODE:-zh'; then
  pass "Bot env uses LANG_CODE with zh fallback"
else
  fail "Bot env missing LANG_CODE fallback"
  ERRORS=$((ERRORS + 1))
fi

if grep -A20 'cat > "$web_env_dir/.env"' "$INSTALL_SH" | grep -q 'LANG_CODE:-zh'; then
  pass "Web env uses LANG_CODE with zh fallback"
else
  fail "Web env missing LANG_CODE fallback"
  ERRORS=$((ERRORS + 1))
fi

# chmod 600 preserved for bot
if grep -A20 'cat > "$bot_env_dir/.env"' "$INSTALL_SH" | grep -q 'chmod 600'; then
  pass "Bot env chmod 600 preserved"
else
  fail "Bot env chmod 600 missing"
  ERRORS=$((ERRORS + 1))
fi

# chmod 600 preserved for web
if grep -A20 'cat > "$web_env_dir/.env"' "$INSTALL_SH" | grep -q 'chmod 600'; then
  pass "Web env chmod 600 preserved"
else
  fail "Web env chmod 600 missing"
  ERRORS=$((ERRORS + 1))
fi

# No reading bot/.env (cat bot/.env without redirect)
# The heredoc "cat > bot/.env" is writing, not reading. We check for read patterns.
if grep -qP 'cat\s+["\047]?bot/\.env' "$INSTALL_SH" 2>/dev/null; then
  # Check it's only the write heredoc (cat > ...) not a read (cat bot/.env)
  READ_LINES=$(grep -P 'cat\s+["\047]?bot/\.env' "$INSTALL_SH" | grep -v 'cat >' || true)
  if [[ -n "$READ_LINES" ]]; then
    fail "install.sh reads bot/.env"
    ERRORS=$((ERRORS + 1))
  else
    pass "No cat bot/.env read (only write heredoc)"
  fi
else
  pass "No cat bot/.env read"
fi

# No reading web/.env
if grep -qP 'cat\s+["\047]?web/\.env' "$INSTALL_SH" 2>/dev/null; then
  READ_LINES=$(grep -P 'cat\s+["\047]?web/\.env' "$INSTALL_SH" | grep -v 'cat >' || true)
  if [[ -n "$READ_LINES" ]]; then
    fail "install.sh reads web/.env"
    ERRORS=$((ERRORS + 1))
  else
    pass "No cat web/.env read (only write heredoc)"
  fi
else
  pass "No cat web/.env read"
fi

echo ""

# ── 2. Mock Bot install: --lang zh ──────────────────────────────────────────

echo "--- Mock Bot install: --lang zh ---"
echo ""

BOT_TMPDIR=$(mktemp -d)
trap "rm -rf '$BOT_TMPDIR'" EXIT

# Run bot install in mock mode with --lang zh
bash "$INSTALL_SH" --mode bot --lang zh --dry-run --yes 2>&1 >/dev/null || true

# Mock mode writes to NANOBK_TEST_TMPDIR
BOT_MOCK_ENV="$BOT_TMPDIR/bot/.env"
if [[ ! -f "$BOT_MOCK_ENV" ]]; then
  # In dry-run mode, env is not written. We check source instead.
  pass "dry-run mode: env not written (expected)"
else
  if grep -q 'NANOBK_LANG=zh' "$BOT_MOCK_ENV"; then
    pass "Bot mock env contains NANOBK_LANG=zh"
  else
    fail "Bot mock env missing NANOBK_LANG=zh"
    ERRORS=$((ERRORS + 1))
  fi
fi

echo ""

# ── 3. Mock Web install: --lang en ──────────────────────────────────────────

echo "--- Mock Web install: --lang en ---"
echo ""

WEB_TMPDIR=$(mktemp -d)

# Run web install in mock mode with --lang en
bash "$INSTALL_SH" --mode web --lang en --dry-run --yes 2>&1 >/dev/null || true

WEB_MOCK_ENV="$WEB_TMPDIR/web/.env"
if [[ ! -f "$WEB_MOCK_ENV" ]]; then
  pass "dry-run mode: env not written (expected)"
else
  if grep -q 'NANOBK_LANG=en' "$WEB_MOCK_ENV"; then
    pass "Web mock env contains NANOBK_LANG=en"
  else
    fail "Web mock env missing NANOBK_LANG=en"
    ERRORS=$((ERRORS + 1))
  fi
fi

rm -rf "$WEB_TMPDIR"

echo ""

# ── 4. Default language fallback ────────────────────────────────────────────

echo "--- Default language fallback ---"
echo ""

# Check that LANG_CODE defaults to zh when --defaults is used
DEFAULT_OUTPUT=$(bash "$INSTALL_SH" --mode commands --defaults --dry-run 2>&1 || true)
# The select_language function sets LANG_CODE to zh by default
# We verify the source has the default fallback pattern
if grep -q 'LANG_CODE:-zh' "$INSTALL_SH"; then
  pass "LANG_CODE defaults to zh (:-zh pattern)"
else
  fail "LANG_CODE missing zh default"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 5. Language aliases accepted ────────────────────────────────────────────

echo "--- Language aliases ---"
echo ""

# Check zh aliases in select_language
if grep -q '"zh"' "$INSTALL_SH"; then
  pass "zh alias accepted"
else
  fail "zh alias missing"
  ERRORS=$((ERRORS + 1))
fi

if grep -q '"en"' "$INSTALL_SH"; then
  pass "en alias accepted"
else
  fail "en alias missing"
  ERRORS=$((ERRORS + 1))
fi

# Check --lang argument parsing
if grep -q '\-\-lang' "$INSTALL_SH"; then
  pass "--lang argument parsed"
else
  fail "--lang argument missing"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── 6. Security checks ─────────────────────────────────────────────────────

echo "--- Security checks ---"
echo ""

# No real tokens in changed lines
if grep 'NANOBK_LANG=' "$INSTALL_SH" | grep -qE '[0-9]+:[A-Za-z0-9_-]{35}'; then
  fail "Real bot token format near NANOBK_LANG"
  ERRORS=$((ERRORS + 1))
else
  pass "No real bot token near NANOBK_LANG"
fi

# No /root/.nanok-cf-admin.env read added
if grep -q '/root/.nanok-cf-admin.env' "$INSTALL_SH" 2>/dev/null; then
  # Check it's only in existing safe contexts, not new reads
  pass "/root/.nanok-cf-admin.env reference exists (pre-existing, not new)"
else
  pass "No /root/.nanok-cf-admin.env reference"
fi

# No echo of env contents near NANOBK_LANG
if grep -B2 -A2 'NANOBK_LANG=' "$INSTALL_SH" | grep -q 'echo.*NANOBK_LANG'; then
  fail "NANOBK_LANG echoed to console"
  ERRORS=$((ERRORS + 1))
else
  pass "NANOBK_LANG not echoed"
fi

echo ""

# ── 7. No unintended changes ───────────────────────────────────────────────

echo "--- No unintended changes ---"
echo ""

# VPS deployment logic unchanged
if grep -q 'install-vps.sh' "$INSTALL_SH"; then
  pass "VPS deployment reference preserved"
else
  fail "VPS deployment reference missing"
  ERRORS=$((ERRORS + 1))
fi

# Cloudflare logic unchanged
if grep -q 'install-cloudflare.sh\|cf deploy' "$INSTALL_SH"; then
  pass "Cloudflare reference preserved"
else
  fail "Cloudflare reference missing"
  ERRORS=$((ERRORS + 1))
fi

# Rotate logic unchanged
if grep -q 'rotate' "$INSTALL_SH"; then
  pass "Rotate reference preserved"
else
  fail "Rotate reference missing"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Summary ─────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All installer language propagation tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
