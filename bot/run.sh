#!/usr/bin/env bash
# NanoBK Telegram Bot — Runner
#
# Sets up Python venv and starts the bot.
#
# Usage:
#   bash bot/run.sh

set -Eeuo pipefail

cd "$(dirname "$0")"

if [[ ! -f ".env" ]]; then
  echo "ERROR: Missing bot/.env"
  echo "Copy .env.example to .env and edit it:"
  echo "  cp .env.example .env"
  echo "  nano .env"
  exit 1
fi

# ── Check Python venv availability ──────────────────────────────────────────

if [[ ! -d ".venv" ]]; then
  echo "Checking Python venv support..."
  tmp_venv="$(mktemp -d)"
  if ! python3 -m venv "$tmp_venv/test-venv" >/tmp/nanobk-venv-check.log 2>&1; then
    echo ""
    echo "ERROR: Python venv is not available."
    echo ""
    # Detect OS for package hint
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
    echo "Error log: /tmp/nanobk-venv-check.log"
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

echo "Starting NanoBK Bot..."
exec python3 nanobk_bot.py
