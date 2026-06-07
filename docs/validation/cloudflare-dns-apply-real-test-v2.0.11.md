# NanoBK Proxy Suite v2.0.11 — Cloudflare DNS Apply 首次真实验证

## 1. 验证结论

**PASS**

本次验证为 NanoBK Proxy Suite `nanobk cf dns apply` 命令的首次真实 Cloudflare DNS Apply 验证。使用一次性测试主机名创建了 A 记录，确认了幂等性、DNS-only 模式、所有权标记，并在验证完成后手动清理了测试记录。

## 2. 测试环境

| 项目 | 值 |
|------|-----|
| 操作系统 | Ubuntu 24.04.1 LTS |
| 主机名 | grand-peach |
| 用户 | root |
| 项目路径 | /opt/NanoBK-Proxy-Suite |
| CLI 符号链接 | /usr/local/bin/nanobk -> /opt/NanoBK-Proxy-Suite/bin/nanobk |
| Cloudflare Zone | biankai314.uk |
| 一次性测试主机名 | nanobk-test-ab12.biankai314.uk |
| 记录类型 | A |
| 目标 IP | REDACTED_VPS_IPV4 |

## 3. 代码版本

| 项目 | 值 |
|------|-----|
| nanobk 版本 | 2.0.11 |
| Git 提交 | 4960fad |
| 提交信息 | v2.0.11 repair Cloudflare DNS apply CLI consistency |

## 4. 安全范围

本次测试仅针对 Cloudflare DNS Apply 功能，以下内容均未涉及：

- Cloudflare Worker 逻辑
- Cloudflare Tunnel
- Cloudflare Access
- Cloudflare SSL/TLS 证书
- VPS 协议部署模板
- Bot / Web 运行时行为
- Full Wizard 集成
- 订阅链接
- 协议链接（hysteria2 / tuic / vless / trojan）
- Reality 私钥

## 5. 模拟测试结果

在进行真实测试前，先通过了所有模拟测试：

```
$ bash tests/cf-dns-plan.sh
All cf-dns-plan tests passed
exit=0

$ bash tests/cf-dns-apply.sh
All cf-dns-apply tests passed
exit=0
```

## 6. 真实 Cloudflare DNS Apply 流程

### 6.1 仓库同步确认

```
$ nanobk version
nanobk 2.0.11

$ git log -1
4960fad v2.0.11 repair Cloudflare DNS apply CLI consistency

$ nanobk cf dns apply --help
exit=0
```

帮助文本正确显示，包含 `--dry-run`、`--check`、`--yes`、`--api-env`、`--profile`、`--force`（保留）等选项说明。

### 6.2 Profile 验证

```
$ nanobk cf dns validate-profile ...
exit=0
```

Profile 验证通过。

### 6.3 Plan（干跑）

```
$ nanobk cf dns plan ...
exit=0
```

Plan 输出正确显示了计划中的 A 记录、proxied=false 等信息。

### 6.4 Dry-Run

```
$ nanobk cf dns apply --dry-run ...
exit=2
```

退出码 2 符合预期：存在需要创建的记录，但 `--dry-run` 模式不执行任何变更。

### 6.5 Check（仅 GET）

```
$ nanobk cf dns apply --check ...
exit=2
```

退出码 2 符合预期：GET 请求确认记录不存在，需要创建，但 `--check` 模式不执行变更。

### 6.6 首次 Apply（创建记录）

```
$ nanobk cf dns apply --yes ...
exit=0
```

成功创建了 A 记录。记录内容：

- 类型：A
- 主机名：nanobk-test-ab12.biankai314.uk
- 目标 IP：REDACTED_VPS_IPV4
- 代理状态：DNS-only（proxied=false / 灰云）
- 注释标记：`managed-by=nanobk; component=cf-dns-apply; hostname=nanobk-test-ab12.biankai314.uk`

### 6.7 二次 Apply（幂等性确认）

```
$ nanobk cf dns apply --yes ...
exit=0
```

第二次执行结果为 no-op（无操作），确认了幂等性：已存在的匹配记录不会被重复创建或修改。

## 7. Cloudflare Dashboard 验证

在 Cloudflare Dashboard 中手动确认：

- A 记录 `nanobk-test-ab12.biankai314.uk` 已创建
- 目标 IP 为 REDACTED_VPS_IPV4
- 代理状态为 **DNS only**（灰云，proxied=false）
- 注释中包含所有权标记：`managed-by=nanobk; component=cf-dns-apply; hostname=...`

## 8. DNS 解析验证

```
$ dig A nanobk-test-ab12.biankai314.uk
返回 REDACTED_VPS_IPV4
```

DNS 解析正确返回了预期的 IP 地址。

## 9. 清理验证

一次性测试记录已通过 Cloudflare Dashboard 手动删除：

```
$ dig A nanobk-test-ab12.biankai314.uk
无结果返回
```

清理确认通过。测试记录已完全移除。

## 10. 安全 / 隐私验证

本次测试过程中：

- **无 CF_API_TOKEN 泄露**：令牌未出现在任何输出、日志或文档中
- **无 Authorization 头泄露**：API 请求头未被记录或输出
- **无原始 env 文件内容泄露**：env 文件内容未被打印
- **无订阅链接泄露**
- **无协议链接泄露**（hysteria2 / tuic / vless / trojan）
- **无 Reality 私钥泄露**
- **无原始 Cloudflare API 响应泄露**
- **无 workers.dev URL 泄露**

## 11. 未触及的生产记录

以下生产记录在测试过程中未被修改或影响：

- `node.biankai314.uk` — 未触及
- `panel.biankai314.uk` — 未触及
- `nanok.biankai314.uk` — 未触及
- `nanob.biankai314.uk` — 未触及
- hy2 / tuic / trojan / reality 生产 DNS — 未触及
- Cloudflare Worker — 未触及
- Cloudflare Tunnel — 未触及
- Cloudflare Access — 未触及
- Cloudflare SSL/TLS 证书 — 未触及
- VPS 协议部署模板 — 未触及
- Bot / Web 运行时 — 未触及
- Full Wizard — 未触及

## 12. 测试过程中发现的问题

### 问题 A：初始 nanobk 不在 PATH 中

**现象**：直接运行 `nanobk` 命令提示找不到。

**原因**：系统中存在多个 NanoBK 目录。

**解决方案**：
- 将活跃仓库标准化为 `/opt/NanoBK-Proxy-Suite`
- 创建符号链接：`/usr/local/bin/nanobk -> /opt/NanoBK-Proxy-Suite/bin/nanobk`

### 问题 B：v2.0.11 之前的主线不一致

**现象**：活跃仓库版本为 nanobk 2.0.9 / 提交 5770578，`nanobk cf dns plan` 输出仍然显示 "apply not implemented"，且 `nanobk cf dns apply --help` 报错。

**原因**：仓库版本落后于最新的 v2.0.11 修复。

**解决方案**：
- 暂停测试
- 更新至 v2.0.11，确认 `apply --help` 正常工作
- 通过模拟测试后才恢复真实测试

### 问题 C：Cloudflare 手动添加记录 UI 默认为 Proxied

**现象**：Cloudflare Dashboard 的 "Add record" 界面默认将新记录设为 Proxied（橙云）。

**说明**：
- 用户未手动保存任何记录
- NanoBK apply 创建的记录为 DNS-only / proxied=false（灰云）

## 13. 最终结论

**PASS**

NanoBK Proxy Suite v2.0.11 的 `nanobk cf dns apply` 命令通过了首次真实 Cloudflare DNS Apply 验证。测试覆盖了完整的 apply 生命周期：validate → plan → dry-run → check → apply（创建）→ apply（幂等 no-op）→ 清理。

关键确认点：
- 记录成功创建且为 DNS-only 模式
- 幂等性正常工作
- 所有权标记正确写入
- 无安全/隐私泄露
- 生产记录未受影响
- 一次性测试记录已清理

## 14. 下一步建议

本次验证确认了 Cloudflare DNS Apply 基础功能正常。以下功能仍为未来工作：

- Full Wizard 集成
- 证书自动化
- Cloudflare Tunnel
- Cloudflare Access
- Worker 自定义域名
- 订阅集成
- `--force` 覆盖功能
- 删除记录功能
