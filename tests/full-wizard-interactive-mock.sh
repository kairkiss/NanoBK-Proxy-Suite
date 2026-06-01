#!/usr/bin/env bash
# NanoBK Proxy Suite — Full Wizard Interactive Mock Test
#
# Runs the Python-based dynamic mock test that executes
# installer/install.sh --mode full with real input streams.
#
# Usage:
#   bash tests/full-wizard-interactive-mock.sh

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_TEST="$SCRIPT_DIR/full_wizard_interactive_mock.py"

echo "=== Full Wizard Interactive Mock Test ==="
echo ""
echo "Running dynamic Python mock test..."
echo ""

python3 "$PYTHON_TEST"
