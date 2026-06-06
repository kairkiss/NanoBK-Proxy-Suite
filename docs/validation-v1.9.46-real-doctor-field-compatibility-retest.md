# v1.9.46 — Real Doctor Field Compatibility Retest Validation

> 验证类型：真实 Doctor 字段兼容性重测验证文档
> 日期：2026-06-05
> 基线 commit：`3881e4c85aa4c3bd03d20a31e58588a62ebe4436`
> 基线信息：`docs: add v1.9.45 doctor field retest plan`

---

## 1. 本轮目标与结论

**v1.9.46 记录了用户手动执行的 T16 真实 Doctor 字段兼容性重测：**

- ✅ 本文档仅记录测试结果
- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无部署逻辑变更
- ✅ Claude Code 未执行真实 status/doctor
- ✅ 无 tag/release
- ✅ 测试结果：**PASS WITH POLISH**
- ✅ T15-P2-001 确认已修复

**结论：T16 真实 Doctor 字段兼容性重测确认 T15-P2-001 在真实 VPS、真实 Bot UI、真实 Web UI 和真实 status 数据层已修复。Bot/Web Doctor Summary 现在正确显示 Profile present、Config present。**

---

## 2. 测试环境摘要

| 属性 | 值（脱敏） |
|------|-----------|
| 操作系统 | Ubuntu 24.04.1 LTS |
| 用户 | root |
| systemd | 可用 |
| Python | 3.12 |
| VPS 环境 | 脏/测试环境 |
| 仓库路径 | /opt/NanoBK-Proxy-Suite |
| 仓库更新 | 从 v1.9.39 时代 commit 更新至 v1.9.45 commit |
| 全局 CLI 链接 | /usr/local/bin/nanobk → /opt/NanoBK-Proxy-Suite/bin/nanobk |
| CLI 版本显示 | nanobk 1.8.45（已知版本显示问题） |
| env 文件 | 存在，mode 600，内容未读取/粘贴 |
| Bot/Web | 更新后重启 |
| Web 访问 | 仅本地 127.0.0.1:8080 |
| 四协议服务 | HY2/TUIC/REALITY/TROJAN active |

**不包含：真实 IP、真实域名、真实 token、真实 URL。**

---

## 3. 初始基线发现

| 发现 | 说明 | 状态 |
|------|------|------|
| 仓库落后 6 个 commit | 初始在 a8b392e | 已解决 |
| 旧 Bot/Web 进程存在 | 用户停止后重启 | 已解决 |
| 全局 CLI 链接存在 | 指向仓库 | 正常 |
| CLI 版本仍显示 1.8.45 | 已知问题 | 记录 |
| 四协议服务活跃 | 测试前后保持 | 正常 |

---

## 4. Focused Tests 结果

用户在真实 VPS 上运行了相关测试套件，观察到 PASS 结果。

| 测试 | 结果 |
|------|------|
| `tests/doctor-summary-contract-v1.9.35.py` | ✅ 352 passed |
| `tests/doctor-field-compatibility-fixtures-v1.9.42.py` | ✅ 294 passed |
| `tests/doctor-field-compatibility-runtime-v1.9.43.py` | ✅ 282 passed |
| `tests/doctor-field-compatibility-checkpoint-v1.9.44.py` | ✅ 242 passed |
| `tests/bot-doctor-summary-v1.9.36.py` | ✅ 163 passed |
| `tests/web-doctor-summary-v1.9.37.py` | ✅ 164 passed |
| `tests/doctor-output-checkpoint-v1.9.38.py` | ✅ 208 passed |
| `bot/nanobk_bot.py --self-test` | ✅ 180 passed |
| `web/app.py --self-test` | ✅ 106 passed |
| `tests/bot-cli-mock.sh` | ✅ PASS |
| `tests/web-panel-mock.sh` | ✅ PASS |

---

## 5. 真实状态安全探针结果

用户执行了安全探针：

- `nanobk --json status` 由用户执行
- 原始 JSON 未打印
- 原始 status 仅在内存中由 Bot/Web `build_doctor_summary()` 消费
- 仅报告安全派生字段

**Bot/Web 派生摘要结果（安全）：**

| 字段 | 值 |
|------|-----|
| overall | healthy |
| control_plane | ok |
| cli | available |
| profile | present |
| config | present |
| security | ok |
| cloudflare | configured |
| subscription | unknown |
| services | hy2: active, tuic: active, reality: active, trojan: active |
| doctor.errors | 0 |
| doctor.warnings | 0 |
| doctor.full_available | true |
| display_policy.beginner_safe | true |
| display_policy.full_output_advanced_only | true |
| display_policy.redaction_required | true |

**Bot/Web 关键一致性：**

| 字段 | 结果 |
|------|:----:|
| overall | MATCH |
| profile | MATCH |
| config | MATCH |
| security | MATCH |
| cloudflare | MATCH |
| subscription | MATCH |

**禁止片段检查：** PASS

**T16 字段兼容性判定：**

| 字段 | 值 | 结果 |
|------|-----|:----:|
| profile | present | PASS_CANDIDATE |
| config | present | PASS_CANDIDATE |

---

## 6. Bot 真实 UI 结果

| 步骤 | 结果 | 备注 |
|------|:----:|------|
| `/advanced off` | PASS | 高级模式禁用 |
| `/doctor` 高级 OFF | PASS | 仅 Doctor Summary |
| Profile present | PASS | 非 unknown |
| Config present | PASS | 非 unknown |
| 摘要仅显示 | PASS | 无完整技术诊断 |
| 无 raw secret | PASS | 无 token/private key/URL |
| `/advanced on` | PASS | 警告 + 15 分钟过期 |
| `/doctor` 高级 ON | PASS WITH POLISH | 摘要 + 警告 + 脱敏完整诊断 |
| systemd 服务名脱敏 | PASS | [REDACTED_DOMAIN] |
| 无 raw token/private key | PASS | |
| `/status_json` 高级 OFF 门控 | PASS | 仅引导，无 JSON |

### Bot /doctor 高级 OFF 详情

- 仅显示 Doctor Summary
- Overall healthy
- Control Plane ok
- CLI available
- Profile present
- Config present
- Services all active
- Cloudflare configured
- Subscription unknown
- Security ok
- Errors 0
- Warnings 0
- Next step: No immediate action required
- 完整诊断提示已显示
- 无完整技术诊断
- 无 raw token/private key/subscription URL/workers.dev

### Bot /doctor 高级 ON 详情

- 摘要先出现
- Profile present
- Config present
- 高级诊断警告
- 脱敏完整诊断显示
- systemd 服务名脱敏为 [REDACTED_DOMAIN]
- 无 raw token/private key/subscription URL/workers.dev
- 完整诊断仍显示工程信息（OS/kernel/工具路径/config path/admin env path/ports/config files）
- 此为可接受的高级专用打磨项

---

## 7. Web 真实 UI 结果

| 步骤 | 结果 | 备注 |
|------|:----:|------|
| Web 登录 | PASS | |
| Dashboard 安全卡片 | PASS | Profile present, Secrets mode 600 |
| Status + 高级模式 | PASS | 门控正常 |
| Raw JSON 门控 | PASS | OFF 锁定, ON 展开 |
| `/doctor` 高级 OFF | PASS | 仅摘要卡片 |
| Profile present | PASS | 非 unknown |
| Config present | PASS | 非 unknown |
| 无 raw secret | PASS | |
| `/doctor` 高级 ON | PASS WITH POLISH | 摘要 + 警告 + 折叠完整诊断 |
| 完整诊断默认折叠 | PASS | 截图确认 |

### Web /doctor 高级 OFF 详情

- Doctor Summary 卡片仅显示
- Profile present
- Config present
- 四协议 active
- 无完整诊断
- 无 raw path/IP/domain/URL/token/private key

### Web /doctor 高级 ON 详情

- 摘要先出现
- Profile present
- Config present
- 高级诊断警告存在
- Full Diagnostics 高级脱敏入口存在
- 截图显示完整诊断默认折叠
- 完整诊断内容在 T16 Web 检查中未展开
- 之前 v1.9.37/v1.9.38 已覆盖代码路径，Bot 完整诊断在 T16 中已检查

---

## 8. 最终健康检查

| 检查项 | 结果 |
|--------|:----:|
| Bot/Web 进程运行 | ✅ |
| Web healthz ok | ✅ |
| 四协议服务活跃 | ✅ |
| 日志无明显错误 | ✅ |
| 无服务崩溃 | ✅ |
| 无破坏性操作执行 | ✅ |

---

## 9. 泄漏检查结果

### 未观察到泄露

| 数据类 | 是否泄露 |
|--------|:--------:|
| 原始 token | 否 |
| Private key | 否 |
| Reality private key | 否 |
| Subscription URL/path | 否 |
| workers.dev | 否 |
| 原始 env 内容 | 否 |
| Bot token | 否 |
| Web token | 否 |
| Cloudflare/Admin token 原始值 | 否 |

### 高级专用可见信息

| 项目 | 状态 | 说明 |
|------|------|------|
| OS/kernel | 高级模式内可见 | 仅限高级 |
| 工具路径 | 高级模式内可见 | 仅限高级 |
| 配置路径 | 高级模式内可见 | 仅限高级 |
| Admin env 路径 | 高级模式内可见 | 仅限高级 |
| 端口号 | 高级模式内可见 | 仅限高级 |
| 配置文件路径 | 高级模式内可见 | 仅限高级 |
| 服务状态 | 高级模式内可见 | 仅限高级 |

**这些仍为高级专用信息，不适合公开转发。**

---

## 10. 问题矩阵

| ID | 严重度 | 发现 | 状态 | 推荐下一步 |
|----|:------:|------|------|-----------|
| T16-P0-001 | P0 | 无 P0 安全泄露 | 通过 | — |
| T16-P1-001 | P1 | 无新 P1 核心不可用/安全泄露 | 通过 | — |
| T16-P2-001 | P2 | 初始仓库落后 6 个 commit | 已解决 | 测试应确认 HEAD == origin/main |
| T16-P2-002 | P2 | CLI 版本仍显示 nanobk 1.8.45 | 已知 | 规划 CLI/版本显示策略 |
| T16-P2-003 | P2 | Bot/Web 仍通过 nohup/run.sh 运行 | 已知 | 规划 Bot/Web systemd 安装 |
| T16-P2-004 | P2 | Web 仍使用 Flask 开发服务器 | 已知 | 规划 Web production runner |
| T16-P2-005 | P2 | UI 默认仍主要英文 | 已知 | i18n 存在，需安装器/env 语言传播和中文默认策略 |
| T16-P2-006 | P2 | 高级完整诊断仍为工程导向 | 已知 | 保持高级专用，规划完整诊断 UX 打磨 |
| T16-P2-007 | P2 | Fingerprint redaction 策略仍待定 | 已知 | |
| T16-P2-008 | P2 | Bot/Web Doctor Summary builder 逻辑重复 | 已知 | 未来共享 helper 可能，非阻塞 |
| T16-TEST-001 | 测试 | 端口摘要脱敏命令输出难以阅读 | 仅测试问题 | |

---

## 11. 总体结论

**T16 有限真实 Doctor 字段兼容性重测：PASS WITH POLISH**

**通过原因：**

- v1.9.43 修复确认真实
- Bot/Web Doctor Summary 现在显示 Profile present、Config present
- 门控仍正常
- 服务活跃
- 无 P0/P1 泄露
- 无破坏性操作运行

**非纯 PASS 原因（打磨项）：**

- CLI 版本仍 1.8.45
- Bot/Web 未 systemd 产品化
- Web 使用 Flask 开发服务器
- UI 默认仍英文
- 高级完整诊断仍为工程导向
- Fingerprint 策略待定
- Web 完整诊断在 T16 中未展开
- Builder 逻辑重复

---

## 12. 建议下一步

**推荐：v1.9.47 — Bot/Web 语言传播和中文默认规划**

原因：
- 用户希望在稳定 tag 前完成中文支持并设为默认中文
- i18n 已存在，但运行时语言传播/默认中文未完成

**后续路线：**

| 版本 | 内容 |
|------|------|
| v1.9.47 | Bot/Web 语言传播和中文默认规划 |
| v1.9.48 | Bot/Web 中文默认最小实现 |
| v1.9.49 | 安装器 Bot/Web 语言传播最小实现 |
| v1.9.50 | 语言切换 UX 规划 |
| 后续 | CLI 版本显示打磨、AI 维护接口、稳定 tag 准备 |

**不推荐立即 tag/release。**

---

## 13. 未变更内容

| 组件 | 状态 |
|------|------|
| Bot 运行时 | 未变更 |
| Web 运行时 | 未变更 |
| CLI | 未变更 |
| bin/nanobk | 未变更 |
| installer/doctor.sh | 未变更 |
| installer/install.sh | 未变更 |
| redaction | 未变更 |
| Raw JSON 门控 | 未变更 |
| 高级模式 | 未变更 |
| rotate | 未变更 |
| 部署逻辑 | 未变更 |
| 无测试新增 | ✅ |
| 无功能实现 | ✅ |
| 无 tag/release | ✅ |

---

## 14. 已知限制

| 限制 | 说明 |
|------|------|
| 验证记录用户报告的 T16 结果 | Claude Code 未独立运行真实测试 |
| Web 完整诊断在 T16 中未展开 | Bot 完整诊断已检查 |
| Fingerprint redaction 仍待定 | 未变更 |
| 语言传播仍待定 | 未变更 |
| systemd/Web production runner 仍待定 | 未变更 |
| CLI 版本显示仍待定 | 未变更 |

---

## 15. Guardrails

| # | 约束 | 状态 |
|---|------|------|
| 1 | 无 install.sh 行为变更 | ✅ |
| 2 | 无 bin/nanobk 行为变更 | ✅ |
| 3 | 无 installer/doctor.sh 行为变更 | ✅ |
| 4 | 无协议模板变更 | ✅ |
| 5 | 无 Worker 变更 | ✅ |
| 6 | 无 rotate sync 变更 | ✅ |
| 7 | 无直接 Bot/Web 写入 configs/systemd/secrets | ✅ |
| 8 | 无 raw env 读取 | ✅ |
| 9 | 无真实 status 执行（Claude Code） | ✅ |
| 10 | 无真实 doctor 执行（Claude Code） | ✅ |
| 11 | 无 production status wrapper | ✅ |
| 12 | 无 dirty VPS status wrapping | ✅ |
| 13 | 无 operation-log full rollout | ✅ |
| 14 | 无 raw subscription delivery | ✅ |
| 15 | 无 tag/release | ✅ |
