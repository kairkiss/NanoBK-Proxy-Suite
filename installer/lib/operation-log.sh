#!/usr/bin/env bash
# NanoBK Proxy Suite — Operation Log v1.8.20
#
# Provides operation logging for the installer.
# Default UI shows concise messages; verbose mode shows full output.
# Failed operations hint at the log file path.
#
# This file only handles logging infrastructure — it never makes deployment decisions.
#
# Environment variables:
#   NANOBK_VERBOSE=1    — show detailed command output inline
#   NANOBK_PLAIN=1      — plainest log format
#   NANOBK_LOG_DIR      — override log directory
#   NANOBK_OPLOG_DIR    — alias for NANOBK_LOG_DIR (test convenience)
#
# Source this file; do not execute directly.

# ── Guard: prevent double-source ──────────────────────────────────────────

if [[ "${_NANOBK_OPLOG_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_NANOBK_OPLOG_LOADED=1

# ── Color capability (lightweight, independent of ui.sh) ──────────────────

_oplog_has_color() {
  [[ "${NANOBK_PLAIN:-}" != "1" ]] &&
  [[ "${NANOBK_UI:-}" != "0" ]] &&
  [[ "${NO_COLOR:-}" == "" ]] &&
  [[ "${CI:-}" == "" ]] &&
  [[ -t 1 ]]
}

# ── Resolve log directory ─────────────────────────────────────────────────

_oplog_dir=""
_oplog_current_file=""

_oplog_resolve_dir() {
  # Check NANOBK_OPLOG_DIR first (test convenience), then NANOBK_LOG_DIR
  local dir="${NANOBK_OPLOG_DIR:-${NANOBK_LOG_DIR:-}}"
  if [[ -n "$dir" ]] && [[ -d "$dir" ]]; then
    _oplog_dir="$dir"
    return 0
  fi

  # Prefer /var/log/nanobk if writable
  if [[ -d "/var/log/nanobk" ]] && [[ -w "/var/log/nanobk" ]]; then
    _oplog_dir="/var/log/nanobk"
    return 0
  fi

  # Try to create /var/log/nanobk if we have root
  if [[ "${EUID:-$(id -u)}" == "0" ]] && [[ -d "/var/log" ]]; then
    mkdir -p /var/log/nanobk 2>/dev/null && _oplog_dir="/var/log/nanobk" && return 0
  fi

  # Fallback: TMPDIR or /tmp
  local tmp="${TMPDIR:-/tmp}"
  _oplog_dir="${tmp%/}/nanobk-logs"
  mkdir -p "$_oplog_dir" 2>/dev/null || true
}

# ── Initialize log file ───────────────────────────────────────────────────

# Usage: oplog_init [label]
# Creates a timestamped log file and returns its path via _oplog_current_file.
oplog_init() {
  local label="${1:-install}"
  local safe_label
  safe_label=$(oplog_redact "$label")
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "unknown")

  _oplog_resolve_dir

  _oplog_current_file="${_oplog_dir}/${safe_label}-${timestamp}.log"

  # Create empty file with restrictive permissions
  : > "$_oplog_current_file" 2>/dev/null || true
  chmod 600 "$_oplog_current_file" 2>/dev/null || true

  # Write header
  _oplog_write_raw "# NanoBK Proxy Suite — Operation Log"
  _oplog_write_raw "# Started: $(date 2>/dev/null || echo 'unknown')"
  _oplog_write_raw "# Label: ${safe_label}"
  _oplog_write_raw "# ---"
  _oplog_write_raw ""

  echo "$_oplog_current_file"
}

# ── Get current log path ──────────────────────────────────────────────────

oplog_path() {
  echo "${_oplog_current_file:-}"
}

# ── Internal: raw write (no redaction, for headers only) ──────────────────

_oplog_write_raw() {
  local msg="$1"
  if [[ -n "${_oplog_current_file:-}" ]]; then
    echo "$msg" >> "$_oplog_current_file" 2>/dev/null || true
  fi
}

# ── Append to log (redacted) ──────────────────────────────────────────────

# Usage: oplog_write "message"
# Always redacts before writing to prevent secret leakage.
oplog_write() {
  local msg="$1"
  if [[ -n "${_oplog_current_file:-}" ]]; then
    local redacted
    redacted=$(oplog_redact "$msg")
    echo "$redacted" >> "$_oplog_current_file" 2>/dev/null || true
  fi
}

# ── Redaction helper ──────────────────────────────────────────────────────

# Strips sensitive values from a string before logging.
# Usage: oplog_redact "output text"
oplog_redact() {
  local text="$1"

  # Redact common token patterns — conservative, err on the side of redacting more
  text=$(printf '%s\n' "$text" | sed -E \
    -e 's/[0-9]{8,10}:[A-Za-z0-9_-]{30,}/[REDACTED_BOT_TOKEN]/g' \
    -e 's/(SUB_TOKEN=)[^ ]*/\1[REDACTED]/g' \
    -e "s/(SUB_TOKEN=')[^']*'/\1[REDACTED]'/g" \
    -e 's/(SUB_TOKEN=")[^"]*"/\1[REDACTED]"/g' \
    -e 's/(ADMIN_TOKEN=)[^ ]*/\1[REDACTED]/g' \
    -e "s/(ADMIN_TOKEN=')[^']*'/\1[REDACTED]'/g" \
    -e 's/(ADMIN_TOKEN=")[^"]*"/\1[REDACTED]"/g' \
    -e 's/(NANOB_TOKEN=)[^ ]*/\1[REDACTED]/g' \
    -e "s/(NANOB_TOKEN=')[^']*'/\1[REDACTED]'/g" \
    -e 's/(NANOB_TOKEN=")[^"]*"/\1[REDACTED]"/g' \
    -e 's/(CF_API_TOKEN=)[^ ]*/\1[REDACTED]/g' \
    -e "s/(CF_API_TOKEN=')[^']*'/\1[REDACTED]'/g" \
    -e 's/(CF_API_TOKEN=")[^"]*"/\1[REDACTED]"/g' \
    -e 's/(REALITY_PRIVATE_KEY=)[^ ]*/\1[REDACTED]/g' \
    -e "s/(REALITY_PRIVATE_KEY=')[^']*'/\1[REDACTED]'/g" \
    -e 's/(REALITY_PRIVATE_KEY=")[^"]*"/\1[REDACTED]"/g' \
    -e 's/(PRIVATE_KEY=)[^ ]*/\1[REDACTED]/g' \
    -e "s/(PRIVATE_KEY=')[^']*'/\1[REDACTED]'/g" \
    -e 's/(PRIVATE_KEY=")[^"]*"/\1[REDACTED]"/g' \
    -e 's/(SECRET=)[A-Za-z0-9_-]{4,}/\1[REDACTED]/g' \
    -e "s/(SECRET=')[^']*'/\1[REDACTED]'/g" \
    -e 's/(SECRET=")[^"]*"/\1[REDACTED]"/g' \
    -e 's/(KEY=)[A-Za-z0-9_-]{8,}/\1[REDACTED]/g' \
    -e "s/(KEY=')[^']*'/\1[REDACTED]'/g" \
    -e 's/(KEY=")[^"]*"/\1[REDACTED]"/g' \
    -e 's/(TOKEN=)[A-Za-z0-9_-]{4,}/\1[REDACTED]/g' \
    -e "s/(TOKEN=')[^']*'/\1[REDACTED]'/g" \
    -e 's/(TOKEN=")[^"]*"/\1[REDACTED]"/g' \
    -e 's/(password=)[^ ]*/\1[REDACTED]/gi' \
    -e "s/(password=')[^']*'/\1[REDACTED]'/gi" \
    -e 's/(password=")[^"]*"/\1[REDACTED]"/gi' \
    -e 's/(Authorization: Bearer )[A-Za-z0-9._-]+/\1[REDACTED]/g' \
    -e 's|https://[a-zA-Z0-9.-]+\.workers\.dev[^ ]*|[REDACTED_WORKERS_URL]|g' \
    -e 's|https://[a-zA-Z0-9.-]+\.pages\.dev[^ ]*|[REDACTED_PAGES_URL]|g' \
    -e 's/([?&](admin_)?token=)[^& ]*/\1[REDACTED]/gi' \
    -e 's/([?&]sub_token=)[^& ]*/\1[REDACTED]/gi' \
    2>/dev/null || echo "$text")

  echo "$text"
}

# ── Run command with logging (hidden output) ──────────────────────────────

# Captures command output to log. Screen only shows label + success/failure.
# On failure, shows log path hint.
#
# Usage: oplog_run_hidden "label" command [args...]
# Returns: command's exit code
oplog_run_hidden() {
  local label="$1"
  shift
  local cmd=("$@")

  # Ensure log is initialized
  if [[ -z "${_oplog_current_file:-}" ]]; then
    oplog_init "pilot"
  fi

  oplog_write "--- ${label} ---"
  local cmd_display="${cmd[*]}"
  local cmd_redacted
  cmd_redacted=$(oplog_redact "$cmd_display")
  oplog_write "Command: ${cmd_redacted}"
  oplog_write ""

  local output=""
  local rc=0

  # Capture both stdout and stderr
  output=$("${cmd[@]}" 2>&1) || rc=$?

  # Redact and log
  local redacted
  redacted=$(oplog_redact "$output")
  oplog_write "$redacted"
  oplog_write ""
  oplog_write "Exit code: ${rc}"
  oplog_write ""

  # Display based on verbosity
  if [[ "${NANOBK_VERBOSE:-}" == "1" ]]; then
    # Show redacted output
    echo "$redacted"
  fi

  return $rc
}

# ── Run command with logging (visible output) ─────────────────────────────

# Captures command output to log AND shows it on screen.
# Output is redacted before display.
#
# Usage: oplog_run "description" command [args...]
# Returns: command's exit code
oplog_run() {
  local desc="$1"
  shift
  local cmd=("$@")

  # Ensure log is initialized
  if [[ -z "${_oplog_current_file:-}" ]]; then
    oplog_init "pilot"
  fi

  oplog_write "--- ${desc} ---"
  local cmd_display="${cmd[*]}"
  local cmd_redacted
  cmd_redacted=$(oplog_redact "$cmd_display")
  oplog_write "Command: ${cmd_redacted}"
  oplog_write ""

  local output=""
  local rc=0

  # Capture both stdout and stderr
  output=$("${cmd[@]}" 2>&1) || rc=$?

  # Redact and log
  local redacted
  redacted=$(oplog_redact "$output")
  oplog_write "$redacted"
  oplog_write ""
  oplog_write "Exit code: ${rc}"
  oplog_write ""

  # Always show redacted output (this is the visible variant)
  echo "$redacted"

  return $rc
}

# ── Log hint on failure ───────────────────────────────────────────────────

# Call after a failed operation to remind the user where logs are.
# Usage: oplog_hint_on_failure [custom_message]
oplog_hint_on_failure() {
  local custom_msg="${1:-操作失败}"

  if [[ -n "${_oplog_current_file:-}" ]] && [[ -f "$_oplog_current_file" ]]; then
    echo ""
    if [[ "${NANOBK_PLAIN:-}" == "1" ]] || ! _oplog_has_color; then
      echo "  ${custom_msg}。详细日志: ${_oplog_current_file}"
    else
      echo -e "  ${custom_msg}。"
      echo -e "  详细日志 → \033[0;36m${_oplog_current_file}\033[0m"
    fi
  fi
}

# ── Close log ─────────────────────────────────────────────────────────────

oplog_close() {
  local status="${1:-completed}"
  local safe_status
  safe_status=$(oplog_redact "$status")
  _oplog_write_raw "# ---"
  _oplog_write_raw "# Finished: $(date 2>/dev/null || echo 'unknown')"
  _oplog_write_raw "# Status: ${safe_status}"
}
