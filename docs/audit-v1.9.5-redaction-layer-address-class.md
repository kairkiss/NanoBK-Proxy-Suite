# v1.9.5 — Redaction Layer Audit and Address-Class Redaction Tests

> 审计类型：Redaction 层审计 + 地址类脱敏合约测试
> 日期：2026-06-05
> 基线 commit：`1046b46a9b24b5dcbfa6951f363a8f5cca7326fd`
> 基线信息：`test: add v1.9.4 bot web command allowlist guard`

---

## 1. 本轮目标与结论

**v1.9.5 是 Redaction 审计 + 地址类脱敏合约测试任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release
- ✅ 本版本创建显示安全需求，供后续实现使用

**结论：本版本审计了当前 Bot/Web redaction 行为，定义了地址类脱敏需求，添加了安全 fixture 文件和合约测试。测试使用 test-local redaction 实现证明预期行为，不接入生产代码。**

---

## 2. 当前 Redaction 现状

### Bot Redaction 辅助函数

来自 `bot/nanobk_bot.py`：

| 函数 | 说明 |
|------|------|
| `strip_ansi()` | 去除 ANSI 转义码 |
| `redact_text()` | 文本级脱敏，3 个正则 |
| `limit_text()` | 截断到 3500 字符 |
| `safe_output()` | strip_ansi + redact_text + limit_text |
| `format_status()` | 格式化 JSON status（展示 domain/vpsIp/geo，未脱敏） |

Bot `redact_text()` 使用 3 个正则：

1. Telegram bot token（`\d{6,}:[A-Za-z0-9_-]{20,}`）→ `[BOT_TOKEN_REDACTED]`
2. token/password/private_key/key=value → `[REDACTED]`
3. 长 base64/hex 串（≥40 字符）→ `[REDACTED_B64]`

### Web Redaction 辅助函数

来自 `web/app.py`：

| 函数 | 说明 |
|------|------|
| `strip_ansi()` | 去除 ANSI 转义码 |
| `redact_text()` | 文本级脱敏，3 个正则（与 Bot 相同） |
| `redact_json()` | 递归 JSON 脱敏，按敏感 key substring 匹配 |
| `limit_text()` | 截断到 12000 字符 |
| `safe_output()` | strip_ansi + redact_text + limit_text |
| `format_status()` | 格式化 JSON status，包含 `raw_json` 字段 |

Web `redact_json()` 使用 `_SENSITIVE_KEY_SUBSTRINGS`：
- `("token", "password", "secret", "private", "privatekey")`

### 当前覆盖总结

| 数据类 | Bot 覆盖 | Web 覆盖 |
|--------|----------|----------|
| token/password/secret 类 key-value | ✅ | ✅ |
| 长 base64/hex 串 | ✅ | ✅ |
| Telegram bot token 专用格式 | ✅ | ❌（无专用正则） |
| JSON key-level 脱敏 | ❌（仅文本级） | ✅ `redact_json()` |
| **IPv4 地址** | ❌ | ❌ |
| **IPv6 地址** | ❌ | ❌ |
| **域名** | ❌ | ❌ |
| **URL** | ❌ | ❌ |
| **workers.dev** | ❌ | ❌ |
| **订阅 URL/路径** | ❌ | ❌ |
| Reality private key（值级） | ⚠️ 部分 | ⚠️ 部分 |

---

## 3. 地址类敏感信息定义

### 地址类敏感数据

| 数据类 | 说明 | 示例（fake） |
|--------|------|-------------|
| IPv4 地址 | VPS 真实 IP | `203.0.113.10` |
| IPv6 地址 | VPS IPv6 | `2001:db8::10` |
| 域名 | VPS/服务域名 | `node.example.invalid` |
| URL | 完整 URL | `https://worker.example.invalid/sub/...` |
| workers.dev 主机 | Worker 默认域名 | `nanobk-test.example.invalid.workers.dev` |
| route URL | Cloudflare route | `https://worker.example.invalid/sub/...` |
| 订阅 URL/path | 订阅入口 | `/sub/fake-sub-path-12345` |
| callback URL | 回调地址 | 如存在 |

### 涉及的 JSON 字段

以下字段在 `nanobk --json status` 输出中可能出现，当前未做地址类脱敏：

| 字段 | 说明 | 风险 |
|------|------|------|
| `domain` | VPS 域名 | 高 |
| `vpsIp` / `vps_ip` | VPS IP | 高 |
| `ipv6` | VPS IPv6 | 高 |
| `route` / `routeUrl` | CF route URL | 高 |
| `workers.dev` | Worker 默认域名 | 高 |
| `subscriptionUrl` / `sub_url` | 订阅 URL | 高 |
| `subscriptionPath` / `path` | 订阅路径 | 高 |
| `geo` | 地理位置 | 中（间接） |

---

## 4. Redaction 策略

### 分层策略

| 视图 | 地址类展示 | 原因 |
|------|----------|------|
| 新手（L1） | 禁止展示 | 安全 |
| 高级（L2） | Redacted 后可展示诊断 | 调试需要 |
| 维护者（L3） | Redacted 后可展示诊断 | 调试需要 |
| Raw JSON | 高级/Owner + 地址类 redaction | 调试需要 |

### 具体规则

1. **新手视图**不得展示任何地址类值
2. **高级视图**可展示诊断，但必须经过地址类 redaction
3. **Owner 视图**仍然不得展示 raw secret
4. **Raw JSON** 必须高级/Owner-only 且经过地址类 redaction
5. **Doctor/status/failure 输出**必须地址类 redaction 后再展示
6. **订阅交付**需要独立安全设计
7. **不默认暴露 workers.dev 或完整订阅 URL**

---

## 5. 替换 Token 约定

### 标准化替换字符串

| 替换 Token | 用途 |
|-----------|------|
| `[REDACTED_IPV4]` | IPv4 地址 |
| `[REDACTED_IPV6]` | IPv6 地址 |
| `[REDACTED_DOMAIN]` | 域名 |
| `[REDACTED_URL]` | 完整 URL |
| `[REDACTED_WORKERS_DEV]` | workers.dev 主机 |
| `[REDACTED_SUBSCRIPTION_PATH]` | 订阅路径 |
| `[REDACTED_ROUTE_URL]` | Cloudflare route URL |
| `[REDACTED_TOKEN]` | Token 值 |
| `[REDACTED_SECRET]` | Secret 值 |
| `[REDACTED_PRIVATE_KEY]` | Private key 值 |
| `[REDACTED]` | 通用敏感值 |

### 使用规则

- JSON key-level 脱敏保持使用 `[REDACTED]`
- 地址类使用专用 token 以便调试时区分
- 替换 token 本身不包含任何真实信息

---

## 6. JSON Redaction 需求

### 规则

1. **保持 JSON 有效性** — redacted 输出必须仍是合法 JSON
2. **保留高层状态字段** — `ok`、`services`、`security.secretsMode` 等不变
3. **替换敏感字段值** — 不删除 key，只替换 value
4. **不改变布尔/状态字段** — `true`/`false`/`active` 等不变
5. **按 key 名和值模式 redact 地址类** — `domain`、`vpsIp` 等 key 的值替换
6. **Raw JSON 在新手视图隐藏** — 即使 redacted 后也隐藏

### Fixture 示例

输入（fake）：
```json
{
  "domain": "node.example.invalid",
  "vpsIp": "203.0.113.10",
  "services": {"hy2": "active"}
}
```

输出（redacted）：
```json
{
  "domain": "[REDACTED_DOMAIN]",
  "vpsIp": "[REDACTED_IPV4]",
  "services": {"hy2": "active"}
}
```

---

## 7. 文本输出 Redaction 需求

### 必须覆盖

| 模式 | 替换 |
|------|------|
| URL（https?://...） | `[REDACTED_URL]` |
| IPv4（x.x.x.x） | `[REDACTED_IPV4]` |
| IPv6（hex:colon） | `[REDACTED_IPV6]` |
| workers.dev 主机 | `[REDACTED_WORKERS_DEV]` |
| 域名 | `[REDACTED_DOMAIN]` |
| 订阅路径（/sub/...） | `[REDACTED_SUBSCRIPTION_PATH]` |
| token=key 文本 | `token=[REDACTED]` |
| secret=key 文本 | `secret=[REDACTED]` |
| private_key=key 文本 | `private_key=[REDACTED]` |
| 包含 host/path 的 failure 消息 | 地址类部分 redacted |

---

## 8. 当前差距表

| 数据类 | 当前 Bot | 当前 Web | 需要未来覆盖 | 风险 | Fixture 包含 |
|--------|----------|----------|-------------|------|-------------|
| token/secret | ✅ | ✅ | ✅ 保持 | 高 | ✅ |
| 长随机串 | ✅ | ✅ | ✅ 保持 | 中 | — |
| IPv4 | ❌ | ❌ | ✅ 需新增 | 高 | ✅ |
| IPv6 | ❌ | ❌ | ✅ 需新增 | 高 | ✅ |
| 域名 | ❌ | ❌ | ✅ 需新增 | 高 | ✅ |
| URL | ❌ | ❌ | ✅ 需新增 | 高 | ✅ |
| workers.dev | ❌ | ❌ | ✅ 需新增 | 高 | ✅ |
| 订阅路径 | ❌ | ❌ | ✅ 需新增 | 高 | ✅ |
| route URL | ❌ | ❌ | ✅ 需新增 | 高 | ✅ |
| Reality private key | ⚠️ 部分 | ⚠️ 部分 | ✅ 需加强 | 高 | ✅ |
| Cloudflare token | ⚠️ 部分 | ⚠️ 部分 | ✅ 需加强 | 高 | ✅ |
| Bot token | ✅ | ❌ 无专用 | ✅ 需统一 | 高 | ✅ |
| Admin token | ⚠️ 部分 | ⚠️ 部分 | ✅ 需加强 | 高 | ✅ |

---

## 9. Fixture 设计

### 文件清单

```
tests/fixtures/redaction-v1.9.5/
├── sample-status-input.json           # JSON 状态输入（fake 值）
├── sample-status-expected-redacted.json # JSON 状态预期 redacted 输出
├── sample-cli-output-input.txt        # 文本 CLI 输出输入（fake 值）
└── sample-cli-output-expected-redacted.txt # 文本 CLI 输出预期 redacted 输出
```

### 安全说明

**所有 fixture 值均为 fake 和 documentation-safe：**

| 类型 | 使用的值 | 安全标准 |
|------|---------|----------|
| IPv4 | `203.0.113.10` | RFC 5737 TEST-NET-3 |
| IPv6 | `2001:db8::10` | RFC 3849 文档前缀 |
| 域名 | `*.example.invalid` | RFC 2606 保留 |
| workers.dev | `*.workers.dev` | 假名 + 保留域 |
| Token | `fake-doc-token-*` | 明确 fake |
| Secret | `fake-secret-*` | 明确 fake |
| Private key | `FAKE_PRIVATE_KEY_*` | 明确 fake |

---

## 10. 新测试脚本设计

### 测试文件

`tests/redaction-address-class-v1.9.5.sh`

### 设计

- 使用 bash + `set -euo pipefail`
- 计算 repo root 并 cd
- 仅使用 fixture 文件
- 不读取真实 env
- 不运行真实 status/doctor/rotate
- 不运行 Cloudflare 命令
- 使用 test-local redaction 函数证明合约
- 验证预期替换 token 出现
- 验证禁止的 raw 值不出现
- 验证 redacted JSON 仍为合法 JSON
- 打印清晰 PASS/FAIL
- 失败时 exit 1

### 检查项

| # | 检查 |
|---|------|
| 1 | Redacted JSON 不含 fixture raw IPv4 |
| 2 | Redacted JSON 不含 fixture raw IPv6 |
| 3 | Redacted JSON 不含 fixture raw domain |
| 4 | Redacted JSON 不含 fixture raw URL |
| 5 | Redacted JSON 不含 fixture workers.dev 值 |
| 6 | Redacted JSON 不含 fixture 订阅路径 |
| 7 | Redacted JSON 不含 fixture token |
| 8 | Redacted JSON 含预期替换 token |
| 9 | Redacted JSON 仍为合法 JSON |
| 10 | Redacted text 不含 fixture raw IPv4 |
| 11 | Redacted text 不含 fixture raw IPv6 |
| 12 | Redacted text 不含 fixture raw domain |
| 13 | Redacted text 不含 fixture raw URL |
| 14 | Redacted text 不含 fixture workers.dev 值 |
| 15 | Redacted text 不含 fixture 订阅路径 |
| 16 | Redacted text 不含 fixture secret |
| 17 | Redacted text 含预期替换 token |
| 18 | 非敏感内容保留 |
| 19 | 现有 v1.9.4 测试通过 |

---

## 11. 与 v1.9.4 静态测试的关系

| 版本 | 测试内容 | 保护范围 |
|------|----------|----------|
| v1.9.4 | 执行安全（shell=True、直接写入等） | 命令执行边界 |
| v1.9.5 | 显示安全（地址类脱敏合约） | 输出显示边界 |

**两者都必须在 Bot/Web status UI 实现前通过。**

---

## 12. 仍然阻塞的事项

以下事项在 future implementation 完成前保持阻塞：

| 事项 | 阻塞原因 |
|------|----------|
| 新手 raw JSON 展示 | 需要地址类 redaction |
| Bot status 展示 raw IP/domain/URL | 需要地址类 redaction |
| Web Dashboard/Status 展示 raw IP/domain/URL | 需要地址类 redaction |
| raw workers.dev 展示 | 需要地址类 redaction |
| raw subscription URL/path 展示 | 需要独立安全设计 |
| Doctor 新手 raw 输出 | 需要地址类 redaction |
| Production status wrapper | 未批准 |
| Dirty VPS status wrapping | 未批准 |
| Operation-log full rollout | 未批准 |
| Raw subscription delivery | 需要独立安全设计 |

---

## 13. v1.9.6 推荐

### 推荐：v1.9.6 — Shared Redaction Helper Design / Prototype Review

**选择 A：先实现共享生产级 redaction helper（不接入 Bot/Web UI）**

**理由：**

1. v1.9.4 定义了执行安全边界（命令白名单）
2. v1.9.5 定义了显示安全边界（地址类脱敏合约）
3. 下一步应将合约转化为可复用的生产级 redaction helper
4. Helper 应作为独立模块，不直接修改 Bot/Web 运行时
5. 之后的小步实现可以引入 helper，经 ChatGPT 审核后接入

**v1.9.6 应包含：**

- 共享 redaction helper 模块设计（如 `scripts/redaction.sh` 或 `lib/redaction.py`）
- 覆盖 v1.9.5 定义的所有地址类模式
- 单元测试证明覆盖范围
- 不接入 Bot/Web 运行时
- 等待 ChatGPT 审核后才能接入

**不推荐立即实现 Bot/Web status UI：**

- Redaction helper 尚未实现
- UX spec 需要人工审核
- 实现应小步、可 review、可回滚

---

## 14. v1.9.3 实现顺序修正

`docs/spec-v1.9.3-web-dashboard-ux.md` 的实现顺序已在 v1.9.4 中修正。本轮更新了"实现前必须完成"的完成状态：

1. v1.9.2 Bot UX/Menu Spec — ✅ 已完成
2. v1.9.3 Web Dashboard UX Spec — ✅ 已完成
3. v1.9.4 Command Allowlist Spec/Tests — ✅ 已完成
4. v1.9.5 Redaction Layer Audit/Tests — ✅ 已完成

---

## 15. Implementation Guardrails

### 硬性约束

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止 v1.9.5 修改 Bot 运行时行为 | 仅文档/fixture/测试 |
| 2 | 禁止 v1.9.5 修改 Web 运行时行为 | 仅文档/fixture/测试 |
| 3 | 禁止新手视图展示 raw JSON | 使用安全摘要 |
| 4 | 禁止新手视图展示 raw IP/domain/URL/workers.dev/subscription path | 默认脱敏 |
| 5 | 禁止直接写 configs/systemd/secrets/env | 必须通过 nanobk CLI |
| 6 | 禁止直接 systemctl | 必须通过 nanobk CLI |
| 7 | 禁止读取 env 内容 | 不读取 .env 文件 |
| 8 | 所有操作通过 nanobk CLI | 不绕过 CLI |
| 9 | 高风险操作需确认 | 两步确认 |
| 10 | 禁止 production status wrapper | 未批准 |
| 11 | 禁止 dirty VPS status wrapping | 未批准 |
| 12 | 禁止 operation-log full rollout | 未批准 |
| 13 | 禁止修改 install.sh | 保护 v1.7.27 基线 |
| 14 | 禁止 tag/release | 未批准 |

---

## 附录 A：当前 Bot Redaction 代码

```python
# bot/nanobk_bot.py — redact_text()
_REDACT_PATTERNS = [
    (re.compile(r'\b\d{6,}:[A-Za-z0-9_-]{20,}\b'), '[BOT_TOKEN_REDACTED]'),
    (re.compile(r'(?i)(token|password|private[_ -]?key|secret)\s*[:=]\s*\S+'),
     lambda m: f'{m.group(1)}=[REDACTED]'),
    (re.compile(r'\b[A-Za-z0-9+/]{40,}={0,2}\b'), '[REDACTED_B64]'),
]
```

## 附录 B：当前 Web Redaction 代码

```python
# web/app.py — redact_text() + redact_json()
_REDACT_PATTERNS = [
    (re.compile(r'\b\d{6,}:[A-Za-z0-9_-]{20,}\b'), '[TOKEN_REDACTED]'),
    (re.compile(r'(?i)(token|password|private[_ -]?key|secret)\s*[:=]\s*\S+'),
     lambda m: f'{m.group(1)}=[REDACTED]'),
    (re.compile(r'\b[A-Za-z0-9+/]{40,}={0,2}\b'), '[REDACTED_B64]'),
]

_SENSITIVE_KEY_SUBSTRINGS = ("token", "password", "secret", "private", "privatekey")
```

## 附录 C：参考文档

| 文档 | 说明 |
|------|------|
| `docs/audit-v1.9.1-bot-web-current-state-safety.md` | v1.9.1 Redaction 覆盖审计 |
| `docs/spec-v1.9.2-bot-ux-menu.md` | v1.9.2 Redaction 需求 |
| `docs/spec-v1.9.3-web-dashboard-ux.md` | v1.9.3 Raw JSON 策略 |
| `docs/spec-v1.9.4-bot-web-command-allowlist.md` | v1.9.4 命令白名单 |
| `bot/nanobk_bot.py` | Bot 当前 redaction 代码 |
| `web/app.py` | Web 当前 redaction 代码 |
