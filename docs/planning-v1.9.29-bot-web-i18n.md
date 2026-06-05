# v1.9.29 — Bot/Web i18n Planning

> 规划类型：Bot/Web 中英文国际化规划文档
> 日期：2026-06-05
> 基线 commit：`07892c7073dc0934430824b377f286fd907d8bd1`
> 基线信息：`docs: add v1.9.28 real smoke test validation`

---

## 1. 本轮目标与结论

**v1.9.29 是规划/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release
- ✅ 目的是规划 Bot/Web zh/en 国际化策略

**结论：定义安全的分阶段 i18n 策略——先 Bot 后 Web，使用显式 NANOBK_LANG 环境变量，翻译标签和文案而非命令名，不改变 redaction/安全规则。**

---

## 2. 为什么需要 i18n

| 理由 | 说明 |
|------|------|
| 真实冒烟测试确认可用但英文为主 | v1.9.28 PASS WITH POLISH |
| 目标新手用户可能偏好中文 | 初学者友好 |
| 安装器已支持语言流程 | Bot/Web 应跟上 |
| Bot/Web 应成为 zh/en 新手友好 | 产品化 |
| i18n 不得削弱安全/redaction | 安全底线 |
| i18n 不得改变命令语义 | 稳定性底线 |

---

## 3. 当前文案现状

### Bot

| 区域 | 当前状态 |
|------|----------|
| /start Control Center | 英文 |
| /help | 英文 |
| /status 安全摘要 | 英文（标签） |
| /advanced on/off/status | 英文 |
| /status_json 警告/门控 | 英文 |
| /doctor 输出 | CLI 英文 |
| 回调引导 | 英文 |
| Rotate 引导 | 英文 |
| Web Panel 引导 | 英文 |

### Web

| 区域 | 当前状态 |
|------|----------|
| 登录页 | 英文 |
| Dashboard | 英文 |
| Status 页面 | 英文 |
| 安全卡片 | 英文 |
| Raw JSON 锁定/警告 | 英文 |
| 高级模式控件 | 英文 |
| Doctor 页面 | 英文 |
| Rotate 页面 | 英文 |
| 错误/Flash 消息 | 英文 |

**结论：Bot/Web 文案以英文为主，需中英文支持。**

---

## 4. 语言来源策略

### 选项对比

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| A. `NANOBK_LANG=zh\|en` | Bot/Web env 显式设置 | 简单、显式、可控 | 需要 env 配置 |
| B. 继承安装器 `--lang` | 安装器写入 Bot/Web env | 无缝 | 需要安装器变更 |
| C. 存储在 profile/config | 持久化语言偏好 | 持久化 | 增加复杂度 |
| D. 自动检测浏览器/Telegram 语言 | 自动化 | 方便 | 不可控、可能误判 |

### 推荐方案

**A. 显式 `NANOBK_LANG=zh|en`**

- v1.9.x 先使用显式 env 变量
- 缺失时默认 `en`（向后兼容）
- 未来安装器可安全写入 `NANOBK_LANG`
- 不自动检测
- 不在 UI 中暴露 env 值

---

## 5. Bot i18n 设计

### 翻译字典/常量

- 中心化翻译字典或常量
- 辅助函数 `t(key, lang="en", **kwargs)`
- 安全回退到英文
- 不将 secret 或 raw status 值格式化到翻译字符串中

### 命令名不变

以下命令名保持不变（不翻译）：

- `/start`、`/help`、`/status`、`/status_json`、`/advanced`、`/doctor`、`/rotate_*`、`/cancel`

### 翻译内容

- 按钮标签（zh/en 变体）
- 引导文案
- 警告文案
- 状态标签
- 错误消息

### 警告文案

- 两种语言都必须清晰有力
- Raw JSON 脱敏消息应翻译，但 redaction 逻辑不变

---

## 6. Web i18n 设计

### 翻译字典/辅助

- 最小模板翻译辅助
- 中心字典/模块
- 安全回退
- 翻译标题、按钮、卡片、警告、辅助文案、Flash 消息

### 不翻译的内容

- Raw status JSON 中的键名
- `/api/status` schema
- 安全类别值（`healthy`、`verified`、`failed`、`unknown` 等保持英文）
- 可选：显示标签可本地化，但底层值保持稳定

---

## 7. 共享 vs 独立翻译层

| 方案 | 说明 | 推荐 |
|------|------|------|
| A. 独立 `bot_i18n.py` + `web_i18n.py` | 各自管理 | 可选 |
| B. 共享 `lib/nanobk_i18n.py` | 统一管理 | ✅ 如导入路径简单 |
| C. 内联常量 | 各自定义 | 简单但重复 |

**推荐：** 先从独立小字典开始，如导入路径简单可共享 `lib/nanobk_i18n.py`。避免大型框架、外部依赖。不将 i18n 与 redaction helper 混合。

---

## 8. 安全和 Redaction 要求

| 要求 | 说明 |
|------|------|
| i18n 不改变 redaction | ✅ |
| 翻译字符串不包含 raw IP/domain/token/workers.dev/subscription URL/private key | ✅ |
| 不通过直接注入 raw JSON 字段翻译 | ✅ |
| `/status_json` 仍门控 | ✅ |
| Raw JSON 值仍脱敏 | ✅ |
| Web `/api/status` schema 不变 | ✅ |
| Fingerprint 策略是独立未来任务 | ✅ |
| Doctor 输出产品化是独立未来任务 | ✅ |

---

## 9. Bot 文案清单（未来实现）

| 区域 | 当前用途 | 翻译优先级 | 建议 key 前缀 | 风险 |
|------|----------|-----------|---------------|------|
| Control Center 标题 | /start 欢迎 | 高 | `bot.start.title` | 低 |
| Control Center 副标题 | /start 说明 | 高 | `bot.start.subtitle` | 低 |
| 按钮标签 | InlineKeyboard | 高 | `bot.btn.*` | 低 |
| /help 各分区 | 帮助文本 | 高 | `bot.help.*` | 低 |
| /status 标签 | 状态摘要 | 高 | `bot.status.*` | 低 |
| 高级模式消息 | /advanced on/off/status | 高 | `bot.advanced.*` | 低 |
| status_json 门控消息 | 门控提示 | 高 | `bot.status_json.gate` | 低 |
| status_json 警告 | 输出警告 | 高 | `bot.status_json.warning` | 低 |
| 诊断引导 | 回调引导 | 中 | `bot.guidance.diagnostics` | 低 |
| 恢复引导 | 回调引导 | 中 | `bot.guidance.recovery` | 低 |
| Rotate 引导 | 回调引导 | 中 | `bot.guidance.rotate` | 低 |
| Web Panel 引导 | 回调引导 | 中 | `bot.guidance.web` | 低 |
| 未授权消息 | 安全拒绝 | 中 | `bot.unauthorized` | 低 |
| 错误消息 | 各种错误 | 中 | `bot.error.*` | 低 |

---

## 10. Web 文案清单（未来实现）

| 区域 | 当前用途 | 翻译优先级 | 建议 key 前缀 | 风险 |
|------|----------|-----------|---------------|------|
| 登录页 | token 登录 | 高 | `web.login.*` | 低 |
| Dashboard 标题 | 首页标题 | 高 | `web.dashboard.title` | 低 |
| 状态卡片 | 各段标签 | 高 | `web.status.*` | 低 |
| Raw JSON 锁定面板 | 门控提示 | 高 | `web.raw_json.locked` | 低 |
| Raw JSON 警告 | 输出警告 | 高 | `web.raw_json.warning` | 低 |
| 高级模式控件 | 启用/禁用 | 高 | `web.advanced.*` | 低 |
| Doctor 页面 | 诊断页 | 中 | `web.doctor.*` | 低 |
| Rotate 请求页 | 轮换选择 | 中 | `web.rotate.request` | 低 |
| Rotate 确认页 | 轮换确认 | 中 | `web.rotate.confirm` | 低 |
| Flash 消息 | 各种反馈 | 中 | `web.flash.*` | 低 |
| 状态标签 | 健康/失败等 | 中 | `web.labels.*` | 低 |
| 导航栏 | 顶部导航 | 低 | `web.nav.*` | 低 |

---

## 11. 实现路线

| 版本 | 内容 | 范围 |
|------|------|------|
| **v1.9.29** | Bot/Web i18n 规划 | ✅ 本文档 |
| **v1.9.30** | Bot i18n 最小实现 | Bot 文本常量/字典 + NANOBK_LANG + zh/en /start、/help、/status、advanced/status_json、回调引导 |
| **v1.9.31** | Web i18n 最小实现 | Web 翻译字典/辅助 + NANOBK_LANG + zh/en Dashboard/Status/Raw JSON 警告/高级控件 |
| **v1.9.32** | i18n 检查点 | Bot/Web 一致性、无泄露、回退行为、必要时真实冒烟重测 |

**不推荐一次实现 Bot + Web i18n。**

---

## 12. 测试策略

### Bot 测试

| 测试 | 说明 |
|------|------|
| 默认语言回退 | 缺失 NANOBK_LANG 时英文 |
| zh 语言文案 | 中文输出 |
| en 语言文案 | 英文输出 |
| 斜杠命令不变 | 命令名不受影响 |
| 按钮标签本地化 | zh/en 变体 |
| 状态类别保持 | healthy/failed/unknown 不翻译 |
| status_json 门控保持 | 门控行为不变 |
| 高级消息本地化 | zh/en 警告 |
| 翻译无 raw secret | 安全 |
| 现有 Bot 测试通过 | 回归 |

### Web 测试

| 测试 | 说明 |
|------|------|
| 默认语言回退 | 缺失 NANOBK_LANG 时英文 |
| zh/en 模板渲染 | 中英文页面 |
| 状态卡片本地化标签 | zh/en 标签 |
| Raw/API schema 不变 | 底层不变 |
| Raw JSON 门控保持 | 门控行为不变 |
| 高级控件本地化 | zh/en 控件 |
| 翻译无 raw secret | 安全 |
| 现有 Web 测试通过 | 回归 |

### 通用

- 无外部依赖
- 无 env cat
- 无真实 VPS/Cloudflare
- 无 release/tag

---

## 13. 与安装器的交互（规划）

- 安装器最终可能为 Bot/Web env 写入 `NANOBK_LANG=zh|en`
- 当前不实现
- 当前不修改 `installer/install.sh`
- 未来实现必须保留现有语言标志和 Summary 诚实性

---

## 14. 与未来任务的交互

| 任务 | 状态 | 说明 |
|------|------|------|
| Doctor 输出产品化 | 独立任务 | 未来规划 |
| Fingerprint redaction | 独立任务 | 未来规划 |
| Bot/Web systemd | 独立任务 | 未来规划 |
| Web 生产 runner | 独立任务 | 未来规划 |
| CLI 版本显示策略 | 独立任务 | 未来规划 |
| Raw subscription delivery | 阻塞 | 未批准 |

---

## 15. 就绪决策

**A. READY FOR BOT I18N MINIMAL IMPLEMENTATION AFTER CHATGPT REVIEW**

**范围限制：**

- ✅ Bot 优先
- ✅ 仅最小实现
- ❌ 无 Web 变更在 Bot 步骤中
- ❌ 无安装器变更（除非单独批准）
- ❌ 无 redaction 变更
- ❌ 无 release/tag

---

## 16. Guardrails

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
