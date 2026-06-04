#!/usr/bin/env bash
# NanoBK Proxy Suite — v1.8.36 Operation Log Help Fast Test
#
# Focused fast test for NANOBK_OPLOG_HELP_PILOT=1 (bin/nanobk --help).
# Uses NANOBK_TEST_OVERRIDE_SCRIPT to avoid running All safe tests.
#
# Usage:
#   bash tests/unified-cli-operation-log-help-fast-v1.8.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/lib/assertions.sh"

trap cleanup_temp EXIT

echo ""
echo "=== Test Suite: v1.8.36 Help Fast Test ==="

# ── Helper: create override script ─────────────────────────────────────
make_override_script
register_cleanup "$OVERRIDE_SCRIPT"

# ── 1: default test mode does NOT trigger help pilot ───────────────────

echo ""
echo "--- 1: default no-trigger ---"

default_out=$(NANOBK_TEST_OVERRIDE_SCRIPT="$OVERRIDE_SCRIPT" \
  bash "${REPO_DIR}/installer/install.sh" --mode test --defaults 2>&1 < /dev/null || true)
assert_not_contains "$default_out" "operation-log help command pilot enabled" "1a Default: pilot not triggered"
assert_not_contains "$default_out" "operation-log help command pilot completed" "1a Default: pilot not completed"
assert_contains "$default_out" "override test ran" "1a Default: override test ran (no All safe tests)"

# ── 2: help pilot triggers with override (fast) ────────────────────────

echo ""
echo "--- 2: help pilot fast trigger ---"

PILOT_DIR=$(mktemp -d)
register_cleanup "$PILOT_DIR"

fast_out=$(NANOBK_OPLOG_HELP_PILOT=1 NANOBK_OPLOG_DIR="$PILOT_DIR" \
  NANOBK_TEST_OVERRIDE_SCRIPT="$OVERRIDE_SCRIPT" \
  bash "${REPO_DIR}/installer/install.sh" --mode test --defaults 2>&1 < /dev/null || true)

assert_contains "$fast_out" "operation-log help command pilot enabled" "2a Fast: pilot enabled"
assert_contains "$fast_out" "bin/nanobk --help" "2a Fast: contains command"
assert_contains "$fast_out" "operation-log help command pilot completed" "2a Fast: pilot completed"
assert_contains "$fast_out" "Log:" "2a Fast: shows log path"
assert_contains "$fast_out" "override test ran" "2a Fast: override test ran"

# Screen should NOT contain raw help output (hidden output works)
assert_not_contains "$fast_out" "用法:" "2a Fast: no raw 用法 on screen"
assert_not_contains "$fast_out" "命令:" "2a Fast: no raw 命令 on screen"
assert_not_contains "$fast_out" "全局选项:" "2a Fast: no raw 全局选项 on screen"

assert_not_contains "$fast_out" "SECRET=" "2a Fast: no SECRET="
assert_not_contains "$fast_out" "status: success" "2a Fast: no status: success"

# Check log file
help_log=$(ls "${PILOT_DIR}"/real-command-help-pilot-*.log 2>/dev/null | head -1 || true)
if [[ -n "$help_log" ]]; then
  pass "2b Fast: log file exists"
  help_log_perms=$(stat -f '%Lp' "$help_log" 2>/dev/null || stat -c '%a' "$help_log" 2>/dev/null || echo "unknown")
  if [[ "$help_log_perms" == "600" ]]; then
    pass "2b Fast: log chmod 600"
  else
    fail "2b Fast: log chmod 600 (got $help_log_perms)"
  fi
  help_log_content=$(cat "$help_log")
  assert_contains "$help_log_content" "用法:" "2b Fast: log contains 用法"
  assert_contains "$help_log_content" "命令:" "2b Fast: log contains 命令"
else
  fail "2b Fast: log file not found"
fi

# ── 3: verbose shows help output ───────────────────────────────────────

echo ""
echo "--- 3: verbose ---"

PILOT_DIR=$(mktemp -d)
register_cleanup "$PILOT_DIR"

verbose_out=$(NANOBK_VERBOSE=1 NANOBK_OPLOG_HELP_PILOT=1 NANOBK_OPLOG_DIR="$PILOT_DIR" \
  NANOBK_TEST_OVERRIDE_SCRIPT="$OVERRIDE_SCRIPT" \
  bash "${REPO_DIR}/installer/install.sh" --mode test --defaults 2>&1 < /dev/null || true)

assert_contains "$verbose_out" "operation-log help command pilot enabled" "3a Verbose: pilot enabled"
assert_contains "$verbose_out" "operation-log help command pilot completed" "3a Verbose: pilot completed"
assert_contains "$verbose_out" "用法:" "3a Verbose: shows help output"
assert_contains "$verbose_out" "命令:" "3a Verbose: shows 命令"
assert_contains "$verbose_out" "Log:" "3a Verbose: shows log path"
assert_not_contains "$verbose_out" "SECRET=" "3a Verbose: no SECRET="

# ── 4: PLAIN no ANSI ───────────────────────────────────────────────────

echo ""
echo "--- 4: PLAIN ---"

PILOT_DIR=$(mktemp -d)
register_cleanup "$PILOT_DIR"

plain_out=$(NANOBK_PLAIN=1 NANOBK_OPLOG_HELP_PILOT=1 NANOBK_OPLOG_DIR="$PILOT_DIR" \
  NANOBK_TEST_OVERRIDE_SCRIPT="$OVERRIDE_SCRIPT" \
  bash "${REPO_DIR}/installer/install.sh" --mode test --defaults 2>&1 < /dev/null || true)

assert_contains "$plain_out" "operation-log help command pilot enabled" "4a PLAIN: pilot enabled"
assert_contains "$plain_out" "operation-log help command pilot completed" "4a PLAIN: pilot completed"
assert_contains "$plain_out" "Log:" "4a PLAIN: shows log path"
plain_pilot_lines=$(grep -E "help command pilot|Log:" <<< "$plain_out" || true)
if has_ansi "$plain_pilot_lines"; then
  fail "4a PLAIN: no ANSI in pilot output"
else
  pass "4a PLAIN: no ANSI in pilot output"
fi
assert_not_contains "$plain_out" "SECRET=" "4a PLAIN: no SECRET="

# ── 5: UI=0 no ANSI ────────────────────────────────────────────────────

echo ""
echo "--- 5: UI=0 ---"

PILOT_DIR=$(mktemp -d)
register_cleanup "$PILOT_DIR"

ui0_out=$(NANOBK_UI=0 NANOBK_OPLOG_HELP_PILOT=1 NANOBK_OPLOG_DIR="$PILOT_DIR" \
  NANOBK_TEST_OVERRIDE_SCRIPT="$OVERRIDE_SCRIPT" \
  bash "${REPO_DIR}/installer/install.sh" --mode test --defaults 2>&1 < /dev/null || true)

assert_contains "$ui0_out" "operation-log help command pilot enabled" "5a UI=0: pilot enabled"
assert_contains "$ui0_out" "operation-log help command pilot completed" "5a UI=0: pilot completed"
assert_contains "$ui0_out" "Log:" "5a UI=0: shows log path"
ui0_pilot_lines=$(grep -E "help command pilot|Log:" <<< "$ui0_out" || true)
if has_ansi "$ui0_pilot_lines"; then
  fail "5a UI=0: no ANSI in pilot output"
else
  pass "5a UI=0: no ANSI in pilot output"
fi
if grep -qF '╭' <<< "$ui0_pilot_lines"; then
  fail "5a UI=0: no box drawing in pilot output"
else
  pass "5a UI=0: no box drawing in pilot output"
fi
assert_not_contains "$ui0_out" "SECRET=" "5a UI=0: no SECRET="

# ── 6: CI no ANSI ──────────────────────────────────────────────────────

echo ""
echo "--- 6: CI ---"

PILOT_DIR=$(mktemp -d)
register_cleanup "$PILOT_DIR"

ci_out=$(CI=1 NANOBK_OPLOG_HELP_PILOT=1 NANOBK_OPLOG_DIR="$PILOT_DIR" \
  NANOBK_TEST_OVERRIDE_SCRIPT="$OVERRIDE_SCRIPT" \
  bash "${REPO_DIR}/installer/install.sh" --mode test --defaults 2>&1 < /dev/null || true)

assert_contains "$ci_out" "operation-log help command pilot enabled" "6a CI: pilot enabled"
assert_contains "$ci_out" "operation-log help command pilot completed" "6a CI: pilot completed"
assert_contains "$ci_out" "Log:" "6a CI: shows log path"
ci_pilot_lines=$(grep -E "help command pilot|Log:" <<< "$ci_out" || true)
if has_ansi "$ci_pilot_lines"; then
  fail "6a CI: no ANSI in pilot output"
else
  pass "6a CI: no ANSI in pilot output"
fi
assert_not_contains "$ci_out" "SECRET=" "6a CI: no SECRET="

# ── 7: full dry-run unaffected ─────────────────────────────────────────

echo ""
echo "--- 7: full dry-run ---"

full_dry_out=$(NANOBK_OPLOG_HELP_PILOT=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash "${REPO_DIR}/installer/install.sh" --mode full --dry-run --defaults --lang zh 2>&1 < /dev/null || true)
assert_not_contains "$full_dry_out" "operation-log help command pilot enabled" "7a Full dry-run: pilot not triggered"
assert_contains "$full_dry_out" "planned / dry-run" "7a Full dry-run: planned / dry-run preserved"
assert_not_contains "$full_dry_out" "status: success" "7a Full dry-run: no status: success"

# ── Summary ─────────────────────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo "  Passed: ${PASS}"
echo "  Failed: ${FAIL}"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "FAILED"
  exit 1
else
  echo "ALL PASSED"
  exit 0
fi
