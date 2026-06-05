# v1.9.40 — Real Doctor Smoke Retest Validation

> 验证类型：真实 Doctor 冒烟重测验证文档
> 日期：2026-06-05
> 基线 commit：`a8b392e20a1940ac85d026bf0db90564411c8717`
> 基线信息：`docs: add v1.9.39 doctor smoke retest plan`

---

## 1. 本轮目标与结论

**v1.9.40 记录了用户手动执行的 T15 真实 Bot/Web Doctor 冒烟重测：**

- ✅ 本文档仅记录测试结果
- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release
- ✅ 测试结果：**PASS WITH POLISH**

**结论：T15 有限真实 Bot/Web Doctor 冒烟重测在真实 VPS 控制面环境手动执行。Bot /doctor 摘要行为通过，Web /doctor 摘要行为通过，高级模式门控通过，脱敏通过。未观察到 P0/P1 泄露。剩余问题为产品化打磨项。**

---

## 2. 测试环境摘要

| 属性 | 值（脱敏） |
|------|-----------|
| 操作系统 | Ubuntu 24.04.1 LTS |
| 用户 | root |
| systemd | 可用 |
| Python | 3.12 |
| 现有服务 | 四协议服务已存在并保持活跃 |
| VPS 环境 | 脏/测试环境 |
| 仓库路径 | /opt/NanoBK-Proxy-Suite |
| 测试 commit | a8b392e20a1940ac85d026bf0db90564411c8717 |
| Bot/.env | 存在，chmod 600，root:root |
| Web/.env | 存在，chmod 600，root:root |
| 四协议服务状态 | HY2 active, TUIC active, REALITY active, TROJAN active |

**不包含：真实 IP、真实域名、真实 token、真实 URL。**

---

## 3. 本地测试套件结果

用户在真实 VPS 上运行了相关测试套件，观察到 PASS 结果。

| 测试 | 结果 |
|------|------|
| `tests/doctor-summary-contract-v1.9.35.py` | ✅ 通过 |
| `tests/bot-doctor-summary-v1.9.36.py` | ✅ 通过 |
| `tests/web-doctor-summary-v1.9.37.py` | ✅ 通过 |
| `tests/doctor-output-checkpoint-v1.9.38.py` | ✅ 通过 |
| `bot/nanobk_bot.py --self-test` | ✅ 180 passed, 0 failed |
| `web/app.py --self-test` | ✅ 106 passed, 0 failed |
| `tests/bot-i18n-minimal-v1.9.30.py` | ✅ 116 passed, 0 failed |
| `tests/web-i18n-minimal-v1.9.31.py` | ✅ 123 passed, 0 failed |
| `tests/i18n-checkpoint-v1.9.32.py` | ✅ 167 passed, 0 failed |
| `tests/bot-cli-mock.sh` | ✅ 通过 |
| `tests/web-panel-mock.sh` | ✅ 通过 |

---

## 4. Telegram Bot 真实测试结果

| 步骤 | 结果 | 备注 |
|------|------|------|
| Bot 启动 | PASS | 旧进程存在，用户停止后重启，进程恢复 |
| `/start` | PASS | 显示 NanoBK Control Center，按钮可见 |
| `/status` | PASS | 显示安全摘要，无原始 IP/domain/token/URL |
| `/doctor` 高级 OFF | PASS | 仅显示 Doctor Summary |
| `/doctor` 高级 ON | PASS | 摘要 + 警告 + 脱敏完整诊断 |
| `/doctor` 高级 OFF 再次 | PASS | 完整诊断消失，仅摘要 |
| `/status_json` 门控 | PASS WITH POLISH | 门控正常，但有 fingerprint 字段 |

### Bot /start 详情

- 显示 NanoBK Control Center
- 按钮可见：Status Summary、Recovery Help、Diagnostics、Advanced Mode、Rotate Secrets、Web Panel、Help
- 包含敏感地址隐藏消息
- 无原始 IP/domain/token/URL 观察

### Bot /status 详情

- 显示安全摘要
- Overall healthy
- VPS healthy
- HY2/TUIC/REALITY/TROJAN active
- Cloudflare nanok/nanob configured
- Subscription unknown
- Secrets present, mode 600
- Profile present
- 无原始 IP/domain/token/workers.dev/subscription URL/private key

### Bot /doctor 高级 OFF 详情

- 用户运行 `/advanced off` 然后 `/doctor`
- 仅显示 Doctor Summary
- 显示：Overall healthy、Control Plane ok、CLI available、services active、Cloudflare configured、Subscription unknown、Security ok、Errors 0、Warnings 0、Next step no immediate action
- 不显示完整技术 doctor 输出
- 默认无 OS/kernel/工具路径/配置路径/端口转储
- 无原始 IP/domain/token/private key
- 显示完整诊断需要 `/advanced on`

### Bot /doctor 高级 ON 详情

- 用户运行 `/advanced on` 然后 `/doctor`
- 输出顺序：
  1. Doctor Summary
  2. 高级诊断警告
  3. 脱敏完整诊断
- 完整诊断显示 OS/kernel、工具路径、配置路径、admin env 路径、systemd 服务、端口、配置文件
- 服务名被脱敏为 `[REDACTED_DOMAIN]`
- 无原始 token/private key/subscription URL/workers.dev 观察

### Bot /status_json 门控详情

- 高级 OFF：仅引导，无 JSON。PASS。
- 高级 ON：警告 + 脱敏 JSON。PASS WITH POLISH。
- 原始 domain 和原始 IPv4 已脱敏
- services/status 保留
- Cloudflare 字段保留
- adminTokenFingerprint/fingerprint 类字段仍可见
- 非原始 token 泄露，但应作为未来 fingerprint redaction 策略项

---

## 5. Web Panel 真实测试结果

| 步骤 | 结果 | 备注 |
|------|------|------|
| Web 启动 | PASS | run.sh/nohup 启动，127.0.0.1:8080 |
| 登录 | PASS | 安全获取 token 并登录 |
| Dashboard | PASS | 安全卡片正常显示 |
| Status + 高级模式 | PASS | 门控正常 |
| `/doctor` 高级 OFF | PASS WITH POLISH | 仅摘要卡片 |
| `/doctor` 高级 ON | PASS WITH POLISH | 摘要 + 警告 + 脱敏完整诊断 |

### Web 启动详情

- Web 通过 run.sh/nohup 重启
- python3 app.py 进程存在
- 监听 127.0.0.1:8080
- /healthz 返回 `{"ok": true}`
- 通过本地地址/SSH 隧道访问
- 未公开暴露

### Web Dashboard 详情

- Dashboard 安全卡片正常显示
- Overall Status、VPS healthy、protocols active、Cloudflare configured、Subscription unknown、Secrets present mode 600、Profile present、Next step
- 无原始 IP/domain/token/workers.dev/subscription URL/private key

### Web Status + 高级诊断详情

- 高级 OFF：Status 安全卡片正常，高级诊断禁用，Raw JSON 门控
- 高级 ON：启用并显示过期时间，Raw JSON 警告可见，Raw JSON 详情可见

### Web /doctor 高级 OFF 详情

- 运行 Doctor 仅显示 Doctor Summary 卡片
- 无完整技术转储
- 无 OS/kernel/工具路径/配置路径/端口转储
- 无原始 IP/domain/token/private key
- 显示：Overall healthy、Control Plane ok、CLI available、Profile unknown、Config unknown、services active、Cloudflare configured、Subscription unknown、Security ok、Errors 0、Warnings 0、Next step no immediate action
- **PASS WITH POLISH**
- 打磨原因：Profile/Config 显示 unknown，而 Dashboard/Status 显示 Profile present 且真实配置存在

### Web /doctor 高级 ON 详情

- 高级 ON 显示 Doctor Summary
- 高级诊断警告出现
- 完整诊断可见
- 服务名被脱敏为 `[REDACTED_DOMAIN]`
- 无原始 token/private key/subscription URL/workers.dev 观察
- 完整诊断包含 Required Tools、config paths、admin env path、service status、port listening、config file paths、summary all checks passed
- **PASS WITH POLISH**
- 打磨原因：完整诊断仍为工程导向；默认折叠状态未从截图完全确认

### /healthz 详情

- 返回 `{"ok": true}`
- 未暴露 token

---

## 6. 泄露检查结果

### 未观察到泄露

| 数据类 | 是否泄露 |
|--------|:--------:|
| 原始 token | 否 |
| Private key | 否 |
| Subscription URL | 否 |
| workers.dev | 否 |
| 原始 env 内容 | 否 |
| Reality private key | 否 |
| Cloudflare/Admin token 原始值 | 否 |
| Bot/Web token 原始值 | 否 |

### 可见但可接受或未来打磨项

| 项目 | 状态 | 说明 |
|------|------|------|
| OS/kernel | 高级模式内可见 | 仅限高级 |
| 工具路径 | 高级模式内可见 | 仅限高级 |
| 配置路径 | 高级模式内可见 | 仅限高级 |
| Admin env 路径 | 高级模式内可见 | 仅限高级 |
| 端口号 | 高级模式内可见 | 仅限高级 |
| 配置文件路径 | 高级模式内可见 | 仅限高级 |
| 服务状态 | 高级模式内可见 | 仅限高级 |
| Token fingerprint 类字段 | `/status_json` 可见 | 需未来 fingerprint redaction 策略 |

---

## 7. 本轮未执行事项

| 事项 | 状态 |
|------|------|
| 完整重部署 | ❌ 未执行 |
| Cloudflare 变更 | ❌ 未执行 |
| 真实 rotate | ❌ 未执行 |
| Repair/restart | ❌ 未执行 |
| Production status wrapper | ❌ 未执行 |
| Dirty VPS status wrapping | ❌ 未执行 |
| Raw subscription delivery | ❌ 未执行 |
| Subscription QR delivery | ❌ 未执行 |
| systemd 安装 | ❌ 未执行 |
| Web production runner | ❌ 未执行 |
| Tag/release | ❌ 未执行 |

### 已执行事项

| 事项 | 状态 |
|------|------|
| Bot 重启 | ✅ 执行 |
| Web 重启 | ✅ 执行 |
| Bot /start, /status, /advanced, /doctor, /status_json | ✅ 执行 |
| Web login, Dashboard, Status, Advanced mode, Doctor | ✅ 执行 |
| 本地测试套件 | ✅ 执行 |
| Web /healthz | ✅ 执行 |

---

## 8. 问题矩阵

| ID | 严重度 | 发现 | 状态 | 推荐下一步 |
|----|:------:|------|------|-----------|
| T15-P2-001 | P2 | Bot/Web Doctor Summary 显示 Profile/Config unknown，而 Dashboard/Status 显示 Profile present 且真实配置存在 | 新 | 规划真实状态字段兼容性修复 |
| T15-P2-002 | P2 | 高级完整诊断仍显示路径、端口、kernel、工具路径 | 已知 | 保持高级专用；未来 UX/警告/折叠打磨 |
| T15-P2-003 | P2 | /status_json 仍显示 tokenFingerprint/adminTokenFingerprint 类字段 | 已知 | 规划 fingerprint redaction 策略 |
| T15-P2-004 | P2 | Web Doctor 高级完整诊断默认折叠状态未从截图完全确认 | 记录 | 通过模板/测试或后续真实重测确认 |
| T15-P2-005 | P2 | Bot/Web UI 在真实测试中仍主要为英文 | 已知 | i18n 基础存在；规划语言传播/默认中文策略 |
| T15-P1-005 | P1 | Bot/Web 仍非 systemd 产品化 | 已知 | 未来 Bot/Web systemd 安装规划 |
| T15-P2-007 | P2 | Web 使用 Flask 开发服务器 | 已知 | 未来 Web production runner 规划 |

**无 P0。无新 P1 安全泄露。**

---

## 9. 总体测试结论

**T15 有限真实 Bot/Web Doctor 冒烟重测：PASS WITH POLISH**

**通过原因：**

- Bot 重启并在 Telegram 中响应
- Bot /doctor 高级 OFF 仅显示安全摘要
- Bot /doctor 高级 ON 显示警告 + 脱敏完整诊断
- Bot /status_json 门控正常
- Web 启动并登录
- Web Dashboard/Status 安全卡片正常
- Web 高级模式正常
- Web /doctor 高级 OFF 仅显示摘要卡片
- Web /doctor 高级 ON 显示警告 + 脱敏完整诊断
- 未观察到 P0/P1 泄露
- 四协议服务保持活跃
- 无部署/协议服务中断

**非纯 PASS 原因（打磨项）：**

- Doctor Summary Profile/Config 字段兼容性问题
- 高级诊断仍为工程导向
- Fingerprint redaction 策略待定
- Web Doctor 完整诊断折叠状态需更严格确认
- Bot/Web systemd 和 Web production runner 仍非产品化

---

## 10. 建议下一步

**推荐：v1.9.41 — Doctor Summary Real Status Field Compatibility Fix Planning**

但首先需 ChatGPT 审核本 v1.9.40 文档提交。

**未来可能路线：**

| 版本 | 内容 |
|------|------|
| v1.9.41 | Doctor Summary Real Status Field Compatibility Fix Planning |
| v1.9.42 | Fingerprint Redaction Policy Planning |
| 后续 | Bot/Web systemd 安装规划 |
| 后续 | Web production runner 规划 |
| 后续 | CLI 版本显示策略 |
| 后续 | Doctor 完整诊断 UX 打磨 |
| 后续 | 发布候选干净 VPS 回归 |

**不推荐 release/tag。**

---

## 11. Guardrails

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
| 9 | 无 production status wrapper | ✅ |
| 10 | 无 dirty VPS status wrapping | ✅ |
| 11 | 无 operation-log full rollout | ✅ |
| 12 | 无 raw subscription delivery | ✅ |
| 13 | 无 tag/release | ✅ |
