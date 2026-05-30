#!/usr/bin/env bash
# NanoBK Proxy Suite — Profile generation and Geo detection
# Source this file; do not execute directly.

# Requires: vps/lib/common.sh, vps/lib/os.sh (for generate_uuid)

# ── Public IP detection ─────────────────────────────────────────────────────

detect_public_ip() {
  local ip=""

  for url in "https://api.ipify.org" "https://ifconfig.me/ip" "https://icanhazip.com"; do
    ip=$(curl -fsSL --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')
    if [[ -n "$ip" ]] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  done

  return 1
}

# ── Geo label from IP ──────────────────────────────────────────────────────

resolve_geo_label() {
  local ip="$1"
  local label="UN"

  if [[ -z "$ip" ]]; then
    echo "$label"
    return
  fi

  local geo_json
  geo_json=$(curl -fsSL --max-time 5 "https://ipwho.is/${ip}" 2>/dev/null) || {
    echo "$label"
    return
  }

  local success
  success=$(echo "$geo_json" | jq -r '.success // false' 2>/dev/null)
  if [[ "$success" != "true" ]]; then
    echo "$label"
    return
  fi

  local country_code
  country_code=$(echo "$geo_json" | jq -r '.country_code // empty' 2>/dev/null)
  if [[ -n "$country_code" ]]; then
    label="$country_code"
  else
    local country
    country=$(echo "$geo_json" | jq -r '.country // empty' 2>/dev/null)
    [[ -n "$country" ]] && label="$country"
  fi

  echo "$label"
}

# ── Credential generation ──────────────────────────────────────────────────

# Globals set by generate_all_credentials():
#   HY2_PASSWORD, TUIC_UUID, TUIC_PASSWORD
#   REALITY_UUID, REALITY_PRIVATE_KEY, REALITY_PUBLIC_KEY, REALITY_SHORT_ID
#   TROJAN_PASSWORD

generate_all_credentials() {
  log "Generating credentials..."

  HY2_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
  TUIC_UUID=$(generate_uuid)
  TUIC_PASSWORD=$(openssl rand -hex 32 | tr -d '\n')
  TROJAN_PASSWORD=$(openssl rand -base64 24 | tr -d '\n')
  REALITY_UUID=$(generate_uuid)
  REALITY_SHORT_ID=$(openssl rand -hex 8 | tr -d '\n')

  # Reality X25519 keypair
  if command -v xray &>/dev/null; then
    local keypair
    keypair=$(xray x25519) || die "Failed to generate Reality keypair"
    # Robust parser: handles "Private key:", "PrivateKey:", "private key:" etc.
    REALITY_PRIVATE_KEY=$(printf '%s\n' "$keypair" | awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}' | tr -d '\r\n')
    REALITY_PUBLIC_KEY=$(printf '%s\n' "$keypair" | awk -F': *' 'tolower($1) ~ /public/ {print $2; exit}' | tr -d '\r\n')
  elif [[ "$NANOBK_DRY_RUN" == "1" ]] || [[ "$NANOBK_RENDER_ONLY" == "1" ]]; then
    warn "xray not available for keypair generation (using placeholder for test)"
    REALITY_PRIVATE_KEY="RENDER_ONLY_PLACEHOLDER_PRIVATE_KEY_NOT_FOR_PRODUCTION"
    REALITY_PUBLIC_KEY="RENDER_ONLY_PLACEHOLDER_PUBLIC_KEY_NOT_FOR_PRODUCTION"
  else
    die "xray is required for Reality keypair generation"
  fi

  [[ -n "$REALITY_PRIVATE_KEY" ]] || die "Reality private key is empty"
  [[ -n "$REALITY_PUBLIC_KEY" ]] || die "Reality public key is empty"

  ok "Generated credential fingerprints:"
  echo "    HY2 password:     $(fingerprint "$HY2_PASSWORD")"
  echo "    TUIC UUID:        $(fingerprint "$TUIC_UUID")"
  echo "    TUIC password:    $(fingerprint "$TUIC_PASSWORD")"
  echo "    Reality UUID:     $(fingerprint "$REALITY_UUID")"
  echo "    Reality public:   $(fingerprint "$REALITY_PUBLIC_KEY")"
  echo "    Reality shortId:  $(fingerprint "$REALITY_SHORT_ID")"
  echo "    Trojan password:  $(fingerprint "$TROJAN_PASSWORD")"
}

# ── Profile JSON generation ────────────────────────────────────────────────

# Generates the profile JSON compatible with nanok Worker KV format.
# Does NOT include Reality private key.
#
# Args: domain vps_ip geo_label reality_servername
# Reads from globals: all credential variables

generate_profile_json() {
  local domain="$1"
  local vps_ip="$2"
  local geo="$3"
  local reality_sname="$4"

  cat <<EOF
{
  "updatedAt": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
  "hy2": {
    "name": "[${geo}] HY2 | 443 | Primary",
    "server": "${domain}",
    "port": 443,
    "password": "${HY2_PASSWORD}",
    "sni": "${domain}"
  },
  "tuic": {
    "name": "[${geo}] TUIC | 9443 | Speed",
    "server": "${domain}",
    "port": 9443,
    "uuid": "${TUIC_UUID}",
    "password": "${TUIC_PASSWORD}",
    "sni": "${domain}"
  },
  "reality": {
    "name": "[${geo}] Reality | 8443 | Stealth",
    "server": "${vps_ip}",
    "port": 8443,
    "uuid": "${REALITY_UUID}",
    "servername": "${reality_sname}",
    "publicKey": "${REALITY_PUBLIC_KEY}",
    "shortId": "${REALITY_SHORT_ID}"
  },
  "trojan": {
    "name": "[${geo}] Trojan | 2443 | Fallback",
    "server": "${domain}",
    "port": 2443,
    "password": "${TROJAN_PASSWORD}",
    "sni": "${domain}"
  },
  "extraNodes": {
    "poetryNodeName": "NanoBK notice",
    "recommendNodeName": "NanoBK recommendation"
  }
}
EOF
}

# ── Secrets env generation ──────────────────────────────────────────────────

generate_secrets_env() {
  cat <<EOF
# NanoBK Proxy Suite — Generated secrets
# Generated: $(iso_date)
# KEEP THIS FILE PRIVATE — never commit to Git.
#
# This file is sourced by rotate-keys.sh and other management scripts.

HY2_PASSWORD="${HY2_PASSWORD}"
TUIC_UUID="${TUIC_UUID}"
TUIC_PASSWORD="${TUIC_PASSWORD}"
REALITY_UUID="${REALITY_UUID}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY}"
REALITY_SHORT_ID="${REALITY_SHORT_ID}"
TROJAN_PASSWORD="${TROJAN_PASSWORD}"
EOF
}

# ── Cloudflare admin env template ──────────────────────────────────────────

generate_cf_admin_env_template() {
  cat <<'EOF'
# NanoBK Proxy Suite — Cloudflare Admin Environment
# Copy to /root/.nanok-cf-admin.env and fill in real values.
# chmod 600 /root/.nanok-cf-admin.env
# Do NOT commit this file.

ADMIN_TOKEN="REPLACE_WITH_YOUR_ADMIN_TOKEN"
ADMIN_CURRENT_URL="https://YOUR_WORKER_HOST/admin/current"
ADMIN_UPDATE_URL="https://YOUR_WORKER_HOST/admin/update"
EOF
}
