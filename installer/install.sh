#!/usr/bin/env bash
# NanoBK Proxy Suite — Main Installer v0.5.1
#
# Interactive entry point for NanoBK Proxy Suite.
# Guides users through VPS deployment, Cloudflare setup, key rotation, and testing.
#
# Usage:
#   bash installer/install.sh
#   bash installer/install.sh --mode doctor
#   bash installer/install.sh --mode vps --dry-run
#   bash installer/install.sh --mode commands

set -Eeuo pipefail

# ── Resolve script directory ───────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Constants ───────────────────────────────────────────────────────────────

REPO_URL="https://github.com/kairkiss/NanoBK-Proxy-Suite"
VERSION="1.0.3"

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
LANG_CODE="zh"
MODE=""
COMMAND_ONLY=0
REPO_DIR_OVERRIDE=""

# Environment state (set by detect_environment)
ENV_IS_LINUX=0
ENV_HAS_SYSTEMD=0
ENV_HAS_ROOT=0

# ── Helpers ─────────────────────────────────────────────────────────────────

log()   { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

# Safe command printing with proper quoting
print_cmd() {
  local cmd=("$@")
  printf "  ${CYAN}\$${NC} "
  printf "%q " "${cmd[@]}"
  printf "\n"
}

# Safe command execution
run_cmd() {
  local desc="$1"
  shift
  local cmd=("$@")

  echo ""
  log "$desc"
  print_cmd "${cmd[@]}"

  if [[ "$COMMAND_ONLY" == "1" ]]; then
    echo -e "  ${YELLOW}(仅生成命令，未执行)${NC}"
    return 0
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} 跳过执行"
    return 0
  fi

  if [[ "$YES" != "1" ]]; then
    echo -en "${YELLOW}  是否现在执行？[y/N]${NC} "
    read -r reply
    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
      echo -e "  ${YELLOW}已跳过。你可以手动复制上面的命令执行。${NC}"
      return 0
    fi
  fi

  "${cmd[@]}"
}

# Prompt for input with default
prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default="${3:-}"

  if [[ "$YES" == "1" ]] && [[ -n "$default" ]]; then
    eval "$var_name=\"\$default\""
    return
  fi

  if [[ -n "$default" ]]; then
    echo -en "${BOLD}${prompt_text}${NC} [${default}]: "
  else
    echo -en "${BOLD}${prompt_text}${NC}: "
  fi
  read -r input

  if [[ -z "$input" ]] && [[ -n "$default" ]]; then
    eval "$var_name=\"\$default\""
  else
    eval "$var_name=\"\$input\""
  fi
}

# Yes/No prompt
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

# Run a single test script safely (no eval)
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

  "${cmd[@]}" || warn "测试失败: ${label}"
}

# Check if mode is destructive (requires real system/CF changes)
is_destructive_mode() {
  local mode="$1"
  case "$mode" in
    vps|cloudflare|nanob|rotate|full) return 0 ;;
    *) return 1 ;;
  esac
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

  # Check tools
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

# ── Argument parsing ────────────────────────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)    DRY_RUN=1 ;;
      --yes)        YES=1 ;;
      --lang)       LANG_CODE="$2"; shift ;;
      --mode)       MODE="$2"; shift ;;
      --repo-dir)   REPO_DIR_OVERRIDE="$2"; shift ;;
      --help|-h)    show_help; exit 0 ;;
      *)            err "未知参数: $1"; show_help; exit 1 ;;
    esac
    shift
  done

  # Handle --repo-dir override
  if [[ -n "$REPO_DIR_OVERRIDE" ]]; then
    if [[ ! -d "$REPO_DIR_OVERRIDE" ]]; then
      die "指定的仓库目录不存在: ${REPO_DIR_OVERRIDE}"
    fi
    REPO_DIR="$(cd "$REPO_DIR_OVERRIDE" && pwd)"
  fi

  # Handle --lang en (reserved)
  if [[ "$LANG_CODE" == "en" ]]; then
    warn "English UI is reserved and incomplete; falling back to Chinese for now."
    LANG_CODE="zh"
  fi

  # Safety: --yes without --dry-run on destructive modes
  if [[ "$YES" == "1" ]] && [[ "$DRY_RUN" != "1" ]] && [[ -n "$MODE" ]]; then
    if is_destructive_mode "$MODE"; then
      err "为避免使用 example.com 默认值执行真实部署，install.sh 不支持 --yes 直接运行 ${MODE}。"
      echo ""
      echo "  请去掉 --yes 使用交互式输入，或使用具体子安装器并显式提供完整参数："
      echo ""
      echo "    bash installer/install-vps.sh --yes --domain your-domain.com ..."
      echo "    bash installer/install-cloudflare.sh --yes --route-url https://your-worker ..."
      echo ""
      echo "  或使用 --dry-run 预览："
      echo "    bash installer/install.sh --mode ${MODE} --yes --dry-run"
      echo ""
      exit 1
    fi
  fi
}

show_help() {
  cat <<EOF
NanoBK Proxy Suite — 交互式安装器 v${VERSION}

用法:
  bash installer/install.sh [选项]

选项:
  --dry-run          只打印命令，不执行
  --yes              非交互模式（仅限 doctor/test/commands 模式）
  --lang zh|en       语言（当前主要支持 zh，en 为预留）
  --mode MODE        直接指定模式，跳过菜单
  --repo-dir PATH    指定仓库根目录
  --help             显示帮助

模式（--mode）:
  vps                部署 VPS 四协议节点
  cloudflare         部署 Cloudflare nanok 主订阅
  full               完整链路向导（VPS + Cloudflare）
  nanob              部署 nanob 聚合器
  rotate             一键换密钥
  doctor             运行环境诊断
  test               运行本地安全测试
  commands           只生成命令模板，不执行

示例:
  bash installer/install.sh
  bash installer/install.sh --mode doctor
  bash installer/install.sh --mode vps --dry-run
  bash installer/install.sh --mode commands
  bash installer/install.sh --repo-dir /path/to/NanoBK-Proxy-Suite --mode doctor
EOF
}

# ── VPS parameter collection ────────────────────────────────────────────────

collect_vps_args() {
  echo ""
  echo -e "${BOLD}── VPS 四协议部署参数 ──${NC}"
  echo ""

  local domain cert_mode cert_file key_file reality_sname

  prompt domain "请输入节点域名" "proxy.example.com"
  prompt cert_mode "证书模式 (existing/self-signed)" "existing"

  if [[ "$cert_mode" == "existing" ]]; then
    prompt cert_file "证书 fullchain 路径" "/etc/letsencrypt/live/${domain}/fullchain.pem"
    prompt key_file "证书 privkey 路径" "/etc/letsencrypt/live/${domain}/privkey.pem"
  elif [[ "$cert_mode" == "self-signed" ]]; then
    warn "自签证书只建议测试，有些客户端可能拒绝。生产建议使用真实证书。"
    cert_file=""
    key_file=""
  else
    err "无效的证书模式: ${cert_mode}"
    return 1
  fi

  prompt reality_sname "Reality 伪装域名" "www.microsoft.com"

  echo ""
  log "将执行以下命令："
  echo ""

  local cmd=(bash "$REPO_DIR/installer/install-vps.sh" --yes
    --domain "$domain"
    --cert-mode "$cert_mode"
    --reality-servername "$reality_sname")

  [[ "$cert_mode" == "existing" ]] && cmd+=(--cert-file "$cert_file" --key-file "$key_file")
  [[ "$DRY_RUN" == "1" ]] && cmd+=(--dry-run)

  print_cmd "${cmd[@]}"
  echo ""
  echo "  ${YELLOW}提示：此命令需要在 Linux VPS 上以 root 运行。${NC}"

  run_cmd "部署 VPS 四协议" "${cmd[@]}"
}

# ── Cloudflare nanok parameter collection ───────────────────────────────────

collect_cloudflare_nanok_args() {
  echo ""
  echo -e "${BOLD}── Cloudflare nanok 部署参数 ──${NC}"
  echo ""

  local profile route_url kv_choice kv_id skip_upload skip_verify

  prompt profile "profile.current.json 路径" "/etc/nanobk/profile.current.json"
  prompt route_url "nanok Worker URL" "https://nanok.example.workers.dev"

  echo ""
  echo "  KV namespace 选择："
  echo "    1) 自动创建 KV"
  echo "    2) 使用已有 KV namespace ID"
  prompt kv_choice "请选择" "1"

  local kv_args=()
  if [[ "$kv_choice" == "2" ]]; then
    prompt kv_id "KV namespace ID"
    kv_args+=(--kv-namespace-id "$kv_id")
  else
    kv_args+=(--create-kv)
  fi

  if confirm "跳过 profile 上传？" "n"; then
    skip_upload=1
  else
    skip_upload=0
  fi

  if confirm "跳过验证？" "n"; then
    skip_verify=1
  else
    skip_verify=0
  fi

  echo ""
  log "将执行以下命令："
  echo ""

  local cmd=(bash "$REPO_DIR/installer/install-cloudflare.sh" --yes
    "${kv_args[@]}"
    --profile "$profile"
    --route-url "$route_url")

  [[ "$skip_upload" == "1" ]] && cmd+=(--skip-profile-upload)
  [[ "$skip_verify" == "1" ]] && cmd+=(--skip-verify)
  [[ "$DRY_RUN" == "1" ]] && cmd+=(--dry-run)

  print_cmd "${cmd[@]}"

  CF_CMD=("${cmd[@]}")
  CF_ROUTE_URL="$route_url"
  CF_PROFILE="$profile"
}

# ── Cloudflare nanob parameter collection ───────────────────────────────────

collect_cloudflare_nanob_args() {
  collect_cloudflare_nanok_args

  echo ""
  echo -e "${BOLD}── nanob 聚合器参数 ──${NC}"
  echo ""

  local nanob_url geo_choice geo_id edge_host edge_token

  prompt nanob_url "nanob Worker URL" "https://nanob.example.workers.dev"

  echo ""
  echo "  Geo KV namespace 选择："
  echo "    1) 自动创建"
  echo "    2) 使用已有 Geo KV ID"
  prompt geo_choice "请选择" "1"

  local geo_args=()
  if [[ "$geo_choice" == "2" ]]; then
    prompt geo_id "Geo KV namespace ID"
    geo_args+=(--nanob-geo-kv-namespace-id "$geo_id")
  else
    geo_args+=(--create-nanob-geo-kv)
  fi

  local edge_args=()
  if confirm "是否配置 edgetunnel backup？" "n"; then
    prompt edge_host "edgetunnel host" "edge-subscription.example.com"
    edge_args+=(--edge-host "$edge_host")

    if confirm "是否有 edgetunnel internal auth token？" "n"; then
      prompt edge_token "edgetunnel export token"
      edge_args+=(--edgetunnel-export-token "$edge_token")
    fi
  fi

  echo ""
  log "将执行以下命令："
  echo ""

  local cmd=("${CF_CMD[@]}")
  cmd+=(--deploy-nanob
    --nanob-route-url "$nanob_url"
    "${geo_args[@]}"
    "${edge_args[@]}")

  print_cmd "${cmd[@]}"

  CF_CMD=("${cmd[@]}")
  CF_NANOB_URL="$nanob_url"
}

# ── Rotate parameter collection ─────────────────────────────────────────────

collect_rotate_args() {
  echo ""
  echo -e "${BOLD}── 一键换密钥参数 ──${NC}"
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

  echo ""
  log "将执行以下命令："
  echo ""

  local cmd=(sudo bash "$REPO_DIR/vps/scripts/rotate-keys.sh" --yes
    --config-dir "$config_dir"
    --cf-admin-env "$cf_admin_env")

  [[ "$skip_cf" == "1" ]] && cmd+=(--skip-cloudflare)
  [[ "$skip_svc" == "1" ]] && cmd+=(--skip-services)
  [[ "$DRY_RUN" == "1" ]] && cmd+=(--dry-run)

  print_cmd "${cmd[@]}"
  echo ""
  echo "  ${YELLOW}提示：此命令需要在 VPS 上以 root 运行。${NC}"

  run_cmd "一键换密钥" "${cmd[@]}"
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

run_cloudflare_mode() {
  collect_cloudflare_nanok_args
}

run_full_wizard() {
  echo ""
  echo -e "${BOLD}═══ 完整链路部署向导 ═══${NC}"
  echo ""
  echo "  完整链路包含以下步骤："
  echo "    1. VPS 部署四协议节点"
  echo "    2. Cloudflare 部署 nanok 主订阅"
  echo "    3. （可选）部署 nanob 聚合器"
  echo "    4. 导入订阅到客户端"
  echo ""
  echo "  ${YELLOW}每一步都可以单独执行，不会一次性全部自动跑。${NC}"
  echo ""

  # Phase 1: VPS
  echo -e "${BOLD}── 阶段 1：VPS 部署 ──${NC}"
  echo ""
  echo "  此步骤需要在 Linux VPS 上运行。"
  echo "  如果你当前不在 VPS 上，可以选择只生成命令。"
  echo ""

  if confirm "是否现在配置 VPS 部署参数？" "y"; then
    collect_vps_args
  else
    echo ""
    echo "  跳过 VPS 部署。你可以稍后运行："
    echo "    bash installer/install.sh --mode vps"
  fi

  # Phase 2: Cloudflare
  echo ""
  echo -e "${BOLD}── 阶段 2：Cloudflare 部署 ──${NC}"
  echo ""
  echo "  此步骤可以在 Mac 或 Linux 上运行。"
  echo "  需要先安装 wrangler 并登录：npm install -g wrangler && wrangler login"
  echo ""

  if confirm "是否现在配置 Cloudflare 部署参数？" "y"; then
    collect_cloudflare_nanok_args
  else
    echo ""
    echo "  跳过 Cloudflare 部署。你可以稍后运行："
    echo "    bash installer/install.sh --mode cloudflare"
  fi

  # Phase 3: Client import
  echo ""
  echo -e "${BOLD}── 阶段 3：客户端导入 ──${NC}"
  echo ""
  echo "  部署完成后，将以下订阅 URL 导入 Clash/Mihomo："
  echo ""
  if [[ -n "${CF_NANOB_URL:-}" ]]; then
    echo "    推荐（nanob 聚合）：${CF_NANOB_URL}/jb?token=<NANOB_TOKEN>"
    echo "    直接（nanok 主订阅）：${CF_ROUTE_URL:-<nanok-url>}/jb?token=<SUB_TOKEN>"
  elif [[ -n "${CF_ROUTE_URL:-}" ]]; then
    echo "    ${CF_ROUTE_URL}/jb?token=<SUB_TOKEN>"
  else
    echo "    https://<your-worker-url>/jb?token=<your-token>"
  fi

  # Phase 4: Key rotation
  echo ""
  echo -e "${BOLD}── 阶段 4：换密钥 ──${NC}"
  echo ""
  echo "  以后需要换密钥时，运行："
  echo "    bash installer/install.sh --mode rotate"
  echo "  或直接："
  echo "    sudo bash vps/scripts/rotate-keys.sh --yes"
  echo ""
  echo -e "${GREEN}  向导完成！${NC}"
}

run_nanob_mode() {
  collect_cloudflare_nanob_args
}

run_rotate_mode() {
  collect_rotate_args
}

run_doctor_mode() {
  run_cmd "运行环境诊断" bash "$REPO_DIR/installer/doctor.sh"
}

run_test_mode() {
  echo ""
  echo -e "${BOLD}── 本地安全测试 ──${NC}"
  echo ""
  echo "  1) VPS render-only 测试"
  echo "  2) rotate 离线测试"
  echo "  3) nanok wrangler bundle 测试"
  echo "  4) nanob wrangler bundle 测试"
  echo "  5) 全部测试"
  echo ""

  local choice
  prompt choice "请选择" "5"

  case "$choice" in
    1) run_one_test "$REPO_DIR/tests/render-install-vps.sh" "VPS render-only 测试" ;;
    2) run_one_test "$REPO_DIR/tests/rotate-render-only.sh" "rotate 离线测试" ;;
    3) run_one_test "$REPO_DIR/tests/wrangler-nanok-dry-run.sh" "nanok wrangler bundle 测试" ;;
    4) run_one_test "$REPO_DIR/tests/wrangler-nanob-dry-run.sh" "nanob wrangler bundle 测试" ;;
    5)
      run_one_test "$REPO_DIR/tests/render-install-vps.sh" "VPS render-only 测试"
      run_one_test "$REPO_DIR/tests/rotate-render-only.sh" "rotate 离线测试"
      run_one_test "$REPO_DIR/tests/wrangler-nanok-dry-run.sh" "nanok wrangler bundle 测试"
      run_one_test "$REPO_DIR/tests/wrangler-nanob-dry-run.sh" "nanob wrangler bundle 测试"
      ;;
    *) err "无效选择"; return 1 ;;
  esac
}

run_commands_mode() {
  echo ""
  echo -e "${BOLD}═══ 命令模板（可复制） ═══${NC}"
  echo ""

  echo -e "${BOLD}── VPS 部署 ──${NC}"
  echo ""
  echo "  sudo bash installer/install-vps.sh --yes \\"
  echo "    --domain proxy.example.com \\"
  echo "    --cert-mode existing \\"
  echo "    --cert-file /etc/letsencrypt/live/proxy.example.com/fullchain.pem \\"
  echo "    --key-file /etc/letsencrypt/live/proxy.example.com/privkey.pem"
  echo ""

  echo -e "${BOLD}── Cloudflare nanok ──${NC}"
  echo ""
  echo "  bash installer/install-cloudflare.sh --yes \\"
  echo "    --create-kv \\"
  echo "    --profile /etc/nanobk/profile.current.json \\"
  echo "    --route-url https://nanok.example.workers.dev"
  echo ""

  echo -e "${BOLD}── Cloudflare nanok + nanob ──${NC}"
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

  echo -e "${BOLD}── 诊断和测试 ──${NC}"
  echo ""
  echo "  bash installer/doctor.sh"
  echo "  bash tests/render-install-vps.sh"
  echo "  bash tests/rotate-render-only.sh"
  echo "  bash tests/wrangler-nanok-dry-run.sh"
  echo "  bash tests/wrangler-nanob-dry-run.sh"
  echo ""
}

# ── Main menu ───────────────────────────────────────────────────────────────

show_menu() {
  echo ""
  echo -e "${BOLD}NanoBK Proxy Suite${NC} v${VERSION}"
  echo ""
  echo "  请选择要做什么："
  echo ""
  echo "    1) VPS 一键部署四协议节点"
  echo "    2) Cloudflare 部署 nanok 主订阅"
  echo "    3) Cloudflare 部署 nanok + nanob 聚合订阅"
  echo "    4) 完整链路提示向导（VPS → Cloudflare → 导入客户端）"
  echo "    5) 一键换密钥并同步订阅"
  echo "    6) 运行环境诊断 doctor"
  echo "    7) 运行本地安全测试"
  echo "    8) 只生成命令，不执行"
  echo "    9) 退出"
  echo ""
}

handle_menu_choice() {
  local choice="$1"

  case "$choice" in
    1) run_vps_mode ;;
    2) run_cloudflare_mode ;;
    3) run_nanob_mode ;;
    4) run_full_wizard ;;
    5) run_rotate_mode ;;
    6) run_doctor_mode ;;
    7) run_test_mode ;;
    8) run_commands_mode ;;
    9) echo "  再见！"; exit 0 ;;
    *) err "无效选择: ${choice}"; return 1 ;;
  esac
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  parse_args "$@"

  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║           NanoBK Proxy Suite Installer v${VERSION}          ║"
  echo "║                                                          ║"
  echo "║  VPS 四协议 + Cloudflare 订阅 + 自动换密钥              ║"
  echo "╚══════════════════════════════════════════════════════════╝"

  check_repo
  detect_environment

  # If --mode specified, run directly
  if [[ -n "$MODE" ]]; then
    case "$MODE" in
      vps)         run_vps_mode ;;
      cloudflare)  run_cloudflare_mode ;;
      full)        run_full_wizard ;;
      nanob)       run_nanob_mode ;;
      rotate)      run_rotate_mode ;;
      doctor)      run_doctor_mode ;;
      test)        run_test_mode ;;
      commands)    run_commands_mode ;;
      *)           err "未知模式: ${MODE}"; show_help; exit 1 ;;
    esac
    return
  fi

  # Interactive menu
  while true; do
    show_menu
    echo -en "${BOLD}  请输入选项 [1-9]:${NC} "
    read -r choice
    handle_menu_choice "$choice" || true
    echo ""
  done
}

main "$@"
