# v1.9.18 — Advanced Diagnostics Mode Checkpoint

> 验证类型：高级诊断模式一致性检查点
> 日期：2026-06-05
> 基线 commit：`8a8fd9c419a447f9311a9d54e99966cdc2244c06`
> 基线信息：`feat: add web advanced mode`

---

## 1. 本轮目标与结论

**v1.9.18 是检查点/验证任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release
- ✅ 目的是验证 Bot/Web 高级诊断模式一致性和安全性，为 Raw JSON 门控规划做准备

**结论：Bot 和 Web 高级诊断模式在安全性、临时性、非持久性、警告保护方面一致。两者都不绕过 redaction，不改变高风险操作。可以进入 Raw JSON 门控规划阶段。**

---

## 2. 当前高级诊断模式架构

### Bot (v1.9.16)

| 特性 | 说明 |
|------|------|
| 命令 | `/advanced on`、`/advanced off`、`/advanced status` |
| 权限 | owner-only |
| 状态存储 | 内存 dict（`_ADVANCED_MODE_EXPIRES_AT`） |
| TTL | 15 分钟 |
| 过期 | 检查时自动清理 |
| 持久化 | 无 |
| 重启重置 | 是 |

### Web (v1.9.17)

| 特性 | 说明 |
|------|------|
| 路由 | `POST /advanced/on`、`POST /advanced/off`、`GET /advanced/status` |
| 权限 | login + CSRF（POST） |
| 状态存储 | Flask session |
| TTL | 15 分钟 |
| 过期 | 检查时自动清理 |
| 持久化 | 无 |
| 登出重置 | 是（`session.clear()`） |
| URL query 绕过 | 无 |

### 共享

- 不解锁 raw secret
- 不绕过 redaction
- 不门控 Raw JSON
- 不交付订阅

---

## 3. Bot 检查点

| 检查项 | 状态 |
|--------|------|
| owner-only 保护 | ✅ `is_owner()` 检查 |
| 内存状态 | ✅ `_ADVANCED_MODE_EXPIRES_AT` dict |
| 无持久化 | ✅ 不写文件/env/config |
| 15 分钟过期 | ✅ `ADVANCED_MODE_TTL_SECONDS = 900` |
| 警告文案 | ✅ 启用时显示警告 |
| `/status_json` 仍可用 | ✅ 未门控 |
| `/status_json` 警告 | ✅ 仍显示警告 |
| redaction 不变 | ✅ 委托给共享 helper |
| rotate 不变 | ✅ 两步确认不变 |
| `run_nanobk` 不变 | ✅ 未修改 |

---

## 4. Web 检查点

| 检查项 | 状态 |
|--------|------|
| login 必需 | ✅ `@require_login` |
| POST 启用/禁用 | ✅ `POST /advanced/on`、`POST /advanced/off` |
| CSRF 必需 | ✅ `validate_csrf()` |
| session 级状态 | ✅ `session["advanced_mode"]` |
| 无 URL query 绕过 | ✅ 无 `request.args` |
| 15 分钟过期 | ✅ `ADVANCED_MODE_TTL_SECONDS = 900` |
| 登出/session 过期重置 | ✅ `session.clear()` |
| Raw JSON details 仍可见 | ✅ `<details>` 块未隐藏 |
| Raw JSON 警告 | ✅ 仍显示警告 |
| `/api/status` 不变 | ✅ 未门控 |
| redaction 不变 | ✅ 委托给共享 helper |
| rotate 不变 | ✅ 两步确认 + CSRF 不变 |
| `run_nanobk` 不变 | ✅ 未修改 |

---

## 5. 一致性矩阵

| 能力/边界 | Bot v1.9.16 | Web v1.9.17 | 测试覆盖 | 剩余风险 |
|----------|-------------|-------------|----------|----------|
| 启用高级模式 | ✅ `/advanced on` | ✅ `POST /advanced/on` | ✅ | 无 |
| 禁用高级模式 | ✅ `/advanced off` | ✅ `POST /advanced/off` | ✅ | 无 |
| 状态检查 | ✅ `/advanced status` | ✅ `GET /advanced/status` | ✅ | 无 |
| 认证要求 | ✅ owner-only | ✅ login + CSRF | ✅ | 无 |
| 状态存储 | ✅ 内存 dict | ✅ Flask session | ✅ | 无 |
| 过期时间 | ✅ 15 分钟 | ✅ 15 分钟 | ✅ | 无 |
| 重启/登出重置 | ✅ 重启重置 | ✅ 登出重置 | ✅ | 无 |
| 警告文案 | ✅ | ✅ | ✅ | 无 |
| redaction 不变 | ✅ | ✅ | ✅ | 无 |
| Raw JSON 未门控 | ✅ | ✅ | ✅ | 待 v1.9.19 规划 |
| API/status_json 不变 | ✅ | ✅ | ✅ | 无 |
| 无持久化存储 | ✅ | ✅ | ✅ | 无 |
| 无 URL query 绕过 | ✅ N/A | ✅ | ✅ | 无 |
| 高风险操作不变 | ✅ rotate 不变 | ✅ rotate 不变 | ✅ | 无 |
| raw secrets 仍禁止 | ✅ | ✅ | ✅ | 无 |

---

## 6. 安全决策

高级诊断模式作为状态/toggle 基础是安全的。

**但它尚不构成以下许可：**

- 展示 raw IP/domain/URL
- 展示 workers.dev
- 展示 subscription URL/path
- 展示 tokens/secrets/private keys
- 读取 env 文件
- 运行 production status wrapper
- 运行 dirty VPS status wrapping
- 交付订阅
- 运行 repair/restart/Cloudflare mutations

---

## 7. 就绪决策

**A. READY FOR RAW JSON GATING PLANNING**

**范围限制：**

- ✅ 就绪于规划 Raw JSON 门控
- ❌ 不就绪于在同一版本实现
- ❌ 不就绪于 raw subscription delivery
- ❌ 不就绪于 production status wrapper
- ❌ 不就绪于 release/tag

---

## 8. 可选下一步方案

| 方案 | 说明 | 推荐 |
|------|------|------|
| v1.9.19 — Raw JSON 门控策略规划 | 规划 Bot/Web Raw JSON 何时/如何门控 | ✅ 推荐 |
| v1.9.19 — Bot Raw JSON 门控最小实现 | 实现 Bot 端门控 | 需先规划 |
| v1.9.19 — Web Raw JSON 门控最小实现 | 实现 Web 端门控 | 需先规划 |
| v1.9.19 — 高级模式打磨 | 门控前的模式优化 | 可选 |

**推荐：v1.9.19 — Raw JSON Gating Policy Planning**

**理由：** Bot 和 Web 高级模式都已存在，但门控策略应在实现前规划，以避免破坏诊断功能。

---

## 9. 剩余阻塞项

| 事项 | 状态 | 说明 |
|------|------|------|
| Raw subscription delivery | 阻塞 | 需独立安全设计 |
| Subscription QR delivery | 阻塞 | 需独立安全设计 |
| Production status wrapper | 阻塞 | 未批准 |
| Dirty VPS status wrapping | 阻塞 | 未批准 |
| Operation-log full rollout | 阻塞 | 未批准 |
| 直接 Bot/Web repair/restart | 阻塞 | 未实现 |
| Cloudflare 变更操作 | 阻塞 | 未实现 |
| 直接 config/systemd/secrets 写入 | 阻塞 | 安全禁止 |
| Raw env 读取/显示 | 阻塞 | 安全禁止 |
| Release/tag | 阻塞 | 未批准 |

---

## 10. 测试运行

| 测试 | 结果 |
|------|------|
| `bash tests/bot-cli-mock.sh` | ✅ All passed |
| `bash tests/web-panel-mock.sh` | ✅ All passed |
| `bash tests/bot-web-command-allowlist-v1.9.4.sh` | ✅ All passed |
| `bash tests/redaction-address-class-v1.9.5.sh` | ✅ All passed |
| `python3 tests/redaction-helper-v1.9.6.py` | ✅ All passed |
| `python3 tests/bot-redaction-helper-integration-v1.9.7.py` | ✅ All passed |
| `python3 tests/web-redaction-helper-integration-v1.9.8.py` | ✅ All passed |
| `python3 tests/redaction-integration-checkpoint-v1.9.9.py` | ✅ All passed |
| `python3 tests/bot-safe-status-summary-v1.9.10.py` | ✅ All passed |
| `python3 tests/web-safe-status-cards-v1.9.11.py` | ✅ All passed |
| `python3 tests/bot-status-json-warning-v1.9.13.py` | ✅ All passed |
| `python3 tests/web-raw-json-warning-v1.9.14.py` | ✅ All passed |
| `python3 tests/bot-advanced-mode-v1.9.16.py` | ✅ All passed |
| `python3 tests/web-advanced-mode-v1.9.17.py` | ✅ All passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ All passed |
| `python3 web/app.py --self-test` | ✅ All passed |
| `python3 tests/advanced-diagnostics-checkpoint-v1.9.18.py` | ✅ All passed |

---

## 11. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Bot session | 未连接 Telegram |
| 无真实 Web 浏览器 session | 未启动 Web 服务器 |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| 高级模式未门控 Raw JSON | 本版本仅检查点 |
| Web session 行为主要通过 mock/source 检查测试 | 无真实浏览器测试 |
| Production status wrapper 仍阻塞 | 未批准 |
| Raw subscription delivery 仍阻塞 | 未批准 |

---

## 12. Guardrails

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止修改 `install.sh` | 保护 v1.7.27 基线 |
| 2 | 禁止修改 `bin/nanobk` | 保护 CLI 核心 |
| 3 | 禁止修改协议模板 | 保护部署 |
| 4 | 禁止修改 Worker | 保护 Cloudflare |
| 5 | 禁止修改 rotate sync | 保护轮换 |
| 6 | 禁止直接 Bot/Web 写入 configs/systemd/secrets | 安全 |
| 7 | 禁止 raw env 读取 | 安全 |
| 8 | 禁止 production status wrapper | 未批准 |
| 9 | 禁止 dirty VPS status wrapping | 未批准 |
| 10 | 禁止 operation-log full rollout | 未批准 |
| 11 | 禁止 raw subscription delivery | 未批准 |
| 12 | 禁止 tag/release | 未批准 |
