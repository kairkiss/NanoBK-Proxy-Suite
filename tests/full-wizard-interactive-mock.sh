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

# Resolve timeout binary (macOS may have gtimeout via coreutils)
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
else
  TIMEOUT_BIN=""
fi

echo "=== Full Wizard Interactive Mock Test ==="
echo ""
echo "Running dynamic Python mock test..."
echo ""

MOCK_TIMEOUT="${NANOBK_MOCK_TEST_TIMEOUT:-240}"

if [[ -n "$TIMEOUT_BIN" ]]; then
  $TIMEOUT_BIN "${MOCK_TIMEOUT}s" python3 "$PYTHON_TEST"
  rc=$?
  if [[ $rc -eq 124 ]]; then
    echo ""
    echo "[TIMEOUT] Python mock test exceeded ${MOCK_TIMEOUT}s hard timeout."
    echo "  This likely means an installer subprocess hung waiting for input."
    echo "  Check per-test timeout diagnostics in Python output above."
    exit 1
  fi
  exit $rc
else
  echo "[WARN] timeout/gtimeout not found; relying on Python per-test timeouts (180s each)."
  python3 "$PYTHON_TEST"
fi
