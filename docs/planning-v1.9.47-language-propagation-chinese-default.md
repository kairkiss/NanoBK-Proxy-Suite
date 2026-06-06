# v1.9.47 — Bot/Web Language Propagation and Chinese Default Planning

> 规划类型：Bot/Web 语言传播和中文默认规划文档
> 日期：2026-06-06
> 基线 commit：`f3e3849c5f6a342f6c305868cd4c8cf7c82704a2`
> 基线信息：`docs: add v1.9.46 real doctor field validation`

---

## 1. 本轮目标与结论

**v1.9.47 是规划/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无安装器行为变更
- ✅ 无部署逻辑变更
- ✅ 无 env 文件读取
- ✅ 无 tag/release
- ✅ 目的是规划中文默认、语言传播和中英文切换，以在稳定 tag 前完成中文支持

**结论：Bot/Web i18n 基础已存在（v1.9.30/v1.9.31），但运行时默认仍为英文，安装器语言选择未传播到 Bot/Web env，且无用户面向语言切换 UX。本规划定义分阶段路线，在稳定 tag 前完成中文默认和切换能力。**

---

## 2. 为什么需要补齐中文

| 理由 | 说明 |
|------|------|
| 真实 T14/T15/T16 测试确认 UI 仍主要英文 | T16-P2-005: UI 默认仍主要英文 |
| Bot/Web i18n 基础已存在 | v1.9.30 Bot、v1.9.31 Web 已实现 zh/en 翻译字典 |
| 但默认回退为英文 | `DEFAULT_LANG = "en"`，缺失 `NANOBK_LANG` 时回退英文 |
| 安装器语言选择未传播 | `select_language()` 默认中文，但未写入 bot/.env/web/.env |
| 目标新手用户偏好中文 | 中文初学者友好是产品核心方向 |
| 英文必须保留 | 国际用户和高级用户需要英文 |
| 斜杠命令名必须保持英文 | `/start`、`/help`、`/status` 等不变 |
| Raw JSON schema 不得翻译 | 底层值和键名保持英文 |

---

## 3. 当前 i18n 架构审计

### Bot（v1.9.30）

| 特性 | 当前状态 |
|------|----------|
| 语言源 | `NANOBK_LANG=zh|en` 环境变量 |
| 默认回退 | `en`（缺失/无效时） |
| 中文别名 | `zh`、`zh-cn`、`zh_cn`、`chinese`、`中文` |
| 翻译字典 | `BOT_TEXT`（80+ 条目，zh/en 双语） |
| 翻译辅助 | `bt(lang, key, **kwargs)` 安全回退英文 |
| Builder 函数 | `build_control_center_text()`、`build_help_text()`、`build_guidance_*()` |
| 斜杠命令 | 不变 |
| 状态类别值 | 稳定（`healthy`/`failed`/`unknown`/`active` 等不翻译） |
| /status_json 门控 | 不变 |
| 高级模式 | 不变（15 分钟 TTL） |
| 回调 | 不变（owner-only，nanobk: 前缀） |
| Redaction | 不变 |

### Web（v1.9.31）

| 特性 | 当前状态 |
|------|----------|
| 语言源 | `NANOBK_LANG=zh|en` 环境变量 |
| 默认回退 | `en`（缺失/无效时） |
| 翻译模块 | `web/i18n.py` |
| 翻译字典 | `WEB_TEXT`（80+ 条目，zh/en 双语） |
| 翻译辅助 | `wt(lang, key, **kwargs)` 安全回退英文 |
| 模板注入 | Flask context processor 注入 `t()` 和 `lang` |
| 模板调用 | `{{ t('key') }}` |
| /api/status | 不变（schema 不变，未门控，返回 redacted JSON） |
| Redaction | 不变 |

### 当前差距

| 差距 | 说明 |
|------|------|
| 默认语言为英文 | `DEFAULT_LANG = "en"`，缺失 `NANOBK_LANG` 时回退英文 |
| 安装器未传播语言 | `select_language()` 选择中文，但 bot/.env/web/.env 不含 `NANOBK_LANG` |
| 无用户面向语言切换 | Bot 无 `/language` 命令，Web 无语言切换 UI |
| 无持久语言设置 | 语言仅从 env 读取，无持久化机制 |
| 无真实中文冒烟测试 | i18n 后未执行真实中文 Bot/Web 冒烟测试 |

---

## 4. 语言产品目标

| 目标 | 说明 |
|------|------|
| 中文默认 | 新安装默认中文 |
| 英文保留 | `NANOBK_LANG=en` 时英文 |
| Bot/Web 语义一致 | 同一语言设置下 Bot/Web 行为一致 |
| 安装器传播 | 安装器语言选择传播到 Bot/Web env |
| 现有安装可切换 | 已安装用户可安全切换语言 |
| 语言切换不暴露密钥 | 切换过程不读取/打印 env 内容 |
| 命令名稳定 | 斜杠命令保持英文 |
| Raw JSON 不翻译 | 底层值和键名保持英文 |
| 状态类别值稳定 | `healthy`/`failed`/`unknown` 等保持英文 |
| Redaction/gating 不变 | 语言切换不影响安全行为 |

---

## 5. 默认语言决策

### 选项对比

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| A. 保持默认英文 | 缺失 `NANOBK_LANG` 时英文 | 向后兼容 | 不符合产品方向 |
| B. Bot/Web 缺失时默认中文 | `DEFAULT_LANG` 改为 `zh` | 简单 | 现有英文用户可能受影响 |
| C. 跟随安装器语言；缺失时默认中文 | 安装器传播 + 缺失回退中文 | 最佳产品体验 | 需要安装器变更 |

### 推荐方案

**C. 跟随安装器语言；缺失时默认中文**

分阶段实施：

1. **短期（v1.9.48）**：Bot/Web 缺失 `NANOBK_LANG` 时回退 `zh`（而非 `en`）
2. **中期（v1.9.49）**：安装器显式写入 `NANOBK_LANG` 到 bot/.env/web/.env
3. **长期**：持久语言切换通过 CLI/installer 安全路径

### 权衡

| 权衡 | 说明 |
|------|------|
| 向后兼容 | 现有安装无 `NANOBK_LANG`，将从英文切换到中文 |
| 英文用户 | 需要手动设置 `NANOBK_LANG=en` 或使用语言切换 |
| 安全性 | 语言切换不涉及密钥读写 |
| 测试覆盖 | 需要验证缺失/zh/en/无效四种情况 |

---

## 6. 安装器传播计划

### 当前状态

安装器 `select_language()` 已支持 `--lang zh|en` 和交互选择，默认中文。但：

- bot/.env 写入内容：`TELEGRAM_BOT_TOKEN`、`OWNER_TELEGRAM_ID`、`NANOBK_CLI`、`NANOBK_REPO_DIR`、`NANOBK_BOT_DRY_RUN`、`NANOBK_COMMAND_TIMEOUT`、`NANOBK_ROTATE_TIMEOUT`
- web/.env 写入内容：`NANOBK_WEB_TOKEN`、`NANOBK_WEB_SECRET_KEY`、`NANOBK_WEB_HOST`、`NANOBK_WEB_PORT`、`NANOBK_CLI`、`NANOBK_REPO_DIR`、`NANOBK_WEB_DRY_RUN`、`NANOBK_COMMAND_TIMEOUT`、`NANOBK_ROTATE_TIMEOUT`
- **两者都不含 `NANOBK_LANG`**

### 计划

安装器最终应：

1. `nanobk install --mode bot --lang zh` → 写入 `NANOBK_LANG=zh` 到 bot/.env
2. `nanobk install --mode web --lang zh` → 写入 `NANOBK_LANG=zh` 到 web/.env
3. 同理 `--lang en`
4. Full Wizard 语言选择应传播到 Bot/Web 阶段
5. 现有 env 权限 `chmod 600` 必须保留
6. 安装输出不得打印 env 内容
7. Bot/Web 不得直接写入 env

### 安全约束

| 约束 | 说明 |
|------|------|
| env 权限 600 | 保留 |
| 不打印 env 内容 | 安装输出不展示 |
| Bot/Web 不写 env | 仅 CLI/installer 安全路径 |
| 现有安装恢复不破坏 | resume 流程兼容 |

**不在 v1.9.47 实现。**

---

## 7. 用户面向语言切换策略

### 选项对比

| 方案 | 说明 | 优点 | 缺点 |
|------|------|------|------|
| A. Web session 级切换，无持久化 | Web UI 下拉切换，仅 session 有效 | 即时生效 | 不持久，Bot 不受影响 |
| Bot 命令 `/language zh\|en`，session/memory 级 | Bot 命令切换，内存级 | Bot 可切换 | 不持久，重启丢失 |
| C. CLI 持久设置，Bot/Web 调用 CLI 或引导用户 | CLI `nanobk language set zh` | 持久 | 需要 CLI 变更 |
| D. 混合：Web session + CLI 持久 + Bot 引导 | 分阶段混合 | 最佳体验 | 复杂度高 |

### 推荐：分阶段混合

| 版本 | 内容 | 范围 |
|------|------|------|
| **v1.9.48** | Bot/Web 中文默认最小实现 | `DEFAULT_LANG` 改为 `zh` |
| **v1.9.49** | 安装器 Bot/Web 语言传播最小实现 | 安装器写入 `NANOBK_LANG` |
| **v1.9.50** | 语言切换 UX 规划 | 设计切换方案 |
| **v1.9.51** | Web 语言切换最小实现 | Web session 级下拉切换 |
| **v1.9.52** | Bot 语言切换最小实现或安全引导 | Bot `/language` 或引导 CLI |
| **v1.9.53+** | 持久切换仅通过 CLI/installer 安全路径 | 长期方案 |

### 设计原则

- Web session 切换用于即时 UI 体验
- CLI 持久设置用于长期默认
- Bot 命令初期引导或安全调用 CLI
- 语言切换不得暴露或读取 env 内容
- 语言切换不得影响 redaction/gating/rotate 行为

---

## 8. 安全边界

语言工作不得：

| 边界 | 说明 |
|------|------|
| 改变 Raw JSON schema | ✅ 禁止 |
| 翻译 JSON 键名 | ✅ 禁止 |
| 绕过 redaction | ✅ 禁止 |
| 绕过 Raw JSON 门控 | ✅ 禁止 |
| 绕过高级模式 | ✅ 禁止 |
| 暴露 env 内容 | ✅ 禁止 |
| 打印 token | ✅ 禁止 |
| 直接从 Bot/Web 写入 configs/systemd/secrets | ✅ 禁止 |
| 改变 rotate 行为 | ✅ 禁止 |
| 改变部署逻辑 | ✅ 禁止 |

---

## 9. 测试策略

### 默认中文测试

| 测试 | 说明 |
|------|------|
| 缺失 `NANOBK_LANG` → zh | 新默认 |
| `NANOBK_LANG=zh` → zh | 显式中文 |
| `NANOBK_LANG=en` → en | 显式英文 |
| 无效值 → 安全回退 | 回退 zh（而非 en） |

### Bot 测试

| 测试 | 说明 |
|------|------|
| `/start` 中文 | 控制中心中文 |
| `/help` 中文 | 帮助文本中文 |
| `/status` 标签中文 | 状态摘要标签中文 |
| `/doctor` 标签中文 | 诊断摘要标签中文 |
| `/status_json` 警告/门控中文 | 门控消息中文 |
| 命令名不变 | `/start`、`/help` 等不变 |
| 翻译无 raw secret | 安全 |

### Web 测试

| 测试 | 说明 |
|------|------|
| Dashboard 中文 | 控制台中文 |
| Status 中文 | 状态页面中文 |
| Doctor 中文 | 诊断页面中文 |
| Raw JSON 警告中文 | 高级诊断警告中文 |
| 高级模式中文 | 启用/禁用控件中文 |
| Login/nav/rotate 标签中文 | 各页面中文 |
| `/api/status` 不变 | API schema 不变 |
| raw JSON 键名不变 | 底层不变 |

### 安装器传播测试

| 测试 | 说明 |
|------|------|
| 生成 env 含 `NANOBK_LANG` | 安全写入 |
| chmod 600 保留 | 权限不变 |
| 不打印 env 内容 | 安全 |
| 现有安装恢复不破坏 | resume 兼容 |

### 真实冒烟测试

| 测试 | 说明 |
|------|------|
| 中文默认可见 | Bot/Web 启动即中文 |
| 英文切换有效 | `NANOBK_LANG=en` 时英文 |
| 无 redaction/gate 回归 | 安全行为不变 |

---

## 10. 稳定 tag 门控

### v1.9 稳定 tag 前置条件（语言相关）

| 条件 | 说明 |
|------|------|
| 中文默认已实现 | Bot/Web 缺失 `NANOBK_LANG` 时中文 |
| 英文模式仍有效 | `NANOBK_LANG=en` 时英文 |
| 安装器语言传播已实现 | 安装器写入 `NANOBK_LANG` |
| 至少一次真实中文 Bot/Web 冒烟测试已记录 | 真实环境验证 |
| CLI 版本显示策略已解决或记录 | 独立任务 |
| 不在 UI 仍主要英文时 tag | 必须中文默认可见 |

---

## 11. AI 维护接口（后续）

### 计划（不实现）

在最终稳定 tag 前，添加：

- `docs/maintenance-map.md` — 维护区域地图
- `docs/ai-handoff-template.md` — AI 交接模板
- 代码维护合同注释（Bot/Web/redaction/doctor/status/i18n 区域）
- 清晰的"允许变更 / 受保护区域"地图
- 稳定接口供未来无记忆 AI 安全执行定向修复

### 目的

未来 AI 维护者（无项目记忆）应能：

1. 读取 `docs/maintenance-map.md` 了解项目结构
2. 读取 `docs/ai-handoff-template.md` 了解安全规则
3. 通过代码注释了解哪些区域可安全修改
4. 通过稳定接口执行定向修复而不破坏安全边界

**在语言工作之后、最终 tag 之前实施。**

---

## 12. 建议实施路线

| 版本 | 内容 | 范围 |
|------|------|------|
| **v1.9.47** | 语言传播和中文默认规划 | ✅ 本文档 |
| **v1.9.48** | Bot/Web 中文默认最小实现 | `DEFAULT_LANG` 改为 `zh`，Bot/Web 缺失 `NANOBK_LANG` 时回退中文 |
| **v1.9.49** | 安装器 Bot/Web 语言传播最小实现 | 安装器写入 `NANOBK_LANG` 到 bot/.env/web/.env |
| **v1.9.50** | 语言切换 UX 规划 | 设计 Web session 切换 + Bot 引导方案 |
| **v1.9.51** | Web 语言切换最小实现 | Web session 级下拉切换 |
| **v1.9.52** | Bot 语言切换最小实现或安全引导 | Bot `/language` 命令或引导 CLI |
| **v1.9.53** | 中文控制面冒烟测试计划 | 定义真实中文冒烟测试清单 |
| **v1.9.54** | 真实中文控制面冒烟测试验证 | 记录用户执行的真实中文冒烟测试 |
| **v1.9.55** | v1.9 稳定收口范围决策 | 确定稳定 tag 前置条件 |
| **v1.9.56** | CLI 版本显示打磨规划/修复 | 独立任务 |
| **v1.9.57** | AI 维护接口规划 | 设计维护地图和交接模板 |
| **v1.9.58** | 维护锚点 / 接口注释最小实现 | 代码注释和稳定接口 |
| **v1.9.59** | 维护地图和 AI 交接文档 | 文档完成 |
| **v1.9.60+** | 稳定 tag 准备和最终 tag | 收口和发布 |

---

## 13. 就绪决策

**A. READY FOR BOT/WEB CHINESE DEFAULT MINIMAL IMPLEMENTATION AFTER CHATGPT REVIEW**

**范围限制：**

- ✅ 仅最小实现
- ✅ `DEFAULT_LANG` 改为 `zh`
- ✅ Bot/Web 缺失 `NANOBK_LANG` 时回退中文
- ❌ 无安装器变更（单独步骤）
- ❌ 无语言切换实现（单独步骤）
- ❌ 无 tag/release

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
| Raw JSON 门控 | 未变更 |
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
| 当前默认语言仍英文 | 未改变 |
| 安装器传播仍待定 | 未实现 |
| 语言切换仍待定 | 未实现 |
| 真实中文冒烟测试仍待定 | 未执行 |
| AI 维护接口仍待定 | 未实现 |
| CLI 版本显示仍待定 | 独立任务 |

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
