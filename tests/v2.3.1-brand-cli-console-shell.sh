#!/usr/bin/env bash
# v2.3.1 Brand CLI Console Shell Test
#
# Lightweight check that the nanobk CLI has a product-grade console entry.
# No Cloudflare calls, no mutation, no real config.
set -Eeuo pipefail

PASS=0
FAIL=0

ok() { echo "[OK] $1"; PASS=$((PASS + 1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL + 1)); }

CLI="bin/nanobk"
export HOME
HOME=$(mktemp -d)
trap 'rm -rf "$HOME"' EXIT

# 1. bin/nanobk exists and has shebang
if [[ -f "$CLI" ]] && head -1 "$CLI" | grep -q '^#!'; then
  ok "bin/nanobk exists with shebang"
else
  fail "bin/nanobk missing or no shebang"
fi

# 2. TTY console can exit
export NANOBK_TEST_FORCE_TTY=1
TTY_OUT=$(echo "9" | NANOBK_TEST_FORCE_TTY=1 bash "$CLI" 2>/dev/null || true)
if echo "$TTY_OUT" | grep -q "NanoBK"; then
  ok "TTY console runs and produces output"
else
  fail "TTY console did not produce expected output"
fi

# 3. Console output contains NanoBK brand
if echo "$TTY_OUT" | grep -qi "NanoBK"; then
  ok "Console output contains NanoBK brand"
else
  fail "Console output missing NanoBK brand"
fi

# 4. Contains welcome text
if echo "$TTY_OUT" | grep -q "欢迎使用 NanoBK"; then
  ok "Console contains '欢迎使用 NanoBK'"
elif echo "$TTY_OUT" | grep -q "让 VPS 代理部署变简单"; then
  ok "Console contains '让 VPS 代理部署变简单'"
else
  fail "Console missing welcome text"
fi

# 5. First menu item is "开始配置 NanoBK"
if echo "$TTY_OUT" | grep -q "开始配置 NanoBK"; then
  ok "Menu contains '开始配置 NanoBK'"
else
  fail "Menu missing '开始配置 NanoBK'"
fi

# 6. Menu contains "查看当前状态"
if echo "$TTY_OUT" | grep -q "查看当前状态"; then
  ok "Menu contains '查看当前状态'"
else
  fail "Menu missing '查看当前状态'"
fi

# 7. Menu contains Cloudflare or 域名
if echo "$TTY_OUT" | grep -qi "Cloudflare\|域名"; then
  ok "Menu contains Cloudflare/域名 reference"
else
  fail "Menu missing Cloudflare/域名 reference"
fi

# 8. Menu contains 安全 or 密钥
if echo "$TTY_OUT" | grep -q "安全\|密钥"; then
  ok "Menu contains 安全/密钥 reference"
else
  fail "Menu missing 安全/密钥 reference"
fi

# 9. Menu contains 高级命令
if echo "$TTY_OUT" | grep -q "高级命令"; then
  ok "Menu contains '高级命令'"
else
  fail "Menu missing '高级命令'"
fi

# 10. Non-TTY output does not auto-deploy
NONTTY_OUT=$(NANOBK_TEST_FORCE_TTY=0 bash "$CLI" 2>/dev/null || true)
if echo "$NONTTY_OUT" | grep -qi "not started automatically\|不会自动启动\|Deployment is not started"; then
  ok "Non-TTY output states deployment not automatic"
else
  fail "Non-TTY output does not state deployment not automatic"
fi

# 11. Non-TTY contains Chinese or English no-auto-deploy message
if echo "$NONTTY_OUT" | grep -q "不会自动启动\|Deployment is not started automatically"; then
  ok "Non-TTY contains explicit no-auto-deploy message"
else
  fail "Non-TTY missing explicit no-auto-deploy message"
fi

# 12. Output must not leak secrets
ALL_OUT="$TTY_OUT
$NONTTY_OUT"
for leak in "CF_API_TOKEN" "PRIVATE KEY" "api.cloudflare.com/client/v4" "/dns_records" "SUB_TOKEN=" "ADMIN_TOKEN=" "token="; do
  if echo "$ALL_OUT" | grep -q "$leak"; then
    fail "Output leaks: $leak"
  else
    ok "No leak: $leak"
  fi
done

# 13. No owner-smoke-create auto-execution in bin/nanobk
# Check for actual auto-execution (not echo/help/Usage lines)
SMOKE_EXEC=$(grep -n 'owner-smoke-create' "$CLI" 2>/dev/null | grep -v 'echo\|help\|Usage\|cat\|die\|#' | grep 'cmd_cf_dns\|run_script\|bash.*owner-smoke-create' || true)
if [[ -n "$SMOKE_EXEC" ]]; then
  fail "bin/nanobk appears to auto-execute owner-smoke-create"
else
  ok "No owner-smoke-create auto-execution path"
fi

# 14. "开始配置 NanoBK" only calls setup wizard/home/status, not DNS apply
# Check the console_setup_submenu function
if grep -A 30 "console_setup_submenu" "$CLI" | grep -q "cmd_setup_wizard\|cmd_home"; then
  ok "Setup menu calls wizard/home (safe commands)"
else
  fail "Setup menu does not call expected safe commands"
fi
# Verify it does NOT call DNS apply
if grep -A 30 "console_setup_submenu" "$CLI" | grep -q "cmd_cf_dns apply\|cf dns apply"; then
  fail "Setup menu calls DNS apply (not allowed)"
else
  ok "Setup menu does not call DNS apply"
fi

# Summary
echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "All v2.3.1 brand CLI console shell checks passed."
  exit 0
else
  echo "FAILED: ${FAIL} check(s) failed, ${PASS} passed."
  exit 1
fi
