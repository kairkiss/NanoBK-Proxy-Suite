# v1.9.35 — Doctor Summary Contract / Fixture Tests

> 合约类型：Doctor 摘要合约与 fixture 测试
> 日期：2026-06-05
> 基线 commit：`6076051acffc575e140ab91139272c39dca76f7c`
> 基线信息：`docs: add v1.9.34 doctor output audit`

---

## 1. 本轮目标与结论

**v1.9.35 定义 Doctor Summary fixture 和测试：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 未执行真实 doctor
- ✅ 无 tag/release
- ✅ 目的是在实现前定义安全的摘要合约

**结论：定义了 7 个输入 fixture 和 7 个预期摘要 fixture，覆盖健康/部分服务/缺失配置/Cloudflare 缺失/失败/含密钥/未知场景。合约测试验证 schema、安全规则和诚实性，为 v1.9.36 Bot 实现提供稳定基础。**

---

## 2. 合约目的

| 目的 | 说明 |
|------|------|
| 实现前建立安全摘要合约 | 防止实现时偏离安全要求 |
| 防止伪造成功 | unknown/failed/manual_pending 不得显示为成功 |
| 防止密钥泄漏 | 摘要中不得出现原始 IP/domain/URL/token/private key |
| 定义稳定输出形状 | 为未来 Bot/Web 实现提供统一 schema |
| 保持完整诊断仅限高级模式 | 新手摘要不包含技术细节 |

---

## 3. 输入 Fixture 集

| 文件 | 场景 | 说明 |
|------|------|------|
| `healthy-status.json` | 健康状态 | 所有服务 active，配置存在，Cloudflare verified |
| `partial-services-status.json` | 部分服务 | HY2/Reality active，TUIC failed，Trojan inactive |
| `missing-config-status.json` | 缺失配置 | 配置目录/文件缺失，所有服务 unknown |
| `cloudflare-missing-status.json` | Cloudflare 缺失 | 服务正常但 Cloudflare admin env 不存在 |
| `failure-doctor-output.txt` | 失败 doctor 输出 | 包含 2 个错误（HY2/TUIC 服务失败）的假 doctor 文本 |
| `secret-containing-doctor-output.txt` | 含密钥假输出 | 包含假 token/secret/private key 的 doctor 文本 |
| `unknown-invalid-output.txt` | 未知/无效输出 | 空文件，模拟无输出场景 |

**所有值均为假数据，使用 RFC 5737/3849/2606 安全范围。**

---

## 4. 预期摘要 Schema

```json
{
  "overall": "healthy|partial|failed|unknown",
  "control_plane": "ok|warning|failed|unknown",
  "cli": "available|missing|unknown",
  "profile": "present|missing|unknown",
  "config": "present|missing|unknown",
  "services": {
    "hy2": "active|inactive|missing|unknown",
    "tuic": "active|inactive|missing|unknown",
    "reality": "active|inactive|missing|unknown",
    "trojan": "active|inactive|missing|unknown"
  },
  "cloudflare": "verified|configured|missing|manual_pending|unknown",
  "subscription": "verified|configured|missing|unknown",
  "security": "ok|warning|failed|unknown",
  "doctor": {
    "errors": 0,
    "warnings": 0,
    "full_available": true
  },
  "next_step": "no_action|check_failed_services|complete_config|configure_cloudflare|use_advanced_diagnostics|unknown",
  "display_policy": {
    "beginner_safe": true,
    "full_output_advanced_only": true,
    "redaction_required": true
  }
}
```

### 允许值集

| 字段 | 允许值 |
|------|--------|
| overall | healthy, partial, failed, unknown |
| control_plane | ok, warning, failed, unknown |
| cli | available, missing, unknown |
| profile | present, missing, unknown |
| config | present, missing, unknown |
| services.* | active, inactive, missing, unknown |
| cloudflare | verified, configured, missing, manual_pending, unknown |
| subscription | verified, configured, missing, unknown |
| security | ok, warning, failed, unknown |
| next_step | no_action, check_failed_services, complete_config, configure_cloudflare, use_advanced_diagnostics, unknown |
| display_policy.beginner_safe | true（必须） |
| display_policy.full_output_advanced_only | true（必须） |
| display_policy.redaction_required | true（必须） |

---

## 5. 安全规则

| # | 规则 | 说明 |
|---|------|------|
| 1 | 无原始 IP/domain/URL | 摘要中不得出现 192.0.2.10、example.invalid 等 |
| 2 | 无 workers.dev | 摘要中不得出现 workers.dev |
| 3 | 无 subscription URL/path | 摘要中不得出现 /sub/ 路径 |
| 4 | 无原始 token | 摘要中不得出现 TEST_TOKEN 等 |
| 5 | 无原始 secret | 摘要中不得出现 TEST_SECRET 等 |
| 6 | 无原始 private key | 摘要中不得出现 TEST_PRIVATE_KEY 等 |
| 7 | 无原始 env 内容 | 摘要中不得包含 env 文件内容 |
| 8 | 无完整诊断文本 | 摘要中不得包含 doctor 原始输出 |
| 9 | beginner_safe 必须为 true | 所有预期摘要 |
| 10 | full_output_advanced_only 必须为 true | 所有预期摘要 |
| 11 | redaction_required 必须为 true | 所有预期摘要 |
| 12 | unknown 保持 unknown | 不得将 unknown 显示为其他状态 |
| 13 | failed 保持 failed | 不得将 failed 显示为 healthy |
| 14 | missing config 不得变为 healthy | 配置缺失时 overall 不得为 healthy |
| 15 | Cloudflare missing 不得变为 verified | Cloudflare 缺失时不得显示 verified |
| 16 | partial 保持 partial | 部分服务失败时不得显示 healthy |
| 17 | 无 shell 执行 | 测试不得执行任何 shell 命令 |

---

## 6. 场景预期

| 场景 | 预期 overall | 重要字段 | next_step | 说明 |
|------|:------------:|----------|-----------|------|
| 健康 | healthy | 全部 active/verified | no_action | 所有检查通过 |
| 部分服务 | partial | tuic=failed, trojan=inactive | check_failed_services | 部分服务异常 |
| 缺失配置 | unknown | config=missing, profile=missing | complete_config | 配置不存在 |
| Cloudflare 缺失 | partial | cloudflare=missing | configure_cloudflare | CF 未配置 |
| 失败 doctor | failed | hy2=inactive, tuic=failed | check_failed_services | 服务失败 |
| 含密钥 | healthy | 无密钥泄漏 | no_action | redaction 生效 |
| 未知 | unknown | 全部 unknown | unknown | 无有效数据 |

---

## 7. 未来实现指导

| 说明 | 详情 |
|------|------|
| v1.9.36 Bot 实现应消费此合约 | 使用 fixture 验证摘要构建逻辑 |
| v1.9.37 Web 实现应消费此合约 | 使用 fixture 验证摘要卡片渲染 |
| 不要在合约测试通过前解析真实输出 | 先证明 redaction 和诚实性 |
| 如需实时解析，映射到此 schema | 保持输出形状一致 |
| 如未来 doctor --json 存在，映射到此 schema | 保持输出形状一致 |
| 完整输出保持高级模式专用 | 新手摘要不包含技术细节 |

---

## 8. 测试策略

| 测试 | 说明 |
|------|------|
| Fixture JSON 有效性 | 所有 JSON fixture 可解析 |
| 预期 schema 验证 | 所有必需字段存在，值在允许范围内 |
| 禁止模式扫描 | 预期摘要中无原始 IP/token/secret/URL |
| 诚实性规则 | unknown/failed/partial 不得变为 healthy |
| Redaction 规则 | display_policy.redaction_required == true |
| 无运行时命令 | 测试不执行任何 CLI 命令 |
| 无真实 env | 测试不读取真实 env 文件 |

---

## 9. 就绪决策

**A. READY FOR BOT DOCTOR SUMMARY MINIMAL IMPLEMENTATION AFTER CHATGPT REVIEW**

约束：
- 仅 Bot
- 最小实现
- 使用合约/fixtures
- 无 Web 变更在 Bot 步骤中
- 无 CLI 行为变更
- 无真实 doctor 执行
- 无 release/tag

---

## 10. Guardrails

| # | 约束 | 说明 |
|---|------|------|
| 1 | 无 install.sh 行为变更 | 保护 v1.7.27 基线 |
| 2 | 无 bin/nanobk 行为变更 | 保护 CLI 核心 |
| 3 | 无 installer/doctor.sh 行为变更 | 保护 CLI 核心 |
| 4 | 无协议模板变更 | 保护部署 |
| 5 | 无 Worker 变更 | 保护 Cloudflare |
| 6 | 无 rotate sync 变更 | 保护轮换 |
| 7 | 无直接 Bot/Web 写入 configs/systemd/secrets | 安全 |
| 8 | 无 raw env 读取 | 安全 |
| 9 | 无 production status wrapper | 未批准 |
| 10 | 无 dirty VPS status wrapping | 未批准 |
| 11 | 无 operation-log full rollout | 未批准 |
| 12 | 无 raw subscription 交付 | 未批准 |
| 13 | 无 tag/release | 未批准 |
