# v1.9.48 — Bot/Web Chinese Default Minimal Implementation

> 验证类型：Bot/Web 中文默认最小实现
> 日期：2026-06-06
> 基线 commit：`7e61c6f3fe3232dc66f0f98adbda3d5ffdccc3df`
> 基线信息：`docs: add v1.9.47 language propagation planning`

---

## 1. 本轮目标与结论

**v1.9.48 实现了 Bot/Web 中文默认最小行为：**

- ✅ Bot/Web 缺失 `NANOBK_LANG` 时回退中文
- ✅ Bot/Web 无效 `NANOBK_LANG` 时回退中文
- ✅ `NANOBK_LANG=zh` 仍为中文
- ✅ `NANOBK_LANG=en` 仍为英文
- ✅ 无安装器变更
- ✅ 无语言切换 UX
- ✅ 无 CLI 变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

**结论：Bot/Web `DEFAULT_LANG` 从 `"en"` 改为 `"zh"`，缺失/空/无效语言回退中文。显式 `NANOBK_LANG=en` 仍强制英文。斜杠命令名、状态机器值、redaction/gating/rotate 行为均不变。**

---

## 2. Changed paths

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | `DEFAULT_LANG` 改为 `"zh"`，`BotConfig.lang` 默认改为 `"zh"` |
| `web/i18n.py` | `DEFAULT_LANG` 改为 `"zh"` |
| `web/app.py` | `WebConfig.lang` 默认改为 `"zh"`，self-test 断言更新 |
| `tests/bot-i18n-minimal-v1.9.30.py` | 更新默认语言断言为 `"zh"` |
| `tests/web-i18n-minimal-v1.9.31.py` | 更新默认语言断言为 `"zh"` |
| `tests/i18n-checkpoint-v1.9.32.py` | 更新默认语言和交叉一致性断言为 `"zh"` |
| `tests/chinese-default-v1.9.48.py` | 新增聚焦测试（75 项） |
| `docs/validation-v1.9.48-bot-web-chinese-default.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.48 条目 |
| `docs/roadmap.md` | 新增 v1.9.48 版本行 |

---

## 3. Bot behavior

| 特性 | 说明 |
|------|------|
| `DEFAULT_LANG` | `"zh"`（原 `"en"`） |
| 缺失值 | 返回 `"zh"` |
| 空值 | 返回 `"zh"` |
| 无效值 | 返回 `"zh"` |
| zh 别名 | `zh`、`zh-cn`、`zh_cn`、`chinese`、`中文` → `"zh"` |
| 显式 en | `NANOBK_LANG=en` → `"en"` |
| `BotConfig.lang` 默认 | `"zh"`（原 `"en"`） |
| 斜杠命令名 | 不变 |
| 状态机器值 | 不变（`healthy`/`failed`/`unknown`/`active` 等） |
| redaction | 不变 |
| /status_json 门控 | 不变 |
| 高级模式 | 不变 |
| rotate 行为 | 不变 |

---

## 4. Web behavior

| 特性 | 说明 |
|------|------|
| `DEFAULT_LANG` | `"zh"`（原 `"en"`） |
| 缺失值 | 返回 `"zh"` |
| 空值 | 返回 `"zh"` |
| 无效值 | 返回 `"zh"` |
| zh 别名 | `zh`、`zh-cn`、`zh_cn`、`chinese`、`中文` → `"zh"` |
| 显式 en | `NANOBK_LANG=en` → `"en"` |
| `WebConfig.lang` 默认 | `"zh"`（原 `"en"`） |
| 模板 | 继续使用 `{{ t() }}` |
| `/api/status` schema | 不变 |
| Raw JSON 键名 | 不变 |
| redaction | 不变 |
| Raw JSON 门控 | 不变 |
| 高级模式 | 不变 |
| rotate 行为 | 不变 |

---

## 5. Compatibility and tradeoffs

| 权衡 | 说明 |
|------|------|
| 现有无 `NANOBK_LANG` 安装 | 将从英文切换到中文 |
| 英文用户 | 需设置 `NANOBK_LANG=en` |
| 安装器传播 | 尚未实现（v1.9.49） |
| 语言切换 UX | 尚未实现（v1.9.50+） |
| 设计意图 | 最小步骤，为安装器传播和切换 UX 铺路 |

---

## 6. Safety boundaries

| 边界 | 状态 |
|------|------|
| 无 env 文件读取 | ✅ |
| 无 env 文件写入 | ✅ |
| 无 token 打印 | ✅ |
| 无 Raw JSON schema 翻译 | ✅ |
| 无 redaction 绕过 | ✅ |
| 无高级模式绕过 | ✅ |
| 无 rotate/部署变更 | ✅ |
| 无安装器变更 | ✅ |

---

## 7. Tests run

| 测试 | 结果 |
|------|------|
| `tests/bot-i18n-minimal-v1.9.30.py` | ✅ 116 passed |
| `tests/web-i18n-minimal-v1.9.31.py` | ✅ 123 passed |
| `tests/i18n-checkpoint-v1.9.32.py` | ✅ 167 passed |
| `tests/chinese-default-v1.9.48.py` | ✅ 75 passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 180 passed |
| `python3 web/app.py --self-test` | ✅ 106 passed |
| `tests/bot-doctor-summary-v1.9.36.py` | ✅ 163 passed |
| `tests/web-doctor-summary-v1.9.37.py` | ✅ 164 passed |
| `tests/doctor-output-checkpoint-v1.9.38.py` | ✅ 208 passed |
| `tests/bot-status-json-soft-gate-v1.9.20.py` | ✅ 50 passed |
| `tests/web-raw-json-soft-gate-v1.9.21.py` | ✅ 48 passed |
| `tests/raw-json-gating-checkpoint-v1.9.22.py` | ✅ 58 passed |
| `bash tests/bot-cli-mock.sh` | ✅ PASS |
| `bash tests/web-panel-mock.sh` | ✅ PASS |

**总计：1,524 项检查通过。**

---

## 8. Known limitations

| 限制 | 说明 |
|------|------|
| 安装器尚未写入 `NANOBK_LANG` | v1.9.49 任务 |
| 无 UI 语言切换 | v1.9.50+ 任务 |
| 无真实中文 Bot/Web 冒烟测试 | 尚未执行 |
| CLI 版本显示仍待定 | 独立任务 |
| AI 维护接口仍待定 | 独立任务 |

---

## 9. Next step

**推荐：v1.9.49 — Installer Bot/Web Language Propagation Minimal Implementation**

仅在 ChatGPT 审核后实施。
