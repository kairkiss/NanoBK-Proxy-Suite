# v1.9.0-planning — Bot/Web Control Plane Productization Scope Proposal

## 1. 当前状态判断

v1.7.27 是当前稳定部署基线。这个基线的价值在于 Full Wizard 阶段机、严格编号菜单、输入校验、诚实 Summary、失败恢复命令、既有部署恢复、Cloudflare nanok/nanob verified Summary、admin env 自动安装、rotate sync 稳定性、四协议 VPS 部署链、Reality 私钥不进入 `profile.current.json`、私密 env 权限 600，以及 Bot/Web 作为控制面而不是直接配置写入器。

v1.8.45 是 v1.8 closeout decision。v1.8 已完成 CLI 默认产品化界面、紧凑模式、Plain/CI 模式、UI=0 兼容模式、stage cards、品牌视觉、token safety copy、recovery copy、visual acceptance docs、focused test strategy、operation-log redaction groundwork、hidden output groundwork、verbose redacted output groundwork、chmod 600 logs、failure propagation、harmless real command pilots、status mock/oplog proof、no fake success 和 secret safety gates。

v1.8 功能开发应在 v1.8.45 后停止。继续推进 production status wrapper、dirty VPS status wrapping、`NANOBK_OPLOG_STATUS_PILOT`、`run_cmd`/`run_critical_step` 全量 rollout、真实 deploy/healthcheck/Cloudflare verify/rotate sync wrapping，会扩大风险并偏离 v1.9 的产品价值。

v1.9 应从 Bot/Web control-plane productization planning 开始，而不是直接实现。v1.9.0-planning 只定义范围、边界、用户体验、状态模型、安全确认、allowlist、redaction/logging policy 和测试策略。

本文件不是 release tag 建议，不批准 tag，不批准发布。

## 2. v1.9 总目标

v1.9 定义为：Bot/Web Control Plane Productization。

Telegram Bot 的定位是手机控制中心。它应让用户在手机上看懂 VPS、Cloudflare、订阅、服务健康、最近操作和恢复建议，但不能把 Telegram 变成底层配置写入器。

Web Panel 的定位是浏览器 dashboard。它应让用户在本地浏览器或受保护访问通道中查看状态、执行受控动作、理解失败原因、获取恢复提示，但不能把 Web 后台变成直接编辑配置、systemd 或 secrets 的面板。

Bot 和 Web 都是 control planes only：

- 必须调用 `nanobk` CLI。
- 不得直接写配置文件。
- 不得直接写 systemd。
- 不得直接写 secrets。
- 不得绕开 CLI 的状态、确认、失败传播和安全边界。
- CLI 失败时，Bot/Web 必须显示失败或 unknown/manual_pending，而不是自行修复或假装成功。

## 3. v1.9 非目标

v1.9 不做以下事项：

- 不重写部署核心。
- 不重写 installer。
- 不修改 VPS 协议模板。
- 不修改 Cloudflare Worker core。
- 不修改 rotate sync。
- 不实现 production status wrapper。
- 不做 dirty VPS status wrapping。
- 不做 operation-log full rollout。
- 不允许 Bot/Web 直接写 configs/systemd/secrets。
- 不恢复 v1.8 未批准的 status pilot。
- 不 tag。
- 不 release。

## 4. Bot 当前状态审计

实际仓库结构：

- `bot/nanobk_bot.py` 是 Python Telegram Bot 主入口，文件头标注 v1.1.0。
- `bot/requirements.txt` 使用 `python-telegram-bot>=21,<22`。
- `bot/run.sh` 负责 venv 和启动。
- `bot/systemd/nanobk-telegram-bot.service.example` 是 systemd 示例。
- `bot/README.md` 说明 Bot 只调用 `nanobk` CLI，不直接读写 secrets、profiles、configs 或 systemd services。

当前命令/菜单形态：

- `/start`
- `/help`
- `/status`
- `/status_json`
- `/doctor`
- `/rotate_all`
- `/rotate_hy2`
- `/rotate_tuic`
- `/rotate_reality`
- `/rotate_trojan`
- `/cancel`
- `/confirm_rotate_*`

当前没有按钮式 UX，主要是文本命令。`/start` 只返回 Bot online 和 `/help` 提示，尚未形成“小白控制中心”入口。

当前调用方式：

- `run_nanobk(config, args, timeout)` 使用 `subprocess.run(cmd, capture_output=True, text=True, timeout=...)`。
- `cmd` 以 list 形式构造，没有 shell 字符串执行。
- 支持 `NANOBK_CLI` 和 `NANOBK_REPO_DIR`。
- `/status` 调用 `nanobk --json status`。
- `/status_json` 调用 `nanobk --json status` 并展示 redacted raw output。
- `/doctor` 调用 `nanobk doctor`。
- rotate 确认后调用 `nanobk rotate <protocol> --yes`。

当前确认流：

- rotate 有 pending confirmation，默认 120 秒过期。
- 确认命令必须匹配 pending action。
- `NANOBK_BOT_DRY_RUN=true` 时 rotate 只显示 would execute。
- 目前确认模型主要覆盖 rotate，尚未分层覆盖 Cloudflare、repair、healthcheck、订阅刷新等未来高风险动作。

当前 redaction：

- `strip_ansi()` 去除 ANSI。
- `redact_text()` 覆盖 Telegram bot token、token/password/private key/secret 类 key-value、长 base64/hex 风险串。
- `safe_output()` 统一 strip/redact/limit。

明显风险或未知：

- `format_status()` 当前会显示 `domain`、`vpsIp`、`geo`。这对产品化 Bot 不够安全，v1.9 应要求地址、域名、订阅入口和 Worker 地址默认脱敏或摘要化。
- `/status_json` 仍然是“raw JSON status”的用户命令，即使经过基础 redaction，也可能暴露非 token 类敏感信息，例如 VPS IP、域名、Cloudflare route URL。v1.9 应考虑移除、隐藏、仅调试可见，或改为 safe JSON。
- Bot redaction 主要是文本正则，尚未证明覆盖所有 URL、IP、订阅入口、Worker 默认域名、profile 字段。
- 未发现 Bot 直接写 `/etc/nanobk`、systemd 或 secrets 的代码路径；本次只做静态阅读，未连接真实 Telegram，也未运行真实 status。

## 5. Web 当前状态审计

实际仓库结构：

- `web/app.py` 是 Flask Web Panel 主入口，文件头标注 v1.2.1。
- `web/requirements.txt` 使用 Flask 相关依赖。
- `web/run.sh` 负责 venv 和启动。
- `web/templates/` 包含 `layout.html`、`login.html`、`index.html`、`status.html`、`doctor.html`、`rotate.html`。
- `web/static/style.css` 是当前样式。
- `web/systemd/nanobk-web-panel.service.example` 是 systemd 示例。
- `web/README.md` 说明 Web Panel 默认绑定 `127.0.0.1:8080`，只调用 `nanobk` CLI，不直接读写 secrets、profiles、configs 或 systemd services。

当前 framework/runtime：

- Python Flask。
- Token login。
- Flask session。
- CSRF token helpers。
- 默认 host 是 `127.0.0.1`。
- 默认 rotate dry-run 为 true。

当前 pages/routes/actions：

- `GET/POST /login`
- `POST /logout`
- `GET /`
- `GET /status`
- `GET /api/status`
- `GET/POST /doctor`
- `GET /rotate`
- `POST /rotate/request`
- `POST /rotate/confirm`
- `POST /rotate/cancel`
- `GET /healthz`

当前调用方式：

- `run_nanobk(config, args, timeout)` 使用 `subprocess.run(cmd, capture_output=True, text=True, timeout=...)`。
- `cmd` 以 list 形式构造，没有 shell 字符串执行。
- Dashboard、Status、API status 调用 `nanobk --json status`。
- Doctor POST 调用 `nanobk doctor`。
- Rotate confirm 调用 `nanobk rotate <protocol> --yes`，dry-run 时只显示 would execute。

当前确认流：

- Rotate 使用 session pending confirmation，默认 120 秒过期。
- POST 表单带 CSRF。
- 当前确认模型主要覆盖 rotate；doctor 是 POST 触发但不属于高风险二次确认。

当前 redaction：

- `strip_ansi()` 去除 ANSI。
- `redact_text()` 覆盖 token/password/private key/secret 和长串。
- `redact_json()` 递归按敏感 key 字段脱敏。
- `/api/status` 使用 `redact_json()`。
- `format_status()` 输出 `raw_json`，但只对敏感 key/value 做脱敏。

明显风险或未知：

- Dashboard 和 Status 当前展示 `domain`、`vps_ip`、`geo`。这对本地面板比 Bot 风险低，但仍不应默认暴露给截图、日志或 API response。
- `raw_json` details 仍可能包含 VPS IP、域名、route URL、path 等非 token 类敏感字段。
- Web redaction 对敏感 key 较强，但对地址类、Worker 默认域名、订阅入口和完整 URL 的产品化策略仍未完整定义。
- 当前 UI 是基础卡片和链接，不是面向新手的完整 dashboard 信息架构。
- 未发现 Web 直接写 `/etc/nanobk`、systemd 或 secrets 的代码路径；本次只做静态阅读，未启动 Web server，也未运行真实 status。

## 6. Bot 目标用户体验

目标入口：

```text
/start
NanoBK 控制中心
```

建议按钮：

- VPS 状态
- Cloudflare 状态
- 订阅状态
- 服务健康检查
- 最近操作日志
- 安全恢复命令
- Web Panel 地址
- 帮助

输出原则：

- 默认短摘要，适合手机屏幕。
- 每个结果必须标明状态类别和来源。
- 不展示 raw IP。
- 不展示 raw token。
- 不展示 raw domain。
- 不展示 raw 订阅 URL。
- 不展示 raw private key。
- 不展示 raw Cloudflare Worker 地址。
- 失败输出也必须经过 redaction。
- 对 unknown/skipped/dry-run/manual_pending 使用诚实文字，不转成成功。

建议 Bot 文案形态：

```text
VPS 状态
状态：healthy
四协议：4/4 configured
服务：3 active, 1 unknown
说明：状态来自 nanobk CLI，敏感地址已隐藏。
```

## 7. Web 目标用户体验

目标是 browser dashboard，不是脚本输出页面。首屏建议包含：

- VPS Card
- Cloudflare Card
- Bot Card
- Web Card
- Subscription Card
- Recent Operations
- Recovery Tips

状态颜色必须保持诚实语义：

- green: verified / healthy
- yellow: manual_pending / planned
- gray: skipped / unknown
- red: failed

展示原则：

- 不把 unknown 显示成绿色。
- 不把 skipped 显示成绿色。
- 不把 dry-run 显示成已完成。
- Card 应说明状态来源，例如 `nanobk status`、mock fixture、manual record 或 not checked。
- Raw JSON 默认不应面向普通用户展示；如果保留，应只显示 safe JSON，并隐藏地址类敏感字段。
- Recovery Tips 应给出可复制但安全的恢复命令，不包含真实 token、真实地址或真实订阅入口。

## 8. 状态展示模型

Bot/Web 应使用统一安全状态类别：

- `installed`: 已安装或配置文件存在，但尚不代表服务健康。
- `healthy`: 本地服务或检查结果健康。
- `verified`: 已通过明确验证，例如 Cloudflare verified Summary 或真实检查成功。
- `planned`: 规划中、未执行。
- `dry-run`: 只模拟或预览，没有写入真实环境。
- `manual_pending`: 需要用户手动完成，例如填写 token、确认 DNS、配置 Cloudflare 权限。
- `skipped`: 用户选择跳过，或当前模式不包含此阶段。
- `failed`: 命令失败、校验失败、依赖缺失或服务异常。
- `unknown`: 未检查、无法读取、输出不可解析或安全策略阻止展示。

展示规则：

- `verified` 和 `healthy` 才能使用绿色。
- `installed` 不能自动等同于 `healthy`。
- `dry-run` 不能自动等同于 `installed`。
- `manual_pending` 必须给出下一步。
- `skipped` 必须保持中性。
- `failed` 必须展示 redacted failure reason 和安全恢复建议。
- `unknown` 必须解释“未检查/不可确认”，不能补写推测结果。

## 9. 安全确认机制

v1.9 只定义确认模型，不批准高风险实现。

确认等级：

- Safe read-only actions: direct
- Medium-risk actions: simple confirmation
- High-risk actions: two-step confirmation

Safe read-only actions 示例：

- 查看版本。
- 查看帮助。
- 查看已脱敏状态摘要。
- 查看帮助/恢复建议。

Medium-risk actions 示例：

- 运行只读 doctor。
- 刷新 dashboard status。
- 查看最近操作日志摘要。
- 获取 Web Panel 访问提示。

High-risk actions 示例：

- rotate token。
- restart services。
- rerun healthcheck。
- refresh 订阅。
- Cloudflare related operations。
- repair actions。

High-risk 两步确认建议：

- 第一步：说明将调用的 `nanobk` CLI allowlist 命令、影响范围、可能中断的服务、预计耗时。
- 第二步：用户显式确认，例如 Bot 中二次按钮/确认词，Web 中二次确认页和 CSRF。
- 执行后：必须展示 redacted result、exit code、状态是否 verified/failed/unknown，以及恢复建议。

## 10. Bot/Web command allowlist principle

Bot/Web 只能调用已批准的 `nanobk` CLI 命令。不能接受用户输入拼接任意 shell，不能提供 raw command box，不能把 Web/Bot 变成远程 root shell。

初始概念 allowlist：

- `nanobk --version`
- `nanobk --help`
- `nanobk status`，仅当输出已安全脱敏并且不会读取未批准的真实路径。
- `nanobk --json status`，仅当包装层能保证 safe JSON，不直出 raw 字段。
- `nanobk doctor`，仅当输出已安全脱敏。
- `nanobk` recovery/help 类命令，如果 CLI 已存在且是只读/安全输出。
- Bot/Web 专用 status 命令，如果未来存在且经过 redaction 和 mock/fixture proof。

denylist 类别：

- raw shell execution。
- Bot/Web 直接调用 `systemctl`。
- Bot/Web 直接写 `/etc/nanobk`。
- Bot/Web 直接读取 env 内容。
- Bot/Web 直接写 Cloudflare Worker/env。
- Bot/Web 直接写 secrets。
- 用户可控参数绕过 allowlist。
- 任意文件浏览、任意日志读取、任意命令执行。

## 11. Redaction and logging policy

Bot/Web 的屏幕输出、日志输出和 API response 必须先 redaction，再展示或保存。

禁止展示：

- raw secret。
- raw env。
- raw Cloudflare Worker 默认域名。
- raw 订阅 URL。
- Reality private key。
- raw token。
- raw VPS IP。
- raw domain。

失败输出同样必须脱敏。不能因为命令失败就直出 stderr/stdout。

v1.8 的 operation-log groundwork 可以在安全位置复用，但 v1.9 规划阶段不得扩展到真实 deploy、healthcheck、Cloudflare verify、rotate sync。operation-log 可作为 future design input，不作为本规划的实现许可。

地址类脱敏建议：

- IP 显示为 `[REDACTED_IP]` 或只显示区域/协议数量。
- 域名显示为 `[REDACTED_DOMAIN]` 或只显示“已配置”。
- URL 显示为 `[REDACTED_URL]`。
- token 显示为 `present`、`missing` 或短 fingerprint。
- private key 永远不显示 fingerprint 以外的内容；必要时仅显示 `present`。

## 12. Testing strategy

继续使用现有 tiered strategy。

Tier 0 static grep/docs/version checks：

- 文档包含 v1.9 scope、非目标、allowlist、denylist。
- Bot/Web 代码中不存在 shell 执行开关。
- Bot/Web 代码中不存在直接写 `/etc/nanobk`、systemd、secrets 的路径。
- 文档和 changed files 不包含明显 raw secret pattern。
- 不出现读取真实 env 内容的示例。
- 不出现未批准 v1.8 status pilot。

Tier 1 focused fast tests：

- Bot menu rendering mock。
- Web dashboard rendering mock。
- command allowlist 单元测试。
- forbidden direct writes 静态测试。
- redaction helper 单元测试。
- honest status display 单元测试。
- confirmation flow mock。
- failure display mock。
- no env content read pattern。
- no raw secret pattern。

Tier 2 related regression：

- `tests/bot-cli-mock.sh`
- `tests/web-panel-mock.sh`
- `tests/unified-beginner-flow.sh`
- `tests/unified-installer-safety.sh`
- v1.8 status fixture/redaction focused tests，限 mock/fixture。

Tier 3 full/manual review：

- Full Wizard dry-run visual review。
- Bot/Web manual UX review with fake/mock data。
- Web local-only binding review。
- Security checklist review。
- No real VPS status。
- No real Cloudflare commands。
- No healthcheck。
- No rotate sync。
- No tag/release。

## 13. Suggested v1.9 version roadmap

建议小步推进：

- v1.9.0-planning: 本 scope proposal。
- v1.9.1: Bot/Web current-state audit，补充安全差距和现有代码证据。
- v1.9.2: Bot UX/menu spec，定义 `/start` 控制中心和按钮流，不执行真实动作。
- v1.9.3: Web dashboard UX spec，定义 card、状态颜色、safe raw JSON 策略。
- v1.9.4: command allowlist spec/tests，先测试 allowlist/denylist，不扩大命令面。
- v1.9.5: redaction layer audit/tests，覆盖 token、key、IP、domain、URL、Worker 默认域名、订阅入口。
- v1.9.6: Bot confirmation flow mock/skeleton，仅 mock/safe flow，不批准高风险动作落地。
- v1.9.7: Web confirmation flow mock/skeleton，仅 mock/safe flow，不批准高风险动作落地。
- v1.9.8: safe status cards polish，使用 mock/fixture 或已批准 safe CLI 输出。
- v1.9.9: v1.9 checkpoint，决定是否进入更高风险实现或继续补测试。

根据当前 repo 发现，v1.9.1 和 v1.9.5 应特别关注：Bot/Web 对 `nanobk --json status` 的 raw 字段展示、地址类脱敏、`/status_json` 与 Web raw_json 的产品化边界。

## 14. 推迟到 v2.0 的事项

以下事项不应在 v1.9 执行：

- multi-user RBAC。
- multi-VPS management。
- SaaS control center。
- full database-backed Web panel。
- real-time WebSocket logs。
- production status wrapper。
- dirty VPS status wrapping。
- full operation-log rollout。
- graphical protocol editor。
- graphical Cloudflare Worker editor。
- direct secrets editing。
- public internet exposure model。
- advanced audit trail with persistent database。

## 15. Acceptance criteria

v1.9 成功标准：

- Bot/Web 更清晰、更安全、更适合新手。
- 状态展示诚实，不把 unknown/skipped/dry-run/manual_pending 伪装成 success。
- 不泄露 secret。
- 不泄露 raw IP/domain/URL/订阅入口/private key。
- Bot/Web 不直接写 configs/systemd/secrets。
- 不改部署核心。
- 不改 installer 部署逻辑。
- 不改 VPS 协议模板。
- 不改 Cloudflare Worker core。
- 不改 rotate sync。
- 不复活 v1.8 status pilot。
- 不 tag。
- 不 release。
- 测试范围小、快、诚实，优先 mock/fixture。
- 未来实现任务小步、可 review、可回滚。
