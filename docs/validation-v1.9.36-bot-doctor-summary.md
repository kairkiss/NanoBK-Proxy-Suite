# v1.9.36 — Bot Doctor Summary Minimal Implementation Validation

> 验证类型：Bot Doctor 摘要最小实现
> 日期：2026-06-05
> 基线 commit：`2dcdc436539ddc9257ad767a87b1fb0a396be8af`
> 基线信息：`test: add v1.9.35 doctor summary contract`

---

## 1. 本轮目标与结论

**v1.9.36 实现了 Bot /doctor 新手友好摘要：**

- ✅ Bot /doctor 默认显示安全新手摘要
- ✅ 无 Web 运行时变更
- ✅ 无 CLI 行为变更
- ✅ 无安装器变更
- ✅ 无部署逻辑变更
- ✅ 无 tag/release

**结论：Bot /doctor 现在从 `nanobk --json status` 构建安全摘要，默认不显示完整技术输出。高级模式 ON 时附加脱敏完整诊断。符合 v1.9.35 Doctor Summary 合约。**

---

## 2. 变更路径

| 文件 | 变更 |
|------|------|
| `bot/nanobk_bot.py` | 新增 i18n 键、doctor 摘要构建函数、更新 cmd_doctor、更新 self-test |
| `tests/bot-doctor-summary-v1.9.36.py` | 新增测试（163 项） |
| `docs/validation-v1.9.36-bot-doctor-summary.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.36 条目 |
| `docs/roadmap.md` | 新增 v1.9.36 行 |

---

## 3. Doctor 摘要构建器

### 辅助函数

| 函数 | 说明 |
|------|------|
| `build_doctor_summary(data, *, full_available=True)` | 从 status JSON 构建摘要 dict，符合 v1.9.35 schema |
| `format_doctor_summary(summary, lang="en")` | 将摘要 dict 格式化为人类可读文本 |
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

符合 v1.9.35 合约：
- overall: healthy/partial/failed/unknown
- control_plane: ok/warning/failed/unknown
- cli: available/missing/unknown
- profile: present/missing/unknown
- config: present/missing/unknown
- services: {hy2, tuic, reality, trojan}: active/inactive/missing/unknown
- cloudflare: verified/configured/missing/manual_pending/unknown
- subscription: verified/configured/missing/unknown
- security: ok/warning/failed/unknown
- doctor: {errors, warnings, full_available}
- next_step: no_action/check_failed_services/complete_config/configure_cloudflare/use_advanced_diagnostics/unknown
- display_policy: {beginner_safe: true, full_output_advanced_only: true, redaction_required: true}

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

## 4. Bot /doctor 行为

### 高级 OFF（默认）

1. 显示 "正在运行诊断..." 消息
2. 调用 `run_nanobk(config, ["--json", "status"])`
3. 解析 JSON（防御性）
4. 构建摘要：`build_doctor_summary(data)`
5. 格式化摘要：`format_doctor_summary(summary, lang)`
6. 发送摘要
7. 发送提示："💡 完整诊断：使用 /advanced on，然后再次 /doctor。"
8. **不调用** `run_nanobk(config, ["doctor"])`

### 高级 ON

1. 构建并发送同样的安全摘要
2. 调用 `run_nanobk(config, ["doctor"])` 获取完整输出
3. 应用 `safe_output()` 脱敏
4. 添加警告头："⚠️ 高级诊断..."
5. 发送脱敏完整输出
6. 如果完整输出失败，显示 "完整诊断不可用（命令失败）。"

### 失败行为

- status JSON 获取失败 → 显示 unknown 摘要 + 解析错误
- 不伪造健康状态
- 错误保持可见

---

## 5. 安全行为

| 安全特性 | 状态 |
|----------|------|
| 无原始 IP/domain/URL 在摘要中 | ✅ |
| 完整输出仅限高级模式 | ✅ |
| Redaction 不变 | ✅ |
| Owner-only 不变 | ✅ |
| 无 env 读取 | ✅ |
| 无直接写入 | ✅ |
| 无 CLI 变更 | ✅ |
| 无 shell=True | ✅ |
| display_policy 始终为 true | ✅ |

---

## 6. i18n 行为

| 特性 | 说明 |
|------|------|
| zh/en doctor 摘要标签 | 23 个新 i18n 键 |
| 机器状态值稳定 | healthy/failed/unknown 等不翻译 |
| 回退行为不变 | 缺失 key → key 名，缺失 lang → 英文 |

新增 i18n 键：
- doctor_summary_title, doctor_label_overall/control_plane/cli/profile/config/services/cloudflare/subscription/security/next_step/errors/warnings
- doctor_next_no_action/check_failed/complete_config/configure_cf/use_advanced/unknown
- doctor_full_note, doctor_full_warning, doctor_status_parse_error, doctor_full_unavailable

---

## 7. 未变更内容

| 组件 | 状态 |
|------|------|
| Web | 未变更 |
| bin/nanobk | 未变更 |
| installer/doctor.sh | 未变更 |
| install.sh | 未变更 |
| redaction helper | 未变更 |
| /status_json | 未变更 |
| 高级模式 | 未变更 |
| rotate | 未变更 |
| tag/release | 无 |

---

## 8. 测试运行

| 测试 | 结果 |
|------|------|
| `python3 bot/nanobk_bot.py --self-test`（180 项） | ✅ All passed |
| `python3 tests/bot-doctor-summary-v1.9.36.py`（163 项） | ✅ All passed |
| `python3 tests/doctor-summary-contract-v1.9.35.py`（352 项） | ✅ All passed |
| `python3 tests/bot-i18n-minimal-v1.9.30.py`（116 项） | ✅ All passed |
| `python3 tests/bot-control-center-checkpoint-v1.9.26.py`（66 项） | ✅ All passed |
| `python3 tests/bot-status-json-soft-gate-v1.9.20.py`（50 项） | ✅ All passed |
| `python3 tests/bot-advanced-mode-v1.9.16.py`（65 项） | ✅ All passed |
| `bash tests/bot-cli-mock.sh` | ✅ All passed |
| `python3 web/app.py --self-test`（75 项） | ✅ All passed |

---

## 9. 已知限制

| 限制 | 说明 |
|------|------|
| Web Doctor Summary 未实现 | v1.9.37 任务 |
| CLI doctor --json 未实现 | 独立任务 |
| 完整诊断源仍为文本 | doctor.sh 文本输出 |
| 真实 Bot session 未重测 | 用户可后续执行 |
| 真实 doctor 未运行 | 仅使用 status JSON |
| Production status wrapper 仍阻塞 | 未批准 |

---

## 10. 下一步

**推荐：v1.9.37 — Web Doctor Summary Minimal Implementation**

需 ChatGPT 审核后实施。
