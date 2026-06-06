# v1.9.54 — Web Language Switch Test Debt Fix

> 验证类型：Web 语言切换测试债务修复
> 日期：2026-06-06
> 基线 commit：`0ff11aec56729661b393ec0553245f99f23b781a`
> 基线信息：`docs: add v1.9.53 chinese english smoke plan`

---

## 1. 本轮目标与结论

**v1.9.54 修复了已知的 `tests/web-language-switch-v1.9.51.py` 测试债务：**

- ✅ 测试债务是源码级/脆弱匹配问题，不是运行时行为问题
- ✅ 无 Web 运行时行为变更
- ✅ 无 Bot 变更
- ✅ 无安装器变更
- ✅ 无 CLI 变更
- ✅ 无 tag/release

**结论：测试使用 `web_source.split("def language(")` 定位语言路由代码，但 `web/app.py` 中 `def language(` 出现两次（实际函数定义 + self-test 代码中的字符串引用），导致 `split` 产生 3 个部分，`parts[1]` 指向 self-test 代码而非路由函数体。修复方案：使用 `re.search(r'^[ ]*def language\\(', web_source, re.MULTILINE)` 精确定位行首函数定义。**

---

## 2. Root cause

### 旧测试行为

```python
lang_decorator_area = web_source.split("def language(")[0][-200:]
lang_body = web_source.split("def language(")[1].split("\n    def ")[0]
```

### 失败原因

`web/app.py` 包含两处 `def language(`：

1. **实际路由函数**（第 1048 行附近）：
   ```python
   def language():
       if not validate_csrf():
           ...
   ```

2. **self-test 代码中的字符串引用**（第 952 行附近）：
   ```python
   _lang_parts = _src.rsplit("def language(", 1)
   ```

`split("def language(")` 产生 3 个部分：`parts[0]` = 第一个匹配前，`parts[1]` = 两个匹配之间（self-test 代码），`parts[2]` = 第二个匹配后（实际函数体）。

测试检查 `parts[1]`（self-test 代码）中的 "POST"、"require_login" 等，自然找不到。

### 为什么是假阳性

Web 语言切换运行时功能正常。self-test（`web/app.py --self-test`）使用 `rsplit` 正确提取了最后一个 `def language(`，因此 self-test 通过。外部测试使用 `split`（取第一个），因此匹配到错误的代码段。

---

## 3. Test fix summary

| 项目 | 旧 | 新 |
|------|-----|-----|
| 提取方式 | `web_source.split("def language(")` | `re.search(r'^[ ]*def language\\(', web_source, re.MULTILINE)` |
| 匹配目标 | 第一个出现（可能是字符串引用） | 行首函数定义（跳过字符串） |
| 装饰器区域 | `parts[0][-200:]` | `web_source[max(0, m.start()-200):m.start()]` |
| 函数体 | `parts[1].split("\\n    def ")[0]` | `web_source[m.end():].split('\\n    def ')[0]` |
| 新增依赖 | 无 | `import re` |

### 保留的安全检查

- `/language route exists` — 检查 `"/language"` 在源码中
- `/language is POST only` — 检查装饰器区域的 "POST"
- `/language requires login` — 检查装饰器区域的 "require_login"
- `/language validates CSRF` — 检查函数体的 "validate_csrf"
- `/language accepts lang form field` — 检查函数体的 `request.form.get("lang"`
- `/language stores valid lang` — 检查函数体的 `session["lang"]`
- `/language only accepts zh/en` — 检查函数体的 `"zh", "en"`
- `/language redirects safely` — 检查函数体的 "redirect"
- 无断言被削弱

---

## 4. Web language switch verification

| 特性 | 验证方式 | 结果 |
|------|----------|------|
| 路由存在 | 源码检查 `"/language"` | ✅ |
| POST only | 装饰器 `methods=["POST"]` | ✅ |
| 需要登录 | 装饰器 `@require_login` | ✅ |
| CSRF 保护 | 函数体 `validate_csrf()` | ✅ |
| 接受 lang 字段 | `request.form.get("lang"` | ✅ |
| 存储有效语言 | `session["lang"] = lang` | ✅ |
| 仅接受 zh/en | `if lang in ("zh", "en")` | ✅ |
| 无效语言安全 | 无效值静默忽略 | ✅ |
| 安全重定向 | referrer 同源检查 | ✅ |
| 登出重置 | `session.clear()` | ✅ |
| 无 env 写入 | 源码检查 | ✅ |
| 无 shell=True | 源码检查 | ✅ |
| 无 os.system | 源码检查 | ✅ |

---

## 5. Safety boundaries

| 边界 | 状态 |
|------|------|
| 不读 env 文件 | ✅ |
| 不写 env 文件 | ✅ |
| 不打印密钥 | ✅ |
| 不改变 Raw JSON schema | ✅ |
| 不改变 redaction/gating/advanced/rotate | ✅ |
| 不改变 Bot/installer/CLI | ✅ |

---

## 6. Tests run

| 测试 | 结果 |
|------|------|
| `tests/web-language-switch-v1.9.51.py` | ✅ 57 passed, 0 failed |
| `tests/web-i18n-minimal-v1.9.31.py` | ✅ 123 passed |
| `tests/chinese-default-v1.9.48.py` | ✅ 75 passed |
| `tests/i18n-checkpoint-v1.9.32.py` | ✅ 167 passed |
| `python3 web/app.py --self-test` | ✅ 118 passed |
| `bash tests/web-panel-mock.sh` | ✅ passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 228 passed |
| `bash tests/bot-cli-mock.sh` | ✅ passed |

---

## 7. Known limitations

| 限制 | 说明 |
|------|------|
| 不运行真实 Web 冒烟 | 测试环境无 Flask |
| 不添加持久语言设置 | 长期任务 |
| 不实现 Bot 运行时切换 | 仅引导 |
| 真实中英文冒烟测试仍待执行 | v1.9.53 计划 |

---

## 8. Next step

**推荐：v1.9.55 — Real Chinese/English Control Plane Smoke Test Validation**

仅在 ChatGPT 审核后实施。
