# v1.9.24 — Bot Control Center Static Menu Minimal Implementation Validation

> 验证类型：Bot 控制中心静态菜单最小实现
> 日期：2026-06-05
> 基线 commit：`6d0d70630c3489bdbdacbb3cfd1db6d498c9ee2c`
> 基线信息：`docs: add v1.9.23 bot control center planning`

---

## 1. 本轮目标与结论

**v1.9.24 实现了 Bot 控制中心静态菜单：**

- ✅ `/start` 显示产品化控制中心消息 + InlineKeyboardButton 菜单
- ✅ 所有斜杠命令仍可用
- ✅ 回调处理为保守/静态引导
- ✅ 不添加新风险操作
- ✅ 不绕过 owner 检查
- ✅ 不绕过高级模式门控
- ✅ 不绕过 rotate 确认
- ✅ 未修改 Web
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | 新增控制中心菜单 + 回调处理 + self-test 更新 |
| `tests/bot-control-center-menu-v1.9.24.py` | 新增测试（46 项） |
| `docs/validation-v1.9.24-bot-control-center-static-menu.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.24 条目 |
| `docs/roadmap.md` | 新增 v1.9.24 版本行 |

---

## 3. /start 控制中心行为

### 消息内容

```
🏠 NanoBK Control Center

Use the buttons below for quick actions, or type /help for all commands.
Sensitive addresses and secrets are hidden.
```

### 按钮布局

```
Row 1: [📊 Status Summary] [🧭 Recovery Help]
Row 2: [🩺 Diagnostics]   [🔐 Advanced Mode]
Row 3: [🔄 Rotate Secrets] [🌐 Web Panel]
Row 4: [❓ Help]
```

### 特性

- 使用 `InlineKeyboardButton` + `InlineKeyboardMarkup`
- Owner-only（`is_owner()` 检查）
- 不调用 `run_nanobk`
- 不输出 raw status
- 不展示 secrets/raw 地址

---

## 4. 回调行为摘要

| 按钮 | 回调数据 | 行为 |
|------|----------|------|
| 📊 Status Summary | `nanobk:status` | 调用 `run_nanobk` 获取安全摘要 |
| 🧭 Recovery Help | `nanobk:recovery` | 静态安全恢复文本 |
| 🩺 Diagnostics | `nanobk:diagnostics` | 静态引导（/doctor、/advanced on、/status_json） |
| 🔐 Advanced Mode | `nanobk:advanced` | 显示当前状态 + 命令引导 |
| 🔄 Rotate Secrets | `nanobk:rotate` | 静态引导（列出命令，不执行） |
| 🌐 Web Panel | `nanobk:web` | 安全引导文本（不暴露 raw URL） |
| ❓ Help | `nanobk:help` | 显示帮助文本 |

---

## 5. 授权/安全边界

| 安全特性 | 状态 |
|----------|------|
| 回调 owner-only | ✅ `query.from_user.id != config.owner_id` 检查 |
| 非 owner 拒绝 | ✅ `await query.answer("Unauthorized.")` |
| 不暴露 owner id | ✅ |
| 不暴露 config | ✅ |
| 不暴露 token | ✅ |

---

## 6. Rotate/Web/Raw JSON 边界

| 边界 | 状态 |
|------|------|
| Rotate 回调不执行 rotate | ✅ 仅显示引导 |
| Rotate 回调不调用 `run_nanobk` | ✅ |
| Rotate 回调不调用 `confirmations.set` | ✅ |
| Web Panel 回调不暴露 raw URL | ✅ |
| Raw JSON 仍门控于 `/status_json` | ✅ |
| `/status_json` 软门控未改变 | ✅ |
| `/advanced` 未改变 | ✅ |

---

## 7. 测试运行

| 测试 | 结果 |
|------|------|
| Bot self-test（81 项） | ✅ All passed |
| `tests/bot-control-center-menu-v1.9.24.py`（46 项） | ✅ All passed |
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
| `python3 web/app.py --self-test` | ✅ All passed |

---

## 8. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Bot session | 未连接 Telegram |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| 回调大多为静态引导 | v1.9.25 将打磨 |
| Rotate 子菜单执行未实现 | 安全设计 |
| Web Panel raw URL 未显示 | 安全设计 |
| Raw subscription delivery 仍阻塞 | 需独立安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |

---

## 9. 下一步

**推荐：v1.9.25 — Bot Control Center Callback Polish**

需 ChatGPT 审核后实施。
