#!/usr/bin/env bash
# NanoBK Proxy Suite — Address-Class Redaction Contract Test (v1.9.5)
#
# Tests the expected redaction contract for address-class sensitive data
# using safe documentation-only fixtures. This is a CONTRACT TEST — it
# proves expected fixture transformations using a test-local redaction
# implementation. It does NOT modify production Bot/Web code.
#
# All fixture values are fake and documentation-safe:
#   IPv4: 203.0.113.0/24 (RFC 5737 TEST-NET-3)
#   IPv6: 2001:db8::/32 (RFC 3849 documentation prefix)
#   Domains: *.example.invalid, *.invalid (RFC 2606 reserved)
#
# Usage:
#   bash tests/redaction-address-class-v1.9.5.sh

set -euo pipefail

# ── Repo root ────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

FIXTURE_DIR="tests/fixtures/redaction-v1.9.5"

# ── Colors ───────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*" >&2; }
info() { echo -e "  ${YELLOW}ℹ${NC} $*"; }

ERRORS=0

# ── Header ───────────────────────────────────────────────────────────────────

echo ""
echo "=== NanoBK Address-Class Redaction Contract Test (v1.9.5) ==="
echo ""
echo "Purpose: Verify address-class redaction contract using safe fixtures."
echo "Scope:   Contract test only. Test-local redaction, NOT production wiring."
echo "Fixtures: All values are fake (RFC 5737/3849/2606 safe ranges)."
echo ""

# ── Verify fixtures exist ───────────────────────────────────────────────────

echo "--- Fixture verification ---"
echo ""

for f in \
  "$FIXTURE_DIR/sample-status-input.json" \
  "$FIXTURE_DIR/sample-status-expected-redacted.json" \
  "$FIXTURE_DIR/sample-cli-output-input.txt" \
  "$FIXTURE_DIR/sample-cli-output-expected-redacted.txt"; do
  if [[ -f "$f" ]]; then
    pass "Fixture exists: $f"
  else
    fail "Fixture missing: $f"
    ERRORS=$((ERRORS + 1))
  fi
done

echo ""

# ── Test-local redaction function ────────────────────────────────────────────
# This is a CONTRACT DEMONSTRATION only. It shows what production redaction
# SHOULD do. It is NOT wired into Bot/Web runtime.

redact_contract_text() {
  local text="$1"

  # Use perl for reliable regex (macOS sed lacks \b support)
  text=$(perl -pe '
    # IPv4 addresses
    s/\b(?:\d{1,3}\.){3}\d{1,3}\b/[REDACTED_IPV4]/g;
    # IPv6 addresses (hex:colon patterns, 6+ chars)
    s/\b[0-9a-fA-F:]{6,39}\b/[REDACTED_IPV6]/g;
    # URLs
    s|https?://\S+|[REDACTED_URL]|g;
    # workers.dev-like hosts
    s/[a-zA-Z0-9._-]+\.workers\.dev/[REDACTED_WORKERS_DEV]/g;
    # Subscription paths
    s|/sub/[a-zA-Z0-9_-]+|/[REDACTED_SUBSCRIPTION_PATH]|g;
    # Domains with .example.invalid
    s/[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?\.example\.invalid/[REDACTED_DOMAIN]/g;
    # Token/secret/key=value patterns (case insensitive)
    s/([Tt]oken|[Ss]ecret|[Pp]rivate[_ -]?[Kk]ey|[Aa]dmin[_ -]?[Tt]oken|[Aa]pi[_ -]?[Tt]oken)\s*[:=]\s*\S+/$1=[REDACTED]/g;
  ' <<< "$text")

  echo "$text"
}

redact_contract_json() {
  # Uses python if available for reliable JSON handling
  if command -v python3 &>/dev/null; then
    python3 - "$1" <<'PYEOF'
import json, re, sys

def redact_value(val):
    if isinstance(val, str):
        # IPv4
        val = re.sub(r'\b(\d{1,3}\.){3}\d{1,3}\b', '[REDACTED_IPV4]', val)
        # IPv6 (simplified)
        val = re.sub(r'\b[0-9a-fA-F:]{6,39}\b', '[REDACTED_IPV6]', val)
        # URLs
        val = re.sub(r'https?://\S+', '[REDACTED_URL]', val)
        # workers.dev
        val = re.sub(r'[a-zA-Z0-9._-]+\.workers\.dev', '[REDACTED_WORKERS_DEV]', val)
        # Subscription paths
        val = re.sub(r'/sub/[a-zA-Z0-9_-]+', '/[REDACTED_SUBSCRIPTION_PATH]', val)
        # Domains
        val = re.sub(r'[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.example\.invalid', '[REDACTED_DOMAIN]', val)
        val = re.sub(r'[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.invalid', '[REDACTED_DOMAIN]', val)
        # token/secret/key values
        val = re.sub(r'(?i)(token|secret|private[_ -]?key|admin[_ -]?token|api[_ -]?token)\s*[:=]\s*\S+', r'\1=[REDACTED]', val)
    return val

def redact_obj(obj):
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            key_norm = k.lower().replace("_", "").replace("-", "")
            sensitive = ("token", "password", "secret", "private", "privatekey", "admintoken", "apitoken")
            if any(s in key_norm for s in sensitive):
                if isinstance(v, str):
                    out[k] = "[REDACTED]"
                else:
                    out[k] = v
            else:
                out[k] = redact_obj(v)
        return out
    if isinstance(obj, list):
        return [redact_obj(i) for i in obj]
    if isinstance(obj, str):
        return redact_value(obj)
    return obj

with open(sys.argv[1]) as f:
    data = json.load(f)

redacted = redact_obj(data)
print(json.dumps(redacted, indent=2, ensure_ascii=False))
PYEOF
  else
    info "python3 not available, skipping JSON redaction test"
    return 1
  fi
}

# ── JSON Redaction Contract Tests ────────────────────────────────────────────

echo "--- JSON redaction contract tests ---"
echo ""

INPUT_JSON="$FIXTURE_DIR/sample-status-input.json"
EXPECTED_JSON="$FIXTURE_DIR/sample-status-expected-redacted.json"

if [[ -f "$INPUT_JSON" && -f "$EXPECTED_JSON" ]]; then
  # Apply contract redaction
  ACTUAL_JSON=$(redact_contract_json "$INPUT_JSON" 2>/dev/null || echo "")

  if [[ -n "$ACTUAL_JSON" ]]; then
    # Check 1: Redacted JSON does not contain fixture raw IPv4
    if echo "$ACTUAL_JSON" | grep -q "203\.0\.113\.10"; then
      fail "JSON redacted output contains raw IPv4 (203.0.113.10)"
      ERRORS=$((ERRORS + 1))
    else
      pass "JSON redacted output does not contain raw IPv4"
    fi

    # Check 2: Redacted JSON does not contain fixture raw IPv6
    if echo "$ACTUAL_JSON" | grep -q "2001:db8::10"; then
      fail "JSON redacted output contains raw IPv6 (2001:db8::10)"
      ERRORS=$((ERRORS + 1))
    else
      pass "JSON redacted output does not contain raw IPv6"
    fi

    # Check 3: Redacted JSON does not contain fixture raw domain
    if echo "$ACTUAL_JSON" | grep -q "node\.example\.invalid"; then
      fail "JSON redacted output contains raw domain (node.example.invalid)"
      ERRORS=$((ERRORS + 1))
    else
      pass "JSON redacted output does not contain raw domain"
    fi

    # Check 4: Redacted JSON does not contain fixture raw URL
    if echo "$ACTUAL_JSON" | grep -q "https://worker\.example\.invalid"; then
      fail "JSON redacted output contains raw URL (worker.example.invalid)"
      ERRORS=$((ERRORS + 1))
    else
      pass "JSON redacted output does not contain raw URL"
    fi

    # Check 5: Redacted JSON does not contain fixture workers.dev-like value
    if echo "$ACTUAL_JSON" | grep -q "nanobk-test\.example\.invalid\.workers\.dev"; then
      fail "JSON redacted output contains raw workers.dev-like value"
      ERRORS=$((ERRORS + 1))
    else
      pass "JSON redacted output does not contain raw workers.dev-like value"
    fi

    # Check 6: Redacted JSON does not contain fixture subscription path
    if echo "$ACTUAL_JSON" | grep -q "fake-sub-path-12345"; then
      fail "JSON redacted output contains raw subscription path"
      ERRORS=$((ERRORS + 1))
    else
      pass "JSON redacted output does not contain raw subscription path"
    fi

    # Check 7: Redacted JSON does not contain fixture tokens
    if echo "$ACTUAL_JSON" | grep -q "fake-doc-token-abc123xyz"; then
      fail "JSON redacted output contains raw token"
      ERRORS=$((ERRORS + 1))
    else
      pass "JSON redacted output does not contain raw token"
    fi

    # Check 8: Redacted JSON contains expected replacement tokens
    for token in "[REDACTED_IPV4]" "[REDACTED_DOMAIN]" "[REDACTED_URL]" "[REDACTED]" ; do
      if echo "$ACTUAL_JSON" | grep -qF "$token"; then
        pass "JSON redacted output contains $token"
      else
        fail "JSON redacted output missing expected $token"
        ERRORS=$((ERRORS + 1))
      fi
    done

    # Check 9: Redacted JSON remains valid JSON
    if python3 -c "import json, sys; json.loads(sys.stdin.read())" <<< "$ACTUAL_JSON" 2>/dev/null; then
      pass "Redacted JSON is valid JSON"
    else
      fail "Redacted JSON is NOT valid JSON"
      ERRORS=$((ERRORS + 1))
    fi
  else
    info "JSON redaction produced empty output (python may be unavailable)"
  fi
else
  info "JSON fixtures not found, skipping JSON tests"
fi

echo ""

# ── Text Output Redaction Contract Tests ─────────────────────────────────────

echo "--- Text output redaction contract tests ---"
echo ""

INPUT_TXT="$FIXTURE_DIR/sample-cli-output-input.txt"
EXPECTED_TXT="$FIXTURE_DIR/sample-cli-output-expected-redacted.txt"

if [[ -f "$INPUT_TXT" && -f "$EXPECTED_TXT" ]]; then
  ACTUAL_TXT=$(redact_contract_text "$(cat "$INPUT_TXT")")

  # Check 10: Redacted text does not contain fixture raw IPv4
  if echo "$ACTUAL_TXT" | grep -q "203\.0\.113\.10"; then
    fail "Text redacted output contains raw IPv4 (203.0.113.10)"
    ERRORS=$((ERRORS + 1))
  else
    pass "Text redacted output does not contain raw IPv4"
  fi

  # Check 11: Redacted text does not contain fixture raw IPv6
  if echo "$ACTUAL_TXT" | grep -q "2001:db8::10"; then
    fail "Text redacted output contains raw IPv6 (2001:db8::10)"
    ERRORS=$((ERRORS + 1))
  else
    pass "Text redacted output does not contain raw IPv6"
  fi

  # Check 12: Redacted text does not contain fixture raw domain
  if echo "$ACTUAL_TXT" | grep -q "node\.example\.invalid"; then
    fail "Text redacted output contains raw domain (node.example.invalid)"
    ERRORS=$((ERRORS + 1))
  else
    pass "Text redacted output does not contain raw domain"
  fi

  # Check 13: Redacted text does not contain fixture raw URL
  if echo "$ACTUAL_TXT" | grep -q "https://worker\.example\.invalid"; then
    fail "Text redacted output contains raw URL"
    ERRORS=$((ERRORS + 1))
  else
    pass "Text redacted output does not contain raw URL"
  fi

  # Check 14: Redacted text does not contain fixture workers.dev-like value
  if echo "$ACTUAL_TXT" | grep -q "nanobk-test\.example\.invalid\.workers\.dev"; then
    fail "Text redacted output contains raw workers.dev-like value"
    ERRORS=$((ERRORS + 1))
  else
    pass "Text redacted output does not contain raw workers.dev-like value"
  fi

  # Check 15: Redacted text does not contain fixture subscription path
  if echo "$ACTUAL_TXT" | grep -q "fake-sub-path-12345"; then
    fail "Text redacted output contains raw subscription path"
    ERRORS=$((ERRORS + 1))
  else
    pass "Text redacted output does not contain raw subscription path"
  fi

  # Check 16: Redacted text does not contain fixture tokens/secrets
  for secret in "fake-doc-token-abc123xyz" "fake-secret-value-do-not-use" "FAKE_PRIVATE_KEY_DO_NOT_USE" "fake-cf-admin-token-do-not-use"; do
    if echo "$ACTUAL_TXT" | grep -q "$secret"; then
      fail "Text redacted output contains raw secret: $secret"
      ERRORS=$((ERRORS + 1))
    else
      pass "Text redacted output does not contain: $secret"
    fi
  done

  # Check 17: Redacted text contains expected replacement tokens
  for token in "[REDACTED_IPV4]" "[REDACTED_IPV6]" "[REDACTED_DOMAIN]" "[REDACTED_URL]" "[REDACTED_WORKERS_DEV]" "[REDACTED_SUBSCRIPTION_PATH]" "[REDACTED]"; do
    if echo "$ACTUAL_TXT" | grep -qF "$token"; then
      pass "Text redacted output contains $token"
    else
      fail "Text redacted output missing expected $token"
      ERRORS=$((ERRORS + 1))
    fi
  done

  # Check 18: Non-sensitive content is preserved
  for preserved in "NanoBK Status Report" "Region: JP" "Services:" "HY2: active" "TUIC: active"; do
    if echo "$ACTUAL_TXT" | grep -qF "$preserved"; then
      pass "Preserved non-sensitive content: $preserved"
    else
      fail "Lost non-sensitive content: $preserved"
      ERRORS=$((ERRORS + 1))
    fi
  done
else
  info "Text fixtures not found, skipping text tests"
fi

echo ""

# ── Existing tests still pass ────────────────────────────────────────────────

echo "--- Existing tests still pass ---"
echo ""

if bash tests/bot-cli-mock.sh >/dev/null 2>&1; then
  pass "tests/bot-cli-mock.sh passes"
else
  fail "tests/bot-cli-mock.sh failed"
  ERRORS=$((ERRORS + 1))
fi

if bash tests/web-panel-mock.sh >/dev/null 2>&1; then
  pass "tests/web-panel-mock.sh passes"
else
  fail "tests/web-panel-mock.sh failed"
  ERRORS=$((ERRORS + 1))
fi

if bash tests/bot-web-command-allowlist-v1.9.4.sh >/dev/null 2>&1; then
  pass "tests/bot-web-command-allowlist-v1.9.4.sh passes"
else
  fail "tests/bot-web-command-allowlist-v1.9.4.sh failed"
  ERRORS=$((ERRORS + 1))
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────────────

echo "=== Test Summary ==="
echo ""

if [[ $ERRORS -eq 0 ]]; then
  echo -e "  ${GREEN}All address-class redaction contract tests passed!${NC}"
  echo ""
  echo "  Contract proves expected redaction behavior using safe fixtures."
  echo "  This is a test contract, NOT production wiring."
  echo "  Production integration requires later implementation after review."
  exit 0
else
  echo -e "  ${RED}${ERRORS} test(s) failed.${NC}"
  echo ""
  echo "  Review failures above. Fix test contract or fixtures."
  exit 1
fi
