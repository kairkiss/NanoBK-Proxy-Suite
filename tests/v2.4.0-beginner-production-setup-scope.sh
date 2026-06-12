#!/usr/bin/env bash
# v2.4.0 Beginner Production Setup UX Scope Test
#
# Static checks only. No real Cloudflare calls. No DNS mutation.
# No certificate request. No token rotation. No Worker mutation.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

DOC="docs/v2.4-beginner-production-setup-ux.md"

# 1. Document exists
if [[ -f "$DOC" ]]; then
  ok "docs/v2.4-beginner-production-setup-ux.md exists"
else
  fail "docs/v2.4-beginner-production-setup-ux.md missing"
fi

# 2. Contains "Built on v2.3 CLI Automation Gate"
if grep -q "Built on v2.3 CLI Automation Gate" "$DOC" 2>/dev/null; then
  ok "Contains 'Built on v2.3 CLI Automation Gate'"
else
  fail "Missing 'Built on v2.3 CLI Automation Gate'"
fi

# 3. Contains "No runtime behavior change"
if grep -qi "no runtime behavior change" "$DOC" 2>/dev/null; then
  ok "Contains 'No runtime behavior change'"
else
  fail "Missing 'No runtime behavior change'"
fi

# 4. Contains nanobk
if grep -q "nanobk" "$DOC" 2>/dev/null; then
  ok "Contains nanobk"
else
  fail "Missing nanobk"
fi

# 5. Contains "默认只读"
if grep -q "默认只读" "$DOC" 2>/dev/null; then
  ok "Contains '默认只读'"
else
  fail "Missing '默认只读'"
fi

# 6. Contains "exact confirmation"
if grep -qi "exact confirmation" "$DOC" 2>/dev/null; then
  ok "Contains 'exact confirmation'"
else
  fail "Missing 'exact confirmation'"
fi

# 7. Contains "不创建 DNS"
if grep -q "不创建 DNS" "$DOC" 2>/dev/null; then
  ok "Contains '不创建 DNS'"
else
  fail "Missing '不创建 DNS'"
fi

# 8. Contains "不申请证书"
if grep -q "不申请证书" "$DOC" 2>/dev/null; then
  ok "Contains '不申请证书'"
else
  fail "Missing '不申请证书'"
fi

# 9. Contains "不轮换 token"
if grep -qi "不轮换 token" "$DOC" 2>/dev/null; then
  ok "Contains '不轮换 token'"
else
  fail "Missing '不轮换 token'"
fi

# 10. Contains "不修改 Worker"
if grep -qi "不修改 worker" "$DOC" 2>/dev/null; then
  ok "Contains '不修改 Worker'"
else
  fail "Missing '不修改 Worker'"
fi

# 11. Contains "不 reload/restart"
if grep -qi "不.*reload.*restart\|不自动.*reload\|不自动.*restart" "$DOC" 2>/dev/null; then
  ok "Contains '不 reload/restart'"
else
  fail "Missing '不 reload/restart'"
fi

# 12. Contains "不发布 release/tag"
if grep -qi "不发布.*release.*tag\|不.*release.*tag" "$DOC" 2>/dev/null; then
  ok "Contains '不发布 release/tag'"
else
  fail "Missing '不发布 release/tag'"
fi

# 13. Contains proxy
if grep -q "proxy" "$DOC" 2>/dev/null; then
  ok "Contains proxy"
else
  fail "Missing proxy"
fi

# 14. Contains web
if grep -q "web" "$DOC" 2>/dev/null; then
  ok "Contains web"
else
  fail "Missing web"
fi

# 15. Contains IPv4
if grep -q "IPv4" "$DOC" 2>/dev/null; then
  ok "Contains IPv4"
else
  fail "Missing IPv4"
fi

# 16. Contains IPv6
if grep -q "IPv6" "$DOC" 2>/dev/null; then
  ok "Contains IPv6"
else
  fail "Missing IPv6"
fi

# 17. Contains 子域名冲突
if grep -q "子域名冲突\|冲突.*子域名\|已被占用" "$DOC" 2>/dev/null; then
  ok "Contains 子域名冲突 handling"
else
  fail "Missing 子域名冲突 handling"
fi

# 18. Contains 小白语言
if grep -q "小白" "$DOC" 2>/dev/null; then
  ok "Contains 小白 language"
else
  fail "Missing 小白 language"
fi

# 19. Contains "Cloudflare Zone -> 你的域名"
if grep -q "Cloudflare Zone.*你的域名\|Cloudflare Zone.*->.*你的域名" "$DOC" 2>/dev/null; then
  ok "Contains 'Cloudflare Zone -> 你的域名'"
else
  fail "Missing 'Cloudflare Zone -> 你的域名'"
fi

# 20. Contains "DNS Record -> 域名指向"
if grep -q "DNS Record.*域名指向\|DNS Record.*->.*域名指向" "$DOC" 2>/dev/null; then
  ok "Contains 'DNS Record -> 域名指向'"
else
  fail "Missing 'DNS Record -> 域名指向'"
fi

# 21. Does not contain real token
if grep -qi "CF_API_TOKEN=\|SUB_TOKEN=\|ADMIN_TOKEN=" "$DOC" 2>/dev/null; then
  fail "Document leaks token"
else
  ok "No token leak in document"
fi

# 22. Does not contain private key (actual key content, not safety mentions)
if grep -qi "BEGIN.*PRIVATE KEY\|MIIEvg\|MII" "$DOC" 2>/dev/null; then
  fail "Document leaks private key content"
else
  ok "No private key content in document"
fi

# 23. Does not contain subscription URL (actual URL, not safety mentions)
if grep -qi "https://.*subscription\|http://.*sub.*url" "$DOC" 2>/dev/null; then
  fail "Document leaks subscription URL"
else
  ok "No subscription URL in document"
fi

# 24. Does not contain git tag
if grep -qE "^\s*git tag" "$DOC" 2>/dev/null; then
  fail "Document contains git tag command"
else
  ok "No git tag command in document"
fi

# 25. Does not contain gh release
if grep -qE "^\s*gh release" "$DOC" 2>/dev/null; then
  fail "Document contains gh release command"
else
  ok "No gh release command in document"
fi

# 26. Test script itself does not call dangerous commands
SELF="$0"
# Only match actual command invocations, not grep patterns or comments
DANGEROUS_CALLS=$(grep -nE "^\s*(curl |wrangler |certbot |acme\.sh |systemctl reload|systemctl restart|git tag |gh release )" "$SELF" 2>/dev/null | grep -v '^\s*#' || true)
if [[ -z "$DANGEROUS_CALLS" ]]; then
  ok "Test script has no dangerous command calls"
else
  fail "Test script calls dangerous commands: $DANGEROUS_CALLS"
fi

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.4.0 beginner production setup scope checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
