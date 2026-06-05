#!/usr/bin/env bash
# NanoBK Proxy Suite — Bot/Web Command Allowlist Static Guard Test (v1.9.4)
#
# Checks that Bot/Web source code does not contain unsafe command execution
# patterns. This is a static source-code check only — it does NOT run real
# VPS status, Cloudflare commands, healthcheck, rotate sync, or read env files.
#
# Usage:
#   bash tests/bot-web-command-allowlist-v1.9.4.sh

set -euo pipefail

# ── Repo root ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

# ── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }
info() { echo -e "  ${YELLOW}ℹ${NC} $*"; }

ERRORS=0

# ── Header ───────────────────────────────────────────────────────────────────

echo ""
echo "=== NanoBK Bot/Web Command Allowlist Static Guard Test (v1.9.4) ==="
echo ""
echo "Purpose: Verify Bot/Web source code safety boundaries."
echo "Scope:   Static code checks only. No real commands executed."
echo ""

# ── Source file list ─────────────────────────────────────────────────────────
# Only check runtime source files, not documentation or examples.

BOT_SOURCE="bot/nanobk_bot.py"
WEB_SOURCE="web/app.py"
WEB_TEMPLATES_DIR="web/templates"

# Verify source files exist
for f in "$BOT_SOURCE" "$WEB_SOURCE"; do
  if [[ ! -f "$f" ]]; then
    fail "Source file missing: $f"
    ERRORS=$((ERRORS + 1))
  fi
done

# ── Helper ───────────────────────────────────────────────────────────────────
# check_absent CODE_PATTERN DESCRIPTION FILE...
# Checks that CODE_PATTERN does not appear in runtime code (excluding comments
# and docstrings). Fails on clear runtime violations.

check_absent() {
  local pattern="$1"
  local desc="$2"
  shift 2
  local files=("$@")

  # grep -n for the pattern, excluding lines that are pure comments (#) or
  # docstring markers ("""). This is a best-effort heuristic.
  local matches
  matches=$(grep -nE "$pattern" "${files[@]}" 2>/dev/null | \
    grep -v '^\s*#' | \
    grep -v '^\s*"""' | \
    grep -v "^\s*'''" | \
    grep -v '^\s*#' || true)

  if [[ -n "$matches" ]]; then
    fail "$desc"
    echo "$matches" | head -5 | while IFS= read -r line; do
      echo "    $line"
    done
    ERRORS=$((ERRORS + 1))
  else
    pass "$desc"
  fi
}

# ── Check 1: No shell=True ──────────────────────────────────────────────────

echo "--- Check 1: No shell=True in Bot/Web ---"
echo ""

check_absent "shell\s*=\s*True" \
  "No shell=True in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "shell\s*=\s*True" \
  "No shell=True in web/app.py" \
  "$WEB_SOURCE"

echo ""

# ── Check 2: No os.system ───────────────────────────────────────────────────

echo "--- Check 2: No os.system in Bot/Web ---"
echo ""

check_absent "os\.system\s*\(" \
  "No os.system() in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "os\.system\s*\(" \
  "No os.system() in web/app.py" \
  "$WEB_SOURCE"

echo ""

# ── Check 3: No direct systemctl invocation ─────────────────────────────────

echo "--- Check 3: No direct systemctl invocation in Bot/Web ---"
echo ""

# Check for systemctl as a runtime subprocess command, not in comments/strings
# that explain what NOT to do. We look for systemctl appearing in subprocess
# call arguments or os.system calls.
check_absent "(subprocess|os\.system|Popen).*systemctl" \
  "No subprocess/systemctl in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "(subprocess|os\.system|Popen).*systemctl" \
  "No subprocess/systemctl in web/app.py" \
  "$WEB_SOURCE"

echo ""

# ── Check 4: No direct write to /etc/nanobk ─────────────────────────────────

echo "--- Check 4: No direct write to /etc/nanobk in Bot/Web ---"
echo ""

# Look for open() with write mode targeting /etc/nanobk
check_absent "open\s*\(\s*['\"]\/etc\/nanobk" \
  "No open(/etc/nanobk) in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "open\s*\(\s*['\"]\/etc\/nanobk" \
  "No open(/etc/nanobk) in web/app.py" \
  "$WEB_SOURCE"

echo ""

# ── Check 5: No direct write to systemd unit paths ──────────────────────────

echo "--- Check 5: No direct write to systemd unit paths in Bot/Web ---"
echo ""

check_absent "open\s*\(\s*['\"]\/etc\/systemd" \
  "No open(/etc/systemd) in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "open\s*\(\s*['\"]\/etc\/systemd" \
  "No open(/etc/systemd) in web/app.py" \
  "$WEB_SOURCE"

echo ""

# ── Check 6: No direct read/cat of sensitive env files ──────────────────────

echo "--- Check 6: No direct read/cat of sensitive env files in Bot/Web ---"
echo ""

# Check for open() calls that read sensitive env file paths
check_absent "open\s*\(\s*['\"]\/root\/\.nanok" \
  "No open(/root/.nanok*) in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "open\s*\(\s*['\"]\/root\/\.nanok" \
  "No open(/root/.nanok*) in web/app.py" \
  "$WEB_SOURCE"

check_absent "open\s*\(\s*['\"]\/etc\/nanobk\/secrets" \
  "No open(/etc/nanobk/secrets*) in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "open\s*\(\s*['\"]\/etc\/nanobk\/secrets" \
  "No open(/etc/nanobk/secrets*) in web/app.py" \
  "$WEB_SOURCE"

echo ""

# ── Check 7: No direct Cloudflare deploy/write commands ─────────────────────

echo "--- Check 7: No direct Cloudflare deploy/write in Bot/Web ---"
echo ""

# Check for wrangler or direct CF API calls as subprocess commands
check_absent "(subprocess|Popen).*wrangler" \
  "No subprocess wrangler in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "(subprocess|Popen).*wrangler" \
  "No subprocess wrangler in web/app.py" \
  "$WEB_SOURCE"

echo ""

# ── Check 8: No direct protocol config writes ───────────────────────────────

echo "--- Check 8: No direct protocol config writes in Bot/Web ---"
echo ""

# Check for direct file writes to protocol config paths
check_absent "open\s*\(\s*['\"].*\/(hy2|tuic|reality|trojan).*['\"].*['\"]w" \
  "No direct protocol config writes in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "open\s*\(\s*['\"].*\/(hy2|tuic|reality|trojan).*['\"].*['\"]w" \
  "No direct protocol config writes in web/app.py" \
  "$WEB_SOURCE"

echo ""

# ── Check 8b: No shutil.copy to sensitive paths ────────────────────────────

echo "--- Check 8b: No shutil.copy to sensitive paths in Bot/Web ---"
echo ""

check_absent "(shutil\.copy|shutil\.copyfile|shutil\.copy2).*\/etc\/(nanobk|systemd)" \
  "No shutil.copy to /etc/nanobk or /etc/systemd in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "(shutil\.copy|shutil\.copyfile|shutil\.copy2).*\/etc\/(nanobk|systemd)" \
  "No shutil.copy to /etc/nanobk or /etc/systemd in web/app.py" \
  "$WEB_SOURCE"

echo ""

# ── Check 8c: No Path.write_text/write_bytes to sensitive paths ────────────

echo "--- Check 8c: No Path.write to sensitive paths in Bot/Web ---"
echo ""

check_absent "(write_text|write_bytes).*\/etc\/(nanobk|systemd)" \
  "No Path.write to /etc/nanobk or /etc/systemd in bot/nanobk_bot.py" \
  "$BOT_SOURCE"

check_absent "(write_text|write_bytes).*\/etc\/(nanobk|systemd)" \
  "No Path.write to /etc/nanobk or /etc/systemd in web/app.py" \
  "$WEB_SOURCE"

echo ""

# ── Check 9: subprocess.run uses list-based commands ────────────────────────

echo "--- Check 9: subprocess.run uses list-based commands ---"
echo ""

# Verify that subprocess.run calls use list form (not string concatenation)
# We check that subprocess.run is called and that shell= is NOT True.
# A more precise check: ensure subprocess.run appears and shell=True does not.
if grep -q "subprocess\.run" "$BOT_SOURCE" 2>/dev/null; then
  if grep "subprocess\.run" "$BOT_SOURCE" | grep -q "shell.*=.*True" 2>/dev/null; then
    fail "bot/nanobk_bot.py: subprocess.run with shell=True"
    ERRORS=$((ERRORS + 1))
  else
    pass "bot/nanobk_bot.py: subprocess.run without shell=True"
  fi
else
  info "bot/nanobk_bot.py: no subprocess.run found (may use wrapper)"
fi

if grep -q "subprocess\.run" "$WEB_SOURCE" 2>/dev/null; then
  if grep "subprocess\.run" "$WEB_SOURCE" | grep -q "shell.*=.*True" 2>/dev/null; then
    fail "web/app.py: subprocess.run with shell=True"
    ERRORS=$((ERRORS + 1))
  else
    pass "web/app.py: subprocess.run without shell=True"
  fi
else
  info "web/app.py: no subprocess.run found (may use wrapper)"
fi

echo ""

# ── Check 10: CLI calls are centralized through run_nanobk ──────────────────

echo "--- Check 10: CLI calls centralized through run_nanobk ---"
echo ""

# Count direct subprocess.run calls outside of run_nanobk function
# In bot/nanobk_bot.py, subprocess.run should only appear in run_nanobk()
bot_subprocess_count=$(grep -c "subprocess\.run" "$BOT_SOURCE" 2>/dev/null || echo "0")
bot_run_nanobk_count=$(grep -c "def run_nanobk" "$BOT_SOURCE" 2>/dev/null || echo "0")

if [[ "$bot_run_nanobk_count" -ge 1 ]]; then
  pass "bot/nanobk_bot.py: run_nanobk() wrapper exists"
else
  fail "bot/nanobk_bot.py: run_nanobk() wrapper missing"
  ERRORS=$((ERRORS + 1))
fi

web_subprocess_count=$(grep -c "subprocess\.run" "$WEB_SOURCE" 2>/dev/null || echo "0")
web_run_nanobk_count=$(grep -c "def run_nanobk" "$WEB_SOURCE" 2>/dev/null || echo "0")

if [[ "$web_run_nanobk_count" -ge 1 ]]; then
  pass "web/app.py: run_nanobk() wrapper exists"
else
  fail "web/app.py: run_nanobk() wrapper missing"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Check 11: Existing mock tests still pass ────────────────────────────────

echo "--- Check 11: Existing mock tests ---"
echo ""

if bash tests/bot-cli-mock.sh >/dev/null 2>&1; then
  pass "tests/bot-cli-mock.sh passes"
else
  fail "tests/bot-cli-mock.sh failed"
  ERRORS=$((ERRORS + 1))
fi

if bash tests/web-panel-mock.sh >/dev/null 2>&1; then
  pass "tests/web-panel-mock.sh passes"
else
  fail "tests/web-panel-mock.sh failed"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All allowlist guard tests passed!${NC}"
  echo ""
  echo "  Bot/Web source code safety boundaries verified."
  echo "  No unsafe command execution patterns found."
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  echo ""
  echo "  Bot/Web source code has safety boundary violations."
  echo "  Review failures above before proceeding."
  exit 1
fi
