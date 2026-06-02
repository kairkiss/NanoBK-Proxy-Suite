#!/usr/bin/env bash
# NanoBK Proxy Suite — Operation Log Skeleton
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
#
# Source this file; do not execute directly.

# ── Guard: prevent double-source ──────────────────────────────────────────

if [[ "${_NANOBK_OPLOG_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_NANOBK_OPLOG_LOADED=1

# ── Resolve log directory ─────────────────────────────────────────────────

_oplog_dir=""
_oplog_current_file=""

_oplog_resolve_dir() {
  if [[ -n "${NANOBK_LOG_DIR:-}" ]] && [[ -d "$NANOBK_LOG_DIR" ]]; then
    _oplog_dir="$NANOBK_LOG_DIR"
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
  local timestamp
  timestamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "unknown")

  _oplog_resolve_dir

  _oplog_current_file="${_oplog_dir}/${label}-${timestamp}.log"

  # Create empty file
  : > "$_oplog_current_file" 2>/dev/null || true

  # Write header
  {
    echo "# NanoBK Proxy Suite — Operation Log"
    echo "# Started: $(date 2>/dev/null || echo 'unknown')"
    echo "# Label: ${label}"
    echo "# ---"
    echo ""
  } >> "$_oplog_current_file" 2>/dev/null || true

  echo "$_oplog_current_file"
}

# ── Get current log path ──────────────────────────────────────────────────

oplog_path() {
  echo "${_oplog_current_file:-}"
}

# ── Append to log (redacted) ──────────────────────────────────────────────

# Usage: oplog_write "message"
oplog_write() {
  local msg="$1"
  if [[ -n "${_oplog_current_file:-}" ]]; then
    echo "$msg" >> "$_oplog_current_file" 2>/dev/null || true
  fi
}

# ── Redaction helper ──────────────────────────────────────────────────────

# Strips sensitive values from a string before logging.
# Usage: oplog_redact "output text"
oplog_redact() {
  local text="$1"

  # Redact common token patterns
  text=$(echo "$text" | sed -E \
    -e 's/[0-9]{8,10}:[A-Za-z0-9_-]{30,}/[REDACTED_BOT_TOKEN]/g' \
    -e 's/CF_API_TOKEN[= ][^ ]+/CF_API_TOKEN=[REDACTED]/g' \
    -e 's/TOKEN[= ][A-Za-z0-9_-]{20,}/TOKEN=[REDACTED]/g' \
    -e 's/SECRET[= ][A-Za-z0-9_-]{20,}/SECRET=[REDACTED]/g' \
    -e 's/KEY[= ][A-Za-z0-9_-]{20,}/KEY=[REDACTED]/g' \
    -e 's/password[= ][^ ]+/password=[REDACTED]/gi' \
    -e 's/PRIVATE[= ][^ ]+/PRIVATE=[REDACTED]/g' \
    -e 's|https://[a-zA-Z0-9.-]+\.workers\.dev[^ ]*|[REDACTED_WORKERS_URL]|g' \
    -e 's|https://[a-zA-Z0-9.-]+\.pages\.dev[^ ]*|[REDACTED_PAGES_URL]|g' \
    2>/dev/null || echo "$text")

  echo "$text"
}

# ── Run command with logging ──────────────────────────────────────────────

# Captures command output to log. In non-verbose mode, only shows success/failure.
# In verbose mode, also shows output inline.
#
# Usage: oplog_run "description" command [args...]
# Returns: command's exit code
oplog_run() {
  local desc="$1"
  shift
  local cmd=("$@")

  oplog_write "--- ${desc} ---"
  oplog_write "Command: ${cmd[*]}"
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
    # Show full (redacted) output
    echo "$redacted"
  fi

  return $rc
}

# ── Log hint on failure ───────────────────────────────────────────────────

# Call after a failed operation to remind the user where logs are.
# Usage: oplog_hint_on_failure [custom_message]
oplog_hint_on_failure() {
  local custom_msg="${1:-操作失败}"

  if [[ -n "${_oplog_current_file:-}" ]] && [[ -f "$_oplog_current_file" ]]; then
    echo ""
    if [[ "${NANOBK_PLAIN:-}" == "1" ]]; then
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
  oplog_write "# ---"
  oplog_write "# Finished: $(date 2>/dev/null || echo 'unknown')"
  oplog_write "# Status: ${status}"
}
