# v1.9.14 — Web Raw JSON Warning Copy Minimal Implementation Validation

> 验证类型：Web Raw JSON 警告文案
> 日期：2026-06-05
> 基线 commit：`152f5c234ce311c1067eb20113b43f516cf97946`
> 基线信息：`feat: add bot status json warning`

---

## 1. 本轮目标与结论

**v1.9.14 实现了最小的 Web-only Raw JSON 警告文案：**

- ✅ Raw JSON details 仍可用，未隐藏/移除
- ✅ Raw JSON details 仍默认折叠
- ✅ Raw JSON 值仍通过 shared redaction helper 脱敏
- ✅ 在 Raw JSON details 前添加安全警告
- ✅ 未实现高级模式
- ✅ 未变更 `/api/status`
- ✅ 无 Bot 运行时变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `web/templates/status.html` | 添加警告文案 `<div>` |
| `web/static/style.css` | 添加 `.warning-box` 样式 |
| `tests/web-raw-json-warning-v1.9.14.py` | 新增 33 项测试 |
| `docs/validation-v1.9.14-web-raw-json-warning.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.14 条目 |
| `docs/roadmap.md` | 新增 v1.9.14 版本行 |

---

## 3. Web Raw JSON 警告行为

### 警告文案

```
⚠️ Advanced diagnostics
Raw JSON is redacted and intended for troubleshooting only.
It is not the normal status view and should not be shared as subscription information.
Use the status cards above for the normal safe summary.
```

### 位置

- 警告在 Raw JSON `<details>` 块前显示
- 使用 `.warning-box` CSS 类（深色背景 + 黄色边框）
- Raw JSON details 仍默认折叠

---

## 4. Raw JSON 边界

| 项 | 状态 |
|----|------|
| Raw JSON details | ✅ 仍存在 |
| Raw JSON 可见性 | ✅ 未隐藏（`<details>` 块） |
| Raw JSON 值 | ✅ 经过 shared redaction |
| `/api/status` | ✅ 仍可用，返回 redacted JSON |
| 高级模式 | ❌ 未实现 |

---

## 5. 未变更项

| 项 | 状态 |
|----|------|
| Bot | 未修改 |
| `/status_json` | 未变更 |
| Login/Session/CSRF | 未变更 |
| Rotate 行为 | 未变更 |
| `run_nanobk` | 未变更 |
| `lib/nanobk_redaction.py` | 未修改 |
| `bin/nanobk` | 未修改 |
| `installer/install.sh` | 未修改 |
| `web/app.py` 运行时行为 | 未变更 |

---

## 6. 测试运行

| 测试 | 结果 |
|------|------|
| Web self-test（48 项） | ✅ All passed |
| `tests/web-raw-json-warning-v1.9.14.py`（33 项） | ✅ All passed |
| `bash tests/bot-cli-mock.sh` | ✅ All passed |
| `bash tests/web-panel-mock.sh` | ✅ All passed |
| `bash tests/bot-web-command-allowlist-v1.9.4.sh` | ✅ All passed |
| `bash tests/redaction-address-class-v1.9.5.sh` | ✅ All passed |
| `python3 tests/redaction-helper-v1.9.6.py` | ✅ All passed |
| `python3 tests/bot-redaction-helper-integration-v1.9.7.py` | ✅ All passed |
| `python3 tests/web-redaction-helper-integration-v1.9.8.py` | ✅ All passed |
| `python3 tests/redaction-integration-checkpoint-v1.9.9.py` | ✅ 94/94 passed |
| `python3 tests/bot-safe-status-summary-v1.9.10.py` | ✅ 67/67 passed |
| `python3 tests/web-safe-status-cards-v1.9.11.py` | ✅ 82/82 passed |
| `python3 tests/bot-status-json-warning-v1.9.13.py` | ✅ 52/52 passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 47/47 passed |

---

## 7. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Web session | 未启动 Web 服务器 |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| 高级模式未实现 | v1.9.12 规划，未实施 |
| Raw JSON 仍可见 | 未隐藏 |
| 订阅交付仍阻塞 | 需独立安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |
| Dirty VPS status wrapping 仍阻塞 | 未批准 |

---

## 8. 下一步

**推荐：v1.9.15 — Advanced Diagnostics Mode Planning**

Bot 和 Web 的 Raw JSON 警告文案已完成。下一步应规划高级诊断模式的实现方案。

需 ChatGPT 审核后实施。
