#!/usr/bin/env bash
# NanoBK Proxy Suite — Shared test assertion helpers
#
# Source this file in test scripts:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/assertions.sh"
#
# Provides: pass, fail, assert_contains, assert_not_contains, has_ansi,
#           make_override_script, cleanup_temp

PASS=${PASS:-0}
FAIL=${FAIL:-0}

pass() {
  PASS=$((PASS + 1))
  echo "  OK $1"
}

fail() {
  FAIL=$((FAIL + 1))
  echo "  FAIL $1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    pass "$label"
  else
    fail "$label — expected to contain: $needle"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  if grep -qF -- "$needle" <<< "$haystack"; then
    fail "$label — should NOT contain: $needle"
  else
    pass "$label"
  fi
}

has_ansi() {
  grep -qE $'\x1b\[' <<< "$1"
}

# Create a minimal override script that exits 0.
# Usage: make_override_script
# Sets: OVERRIDE_SCRIPT (path to temp file)
# Caller must call cleanup_temp on exit.
make_override_script() {
  OVERRIDE_SCRIPT=$(mktemp)
  cat > "$OVERRIDE_SCRIPT" <<'OVERRIDE'
#!/usr/bin/env bash
echo "override test ran"
exit 0
OVERRIDE
  chmod +x "$OVERRIDE_SCRIPT"
}

# Collect temp files for cleanup. Call in trap.
_CLEANUP_FILES=()

cleanup_temp() {
  local f
  for f in "${_CLEANUP_FILES[@]:-}"; do
    [[ -n "$f" && -e "$f" ]] && rm -rf "$f" 2>/dev/null || true
  done
}

# Register a temp file/dir for cleanup.
register_cleanup() {
  _CLEANUP_FILES+=("$@")
}
