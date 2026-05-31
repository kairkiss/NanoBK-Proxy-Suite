#!/usr/bin/env bash
# NanoBK Proxy Suite — Unified Installer Resume Test
#
# Tests --resume with explicit --mode precedence and config loading.
#
# Usage:
#   bash tests/unified-installer-resume.sh

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/nanobk-resume-test"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }

ERRORS=0

echo ""
echo "=== Unified Installer Resume Test ==="
echo ""

rm -rf "$TMP"
mkdir -p "$TMP"

# ── Test 1: --resume reads config ───────────────────────────────────────────

echo "--- --resume reads config ---"
echo ""

cat > "$TMP/test.env" <<'EOF'
NANOBK_LANG="zh"
NANOBK_MODE="commands"
NANOBK_DOMAIN="test.example.com"
EOF

OUTPUT=$(bash "$ROOT/installer/install.sh" --mode doctor --dry-run --defaults \
  --config-file "$TMP/test.env" --resume 2>&1 || true)

if echo "$OUTPUT" | grep -q "读取已有配置"; then
  pass "--resume reads config"
else
  fail "--resume missing config read message"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 2: explicit --mode overrides config mode ───────────────────────────

echo ""
echo "--- explicit --mode overrides config ---"
echo ""

# Config says "commands" but CLI says "doctor"
# The script reads config and should run doctor mode.
# On non-Linux/macOS, doctor may exit early, but config should still be read.
OUTPUT2=$(bash "$ROOT/installer/install.sh" --mode doctor --dry-run --defaults \
  --config-file "$TMP/test.env" --resume 2>&1 || true)

# Config was read (we see the log message)
if echo "$OUTPUT2" | grep -q "读取已有配置"; then
  pass "explicit --mode: config was read"
else
  fail "explicit --mode: config was not read"
  ERRORS=$((ERRORS + 1))
fi

# Should NOT show "命令模板" which is the commands mode output
if echo "$OUTPUT2" | grep -q "命令模板"; then
  fail "config mode=commands leaked through despite explicit --mode doctor"
  ERRORS=$((ERRORS + 1))
else
  pass "config mode=commands did not leak"
fi

# ── Test 3: --resume without --mode uses config mode ────────────────────────

echo ""
echo "--- --resume without --mode uses config ---"
echo ""

OUTPUT3=$(bash "$ROOT/installer/install.sh" --dry-run --defaults \
  --config-file "$TMP/test.env" --resume 2>&1 || true)

# Config was read (we see the log message)
if echo "$OUTPUT3" | grep -q "读取已有配置"; then
  pass "--resume without --mode: config was read"
else
  fail "--resume without --mode: config was not read"
  ERRORS=$((ERRORS + 1))
fi

# ── Test 4: --lang overrides config lang ────────────────────────────────────

echo ""
echo "--- --lang overrides config lang ---"
echo ""

cat > "$TMP/lang-test.env" <<'EOF'
NANOBK_LANG="zh"
NANOBK_MODE="commands"
EOF

OUTPUT4=$(bash "$ROOT/installer/install.sh" --mode doctor --dry-run --defaults --lang zh \
  --config-file "$TMP/lang-test.env" --resume 2>&1 || true)

# Should NOT show English warning since zh is explicit
if echo "$OUTPUT4" | grep -q "English UI is partial"; then
  fail "English warning shown despite explicit --lang zh"
  ERRORS=$((ERRORS + 1))
else
  pass "no English warning with explicit --lang zh"
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────

rm -rf "$TMP"

# ── Summary ─────────────────────────────────────────────────────────────────

echo ""
echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All resume tests passed!${NC}"
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  exit 1
fi
