#!/usr/bin/env bash
# NanoBK Proxy Suite — VPS Installer v0.2
#
# Installs and configures four proxy services on a Linux VPS:
#   - Hysteria2 (UDP 443)
#   - TUIC v5 (UDP 9443)
#   - VLESS Reality (TCP 8443)
#   - Trojan TLS (TCP 2443)
#
# Generates Cloudflare Worker-compatible profile JSON.
#
# Usage:
#   sudo bash installer/install-vps.sh --domain proxy.example.com --cert-mode existing \
#     --cert-file /etc/ssl/fullchain.pem --key-file /etc/ssl/privkey.pem
#
#   sudo bash installer/install-vps.sh --dry-run --domain proxy.example.com --cert-mode self-signed

set -Eeuo pipefail

# ── Resolve script directory ───────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Source libraries ────────────────────────────────────────────────────────

source "${REPO_DIR}/vps/lib/common.sh"
source "${REPO_DIR}/vps/lib/os.sh"
source "${REPO_DIR}/vps/lib/download.sh"
source "${REPO_DIR}/vps/lib/profile.sh"

# ── Default configuration ──────────────────────────────────────────────────

NANOBK_DRY_RUN=0
NANOBK_YES=0
NANOBK_FORCE=0
NANOBK_OPEN_FIREWALL=0

NANOBK_DOMAIN=""
NANOBK_REALITY_SERVERNAME="www.microsoft.com"
NANOBK_VPS_IP=""
NANOBK_EMAIL=""
NANOBK_CERT_MODE="existing"
NANOBK_CERT_FILE=""
NANOBK_KEY_FILE=""

NANOBK_INSTALL_DIR="/opt/nanobk"
NANOBK_CONFIG_DIR="/etc/nanobk"

# Derived paths
NANOBK_SECRETS_FILE=""
NANOBK_PROFILE_FILE=""
NANOBK_PROFILE_INITIAL=""
NANOBK_CONFIG_ENV_FILE=""

# Service config paths
HY2_CONFIG=""
TUIC_CONFIG=""
REALITY_CONFIG=""
TROJAN_CONFIG=""

# ── Help ────────────────────────────────────────────────────────────────────

show_help() {
  cat <<'EOF'
NanoBK Proxy Suite — VPS Installer v0.2

Usage:
  sudo bash installer/install-vps.sh [OPTIONS]

Options:
  --dry-run                   Print actions without modifying the system
  --yes                       Non-interactive mode (accept defaults)
  --domain DOMAIN             Domain for HY2/TUIC/Trojan (required for TLS)
  --reality-servername NAME   Reality camouflage SNI (default: www.microsoft.com)
  --vps-ip IP                 VPS public IP (auto-detected if omitted)
  --email EMAIL               Email for certificate requests
  --cert-mode MODE            Certificate mode: existing | self-signed | none
  --cert-file PATH            Path to TLS certificate (fullchain) for existing mode
  --key-file PATH             Path to TLS private key for existing mode
  --install-dir PATH          Installation dir (default: /opt/nanobk)
  --config-dir PATH           Config dir (default: /etc/nanobk)
  --open-firewall             Attempt to open firewall ports
  --force                     Overwrite existing configuration
  --help                      Show this help

Certificate modes:
  existing     Use provided cert/key files (recommended for production)
  self-signed  Generate self-signed certs (testing only, clients need skip-cert-verify)
  none         No TLS certs (only Reality will work; HY2/TUIC/Trojan require TLS)

Examples:
  # Production with existing certificate
  sudo bash installer/install-vps.sh --yes \
    --domain proxy.example.com \
    --cert-mode existing \
    --cert-file /etc/letsencrypt/live/proxy.example.com/fullchain.pem \
    --key-file /etc/letsencrypt/live/proxy.example.com/privkey.pem

  # Dry-run to preview actions
  sudo bash installer/install-vps.sh --dry-run \
    --domain proxy.example.com \
    --cert-mode self-signed

  # Test with custom directories (no root needed)
  bash installer/install-vps.sh --dry-run \
    --install-dir /tmp/nanobk-test/opt \
    --config-dir /tmp/nanobk-test/etc \
    --domain proxy.example.com \
    --cert-mode self-signed --yes
EOF
}

# ── Argument parsing ────────────────────────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)          NANOBK_DRY_RUN=1 ;;
      --yes)              NANOBK_YES=1 ;;
      --domain)           NANOBK_DOMAIN="$2"; shift ;;
      --reality-servername) NANOBK_REALITY_SERVERNAME="$2"; shift ;;
      --vps-ip)           NANOBK_VPS_IP="$2"; shift ;;
      --email)            NANOBK_EMAIL="$2"; shift ;;
      --cert-mode)        NANOBK_CERT_MODE="$2"; shift ;;
      --cert-file)        NANOBK_CERT_FILE="$2"; shift ;;
      --key-file)         NANOBK_KEY_FILE="$2"; shift ;;
      --install-dir)      NANOBK_INSTALL_DIR="$2"; shift ;;
      --config-dir)       NANOBK_CONFIG_DIR="$2"; shift ;;
      --open-firewall)    NANOBK_OPEN_FIREWALL=1 ;;
      --force)            NANOBK_FORCE=1 ;;
      --help|-h)          show_help; exit 0 ;;
      *)                  die "Unknown option: $1. Use --help for usage." ;;
    esac
    shift
  done

  # Validate cert mode
  case "$NANOBK_CERT_MODE" in
    existing|self-signed|none) ;;
    *) die "Invalid --cert-mode: ${NANOBK_CERT_MODE}. Must be: existing, self-signed, none" ;;
  esac

  # Derive paths
  NANOBK_SECRETS_FILE="${NANOBK_CONFIG_DIR}/secrets.private.env"
  NANOBK_PROFILE_FILE="${NANOBK_CONFIG_DIR}/profile.current.json"
  NANOBK_PROFILE_INITIAL="${NANOBK_CONFIG_DIR}/profile.initial.json"
  NANOBK_CONFIG_ENV_FILE="${NANOBK_CONFIG_DIR}/config.env"

  HY2_CONFIG="${NANOBK_CONFIG_DIR}/hysteria/config.yaml"
  TUIC_CONFIG="${NANOBK_CONFIG_DIR}/tuic-v5-9443/config.json"
  REALITY_CONFIG="${NANOBK_CONFIG_DIR}/xray-reality-8443/config.json"
  TROJAN_CONFIG="${NANOBK_CONFIG_DIR}/xray-trojan-2443/config.json"
}

# ── Confirmation ────────────────────────────────────────────────────────────

confirm_install() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║          NanoBK Proxy Suite — VPS Installer             ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Domain:          ${NANOBK_DOMAIN:-<not set>}"
  echo "  VPS IP:          ${NANOBK_VPS_IP:-<auto-detect>}"
  echo "  Reality SNI:     ${NANOBK_REALITY_SERVERNAME}"
  echo "  Cert mode:       ${NANOBK_CERT_MODE}"
  echo "  Cert file:       ${NANOBK_CERT_FILE:-<none>}"
  echo "  Key file:        ${NANOBK_KEY_FILE:-<none>}"
  echo "  Config dir:      ${NANOBK_CONFIG_DIR}"
  echo "  Install dir:     ${NANOBK_INSTALL_DIR}"
  echo "  Open firewall:   $([ "$NANOBK_OPEN_FIREWALL" == "1" ] && echo "yes" || echo "no")"
  echo "  Force overwrite: $([ "$NANOBK_FORCE" == "1" ] && echo "yes" || echo "no")"
  echo "  Dry-run:         $([ "$NANOBK_DRY_RUN" == "1" ] && echo "yes" || echo "no")"
  echo ""

  confirm_or_die "Proceed with installation?"
}

# ── Certificate validation ──────────────────────────────────────────────────

validate_cert_inputs() {
  log "Validating certificate configuration..."

  case "$NANOBK_CERT_MODE" in
    existing)
      if [[ -z "$NANOBK_CERT_FILE" ]] || [[ -z "$NANOBK_KEY_FILE" ]]; then
        die "--cert-mode existing requires --cert-file and --key-file"
      fi
      if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
        [[ -f "$NANOBK_CERT_FILE" ]] || die "Certificate file not found: ${NANOBK_CERT_FILE}"
        [[ -f "$NANOBK_KEY_FILE" ]] || die "Key file not found: ${NANOBK_KEY_FILE}"
      fi
      ok "Certificate mode: existing"
      ;;
    self-signed)
      warn "Certificate mode: self-signed (NOT recommended for production)"
      warn "Clients will need to enable skip-cert-verify."
      NANOBK_CERT_FILE="${NANOBK_CONFIG_DIR}/tls/selfsigned.pem"
      NANOBK_KEY_FILE="${NANOBK_CONFIG_DIR}/tls/selfsigned-key.pem"
      ;;
    none)
      warn "Certificate mode: none"
      warn "HY2, TUIC, and Trojan require TLS certificates to function."
      warn "Only VLESS Reality will work without TLS certificates."
      NANOBK_CERT_FILE="/dev/null"
      NANOBK_KEY_FILE="/dev/null"
      ;;
  esac
}

# ── Self-signed certificate generation ──────────────────────────────────────

generate_self_signed_cert() {
  if [[ "$NANOBK_CERT_MODE" != "self-signed" ]]; then
    return 0
  fi

  require_var "NANOBK_DOMAIN" "$NANOBK_DOMAIN"

  local cert_dir="${NANOBK_CONFIG_DIR}/tls"
  ensure_dir "$cert_dir"

  if [[ -f "$NANOBK_CERT_FILE" ]] && [[ -f "$NANOBK_KEY_FILE" ]] && [[ "$NANOBK_FORCE" != "1" ]]; then
    ok "Self-signed certificate already exists"
    return 0
  fi

  run_cmd "Generate self-signed certificate" \
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$NANOBK_KEY_FILE" \
    -out "$NANOBK_CERT_FILE" \
    -days 3650 -nodes \
    -subj "/CN=${NANOBK_DOMAIN}" \
    -addext "subjectAltName=DNS:${NANOBK_DOMAIN},IP:${NANOBK_VPS_IP:-127.0.0.1}"
}

# ── Config rendering ────────────────────────────────────────────────────────

render_configs() {
  log "Rendering service configurations..."

  local tpl_dir="${REPO_DIR}/vps/templates"

  # Read templates
  local hy2_tpl tuic_tpl reality_tpl trojan_tpl
  hy2_tpl=$(cat "${tpl_dir}/hysteria2.config.yaml.tpl")
  tuic_tpl=$(cat "${tpl_dir}/tuic-v5.config.json.tpl")
  reality_tpl=$(cat "${tpl_dir}/xray-reality.config.json.tpl")
  trojan_tpl=$(cat "${tpl_dir}/xray-trojan.config.json.tpl")

  # Render HY2
  local hy2_content
  hy2_content=$(render_template "$hy2_tpl" \
    "HY2_PORT=443" \
    "CERT_FILE=${NANOBK_CERT_FILE}" \
    "KEY_FILE=${NANOBK_KEY_FILE}" \
    "HY2_PASSWORD=${HY2_PASSWORD}")
  write_file "$HY2_CONFIG" 600 "$hy2_content"

  # Render TUIC
  local tuic_content
  tuic_content=$(render_template "$tuic_tpl" \
    "TUIC_PORT=9443" \
    "CERT_FILE=${NANOBK_CERT_FILE}" \
    "KEY_FILE=${NANOBK_KEY_FILE}" \
    "TUIC_UUID=${TUIC_UUID}" \
    "TUIC_PASSWORD=${TUIC_PASSWORD}")
  write_file "$TUIC_CONFIG" 600 "$tuic_content"

  # Reality dest: servername:443
  local reality_dest="${NANOBK_REALITY_SERVERNAME}:443"

  # Render Reality
  local reality_content
  reality_content=$(render_template "$reality_tpl" \
    "REALITY_PORT=8443" \
    "REALITY_UUID=${REALITY_UUID}" \
    "REALITY_SERVERNAME=${NANOBK_REALITY_SERVERNAME}" \
    "REALITY_DEST=${reality_dest}" \
    "REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}" \
    "REALITY_SHORT_ID=${REALITY_SHORT_ID}")
  write_file "$REALITY_CONFIG" 600 "$reality_content"

  # Render Trojan
  local trojan_content
  trojan_content=$(render_template "$trojan_tpl" \
    "TROJAN_PORT=2443" \
    "CERT_FILE=${NANOBK_CERT_FILE}" \
    "KEY_FILE=${NANOBK_KEY_FILE}" \
    "TROJAN_PASSWORD=${TROJAN_PASSWORD}")
  write_file "$TROJAN_CONFIG" 600 "$trojan_content"
}

# ── Systemd units ───────────────────────────────────────────────────────────

render_systemd_units() {
  log "Rendering systemd service units..."

  local tpl_dir="${REPO_DIR}/vps/systemd"

  local svcs=(
    "hysteria-server.service:${tpl_dir}/hysteria-server.service.tpl:HY2_CONFIG=${HY2_CONFIG}"
    "tuic-v5-9443.service:${tpl_dir}/tuic-v5-9443.service.tpl:TUIC_CONFIG=${TUIC_CONFIG}"
    "xray-reality-8443.service:${tpl_dir}/xray-reality-8443.service.tpl:REALITY_CONFIG=${REALITY_CONFIG}"
    "xray-trojan-2443.service:${tpl_dir}/xray-trojan-2443.service.tpl:TROJAN_CONFIG=${TROJAN_CONFIG}"
  )

  for entry in "${svcs[@]}"; do
    IFS=':' read -r svc_name tpl_path kv_pair <<< "$entry"
    local kv_key="${kv_pair%%=*}"
    local kv_val="${kv_pair#*=}"

    local tpl_content
    tpl_content=$(cat "$tpl_path")
    local rendered
    rendered=$(render_template "$tpl_content" "${kv_key}=${kv_val}")

    local svc_path="/etc/systemd/system/${svc_name}"
    write_file "$svc_path" 644 "$rendered"
  done

  run_cmd "Reload systemd daemon" systemctl daemon-reload
}

# ── Config env file ────────────────────────────────────────────────────────

write_config_env() {
  log "Writing config environment..."

  local content
  content=$(cat <<EOF
# NanoBK Proxy Suite — VPS Configuration
# Generated: $(iso_date)
# This file is sourced by management scripts.

NANOBK_DOMAIN="${NANOBK_DOMAIN}"
NANOBK_VPS_IP="${NANOBK_VPS_IP}"
NANOBK_GEO_LABEL="${NANOBK_GEO_LABEL:-UN}"
NANOBK_CERT_MODE="${NANOBK_CERT_MODE}"
NANOBK_CERT_FILE="${NANOBK_CERT_FILE}"
NANOBK_KEY_FILE="${NANOBK_KEY_FILE}"

HY2_SERVICE="hysteria-server.service"
TUIC_SERVICE="tuic-v5-9443.service"
REALITY_SERVICE="xray-reality-8443.service"
TROJAN_SERVICE="xray-trojan-2443.service"

HY2_CONFIG="${HY2_CONFIG}"
TUIC_CONFIG="${TUIC_CONFIG}"
REALITY_CONFIG="${REALITY_CONFIG}"
TROJAN_CONFIG="${TROJAN_CONFIG}"

HY2_PORT=443
TUIC_PORT=9443
REALITY_PORT=8443
TROJAN_PORT=2443

REALITY_SERVERNAME="${NANOBK_REALITY_SERVERNAME}"
EOF
)
  write_file "$NANOBK_CONFIG_ENV_FILE" 600 "$content"
}

# ── Service management ──────────────────────────────────────────────────────

enable_and_start_services() {
  log "Enabling and starting services..."

  local services=(
    "hysteria-server.service"
    "tuic-v5-9443.service"
    "xray-reality-8443.service"
    "xray-trojan-2443.service"
  )

  for svc in "${services[@]}"; do
    run_cmd "Enable and start ${svc}" systemctl enable --now "$svc"
  done

  if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
    sleep 2
    log "Checking service status..."
    for svc in "${services[@]}"; do
      local status
      status=$(systemctl is-active "$svc" 2>/dev/null || true)
      if [[ "$status" == "active" ]]; then
        ok "${svc}: active"
      else
        warn "${svc}: ${status} (check journalctl -u ${svc})"
      fi
    done
  fi
}

# ── Firewall ────────────────────────────────────────────────────────────────

open_firewall() {
  if [[ "$NANOBK_OPEN_FIREWALL" != "1" ]]; then
    return 0
  fi

  log "Opening firewall ports..."

  if command -v ufw &>/dev/null; then
    run_cmd "ufw allow 443/udp" ufw allow 443/udp
    run_cmd "ufw allow 9443/udp" ufw allow 9443/udp
    run_cmd "ufw allow 8443/tcp" ufw allow 8443/tcp
    run_cmd "ufw allow 2443/tcp" ufw allow 2443/tcp
  elif command -v firewall-cmd &>/dev/null; then
    run_cmd "firewall-cmd permanent 443/udp" firewall-cmd --permanent --add-port=443/udp
    run_cmd "firewall-cmd permanent 9443/udp" firewall-cmd --permanent --add-port=9443/udp
    run_cmd "firewall-cmd permanent 8443/tcp" firewall-cmd --permanent --add-port=8443/tcp
    run_cmd "firewall-cmd permanent 2443/tcp" firewall-cmd --permanent --add-port=2443/tcp
    run_cmd "firewall-cmd reload" firewall-cmd --reload
  else
    warn "No firewall tool found (ufw/firewall-cmd). Manually open ports if needed."
  fi
}

# ── Print next steps ────────────────────────────────────────────────────────

print_next_steps() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║          NanoBK VPS Install Completed                   ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Generated profile: ${NANOBK_PROFILE_FILE}"
  echo ""
  echo "  Next steps:"
  echo "    1. Deploy nanok Worker on Cloudflare."
  echo "    2. Upload profile.current.json into KV key profile:main."
  echo "    3. Set SUB_TOKEN and ADMIN_TOKEN secrets."
  echo "    4. Import subscription URL into Clash/Mihomo."
  echo "    5. Optional: configure nanob and edgetunnel backup."
  echo ""
  echo "  Full secrets are stored locally:"
  echo "    ${NANOBK_SECRETS_FILE}"
  echo "  Never commit this file."
  echo ""
  echo "  To rotate keys later:"
  echo "    bash ${NANOBK_INSTALL_DIR}/bin/rotate-keys.sh"
  echo ""
  echo "  To check health:"
  echo "    bash ${NANOBK_INSTALL_DIR}/bin/healthcheck.sh"
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  parse_args "$@"

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║    NanoBK VPS Installer — DRY-RUN MODE                  ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
  fi

  # Phase 1: Environment
  detect_os
  ensure_root_or_dry_run
  ensure_systemd
  confirm_install

  # Phase 2: Dependencies
  install_dependencies

  # Phase 3: Binaries
  install_all_binaries

  # Phase 4: Network detection
  if [[ -z "$NANOBK_VPS_IP" ]]; then
    log "Detecting public IP..."
    NANOBK_VPS_IP=$(detect_public_ip) || warn "Could not auto-detect VPS IP. Use --vps-ip."
  fi
  if [[ -n "$NANOBK_VPS_IP" ]]; then
    ok "VPS IP: ${NANOBK_VPS_IP}"
  fi

  log "Resolving geo label..."
  NANOBK_GEO_LABEL=$(resolve_geo_label "$NANOBK_VPS_IP")
  ok "Geo label: ${NANOBK_GEO_LABEL}"

  # Phase 5: Certificates
  validate_cert_inputs
  generate_self_signed_cert

  # Phase 6: Credentials
  generate_all_credentials

  # Phase 7: Config files
  ensure_dir "$NANOBK_CONFIG_DIR"
  ensure_dir "${NANOBK_INSTALL_DIR}/bin"
  ensure_dir "${NANOBK_INSTALL_DIR}/backups"
  ensure_dir "${NANOBK_INSTALL_DIR}/logs"

  render_configs
  render_systemd_units
  write_config_env

  # Phase 8: Secrets
  write_file "$NANOBK_SECRETS_FILE" 600 "$(generate_secrets_env)"

  # Phase 9: Profile JSON
  local profile_json
  profile_json=$(generate_profile_json \
    "$NANOBK_DOMAIN" \
    "$NANOBK_VPS_IP" \
    "$NANOBK_GEO_LABEL" \
    "$NANOBK_REALITY_SERVERNAME")

  write_file "$NANOBK_PROFILE_FILE" 644 "$profile_json"
  write_file "$NANOBK_PROFILE_INITIAL" 644 "$profile_json"

  # Validate profile
  if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
    jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' \
      "$NANOBK_PROFILE_FILE" >/dev/null || die "Profile JSON validation failed"
    ok "Profile JSON validated"
  fi

  # Phase 10: Services
  enable_and_start_services
  open_firewall

  # Phase 11: Install management scripts
  run_cmd "Copy healthcheck.sh" cp "${REPO_DIR}/vps/scripts/healthcheck.sh" "${NANOBK_INSTALL_DIR}/bin/healthcheck.sh"
  run_cmd "Copy rotate-keys.sh" cp "${REPO_DIR}/vps/scripts/rotate-keys.sh" "${NANOBK_INSTALL_DIR}/bin/rotate-keys.sh"
  if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
    chmod +x "${NANOBK_INSTALL_DIR}/bin/"*.sh 2>/dev/null || true
  fi

  # Done
  print_next_steps
}

main "$@"
