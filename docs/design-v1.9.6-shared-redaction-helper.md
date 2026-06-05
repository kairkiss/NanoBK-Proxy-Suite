# v1.9.6 — Shared Redaction Helper Design / Prototype Review

> 设计类型：共享 Redaction Helper 模块设计
> 日期：2026-06-05
> 基线 commit：`0a8322aeb96fc0332d48d6e0a1f301182caa6bbf`
> 基线信息：`test: add v1.9.5 address redaction fixtures`

---

## 1. 本轮目标与结论

**v1.9.6 是共享 Redaction Helper + 测试任务：**

- ✅ 无 Bot 运行时集成
- ✅ 无 Web 运行时集成
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release
- ✅ 添加了可复用的 redaction helper 模块和测试

**结论：本版本将 v1.9.5 的 test-local contract 转化为可复用的生产级 helper 模块 `lib/nanobk_redaction.py`，并通过 82 项测试验证。Helper 未接入 Bot/Web 运行时。**

---

## 2. 为什么需要共享 Redaction Helper

### 当前问题

Bot 和 Web 各有独立的 redaction 辅助函数：

| 维度 | Bot (`nanobk_bot.py`) | Web (`app.py`) |
|------|----------------------|----------------|
| `redact_text()` | ✅ 3 个正则 | ✅ 3 个正则（相同） |
| `redact_json()` | ❌ 仅文本级 | ✅ 递归 JSON 脱敏 |
| 地址类脱敏 | ❌ 未覆盖 | ❌ 未覆盖 |
| `strip_ansi()` | ✅ | ✅ |

### v1.9.1 发现

- 地址类信息（IPv4/IPv6/domain/URL/workers.dev/subscription path）未被脱敏
- Bot 和 Web 的 redaction 实现存在漂移风险

### v1.9.5 建立合约

- 使用 fixture 证明了预期的 redaction 行为
- 使用 test-local 实现验证了合约

### v1.9.6 目标

- 将合约转化为可复用的生产级 helper
- 减少 Bot/Web 之间的 redaction 漂移
- 为未来集成提供统一基础

---

## 3. Helper API

### 模块路径

`lib/nanobk_redaction.py`

### 导出函数

```python
from lib.nanobk_redaction import (
    redact_text,        # 文本级脱敏
    redact_json_obj,    # JSON 对象脱敏
    redact_json_text,   # JSON 文本脱敏
    strip_ansi,         # ANSI 转义码去除
    # 替换 token 常量
    REDACTED_IPV4,
    REDACTED_IPV6,
    REDACTED_DOMAIN,
    REDACTED_URL,
    REDACTED_WORKERS_DEV,
    REDACTED_SUBSCRIPTION_PATH,
    REDACTED,
)
```

### 函数说明

| 函数 | 输入 | 输出 | 说明 |
|------|------|------|------|
| `strip_ansi(text)` | str | str | 去除 ANSI 转义码 |
| `redact_text(text)` | str | str | 文本级全量脱敏 |
| `redact_json_obj(obj)` | object | object | 递归 JSON 对象脱敏 |
| `redact_json_text(text)` | str | str | JSON 文本解析+脱敏+序列化 |

---

## 4. 覆盖的 Redaction 类别

### Token/Secret 类

| 类别 | 替换 | 方式 |
|------|------|------|
| Telegram bot token | `[REDACTED_TOKEN]` | 正则匹配 |
| token/key=value | `[REDACTED]` | key-value 正则 |
| secret=value | `[REDACTED]` | key-value 正则 |
| password=value | `[REDACTED]` | key-value 正则 |
| private_key=value | `[REDACTED]` | key-value 正则 |
| 长 base64/hex 串 | `[REDACTED_B64]` | 长度模式 |

### 地址类

| 类别 | 替换 | 方式 |
|------|------|------|
| IPv4 | `[REDACTED_IPV4]` | 正则匹配 |
| IPv6（full + compressed） | `[REDACTED_IPV6]` | 正则匹配 |
| URL | `[REDACTED_URL]` | 正则匹配 |
| workers.dev 主机 | `[REDACTED_WORKERS_DEV]` | 正则匹配 |
| 订阅路径 | `[REDACTED_SUBSCRIPTION_PATH]` | 正则匹配 |
| 域名 | `[REDACTED_DOMAIN]` | 正则 + 文件扩展名排除 |

### JSON Key 类

| Key 模式 | 替换 | 说明 |
|----------|------|------|
| `*token*` | `[REDACTED]` | adminToken, apiToken, botToken |
| `*password*` | `[REDACTED]` | — |
| `*secret*` | `[REDACTED]` | 但 NOT secretsMode |
| `*private*` | `[REDACTED]` | privateKey, realityPrivateKey |
| `*privatekey*` | `[REDACTED]` | — |

### 豁免 Key

| Key | 原因 |
|-----|------|
| `secretsMode` | 安全模式字符串，不是 secret |
| `currentPath` | 文件路径，不是 secret |

---

## 5. JSON 策略

### 规则

1. **保持 JSON 有效性** — redacted 输出必须仍是合法 JSON
2. **保留状态字段** — `ok`、`services.*`、`configured` 等不变
3. **替换敏感值** — 不删除 key，只替换 value
4. **保留布尔/数字** — `true`/`false`/`42` 不变
5. **按 key + 值模式 redact** — 敏感 key 的值替换，地址类值替换
6. **递归处理** — dict/list 递归处理

### `redact_json_text()` 行为

- 解析 JSON → `redact_json_obj()` → `json.dumps(sort_keys=True)`
- 解析失败时 fallback 到 `redact_text()`

---

## 6. 文本策略

### 顺序

文本 redaction 的顺序很重要：

1. **URL** 先于域名（URL 包含域名）
2. **workers.dev** 先于通用域名
3. **订阅路径** 先于通用路径
4. **IPv6** 先于 IPv4
5. **key=value secret** 先于长串

### 域名处理

- 使用 callable replacement 排除文件扩展名（.json, .py 等）
- 排除 bare `workers.dev` 标签（由专用 pattern 处理）
- 保守匹配：需要至少一个点和有效的 TLD

---

## 7. 已知限制

| 限制 | 说明 |
|------|------|
| 域名正则保守 | 可能过度/不足匹配，需持续调整 |
| IPv6 正则保守 | 复杂压缩形式可能未完全覆盖 |
| geo 字段未脱敏 | 除非策略变更 |
| 端口展示待定 | 产品决策 |
| 订阅交付需独立设计 | 安全设计 |
| Helper 未接入 Bot/Web | 需未来集成 |
| 文件扩展名列表不完整 | 可能需要扩展 |

---

## 8. 测试覆盖

### 测试文件

`tests/redaction-helper-v1.9.6.py`

### 测试范围

| 测试组 | 数量 | 说明 |
|--------|------|------|
| JSON fixture 合约 | 33 | v1.9.5 fixture 验证 |
| 文本 fixture 合约 | 28 | v1.9.5 fixture 验证 |
| 幂等性 | 4 | 重复 redaction 不引入 raw 值 |
| 边界情况 | 14 | 空串、纯文本、布尔、无效 JSON |
| ANSI 去除 | 3 | strip_ansi 验证 |
| **总计** | **82** | — |

### Fixture 复用

使用 v1.9.5 的 fixture 文件：

- `tests/fixtures/redaction-v1.9.5/sample-status-input.json`
- `tests/fixtures/redaction-v1.9.5/sample-status-expected-redacted.json`
- `tests/fixtures/redaction-v1.9.5/sample-cli-output-input.txt`
- `tests/fixtures/redaction-v1.9.5/sample-cli-output-expected-redacted.txt`

---

## 9. 未来集成计划

### 分阶段集成

| 版本 | 任务 | 说明 |
|------|------|------|
| v1.9.7 | Bot redaction 集成 | 将 helper 接入 Bot `redact_text()` + `format_status()` |
| v1.9.8 | Web redaction 集成 | 将 helper 接入 Web `redact_text()` + `redact_json()` + `format_status()` |

### 集成规则

- 每次只集成一个控制面
- 集成必须有测试
- 不要同时集成 Bot 和 Web（除非 ChatGPT 明确批准）
- Status/Raw JSON 新手 UI 变更需等待集成测试通过

---

## 10. Guardrails

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止直接写 configs/systemd/secrets/env | 必须通过 nanobk CLI |
| 2 | 禁止新手视图展示 raw JSON | 使用安全摘要 |
| 3 | 禁止新手视图展示 raw IP/domain/URL/workers.dev/subscription path | 默认脱敏 |
| 4 | 禁止高风险操作无确认 | 两步确认 |
| 5 | 禁止直接 systemctl | 必须通过 nanobk CLI |
| 6 | 禁止读取 env 内容 | 不读取 .env 文件 |
| 7 | 禁止 production status wrapper | 未批准 |
| 8 | 禁止 dirty VPS status wrapping | 未批准 |
| 9 | 禁止 operation-log full rollout | 未批准 |
| 10 | 禁止修改 install.sh | 保护 v1.7.27 基线 |
| 11 | 禁止 tag/release | 未批准 |

---

## 附录 A：模块结构

```
lib/
└── nanobk_redaction.py    # 共享 redaction helper

tests/
├── redaction-helper-v1.9.6.py           # helper 测试
├── redaction-address-class-v1.9.5.sh    # contract 测试（bash）
└── fixtures/redaction-v1.9.5/           # fixture 文件
```

## 附录 B：参考文档

| 文档 | 说明 |
|------|------|
| `docs/audit-v1.9.5-redaction-layer-address-class.md` | Redaction 合约 |
| `docs/spec-v1.9.4-bot-web-command-allowlist.md` | 命令白名单 |
| `docs/spec-v1.9.2-bot-ux-menu.md` | Bot UX spec |
| `docs/spec-v1.9.3-web-dashboard-ux.md` | Web UX spec |
| `bot/nanobk_bot.py` | Bot 当前 redaction |
| `web/app.py` | Web 当前 redaction |
