#!/usr/bin/env bash
# NanoBK Proxy Suite — Unified Beginner Installer v1.7.8
#
# Interactive entry point for NanoBK Proxy Suite.
# Guides users through VPS deployment, Cloudflare setup, Bot, Web Panel.
#
# Usage:
#   bash installer/install.sh
#   bash installer/install.sh --mode full
#   bash installer/install.sh --mode doctor
#   bash installer/install.sh --mode commands --dry-run

set -Eeuo pipefail

# ── Resolve script directory ───────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Constants ───────────────────────────────────────────────────────────────

REPO_URL="https://github.com/kairkiss/NanoBK-Proxy-Suite"
VERSION="1.7.8"

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Global flags ────────────────────────────────────────────────────────────

DRY_RUN=0
YES=0
LANG_CODE=""
LANG_EXPLICIT=0
MODE=""
MODE_EXPLICIT=0
COMMAND_ONLY=0
REPO_DIR_OVERRIDE=""
SAVE_CONFIG=0
RESUME=0
DEFAULTS=0
CONFIG_FILE=""

# Environment state
ENV_IS_LINUX=0
ENV_HAS_SYSTEMD=0
ENV_HAS_ROOT=0

# Config file path (set after parse)
INSTALLER_CONFIG=""

# ── Helpers ─────────────────────────────────────────────────────────────────

log()   { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

print_cmd() {
  local cmd=("$@")
  printf "  ${CYAN}\$${NC} "
  printf "%q " "${cmd[@]}"
  printf "\n"
}

LAST_RUN_CMD_STATUS="unknown"

run_cmd() {
  local desc="$1"
  shift
  local cmd=("$@")
  LAST_RUN_CMD_STATUS="unknown"

  echo ""
  log "$desc"
  print_cmd "${cmd[@]}"

  if [[ "$COMMAND_ONLY" == "1" ]]; then
    LAST_RUN_CMD_STATUS="commands_only"
    echo -e "  ${YELLOW}(仅生成命令，未执行)${NC}"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    LAST_RUN_CMD_STATUS="dry_run"
    echo -e "  ${CYAN}[DRY-RUN]${NC} 跳过执行"
    return 0
  fi

  if [[ "$YES" != "1" ]]; then
    echo -en "${YELLOW}  是否现在执行？[y/N]${NC} "
    read -r reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      LAST_RUN_CMD_STATUS="skipped_user"
      echo -e "  ${YELLOW}已跳过。你可以手动复制上面的命令执行。${NC}"
      return 0
    fi
  fi

  if "${cmd[@]}"; then
    LAST_RUN_CMD_STATUS="executed"
    return 0
  else
    LAST_RUN_CMD_STATUS="failed"
    return 1
  fi
}

# Critical step helper — menu with default=execute (not skip)
# Returns: 0=executed/success, 1=failed/abort, 2=skipped_user(manual_pending)
run_critical_step() {
  local desc="$1"
  shift
  local cmd=("$@")
  LAST_RUN_CMD_STATUS="unknown"

  echo ""
  log "即将执行关键步骤：${desc}"
  print_cmd "${cmd[@]}"

  if [[ "$COMMAND_ONLY" == "1" ]]; then
    LAST_RUN_CMD_STATUS="commands_only"
    echo -e "  ${YELLOW}(仅生成命令，未执行)${NC}"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    LAST_RUN_CMD_STATUS="dry_run"
    echo -e "  ${CYAN}[DRY-RUN]${NC} 跳过执行"
    return 0
  fi

  echo ""
  echo "    1) 现在执行（推荐）"
  echo "    2) 取消此阶段"
  echo "    3) 稍后手动执行"
  echo "    4) 退出"
  echo ""
  local crit_choice
  prompt crit_choice "请选择" "1"

  case "$crit_choice" in
    1)
      if "${cmd[@]}"; then
        LAST_RUN_CMD_STATUS="executed"
        return 0
      else
        LAST_RUN_CMD_STATUS="failed"
        return 1
      fi
      ;;
    2)
      LAST_RUN_CMD_STATUS="skipped_user"
      echo -e "  ${YELLOW}已取消。${NC}"
      return 2
      ;;
    3)
      LAST_RUN_CMD_STATUS="skipped_user"
      echo -e "  ${YELLOW}已跳过。你可以手动执行上面的命令。${NC}"
      return 0
      ;;
    4|*)
      LAST_RUN_CMD_STATUS="skipped_user"
      return 2
      ;;
  esac
}

# ── Domain validation ──────────────────────────────────────────────────────

is_valid_domain_name() {
  local domain="$1"

  # Must not be empty
  [[ -z "$domain" ]] && return 1

  # Must not be too short or too long
  [[ ${#domain} -lt 3 ]] && return 1
  [[ ${#domain} -gt 253 ]] && return 1

  # Must contain at least one dot
  [[ "$domain" != *.* ]] && return 1

  # Must not start or end with dot
  [[ "$domain" == .* ]] && return 1
  [[ "$domain" == *. ]] && return 1

  # Must not have consecutive dots
  [[ "$domain" == *..* ]] && return 1

  # Must only contain valid chars: a-z A-Z 0-9 . -
  if [[ "$domain" =~ [^a-zA-Z0-9.\-] ]]; then
    return 1
  fi

  # Must not be all numeric
  if [[ "$domain" =~ ^[0-9.]+$ ]]; then
    return 1
  fi

  # Each label must be 1-63 chars, not start/end with hyphen
  local IFS='.'
  local labels=($domain)
  for label in "${labels[@]}"; do
    [[ ${#label} -lt 1 ]] && return 1
    [[ ${#label} -gt 63 ]] && return 1
    [[ "$label" == -* ]] && return 1
    [[ "$label" == *- ]] && return 1
  done

  return 0
}

# ── Control plane dependency helpers ────────────────────────────────────────
# Bot/Web are control-plane-only unless VPS and Cloudflare are both ready.
# "ready" means actually installed/deployed, not just planned or skipped.

vps_ready_for_control_plane() {
  case "${VPS_STAGE_STATUS:-unknown}" in
    installed) return 0 ;;
    *)         return 1 ;;
  esac
}

cf_ready_for_control_plane() {
  case "${CF_STAGE_STATUS:-unknown}" in
    deployed|verified) return 0 ;;
    *)                 return 1 ;;
  esac
}

control_plane_only_required() {
  if ! vps_ready_for_control_plane; then
    return 0
  fi
  if ! cf_ready_for_control_plane; then
    return 0
  fi
  return 1
}

# ── Placeholder / example value detection ──────────────────────────────────

is_placeholder_value() {
  local val="${1,,}"  # lowercase
  case "$val" in
    example.com|example.org|example.net|proxy.example.com|\
    your_domain|your_vps_ip|replace_me|change_me|placeholder|localhost)
      return 0 ;;
    *.example.com|*.example.org|*.example.net|*.example.workers.dev)
      return 0 ;;
    "")
      return 0 ;;
    *)
      return 1 ;;
  esac
}

is_placeholder_worker_url() {
  local url="${1,,}"
  # Strip protocol
  url="${url#https://}"
  url="${url#http://}"
  url="${url%%/*}"
  url="${url%%\?*}"
  is_placeholder_value "$url"
}

# ── Wizard state / resume helpers ───────────────────────────────────────────

WIZARD_STATE_FILE=""

wizard_state_path() {
  if [[ -n "$WIZARD_STATE_FILE" ]]; then
    echo "$WIZARD_STATE_FILE"
    return
  fi
  # Try /opt repo first, then local repo
  if [[ -w "/opt/NanoBK-Proxy-Suite" ]]; then
    WIZARD_STATE_FILE="/opt/NanoBK-Proxy-Suite/.nanobk-wizard-state.json"
  else
    WIZARD_STATE_FILE="${REPO_DIR:-.}/.nanobk-wizard-state.json"
  fi
  echo "$WIZARD_STATE_FILE"
}

wizard_state_write() {
  local phase="$1"
  local state_file
  state_file=$(wizard_state_path)

  # Only save non-sensitive state
  cat > "$state_file" <<STATEEOF
{
  "version": "${VERSION}",
  "current_phase": "${phase}",
  "vps_status": "${VPS_STAGE_STATUS:-unknown}",
  "cf_status": "${CF_STAGE_STATUS:-unknown}",
  "bot_status": "${BOT_STAGE_STATUS:-unknown}",
  "web_status": "${WEB_STAGE_STATUS:-unknown}",
  "domain": "${NANOBK_DOMAIN:-}",
  "cert_mode": "${NANOBK_CERT_MODE:-}",
  "reality_servername": "${NANOBK_REALITY_SERVERNAME:-}",
  "nanok_url": "${NANOBK_NANOK_URL:-}",
  "nanob_url": "${NANOBK_NANOB_URL:-}",
  "nanob_enabled": "${NANOBK_DEPLOY_NANOB:-false}",
  "timestamp": "$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"
}
STATEEOF
}

wizard_state_print() {
  local state_file
  state_file=$(wizard_state_path)

  if [[ ! -f "$state_file" ]]; then
    echo "  没有找到之前的安装状态。"
    return 1
  fi

  echo "  检测到已有 NanoBK 状态："
  echo ""

  # Read values safely
  local phase vps cf bot web domain
  phase=$(python3 -c "import json; d=json.load(open('$state_file')); print(d.get('current_phase','unknown'))" 2>/dev/null || echo "unknown")
  vps=$(python3 -c "import json; d=json.load(open('$state_file')); print(d.get('vps_status','unknown'))" 2>/dev/null || echo "unknown")
  cf=$(python3 -c "import json; d=json.load(open('$state_file')); print(d.get('cf_status','unknown'))" 2>/dev/null || echo "unknown")
  bot=$(python3 -c "import json; d=json.load(open('$state_file')); print(d.get('bot_status','unknown'))" 2>/dev/null || echo "unknown")
  web=$(python3 -c "import json; d=json.load(open('$state_file')); print(d.get('web_status','unknown'))" 2>/dev/null || echo "unknown")
  domain=$(python3 -c "import json; d=json.load(open('$state_file')); print(d.get('domain',''))" 2>/dev/null || echo "")

  echo "    上次阶段: ${phase}"
  echo "    VPS: ${vps}"
  echo "    Cloudflare: ${cf}"
  echo "    Bot: ${bot}"
  echo "    Web: ${web}"
  [[ -n "$domain" ]] && echo "    域名: ${domain}"
  echo ""
}

wizard_state_detect_existing() {
  # Check actual system state
  local vps_ok=0 cf_ok=0 bot_ok=0 web_ok=0

  # VPS check
  if [[ -f "/etc/nanobk/profile.current.json" ]]; then
    vps_ok=1
  fi

  # Cloudflare check
  if [[ -f "${REPO_DIR:-.}/.cloudflare.local.env" ]]; then
    local cf_verify
    cf_verify=$(read_env_value "${REPO_DIR:-.}/.cloudflare.local.env" "NANOBK_VERIFY_STATUS" 2>/dev/null || echo "")
    if [[ "$cf_verify" == "verified" ]]; then
      cf_ok=1
    fi
  fi

  # Bot check
  if [[ -f "${REPO_DIR:-.}/bot/.env" ]]; then
    bot_ok=1
  fi

  # Web check
  if [[ -f "${REPO_DIR:-.}/web/.env" ]]; then
    web_ok=1
  fi

  # If nothing found, no existing state
  if [[ $vps_ok -eq 0 ]] && [[ $cf_ok -eq 0 ]] && [[ $bot_ok -eq 0 ]] && [[ $web_ok -eq 0 ]]; then
    return 1
  fi

  return 0
}

# ── Existing Cloudflare KV recovery ────────────────────────────────────────

check_existing_kv() {
  local binding="$1"
  local wrangler_cmd="$2"

  if [[ "$DRY_RUN" == "1" ]] || [[ "$COMMAND_ONLY" == "1" ]]; then
    return 1  # Assume not existing in dry-run
  fi

  if ! command -v $wrangler_cmd &>/dev/null; then
    return 1
  fi

  local output
  output=$($wrangler_cmd kv namespace list 2>/dev/null) || return 1

  if echo "$output" | grep -qi "\"title\".*\"${binding}\""; then
    return 0  # Found
  fi
  return 1  # Not found
}

# ── Output control character check ─────────────────────────────────────────

check_output_clean() {
  local text="$1"
  # Check for NUL and dangerous control chars (allow tab, newline, CR, ANSI escapes)
  if echo "$text" | python3 -c "
import sys
text = sys.stdin.buffer.read()
for b in text:
    if b == 0:  # NUL
        sys.exit(1)
    if b < 32 and b not in (9, 10, 13):  # tab, LF, CR allowed
        sys.exit(1)
    if b == 127:  # DEL
        sys.exit(1)
sys.exit(0)
" 2>/dev/null; then
    return 0  # Clean
  fi
  return 1  # Has bad chars
}

# ── Test-only mock infrastructure ──────────────────────────────────────────
# Only active when NANOBK_TEST_MOCK=1
# Does NOT connect to VPS or Cloudflare
# Does NOT write to /etc or /root
# All mock output clearly labeled [MOCK]

mock_log() {
  echo -e "  ${CYAN}[MOCK]${NC} $*"
}

mock_deploy_vps() {
  mock_log "VPS deploy success (simulated)"
  LAST_RUN_CMD_STATUS="executed"
  return 0
}

mock_deploy_cloudflare() {
  mock_log "Cloudflare deploy success (simulated)"
  LAST_RUN_CMD_STATUS="executed"
  return 0
}

mock_preflight() {
  mock_log "Cloudflare preflight passed (simulated)"
  LAST_RUN_CMD_STATUS="executed"
  return 0
}

mock_validate_profile() {
  mock_log "Profile validation passed (simulated)"
  LAST_RUN_CMD_STATUS="executed"
  return 0
}

mock_healthcheck() {
  mock_log "Healthcheck passed (simulated)"
  return 0
}

mock_cf_verify() {
  mock_log "Cloudflare verify passed (simulated)"
  return 0
}

mock_find_existing_kv() {
  local binding="$1"
  if [[ "${NANOBK_TEST_MOCK_EXISTING_KV:-}" == "1" ]]; then
    case "$binding" in
      SUB_STORE)       echo "mock-sub-store-id"; return 0 ;;
      NANOB_GEO_CACHE) echo "mock-geo-cache-id"; return 0 ;;
    esac
  fi
  return 1
}

TEST_FAILURES=0
TEST_FAILED_NAMES=()

run_one_test() {
  local script="$1"
  local label="$2"
  local cmd=(bash "$script")

  log "运行: ${label}"
  print_cmd "${cmd[@]}"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} 跳过执行"
    return 0
  fi
  if [[ "$COMMAND_ONLY" == "1" ]]; then
    echo -e "  ${YELLOW}(仅生成命令，未执行)${NC}"
    return 0
  fi

  if "${cmd[@]}"; then
    return 0
  else
    warn "测试失败: ${label}"
    TEST_FAILURES=$((TEST_FAILURES + 1))
    TEST_FAILED_NAMES+=("${label}")
    return 1
  fi
}

prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default="${3:-}"

  if [[ "$YES" == "1" ]]; then
    printf -v "$var_name" '%s' "${default:-}"
    return
  fi

  if [[ -n "$default" ]]; then
    echo -en "${BOLD}${prompt_text}${NC} [${default}]: "
  else
    echo -en "${BOLD}${prompt_text}${NC}: "
  fi
  read -r input

  if [[ -z "$input" ]] && [[ -n "$default" ]]; then
    printf -v "$var_name" '%s' "$default"
  else
    printf -v "$var_name" '%s' "$input"
  fi
}

confirm() {
  local prompt_text="$1"
  local default="${2:-n}"

  if [[ "$YES" == "1" ]]; then
    [[ "$default" == "y" ]] && return 0 || return 1
  fi

  if [[ "$default" == "y" ]]; then
    echo -en "${BOLD}${prompt_text}${NC} [Y/n]: "
  else
    echo -en "${BOLD}${prompt_text}${NC} [y/N]: "
  fi
  read -r reply

  if [[ "$default" == "y" ]]; then
    [[ "$reply" =~ ^[Nn]$ ]] && return 1 || return 0
  else
    [[ "$reply" =~ ^[Yy]$ ]] && return 0 || return 1
  fi
}

# Strict numbered menu — loops until valid input or exit
# Usage: prompt_menu_choice VAR "请选择" "1" "4"
#   VAR: variable name to store result
#   prompt_text: display text
#   default: default choice (empty = no default)
#   max: maximum valid choice number
prompt_menu_choice() {
  local var_name="$1"
  local prompt_text="$2"
  local default="$3"
  local max="$4"

  if [[ "$YES" == "1" ]] && [[ -n "$default" ]]; then
    printf -v "$var_name" '%s' "$default"
    return 0
  fi

  while true; do
    if [[ -n "$default" ]]; then
      echo -en "${BOLD}${prompt_text}${NC} [${default}]: "
    else
      echo -en "${BOLD}${prompt_text}${NC}: "
    fi
    read -r input

    # Use default if empty
    if [[ -z "$input" ]] && [[ -n "$default" ]]; then
      printf -v "$var_name" '%s' "$default"
      return 0
    fi

    # Validate: must be a number in range
    if [[ "$input" =~ ^[0-9]+$ ]] && [[ "$input" -ge 1 ]] && [[ "$input" -le "$max" ]]; then
      printf -v "$var_name" '%s' "$input"
      return 0
    fi

    echo -e "  ${RED}无效输入：${input}${NC}"
    echo "  请输入 1 到 ${max} 之间的数字。"
  done
}

# ── Config save/resume ──────────────────────────────────────────────────────

resolve_config_file() {
  if [[ -n "$CONFIG_FILE" ]]; then
    INSTALLER_CONFIG="$CONFIG_FILE"
  elif [[ $EUID -eq 0 ]]; then
    INSTALLER_CONFIG="/root/.nanobk/installer.env"
  else
    INSTALLER_CONFIG="${HOME}/.nanobk/installer.env"
  fi
}

save_config() {
  [[ "$SAVE_CONFIG" == "1" ]] || return 0
  [[ "$DRY_RUN" == "1" ]] && return 0

  mkdir -p "$(dirname "$INSTALLER_CONFIG")"

  cat > "$INSTALLER_CONFIG" <<EOF
# NanoBK Installer Config — generated $(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
# This file contains non-sensitive installer preferences.
# Sensitive tokens are stored in bot/.env, web/.env, .cloudflare.local.env etc.

NANOBK_LANG="${LANG_CODE}"
NANOBK_MODE="${MODE}"
NANOBK_DOMAIN="${NANOBK_DOMAIN:-}"
NANOBK_CERT_MODE="${NANOBK_CERT_MODE:-}"
NANOBK_DEPLOY_CLOUDFLARE="${NANOBK_DEPLOY_CLOUDFLARE:-}"
NANOBK_DEPLOY_NANOB="${NANOBK_DEPLOY_NANOB:-}"
NANOBK_ENABLE_BOT="${NANOBK_ENABLE_BOT:-}"
NANOBK_ENABLE_WEB="${NANOBK_ENABLE_WEB:-}"
NANOBK_WEB_PORT="${NANOBK_WEB_PORT:-8080}"
NANOBK_NANOK_URL="${NANOBK_NANOK_URL:-}"
NANOBK_NANOB_URL="${NANOBK_NANOB_URL:-}"
EOF
  chmod 600 "$INSTALLER_CONFIG"
  ok "配置已保存: ${INSTALLER_CONFIG}"
}

# Safe config value reader — no source, no eval, no command execution.
# Only reads whitelisted keys from KEY=value format.
read_config_value() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    # Strip leading whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    # Must look like KEY=...
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || continue
    local name="${line%%=*}"
    name="${name// /}"
    [[ "$name" == "$key" ]] || continue
    local val="${line#*=}"
    # Strip surrounding whitespace
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    # Strip surrounding quotes
    if [[ "${val:0:1}" == '"' ]] && [[ "${val: -1}" == '"' ]] && [[ ${#val} -ge 2 ]]; then
      val="${val:1:${#val}-2}"
    elif [[ "${val:0:1}" == "'" ]] && [[ "${val: -1}" == "'" ]] && [[ ${#val} -ge 2 ]]; then
      val="${val:1:${#val}-2}"
    fi
    printf '%s' "$val"
    return 0
  done < "$file"
  return 0
}

valid_mode() {
  case "$1" in
    full|cli-only|cli-bot|cli-web|cli-bot-web|vps|cloudflare|bot|web|commands|doctor|test|rotate|validate-plan|"") return 0 ;;
    *) return 1 ;;
  esac
}

load_config() {
  if [[ ! -f "$INSTALLER_CONFIG" ]]; then
    return 0
  fi
  log "读取已有配置: ${INSTALLER_CONFIG}"

  local v

  # Only load lang/mode from config if not explicitly set via CLI
  if [[ "$LANG_EXPLICIT" != "1" ]]; then
    v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_LANG || true)"
    [[ -n "$v" ]] && LANG_CODE="$v"
  fi

  if [[ "$MODE_EXPLICIT" != "1" ]]; then
    v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_MODE || true)"
    if [[ -n "$v" ]]; then
      if valid_mode "$v"; then
        MODE="$v"
      else
        warn "Ignoring invalid mode from config: ${v}"
      fi
    fi
  fi

  v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_DOMAIN || true)"
  [[ -n "$v" ]] && NANOBK_DOMAIN="$v"

  v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_CERT_MODE || true)"
  [[ -n "$v" ]] && NANOBK_CERT_MODE="$v"

  v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_DEPLOY_CLOUDFLARE || true)"
  [[ -n "$v" ]] && NANOBK_DEPLOY_CLOUDFLARE="$v"

  v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_DEPLOY_NANOB || true)"
  [[ -n "$v" ]] && NANOBK_DEPLOY_NANOB="$v"

  v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_ENABLE_BOT || true)"
  [[ -n "$v" ]] && NANOBK_ENABLE_BOT="$v"

  v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_ENABLE_WEB || true)"
  [[ -n "$v" ]] && NANOBK_ENABLE_WEB="$v"

  v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_WEB_PORT || true)"
  [[ -n "$v" ]] && NANOBK_WEB_PORT="$v"

  v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_NANOK_URL || true)"
  [[ -n "$v" ]] && NANOBK_NANOK_URL="$v"

  v="$(read_config_value "$INSTALLER_CONFIG" NANOBK_NANOB_URL || true)"
  [[ -n "$v" ]] && NANOBK_NANOB_URL="$v"
}

# ── Environment detection ───────────────────────────────────────────────────

detect_environment() {
  log "检测环境..."

  local os_name
  os_name="$(uname -s)"
  local arch
  arch="$(uname -m)"

  echo "  操作系统: ${os_name} ${arch}"

  [[ "$os_name" == "Linux" ]] && ENV_IS_LINUX=1
  command -v systemctl &>/dev/null && ENV_HAS_SYSTEMD=1
  [[ $EUID -eq 0 ]] && ENV_HAS_ROOT=1

  local tools_status=""
  for cmd in curl jq python3 openssl git node npm; do
    if command -v "$cmd" &>/dev/null; then
      tools_status+="  ✓ ${cmd}\n"
    else
      tools_status+="  ✗ ${cmd}\n"
    fi
  done

  echo ""
  echo -e "${BOLD}  工具状态:${NC}"
  echo -e "$tools_status"
}

# ── Repo check ──────────────────────────────────────────────────────────────

check_repo() {
  if [[ ! -f "$REPO_DIR/installer/install-vps.sh" ]]; then
    err "检测到你正在远程单文件运行或不在完整仓库中。"
    echo ""
    echo "  NanoBK 需要调用 installer/、vps/、workers/、tests/ 下的多个文件。"
    echo "  请先 clone 仓库后运行："
    echo ""
    echo "    git clone ${REPO_URL}.git"
    echo "    cd NanoBK-Proxy-Suite"
    echo "    bash installer/install.sh"
    echo ""
    exit 1
  fi
  ok "仓库目录: ${REPO_DIR}"
}

# ── Language selection ───────────────────────────────────────────────────────

select_language() {
  if [[ -n "$LANG_CODE" ]]; then
    if [[ "$LANG_CODE" == "en" ]]; then
      warn "English UI is partial in v${VERSION}; some prompts are still Chinese."
    fi
    return 0
  fi

  # Check saved config
  if [[ -n "${NANOBK_LANG:-}" ]]; then
    LANG_CODE="$NANOBK_LANG"
    return 0
  fi

  echo ""
  echo "  请选择语言 / Choose language:"
  echo "    1) 简体中文"
  echo "    2) English"
  echo -en "${BOLD}  [1]:${NC} "
  read -r lang_choice

  case "${lang_choice:-1}" in
    2) LANG_CODE="en"; warn "English UI is partial in v${VERSION}; some prompts are still Chinese." ;;
    *) LANG_CODE="zh" ;;
  esac
}

# ── Argument parsing ────────────────────────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)      DRY_RUN=1 ;;
      --yes)          YES=1 ;;
      --lang)         LANG_CODE="$2"; LANG_EXPLICIT=1; shift ;;
      --mode)         MODE="$2"; MODE_EXPLICIT=1; shift ;;
      --repo-dir)     REPO_DIR_OVERRIDE="$2"; shift ;;
      --save-config)  SAVE_CONFIG=1 ;;
      --config-file)  CONFIG_FILE="$2"; shift ;;
      --resume)       RESUME=1 ;;
      --defaults)     DEFAULTS=1 ;;
      --help|-h)      show_help; exit 0 ;;
      *)              err "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
  done

  # Handle --repo-dir override
  if [[ -n "$REPO_DIR_OVERRIDE" ]]; then
    [[ -d "$REPO_DIR_OVERRIDE" ]] || die "指定的仓库目录不存在: ${REPO_DIR_OVERRIDE}"
    REPO_DIR="$(cd "$REPO_DIR_OVERRIDE" && pwd)"
  fi

  # Resolve config file path
  resolve_config_file

  # --resume loads saved config
  if [[ "$RESUME" == "1" ]]; then
    load_config
  fi

  # --defaults sets defaults mode
  if [[ "$DEFAULTS" == "1" ]]; then
    YES=1
    LANG_CODE="${LANG_CODE:-zh}"
  fi

  # Safety: --yes without --dry-run on destructive modes
  if [[ "$YES" == "1" ]] && [[ "$DRY_RUN" != "1" ]] && [[ -n "$MODE" ]]; then
    case "$MODE" in
      vps|cloudflare|nanob|rotate|full|cli-only|cli-bot|cli-web|cli-bot-web)
        err "为避免使用默认值执行真实部署，install.sh 不支持 --yes 直接运行 ${MODE}。"
        echo ""
        echo "  请去掉 --yes 使用交互式输入，或使用 --dry-run 预览："
        echo "    bash installer/install.sh --mode ${MODE} --dry-run"
        echo ""
        exit 1
        ;;
    esac
  fi
}

show_help() {
  cat <<EOF
NanoBK Proxy Suite — 交互式安装器 v${VERSION}

用法:
  bash installer/install.sh [选项]

选项:
  --dry-run          只打印命令，不执行
  --yes              非交互模式（仅限 doctor/test/commands）
  --lang zh|en       语言
  --mode MODE        直接指定模式，跳过菜单
  --repo-dir PATH    指定仓库根目录
  --save-config      保存安装配置到本地
  --config-file PATH 指定配置文件路径
  --resume           读取上次配置继续
  --defaults         使用默认值（非交互）
  --help             显示帮助

模式（--mode）:
  full               Full Recommended — VPS + Cloudflare + Bot + Web
  cli-only           只部署 VPS + nanobk CLI
  cli-bot            VPS + Telegram Bot
  cli-web            VPS + Web Panel
  cli-bot-web        VPS + Telegram Bot + Web Panel
  vps                部署 VPS 四协议节点
  cloudflare         部署 Cloudflare nanok/nanob
  bot                配置 Telegram Bot
  web                配置 Web Panel
  rotate             一键换密钥
  doctor             运行环境诊断
  test               运行本地安全测试
  commands           只生成命令模板，不执行
  validate-plan      输出 clean VPS full wizard 验收计划（不执行）

示例:
  bash installer/install.sh
  bash installer/install.sh --mode doctor
  bash installer/install.sh --mode full --dry-run --defaults --lang zh
  bash installer/install.sh --mode cli-bot --dry-run --defaults
  bash installer/install.sh --mode commands --defaults
  bash installer/install.sh --mode validate-plan
EOF
}

# ── VPS parameter collection ────────────────────────────────────────────────

collect_vps_args() {
  echo ""
  echo -e "${BOLD}── VPS 四协议部署参数 ──${NC}"
  echo ""

  local domain cert_mode cert_file key_file reality_sname

  # Domain with validation and user confirmation
  while true; do
    prompt domain "请输入节点域名 (例如 proxy.example.com)" "${NANOBK_DOMAIN:-proxy.example.com}"

    if [[ -z "$domain" ]]; then
      err "域名不能为空。"
      continue
    fi

    # Step 1: Check for protocol prefix FIRST (before format validation)
    if [[ "$domain" == https://* ]] || [[ "$domain" == http://* ]]; then
      local suggested="${domain#http://}"
      suggested="${suggested#https://}"
      suggested="${suggested%%/*}"
      suggested="${suggested%% *}"
      echo ""
      echo -e "  ${YELLOW}这里需要的是域名本身，例如 example.com，不要带 https:// 或路径。${NC}"
      echo "  检测到你可能想输入：${suggested}"
      echo ""
      echo "    1) 使用 ${suggested}"
      echo "    2) 重新输入"
      echo "    3) 退出"
      echo ""
      local domain_fix_choice
      prompt domain_fix_choice "请选择" "1"
      case "$domain_fix_choice" in
        1)
          domain="$suggested"
          # Re-validate: corrected domain must also pass placeholder check
          if [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
            if is_placeholder_value "$domain"; then
              echo -e "  ${YELLOW}真实部署不能使用示例域名。${NC}"
              continue
            fi
          fi
          ;;
        2) continue ;;
        3|*) return 1 ;;
      esac
    fi

    # Check for spaces
    if [[ "$domain" == *" "* ]]; then
      err "域名不能包含空格。请只输入域名，例如 proxy.example.com"
      continue
    fi

    # Check for path
    if [[ "$domain" == *"/"* ]]; then
      local suggested_path="${domain%%/*}"
      echo ""
      echo -e "  ${YELLOW}域名不应包含路径。${NC}"
      echo "  检测到你可能想输入：${suggested_path}"
      echo ""
      echo "    1) 使用 ${suggested_path}"
      echo "    2) 重新输入"
      echo "    3) 退出"
      echo ""
      local domain_path_choice
      prompt domain_path_choice "请选择" "1"
      case "$domain_path_choice" in
        1)
          domain="$suggested_path"
          # Re-validate: corrected domain must also pass placeholder check
          if [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
            if is_placeholder_value "$domain"; then
              echo -e "  ${YELLOW}真实部署不能使用示例域名。${NC}"
              continue
            fi
          fi
          ;;
        2) continue ;;
        3|*) return 1 ;;
      esac
    fi

    # Step 2: Reject placeholder/example domains in real deployment mode
    if [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
      if is_placeholder_value "$domain"; then
        echo ""
        echo -e "  ${YELLOW}真实部署不能使用示例域名。${NC}"
        echo "  请输入你自己的域名，例如 proxy.yourdomain.com"
        echo ""
        continue
      fi
    fi

    # Step 3: Validate domain format (after protocol/path correction)
    if ! is_valid_domain_name "$domain"; then
      err "这不像有效域名。域名通常长这样：proxy.yourdomain.com"
      err "  - 至少包含一个点"
      err "  - 只能包含字母、数字、点、横线"
      err "  - 不能是纯数字"
      continue
    fi

    break
  done
  NANOBK_DOMAIN="$domain"

  # Cert-mode with numbered menu for beginners
  # IMPORTANT: retry/reselect paths use continue (loop back), not return 0.
  # return 0 means VPS deploy command completed successfully.
  # return 1 means user cancelled or deploy failed.
  while true; do
    echo ""
    echo "  请选择证书模式："
    echo "    1) self-signed — 测试/自用，最快开始（推荐）"
    echo "    2) existing — 我已有证书 fullchain.pem / privkey.pem"
    echo "    3) letsencrypt — 暂不推荐，后续版本完善"
    echo ""

    local cert_choice
    prompt cert_choice "请选择" "1"

    case "$cert_choice" in
      1|self-signed|self)
        cert_mode="self-signed"
        warn "自签证书只建议测试，有些客户端可能需要开启 skip-cert-verify。"
        cert_file=""
        key_file=""
        break
        ;;
      2|existing)
        cert_mode="existing"
        prompt cert_file "证书 fullchain 路径" "/etc/letsencrypt/live/${domain}/fullchain.pem"
        prompt key_file "证书 privkey 路径" "/etc/letsencrypt/live/${domain}/privkey.pem"
        break
        ;;
      3|letsencrypt)
        echo ""
        echo -e "  ${YELLOW}暂不推荐自动配置 Let's Encrypt。${NC}"
        echo "  请手动申请证书后选择 existing 模式，或先用 self-signed 测试。"
        echo ""
        echo "    1) 改用 self-signed"
        echo "    2) 改用 existing"
        echo "    3) 返回重新选择"
        echo "    4) 退出"
        echo ""
        local le_choice
        prompt le_choice "请选择" "1"
        case "$le_choice" in
          1)
            cert_mode="self-signed"
            warn "自签证书只建议测试。"
            cert_file=""
            key_file=""
            break
            ;;
          2)
            cert_mode="existing"
            prompt cert_file "证书 fullchain 路径" "/etc/letsencrypt/live/${domain}/fullchain.pem"
            prompt key_file "证书 privkey 路径" "/etc/letsencrypt/live/${domain}/privkey.pem"
            break
            ;;
          3)
            continue  # Re-enter cert-mode selection
            ;;
          4|*)
            return 1
            ;;
        esac
        ;;
      *)
        # Handle common typos
        case "$cert_choice" in
          self-|selfsigned|self_signed)
            echo ""
            echo -e "  ${YELLOW}你是不是想选择 self-signed？${NC}"
            echo "    1) 使用 self-signed"
            echo "    2) 重新选择"
            echo "    3) 退出"
            echo ""
            local cert_fix_choice
            prompt cert_fix_choice "请选择" "1"
            case "$cert_fix_choice" in
              1)
                cert_mode="self-signed"
                warn "自签证书只建议测试。"
                cert_file=""
                key_file=""
                break
                ;;
              2)
                continue  # Re-enter cert-mode selection
                ;;
              3|*)
                return 1
                ;;
            esac
            ;;
          *)
            err "无效选择: ${cert_choice}"
            echo "    1) 重新选择"
            echo "    2) 退出"
            echo ""
            local invalid_cert_choice
            prompt invalid_cert_choice "请选择" "1"
            case "$invalid_cert_choice" in
              1) continue ;;
              2|*) return 1 ;;
            esac
            ;;
        esac
        ;;
    esac
  done
  NANOBK_CERT_MODE="$cert_mode"

  prompt reality_sname "Reality 伪装域名" "www.microsoft.com"

  # VPS Review Table
  echo ""
  echo -e "${BOLD}VPS 配置确认${NC}"
  echo ""
  echo "  1. 节点域名：${domain}"
  echo "  2. 证书模式：${cert_mode}"
  echo "  3. Reality 伪装域名：${reality_sname}"
  echo ""
  echo "    1) 确认并执行 VPS 部署"
  echo "    2) 修改节点域名"
  echo "    3) 修改证书模式"
  echo "    4) 修改 Reality 伪装域名"
  echo "    5) 返回上一级"
  echo "    6) 退出"
  echo ""
  local vps_review_choice
  prompt_menu_choice vps_review_choice "请选择" "1" "6"
  case "$vps_review_choice" in
    1) ;;  # Continue to deploy
    2) prompt domain "请输入节点域名" "$domain"; NANOBK_DOMAIN="$domain" ;;
    3) # Re-select cert mode
       echo "  请选择证书模式："
       echo "    1) self-signed（推荐）"
       echo "    2) existing"
       local cert_re_choice
       prompt_menu_choice cert_re_choice "请选择" "1" "2"
       case "$cert_re_choice" in
         1) cert_mode="self-signed"; cert_file=""; key_file="" ;;
         2) cert_mode="existing"; prompt cert_file "证书路径" "${cert_file:-}"; prompt key_file "密钥路径" "${key_file:-}" ;;
       esac
       NANOBK_CERT_MODE="$cert_mode"
       ;;
    4) prompt reality_sname "Reality 伪装域名" "$reality_sname" ;;
    5) return 0 ;;  # Return to caller
    6|*) return 1 ;;
  esac

  echo ""

  local cmd=(bash "$REPO_DIR/installer/install-vps.sh" --yes
    --domain "$domain"
    --cert-mode "$cert_mode"
    --reality-servername "$reality_sname")

  [[ "$cert_mode" == "existing" ]] && cmd+=(--cert-file "$cert_file" --key-file "$key_file")
  [[ "$DRY_RUN" == "1" ]] && cmd+=(--dry-run)

  # IMPORTANT: run_cmd sets LAST_RUN_CMD_STATUS
  # executed = real deploy ran and succeeded
  # dry_run / commands_only = preview only, not real deploy
  # skipped_user = user chose not to execute, not a deploy
  # failed = command ran but failed
  run_critical_step "部署 VPS 四协议" "${cmd[@]}" || return 1

  # Post-deploy healthcheck and status (only meaningful if actually deployed)
  if [[ "$LAST_RUN_CMD_STATUS" == "executed" ]]; then
    run_cmd "VPS healthcheck" sudo bash "${REPO_DIR}/vps/scripts/healthcheck.sh" --config-dir /etc/nanobk || true
    run_cmd "NanoBK status" bash "${REPO_DIR}/bin/nanobk" status --config-dir /etc/nanobk || true
  fi
}

# ── Cloudflare parameter collection ─────────────────────────────────────────

collect_cloudflare_args() {
  echo ""
  echo -e "${BOLD}── Cloudflare 部署参数 ──${NC}"
  echo ""

  local profile route_url kv_choice kv_id nanob_url geo_choice geo_id

  prompt profile "profile.current.json 路径" "/etc/nanobk/profile.current.json"

  # Cloudflare URL validation
  while true; do
    prompt route_url "nanok Worker URL (例如 https://nanok.xxx.workers.dev)" "${NANOBK_NANOK_URL:-https://nanok.example.workers.dev}"

    # Check for token/subscription URL first
    if [[ "$route_url" == *"token="* ]] || [[ "$route_url" == *"/jb"* ]] || [[ "$route_url" == *"/sub"* ]]; then
      echo ""
      echo -e "  ${YELLOW}这里需要 Worker 根地址，例如 https://nanok.xxx.workers.dev${NC}"
      echo "  不要粘贴带 token 的订阅链接。"
      echo ""
      continue
    fi

    # Reject placeholder/example URLs in real deployment mode
    if [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
      if is_placeholder_worker_url "$route_url"; then
        echo ""
        echo -e "  ${YELLOW}真实部署不能使用示例地址。${NC}"
        echo "  请输入你自己的 Worker 地址，例如："
        echo "    https://nanok.<你的 workers.dev 子域>.workers.dev"
        echo ""
        continue
      fi
    fi

    # Check for http:// (must use https)
    if [[ "$route_url" == http://* ]]; then
      echo ""
      echo -e "  ${YELLOW}Worker URL 必须使用 https://，不支持 http://。${NC}"
      echo ""
      continue
    fi

    # Bare host detection (no protocol)
    if [[ "$route_url" != https://* ]] && [[ "$route_url" != http://* ]] && [[ -n "$route_url" ]] && [[ "$route_url" != *" "* ]]; then
      # Looks like a bare host
      local cleaned="${route_url%%/*}"
      cleaned="${cleaned%%\?*}"
      cleaned="${cleaned%/}"
      echo ""
      echo -e "  ${YELLOW}检测到未包含 https://${NC}"
      echo "  是否使用 https://${cleaned} ？"
      echo "    1) 使用 https://${cleaned}"
      echo "    2) 重新输入"
      echo "    3) 退出"
      echo ""
      local url_fix_choice
      prompt url_fix_choice "请选择" "1"
      case "$url_fix_choice" in
        1) route_url="https://${cleaned}" ;;
        2) continue ;;
        3|*) return 1 ;;
      esac
    fi

    # Clean: strip query params, fragment, trailing slash
    route_url="${route_url%%\?*}"
    route_url="${route_url%%#*}"
    route_url="${route_url%/}"

    # Validate result looks like a proper https URL
    if [[ "$route_url" != https://* ]]; then
      echo -e "  ${YELLOW}URL 必须以 https:// 开头。${NC}"
      continue
    fi

    break
  done
  NANOBK_NANOK_URL="$route_url"

  echo ""
  echo "  KV namespace 选择："
  echo "    1) 自动创建 KV（推荐）"
  echo "    2) 使用已有 KV namespace ID"
  prompt kv_choice "请选择" "1"

  local kv_args=()
  if [[ "$kv_choice" == "2" ]]; then
    prompt kv_id "KV namespace ID"
    kv_args+=(--kv-namespace-id "$kv_id")
  else
    kv_args+=(--create-kv)
  fi

  # Cloudflare Review Table
  echo ""
  echo -e "${BOLD}Cloudflare 配置确认${NC}"
  echo ""
  echo "  1. 节点配置文件：${profile}"
  echo "  2. nanok 地址：${route_url}"
  echo "  3. KV：$([ "$kv_choice" == "2" ] && echo "使用已有 ID: ${kv_id}" || echo "自动创建")"
  echo "  4. nanob：$([ "${NANOBK_DEPLOY_NANOB:-true}" == "true" ] && echo "启用" || echo "不启用")"
  [[ -n "${NANOBK_NANOB_URL:-}" ]] && echo "  5. nanob 地址：${NANOBK_NANOB_URL}"
  echo ""
  echo "    1) 确认并部署 Cloudflare"
  echo "    2) 修改 Worker 地址"
  echo "    3) 修改 KV 设置"
  echo "    4) 修改 nanob 设置"
  echo "    5) 返回上一级"
  echo "    6) 退出"
  echo ""
  local cf_review_choice
  prompt_menu_choice cf_review_choice "请选择" "1" "6"
  case "$cf_review_choice" in
    1) ;;  # Continue to deploy
    2) prompt route_url "nanok Worker URL" "$route_url"; NANOBK_NANOK_URL="$route_url" ;;
    3) echo "  KV namespace 选择："
       echo "    1) 自动创建 KV（推荐）"
       echo "    2) 使用已有 KV namespace ID"
       prompt kv_choice "请选择" "$kv_choice"
       if [[ "$kv_choice" == "2" ]]; then
         prompt kv_id "KV namespace ID"
         kv_args=(--kv-namespace-id "$kv_id")
       else
         kv_args=(--create-kv)
       fi
       ;;
    4) if confirm "是否部署 nanob 聚合器？" "y"; then
         NANOBK_DEPLOY_NANOB="true"
       else
         NANOBK_DEPLOY_NANOB="false"
       fi
       ;;
    5) return 0 ;;
    6|*) return 1 ;;
  esac

  NANOBK_DEPLOY_CLOUDFLARE="true"

  # Preflight and profile validation before deployment
  run_critical_step "Cloudflare preflight" bash "$REPO_DIR/installer/install-cloudflare.sh" --preflight || {
    err "Cloudflare preflight failed."
    err ""
    err "常见修复："
    err "  1. 安装 Node.js >= 22:"
    err "     curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
    err "     sudo apt install -y nodejs"
    err "  2. 安装 wrangler: npm install -g wrangler"
    err ""
    # Headless Wrangler OAuth guidance
    if [[ -z "${DISPLAY:-}" ]] || ! command -v xdg-open &>/dev/null; then
      err "  检测到这是无图形界面的 VPS，Wrangler OAuth 需要本地浏览器授权："
      err ""
      err "    1. 在本地电脑执行 SSH 隧道："
      err "       ssh -L 8976:127.0.0.1:8976 root@YOUR_VPS_IP"
      err "    2. 在 VPS 上执行："
      err "       wrangler login --browser=false"
      err "    3. 复制授权 URL 到本地浏览器打开"
      err "    4. 授权完成后验证：wrangler whoami"
      err ""
    else
      err "  3. 登录 wrangler: wrangler login --browser=false"
    fi
    return 1
  }

  # Check if preflight was skipped by user
  if [[ "${LAST_RUN_CMD_STATUS:-}" == "skipped_user" ]]; then
    CF_DEPLOY_STATUS="manual_pending"
    warn "Cloudflare preflight was not executed."
    echo "  恢复命令："
    echo "    bash installer/install-cloudflare.sh --preflight"
    echo "    bash installer/install.sh --mode cloudflare --lang zh"
    return 2
  fi

  run_critical_step "Validate profile" bash "$REPO_DIR/installer/install-cloudflare.sh" --validate-profile-only --profile "$profile" || {
    err "Profile validation failed."
    err "请检查 profile 文件是否包含 hy2/tuic/reality/trojan 四个协议段。"
    return 1
  }

  # Check if profile validation was skipped by user
  if [[ "${LAST_RUN_CMD_STATUS:-}" == "skipped_user" ]]; then
    CF_DEPLOY_STATUS="manual_pending"
    warn "Profile validation was not executed."
    echo "  恢复命令："
    echo "    bash installer/install-cloudflare.sh --validate-profile-only --profile /etc/nanobk/profile.current.json"
    echo "    bash installer/install.sh --mode cloudflare --lang zh"
    return 2
  fi

  # nanob
  echo ""
  if confirm "是否部署 nanob 聚合器？（推荐）" "y"; then
    NANOBK_DEPLOY_NANOB="true"
    while true; do
      prompt nanob_url "nanob Worker URL (例如 https://nanob.xxx.workers.dev)" "${NANOBK_NANOB_URL:-https://nanob.example.workers.dev}"

      # Check for token/subscription URL
      if [[ "$nanob_url" == *"token="* ]] || [[ "$nanob_url" == *"/jb"* ]] || [[ "$nanob_url" == *"/sub"* ]]; then
        echo -e "  ${YELLOW}这里需要 Worker 根地址，不要粘贴带 token 的订阅链接。${NC}"
        continue
      fi

      # Reject placeholder/example URLs in real deployment mode
      if [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
        if is_placeholder_worker_url "$nanob_url"; then
          echo -e "  ${YELLOW}真实部署不能使用示例地址。请输入你自己的 Worker 地址。${NC}"
          continue
        fi
      fi

      # Check for http://
      if [[ "$nanob_url" == http://* ]]; then
        echo -e "  ${YELLOW}Worker URL 必须使用 https://，不支持 http://。${NC}"
        continue
      fi

      # Bare host detection
      if [[ "$nanob_url" != https://* ]] && [[ "$nanob_url" != http://* ]] && [[ -n "$nanob_url" ]] && [[ "$nanob_url" != *" "* ]]; then
        local cleaned_n="${nanob_url%%/*}"
        cleaned_n="${cleaned_n%%\?*}"
        cleaned_n="${cleaned_n%/}"
        echo -e "  ${YELLOW}检测到未包含 https://${NC}"
        echo "  是否使用 https://${cleaned_n} ？"
        echo "    1) 使用 https://${cleaned_n}"
        echo "    2) 重新输入"
        echo "    3) 退出"
        echo ""
        local nanob_url_fix
        prompt nanob_url_fix "请选择" "1"
        case "$nanob_url_fix" in
          1) nanob_url="https://${cleaned_n}" ;;
          2) continue ;;
          3|*) return 1 ;;
        esac
      fi

      # Clean
      nanob_url="${nanob_url%%\?*}"
      nanob_url="${nanob_url%%#*}"
      nanob_url="${nanob_url%/}"

      if [[ "$nanob_url" != https://* ]]; then
        echo -e "  ${YELLOW}URL 必须以 https:// 开头。${NC}"
        continue
      fi

      break
    done
    NANOBK_NANOB_URL="$nanob_url"

    echo ""
    echo "  Geo KV namespace 选择："
    echo "    1) 自动创建（推荐）"
    echo "    2) 使用已有 Geo KV ID"
    prompt geo_choice "请选择" "1"

    local geo_args=()
    if [[ "$geo_choice" == "2" ]]; then
      prompt geo_id "Geo KV namespace ID"
      geo_args+=(--nanob-geo-kv-namespace-id "$geo_id")
    else
      geo_args+=(--create-nanob-geo-kv)
    fi

    local nanok_cmd=(bash "$REPO_DIR/installer/install-cloudflare.sh" --yes
      "${kv_args[@]}"
      --profile "$profile"
      --route-url "$route_url"
      --deploy-nanob
      --nanob-route-url "$nanob_url"
      "${geo_args[@]}")
    [[ "$DRY_RUN" == "1" ]] && nanok_cmd+=(--dry-run)

    run_critical_step "部署 nanok + nanob" "${nanok_cmd[@]}"
  else
    NANOBK_DEPLOY_NANOB="false"
    local nanok_cmd=(bash "$REPO_DIR/installer/install-cloudflare.sh" --yes
      "${kv_args[@]}"
      --profile "$profile"
      --route-url "$route_url")
    [[ "$DRY_RUN" == "1" ]] && nanok_cmd+=(--dry-run)

    run_critical_step "部署 nanok" "${nanok_cmd[@]}"
  fi

  # Set CF deploy status based on run_cmd outcome
  case "${LAST_RUN_CMD_STATUS:-unknown}" in
    executed)    CF_DEPLOY_STATUS="deployed" ;;
    dry_run)     CF_DEPLOY_STATUS="dry_run" ;;
    commands_only) CF_DEPLOY_STATUS="commands_only" ;;
    skipped_user) CF_DEPLOY_STATUS="manual_pending" ;;
    failed)      CF_DEPLOY_STATUS="failed" ;;
    *)           CF_DEPLOY_STATUS="unknown" ;;
  esac

  # Auto-write admin env for rotate sync if deploy succeeded
  if [[ "$CF_DEPLOY_STATUS" == "deployed" ]]; then
    local admin_env="/root/.nanok-cf-admin.env"
    local local_env="${REPO_DIR:-.}/.cloudflare.local.env"

    # Read admin token and URLs from local env
    local adm_token adm_current adm_update
    if [[ -f "$local_env" ]]; then
      adm_token=$(read_env_value "$local_env" "ADMIN_TOKEN" 2>/dev/null || echo "")
      adm_current=$(read_env_value "$local_env" "ADMIN_CURRENT_URL" 2>/dev/null || echo "")
      adm_update=$(read_env_value "$local_env" "ADMIN_UPDATE_URL" 2>/dev/null || echo "")

      # Also try to construct from route URL if not set
      if [[ -z "$adm_current" ]] && [[ -n "${NANOBK_NANOK_URL:-}" ]]; then
        adm_current="${NANOBK_NANOK_URL}/admin/current"
      fi
      if [[ -z "$adm_update" ]] && [[ -n "${NANOBK_NANOK_URL:-}" ]]; then
        adm_update="${NANOBK_NANOK_URL}/admin/update"
      fi
    fi

    if [[ -n "$adm_token" ]] && [[ -n "$adm_current" ]] && [[ -n "$adm_update" ]]; then
      # Write to temp file first (never put token in sudo command args)
      local tmp_admin
      tmp_admin=$(mktemp)
      chmod 600 "$tmp_admin"
      cat > "$tmp_admin" <<ENVEOF
ADMIN_TOKEN="${adm_token}"
ADMIN_CURRENT_URL="${adm_current}"
ADMIN_UPDATE_URL="${adm_update}"
ENVEOF

      if [[ $EUID -eq 0 ]]; then
        # Running as root, install directly
        install -m 600 "$tmp_admin" "$admin_env"
        rm -f "$tmp_admin"
        ok "Admin env written: ${admin_env} (mode 600)"
      else
        # Not root, try sudo install (no token in argv)
        if command -v sudo &>/dev/null; then
          sudo install -m 600 "$tmp_admin" "$admin_env" 2>/dev/null && {
            rm -f "$tmp_admin"
            ok "Admin env written via sudo: ${admin_env} (mode 600)"
          } || {
            rm -f "$tmp_admin"
            warn "无法写入 ${admin_env}，需要 sudo 权限。"
            echo "  恢复命令："
            echo "    bash bin/nanobk cf install-admin-env"
          }
        else
          rm -f "$tmp_admin"
          warn "无法写入 ${admin_env}，需要 sudo 权限。"
          echo "  恢复命令："
          echo "    bash bin/nanobk cf install-admin-env"
        fi
      fi
    else
      warn "Admin env 未自动生成：缺少 ADMIN_TOKEN 或 admin URLs。"
      echo "  rotate sync 可能失败，请手动创建 ${admin_env}"
    fi
  fi
}

# ── Bot configuration ───────────────────────────────────────────────────────

collect_bot_args() {
  echo ""
  echo -e "${BOLD}── Telegram Bot 配置 ──${NC}"
  echo ""

  NANOBK_ENABLE_BOT="true"

  # Check python3-venv
  if command -v python3 &>/dev/null; then
    if ! python3 -c "import venv" &>/dev/null 2>&1; then
      warn "python3-venv 不可用。Bot 运行需要 venv 支持。"
      echo ""
      echo "  Ubuntu/Debian 安装："
      echo "    sudo apt update && sudo apt install -y python3-venv"
      echo "  如果仍失败："
      echo "    sudo apt install -y python3.12-venv"
      echo ""
      if ! confirm "已安装或稍后安装，继续？" "y"; then
        return 1
      fi
    fi
  else
    warn "python3 未找到。Bot 需要 python3 才能运行。"
  fi

  local bot_token owner_id bot_dry_run

  # Safety warning before token input
  echo ""
  echo -e "  ${YELLOW}安全提示：${NC}"
  echo "    - Bot Token 是敏感凭证"
  echo "    - 不要截图，不要粘贴到聊天、issue、日志"
  echo "    - 不要执行 cat bot/.env"
  echo "    - 如果 token 曾暴露，请去 BotFather revoke / regenerate"
  echo ""

  prompt bot_token "Telegram Bot Token (从 @BotFather 获取)" ""
  prompt owner_id "你的 Telegram 数字 User ID" ""

  # Validate inputs
  if [[ -n "$bot_token" ]] && { [[ "$bot_token" == *$'\n'* ]] || [[ "$bot_token" == *$'\r'* ]]; }; then
    err "Bot Token 包含换行符，请检查输入。"
    return 1
  fi
  if [[ -n "$owner_id" ]] && { [[ "$owner_id" == *$'\n'* ]] || [[ "$owner_id" == *$'\r'* ]]; }; then
    err "User ID 包含换行符，请检查输入。"
    return 1
  fi
  if [[ -n "$owner_id" ]] && ! [[ "$owner_id" =~ ^[0-9]+$ ]]; then
    err "User ID 必须是纯数字。"
    return 1
  fi

  if [[ -z "$bot_token" ]] || [[ -z "$owner_id" ]]; then
    warn "Bot Token 或 User ID 为空，Bot 将无法启动。"
    warn "请稍后编辑 bot/.env 填写。"
  fi

  # Bot Review Table
  echo ""
  echo -e "${BOLD}Telegram Bot 配置确认${NC}"
  echo ""
  echo "  1. Bot Token：$([ -n "$bot_token" ] && echo "已填写" || echo "未填写")"
  echo "  2. Owner ID：${owner_id:-未填写}"
  echo "  3. Dry-run：待选择"
  echo ""
  echo "    1) 确认并继续"
  echo "    2) 修改 Bot Token"
  echo "    3) 修改 Owner ID"
  echo "    4) 返回上一级"
  echo "    5) 退出"
  echo ""
  local bot_review_choice
  prompt_menu_choice bot_review_choice "请选择" "1" "5"
  case "$bot_review_choice" in
    1) ;;  # Continue
    2) prompt bot_token "Telegram Bot Token" "$bot_token" ;;
    3) prompt owner_id "Telegram User ID" "$owner_id" ;;
    4) return 0 ;;
    5|*) return 1 ;;
  esac

  if confirm "首次启动使用 dry-run 模式？(推荐)" "y"; then
    bot_dry_run="true"
  else
    bot_dry_run="false"
  fi

  local repo_dir_for_bot="$REPO_DIR"
  if [[ "$DRY_RUN" != "1" ]]; then
    mkdir -p "$REPO_DIR/bot"
    cat > "$REPO_DIR/bot/.env" <<EOF
TELEGRAM_BOT_TOKEN=${bot_token}
OWNER_TELEGRAM_ID=${owner_id}
NANOBK_CLI=${repo_dir_for_bot}/bin/nanobk
NANOBK_REPO_DIR=${repo_dir_for_bot}
NANOBK_BOT_DRY_RUN=${bot_dry_run}
NANOBK_COMMAND_TIMEOUT=120
NANOBK_ROTATE_TIMEOUT=300
EOF
    chmod 600 "$REPO_DIR/bot/.env"
    ok "Bot 配置已保存: bot/.env (mode 600)"
  else
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would write bot/.env"
  fi

  echo ""
  echo "  测试 Bot 配置:"
  print_cmd python3 "$REPO_DIR/bot/nanobk_bot.py" --self-test

  if [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
    if confirm "现在运行 Bot self-test？" "y"; then
      python3 "$REPO_DIR/bot/nanobk_bot.py" --self-test || warn "Bot self-test 失败"
    fi
  fi

  echo ""
  if [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
    if confirm "是否现在启动 Bot？" "n"; then
      echo "  启动 Bot:"
      echo "    cd $REPO_DIR/bot && bash run.sh"
    fi
  else
    echo "  启动 Bot:"
    echo "    cd $REPO_DIR/bot && bash run.sh"
  fi
  echo ""
  echo "  systemd 示例:"
  echo "    bot/systemd/nanobk-telegram-bot.service.example"
}

# ── Web Panel configuration ─────────────────────────────────────────────────

collect_web_args() {
  echo ""
  echo -e "${BOLD}── Web Panel 配置 ──${NC}"
  echo ""

  NANOBK_ENABLE_WEB="true"

  local web_token web_secret web_host web_port web_dry_run

  prompt web_token "Web 登录 Token (留空自动生成)" ""
  prompt web_secret "Flask Secret Key (留空自动生成)" ""
  prompt web_host "监听地址" "127.0.0.1"
  prompt web_port "监听端口" "8080"

  # Validate inputs
  if [[ -n "$web_token" ]] && { [[ "$web_token" == *$'\n'* ]] || [[ "$web_token" == *$'\r'* ]]; }; then
    err "Web Token 包含换行符，请检查输入。"
    return 1
  fi
  if [[ -n "$web_secret" ]] && { [[ "$web_secret" == *$'\n'* ]] || [[ "$web_secret" == *$'\r'* ]]; }; then
    err "Flask Secret Key 包含换行符，请检查输入。"
    return 1
  fi
  if ! [[ "$web_port" =~ ^[0-9]+$ ]]; then
    err "端口必须是数字: ${web_port}"
    return 1
  fi
  if [[ "$web_host" == "0.0.0.0" ]]; then
    echo ""
    echo -e "  ${RED}⚠ 警告: 你正在让 Web Panel 监听 0.0.0.0，可能暴露公网。${NC}"
    echo "  推荐保持 127.0.0.1，并通过 SSH tunnel 或 Cloudflare Tunnel 访问。"
    echo ""
    if ! confirm "确认使用 0.0.0.0？" "n"; then
      web_host="127.0.0.1"
      echo "  已切换回 127.0.0.1"
    fi
  fi

  NANOBK_WEB_PORT="$web_port"
  NANOBK_WEB_HOST="$web_host"

  # Auto-generate if empty
  if [[ -z "$web_token" ]]; then
    web_token=$(openssl rand -base64 32 | tr -d '\n/+=' | head -c 32)
    ok "自动生成 Web Token"
  fi
  if [[ -z "$web_secret" ]]; then
    web_secret=$(openssl rand -base64 32 | tr -d '\n/+=' | head -c 32)
    ok "自动生成 Flask Secret Key"
  fi

  # Web Review Table
  echo ""
  echo -e "${BOLD}Web Panel 配置确认${NC}"
  echo ""
  echo "  1. Listen host：${web_host}"
  echo "  2. Listen port：${web_port}"
  echo "  3. Token：$([ -n "$web_token" ] && echo "已生成" || echo "待生成")"
  echo "  4. Secret：$([ -n "$web_secret" ] && echo "已生成" || echo "待生成")"
  echo ""
  echo "    1) 确认并继续"
  echo "    2) 修改 host"
  echo "    3) 修改 port"
  echo "    4) 重新生成 token/secret"
  echo "    5) 返回上一级"
  echo "    6) 退出"
  echo ""
  local web_review_choice
  prompt_menu_choice web_review_choice "请选择" "1" "6"
  case "$web_review_choice" in
    1) ;;  # Continue
    2) prompt web_host "监听地址" "$web_host"; NANOBK_WEB_HOST="$web_host" ;;
    3) prompt web_port "监听端口" "$web_port"; NANOBK_WEB_PORT="$web_port" ;;
    4) web_token=$(openssl rand -base64 32 | tr -d '\n/+=' | head -c 32)
       web_secret=$(openssl rand -base64 32 | tr -d '\n/+=' | head -c 32)
       ok "已重新生成 token/secret"
       ;;
    5) return 0 ;;
    6|*) return 1 ;;
  esac

  if confirm "首次启动使用 dry-run 模式？(推荐)" "y"; then
    web_dry_run="true"
  else
    web_dry_run="false"
  fi

  local repo_dir_for_web="$REPO_DIR"
  if [[ "$DRY_RUN" != "1" ]]; then
    mkdir -p "$REPO_DIR/web"
    cat > "$REPO_DIR/web/.env" <<EOF
NANOBK_WEB_TOKEN=${web_token}
NANOBK_WEB_SECRET_KEY=${web_secret}
NANOBK_WEB_HOST=${web_host}
NANOBK_WEB_PORT=${web_port}
NANOBK_CLI=${repo_dir_for_web}/bin/nanobk
NANOBK_REPO_DIR=${repo_dir_for_web}
NANOBK_WEB_DRY_RUN=${web_dry_run}
NANOBK_COMMAND_TIMEOUT=120
NANOBK_ROTATE_TIMEOUT=300
EOF
    chmod 600 "$REPO_DIR/web/.env"
    ok "Web Panel 配置已保存: web/.env (mode 600)"
    echo ""
    echo -e "  ${YELLOW}安全提示：${NC}"
    echo "    - Web token/secret 已写入 web/.env，权限应为 600"
    echo "    - 不要 cat web/.env，不要把内容贴到聊天或日志"
  else
    echo -e "  ${CYAN}[DRY-RUN]${NC} Would write web/.env"
  fi

  echo ""
  echo "  测试 Web Panel 配置:"
  print_cmd python3 "$REPO_DIR/web/app.py" --self-test

  if [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
    if confirm "现在运行 Web Panel self-test？" "y"; then
      python3 "$REPO_DIR/web/app.py" --self-test || warn "Web Panel self-test 失败"
    fi
  fi

  echo ""
  echo -e "  ${YELLOW}默认只监听 127.0.0.1，不裸露公网。${NC}"
  echo "  远程访问请用 SSH tunnel:"
  echo "    ssh -L ${web_port}:127.0.0.1:${web_port} root@YOUR_VPS_IP"
  echo "    浏览器打开: http://127.0.0.1:${web_port}"
  echo ""
  echo "  systemd 示例:"
  echo "    web/systemd/nanobk-web-panel.service.example"
}

# ── Unified preflight ──────────────────────────────────────────────────────

PREFLIGHT_ERRORS=0
PREFLIGHT_WARNINGS=0

preflight_pass() { echo -e "  ${GREEN}✓${NC} $*"; }
preflight_fail() { echo -e "  ${RED}✗${NC} $*"; PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS + 1)); }
preflight_warn() { echo -e "  ${YELLOW}⚠${NC} $*"; PREFLIGHT_WARNINGS=$((PREFLIGHT_WARNINGS + 1)); }

check_port_available() {
  local port="$1"
  local proto="$2"
  local label="$3"

  if [[ "$DRY_RUN" == "1" ]]; then
    preflight_pass "${label} :${port} (${proto}): [DRY-RUN] assumed free"
    return 0
  fi

  if [[ "$proto" == "udp" ]]; then
    if command -v ss &>/dev/null; then
      if ss -ulnp 2>/dev/null | grep -q ":${port} "; then
        local proc
        proc=$(ss -ulnp 2>/dev/null | grep ":${port} " | head -1 | sed 's/.*users:(("\([^"]*\)".*/\1/' || echo "unknown")
        preflight_fail "${label} :${port} (${proto}): occupied by ${proc}"
        return 1
      fi
    fi
  else
    if command -v ss &>/dev/null; then
      if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        local proc
        proc=$(ss -tlnp 2>/dev/null | grep ":${port} " | head -1 | sed 's/.*users:(("\([^"]*\)".*/\1/' || echo "unknown")
        preflight_fail "${label} :${port} (${proto}): occupied by ${proc}"
        return 1
      fi
    fi
  fi

  preflight_pass "${label} :${port} (${proto}): free"
  return 0
}

handle_core_port_conflict() {
  local port="$1"
  local label="$2"

  echo ""
  echo -e "  ${YELLOW}端口 ${port} (${label}) 已被占用。${NC}"
  echo ""
  echo "    1) 显示占用进程详情"
  echo "    2) 我已处理，重新检测"
  echo "    3) 退出"
  echo ""
  local choice
  prompt choice "请选择" "3"
  case "$choice" in
    1)
      echo ""
      if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | grep ":${port} " || ss -ulnp 2>/dev/null | grep ":${port} " || echo "  无法获取详情"
      elif command -v lsof &>/dev/null; then
        lsof -i ":${port}" 2>/dev/null || echo "  无法获取详情"
      else
        echo "  ss/lsof 均不可用"
      fi
      echo ""
      handle_core_port_conflict "$port" "$label"
      ;;
    2)
      # Re-check the port
      if ! command -v ss &>/dev/null; then
        warn "无法重新检测端口：ss 不可用。请安装 iproute2 或手动确认端口后重试。"
        return 1
      fi
      local recheck_ok=0
      if ! ss -ulnp 2>/dev/null | grep -q ":${port} " && ! ss -tlnp 2>/dev/null | grep -q ":${port} "; then
        preflight_pass "${label} :${port}: now free"
        recheck_ok=1
      fi
      if [[ "$recheck_ok" == "0" ]]; then
        preflight_fail "${label} :${port}: still occupied"
        handle_core_port_conflict "$port" "$label"
      fi
      ;;
    3|*)
      die "端口冲突，已退出。请先释放端口 ${port} 后重试。"
      ;;
  esac
}

run_unified_preflight() {
  local check_cf="${NANOBK_DEPLOY_CLOUDFLARE:-false}"
  local check_bot="${NANOBK_ENABLE_BOT:-false}"
  local check_web="${NANOBK_ENABLE_WEB:-false}"

  # Auto-detect from mode if flags not set
  case "${MODE:-full}" in
    full)
      check_cf="true"; check_bot="true"; check_web="true" ;;
    cli-bot)
      check_bot="true" ;;
    cli-web)
      check_web="true" ;;
    cli-bot-web)
      check_bot="true"; check_web="true" ;;
    cloudflare)
      check_cf="true" ;;
    bot)
      check_bot="true" ;;
    web)
      check_web="true" ;;
  esac

  PREFLIGHT_ERRORS=0
  PREFLIGHT_WARNINGS=0

  echo ""
  echo -e "${BOLD}── Preflight ──${NC}"
  echo ""

  # OS
  local os_name
  os_name="$(uname -s)"
  local os_label
  if [[ -f /etc/os-release ]]; then
    os_label=$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "$os_name")
  else
    os_label="$os_name"
  fi
  if [[ "$os_name" == "Linux" ]]; then
    preflight_pass "OS: ${os_label}"
  elif [[ "$os_name" == "Darwin" ]]; then
    preflight_pass "OS: macOS (dry-run/render-only 适用)"
  else
    preflight_warn "OS: ${os_label} (可能不完全兼容)"
  fi

  # Arch
  local arch
  arch="$(uname -m)"
  preflight_pass "Arch: ${arch}"

  # systemd
  if command -v systemctl &>/dev/null; then
    preflight_pass "systemd: available"
  elif [[ "$os_name" == "Darwin" ]]; then
    preflight_pass "systemd: N/A (macOS)"
  else
    preflight_warn "systemd: not found (VPS 部署需要 systemd)"
  fi

  # Core tools
  local missing_tools=()
  for cmd in curl git python3 bash openssl; do
    if command -v "$cmd" &>/dev/null; then
      preflight_pass "${cmd}: $(command -v "$cmd")"
    else
      preflight_fail "${cmd}: not found"
      missing_tools+=("$cmd")
    fi
  done

  # Disk space (only on Linux with df available)
  if command -v df &>/dev/null && [[ "$os_name" == "Linux" ]]; then
    local avail_mb
    avail_mb=$(df -BM / 2>/dev/null | awk 'NR==2 {gsub(/M/,"",$4); print $4}' || echo "")
    if [[ -n "$avail_mb" ]] && [[ "$avail_mb" -gt 500 ]] 2>/dev/null; then
      preflight_pass "Disk: ${avail_mb}MB available on /"
    elif [[ -n "$avail_mb" ]]; then
      preflight_warn "Disk: ${avail_mb}MB available on / (建议 >500MB)"
    fi
  fi

  # Memory (only on Linux)
  if command -v free &>/dev/null && [[ "$os_name" == "Linux" ]]; then
    local mem_mb
    mem_mb=$(free -m 2>/dev/null | awk '/^Mem:/ {print $2}' || echo "")
    if [[ -n "$mem_mb" ]] && [[ "$mem_mb" -ge 512 ]] 2>/dev/null; then
      preflight_pass "Memory: ${mem_mb}MB total"
    elif [[ -n "$mem_mb" ]]; then
      preflight_warn "Memory: ${mem_mb}MB total (建议 ≥512MB)"
    fi
  fi

  # Port checks (VPS protocols)
  if [[ "$DRY_RUN" == "1" ]]; then
    echo ""
    preflight_pass "HY2 :443 (udp): assumed free (dry-run)"
    preflight_pass "TUIC :9443 (udp): assumed free (dry-run)"
    preflight_pass "Reality :8443 (tcp): assumed free (dry-run)"
    preflight_pass "Trojan :2443 (tcp): assumed free (dry-run)"
  elif [[ "$os_name" == "Linux" ]]; then
    echo ""
    check_port_available 443 udp "HY2" || handle_core_port_conflict 443 "HY2" || true
    check_port_available 9443 udp "TUIC" || handle_core_port_conflict 9443 "TUIC" || true
    check_port_available 8443 tcp "Reality" || handle_core_port_conflict 8443 "Reality" || true
    check_port_available 2443 tcp "Trojan" || handle_core_port_conflict 2443 "Trojan" || true
  fi

  # Cloudflare checks
  if [[ "$check_cf" == "true" ]]; then
    echo ""
    log "Cloudflare 工具检查:"

    if command -v node &>/dev/null; then
      local nmajor
      nmajor=$(node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1 || echo "0")
      if [[ "$nmajor" -ge 22 ]] 2>/dev/null; then
        preflight_pass "node: $(node -v) (>=22)"
      else
        preflight_fail "node: $(node -v) (需要 >=22)"
        echo ""
        echo "  Cloudflare 部署需要 Node.js >= 22。"
        echo "  Ubuntu/Debian 推荐："
        echo "    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
        echo "    sudo apt install -y nodejs"
        echo ""
      fi
    else
      preflight_fail "node: not found"
      echo ""
      echo "  Cloudflare 部署需要 Node.js >= 22。"
      echo "  Ubuntu/Debian 推荐："
      echo "    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
      echo "    sudo apt install -y nodejs"
      echo ""
    fi

    if command -v npx &>/dev/null; then
      preflight_pass "npx: available"
    elif command -v npm &>/dev/null; then
      preflight_pass "npm: available (npx not found)"
    else
      preflight_warn "npm/npx: not found"
    fi

    local wrangler_found=0
    if command -v wrangler &>/dev/null; then
      preflight_pass "wrangler: $(wrangler --version 2>/dev/null | head -1)"
      wrangler_found=1
    elif command -v npx &>/dev/null; then
      if npx wrangler --version &>/dev/null 2>&1; then
        preflight_pass "wrangler (via npx): $(npx wrangler --version 2>/dev/null | head -1)"
        wrangler_found=1
      fi
    fi
    if [[ "$wrangler_found" == "0" ]]; then
      preflight_warn "wrangler: not found (npm install -g wrangler)"
    fi

    if [[ "$wrangler_found" == "1" ]] && [[ "$DRY_RUN" != "1" ]]; then
      local wcmd="wrangler"
      command -v wrangler &>/dev/null || wcmd="npx wrangler"
      if $wcmd whoami &>/dev/null 2>&1; then
        preflight_pass "wrangler login: authenticated"
      else
        preflight_warn "wrangler login: not authenticated"
        echo ""
        if [[ -z "${DISPLAY:-}" ]] || ! command -v xdg-open &>/dev/null; then
          echo "  检测到无图形界面环境，Wrangler OAuth 需要本地浏览器："
          echo "    1. 本地电脑: ssh -L 8976:127.0.0.1:8976 root@YOUR_VPS_IP"
          echo "    2. VPS 上: wrangler login --browser=false"
          echo "    3. 复制授权 URL 到本地浏览器"
          echo "    4. 验证: wrangler whoami"
        else
          echo "  请执行："
          echo "    wrangler login --browser=false"
          echo "  如果通过 SSH 连接 VPS，可在本机建立隧道："
          echo "    ssh -L 8976:127.0.0.1:8976 root@YOUR_VPS_IP"
          echo ""
        fi
      fi
    fi
  fi

  # Bot checks
  if [[ "$check_bot" == "true" ]]; then
    echo ""
    log "Bot 工具检查:"
    if command -v python3 &>/dev/null; then
      preflight_pass "python3: $(python3 --version 2>&1)"
      if python3 -c "import venv" &>/dev/null 2>&1; then
        preflight_pass "python3-venv: available"
      else
        preflight_warn "python3-venv: not available"
        echo ""
        echo "  Bot 运行需要 python3-venv。Ubuntu/Debian 安装："
        echo "    sudo apt update && sudo apt install -y python3-venv"
        echo "  如果仍失败："
        echo "    sudo apt install -y python3.12-venv"
        echo ""
      fi
    else
      preflight_fail "python3: not found (Bot 需要 python3)"
    fi
  fi

  # Web checks
  if [[ "$check_web" == "true" ]]; then
    echo ""
    log "Web Panel 工具检查:"
    local web_port="${NANOBK_WEB_PORT:-8080}"
    if [[ "$DRY_RUN" == "1" ]]; then
      preflight_pass "Web Panel :${web_port} (tcp): assumed free (dry-run)"
    else
      check_port_available "$web_port" tcp "Web Panel" || true
    fi
    if command -v python3 &>/dev/null; then
      if python3 -c "import venv" &>/dev/null 2>&1; then
        preflight_pass "python3-venv: available"
      else
        preflight_warn "python3-venv: not available (Web Panel 需要)"
      fi
    fi
  fi

  # Summary
  echo ""
  if [[ $PREFLIGHT_ERRORS -eq 0 ]] && [[ $PREFLIGHT_WARNINGS -eq 0 ]]; then
    echo -e "  ${GREEN}Preflight: ALL CHECKS PASSED${NC}"
  elif [[ $PREFLIGHT_ERRORS -eq 0 ]]; then
    echo -e "  ${YELLOW}Preflight: ${PREFLIGHT_WARNINGS} warning(s), no errors.${NC}"
  else
    echo -e "  ${RED}Preflight: ${PREFLIGHT_ERRORS} error(s), ${PREFLIGHT_WARNINGS} warning(s).${NC}"
  fi
  echo ""

  return $PREFLIGHT_ERRORS
}

# ── Full wizard ─────────────────────────────────────────────────────────────

run_full_wizard() {
  NANOBK_DEPLOY_CLOUDFLARE="true"
  NANOBK_DEPLOY_NANOB="true"
  NANOBK_ENABLE_BOT="true"
  NANOBK_ENABLE_WEB="true"

  # Stage status tracking
  VPS_STAGE_STATUS="unknown"
  CF_STAGE_STATUS="unknown"
  BOT_STAGE_STATUS="unknown"
  WEB_STAGE_STATUS="unknown"
  SUMMARY_HAS_FAILURES=0

  echo ""
  echo -e "${BOLD}═══ Full Recommended — VPS + Cloudflare + Bot + Web Panel ═══${NC}"
  echo ""
  echo "  将引导你完成以下步骤："
  echo "    0. Preflight 环境预检"
  echo "    1. VPS 四协议部署"
  echo "    2. Cloudflare nanok/nanob 订阅部署"
  echo "    3. Telegram Bot 配置"
  echo "    4. Web Panel 配置"
  echo "    5. 最终摘要"
  echo ""
  echo -e "  ${YELLOW}安全提示：${NC}"
  echo "    - 一错不崩，每一步失败都有恢复命令"
  echo "    - Bot/Web 是控制端配置，不等于节点可用"
  echo "    - 不会泄露 token/password 到屏幕或日志"
  echo ""

  # Check for existing installation state
  if wizard_state_detect_existing 2>/dev/null; then
    echo ""
    wizard_state_print
    echo "    1) 从推荐阶段继续"
    echo "    2) 从 VPS 重新配置"
    echo "    3) 从 Cloudflare 继续"
    echo "    4) 只配置 Bot/Web"
    echo "    5) 查看恢复命令"
    echo "    6) 退出"
    echo ""
    local resume_choice
    prompt_menu_choice resume_choice "请选择" "1" "6"
    local START_FROM_STAGE="auto"
    case "$resume_choice" in
      1) START_FROM_STAGE="auto" ;;  # Continue with recommended flow
      2) START_FROM_STAGE="vps" ;;  # Continue with VPS
      3)
        # Skip to Cloudflare
        START_FROM_STAGE="cloudflare"
        VPS_STAGE_STATUS="installed"
        CF_STAGE_STATUS="unknown"
        ;;
      4)
        # Skip to Bot/Web
        START_FROM_STAGE="botweb"
        VPS_STAGE_STATUS="installed"
        CF_STAGE_STATUS="deployed"
        ;;
      5)
        echo ""
        echo "  恢复命令："
        echo "    bash installer/install.sh --mode vps --lang zh"
        echo "    bash installer/install.sh --mode cloudflare --lang zh"
        echo "    bash installer/install.sh --mode bot --lang zh"
        echo "    bash installer/install.sh --mode web --lang zh"
        echo "    sudo bash /opt/nanobk/bin/healthcheck.sh"
        echo "    bash bin/nanobk status"
        echo "    bash bin/nanobk cf verify"
        echo ""
        return 0
        ;;
      6)
        return 0
        ;;
    esac
  fi

  # Phase 0: Preflight
  local START_FROM_STAGE="${START_FROM_STAGE:-auto}"
  run_unified_preflight || true

  # Phase 1: VPS (skip if resuming from cloudflare/botweb)
  echo ""
  echo -e "${BOLD}── 阶段 1：VPS 部署 ──${NC}"
  echo ""
  if [[ "$START_FROM_STAGE" == "cloudflare" ]] || [[ "$START_FROM_STAGE" == "botweb" ]]; then
    echo "  已跳过 VPS 部署（从 ${START_FROM_STAGE} 继续）。"
  elif confirm "是否配置 VPS 部署？" "y"; then
    local vps_rc=0
    collect_vps_args || vps_rc=$?
    case "$vps_rc" in
      0)
        # Check what actually happened
        case "${LAST_RUN_CMD_STATUS:-unknown}" in
          executed)
            VPS_STAGE_STATUS="installed"
            ;;
          dry_run)
            VPS_STAGE_STATUS="dry_run"
            ;;
          commands_only)
            VPS_STAGE_STATUS="commands_only"
            ;;
          skipped_user)
            VPS_STAGE_STATUS="manual_pending"
            SUMMARY_HAS_FAILURES=1
            warn "VPS 部署命令已跳过，未实际执行。"
            echo ""
            echo "  你可以手动执行："
            echo "    bash installer/install.sh --mode vps --lang zh"
            echo ""
            ;;
          *)
            VPS_STAGE_STATUS="installed"
            ;;
        esac
        ;;
      *)
        VPS_STAGE_STATUS="failed"
        SUMMARY_HAS_FAILURES=1
        warn "VPS 阶段失败。"
        echo ""
        echo "  恢复命令："
        echo "    bash installer/install.sh --mode vps --lang zh"
        echo ""
        ;;
    esac

    if [[ "$VPS_STAGE_STATUS" == "failed" ]] || [[ "$VPS_STAGE_STATUS" == "manual_pending" ]]; then
      if [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
        echo "  VPS 未完成，Cloudflare 将被跳过（依赖 profile.current.json）。"
        echo "  Bot/Web 可以配置，但仅为控制端，不代表节点可用。"
        echo ""
        if ! confirm "是否继续配置 Bot/Web（控制端）？" "n"; then
          save_config
          print_summary
          return 1
        fi
      fi
    fi
  else
    VPS_STAGE_STATUS="skipped"
    echo "  跳过 VPS 部署。"
  fi

  # Write wizard state
  [[ "$DRY_RUN" != "1" ]] && wizard_state_write "vps_done" 2>/dev/null || true

  # Phase 2: Cloudflare — strict dependency on VPS profile
  echo ""
  echo -e "${BOLD}── 阶段 2：Cloudflare 部署 ──${NC}"
  echo ""

  # Check if profile exists (skip in dry-run) — unconditional dependency check
  if [[ "$DRY_RUN" != "1" ]] && [[ ! -f "/etc/nanobk/profile.current.json" ]]; then
    CF_STAGE_STATUS="skipped_dependency"
    warn "Cloudflare 部署需要 /etc/nanobk/profile.current.json"
    warn "请先完成 VPS 安装。"
    echo ""
    echo "  恢复命令："
    echo "    bash installer/install.sh --mode vps --lang zh"
    echo "    sudo bash /opt/nanobk/bin/healthcheck.sh"
    echo "    bash bin/nanobk status"
    echo "    bash installer/install.sh --mode cloudflare --lang zh"
    echo "    bash bin/nanobk cf verify"
    echo ""
    echo "  如果 /opt/nanobk/bin/healthcheck.sh 不存在："
    echo "    sudo bash installer/install-vps.sh --yes --domain YOUR_DOMAIN --cert-mode self-signed --open-firewall --force"
    echo ""
  fi

  # Only proceed with Cloudflare if dependency check passed and not skipping
  if [[ "$START_FROM_STAGE" == "botweb" ]]; then
    echo "  已跳过 Cloudflare 部署（从 botweb 继续）。"
  elif [[ "$CF_STAGE_STATUS" != "skipped_dependency" ]]; then
    if confirm "是否配置 Cloudflare 部署？" "y"; then
      NANOBK_DEPLOY_CLOUDFLARE="true"
      CF_DEPLOY_STATUS="unknown"
      local cf_rc=0
      collect_cloudflare_args || cf_rc=$?
      case "$cf_rc" in
        0)
          # Check what actually happened
          case "${CF_DEPLOY_STATUS:-unknown}" in
            executed)      CF_STAGE_STATUS="deployed" ;;
            dry_run)       CF_STAGE_STATUS="dry_run" ;;
            commands_only) CF_STAGE_STATUS="commands_only" ;;
            skipped_user)
              CF_STAGE_STATUS="manual_pending"
              SUMMARY_HAS_FAILURES=1
              warn "Cloudflare 部署命令已跳过，未实际执行。"
              echo ""
              echo "  你可以手动执行："
              echo "    bash installer/install.sh --mode cloudflare --lang zh"
              echo "    bash bin/nanobk cf verify"
              echo ""
              ;;
            failed)
              CF_STAGE_STATUS="failed"
              SUMMARY_HAS_FAILURES=1
              warn "Cloudflare 部署失败。"
              ;;
            *)
              CF_STAGE_STATUS="deployed"
              ;;
          esac
          ;;
        *)
          CF_STAGE_STATUS="failed"
          SUMMARY_HAS_FAILURES=1
          warn "Cloudflare 部署阶段失败。"
          echo ""
          echo "  恢复命令："
          echo "    bash installer/install.sh --mode cloudflare --lang zh"
          echo "    bash bin/nanobk cf verify"
          echo ""
          ;;
      esac

      if [[ "$CF_STAGE_STATUS" == "failed" ]] || [[ "$CF_STAGE_STATUS" == "manual_pending" ]]; then
        if [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
          if ! confirm "是否继续后续步骤？" "n"; then
            save_config
            print_summary
            return 1
          fi
        fi
      fi
    else
      NANOBK_DEPLOY_CLOUDFLARE="false"
      CF_STAGE_STATUS="skipped"
      echo "  跳过 Cloudflare 部署。"
    fi
  fi

  # Write wizard state
  [[ "$DRY_RUN" != "1" ]] && wizard_state_write "cloudflare_done" 2>/dev/null || true

  # Phase 3: Bot
  echo ""
  echo -e "${BOLD}── 阶段 3：Telegram Bot ──${NC}"
  echo ""

  # Control-plane-only warning if VPS/CF not ready
  if control_plane_only_required; then
    echo -e "  ${YELLOW}注意：Bot 是控制端配置，不代表 VPS 节点或 Cloudflare 订阅已经可用。${NC}"
    echo ""
  fi

  if confirm "是否配置 Telegram Bot？" "y"; then
    NANOBK_ENABLE_BOT="true"
    if collect_bot_args; then
      if control_plane_only_required; then
        BOT_STAGE_STATUS="control_only"
      else
        BOT_STAGE_STATUS="configured"
      fi
    else
      BOT_STAGE_STATUS="failed"
      SUMMARY_HAS_FAILURES=1
      warn "Bot 配置失败。"
      echo ""
      echo "  恢复命令："
      echo "    cd bot"
      echo "    cp .env.example .env"
      echo "    nano .env"
      echo "    bash run.sh"
      echo "    python3 nanobk_bot.py --self-test"
      echo ""
    fi
  else
    NANOBK_ENABLE_BOT="false"
    BOT_STAGE_STATUS="skipped"
    echo "  跳过 Telegram Bot。"
  fi

  # Phase 4: Web Panel
  echo ""
  echo -e "${BOLD}── 阶段 4：Web Panel ──${NC}"
  echo ""

  # Control-plane-only warning if VPS/CF not ready
  if control_plane_only_required; then
    echo -e "  ${YELLOW}注意：Web Panel 是控制端配置，不代表 VPS 节点或 Cloudflare 订阅已经可用。${NC}"
    echo ""
  fi

  if confirm "是否配置 Web Panel？" "y"; then
    NANOBK_ENABLE_WEB="true"
    if collect_web_args; then
      if control_plane_only_required; then
        WEB_STAGE_STATUS="control_only"
      else
        WEB_STAGE_STATUS="configured"
      fi
    else
      WEB_STAGE_STATUS="failed"
      SUMMARY_HAS_FAILURES=1
      warn "Web Panel 配置失败。"
      echo ""
      echo "  恢复命令："
      echo "    cd web"
      echo "    cp .env.example .env"
      echo "    nano .env"
      echo "    bash run.sh"
      echo "    ssh -L 8080:127.0.0.1:8080 root@YOUR_VPS_IP"
      echo ""
    fi
  else
    NANOBK_ENABLE_WEB="false"
    WEB_STAGE_STATUS="skipped"
    echo "  跳过 Web Panel。"
  fi

  # Save config
  save_config

  # Write final wizard state
  [[ "$DRY_RUN" != "1" ]] && wizard_state_write "completed" 2>/dev/null || true

  # Phase 5: Summary
  print_summary
}

# ── Summary ─────────────────────────────────────────────────────────────────

print_summary() {
  echo ""
  echo -e "${BOLD}────────────────────────────${NC}"
  echo -e "${BOLD}  NanoBK Setup Summary${NC}"
  echo -e "${BOLD}────────────────────────────${NC}"
  echo ""

  # VPS — honest status
  echo "  VPS:"
  if [[ "${VPS_STAGE_STATUS:-}" == "dry_run" ]]; then
    echo "    domain:  ${NANOBK_DOMAIN:-unknown}"
    echo "    cert:    ${NANOBK_CERT_MODE:-unknown}"
    echo "    status:  planned / dry-run"
  elif [[ "${VPS_STAGE_STATUS:-}" == "commands_only" ]]; then
    echo "    domain:  ${NANOBK_DOMAIN:-unknown}"
    echo "    status:  commands only / not executed"
  elif [[ "${VPS_STAGE_STATUS:-}" == "manual_pending" ]]; then
    echo "    domain:  ${NANOBK_DOMAIN:-unknown}"
    echo "    status:  manual command not executed"
    echo "    note:    deploy command was printed but not run"
    echo "    next:"
    echo "      bash installer/install.sh --mode vps --lang zh"
  elif [[ "${VPS_STAGE_STATUS:-}" == "failed" ]]; then
    echo "    status:  failed"
    echo "    reason:  install-vps failed"
    echo "    recover:"
    echo "      bash installer/install.sh --mode vps --lang zh"
  elif [[ "$DRY_RUN" == "1" ]]; then
    if [[ -n "${NANOBK_DOMAIN:-}" ]] && [[ "$NANOBK_DOMAIN" != "proxy.example.com" ]]; then
      echo "    domain:  ${NANOBK_DOMAIN}"
      echo "    cert:    ${NANOBK_CERT_MODE:-unknown}"
      echo "    status:  planned / dry-run"
    else
      echo "    status:  skipped (dry-run)"
    fi
  elif [[ -f "/etc/nanobk/profile.current.json" ]]; then
    echo "    domain:  ${NANOBK_DOMAIN:-unknown}"
    echo "    status:  installed / not healthchecked"
    echo "    note:    run nanobk status or healthcheck to verify services"
  elif [[ -n "${NANOBK_DOMAIN:-}" ]] && [[ "$NANOBK_DOMAIN" != "proxy.example.com" ]]; then
    echo "    domain:  ${NANOBK_DOMAIN}"
    echo "    cert:    ${NANOBK_CERT_MODE:-unknown}"
    echo "    status:  configured / not verified"
  else
    echo "    status:  skipped"
  fi

  # Cloudflare — honest status
  echo ""
  echo "  Cloudflare:"
  if [[ "${CF_STAGE_STATUS:-}" == "skipped_dependency" ]]; then
    echo "    status:  skipped / dependency missing"
    echo "    reason:  /etc/nanobk/profile.current.json not found"
    echo "    recover:"
    echo "      finish VPS first, then run:"
    echo "      bash installer/install.sh --mode cloudflare --lang zh"
  elif [[ "${CF_STAGE_STATUS:-}" == "dry_run" ]]; then
    echo "    status:  planned / dry-run"
  elif [[ "${CF_STAGE_STATUS:-}" == "commands_only" ]]; then
    echo "    status:  commands only / not executed"
  elif [[ "${CF_STAGE_STATUS:-}" == "manual_pending" ]]; then
    echo "    status:  manual command not executed"
    echo "    note:    deploy command was printed but not run"
    echo "    next:"
    echo "      bash installer/install.sh --mode cloudflare --lang zh"
    echo "      bash bin/nanobk cf verify"
  elif [[ "${CF_STAGE_STATUS:-}" == "failed" ]]; then
    echo "    status:  failed / needs retry"
    echo "    recover:"
    echo "      bash installer/install.sh --mode cloudflare --lang zh"
    echo "      bash bin/nanobk cf verify"
  elif [[ "$DRY_RUN" == "1" ]]; then
    if [[ "${NANOBK_DEPLOY_CLOUDFLARE:-}" == "true" ]]; then
      echo "    nanok:   planned / dry-run"
      [[ -n "${NANOBK_NANOK_URL:-}" ]] && echo "    url:     ${NANOBK_NANOK_URL}"
      if [[ "${NANOBK_DEPLOY_NANOB:-}" == "true" ]]; then
        echo "    nanob:   planned / dry-run"
        [[ -n "${NANOBK_NANOB_URL:-}" ]] && echo "    url:     ${NANOBK_NANOB_URL}"
      fi
    else
      echo "    status:  skipped (dry-run)"
    fi
  elif [[ -f "${REPO_DIR:-.}/.cloudflare.local.env" ]]; then
    local cf_verify
    cf_verify=$(read_env_value "${REPO_DIR:-.}/.cloudflare.local.env" "NANOBK_VERIFY_STATUS" 2>/dev/null || echo "")
    if [[ "$cf_verify" == "verified" ]]; then
      echo "    nanok:   verified"
    else
      echo "    nanok:   configured / ${cf_verify:-pending}"
    fi
    if [[ -f "${REPO_DIR:-.}/.nanob.local.env" ]]; then
      local nanob_verify
      nanob_verify=$(read_env_value "${REPO_DIR:-.}/.nanob.local.env" "NANOB_VERIFY_STATUS" 2>/dev/null || echo "")
      if [[ "$nanob_verify" == "verified" ]]; then
        echo "    nanob:   verified"
      else
        echo "    nanob:   configured / ${nanob_verify:-pending}"
      fi
    fi
  elif [[ "${NANOBK_DEPLOY_CLOUDFLARE:-}" == "true" ]]; then
    echo "    status:  unknown / not configured"
    echo "    note:    Cloudflare was requested but no deployment evidence found"
  else
    echo "    status:  skipped"
  fi

  # Bot — honest status
  echo ""
  echo "  Telegram Bot:"
  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ "${NANOBK_ENABLE_BOT:-}" == "true" ]]; then
      echo "    status:  planned / dry-run"
      echo "    dry-run: ${NANOBK_BOT_DRY_RUN:-true}"
    else
      echo "    status:  skipped (dry-run)"
    fi
  elif [[ "${BOT_STAGE_STATUS:-}" == "failed" ]]; then
    echo "    status:  failed"
    echo "    recover:"
    echo "      cd bot && cp .env.example .env && nano .env"
    echo "      bash run.sh"
    echo "      python3 nanobk_bot.py --self-test"
  elif [[ "${BOT_STAGE_STATUS:-}" == "control_only" ]]; then
    echo "    status:  configured / control plane only"
    echo "    note:    VPS/Cloudflare are not verified yet"
    echo "    env:     bot/.env"
    echo "    dry-run: ${NANOBK_BOT_DRY_RUN:-true}"
    echo "    start:   cd bot && bash run.sh"
  elif [[ -f "${REPO_DIR:-.}/bot/.env" ]]; then
    echo "    status:  configured"
    echo "    env:     bot/.env"
    echo "    dry-run: ${NANOBK_BOT_DRY_RUN:-true}"
    echo "    start:   cd bot && bash run.sh"
  elif [[ "${NANOBK_ENABLE_BOT:-}" == "true" ]]; then
    echo "    status:  planned / env not created"
  else
    echo "    status:  skipped"
  fi

  # Web Panel — honest status
  echo ""
  echo "  Web Panel:"
  if [[ "$DRY_RUN" == "1" ]]; then
    if [[ "${NANOBK_ENABLE_WEB:-}" == "true" ]]; then
      echo "    status:  planned / dry-run"
      echo "    listen:  ${NANOBK_WEB_HOST:-127.0.0.1}:${NANOBK_WEB_PORT:-8080}"
      echo "    dry-run: ${NANOBK_WEB_DRY_RUN:-true}"
    else
      echo "    status:  skipped (dry-run)"
    fi
  elif [[ "${WEB_STAGE_STATUS:-}" == "failed" ]]; then
    echo "    status:  failed"
    echo "    recover:"
    echo "      cd web && cp .env.example .env && nano .env"
    echo "      bash run.sh"
    echo "      ssh -L ${NANOBK_WEB_PORT:-8080}:127.0.0.1:${NANOBK_WEB_PORT:-8080} root@YOUR_VPS_IP"
  elif [[ "${WEB_STAGE_STATUS:-}" == "control_only" ]]; then
    echo "    status:  configured / control plane only"
    echo "    note:    VPS/Cloudflare are not verified yet"
    echo "    env:     web/.env"
    echo "    listen:  ${NANOBK_WEB_HOST:-127.0.0.1}:${NANOBK_WEB_PORT:-8080}"
    echo "    dry-run: ${NANOBK_WEB_DRY_RUN:-true}"
    echo "    start:   cd web && bash run.sh"
  elif [[ -f "${REPO_DIR:-.}/web/.env" ]]; then
    echo "    status:  configured"
    echo "    env:     web/.env"
    echo "    listen:  ${NANOBK_WEB_HOST:-127.0.0.1}:${NANOBK_WEB_PORT:-8080}"
    echo "    dry-run: ${NANOBK_WEB_DRY_RUN:-true}"
    echo "    start:   cd web && bash run.sh"
    echo "    access:  ssh -L ${NANOBK_WEB_PORT:-8080}:127.0.0.1:${NANOBK_WEB_PORT:-8080} root@YOUR_VPS_IP"
  elif [[ "${NANOBK_ENABLE_WEB:-}" == "true" ]]; then
    echo "    status:  planned / env not created"
  else
    echo "    status:  skipped"
  fi

  # Warnings
  local has_warnings=0
  if [[ "${BOT_STAGE_STATUS:-}" == "control_only" ]] || [[ "${WEB_STAGE_STATUS:-}" == "control_only" ]]; then
    echo ""
    echo "  Warnings:"
    echo "    - Bot/Web are control plane only."
    echo "    - VPS status: ${VPS_STAGE_STATUS:-unknown}"
    echo "    - Cloudflare status: ${CF_STAGE_STATUS:-unknown}"
    echo "    - Control plane configuration does not mean nodes or subscriptions are usable."
    has_warnings=1
  fi

  # Next commands and recovery
  echo ""
  if control_plane_only_required; then
    echo "  恢复命令:"
    case "${VPS_STAGE_STATUS:-unknown}" in
      installed) ;;
      *) echo "    bash installer/install.sh --mode vps --lang zh" ;;
    esac
    case "${CF_STAGE_STATUS:-unknown}" in
      deployed|verified) ;;
      *) echo "    bash installer/install.sh --mode cloudflare --lang zh" ;;
    esac
    echo "    sudo bash /opt/nanobk/bin/healthcheck.sh"
    echo "    bash bin/nanobk status"
    echo "    bash bin/nanobk cf verify"
  else
    echo "  Next commands:"
    echo "    nanobk status"
    echo "    nanobk cf verify"
    echo "    sudo bash /opt/nanobk/bin/rotate-keys.sh --yes --protocol tuic"
  fi
  echo ""

  if [[ -n "$INSTALLER_CONFIG" ]] && [[ -f "$INSTALLER_CONFIG" ]]; then
    echo "  配置已保存: ${INSTALLER_CONFIG}"
    echo "  使用 --resume 可以继续上次配置。"
    echo ""
  fi

  # Disclaimers
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${YELLOW}注意: 这是 dry-run 摘要，没有执行真实部署。${NC}"
    echo -e "  ${YELLOW}Note: This is a dry-run summary. No real deployment was performed.${NC}"
    echo ""
  fi
  if [[ "$COMMAND_ONLY" == "1" ]]; then
    echo -e "  ${YELLOW}注意: commands-only 模式只输出命令，不代表当前系统已经可用。${NC}"
    echo -e "  ${YELLOW}Note: Commands-only mode only outputs commands, not system validation.${NC}"
    echo ""
  fi
}

# ── Mode handlers ───────────────────────────────────────────────────────────

run_vps_mode() {
  if [[ "$ENV_IS_LINUX" != "1" ]] && [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
    warn "当前不是 Linux 系统，VPS 安装需要在 Linux VPS 上运行。"
    if ! confirm "仍然继续（可能失败）？" "n"; then
      return
    fi
  fi
  collect_vps_args
}

require_default_profile_for_cloudflare() {
  local profile="${NANOBK_DEFAULT_PROFILE_PATH:-/etc/nanobk/profile.current.json}"
  if [[ ! -f "$profile" ]]; then
    warn "Cloudflare 部署需要 ${profile}"
    warn "这通常表示 VPS 四协议尚未安装完成。"
    echo ""
    echo "  请先运行："
    echo "    bash installer/install.sh --mode vps --lang zh"
    echo ""
    echo "  或直接运行底层安装："
    echo "    sudo bash installer/install-vps.sh --yes --domain YOUR_DOMAIN --cert-mode self-signed --open-firewall --force"
    echo ""
    echo "  完成后再运行："
    echo "    bash installer/install.sh --mode cloudflare --lang zh"
    echo ""
    return 1
  fi
  return 0
}

run_cloudflare_mode() {
  if ! require_default_profile_for_cloudflare; then
    CF_STAGE_STATUS="skipped_dependency"
    NANOBK_DEPLOY_CLOUDFLARE="false"
    print_summary
    return 1
  fi
  collect_cloudflare_args
  save_config
}

run_bot_mode() {
  collect_bot_args
  save_config
}

run_web_mode() {
  collect_web_args
  save_config
}

# ── Combo mode handlers ────────────────────────────────────────────────────

run_cli_only_mode() {
  echo ""
  echo -e "${BOLD}═══ CLI Only — VPS 四协议 + nanobk CLI ═══${NC}"
  echo ""
  NANOBK_DEPLOY_CLOUDFLARE="false"
  NANOBK_ENABLE_BOT="false"
  NANOBK_ENABLE_WEB="false"

  # Preflight: VPS checks only
  run_unified_preflight || true

  if [[ "$ENV_IS_LINUX" != "1" ]] && [[ "$DRY_RUN" != "1" ]] && [[ "$COMMAND_ONLY" != "1" ]]; then
    warn "当前不是 Linux 系统，VPS 安装需要在 Linux VPS 上运行。"
    if ! confirm "仍然继续（可能失败）？" "n"; then
      return
    fi
  fi
  collect_vps_args
  save_config
  print_summary
}

run_cli_bot_mode() {
  echo ""
  echo -e "${BOLD}═══ CLI + Bot — VPS + Telegram Bot ═══${NC}"
  echo ""
  NANOBK_ENABLE_BOT="true"
  NANOBK_DEPLOY_CLOUDFLARE="false"
  NANOBK_ENABLE_WEB="false"

  # Preflight: VPS + Bot checks
  run_unified_preflight || true

  if confirm "是否配置 VPS 部署？" "y"; then
    if ! collect_vps_args; then
      warn "VPS 部署阶段失败。"
    fi
  fi

  echo ""
  collect_bot_args
  save_config
  print_summary
}

run_cli_web_mode() {
  echo ""
  echo -e "${BOLD}═══ CLI + Web — VPS + Web Panel ═══${NC}"
  echo ""
  NANOBK_ENABLE_WEB="true"
  NANOBK_DEPLOY_CLOUDFLARE="false"
  NANOBK_ENABLE_BOT="false"

  # Preflight: VPS + Web checks
  run_unified_preflight || true

  if confirm "是否配置 VPS 部署？" "y"; then
    if ! collect_vps_args; then
      warn "VPS 部署阶段失败。"
    fi
  fi

  echo ""
  collect_web_args
  save_config
  print_summary
}

run_cli_bot_web_mode() {
  echo ""
  echo -e "${BOLD}═══ CLI + Bot + Web — VPS + Telegram Bot + Web Panel ═══${NC}"
  echo ""
  NANOBK_ENABLE_BOT="true"
  NANOBK_ENABLE_WEB="true"
  NANOBK_DEPLOY_CLOUDFLARE="false"

  # Preflight: VPS + Bot + Web checks
  run_unified_preflight || true

  if confirm "是否配置 VPS 部署？" "y"; then
    if ! collect_vps_args; then
      warn "VPS 部署阶段失败。"
    fi
  fi

  echo ""
  collect_bot_args
  echo ""
  collect_web_args
  save_config
  print_summary
}

run_rotate_mode() {
  echo ""
  echo -e "${BOLD}── 一键换密钥 ──${NC}"
  echo ""

  local config_dir cf_admin_env skip_cf skip_svc

  prompt config_dir "config-dir" "/etc/nanobk"
  prompt cf_admin_env "cf-admin-env 路径" "/root/.nanok-cf-admin.env"

  if confirm "跳过 Cloudflare 同步？" "n"; then
    skip_cf=1
  else
    skip_cf=0
  fi

  if confirm "跳过服务重启？" "n"; then
    skip_svc=1
  else
    skip_svc=0
  fi

  local cmd=(sudo bash "$REPO_DIR/vps/scripts/rotate-keys.sh" --yes
    --config-dir "$config_dir"
    --cf-admin-env "$cf_admin_env")

  [[ "$skip_cf" == "1" ]] && cmd+=(--skip-cloudflare)
  [[ "$skip_svc" == "1" ]] && cmd+=(--skip-services)
  [[ "$DRY_RUN" == "1" ]] && cmd+=(--dry-run)

  echo ""
  echo -e "  ${YELLOW}提示：此命令需要在 VPS 上以 root 运行。${NC}"

  run_cmd "一键换密钥" "${cmd[@]}"
}

run_doctor_mode() {
  run_cmd "运行环境诊断" bash "$REPO_DIR/installer/doctor.sh"
}

finalize_test_mode() {
  if [[ "${TEST_FAILURES:-0}" -gt 0 ]]; then
    echo ""
    err "本地安全测试失败: ${TEST_FAILURES}"
    echo "  失败项目："
    for name in "${TEST_FAILED_NAMES[@]}"; do
      echo "    - $name"
    done
    return 1
  fi
  ok "本地安全测试全部通过"
  return 0
}

run_safe_test() {
  local script="$1"
  local label="$2"
  if [[ -f "$script" ]]; then
    run_one_test "$script" "$label" || true
  else
    warn "测试文件不存在: $script"
    TEST_FAILURES=$((TEST_FAILURES + 1))
    TEST_FAILED_NAMES+=("${label} (missing)")
  fi
}

run_test_mode() {
  # Reset failure state
  TEST_FAILURES=0
  TEST_FAILED_NAMES=()

  echo ""
  echo -e "${BOLD}── 本地安全测试 ──${NC}"

  # Test override hook (for test harness only)
  if [[ -n "${NANOBK_TEST_OVERRIDE_SCRIPT:-}" ]]; then
    local override_label="${NANOBK_TEST_OVERRIDE_LABEL:-override test}"
    warn "Using NANOBK_TEST_OVERRIDE_SCRIPT for test harness"
    run_safe_test "$NANOBK_TEST_OVERRIDE_SCRIPT" "$override_label"
    finalize_test_mode
    return $?
  fi

  echo ""
  echo "  1) Quick tests (核心 CLI + VPS render)"
  echo "  2) Installer tests (安装器 dry-run/config/resume)"
  echo "  3) Cloudflare tests (KV parser/profile/validation)"
  echo "  4) Bot/Web tests (mock self-tests)"
  echo "  5) All safe tests (全部离线安全测试)"
  echo ""

  local choice
  prompt choice "请选择" "5"

  case "$choice" in
    1)
      run_safe_test "$REPO_DIR/tests/nanobk-cli-dry-run.sh" "CLI dry-run"
      run_safe_test "$REPO_DIR/tests/render-install-vps.sh" "VPS render-only"
      run_safe_test "$REPO_DIR/tests/rotate-render-only.sh" "rotate offline"
      run_safe_test "$REPO_DIR/tests/nanobk-status-cloudflare.sh" "status + security"
      ;;
    2)
      run_safe_test "$REPO_DIR/tests/unified-beginner-flow.sh" "beginner flow"
      run_safe_test "$REPO_DIR/tests/unified-preflight-static.sh" "preflight static"
      run_safe_test "$REPO_DIR/tests/unified-installer-dry-run.sh" "installer dry-run"
      run_safe_test "$REPO_DIR/tests/unified-installer-config.sh" "installer config"
      run_safe_test "$REPO_DIR/tests/unified-installer-resume.sh" "installer resume"
      run_safe_test "$REPO_DIR/tests/unified-validation-plan.sh" "validation plan"
      run_safe_test "$REPO_DIR/tests/unified-full-wizard-productization.sh" "full wizard productization"
      run_safe_test "$REPO_DIR/tests/unified-summary-honesty.sh" "summary honesty"
      run_safe_test "$REPO_DIR/tests/unified-full-wizard-behavior.sh" "full wizard behavior"
      run_safe_test "$REPO_DIR/tests/rotate-render-only-tempdir.sh" "rotate tempdir"
      ;;
    3)
      run_safe_test "$REPO_DIR/tests/cloudflare-kv-parser.sh" "KV parser"
      run_safe_test "$REPO_DIR/tests/cloudflare-installer-dry-run.sh" "CF installer dry-run"
      run_safe_test "$REPO_DIR/tests/cloudflare-profile-validation.sh" "profile validation"
      run_safe_test "$REPO_DIR/tests/nanob-fallback-static.sh" "nanob fallback"
      run_safe_test "$REPO_DIR/tests/nanob-status-env.sh" "nanob status env"
      run_safe_test "$REPO_DIR/tests/rotate-cloudflare-stale-read-static.sh" "stale read"
      run_safe_test "$REPO_DIR/tests/cloudflare-sync-retry-static.sh" "sync retry"
      ;;
    4)
      run_safe_test "$REPO_DIR/tests/bot-cli-mock.sh" "bot mock"
      run_safe_test "$REPO_DIR/tests/web-panel-mock.sh" "web panel mock"
      ;;
    5)
      run_safe_test "$REPO_DIR/tests/unified-beginner-flow.sh" "beginner flow"
      run_safe_test "$REPO_DIR/tests/unified-preflight-static.sh" "preflight static"
      run_safe_test "$REPO_DIR/tests/unified-installer-dry-run.sh" "installer dry-run"
      run_safe_test "$REPO_DIR/tests/unified-installer-config.sh" "installer config"
      run_safe_test "$REPO_DIR/tests/unified-installer-resume.sh" "installer resume"
      run_safe_test "$REPO_DIR/tests/nanobk-cli-dry-run.sh" "CLI dry-run"
      run_safe_test "$REPO_DIR/tests/nanobk-status-cloudflare.sh" "status + security"
      run_safe_test "$REPO_DIR/tests/render-install-vps.sh" "VPS render-only"
      run_safe_test "$REPO_DIR/tests/rotate-render-only.sh" "rotate offline"
      run_safe_test "$REPO_DIR/tests/cloudflare-kv-parser.sh" "KV parser"
      run_safe_test "$REPO_DIR/tests/cloudflare-installer-dry-run.sh" "CF installer dry-run"
      run_safe_test "$REPO_DIR/tests/cloudflare-profile-validation.sh" "profile validation"
      run_safe_test "$REPO_DIR/tests/nanob-fallback-static.sh" "nanob fallback"
      run_safe_test "$REPO_DIR/tests/nanob-status-env.sh" "nanob status env"
      run_safe_test "$REPO_DIR/tests/rotate-cloudflare-stale-read-static.sh" "stale read"
      run_safe_test "$REPO_DIR/tests/cloudflare-sync-retry-static.sh" "sync retry"
      run_safe_test "$REPO_DIR/tests/production-hotfix-static.sh" "production hotfix"
      run_safe_test "$REPO_DIR/tests/installed-layout-rotate.sh" "installed layout"
      run_safe_test "$REPO_DIR/tests/bot-cli-mock.sh" "bot mock"
      run_safe_test "$REPO_DIR/tests/web-panel-mock.sh" "web panel mock"
      run_safe_test "$REPO_DIR/tests/unified-validation-plan.sh" "validation plan"
      run_safe_test "$REPO_DIR/tests/unified-full-wizard-productization.sh" "full wizard productization"
      run_safe_test "$REPO_DIR/tests/unified-summary-honesty.sh" "summary honesty"
      run_safe_test "$REPO_DIR/tests/unified-full-wizard-behavior.sh" "full wizard behavior"
      run_safe_test "$REPO_DIR/tests/unified-real-vps-ux-hardening.sh" "real VPS UX hardening"
      run_safe_test "$REPO_DIR/tests/full-wizard-interactive-mock.sh" "interactive mock"
      run_safe_test "$REPO_DIR/tests/unified-full-wizard-review-resume.sh" "review resume"
      run_safe_test "$REPO_DIR/tests/output-control-chars.sh" "output control chars"
      run_safe_test "$REPO_DIR/tests/rotate-render-only-tempdir.sh" "rotate tempdir"
      ;;
    *) err "无效选择"; return 1 ;;
  esac

  finalize_test_mode
  return $?
}

run_commands_mode() {
  echo ""
  echo -e "${BOLD}═══ 命令模板（可复制） ═══${NC}"
  echo ""
  echo -e "  ${YELLOW}注意: commands-only 模式不会验证系统状态。${NC}"
  echo -e "  ${YELLOW}Note: Commands-only mode does not validate the system.${NC}"
  echo ""

  echo -e "${BOLD}── VPS 部署 ──${NC}"
  echo ""
  echo "  sudo bash installer/install-vps.sh --yes \\"
  echo "    --domain proxy.example.com \\"
  echo "    --cert-mode existing \\"
  echo "    --cert-file /etc/letsencrypt/live/proxy.example.com/fullchain.pem \\"
  echo "    --key-file /etc/letsencrypt/live/proxy.example.com/privkey.pem"
  echo ""

  echo -e "${BOLD}── VPS healthcheck ──${NC}"
  echo ""
  echo "  sudo bash vps/scripts/healthcheck.sh --config-dir /etc/nanobk"
  echo ""

  echo -e "${BOLD}── Cloudflare preflight ──${NC}"
  echo ""
  echo "  bash installer/install-cloudflare.sh --preflight"
  echo ""

  echo -e "${BOLD}── Cloudflare profile validation ──${NC}"
  echo ""
  echo "  bash installer/install-cloudflare.sh --validate-profile-only \\"
  echo "    --profile /etc/nanobk/profile.current.json"
  echo ""

  echo -e "${BOLD}── Cloudflare nanok deploy ──${NC}"
  echo ""
  echo "  bash installer/install-cloudflare.sh --yes \\"
  echo "    --create-kv \\"
  echo "    --profile /etc/nanobk/profile.current.json \\"
  echo "    --route-url https://nanok.example.workers.dev"
  echo ""

  echo -e "${BOLD}── Cloudflare nanok + nanob deploy ──${NC}"
  echo ""
  echo "  bash installer/install-cloudflare.sh --yes \\"
  echo "    --create-kv --create-nanob-geo-kv \\"
  echo "    --profile /etc/nanobk/profile.current.json \\"
  echo "    --route-url https://nanok.example.workers.dev \\"
  echo "    --deploy-nanob \\"
  echo "    --nanob-route-url https://nanob.example.workers.dev"
  echo ""

  echo -e "${BOLD}── 一键换密钥 ──${NC}"
  echo ""
  echo "  sudo bash vps/scripts/rotate-keys.sh --yes"
  echo ""

  echo -e "${BOLD}── Bot 配置模板 ──${NC}"
  echo ""
  echo "  # bot/.env 内容："
  echo "  TELEGRAM_BOT_TOKEN=YOUR_BOT_TOKEN"
  echo "  OWNER_TELEGRAM_ID=YOUR_USER_ID"
  echo "  NANOBK_CLI=$(pwd)/bin/nanobk"
  echo "  NANOBK_REPO_DIR=$(pwd)"
  echo "  NANOBK_BOT_DRY_RUN=true"
  echo "  NANOBK_COMMAND_TIMEOUT=120"
  echo "  NANOBK_ROTATE_TIMEOUT=300"
  echo ""
  echo "  # 启动："
  echo "  cd bot && bash run.sh"
  echo ""

  echo -e "${BOLD}── Web Panel 配置模板 ──${NC}"
  echo ""
  echo "  # web/.env 内容："
  echo "  NANOBK_WEB_TOKEN=YOUR_RANDOM_TOKEN"
  echo "  NANOBK_WEB_SECRET_KEY=YOUR_RANDOM_SECRET"
  echo "  NANOBK_WEB_HOST=127.0.0.1"
  echo "  NANOBK_WEB_PORT=8080"
  echo "  NANOBK_CLI=$(pwd)/bin/nanobk"
  echo "  NANOBK_REPO_DIR=$(pwd)"
  echo "  NANOBK_WEB_DRY_RUN=true"
  echo "  NANOBK_COMMAND_TIMEOUT=120"
  echo "  NANOBK_ROTATE_TIMEOUT=300"
  echo ""
  echo "  # 启动："
  echo "  cd web && bash run.sh"
  echo ""
  echo "  # 访问："
  echo "  ssh -L 8080:127.0.0.1:8080 root@YOUR_VPS_IP"
  echo ""

  echo -e "${BOLD}── 诊断和测试 ──${NC}"
  echo ""
  echo "  bash installer/doctor.sh"
  echo "  bash bin/nanobk status"
  echo "  bash bin/nanobk --json status"
  echo "  bash bin/nanobk cf verify"
  echo "  bash tests/render-install-vps.sh"
  echo "  bash tests/rotate-render-only.sh"
  echo ""
}

# ── Validate plan ──────────────────────────────────────────────────────────

run_validate_plan() {
  cat <<'PLAN'
NanoBK v1.6 Clean VPS Full Wizard Validation Plan
===================================================

⚠ 本计划需要由人工测试员在真实 VPS 上执行。
⚠ dry-run 输出不能代表真实 VPS 验收通过。
⚠ This plan must be executed by a human tester on a real VPS.
⚠ The installer cannot claim real VPS validation from dry-run output.

Phase 0: Baseline
-----------------
  - Clean Ubuntu 24.04 VPS (root access)
  - Domain pointed to VPS IP
  - Cloudflare account with Workers enabled; paid plan may be required
  - Telegram Bot Token from @BotFather
  - Your Telegram numeric User ID

Phase 1: Bootstrap
------------------
  bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/bootstrap.sh)

  Verify:
    - Repository cloned to /opt/NanoBK-Proxy-Suite or ~/NanoBK-Proxy-Suite
    - install.sh launched automatically

Phase 2: Full Recommended Wizard
---------------------------------
  bash installer/install.sh --mode full --lang zh

  Steps:
    1. Preflight checks pass (OS, tools, ports)
    2. VPS domain/cert input
    3. VPS deploy succeeds
    4. Cloudflare preflight passes (Node>=22, wrangler login)
    5. Profile validation passes
    6. nanok KV created and Worker deployed
    7. nanok profile uploaded and verified
    8. nanob deployed and verified
    9. Bot .env generated (chmod 600)
   10. Web Panel .env generated (chmod 600)
   11. Summary shows honest status

Phase 3: VPS Verification
--------------------------
  sudo bash /opt/nanobk/bin/healthcheck.sh

  Verify all pass:
    - HY2 :443 (udp) active
    - TUIC :9443 (udp) active
    - Reality :8443 (tcp) active
    - Trojan :2443 (tcp) active
    - Profile JSON valid
    - Secrets mode 600

Phase 4: Cloudflare Verification
---------------------------------
  bash bin/nanobk cf verify

  Or manually:
  bash installer/install-cloudflare.sh --verify-nanok-only
  bash installer/install-cloudflare.sh --verify-nanob-only

  Verify:
    - nanok subscription returns valid YAML
    - nanob subscription returns valid YAML
    - Both contain all four protocols

Phase 5: nanok Subscription Verification
-----------------------------------------
  curl -fsS "https://YOUR_NANOK_URL/jb?token=YOUR_SUB_TOKEN"

  Verify:
    - Returns valid Clash/Mihomo YAML
    - Contains: proxies, type: hysteria2, type: tuic, type: vless, type: trojan
    - No invalid control characters

Phase 6: nanob Subscription Verification
-----------------------------------------
  curl -fsS "https://YOUR_NANOB_URL/jb?token=YOUR_NANOB_TOKEN"

  Verify:
    - Returns valid YAML
    - Contains all four protocol types
    - If edgetunnel configured, backup nodes present

Phase 7: Bot Env Verification
------------------------------
  stat -c "%a %n" bot/.env
  grep -q '^TELEGRAM_BOT_TOKEN=' bot/.env && echo "TELEGRAM_BOT_TOKEN: present"
  grep -q '^OWNER_TELEGRAM_ID=' bot/.env && echo "OWNER_TELEGRAM_ID: present"
  grep -q '^NANOBK_CLI=' bot/.env && echo "NANOBK_CLI: present"
  python3 bot/nanobk_bot.py --self-test

  Verify:
    - File mode 600
    - TELEGRAM_BOT_TOKEN: present
    - OWNER_TELEGRAM_ID: present
    - NANOBK_CLI: present
    - Self-test passes

  ⚠ Do NOT cat bot/.env — prints tokens to terminal/logs

Phase 8: Web Panel Env Verification
-------------------------------------
  stat -c "%a %n" web/.env
  grep -q '^NANOBK_WEB_TOKEN=' web/.env && echo "NANOBK_WEB_TOKEN: present"
  grep -q '^NANOBK_WEB_SECRET_KEY=' web/.env && echo "NANOBK_WEB_SECRET_KEY: present"
  grep -q '^NANOBK_WEB_HOST=127.0.0.1' web/.env && echo "NANOBK_WEB_HOST: 127.0.0.1"
  python3 web/app.py --self-test

  Verify:
    - File mode 600
    - NANOBK_WEB_TOKEN: present
    - NANOBK_WEB_SECRET_KEY: present
    - NANOBK_WEB_HOST=127.0.0.1
    - File mode 600
    - python3 web/app.py --self-test passes

Phase 9: Rotate TUIC + Cloudflare Sync
----------------------------------------
  sudo bash /opt/nanobk/bin/rotate-keys.sh --yes --protocol tuic

  Verify:
    - New credentials generated
    - Backup created
    - Services restarted
    - Healthcheck passes
    - Cloudflare profile updated and verified
    - New TUIC UUID/password in profile

Phase 10: Final Status
-----------------------
  bash bin/nanobk status
  bash bin/nanobk --json status | python3 -m json.tool

  Verify:
    - ok: true
    - All four services active
    - Cloudflare nanok verifyStatus: verified
    - Cloudflare nanob verifyStatus: verified

Pass Criteria
-------------
  - All 10 phases complete without errors
  - All four proxy protocols active
  - Cloudflare subscriptions verified
  - Rotate with Cloudflare sync works
  - Summary shows honest status throughout

Fail Criteria
-------------
  - Any phase exits non-zero
  - Any service not active
  - Cloudflare verification fails
  - Rotate fails or Cloudflare sync fails
  - Summary shows misleading status

Data to Report Back
-------------------
  - Which phases passed/failed
  - Error messages from failures
  - nanobk --json status output (redact tokens)
  - healthcheck output
  - Do NOT paste real tokens or subscription URLs
PLAN
}

# ── Main menu ───────────────────────────────────────────────────────────────

show_menu() {
  echo ""
  echo -e "${BOLD}NanoBK Proxy Suite${NC} v${VERSION}"
  echo ""
  echo "  请选择安装模式："
  echo ""
  echo "    1) Full Recommended — VPS + Cloudflare + Bot + Web Panel"
  echo "    2) CLI only — 只部署 VPS + nanobk CLI"
  echo "    3) CLI + Bot — VPS + Telegram Bot"
  echo "    4) CLI + Web — VPS + Web Panel"
  echo "    5) CLI + Bot + Web — VPS + Telegram Bot + Web Panel"
  echo "    6) Cloudflare only — 只部署 nanok/nanob"
  echo "    7) Bot only — 配置 Telegram Bot"
  echo "    8) Web Panel only — 配置 Web Panel"
  echo "    9) Doctor / Diagnose — 检查当前环境"
  echo "   10) Commands only — 只输出命令，不执行"
  echo "    0) 退出"
  echo ""
}

handle_menu_choice() {
  local choice="$1"

  case "$choice" in
    1)  run_full_wizard ;;
    2)  run_cli_only_mode ;;
    3)  run_cli_bot_mode ;;
    4)  run_cli_web_mode ;;
    5)  run_cli_bot_web_mode ;;
    6)  run_cloudflare_mode ;;
    7)  run_bot_mode ;;
    8)  run_web_mode ;;
    9)  run_doctor_mode ;;
    10) run_commands_mode ;;
    0)  echo "  再见！"; exit 0 ;;
    *)  err "无效选择: ${choice}"; return 1 ;;
  esac
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  parse_args "$@"

  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║           NanoBK Proxy Suite Installer v${VERSION}          ║"
  echo "║                                                          ║"
  echo "║  VPS 四协议 + Cloudflare 订阅 + Bot + Web Panel         ║"
  echo "╚══════════════════════════════════════════════════════════╝"

  check_repo

  # validate-plan can run without full environment detection
  if [[ "$MODE" == "validate-plan" ]]; then
    run_validate_plan
    return
  fi

  # Non-interactive modes should not hang on language selection
  if [[ -n "$MODE" ]] && [[ "$LANG_EXPLICIT" != "1" ]]; then
    case "$MODE" in
      commands|test|doctor)
        LANG_CODE="${LANG_CODE:-zh}"
        ;;
    esac
  fi

  select_language
  detect_environment

  # If --mode specified, run directly
  if [[ -n "$MODE" ]]; then
    case "$MODE" in
      full)          run_full_wizard ;;
      cli-only)      run_cli_only_mode ;;
      cli-bot)       run_cli_bot_mode ;;
      cli-web)       run_cli_web_mode ;;
      cli-bot-web)   run_cli_bot_web_mode ;;
      vps)           run_vps_mode ;;
      cloudflare)    run_cloudflare_mode ;;
      bot)           run_bot_mode ;;
      web)           run_web_mode ;;
      rotate)        run_rotate_mode ;;
      doctor)        run_doctor_mode ;;
      test)          run_test_mode ;;
      commands)      run_commands_mode ;;
      validate-plan) run_validate_plan ;;
      *)             err "未知模式: ${MODE}"; show_help; exit 1 ;;
    esac
    save_config
    return
  fi

  # Interactive menu
  while true; do
    show_menu
    echo -en "${BOLD}  请输入选项 [0-9]:${NC} "
    read -r choice
    handle_menu_choice "$choice" || true
    echo ""
  done
}

main "$@"
