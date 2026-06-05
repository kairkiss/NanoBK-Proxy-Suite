# v1.9.4 — Bot/Web Command Allowlist Spec and Static Tests

> 规格类型：命令白名单 + 静态安全测试
> 日期：2026-06-05
> 基线 commit：`6caf887819209cf1ff16a5feeb4d0052a922a656`
> 基线信息：`docs: add v1.9.3 web dashboard ux spec`

---

## 1. 本轮目标与结论

**v1.9.4 是命令白名单规格 + 静态安全测试任务：**

- ✅ 无 Bot 代码变更
- ✅ 无 Web 代码变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release
- ✅ 本规格和测试为后续实现创建安全门禁，但不批准实现

**结论：本规格定义了 Bot/Web 可调用的 `nanobk` CLI 命令白名单、禁止类别、风险分级、确认要求，以及静态测试如何防止不安全的命令执行模式。静态测试 `tests/bot-web-command-allowlist-v1.9.4.sh` 验证当前代码的安全边界。**

---

## 2. Allowlist 设计原则

### 控制面原则

| 原则 | 说明 |
|------|------|
| 控制面 only | Bot/Web 只是控制面，不是部署核心 |
| CLI-backed | Bot/Web 必须调用 `nanobk` CLI，不复制部署逻辑 |
| 禁止任意 shell | Bot/Web 不得调用任意 shell 命令 |
| 禁止 shell=True | subprocess 必须使用 list 形式 |
| 禁止直接写入 | Bot/Web 不得直接写 configs/systemd/secrets/env |
| 禁止直接读取 | Bot/Web 不得直接读取 raw env 内容 |
| 禁止直接 CF | Bot/Web 不得直接调用 Cloudflare 工具 |
| 禁止直接 systemctl | Bot/Web 不得直接调用 systemctl |
| List-based | 命令必须是 list 形式，不是字符串拼接 shell |
| 输出脱敏 | 输出必须先 redaction 再展示 |
| 高风险确认 | 高风险操作必须有确认机制 |

### 安全分层

```
┌──────────────────────────────────────────────────┐
│  Bot / Web 控制面                                 │
│  只调用已批准的 nanobk CLI 命令                    │
│  输出先脱敏再展示                                  │
│  高风险操作需确认                                  │
├──────────────────────────────────────────────────┤
│  nanobk CLI (bin/nanobk)                         │
│  统一命令入口                                      │
│  部署逻辑、状态查询、诊断、轮换                     │
├──────────────────────────────────────────────────┤
│  底层：installer / VPS templates / Workers        │
│  Bot/Web 绝不直接触碰                              │
└──────────────────────────────────────────────────┘
```

---

## 3. 命令风险级别

### L0 — 安全只读

| 属性 | 说明 |
|------|------|
| 定义 | 不修改任何状态，不输出敏感信息 |
| 确认 | 无，直接执行 |
| 展示 | 所有用户可见 |
| 示例 | `nanobk --version`、`nanobk --help` |

### L1 — 中风险诊断

| 属性 | 说明 |
|------|------|
| 定义 | 只读但输出可能含敏感信息 |
| 确认 | 简单警告或用户触发时明确提示 |
| 展示 | 新手看摘要，高级看 redacted 详情 |
| 示例 | `nanobk doctor`、`nanobk --json status`（需地址类 redaction 后） |

**规则：**

- 输出必须 redacted
- 新手视图只显示摘要
- Raw 详情仅高级可用
- 用户触发时显示警告

### L2 — 高风险变更

| 属性 | 说明 |
|------|------|
| 定义 | 修改凭证或服务状态 |
| 确认 | 两步确认 |
| 展示 | Redacted 结果摘要 + 恢复建议 |
| 示例 | `nanobk rotate <proto> --yes` |

**规则：**

- Owner-only
- 两步确认
- Web 需 CSRF
- Pending 确认过期机制
- Redacted 结果摘要
- 失败时给恢复建议
- 不展示 raw 输出

### L3 — 禁止 / 未批准

| 属性 | 说明 |
|------|------|
| 定义 | 不允许 Bot/Web 执行的类别 |
| 状态 | 硬性禁止 |
| 示例 | 任意 shell、systemctl、文件写入、env 读取 |

---

## 4. 当前 Bot 命令清单

基于 `bot/nanobk_bot.py` 实际代码：

| 处理器/函数 | 命令形状 | 风险 | shell=True | list-based | 输出脱敏 | 确认 | Allowlist 状态 |
|------------|----------|------|------------|------------|----------|------|---------------|
| `cmd_start()` | 不调用 CLI | 只读 | — | — | — | 无 | ✅ 允许（无 CLI 调用） |
| `cmd_help()` | 不调用 CLI | 只读 | — | — | — | 无 | ✅ 允许（无 CLI 调用） |
| `cmd_status()` | `nanobk --json status` | L1 中风险 | ❌ | ✅ | ✅ `safe_output()` | 无 | ⚠️ 允许，但需 v1.9.5 地址类 redaction |
| `cmd_status_json()` | `nanobk --json status` | L1 中风险 | ❌ | ✅ | ✅ `safe_output()` | 无 | ⚠️ 允许，但需隐藏（高级模式）+ v1.9.5 redaction |
| `cmd_doctor()` | `nanobk doctor` | L1 中风险 | ❌ | ✅ | ✅ `safe_output()` | 无 | ⚠️ 允许，但输出可能含路径/IP |
| `make_rotate_handler()` | `nanobk rotate <proto> --yes` | L2 高风险 | ❌ | ✅ | ✅ `safe_output()` | ✅ 两步确认 | ✅ 允许（有确认机制） |
| `cmd_confirm_rotate()` | `nanobk rotate <proto> --yes` | L2 高风险 | ❌ | ✅ | ✅ `safe_output()` | ✅ 两步确认 | ✅ 允许（有确认机制） |
| `cmd_cancel()` | 不调用 CLI | 只读 | — | — | — | 无 | ✅ 允许（无 CLI 调用） |
| `cmd_unknown()` | 不调用 CLI | 只读 | — | — | — | 无 | ✅ 允许（无 CLI 调用） |

### 关键发现

- ✅ 所有 CLI 调用使用 `subprocess.run()` + list 形式 + `shell=False`
- ✅ 无 `shell=True`
- ✅ 无 `os.system`
- ✅ 无直接文件写入
- ✅ 无直接 env 读取
- ✅ 无直接 systemctl 调用
- ✅ Rotate 有两步确认 + 120 秒过期
- ⚠️ `/status` 和 `/status_json` 的地址类 redaction 待 v1.9.5
- ⚠️ `/doctor` 输出可能含路径/IP，待证明安全

---

## 5. 当前 Web 命令清单

基于 `web/app.py` 实际代码：

| 路由/函数 | 命令形状 | 风险 | shell=True | list-based | 输出脱敏 | 确认 | Allowlist 状态 |
|----------|----------|------|------------|------------|----------|------|---------------|
| `healthz()` | 不调用 CLI | 只读 | — | — | — | 无 | ✅ 允许（无 CLI 调用） |
| `login()` | 不调用 CLI | 只读 | — | — | — | 无 | ✅ 允许（无 CLI 调用） |
| `logout()` | 不调用 CLI | 只读 | — | — | — | CSRF | ✅ 允许（无 CLI 调用） |
| `dashboard()` | `nanobk --json status` | L1 中风险 | ❌ | ✅ | ✅ `format_status()` + `redact_json()` | 无 | ⚠️ 允许，但需 v1.9.5 地址类 redaction |
| `status()` | `nanobk --json status` | L1 中风险 | ❌ | ✅ | ✅ `format_status()` + `safe_output()` | 无 | ⚠️ 允许，但需 v1.9.5 地址类 redaction |
| `api_status()` | `nanobk --json status` | L1 中风险 | ❌ | ✅ | ✅ `redact_json()` | 无 | ⚠️ 允许，但需 v1.9.5 地址类 redaction |
| `doctor()` | `nanobk doctor` | L1 中风险 | ❌ | ✅ | ✅ `safe_output()` | CSRF | ⚠️ 允许，但输出可能含路径/IP |
| `rotate()` | 不调用 CLI | 只读 | — | — | — | 无 | ✅ 允许（展示页面） |
| `rotate_request()` | 不调用 CLI | 只读 | — | — | — | CSRF | ✅ 允许（设置 pending） |
| `rotate_confirm()` | `nanobk rotate <proto> --yes` | L2 高风险 | ❌ | ✅ | ✅ `safe_output()` | ✅ 两步 + CSRF | ✅ 允许（有确认机制） |
| `rotate_cancel()` | 不调用 CLI | 只读 | — | — | — | CSRF | ✅ 允许（清除 pending） |

### 关键发现

- ✅ 所有 CLI 调用使用 `subprocess.run()` + list 形式 + `shell=False`
- ✅ 无 `shell=True`
- ✅ 无 `os.system`
- ✅ 无直接文件写入
- ✅ 无直接 env 读取
- ✅ 无直接 systemctl 调用
- ✅ 所有 POST 端点有 CSRF 保护
- ✅ Rotate 有两步确认 + CSRF + 120 秒过期
- ⚠️ Dashboard/Status/API 的地址类 redaction 待 v1.9.5
- ⚠️ Doctor 输出可能含路径/IP，待证明安全

---

## 6. 提议的 Allowlist 表

| CLI 命令模式 | 允许调用者 | 风险级别 | 用户级别 | 确认要求 | Redaction 要求 | 当前状态 | 备注 |
|-------------|-----------|----------|----------|----------|---------------|----------|------|
| `nanobk --version` | Both | L0 只读 | Beginner | 无 | 无（无敏感信息） | 未使用，可允许 | 版本信息 |
| `nanobk --help` | Both | L0 只读 | Beginner | 无 | 无（无敏感信息） | 未使用，可允许 | 帮助文本 |
| `nanobk --json status` | Both | L1 中风险 | Beginner/Advanced | 无 | ✅ 需地址类 redaction | ✅ 已使用 | v1.9.5 前仅高级视图 |
| `nanobk doctor` | Both | L1 中风险 | Beginner/Advanced | 简单警告 | ✅ 需 redaction | ✅ 已使用 | 输出可能含路径/IP |
| `nanobk rotate hy2 --yes` | Both | L2 高风险 | Owner | 两步确认 | ✅ safe_output | ✅ 已使用 | 有确认机制 |
| `nanobk rotate tuic --yes` | Both | L2 高风险 | Owner | 两步确认 | ✅ safe_output | ✅ 已使用 | 有确认机制 |
| `nanobk rotate reality --yes` | Both | L2 高风险 | Owner | 两步确认 | ✅ safe_output | ✅ 已使用 | 有确认机制 |
| `nanobk rotate trojan --yes` | Both | L2 高风险 | Owner | 两步确认 | ✅ safe_output | ✅ 已使用 | 有确认机制 |
| `nanobk rotate all --yes` | Both | L2 高风险 | Owner | 两步确认 | ✅ safe_output | ✅ 已使用 | 有确认机制 |
| 任意 shell 命令 | — | L3 禁止 | — | — | — | ❌ 未使用 | 硬性禁止 |
| `systemctl *` | — | L3 禁止 | — | — | — | ❌ 未使用 | 硬性禁止 |
| 直接文件写入 | — | L3 禁止 | — | — | — | ❌ 未使用 | 硬性禁止 |
| 直接 env 读取 | — | L3 禁止 | — | — | — | ❌ 未使用 | 硬性禁止 |

---

## 7. Denylist 类别

### 硬性禁止

| 类别 | 说明 | 检测方式 |
|------|------|----------|
| `shell=True` | subprocess 必须使用 list 形式 | 静态 grep |
| `os.system` | 禁止直接 shell 执行 | 静态 grep |
| 任意 subprocess from user input | 禁止用户输入拼接到命令 | 代码审查 |
| `systemctl` 直接调用 | 必须通过 nanobk CLI | 静态 grep |
| 直接写 `/etc/nanobk` | 必须通过 nanobk CLI | 静态 grep |
| 直接写 systemd unit | 必须通过 nanobk CLI | 静态 grep |
| 直接写 secrets/env | 必须通过 nanobk CLI | 静态 grep |
| 直接读取 env 文件 | 禁止 cat/read env 内容 | 静态 grep |
| 直接 CF Worker/env 写入 | 必须通过 nanobk CLI | 静态 grep |
| 直接协议配置写入 | 必须通过 nanobk CLI | 静态 grep |
| 直接订阅 URL 生成 | 必须通过 nanobk CLI | 代码审查 |
| Raw 日志文件倾倒 | 禁止直接 cat 日志 | 代码审查 |
| 新手视图 raw JSON | 禁止 | UX 测试 |
| Dirty VPS status wrapping | 禁止 | 未批准 |
| Production status wrapper | 禁止 | 未批准 |
| Operation-log full rollout | 禁止 | 未批准 |

---

## 8. 静态测试设计

### 测试文件

`tests/bot-web-command-allowlist-v1.9.4.sh`

### 测试目标

验证 Bot/Web 源代码不包含不安全的命令执行模式。

### 检查项

| # | 检查 | 说明 |
|---|------|------|
| 1 | 无 `shell=True` | Bot/Web subprocess 不使用 shell |
| 2 | 无 `os.system` | Bot/Web 不使用 os.system |
| 3 | 无直接 `systemctl` | Bot/Web 不直接调用 systemctl |
| 4 | 无直接写 `/etc/nanobk` | Bot/Web 不直接写配置目录 |
| 5 | 无直接写 systemd unit | Bot/Web 不直接写 service 文件 |
| 6 | 无直接读取 env 文件 | Bot/Web 不 cat/read 敏感 env |
| 7 | 无直接 CF 写入 | Bot/Web 不直接写 Cloudflare Worker/env |
| 8 | 无直接协议配置写入 | Bot/Web 不直接写协议配置 |
| 9 | 现有 mock 测试通过 | Bot/Web 测试继续通过 |

### 测试约束

- 仅检查源代码，不运行真实命令
- 不检查 `/etc/nanobk`、`/root` 等真实路径
- 不运行 status/doctor/rotate
- 不运行 Cloudflare 命令
- 不修改文件
- 区分代码中的运行时行为和文档/注释中的安全说明

---

## 9. 静态测试实现说明

### 实现要点

- 使用 bash + `set -euo pipefail`
- 计算 `REPO_DIR` 并 cd 到仓库根目录
- 打印清晰的 PASS/FAIL 行
- 仅检查 `bot/nanobk_bot.py`、`web/app.py`、`web/templates/*.html`
- 不检查真实 env 文件
- 不检查 `/etc/nanobk`、`/root`
- 不运行真实 nanobk 命令
- 不修改文件
- 违规时 exit 1

### 检测策略

- 使用 `grep -RInE` 在明确的文件列表上
- 对 clear runtime-dangerous 模式 fail
- 对仅在文档/注释/安全说明中出现的模式不过度 fail
- 保持测试逻辑可读、可维护

---

## 10. 与 v1.9.5 Redaction 的交互

### v1.9.4 不解决地址类 redaction

v1.9.4 定义命令白名单和执行安全边界，但不解决显示安全问题。

### v1.9.5 应处理

| 类别 | 当前覆盖 | v1.9.5 需新增 |
|------|----------|--------------|
| IPv4 地址 | ❌ | ✅ |
| IPv6 地址 | ❌ | ✅ |
| 域名 | ❌ | ✅ |
| URL | ❌ | ✅ |
| workers.dev | ❌ | ✅ |
| subscription URL/path | ❌ | ✅ |
| route URL | ❌ | ✅ |

### 实现阻塞

**在 v1.9.5 完成之前：**

- Status/raw JSON 的新手视图展示应保持实现阻塞
- `/status_json` 应保持隐藏
- Dashboard/Status 的地址类字段（IP/domain/URL）不应展示给新手

---

## 11. 与 Bot/Web UX 实现的交互

### 实现必须等待

Bot/Web UX 实现必须等到以下条件全部满足：

1. ✅ v1.9.4 Allowlist 静态门禁通过
2. ⬜ v1.9.5 Redaction 层测试通过
3. ⬜ ChatGPT 审核并批准小步实现 prompt

**本文件不批准任何实现。**

### 实现顺序

1. v1.9.4 — 命令白名单 + 静态测试（本文件）
2. v1.9.5 — Redaction 层 + 地址类 redaction 测试
3. 然后才能开始 Bot/Web UX 小步实现
4. 实现应小步、可 review、可回滚

---

## 12. 未来测试需求

### v1.9.4 之后的测试

| 测试 | 说明 | 前置 |
|------|------|------|
| Allowlist 测试集成到 CI | 每次提交运行 | v1.9.4 |
| Bot 菜单测试：新手无 raw JSON | 验证新手视图 | v1.9.2 + v1.9.5 |
| Web Dashboard 测试：新手无 raw JSON | 验证新手视图 | v1.9.3 + v1.9.5 |
| 地址类 redaction 测试 | IPv4/IPv6/domain/URL | v1.9.5 |
| Rotate 确认测试 | 两步确认 + CSRF | 现有 |
| Doctor 输出 redaction 测试 | 无路径/IP 泄露 | v1.9.5 |
| Direct-write guard 持续测试 | 防止回归 | v1.9.4 |

---

## 13. v1.9.3 实现顺序修正

### 问题

v1.9.3 spec 中的实现顺序建议存在小的排序问题：

```
1. v1.9.5 Redaction 层先就位
2. v1.9.4 Allowlist 先定义
```

这暗示 v1.9.5 应在 v1.9.4 之前，但版本号顺序是 v1.9.4 → v1.9.5。

### 修正

正确的实现顺序应为：

1. **v1.9.4** — 命令白名单 + 静态测试（本文件）— 定义执行安全边界
2. **v1.9.5** — Redaction 层 + 地址类 redaction 测试 — 定义显示安全边界
3. 两者都通过后：Bot/Web UX 小步实现

v1.9.4 和 v1.9.5 是并行安全门禁，都需要在实现前通过。版本号顺序（v1.9.4 先于 v1.9.5）不影响它们作为实现前置条件的并行关系。

---

## 14. v1.9.5 推荐

### 推荐：v1.9.5 — Redaction Layer Audit and Address-Class Redaction Tests

**理由：**

1. v1.9.1 审计发现当前 redaction 不覆盖 IP/domain/URL/workers.dev/subscription path
2. v1.9.2/v1.9.3 UX spec 要求地址类 redaction 在 status/raw JSON 实现前就位
3. v1.9.4 Allowlist 保护命令执行安全，但不保护显示安全
4. 两者（执行安全 + 显示安全）都需在实现前就位

**v1.9.5 应包含：**

- 当前 redaction 覆盖范围审计
- 地址类 redaction 需求规格（IPv4/IPv6/domain/URL/workers.dev/subscription path）
- Redaction 测试：验证覆盖范围
- Redaction 测试：验证 Bot/Web 输出不包含地址类信息
- `redact_text()` 和 `redact_json()` 的增强规格
- 实现优先级建议

---

## 15. Implementation Guardrails

### 硬性约束

以下约束适用于 v1.9.x 系列所有实现任务：

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止 Bot/Web 直接写 configs/systemd/secrets/env | 必须通过 nanobk CLI |
| 2 | 禁止新手视图展示 raw JSON | 使用安全摘要 |
| 3 | 禁止新手视图展示 raw IP/domain/URL/workers.dev/subscription path | 默认脱敏 |
| 4 | 禁止高风险操作无确认 | rotate/restart/repair 必须两步确认 |
| 5 | 禁止直接 systemctl | 必须通过 nanobk CLI |
| 6 | 禁止读取 env 内容 | 不读取 .env 文件 |
| 7 | 所有操作通过 nanobk CLI | 不绕过 CLI |
| 8 | 高风险操作两步确认 | 已有机制，保持并增强 |
| 9 | 禁止 production status wrapper | 未批准 |
| 10 | 禁止 dirty VPS status wrapping | 未批准 |
| 11 | 禁止 operation-log full rollout | 未批准 |
| 12 | 禁止修改 install.sh | 保护 v1.7.27 基线 |
| 13 | 禁止 tag/release | 未批准 |
| 14 | 所有输出经过 safe_output/redact_json | 包括失败输出 |
| 15 | 所有 POST 需要 CSRF 验证 | 已有机制 |
| 16 | 禁止 shell=True | subprocess 必须使用 list 形式 |

### 实现前必须完成

1. v1.9.2 Bot UX/Menu Spec — ✅ 已完成
2. v1.9.3 Web Dashboard UX Spec — ✅ 已完成
3. v1.9.4 Command Allowlist Spec/Tests（本文件）— ✅ 已完成
4. v1.9.5 Redaction Layer Audit/Tests — 待完成

---

## 附录 A：当前 Bot CLI 调用汇总

来自 `bot/nanobk_bot.py`：

```python
# run_nanobk() 封装
cmd = [config.nanobk_cli] + args
proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

# 实际调用
cmd_status()        → ["--json", "status"]
cmd_status_json()   → ["--json", "status"]
cmd_doctor()        → ["doctor"]
cmd_confirm_rotate() → ["rotate", proto, "--yes"]
```

## 附录 B：当前 Web CLI 调用汇总

来自 `web/app.py`：

```python
# run_nanobk() 封装
cmd = [config.nanobk_cli] + args
proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

# 实际调用
dashboard()         → ["--json", "status"]
status()            → ["--json", "status"]
api_status()        → ["--json", "status"]
doctor()            → ["doctor"]
rotate_confirm()    → ["rotate", protocol, "--yes"]
```

## 附录 C：参考文档

| 文档 | 说明 |
|------|------|
| `docs/planning-v1.9.0-bot-web-control-plane-productization.md` | v1.9 范围提案 |
| `docs/audit-v1.9.1-bot-web-current-state-safety.md` | v1.9.1 安全审计 |
| `docs/spec-v1.9.2-bot-ux-menu.md` | v1.9.2 Bot UX/Menu Spec |
| `docs/spec-v1.9.3-web-dashboard-ux.md` | v1.9.3 Web Dashboard UX Spec |
| `bot/nanobk_bot.py` | Bot 当前代码 |
| `web/app.py` | Web 当前代码 |
