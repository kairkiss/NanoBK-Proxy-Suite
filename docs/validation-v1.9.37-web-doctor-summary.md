# v1.9.37 — Web Doctor Summary Minimal Implementation Validation

> 验证类型：Web Doctor 摘要最小实现
> 日期：2026-06-05
> 基线 commit：`8df4f136199aa346d83c093c8c087e14629072b5`
> 基线信息：`feat: add bot doctor summary`

---

## 1. 本轮目标与结论

**v1.9.37 实现了 Web /doctor 新手友好摘要：**

- ✅ Web /doctor 默认显示安全新手摘要卡片
- ✅ 无 Bot 运行时变更
- ✅ 无 CLI 行为变更
- ✅ 无安装器变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

**结论：Web /doctor 现在从 `nanobk --json status` 构建安全摘要，默认不显示完整技术输出。高级模式 ON 时附加脱敏完整诊断，折叠显示。符合 v1.9.35 Doctor Summary 合约。**

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `web/app.py` | 新增 doctor 摘要构建函数、更新 doctor 路由、更新 self-test |
| `web/i18n.py` | 新增 25 个 doctor 摘要 i18n 键 |
| `web/templates/doctor.html` | 重写为摘要卡片 + 高级模式完整诊断 |
| `tests/web-doctor-summary-v1.9.37.py` | 新增测试（164 项） |
| `docs/validation-v1.9.37-web-doctor-summary.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.37 条目 |
| `docs/roadmap.md` | 新增 v1.9.37 行 |

---

## 3. Doctor 摘要构建器

### 辅助函数

| 函数 | 说明 |
|------|------|
| `build_doctor_summary(data, *, full_available=True)` | 从 status JSON 构建摘要 dict，符合 v1.9.35 schema |
| `_infer_doctor_overall(data)` | 从服务状态推断 overall（服务优先，ok 字段兜底） |
| `_infer_doctor_cloudflare(data)` | 推断 Cloudflare 状态 |
| `_infer_doctor_subscription(data)` | 推断订阅状态 |
| `_infer_doctor_security(data)` | 推断安全状态 |
| `_doctor_next_step(summary)` | 从摘要字段确定下一步 |

### 输入源

- 使用 `nanobk --json status` 的结构化 JSON
- 不解析 doctor.sh 文本输出
- 不读取 env 文件

### 摘要 Schema

符合 v1.9.35 合约，与 Bot v1.9.36 实现一致。

### 安全字段

- 不包含原始 IP/domain/URL
- 不包含 token/secret/private key
- 不包含 workers.dev
- 不包含 subscription URL/path

### Unknown/Failure 处理

- 输入为 None 或空 dict → 全部 unknown
- JSON 解析失败 → 显示 unknown 摘要 + 解析错误消息
- 服务 failed/inactive → overall=failed 或 partial
- 配置缺失 → config=missing, profile=missing

---

## 4. Web /doctor 行为

### GET /doctor

- 登录要求保持
- 显示 Doctor 页面，带介绍文本
- 显示 "运行诊断" 按钮
- 不显示原始 doctor 输出

### POST /doctor，高级 OFF

1. CSRF 要求保持
2. 调用 `run_nanobk(config, ["--json", "status"])`
3. 解析 JSON（防御性）
4. 构建摘要：`build_doctor_summary(data)`
5. 渲染摘要卡片
6. **不调用** `run_nanobk(config, ["doctor"])`
7. 显示提示：完整诊断仅在高级模式下可用

### POST /doctor，高级 ON

1. 构建并渲染摘要卡片
2. 调用 `run_nanobk(config, ["doctor"])` 获取完整输出
3. 应用 `safe_output()` 脱敏
4. 在 `<details>` 块中渲染完整诊断（默认折叠）
5. 添加警告头
6. 如果完整输出失败，显示失败消息

### 失败行为

- status JSON 获取失败 → 显示 unknown 摘要 + 解析错误
- 不伪造健康状态
- 错误保持可见

---

## 5. 高级/完整诊断边界

| 边界 | 说明 |
|------|------|
| 高级 OFF 不调用/显示完整 doctor 输出 | ✅ |
| 高级 ON 可显示脱敏完整输出 | ✅ |
| 完整输出有警告保护 | ✅ |
| 完整输出默认折叠（`<details>`） | ✅ |
| `safe_output()` 仍被使用 | ✅ |

---

## 6. i18n 行为

| 特性 | 说明 |
|------|------|
| zh/en doctor 摘要标签 | 25 个新 i18n 键 |
| 机器状态值稳定 | healthy/failed/unknown/active/inactive 等不翻译 |
| 回退行为不变 | 缺失 key → key 名，缺失 lang → 英文 |

新增 i18n 键：
- doctor_summary_title, doctor_label_overall/control_plane/cli/profile/config/services/cloudflare/subscription/security/next_step/errors/warnings
- doctor_next_no_action/check_failed/complete_config/configure_cf/use_advanced/unknown
- doctor_full_note, doctor_full_warning, doctor_full_details_label, doctor_status_parse_error, doctor_full_unavailable, doctor_intro_text

---

## 7. 安全行为

| 安全特性 | 状态 |
|----------|------|
| 无原始 IP/domain/URL 在摘要中 | ✅ |
| 完整输出仅限高级模式 | ✅ |
| Redaction 不变 | ✅ |
| Login/CSRF 不变 | ✅ |
| 无 env 读取 | ✅ |
| 无直接写入 | ✅ |
| 无 CLI 变更 | ✅ |
| 无 shell=True | ✅ |
| display_policy 始终为 true | ✅ |

---

## 8. 未变更内容

| 组件 | 状态 |
|------|------|
| Bot | 未变更 |
| bin/nanobk | 未变更 |
| installer/doctor.sh | 未变更 |
| install.sh | 未变更 |
| redaction helper | 未变更 |
| /api/status | 未变更 |
| Raw JSON 门控 | 未变更 |
| 高级模式 | 未变更 |
| rotate | 未变更 |
| tag/release | 无 |

---

## 9. 测试运行

| 测试 | 结果 |
|------|------|
| `python3 web/app.py --self-test`（106 项） | ✅ All passed |
| `python3 tests/web-doctor-summary-v1.9.37.py`（164 项） | ✅ All passed |
| `python3 tests/doctor-summary-contract-v1.9.35.py`（352 项） | ✅ All passed |
| `python3 tests/bot-doctor-summary-v1.9.36.py`（163 项） | ✅ All passed |
| `python3 tests/web-i18n-minimal-v1.9.31.py`（123 项） | ✅ All passed |
| `python3 tests/web-advanced-mode-v1.9.17.py`（64 项） | ✅ All passed |
| `python3 tests/web-raw-json-soft-gate-v1.9.21.py`（48 项） | ✅ All passed |
| `bash tests/web-panel-mock.sh` | ✅ All passed |
| `python3 bot/nanobk_bot.py --self-test`（180 项） | ✅ All passed |

---

## 10. 已知限制

| 限制 | 说明 |
|------|------|
| Bot Doctor Summary 已在 v1.9.36 实现 | 未变更 |
| CLI doctor --json 未实现 | 独立任务 |
| 完整诊断源仍为文本 | doctor.sh 文本输出 |
| 真实 Web session 未重测 | 用户可后续执行 |
| 真实 doctor 未运行 | 仅使用 status JSON |
| Production status wrapper 仍阻塞 | 未批准 |

---

## 11. 下一步

**推荐：v1.9.38 — Doctor Output Checkpoint**

需 ChatGPT 审核后实施。
