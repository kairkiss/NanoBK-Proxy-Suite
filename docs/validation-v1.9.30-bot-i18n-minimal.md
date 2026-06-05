# v1.9.30 — Bot i18n Minimal Implementation Validation

> 验证类型：Bot 最小 zh/en 国际化实现
> 日期：2026-06-05
> 基线 commit：`cf92fe68deff4734b511584b3306c1cec0bef036`
> 基线信息：`docs: add v1.9.29 bot web i18n planning`

---

## 1. 本轮目标与结论

**v1.9.30 实现了 Bot 最小 zh/en 国际化：**

- ✅ `NANOBK_LANG=zh|en` 环境变量支持
- ✅ 缺失/无效值默认英文
- ✅ 斜杠命令名不变
- ✅ 仅翻译 Bot 控制面文本
- ✅ 不改变命令语义
- ✅ 不改变 redaction
- ✅ 不改变 /status_json 门控
- ✅ 不改变高级模式行为
- ✅ 不改变 rotate 行为
- ✅ 不改变 Web
- ✅ 不改变安装器
- ✅ 无 tag/release

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | 新增 i18n 系统 + 翻译字典 + 翻译辅助函数 + 更新所有用户面向文本 |
| `tests/bot-i18n-minimal-v1.9.30.py` | 新增测试（116 项） |
| `tests/bot-control-center-callback-polish-v1.9.25.py` | 更新测试（适配新常量） |
| `tests/bot-control-center-menu-v1.9.24.py` | 更新测试（适配新常量） |
| `tests/bot-control-center-checkpoint-v1.9.26.py` | 更新测试（适配新常量） |
| `tests/raw-json-gating-checkpoint-v1.9.22.py` | 更新测试（适配新常量） |
| `tests/bot-advanced-mode-v1.9.16.py` | 更新测试（适配新常量） |
| `tests/bot-status-json-warning-v1.9.13.py` | 更新测试（适配新常量） |
| `docs/validation-v1.9.30-bot-i18n-minimal.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.30 条目 |
| `docs/roadmap.md` | 新增 v1.9.30 版本行 |

---

## 3. Bot 语言来源行为

| 特性 | 说明 |
|------|------|
| 环境变量 | `NANOBK_LANG=zh|en` |
| 默认值 | `en`（向后兼容） |
| 无效值 | 回退到 `en` |
| 中文别名 | `zh`、`zh-cn`、`zh_cn`、`chinese`、`中文` |
| 存储 | `BotConfig.lang` 字段 |
| 持久化 | 无（env 读取，不写入） |
| 暴露 | 不在 UI 中暴露 env 值 |

---

## 4. 翻译辅助摘要

| 函数 | 说明 |
|------|------|
| `normalize_lang(value)` | 标准化语言代码，返回 `en` 或 `zh` |
| `bt(lang, key, **kwargs)` | 获取翻译文本，支持 kwargs 格式化，安全回退英文 |
| `build_control_center_text(lang)` | 构建控制中心文本 |
| `build_help_text(lang)` | 构建帮助文本 |
| `build_guidance_recovery(lang)` | 构建恢复引导 |
| `build_guidance_diagnostics(lang)` | 构建诊断引导 |
| `build_guidance_rotate(lang)` | 构建轮换引导 |
| `build_guidance_web(lang)` | 构建 Web Panel 引导 |

---

## 5. 本地化 Bot 区域

| 区域 | 英文 | 中文 |
|------|------|------|
| Control Center 标题 | 🏠 NanoBK Control Center | 🏠 NanoBK 控制中心 |
| 按钮标签 | 📊 Status Summary | 📊 状态总览 |
| /help 标题 | NanoBK Bot Commands | NanoBK 机器人命令 |
| /status 标签 | Overall / VPS / Protocols | 总览 / VPS / 协议 |
| /advanced 消息 | Advanced diagnostics mode enabled | 高级诊断模式已启用 |
| /status_json 门控 | Advanced diagnostics mode is not enabled | 高级诊断模式未启用 |
| /status_json 警告 | This output is redacted... | 此输出已脱敏... |
| 回调引导 | Recovery Help / Diagnostics / Rotate Secrets / Web Panel | 恢复帮助 / 诊断检查 / 轮换密钥 / Web 面板 |
| 未授权 | Unauthorized | 未授权 |
| 错误消息 | Unknown command / No pending confirmation | 未知命令 / 无待处理确认 |

**状态类别值（healthy/failed/unknown 等）不翻译。**

---

## 6. 安全/redaction 边界

| 安全特性 | 状态 |
|----------|------|
| 斜杠命令名不变 | ✅ |
| redaction 不变 | ✅ |
| /status_json 门控不变 | ✅ |
| 高级模式不变 | ✅ |
| rotate 确认不变 | ✅ |
| 回调 owner-only 不变 | ✅ |
| Web Panel 引导无 raw URL | ✅ |
| 翻译字符串无 raw secret | ✅ |
| 无外部依赖 | ✅ |

---

## 7. 斜杠命令兼容性

| 命令 | 状态 |
|------|------|
| /start | ✅ 不变 |
| /help | ✅ 不变（内容本地化） |
| /status | ✅ 不变（标签本地化） |
| /status_json | ✅ 不变（警告本地化） |
| /advanced | ✅ 不变（消息本地化） |
| /doctor | ✅ 不变（运行消息本地化） |
| /rotate_* | ✅ 不变 |
| /cancel | ✅ 不变 |

---

## 8. 测试运行

| 测试 | 结果 |
|------|------|
| Bot self-test（117 项） | ✅ All passed |
| `tests/bot-i18n-minimal-v1.9.30.py`（116 项） | ✅ All passed |
| `tests/bot-control-center-menu-v1.9.24.py` | ✅ All passed |
| `tests/bot-control-center-callback-polish-v1.9.25.py` | ✅ All passed |
| `tests/bot-control-center-checkpoint-v1.9.26.py` | ✅ All passed |
| `tests/raw-json-gating-checkpoint-v1.9.22.py` | ✅ All passed |
| `tests/bot-advanced-mode-v1.9.16.py` | ✅ All passed |
| `tests/bot-status-json-warning-v1.9.13.py` | ✅ All passed |
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
| `python3 tests/web-raw-json-warning-v1.9.14.py` | ✅ All passed |
| `python3 tests/web-advanced-mode-v1.9.17.py` | ✅ All passed |
| `python3 tests/advanced-diagnostics-checkpoint-v1.9.18.py` | ✅ All passed |
| `python3 tests/web-raw-json-soft-gate-v1.9.21.py` | ✅ All passed |
| `python3 web/app.py --self-test` | ✅ All passed |

---

## 9. 已知限制

| 限制 | 说明 |
|------|------|
| Web i18n 未实现 | v1.9.31 任务 |
| 安装器语言传播未实现 | 未来规划 |
| Doctor 输出产品化未实现 | 独立任务 |
| Fingerprint redaction 未变更 | 独立任务 |
| 真实 Bot session 未重测 | 用户可后续执行 |

---

## 10. 下一步

**推荐：v1.9.31 — Web i18n Minimal Implementation**

需 ChatGPT 审核后实施。
