# v1.9.57 — Web Chinese Copy Polish / i18n Coverage Fix

> 验证类型：Web 中文 Copy 打磨 / i18n 覆盖修复
> 日期：2026-06-06
> 基线 commit：`48102f629fdc084f57d2210757f9af602e219b32`
> 基线信息：`test: fix installer language propagation check`

---

## 1. 本轮目标与结论

**v1.9.57 修复了 T17-P2-003 Web 中文 Copy 残留问题。**

- ✅ Web 状态卡 "下一步" 提示现在使用 i18n
- ✅ zh 模式返回中文，en 模式返回英文
- ✅ 无 Bot/安装器/CLI 变更
- ✅ 无 `/api/status` schema 变更
- ✅ 无 Raw JSON key 翻译
- ✅ 无机器值翻译
- ✅ 无 tag/release

**结论：`_next_step_hint` 函数中的 6 个硬编码英文字符串已替换为 i18n 调用。Web 状态/仪表盘页面的 "下一步" 提示现在根据语言设置正确显示中文或英文。**

---

## 2. Root cause

### 英文残留来源

`web/app.py` 中的 `_next_step_hint` 函数返回硬编码英文字符串：

```python
def _next_step_hint(overall, vps, cf_nanok, cf_nanob, sub):
    if overall == "failed":
        return "Check SSH or run NanoBK recovery from the server."
    if vps == "failed":
        return "Check SSH and verify proxy services are running."
    ...
```

这些字符串直接存储在 `cards["next_step"]` 中，由模板通过 `{{ status.cards.next_step }}` 显示，完全绕过了 i18n 系统。

### 为什么机器值保持英文

机器状态值（`healthy`、`failed`、`unknown`、`active` 等）由 `_infer_overall`、`_infer_vps` 等函数返回，用于状态推理和逻辑判断。这些值在模板中直接显示为技术状态指标，有意保持英文以确保一致性和可调试性。用户友好的标签（如 "总体状态"、"下一步"）已通过 `t()` 翻译。

---

## 3. Changed paths

| 文件 | 变更 |
|------|------|
| `web/i18n.py` | 新增 6 个 `next_step_*` i18n key（zh/en） |
| `web/app.py` | `_next_step_hint` 接受 `lang` 参数，使用 `wt()`；`_build_safe_cards` 和 `format_status` 传递 `lang`；路由传递 `config.lang` |
| `tests/web-chinese-copy-polish-v1.9.57.py` | 新增聚焦测试（76 项） |
| `docs/validation-v1.9.57-web-chinese-copy-polish.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.57 条目 |
| `docs/roadmap.md` | 新增 v1.9.57 版本行 |

---

## 4. Web Chinese copy fix summary

### 修复的 i18n key

| Key | en | zh |
|-----|----|----|
| `next_step_check_ssh_recovery` | Check SSH or run NanoBK recovery from the server. | 请通过 SSH 检查或在服务器上运行 NanoBK 恢复。 |
| `next_step_check_ssh_services` | Check SSH and verify proxy services are running. | 请通过 SSH 检查并确认代理服务正在运行。 |
| `next_step_finish_cf` | Finish Cloudflare verification from the Full Wizard or CLI. | 请从完整向导或 CLI 完成 Cloudflare 验证。 |
| `next_step_verify_subscription` | Verify subscription access from the Full Wizard or CLI. | 请从完整向导或 CLI 验证订阅访问。 |
| `next_step_no_action` | No immediate action required. | 无需立即操作。 |
| `next_step_run_doctor` | Run Doctor for a redacted diagnostic summary, or check SSH if needed. | 运行诊断获取脱敏诊断摘要，或在需要时通过 SSH 检查。 |

### 调用链变更

```
route handler (config.lang)
  → format_status(data, lang=lang)
    → _build_safe_cards(data, lang=lang)
      → _next_step_hint(..., lang=lang)
        → wt(lang, "next_step_*")
```

### 未触及的区域

- Doctor 页面：已通过机器键映射正确翻译（`no_action` → `t('doctor_next_no_action')`）
- 登录页面：已正确翻译
- 导航标签：已正确翻译
- 按钮标签：已正确翻译
- 轮换页面：已正确翻译

---

## 5. Machine values and Raw JSON boundary

| 边界 | 状态 |
|------|------|
| Raw JSON key 不翻译 | ✅ |
| `/api/status` 不变 | ✅ |
| 机器值保持英文 | ✅ |
| 协议名不变 | ✅ |
| 命令名不变 | ✅ |

---

## 6. Safety boundaries

| 边界 | 状态 |
|------|------|
| 不读 env 文件 | ✅ |
| 不写 env 文件 | ✅ |
| 不打印密钥 | ✅ |
| 不改变 redaction | ✅ |
| 不改变 Raw JSON gating | ✅ |
| 不改变高级模式 | ✅ |
| 不改变 rotate | ✅ |
| 不改变部署逻辑 | ✅ |
| 不改变 Bot/安装器/CLI | ✅ |

---

## 7. Tests run

| 测试 | 结果 |
|------|------|
| `python3 tests/web-chinese-copy-polish-v1.9.57.py` | ✅ 76 passed |
| `python3 tests/web-i18n-minimal-v1.9.31.py` | ✅ 123 passed |
| `python3 tests/chinese-default-v1.9.48.py` | ✅ 75 passed |
| `python3 tests/i18n-checkpoint-v1.9.32.py` | ✅ 167 passed |
| `python3 tests/web-language-switch-v1.9.51.py` | ✅ 57 passed |
| `python3 tests/web-safe-status-cards-v1.9.11.py` | ✅ 82 passed |
| `python3 tests/web-doctor-summary-v1.9.37.py` | ✅ 164 passed |
| `python3 tests/web-raw-json-soft-gate-v1.9.21.py` | ✅ 48 passed |
| `python3 tests/doctor-output-checkpoint-v1.9.38.py` | ✅ 208 passed |
| `bash tests/web-panel-mock.sh` | ✅ passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 228 passed |
| `bash tests/bot-cli-mock.sh` | ✅ passed |
| `python3 web/app.py --self-test` | ✅ 118 passed |

---

## 8. Stable tag impact

- ✅ T17-P2-003 可标记为已解决
- 稳定 tag 仍被以下项阻塞：
  - CLI 版本显示处理（T17-P2-011）
  - AI 维护接口文档（T17-P2-012）
  - 最终聚焦测试通过
  - 用户明确批准

---

## 9. Known limitations

| 限制 | 说明 |
|------|------|
| 未重新设计 Web UI | 仅修复 i18n 覆盖 |
| 未翻译机器值 | 有意保持英文 |
| 未添加 Web 生产运行器 | 未来任务 |
| 未实现指纹脱敏策略 | 未来任务 |
| 真实 Web 冒烟重测可能有用 | 稳定 tag 前建议 |

---

## 10. Next step

**推荐：v1.9.58 — CLI Version Display Strategy / Minimal Fix**

仅在 ChatGPT 审核后实施。
