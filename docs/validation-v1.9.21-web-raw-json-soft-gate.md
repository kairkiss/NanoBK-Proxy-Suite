# v1.9.21 — Web Raw JSON Soft Gate Minimal Implementation Validation

> 验证类型：Web Raw JSON 软门控最小实现
> 日期：2026-06-05
> 基线 commit：`9b107117d5b1e01cbfe6e5b4e25198e5520112de`
> 基线信息：`feat: gate bot status json`

---

## 1. 本轮目标与结论

**v1.9.21 实现了 Web Status 页面 Raw JSON 软门控：**

- ✅ Raw JSON 区域仍可发现
- ✅ 高级模式关闭时显示锁定面板，不渲染 `status.raw_json`
- ✅ 高级模式开启时显示警告 + Redacted Raw JSON details
- ✅ 过期模式表现关闭
- ✅ 未门控 `/api/status`
- ✅ 未改变 redaction 规则
- ✅ 未修改 Bot
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `web/templates/status.html` | Raw JSON 区域门控于高级模式 |
| `web/static/style.css` | 新增 `.locked-panel` 样式 |
| `tests/web-raw-json-soft-gate-v1.9.21.py` | 新增测试（48 项） |
| `docs/validation-v1.9.21-web-raw-json-soft-gate.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.21 条目 |
| `docs/roadmap.md` | 新增 v1.9.21 版本行 |

---

## 3. Web Raw JSON 软门控行为

### 高级模式关闭时

```
🔒 Raw JSON (Advanced Diagnostics)
Raw JSON belongs to advanced diagnostics and is currently locked.
Use the status cards above for the normal safe summary.
Enable advanced diagnostics mode to view redacted Raw JSON. This mode expires automatically after 15 minutes.
Even in advanced mode, secrets, raw addresses, and subscription URLs must remain hidden.
```

- 不渲染 `status.raw_json`
- 不显示 `<pre>` 块
- 显示锁定面板 + 引导信息
- 启用表单在上方 Advanced Diagnostics 卡片中

### 高级模式开启时

```
⚠️ Advanced diagnostics
Raw JSON is redacted and intended for troubleshooting only.
It is not the normal status view and should not be shared as subscription information.
Use the status cards above for the normal safe summary.

[Raw JSON (advanced diagnostics)]  ← collapsed details
  {redacted status.raw_json}
```

- 显示警告文案
- 显示 `<details>` 块（默认折叠）
- 渲染 redacted `status.raw_json`
- 禁用表单在上方 Advanced Diagnostics 卡片中

### 过期模式

- 表现为关闭状态
- `is_advanced_mode_enabled()` 自动清理过期条目

---

## 4. 安全行为

| 安全特性 | 状态 |
|----------|------|
| 关闭状态不渲染 `status.raw_json` | ✅ |
| 高级模式不绕过 redaction | ✅ |
| `/api/status` 未门控 | ✅ |
| Login/Session/CSRF 不变 | ✅ |
| Rotate 不变 | ✅ |
| secrets/raw 地址/subscription URL 仍隐藏 | ✅ |

---

## 5. 未变更项

| 项 | 状态 |
|----|------|
| Bot | ✅ 未修改 |
| `/api/status` | ✅ 未变更，未门控 |
| Redaction 规则 | ✅ 未改变 |
| Web 状态卡片 | ✅ 未变更 |
| Rotate | ✅ 未变更 |
| `run_nanobk` | ✅ 未变更 |
| 部署核心 | ✅ 未变更 |

---

## 6. 测试运行

| 测试 | 结果 |
|------|------|
| Web self-test（62 项） | ✅ All passed |
| `tests/web-raw-json-soft-gate-v1.9.21.py`（48 项） | ✅ All passed |
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
| `python3 tests/bot-status-json-warning-v1.9.13.py` | ✅ 53/53 passed |
| `python3 tests/web-raw-json-warning-v1.9.14.py` | ✅ 37/37 passed |
| `python3 tests/bot-advanced-mode-v1.9.16.py` | ✅ 65/65 passed |
| `python3 tests/web-advanced-mode-v1.9.17.py` | ✅ 64/64 passed |
| `python3 tests/advanced-diagnostics-checkpoint-v1.9.18.py` | ✅ 80/80 passed |
| `python3 tests/bot-status-json-soft-gate-v1.9.20.py` | ✅ 50/50 passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 66/66 passed |

---

## 7. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Web 浏览器 session | 未启动 Web 服务器 |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| `/api/status` 未门控 | v1.9.19 策略明确推迟 |
| Bot 软门控已实现但未变更 | v1.9.20 |
| 订阅交付仍阻塞 | 需独立安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |
| Dirty VPS status wrapping 仍阻塞 | 未批准 |

---

## 8. 下一步

**推荐：v1.9.22 — Raw JSON Gating Checkpoint**

需 ChatGPT 审核后实施。
