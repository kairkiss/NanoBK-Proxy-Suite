# v1.9.22 — Raw JSON Gating Checkpoint

> 验证类型：Raw JSON 软门控一致性检查点
> 日期：2026-06-05
> 基线 commit：`e9288a1750481e21607bf961265253a3b4db32f1`
> 基线信息：`feat: gate web raw json`

---

## 1. 本轮目标与结论

**v1.9.22 是检查点/验证任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release
- ✅ 目的是验证 Bot/Web Raw JSON 软门控一致性和安全性

**结论：Bot `/status_json` 和 Web Raw JSON details 的软门控在安全性和一致性方面均通过检查。两者都使用高级诊断模式作为门控，OFF 状态不输出 JSON，ON 状态显示警告 + 脱敏 JSON。可以进入控制面 UX 打磨规划阶段。**

---

## 2. 当前 Raw JSON 门控架构

### Bot

| 特性 | 说明 |
|------|------|
| `/status_json` | 仍可用 |
| 高级模式 OFF | 引导信息，不输出 JSON，不调用 nanobk |
| 高级模式 ON | 警告 + redacted JSON |
| 过期模式 | 表现为 OFF |
| `/status` | 安全新手摘要，不变 |

### Web

| 特性 | 说明 |
|------|------|
| Raw JSON 区域 | 仍可发现 |
| 高级模式 OFF | 锁定面板，不渲染 `status.raw_json` |
| 高级模式 ON | 警告 + Redacted Raw JSON details |
| 过期模式 | 表现为 OFF |
| `/api/status` | 仍可用，未门控 |
| 安全卡片 | 仍可见 |

### 共享

- redaction 不变
- 无 raw subscription delivery
- 无 production status wrapper
- 无 dirty VPS status wrapping
- 无直接 env 读取
- 高风险操作不变

---

## 3. Bot 检查点

| 检查项 | 状态 |
|--------|------|
| `/status_json` 软门控 | ✅ |
| OFF 状态不调用 run_nanobk | ✅ |
| OFF 状态不输出 JSON | ✅ |
| OFF 状态引导至 `/status` 和 `/advanced on` | ✅ |
| ON 状态保留警告 + redacted JSON | ✅ |
| 过期模式表现 OFF | ✅ |
| `run_nanobk(config, ["--json", "status"])` 参数不变 | ✅ |
| `safe_output()` 仍使用 | ✅ |
| `/status` 不变 | ✅ |
| rotate 不变 | ✅ |
| redaction 不变 | ✅ |

---

## 4. Web 检查点

| 检查项 | 状态 |
|--------|------|
| Raw JSON 区域软门控 | ✅ |
| OFF 状态显示锁定面板 | ✅ |
| OFF 状态不渲染 `status.raw_json` | ✅ |
| OFF 状态提供 POST + CSRF 启用表单 | ✅ |
| ON 状态显示警告 + Redacted Raw JSON details | ✅ |
| details 默认折叠 | ✅ |
| 过期模式表现 OFF | ✅ |
| `/api/status` 未门控 | ✅ |
| 状态卡片不变 | ✅ |
| login/session/CSRF 不变 | ✅ |
| rotate 不变 | ✅ |
| redaction 不变 | ✅ |

---

## 5. 一致性矩阵

| 能力/边界 | Bot v1.9.20 | Web v1.9.21 | 测试覆盖 | 剩余风险 |
|----------|-------------|-------------|----------|----------|
| Raw JSON 入口可发现 | ✅ | ✅ | ✅ | 无 |
| 高级模式 OFF 行为 | ✅ 引导信息 | ✅ 锁定面板 | ✅ | 无 |
| 高级模式 ON 行为 | ✅ 警告+JSON | ✅ 警告+JSON | ✅ | 无 |
| 过期模式行为 | ✅ 表现 OFF | ✅ 表现 OFF | ✅ | 无 |
| 普通状态回退 | ✅ `/status` | ✅ 安全卡片 | ✅ | 无 |
| 警告文案 | ✅ | ✅ | ✅ | 无 |
| redaction 不变 | ✅ | ✅ | ✅ | 无 |
| Raw JSON 对新手隐藏 | ✅ | ✅ | ✅ | 无 |
| 诊断仍可用 | ✅ | ✅ | ✅ | 无 |
| API/status_json 边界 | ✅ 未变更 | ✅ `/api/status` 未门控 | ✅ | 无 |
| 无 raw subscription delivery | ✅ | ✅ | ✅ | 无 |
| 无 status wrapper | ✅ | ✅ | ✅ | 无 |
| 无直接 env 读取 | ✅ | ✅ | ✅ | 无 |
| 高风险操作不变 | ✅ | ✅ | ✅ | 无 |
| 无 tag/release | ✅ | ✅ | ✅ | 无 |

---

## 6. 安全决策

Raw JSON 软门控作为 UI/诊断可见性控制是安全的。

**但它不构成以下许可：**

- 展示 raw IP/domain/URL
- 展示 workers.dev
- 展示 subscription URL/path
- 展示 tokens/secrets/private keys
- 读取 env 文件
- 运行 production status wrapper
- 运行 dirty VPS status wrapping
- 交付订阅
- 运行 repair/restart/Cloudflare mutations

---

## 7. 就绪决策

**A. READY FOR CONTROL-PLANE UX POLISH PLANNING**

**范围限制：**

- ✅ 就绪于控制面 UX 打磨规划
- ✅ 也适合规划后续真实 Bot/Web 冒烟测试
- ❌ 不就绪于完整真实 VPS 部署回归
- ❌ 不就绪于 tag/release
- ❌ 不就绪于 production status wrapper
- ❌ 不就绪于 raw subscription delivery

---

## 8. 可选下一步方案

| 方案 | 说明 | 推荐 |
|------|------|------|
| v1.9.23 — Bot 控制中心菜单规划 | 规划 Bot 产品化控制中心 UX | ✅ 推荐 |
| v1.9.23 — Bot 控制中心菜单最小实现 | 实现 Bot 菜单 | 需先规划 |
| v1.9.23 — 真实 Bot/Web 冒烟测试规划 | 规划有限真实测试 | 可选 |
| v1.9.23 — Web Dashboard UX 打磨规划 | 规划 Web UX 打磨 | 可选 |

**推荐：v1.9.23 — Bot Control Center Menu Planning**

**理由：** 状态安全、高级模式和 Raw JSON 门控已就位，Bot 可以进入产品化控制中心 UX 规划。先规划再实现，避免大范围菜单/按钮变更。

---

## 9. 真实 VPS / Bot-Web 冒烟测试定位

- 不运行完整真实 VPS 部署测试
- v1.9 主要变更了 Bot/Web UI、redaction、诊断可见性和测试
- `installer/install.sh`、VPS 模板、Worker 核心、rotate sync、部署逻辑未变更
- 完整真实 VPS 部署回归应等到部署/status/Cloudflare/rotate 核心变更或发布候选
- v1.9.22 后可规划有限真实 Bot/Web 冒烟测试
- 第一次真实冒烟测试应仅限控制面：
    - Bot 启动
    - owner-only 有效
    - `/status` 安全摘要
    - `/advanced on/off/status`
    - `/status_json` OFF/ON 行为
    - Web 登录
    - Web 高级切换
    - Web Raw JSON 锁定/解锁行为
    - `/api/status` 脱敏
    - 无 raw IP/domain/token/workers.dev/subscription URL 出现
- 不要求用户粘贴真实 secrets 或 raw env

---

## 10. 剩余阻塞项

| 事项 | 状态 | 说明 |
|------|------|------|
| Raw subscription delivery | 阻塞 | 需独立安全设计 |
| Subscription QR delivery | 阻塞 | 需独立安全设计 |
| Production status wrapper | 阻塞 | 未批准 |
| Dirty VPS status wrapping | 阻塞 | 未批准 |
| Operation-log full rollout | 阻塞 | 未批准 |
| 直接 Bot/Web repair/restart | 阻塞 | 未实现 |
| Cloudflare 变更操作 | 阻塞 | 未实现 |
| 直接 config/systemd/secrets 写入 | 阻塞 | 安全禁止 |
| Raw env 读取/显示 | 阻塞 | 安全禁止 |
| Release/tag | 阻塞 | 未批准 |

---

## 11. 测试运行

| 测试 | 结果 |
|------|------|
| `bash tests/bot-cli-mock.sh` | ✅ All passed |
| `bash tests/web-panel-mock.sh` | ✅ All passed |
| `bash tests/bot-web-command-allowlist-v1.9.4.sh` | ✅ All passed |
| `bash tests/redaction-address-class-v1.9.5.sh` | ✅ All passed |
| `python3 tests/redaction-helper-v1.9.6.py` | ✅ All passed |
| `python3 tests/bot-redaction-helper-integration-v1.9.7.py` | ✅ All passed |
| `python3 tests/web-redaction-helper-integration-v1.9.8.py` | ✅ All passed |
| `python3 tests/redaction-integration-checkpoint-v1.9.9.py` | ✅ All passed |
| `python3 tests/bot-safe-status-summary-v1.9.10.py` | ✅ All passed |
| `python3 tests/web-safe-status-cards-v1.9.11.py` | ✅ All passed |
| `python3 tests/bot-status-json-warning-v1.9.13.py` | ✅ All passed |
| `python3 tests/web-raw-json-warning-v1.9.14.py` | ✅ All passed |
| `python3 tests/bot-advanced-mode-v1.9.16.py` | ✅ All passed |
| `python3 tests/web-advanced-mode-v1.9.17.py` | ✅ All passed |
| `python3 tests/advanced-diagnostics-checkpoint-v1.9.18.py` | ✅ All passed |
| `python3 tests/bot-status-json-soft-gate-v1.9.20.py` | ✅ All passed |
| `python3 tests/web-raw-json-soft-gate-v1.9.21.py` | ✅ All passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ All passed |
| `python3 web/app.py --self-test` | ✅ All passed |
| `python3 tests/raw-json-gating-checkpoint-v1.9.22.py` | ✅ All passed |

---

## 12. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Bot session | 未连接 Telegram |
| 无真实 Web 浏览器 session | 未启动 Web 服务器 |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| 检查点依赖 mock/source 测试 | 无真实运行时验证 |
| `/api/status` 故意未门控 | v1.9.19 策略 |
| Production status wrapper 仍阻塞 | 未批准 |
| Raw subscription delivery 仍阻塞 | 未批准 |

---

## 13. Guardrails

| # | 约束 | 说明 |
|---|------|------|
| 1 | 禁止修改 `install.sh` | 保护 v1.7.27 基线 |
| 2 | 禁止修改 `bin/nanobk` | 保护 CLI 核心 |
| 3 | 禁止修改协议模板 | 保护部署 |
| 4 | 禁止修改 Worker | 保护 Cloudflare |
| 5 | 禁止修改 rotate sync | 保护轮换 |
| 6 | 禁止直接 Bot/Web 写入 configs/systemd/secrets | 安全 |
| 7 | 禁止 raw env 读取 | 安全 |
| 8 | 禁止 production status wrapper | 未批准 |
| 9 | 禁止 dirty VPS status wrapping | 未批准 |
| 10 | 禁止 operation-log full rollout | 未批准 |
| 11 | 禁止 raw subscription delivery | 未批准 |
| 12 | 禁止 tag/release | 未批准 |
