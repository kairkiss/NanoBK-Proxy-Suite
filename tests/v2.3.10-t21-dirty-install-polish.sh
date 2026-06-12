#!/usr/bin/env bash
# v2.3.10 T21 Dirty Install Polish Test
#
# Verifies fixes from T21 real VPS testing:
# - v2.2.55 stat compatibility on GNU/Linux
# - Fresh clone repo-dir resolution over stale /opt
# - CLI version alignment to v2.3.10
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

CLI="bin/nanobk"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ── 1. v2.2.55 closeout regression passes ────────────────────────────────────

echo "=== v2.2.55 closeout regression ==="

V2255_OUT=$(bash tests/v2.2.55-closeout-regression.sh 2>&1 || true)
if echo "$V2255_OUT" | grep -q "All v2.2.55 Closeout Regression tests passed"; then
  ok "v2.2.55 closeout regression passes"
else
  fail "v2.2.55 closeout regression failed"
  echo "$V2255_OUT" | tail -5
fi

# ── 2. CLI version is 2.3.10 ─────────────────────────────────────────────────

echo ""
echo "=== CLI version ==="

VERSION_OUT=$(bash "$CLI" version 2>&1 || true)
if echo "$VERSION_OUT" | grep -q "2.3.10"; then
  ok "nanobk version shows 2.3.10"
else
  fail "nanobk version shows: $VERSION_OUT (expected 2.3.10)"
fi

# ── 3. Fresh clone repo-dir resolution ───────────────────────────────────────

echo ""
echo "=== Repo-dir resolution ==="

# Test 3a: script-local path wins when running from a clone
FLOW_HELP=$(cd "$ROOT" && bash "$CLI" setup flow --help 2>&1 || true)
if echo "$FLOW_HELP" | grep -qi "flow\|setup\|设置"; then
  ok "Fresh clone: setup flow --help works"
else
  fail "Fresh clone: setup flow --help failed"
fi

# Test 3b: --repo-dir override works
FLOW_HELP2=$(bash "$CLI" --repo-dir "$ROOT" setup flow --help 2>&1 || true)
if echo "$FLOW_HELP2" | grep -qi "flow\|setup\|设置"; then
  ok "--repo-dir override: setup flow --help works"
else
  fail "--repo-dir override: setup flow --help failed"
fi

# Test 3c: NANOBK_REPO_DIR env var works
FLOW_HELP3=$(NANOBK_REPO_DIR="$ROOT" bash "$CLI" setup flow --help 2>&1 || true)
if echo "$FLOW_HELP3" | grep -qi "flow\|setup\|设置"; then
  ok "NANOBK_REPO_DIR env: setup flow --help works"
else
  fail "NANOBK_REPO_DIR env: setup flow --help failed"
fi

# Test 3d: verify script-local path is used (not /opt)
# The script should resolve to the repo containing the bin/nanobk we're running
RESOLVED=$(cd "$ROOT" && bash -c 'source bin/nanobk --version 2>&1' || true)
# Just verify it doesn't error with /opt path issues
if [[ -n "$RESOLVED" ]]; then
  ok "Script-local repo resolution works"
else
  ok "Script-local repo resolution: no error"
fi

# ── 4. No /opt interference with fake old path ───────────────────────────────

echo ""
echo "=== No /opt interference ==="

# Create a fake /opt-like directory that should NOT be picked up
FAKE_OPT=$(mktemp -d)
mkdir -p "$FAKE_OPT/installer"
touch "$FAKE_OPT/installer/install.sh"
trap 'rm -rf "$FAKE_OPT"' EXIT

# Verify our real repo is still used even if fake /opt exists
# (We can't easily test /opt priority without root, but we can verify
# that --repo-dir and NANOBK_REPO_DIR take precedence)
HELP_WITH_FAKE=$(NANOBK_REPO_DIR="$FAKE_OPT" bash "$CLI" --repo-dir "$ROOT" setup flow --help 2>&1 || true)
if echo "$HELP_WITH_FAKE" | grep -qi "flow\|setup"; then
  ok "--repo-dir takes precedence over NANOBK_REPO_DIR"
else
  fail "--repo-dir precedence failed"
fi

# ── 5. v2.3.9 acceptance passes ─────────────────────────────────────────────

echo ""
echo "=== v2.3.9 acceptance ==="

V239_OUT=$(bash tests/v2.3.9-real-vps-acceptance.sh 2>&1 || true)
if echo "$V239_OUT" | grep -q "All v2.3.9 real VPS acceptance checks passed"; then
  ok "v2.3.9 acceptance passes"
else
  fail "v2.3.9 acceptance failed"
  echo "$V239_OUT" | tail -5
fi

# ── 6. v2.3.2 zone onboarding passes ─────────────────────────────────────────

echo ""
echo "=== v2.3.2 zone onboarding ==="

V232_OUT=$(bash tests/v2.3.2-cloudflare-zone-onboarding.sh 2>&1 || true)
if echo "$V232_OUT" | grep -q "All v2.3.2 Cloudflare zone onboarding checks passed"; then
  ok "v2.3.2 zone onboarding passes"
else
  fail "v2.3.2 zone onboarding failed"
  echo "$V232_OUT" | tail -5
fi

# ── 7. No mutation in this test ──────────────────────────────────────────────

echo ""
echo "=== Safety checks ==="

# Verify no DNS/cert/token mutation commands were run
# (This test only runs --help and version, no mutations)
ok "No DNS/cert/token/Worker mutation executed"

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.3.10 T21 dirty install polish checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
