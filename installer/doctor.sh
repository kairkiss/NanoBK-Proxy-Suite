#!/usr/bin/env bash
# NanoBK Proxy Suite — Environment Doctor
#
# Read-only diagnostic check for VPS environment.
# Does NOT modify any files or services.
#
# Usage:
#   bash installer/doctor.sh

set -Eeuo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

pass()  { echo -e "  ${GREEN}✓${NC} $*"; }
fail()  { echo -e "  ${RED}✗${NC} $*"; }
warn()  { echo -e "  ${YELLOW}!${NC} $*"; }
info()  { echo -e "  ${BLUE}i${NC} $*"; }
header() { echo -e "\n${BLUE}── $* ──${NC}"; }

# ── Counters (global) ──────────────────────────────────────────────────────

ERRORS=0
WARNINGS=0

# ── Functions ───────────────────────────────────────────────────────────────

check_file_perms() {
  local file="$1"
  local perms
  perms=$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || echo "unknown")
  if [[ "$perms" == "600" ]]; then
    pass "Config env permissions: ${perms} (secure)"
  elif [[ "$perms" == "unknown" ]]; then
    warn "Cannot check config env permissions"
  else
    warn "Config env permissions: ${perms} (recommend 600)"
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_port() {
  local port="$1"
  local proto="$2"
  local name="$3"

  if ! command -v ss &>/dev/null; then
    warn "ss not available, cannot check port ${port}"
    return
  fi

  if [[ "$proto" == "udp" ]]; then
    if ss -ulnp 2>/dev/null | grep -q ":${port} "; then
      pass "${name} :${port} (${proto}): listening"
    else
      fail "${name} :${port} (${proto}): NOT listening"
      ERRORS=$((ERRORS + 1))
    fi
  else
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      pass "${name} :${port} (${proto}): listening"
    else
      fail "${name} :${port} (${proto}): NOT listening"
      ERRORS=$((ERRORS + 1))
    fi
  fi
}

check_system_info() {
  header "System Info"

  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    pass "OS: ${PRETTY_NAME:-$ID $VERSION_ID}"
  else
    fail "Cannot detect OS (/etc/os-release missing)"
    ERRORS=$((ERRORS + 1))
  fi

  pass "Kernel: $(uname -r)"
  pass "Arch: $(uname -m)"

  if [[ $EUID -eq 0 ]]; then
    pass "Running as root"
  else
    warn "Not running as root (some checks may need sudo)"
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_required_tools() {
  header "Required Tools"

  local required_cmds=("curl" "jq" "python3" "openssl" "systemctl" "ss")
  local optional_cmds=("uuidgen" "xray" "hysteria" "tuic-server")

  for cmd in "${required_cmds[@]}"; do
    if command -v "$cmd" &>/dev/null; then
      pass "$cmd: $(command -v "$cmd")"
    else
      fail "$cmd: NOT FOUND"
      ERRORS=$((ERRORS + 1))
    fi
  done

  for cmd in "${optional_cmds[@]}"; do
    if command -v "$cmd" &>/dev/null; then
      pass "$cmd: $(command -v "$cmd")"
    else
      warn "$cmd: not found (may be needed for full functionality)"
      WARNINGS=$((WARNINGS + 1))
    fi
  done
}

check_nanobk_config() {
  header "NanoBK Configuration"

  local nanobk_home="/etc/nanobk"
  local config_env="${nanobk_home}/config.env"

  if [[ -d "$nanobk_home" ]]; then
    pass "Config directory: ${nanobk_home}"
  else
    warn "Config directory not found: ${nanobk_home}"
    WARNINGS=$((WARNINGS + 1))
  fi

  if [[ -f "$config_env" ]]; then
    pass "Config env: ${config_env}"
    check_file_perms "$config_env"
  else
    warn "Config env not found: ${config_env}"
    info "Create it during VPS setup: bash installer/install-vps.sh"
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_cloudflare_admin() {
  header "Cloudflare Admin Config"

  local cf_env="/root/.nanok-cf-admin.env"

  if [[ -f "$cf_env" ]]; then
    pass "CF admin env: ${cf_env}"
    # shellcheck source=/dev/null
    source "$cf_env" 2>/dev/null || true
    if [[ -n "${ADMIN_TOKEN:-}" ]]; then
      pass "ADMIN_TOKEN is set"
    else
      fail "ADMIN_TOKEN is not set in ${cf_env}"
      ERRORS=$((ERRORS + 1))
    fi
    if [[ -n "${ADMIN_UPDATE_URL:-}" ]]; then
      pass "ADMIN_UPDATE_URL is set"
    else
      fail "ADMIN_UPDATE_URL is not set"
      ERRORS=$((ERRORS + 1))
    fi
  else
    warn "CF admin env not found: ${cf_env}"
    info "Create it after Cloudflare setup: see examples/env.cloudflare.example"
    WARNINGS=$((WARNINGS + 1))
  fi
}

check_systemd_services() {
  header "Systemd Services"

  if ! command -v systemctl &>/dev/null; then
    warn "systemctl not available (not a systemd system?)"
    WARNINGS=$((WARNINGS + 1))
    return
  fi

  local services=(
    "hysteria-server.service"
    "tuic-v5-9443.service"
    "xray-reality-8443.service"
    "xray-trojan-2443.service"
  )

  for svc in "${services[@]}"; do
    if systemctl list-unit-files "$svc" &>/dev/null; then
      local svc_status
      svc_status=$(systemctl is-active "$svc" 2>/dev/null || true)
      if [[ "$svc_status" == "active" ]]; then
        pass "${svc}: active"
      else
        fail "${svc}: ${svc_status}"
        ERRORS=$((ERRORS + 1))
      fi
    else
      warn "${svc}: not installed"
      WARNINGS=$((WARNINGS + 1))
    fi
  done
}

check_ports() {
  header "Port Listening"

  check_port 443  "udp" "HY2"
  check_port 9443 "udp" "TUIC"
  check_port 8443 "tcp" "Reality"
  check_port 2443 "tcp" "Trojan"
}

check_config_files() {
  header "Config Files"

  local config_files=(
    "/etc/hysteria/config.yaml:HY2"
    "/etc/proxy-stack/tuic-v5-9443/config.json:TUIC"
    "/etc/proxy-stack/xray-reality-8443/config.json:Reality"
    "/etc/proxy-stack/xray-trojan-2443/config.json:Trojan"
  )

  for entry in "${config_files[@]}"; do
    local path="${entry%%:*}"
    local name="${entry##*:}"
    if [[ -f "$path" ]]; then
      pass "${name} config: ${path}"
    else
      warn "${name} config not found: ${path}"
      WARNINGS=$((WARNINGS + 1))
    fi
  done
}

print_summary() {
  header "Summary"

  echo ""
  if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "  ${GREEN}All checks passed!${NC}"
  elif [[ $ERRORS -eq 0 ]]; then
    echo -e "  ${YELLOW}${WARNINGS} warning(s), no errors.${NC}"
  else
    echo -e "  ${RED}${ERRORS} error(s), ${WARNINGS} warning(s).${NC}"
    echo ""
    echo "  Fix the errors above before proceeding."
  fi
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  check_system_info
  check_required_tools
  check_nanobk_config
  check_cloudflare_admin
  check_systemd_services
  check_ports
  check_config_files
  print_summary

  if [[ $ERRORS -gt 0 ]]; then
    return 1
  fi
  return 0
}

main "$@"
