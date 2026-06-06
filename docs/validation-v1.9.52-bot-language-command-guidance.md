# v1.9.52 — Bot Language Command / Guidance Minimal Implementation

> 验证类型：Bot 语言命令/引导最小实现
> 日期：2026-06-06
> 基线 commit：`54c6c8a2ed36394cc9243e1bb8cfaf0a7e3ec1e1`
> 基线信息：`feat: add web language switch`

---

## 1. 本轮目标与结论

**v1.9.52 添加了 Bot `/language` 状态/引导命令：**

- ✅ Bot `/language` 命令已添加
- ✅ Owner-only
- ✅ 仅引导/状态
- ✅ 不持久化语言切换
- ✅ 不写 env
- ✅ 不读 env
- ✅ 不改变 Web
- ✅ 不改变 CLI
- ✅ 不改变安装器
- ✅ 不 tag/release

**结论：Bot 添加了 `/language` 命令，显示当前运行时语言（来自 config.lang），解释语言来源（NANOBK_LANG/安装器），说明中文默认、英文可用，以及持久切换计划在未来 CLI/installer 安全命令中实现。`/help` 已更新包含 `/language`。**

---

## 2. Changed paths

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | 添加 `cmd_language` 处理器、`build_language_guidance()` 函数、10 个 i18n 键、更新 `build_help_text()`、注册 `CommandHandler("language")`、更新 self-test |
| `tests/bot-language-command-v1.9.52.py` | 新增聚焦测试（90 项） |
| `docs/validation-v1.9.52-bot-language-command-guidance.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.52 条目 |
| `docs/roadmap.md` | 新增 v1.9.52 版本行 |

---

## 3. Bot language command behavior

| 特性 | 说明 |
|------|------|
| 命令 | `/language` |
| 权限 | Owner-only |
| 功能 | 显示当前运行时语言和引导 |
| 当前语言来源 | `config.lang`（来自 `NANOBK_LANG` env） |
| 中文默认 | ✅ 新安装默认中文 |
| 英文可用 | ✅ 通过 `NANOBK_LANG=en` |
| 持久切换 | 计划在未来 CLI/installer 安全命令中实现 |
| 不运行 nanobk | ✅ |
| 不写 env | ✅ |
| 不读 env | ✅ |
| 不暴露 token | ✅ |
| 不暴露 env 路径 | ✅ |

### 引导内容

- 当前语言：中文/英文
- 语言来源：NANOBK_LANG 环境变量或安装器语言选项
- 中文默认：新安装默认中文
- 英文可用：安装前设置 NANOBK_LANG=en
- 持久切换：计划在未来 CLI/installer 安全命令中实现
- 不写配置文件

---

## 4. Help integration

| 特性 | 说明 |
|------|------|
| `/help` 包含 `/language | ✅ |
| 位置 | Basic 部分，`/cancel` 之后 |
| 英文描述 | "Show language info and guidance" |
| 中文描述 | "显示语言信息和引导" |
| 现有命令不变 | ✅ `/start`、`/status`、`/doctor`、`/cancel`、`/rotate_*`、`/advanced`、`/status_json` |

---

## 5. Safety boundaries

| 边界 | 状态 |
|------|------|
| 不读 env 文件 | ✅ |
| 不写 env 文件 | ✅ |
| 不打印密钥 | ✅ |
| 不打印 raw IP/domain/URL | ✅ |
| 不改变 redaction/gating/advanced/rotate | ✅ |
| 不改变 Web | ✅ |
| 不改变 CLI | ✅ |
| 不改变安装器 | ✅ |
| shell=True 无 | ✅ |
| os.system 无 | ✅ |

---

## 6. Compatibility and tradeoffs

| 权衡 | 说明 |
|------|------|
| Bot 语言引导 | 安全、诚实 |
| 不是真正的持久切换 | 仅显示当前语言和引导 |
| 持久切换 | 需要未来 CLI/installer 安全路径 |
| Web 已有 session 切换 | v1.9.51 |
| Bot 仍跟随安装/运行时语言 | 不支持运行时切换 |

---

## 7. Tests run

| 测试 | 结果 |
|------|------|
| `tests/bot-language-command-v1.9.52.py` | ✅ 90 passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 228 passed |
| `tests/bot-i18n-minimal-v1.9.30.py` | ✅ 116 passed |
| `tests/chinese-default-v1.9.48.py` | ✅ 75 passed |
| `tests/i18n-checkpoint-v1.9.32.py` | ✅ 167 passed |
| `tests/bot-control-center-menu-v1.9.24.py` | ✅ 47 passed |
| `tests/bot-control-center-callback-polish-v1.9.25.py` | ✅ 50 passed |
| `tests/bot-control-center-checkpoint-v1.9.26.py` | ✅ 66 passed |
| `tests/bot-doctor-summary-v1.9.36.py` | ✅ 163 passed |
| `tests/bot-status-json-soft-gate-v1.9.20.py` | ✅ 50 passed |
| `bash tests/bot-cli-mock.sh` | ✅ passed |
| `python3 web/app.py --self-test` | ✅ 118 passed |
| `bash tests/web-panel-mock.sh` | ✅ passed |

**注：** `tests/web-language-switch-v1.9.51.py` 有 5 个预先存在的源码级检查失败（52 passed, 5 failed），与本次 Bot 变更无关。该测试在变更前即有相同失败。

---

## 8. Known limitations

| 限制 | 说明 |
|------|------|
| 无持久 Bot 语言切换 | 仅引导，不切换 |
| 无 CLI 语言命令 | 长期任务 |
| 无真实中英文冒烟测试 | v1.9.53-54 任务 |
| CLI 版本显示仍待定 | 独立任务 |
| AI 维护接口仍待定 | v1.9.57-59 任务 |

---

## 9. Next step

**推荐：v1.9.53 — Chinese/English Control Plane Smoke Test Plan**

仅在 ChatGPT 审核后实施。
