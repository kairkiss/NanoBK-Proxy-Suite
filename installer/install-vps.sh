#!/usr/bin/env bash
# NanoBK Proxy Suite — VPS Installer
#
# Installs and configures the four proxy services on a Linux VPS:
#   - Hysteria2 (HY2) on UDP :443
#   - TUIC v5 on UDP :9443
#   - VLESS + Reality (Xray) on TCP :8443
#   - Trojan TLS (Xray) on TCP :2443
#
# Usage:
#   sudo bash installer/install-vps.sh
#
# Status: v0.1 scaffold — lists steps but does not yet execute them.

set -Eeuo pipefail

NANOBK_HOME="/etc/nanobk"
CONFIG_ENV="${NANOBK_HOME}/config.env"

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

# ── Pre-flight Checks ──────────────────────────────────────────────────────

check_root() {
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root."
    err "Usage: sudo bash $0"
    exit 1
  fi
  ok "Running as root"
}

check_os() {
  if [[ ! -f /etc/os-release ]]; then
    err "Cannot detect OS. /etc/os-release not found."
    exit 1
  fi
  # shellcheck source=/dev/null
  source /etc/os-release
  info "OS: ${PRETTY_NAME:-$ID $VERSION_ID}"
}

# ── Installation Steps (TODO: implement each step) ─────────────────────────

step_install_dependencies() {
  info "Step 1/8: Install system dependencies"
  echo "  TODO: apt-get install -y curl jq python3 openssl uuid-runtime"
  echo "  TODO: Install Xray-core"
  echo "  TODO: Install Hysteria2"
  echo "  TODO: Install tuic-server"
  echo ""
}

step_generate_keys() {
  info "Step 2/8: Generate initial credentials"
  echo "  TODO: Generate HY2 password (openssl rand -base64 24)"
  echo "  TODO: Generate TUIC UUID (uuidgen) + password (openssl rand -hex 32)"
  echo "  TODO: Generate Reality keypair (xray x25519) + UUID + shortId"
  echo "  TODO: Generate Trojan password (openssl rand -base64 24)"
  echo ""
}

step_write_configs() {
  info "Step 3/8: Write service configuration files"
  echo "  TODO: Write HY2 config to /etc/hysteria/config.yaml"
  echo "  TODO: Write TUIC config to /etc/proxy-stack/tuic-v5-9443/config.json"
  echo "  TODO: Write Xray Reality config to /etc/proxy-stack/xray-reality-8443/config.json"
  echo "  TODO: Write Xray Trojan config to /etc/proxy-stack/xray-trojan-2443/config.json"
  echo ""
}

step_create_systemd_services() {
  info "Step 4/8: Create systemd service units"
  echo "  TODO: Create hysteria-server.service"
  echo "  TODO: Create tuic-v5-9443.service"
  echo "  TODO: Create xray-reality-8443.service"
  echo "  TODO: Create xray-trojan-2443.service"
  echo "  TODO: systemctl daemon-reload"
  echo ""
}

step_start_services() {
  info "Step 5/8: Start and enable services"
  echo "  TODO: systemctl enable --now hysteria-server.service"
  echo "  TODO: systemctl enable --now tuic-v5-9443.service"
  echo "  TODO: systemctl enable --now xray-reality-8443.service"
  echo "  TODO: systemctl enable --now xray-trojan-2443.service"
  echo ""
}

step_verify_ports() {
  info "Step 6/8: Verify ports are listening"
  echo "  TODO: Check UDP :443 (HY2)"
  echo "  TODO: Check UDP :9443 (TUIC)"
  echo "  TODO: Check TCP :8443 (Reality)"
  echo "  TODO: Check TCP :2443 (Trojan)"
  echo ""
}

step_write_config_env() {
  info "Step 7/8: Write local config environment file"
  echo "  TODO: Create ${NANOBK_HOME}/"
  echo "  TODO: Write config.env with domain, IP, service paths"
  echo "  TODO: chmod 600 config.env"
  echo ""
}

step_generate_cf_profile() {
  info "Step 8/8: Generate Cloudflare Worker profile JSON"
  echo "  TODO: Build profile.example.json with generated credentials"
  echo "  TODO: Output instructions for Cloudflare Worker setup"
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║           NanoBK Proxy Suite — VPS Installer            ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  check_root
  check_os
  echo ""

  warn "v0.1 scaffold: This script shows the planned steps but does not"
  warn "execute them yet. Each step will be implemented in v0.2."
  echo ""

  step_install_dependencies
  step_generate_keys
  step_write_configs
  step_create_systemd_services
  step_start_services
  step_verify_ports
  step_write_config_env
  step_generate_cf_profile

  info "Setup complete (when implemented)."
  echo ""
  info "Next steps:"
  echo "  1. Set up Cloudflare Workers: bash installer/install-cloudflare.sh"
  echo "  2. Configure CF admin token: see examples/env.cloudflare.example"
  echo "  3. Test subscription: curl https://YOUR_WORKER/jb?token=YOUR_TOKEN"
  echo ""
}

main "$@"
