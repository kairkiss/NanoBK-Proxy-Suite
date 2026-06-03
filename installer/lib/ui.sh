#!/usr/bin/env bash
# NanoBK Proxy Suite — UI Display Layer v1.8.10
#
# Provides unified, product-quality CLI display functions for the installer.
# This file only handles display — it never makes deployment decisions.
#
# Environment variables:
#   NANOBK_PLAIN=1     — disable color, emoji, and complex progress (plainest text)
#   NANOBK_NO_EMOJI=1  — disable emoji only; color and symbols may remain
#   NANOBK_VERBOSE=1   — show detailed command output / extra log hints
#   NANOBK_UI=0        — completely bypass new UI (fallback to legacy output)
#
# Source this file; do not execute directly.

# ── Guard: prevent double-source ──────────────────────────────────────────

if [[ "${_NANOBK_UI_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_NANOBK_UI_LOADED=1

# ── Capability detection ──────────────────────────────────────────────────

_ui_has_color=0
_ui_has_emoji=0
_ui_is_tty=0
_ui_term_width=80

ui_detect_capabilities() {
  # TTY check
  if [[ -t 1 ]] && [[ -t 2 ]]; then
    _ui_is_tty=1
  fi

  # Color: available unless PLAIN or NO_COLOR or non-TTY or CI
  if [[ "${NANOBK_PLAIN:-}" != "1" ]] && [[ "${NO_COLOR:-}" == "" ]] && [[ "${CI:-}" == "" ]] && [[ "$_ui_is_tty" == "1" ]]; then
    _ui_has_color=1
  fi

  # Emoji: available unless PLAIN or NO_EMOJI or non-TTY or dumb terminal
  if [[ "${NANOBK_PLAIN:-}" != "1" ]] && [[ "${NANOBK_NO_EMOJI:-}" != "1" ]] && [[ "$_ui_is_tty" == "1" ]] && [[ "${TERM:-}" != "dumb" ]]; then
    _ui_has_emoji=1
  fi

  # Terminal width (fallback to 80)
  if command -v tput &>/dev/null && [[ "$_ui_is_tty" == "1" ]]; then
    local cols
    cols=$(tput cols 2>/dev/null || echo "80")
    _ui_term_width="${cols:-80}"
  fi
}

# Auto-detect on source
ui_detect_capabilities

# ── Color codes ───────────────────────────────────────────────────────────

_ui_c_red=""
_ui_c_green=""
_ui_c_yellow=""
_ui_c_blue=""
_ui_c_cyan=""
_ui_c_bold=""
_ui_c_reset=""

_ui_apply_colors() {
  if [[ "$_ui_has_color" == "1" ]]; then
    _ui_c_red='\033[0;31m'
    _ui_c_green='\033[0;32m'
    _ui_c_yellow='\033[1;33m'
    _ui_c_blue='\033[0;34m'
    _ui_c_cyan='\033[0;36m'
    _ui_c_bold='\033[1m'
    _ui_c_reset='\033[0m'
  else
    _ui_c_red=""
    _ui_c_green=""
    _ui_c_yellow=""
    _ui_c_blue=""
    _ui_c_cyan=""
    _ui_c_bold=""
    _ui_c_reset=""
  fi
}

_ui_apply_colors

# ── Emoji / symbol helpers ────────────────────────────────────────────────

_ui_sym() {
  local emoji="$1" plain="$2"
  if [[ "$_ui_has_emoji" == "1" ]]; then
    echo -n "$emoji"
  else
    echo -n "$plain"
  fi
}

# ── Banner / Brand Identity ───────────────────────────────────────────────

# Box-drawing banner for interactive terminals (≤80 cols, 7 lines)
_ui_banner_box() {
  local version="${1:-}"
  local subtitle="${2:-}"
  local vdisp="${version:+ ${version}}"

  local line1=" NanoBK Proxy Suite${vdisp}"
  local line2=" 一条命令，完成 VPS 代理部署"
  local line3=""
  local line4=" ${subtitle}"

  # Calculate box width (max of content lines, min 46, max 52)
  local max_len=${#line1}
  [[ ${#line2} -gt $max_len ]] && max_len=${#line2}
  [[ -n "$subtitle" ]] && [[ ${#line4} -gt $max_len ]] && max_len=${#line4}
  local inner=$((max_len + 2))
  [[ $inner -lt 46 ]] && inner=46
  [[ $inner -gt 52 ]] && inner=52

  # Build horizontal lines
  local top_bot=""
  local mid=""
  for ((i=0; i<inner; i++)); do top_bot+="─"; done
  for ((i=0; i<inner; i++)); do mid+=" "; done

  # Pad content lines to inner width
  local pad1="" pad2="" pad4=""
  local diff1=$((inner - ${#line1}))
  local diff2=$((inner - ${#line2}))
  for ((i=0; i<diff1; i++)); do pad1+=" "; done
  for ((i=0; i<diff2; i++)); do pad2+=" "; done

  echo ""
  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_cyan}╭${top_bot}╮${_ui_c_reset}"
    echo -e "  ${_ui_c_cyan}│${_ui_c_reset}${_ui_c_bold}${line1}${_ui_c_reset}${pad1}${_ui_c_cyan}│${_ui_c_reset}"
    echo -e "  ${_ui_c_cyan}│${_ui_c_reset}${line2}${pad2}${_ui_c_cyan}│${_ui_c_reset}"
    echo -e "  ${_ui_c_cyan}│${_ui_c_reset}${mid}${_ui_c_cyan}│${_ui_c_reset}"
    if [[ -n "$subtitle" ]]; then
      local diff4=$((inner - ${#line4}))
      for ((i=0; i<diff4; i++)); do pad4+=" "; done
      echo -e "  ${_ui_c_cyan}│${_ui_c_reset}${_ui_c_bold}${line4}${_ui_c_reset}${pad4}${_ui_c_cyan}│${_ui_c_reset}"
    fi
    echo -e "  ${_ui_c_cyan}╰${top_bot}╯${_ui_c_reset}"
  else
    echo "  +${top_bot}+"
    echo "  |${line1}${pad1}|"
    echo "  |${line2}${pad2}|"
    echo "  |${mid}|"
    if [[ -n "$subtitle" ]]; then
      local diff4=$((inner - ${#line4}))
      for ((i=0; i<diff4; i++)); do pad4+=" "; done
      echo "  |${line4}${pad4}|"
    fi
    echo "  +${top_bot}+"
  fi
  echo ""
}

# PLAIN / non-TTY banner: clean text, no box, no ANSI, no emoji
_ui_banner_plain() {
  local version="${1:-}"
  local subtitle="${2:-}"
  local vdisp="${version:+ ${version}}"

  echo ""
  echo "NanoBK Proxy Suite${vdisp}"
  echo "  一条命令，完成 VPS 代理部署"
  if [[ -n "$subtitle" ]]; then
    echo "  ${subtitle}"
  fi
  echo ""
}

ui_banner() {
  local version="${1:-}"
  local subtitle="${2:-}"

  # UI=0: legacy bypass — minimal traditional output
  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo ""
    echo "NanoBK Proxy Suite ${version}"
    [[ -n "$subtitle" ]] && echo "  ${subtitle}"
    echo ""
    return 0
  fi

  # PLAIN or non-TTY: clean text fallback
  if [[ "${NANOBK_PLAIN:-}" == "1" ]] || [[ "$_ui_is_tty" != "1" ]]; then
    _ui_banner_plain "$version" "$subtitle"
    return 0
  fi

  # Default: branded box banner
  _ui_banner_box "$version" "$subtitle"
}

# ── Section header ────────────────────────────────────────────────────────

ui_section() {
  local title="$1"
  local step_num="${2:-}"
  local step_total="${3:-}"

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo ""
    echo "── $title ──"
    echo ""
    return 0
  fi

  # PLAIN mode: pure ASCII, no Unicode bars
  if [[ "${NANOBK_PLAIN:-}" == "1" ]]; then
    echo ""
    if [[ -n "$step_num" ]] && [[ -n "$step_total" ]]; then
      echo "  Step ${step_num}/${step_total} - ${title}"
    else
      echo "  ${title}"
    fi
    echo ""
    return 0
  fi

  local prefix=""
  if [[ -n "$step_num" ]] && [[ -n "$step_total" ]]; then
    # Progress bar: [■■■□□□] 3/6
    local filled=$((step_num))
    local empty=$((step_total - step_num))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="■"; done
    for ((i=0; i<empty; i++)); do bar+="□"; done

    if [[ "$_ui_has_color" == "1" ]]; then
      prefix="${_ui_c_green}${bar}${_ui_c_reset} ${step_num}/${step_total}  "
    else
      prefix="${bar} ${step_num}/${step_total}  "
    fi
  fi

  echo ""
  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${prefix}${_ui_c_bold}── ${title} ──${_ui_c_reset}"
  else
    echo "  ${prefix}── ${title} ──"
  fi
  echo ""
}

# ── Step indicator ────────────────────────────────────────────────────────

ui_step() {
  local num="$1"
  local total="$2"
  local desc="$3"

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "Step ${num}/${total}: ${desc}"
    return 0
  fi

  if [[ "${NANOBK_PLAIN:-}" == "1" ]]; then
    echo "  Step ${num}/${total}: ${desc}"
    return 0
  fi

  local sym
  sym=$(_ui_sym "→" ">")

  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_cyan}${sym}${_ui_c_reset} [${num}/${total}] ${desc}"
  else
    echo "  ${sym} [${num}/${total}] ${desc}"
  fi
}

# ── Info message ──────────────────────────────────────────────────────────

ui_info() {
  local msg="$1"

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "[INFO]  ${msg}"
    return 0
  fi

  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_blue}[INFO]${_ui_c_reset}  ${msg}"
  else
    echo "  [INFO]  ${msg}"
  fi
}

# ── Success message ───────────────────────────────────────────────────────

ui_success() {
  local msg="$1"

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "[OK]    ${msg}"
    return 0
  fi

  local sym
  sym=$(_ui_sym "✓" "OK")

  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_green}${sym}${_ui_c_reset}  ${msg}"
  else
    echo "  ${sym}  ${msg}"
  fi
}

# ── Warning message ───────────────────────────────────────────────────────

ui_warn() {
  local msg="$1"

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "[WARN]  ${msg}" >&2
    return 0
  fi

  local sym
  sym=$(_ui_sym "!" "WARN")

  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_yellow}${sym}${_ui_c_reset}  ${msg}" >&2
  else
    echo "  ${sym}  ${msg}" >&2
  fi
}

# ── Error message ─────────────────────────────────────────────────────────

ui_error() {
  local msg="$1"

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "[ERROR] ${msg}" >&2
    return 0
  fi

  local sym
  sym=$(_ui_sym "✕" "ERR")

  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_red}${sym}${_ui_c_reset}  ${msg}" >&2
  else
    echo "  ${sym}  ${msg}" >&2
  fi
}

# ── Progress bar ──────────────────────────────────────────────────────────

# Usage: ui_progress <current> <total> [label]
ui_progress() {
  local current="$1"
  local total="$2"
  local label="${3:-}"

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "Progress: ${current}/${total}"
    return 0
  fi

  # PLAIN mode: pure ASCII
  if [[ "${NANOBK_PLAIN:-}" == "1" ]]; then
    echo "  Step ${current}/${total} - ${label}"
    return 0
  fi

  if [[ "$_ui_has_color" == "1" ]]; then
    local filled=$((current))
    local empty=$((total - current))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="■"; done
    for ((i=0; i<empty; i++)); do bar+="□"; done
    echo -e "  ${_ui_c_green}${bar}${_ui_c_reset} ${current}/${total} ${label}"
  else
    echo "  Step ${current}/${total} ${label}"
  fi
}

# ── Spinner (non-TTY safe) ───────────────────────────────────────────────

_ui_spinner_pid=""

ui_spinner_start() {
  local msg="${1:-Processing...}"

  # PLAIN, non-TTY, or UI=0: just print text, no animation
  if [[ "${NANOBK_PLAIN:-}" == "1" ]] || [[ "${NANOBK_UI:-}" == "0" ]] || [[ "$_ui_is_tty" != "1" ]]; then
    echo "  ${msg}"
    return 0
  fi

  local frames=('-' '\' '|' '/')

  (
    while true; do
      for frame in "${frames[@]}"; do
        if [[ "$_ui_has_color" == "1" ]]; then
          printf "\r  ${_ui_c_cyan}%s${_ui_c_reset} %s" "$frame" "$msg"
        else
          printf "\r  %s %s" "$frame" "$msg"
        fi
        sleep 0.2
      done
    done
  ) &
  _ui_spinner_pid=$!
}

ui_spinner_stop() {
  if [[ -n "${_ui_spinner_pid:-}" ]]; then
    kill "$_ui_spinner_pid" 2>/dev/null || true
    wait "$_ui_spinner_pid" 2>/dev/null || true
    _ui_spinner_pid=""
    # Only clear line on TTY and not in PLAIN mode
    if [[ "$_ui_is_tty" == "1" ]] && [[ "${NANOBK_PLAIN:-}" != "1" ]]; then
      printf "\r\033[K"
    fi
  fi
}

# ── Summary card ──────────────────────────────────────────────────────────

# Usage: ui_summary_card "Title" "key1: value1" "key2: value2" ...
ui_summary_card() {
  local title="$1"
  shift
  local entries=("$@")

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "=== ${title} ==="
    for entry in "${entries[@]}"; do
      echo "  ${entry}"
    done
    echo ""
    return 0
  fi

  echo ""
  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_bold}╔═══ ${title} ═══╗${_ui_c_reset}"
  else
    echo "  === ${title} ==="
  fi

  for entry in "${entries[@]}"; do
    # Color status words
    local display="$entry"
    case "$entry" in
      *": installed"*|*": verified"*|*": healthy"*|*": passed"*)
        if [[ "$_ui_has_color" == "1" ]]; then
          display=$(echo "$entry" | sed -E 's/(installed|verified|healthy|passed)/\\033[0;32m\1\\033[0m/g')
        fi
        ;;
      *": failed"*)
        if [[ "$_ui_has_color" == "1" ]]; then
          display=$(echo "$entry" | sed -E 's/(failed)/\\033[0;31m\1\\033[0m/g')
        fi
        ;;
      *": dry-run"*|*": planned"*|*": manual_pending"*|*": skipped"*|*": unknown"*)
        if [[ "$_ui_has_color" == "1" ]]; then
          display=$(echo "$entry" | sed -E 's/(dry-run|planned|manual_pending|skipped|unknown)/\\033[1;33m\1\\033[0m/g')
        fi
        ;;
    esac
    echo -e "  ${display}"
  done

  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_bold}╚═══════════════════════════╝${_ui_c_reset}"
  else
    echo "  ========================="
  fi
  echo ""
}

# ── Recovery block ────────────────────────────────────────────────────────

# Usage: ui_recovery_block "recovery command 1" "recovery command 2" ...
ui_recovery_block() {
  local commands=("$@")

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "  可以稍后继续："
    for cmd in "${commands[@]}"; do
      echo "    \$ ${cmd}"
    done
    echo ""
    return 0
  fi

  echo ""
  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_yellow}可以稍后继续${_ui_c_reset}"
    echo "  下面这些命令可以帮助你恢复或重新执行当前阶段："
    echo ""
    for cmd in "${commands[@]}"; do
      echo -e "    ${_ui_c_cyan}\$${_ui_c_reset} ${cmd}"
    done
  else
    echo "  可以稍后继续"
    echo "  下面这些命令可以帮助你恢复或重新执行当前阶段："
    echo ""
    for cmd in "${commands[@]}"; do
      echo "    \$ ${cmd}"
    done
  fi
  echo ""
}

# ── Verbose / log hint ────────────────────────────────────────────────────

# Usage: ui_log_hint "log file path"
ui_log_hint() {
  local log_path="${1:-}"

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    [[ -n "$log_path" ]] && echo "  详细日志: ${log_path}"
    return 0
  fi

  if [[ "${NANOBK_VERBOSE:-}" == "1" ]]; then
    if [[ -n "$log_path" ]]; then
      if [[ "$_ui_has_color" == "1" ]]; then
        echo -e "  ${_ui_c_cyan}详细日志${_ui_c_reset} → ${log_path}"
      else
        echo "  详细日志 → ${log_path}"
      fi
    fi
  fi
}

# ── Plain text description block ──────────────────────────────────────────

# Shows a human-friendly description of what the next step does.
# Usage: ui_describe "NanoBK 正在检查你的 VPS 环境" "系统版本是否支持" "必要依赖是否可安装"
ui_describe() {
  local headline="$1"
  shift
  local items=("$@")

  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "  ${headline}"
    return 0
  fi

  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_bold}${headline}${_ui_c_reset}"
  else
    echo "  ${headline}"
  fi

  if [[ "${#items[@]}" -gt 0 ]]; then
    echo "  这一步会确认："
    for item in "${items[@]}"; do
      local bullet
      bullet=$(_ui_sym "·" "-")
      echo "    ${bullet} ${item}"
    done
  fi

  echo "  你不需要手动操作。"
  echo ""
}

# ── Token / secret safety reminder ────────────────────────────────────────

ui_token_reminder() {
  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "  安全提示："
    echo "    - 输入 token 时请不要截图，也不要把它发到聊天、issue 或日志里。"
    echo "    - NanoBK 会尽量隐藏敏感信息，但你仍然应该把 token 当作密码保管。"
    echo "    - 如果 token 暴露，请立即在对应平台 revoke / regenerate。"
    return 0
  fi

  local lock
  lock=$(_ui_sym "🔒" "[SECURE]")

  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_cyan}${lock}${_ui_c_reset}  安全提示"
  else
    echo "  ${lock}  安全提示"
  fi
  echo "    - 输入 token 时请不要截图，也不要把它发到聊天、issue 或日志里。"
  echo "    - NanoBK 会尽量隐藏敏感信息，但你仍然应该把 token 当作密码保管。"
  echo "    - 如果 token 暴露，请立即在对应平台 revoke / regenerate。"
}

# ── Decorative divider ────────────────────────────────────────────────────

ui_divider() {
  local width=60

  # PLAIN mode: use simple ASCII dash
  if [[ "${NANOBK_PLAIN:-}" == "1" ]]; then
    printf "  "
    printf "%0.s-" $(seq 1 $width)
    printf "\n"
    return 0
  fi

  local char="${1:-─}"

  if [[ "$_ui_has_color" == "1" ]]; then
    printf "  ${_ui_c_cyan}"
    printf "%0.s${char}" $(seq 1 $width)
    printf "${_ui_c_reset}\n"
  else
    printf "  "
    printf "%0.s${char}" $(seq 1 $width)
    printf "\n"
  fi
}

# ── Dry-run notice ────────────────────────────────────────────────────────

# Displays a clear dry-run disclaimer.
# Usage: ui_dry_run_notice
ui_dry_run_notice() {
  if [[ "${NANOBK_UI:-}" == "0" ]]; then
    echo "  [DRY-RUN] 这是 dry-run 摘要，没有执行真实部署。"
    echo "  [DRY-RUN] This is a dry-run summary. No real deployment was performed."
    return 0
  fi

  local info
  info=$(_ui_sym "ℹ" "[DRY-RUN]")

  echo ""
  if [[ "$_ui_has_color" == "1" ]]; then
    echo -e "  ${_ui_c_cyan}${info}${_ui_c_reset}  这是 dry-run 摘要，没有执行真实部署。"
    echo -e "  ${_ui_c_cyan}${info}${_ui_c_reset}  This is a dry-run summary. No real deployment was performed."
  else
    echo "  ${info}  这是 dry-run 摘要，没有执行真实部署。"
    echo "  ${info}  This is a dry-run summary. No real deployment was performed."
  fi
  echo ""
}
