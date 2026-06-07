# NanoBK Proxy Suite v2.0 — DNS 与 Full Wizard DNS 阶段收尾

## 1. 收尾结论

**PASS — v2.0 DNS / Full Wizard DNS 阶段正式关闭。**

本文件记录 v2.0 系列中 DNS 计划、验证、应用 CLI 以及 Full Wizard DNS 集成的完整收尾。该阶段从 v2.0.7 延伸至 v2.0.21，涵盖本地计划、真实 Cloudflare 验证、Full Wizard 集成、脏 VPS 修复和版本一致性打磨。

---

## 2. 本阶段范围

### 2.1 涵盖内容

- DNS profile 计划（`nanobk cf dns plan`）
- DNS profile 验证（`nanobk cf dns validate-profile`）
- DNS apply CLI（`nanobk cf dns apply --dry-run / --check / --yes`）
- Full Wizard DNS plan/check 集成
- 脏 VPS preflight 修复
- 版本显示一致性打磨

### 2.2 不涵盖内容

- DNS-01 证书自动化
- Cloudflare Tunnel
- Cloudflare Access
- Worker 自定义域名自动化
- Web/Bot DNS UI 集成
- Full Wizard 自动执行 apply --yes
- 发布/标签

---

## 3. 已完成里程碑

### 3.1 v2.0.1 / v2.0.2 — CLI 单协议链接导出

- `nanobk export link hy2|tuic|reality|trojan`
- `nanobk export links`
- 仅显式导出，不包含在默认 status/Web/Bot 摘要中

### 3.2 v2.0.3 / v2.0.4 — Web UI Apple 风格重设计

- Token 登录、CSRF、Advanced Mode、原始 JSON 门控、doctor 门控、rotate 确认保留

### 3.3 v2.0.5 / v2.0.6 — Web 本地/systemd 启动加固

- 本地绑定限制、systemd 加固、venv 幂等性

### 3.4 v2.0.7 / v2.0.8 — Cloudflare DNS 干跑计划

- `nanobk cf dns plan`
- `nanobk cf dns validate-profile`
- 强制 defaultProxied=false
- 仅本地计划，无 Cloudflare API 调用，无变更

### 3.5 v2.0.9 / v2.0.10 — Cloudflare DNS Apply 骨架与安全打磨

- `nanobk cf dns apply --dry-run`
- `nanobk cf dns apply --check`
- `nanobk cf dns apply --yes`
- api-env 白名单与 chmod 600
- 假传输测试
- 精确主机名所有权标记

### 3.6 v2.0.11 — Cloudflare DNS Apply CLI 一致性修复

- `apply --help` 修复
- 过时计划措辞移除

### 3.7 v2.0.12 — 首次真实 Cloudflare DNS Apply 验证记录

- 一次性 A 记录在真实 Cloudflare zone 创建
- DNS-only / proxied=false 确认
- 所有权标记确认
- 二次 apply no-op 确认
- 手动清理确认

### 3.8 v2.0.13–v2.0.17 — Full Wizard Cloudflare DNS Plan/Check 骨架

- 提示流程、profile 写入、chmod 600、validate/plan/check、Summary 状态
- Mock 交互验证
- Resume 与 EOF 安全打磨
- apply --yes 仍仅为手动指令

### 3.9 v2.0.18 / v2.0.19 — 脏 VPS Full Wizard preflight 修复

- 修复 T19 问题：现有 HY2/TUIC/Reality/Trojan 端口在用户跳过 VPS 之前阻塞 DNS
- T20 确认脏 VPS PASS

### 3.10 v2.0.20 — Full Wizard DNS 脏 VPS 验证记录

- T19 PASS WITH PRODUCT ISSUE
- T20 在 v2.0.19 修复后 PASS

### 3.11 v2.0.21 — 版本显示一致性打磨

- nanobk 版本、installer 横幅、bootstrap 版本统一为 v2.0.21

---

## 4. DNS CLI 最终状态

### 4.1 可用命令

| 命令 | 说明 |
|------|------|
| `nanobk cf dns plan` | 仅本地计划，无 API 调用，无变更 |
| `nanobk cf dns validate-profile` | 验证 profile 文件格式 |
| `nanobk cf dns apply --dry-run` | 验证模式，无 API 调用 |
| `nanobk cf dns apply --check` | GET-only 检查，不执行变更 |
| `nanobk cf dns apply --yes` | 唯一变更路径，创建/更新 A/AAAA 记录 |

### 4.2 安全约束

- `--dry-run`：无 API 调用
- `--check`：仅 GET 请求
- `--yes`：唯一触发变更的选项
- 无删除命令
- `--force` 保留且被拒绝
- api-env 必须为 chmod 600
- api-env 白名单：`CF_API_TOKEN`、`CF_ZONE_ID`、`CF_ZONE_NAME`
- 不 source/eval env 文件
- 所有权标记：`managed-by=nanobk; component=cf-dns-apply; hostname=...`

---

## 5. Full Wizard 最终状态

### 5.1 DNS Profile 写入

- 路径：`/etc/nanobk/cloudflare-dns-profile.json`
- 权限：chmod 600
- 测试模式下写入 `NANOBK_TEST_TMPDIR` 下

### 5.2 自动执行流程

- 自动运行 `validate-profile`
- 自动运行 `plan`
- 可选显式 GET-only `--check`（需用户确认）
- **永不自动执行 `apply --yes`**

### 5.3 Summary 状态

| 字段 | 可能值 |
|------|--------|
| dns_profile | written / skipped / failed / dry_run |
| dns_plan | planned / skipped / failed / dry_run |
| dns_check | check_passed_create_needed / check_noop / skipped / permission_failed / conflict / failed |
| dns_apply | manual_apply_pending / skipped / failed / unknown |

dns_apply 的最终安全状态为 `manual_apply_pending` / `skipped` / `failed` / `unknown`，**永远不是** `done` / `installed` / `verified` / `success`。

---

## 6. 真实验证证据

### 6.1 首次真实 DNS Apply 验证

- **文档**：`docs/validation/cloudflare-dns-apply-real-test-v2.0.11.md`
- 一次性 A 记录创建
- DNS-only / proxied=false 确认
- NanoBK 所有权注释确认
- 二次 apply no-op 确认
- 记录手动清理
- 无 token/env/protocol/subscription 泄露

### 6.2 Full Wizard DNS 真实 VPS 验证

- **文档**：`docs/validation/full-wizard-dns-dirty-vps-real-test-v2.0.19.md`
- DNS profile 写入 `/etc/nanobk/cloudflare-dns-profile.json`
- chmod 600 确认
- validate-profile 通过
- plan 通过
- GET-only `--check` 通过
- Summary 显示 `dns_apply: manual_apply_pending`
- 未执行 `apply --yes`
- 未创建 DNS 记录

### 6.3 脏 VPS 验证

- **文档**：`docs/validation/full-wizard-dns-dirty-vps-real-test-v2.0.19.md`
- 现有 HY2/TUIC/Reality/Trojan 服务继续运行
- Full Wizard Phase 0 不再因占用的协议端口阻塞
- 用户跳过 VPS 并到达 DNS 阶段
- DNS profile/validate/plan/check 通过
- 现有服务未停止或损坏
- 未发生 DNS 变更

---

## 7. 测试覆盖摘要

### 7.1 模拟测试

| 测试脚本 | 覆盖范围 |
|----------|----------|
| `tests/cf-dns-plan.sh` | DNS plan 本地干跑 |
| `tests/cf-dns-apply.sh` | DNS apply 假传输测试 |
| `tests/full-wizard-dns-skeleton.sh` | Full Wizard DNS 骨架静态+动态检查 |
| `tests/full_wizard_interactive_mock.py` | Full Wizard 交互式 mock（Test A–I） |

### 7.2 关键测试场景

- profile 渲染与内容验证
- chmod 600 检查
- validate-profile / plan 退出码
- `--yes` 不自动执行（静态源码检查 + mock 驱动验证）
- Summary 包含 DNS 字段
- 无真实 Cloudflare API 调用
- 无 token/env 泄露
- IPv6 可选
- 阶段卡存在
- DNS 阶段失败被捕获
- 不安全 cat-heredoc api-env 指令检查
- 不安全默认值检查
- 脏 VPS 跳过 VPS → DNS 继续
- 脏 VPS 重新配置 VPS → 端口冲突致命
- Resume cloudflare/botweb → DNS 跳过
- EOF 安全

---

## 8. 安全与隐私护栏

以下为不可协商的安全规则：

- **Full Wizard 不得自动执行 `nanobk cf dns apply --yes`**
- **Bot/Web 不得直接写入配置/systemd/secrets/env/DNS**
- **Bot/Web 仅通过 CLI 调用**
- **DNS A/AAAA 节点记录必须为 DNS-only / proxied=false**
- **Cloudflare API env 必须为 chmod 600，不得被 cat/read/打印**
- **协议链接、订阅 URL、token、私钥、workers.dev URL 不得泄露到正常输出/日志**
- **类地址值可在显式交互确认/手动命令中出现，但在日志/Web/Bot 中需谨慎处理**

---

## 9. 已接受限制

| 限制 | 说明 |
|------|------|
| Full Wizard 不自动执行 --yes | 设计决策，保护用户 |
| 无 DNS 删除命令 | 未实现 |
| --force 保留且被拒绝 | 未实现 |
| 无 DNS-01 证书自动化 | 未来工作 |
| 无 Cloudflare Tunnel / Access 自动化 | 未来工作 |
| 无 Worker 自定义域名自动化 | 未来工作 |
| 无 Web/Bot DNS UI 集成 | 未来工作 |
| 版本需手动更新 | 未来需自动化或流程约束 |
| 真实 Cloudflare 回归为手动 | 未自动化 |

---

## 10. 未完成 / 未来工作

以下功能不在本阶段范围内，留待未来规划：

1. DNS-01 证书自动化
2. Cloudflare Tunnel + Access for Web Panel
3. Worker 自定义域名自动化
4. Web/Bot DNS 状态 UI 集成
5. 自动 Full Wizard DNS apply（需明确安全设计）
6. DNS 记录删除命令
7. `--force` 覆盖功能
8. 订阅集成
9. 真实 Cloudflare 回归自动化

**注意：在负责人批准下一阶段之前，不要启动上述任何工作。**

---

## 11. 发布/标签策略

- **本次收尾不创建发布标签。**
- 任何标签/发布需要负责人明确批准。
- 仓库保持主线开发状态。

---

## 12. 建议下一阶段

收尾后建议暂停功能工作，等待负责人批准下一阶段。

以下为候选方向：

- **选项 A**：`v2.1.0-planning` — Cloudflare DNS-01 证书自动化
- **选项 B**：`v2.1.0-planning` — Cloudflare Tunnel + Access for Web Panel
- **选项 C**：`v2.1.0-planning` — Web/Bot DNS 状态 UI 集成

**在负责人批准之前，不要启动任何下一阶段工作。**

---

## 13. 最终结论

**PASS — v2.0 DNS / Full Wizard DNS 阶段正式关闭。**

关键确认点：

- DNS CLI 完整可用：plan / validate-profile / apply（dry-run / check / yes）
- Full Wizard DNS 集成完整：profile 写入、validate、plan、check、Summary 状态
- 脏 VPS preflight 问题已修复
- 版本显示已统一
- 真实验证通过（首次 Apply + Full Wizard DNS + 脏 VPS）
- 安全护栏完整：无自动 --yes、无 token 泄露、DNS-only 模式
- 测试覆盖充分：模拟测试 + mock 交互测试 + 真实验证记录
- 生产资源未受影响
- 无发布标签
