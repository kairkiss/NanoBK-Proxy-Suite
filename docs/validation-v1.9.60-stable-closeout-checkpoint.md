# v1.9.60 — v1.9 Stable Closeout Checkpoint

> 验证类型：v1.9 稳定收口检查点
> 日期：2026-06-06
> 基线 commit：`679d0dfaa517b9eb4addbef92685f42150d2b1f5`
> 基线信息：`docs: add ai maintenance handoff map`

---

## 1. 本轮目标与结论

**v1.9.60 是 v1.9 稳定收口的最终检查点。**

- ✅ 无运行时行为变更
- ✅ 无部署行为变更
- ✅ 无 tag/release
- ✅ 最终聚焦测试全部通过

**结论：READY FOR USER-APPROVED STABLE TAG**

v1.9 Bot/Web 控制面产品化线已完成所有门控项。所有聚焦测试通过。无 P0/P1 安全问题。建议创建 `v1.9.60` 标签，但仅在用户明确批准后执行。

---

## 2. 当前产品状态

| 维度 | 状态 |
|------|------|
| 部署核心 | v1.7.27 受保护基线，未变更 |
| 历史基线 | v1.8.45 收口决策，历史记录 |
| 控制面 | v1.9 Bot/Web 产品化完成 |
| 默认语言 | 中文优先（zh） |
| Web 语言切换 | 会话级别 zh/en 切换 |
| Bot 语言引导 | `/language` 指导命令 |
| 安全状态 | 安全摘要默认，无原始 IP/域名/token |
| 安全诊断 | Doctor 摘要默认，完整诊断仅高级模式 |
| Raw JSON | 高级模式门控，15 分钟过期 |
| 脱敏 | 共享 redaction 助手，Bot/Web 均使用 |
| 真实冒烟测试 | T17 通过（with polish） |
| 版本显示 | `nanobk 1.9.58` |
| AI 维护接口 | 已添加（维护地图、交接模板、门控文档） |
| CLI | `bin/nanobk` 统一入口 |
| 安装器 | `installer/install.sh` 一键安装 |

---

## 3. Completed stable gate items

| 门控项 | 版本 | 状态 |
|--------|------|------|
| Bot/Web 脱敏和 Raw JSON 门控 | v1.9.5–v1.9.9 | ✅ 完成 |
| Bot 安全状态摘要 | v1.9.10 | ✅ 完成 |
| Web 安全状态卡片 | v1.9.11 | ✅ 完成 |
| Raw JSON / 高级诊断策略 | v1.9.12–v1.9.14 | ✅ 完成 |
| 高级诊断模式（Bot/Web） | v1.9.15–v1.9.18 | ✅ 完成 |
| Doctor 摘要（Bot/Web） | v1.9.35–v1.9.38 | ✅ 完成 |
| Bot/Web i18n（en/zh，默认 zh） | v1.9.30–v1.9.32 | ✅ 完成 |
| Bot/Web 默认中文 | v1.9.48 | ✅ 完成 |
| 安装器语言传播 | v1.9.49 | ✅ 完成 |
| Web 会话语言切换 | v1.9.51 | ✅ 完成 |
| Bot `/language` 引导 | v1.9.52 | ✅ 完成 |
| T17 真实中/英文冒烟测试 | v1.9.53–v1.9.55 | ✅ 通过（with polish） |
| 安装器语言测试债务修复 | v1.9.56 | ✅ 完成 |
| Web 中文 Copy 残留修复 | v1.9.57 | ✅ 完成 |
| CLI 版本显示修复 | v1.9.58 | ✅ 完成 |
| AI 维护接口 / 交接地图 | v1.9.59 | ✅ 完成 |
| v1.9.60 收口检查点 | v1.9.60 | ✅ 本文档 |
| 最终聚焦测试 | v1.9.60 | ✅ 全部通过 |

---

## 4. Remaining gate items after this checkpoint

| 门控项 | 状态 |
|--------|------|
| 最终用户批准 | ⏳ 待用户决定 |
| 可选最终真实冒烟重测 | ⏳ 可选（用户决定） |
| 实际 tag 命令 | ⏳ 未执行 |

---

## 5. Final focused test matrix

| 测试 | 结果 |
|------|------|
| `bash tests/maintenance-docs-v1.9.59.sh` | ✅ 35 passed |
| `bash tests/cli-version-display-v1.9.58.sh` | ✅ 28 passed |
| `bash tests/installer-language-propagation-v1.9.49.sh` | ✅ passed |
| `bash tests/bot-cli-mock.sh` | ✅ passed |
| `bash tests/web-panel-mock.sh` | ✅ passed |
| `python3 tests/chinese-default-v1.9.48.py` | ✅ 75 passed |
| `python3 tests/web-language-switch-v1.9.51.py` | ✅ 57 passed |
| `python3 tests/bot-language-command-v1.9.52.py` | ✅ 90 passed |
| `python3 tests/web-chinese-copy-polish-v1.9.57.py` | ✅ passed |
| `python3 tests/i18n-checkpoint-v1.9.32.py` | ✅ 167 passed |
| `python3 tests/raw-json-gating-checkpoint-v1.9.22.py` | ✅ 58 passed |
| `python3 tests/doctor-output-checkpoint-v1.9.38.py` | ✅ 208 passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 228 passed |
| `python3 web/app.py --self-test` | ✅ 118 passed |
| `bash bin/nanobk --version` | ✅ `nanobk 1.9.58` |

**14/14 测试套件通过，0 失败。**

---

## 6. Security posture

| 安全面 | 状态 |
|--------|------|
| 已知 P0/P1 安全泄露 | 无 |
| T17 中观察到的泄露 | 无 raw token/private key/env/subscription URL/workers.dev |
| 脱敏要求 | 持续有效 |
| 高级模式 ≠ 未脱敏 | 确认 |
| Bot/Web 不能直接写 config/systemd/secrets | 确认 |
| env 文件不能读取或粘贴 | 确认 |

---

## 7. Control-plane boundaries

| 边界 | 状态 |
|------|------|
| Bot 仅控制面 | ✅ 确认 |
| Web 仅控制面 | ✅ 确认 |
| Bot/Web 调用 CLI | ✅ 确认 |
| Bot/Web 不直接写 config/systemd/secrets/env | ✅ 确认 |
| `/api/status` 脱敏且有意不门控 | ✅ 确认 |
| Raw JSON UI 高级模式门控 | ✅ 确认 |
| Doctor 完整诊断仅高级模式 | ✅ 确认 |

---

## 8. What is NOT included in v1.9 stable

以下项目明确不要求在 v1.9 稳定标签之前完成：

* systemd 产品化
* Web 生产运行器（Gunicorn/uvicorn）
* 指纹/哈希脱敏策略实现
* 原始订阅交付
* 订阅 QR 交付
* 修复/重启实现
* Cloudflare 控制面变更操作
* 完整清洁 VPS 重部署回归
* UI 重设计
* v2.0 功能

---

## 9. Known limitations accepted for v1.9 stable

| 已接受局限 | 说明 |
|------------|------|
| Bot/Web 运行方式 | 当前测试流程中可能仍通过 run.sh/nohup 运行 |
| Web 服务器 | 当前测试流程中使用 Flask 开发服务器 |
| 高级诊断 | 仍为技术性内容 |
| 指纹/哈希策略 | 仍为未来任务 |
| UI 美观度 | v2.0 可改进 |
| 最终冒烟重测 | 仍为用户决定 |

---

## 10. Tag recommendation

**推荐标签名称：**

```
v1.9.60
```

**推荐标签消息：**

```
NanoBK Proxy Suite v1.9.60 Control Plane Stable
```

**但不执行标签命令。**

标签仅在用户明确批准后创建。

---

## 11. Release notes draft

### NanoBK Proxy Suite v1.9.60 — Control Plane Stable

**亮点：**

* 🇨🇳 中文优先 Bot/Web 控制面
* 🔒 安全状态 / 诊断摘要
* 🛡️ Raw JSON 和高级诊断门控
* 🌐 Web 中/英文会话切换
* 🤖 Bot `/language` 语言引导
* 🔐 共享脱敏层
* ✅ 真实冒烟测试验证
* 📖 AI 维护交接文档

**架构：**

* CLI 是所有密钥和配置的唯一入口
* Bot/Web 仅控制面，通过 subprocess 调用 CLI
* 默认中文，支持英文切换
* 高级诊断 15 分钟自动过期
* 所有输出经过脱敏处理

---

## 12. Next step options

| 选项 | 说明 |
|------|------|
| 1 | 用户批准创建 `v1.9.60` 标签 |
| 2 | 用户要求先执行可选最终真实冒烟重测 |
| 3 | 用户推迟标签，开始 v2.0 规划 |
| 4 | 用户要求最终发布说明润色 |

**推荐：请用户做出明确决定。**

---

## 13. What was intentionally not changed

* Bot 运行时
* Web 运行时
* CLI 行为
* 安装器行为
* env 文件
* 脱敏行为
* Raw JSON 门控
* 高级模式
* rotate
* 部署逻辑
* 协议模板
* Worker
* 无 tag/release

---

## 14. Guardrails for future v2.0

未来工作应与 v1.9 稳定分离：

* Bot/Web systemd 安装规划
* Web 生产运行器
* 订阅交付
* 指纹脱敏
* UI 重设计
* 更清洁的操作日志
* 真实修复/重启流程
* Cloudflare 变更工作流
* 更大版本发布前的完整清洁 VPS 回归
