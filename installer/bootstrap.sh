#!/usr/bin/env bash
# NanoBK Proxy Suite — Remote Bootstrap Installer
#
# Downloads (or updates) the NanoBK repository and launches the interactive installer.
# Does NOT directly deploy VPS services, modify Cloudflare, or rotate keys.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/bootstrap.sh)
#   bash installer/bootstrap.sh
#   bash installer/bootstrap.sh -- --mode doctor
#   bash installer/bootstrap.sh --install-dir ~/NanoBK -- --mode commands

set -Eeuo pipefail

# ── Constants ───────────────────────────────────────────────────────────────

REPO_URL="https://github.com/kairkiss/NanoBK-Proxy-Suite.git"
BRANCH="main"
BOOTSTRAP_VERSION="1.8.31"

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

print_cmd() {
  printf "  ${CYAN}\$${NC} "
  printf "%q " "$@"
  printf "\n"
}

# ── Global flags ────────────────────────────────────────────────────────────

DRY_RUN=0
YES=0
INSTALL_DIR=""
INSTALL_ARGS=()
WOULD_CLONE=0

# ── Help ────────────────────────────────────────────────────────────────────

show_help() {
  cat <<'EOF'
NanoBK Proxy Suite — Remote Bootstrap Installer

Downloads (or updates) the NanoBK repository and launches the interactive installer.

Usage:
  bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/bootstrap.sh)
  bash installer/bootstrap.sh [OPTIONS] [-- INSTALL.SH_ARGS...]

Options:
  --dry-run             Print actions without executing
  --yes                 Non-interactive mode for clone/pull confirmation
  --install-dir PATH    Installation directory (default: /opt/NanoBK-Proxy-Suite or ~/NanoBK-Proxy-Suite)
  --branch BRANCH       Git branch (default: main)
  --repo-url URL        Repository URL
  --help                Show this help

Arguments after -- are passed to installer/install.sh:
  bash installer/bootstrap.sh -- --mode doctor
  bash installer/bootstrap.sh -- --mode commands
  bash installer/bootstrap.sh -- --mode vps --dry-run
EOF
}

# ── Argument parsing ────────────────────────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)      DRY_RUN=1 ;;
      --yes)          YES=1 ;;
      --install-dir)  INSTALL_DIR="$2"; shift ;;
      --branch)       BRANCH="$2"; shift ;;
      --repo-url)     REPO_URL="$2"; shift ;;
      --help|-h)      show_help; exit 0 ;;
      --)             shift; INSTALL_ARGS=("$@"); return ;;
      *)              die "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
  done
}

# ── URL normalization ───────────────────────────────────────────────────────

# Normalize a GitHub repo URL to a comparable form: "owner/repo" (lowercase).
# Handles: https://github.com/X/Y.git, git@github.com:X/Y.git, trailing slashes.
normalize_repo_url() {
  local url="$1"
  url="${url%.git}"
  url="${url%/}"
  url="${url#git@github.com:}"
  url="${url#https://github.com/}"
  url="${url#http://github.com/}"
  printf '%s' "$url" | tr '[:upper:]' '[:lower:]'
}

# ── Resolve install directory ───────────────────────────────────────────────

resolve_install_dir() {
  if [[ -n "$INSTALL_DIR" ]]; then
    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
    return
  fi

  if [[ $EUID -eq 0 ]]; then
    INSTALL_DIR="/opt/NanoBK-Proxy-Suite"
  else
    INSTALL_DIR="${HOME}/NanoBK-Proxy-Suite"
  fi
}

# ── Dependency check ────────────────────────────────────────────────────────

check_requirements() {
  log "检查依赖..."

  local missing=()
  for cmd in bash git curl; do
    if command -v "$cmd" &>/dev/null; then
      ok "${cmd}: $(command -v "$cmd")"
    else
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    err "缺少必需工具: ${missing[*]}"
    echo ""
    echo "  请先安装:"
    if [[ "$(uname -s)" == "Darwin" ]]; then
      echo "    macOS:  brew install ${missing[*]}"
      echo "    或:     xcode-select --install"
    elif [[ -f /etc/debian_version ]]; then
      echo "    Debian/Ubuntu:  sudo apt-get update && sudo apt-get install -y ${missing[*]}"
    elif [[ -f /etc/redhat-release ]] || [[ -f /etc/fedora-release ]]; then
      echo "    RHEL/Rocky/Fedora:  sudo dnf install -y ${missing[*]}"
    else
      echo "    请使用系统包管理器安装: ${missing[*]}"
    fi
    echo ""
    exit 1
  fi
}

# ── Directory handling ──────────────────────────────────────────────────────

handle_directory() {
  if [[ ! -d "$INSTALL_DIR" ]]; then
    # Case A: Directory does not exist — clone
    WOULD_CLONE=1
    log "安装目录不存在，将 clone 仓库:"
    print_cmd git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"

    if [[ "$DRY_RUN" == "1" ]]; then
      echo -e "  ${CYAN}[DRY-RUN]${NC} 跳过执行"
      return 0
    fi

    if [[ "$YES" != "1" ]]; then
      echo -en "${YELLOW}  是否 clone 到 ${INSTALL_DIR}？[Y/n]${NC} "
      read -r reply
      if [[ "$reply" =~ ^[Nn]$ ]]; then
        die "已取消。"
      fi
    fi

    git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
    ok "仓库已 clone 到 ${INSTALL_DIR}"
    return 0
  fi

  # Directory exists
  if [[ ! -d "$INSTALL_DIR/.git" ]]; then
    die "安装目录已存在，但不是 Git 仓库，不会覆盖。
  路径: ${INSTALL_DIR}
  请换一个 --install-dir，或手动移动该目录。"
  fi

  # Is a git repo — check remote
  local remote_url
  remote_url=$(git -C "$INSTALL_DIR" remote get-url origin 2>/dev/null || echo "")

  local normalized_remote normalized_repo
  normalized_remote=$(normalize_repo_url "$remote_url")
  normalized_repo=$(normalize_repo_url "$REPO_URL")

  if [[ "$normalized_remote" != "$normalized_repo" ]]; then
    die "安装目录是其他 Git 仓库，不会覆盖。
  路径: ${INSTALL_DIR}
  Remote: ${remote_url}
  期望: ${REPO_URL}"
  fi

  # Same repo — check for local changes
  if ! git -C "$INSTALL_DIR" diff --quiet 2>/dev/null || \
     ! git -C "$INSTALL_DIR" diff --cached --quiet 2>/dev/null; then
    die "检测到已有仓库存在本地修改，不会自动 pull。
  路径: ${INSTALL_DIR}
  请先手动处理:
    cd ${INSTALL_DIR}
    git status"
  fi

  # Pull latest
  log "检测到已有仓库，将更新:"
  print_cmd git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} 跳过执行"
    return 0
  fi

  if [[ "$YES" != "1" ]]; then
    echo -en "${YELLOW}  是否 pull 最新代码？[Y/n]${NC} "
    read -r reply
    if [[ "$reply" =~ ^[Nn]$ ]]; then
      warn "跳过 pull，使用现有代码。"
      return 0
    fi
  fi

  git -C "$INSTALL_DIR" fetch origin "$BRANCH"
  git -C "$INSTALL_DIR" checkout "$BRANCH"
  git -C "$INSTALL_DIR" pull --ff-only origin "$BRANCH"
  ok "仓库已更新到最新 ${BRANCH}"
}

# ── Launch installer ────────────────────────────────────────────────────────

launch_installer() {
  local installer_path="${INSTALL_DIR}/installer/install.sh"

  if [[ "$DRY_RUN" == "1" ]]; then
    local cmd=(bash "$installer_path" --repo-dir "$INSTALL_DIR")
    [[ ${#INSTALL_ARGS[@]} -gt 0 ]] && cmd+=("${INSTALL_ARGS[@]}")

    if [[ "$WOULD_CLONE" == "1" ]]; then
      echo ""
      echo -e "  ${CYAN}[DRY-RUN]${NC} 仓库尚未实际 clone。"
      echo -e "  ${CYAN}[DRY-RUN]${NC} 下面的命令表示 clone 成功后将启动的安装器："
    else
      log "启动 NanoBK 交互式安装器:"
    fi

    print_cmd "${cmd[@]}"
    echo -e "  ${CYAN}[DRY-RUN]${NC} 跳过执行"
    return 0
  fi

  if [[ ! -f "$installer_path" ]]; then
    die "install.sh 未找到: ${installer_path}"
  fi

  local cmd=(bash "$installer_path" --repo-dir "$INSTALL_DIR")
  [[ ${#INSTALL_ARGS[@]} -gt 0 ]] && cmd+=("${INSTALL_ARGS[@]}")

  echo ""
  log "启动 NanoBK 交互式安装器:"
  print_cmd "${cmd[@]}"
  echo ""

  exec "${cmd[@]}"
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  parse_args "$@"

  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║           NanoBK Proxy Suite — Bootstrap                ║"
  echo "║                                                          ║"
  echo "║  获取仓库并启动交互式安装器                              ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  check_requirements
  resolve_install_dir

  log "安装目录: ${INSTALL_DIR}"
  log "分支: ${BRANCH}"

  handle_directory
  launch_installer
}

main "$@"
