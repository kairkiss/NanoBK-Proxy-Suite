# v1.9.41 — Doctor Summary Real Status Field Compatibility Fix Planning

> 规划类型：Doctor Summary 真实状态字段兼容性修复规划
> 日期：2026-06-05
> 基线 commit：`07b70d5f90c1d78aa2229ad10858c910999c6e55`
> 基线信息：`docs: add v1.9.40 real doctor smoke validation`

---

## 1. 本轮目标与结论

**v1.9.41 是规划/文档任务：**

- ✅ 无 Bot 运行时行为变更
- ✅ 无 Web 运行时行为变更
- ✅ 无 CLI 行为变更
- ✅ 无部署逻辑变更
- ✅ Claude Code 未执行真实 status
- ✅ 无 tag/release
- ✅ 目的是规划 T15-P2-001 的安全修复

**结论：Doctor Summary builder 的 profile/config 推断逻辑与真实 `nanobk --json status` 输出 shape 不兼容。真实 status JSON 使用 `profile.exists` 和 `security.secretsExists`，而 builder 仅检查 `profile.currentPath`/`profile.domain`。修复方案安全——仅扩展安全结构化字段的解释。**

---

## 2. T15-P2-001 问题定义

| 属性 | 说明 |
|------|------|
| 问题 | Bot/Web Doctor Summary 显示 Profile/Config unknown |
| 对比 | Dashboard/Status 显示 Profile present |
| 真实状态 | 配置存在，四协议活跃 |
| 根因 | 字段兼容性问题，非安全问题 |
| 影响 | 影响新手信任和状态诚实性 |
| 严重度 | P2 |

**T15 观察：**
- Dashboard: Profile present, Secrets present mode 600
- Bot /doctor: Profile unknown, Config unknown
- Web /doctor: Profile unknown, Config unknown
- Services 和 Cloudflare 正确

---

## 3. 当前 builder 行为审计

### Doctor Summary builder（Bot 和 Web 相同）

**Profile 推断逻辑：**
```python
profile_data = data.get("profile")
profile = "unknown"
if isinstance(profile_data, dict):
    if profile_data.get("currentPath") or profile_data.get("domain"):
        profile = "present"
elif data.get("domain") and data.get("domain") != "<not set>":
    profile = "present"
```

**Config 推断逻辑：**
```python
config = "present" if profile == "present" else "unknown"
# 如果 warnings 包含 "config directory not found" 或 "profile not found" → missing
```

**Security 推断逻辑：**
```python
security = data.get("security")
if not isinstance(security, dict):
    return "unknown"
mode = security.get("secretsMode")
if mode:
    return "ok"
return "warning"
```

### Dashboard/Status formatter（Bot 和 Web 相同）

**Profile 推断逻辑：**
```python
def _infer_profile(data):
    profile = data.get("profile")
    if isinstance(profile, dict):
        if profile.get("currentPath") or profile.get("domain"):
            return "present"
    if data.get("domain") and data.get("domain") != "<not set>":
        return "present"
    return "unknown"
```

**Secrets 推断逻辑：**
```python
def _infer_secrets(data):
    security = data.get("security")
    if not isinstance(security, dict):
        return "unknown"
    mode = security.get("secretsMode")
    if mode:
        return f"present, mode {mode}"
    return "present"
```

### 推断差异分析

Doctor Summary builder 和 Dashboard/Status formatter 的 profile 推断逻辑**完全相同**。

但 T15 报告 Dashboard 显示 "Profile present"，Doctor Summary 显示 "Profile unknown"。

**可能原因：**

1. 真实 status JSON 的 `profile` 对象有 `exists: true` 但没有 `currentPath` 或 `domain`。
2. 真实 status JSON 的顶层 `domain` 可能是空字符串、`"<not set>"` 或不存在。
3. Dashboard 可能使用了不同的代码路径（如 `_build_safe_cards` 直接检查 profile 对象）。

**关键发现：** 真实 `nanobk --json status` 输出的 profile 对象 shape 为：
```json
{
  "profile": {
    "exists": true,
    "updatedAt": "...",
    "hy2": true,
    "tuic": true,
    "reality": true,
    "trojan": true
  }
}
```

**不包含** `currentPath` 或 `domain`。因此 builder 的 `profile_data.get("currentPath")` 和 `profile_data.get("domain")` 都返回 None/falsy。

---

## 4. 真实 status shape 假设

基于源码检查（`bin/nanobk` 第 505-545 行）：

| 字段 | 类型 | 说明 |
|------|------|------|
| `ok` | boolean | 整体状态 |
| `configDir` | string | 配置目录路径（如 `/etc/nanobk`） |
| `domain` | string | 域名（可能为空或 `"<not set>"`） |
| `vpsIp` | string | VPS IP（脱敏后） |
| `profile.exists` | boolean | profile 文件是否存在 |
| `profile.updatedAt` | string | profile 更新时间 |
| `profile.hy2/tuic/reality/trojan` | boolean | 协议 section 是否存在 |
| `services.hy2/tuic/reality/trojan` | string | 服务状态（active/inactive/failed/missing） |
| `security.secretsExists` | boolean | secrets 文件是否存在 |
| `security.secretsMode` | string | secrets 权限模式（如 "600"） |
| `security.secretsModeOk` | boolean | secrets 权限是否正确 |
| `cloudflare.nanok.envExists` | boolean | nanok env 是否存在 |
| `cloudflare.nanob.envExists` | boolean | nanob env 是否存在 |
| `warnings` | array | 警告列表 |

**关键：** 真实 profile 对象使用 `exists` 而非 `currentPath`/`domain`。

---

## 5. 兼容性映射提案

### Profile 映射规则

**Profile 应为 present 当以下任一安全条件满足：**

| 条件 | 来源 | 安全性 |
|------|------|--------|
| `profile.currentPath` 存在且非空 | 现有 fixture | ✅ 不显示路径 |
| `profile.domain` 存在且非空 | 现有 fixture | ✅ 不显示域名 |
| `profile.exists == true` | 真实 status JSON | ✅ 仅布尔值 |
| 顶层 `domain` 存在且不为 `"<not set>"` | 现有逻辑 | ✅ 不显示域名 |

**Profile 应为 missing 当：**

| 条件 | 说明 |
|------|------|
| `profile.exists == false` | 明确缺失 |
| warnings 包含 "profile not found" | 明确缺失 |
| profile 为 null 且无其他证据 | 无证据 |

**Profile 应为 unknown 当：**

| 条件 | 说明 |
|------|------|
| 字段不存在且无安全推断 | 诚实 unknown |

### Config 映射规则

**Config 应为 present 当以下任一安全条件满足：**

| 条件 | 来源 | 安全性 |
|------|------|--------|
| profile 为 present | 现有逻辑 | ✅ |
| `configDir` 存在且非空 | 真实 status JSON | ✅ 不显示路径 |
| `security.secretsExists == true` | 真实 status JSON | ✅ 仅布尔值 |

**Config 应为 missing 当：**

| 条件 | 说明 |
|------|------|
| warnings 包含 "config directory not found" | 明确缺失 |
| `security.secretsExists == false` 且 profile 缺失 | 强证据 |

**Config 应为 unknown 当：**

| 条件 | 说明 |
|------|------|
| 无安全证据 | 诚实 unknown |

### Security 映射规则（保持不变）

| 条件 | 结果 |
|------|------|
| `security.secretsMode` 存在 | ok |
| `security` 为 dict 但无 secretsMode | warning |
| `security` 不是 dict | unknown |

---

## 6. 诚实性规则

| 规则 | 说明 |
|------|------|
| 不将 unknown 转换为 present（无证据） | ✅ |
| 不从 raw configDir 路径单独显示为 config present | ✅ 仅用于推断，不显示路径 |
| 不从 domain/IP 显示 profile present | ✅ 仅布尔/结构化证据 |
| missing 优先于推断的 present | ✅ |
| failed 优先于 healthy | ✅ |
| manual_pending 不变为 verified | ✅ |
| 不输出 raw 路径 | ✅ |
| 不输出 raw IP/domain/URL | ✅ |

---

## 7. Fixture/测试计划

### 需要新增/更新的 fake fixture 情况

| Fixture | 说明 |
|---------|------|
| `realistic-status.json` | 真实 shape：`profile.exists: true`，`security.secretsExists: true`，`configDir` 非空，无 `profile.currentPath`/`profile.domain` |
| `profile-exists-no-domain.json` | `profile.exists: true`，无 `currentPath`/`domain`，顶层 `domain` 为 `"<not set>"` |
| `profile-missing-explicit.json` | `profile.exists: false` |
| `security-missing-secrets.json` | `security.secretsExists: false` |
| `profile-present-services-missing.json` | `profile.exists: true`，但 services 全 unknown |
| `dashboard-compatible-shape.json` | 与 Dashboard/Status formatter 兼容的 shape |

### 预期测试

| 测试 | 说明 |
|------|------|
| Bot builder 将 `profile.exists: true` 映射为 present | 兼容性 |
| Web builder 将 `profile.exists: true` 映射为 present | 兼容性 |
| 无 raw configDir 路径出现在格式化摘要中 | 安全 |
| 无证据时 unknown 保持 unknown | 诚实 |
| explicit missing 保持 missing | 诚实 |
| Bot/Web 输出匹配 | 一致性 |
| v1.9.35 合约仍通过 | 回归 |

---

## 8. 实现路线推荐

| 选项 | 内容 | 推荐 |
|------|------|------|
| **选项 A** | v1.9.42 — Doctor Summary Field Compatibility Fixture Tests | ✅ 推荐 |
| 选项 B | v1.9.42 — Bot/Web Doctor Summary Field Compatibility Minimal Fix | 可选 |
| 选项 C | v1.9.42 — Shared Doctor Summary Helper Planning | 可选 |

**推荐选项 A：**

原因：虽然源码审计使映射变得明显，但最安全的下一步是先将真实-like status shape 锁定到测试中，再修改 Bot/Web builder。

**后续路线：**

| 版本 | 内容 |
|------|------|
| v1.9.42 | Doctor Summary Field Compatibility Fixture Tests |
| v1.9.43 | Bot/Web Doctor Summary Field Compatibility Minimal Fix |
| v1.9.44 | Doctor Summary Field Compatibility Checkpoint |

---

## 9. 安全决策

**字段兼容性修复是安全的，因为它仅改变安全结构化 status JSON 字段的解释方式。**

但不构成以下许可：

- ❌ 泄漏 raw config 路径
- ❌ 泄漏 raw IP/domain/URL
- ❌ 读取 env 文件
- ❌ 运行真实 status
- ❌ 运行真实 doctor
- ❌ 检查 /etc/nanobk
- ❌ 实现 production status wrapper
- ❌ 实现 dirty VPS status wrapping
- ❌ 改变 CLI
- ❌ release/tag

---

## 10. 就绪决策

**A. READY FOR FIELD COMPATIBILITY FIXTURE TESTS**

原因：问题是真实的，但最安全的下一步是在修改 Bot/Web builder 之前，先将假的真实-like status shape 锁定到测试中。

约束：
- 仅 fixture 测试
- 无运行时变更
- 无真实 status 执行
- 无真实 doctor 执行
- 无 release/tag

---

## 11. Guardrails

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
| 9 | 无真实 status 执行 | ✅ |
| 10 | 无真实 doctor 执行 | ✅ |
| 11 | 无 production status wrapper | ✅ |
| 12 | 无 dirty VPS status wrapping | ✅ |
| 13 | 无 operation-log full rollout | ✅ |
| 14 | 无 raw subscription delivery | ✅ |
| 15 | 无 tag/release | ✅ |
