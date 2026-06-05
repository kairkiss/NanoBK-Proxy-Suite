# v1.9.13 — Bot /status_json Warning and Help Classification Validation

> 验证类型：Bot /status_json 警告和 /help 分类
> 日期：2026-06-05
> 基线 commit：`319941c89e074abcd4832d0686d466cae713eb75`
> 基线信息：`docs: add v1.9.12 raw json diagnostics policy`

---

## 1. 本轮目标与结论

**v1.9.13 实现了最小的 Bot-only /status_json 警告和 /help 分类：**

- ✅ `/status_json` 仍可用，未隐藏/移除
- ✅ `/status_json` 从主命令列表移到 "Advanced diagnostics" 分区
- ✅ `/status_json` 输出前添加安全警告
- ✅ 输出仍通过 shared redaction helper 脱敏
- ✅ 未实现高级模式
- ✅ 无 Web 运行时变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | `/help` 文本重分类 + `/status_json` 警告 + self-test 更新 |
| `tests/bot-status-json-warning-v1.9.13.py` | 新增 44 项测试 |
| `docs/validation-v1.9.13-bot-status-json-warning.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.13 条目 |
| `docs/roadmap.md` | 新增 v1.9.13 版本行 |

---

## 3. Bot /help 行为

### 新 /help 结构

```
NanoBK Bot Commands

Basic:
/start          — Show welcome and quick help
/status         — Safe status summary
/doctor         — Redacted diagnostic check
/cancel         — Cancel pending action

Safe operations:
/rotate_all     — Rotate ALL protocols (requires confirmation)
/rotate_hy2     — Rotate HY2 secret with confirmation
/rotate_tuic    — Rotate TUIC secret with confirmation
/rotate_reality — Rotate Reality credentials with confirmation
/rotate_trojan  — Rotate Trojan password with confirmation

Advanced diagnostics:
/status_json    — Redacted raw status JSON for debugging

/help           — Show this help

⚠️ Rotate commands require confirmation to prevent accidents.
```

### 变更说明

- `/status_json` 从主命令列表移到 "Advanced diagnostics" 分区
- 命令仍可用，未隐藏/移除
- 新增 "Basic" 和 "Safe operations" 分区，结构更清晰
- 高级模式未实现

---

## 4. /status_json 警告行为

### 警告文本

```
⚠️ Advanced diagnostics
This output is redacted, but it may still reveal system structure.
Do not forward the full output to untrusted people.
Use /status for the normal safe summary.
```

### 行为

- 警告在 `/status_json` 输出前显示
- 输出仍通过 `safe_output()` 脱敏（调用 shared redaction helper）
- 失败输出仍通过 `safe_output()` 脱敏
- 命令执行行为未变更

---

## 5. 未变更项

| 项 | 状态 |
|----|------|
| `/status_json` 命令 | ✅ 仍可用 |
| `/status_json` 脱敏 | ✅ 仍通过 shared helper |
| `/status` 安全摘要 | ✅ 未变更 |
| `/doctor` | ✅ 未变更 |
| Rotate 命令 | ✅ 未变更 |
| `run_nanobk` | ✅ 未变更 |
| 授权检查 | ✅ 未变更 |
| Web | ✅ 未变更 |
| `lib/nanobk_redaction.py` | ✅ 未变更 |
| `installer/install.sh` | ✅ 未变更 |
| `bin/nanobk` | ✅ 未变更 |

---

## 6. 测试运行

| 测试 | 结果 |
|------|------|
| Bot self-test（47 项） | ✅ All passed |
| `tests/bot-status-json-warning-v1.9.13.py`（44 项） | ✅ All passed |
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
| `python3 web/app.py --self-test` | ✅ 48/48 passed |

---

## 7. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Bot session | 未连接 Telegram |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| 高级模式未实现 | v1.9.12 规划，未实施 |
| Web Raw JSON 警告未实现 | 下一步 v1.9.14 |
| 订阅交付仍阻塞 | 需独立安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |
| Dirty VPS status wrapping 仍阻塞 | 未批准 |

---

## 8. 下一步

**推荐：v1.9.14 — Web Raw JSON Warning Copy Minimal Implementation**

在 Web Status 页面的 Raw JSON details 块前添加类似的警告文案。

需 ChatGPT 审核后实施。
