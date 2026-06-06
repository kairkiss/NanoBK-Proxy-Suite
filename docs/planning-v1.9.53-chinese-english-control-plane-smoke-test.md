# v1.9.53 — Chinese/English Control Plane Smoke Test Plan

> 规划类型：中英文控制面冒烟测试计划
> 日期：2026-06-06
> 基线 commit：`a6365f955e83e7d8c267c2c1be9af62edb189abe`
> 基线信息：`feat: add bot language guidance`

---

## 1. 本轮目标与结论

**v1.9.53 是规划/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无安装器行为变更
- ✅ 无 env 文件读写
- ✅ 无 tag/release
- ✅ 目的是定义安全的用户运行真实中英文控制面冒烟测试计划

**结论：本计划定义用户可在真实 VPS 上运行的中英文 Bot/Web 控制面冒烟测试流程。测试范围限于控制面行为验证，不包含部署/Cloudflare/rotate 变更。v1.9.52 报告的 `tests/web-language-switch-v1.9.51.py` 5 个预先存在源码级检查失败必须在真实冒烟前解决或明确记录。**

---

## 2. 当前语言功能状态

| 功能 | 状态 | 来源 |
|------|------|------|
| Bot/Web 默认中文 | ✅ 已实现 | v1.9.48 |
| 显式英文 `NANOBK_LANG=en` | ✅ 已实现 | v1.9.48 |
| 安装器写入 `NANOBK_LANG=zh\|en` | ✅ 已实现 | v1.9.49 |
| Web session 级 zh/en 切换 | ✅ 已实现 | v1.9.51 |
| Bot `/language` 引导命令 | ✅ 已实现 | v1.9.52 |
| 持久 CLI 语言命令 | ❌ 未实现 | 长期任务 |
| Bot 运行时语言切换 | ❌ 未实现 | 仅引导，不切换 |
| 真实中英文冒烟测试 | ❌ 未执行 | 本文档计划 |

---

## 3. 已知预检测试债务

### 问题描述

v1.9.52 验证记录指出：`tests/web-language-switch-v1.9.51.py` 有 5 个预先存在的源码级检查失败（52 passed, 5 failed）。

这不是 v1.9.52 Bot 变更引起的。在 v1.9.52 变更前后，该测试结果相同。

### 失败区域

5 个失败位于 "Language route" 源码级检查区域：

- `/language is POST only` — 检查 `lang_decorator_area` 中的 "POST"
- `/language requires login` — 检查 `lang_decorator_area` 中的 "require_login"
- `/language validates CSRF` — 检查 `lang_body` 中的 "validate_csrf"
- `/language accepts lang form field` — 检查 `lang_body` 中的 'request.form.get("lang"'
- `/language stores valid lang` — 检查 `lang_body` 中的 'session["lang"]'

根本原因：测试使用 `web_source.split("def language(")` 定位语言路由代码，但该分割可能匹配到测试文件自身对 `def language(` 的引用，而非 `web/app.py` 中的实际函数定义。这是测试的源码级模式匹配问题，不是 Web 语言切换功能的问题。

### 预检决策

在运行真实冒烟测试前，测试者必须：

1. **重新运行** `python3 tests/web-language-switch-v1.9.51.py`
2. 如果全部通过 → 记录为 PASS，继续冒烟测试
3. 如果仍有 5 个失败 → 检查失败名称，确认是否与上述分析一致
4. 如果失败名称一致 → 记录为已知测试债务（源码级模式匹配假阳性），继续冒烟测试
5. 如果失败名称不一致或有新失败 → 标记为潜在真实问题，不继续到稳定 tag

**此测试债务必须在 v1.9 稳定收口前解决或明确分类。**

---

## 4. 测试范围

### 包含

| 组件 | 测试内容 |
|------|----------|
| Bot 启动 | Bot 进程正常启动 |
| Bot /start | 默认语言显示 |
| Bot /help | 默认语言显示，包含 /language |
| Bot /language | 当前语言和引导显示 |
| Bot /status | 安全摘要正常 |
| Bot /doctor Advanced OFF | 仅摘要 |
| Bot /advanced on/off/status | 高级模式切换 |
| Bot /status_json gate | Advanced OFF 时阻止 |
| Bot 按钮回调 | 控制中心菜单正常 |
| Web 启动 | 本地 127.0.0.1 启动 |
| Web 登录 | token 登录正常 |
| Web Dashboard | 默认中文 |
| Web Status | 默认中文 |
| Web Doctor | 默认中文 |
| Web 语言切换 zh→en→zh | UI 切换即时生效 |
| Web Raw JSON gate | Advanced OFF 时锁定 |
| /api/status | schema 不变，已脱敏 |
| 四协议服务 | 保持活跃 |
| 泄漏检查 | 无 raw IP/domain/token/workers.dev/subscription URL/private key |

### 不包含

| 项目 | 原因 |
|------|------|
| 完整 VPS 部署 | 不在控制面测试范围 |
| Cloudflare 变更 | 安全边界 |
| 真实 rotate | 安全边界 |
| 修复/重启 | 安全边界 |
| 生产 status wrapper | 未批准 |
| dirty VPS status wrapper | 未批准 |
| raw subscription delivery | 未批准 |
| systemd 安装 | 独立任务 |
| Web 生产 runner | 独立任务 |
| tag/release | 未批准 |

---

## 5. 预检清单

### 环境确认

- [ ] 确认 repo HEAD 等于测试版本预期 commit
- [ ] 确认工作目录干净（`git status -sb`）
- [ ] 确认无旧 Bot/Web 进程残留（如测试最新代码）
- [ ] 确认 env 文件权限为 600（不打印内容）

### 聚焦语言测试重运行

```bash
python3 tests/chinese-default-v1.9.48.py
python3 tests/bot-language-command-v1.9.52.py
python3 web/app.py --self-test
python3 bot/nanobk_bot.py --self-test
```

### Web 语言切换测试债务处理

```bash
python3 tests/web-language-switch-v1.9.51.py
```

- 如果 PASS → 记录
- 如果 5 个失败 → 记录失败名称，对照第 3 节分析
- 如果失败名称一致 → 记录为已知测试债务，继续
- 如果不一致 → 标记问题，不继续到稳定 tag

### 安全规则

- [ ] 不打印 env 内容
- [ ] 不粘贴 raw JSON 或 raw doctor 输出
- [ ] 不粘贴 token/IP/domain/subscription URL/workers.dev

---

## 6. Bot 中英文冒烟清单

### 中文默认行为

| 步骤 | 预期 | P0/P1 泄漏检查 |
|------|------|-----------------|
| Bot 启动 | 正常启动，无崩溃 | 无 token 泄漏 |
| `/start` | 控制中心中文标题 + 按钮 | 无 raw URL |
| `/help` | 中文帮助，包含 `/language` | 无 token |
| `/language` | 显示当前中文、NANOBK_LANG 来源、中文默认、英文可用 | 无 env 路径/token |
| `/status` | 中文标签安全摘要 | 无 raw IP/domain |
| `/doctor` Advanced OFF | 仅中文摘要，无完整诊断 | 无 raw path |
| `/advanced on` | 中文警告消息 | — |
| `/doctor` Advanced ON | 中文摘要 + 警告 + 脱敏完整诊断 | 无 raw token/IP |
| `/advanced off` | 中文禁用消息 | — |
| `/status_json` Advanced OFF | 中文门控消息，无 JSON | — |
| 按钮回调 | 各菜单中文引导 | 无 raw URL |
| 最终服务检查 | 四协议服务保持活跃 | — |

### 英文行为（有限）

Bot 目前不支持运行时语言切换。测试英文 Bot 有以下选项：

**选项 A：使用安全测试 env/config 方法**

如果有安全的测试环境，可设置 `NANOBK_LANG=en` 后重启 Bot 验证英文行为。**不要编辑/粘贴真实 env 内容。**

**选项 B：推迟完整英文 Bot 测试**

等到持久 CLI 语言命令实现后再测试。当前 `/language` 引导已确认英文可用，Bot i18n 字典已验证英文翻译存在。

**推荐：选项 B** — Bot 英文行为通过 i18n 测试已验证，真实冒烟可推迟。

---

## 7. Web 中英文冒烟清单

### 中文默认行为

| 步骤 | 预期 | P0/P1 泄漏检查 |
|------|------|-----------------|
| Web 启动（本地 127.0.0.1） | 正常启动 | 无 token 泄漏 |
| 登录 | token 登录正常 | — |
| Dashboard | 中文标题、中文卡片标签 | 无 raw IP/domain |
| Status | 中文标签、中文卡片 | 无 raw IP/domain |
| Doctor | 中文标题、中文摘要 | 无 raw path |
| Raw JSON gate Advanced OFF | 中文锁定面板 | 无 JSON 暴露 |

### 英文切换行为

| 步骤 | 预期 | P0/P1 泄漏检查 |
|------|------|-----------------|
| 点击语言切换按钮 | 切换到英文 | — |
| Dashboard | 英文标题、英文卡片标签 | 无 raw IP/domain |
| Status | 英文标签、英文卡片 | 无 raw IP/domain |
| Doctor | 英文标题、英文摘要 | 无 raw path |
| Raw JSON gate Advanced OFF | 英文锁定面板 | 无 JSON 暴露 |
| 切换回中文 | 即时生效 | — |
| Dashboard | 中文标题 | — |
| 登出 | session 语言重置 | — |
| 重新登录 | 使用 config/默认语言 | — |
| `/api/status` | schema 不变，已脱敏 | 无 raw token/IP |

---

## 8. 脱敏和泄漏清单

### P0 关键泄漏

| 数据类 | 检查方法 | 预期 |
|--------|----------|------|
| raw token | Bot/Web 所有输出 | 不出现 |
| private key | Bot/Web 所有输出 | 不出现 |
| env 内容 | Bot/Web 所有输出 | 不出现 |
| subscription URL/path | Bot/Web 所有输出 | 不出现 |
| Reality private key | Bot/Web 所有输出 | 不出现 |

### P1 高风险泄漏

| 数据类 | 检查方法 | 预期 |
|--------|----------|------|
| raw IP/domain/workers.dev | 初学者 UI | 不出现 |
| Raw JSON Advanced OFF 时可见 | Web Status 页面 | 锁定 |
| 完整诊断 Advanced OFF 时可见 | Bot/Web Doctor | 仅摘要 |
| 语言路由 CSRF/login 绕过 | Web /language | 需要登录+CSRF |
| Bot /language 暴露 env 路径/内容 | Bot /language 输出 | 不出现 |

### P2 打磨项

| 项目 | 说明 |
|------|------|
| 混合语言文案 | 部分中文/部分英文 |
| 翻译生硬 | 某些翻译不自然 |
| 按钮布局 | 排版不美观 |
| Web 切换不明显 | 语言按钮位置不直观 |
| Bot 引导过长 | /language 输出太多 |

---

## 9. 用户报告模板

```
# Chinese/English Control Plane Smoke Test Report

## Environment
- OS: [distribution/version]
- Commit: [git rev-parse HEAD]
- Working tree: [clean/dirty]
- Bot running: [yes/no — method: systemd/nohup/run.sh]
- Web running: [yes/no — method: systemd/nohup/run.sh]
- Web access: [127.0.0.1:8080 / SSH tunnel / other]

## Preflight Tests
- chinese-default-v1.9.48.py: [PASS/FAIL — N passed]
- bot-language-command-v1.9.52.py: [PASS/FAIL — N passed]
- web-language-switch-v1.9.51.py: [PASS/FAIL — N passed, N failed]
  - If 5 failures: [recorded as known test debt / real issue]
- bot self-test: [PASS/FAIL — N passed]
- web self-test: [PASS/FAIL — N passed]

## Bot Chinese Result
- /start: [PASS/POLISH/BLOCKED]
- /help: [PASS/POLISH/BLOCKED]
- /language: [PASS/POLISH/BLOCKED]
- /status: [PASS/POLISH/BLOCKED]
- /doctor Advanced OFF: [PASS/POLISH/BLOCKED]
- /advanced on/off: [PASS/POLISH/BLOCKED]
- /doctor Advanced ON: [PASS/POLISH/BLOCKED]
- /status_json gate: [PASS/POLISH/BLOCKED]
- Button callbacks: [PASS/POLISH/BLOCKED]

## Bot English Result
- [Tested with NANOBK_LANG=en / Deferred — reason]

## Web Chinese Result
- Login: [PASS/POLISH/BLOCKED]
- Dashboard: [PASS/POLISH/BLOCKED]
- Status: [PASS/POLISH/BLOCKED]
- Doctor: [PASS/POLISH/BLOCKED]
- Raw JSON gate: [PASS/POLISH/BLOCKED]

## Web English Result
- Switch to EN: [PASS/POLISH/BLOCKED]
- Dashboard EN: [PASS/POLISH/BLOCKED]
- Status EN: [PASS/POLISH/BLOCKED]
- Doctor EN: [PASS/POLISH/BLOCKED]
- Switch back to ZH: [PASS/POLISH/BLOCKED]
- Logout resets: [PASS/POLISH/BLOCKED]
- /api/status: [PASS/POLISH/BLOCKED]

## Leak Checklist
- Raw token: [CLEAN / LEAKED — P0]
- Private key: [CLEAN / LEAKED — P0]
- Env content: [CLEAN / LEAKED — P0]
- Subscription URL: [CLEAN / LEAKED — P0]
- Raw IP/domain: [CLEAN / LEAKED — P1]
- Raw JSON while Advanced OFF: [CLEAN / LEAKED — P1]
- Full diagnostics while Advanced OFF: [CLEAN / LEAKED — P1]
- /language exposes env path: [CLEAN / LEAKED — P1]

## Existing Gates Sanity
- Four protocol services: [all active / some down — list]
- Advanced mode TTL: [working / broken]
- Rotate confirmation: [not tested / working]

## Issues Found
- [list issues with P0/P1/P2 classification]

## Final Verdict
- [ ] PASS
- [ ] PASS WITH POLISH
- [ ] BLOCKED — reason: ___

## Notes for ChatGPT
[Redacted notes — no raw secrets/IP/domain/URL]
```

**警告：**

- 不粘贴 raw env
- 不粘贴 raw JSON
- 不粘贴完整 doctor 输出
- 不粘贴 token/IP/domain/subscription URL/workers.dev

---

## 10. 失败处理

| 场景 | 处理 |
|------|------|
| 出现 raw secret | 立即停止，如需撤销/重新生成，仅报告类别 |
| Web 语言路由绕过 CSRF/login | 立即停止，标记 P1 |
| Raw JSON Advanced OFF 时可见 | 立即停止，标记 P1 |
| 测试套件失败 | 记录精确失败测试名称，不隐藏 |
| 服务意外变更 | 立即停止，不在本次冒烟中修复 |

---

## 11. 稳定 tag 含义

**v1.9 稳定 tag 前置条件：**

| 条件 | 状态 |
|------|------|
| 中文默认已验证 | 待冒烟 |
| Web zh/en 切换已验证 | 待冒烟 |
| Bot /language 引导已验证 | 待冒烟 |
| 语言测试债务已解决或明确分类 | 待处理 |
| 无 P0/P1 泄漏 | 待冒烟 |
| CLI 版本显示已解决 | 待处理 |
| AI 维护接口已添加/规划 | 待处理 |

**不在 UI 仍主要英文时 tag。**

---

## 12. 建议判定标准

### PASS

- 所有语言功能正常
- 无 P0/P1
- 测试通过或测试债务记录为假阳性
- 无服务中断

### PASS WITH POLISH

- 语言功能正常且无 P0/P1
- 但存在措辞/布局/测试债务打磨项

### BLOCKED

- raw secret 泄漏
- Web 语言路由安全绕过
- Raw JSON gate 损坏
- Bot/Web 无法启动
- 协议服务中断
- 因真实行为 bug 导致测试失败

---

## 13. 就绪决策

**A. READY FOR USER-RUN CHINESE/ENGLISH CONTROL PLANE SMOKE TEST AFTER CHATGPT REVIEW**

**条件：**

- Web 语言切换测试债务必须在稳定收口前重新运行并确认通过或精确记录

---

## 14. 未变更内容

| 组件 | 状态 |
|------|------|
| Bot 运行时 | 未变更 |
| Web 运行时 | 未变更 |
| CLI | 未变更 |
| 安装器 | 未变更 |
| env 文件 | 未变更 |
| redaction | 未变更 |
| Raw JSON gating | 未变更 |
| 高级模式 | 未变更 |
| rotate | 未变更 |
| 部署逻辑 | 未变更 |
| 无测试新增 | ✅ |
| 无功能实现 | ✅ |
| 无 tag/release | ✅ |

---

## 15. 已知限制

| 限制 | 说明 |
|------|------|
| 仅规划 | 未执行真实冒烟测试 |
| Bot 无运行时切换 | 仅引导，不切换 |
| 持久 CLI 语言命令缺失 | 长期任务 |
| web-language-switch 测试债务 | 5 个源码级假阳性待处理 |
| CLI 版本显示待定 | 独立任务 |
| AI 维护接口待定 | v1.9.57-59 任务 |

---

## 16. Guardrails

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止修改 install.sh | 保护 v1.7.27 基线 |
| 2 | 禁止修改 bin/nanobk | 保护 CLI 核心 |
| 3 | 禁止修改协议模板 | 保护部署 |
| 4 | 禁止修改 Worker | 保护 Cloudflare |
| 5 | 禁止修改 rotate sync | 保护轮换 |
| 6 | 禁止直接 Bot/Web 写入 configs/systemd/secrets | 安全 |
| 7 | 禁止直接 Bot/Web 写入 env | 安全 |
| 8 | 禁止 raw env 读取 | 安全 |
| 9 | 禁止 production status wrapper | 未批准 |
| 10 | 禁止 dirty VPS status wrapping | 未批准 |
| 11 | 禁止 operation-log full rollout | 未批准 |
| 12 | 禁止 raw subscription delivery | 未批准 |
| 13 | 禁止 tag/release | 未批准 |
