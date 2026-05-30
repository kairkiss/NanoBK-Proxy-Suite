#!/usr/bin/env bash
# NanoBK Proxy Suite — Cloudflare Workers Installer
#
# Sets up nanok and nanob Workers on Cloudflare.
#
# Prerequisites:
#   - Node.js and npm installed
#   - Wrangler CLI installed (npm install -g wrangler)
#   - Cloudflare account with Workers and KV enabled
#   - A domain configured on Cloudflare
#
# Usage:
#   bash installer/install-cloudflare.sh
#
# Status: v0.1 scaffold — lists steps but does not yet execute them.

set -Eeuo pipefail

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

check_tools() {
  local missing=0
  for cmd in node npm; do
    if ! command -v "$cmd" &>/dev/null; then
      err "Missing: $cmd"
      missing=1
    fi
  done
  if [[ $missing -eq 1 ]]; then
    err "Install Node.js from https://nodejs.org/"
    exit 1
  fi
  ok "Node.js $(node --version), npm $(npm --version)"

  if ! command -v wrangler &>/dev/null; then
    warn "Wrangler CLI not found. Install with: npm install -g wrangler"
    warn "Or use: npx wrangler"
  else
    ok "Wrangler $(wrangler --version 2>/dev/null || echo 'installed')"
  fi
}

# ── Installation Steps (TODO) ──────────────────────────────────────────────

step_create_kv_namespaces() {
  info "Step 1/6: Create KV namespaces"
  echo "  TODO: wrangler kv:namespace create SUB_STORE"
  echo "  TODO: wrangler kv:namespace create NANOB_GEO_CACHE"
  echo "  TODO: Record namespace IDs"
  echo ""
}

step_deploy_nanok() {
  info "Step 2/6: Deploy nanok (primary subscription Worker)"
  echo "  TODO: Copy workers/nanok/wrangler.toml.example to wrangler.toml"
  echo "  TODO: Set KV namespace ID"
  echo "  TODO: wrangler secret put SUB_TOKEN"
  echo "  TODO: wrangler secret put ADMIN_TOKEN"
  echo "  TODO: wrangler deploy"
  echo "  TODO: Attach custom domain"
  echo ""
}

step_init_profile() {
  info "Step 3/6: Initialize KV profile"
  echo "  TODO: Prepare profile JSON (from VPS setup or examples/profile.example.json)"
  echo "  TODO: POST to /admin/update with admin token"
  echo "  TODO: Verify GET /admin/current returns the profile"
  echo ""
}

step_deploy_nanob() {
  info "Step 4/6: Deploy nanob (aggregator Worker)"
  echo "  TODO: Copy workers/nanob/wrangler.toml.example to wrangler.toml"
  echo "  TODO: Set KV namespace ID for NANOB_GEO_CACHE"
  echo "  TODO: wrangler secret put NANOB_TOKEN"
  echo "  TODO: wrangler secret put NANOK_SUB_TOKEN"
  echo "  TODO: (Optional) wrangler secret put EDGETUNNEL_EXPORT_TOKEN"
  echo "  TODO: wrangler deploy"
  echo "  TODO: Attach custom domain"
  echo ""
}

step_verify() {
  info "Step 5/6: Verify deployment"
  echo "  TODO: curl https://YOUR_NANOK_HOST/ (should show status page)"
  echo "  TODO: curl https://YOUR_NANOK_HOST/jb?token=YOUR_TOKEN (should return YAML)"
  echo "  TODO: curl https://YOUR_NANOB_HOST/jb?token=YOUR_TOKEN (should return YAML)"
  echo ""
}

step_setup_vps_admin() {
  info "Step 6/6: Configure VPS admin token"
  echo "  TODO: Write /root/.nanok-cf-admin.env on VPS"
  echo "  TODO: See examples/env.cloudflare.example for required variables"
  echo "  TODO: chmod 600 /root/.nanok-cf-admin.env"
  echo ""
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║       NanoBK Proxy Suite — Cloudflare Installer         ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""

  check_tools
  echo ""

  warn "v0.1 scaffold: This script shows the planned steps but does not"
  warn "execute them yet. Each step will be implemented in v0.3."
  echo ""

  step_create_kv_namespaces
  step_deploy_nanok
  step_init_profile
  step_deploy_nanob
  step_verify
  step_setup_vps_admin

  info "Cloudflare setup complete (when implemented)."
  echo ""
  info "Your subscription URL:"
  echo "  https://YOUR_NANOB_HOST/jb?token=YOUR_NANOB_TOKEN"
  echo ""
}

main "$@"
