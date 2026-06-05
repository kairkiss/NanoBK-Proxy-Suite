# v1.9.28 — Real Bot/Web Smoke Test Validation

> 验证类型：真实 Bot/Web 冒烟测试验证文档
> 日期：2026-06-05
> 基线 commit：`094d6e740c4c0a5546db778a79dcd1ffd8ce5bba`
> 基线信息：`docs: add v1.9.27 bot web smoke test plan`

---

## 1. 本轮目标与结论

**v1.9.28 记录了用户手动执行的真实 Bot/Web 冒烟测试：**

- ✅ 本文档仅记录测试结果
- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release
- ✅ 测试结果：**PASS WITH POLISH**

**结论：v1.9.27 有限真实 Bot/Web 冒烟测试已在真实 VPS 控制面环境手动执行。Web 控制面通过，Bot 控制面通过，Raw JSON 门控通过，高级模式通过，脱敏通过，dry-run rotate 流程未破坏服务。未观察到 P0/P1 泄露。剩余问题为产品化打磨和规划项。**

---

## 2. 测试性质与范围

| 属性 | 说明 |
|------|------|
| 测试类型 | 第十四次真实控制面测试 |
| 测试范围 | 仅限控制面 |
| 是否完整重部署 | 否 |
| 是否发布验证 | 否 |
| 是否 tag/release 批准 | 否 |
| 关注点 | Bot/Web 状态、诊断、高级模式、Raw JSON 门控、脱敏、安全 UI |

---

## 3. 测试环境摘要

| 属性 | 值（脱敏） |
|------|-----------|
| 操作系统 | Ubuntu 24.04.1 LTS |
| 用户 | root |
| systemd | 可用 |
| Python | 3.12 |
| 现有服务 | 四协议服务已存在并保持活跃 |
| VPS 环境 | 脏/测试环境 |
| 仓库状态 | 更新至 v1.9.27 commit |
| CLI 版本显示 | nanobk 1.8.45（记录为版本显示打磨项） |

**不包含：真实 IP、真实域名、真实 token。**

---

## 4. 初始环境发现

| 发现 | 说明 | 状态 |
|------|------|------|
| 旧仓库/测试目录存在 | 先前测试遗留 | 已知 |
| 全局 nanobk 最初缺失 | 使用 `nanobk install-cli` 恢复 | 已解决 |
| 四协议服务存在 | HY2/TUIC/Reality/Trojan 保持活跃 | 正常 |
| CLI 版本显示不匹配 | 仍显示 1.8.45 | 记录为打磨项 |

**不包含：真实路径（除通用 `/opt/NanoBK-Proxy-Suite` 和 `/usr/local/bin/nanobk`）。**

---

## 5. CLI / Status 验证

| 检查项 | 结果 |
|--------|------|
| `nanobk --json status` 返回码 | rc=0 |
| JSON 有效性 | 有效 JSON |
| 预期字段存在 | 是 |
| 敏感原始字段 | 存在，但 Bot/Web redaction/门控保护 UI |
| 真实值泄露 | 未包含 |

---

## 6. 本地测试套件结果

| 测试类别 | 结果 |
|----------|------|
| Mock 测试（bot-cli-mock, web-panel-mock） | ✅ 通过 |
| Allowlist 测试 | ✅ 通过 |
| Redaction 测试（合约、helper、Bot/Web 集成） | ✅ 通过 |
| Raw JSON 门控检查点 | ✅ 通过 |
| Bot 控制中心测试（菜单、回调、检查点） | ✅ 通过 |
| Bot self-test | ✅ 93/93 通过 |
| Web self-test | ✅ 62/62 通过 |

---

## 7. Web Panel 真实测试结果

| 步骤 | 结果 |
|------|------|
| `nanobk install --mode web --defaults --lang zh` | ✅ 成功 |
| `web/.env` 权限 | ✅ mode 600 root:root |
| Web self-test | ✅ 通过 |
| `run.sh` 启动本地 Web | ✅ 127.0.0.1:8080 |
| `/healthz` | ✅ ok |
| `/login` 可访问 | ✅ |
| Dashboard 安全卡片 | ✅ 显示预期状态段 |
| Status 安全卡片 | ✅ 显示预期状态段 |
| `/api/status` | ✅ 可访问，脱敏 |
| Doctor 页面 | ✅ 可访问 |
| Rotate 页面 | ✅ 可访问 |
| 无 raw IP/domain/workers.dev/subscription URL/token/private key 观察 | ✅ |
| Raw JSON OFF 状态 | ✅ 显示锁定面板，不渲染 raw_json |
| Raw JSON ON 状态 | ✅ 显示警告 + details，默认折叠 |
| `/api/status` 未门控但脱敏 | ✅ |
| logout/off 重置锁定 | ✅ |
| Web rotate dry-run request/confirm 流程 | ✅ 通过 |
| 服务在 dry-run rotate 后保持活跃 | ✅ |
| **Web 结论** | **PASS** |

**限制：** run.sh 手动启动、Flask 开发服务器、真实 rotate 未测试。

---

## 8. Telegram Bot 真实测试结果

| 步骤 | 结果 |
|------|------|
| `nanobk install --mode bot --lang zh` | ✅ 成功 |
| `bot/.env` 权限 | ✅ mode 600 root:root |
| Bot self-test | ✅ 通过 |
| Bot dry-run | ✅ true |
| Bot run.sh/nohup/setsid 启动进程 | ✅ |
| Telegram 连接 | ✅ 存在 |
| `/start` | ✅ 显示 NanoBK Control Center 按钮 |
| `/help` | ✅ 显示 Basic / Safe operations / Advanced diagnostics |
| `/status` | ✅ 显示安全摘要 |
| `/status_json` OFF | ✅ 未输出 JSON |
| `/advanced on` | ✅ 显示警告 |
| `/status_json` ON | ✅ 显示警告 + redacted Raw JSON |
| `/advanced off` | ✅ |
| `/status_json` after OFF | ✅ 返回锁定/引导状态 |
| `/doctor` | ✅ 显示诊断（含脱敏） |
| **按钮测试** | |
| Status Summary | ✅ |
| Recovery Help | ✅ |
| Diagnostics | ✅ |
| Advanced Mode | ✅ |
| Rotate Secrets | ✅ |
| Web Panel | ✅ |
| Help | ✅ |
| Bot 进程和 Telegram 连接保持健康 | ✅ |
| **Bot 结论** | **PASS** |

**限制：** 无 systemd 服务、`/doctor` 输出技术性强/长。

---

## 9. 安全结论

### 未观察到泄露

| 数据类 | 是否泄露 |
|--------|----------|
| Raw IPv4 | 否 |
| Raw IPv6 | 否 |
| Raw domain | 否 |
| workers.dev URL | 否 |
| subscription URL/path | 否 |
| Telegram Bot token | 见第 11 节 |
| Cloudflare token | 否 |
| Admin token raw value | 否 |
| Reality private key | 否 |
| raw env content | 否 |

### 未执行操作

| 操作 | 状态 |
|------|------|
| 完整重部署 | ❌ 未执行 |
| Cloudflare 变更 | ❌ 未执行 |
| 真实 rotate | ❌ 未执行 |
| repair/restart | ❌ 未执行 |
| production status wrapper | ❌ 未执行 |
| dirty VPS status wrapping | ❌ 未执行 |
| raw subscription delivery | ❌ 未执行 |
| subscription QR delivery | ❌ 未执行 |
| tag/release | ❌ 未执行 |

### 已执行操作

| 操作 | 状态 |
|------|------|
| Web dry-run rotate confirm | ✅ 执行 |
| Bot 控制面命令 | ✅ 执行 |
| Web login/status/doctor/rotate | ✅ 执行 |
| Bot start/help/status/status_json/advanced/doctor/buttons | ✅ 执行 |

---

## 10. 问题矩阵

| ID | 严重度 | 发现 | 状态 | 推荐下一步 |
|----|--------|------|------|-----------|
| T14-P0-001 | P0 | 仓库最初为旧状态 | 已解决 | — |
| T14-P1-001 | P1 | 全局 nanobk 最初缺失 | 已解决 | — |
| T14-P2-001 | P2 | CLI 版本仍显示 1.8.45 | 记录 | 版本策略规划 |
| T14-P1-005 | P1 | Bot/Web 未 systemd 产品化 | 记录 | 需规划 |
| T14-P2-007 | P2 | Web 使用 Flask 开发服务器 | 记录 | 需生产 runner 规划 |
| T14-P2-008 | P2 | Bot/Web 需 zh/en i18n | 记录 | v1.9.29 规划 |
| T14-P2-009 | P2 | `/doctor` 输出过于技术化 | 记录 | 需产品化规划 |
| T14-P2-010 | P2 | token/admin fingerprint 字段可能需更严格 redaction 策略 | 记录 | 需策略规划 |
| T14-TEST-001 | 测试 | 初始 rotate 端点探测错误 | 已纠正 | — |

---

## 11. Token 暴露后续

**重要安全事项：**

- 测试期间，真实 Bot token 被粘贴到聊天中
- **必须通过 BotFather 撤销/重新生成该 token**
- 暴露的 token 不得用于生产环境
- 未来报告不得包含 token 或 env 内容
- 如继续 Bot 测试，请安全更新 bot token，不打印 env 内容

**不包含 token 值。**

---

## 12. 总体结论

**v1.9.27 有限真实 Bot/Web 冒烟测试：PASS WITH POLISH**

**通过原因：**

- Web 控制面通过
- Bot 控制面通过
- Raw JSON 门控通过
- 高级模式通过
- 脱敏通过
- dry-run rotate 流程未破坏服务
- 未观察到 P0/P1 泄露

**非纯 PASS 原因（打磨项）：**

- Bot/Web 未 systemd 产品化
- Web 使用 Flask 开发服务器
- Bot/Web 需 zh/en i18n
- `/doctor` 输出对新手过于技术化
- Raw JSON token/admin 指纹可能需更严格 redaction 策略
- Bot token 在测试期间暴露，必须撤销/重新生成

---

## 13. 推荐下一步

**推荐：v1.9.29 — Bot/Web i18n Planning**

**理由：** 真实 Bot/Web 冒烟测试后，最大的用户面向差距是语言/产品文案。Bot/Web 可用但英文为主；zh/en 规划应在更深入实现前进行。

**其他未来规划项：**

- Doctor 输出产品化规划
- Bot/Web systemd 安装规划
- Web 生产 runner 规划
- Fingerprint redaction 策略
- Raw subscription delivery 安全设计
- 发布候选完整干净 VPS 回归

---

## 14. 仍然阻塞的事项

| 事项 | 状态 | 说明 |
|------|------|------|
| Release/tag | 阻塞 | 未批准 |
| Raw subscription delivery | 阻塞 | 需独立安全设计 |
| Subscription QR delivery | 阻塞 | 需独立安全设计 |
| Production status wrapper | 阻塞 | 未批准 |
| Dirty VPS status wrapping | 阻塞 | 未批准 |
| Operation-log full rollout | 阻塞 | 未批准 |
| 直接 Bot/Web repair/restart | 阻塞 | 未实现 |
| Cloudflare 变更操作 | 阻塞 | 未实现 |
| 完整真实 VPS 部署回归 | 阻塞 | 等待发布候选或核心变更 |

---

## 15. Guardrails

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止修改 `install.sh` | 保护 v1.7.27 基线 |
| 2 | 禁止修改 `bin/nanobk` | 保护 CLI 核心 |
| 3 | 禁止修改协议模板 | 保护部署 |
| 4 | 禁止修改 Worker | 保护 Cloudflare |
| 5 | 禁止修改 rotate sync | 保护轮换 |
| 6 | 禁止直接 Bot/Web 写入 configs/systemd/secrets | 安全 |
| 7 | 禁止 raw env 读取 | 安全 |
| 8 | 禁止 raw secret 展示 | 安全 |
| 9 | 禁止 tag/release | 未批准 |
