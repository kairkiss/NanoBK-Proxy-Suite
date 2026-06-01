#!/usr/bin/env bash
# NanoBK Proxy Suite — Output Control Character Test
#
# Verifies that installer/status/cloudflare output does not contain
# NUL or dangerous control characters.
#
# Usage:
#   bash tests/output-control-chars.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$REPO_DIR/installer/install.sh"
NANOBK="$REPO_DIR/bin/nanobk"

PASS=0
FAIL=0

check() {
  local desc="$1"
  local ok="$2"
  if [[ "$ok" == "1" ]]; then
    echo "  ✓ ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  ✗ ${desc}"
    FAIL=$((FAIL + 1))
  fi
}

check_clean_output() {
  local label="$1"
  local text="$2"

  # Check for NUL
  if echo "$text" | python3 -c "
import sys
text = sys.stdin.buffer.read()
for b in text:
    if b == 0:
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    check "${label}: no NUL chars" "1"
  else
    check "${label}: no NUL chars" "0"
  fi

  # Check for dangerous control chars (allow tab, LF, CR, ESC for ANSI)
  if echo "$text" | python3 -c "
import sys
text = sys.stdin.buffer.read()
i = 0
while i < len(text):
    b = text[i]
    if b == 27:  # ESC - skip ANSI escape sequence
        i += 1
        # Skip until we find a letter (end of ANSI sequence)
        while i < len(text) and not chr(text[i]).isalpha():
            i += 1
        i += 1
        continue
    if b < 32 and b not in (9, 10, 13):
        sys.exit(1)
    if b == 127:
        sys.exit(1)
    i += 1
sys.exit(0)
" 2>/dev/null; then
    check "${label}: no dangerous control chars" "1"
  else
    check "${label}: no dangerous control chars" "0"
  fi
}

echo "=== Output Control Character Test ==="
echo ""

# ── Test 1: installer dry-run output ────────────────────────────────────────
echo "── Test 1: installer dry-run output ──"

OUTPUT=$(bash "$INSTALLER" --mode full --dry-run --defaults --lang zh 2>&1) || true
check_clean_output "installer dry-run" "$OUTPUT"

# ── Test 2: commands mode output ─────────────────────────────────────────────
echo ""
echo "── Test 2: commands mode output ──"

OUTPUT_CMD=$(bash "$INSTALLER" --mode commands --defaults 2>&1) || true
check_clean_output "commands mode" "$OUTPUT_CMD"

# ── Test 3: nanobk version ──────────────────────────────────────────────────
echo ""
echo "── Test 3: nanobk version ──"

OUTPUT_VER=$(bash "$NANOBK" --version 2>&1) || true
check_clean_output "nanobk version" "$OUTPUT_VER"

# ── Test 4: has check_output_clean helper ───────────────────────────────────
echo ""
echo "── Test 4: static checks ──"

check "has check_output_clean helper" "$(grep -q 'check_output_clean' "$INSTALLER" && echo 1 || echo 0)"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== ${PASS} passed, ${FAIL} failed ==="

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
