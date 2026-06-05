# v1.9.20 — Bot /status_json Soft Gate Minimal Implementation Validation

> 验证类型：Bot /status_json 软门控最小实现
> 日期：2026-06-05
> 基线 commit：`58101e83b30c51afc257a2c4cb485faeaa1afdda`
> 基线信息：`docs: add v1.9.19 raw json gating policy`

---

## 1. 本轮目标与结论

**v1.9.20 实现了 Bot `/status_json` 软门控：**

- ✅ `/status_json` 仍可用，未隐藏/移除/重命名
- ✅ 高级模式关闭时显示引导信息，不输出 JSON
- ✅ 高级模式开启时显示警告 + redacted JSON
- ✅ 过期模式表现关闭
- ✅ 未改变 redaction 规则
- ✅ 未改变 `run_nanobk` 参数
- ✅ 未修改 Web
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | `cmd_status_json` 添加软门控 + `/help` 更新 + self-test 更新 |
| `tests/bot-status-json-soft-gate-v1.9.20.py` | 新增测试（50 项） |
| `docs/validation-v1.9.20-bot-status-json-soft-gate.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.20 条目 |
| `docs/roadmap.md` | 新增 v1.9.20 版本行 |

---

## 3. Bot `/status_json` 软门控行为

### 高级模式关闭时

```
Advanced diagnostics mode is not enabled.

/status_json is for troubleshooting and shows redacted Raw JSON.
Use /status for the normal safe summary first.

To continue, run /advanced on.
Advanced mode expires automatically after 15 minutes.

Even in advanced mode, secrets, raw addresses, and subscription URLs must remain hidden.
```

- 不调用 `run_nanobk`
- 不输出 JSON
- 显示引导信息

### 高级模式开启时

```
⚠️ Advanced diagnostics
This output is redacted, but it may still reveal system structure.
Do not forward the full output to untrusted people.
Use /status for the normal safe summary.

{redacted JSON output}
```

- 保持现有行为
- 警告头部 + redacted JSON
- 通过 `safe_output()` 脱敏

### 过期模式

- 表现为关闭状态
- `is_advanced_mode_enabled()` 自动清理过期条目

---

## 4. 安全行为

| 安全特性 | 状态 |
|----------|------|
| 关闭状态不运行 nanobk | ✅ |
| 高级模式不绕过 redaction | ✅ |
| `safe_output` 仍保护输出 | ✅ |
| `run_nanobk` 参数不变 | ✅ |
| secrets/raw 地址/subscription URL 仍隐藏 | ✅ |

---

## 5. 未变更项

| 项 | 状态 |
|----|------|
| `/status` 安全摘要 | ✅ 未变更 |
| `/advanced on/off/status` | ✅ 未变更 |
| `/doctor` | ✅ 未变更 |
| Rotate | ✅ 未变更 |
| `run_nanobk` | ✅ 未变更（仅不在门控关闭时调用） |
| Web | ✅ 未修改 |
| `/api/status` | ✅ 未变更 |
| 部署核心 | ✅ 未变更 |

---

## 6. 测试运行

| 测试 | 结果 |
|------|------|
| Bot self-test（66 项） | ✅ All passed |
| `tests/bot-status-json-soft-gate-v1.9.20.py`（50 项） | ✅ All passed |
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
| `python3 web/app.py --self-test` | ✅ All passed |

---

## 7. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Bot session | 未连接 Telegram |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| Web Raw JSON 门控未实现 | v1.9.21 任务 |
| `/api/status` 未门控 | 独立规划 |
| 订阅交付仍阻塞 | 需独立安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |
| Dirty VPS status wrapping 仍阻塞 | 未批准 |

---

## 8. 下一步

**推荐：v1.9.21 — Web Raw JSON Soft Gate Minimal Implementation**

需 ChatGPT 审核后实施。
