# v1.9.33 — Doctor Output Productization Planning

> 规划类型：Doctor 输出产品化规划文档
> 日期：2026-06-05
> 基线 commit：`08dad0d8572dacfa0cebcf9f2c581f4c9aebbd58`
> 基线信息：`test: add v1.9.32 i18n checkpoint`

---

## 1. 本轮目标与结论

**v1.9.33 是规划/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release
- ✅ 目的是规划面向新手的 Doctor 输出产品化

**结论：定义安全的分阶段 Doctor 产品化路线——将当前过于技术化的 /doctor 输出拆分为面向新手的诊断摘要和面向维护者的完整诊断，先审计再实现。**

---

## 2. 为什么需要 Doctor 产品化

| 理由 | 说明 |
|------|------|
| 真实冒烟测试确认功能可用 | v1.9.28 PASS WITH POLISH |
| 真实冒烟测试标记过于技术化 | T14-P2-009: `/doctor` 输出对新手过于技术化 |
| 当前输出暴露系统结构 | OS/kernel、工具路径、配置路径、端口、服务名 |
| 新手需要简单答案 | 控制面正常吗？代理正常吗？Cloudflare 正常吗？下一步做什么？ |
| 维护者仍需完整诊断 | 排障需要详细信息 |
| Bot/Web i18n 已就绪 | 可以本地化摘要标签和警告 |
| 安全脱敏已集成 | redaction 已在路径中 |

---

## 3. 当前 Doctor 状态

### Bot /doctor

| 属性 | 说明 |
|------|------|
| 命令 | `/doctor` |
| 处理器 | `cmd_doctor()` |
| 执行路径 | `run_nanobk(config, ["doctor"])` → `safe_output()` → reply text |
| 输出处理 | `safe_output()` = strip ANSI + redact + limit text |
| i18n | 命令标签/帮助已翻译，输出本身是命令原始输出 |
| 安全 | owner-only、redacted、无 shell=True |

### Web /doctor

| 属性 | 说明 |
|------|------|
| 路由 | `/doctor` (GET/POST) |
| 处理器 | `doctor()` |
| 执行路径 | `run_nanobk(config, ["doctor"])` → `safe_output()` → render template |
| 输出处理 | `safe_output()` = strip ANSI + redact + limit text |
| i18n | 页面 chrome 已翻译，输出本身是命令原始输出 |
| 安全 | login-required、CSRF、redacted |

### CLI nanobk doctor

| 属性 | 说明 |
|------|------|
| 入口 | `bin/nanobk doctor` |
| 脚本 | `installer/doctor.sh` |
| 输出类型 | 文本（非 JSON） |
| 检查类别 | System Info、Required Tools、NanoBK Configuration、Cloudflare Admin Config、Systemd Services、Port Listening、Config Files |
| 输出内容 | OS/kernel/arch、工具路径、配置路径、admin env 路径、端口号、服务状态、systemd 单元名 |
| JSON 支持 | `--json` 返回占位符（planned for v1.x） |

### 共享状态

| 属性 | 说明 |
|------|------|
| Redaction | 已集成（`lib/nanobk_redaction.py`） |
| 高级模式 | Bot/Web 均存在（15 分钟 TTL） |
| Raw JSON 门控 | 存在但与 doctor 独立 |
| Production status wrapper | 未批准 |

---

## 4. 产品目标

| 目标 | 说明 |
|------|------|
| 新手安全摘要优先 | 默认展示简洁诊断结果 |
| 完整诊断仅作为高级/手动操作 | 不默认暴露技术细节 |
| 无伪造成功 | 失败必须可见 |
| 无原始密钥 | 不展示 token/secret/private key |
| 无原始 IP/domain/workers.dev/subscription URL | redaction 保护 |
| 清晰下一步 | 告诉用户该做什么 |
| Bot/Web 文案一致 | 两平台体验一致 |
| zh/en 兼容 | 利用现有 i18n |
| 仅控制面 | Bot/Web 只调用 CLI |
| 始终通过 nanobk CLI 或未来安全包装器 | 不直接读取 env |
| 失败必须可见 | 不隐藏错误 |

---

## 5. 提议 UX 模型

### 两层模型

**Layer 1: Doctor Summary（默认）**

面向新手的简洁诊断结果。

Bot:
- `/doctor` 默认返回摘要消息。

Web:
- Doctor 页面默认展示摘要卡片。

摘要内容：
- 人类可读结果
- 简短状态类别
- 简洁卡片/段落：
  - 控制面（Bot/Web 是否可用）
  - CLI 可用性（nanobk 是否可执行）
  - 配置/Profile（配置文件是否存在/有效）
  - 服务（HY2/TUIC/Reality/Trojan 状态）
  - Cloudflare/订阅（配置/验证状态）
  - 安全/redaction（权限、脱敏状态）
  - 下一步（明确操作建议）
- 无原始路径（除非必要）
- 无原始端口（除非明确安全）
- 无原始服务转储
- 无原始 env 路径
- 无原始 URL

**Layer 2: Full Diagnostics（高级模式）**

面向维护者的完整诊断。

Bot:
- 高级模式 ON 时，`/doctor` 同时展示摘要 + 完整脱敏输出。
- 或提供 `/doctor_full` 命令（仅高级模式可用）。

Web:
- 高级模式 ON 时，Doctor 页面展示完整脱敏输出详情。
- 默认折叠，点击展开。

两者：
- 仍然脱敏
- 仍然有警告保护
- 仍然不可直接分享

---

## 6. Bot Doctor 设计选项

### 选项 A: /doctor 变为摘要，/doctor_full 为完整输出

| 优点 | 缺点 |
|------|------|
| 清晰分离 | 需要新命令 |
| 新手默认安全 | 改变现有 /doctor 行为 |
| 符合产品哲学 | 需要更新 /help |

### 选项 B: /doctor 保持完整输出，新增 /doctor_summary

| 优点 | 缺点 |
|------|------|
| 不改变现有行为 | 新手仍然看到技术输出 |
| 向后兼容 | 需要知道新命令 |
| 实现简单 | 不符合新手优先 |

### 选项 C: /doctor 行为取决于高级模式

| 优点 | 缺点 |
|------|------|
| 与 Raw JSON 门控一致 | 实现复杂度较高 |
| 无需新命令 | 改变现有行为 |
| 自动切换 | 高级模式用户可能只想看摘要 |

行为：
- 高级 OFF：`/doctor` 返回新手摘要
- 高级 ON：`/doctor` 返回摘要 + 完整脱敏诊断输出或提示 `/doctor_full`

### 选项 D: 保持运行时不变，仅添加警告文案

| 优点 | 缺点 |
|------|------|
| 最小变更 | 不解决根本问题 |
| 零风险 | 新手仍看到技术输出 |

### 推荐

**推荐选项 C**，与 Raw JSON 门控保持一致：

- 高级 OFF：`/doctor` 返回新手摘要
- 高级 ON：`/doctor` 返回摘要 + 完整脱敏输出

**备选：** 如实现复杂度高，可先实现选项 A（v1.9.36），后续再合并为选项 C。

**不推荐选项 B/D：** 不符合新手优先产品哲学。

---

## 7. Web Doctor 设计选项

### 选项 A: 默认摘要卡片，高级模式显示完整输出

| 优点 | 缺点 |
|------|------|
| 与 Bot 选项 C 一致 | 需要模板重构 |
| 新手默认安全 | 实现工作量 |
| 利用现有高级模式 | — |

### 选项 B: 保持完整输出但添加警告

| 优点 | 缺点 |
|------|------|
| 最小变更 | 不解决根本问题 |
| — | 新手仍看到技术输出 |

### 选项 C: 分离标签页

| 优点 | 缺点 |
|------|------|
| 清晰分离 | 需要更多模板工作 |
| 用户可选择 | 复杂度 |
| 两种输出都可访问 | — |

实现：
- 标签 1: Summary（默认可见）
- 标签 2: Advanced Details（高级模式门控）
- 完整脱敏输出默认折叠

### 选项 D: 分离路由

| 优点 | 缺点 |
|------|------|
| URL 可分享 | 需要新路由 |
| 清晰分离 | — |

实现：
- `/doctor` — 摘要
- `/doctor/full` — 完整输出（高级模式门控）

### 推荐

**推荐选项 C**（如模板工作合理）：

- Summary 标签默认可见
- Advanced Details 标签由高级模式门控
- 完整脱敏输出默认折叠

**备选：** 选项 A（更简单）。

---

## 8. Doctor 摘要数据源策略

### 选项对比

| 选项 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| A. 解析现有 nanobk doctor 文本输出 | 从文本提取安全类别 | 无需 CLI 变更 | 脆弱解析、依赖输出格式 |
| B. 新增 nanobk doctor --json 安全摘要 | CLI 输出结构化 JSON | 稳定、可解析 | 需要 CLI 变更（单独规划） |
| C. 复用 nanobk --json status + 选定 doctor 检查 | 组合现有 JSON | 已有 JSON | 可能信息不足 |
| D. 仅使用静态引导 | 不运行命令 | 最简单 | 无实际诊断 |

### 推荐分阶段策略

**v1.9.x 规划阶段：**

- 优先考虑未来安全 JSON 摘要（选项 B），如果可行。
- 最小首次实现可能仅解析现有模拟输出（选项 A），前提是解析足够健壮。
- 避免脆弱的长文本解析。
- 不运行 production status wrapper。
- 不从 Bot/Web 直接读取 env。

**重要：** 未来实现可能需要 CLI 级别的安全 doctor 摘要命令，但那需要单独规划。

**不推荐选项 D：** 无法提供实际诊断信息。

---

## 9. 脱敏与信息分类策略

### 新手摘要允许内容

| 类别 | 示例 |
|------|------|
| 状态词 | healthy / failed / unknown / partial |
| 存在性 | present / missing |
| 活跃性 | active / inactive |
| 配置性 | configured / not configured |
| 权限模式 | mode 600 |
| 通用描述 | "Cloudflare configured" |
| 通用订阅状态 | "Subscription status unknown/verified" |
| 下一步建议 | "Run /doctor or check SSH" |

### 谨慎允许内容

| 类别 | 说明 |
|------|------|
| 服务名 | HY2/TUIC/Reality/Trojan（名称本身） |
| 通用端口存在性 | "HY2 port listening"（不一定显示端口号） |
| OS 族 | Ubuntu/Debian（不显示内核细节） |
| 配置存在性 | "Config present/missing"（不显示完整路径） |

### 仅高级模式允许

| 类别 | 说明 |
|------|------|
| OS/kernel 细节 | 内核版本、架构 |
| 工具路径 | /usr/local/bin/nanobk 等 |
| 配置路径 | /etc/nanobk/ 等 |
| systemd 单元名 | nanobk-hy2.service 等 |
| 端口号 | 443、9443、8443、2443 |
| 原始诊断命令输出 | 完整 doctor 输出 |
| Token 指纹 | 如仍允许 |

### 永远不允许

| 类别 | 说明 |
|------|------|
| 原始 token | Bot token、API token |
| 原始 private key | Reality private key |
| 原始 env 内容 | .env 文件内容 |
| 原始 IP/domain/URL | VPS IP、域名、订阅 URL |
| workers.dev | Worker URL |
| subscription URL/path | 订阅路径 |
| admin env 内容 | admin env 文件内容 |

---

## 10. i18n 交互

| 属性 | 说明 |
|------|------|
| Bot/Web i18n | 已就绪（v1.9.30/v1.9.31） |
| 摘要标签 | 应使用 zh/en 翻译 |
| 警告文案 | 应使用 zh/en 翻译 |
| 不翻译原始诊断输出 | 保持命令原始输出 |
| 翻译包装器标签 | 状态卡片、警告、下一步 |
| 保持机器状态值稳定 | healthy/failed/unknown 等不翻译 |
| 测试 | 后续添加 zh/en 测试 |

---

## 11. 测试策略

### 静态/源码测试

| 检查 | 说明 |
|------|------|
| /doctor 摘要文本存在 | 源码中有摘要构建逻辑 |
| /doctor_full 或高级完整输出路径被门控 | 如实现 |
| 高级模式要求完整详情 | 门控行为 |
| 完整输出警告存在 | 警告文案 |
| Redaction 仍在路径中 | 共享 redaction 导入 |
| 无原始 URL/密钥在 doctor 摘要中 | 安全 |
| 无直接 env 读取 | 安全 |
| 无直接 systemd/config 写入 | 安全 |

### Mock 测试

| 检查 | 说明 |
|------|------|
| 假 doctor 输出含密钥/IP/URL 被脱敏 | redaction 测试 |
| 摘要提取安全类别 | 解析测试 |
| 失败仍然可见 | 不隐藏错误 |
| unknown 状态诚实显示 | 不伪造成功 |

### Bot 测试

| 检查 | 说明 |
|------|------|
| /doctor OFF 返回摘要 | 默认行为 |
| /doctor ON 行为如设计 | 高级模式行为 |
| /doctor_full 如选择则被门控 | 门控行为 |
| zh/en 标签 | i18n |

### Web 测试

| 检查 | 说明 |
|------|------|
| Doctor 页面默认摘要 | 默认行为 |
| 高级详情被门控 | 门控行为 |
| 完整详情默认折叠 | UX |
| zh/en 标签 | i18n |

### 回归测试

| 检查 | 说明 |
|------|------|
| 现有 v1.9 测试通过 | 不破坏现有功能 |
| 无需真实 VPS/Cloudflare | mock 测试 |

---

## 12. 提议实现路线

| 版本 | 内容 | 范围 |
|------|------|------|
| **v1.9.33** | Doctor Output Productization Planning | ✅ 本文档 |
| **v1.9.34** | Doctor Output Current-State Audit | 审计当前 Bot/Web/CLI doctor 路径，确定安全钩子，无运行时变更 |
| **v1.9.35** | Doctor Summary Contract / Fixture Tests | 定义假 doctor/status 输入，定义预期新手摘要，redaction 测试，无运行时变更 |
| **v1.9.36** | Bot Doctor Summary Minimal Implementation | 仅 Bot，默认摘要，完整输出暂不暴露（除非单独门控） |
| **v1.9.37** | Web Doctor Summary Minimal Implementation | 仅 Web，摘要卡片，完整详情门控/折叠 |
| **v1.9.38** | Doctor Output Checkpoint | 检查点验证 |

**不推荐在一步中同时实现 Bot 和 Web doctor 变更。**

---

## 13. 就绪决策

**A. READY FOR DOCTOR OUTPUT CURRENT-STATE AUDIT**

约束：
- 仅审计
- 无运行时变更
- 无 CLI 行为变更
- 无真实 doctor 执行
- 无 production status wrapper
- 无 release/tag

---

## 14. 与未来任务的交互

| 任务 | 状态 | 说明 |
|------|------|------|
| Bot/Web systemd 产品化 | 独立任务 | 未来规划 |
| Web production runner | 独立任务 | 未来规划 |
| Fingerprint redaction 策略 | 独立任务 | 未来规划 |
| CLI 版本显示策略 | 独立任务 | 未来规划 |
| Raw subscription 交付 | 阻塞 | 未批准 |
| Production status wrapper | 阻塞 | 未批准 |
| Release candidate clean VPS 回归 | 阻塞 | 等待发布候选 |

---

## 15. Guardrails

| # | 约束 | 说明 |
|---|------|------|
| 1 | 无 install.sh 行为变更 | 保护 v1.7.27 基线 |
| 2 | 无 bin/nanobk 行为变更（规划中） | 保护 CLI 核心 |
| 3 | 无协议模板变更 | 保护部署 |
| 4 | 无 Worker 变更 | 保护 Cloudflare |
| 5 | 无 rotate sync 变更 | 保护轮换 |
| 6 | 无直接 Bot/Web 写入 configs/systemd/secrets | 安全 |
| 7 | 无 raw env 读取 | 安全 |
| 8 | 无 production status wrapper | 未批准 |
| 9 | 无 dirty VPS status wrapping | 未批准 |
| 10 | 无 operation-log full rollout | 未批准 |
| 11 | 无 raw subscription 交付 | 未批准 |
| 12 | 无 tag/release | 未批准 |
