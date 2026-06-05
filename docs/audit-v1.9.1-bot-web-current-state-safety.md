# v1.9.1 — Bot/Web Current-State Safety Audit

> 审计类型：文档/静态代码审计
> 审计日期：2026-06-05
> 基线 commit：`160c141f06b7a5cf90923ab5cd783e2062deb2b0`
> 基线信息：`docs: add v1.9.0 bot web control plane planning`

---

## 1. 本轮审计结论摘要

**结论：PASS — 可进入 v1.9.2 Bot UX/Menu Spec**

本轮为 **documentation/audit only**：

- ✅ 无代码行为变更
- ✅ 无部署逻辑变更
- ✅ 无 `install.sh` 变更
- ✅ 无 `bin/nanobk` 变更
- ✅ 无 tag/release

审计发现：

1. **Bot/Web 均未发现直接写入 configs/systemd/secrets/env 的代码路径。** 两者均通过 `subprocess.run()` 以 list 形式调用 `nanobk` CLI，无 `shell=True`。
2. **`format_status()` 在 Bot 中直接展示 `domain`、`vpsIp`、`geo`，未做地址类脱敏。** 这是 v1.9 产品化的首要安全差距。
3. **`/status_json`（Bot）和 `/status` 的 Raw JSON（Web）暴露经过基础 redaction 的完整 JSON，可能包含 IP、域名、route URL 等非 token 类敏感字段。**
4. **Redaction 覆盖 token/password/private_key/secret 类 key-value 和长 base64/hex 串，但不覆盖 IP 地址、域名、URL、workers.dev、订阅路径。** 这是已知差距，需在 v1.9.5 专门解决。
5. **确认流仅覆盖 rotate，且已有二次确认 + 过期机制。** Doctor 无二次确认（合理，属中风险只读）。
6. **Bot owner-only 授权、Web token 登录 + CSRF + session 基础安全机制已就位。**

---

## 2. 审计范围

### Bot 文件

| 文件 | 说明 |
|------|------|
| `bot/nanobk_bot.py` | 主入口，v1.1.0 |
| `bot/requirements.txt` | `python-telegram-bot>=21,<22` |
| `bot/run.sh` | venv 启动脚本 |
| `bot/.env.example` | 环境变量模板 |
| `bot/README.md` | 文档 |
| `bot/systemd/nanobk-telegram-bot.service.example` | systemd 示例 |

### Web 文件

| 文件 | 说明 |
|------|------|
| `web/app.py` | 主入口，v1.2.1 |
| `web/requirements.txt` | Flask 依赖 |
| `web/run.sh` | venv 启动脚本 |
| `web/.env.example` | 环境变量模板 |
| `web/README.md` | 文档 |
| `web/static/style.css` | 样式 |
| `web/templates/layout.html` | 布局模板 |
| `web/templates/login.html` | 登录页 |
| `web/templates/index.html` | Dashboard |
| `web/templates/status.html` | 状态页 |
| `web/templates/doctor.html` | Doctor 页 |
| `web/templates/rotate.html` | Rotate 页 |
| `web/systemd/nanobk-web-panel.service.example` | systemd 示例 |

### CLI/Status 文件

| 文件 | 说明 |
|------|------|
| `bin/nanobk` | CLI 主入口（仅读取前 100 行了解接口） |

### 测试文件

| 文件 | 说明 |
|------|------|
| `tests/bot-cli-mock.sh` | Bot mock 测试 |
| `tests/web-panel-mock.sh` | Web mock 测试 |
| `tests/fixtures/status-json-sanitized-v1.8.json` | Status JSON fixture |

### 文档文件

| 文件 | 说明 |
|------|------|
| `README.md` | 项目说明 |
| `CHANGELOG.md` | 变更日志 |
| `docs/roadmap.md` | 路线图 |
| `docs/planning-v1.9.0-bot-web-control-plane-productization.md` | v1.9 规划 |
| `docs/validation-v1.8-closeout-decision.md` | v1.8 closeout |
| `SECURITY.md` | 安全文档 |

---

## 3. Bot 当前结构

### 主入口

- `bot/nanobk_bot.py` — Python Telegram Bot，文件头标注 v1.1.0

### 命令处理器

| 命令 | 函数 | 说明 |
|------|------|------|
| `/start` | `cmd_start()` | 返回 Bot online + `/help` 提示 |
| `/help` | `cmd_help()` | 列出所有命令 |
| `/status` | `cmd_status()` | 调用 `nanobk --json status`，格式化展示 |
| `/status_json` | `cmd_status_json()` | 调用 `nanobk --json status`，展示 redacted raw output |
| `/doctor` | `cmd_doctor()` | 调用 `nanobk doctor` |
| `/cancel` | `cmd_cancel()` | 取消 pending confirmation |
| `/rotate_all` | `make_rotate_handler("rotate_all")` | 请求 rotate 确认 |
| `/rotate_hy2` | `make_rotate_handler("rotate_hy2")` | 请求 rotate 确认 |
| `/rotate_tuic` | `make_rotate_handler("rotate_tuic")` | 请求 rotate 确认 |
| `/rotate_reality` | `make_rotate_handler("rotate_reality")` | 请求 rotate 确认 |
| `/rotate_trojan` | `make_rotate_handler("rotate_trojan")` | 请求 rotate 确认 |
| `/confirm_rotate_*` | `cmd_confirm_rotate()` | 确认并执行 rotate |
| 未知命令 | `cmd_unknown()` | 返回 "Use /help" |

### 辅助函数

| 函数 | 说明 |
|------|------|
| `run_nanobk()` | CLI 调用封装，subprocess.run + list cmd |
| `strip_ansi()` | 去除 ANSI 转义码 |
| `redact_text()` | 文本级脱敏（token/password/key/secret + 长串） |
| `limit_text()` | 截断到 3500 字符 |
| `safe_output()` | strip_ansi + redact_text + limit_text |
| `format_status()` | 将 JSON status 格式化为可读文本 |
| `is_owner()` | Owner-only 授权检查 |
| `ConfirmationManager` | 确认管理器，120 秒过期 |

### 确认流

- `ConfirmationManager` 类管理 pending confirmation
- 每个 rotate 命令先设置 pending，用户需回复 `/confirm_rotate_<proto>`
- 120 秒过期自动清除
- `NANOBK_BOT_DRY_RUN=true` 时只显示 "would execute"

### Redaction 函数

- `redact_text()` 使用 3 个正则：
  1. Telegram bot token 格式（`\d{6,}:[A-Za-z0-9_-]{20,}`）→ `[BOT_TOKEN_REDACTED]`
  2. token/password/private_key/key=value → `[REDACTED]`
  3. 长 base64/hex 串（≥40 字符）→ `[REDACTED_B64]`

---

## 4. Bot 调用 nanobk CLI 的路径

### 调用方式总览

所有调用均通过 `run_nanobk(config, args, timeout)` 函数：

```python
cmd = [config.nanobk_cli] + args
proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
```

- ✅ `shell=False`（默认）
- ✅ args 为 list 形式
- ✅ 无用户输入拼接
- ✅ 返回 `CommandResult(code, stdout, stderr, duration)`

### 逐条路径

| # | 文件/函数 | 命令形状 | shell | args | 输出脱敏 | 返回码检查 | 风险级别 | 确认 |
|---|----------|----------|-------|------|----------|-----------|---------|------|
| 1 | `cmd_status()` | `nanobk --json status` | False | list | ✅ `safe_output()` | ✅ `code != 0` 检查 | 低（只读） | 无（直接） |
| 2 | `cmd_status_json()` | `nanobk --json status` | False | list | ✅ `safe_output()` | ✅ `code != 0` 检查 | 中（raw JSON） | 无（直接） |
| 3 | `cmd_doctor()` | `nanobk doctor` | False | list | ✅ `safe_output()` | ✅ `code != 0` 追加 | 中（只读诊断） | 无（直接） |
| 4 | `cmd_confirm_rotate()` | `nanobk rotate <proto> --yes` | False | list | ✅ `safe_output()` | ✅ `code != 0` 检查 | **高（写操作）** | ✅ 二次确认 |

---

## 5. Bot 安全风险表

| 区域 | 当前行为 | 风险 | 证据 | 建议下一步 |
|------|----------|------|------|-----------|
| `/status` | 调用 `nanobk --json status`，`format_status()` 展示 `domain`、`vpsIp`、`geo` | **中** | `nanobk_bot.py:152-153` | v1.9.2 应将 IP/domain 默认脱敏或摘要化 |
| `/status_json` | 调用 `nanobk --json status`，展示 `safe_output(result.stdout)` | **中** | `nanobk_bot.py:412` | v1.9 应考虑移除、隐藏或改为 safe JSON |
| `/doctor` | 调用 `nanobk doctor`，展示 `safe_output()` | 中 | `nanobk_bot.py:419-425` | 可接受，但输出可能包含路径/IP |
| rotate 确认 | 二次确认 + 120 秒过期 + dry-run 支持 | 低 | `nanobk_bot.py:452-519` | 当前覆盖良好 |
| redaction | 覆盖 token/password/key/secret + 长串 | 中 | `nanobk_bot.py:115-131` | 不覆盖 IP/domain/URL/workers.dev/订阅路径 |
| IP/domain 显示 | `format_status()` 直接展示 `vpsIp`、`domain` | **中** | `nanobk_bot.py:152-153` | 应默认 `[REDACTED_IP]`/`[REDACTED_DOMAIN]` |
| subscription URL | 未在 Bot 代码中直接出现 | 低 | — | 但 nanobk status JSON 可能包含 |
| Reality private key | 未在 Bot 代码中直接出现 | 低 | — | nanobk CLI 已保证不进入 profile.current.json |
| raw JSON 暴露 | `/status_json` 展示 redacted raw JSON | **中** | `nanobk_bot.py:401-412` | 应限制为开发者/高级模式 |
| failure 输出 | 失败时展示 `safe_output(stderr)` | 低 | `nanobk_bot.py:388-390` | 已脱敏，可接受 |
| owner-only | 每个命令检查 `is_owner()` | 低 | `nanobk_bot.py:345-346` | 良好 |
| dry-run | `NANOBK_BOT_DRY_RUN` 控制 rotate 行为 | 低 | `nanobk_bot.py:504-509` | 良好 |

---

## 6. Web 当前结构

### 主入口

- `web/app.py` — Python Flask，文件头标注 v1.2.1

### Framework/Runtime

- Python Flask
- Token login（`NANOBK_WEB_TOKEN`）
- Flask session（`app.secret_key`）
- CSRF token（`secrets.token_urlsafe(32)`）
- 默认 host `127.0.0.1`，port `8080`
- 默认 dry-run `true`

### 路由/端点

| 方法 | 路由 | 函数 | 说明 |
|------|------|------|------|
| GET | `/healthz` | `healthz()` | 无认证，返回 `{"ok": true}` |
| GET/POST | `/login` | `login()` | Token 登录 |
| POST | `/logout` | `logout()` | CSRF 保护，清除 session |
| GET | `/` | `dashboard()` | Dashboard，调用 `nanobk --json status` |
| GET | `/status` | `status()` | 状态页，调用 `nanobk --json status` |
| GET | `/api/status` | `api_status()` | API 端点，返回 `redact_json()` 后的 JSON |
| GET/POST | `/doctor` | `doctor()` | Doctor 页，POST 时调用 `nanobk doctor` |
| GET | `/rotate` | `rotate()` | Rotate 页 |
| POST | `/rotate/request` | `rotate_request()` | 请求 rotate 确认 |
| POST | `/rotate/confirm` | `rotate_confirm()` | 确认并执行 rotate |
| POST | `/rotate/cancel` | `rotate_cancel()` | 取消 pending |

### 辅助函数

| 函数 | 说明 |
|------|------|
| `run_nanobk()` | CLI 调用封装，subprocess.run + list cmd |
| `strip_ansi()` | 去除 ANSI 转义码 |
| `redact_text()` | 文本级脱敏 |
| `redact_json()` | 递归 JSON 脱敏，按敏感 key substring 匹配 |
| `limit_text()` | 截断到 12000 字符 |
| `safe_output()` | strip_ansi + redact_text + limit_text |
| `format_status()` | 格式化 JSON status，包含 `raw_json` 字段 |
| `validate_protocol()` | 协议名白名单验证 |
| `get_pending_rotate()` / `set_pending_rotate()` / `clear_pending_rotate()` | Session 级确认管理 |
| `get_csrf_token()` / `validate_csrf()` | CSRF 保护 |
| `is_logged_in()` / `require_login()` | 认证装饰器 |

### 认证/Session/CSRF

- Token 登录：`NANOBK_WEB_TOKEN` 环境变量
- Session：Flask session + `app.secret_key`
- CSRF：`secrets.token_urlsafe(32)`，通过 `context_processor` 注入模板
- Logout：POST 表单 + CSRF 验证
- 所有认证路由使用 `@require_login` 装饰器

### 模板

| 模板 | 说明 |
|------|------|
| `layout.html` | 导航栏 + CSRF logout 按钮 |
| `login.html` | 登录表单 |
| `index.html` | Dashboard，展示 status card + quick actions |
| `status.html` | 状态页，展示 status card + Raw JSON `<details>` |
| `doctor.html` | Doctor 页，POST 触发 + output `<pre>` |
| `rotate.html` | Rotate 页，协议选择 + 确认流程 + dry-run 结果 |

---

## 7. Web 调用 nanobk CLI 的路径

### 调用方式总览

所有调用均通过 `run_nanobk(config, args, timeout)` 函数：

```python
cmd = [config.nanobk_cli] + args
proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
```

- ✅ `shell=False`（默认）
- ✅ args 为 list 形式
- ✅ 无用户输入拼接
- ✅ 返回 `CommandResult(code, stdout, stderr, duration)`

### 逐条路径

| # | 文件/函数 | 路由/端点 | 命令形状 | shell | args | 输出脱敏 | 返回码检查 | 风险 | 确认 |
|---|----------|----------|----------|-------|------|----------|-----------|------|------|
| 1 | `dashboard()` | `GET /` | `nanobk --json status` | False | list | ✅ `format_status()` + `redact_json()` | ✅ `code == 0` 检查 | 低 | 无 |
| 2 | `status()` | `GET /status` | `nanobk --json status` | False | list | ✅ `format_status()` + `safe_output()` | ✅ `code == 0` 检查 | 中 | 无 |
| 3 | `api_status()` | `GET /api/status` | `nanobk --json status` | False | list | ✅ `redact_json()` | ✅ `code == 0` 检查 | 中 | 无 |
| 4 | `doctor()` | `POST /doctor` | `nanobk doctor` | False | list | ✅ `safe_output()` | ✅ `code != 0` 追加 | 中 | CSRF |
| 5 | `rotate_confirm()` | `POST /rotate/confirm` | `nanobk rotate <proto> --yes` | False | list | ✅ `safe_output()` | ✅ `code != 0` 检查 | **高** | ✅ 二次确认 + CSRF |

---

## 8. Web 安全风险表

| 区域 | 当前行为 | 风险 | 证据 | 建议下一步 |
|------|----------|------|------|-----------|
| Dashboard | 展示 `domain`、`vps_ip`、`geo` | **中** | `index.html:12-16`, `app.py:182-186` | 应默认脱敏地址类字段 |
| Status 页 | 展示 `domain`、`vps_ip`、`geo` + Raw JSON | **中** | `status.html:9-11`, `status.html:41-44` | Raw JSON 应限制为高级模式 |
| Raw JSON details | `<details>` 内展示 `status.raw_json` | **中** | `status.html:41-44` | `redact_json()` 覆盖敏感 key，但 IP/domain/URL 未覆盖 |
| API status | 返回 `redact_json(data)` | 中 | `app.py:458-459` | 同上，IP/domain/URL 未覆盖 |
| Doctor | POST 触发，展示 `safe_output()` | 中 | `app.py:471-478` | CSRF 保护良好，输出可能包含路径 |
| Rotate 确认 | 二次确认 + CSRF + session pending + 120s 过期 + dry-run | 低 | `app.py:491-548` | 覆盖良好 |
| 登录/Session | Token 登录 + Flask session | 低 | `app.py:393-404` | 良好 |
| CSRF | 所有 POST 验证 CSRF token | 低 | `app.py:358-368` | 良好 |
| redaction | `redact_json()` 按敏感 key substring 脱敏 | 中 | `app.py:146-163` | 不覆盖 IP/domain/URL/workers.dev/订阅路径 |
| IP/domain 显示 | `format_status()` 直接展示 `vpsIp`、`domain` | **中** | `app.py:182-186` | 应默认脱敏 |
| workers.dev 显示 | 未在 Web 代码中直接出现 | 低 | — | 但 status JSON 可能包含 |
| subscription URL | 未在 Web 代码中直接出现 | 低 | — | 但 status JSON 可能包含 |
| failure 输出 | 失败时展示 `safe_output(stderr)` | 低 | `app.py:446` | 已脱敏 |
| healthz | 无认证 `{"ok": true}` | 低 | `app.py:387-389` | 无敏感信息泄露 |
| 默认 dry-run | `NANOBK_WEB_DRY_RUN` 默认 `true` | 低 | `web/.env.example:28` | 良好安全默认 |

---

## 9. Direct-write 审计

### 审计方法

对 `bot/` 和 `web/` 目录运行以下 grep：

```
grep -RInE 'open\(|write\(|Path.*write|os\.makedirs|os\.mkdir|chmod|shutil|/etc/nanobk|systemd|\.service|\.env.*write' bot/ web/
```

### 发现

**Bot (`bot/nanobk_bot.py`)**：

- ❌ 无 `open()` 调用（写模式）
- ❌ 无 `write()` 调用
- ❌ 无 `Path.write_*` 调用
- ❌ 无 `os.makedirs` / `os.mkdir`
- ❌ 无 `chmod` 调用
- ❌ 无 `/etc/nanobk` 引用（代码中）
- ❌ 无 systemd 文件写入

**Web (`web/app.py`)**：

- ❌ 无 `open()` 调用（写模式）
- ❌ 无 `write()` 调用
- ❌ 无 `Path.write_*` 调用
- ❌ 无 `os.makedirs` / `os.mkdir`
- ❌ 无 `chmod` 调用
- ❌ 无 `/etc/nanobk` 弄用（代码中）
- ❌ 无 systemd 文件写入

**文档中的引用**（仅 `README.md`，非运行时代码）：

- `bot/README.md` 提到 `systemctl` 和 `/etc/systemd/system/` — 属于部署说明文档
- `web/README.md` 提到 `systemctl` 和 `/etc/systemd/system/` — 属于部署说明文档
- `bot/README.md` 提到 `/etc/nanobk/` — 属于 "No direct file access" 说明

### 结论

**Bot/Web 代码运行时无任何直接写入 configs/systemd/secrets/env 的路径。** 所有引用均为文档说明或 `.env.example` 模板。

---

## 10. Raw Status / Raw JSON 暴露审计

### Bot 端

| 区域 | 暴露内容 | 脱敏 | 风险 | 建议 |
|------|----------|------|------|------|
| `/status` → `format_status()` | `domain`、`vpsIp`、`geo`、`services`、`security.secretsMode`、`cloudflare` 状态 | ❌ IP/domain/geo 未脱敏 | **中** | 应默认 `[REDACTED_IP]`、`[REDACTED_DOMAIN]` |
| `/status_json` | `nanobk --json status` 全量输出经 `safe_output()` | ⚠️ 基础 redaction（token/key/secret + 长串），但 IP/domain/URL 未覆盖 | **中** | 应移除或改为 safe JSON summary |

### Web 端

| 区域 | 暴露内容 | 脱敏 | 风险 | 建议 |
|------|----------|------|------|------|
| Dashboard (`/`) | `domain`、`vps_ip`、`geo`、`services`、`warnings` | ❌ IP/domain/geo 未脱敏 | **中** | 应默认脱敏 |
| Status (`/status`) | 同上 + Raw JSON `<details>` 块 | ⚠️ `redact_json()` 覆盖敏感 key，但 IP/domain/URL 未覆盖 | **中** | Raw JSON 应限制为高级模式 |
| API (`/api/status`) | `redact_json(data)` 完整 JSON | ⚠️ 同上 | **中** | 应增加地址类脱敏 |

### 需要关注的字段

以下字段在 `nanobk --json status` 输出中可能出现，当前 Bot/Web 未做地址类脱敏：

- `vpsIp` / `vps_ip` — VPS IP 地址
- `domain` — 域名
- `geo` — 地理位置（间接暴露区域信息）
- `route` / `routeUrl` — Cloudflare route URL
- `workers.dev` — Worker 默认域名
- `subscriptionUrl` / `sub_url` — 订阅 URL
- `subscriptionPath` — 订阅路径

### 分类

| 字段 | 当前状态 | 建议分类 |
|------|----------|----------|
| `ok` | ✅ 安全直接展示 | 安全 |
| `services.*` | ✅ 服务状态 | 安全 |
| `security.secretsMode` | ✅ 模式信息 | 安全 |
| `cloudflare.*.envExists` | ✅ 布尔值 | 安全 |
| `warnings` | ✅ 警告文本 | 安全（需确认无敏感信息） |
| `domain` | ⚠️ 直接展示 | **必须脱敏** |
| `vpsIp` / `vps_ip` | ⚠️ 直接展示 | **必须脱敏** |
| `geo` | ⚠️ 直接展示 | 建议摘要化 |
| `route` / `routeUrl` | 未知（未在当前代码中出现） | **必须脱敏**（如果存在） |
| `workers.dev` 域名 | 未知（未在当前代码中出现） | **必须脱敏**（如果存在） |
| `subscriptionUrl` | 未知（未在当前代码中出现） | **必须脱敏**（如果存在） |

---

## 11. Redaction 覆盖审计

### Bot `redact_text()` 覆盖范围

| 模式 | 覆盖 | 证据 |
|------|------|------|
| Telegram bot token (`\d{6,}:[A-Za-z0-9_-]{20,}`) | ✅ | `nanobk_bot.py:117` |
| `token=value` / `token: value` | ✅ | `nanobk_bot.py:119` |
| `password=value` | ✅ | `nanobk_bot.py:119` |
| `private_key=value` | ✅ | `nanobk_bot.py:119` |
| `secret=value` | ✅ | `nanobk_bot.py:119` |
| 长 base64/hex 串（≥40 字符） | ✅ | `nanobk_bot.py:121` |
| IPv4 地址 | ❌ 未覆盖 | — |
| IPv6 地址 | ❌ 未覆盖 | — |
| 域名 | ❌ 未覆盖 | — |
| URL | ❌ 未覆盖 | — |
| `workers.dev` | ❌ 未覆盖 | — |
| 订阅 URL | ❌ 未覆盖 | — |
| Reality private key | ⚠️ 部分覆盖（通过 `PrivateKey:` key-value 模式） | `nanobk_bot.py:119` |
| Cloudflare token | ⚠️ 部分覆盖（通过 `token=value` 模式） | `nanobk_bot.py:119` |
| Bot token | ✅ 专用正则 | `nanobk_bot.py:117` |
| Admin token | ⚠️ 部分覆盖（通过 `token=value` 模式） | `nanobk_bot.py:119` |

### Web `redact_text()` + `redact_json()` 覆盖范围

| 模式 | 覆盖 | 证据 |
|------|------|------|
| `token` key | ✅ `redact_json()` 按 key substring | `app.py:146` |
| `password` key | ✅ | `app.py:146` |
| `secret` key | ✅ | `app.py:146` |
| `private` / `privatekey` key | ✅ | `app.py:146` |
| 文本级 token/password/key/secret | ✅ `redact_text()` | `app.py:130-133` |
| 长 base64/hex 串 | ✅ | `app.py:133` |
| IPv4 地址 | ❌ 未覆盖 | — |
| IPv6 地址 | ❌ 未覆盖 | — |
| 域名 | ❌ 未覆盖 | — |
| URL | ❌ 未覆盖 | — |
| `workers.dev` | ❌ 未覆盖 | — |
| 订阅 URL | ❌ 未覆盖 | — |
| Reality private key | ⚠️ 部分覆盖（通过 key substring） | `app.py:146` |
| Cloudflare token | ⚠️ 部分覆盖（通过 key substring） | `app.py:146` |

### 总结

| 覆盖维度 | Bot | Web |
|----------|-----|-----|
| token/password/secret 类 key-value | ✅ | ✅ |
| 长 base64/hex 串 | ✅ | ✅ |
| Telegram bot token 专用格式 | ✅ | ❌（无专用正则） |
| JSON key-level 脱敏 | ❌（仅文本级） | ✅ `redact_json()` |
| IPv4 地址 | ❌ | ❌ |
| IPv6 地址 | ❌ | ❌ |
| 域名 | ❌ | ❌ |
| URL | ❌ | ❌ |
| `workers.dev` | ❌ | ❌ |
| 订阅 URL/路径 | ❌ | ❌ |
| Reality private key（值级） | ⚠️ 部分 | ⚠️ 部分 |

**诚实评估：当前 redaction 覆盖了 secret 类值，但不覆盖地址类信息（IP、域名、URL、workers.dev、订阅路径）。这是 v1.9.5 的核心任务。**

---

## 12. Doctor 命令审计

### Bot 端

- **调用方式**：`cmd_doctor()` → `run_nanobk(config, ["doctor"], timeout=config.command_timeout)`
- **命令形状**：`nanobk doctor`，list 形式，`shell=False`
- **输出处理**：`safe_output(result.stdout or result.stderr)`
- **返回码**：非零时追加 `(exit code: N)`
- **确认**：无二次确认（直接执行）
- **风险级别**：中（只读诊断）

### Web 端

- **调用方式**：`doctor()` POST → `run_nanobk(config, ["doctor"], timeout=config.command_timeout)`
- **命令形状**：`nanobk doctor`，list 形式，`shell=False`
- **输出处理**：`safe_output(result.stdout or result.stderr)`
- **返回码**：非零时追加 `(exit code: N)`
- **确认**：CSRF 保护（POST 表单）
- **风险级别**：中（只读诊断）

### 评估

- ✅ Doctor 从 Bot/Web 视角是只读的 — 只调用 `nanobk doctor`，不传 `--yes` 或其他写标志
- ⚠️ Doctor 输出可能包含系统路径、IP 地址、域名等 — 已经过 `safe_output()` 但不覆盖地址类
- ⚠️ 无二次确认 — 但作为只读诊断命令，这是合理的
- **建议**：Doctor 应保持为中风险，直到证明其输出不包含地址类敏感信息

---

## 13. Rotate 命令审计

### Bot 端

- **流程**：
  1. 用户发送 `/rotate_<proto>` → 设置 `ConfirmationManager` pending（120 秒过期）
  2. Bot 回复确认提示（说明影响范围）
  3. 用户发送 `/confirm_rotate_<proto>` → 检查 pending 匹配 → 执行
- **命令形状**：`nanobk rotate <proto> --yes`，list 形式，`shell=False`
- **Dry-run**：`NANOBK_BOT_DRY_RUN=true` 时只显示 "would execute"
- **确认**：✅ 二次确认 + 过期机制
- **输出脱敏**：✅ `safe_output()`
- **风险级别**：高（写操作）

### Web 端

- **流程**：
  1. 用户选择协议 → `POST /rotate/request` → 设置 session pending（120 秒过期）
  2. 显示确认页面（说明影响范围）
  3. 用户点击 "Confirm" → `POST /rotate/confirm` → CSRF 验证 → 执行
- **命令形状**：`nanobk rotate <proto> --yes`，list 形式，`shell=False`
- **Dry-run**：`NANOBK_WEB_DRY_RUN=true`（默认）时只显示 "would execute"
- **确认**：✅ 二次确认 + CSRF + 过期机制
- **输出脱敏**：✅ `safe_output()`
- **风险级别**：高（写操作）

### 评估

- ✅ 两步确认机制完善
- ✅ 120 秒过期自动清除
- ✅ 协议白名单验证（Web 端 `VALID_PROTOCOLS`）
- ✅ `--yes` 标志已包含（避免 CLI 交互式提示）
- ✅ Dry-run 默认安全（Web 默认 true）
- ⚠️ 无 `--dry-run` 标志传递给 CLI（依赖 `NANOBK_BOT_DRY_RUN` / `NANOBK_WEB_DRY_RUN` 环境变量控制）

---

## 14. v1.9.2 Readiness Recommendation

**推荐：A. v1.9.2 Bot UX/Menu Spec 可以继续**

理由：

1. **无直接写入风险**：Bot/Web 代码确认无直接写入 configs/systemd/secrets 的路径。
2. **CLI 调用安全**：所有调用使用 list 形式 + `shell=False`，无用户输入拼接。
3. **确认机制就位**：Rotate 已有完善的二次确认 + 过期机制。
4. **基础安全就位**：Owner-only（Bot）、Token + CSRF + Session（Web）。
5. **已知差距明确**：地址类脱敏（IP/domain/URL）是 v1.9.5 的任务，不阻塞 v1.9.2 UX spec。
6. **测试通过**：`bot-cli-mock.sh` 和 `web-panel-mock.sh` 均通过。

**v1.9.2 应注意**：

- UX spec 中必须明确地址类字段的默认展示策略（脱敏/摘要化）
- `/status_json` 的产品化方向需在 spec 中确定（移除/隐藏/safe JSON）
- Raw JSON details 块的展示策略需在 spec 中确定

---

## 15. v1.9 Implementation Guardrails

以下为 v1.9 实现阶段的硬性约束：

1. **禁止 Bot/Web 直接写入 configs/systemd/secrets/env** — 必须通过 `nanobk` CLI
2. **禁止在新手视图中展示 raw JSON** — 应使用安全摘要或 safe JSON
3. **禁止在新手视图中展示 raw IP/domain/URL/subscription URL/workers.dev** — 应默认脱敏
4. **禁止高风险操作无确认** — rotate/restart/healthcheck/refresh/Cloudflare 操作必须二次确认
5. **禁止实现 production status wrapper** — 未批准
6. **禁止 dirty VPS status wrapping** — 未批准
7. **禁止 operation-log full rollout** — 未批准
8. **禁止修改 `install.sh` 行为** — 保护 v1.7.27 基线
9. **禁止 tag/release** — 未批准
10. **禁止修改 VPS 协议模板** — 保护稳定基线
11. **禁止修改 Cloudflare Worker core** — 保护稳定基线
12. **禁止修改 rotate sync** — 保护稳定基线
13. **禁止修改 `bin/nanobk` 核心逻辑** — 除非 v1.9 明确需要
14. **所有 Bot/Web 输出必须经过 `safe_output()` 或 `redact_json()`** — 包括失败输出
15. **所有 Web POST 端点必须验证 CSRF** — 已有机制
16. **所有 Bot 命令必须检查 `is_owner()`** — 已有机制

---

## 附录 A：Bot 文件清单

```
bot/
├── .env.example
├── README.md
├── nanobk_bot.py          # 主入口 v1.1.0
├── requirements.txt       # python-telegram-bot>=21,<22
├── run.sh                 # venv 启动
└── systemd/
    └── nanobk-telegram-bot.service.example
```

## 附录 B：Web 文件清单

```
web/
├── .env.example
├── README.md
├── app.py                 # 主入口 v1.2.1
├── requirements.txt       # Flask 依赖
├── run.sh                 # venv 启动
├── static/
│   └── style.css
├── systemd/
│   └── nanobk-web-panel.service.example
└── templates/
    ├── doctor.html
    ├── index.html
    ├── layout.html
    ├── login.html
    ├── rotate.html
    └── status.html
```

## 附录 C：测试结果

### tests/bot-cli-mock.sh

```
=== NanoBK Bot CLI Mock Test ===

--- Syntax checks ---
✓ nanobk_bot.py compiles
✓ run.sh syntax

--- Running bot self-test ---
=== NanoBK Bot Self-Test ===
✓ (20/20 passed)

--- Safety checks ---
✓ No shell invocation flag in nanobk_bot.py (code only)
✓ No real bot token in nanobk_bot.py
✓ bot/.env is gitignored
✓ strip_ansi function exists
✓ safe_output calls strip_ansi
✓ bot/run.sh contains venv guidance

=== All bot tests passed! ===
```

### tests/web-panel-mock.sh

```
=== NanoBK Web Panel Mock Test ===

--- Syntax checks ---
✓ app.py compiles
✓ run.sh syntax

--- Running web panel self-test ---
=== NanoBK Web Panel Self-Test ===
✓ (24/24 passed)

--- Safety checks ---
✓ No shell invocation flag in app.py (code only)
✓ No real web token in app.py
✓ web/.env is gitignored
✓ web/.venv is gitignored
✓ strip_ansi function exists
✓ safe_output calls strip_ansi
✓ web/run.sh contains venv guidance
✓ .env.example binds to 127.0.0.1
✓ redact_json function exists
✓ validate_csrf function exists
✓ CSRF tokens in templates (3 files)
✓ No fallback static secret in app.py
✓ Logout uses POST form
✓ /api/status uses redact_json

=== All web panel tests passed! ===
```

## 附录 D：Grep 审计模式

用于直接写入审计的 grep 命令：

```bash
grep -RInE 'open\(|write\(|Path.*write|os\.makedirs|os\.mkdir|chmod|shutil|/etc/nanobk|systemd|\.service|\.env.*write' bot/ web/
```

用于敏感模式审计的 grep 命令：

```bash
grep -RInE 'subprocess|os\.system|Popen|run_nanobk|nanobk|systemctl|/etc/nanobk|secrets|\.env|workers\.dev|vpsIp|vps_ip|domain|route|subscription|private_key|PRIVATE_KEY|token|TOKEN' bot/ web/
```

**注意**：以上命令仅供审计使用，不应用于输出真实敏感值。
