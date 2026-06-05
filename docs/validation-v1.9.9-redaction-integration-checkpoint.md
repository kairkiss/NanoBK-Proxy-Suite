# v1.9.9 — Redaction Integration Checkpoint / Bot-Web Safety Gate

> 检查点类型：Redaction 集成一致性检查 / 安全门禁
> 日期：2026-06-05
> 基线 commit：`639ef0308616371bfbe3242b2ef414c80d563c8a`
> 基线信息：`fix: integrate web redaction helper`

---

## 1. 本轮目标与结论

**v1.9.9 是检查点 / 安全门禁：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release
- ✅ 目的是判断 redaction 集成是否就绪，作为后续 UX 实现的前置条件

**结论：Bot/Web redaction 集成一致、安全，可作为后续 UX 实现的安全门禁。推荐进入小步 UX 实现规划阶段。**

---

## 2. 当前 Redaction 架构

```
┌─────────────────────────────────────────────────┐
│  lib/nanobk_redaction.py (v1.9.6)               │
│  共享 redaction helper                           │
│  strip_ansi / redact_text / redact_json_obj     │
│  覆盖：IPv4/IPv6/domain/URL/workers.dev/        │
│        subscription path/token/secret/private    │
├────────────────────────┬────────────────────────┤
│  bot/nanobk_bot.py     │  web/app.py            │
│  v1.9.7 集成           │  v1.9.8 集成           │
│  strip_ansi → shared   │  strip_ansi → shared   │
│  redact_text → shared  │  redact_text → shared  │
│                        │  redact_json → shared  │
├────────────────────────┴────────────────────────┤
│  执行安全门禁：v1.9.4 命令白名单 + 静态测试       │
│  显示安全门禁：v1.9.5 地址类 redaction 合约       │
└─────────────────────────────────────────────────┘
```

### 安全门禁链

| 版本 | 门禁 | 状态 |
|------|------|------|
| v1.9.4 | 执行安全（命令白名单） | ✅ 通过 |
| v1.9.5 | 显示安全合约（地址类 redaction） | ✅ 通过 |
| v1.9.6 | 共享 helper 实现 | ✅ 完成 |
| v1.9.7 | Bot redaction 集成 | ✅ 完成 |
| v1.9.8 | Web redaction 集成 | ✅ 完成 |
| v1.9.9 | 一致性检查点 | ✅ 本文件 |

---

## 3. Bot Redaction 路径检查点

| 检查项 | 状态 | 证据 |
|--------|------|------|
| `strip_ansi()` 委托给共享 helper | ✅ | `bot/nanobk_bot.py:125` |
| `redact_text()` 委托给共享 helper | ✅ | `bot/nanobk_bot.py:129` |
| `safe_output()` 仍 strip ANSI + redact + limit | ✅ | `bot/nanobk_bot.py:137-140` |
| `/status` 使用 `format_status()` + `safe_output()` | ✅ | `bot/nanobk_bot.py:395-399` |
| `/status_json` 使用 `safe_output()` | ✅ | `bot/nanobk_bot.py:412` |
| `/doctor` 和 failure 使用 `safe_output()` | ✅ | `bot/nanobk_bot.py:425` |
| 命令执行行为不变 | ✅ | `run_nanobk()` 未修改 |
| Rotate 行为不变 | ✅ | 确认流未修改 |
| 授权行为不变 | ✅ | `is_owner()` 未修改 |
| 无旧本地 `_REDACT_PATTERNS` | ✅ | 源码确认 |
| 无旧本地 `_ANSI_RE` | ✅ | 源码确认 |
| 无 `shell=True` | ✅ | 源码确认 |

---

## 4. Web Redaction 路径检查点

| 检查项 | 状态 | 证据 |
|--------|------|------|
| `strip_ansi()` 委托给共享 helper | ✅ | `web/app.py:141` |
| `redact_text()` 委托给共享 helper | ✅ | `web/app.py:145` |
| `redact_json()` 委托给共享 `redact_json_obj` | ✅ | `web/app.py:149` |
| `safe_output()` 仍 strip ANSI + redact + limit | ✅ | `web/app.py:157-160` |
| Dashboard 通过 `format_status()` → `redact_json()` | ✅ | `web/app.py:422-425` |
| Status 通过 `format_status()` + `safe_output()` | ✅ | `web/app.py:441-446` |
| `/api/status` 使用 `redact_json(data)` | ✅ | `web/app.py:459` |
| Raw JSON details 存在但值已 redact | ✅ | `format_status()` → `json.dumps(redact_json(data))` |
| Doctor/Rotate/failure 使用 `safe_output()` | ✅ | `web/app.py:474,540` |
| 命令执行行为不变 | ✅ | `run_nanobk()` 未修改 |
| 登录/Session/CSRF 不变 | ✅ | 未修改 |
| Rotate 确认不变 | ✅ | 未修改 |
| 无旧本地 `_REDACT_PATTERNS` | ✅ | 源码确认 |
| 无旧本地 `_ANSI_RE` | ✅ | 源码确认 |
| 无旧本地 `_SENSITIVE_KEY_SUBSTRINGS` | ✅ | 源码确认 |
| 无 `shell=True` | ✅ | 源码确认 |

---

## 5. 一致性矩阵

| 数据类 | 共享 Helper | Bot 覆盖 | Web 覆盖 | 测试覆盖 | 剩余风险 |
|--------|------------|----------|----------|----------|----------|
| token/secret/password/private_key | ✅ | ✅ | ✅ | ✅ | 低 |
| 长随机串 | ✅ | ✅ | ✅ | ✅ | 低 |
| IPv4 | ✅ | ✅ | ✅ | ✅ | 低 |
| IPv6 | ✅ | ✅ | ✅ | ✅ | 低 |
| 域名 | ✅ | ✅ | ✅ | ✅ | 低 |
| URL | ✅ | ✅ | ✅ | ✅ | 低 |
| workers.dev 主机 | ✅ | ✅ | ✅ | ✅ | 低 |
| 订阅路径 | ✅ | ✅ | ✅ | ✅ | 低 |
| route URL | ✅ | ✅ | ✅ | ✅ | 低 |
| JSON key-level redaction | ✅ | N/A | ✅ | ✅ | 低 |
| ANSI 输出 | ✅ | ✅ | ✅ | ✅ | 低 |
| 状态词 (active/failed/unknown) | 保持 | 保持 | 保持 | ✅ | 无 |
| geo | 保持 | 保持 | 保持 | ✅ | 产品决策待定 |
| 端口 | 保持 | 保持 | 保持 | ⚠️ | 产品决策待定 |

---

## 6. 剩余阻塞项

### 安全阻塞（必须在实现前解决）

| 阻塞项 | 说明 | 状态 |
|--------|------|------|
| Raw JSON 新手展示 | Raw JSON details 仍存在于 Web，需高级模式策略 | 阻塞 UX 实现 |
| 订阅 URL 交付 | 需独立安全设计 | 阻塞订阅功能 |
| Production status wrapper | 未批准 | 阻塞 |
| Dirty VPS status wrapping | 未批准 | 阻塞 |

### 产品/UX 阻塞（可在安全门禁后规划）

| 阻塞项 | 说明 | 状态 |
|--------|------|------|
| Bot 高级模式 | v1.9.2 spec 定义但未实现 | 可规划 |
| Web 高级模式 | v1.9.3 spec 定义但未实现 | 可规划 |
| Bot 菜单实现 | v1.9.2 spec 定义但未实现 | 可规划 |
| Web Dashboard 实现 | v1.9.3 spec 定义但未实现 | 可规划 |
| Cloudflare 变更操作 | 未实现 | 可规划 |
| Repair/Restart 实现 | 未实现 | 可规划 |
| Operation-log full rollout | 未批准 | 可规划 |

---

## 7. 就绪决策

**A. READY FOR SMALL UX IMPLEMENTATION PLANNING**

Bot/Web redaction 集成一致、安全，检查点通过。

**范围限制：**

- ✅ 仅就绪于小步、分阶段、低风险的 UX 实现规划
- ❌ 不就绪于广泛实现
- ❌ 不就绪于 tag/release
- ❌ 不就绪于 production status wrapper
- ❌ 不就绪于 raw subscription delivery
- ❌ 不就绪于 raw JSON 新手展示

---

## 8. 推荐下一步

**推荐：v1.9.10 — Bot Safe Status Summary Minimal Implementation**

理由：

1. Redaction 安全门禁已通过（v1.9.4 + v1.9.5 + v1.9.6 + v1.9.7 + v1.9.8 + v1.9.9）
2. Bot 的 `safe_output()` 已正确 redact 地址类值
3. `format_status()` + `safe_output()` 不泄露 raw IP/domain
4. Bot 是较小的控制面，适合作为第一个 UX 实现目标
5. 仅实现安全状态摘要，不涉及高风险操作

**但需 ChatGPT 审核后才能开始实现。**

---

## 9. 测试运行

| 测试 | 结果 |
|------|------|
| `bash tests/bot-cli-mock.sh` | ✅ All passed |
| `bash tests/web-panel-mock.sh` | ✅ All passed |
| `bash tests/bot-web-command-allowlist-v1.9.4.sh` | ✅ All passed |
| `bash tests/redaction-address-class-v1.9.5.sh` | ✅ All passed |
| `python3 tests/redaction-helper-v1.9.6.py` | ✅ All passed |
| `python3 tests/bot-redaction-helper-integration-v1.9.7.py` | ✅ All passed |
| `python3 tests/web-redaction-helper-integration-v1.9.8.py` | ✅ All passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ All passed |
| `python3 web/app.py --self-test` | ✅ All passed |
| `python3 tests/redaction-integration-checkpoint-v1.9.9.py` | ✅ 94/94 passed |

---

## 10. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Bot session | 未连接 Telegram |
| 无真实 Web session | 未启动 Web 服务器 |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| Status wrapper 未批准 | 不在 v1.9 范围 |
| Raw JSON 仍存在 | 未隐藏，需高级模式策略 |
| 高级模式未实现 | v1.9.2/v1.9.3 spec 定义 |
| 订阅交付未实现 | 需独立安全设计 |
| geo/端口产品决策待定 | 可能在 UX 实现阶段决定 |

---

## 11. Guardrails

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止修改 `install.sh` | 保护 v1.7.27 基线 |
| 2 | 禁止修改 `bin/nanobk` | 保护 CLI 核心 |
| 3 | 禁止修改协议模板 | 保护 VPS 部署 |
| 4 | 禁止修改 Worker | 保护 Cloudflare |
| 5 | 禁止修改 rotate sync | 保护轮换逻辑 |
| 6 | 禁止 Bot/Web 直接写 configs/systemd/secrets | 必须通过 CLI |
| 7 | 禁止 raw env 读取 | 安全 |
| 8 | 禁止 production status wrapper | 未批准 |
| 9 | 禁止 dirty VPS status wrapping | 未批准 |
| 10 | 禁止 operation-log full rollout | 未批准 |
| 11 | 禁止 tag/release | 未批准 |
