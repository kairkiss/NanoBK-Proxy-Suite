#!/usr/bin/env bash
# NanoBK Proxy Suite — VPS Installer v0.2.1
#
# Installs and configures four proxy services on a Linux VPS:
#   - Hysteria2 (UDP 443)
#   - TUIC v5 (UDP 9443)
#   - VLESS Reality (TCP 8443)
#   - Trojan TLS (TCP 2443)
#
# Generates Cloudflare Worker-compatible profile JSON.
#
# Modes:
#   (default)      Full installation on Linux VPS (requires root + systemd)
#   --dry-run      Print actions without modifying the system
#   --render-only  Render all configs to --config-dir, no system changes
#
# Usage:
#   sudo bash installer/install-vps.sh --domain proxy.example.com --cert-mode existing \
#     --cert-file /etc/ssl/fullchain.pem --key-file /etc/ssl/privkey.pem
#
#   bash installer/install-vps.sh --render-only --yes \
#     --config-dir /tmp/nanobk-test/etc/nanobk \
#     --domain proxy.example.com --cert-mode self-signed

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
NANOBK_RENDER_ONLY=0
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

# Derived paths (set in parse_args)
NANOBK_SECRETS_FILE=""
NANOBK_PROFILE_FILE=""
NANOBK_PROFILE_INITIAL=""
NANOBK_CONFIG_ENV_FILE=""
NANOBK_CERTS_DIR=""
NANOBK_SYSTEMD_DIR=""

# Service config paths (set in derive_paths)
HY2_CONFIG=""
TUIC_CONFIG=""
REALITY_CONFIG=""
TROJAN_CONFIG=""

# ── Help ────────────────────────────────────────────────────────────────────

show_help() {
  cat <<'EOF'
NanoBK Proxy Suite — VPS Installer v0.2.1

Usage:
  sudo bash installer/install-vps.sh [OPTIONS]

Modes:
  (default)      Full installation on Linux VPS (requires root + systemd)
  --dry-run      Print actions without modifying the system
  --render-only  Render configs to --config-dir only, no system changes needed

Options:
  --dry-run                   Print actions without modifying the system
  --render-only               Render all configs to config-dir, no system changes
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

  # Render-only test (safe, no system changes)
  bash installer/install-vps.sh --render-only --yes \
    --config-dir /tmp/nanobk-test/etc/nanobk \
    --domain proxy.example.com \
    --vps-ip 198.51.100.10 \
    --cert-mode self-signed

  # Dry-run to preview actions
  sudo bash installer/install-vps.sh --dry-run \
    --domain proxy.example.com \
    --cert-mode self-signed
EOF
}

# ── Path derivation ─────────────────────────────────────────────────────────

derive_paths() {
  NANOBK_SECRETS_FILE="${NANOBK_CONFIG_DIR}/secrets.private.env"
  NANOBK_PROFILE_FILE="${NANOBK_CONFIG_DIR}/profile.current.json"
  NANOBK_PROFILE_INITIAL="${NANOBK_CONFIG_DIR}/profile.initial.json"
  NANOBK_CONFIG_ENV_FILE="${NANOBK_CONFIG_DIR}/config.env"
  NANOBK_CERTS_DIR="${NANOBK_CONFIG_DIR}/certs"

  if [[ "$NANOBK_RENDER_ONLY" == "1" ]]; then
    # Render-only: all generated configs go inside config-dir
    NANOBK_SYSTEMD_DIR="${NANOBK_CONFIG_DIR}/systemd"
    HY2_CONFIG="${NANOBK_CONFIG_DIR}/generated/hysteria/config.yaml"
    TUIC_CONFIG="${NANOBK_CONFIG_DIR}/generated/proxy-stack/tuic-v5-9443/config.json"
    REALITY_CONFIG="${NANOBK_CONFIG_DIR}/generated/proxy-stack/xray-reality-8443/config.json"
    TROJAN_CONFIG="${NANOBK_CONFIG_DIR}/generated/proxy-stack/xray-trojan-2443/config.json"
  else
    # Production: real system paths
    NANOBK_SYSTEMD_DIR="/etc/systemd/system"
    HY2_CONFIG="/etc/hysteria/config.yaml"
    TUIC_CONFIG="/etc/proxy-stack/tuic-v5-9443/config.json"
    REALITY_CONFIG="/etc/proxy-stack/xray-reality-8443/config.json"
    TROJAN_CONFIG="/etc/proxy-stack/xray-trojan-2443/config.json"
  fi
}

# ── Argument parsing ────────────────────────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)          NANOBK_DRY_RUN=1 ;;
      --render-only)      NANOBK_RENDER_ONLY=1 ;;
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

  derive_paths
}

# ── Platform safety guard ───────────────────────────────────────────────────

check_platform_safety() {
  # render-only and dry-run can run anywhere
  if [[ "$NANOBK_RENDER_ONLY" == "1" ]] || [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    return 0
  fi

  # Full install requires Linux
  if [[ "$(uname -s)" != "Linux" ]]; then
    die "NanoBK VPS installer only supports Linux VPS. Use --render-only for local test."
  fi

  # Full install requires systemd
  if ! command -v systemctl &>/dev/null; then
    die "systemctl not found. This installer requires systemd. Use --render-only for local test."
  fi
}

# ── Confirmation ────────────────────────────────────────────────────────────

confirm_install() {
  local mode_label="PRODUCTION"
  [[ "$NANOBK_DRY_RUN" == "1" ]] && mode_label="DRY-RUN"
  [[ "$NANOBK_RENDER_ONLY" == "1" ]] && mode_label="RENDER-ONLY"

  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║    NanoBK VPS Installer — ${mode_label}                "
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Domain:          ${NANOBK_DOMAIN:-<not set>}"
  echo "  VPS IP:          ${NANOBK_VPS_IP:-<auto-detect>}"
  echo "  Reality SNI:     ${NANOBK_REALITY_SERVERNAME}"
  echo "  Cert mode:       ${NANOBK_CERT_MODE}"
  echo "  Config dir:      ${NANOBK_CONFIG_DIR}"
  echo "  Install dir:     ${NANOBK_INSTALL_DIR}"
  echo ""

  confirm_or_die "Proceed?"
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
      warn "Self-signed cert is for testing only. Some clients may reject it unless skip-cert-verify is enabled."
      NANOBK_CERT_FILE="${NANOBK_CERTS_DIR}/selfsigned.fullchain.pem"
      NANOBK_KEY_FILE="${NANOBK_CERTS_DIR}/selfsigned.privkey.pem"
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

  ensure_dir "$NANOBK_CERTS_DIR"

  if [[ -f "$NANOBK_CERT_FILE" ]] && [[ -f "$NANOBK_KEY_FILE" ]] && [[ "$NANOBK_FORCE" != "1" ]]; then
    ok "Self-signed certificate already exists"
    return 0
  fi

  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    echo -e "  ${CYAN}[DRY-RUN]${NC} Generate self-signed certificate"
    echo -e "  ${CYAN}  cert:${NC} ${NANOBK_CERT_FILE}"
    echo -e "  ${CYAN}  key:${NC}  ${NANOBK_KEY_FILE}"
    return 0
  fi

  log "Generating self-signed certificate..."
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$NANOBK_KEY_FILE" \
    -out "$NANOBK_CERT_FILE" \
    -days 3650 -nodes \
    -subj "/CN=${NANOBK_DOMAIN}" \
    -addext "subjectAltName=DNS:${NANOBK_DOMAIN},IP:${NANOBK_VPS_IP:-127.0.0.1}" \
    2>/dev/null

  ok "Self-signed certificate generated"
  warn "Self-signed cert is for testing only. Some clients may reject it unless skip-cert-verify is enabled."
}

# ── Config rendering ────────────────────────────────────────────────────────

render_configs() {
  log "Rendering service configurations..."

  local tpl_dir="${REPO_DIR}/vps/templates"

  local hy2_tpl tuic_tpl reality_tpl trojan_tpl
  hy2_tpl=$(cat "${tpl_dir}/hysteria2.config.yaml.tpl")
  tuic_tpl=$(cat "${tpl_dir}/tuic-v5.config.json.tpl")
  reality_tpl=$(cat "${tpl_dir}/xray-reality.config.json.tpl")
  trojan_tpl=$(cat "${tpl_dir}/xray-trojan.config.json.tpl")

  local hy2_content
  hy2_content=$(render_template "$hy2_tpl" \
    "HY2_PORT=443" \
    "CERT_FILE=${NANOBK_CERT_FILE}" \
    "KEY_FILE=${NANOBK_KEY_FILE}" \
    "HY2_PASSWORD=${HY2_PASSWORD}")
  write_file "$HY2_CONFIG" 600 "$hy2_content"

  local tuic_content
  tuic_content=$(render_template "$tuic_tpl" \
    "TUIC_PORT=9443" \
    "CERT_FILE=${NANOBK_CERT_FILE}" \
    "KEY_FILE=${NANOBK_KEY_FILE}" \
    "TUIC_UUID=${TUIC_UUID}" \
    "TUIC_PASSWORD=${TUIC_PASSWORD}")
  write_file "$TUIC_CONFIG" 600 "$tuic_content"

  local reality_dest="${NANOBK_REALITY_SERVERNAME}:443"
  local reality_content
  reality_content=$(render_template "$reality_tpl" \
    "REALITY_PORT=8443" \
    "REALITY_UUID=${REALITY_UUID}" \
    "REALITY_SERVERNAME=${NANOBK_REALITY_SERVERNAME}" \
    "REALITY_DEST=${reality_dest}" \
    "REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}" \
    "REALITY_SHORT_ID=${REALITY_SHORT_ID}")
  write_file "$REALITY_CONFIG" 600 "$reality_content"

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

    local svc_path="${NANOBK_SYSTEMD_DIR}/${svc_name}"
    write_file "$svc_path" 644 "$rendered"
  done

  if [[ "$NANOBK_RENDER_ONLY" != "1" ]]; then
    run_cmd "Reload systemd daemon" systemctl daemon-reload
  fi
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

NANOBK_INSTALL_DIR="${NANOBK_INSTALL_DIR}"
NANOBK_CONFIG_DIR="${NANOBK_CONFIG_DIR}"
NANOBK_SYSTEMD_DIR="${NANOBK_SYSTEMD_DIR}"

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

# ── Service management (production only) ────────────────────────────────────

enable_and_start_services() {
  if [[ "$NANOBK_RENDER_ONLY" == "1" ]]; then
    log "Skipping service start (render-only mode)"
    return 0
  fi

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

# ── Firewall (production only) ──────────────────────────────────────────────

open_firewall() {
  if [[ "$NANOBK_OPEN_FIREWALL" != "1" ]] || [[ "$NANOBK_RENDER_ONLY" == "1" ]]; then
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

# ── Placeholder residue check ───────────────────────────────────────────────

check_placeholder_residue() {
  if [[ "$NANOBK_DRY_RUN" == "1" ]]; then
    return 0
  fi

  log "Checking for unreplaced placeholders..."

  local check_dirs=(
    "${NANOBK_CONFIG_DIR}/generated"
    "${NANOBK_CONFIG_DIR}/systemd"
    "${NANOBK_CONFIG_DIR}/certs"
  )

  local found=0
  for dir in "${check_dirs[@]}"; do
    if [[ -d "$dir" ]]; then
      if grep -R '__[A-Z0-9_]\+__' "$dir" 2>/dev/null; then
        found=1
      fi
    fi
  done

  # Also check top-level config files
  for f in "$NANOBK_CONFIG_ENV_FILE" "$NANOBK_SECRETS_FILE" "$NANOBK_PROFILE_FILE"; do
    if [[ -f "$f" ]]; then
      if grep -q '__[A-Z0-9_]\+__' "$f" 2>/dev/null; then
        err "Placeholder residue in: $f"
        found=1
      fi
    fi
  done

  if [[ $found -eq 1 ]]; then
    die "Unreplaced placeholders found in generated files"
  fi
  ok "No unreplaced placeholders"
}

# ── Print next steps ────────────────────────────────────────────────────────

print_next_steps() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  if [[ "$NANOBK_RENDER_ONLY" == "1" ]]; then
    echo "║          NanoBK Render Complete                         ║"
  else
    echo "║          NanoBK VPS Install Completed                   ║"
  fi
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Generated profile: ${NANOBK_PROFILE_FILE}"

  if [[ "$NANOBK_RENDER_ONLY" == "1" ]]; then
    echo ""
    echo "  Render-only mode: all files written to ${NANOBK_CONFIG_DIR}"
    echo "  No system services were started."
    echo ""
    echo "  To validate:"
    echo "    bash vps/scripts/healthcheck.sh --config-dir ${NANOBK_CONFIG_DIR} --skip-services --skip-ports"
  else
    echo ""
    echo "  Next steps:"
    echo "    1. Deploy nanok Worker on Cloudflare."
    echo "    2. Upload profile.current.json into KV key profile:main."
    echo "    3. Set SUB_TOKEN and ADMIN_TOKEN secrets."
    echo "    4. Import subscription URL into Clash/Mihomo."
    echo "    5. Optional: configure nanob and edgetunnel backup."
    echo ""
    echo "  To rotate keys later:"
    echo "    bash ${NANOBK_INSTALL_DIR}/bin/rotate-keys.sh"
    echo ""
    echo "  To check health:"
    echo "    bash ${NANOBK_INSTALL_DIR}/bin/healthcheck.sh"
  fi

  echo ""
  echo "  Full secrets are stored locally:"
  echo "    ${NANOBK_SECRETS_FILE}"
  echo "  Never commit this file."
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  parse_args "$@"
  check_platform_safety
  confirm_install

  if [[ "$NANOBK_RENDER_ONLY" == "1" ]]; then
    # ── Render-only mode: skip system operations ──

    # Generate credentials
    generate_all_credentials

    # Create directories
    ensure_dir "$NANOBK_CONFIG_DIR"
    ensure_dir "$NANOBK_CERTS_DIR"
    ensure_dir "$(dirname "$HY2_CONFIG")"
    ensure_dir "$(dirname "$TUIC_CONFIG")"
    ensure_dir "$(dirname "$REALITY_CONFIG")"
    ensure_dir "$(dirname "$TROJAN_CONFIG")"
    ensure_dir "$NANOBK_SYSTEMD_DIR"

    # Certificates
    validate_cert_inputs
    generate_self_signed_cert

    # Render configs
    render_configs
    render_systemd_units
    write_config_env

    # Secrets
    write_file "$NANOBK_SECRETS_FILE" 600 "$(generate_secrets_env)"

    # Profile JSON
    local profile_json
    profile_json=$(generate_profile_json \
      "$NANOBK_DOMAIN" \
      "${NANOBK_VPS_IP:-0.0.0.0}" \
      "${NANOBK_GEO_LABEL:-UN}" \
      "$NANOBK_REALITY_SERVERNAME")

    write_file "$NANOBK_PROFILE_FILE" 644 "$profile_json"
    write_file "$NANOBK_PROFILE_INITIAL" 644 "$profile_json"

    # Validate
    check_placeholder_residue

    if command -v jq &>/dev/null; then
      jq -e 'has("hy2") and has("tuic") and has("reality") and has("trojan")' \
        "$NANOBK_PROFILE_FILE" >/dev/null || die "Profile JSON validation failed"
      ok "Profile JSON validated"
    fi

  else
    # ── Production / dry-run mode ──

    # Phase 1: Environment
    detect_os
    ensure_root_or_dry_run
    ensure_systemd

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
      "${NANOBK_GEO_LABEL:-UN}" \
      "$NANOBK_REALITY_SERVERNAME")

    write_file "$NANOBK_PROFILE_FILE" 644 "$profile_json"
    write_file "$NANOBK_PROFILE_INITIAL" 644 "$profile_json"

    # Validate profile
    if [[ "$NANOBK_DRY_RUN" != "1" ]]; then
      check_placeholder_residue
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
  fi

  print_next_steps
}

main "$@"
