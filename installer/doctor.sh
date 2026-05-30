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

ERRORS=0
WARNINGS=0

# ── System Info ─────────────────────────────────────────────────────────────

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

# ── Required Tools ──────────────────────────────────────────────────────────

header "Required Tools"

REQUIRED_CMDS=("curl" "jq" "python3" "openssl" "systemctl" "ss")
OPTIONAL_CMDS=("uuidgen" "xray" "hysteria" "tuic-server")

for cmd in "${REQUIRED_CMDS[@]}"; do
  if command -v "$cmd" &>/dev/null; then
    pass "$cmd: $(command -v "$cmd")"
  else
    fail "$cmd: NOT FOUND"
    ERRORS=$((ERRORS + 1))
  fi
done

for cmd in "${OPTIONAL_CMDS[@]}"; do
  if command -v "$cmd" &>/dev/null; then
    pass "$cmd: $(command -v "$cmd")"
  else
    warn "$cmd: not found (may be needed for full functionality)"
    WARNINGS=$((WARNINGS + 1))
  fi
done

# ── NanoBK Config ───────────────────────────────────────────────────────────

header "NanoBK Configuration"

NANOBK_HOME="/etc/nanobk"
CONFIG_ENV="${NANOBK_HOME}/config.env"

if [[ -d "$NANOBK_HOME" ]]; then
  pass "Config directory: ${NANOBK_HOME}"
else
  warn "Config directory not found: ${NANOBK_HOME}"
  WARNINGS=$((WARNINGS + 1))
fi

if [[ -f "$CONFIG_ENV" ]]; then
  pass "Config env: ${CONFIG_ENV}"
  # Check file permissions
  local_perms
else
  warn "Config env not found: ${CONFIG_ENV}"
  info "Create it during VPS setup: bash installer/install-vps.sh"
  WARNINGS=$((WARNINGS + 1))
fi

local_perms() {
  local perms
  perms=$(stat -c '%a' "$CONFIG_ENV" 2>/dev/null || stat -f '%Lp' "$CONFIG_ENV" 2>/dev/null || echo "unknown")
  if [[ "$perms" == "600" ]]; then
    pass "Config env permissions: ${perms} (secure)"
  elif [[ "$perms" == "unknown" ]]; then
    warn "Cannot check config env permissions"
  else
    warn "Config env permissions: ${perms} (recommend 600)"
    WARNINGS=$((WARNINGS + 1))
  fi
}

# ── Cloudflare Admin Token ──────────────────────────────────────────────────

header "Cloudflare Admin Config"

CF_ENV="/root/.nanok-cf-admin.env"

if [[ -f "$CF_ENV" ]]; then
  pass "CF admin env: ${CF_ENV}"
  # shellcheck source=/dev/null
  source "$CF_ENV" 2>/dev/null || true
  if [[ -n "${ADMIN_TOKEN:-}" ]]; then
    pass "ADMIN_TOKEN is set"
  else
    fail "ADMIN_TOKEN is not set in ${CF_ENV}"
    ERRORS=$((ERRORS + 1))
  fi
  if [[ -n "${ADMIN_UPDATE_URL:-}" ]]; then
    pass "ADMIN_UPDATE_URL is set"
  else
    fail "ADMIN_UPDATE_URL is not set"
    ERRORS=$((ERRORS + 1))
  fi
else
  warn "CF admin env not found: ${CF_ENV}"
  info "Create it after Cloudflare setup: see examples/env.cloudflare.example"
  WARNINGS=$((WARNINGS + 1))
fi

# ── Systemd Services ────────────────────────────────────────────────────────

header "Systemd Services"

SERVICES=(
  "hysteria-server.service"
  "tuic-v5-9443.service"
  "xray-reality-8443.service"
  "xray-trojan-2443.service"
)

for svc in "${SERVICES[@]}"; do
  if systemctl list-unit-files "$svc" &>/dev/null; then
    local status
    status=$(systemctl is-active "$svc" 2>/dev/null || true)
    if [[ "$status" == "active" ]]; then
      pass "${svc}: active"
    else
      fail "${svc}: ${status}"
      ERRORS=$((ERRORS + 1))
    fi
  else
    warn "${svc}: not installed"
    WARNINGS=$((WARNINGS + 1))
  fi
done

# ── Ports ────────────────────────────────────────────────────────────────────

header "Port Listening"

check_port() {
  local port="$1"
  local proto="$2"
  local name="$3"

  if command -v ss &>/dev/null; then
    if [[ "$proto" == "udp" ]]; then
      if ss -ulnp 2>/dev/null | grep -q ":${port} " ; then
        pass "${name} :${port} (${proto}): listening"
      else
        fail "${name} :${port} (${proto}): NOT listening"
        ERRORS=$((ERRORS + 1))
      fi
    else
      if ss -tlnp 2>/dev/null | grep -q ":${port} " ; then
        pass "${name} :${port} (${proto}): listening"
      else
        fail "${name} :${port} (${proto}): NOT listening"
        ERRORS=$((ERRORS + 1))
      fi
    fi
  else
    warn "ss not available, cannot check port ${port}"
  fi
}

check_port 443  "udp" "HY2"
check_port 9443 "udp" "TUIC"
check_port 8443 "tcp" "Reality"
check_port 2443 "tcp" "Trojan"

# ── Config Files ────────────────────────────────────────────────────────────

header "Config Files"

CONFIG_FILES=(
  "/etc/hysteria/config.yaml:HY2"
  "/etc/proxy-stack/tuic-v5-9443/config.json:TUIC"
  "/etc/proxy-stack/xray-reality-8443/config.json:Reality"
  "/etc/proxy-stack/xray-trojan-2443/config.json:Trojan"
)

for entry in "${CONFIG_FILES[@]}"; do
  local path="${entry%%:*}"
  local name="${entry##*:}"
  if [[ -f "$path" ]]; then
    pass "${name} config: ${path}"
  else
    warn "${name} config not found: ${path}"
    WARNINGS=$((WARNINGS + 1))
  fi
done

# ── Summary ─────────────────────────────────────────────────────────────────

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
