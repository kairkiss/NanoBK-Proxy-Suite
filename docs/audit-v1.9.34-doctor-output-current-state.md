# v1.9.34 — Doctor Output Current-State Audit

> 审计类型：Doctor 输出当前状态审计
> 日期：2026-06-05
> 基线 commit：`0baa59b919cfbd6cd8c591b04ac5146c6aceb151`
> 基线信息：`docs: add v1.9.33 doctor output planning`

---

## 1. 本轮目标与结论

**v1.9.34 是审计/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无部署逻辑变更
- ✅ 未执行真实 doctor
- ✅ 无 tag/release
- ✅ 目的是审计当前 doctor 路径并为 v1.9.35 fixture 合约测试做准备

**结论：Bot/Web doctor 路径安全（owner-only/login、redacted、no shell=True），但输出内容对新手过于技术化。CLI doctor.sh 以文本形式输出系统结构信息（OS/kernel、工具路径、端口、服务名、配置路径），直接暴露给用户不适合新手。推荐 v1.9.35 定义 fixture 合约测试，不解析真实输出。**

---

## 2. 审计方法

| 方法 | 说明 |
|------|------|
| 源码检查 | 仅检查源文件 |
| 无真实 VPS 状态 | 未运行 |
| 无真实 doctor | 未运行 |
| 无 Cloudflare 命令 | 未运行 |
| 无 env 文件读取 | 未读取 |
| 无运行时服务启动 | 未启动 |

**检查的文件：**

- `bot/nanobk_bot.py`（Bot doctor 处理器）
- `web/app.py`（Web doctor 路由）
- `web/templates/doctor.html`（Web doctor 模板）
- `web/i18n.py`（Web i18n doctor 键）
- `bin/nanobk`（CLI doctor 分发）
- `installer/doctor.sh`（CLI doctor 脚本）
- `lib/nanobk_redaction.py`（脱敏模式）
- `tests/bot-cli-mock.sh`、`tests/web-panel-mock.sh`、`tests/bot-web-command-allowlist-v1.9.4.sh`（现有测试）

---

## 3. Bot Doctor 路径

### 命令注册

| 属性 | 值 |
|------|-----|
| 命令 | `/doctor` |
| 注册 | `CommandHandler("doctor", cmd_doctor)`（bot/nanobk_bot.py:1371） |
| 处理器 | `cmd_doctor()`（bot/nanobk_bot.py:1185） |

### 执行流程

```
cmd_doctor(update, context)
  ├── is_owner(update) → 未授权则返回
  ├── reply_text(bt(config.lang, "doctor_running"))  ← i18n 包装
  ├── run_nanobk(config, ["doctor"], timeout=config.command_timeout)
  │     └── subprocess.run([nanobk_cli, "doctor"], capture_output=True, text=True)
  │           └── bin/nanobk doctor → installer/doctor.sh
  ├── output = result.stdout or result.stderr
  ├── if result.code != 0: output += "(exit code: ...)"
  └── reply_text(safe_output(output))
        ├── strip_ansi()  → 移除 ANSI 转义
        ├── redact_text() → 脱敏 IP/domain/URL/token/secret
        └── limit_text(3500) → 截断到 Telegram 限制
```

### 安全特性

| 特性 | 状态 | 位置 |
|------|------|------|
| Owner-only | ✅ | `is_owner(update)` 检查 |
| Redaction | ✅ | `safe_output()` → `redact_text()` |
| ANSI 剥离 | ✅ | `safe_output()` → `strip_ansi()` |
| 文本截断 | ✅ | `limit_text(3500)` |
| 无 shell=True | ✅ | `subprocess.run()` 使用列表形式 |
| 无直接 env 读取 | ✅ | 仅通过 CLI |
| 无直接 systemd/config 写入 | ✅ | 仅通过 CLI |
| i18n 包装 | ✅ | `bt(config.lang, "doctor_running")` |

### 未来钩子候选

| 钩子 | 说明 |
|------|------|
| 包装 cmd_doctor 在 reply 前 | 在 `safe_output()` 后、`reply_text()` 前插入摘要构建逻辑 |
| 添加摘要构建辅助函数 | 从安全数据源构建摘要 |
| 使用现有高级模式门控完整输出 | 检查 `is_advanced_mode_enabled(user_id)` |

### 限制

| 限制 | 说明 |
|------|------|
| 输出直接传递 | 不解析、不分类 |
| 无摘要层 | 全部或无 |
| 无高级模式集成 | 与 /status_json 门控独立 |
| 无结构化数据 | 纯文本 |

---

## 4. Web Doctor 路径

### 路由注册

| 属性 | 值 |
|------|-----|
| 路由 | `/doctor` (GET, POST) |
| 装饰器 | `@require_login` |
| 处理器 | `doctor()`（web/app.py:768） |

### 执行流程

```
GET /doctor
  └── render_template("doctor.html", output=None)  ← 显示空表单

POST /doctor
  ├── validate_csrf() → 失败则 abort(403)
  ├── run_nanobk(config, ["doctor"], timeout=config.command_timeout)
  │     └── subprocess.run([nanobk_cli, "doctor"], capture_output=True, text=True)
  │           └── bin/nanobk doctor → installer/doctor.sh
  ├── output = safe_output(result.stdout or result.stderr)
  ├── if result.code != 0: output = "(exit code: ...)\n" + output
  └── render_template("doctor.html", output=output)
```

### 模板行为

`web/templates/doctor.html`:
```html
{% extends "layout.html" %}
{% block title %}{{ t('doctor_title') }} — NanoBK{% endblock %}
{% block content %}
<h1>{{ t('doctor_title') }}</h1>
<div class="card">
  <form method="POST" action="/doctor">
    <input type="hidden" name="csrf_token" value="{{ csrf_token }}">
    <button type="submit" class="button">{{ t('doctor_run_button') }}</button>
  </form>
</div>
{% if output is not none %}
<div class="card">
  <h3>{{ t('doctor_output_title') }}</h3>
  <pre>{{ output }}</pre>
</div>
{% endif %}
{% endblock %}
```

### 安全特性

| 特性 | 状态 | 位置 |
|------|------|------|
| Login required | ✅ | `@require_login` |
| CSRF 保护 | ✅ | `validate_csrf()` |
| Redaction | ✅ | `safe_output()` → `redact_text()` |
| ANSI 剥离 | ✅ | `safe_output()` → `strip_ansi()` |
| 文本截断 | ✅ | `limit_text(12000)` |
| 无 shell=True | ✅ | `subprocess.run()` 使用列表形式 |
| 无直接 env 读取 | ✅ | 仅通过 CLI |
| 无直接 systemd/config 写入 | ✅ | 仅通过 CLI |
| i18n 包装 | ✅ | `t('doctor_title')`、`t('doctor_run_button')`、`t('doctor_output_title')` |

### 未来钩子候选

| 钩子 | 说明 |
|------|------|
| 摘要卡片在 doctor 路由/模板中 | 在 `doctor()` 中构建摘要数据，模板中渲染卡片 |
| 高级详情由现有高级模式门控 | 检查 `is_advanced_mode_enabled(session)` |
| 完整输出默认折叠 | `<details>` 标签 |

### 限制

| 限制 | 说明 |
|------|------|
| 输出直接传递 | 不解析、不分类 |
| 无摘要层 | 全部或无 |
| 无高级模式集成 | 与 status 页面高级模式独立 |
| 无结构化数据 | 纯文本 |
| `<pre>` 渲染 | 原始格式化输出 |

---

## 5. CLI Doctor 路径

### 分发路径

```
bin/nanobk doctor [--dry-run] [--json]
  └── cmd_doctor()
        ├── if --json: echo '{"ok":true,"command":"doctor","note":"JSON doctor output is planned for v1.x; raw output is text-only in v0.8"}'
        └── run_script "运行环境诊断" bash "$REPO_DIR/installer/doctor.sh"
```

### JSON 支持状态

| 属性 | 说明 |
|------|------|
| `--json` 标志 | 已解析 |
| 输出 | 占位符 JSON：`{"ok":true,"command":"doctor","note":"..."}` |
| 状态 | planned for v1.x |
| 实际诊断 | 仍为文本输出 |

### installer/doctor.sh 检查段

| 段 | 检查内容 | 输出类型 |
|----|----------|----------|
| `check_system_info` | OS 名称、内核版本、架构、是否 root | 文本（pass/fail/warn） |
| `check_required_tools` | curl/jq/python3/openssl/systemctl/ss/uuidgen/xray/hysteria/tuic-server | 文本（路径或 NOT FOUND） |
| `check_nanobk_config` | /etc/nanobk 目录、config.env 存在性、权限 | 文本（路径或 not found） |
| `check_cloudflare_admin` | /root/.nanok-cf-admin.env 存在性、ADMIN_TOKEN/ADMIN_UPDATE_URL 是否设置 | 文本（set/not set） |
| `check_systemd_services` | hysteria-server/tuic-v5-9443/xray-reality-8443/xray-trojan-2443 服务状态 | 文本（active/状态/not installed） |
| `check_ports` | 端口 443(UDP)/9443(UDP)/8443(TCP)/2443(TCP) 监听 | 文本（listening/NOT listening） |
| `check_config_files` | /etc/hysteria/config.yaml 等配置文件存在性 | 文本（路径或 not found） |
| `print_summary` | 错误/警告计数 | 文本 |

### 脚本安全特性

| 特性 | 状态 | 说明 |
|------|------|------|
| 只读 | ✅ | 脚本注释声明 "Does NOT modify any files or services" |
| set -Eeuo pipefail | ✅ | 严格错误处理 |
| 无 env 内容打印 | ✅ | 仅检查存在性/设置性，不打印值 |
| 无原始 token 输出 | ✅ | 仅检查 ADMIN_TOKEN 是否设置 |
| 直接打印路径 | ⚠️ | 打印完整路径如 /etc/nanobk、/root/.nanok-cf-admin.env |
| 直接打印端口号 | ⚠️ | 打印 443、9443、8443、2443 |
| 直接打印服务名 | ⚠️ | 打印 hysteria-server.service 等 |
| 直接打印内核版本 | ⚠️ | 打印 `uname -r` 输出 |

### 脚本读取的敏感路径

| 路径 | 读取方式 | 暴露内容 |
|------|----------|----------|
| `/etc/os-release` | `source` | OS 名称（非敏感） |
| `/etc/nanobk` | `-d` 检查 | 目录存在性 |
| `/etc/nanobk/config.env` | `-f` 检查 + `stat` 权限 | 文件存在性 + 权限模式 |
| `/root/.nanok-cf-admin.env` | `source` | 仅检查变量是否设置，不打印值 |
| `/etc/hysteria/config.yaml` | `-f` 检查 | 文件存在性 |
| `/etc/proxy-stack/*/config.json` | `-f` 检查 | 文件存在性 |

**关键发现：** 脚本 `source "$cf_env"` 读取 admin env 文件以检查变量是否设置，但不打印变量值。这是一个安全的只读检查模式。

---

## 6. 当前输出风险分类

| 输出类别 | 当前来源 | 新手摘要决策 | 高级专用决策 | 永远不允许？ | 说明 |
|----------|----------|:------------:|:------------:|:------------:|------|
| OS 名称 | doctor.sh | ✅ 可选（仅族名） | ✅ | ❌ | Ubuntu/Debian 可接受，不显示完整 PRETTY_NAME |
| 内核版本 | doctor.sh | ❌ | ✅ | ❌ | `uname -r` 过于技术化 |
| 架构 | doctor.sh | ❌ | ✅ | ❌ | `uname -m` 过于技术化 |
| 工具路径 | doctor.sh | ❌ | ✅ | ❌ | `/usr/local/bin/nanobk` 等 |
| 工具存在性 | doctor.sh | ✅ 存在/缺失 | ✅ | ❌ | "curl: OK" vs "curl: NOT FOUND" |
| 配置目录路径 | doctor.sh | ❌ | ✅ | ❌ | `/etc/nanobk` |
| 配置存在性 | doctor.sh | ✅ 存在/缺失 | ✅ | ❌ | "Config: present" vs "Config: missing" |
| 配置权限 | doctor.sh | ✅ mode 600 | ✅ | ❌ | "Permissions: secure" |
| Admin env 路径 | doctor.sh | ❌ | ✅ | ❌ | `/root/.nanok-cf-admin.env` |
| Admin env 存在性 | doctor.sh | ✅ 存在/缺失 | ✅ | ❌ | "CF admin: configured" |
| ADMIN_TOKEN 设置性 | doctor.sh | ✅ 设置/未设置 | ✅ | ❌ | "Admin token: set" |
| systemd 服务名 | doctor.sh | ❌ | ✅ | ❌ | `hysteria-server.service` |
| 服务状态 | doctor.sh | ✅ active/inactive/missing | ✅ | ❌ | "HY2: active" vs "HY2: failed" |
| 端口号 | doctor.sh | ❌ | ✅ | ❌ | 443、9443、8443、2443 |
| 端口监听状态 | doctor.sh | ✅ listening/not listening | ✅ | ❌ | "HY2 port: OK" vs "HY2 port: not listening" |
| 配置文件路径 | doctor.sh | ❌ | ✅ | ❌ | `/etc/hysteria/config.yaml` |
| 配置文件存在性 | doctor.sh | ✅ 存在/缺失 | ✅ | ❌ | "HY2 config: present" |
| 协议名 | doctor.sh | ✅ | ✅ | ❌ | HY2/TUIC/Reality/Trojan |
| 错误/警告计数 | doctor.sh | ✅ | ✅ | ❌ | "2 errors, 1 warning" |
| 原始 token | — | ❌ | ❌ | ✅ | 永远不允许 |
| 原始 private key | — | ❌ | ❌ | ✅ | 永远不允许 |
| 原始 env 内容 | — | ❌ | ❌ | ✅ | 永远不允许 |
| 原始 IP/domain/URL | — | ❌ | ❌ | ✅ | redaction 保护 |
| workers.dev | — | ❌ | ❌ | ✅ | redaction 保护 |
| subscription URL/path | — | ❌ | ❌ | ✅ | redaction 保护 |

---

## 7. 数据源审计

### 选项 A: 解析现有文本输出

| 属性 | 评估 |
|------|------|
| 可行性 | ⚠️ 中等 — 输出格式由 pass/fail/warn 函数控制，相对稳定 |
| 安全性 | ✅ — Bot/Web safe_output() 已脱敏 |
| 脆弱性 | ⚠️ 高 — 依赖 `✓`/`✗`/`!` 前缀和文本模式 |
| 所需变更 | 无 CLI 变更 |
| 推荐角色 | 仅作为最后手段或最小实现 |

**解析模式示例（基于源码）：**

- `  ✓ OS: Ubuntu 24.04.1 LTS` → pass + "OS: ..."
- `  ✗ curl: NOT FOUND` → fail + "curl: ..."
- `  ! Config directory not found: /etc/nanobk` → warn + "Config ..."
- `  ✓ HY2 :443 (udp): listening` → pass + port check
- `  ✗ hysteria-server.service: inactive` → fail + service status

**风险：** Unicode 字符 `✓`/`✗`/`!` 可能因终端编码变化。ANSI 颜色代码已被 strip_ansi() 移除。文本模式依赖英文输出，i18n 后可能变化。

### 选项 B: 未来 nanobk doctor --json

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 — 已有 --json 占位符 |
| 安全性 | ✅ — 可设计安全 schema |
| 脆弱性 | ✅ 低 — 结构化数据 |
| 所需变更 | 需要 CLI 变更（单独规划） |
| 推荐角色 | 长期首选 |

**当前状态：** `--json` 输出占位符，实际诊断仍为文本。需要单独规划 CLI 级别安全 doctor 摘要命令。

### 选项 C: 复用 nanobk --json status

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 — 已存在 |
| 安全性 | ✅ — 已脱敏 |
| 脆弱性 | ✅ 低 — JSON schema 稳定 |
| 所需变更 | 无 |
| 推荐角色 | 补充信息源 |

**限制：** status JSON 不包含 doctor 特有检查（工具存在性、配置权限、端口监听）。可作为补充但不能完全替代 doctor。

### 选项 D: 混合方案

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 高 |
| 安全性 | ✅ |
| 脆弱性 | ⚠️ 中等 |
| 所需变更 | Bot/Web 逻辑 |
| 推荐角色 | v1.9.36/37 实现策略 |

**方案：** 使用 `nanobk --json status` 获取服务/配置状态，对 doctor 特有检查使用安全的静态映射或有限文本解析。

### 选项 E: 仅静态引导

| 属性 | 评估 |
|------|------|
| 可行性 | ✅ 最高 |
| 安全性 | ✅ 最高 |
| 脆弱性 | ✅ 无 |
| 所需变更 | 无 |
| 推荐角色 | 不推荐 — 无实际诊断 |

### 推荐

- **v1.9.35：** 定义 fixture 合约测试，不解析真实输出。
- **v1.9.36/37：** 最小实现使用选项 D（status JSON + 有限安全映射）。
- **长期：** 优先选项 B（future doctor --json）。
- **不推荐：** 纯文本解析（选项 A）作为长期方案。

---

## 8. 推荐摘要合约方向

### v1.9.35 应测试的内容

**输入 fixtures：**

| Fixture | 说明 |
|---------|------|
| 健康状态 | 所有服务 active，配置存在，Cloudflare verified |
| 部分服务 | 部分 active，部分 failed |
| 缺失配置 | config.env 缺失，profile 缺失 |
| Cloudflare 缺失 | admin env 不存在，subscription unknown |
| 失败 doctor 输出 | 包含错误的假 doctor 文本 |
| 含密钥假输出 | 包含假 token/IP/URL 的 doctor 文本 |
| 未知/无效输出 | 空输出或异常格式 |

**预期摘要结构：**

```
doctor_summary = {
    "overall": "healthy" | "failed" | "unknown",
    "control_plane": "ok" | "error",
    "cli_available": true | false,
    "config": "present" | "missing" | "unknown",
    "services": {
        "hy2": "active" | "inactive" | "missing" | "unknown",
        "tuic": ...,
        "reality": ...,
        "trojan": ...
    },
    "cloudflare": "configured" | "missing" | "unknown",
    "subscription": "verified" | "configured" | "unknown",
    "security": "ok" | "warning" | "unknown",
    "next_step": "...",
    "full_available": true  # 高级模式可查看完整输出
}
```

**规则：**

- 永远不输出原始 IP/domain/URL/token/private key
- unknown 保持 unknown
- failed 保持 failed
- dry-run/planned/manual_pending 不显示为成功
- 完整输出仅限高级模式

---

## 9. Bot 未来实现说明

| 说明 | 详情 |
|------|------|
| 不直接解析真实 env/文件 | 通过 CLI 或未来安全辅助函数 |
| /doctor OFF 返回摘要 | 如后续实现选项 C |
| 高级 ON 可显示完整脱敏输出 | 或提供 /doctor_full |
| 完整输出必须保持脱敏和警告保护 | 与 /status_json 一致 |
| zh/en 标签 | 复用 i18n |
| Owner-only 保持 | 不变 |

**钩子位置：** `cmd_doctor()` 中 `safe_output(output)` 之后、`reply_text()` 之前。

---

## 10. Web 未来实现说明

| 说明 | 详情 |
|------|------|
| 不直接解析真实 env/文件 | 通过 CLI 或未来安全辅助函数 |
| Doctor 页面默认摘要卡片 | 新增卡片渲染 |
| 高级详情门控/折叠 | 复用现有高级模式 |
| 完整输出必须保持脱敏和警告保护 | 与 status 页面 Raw JSON 一致 |
| /api/status 不变 | 不影响 |
| CSRF/login 保持 | 不变 |

**钩子位置：** `doctor()` 路由中 `safe_output()` 之后、`render_template()` 之前。

---

## 11. 安全决策

**当前 doctor 路径作为维护者诊断是可接受的，但不适合作为新手产品化 UX。**

当前路径安全特性：
- ✅ Bot owner-only
- ✅ Web login + CSRF
- ✅ 两者都通过 safe_output() 脱敏
- ✅ 无 shell=True
- ✅ 无直接 env 读取
- ✅ 无直接 systemd/config 写入

**尚未批准：**

- ❌ 直接实现
- ❌ 解析实时脏输出
- ❌ doctor --json 实现
- ❌ CLI 行为变更
- ❌ production status wrapper
- ❌ dirty VPS status wrapping
- ❌ raw subscription delivery
- ❌ tag/release

---

## 12. 就绪决策

**A. READY FOR DOCTOR SUMMARY CONTRACT / FIXTURE TESTS**

约束：
- 仅 fixture 测试
- 无运行时变更
- 无真实 doctor 执行
- 无 CLI 行为变更
- 无 release/tag

---

## 13. 提议下一步

**v1.9.35 — Doctor Summary Contract / Fixture Tests**

说明：
- 先定义假输入和预期安全摘要
- 证明 redaction 和诚实性再改变 Bot/Web 运行时
- v1.9.35 不包含实现

---

## 14. 测试/检查运行

| 检查 | 结果 |
|------|------|
| `git status -sb` | ✅ clean |
| `git diff --check` | ✅ clean |
| `git diff --cached --check` | ✅ clean |
| 静态 grep 检查变更文件 | ✅ 无禁止模式 |

**运行时测试：** 未在此审计/文档周期重新运行。

---

## 15. 已知限制

| 限制 | 说明 |
|------|------|
| 仅源码审计 | 未执行真实 doctor |
| 未验证真实 VPS/Cloudflare | 无真实环境测试 |
| 当前输出示例可能因主机而异 | 不同 VPS 可能有不同输出 |
| 未来 JSON 钩子可能需要单独 CLI 规划 | 不在 v1.9.x 范围 |
| Bot/Web 实现仍待定 | v1.9.36/37 |
| doctor.sh 直接打印路径/端口/服务名 | 对新手过于技术化 |
| 文本解析依赖输出格式 | 脆弱性风险 |

---

## 16. Guardrails

| # | 约束 | 状态 |
|---|------|------|
| 1 | 无 install.sh 行为变更 | ✅ |
| 2 | 无 bin/nanobk 行为变更 | ✅ |
| 3 | 无 installer/doctor.sh 行为变更 | ✅ |
| 4 | 无协议模板变更 | ✅ |
| 5 | 无 Worker 变更 | ✅ |
| 6 | 无 rotate sync 变更 | ✅ |
| 7 | 无直接 Bot/Web 写入 configs/systemd/secrets | ✅ |
| 8 | 无 raw env 读取 | ✅ |
| 9 | 无 production status wrapper | ✅ |
| 10 | 无 dirty VPS status wrapping | ✅ |
| 11 | 无 operation-log full rollout | ✅ |
| 12 | 无 raw subscription 交付 | ✅ |
| 13 | 无 tag/release | ✅ |
