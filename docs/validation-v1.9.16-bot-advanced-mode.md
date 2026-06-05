# v1.9.16 — Bot Advanced Mode Minimal Implementation Validation

> 验证类型：Bot 高级诊断模式最小实现
> 日期：2026-06-05
> 基线 commit：`e548b3f173423cb3994854cd5723b75594478116`
> 基线信息：`docs: add v1.9.15 advanced diagnostics planning`

---

## 1. 本轮目标与结论

**v1.9.16 实现了 Bot 端最小高级诊断模式：**

- ✅ `/advanced on` owner-only 启用
- ✅ `/advanced off` owner-only 禁用
- ✅ `/advanced status` owner-only 查询
- ✅ 内存状态，不持久化
- ✅ 15 分钟自动过期
- ✅ 启用时显示警告
- ✅ 未改变 redaction 规则
- ✅ 未改变 `/status_json` 可用性
- ✅ 未修改 Web
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | 新增高级模式 helper + `/advanced` 命令 + `/help` 更新 + self-test 更新 |
| `tests/bot-advanced-mode-v1.9.16.py` | 新增测试 |
| `docs/validation-v1.9.16-bot-advanced-mode.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.16 条目 |
| `docs/roadmap.md` | 新增 v1.9.16 版本行 |

---

## 3. Bot 高级模式行为

### 命令

| 命令 | 行为 |
|------|------|
| `/advanced on` | 启用高级模式，显示警告和过期信息 |
| `/advanced off` | 禁用高级模式 |
| `/advanced status` | 显示当前模式状态和剩余时间 |
| `/advanced`（无参数） | 显示用法说明 |

### 状态管理

| 特性 | 说明 |
|------|------|
| 存储 | 内存 dict（`_ADVANCED_MODE_EXPIRES_AT`） |
| TTL | 15 分钟（`ADVANCED_MODE_TTL_SECONDS = 900`） |
| 过期 | 检查时自动清理过期条目 |
| 持久化 | 无（不写磁盘/env/config/db） |
| 重启 | Bot 重启后自动重置 |

### Helper 函数

| 函数 | 说明 |
|------|------|
| `enable_advanced_mode(user_id, now)` | 启用，返回过期时间戳 |
| `disable_advanced_mode(user_id)` | 禁用 |
| `advanced_mode_expires_at(user_id)` | 返回过期时间戳或 None |
| `is_advanced_mode_enabled(user_id, now)` | 检查是否启用且未过期 |
| `advanced_mode_remaining_seconds(user_id, now)` | 返回剩余秒数 |

---

## 4. 安全行为

| 安全特性 | 状态 |
|----------|------|
| 高级模式不改变 redaction | ✅ |
| 高级模式不解锁 secrets | ✅ |
| 高级模式不门控 `/status_json` | ✅ |
| 高级模式不改变 rotate | ✅ |
| 无文件/env 持久化 | ✅ |
| Owner-only | ✅ |
| 自动过期 | ✅ |
| 警告文案 | ✅ |

---

## 5. 未变更项

| 项 | 状态 |
|----|------|
| `/status_json` | ✅ 仍可用，未门控 |
| `/status_json` 警告 | ✅ 未变更 |
| `/status` 安全摘要 | ✅ 未变更 |
| `/doctor` | ✅ 未变更 |
| Rotate | ✅ 未变更 |
| `run_nanobk` | ✅ 未变更 |
| Web | ✅ 未修改 |
| `lib/nanobk_redaction.py` | ✅ 未修改 |
| `installer/install.sh` | ✅ 未修改 |
| `bin/nanobk` | ✅ 未修改 |

---

## 6. 测试运行

| 测试 | 结果 |
|------|------|
| Bot self-test（61 项） | ✅ All passed |
| `tests/bot-advanced-mode-v1.9.16.py` | ✅ All passed |
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
| `python3 web/app.py --self-test` | ✅ All passed |

---

## 7. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Bot session | 未连接 Telegram |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| 高级模式未用于门控 Raw JSON | 后续版本 |
| Web 高级模式未实现 | v1.9.17 任务 |
| 订阅交付仍阻塞 | 需独立安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |
| Dirty VPS status wrapping 仍阻塞 | 未批准 |

---

## 8. 下一步

**推荐：v1.9.17 — Web Advanced Mode Planning or Minimal Implementation**

需 ChatGPT 审核后实施。
