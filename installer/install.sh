#!/usr/bin/env bash
# NanoBK Proxy Suite — Main Installer
#
# This is the entry point for one-command installation.
# It detects the environment and delegates to install-vps.sh or install-cloudflare.sh.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/install.sh)
#
# Status: v0.1 scaffold — not yet fully automated.

set -Eeuo pipefail

REPO_URL="https://github.com/kairkiss/NanoBK-Proxy-Suite"
VERSION="0.1.0"

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── Banner ──────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           NanoBK Proxy Suite Installer v${VERSION}          ║"
echo "║                                                          ║"
echo "║  VPS 四协议 + Cloudflare 订阅 + 自动换密钥              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Environment Detection ──────────────────────────────────────────────────

detect_environment() {
  info "Detecting environment..."

  # Check OS
  if [[ "$(uname -s)" != "Linux" ]]; then
    err "This installer is designed for Linux VPS."
    err "Detected OS: $(uname -s)"
    exit 1
  fi
  ok "OS: $(uname -s) $(uname -m)"

  # Check if running on a VPS (has systemd)
  if ! command -v systemctl &>/dev/null; then
    warn "systemctl not found. VPS proxy services require systemd."
  fi

  echo ""
  info "What would you like to install?"
  echo ""
  echo "  1) VPS proxy services (HY2, TUIC, Reality, Trojan)"
  echo "  2) Cloudflare Workers (nanok, nanob)"
  echo "  3) Both (full setup)"
  echo "  4) Run environment check only (doctor)"
  echo ""
  # TODO: Add interactive selection
  warn "Interactive installer not yet implemented in v0.1."
  warn "Please run the specific installer directly:"
  echo ""
  echo "  VPS setup:        bash installer/install-vps.sh"
  echo "  Cloudflare setup: bash installer/install-cloudflare.sh"
  echo "  Doctor check:     bash installer/doctor.sh"
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  detect_environment
}

main "$@"
