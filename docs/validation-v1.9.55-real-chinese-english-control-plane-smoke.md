# v1.9.55 — Real Chinese/English Control Plane Smoke Validation

> 验证类型：用户手动 T17 真实中/英文控制面冒烟测试结果记录
> 日期：2026-06-06
> 基线 commit：`daa97406e0892413394a20fc631709f1f6b8b9c0`
> 基线信息：`test: fix web language switch coverage`

---

## 1. 本轮目标与结论

**v1.9.55 记录用户手动执行的 T17 真实中/英文控制面冒烟测试结果。**

- ✅ 仅文档，无运行时变更
- ✅ 无 Bot/Web/CLI/安装器行为变更
- ✅ 无测试添加
- ✅ 无 env 文件读写
- ✅ 无 tag/release
- 运行时测试未由 Claude Code 重新执行

**最终结论：PASS WITH POLISH**

未达纯 PASS 的原因：
- 已知 CLI 版本显示仍为 `nanobk 1.8.45`
- 安装器语言传播测试存在假阳性测试债务（T17-TEST-002）
- Web 中文模式存在少量英文残留（T17-P2-003）

---

## 2. 测试环境摘要

| 项目 | 值 |
|------|-----|
| 操作系统 | Ubuntu 24.04.1 LTS |
| 用户 | root |
| systemd | 可用 |
| Python | 3.12 |
| VPS 状态 | 脏测试 VPS，已有 NanoBK 四协议部署 |
| 重部署 | 无 |
| 真实 rotate | 无 |
| 修复/重启 | 无 |
| Cloudflare 变更 | 无 |
| Repo commit | `daa97406e0892413394a20fc631709f1f6b8b9c0` |
| Commit message | `test: fix web language switch coverage` |
| CLI 符号链接 | `/usr/local/bin/nanobk -> /opt/NanoBK-Proxy-Suite/bin/nanobk` |
| CLI 版本显示 | `nanobk 1.8.45`（已知待修） |
| env 内容 | 未读取、未粘贴 |

---

## 3. Stage 0 — 基线与更新

| 检查项 | 结果 |
|--------|------|
| 本地 repo 落后 origin/main | 9 commits |
| 快速前进更新 | ✅ 完成 |
| 旧 Bot/Web 进程 | 存在 |
| Bot/Web 用最新代码重启 | ✅ 完成 |
| 四协议服务测试前活跃 | ✅ |
| env 文件存在，mode 600 | ✅ |
| env 内容未读取 | ✅ |

**Stage 0 结论：PASS WITH UPDATE**

---

## 4. Stage 1 — 预检测试

### 4A — 安装器语言传播测试假阳性

`tests/installer-language-propagation-v1.9.49.sh` 发现 2 个失败项：

- `install.sh reads bot/.env`
- `install.sh reads web/.env`

**分类：T17-TEST-002 — 假阳性 / 测试债务**

原因：测试匹配了安全警告文本（如 "Do NOT cat bot/.env" / "不要执行 cat bot/.env"），而非可执行的 env 读取命令。

产品影响：
- install.sh 实际上没有执行 `cat env` 操作
- 无 env 内容泄露
- 不阻塞 T17 冒烟测试
- 应在稳定 tag 前修复

### 4B — 其他聚焦测试

| 测试 | 结果 |
|------|------|
| Web 语言切换 v1.9.51 | ✅ PASS |
| 中文默认 v1.9.48 | ✅ PASS |
| Bot 语言命令 v1.9.52 | ✅ PASS |
| Bot i18n v1.9.30 | ✅ PASS |
| Web i18n v1.9.31 | ✅ PASS |
| i18n 检查点 v1.9.32 | ✅ PASS |
| Bot 自检 | ✅ PASS |
| Web 自检 | ✅ PASS |
| Bot CLI mock | ✅ PASS |
| Web Panel mock | ✅ PASS |

**Stage 1 结论：PASS（含已分类测试债务）**

---

## 5. Stage 2 — Bot/Web 重启与健康检查

| 检查项 | 结果 |
|--------|------|
| 旧 Bot/Web 进程停止 | ✅ |
| Web 重启成功 | ✅ |
| Bot 重启成功 | ✅ |
| Web /healthz 返回 ok | ✅ |
| 四协议服务保持活跃 | ✅ |
| Web 日志无明显错误 | ✅ |
| Bot 日志无明显错误 | ✅ |

**已知局限：**
- Web 仍使用 Flask 开发服务器
- Bot/Web 仍使用 run.sh/nohup 临时操作，未 systemd 产品化

**Stage 2 结论：PASS**

---

## 6. Stage 3 — Web 中文/英文控制面测试

### 默认中文

| 检查项 | 结果 |
|--------|------|
| Web 登录页中文 | ✅ |
| Dashboard 中文 | ✅ |
| Status 中文 | ✅ |
| Doctor 中文 | ✅ |
| Rotate 中文 | ✅ |
| EN 切换按钮存在 | ✅ |

### 切换英文

| 检查项 | 结果 |
|--------|------|
| Dashboard 英文 | ✅ |
| Status 英文 | ✅ |
| Doctor 英文 | ✅ |
| Rotate 英文 | ✅ |
| 语言按钮变为 中文 | ✅ |

### 切换回中文

| 检查项 | 结果 |
|--------|------|
| Dashboard 中文恢复 | ✅ |
| Status 中文恢复 | ✅ |
| Doctor 中文恢复 | ✅ |
| 语言按钮变为 EN | ✅ |

### 登出会话重置

| 检查项 | 结果 |
|--------|------|
| 切换英文 → 登出 → 重新登录 → 默认中文恢复 | ✅ |

### Web 安全回归

| 检查项 | 结果 |
|--------|------|
| Dashboard 安全卡片 | ✅ |
| Status 安全卡片 | ✅ |
| 高级模式可启用并显示到期时间 | ✅ |
| Raw JSON 高级 OFF 锁定 | ✅ |
| Raw JSON 高级 ON 警告 + 详情 | ✅ |
| 高级 OFF 再次锁定 Raw JSON | ✅ |
| Doctor 高级 OFF 仅摘要 | ✅ |
| Doctor 高级 ON 警告 + 完整诊断折叠条目 | ✅ |
| 无 raw token/私钥/订阅 URL/workers.dev 可见 | ✅ |

**Stage 3 结论：Web 中文/英文控制面冒烟：PASS WITH POLISH**

---

## 7. Stage 4 — Bot 中文控制面测试

### /start

| 检查项 | 结果 |
|--------|------|
| 中文控制中心 | ✅ |
| 中文按钮 | ✅ |
| 敏感地址和密钥隐藏提示 | ✅ |
| 无 raw IP/域名/token/URL | ✅ |

### /help

| 检查项 | 结果 |
|--------|------|
| 中文帮助 | ✅ |
| 包含 /language | ✅ |
| /status_json 在高级诊断区域 | ✅ |
| 斜杠命令名称保持英文 | ✅ |

### /language

| 检查项 | 结果 |
|--------|------|
| 显示当前语言为中文 | ✅ |
| 说明 Bot 语言来自 NANOBK_LANG 或安装器语言 | ✅ |
| 说明新安装默认中文 | ✅ |
| 说明英文可通过 NANOBK_LANG=en 配置 | ✅ |
| 说明持久语言切换将使用未来 CLI/安装器安全命令 | ✅ |
| 无 env 内容/token/路径显示 | ✅ |

### /status

| 检查项 | 结果 |
|--------|------|
| 中文安全状态摘要 | ✅ |
| HY2/TUIC/REALITY/TROJAN 活跃 | ✅ |
| Cloudflare nanok/nanob 已配置 | ✅ |
| 密钥存在，mode 600 | ✅ |
| profile/config 存在 | ✅ |
| 无 raw IP/域名/workers.dev/订阅 URL/token/私钥 | ✅ |

### /advanced off + /doctor

| 检查项 | 结果 |
|--------|------|
| Doctor 高级 OFF 仅摘要 | ✅ |
| Profile/config 存在 | ✅ |
| 无完整技术诊断 | ✅ |
| 无 raw 密钥 | ✅ |

### /status_json 高级 OFF

| 检查项 | 结果 |
|--------|------|
| 无 JSON 输出 | ✅ |
| 显示引导 | ✅ |
| /status 和 /advanced on 引导 | ✅ |
| 提及 15 分钟到期 | ✅ |
| 密钥/raw 地址/订阅 URL 必须保持隐藏 | ✅ |

### /advanced on

| 检查项 | 结果 |
|--------|------|
| 高级诊断已启用 | ✅ |
| 警告显示 | ✅ |
| 不要转发完整诊断警告 | ✅ |
| 15 分钟到期显示 | ✅ |

### /status_json 高级 ON

| 检查项 | 结果 |
|--------|------|
| 警告显示 | ✅ |
| 脱敏 JSON 显示 | ✅ |
| 域名/IP 已脱敏 | ✅ |
| 无 raw token/私钥/订阅 URL/workers.dev | ✅ |
| adminTokenFingerprint 类字段仍可见 | ✅ POLISH |

### /doctor 高级 ON

| 检查项 | 结果 |
|--------|------|
| 摘要优先 | ✅ |
| 高级诊断警告 | ✅ |
| 脱敏完整诊断 | ✅ |
| 服务/域名脱敏为 [REDACTED_DOMAIN] | ✅ |
| 无 raw token/私钥/订阅 URL/workers.dev | ✅ |

### /advanced off + /status_json

| 检查项 | 结果 |
|--------|------|
| 再次锁定 | ✅ |

### Bot 按钮回调

| 按钮 | 结果 |
|------|------|
| Status Summary | ✅ |
| Recovery Help | ✅ |
| Diagnostics | ✅ |
| Advanced Mode | ✅ |
| Rotate Secrets | ✅ 仅引导，不执行 rotate |
| Web Panel | ✅ 无 raw URL |
| Help | ✅ |

**Stage 4 结论：Bot 中文控制面冒烟：PASS WITH POLISH**

---

## 8. Stage 5 — 最终健康检查

| 检查项 | 结果 |
|--------|------|
| HEAD == origin/main == `daa97406e0892413394a20fc631709f1f6b8b9c0` | ✅ |
| Web python3 app.py 运行中 | ✅ |
| Bot python3 nanobk_bot.py 运行中 | ✅ |
| Web /healthz ok | ✅ |
| HY2 活跃 | ✅ |
| TUIC 活跃 | ✅ |
| Reality 活跃 | ✅ |
| Trojan 活跃 | ✅ |
| Web 日志正常 | ✅ |
| Bot 日志正常 | ✅ |
| 无服务崩溃 | ✅ |

**Stage 5 结论：PASS**

---

## 9. 泄露检查结果

### 未观察到泄露

- raw token
- 私钥
- Reality 私钥
- 订阅 URL/路径
- workers.dev
- raw env 内容
- Bot token
- Web token
- Cloudflare/Admin token raw 值

### 已观察但可接受（仅高级模式或未来打磨）

- 操作系统/内核信息
- 工具路径
- config/admin env 路径类别信息
- 端口号
- 配置文件路径
- 服务状态
- 指纹/哈希类字段

**说明：** 这些信息仅出现在高级完整诊断或高级 Raw JSON 中。当前设计接受其为高级专属，但指纹/哈希类字段应由未来策略处理。

---

## 10. 问题矩阵

| ID | 严重度 | 问题 | 状态 | 建议 |
|----|--------|------|------|------|
| T17-P0-001 | P0 | 无 P0 安全泄露 | ✅ 通过 | 无 |
| T17-P1-001 | P1 | 无新 P1 核心不可用/安全泄露 | ✅ 通过 | 无 |
| T17-TEST-002 | 测试债务 | installer-language-propagation-v1.9.49.sh 两个假阳性 env-cat 检查 | 🆕 新发现 | 稳定 tag 前修复 |
| T17-P2-003 | P2 | Web 中文模式 Next step 仍有英文残留 | 🆕 新发现 | 修复 i18n key/copy 覆盖 |
| T17-P2-004 | P2 | 高级 Raw JSON / 完整诊断仍显示工程信息 | 已知 | 保持高级专属；后续 UX 收敛 |
| T17-P2-005 | P2 | Web 页面仍像工程仪表盘 | 已知 | 稳定版或 v2.0 后 UI 打磨 |
| T17-P2-006 | P2 | Bot /status_json 高级 ON 仍显示指纹类字段 | 已知 | 规划指纹脱敏策略 |
| T17-P2-007 | P2 | Bot/Web 完整诊断显示系统路径、端口、工具路径 | 已知 | 高级专属可接受；后续打磨 |
| T17-P2-008 | P2 | healthy/active/configured/unknown 机器值保持英文 | 已接受 | 机器值有意保持稳定 |
| T17-P2-009 | P2 | Bot/Web 未 systemd 产品化 | 已知 | 未来 systemd 安装规划 |
| T17-P2-010 | P2 | Web 使用 Flask 开发服务器 | 已知 | 未来 Web 生产运行器规划 |
| T17-P2-011 | P2 | CLI 版本仍显示 nanobk 1.8.45 | 已知 | 稳定 tag 前处理 |
| T17-P2-012 | P2 | AI 维护接口/交接文档未完成 | 已知 | 稳定 tag 前添加 |

---

## 11. 总体结论

**PASS WITH POLISH**

T17 真实中/英文控制面冒烟测试全面通过：

- 无 P0 安全泄露
- 无 P1 核心不可用
- Web 中文默认正常
- Web 中英文切换正常
- Web 会话重置正常
- Web 安全门控正常
- Bot 中文控制面正常
- Bot 语言引导正常
- Bot 安全门控正常
- 四协议服务持续活跃

未达纯 PASS 的原因：
- 安装器语言传播测试存在假阳性测试债务（T17-TEST-002）
- Web 中文模式存在少量英文残留（T17-P2-003）
- CLI 版本显示仍为旧版本（T17-P2-011）

这些均为已知打磨项，不影响核心功能和安全性。

---

## 12. 建议下一步

| 版本 | 内容 |
|------|------|
| v1.9.56 | 安装器语言传播测试债务修复 |
| v1.9.57 | Web 中文 Copy 打磨 / i18n 覆盖修复 |
| v1.9.58 | CLI 版本显示策略 / 最小修复 |
| v1.9.59–v1.9.60 | AI 维护接口文档 |
| 稳定 tag | 仅在收口检查点和用户明确批准后执行 |

---

## 13. 稳定 tag 门控条件

以下条件全部满足后方可考虑稳定 tag：

- [x] T17 验证文档已入库
- [ ] 安装器语言传播测试债务已修复
- [ ] Web 中文残留已修复
- [ ] CLI 版本显示已处理
- [ ] AI 维护接口文档已添加
- [ ] 最终聚焦测试通过
- [ ] 无 P0/P1 问题
- [ ] 用户明确批准 tag/release

---

## 14. 有意未变更的内容

- Bot 运行时
- Web 运行时
- CLI
- 安装器 (installer/install.sh)
- env 文件
- 脱敏逻辑 (lib/nanobk_redaction.py)
- Raw JSON 门控
- 高级模式
- rotate 行为
- 部署逻辑
- 未添加测试
- 未 tag/release

---

## 15. 已知局限

| 局限 | 说明 |
|------|------|
| 验证记录用户报告结果 | Claude Code 未重新执行真实测试 |
| 安装器测试债务待修 | T17-TEST-002 假阳性 |
| 指纹脱敏策略待定 | T17-P2-006 |
| systemd/Web 生产运行器待定 | T17-P2-009, T17-P2-010 |
| CLI 版本显示待处理 | T17-P2-011 |
| AI 维护接口待完成 | T17-P2-012 |

---

## 16. 相关文档

- v1.9.48 — Bot/Web 中文默认最小实现
- v1.9.49 — 安装器 Bot/Web 语言传播最小实现
- v1.9.51 — Web 会话语言切换最小实现
- v1.9.52 — Bot 语言命令 / 引导最小实现
- v1.9.53 — 中/英文控制面冒烟测试计划
- v1.9.54 — Web 语言切换测试债务修复
