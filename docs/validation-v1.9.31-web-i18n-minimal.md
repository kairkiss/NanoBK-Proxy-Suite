# v1.9.31 — Web i18n Minimal Implementation Validation

> 验证类型：Web 最小 zh/en 国际化实现
> 日期：2026-06-05
> 基线 commit：`2b07fef056b1103882f6ac6e524fa40b36e11a38`
> 基线信息：`feat: add bot i18n support`

---

## 1. 本轮目标与结论

**v1.9.31 实现了 Web 最小 zh/en 国际化：**

- ✅ `NANOBK_LANG=zh|en` 环境变量支持
- ✅ 缺失/无效值默认英文
- ✅ 翻译字典模块 `web/i18n.py`
- ✅ 模板使用 `{{ t('key') }}` 翻译调用
- ✅ 仅翻译 Web UI 文本
- ✅ 不改变 /api/status schema
- ✅ 不改变 redaction
- ✅ 不改变 Raw JSON 门控行为
- ✅ 不改变高级模式行为
- ✅ 不改变 rotate 行为
- ✅ 不改变 Bot
- ✅ 不改变安装器
- ✅ 无 tag/release

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `web/i18n.py` | 新增翻译字典模块 |
| `web/app.py` | 新增 NANOBK_LANG 读取 + context processor + 翻译辅助 |
| `web/templates/layout.html` | 使用翻译调用 |
| `web/templates/login.html` | 使用翻译调用 |
| `web/templates/index.html` | 使用翻译调用 |
| `web/templates/status.html` | 使用翻译调用 |
| `web/templates/rotate.html` | 使用翻译调用 |
| `web/templates/doctor.html` | 使用翻译调用 |
| `tests/web-i18n-minimal-v1.9.31.py` | 新增测试（123 项） |
| `tests/web-raw-json-warning-v1.9.14.py` | 更新测试（适配翻译 key） |
| `tests/web-advanced-mode-v1.9.17.py` | 更新测试（适配翻译 key） |
| `tests/advanced-diagnostics-checkpoint-v1.9.18.py` | 更新测试（适配翻译 key） |
| `tests/web-raw-json-soft-gate-v1.9.21.py` | 更新测试（适配翻译 key） |
| `tests/raw-json-gating-checkpoint-v1.9.22.py` | 更新测试（适配翻译 key） |
| `tests/bot-i18n-minimal-v1.9.30.py` | 更新测试（适配 Web i18n） |
| `docs/validation-v1.9.31-web-i18n-minimal.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.31 条目 |
| `docs/roadmap.md` | 新增 v1.9.31 版本行 |

---

## 3. Web 语言来源行为

| 特性 | 说明 |
|------|------|
| 环境变量 | `NANOBK_LANG=zh|en` |
| 默认值 | `en`（向后兼容） |
| 无效值 | 回退到 `en` |
| 中文别名 | `zh`、`zh-cn`、`zh_cn`、`chinese`、`中文` |
| 存储 | `WebConfig.lang` 字段 |
| 模板注入 | context processor 提供 `t()` 函数和 `lang` 变量 |
| 持久化 | 无（env 读取，不写入） |

---

## 4. 翻译辅助摘要

| 组件 | 说明 |
|------|------|
| `web/i18n.py` | 翻译字典模块 |
| `normalize_lang(value)` | 标准化语言代码 |
| `wt(lang, key, **kwargs)` | 获取翻译文本，支持 kwargs 格式化 |
| `WEB_TEXT` | 翻译字典（80+ 条目，zh/en 双语） |
| `{{ t('key') }}` | 模板中的翻译调用 |

---

## 5. 本地化 Web 区域

| 区域 | 英文 | 中文 |
|------|------|------|
| 登录页标题 | NanoBK Web Panel | NanoBK Web 面板 |
| 登录按钮 | Login | 登录 |
| 导航栏 | Dashboard / Status / Doctor / Rotate / Logout | 控制台 / 状态 / 诊断 / 轮换 / 退出 |
| Dashboard 标题 | NanoBK Dashboard | NanoBK 控制台 |
| 状态卡片标签 | Overall / VPS / Protocols / Cloudflare / Subscription / Secrets / Profile / Next step | 总览 / VPS / 协议 / Cloudflare / 订阅 / 密钥 / 配置 / 下一步 |
| 页脚 | Status from nanobk CLI. Sensitive addresses are hidden. | 状态来自 nanobk CLI。敏感地址已隐藏。 |
| Raw JSON 锁定面板 | 🔒 Raw JSON (Advanced Diagnostics) | 🔒 原始 JSON（高级诊断） |
| Raw JSON 警告 | ⚠️ Advanced diagnostics | ⚠️ 高级诊断 |
| 高级模式控件 | Enable/Disable advanced mode | 启用/禁用高级模式 |
| Doctor 页面 | Doctor / Run Doctor / Output | 诊断 / 运行诊断 / 输出 |
| Rotate 页面 | Rotate Keys / Confirm Rotation / Select Protocol | 轮换密钥 / 确认轮换 / 选择协议 |

**状态类别值（healthy/failed/unknown 等）不翻译。**

---

## 6. 安全/redaction 边界

| 安全特性 | 状态 |
|----------|------|
| /api/status schema 不变 | ✅ |
| redaction 不变 | ✅ |
| Raw JSON 门控不变 | ✅ |
| 高级模式不变 | ✅ |
| rotate 行为不变 | ✅ |
| 翻译字符串无 raw secret | ✅ |
| 无 raw URL 显示 | ✅ |

---

## 7. /api/status 兼容性

| 特性 | 状态 |
|------|------|
| 路由存在 | ✅ |
| 未门控 | ✅ |
| 返回 redacted JSON | ✅ |
| schema 不变 | ✅ |

---

## 8. 测试运行

| 测试 | 结果 |
|------|------|
| Web self-test（75 项） | ✅ All passed |
| `tests/web-i18n-minimal-v1.9.31.py`（123 项） | ✅ All passed |
| 全部 24 个测试套件 | ✅ All passed |

---

## 9. v1.9.30 CHANGELOG 打磨

修正了 v1.9.30 CHANGELOG 中的表述：
- 旧：`Bot self-test expanded from 117 to 117 tests with zh/en verification.`
- 新：`Bot self-test now covers 117 tests with zh/en verification.`

---

## 10. 已知限制

| 限制 | 说明 |
|------|------|
| 安装器语言传播未实现 | 未来规划 |
| Doctor 输出产品化未实现 | 独立任务 |
| Fingerprint redaction 未变更 | 独立任务 |
| 真实 Web session 未重测 | 用户可后续执行 |
| Bot 已在 v1.9.30 实现 | 未变更 |

---

## 11. 下一步

**推荐：v1.9.32 — i18n Checkpoint**

需 ChatGPT 审核后实施。
