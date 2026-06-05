# v1.9.26 — Bot Control Center Checkpoint

> 验证类型：Bot 控制中心一致性检查点
> 日期：2026-06-05
> 基线 commit：`b1a519902f4fe0f879d87d8a8bb1a4ebd711f499`
> 基线信息：`fix: polish bot control center callbacks`

---

## 1. 本轮目标与结论

**v1.9.26 是检查点/验证任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release
- ✅ 目的是验证 Bot 控制中心在 v1.9.24/v1.9.25 后的一致性和安全性

**结论：Bot 控制中心作为静态/引导优先的控制面是安全的、owner-only 的、additive 的。不绕过现有斜杠命令安全、Raw JSON 门控、高级模式、rotate 确认、redaction 或 run_nanobk 边界。可以进入有限真实 Bot/Web 冒烟测试规划阶段。**

---

## 2. 当前 Bot 控制中心架构

```
┌─────────────────────────────────────────────────┐
│  /start → Control Center Menu                    │
│  InlineKeyboardButton + nanobk: prefix           │
├─────────────────────────────────────────────────┤
│  📊 Status Summary → get_safe_status_text()      │
│  🧭 Recovery Help  → GUIDANCE_RECOVERY           │
│  🩺 Diagnostics    → GUIDANCE_DIAGNOSTICS        │
│  🔐 Advanced Mode  → advanced_mode_remaining()   │
│  🔄 Rotate Secrets → GUIDANCE_ROTATE (引导)      │
│  🌐 Web Panel      → GUIDANCE_WEB (无 raw URL)   │
│  ❓ Help           → HELP_TEXT                   │
├─────────────────────────────────────────────────┤
│  斜杠命令仍为规范快捷方式                          │
│  CallbackQueryHandler scoped ^nanobk:             │
│  回调 owner-only                                  │
├─────────────────────────────────────────────────┤
│  /status → get_safe_status_text(config)          │
│  /status_json → 高级模式门控                      │
│  /advanced → owner-only, 15 分钟 TTL              │
│  /doctor → safe_output()                         │
│  rotate → 两步确认                                │
│  redaction → shared helper                       │
│  run_nanobk → 唯一 CLI 执行路径                    │
└─────────────────────────────────────────────────┘
```

---

## 3. /start 检查点

| 检查项 | 状态 |
|--------|------|
| /start 是 owner-only | ✅ `is_owner()` 检查 |
| 产品化 Control Center 消息 | ✅ `CONTROL_CENTER_TEXT` |
| /help 仍可用 | ✅ |
| 敏感地址和密钥已隐藏 | ✅ "Sensitive addresses and secrets are hidden." |
| 菜单标签存在 | ✅ 7 个按钮 |
| /start 不直接运行 nanobk | ✅ 仅显示菜单 |
| 无 raw status/IP/domain/URL | ✅ |

---

## 4. 回调检查点

| 回调 | 行为 | 风险 | 调用 nanobk | 暴露 raw 数据 | 安全结果 |
|------|------|------|-------------|---------------|----------|
| 📊 Status Summary | 调用 `get_safe_status_text(config)` | 只读 | ✅ `["--json", "status"]` | ❌ | 安全 |
| 🧭 Recovery Help | 静态引导 | 只读 | ❌ | ❌ | 安全 |
| 🩺 Diagnostics | 静态引导 | 只读 | ❌ | ❌ | 安全 |
| 🔐 Advanced Mode | 显示状态 + 命令引导 | 只读 | ❌ | ❌ | 安全 |
| 🔄 Rotate Secrets | 静态引导（不执行） | 只读 | ❌ | ❌ | 安全 |
| 🌐 Web Panel | 静态引导（无 raw URL） | 只读 | ❌ | ❌ | 安全 |
| ❓ Help | 显示帮助文本 | 只读 | ❌ | ❌ | 安全 |

---

## 5. 共享状态 helper 检查点

| 检查项 | 状态 |
|--------|------|
| `/status` 和 Status Summary 回调共享 `get_safe_status_text(config)` | ✅ |
| `run_nanobk(config, ["--json", "status"])` 参数不变 | ✅ |
| 无 raw JSON 展示在新手状态中 | ✅ |
| `format_status()` + `safe_output()` 仍在管道中 | ✅ |
| redaction 不变 | ✅ |
| 未引入 status wrapper / dirty VPS wrapping | ✅ |

---

## 6. 安全矩阵

| 边界 | 当前行为 | 测试覆盖 | 剩余风险 |
|------|----------|----------|----------|
| owner-only 回调 | ✅ `query.from_user.id != config.owner_id` | ✅ | 无 |
| scoped 回调模式 | ✅ `pattern=r"^nanobk:"` | ✅ | 无 |
| 斜杠命令保留 | ✅ 所有 CommandHandler 仍注册 | ✅ | 无 |
| /status_json 软门控 | ✅ `is_advanced_mode_enabled` 检查 | ✅ | 无 |
| 高级模式保留 | ✅ owner-only, 15 分钟 TTL | ✅ | 无 |
| rotate 确认保留 | ✅ ConfirmationManager 不变 | ✅ | 无 |
| rotate 回调仅引导 | ✅ `GUIDANCE_ROTATE` | ✅ | 无 |
| Web Panel raw URL 隐藏 | ✅ `GUIDANCE_WEB` 无 http/https | ✅ | 无 |
| redaction 不变 | ✅ shared helper 集成 | ✅ | 无 |
| run_nanobk 参数不变 | ✅ `["--json", "status"]` | ✅ | 无 |
| 无直接 config/systemd/secrets 写入 | ✅ | ✅ | 无 |
| 无 raw env 读取 | ✅ | ✅ | 无 |
| 无 subscription delivery | ✅ | ✅ | 无 |
| 无 production status wrapper | ✅ | ✅ | 无 |
| 无 tag/release | ✅ | ✅ | 无 |

---

## 7. 安全决策

Bot 控制中心作为静态/引导优先的控制面是安全的。

**但它不构成以下许可：**

- 展示 raw IP/domain/URL
- 展示 workers.dev
- 展示 subscription URL/path
- 展示 tokens/secrets/private keys
- 读取 env 文件
- 运行 repair/restart
- 运行 Cloudflare mutations
- 从回调直接执行 rotate
- 交付订阅
- 运行 production status wrapper
- 运行 dirty VPS status wrapping

---

## 8. 就绪决策

**A. READY FOR LIMITED REAL BOT/WEB SMOKE TEST PLANNING**

**范围限制：**

- ✅ 就绪于有限真实 Bot/Web 冒烟测试规划
- ❌ 不就绪于完整真实 VPS 部署回归
- ❌ 不就绪于 raw subscription delivery
- ❌ 不就绪于 production status wrapper
- ❌ 不就绪于 tag/release

---

## 9. 可选下一步方案

| 方案 | 说明 | 推荐 |
|------|------|------|
| v1.9.27 — 有限真实 Bot/Web 冒烟测试规划 | 规划用户应测试的控制面项目 | ✅ 推荐 |
| v1.9.27 — Web Dashboard UX 打磨规划 | 规划 Web UX 打磨 | 可选 |
| v1.9.27 — Bot 控制中心真实 session 准备 | 准备真实 Bot 测试 | 可选 |
| v1.9.27 — v1.9 控制面检查点 | 全面检查点 | 可选 |

**推荐：v1.9.27 — Limited Real Bot/Web Smoke Test Plan**

**理由：** Bot 菜单、高级诊断、Raw JSON 门控和 Web Raw JSON 门控已就位。在更深入的 UI 打磨之前，有限的控制面冒烟规划可以定义用户在真实 Bot/Web session 中应测试什么，而不暴露 secrets。

---

## 10. 真实 Bot/Web 冒烟测试定位

- 不运行完整真实 VPS 部署测试
- v1.9 主要变更了 Bot/Web UI、redaction、诊断可见性和测试
- `installer/install.sh`、VPS 模板、Worker 核心、rotate sync、部署逻辑未变更
- 完整真实 VPS 部署回归应等到部署/status/Cloudflare/rotate 核心变更或发布候选
- 有限真实 Bot/Web 冒烟测试应仅限控制面：
    - Bot 启动
    - owner-only 有效
    - /start 菜单出现
    - /status 安全摘要
    - Status Summary 按钮
    - Recovery/Diagnostics/Advanced/Rotate/Web/Help 回调
    - /advanced on/off/status
    - /status_json OFF/ON 行为
    - Web 登录
    - Web 高级切换
    - Web Raw JSON 锁定/解锁行为
    - /api/status 脱敏
    - 无 raw IP/domain/token/workers.dev/subscription URL 出现
- 用户不应粘贴真实 secrets、env 文件、raw IP、raw domain、workers.dev 或 subscription URL

---

## 11. 剩余阻塞项

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

## 12. 测试运行

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
| `python3 tests/advanced-diagnostics-checkpoint-v1.9.18.py` | ✅ All passed |
| `python3 tests/bot-status-json-soft-gate-v1.9.20.py` | ✅ All passed |
| `python3 tests/web-raw-json-soft-gate-v1.9.21.py` | ✅ All passed |
| `python3 tests/raw-json-gating-checkpoint-v1.9.22.py` | ✅ All passed |
| `python3 tests/bot-control-center-menu-v1.9.24.py` | ✅ All passed |
| `python3 tests/bot-control-center-callback-polish-v1.9.25.py` | ✅ All passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ All passed |
| `python3 web/app.py --self-test` | ✅ All passed |
| `python3 tests/bot-control-center-checkpoint-v1.9.26.py` | ✅ All passed |

---

## 13. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Bot session | 未连接 Telegram |
| 无真实 Web 浏览器 session | 未启动 Web 服务器 |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| 检查点依赖 mock/source 测试 | 无真实运行时验证 |
| 回调仍为引导为主 | 安全设计 |
| Rotate 回调执行未实现 | 安全设计 |
| Web Panel raw URL 未显示 | 安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |
| Raw subscription delivery 仍阻塞 | 未批准 |

---

## 14. Guardrails

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
