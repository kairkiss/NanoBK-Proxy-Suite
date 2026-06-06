# v1.9.50 — Language Switch UX Planning

> 规划类型：Bot/Web 语言切换 UX 规划文档
> 日期：2026-06-06
> 基线 commit：`26845a3eca00c1a5ea8c42f7102f519443aa99b2`
> 基线信息：`fix: propagate bot web language setting`

---

## 1. 本轮目标与结论

**v1.9.50 是规划/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无安装器行为变更
- ✅ 无 env 文件读写
- ✅ 无 tag/release
- ✅ 目的是规划安全的中英文切换 UX

**结论：Web 采用 session 级语言切换（推荐方案 A），Bot 采用 `/language` 持久化命令（推荐方案 C 通过 CLI）。Web session 切换可在 v1.9.51 快速实现；Bot 持久化切换需要先实现 CLI 语言命令。**

---

## 2. 当前语言架构

| 组件 | 状态 |
|------|------|
| Bot i18n | ✅ zh/en 翻译字典，默认 zh |
| Web i18n | ✅ zh/en 翻译字典，默认 zh |
| 安装器传播 | ✅ 写入 `NANOBK_LANG=zh\|en` |
| Web 切换 UI | ❌ 不存在 |
| Bot 语言命令 | ❌ 不存在 |
| CLI 持久语言命令 | ❌ 不存在 |
| Bot 运行时语言 | `BotConfig.lang` 从 `NANOBK_LANG` env 读取，启动时固定 |
| Web 运行时语言 | `WebConfig.lang` 从 `NANOBK_LANG` env 读取，启动时固定 |
| Web session | Flask session 已用于 advanced mode 和 pending rotate |

---

## 3. 产品目标

| 目标 | 说明 |
|------|------|
| 中文默认 | 新安装默认中文（已实现） |
| 英文可选 | `NANOBK_LANG=en` 仍然有效（已实现） |
| Web 用户可在 UI 切换 | 不需要手动编辑 env |
| Bot 用户可切换语言 | 安全、简单 |
| 切换不暴露密钥 | Bot/Web 不直接写 env |
| 持久切换通过 CLI/installer | 安全路径 |
| Raw JSON schema 不变 | 底层值和键名保持英文 |
| 斜杠命令名不变 | `/start`、`/help` 等保持英文 |
| Redaction/gating/rotate 不变 | 安全行为不受影响 |

---

## 4. Web 语言切换方案对比

### 方案 A：Session 级切换（推荐）

- `POST /language` 路由
- 需要登录
- CSRF 保护
- 存储语言到 Flask session
- 不写 env 文件
- 立即生效
- 登出/session 过期后重置

**优点：** 简单、安全、不涉及文件写入、与现有 advanced mode 模式一致
**缺点：** 不持久，重启后需要重新切换

### 方案 B：Web 直接写 web/.env

- ❌ 拒绝：Web 不应直接写 env 文件

### 方案 C：Web 调用 CLI 语言命令

- 长期方案，但 CLI 命令尚不存在
- 可作为 v1.9.53+ 的持久化路径

### 方案 D：仅静态说明

- 安全但 UX 差

**推荐：方案 A 作为首次实现，session 级切换。**

---

## 5. Bot 语言切换方案对比

### 方案 A：`/language` 仅显示当前语言和引导

- 安全、简单
- 不切换，仅告知用户如何手动切换

### 方案 B：`/language zh|en` 内存级切换

- 进程重启后重置
- 可能造成混淆（Bot 重启后回到默认语言）

### 方案 C：`/language zh|en` 调用 CLI 语言命令（推荐长期方案）

- 最佳长期方案
- 但 CLI 命令尚不存在

### 方案 D：Bot 直接编辑 bot/.env

- ❌ 拒绝：Bot 不应直接写 env 文件

**推荐分阶段：**
- v1.9.52：`/language` 命令显示当前语言 + 安全引导（方案 A）
- 持久化 Bot 切换等待 CLI/installer 安全语言命令实现后再做

---

## 6. 持久语言策略

### 长期设计

持久语言应通过 CLI/installer 安全路径更改：

```
nanobk language set zh
nanobk language set en
nanobk language status
```

### CLI 语言命令设计要点

- 安全更新 Bot/Web env 文件
- 保留 chmod 600
- 不打印密钥内容
- 支持 `--dry-run` 预览
- 与安装器语言传播一致

### Bot/Web 调用 CLI

- Bot/Web 可在后续版本调用此 CLI
- 仅在策略/测试批准后
- v1.9.50 不实现

---

## 7. Web 首次实现合同（v1.9.51）

### 架构设计

```
┌─────────────────────────────────────┐
│  Web Session Language Override       │
│                                     │
│  session["lang"] = "zh" | "en"     │
│                                     │
│  优先级：                            │
│  1. session["lang"] (用户选择)       │
│  2. config.lang (env 设置)           │
│  3. DEFAULT_LANG (zh)               │
└─────────────────────────────────────┘
```

### 实现要点

- 添加 `get_current_lang(session, config)` 辅助函数
- 优先级：session 语言 > config.lang > 默认 zh
- 添加 `POST /language` 路由
  - 需要登录
  - 需要 CSRF
  - 接受 `lang=zh` 或 `lang=en`
  - 无效输入拒绝或安全回退
- 修改 `inject_i18n()` context processor 使用 `get_current_lang()`
- 添加语言切换按钮/链接到 layout.html 导航栏
- 不改变 `/api/status`
- 不翻译 Raw JSON 键名
- 不写 env
- 不暴露 token

### 模板设计

在 layout.html 导航栏添加语言切换：

```html
<nav>
  <a href="/">{{ t('nav_dashboard') }}</a>
  <a href="/status">{{ t('nav_status') }}</a>
  ...
  <form method="POST" action="/language" style="display:inline">
    <input type="hidden" name="csrf_token" value="{{ csrf_token }}">
    <input type="hidden" name="lang" value="{{ 'en' if lang == 'zh' else 'zh' }}">
    <button type="submit" class="nav-button">
      {{ 'EN' if lang == 'zh' else '中文' }}
    </button>
  </form>
  <form method="POST" action="/logout" style="display:inline">
    ...
  </form>
</nav>
```

### 安全约束

| 约束 | 说明 |
|------|------|
| 登录要求 | ✅ |
| CSRF 保护 | ✅ |
| 仅接受 zh/en | ✅ |
| 不写 env | ✅ |
| 不暴露 token | ✅ |
| 不改变 /api/status | ✅ |
| 不翻译 Raw JSON 键 | ✅ |
| session 过期重置 | ✅ |

---

## 8. Bot 首次实现合同（v1.9.52）

### 方案 A 实现要点（推荐首次）

- 添加 `/language` 命令
- Owner-only
- 显示当前运行时语言
- 解释如何切换（引导到 Web 或未来 CLI）
- 可选：添加控制中心按钮 `🌐 语言 / Language`
- 不写 bot/.env
- 不暴露 env 路径或内容
- 不改变斜杠命令名
- 不影响 redaction/gate

### 控制中心集成

在 `_build_main_menu_keyboard()` 中添加语言按钮：

```python
InlineKeyboardButton(bt(lang, "btn_language"), callback_data=CALLBACK_LANGUAGE)
```

回调显示当前语言和切换说明。

### 安全约束

| 约束 | 说明 |
|------|------|
| Owner-only | ✅ |
| 不写 env | ✅ |
| 不暴露 env 内容 | ✅ |
| 命令名不变 | ✅ |
| Redaction/gate 不变 | ✅ |

---

## 9. 测试策略

### Web 切换测试（v1.9.51）

| 测试 | 说明 |
|------|------|
| 登录要求 | 未登录不能切换 |
| CSRF 要求 | 无 CSRF token 拒绝 |
| session 语言变更 | POST /language 后 session 存储正确语言 |
| 登出重置 | 登出后 session 语言清除 |
| config.lang 回退 | session 无语言时使用 config.lang |
| 无效语言拒绝 | lang=fr 等无效值安全处理 |
| /api/status 不变 | API schema 不变 |
| Raw JSON 键不变 | 底层不变 |
| 不写 env | 无文件写入 |
| 不打印密钥 | 无 token 输出 |

### Bot 引导/切换测试（v1.9.52）

| 测试 | 说明 |
|------|------|
| Owner-only | 非 owner 被拒绝 |
| /language 命令注册 | CommandHandler 存在 |
| 显示当前语言 | 输出包含当前语言 |
| 引导文本 zh/en | 引导文本正确 |
| 不写 env | 无文件写入 |
| 不暴露 env 内容 | 无路径/token 输出 |
| 命令名不变 | 斜杠命令稳定 |

### 回归测试

| 测试 | 说明 |
|------|------|
| Bot/Web i18n 测试 | v1.9.30/v1.9.31 测试通过 |
| 中文默认测试 | v1.9.48 测试通过 |
| 安装器传播测试 | v1.9.49 测试通过 |
| Raw JSON gate 测试 | gating 行为不变 |
| Doctor summary 测试 | 摘要行为不变 |
| Self-test | Bot/Web self-test 通过 |

### 真实冒烟测试

| 测试 | 说明 |
|------|------|
| Web 中文默认可见 | 新安装显示中文 |
| Web 切换到英文 | 点击切换按钮后显示英文 |
| Web 切换回中文 | 再次切换后显示中文 |
| Bot 语言引导 | /language 显示正确信息 |
| 无泄漏 | 无 token/密钥/URL 泄漏 |

---

## 10. 稳定 tag 语言门控

### v1.9 稳定 tag 前置条件（语言相关）

| 条件 | 说明 |
|------|------|
| 中文默认已实现 | ✅ v1.9.48 |
| 安装器传播已实现 | ✅ v1.9.49 |
| Web session 语言切换已实现并测试 | v1.9.51 |
| Bot 语言引导或切换已实现并测试 | v1.9.52 |
| 真实中英文冒烟测试已记录 | v1.9.53-54 |
| CLI 版本显示已解决或记录 | v1.9.56 |
| AI 维护接口已添加或规划 | v1.9.57-59 |

---

## 11. AI 维护接口交互

### 语言切换应在维护地图中记录

未来无记忆 AI 应知道：

- i18n 字典位于 Bot/Web 文件中
- Raw JSON 键名不得翻译
- 斜杠命令名不得翻译
- Bot/Web 不得直接写 env
- 持久语言更改必须通过 CLI/installer 安全路径
- Web session 语言存储在 Flask session 中
- Bot 语言从 env 读取，启动时固定

### v1.9.50 不实现

维护接口在 v1.9.57-59 规划和实现。

---

## 12. 建议实施路线

| 版本 | 内容 | 范围 |
|------|------|------|
| **v1.9.50** | 语言切换 UX 规划 | ✅ 本文档 |
| **v1.9.51** | Web session 语言切换最小实现 | `POST /language`、session 存储、layout 按钮 |
| **v1.9.52** | Bot 语言命令/引导最小实现 | `/language` 命令、控制中心按钮 |
| **v1.9.53** | 中英文控制面冒烟测试计划 | 定义真实中英文冒烟测试清单 |
| **v1.9.54** | 真实中英文控制面冒烟测试验证 | 记录用户执行的真实冒烟测试 |
| **v1.9.55** | v1.9 稳定收口范围决策 | 确定稳定 tag 前置条件 |
| **v1.9.56** | CLI 版本显示打磨 | 独立任务 |
| **v1.9.57** | AI 维护接口规划 | 设计维护地图和交接模板 |
| **v1.9.58** | 维护锚点/接口注释最小实现 | 代码注释和稳定接口 |
| **v1.9.59** | 维护地图和 AI 交接文档 | 文档完成 |
| **v1.9.60+** | 稳定 tag 准备和最终 tag | 收口和发布 |

---

## 13. 就绪决策

**A. READY FOR WEB SESSION LANGUAGE SWITCH MINIMAL IMPLEMENTATION AFTER CHATGPT REVIEW**

**范围限制：**

- ✅ Web 仅 session 级
- ✅ 登录 + CSRF
- ✅ 不写 env
- ✅ 不改变 Bot
- ✅ 不改变 CLI
- ✅ 不改变安装器
- ✅ 不 tag/release

---

## 14. 未变更内容

| 组件 | 状态 |
|------|------|
| Bot 运行时 | 未变更 |
| Web 运行时 | 未变更 |
| CLI | 未变更 |
| 安装器 | 未变更 |
| env 文件 | 未变更 |
| redaction | 未变更 |
| Raw JSON gating | 未变更 |
| 高级模式 | 未变更 |
| rotate | 未变更 |
| 部署逻辑 | 未变更 |
| 无测试新增 | ✅ |
| 无功能实现 | ✅ |
| 无 tag/release | ✅ |

---

## 15. 已知限制

| 限制 | 说明 |
|------|------|
| 仅规划 | 未实现任何变更 |
| 无 Web 语言切换 | v1.9.51 任务 |
| 无 Bot 语言命令 | v1.9.52 任务 |
| 无持久 CLI 语言命令 | 长期任务 |
| 无真实中英文冒烟测试 | v1.9.53-54 任务 |
| CLI 版本显示仍待定 | 独立任务 |
| AI 维护接口仍待定 | v1.9.57-59 任务 |

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
| 7 | 禁止直接 Bot/Web 写入 env | 安全 |
| 8 | 禁止 raw env 读取 | 安全 |
| 9 | 禁止 production status wrapper | 未批准 |
| 10 | 禁止 dirty VPS status wrapping | 未批准 |
| 11 | 禁止 operation-log full rollout | 未批准 |
| 12 | 禁止 raw subscription delivery | 未批准 |
| 13 | 禁止 tag/release | 未批准 |
