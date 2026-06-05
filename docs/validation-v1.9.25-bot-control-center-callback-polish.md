# v1.9.25 — Bot Control Center Callback Polish Validation

> 验证类型：Bot 控制中心回调打磨
> 日期：2026-06-05
> 基线 commit：`e08e686fc7905bd70cb6a7ea35bd70bf8fc80e96`
> 基线信息：`feat: add bot control center menu`

---

## 1. 本轮目标与结论

**v1.9.25 打磨了 Bot 控制中心回调：**

- ✅ 提取共享 `get_safe_status_text()` helper，消除 `/status` 和回调之间的逻辑漂移
- ✅ 提取回调引导常量（`GUIDANCE_RECOVERY` 等），加强测试可检查性
- ✅ 强化 self-test，移除弱检查（`or True`）
- ✅ 回调 owner-only 不变
- ✅ Rotate 回调仍为引导
- ✅ Web Panel 回调不暴露 raw URL
- ✅ `/status_json` 软门控不变
- ✅ 高级模式不变
- ✅ 未修改 Web
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | 新增共享 helper + 引导常量 + 回调重构 + self-test 强化 |
| `tests/bot-control-center-callback-polish-v1.9.25.py` | 新增测试（50 项） |
| `docs/validation-v1.9.25-bot-control-center-callback-polish.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.25 条目 |
| `docs/roadmap.md` | 新增 v1.9.25 版本行 |

---

## 3. 共享状态 helper 行为

### `get_safe_status_text(config)`

```python
def get_safe_status_text(config: BotConfig) -> str:
    result = run_nanobk(config, ["--json", "status"])
    if result.code != 0:
        return safe_output(f"nanobk status failed (code {result.code}):\n{result.stderr}")
    try:
        data = json.loads(result.stdout)
        formatted = format_status(data)
    except json.JSONDecodeError:
        formatted = f"Failed to parse status JSON.\nRaw output:\n{result.stdout[:500]}"
    return safe_output(formatted)
```

- `/status` 和 Status Summary 回调共享同一 helper
- `run_nanobk(config, ["--json", "status"])` 参数不变
- `format_status()` + `safe_output()` 管道不变
- 不展示 raw JSON

---

## 4. 回调引导摘要

| 回调 | 引导常量 | 内容要点 |
|------|----------|----------|
| Recovery Help | `GUIDANCE_RECOVERY` | /status、/doctor、SSH 手动恢复、secrets hidden |
| Diagnostics | `GUIDANCE_DIAGNOSTICS` | /doctor、/advanced on、/status_json、output redacted |
| Rotate Secrets | `GUIDANCE_ROTATE` | 列出 rotate 命令、需确认、不执行 |
| Web Panel | `GUIDANCE_WEB` | 浏览器 dashboard、本地网络、无 raw URL |
| Help | `HELP_TEXT` | 完整帮助文本 |

---

## 5. 安全行为

| 安全特性 | 状态 |
|----------|------|
| 回调 owner-only | ✅ |
| Rotate 回调仍为引导 | ✅ |
| Web Panel 回调无 raw URL | ✅ |
| `/status_json` 软门控不变 | ✅ |
| 高级模式不变 | ✅ |
| redaction 不变 | ✅ |
| `run_nanobk` 执行不变 | ✅ |

---

## 6. 未变更项

| 项 | 状态 |
|----|------|
| `/start` 菜单布局 | ✅ 未变更 |
| `/status` 语义 | ✅ 未变更 |
| `/status_json` | ✅ 未变更 |
| `/advanced` | ✅ 未变更 |
| `/doctor` | ✅ 未变更 |
| Rotate 确认 | ✅ 未变更 |
| Web | ✅ 未修改 |
| `/api/status` | ✅ 未变更 |
| 部署核心 | ✅ 未变更 |

---

## 7. 测试运行

| 测试 | 结果 |
|------|------|
| Bot self-test（93 项） | ✅ All passed |
| `tests/bot-control-center-callback-polish-v1.9.25.py`（50 项） | ✅ All passed |
| `tests/bot-control-center-menu-v1.9.24.py` | ✅ All passed |
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
| 回调仍为引导为主 | v1.9.24 已建立 |
| Rotate 子菜单执行未实现 | 安全设计 |
| Web Panel raw URL 未显示 | 安全设计 |
| Raw subscription delivery 仍阻塞 | 需独立安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |

---

## 9. 下一步

**推荐：v1.9.26 — Bot Control Center Checkpoint**

需 ChatGPT 审核后实施。
