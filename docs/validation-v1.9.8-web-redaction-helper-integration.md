# v1.9.8 — Web Redaction Helper Integration Validation

> 验证类型：Web Redaction Helper 集成验证
> 日期：2026-06-05
> 基线 commit：`dfa5ef1b99421015e543555f4d382ece80cbb5a2`
> 基线信息：`fix: integrate bot redaction helper`

---

## 1. 本轮目标与结论

**v1.9.8 将共享 redaction helper 集成到 Web 输出路径：**

- ✅ 仅修改 Web redaction 路径
- ✅ 无 Bot 运行时变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release

**结论：Web 的 `strip_ansi()`、`redact_text()`、`redact_json()` 现在委托给 `lib/nanobk_redaction.py` 的共享 helper。Web 输出（Dashboard、Status、API、Doctor、Rotate、failure output）现在经过地址类 redaction（IPv4、IPv6、domain、URL、workers.dev、subscription path）。**

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `web/app.py` | 集成共享 redaction helper |
| `tests/web-redaction-helper-integration-v1.9.8.py` | 新增集成测试 |
| `docs/validation-v1.9.8-web-redaction-helper-integration.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.8 条目 |
| `docs/roadmap.md` | 新增 v1.9.8 版本行 |

---

## 3. Web 集成摘要

### 导入方式

```python
_REPO_ROOT = Path(__file__).resolve().parents[1]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from lib.nanobk_redaction import (
    strip_ansi as _shared_strip_ansi,
    redact_text as _shared_redact_text,
    redact_json_obj as _shared_redact_json_obj,
)
```

### 函数委托

| Web 函数 | 变更前 | 变更后 |
|----------|--------|--------|
| `strip_ansi()` | 本地 `_ANSI_RE` 正则 | 委托给 `_shared_strip_ansi()` |
| `redact_text()` | 本地 `_REDACT_PATTERNS`（3 个正则） | 委托给 `_shared_redact_text()`（9 个正则） |
| `redact_json()` | 本地递归 + `_SENSITIVE_KEY_SUBSTRINGS` | 委托给 `_shared_redact_json_obj()` |
| `safe_output()` | 调用本地 strip_ansi + redact_text + limit_text | 不变，通过委托使用共享 helper |
| `format_status()` | 调用本地 redact_json | 不变，通过委托使用共享 helper |
| `limit_text()` | 不变 | 不变 |

### 输出保护

- Dashboard → `format_status()` → `redact_json()` → 共享 helper
- Status → `format_status()` + `safe_output()` → 共享 helper
- API → `redact_json(data)` → 共享 helper
- Doctor → `safe_output(output)` → 共享 helper
- Rotate → `safe_output(output)` → 共享 helper
- Failure → `safe_output(output)` → 共享 helper
- Raw JSON → `format_status()` → `json.dumps(redact_json(data))` → 共享 helper

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
| token/password/secret=key | ✅ | ✅ |
| private_key=key | ✅ | ✅ |
| 长 base64/hex 串 | ✅ | ✅ |
| JSON key-level redaction | ✅ 本地 | ✅ 共享（增强：exempt keys） |

### 保持不变的行为

- ✅ 无 raw env 读取
- ✅ 无直接文件写入
- ✅ 无 `shell=True`
- ✅ 命令执行行为不变
- ✅ 路由可用性不变
- ✅ 登录/Session/CSRF 行为不变
- ✅ 状态语义不变

---

## 5. 测试运行

| 测试 | 结果 |
|------|------|
| Web self-test（42 项） | ✅ All passed |
| `tests/web-panel-mock.sh` | ✅ All passed |
| `tests/bot-cli-mock.sh` | ✅ All passed |
| `tests/bot-web-command-allowlist-v1.9.4.sh` | ✅ All passed |
| `tests/redaction-address-class-v1.9.5.sh` | ✅ All passed |
| `tests/redaction-helper-v1.9.6.py`（82 项） | ✅ All passed |
| `tests/bot-redaction-helper-integration-v1.9.7.py`（57 项） | ✅ All passed |
| `tests/web-redaction-helper-integration-v1.9.8.py`（84 项） | ✅ All passed |

---

## 6. 已知限制

| 限制 | 说明 |
|------|------|
| Raw JSON details 仍然存在 | 未隐藏，未添加高级模式 |
| 高级模式策略未实现 | v1.9.3 spec 定义但未实现 |
| Web Dashboard UX 未变更 | v1.9.3 spec 定义但未实现 |
| Bot 已在 v1.9.7 集成 | 本轮未变更 Bot |
| 订阅交付仍阻塞 | 需独立安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |
| Dirty VPS status wrapping 仍阻塞 | 未批准 |
| `format_status()` 仍输出原始字段名 | `domain`、`vps_ip` 等标签保持，但值被 redact |

---

## 7. 下一步

**推荐：v1.9.9 — Redaction Integration Checkpoint / Bot-Web Safety Gate**

Bot（v1.9.7）和 Web（v1.9.8）的 redaction helper 集成均已完成。下一步应进行集成检查点，验证 Bot 和 Web 的 redaction 行为一致，并决定是否可以开始 UX 实现阶段。

需 ChatGPT 审核后实施。

---

## 附录 A：Web self-test 新增测试

v1.9.8 在 Web self-test 中新增了以下测试：

```
# 19. Address-class redaction: redact_text removes IPv4, IPv6, domain, URL
check("redact_text redacts IPv4", ...)
check("redact_text redacts IPv6", ...)
check("redact_text redacts domain", ...)
check("redact_text redacts URL", ...)
check("redact_text redacts workers.dev", ...)
check("redact_text redacts subscription path", ...)

# 20. Address-class redaction: redact_json removes address values from JSON
check("redact_json redacts domain value", ...)
check("redact_json redacts IPv4 value", ...)
check("redact_json preserves ok=true", ...)
check("redact_json preserves services", ...)

# 21. Address-class redaction: safe_output redacts comprehensive text
check("safe_output redacts IPv6", ...)
check("safe_output redacts URL", ...)
check("safe_output redacts token", ...)
check("safe_output redacts secret", ...)

# 22. format_status + redact_json: raw domain/IP redacted in raw_json
check("format_status raw_json redacts domain", ...)
check("format_status raw_json redacts IPv4", ...)
check("format_status preserves services in raw_json", ...)

# 23. Idempotency
check("safe_output is idempotent", ...)
```

Web self-test 从 18 项增加到 42 项。

## 附录 B：格式化测试变更

原有测试 `format_status includes domain` 变更为 `format_status domain is redacted`，因为 `redact_json()` 现在会 redact 域名值。
