# v1.9.49 — Installer Bot/Web Language Propagation Minimal Implementation

> 验证类型：安装器 Bot/Web 语言传播最小实现
> 日期：2026-06-06
> 基线 commit：`b43117b63d40675e7b83e57082581abcb8351e70`
> 基线信息：`feat: make bot web default Chinese`

---

## 1. 本轮目标与结论

**v1.9.49 实现了安装器 Bot/Web 语言传播最小行为：**

- ✅ Bot 安装写入 `NANOBK_LANG=zh|en`
- ✅ Web 安装写入 `NANOBK_LANG=zh|en`
- ✅ 缺失/无效语言回退 zh
- ✅ 无 Bot/Web 运行时变更
- ✅ 无语言切换 UX
- ✅ 无 CLI 持久语言命令
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

**结论：安装器 Bot/Web env 生成现在包含 `NANOBK_LANG=${LANG_CODE:-zh}`。`--lang zh` 写入 zh，`--lang en` 写入 en，缺失/默认写入 zh。Bot/Web 运行时通过现有 `BotConfig.from_env` / `WebConfig.from_env` 读取。**

---

## 2. Changed paths

| 文件 | 变更 |
|------|------|
| `installer/install.sh` | Bot env heredoc 新增 `NANOBK_LANG=${LANG_CODE:-zh}`，Web env heredoc 新增 `NANOBK_LANG=${LANG_CODE:-zh}` |
| `tests/installer-language-propagation-v1.9.49.sh` | 新增聚焦测试（22 项） |
| `docs/validation-v1.9.49-installer-language-propagation.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.49 条目 |
| `docs/roadmap.md` | 新增 v1.9.49 版本行 |

---

## 3. Installer language behavior

| 特性 | 说明 |
|------|------|
| `--lang zh` | `LANG_CODE=zh`，写入 `NANOBK_LANG=zh` |
| `--lang en` | `LANG_CODE=en`，写入 `NANOBK_LANG=en` |
| `--defaults` | `LANG_CODE` 默认 `zh` |
| 交互选择 1) | `LANG_CODE=zh`（默认） |
| 交互选择 2) | `LANG_CODE=en` |
| 缺失 `--lang` 且无交互 | `LANG_CODE:-zh` 回退 `zh` |
| zh 别名 | `zh`、`zh-cn`、`zh_cn`、`chinese`、`中文` 由 Bot/Web 运行时 normalize_lang 处理 |
| en 别名 | `en` 由 Bot/Web 运行时 normalize_lang 处理 |
| 无效值 | `${LANG_CODE:-zh}` 回退 `zh` |

### Full Wizard 传播

Full Wizard 的 `select_language()` 设置 `LANG_CODE` 全局变量。Bot/Web env 生成使用 `${LANG_CODE:-zh}`，因此 Full Wizard 选择的语言会自动传播到 Bot/Web env。无需额外 Full Wizard 重构。

---

## 4. Bot env propagation

| 特性 | 说明 |
|------|------|
| 新增行 | `NANOBK_LANG=${LANG_CODE:-zh}` |
| 位置 | Bot env heredoc 末尾 |
| chmod 600 | 保留 |
| env 内容不打印 | ✅ |
| 密钥不打印 | ✅ |
| Bot 运行时读取 | `BotConfig.from_env()` 通过 `os.environ.get("NANOBK_LANG")` 读取 |

Bot env 写入内容（完整）：

```
TELEGRAM_BOT_TOKEN=...
OWNER_TELEGRAM_ID=...
NANOBK_CLI=...
NANOBK_REPO_DIR=...
NANOBK_BOT_DRY_RUN=...
NANOBK_COMMAND_TIMEOUT=120
NANOBK_ROTATE_TIMEOUT=300
NANOBK_LANG=zh|en
```

---

## 5. Web env propagation

| 特性 | 说明 |
|------|------|
| 新增行 | `NANOBK_LANG=${LANG_CODE:-zh}` |
| 位置 | Web env heredoc 末尾 |
| chmod 600 | 保留 |
| env 内容不打印 | ✅ |
| 密钥不打印 | ✅ |
| Web 运行时读取 | `WebConfig.from_env()` 通过 `os.environ.get("NANOBK_LANG")` 读取 |

Web env 写入内容（完整）：

```
NANOBK_WEB_TOKEN=...
NANOBK_WEB_SECRET_KEY=...
NANOBK_WEB_HOST=...
NANOBK_WEB_PORT=...
NANOBK_CLI=...
NANOBK_REPO_DIR=...
NANOBK_WEB_DRY_RUN=...
NANOBK_COMMAND_TIMEOUT=120
NANOBK_ROTATE_TIMEOUT=300
NANOBK_LANG=zh|en
```

---

## 6. Safety boundaries

| 边界 | 状态 |
|------|------|
| 无 env 文件读取 | ✅ |
| 无 env 内容打印 | ✅ |
| 无 token 打印 | ✅ |
| 无 raw IP/domain/URL 打印 | ✅ |
| 无 redaction/gating 变更 | ✅ |
| 无高级模式变更 | ✅ |
| 无 rotate 变更 | ✅ |
| 无部署核心变更 | ✅ |
| chmod 600 保留 | ✅ |
| VPS 部署逻辑不变 | ✅ |
| Cloudflare 逻辑不变 | ✅ |
| rotate 逻辑不变 | ✅ |

---

## 7. Compatibility and tradeoffs

| 权衡 | 说明 |
|------|------|
| 新 Bot/Web 安装 | 有显式 `NANOBK_LANG` |
| 现有无重装 | 仍使用 v1.9.48 默认 zh |
| 英文用户 | `--lang en` 或手动设置 `NANOBK_LANG=en` |
| UI 切换 | 尚未实现（v1.9.50+） |
| 持久语言命令 | 尚未实现 |
| Full Wizard | 自动传播（无需重构） |

---

## 8. Tests run

| 测试 | 结果 |
|------|------|
| `tests/installer-language-propagation-v1.9.49.sh` | ✅ 22 passed |
| `bash tests/bot-cli-mock.sh` | ✅ PASS |
| `bash tests/web-panel-mock.sh` | ✅ PASS |
| `python3 tests/chinese-default-v1.9.48.py` | ✅ 75 passed |
| `python3 tests/bot-i18n-minimal-v1.9.30.py` | ✅ 116 passed |
| `python3 tests/web-i18n-minimal-v1.9.31.py` | ✅ 123 passed |
| `python3 tests/i18n-checkpoint-v1.9.32.py` | ✅ 167 passed |

---

## 9. Known limitations

| 限制 | 说明 |
|------|------|
| 无 UI 切换 | v1.9.50+ 任务 |
| 无 Bot /language | v1.9.52 任务 |
| 无 Web 语言下拉 | v1.9.51 任务 |
| 无真实中文冒烟测试 | v1.9.53-54 任务 |
| CLI 版本显示仍待定 | 独立任务 |
| AI 维护接口仍待定 | 独立任务 |

---

## 10. Next step

**推荐：v1.9.50 — Language Switch UX Planning**

仅在 ChatGPT 审核后实施。
