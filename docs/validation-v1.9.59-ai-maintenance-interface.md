# v1.9.59 — AI Maintenance Interface / Handoff Map

> 验证类型：AI 维护接口 / 交接地图
> 日期：2026-06-06
> 基线 commit：`8dcceddd28c2b64a244ed702656aa150568102b4`
> 基线信息：`fix: update cli version display`

---

## 1. 本轮目标与结论

**v1.9.59 为未来无记忆 AI 贡献者添加维护文档和交接接口。**

- ✅ 仅文档 / 维护接口
- ✅ 无运行时行为变更
- ✅ 无部署行为变更
- ✅ 无 tag/release

**结论：添加了三个核心维护文档（维护地图、AI 交接模板、稳定 tag 门控），一个聚焦测试，和 README 链接。未来 AI 代理可以通过这些文档安全地进行定向修复。**

---

## 2. Added documents

| 文件 | 说明 |
|------|------|
| `docs/maintenance-map.md` | 维护地图：子系统所有权、保护区域、合约、测试矩阵、变更报告清单 |
| `docs/ai-handoff-template.md` | AI 交接模板：可复制粘贴的任务提示模板 |
| `docs/stable-tag-gate-v1.9.md` | 稳定 tag 门控：已完成/待完成门控项、推荐流程 |
| `tests/maintenance-docs-v1.9.59.sh` | 维护文档聚焦测试（35 项检查） |
| `docs/validation-v1.9.59-ai-maintenance-interface.md` | 本文档 |
| `README.md` | 新增维护文档链接 |
| `CHANGELOG.md` | 新增 v1.9.59 条目 |
| `docs/roadmap.md` | 新增 v1.9.59 版本行 |

---

## 3. Maintenance map summary

`docs/maintenance-map.md` 包含：

* **产品目标：** 初学者友好的 VPS 代理自动化套件
* **保护核心：** v1.7.27 部署基线、控制面边界、env 文件和密钥
* **子系统所有权表：** 12 个子系统，每个标注主要文件、职责、安全变更示例、危险变更、必需测试
* **Bot 维护合约：** 仅控制面、仅调用 CLI、仅所有者授权、安全摘要、高级门控
* **Web 维护合约：** 仅控制面、仅调用 CLI、登录/CSRF、高级门控、会话语言切换
* **脱敏合约：** 永不泄露真实 IP/域名/token/URL、使用共享助手
* **语言/i18n 合约：** 默认 zh、NANOBK_LANG 控制、机器值保持英文
* **Doctor 合约：** 摘要默认、完整诊断仅高级模式
* **版本/tag 合约：** 版本显示不暗示 release tag
* **标准测试矩阵：** 11 种变更类型对应的必需测试
* **变更报告清单：** 11 个必需字段
* **永不执行清单：** 9 项禁止操作

---

## 4. AI handoff template summary

`docs/ai-handoff-template.md` 是一个可复制粘贴的模板，包含：

* 任务名称、当前基线 commit、范围、非目标
* 保护文件列表、允许变更、必需测试
* 安全规则、预期报告格式、停止条件
* 用户批准要求、密钥处理提醒、稳定 tag 提醒

**使用方式：** 未来 AI 代理在开始任何任务前，应先读取 `docs/maintenance-map.md`，然后将此模板填入任务提示中。

---

## 5. Stable tag gate summary

`docs/stable-tag-gate-v1.9.md` 包含：

* **当前状态：** 无稳定 tag
* **已完成门控项：** 16 项（脱敏、Doctor、i18n、中文默认、冒烟测试、测试债务修复、Web Copy 修复、CLI 版本修复、AI 维护接口）
* **待完成门控项：** 4 项（v1.9.60 收口检查点、最终聚焦测试、最终用户批准、可选最终冒烟重测）
* **v1.9 稳定 tag 不要求：** systemd、Web 生产运行器、指纹脱敏策略、订阅交付等
* **推荐：** 不在 v1.9.59 tag，准备 v1.9.60 收口检查点

---

## 6. Safety boundaries

| 边界 | 状态 |
|------|------|
| 不读 env 文件 | ✅ |
| 不写 env 文件 | ✅ |
| 不改变运行时行为 | ✅ |
| 不改变 Bot/Web/CLI 行为 | ✅ |
| 不改变安装器部署行为 | ✅ |
| 不改变 redaction/gating/advanced/rotate/deployment | ✅ |
| 不 tag/release | ✅ |

---

## 7. Tests run

| 测试 | 结果 |
|------|------|
| `bash tests/maintenance-docs-v1.9.59.sh` | ✅ 35 passed |
| `bash tests/bot-cli-mock.sh` | ✅ passed |
| `bash tests/web-panel-mock.sh` | ✅ passed |
| `bash tests/cli-version-display-v1.9.58.sh` | ✅ 28 passed |
| `bash tests/installer-language-propagation-v1.9.49.sh` | ✅ passed |
| `python3 tests/chinese-default-v1.9.48.py` | ✅ 75 passed |
| `python3 tests/web-language-switch-v1.9.51.py` | ✅ 57 passed |
| `python3 tests/bot-language-command-v1.9.52.py` | ✅ 90 passed |
| `python3 tests/web-chinese-copy-polish-v1.9.57.py` | ✅ passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 228 passed |
| `python3 web/app.py --self-test` | ✅ 118 passed |

---

## 8. Stable tag impact

* ✅ AI 维护接口门控项可标记为已解决
* 稳定 tag 仍需：
  * v1.9.60 收口检查点
  * 最终聚焦测试通过
  * 无 P0/P1 问题
  * 用户明确批准

---

## 9. Known limitations

| 限制 | 说明 |
|------|------|
| 文档不实现 systemd | 未来任务 |
| 文档不实现 Web 生产运行器 | 未来任务 |
| 文档不实现指纹脱敏 | 未来任务 |
| 文档不交付订阅 | 未来任务 |
| 文档不 tag/release | 需用户批准 |

---

## 10. Next step

**推荐：v1.9.60 — v1.9 Stable Closeout Checkpoint**

仅在 ChatGPT 审核后实施。
