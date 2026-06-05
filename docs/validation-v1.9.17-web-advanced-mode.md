# v1.9.17 — Web Advanced Mode Minimal Implementation Validation

> 验证类型：Web 高级诊断模式最小实现
> 日期：2026-06-05
> 基线 commit：`a34ce698b3d3c3778125687aeeb4e85b9e44ae17`
> 基线信息：`feat: add bot advanced mode`

---

## 1. 本轮目标与结论

**v1.9.17 实现了 Web 端最小高级诊断模式：**

- ✅ Session 级状态（不持久化）
- ✅ `POST /advanced/on` 启用（CSRF 保护）
- ✅ `POST /advanced/off` 禁用（CSRF 保护）
- ✅ `GET /advanced/status` 查询
- ✅ 15 分钟自动过期
- ✅ 登出/Session 过期自动重置
- ✅ 警告文案
- ✅ 未门控 Raw JSON
- ✅ 未改变 `/api/status`
- ✅ 未修改 Bot
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

---

## 2. Preflight 结果

| 检查项 | 结果 |
|--------|------|
| Flask session 已使用 | ✅ `session.get("authenticated")` |
| 登录/Session 结构清晰 | ✅ `session["authenticated"] = True` |
| Logout 路由存在 | ✅ `POST /logout` + `session.clear()` |
| CSRF token 用于 POST | ✅ `validate_csrf()` |
| POST 表单模式存在 | ✅ Rotate 使用 POST + CSRF |
| 可添加 toggle 不改变 auth 模型 | ✅ |
| 可避免 URL query 参数 | ✅ |
| 可避免持久化存储 | ✅ |

**结论：实现安全，无需重写 auth 模型。**

---

## 3. 变更路径

| 文件 | 变更 |
|------|------|
| `web/app.py` | 新增高级模式 helper + 路由 + self-test 更新 |
| `web/templates/status.html` | 新增高级模式控制区域 |
| `web/static/style.css` | 新增 `.badge-ok`、`.button-warn` 样式 |
| `tests/web-advanced-mode-v1.9.17.py` | 新增测试 |
| `docs/validation-v1.9.17-web-advanced-mode.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.17 条目 |
| `docs/roadmap.md` | 新增 v1.9.17 版本行 |

---

## 4. Web 高级模式行为

### Helper 函数

| 函数 | 说明 |
|------|------|
| `_get_advanced_mode(session)` | 从 session 获取状态，自动清理过期 |
| `enable_advanced_mode(session)` | 启用，写入 session |
| `disable_advanced_mode(session)` | 禁用，清除 session key |
| `is_advanced_mode_enabled(session)` | 检查是否启用且未过期 |
| `advanced_mode_remaining_seconds(session)` | 返回剩余秒数 |

### 路由

| 路由 | 方法 | 说明 |
|------|------|------|
| `/advanced/on` | POST | 启用高级模式，重定向到 Status |
| `/advanced/off` | POST | 禁用高级模式，重定向到 Status |
| `/advanced/status` | GET | 返回 JSON 状态 |

### Session 状态

```python
session["advanced_mode"] = {
    "enabled_at": time.time(),
}
```

### UI

- Status 页面新增 "Advanced Diagnostics" 卡片
- 禁用时：显示警告 + 启用按钮
- 启用时：显示状态 + 禁用按钮
- 警告文案说明脱敏、15 分钟过期、不要分享

---

## 5. 过期/持久化策略

| 特性 | 策略 |
|------|------|
| TTL | 15 分钟（`ADVANCED_MODE_TTL_SECONDS = 900`） |
| 存储 | Flask session only |
| 持久化 | 无（不写磁盘/env/config/db） |
| 登出 | `session.clear()` 自动清除 |
| Session 过期 | 自动失效 |
| URL query | 不支持 |

---

## 6. Raw JSON / API 边界

| 项 | 状态 |
|----|------|
| Raw JSON details | ✅ 仍存在，未隐藏 |
| Raw JSON 可见性 | ✅ 未改变 |
| Raw JSON 未门控 | ✅ 不依赖高级模式 |
| `/api/status` | ✅ 仍可用，返回 redacted JSON |
| `/api/status` 未门控 | ✅ 不依赖高级模式 |
| Redaction 规则 | ✅ 未改变 |

---

## 7. Session/CSRF/Rotate 边界

| 项 | 状态 |
|----|------|
| 登录模型 | ✅ 未重写 |
| Session 模型 | ✅ 未重写，仅添加 advanced_mode key |
| CSRF 机制 | ✅ 未改变 |
| Rotate 行为 | ✅ 未改变 |
| `run_nanobk` | ✅ 未改变 |

---

## 8. 测试运行

| 测试 | 结果 |
|------|------|
| Web self-test | ✅ All passed |
| `tests/web-advanced-mode-v1.9.17.py` | ✅ All passed |
| `bash tests/bot-cli-mock.sh` | ✅ All passed |
| `bash tests/web-panel-mock.sh` | ✅ All passed |
| `bash tests/bot-web-command-allowlist-v1.9.4.sh` | ✅ All passed |
| `bash tests/redaction-address-class-v1.9.5.sh` | ✅ All passed |
| `python3 tests/redaction-helper-v1.9.6.py` | ✅ All passed |
| `python3 tests/bot-redaction-helper-integration-v1.9.7.py` | ✅ All passed |
| `python3 tests/web-redaction-helper-integration-v1.9.8.py` | ✅ All passed |
| `python3 tests/redaction-integration-checkpoint-v1.9.9.py` | ✅ All passed |
| `python3 tests/bot-safe-status-summary-v1.9.10.py` | ✅ All passed |
| `python3 tests/web-safe-status-cards-v1.9.11.py` | ✅ All passed |
| `python3 tests/bot-status-json-warning-v1.9.13.py` | ✅ All passed |
| `python3 tests/web-raw-json-warning-v1.9.14.py` | ✅ All passed |
| `python3 tests/bot-advanced-mode-v1.9.16.py` | ✅ All passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ All passed |

---

## 9. 已知限制

| 限制 | 说明 |
|------|------|
| 无真实 Web session | 未启动 Web 服务器 |
| 无真实 VPS/Cloudflare 状态 | 仅使用 fake fixture |
| 高级模式未门控 Raw JSON | 本版本仅添加状态/toggle |
| Bot 高级模式已存在 | v1.9.16，未变更 |
| 订阅交付仍阻塞 | 需独立安全设计 |
| Production status wrapper 仍阻塞 | 未批准 |
| Dirty VPS status wrapping 仍阻塞 | 未批准 |

---

## 10. 下一步

**推荐：v1.9.18 — Advanced Diagnostics Mode Checkpoint**

Bot 和 Web 高级模式均已实现。下一步应进行检查点，确认一致性，并决定是否可以开始门控 Raw JSON。

需 ChatGPT 审核后实施。
