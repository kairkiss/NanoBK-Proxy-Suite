#!/usr/bin/env bash
# NanoBK Proxy Suite — Common library
# Shared functions for logging, dry-run, fingerprints, etc.
# Source this file; do not execute directly.

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Logging ─────────────────────────────────────────────────────────────────

log()   { echo -e "${BLUE}[INFO]${NC}  $*"; }

# Cross-platform ISO date
iso_date() {
  date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S%z'
}
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
debug() { [[ "${NANOBK_DEBUG:-}" == "1" ]] && echo -e "${CYAN}[DEBUG]${NC} $*" || true; }

die() {
  err "$*"
  exit 1
}

# ── Dry-run aware execution ────────────────────────────────────────────────

# Global flag: NANOBK_DRY_RUN=1 means print-only
NANOBK_DRY_RUN="${NANOBK_DRY_RUN:-0}"

# Run a command, or print it if dry-run.
# Usage: run_cmd description command [args...]
run_cmd() {
  local desc="$1"
  shift
  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} $desc"
    echo -e "  ${CYAN}  cmd:${NC} $*"
  else
    log "$desc"
    "$@"
  fi
}

# Run a command silently (no output unless it fails)
run_cmd_silent() {
  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    return 0
  fi
  "$@"
}

# Write a file, or print it if dry-run.
# Usage: write_file path mode content
write_file() {
  local path="$1"
  local mode="$2"
  local content="$3"
  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} write ${path} (mode ${mode})"
    echo -e "${CYAN}---content---${NC}"
    echo "$content" | head -20
    if [[ $(echo "$content" | wc -l) -gt 20 ]]; then
      echo -e "${CYAN}  ... ($(echo "$content" | wc -l) lines total)${NC}"
    fi
    echo -e "${CYAN}---end---${NC}"
  else
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    chmod "$mode" "$path"
    ok "wrote ${path} (mode ${mode})"
  fi
}

# Create a directory, or print it if dry-run.
ensure_dir() {
  local dir="$1"
  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} mkdir -p ${dir}"
  else
    mkdir -p "$dir"
  fi
}

# ── Fingerprints (for safe logging) ────────────────────────────────────────

fingerprint() {
  local s="$1"
  local len=${#s}
  if [[ $len -le 12 ]]; then
    echo "${s:0:3}...${s: -3}"
  else
    echo "${s:0:6}...${s: -6}"
  fi
}

# ── Validation helpers ─────────────────────────────────────────────────────

require_var() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    die "Required variable ${name} is empty"
  fi
}

require_file() {
  local path="$1"
  local desc="${2:-file}"
  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    return 0
  fi
  [[ -f "$path" ]] || die "${desc} not found: ${path}"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    die "Required command not found: ${cmd}"
  fi
}

# ── String helpers ──────────────────────────────────────────────────────────

# Replace all __KEY__ placeholders in a template string.
# Usage: render_template "template string" KEY1=value1 KEY2=value2 ...
render_template() {
  local template="$1"
  shift
  local result="$template"
  for kv in "$@"; do
    local key="${kv%%=*}"
    local value="${kv#*=}"
    result="${result//__${key}__/${value}}"
  done
  echo "$result"
}

# ── Confirmation ───────────────────────────────────────────────────────────

confirm_or_die() {
  local prompt="${1:-Continue?}"
  if [[ "$NANOBK_YES" == "1" ]]; then
    return 0
  fi
  echo -en "${YELLOW}${prompt} [y/N]${NC} "
  read -r reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    die "Aborted by user"
  fi
}
