#!/usr/bin/env bash
# v2.5.11 Closeout Manifest Test
#
# Validates the v2.5 closeout manifest and v2.5 production CLI readiness layer.
# No real deployment. No DNS mutation. No certificate request.
# No token rotation. No protocol key rotation. No Worker mutation.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NANOBK="$REPO_DIR/bin/nanobk"
MANIFEST="$REPO_DIR/docs/v2.5-closeout-manifest.md"
CHANGELOG="$REPO_DIR/CHANGELOG.md"

PASS=0
FAIL=0
NOTE_COUNT=0

ok()   { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }
note() { echo "NOTE: $1"; NOTE_COUNT=$((NOTE_COUNT + 1)); }

check_file_exists() {
  local num="$1" label="$2" filepath="$3"
  if [[ -f "$filepath" ]]; then
    ok "$num: $label"
  else
    fail "$num: $label — file not found: $filepath"
  fi
}

check_file_contains() {
  local num="$1" label="$2" filepath="$3" pattern="$4"
  if grep -qi "$pattern" "$filepath" 2>/dev/null; then
    ok "$num: $label"
  else
    fail "$num: $label — pattern '$pattern' not found in $filepath"
  fi
}

check_command_json() {
  local num="$1" label="$2" cmd="$3"
  local json
  json=$($cmd 2>&1) || true
  if echo "$json" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    ok "$num: $label — valid JSON"
  else
    fail "$num: $label — invalid JSON"
  fi
}

check_command_contains() {
  local num="$1" label="$2" cmd="$3" pattern="$4"
  local output
  output=$($cmd 2>&1) || true
  if echo "$output" | grep -qi "$pattern"; then
    ok "$num: $label"
  else
    fail "$num: $label — pattern '$pattern' not found"
  fi
}

check_no_secret() {
  local num="$1" label="$2" text="$3" pattern="$4"
  if echo "$text" | grep -qi "$pattern"; then
    fail "$num: $label — found '$pattern'"
  else
    ok "$num: $label"
  fi
}

# Use temp HOME to avoid interfering with real profile
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

echo "=== v2.5.11 Closeout Manifest Test ==="
echo ""

# ── 1. Manifest exists ─────────────────────────────────────────────────────

check_file_exists "1" "docs/v2.5-closeout-manifest.md exists" "$MANIFEST"

# ── 2. CHANGELOG has v2.5 closeout entry ───────────────────────────────────

check_file_contains "2" "CHANGELOG has v2.5 closeout entry" "$CHANGELOG" "v2.5 Closeout"

# ── 3. Manifest mentions all v2.5 command names ────────────────────────────

COMMANDS=(
  "setup production"
  "setup production actions"
  "setup production dns"
  "setup production worker"
  "setup production cert"
  "setup production rotate"
  "setup production overview"
  "setup production next"
  "setup production preflight"
  "setup production deploy-plan"
  "setup production gates"
  "beginner production"
  "beginner gate dns"
  "beginner gate cert"
  "beginner gate token"
)

for i in "${!COMMANDS[@]}"; do
  num=$((3 + i))
  check_file_contains "$num" "manifest mentions '${COMMANDS[$i]}'" "$MANIFEST" "${COMMANDS[$i]}"
done

# ── 4. Manifest mentions all exact phrases ──────────────────────────────────

check_file_contains "18" "manifest mentions DNS exact phrase" "$MANIFEST" "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"
check_file_contains "19" "manifest mentions cert exact phrase" "$MANIFEST" "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"
check_file_contains "20" "manifest mentions token exact phrase" "$MANIFEST" "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"

# ── 5. Manifest safety contract ────────────────────────────────────────────

check_file_contains "21" "manifest says no default DNS apply" "$MANIFEST" "No DNS apply by default"
check_file_contains "22" "manifest says no default cert issue" "$MANIFEST" "No cert issue by default"
check_file_contains "23" "manifest says no default token rotate" "$MANIFEST" "No token rotate by default"
check_file_contains "24" "manifest says no default Worker deploy" "$MANIFEST" "No Worker deploy by default"
check_file_contains "25" "manifest says no default service restart" "$MANIFEST" "No service restart"
check_file_contains "26" "manifest mentions NANOBK_RUN_LONG_REGRESSION" "$MANIFEST" "NANOBK_RUN_LONG_REGRESSION"

# ── 7. JSON commands ───────────────────────────────────────────────────────

echo ""
echo "=== JSON commands ==="

check_command_json "27" "setup production overview --json" "$NANOBK setup production overview --json"
check_command_json "28" "setup production next --json" "$NANOBK setup production next --json"
check_command_json "29" "setup production preflight --json" "$NANOBK setup production preflight --json"
check_command_json "30" "setup production deploy-plan --json" "$NANOBK setup production deploy-plan --json"
check_command_json "31" "setup production gates --json" "$NANOBK setup production gates --json"

# ── 8. Gate text contains exact phrases ─────────────────────────────────────

echo ""
echo "=== Gate text checks ==="

check_command_contains "32" "beginner gate cert text has exact phrase" "$NANOBK beginner gate cert" "I UNDERSTAND NANOBK WILL REQUEST TLS CERTIFICATES"
check_command_contains "33" "beginner gate dns text has exact phrase" "$NANOBK beginner gate dns" "I UNDERSTAND NANOBK WILL CREATE CLOUDFLARE DNS RECORDS"
check_command_contains "34" "beginner gate token text has exact phrase" "$NANOBK beginner gate token" "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS"

# ── 9. Hard grep on closeout smoke output ──────────────────────────────────

echo ""
echo "=== Safety grep ==="

SMOKE_OUTPUT=""
for cmd in \
  "setup production overview --json" \
  "setup production next --json" \
  "setup production preflight --json" \
  "setup production deploy-plan --json" \
  "setup production gates --json" \
  "beginner gate cert" \
  "beginner gate dns" \
  "beginner gate token"
do
  SMOKE_OUTPUT+=" $($NANOBK $cmd 2>&1 || true)"
done

check_no_secret "35" "no CF_API_TOKEN in smoke output" "$SMOKE_OUTPUT" "CF_API_TOKEN"
check_no_secret "36" "no ADMIN_TOKEN in smoke output" "$SMOKE_OUTPUT" "ADMIN_TOKEN"
check_no_secret "37" "no SUB_TOKEN in smoke output" "$SMOKE_OUTPUT" "SUB_TOKEN"
check_no_secret "38" "no PRIVATE KEY in smoke output" "$SMOKE_OUTPUT" "PRIVATE KEY"
check_no_secret "39" "no subscription URL in smoke output" "$SMOKE_OUTPUT" "subscription.*http"
check_no_secret "40" "no zone_id in smoke output" "$SMOKE_OUTPUT" "zone_id"
check_no_secret "41" "no record_id in smoke output" "$SMOKE_OUTPUT" "record_id"
check_no_secret "42" "no api_env_path in smoke output" "$SMOKE_OUTPUT" "api_env_path"
check_no_secret "43" "no raw Cloudflare response in smoke output" "$SMOKE_OUTPUT" "raw Cloudflare"

# ── 10. Source safety ──────────────────────────────────────────────────────

echo ""
echo "=== Source safety ==="

# Check the closeout script itself doesn't have dangerous execution patterns
# Only check actual command invocations, not grep patterns or comments
DANGEROUS_CMDS="curl |wrangler |certbot |systemctl restart|systemctl reload"
if grep -v "^#" "$0" | grep -v "grep\|pattern\|DANGEROUS_CMDS" | grep -qiE "$DANGEROUS_CMDS"; then
  fail "44: closeout script has dangerous patterns"
else
  ok "44: closeout script has no dangerous patterns"
fi

# ── Summary ────────────────────────────────────────────────────────────────

echo ""
echo "=============================="
echo "Results: $PASS passed, $FAIL failed, $NOTE_COUNT notes"
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
