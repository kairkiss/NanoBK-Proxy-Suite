# v1.9.32 — Bot/Web i18n Checkpoint

> 验证类型：Bot/Web i18n 一致性检查点
> 日期：2026-06-05
> 基线 commit：`3c6d863873201a8281c3cafd6db6cf5c249c8c0d`
> 基线信息：`feat: add web i18n support`

---

## 1. 本轮目标与结论

**v1.9.32 是检查点/验证任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release
- ✅ 目的是验证 v1.9.30/v1.9.31 后 Bot/Web i18n 一致性与安全性

**结论：Bot/Web i18n 实现一致、安全、回退友好，未削弱命令语义、redaction、Raw JSON 门控、高级模式、rotate 安全、/api/status 兼容性或无密钥泄漏保证。**

---

## 2. 当前 i18n 架构

### Bot（v1.9.30）

| 特性 | 说明 |
|------|------|
| 语言源 | `NANOBK_LANG=zh\|en` 环境变量 |
| 默认回退 | `en`（缺失/无效时） |
| 中文别名 | `zh`、`zh-cn`、`zh_cn`、`chinese`、`中文` |
| 翻译字典 | `BOT_TEXT`（80+ 条目，zh/en 双语） |
| 翻译辅助 | `bt(lang, key, **kwargs)` 安全回退英文 |
| Builder 函数 | `build_control_center_text()`、`build_help_text()`、`build_guidance_recovery()`、`build_guidance_diagnostics()`、`build_guidance_rotate()`、`build_guidance_web()` |
| 斜杠命令 | 不变（`/start`、`/help`、`/status`、`/status_json`、`/advanced`、`/doctor`、`/rotate_*`、`/cancel`） |
| 状态标签 | 本地化（总览/协议/下一步等） |
| 状态类别值 | 稳定（`healthy`/`failed`/`unknown`/`active` 等不翻译） |
| /status_json 门控 | 不变（高级模式 OFF = 引导，ON = 警告 + 脱敏 JSON） |
| 高级模式 | 不变（15 分钟 TTL，session-only） |
| 回调 | 不变（owner-only，nanobk: 前缀） |
| Redaction | 不变（共享 `lib/nanobk_redaction.py`） |

### Web（v1.9.31）

| 特性 | 说明 |
|------|------|
| 语言源 | `NANOBK_LANG=zh\|en` 环境变量 |
| 默认回退 | `en`（缺失/无效时） |
| 中文别名 | `zh`、`zh-cn`、`zh_cn`、`chinese`、`中文` |
| 翻译模块 | `web/i18n.py` |
| 翻译字典 | `WEB_TEXT`（80+ 条目，zh/en 双语） |
| 翻译辅助 | `wt(lang, key, **kwargs)` 安全回退英文 |
| 模板注入 | Flask context processor 注入 `t()` 和 `lang` |
| 模板调用 | `{{ t('key') }}` |
| 状态标签 | 本地化（总览/协议/下一步等） |
| 状态类别值 | 稳定（`healthy`/`failed`/`unknown`/`active` 等不翻译） |
| Raw JSON 锁定/警告 | 本地化 |
| 高级模式控件 | 本地化 |
| Doctor/Rotate/Login/导航 | 本地化 |
| /api/status | 不变（schema 不变，未门控，返回 redacted JSON） |
| Redaction | 不变（共享 `lib/nanobk_redaction.py`） |

---

## 3. Bot i18n 检查点

### 语言标准化

| 检查 | 结果 |
|------|------|
| `SUPPORTED_LANGS == {"en", "zh"}` | ✅ |
| `DEFAULT_LANG == "en"` | ✅ |
| `normalize_lang(None) == "en"` | ✅ |
| `normalize_lang("") == "en"` | ✅ |
| `normalize_lang("invalid") == "en"` | ✅ |
| `normalize_lang("zh") == "zh"` | ✅ |
| `normalize_lang("zh-cn") == "zh"` | ✅ |
| `normalize_lang("中文") == "zh"` | ✅ |
| `BotConfig.lang` 读取 `NANOBK_LANG` | ✅ |

### 回退行为

| 检查 | 结果 |
|------|------|
| 缺失 key → 返回 key 名 | ✅ |
| 缺失 lang → 回退英文 | ✅ |
| kwargs 格式化安全 | ✅ |

### 翻译覆盖

| 区域 | 英文 | 中文 |
|------|------|------|
| Control Center 标题 | 🏠 NanoBK Control Center | 🏠 NanoBK 控制中心 |
| 按钮标签 | 📊 Status Summary / 🧭 Recovery Help / 🩺 Diagnostics | 📊 状态总览 / 🧭 恢复帮助 / 🩺 诊断检查 |
| /help 标题 | NanoBK Bot Commands | NanoBK 机器人命令 |
| /status 标签 | Overall / VPS / Protocols | 总览 / VPS / 协议 |
| /status_json 警告 | ⚠️ Advanced diagnostics... | ⚠️ 高级诊断... |
| /advanced 消息 | Advanced diagnostics mode enabled | 高级诊断模式已启用 |
| 回调引导 | Recovery Help / Diagnostics / Rotate Secrets / Web Panel | 恢复帮助 / 诊断检查 / 轮换密钥 / Web 面板 |

### 不变边界

| 边界 | 结果 |
|------|------|
| 斜杠命令名不变 | ✅ |
| /status_json 门控不变 | ✅ |
| 高级模式不变（TTL=900s） | ✅ |
| rotate 确认不变 | ✅ |
| 回调 owner-only 不变 | ✅ |
| Redaction 不变 | ✅ |
| 无 raw URL/密钥在翻译字符串中 | ✅ |
| 无 shell=True | ✅ |

---

## 4. Web i18n 检查点

### 语言标准化

| 检查 | 结果 |
|------|------|
| `SUPPORTED_LANGS == {"en", "zh"}` | ✅ |
| `DEFAULT_LANG == "en"` | ✅ |
| `normalize_lang(None) == "en"` | ✅ |
| `normalize_lang("invalid") == "en"` | ✅ |
| `normalize_lang("zh") == "zh"` | ✅ |
| `normalize_lang("zh-cn") == "zh"` | ✅ |
| `normalize_lang("中文") == "zh"` | ✅ |
| `WebConfig.lang` 读取 `NANOBK_LANG` | ✅ |

### web/app.py 检查

> 注：v1.9.31 报告的 Files changed 遗漏了 `web/app.py`，但 GitHub 显示它被修改。本次检查点明确检查了 `web/app.py`。

`web/app.py` 变更内容：
- 新增 `from web.i18n import normalize_lang, wt` 导入
- `WebConfig` 新增 `lang` 字段，`from_env()` 读取 `NANOBK_LANG`
- 新增 `@app.context_processor def inject_i18n()` 注入 `t()` 和 `lang`
- 路由中使用 `wt(config.lang, ...)` 翻译 flash/error 消息

### 翻译覆盖

| 区域 | 英文 | 中文 |
|------|------|------|
| 登录页 | NanoBK Web Panel / Access Token / Login | NanoBK Web 面板 / 访问令牌 / 登录 |
| 导航 | Dashboard / Status / Doctor / Rotate / Logout | 控制台 / 状态 / 诊断 / 轮换 / 退出 |
| Dashboard | NanoBK Dashboard / Quick Actions | NanoBK 控制台 / 快捷操作 |
| 状态卡片 | Overall / VPS / Protocols / Cloudflare / Subscription / Secrets / Profile / Next step | 总览 / VPS / 协议 / Cloudflare / 订阅 / 密钥 / 配置 / 下一步 |
| Raw JSON 锁定 | 🔒 Raw JSON (Advanced Diagnostics) | 🔒 原始 JSON（高级诊断） |
| Raw JSON 警告 | ⚠️ Advanced diagnostics | ⚠️ 高级诊断 |
| 高级模式 | Enable/Disable advanced mode | 启用/禁用高级模式 |
| Doctor | Doctor / Run Doctor / Output | 诊断 / 运行诊断 / 输出 |
| Rotate | Rotate Keys / Confirm Rotation / Select Protocol | 轮换密钥 / 确认轮换 / 选择协议 |

### 不变边界

| 边界 | 结果 |
|------|------|
| /api/status schema 不变 | ✅ |
| /api/status 未门控 | ✅ |
| /api/status 返回 redacted JSON | ✅ |
| Raw JSON 门控不变（advanced_mode_enabled） | ✅ |
| 高级模式不变（TTL=900s） | ✅ |
| rotate 行为不变（CSRF + 确认） | ✅ |
| 状态类别值稳定 | ✅ |
| Redaction 不变 | ✅ |
| 无 raw URL/密钥在翻译字符串中 | ✅ |
| 无 shell=True | ✅ |
| 模板全部使用 `{{ t() }}` | ✅ |

---

## 5. 一致性矩阵

| 边界/能力 | Bot v1.9.30 | Web v1.9.31 | 测试覆盖 | 剩余风险 |
|-----------|:-----------:|:-----------:|:--------:|:--------:|
| NANOBK_LANG 支持 | ✅ | ✅ | Bot i18n test + Web i18n test + checkpoint | 无 |
| 默认回退 en | ✅ | ✅ | Bot i18n test + Web i18n test + checkpoint | 无 |
| 无效回退 en | ✅ | ✅ | Bot i18n test + Web i18n test + checkpoint | 无 |
| zh 支持 | ✅ | ✅ | Bot i18n test + Web i18n test + checkpoint | 无 |
| en 支持 | ✅ | ✅ | Bot i18n test + Web i18n test + checkpoint | 无 |
| 翻译辅助 | `bt()` | `wt()` | Bot i18n test + Web i18n test + checkpoint | 无 |
| 无外部依赖 | ✅ | ✅ | 源码检查 | 无 |
| 命令名/路由不变 | ✅ | ✅ | Bot control center + checkpoint | 无 |
| 状态标签本地化 | ✅ | ✅ | Bot i18n test + Web i18n test | 无 |
| 状态类别值稳定 | ✅ | ✅ | Bot i18n test + Web i18n test + checkpoint | 无 |
| Raw JSON 警告本地化 | ✅ | ✅ | Bot i18n test + Web i18n test | 无 |
| Raw JSON 门控保留 | ✅ | ✅ | Raw JSON gating checkpoint + checkpoint | 无 |
| 高级模式保留 | ✅ | ✅ | Advanced diagnostics checkpoint + checkpoint | 无 |
| rotate 行为保留 | ✅ | ✅ | Control center checkpoint + checkpoint | 无 |
| Redaction 不变 | ✅ | ✅ | Redaction integration checkpoint + checkpoint | 无 |
| 无 raw URL/密钥 | ✅ | ✅ | Bot i18n test + Web i18n test + checkpoint | 无 |
| API schema 不变 | — | ✅ | Web i18n test + checkpoint | 无 |
| 无安装器传播 | ✅ | ✅ | 源码检查 | 未来任务 |
| 无 tag/release | ✅ | ✅ | Git 检查 | 无 |

---

## 6. 测试覆盖检查点

### Bot i18n 测试安全性

`tests/bot-i18n-minimal-v1.9.30.py` 在 v1.9.31 适配后仍保留以下安全断言：

- ✅ 检查 `no TOKEN= in translations`
- ✅ 检查 `no SECRET= in translations`
- ✅ 检查 `no PRIVATE_KEY= in translations`
- ✅ 检查 `no workers.dev in translations`
- ✅ 检查 `no http:// in translations`
- ✅ 检查 `no https:// in translations`
- ✅ 检查斜杠命令注册（CommandHandler）
- ✅ 检查 `no shell=True`
- ✅ 检查共享 redaction 导入
- ✅ 检查状态类别值不翻译

**结论：v1.9.31 适配未弱化 Bot i18n 测试的安全断言。**

### Web i18n 测试覆盖

`tests/web-i18n-minimal-v1.9.31.py`（123 项）覆盖：

- ✅ 语言标准化（zh/en/无效/别名）
- ✅ 翻译辅助功能
- ✅ 登录/Dashboard/状态/Raw JSON/高级/Doctor/Rotate 文案
- ✅ /api/status 不变
- ✅ 无密钥在翻译中
- ✅ 安全检查（无 shell=True）
- ✅ 模板门控结构

### 现有测试通过

所有 24+ 测试套件通过，包括 redaction/gating/control-center/i18n 测试。

---

## 7. 安全决策

**Bot/Web i18n 作为 UI 翻译层是安全的。**

但 i18n 实现不构成以下许可：

- ❌ 泄漏原始 IP/domain/URL
- ❌ 泄漏 workers.dev
- ❌ 泄漏 subscription URL/path
- ❌ 泄漏 token/secret/private key
- ❌ 读取 env 文件
- ❌ 改变 /api/status schema
- ❌ 改变 Raw JSON 门控
- ❌ 翻译 raw JSON key/value
- ❌ 运行 production status wrapper
- ❌ 运行 dirty VPS status wrapping
- ❌ 交付 subscription
- ❌ tag/release

---

## 8. 就绪决策

**A. READY FOR DOCTOR OUTPUT PRODUCTIZATION PLANNING**

原因：v1.9.28 真实冒烟测试确认 /doctor 输出过于技术化。Bot/Web i18n 已实现，下一步用户面打磨应规划面向新手的 doctor 输出 vs 高级完整诊断。

---

## 9. 可能的下一步选项

| 选项 | 内容 | 推荐 |
|------|------|------|
| **选项 1** | v1.9.33 — Doctor Output Productization Planning | ✅ 推荐 |
| 选项 2 | v1.9.33 — Bot/Web systemd Install Planning | 次选 |
| 选项 3 | v1.9.33 — Web Production Runner Planning | 次选 |
| 选项 4 | v1.9.33 — i18n Real Smoke Retest Plan | 可选 |

**推荐选项 1：v1.9.33 — Doctor Output Productization Planning**

原因：/doctor 在真实冒烟测试中被标记为过于工程化。它影响 Bot 和 Web 用户体验，应在 systemd/Web runner 工作之前规划。

---

## 10. 剩余阻塞项

| 阻塞项 | 状态 |
|--------|------|
| Doctor 输出产品化 | 待规划 |
| Bot/Web systemd 产品化 | 待规划 |
| Web production runner | 待规划 |
| CLI 版本显示策略 | 待规划 |
| Fingerprint redaction 策略 | 待规划 |
| Raw subscription 交付 | 阻塞 |
| Subscription QR 交付 | 阻塞 |
| Production status wrapper | 阻塞 |
| Dirty VPS status wrapping | 阻塞 |
| Operation-log full rollout | 阻塞 |
| 直接 Bot/Web repair/restart | 阻塞 |
| Cloudflare mutating operations | 阻塞 |
| Full clean VPS release-candidate regression | 阻塞 |
| Release/tag | 阻塞 |

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
| `python3 tests/redaction-integration-checkpoint-v1.9.9.py` | ✅ 94 passed |
| `python3 tests/bot-safe-status-summary-v1.9.10.py` | ✅ 67 passed |
| `python3 tests/web-safe-status-cards-v1.9.11.py` | ✅ 82 passed |
| `python3 tests/bot-status-json-warning-v1.9.13.py` | ✅ 53 passed |
| `python3 tests/web-raw-json-warning-v1.9.14.py` | ✅ 37 passed |
| `python3 tests/bot-advanced-mode-v1.9.16.py` | ✅ 65 passed |
| `python3 tests/web-advanced-mode-v1.9.17.py` | ✅ 64 passed |
| `python3 tests/advanced-diagnostics-checkpoint-v1.9.18.py` | ✅ 80 passed |
| `python3 tests/bot-status-json-soft-gate-v1.9.20.py` | ✅ 50 passed |
| `python3 tests/web-raw-json-soft-gate-v1.9.21.py` | ✅ 48 passed |
| `python3 tests/raw-json-gating-checkpoint-v1.9.22.py` | ✅ 58 passed |
| `python3 tests/bot-control-center-menu-v1.9.24.py` | ✅ 47 passed |
| `python3 tests/bot-control-center-callback-polish-v1.9.25.py` | ✅ 50 passed |
| `python3 tests/bot-control-center-checkpoint-v1.9.26.py` | ✅ 66 passed |
| `python3 tests/bot-i18n-minimal-v1.9.30.py` | ✅ 116 passed |
| `python3 tests/web-i18n-minimal-v1.9.31.py` | ✅ 123 passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 117 passed |
| `python3 web/app.py --self-test` | ✅ 75 passed |
| `python3 tests/i18n-checkpoint-v1.9.32.py` | ✅ 167 passed |

---

## 12. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Bot/Web session 重测 | i18n 后未重测，用户可后续执行 |
| 安装器语言传播未实现 | 未来规划 |
| Doctor 输出仍技术化 | 独立任务 |
| Fingerprint redaction 未变更 | 独立任务 |
| Production status wrapper 仍阻塞 | 未批准 |
| Raw subscription 交付仍阻塞 | 未批准 |

---

## 13. Guardrails

| # | 约束 | 状态 |
|---|------|------|
| 1 | 无 install.sh 行为变更 | ✅ |
| 2 | 无 bin/nanobk 行为变更 | ✅ |
| 3 | 无协议模板变更 | ✅ |
| 4 | 无 Worker 变更 | ✅ |
| 5 | 无 rotate sync 变更 | ✅ |
| 6 | 无直接 Bot/Web 写入 configs/systemd/secrets | ✅ |
| 7 | 无 raw env 读取 | ✅ |
| 8 | 无 production status wrapper | ✅ |
| 9 | 无 dirty VPS status wrapping | ✅ |
| 10 | 无 operation-log full rollout | ✅ |
| 11 | 无 raw subscription 交付 | ✅ |
| 12 | 无 tag/release | ✅ |
