# v1.9.51 — Web Session Language Switch Minimal Implementation

> 验证类型：Web Session 语言切换最小实现
> 日期：2026-06-06
> 基线 commit：`3b0a7b73c27f06bde673464bc8a341c2e1ca0d1e`
> 基线信息：`docs: add v1.9.50 language switch planning`

---

## 1. 本轮目标与结论

**v1.9.51 实现了 Web session 级语言切换：**

- ✅ Web 用户可在 UI 切换 zh/en
- ✅ 切换仅 session 级
- ✅ 登录要求
- ✅ CSRF 保护
- ✅ 不写 env
- ✅ 不改变 Bot
- ✅ 不改变 CLI
- ✅ 不改变安装器
- ✅ 不 tag/release

**结论：Web 添加了 `POST /language` 路由，session 存储语言覆盖，`get_current_lang()` 实现 session > config.lang > 默认 zh 优先级，layout.html 添加了语言切换按钮。登出/session 过期自动重置。**

---

## 2. Changed paths

| 文件 | 变更 |
|------|------|
| `web/app.py` | 添加 `get_current_lang()` 辅助函数，更新 `inject_i18n()` context processor，添加 `POST /language` 路由，更新 self-test |
| `web/i18n.py` | 添加 `lang_switch_to_en`、`lang_switch_to_zh`、`lang_changed`、`lang_invalid` i18n 键 |
| `web/templates/layout.html` | 导航栏添加语言切换表单（POST /language，CSRF，按钮） |
| `tests/web-language-switch-v1.9.51.py` | 新增聚焦测试 |
| `docs/validation-v1.9.51-web-session-language-switch.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.51 条目 |
| `docs/roadmap.md` | 新增 v1.9.51 版本行 |

---

## 3. Web language behavior

| 特性 | 说明 |
|------|------|
| 优先级 | session["lang"] > config.lang (NANOBK_LANG) > 默认 zh |
| 有效值 | `zh`、`en` |
| 无效值 | 忽略，不存储，不崩溃 |
| session 过期 | 重置，回退到 config.lang |
| 登出 | `session.clear()` 清除语言覆盖 |
| 不写 env | ✅ |
| 不读 env | ✅ |

---

## 4. Language switch route

| 特性 | 说明 |
|------|------|
| 路径 | `POST /language` |
| 方法 | POST only |
| 登录要求 | ✅ `@require_login` |
| CSRF 保护 | ✅ `validate_csrf()` |
| 表单字段 | `lang`（zh/en）、`csrf_token` |
| 有效输入 | `zh`、`en` |
| 无效输入 | 静默忽略，不存储 |
| 重定向 | referrer（同源）或 dashboard |
| 无开放重定向 | ✅ referrer 检查 `request.host_url` |

---

## 5. Layout UI

| 特性 | 说明 |
|------|------|
| 位置 | 导航栏，logout 按钮前 |
| 当前 lang=zh | 显示 "EN" 按钮 |
| 当前 lang=en | 显示 "中文" 按钮 |
| 表单方法 | POST |
| CSRF | ✅ 包含 csrf_token |
| 外部 JS | 无 |
| 外部 CSS | 无 |
| token 暴露 | 无 |
| env 路径暴露 | 无 |
| 保留现有导航 | ✅ Dashboard/Status/Doctor/Rotate/Logout |

---

## 6. Safety boundaries

| 边界 | 状态 |
|------|------|
| 不读 env 文件 | ✅ |
| 不写 env 文件 | ✅ |
| 不打印密钥 | ✅ |
| 不改变 Raw JSON schema | ✅ |
| 不翻译 Raw JSON 键名 | ✅ |
| 不改变 redaction/gating/advanced/rotate | ✅ |
| 不改变 Bot | ✅ |
| 不改变 CLI | ✅ |
| 不改变安装器 | ✅ |
| shell=True 无 | ✅ |
| os.system 无 | ✅ |

---

## 7. Compatibility and tradeoffs

| 权衡 | 说明 |
|------|------|
| session 切换 | 即时生效，安全 |
| 不持久 | 登出/session 过期/重启后重置 |
| 持久切换 | 未来 CLI/installer 安全路径 |
| 英文仍有效 | NANOBK_LANG=en 或 UI 切换 |
| 中文默认 | 新安装默认中文 |

---

## 8. Tests run

| 测试 | 结果 |
|------|------|
| `tests/web-language-switch-v1.9.51.py` | ✅ 通过 |
| `python3 web/app.py --self-test` | ✅ 通过 |
| `bash tests/web-panel-mock.sh` | ✅ 通过 |

---

## 9. Known limitations

| 限制 | 说明 |
|------|------|
| 不持久 | session 级，重启后重置 |
| 无 Bot 语言命令 | v1.9.52 任务 |
| 无持久 CLI 语言命令 | 长期任务 |
| 无真实中英文冒烟测试 | v1.9.53-54 任务 |
| CLI 版本显示仍待定 | 独立任务 |
| AI 维护接口仍待定 | v1.9.57-59 任务 |

---

## 10. Next step

**推荐：v1.9.52 — Bot Language Command / Guidance Minimal Implementation**

仅在 ChatGPT 审核后实施。
