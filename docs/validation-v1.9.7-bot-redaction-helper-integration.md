# v1.9.7 — Bot Redaction Helper Integration Validation

> 验证类型：Bot Redaction Helper 集成验证
> 日期：2026-06-05
> 基线 commit：`69e66291aaf50c63d0aa893d8de120ee5f0bb0e6`
> 基线信息：`test: add v1.9.6 shared redaction helper`

---

## 1. 本轮目标与结论

**v1.9.7 将共享 redaction helper 集成到 Bot 输出路径：**

- ✅ 仅修改 Bot redaction 路径
- ✅ 无 Web 运行时集成
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release

**结论：Bot 的 `strip_ansi()` 和 `redact_text()` 现在委托给 `lib/nanobk_redaction.py` 的共享 helper。Bot 输出（`/status`、`/status_json`、`/doctor`、failure output）现在经过地址类 redaction（IPv4、IPv6、domain、URL、workers.dev、subscription path）。**

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | 集成共享 redaction helper |
| `tests/bot-redaction-helper-integration-v1.9.7.py` | 新增集成测试 |
| `docs/validation-v1.9.7-bot-redaction-helper-integration.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.7 条目 |
| `docs/roadmap.md` | 新增 v1.9.7 版本行 |

---

## 3. Bot 集成摘要

### 导入方式

```python
_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from lib.nanobk_redaction import (
    strip_ansi as _shared_strip_ansi,
    redact_text as _shared_redact_text,
)
```

### 函数委托

| Bot 函数 | 变更前 | 变更后 |
|----------|--------|--------|
| `strip_ansi()` | 本地 `_ANSI_RE` 正则 | 委托给 `_shared_strip_ansi()` |
| `redact_text()` | 本地 `_REDACT_PATTERNS`（3 个正则） | 委托给 `_shared_redact_text()`（9 个正则） |
| `safe_output()` | 调用本地 strip_ansi + redact_text + limit_text | 不变，但现在通过委托使用共享 helper |
| `limit_text()` | 不变 | 不变 |
| `format_status()` | 不变 | 不变 |

### 输出保护

- `/status` → `format_status()` + `safe_output()` → 共享 redaction
- `/status_json` → `safe_output(result.stdout)` → 共享 redaction
- `/doctor` → `safe_output(output)` → 共享 redaction
- Rotate failure → `safe_output(output)` → 共享 redaction
- Parse error → `safe_output()` → 共享 redaction

---

## 4. 安全行为

### 地址类 redaction（新增）

| 数据类 | 变更前 | 变更后 |
|--------|--------|--------|
| IPv4 地址 | ❌ 未覆盖 | ✅ `[REDACTED_IPV4]` |
| IPv6 地址 | ❌ 未覆盖 | ✅ `[REDACTED_IPV6]` |
| 域名 | ❌ 未覆盖 | ✅ `[REDACTED_DOMAIN]` |
| URL | ❌ 未覆盖 | ✅ `[REDACTED_URL]` |
| workers.dev | ❌ 未覆盖 | ✅ `[REDACTED_WORKERS_DEV]` |
| 订阅路径 | ❌ 未覆盖 | ✅ `[REDACTED_SUBSCRIPTION_PATH]` |

### Token/Secret redaction（保持+增强）

| 数据类 | 变更前 | 变更后 |
|--------|--------|--------|
| Telegram bot token | ✅ | ✅ |
| token/password/secret=value | ✅ | ✅ |
| private_key=value | ✅ | ✅ |
| 长 base64/hex 串 | ✅ | ✅ |
| admin_token=value | ⚠️ 部分 | ✅ 增强 |

### 保持不变的行为

- ✅ 无 raw env 读取
- ✅ 无直接文件写入
- ✅ 无 `shell=True`
- ✅ 命令执行行为不变
- ✅ 状态语义不变（active/failed/unknown 等保持）
- ✅ 布尔/数字字段保持

---

## 5. 测试运行

| 测试 | 结果 |
|------|------|
| Bot self-test（28 项） | ✅ All passed |
| `tests/bot-cli-mock.sh` | ✅ All passed |
| `tests/web-panel-mock.sh` | ✅ All passed |
| `tests/bot-web-command-allowlist-v1.9.4.sh` | ✅ All passed |
| `tests/redaction-address-class-v1.9.5.sh` | ✅ All passed |
| `tests/redaction-helper-v1.9.6.py`（82 项） | ✅ All passed |
| `tests/bot-redaction-helper-integration-v1.9.7.py`（57 项） | ✅ All passed |

---

## 6. 已知限制

| 限制 | 说明 |
|------|------|
| `/status_json` 仍然存在 | 未隐藏，未添加高级模式 |
| 高级模式策略未实现 | v1.9.2 spec 定义但未实现 |
| Bot 菜单 UX 未变更 | v1.9.2 spec 定义但未实现 |
| Web 未集成 | v1.9.8 任务 |
| 订阅交付仍阻塞 | 需独立安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |
| Dirty VPS status wrapping 仍阻塞 | 未批准 |
| `format_status()` 仍输出原始字段名 | `Domain:`、`VPS IP:` 等标签保持，但值被 safe_output redact |

---

## 7. 下一步

**推荐：v1.9.8 — Web Redaction Helper Integration**

将共享 helper 接入 Web 的 `redact_text()`、`redact_json()`、`format_status()` 路径。

需 ChatGPT 审核后实施。

---

## 附录 A：Bot self-test 新增测试

v1.9.7 在 Bot self-test 中新增了以下测试：

```
# 15. Address-class redaction: safe_output removes raw domain/IP from status
check("safe_output redacts raw domain from status", ...)
check("safe_output redacts raw IPv4 from status", ...)
check("safe_output preserves service words in status", ...)

# 16. Address-class redaction: safe_output removes IPv6, URL, workers.dev, subscription path
check("safe_output redacts raw IPv6", ...)
check("safe_output redacts raw URL", ...)
check("safe_output redacts raw workers.dev", ...)
check("safe_output redacts raw subscription path", ...)

# 17. Idempotency: redacting already-redacted output is stable
check("safe_output is idempotent", ...)
```

Bot self-test 从 20 项增加到 28 项。
