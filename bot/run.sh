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

echo "Setting up Python venv..."
python3 -m venv .venv
source .venv/bin/activate

echo "Installing dependencies..."
pip install -q -r requirements.txt

echo "Starting NanoBK Bot..."
exec python3 nanobk_bot.py
