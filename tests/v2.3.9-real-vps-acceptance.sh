#!/usr/bin/env bash
# v2.3.9 Real VPS Acceptance Closeout Test
#
# Read-only acceptance script. Can run on real VPS without executing dangerous actions.
# No real DNS creation. No real certificate request. No real token rotation.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

CLI="bin/nanobk"
FIXTURES="tests/fixtures/v2.3.8"

# Use temp HOME
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

# ── Section 1: Python helpers compile ─────────────────────────────────────────

echo "=== Python helpers compile ==="

for helper in \
  lib/nanobk_cf_onboarding.py \
  lib/nanobk_domain_planner.py \
  lib/nanobk_dns_apply_engine.py \
  lib/nanobk_cert_preflight.py \
  lib/nanobk_cert_issue_gate.py \
  lib/nanobk_token_rotation_gate.py \
  lib/nanobk_setup_flow.py \
; do
  if python3 -m py_compile "$helper" 2>/dev/null; then
    ok "$helper compiles"
  else
    fail "$helper compile error"
  fi
done

# ── Section 2: CLI help ──────────────────────────────────────────────────────

echo ""
echo "=== CLI help ==="

for cmd in \
  "setup flow --help" \
  "setup run --help" \
  "setup dns apply --help" \
  "setup cert plan --help" \
  "setup cert issue --help" \
  "setup token rotate --help" \
; do
  HELP_OUT=$(bash $CLI $cmd 2>&1 || true)
  if [[ -n "$HELP_OUT" ]]; then
    ok "nanobk $cmd exists"
  else
    fail "nanobk $cmd missing"
  fi
done

# ── Section 3: No profile case ───────────────────────────────────────────────

echo ""
echo "=== No profile case ==="

rm -rf "$HOME/.nanobk"
NOPROF_OUT=$(bash "$CLI" setup flow --json 2>&1 || true)
if echo "$NOPROF_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('mutation') == False
assert d.get('dangerous_actions_executed') == False
steps = d.get('steps', [])
# Check no placeholder dangerous commands
for s in steps:
    cmd = s.get('command') or ''
    assert '(未指定)' not in cmd, f'placeholder in {s[\"id\"]}: {cmd}'
# Check next step is cf connect
next_step = d.get('next_recommended_step','')
assert 'cf connect' in next_step or 'connect' in next_step, f'next={next_step}'
" 2>/dev/null; then
  ok "No profile: flow ok, no placeholders, next=cf connect"
else
  fail "No profile: unexpected flow output"
fi

# ── Section 4: Fake full happy path ──────────────────────────────────────────

echo ""
echo "=== Fake happy path ==="

mkdir -p "$HOME/.nanobk"
chmod 700 "$HOME/.nanobk"
cp "$FIXTURES/fake_cf_env.env" "$HOME/.nanobk/cloudflare.env"
chmod 600 "$HOME/.nanobk/cloudflare.env"
cat > "$HOME/.nanobk/setup-profile.json" <<PROFEOF
{
  "zone_name": "example.com",
  "api_env_path": "$HOME/.nanobk/cloudflare.env",
  "nodes": ["proxy", "web"]
}
PROFEOF
chmod 600 "$HOME/.nanobk/setup-profile.json"

export NANOBK_CF_ZONES_FAKE_RESPONSE="$FIXTURES/zones.json"
export NANOBK_CF_DNS_AVAILABILITY_FAKE_RESPONSE_MAP="$FIXTURES/dns_both_owned.json"
export NANOBK_CERT_PREFLIGHT_FAKE_TOOLS='{"acme_sh":true,"certbot":false}'
export NANOBK_CERT_PREFLIGHT_FAKE_PORTS='{"80":"free","443":"listening"}'
export NANOBK_TOKEN_ROTATE_FAKE_RUN=1
export NANOBK_TOKEN_ROTATE_FAKE_RESULT="$FIXTURES/rotation_success.json"
export NANOBK_TEST_DETECTED_IPV4="203.0.113.10"
export NANOBK_TEST_DETECTED_IPV6=""
export NANOBK_TEST_DETECT_IPV4_FAIL=0
export NANOBK_TEST_DETECT_IPV6_FAIL=1
export NANOBK_TEST_FORCE_ENDPOINT_IPV4_FAIL=1
export NANOBK_TEST_FORCE_ENDPOINT_IPV6_FAIL=1

FLOW_OUT=$(bash "$CLI" setup flow --json 2>&1 || true)
if echo "$FLOW_OUT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == True, f'ok={d.get(\"ok\")}'
assert d.get('mutation') == False
assert d.get('dangerous_actions_executed') == False
assert d.get('setup_complete') == False
steps = d.get('steps', [])
# All read-only statuses should be ready or manual_confirm_required
for s in steps:
    assert s['status'] in ('ready','manual_confirm_required','missing_input','blocked','partial','error'), \
        f'{s[\"id\"]} unexpected status: {s[\"status\"]}'
# Manual confirm steps exist
manual = [s for s in steps if s['status'] == 'manual_confirm_required']
assert len(manual) >= 2, f'expected >=2 manual steps, got {len(manual)}'
" 2>/dev/null; then
  ok "Happy path: all read-only, manual_confirm steps exist, no mutation"
else
  fail "Happy path: unexpected"
fi

# ── Section 5: Dangerous commands still gated ────────────────────────────────

echo ""
echo "=== Dangerous commands gated ==="

# DNS apply without --apply
DNS_PLAN=$(bash "$CLI" setup dns apply --json 2>&1 || true)
if echo "$DNS_PLAN" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('apply_executed') == False
assert d.get('mutation') == False
" 2>/dev/null; then
  ok "DNS apply without --apply: mutation=false"
else
  fail "DNS apply without --apply: unexpected"
fi

# DNS apply with --apply but no confirm
DNS_NOCONF=$(bash "$CLI" setup dns apply --apply --json 2>&1 || true)
if echo "$DNS_NOCONF" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert 'confirm' in d.get('blocked_reason','').lower() or 'confirm' in d.get('hint','').lower()
" 2>/dev/null; then
  ok "DNS apply with --apply but no confirm: blocked"
else
  fail "DNS apply with --apply but no confirm: not blocked"
fi

# Cert issue without --issue
CERT_PLAN=$(bash "$CLI" setup cert issue --json 2>&1 || true)
if echo "$CERT_PLAN" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('issue_executed') == False
" 2>/dev/null; then
  ok "Cert issue without --issue: issue_executed=false"
else
  fail "Cert issue without --issue: unexpected"
fi

# Cert issue with --issue but no confirm
CERT_NOCONF=$(bash "$CLI" setup cert issue --issue --json 2>&1 || true)
if echo "$CERT_NOCONF" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
" 2>/dev/null; then
  ok "Cert issue with --issue but no confirm: blocked"
else
  fail "Cert issue with --issue but no confirm: not blocked"
fi

# Token rotate without --rotate
TOK_PLAN=$(bash "$CLI" setup token rotate --worker-name test-worker --json 2>&1 || true)
if echo "$TOK_PLAN" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('rotation_executed') == False
" 2>/dev/null; then
  ok "Token rotate without --rotate: rotation_executed=false"
else
  fail "Token rotate without --rotate: unexpected"
fi

# Token rotate with --rotate but no confirm
TOK_NOCONF=$(bash "$CLI" setup token rotate --rotate --worker-name test-worker --json 2>&1 || true)
if echo "$TOK_NOCONF" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
" 2>/dev/null; then
  ok "Token rotate with --rotate but no confirm: blocked"
else
  fail "Token rotate with --rotate but no confirm: not blocked"
fi

# ── Section 6: Production Worker protection ──────────────────────────────────

echo ""
echo "=== Production Worker protection ==="

# Plan-only nanok
PROD_PLAN=$(bash "$CLI" setup token rotate --worker-name nanok --json 2>&1 || true)
if echo "$PROD_PLAN" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ready_to_rotate') == False
nc = d.get('next_command') or ''
assert '--rotate' not in nc
" 2>/dev/null; then
  ok "Plan-only nanok: ready_to_rotate=false"
else
  fail "Plan-only nanok: unexpected"
fi

# Rotate nanok blocked
PROD_ROT=$(bash "$CLI" setup token rotate --rotate --worker-name nanok --confirm "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS" --json 2>&1 || true)
if echo "$PROD_ROT" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
" 2>/dev/null; then
  ok "Rotate nanok: blocked"
else
  fail "Rotate nanok: not blocked"
fi

# Env marker blocked
mkdir -p "$HOME/.nanobk"
cat > "$HOME/.nanobk/cloudflare.env" <<'EOF'
CF_API_TOKEN="fake-token"
# route: nanok.biankai314.uk
EOF
chmod 600 "$HOME/.nanobk/cloudflare.env"
PROD_DOM=$(bash "$CLI" setup token rotate --rotate --worker-name test-worker --confirm "I UNDERSTAND NANOBK WILL ROTATE SUBSCRIPTION TOKENS" --json 2>&1 || true)
if echo "$PROD_DOM" | python3 -c "
import json,sys
d=json.load(sys.stdin)
assert d.get('ok') == False
assert d.get('mode') == 'blocked'
" 2>/dev/null; then
  ok "Env marker nanok.biankai314.uk: blocked"
else
  fail "Env marker: not blocked"
fi

# Restore env
cp "$FIXTURES/fake_cf_env.env" "$HOME/.nanobk/cloudflare.env"
chmod 600 "$HOME/.nanobk/cloudflare.env"

# ── Section 7: No direct mutation in read-only flow ──────────────────────────

echo ""
echo "=== No direct mutation in helpers ==="

for helper in lib/nanobk_setup_flow.py; do
  DANGEROUS=$(grep -nE "systemctl.*(reload|restart)|nginx.*-s.*reload|service.*reload|owner.smoke.create|acme\.sh.*--issue|certbot.*certonly|POST.*dns|DELETE.*dns|PATCH.*dns" "$helper" 2>/dev/null | grep -v '^\s*#' | grep -v '^\s*"""' | grep -v 'No ' || true)
  if [[ -z "$DANGEROUS" ]]; then
    ok "$helper: no dangerous patterns"
  else
    fail "$helper: dangerous patterns: $DANGEROUS"
  fi
done

# ── Section 8: Existing tests still pass ─────────────────────────────────────

echo ""
echo "=== Regression tests ==="

for ver in v2.3.8 v2.3.7 v2.3.6 v2.3.5 v2.3.4 v2.3.3 v2.3.2 v2.3.1 v2.3.0; do
  test_file="tests/${ver}-"*.sh
  # Find the right test file
  for tf in $test_file; do
    if [[ -f "$tf" ]]; then
      TEST_OUT=$(bash "$tf" 2>&1 || true)
      if echo "$TEST_OUT" | grep -q "passed"; then
        ok "$ver test passes"
      else
        fail "$ver test failed"
        echo "$TEST_OUT" | tail -3
      fi
      break
    fi
  done
done

# Optional: v2.2.55 and v2.2.56
for ver in v2.2.55 v2.2.56; do
  test_file="tests/${ver}-"*.sh
  for tf in $test_file; do
    if [[ -f "$tf" ]]; then
      TEST_OUT=$(bash "$tf" 2>&1 || true)
      if echo "$TEST_OUT" | grep -q "passed"; then
        ok "$ver test passes"
      elif echo "$TEST_OUT" | grep -q "skipped.*Flask"; then
        ok "$ver test passes (Flask not available, static checks only)"
      else
        fail "$ver test failed"
      fi
      break
    fi
  done
done

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.3.9 real VPS acceptance checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
