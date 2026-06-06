#!/usr/bin/env bash
# NanoBK Web Panel — Runner
#
# Sets up Python venv and starts the web panel.
# Default: binds to 127.0.0.1 (local-only, not publicly exposed).
#
# Usage:
#   bash web/run.sh

set -Eeuo pipefail

# ── Resolve web directory ───────────────────────────────────────────────────

WEB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WEB_DIR"

# ── Check .env exists ───────────────────────────────────────────────────────

if [[ ! -f ".env" ]]; then
  echo "ERROR: Missing web/.env"
  echo ""
  echo "Copy .env.example to .env and edit it:"
  echo "  cp .env.example .env"
  echo "  nano .env"
  echo ""
  echo "Required variables:"
  echo "  NANOBK_WEB_TOKEN       — login token (change from default)"
  echo "  NANOBK_WEB_SECRET_KEY  — Flask session key (change from default)"
  echo "  NANOBK_WEB_HOST        — bind address (default: 127.0.0.1)"
  echo "  NANOBK_WEB_PORT        — port (default: 8080)"
  exit 1
fi

# ── Check .env permissions ──────────────────────────────────────────────────

env_perms=$(stat -c '%a' .env 2>/dev/null || stat -f '%Lp' .env 2>/dev/null || echo "unknown")
if [[ "$env_perms" != "unknown" && "$env_perms" != "600" ]]; then
  echo "WARNING: web/.env has permissions $env_perms (recommended: 600)"
  echo "  Fix with: chmod 600 .env"
fi

# ── Validate required env values (source safely, do not echo) ───────────────

# Source .env to check values — we trust this file was created by the installer
set -a
# shellcheck disable=SC1091
source .env
set +a

if [[ "${NANOBK_WEB_TOKEN:-}" == "change-me-long-random-token" || -z "${NANOBK_WEB_TOKEN:-}" ]]; then
  echo "ERROR: NANOBK_WEB_TOKEN is not set or still has the default value."
  echo "  Edit web/.env and set a real token."
  exit 1
fi

if [[ "${NANOBK_WEB_SECRET_KEY:-}" == "change-me-session-secret" || -z "${NANOBK_WEB_SECRET_KEY:-}" ]]; then
  echo "ERROR: NANOBK_WEB_SECRET_KEY is not set or still has the default value."
  echo "  Edit web/.env and set a real secret key."
  exit 1
fi

# ── Guard against public binding ────────────────────────────────────────────

web_host="${NANOBK_WEB_HOST:-127.0.0.1}"
web_port="${NANOBK_WEB_PORT:-8080}"

if [[ "$web_host" == "0.0.0.0" ]]; then
  echo "WARNING: NANOBK_WEB_HOST is 0.0.0.0 — the Web Panel will be accessible from the network."
  echo "  This is NOT recommended unless you are behind a firewall or reverse proxy."
  echo "  Recommended: keep 127.0.0.1 and access via SSH tunnel:"
  echo "    ssh -L ${web_port}:127.0.0.1:${web_port} root@YOUR_VPS_IP"
fi

# ── Check Python venv availability ──────────────────────────────────────────

if [[ ! -d ".venv" ]]; then
  echo "Checking Python venv support..."
  tmp_venv="$(mktemp -d)"
  if ! python3 -m venv "$tmp_venv/test-venv" >/tmp/nanobk-web-venv-check.log 2>&1; then
    echo ""
    echo "ERROR: Python venv is not available."
    echo ""
    if [[ -f /etc/os-release ]]; then
      os_id=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
      case "$os_id" in
        ubuntu|debian|pop|linuxmint)
          echo "On Ubuntu/Debian, install it with:"
          echo "  sudo apt update"
          echo "  sudo apt install -y python3-venv"
          echo ""
          echo "If your Python version is pinned, you may need:"
          pyver=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "X.Y")
          echo "  sudo apt install -y python${pyver}-venv"
          ;;
        rocky|almalinux|centos|rhel|fedora)
          echo "On RHEL/Fedora, install it with:"
          echo "  sudo dnf install -y python3-venv"
          ;;
        *)
          echo "Please install the Python venv package for your OS."
          ;;
      esac
    else
      echo "Please install the Python venv package for your OS."
    fi
    echo ""
    echo "Error log: /tmp/nanobk-web-venv-check.log"
    rm -rf "$tmp_venv"
    exit 1
  fi
  rm -rf "$tmp_venv"
  echo "Python venv support: OK"
fi

# ── Setup and run ───────────────────────────────────────────────────────────

echo "Setting up Python venv..."
python3 -m venv .venv
source .venv/bin/activate

echo "Installing dependencies..."
pip install -q -r requirements.txt

echo "Starting NanoBK Web Panel on ${web_host}:${web_port} (local-only)"
exec python3 app.py
