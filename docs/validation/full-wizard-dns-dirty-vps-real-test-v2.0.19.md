# NanoBK Proxy Suite v2.0.19 — Full Wizard DNS 脏 VPS 真实验证

## 1. 验证结论

| 项目 | 结论 |
|------|------|
| T19 | **PASS WITH PRODUCT ISSUE** |
| T20 | **PASS** |

T19 首次在真实 VPS 上验证 Full Wizard Cloudflare DNS Plan/Check 集成，发现了脏 VPS 上 preflight 阻塞问题。v2.0.19 修复了该问题后，T20 在同一脏 VPS 上重新验证通过。

## 2. 背景

NanoBK Proxy Suite v2.0.13 引入了 Full Wizard Cloudflare DNS Plan/Check 骨架。此前仅通过模拟测试验证。T19 为首次真实 VPS 验证，T20 为 v2.0.19 修复后的回归验证。

## 3. 测试环境

| 项目 | 值 |
|------|-----|
| 操作系统 | Ubuntu 24.04.1 LTS |
| 主机名 | grand-peach |
| 用户 | root |
| 项目路径 | /opt/NanoBK-Proxy-Suite |
| CLI 符号链接 | /usr/local/bin/nanobk -> /opt/NanoBK-Proxy-Suite/bin/nanobk |
| Cloudflare Zone | biankai314.uk |
| Cloudflare API env | /etc/nanobk/cloudflare-api.env |
| api-env 权限 | 600 |
| api-env 所有者 | root/root |

## 4. 代码版本

| 项目 | 值 |
|------|-----|
| Git 提交 | 1400e4e |
| 提交信息 | v2.0.19 fix Full Wizard preflight split |
| nanobk 版本显示 | 2.0.11（版本显示不一致，见第 17 节） |
| installer 横幅 | NanoBK Proxy Suite Installer v1.9.58 |

## 5. 脏 VPS 初始状态

测试开始前，VPS 上已有 NanoBK 代理服务运行：

| 服务 | 端口 | 协议 | 进程 |
|------|------|------|------|
| HY2 | 443 | udp | hysteria |
| TUIC | 9443 | udp | tuic-server |
| Reality | 8443 | tcp | xray |
| Trojan | 2443 | tcp | xray |

## 6. T19 发现

**结论：PASS WITH PRODUCT ISSUE**

T19 在停止代理服务后确认 Full Wizard DNS 子阶段正常工作。但在脏 VPS（服务运行中）测试时发现：

- Full Wizard Phase 0 Preflight 在用户选择是否配置 VPS 之前检查了协议端口
- 现有服务占用了 HY2/TUIC/Reality/Trojan 端口
- Full Wizard 在到达 DNS 阶段之前退出
- 阻塞了真实场景："已有 VPS / 已有 NanoBK 部署，只想继续配置 Cloudflare DNS"

## 7. v2.0.19 修复摘要

| 项目 | 值 |
|------|-----|
| 提交 | 1400e4e588640c95270da4b71488d942e6483158 |
| 提交信息 | v2.0.19 fix Full Wizard preflight split |

修复内容：
- Full Wizard Phase 0 现在调用 `run_unified_preflight common`（公共范围预检）
- 协议端口检查不再在用户选择是否配置 VPS 之前运行
- 严格端口检查仍适用于实际 VPS 部署/重新配置
- 跳过 VPS 的用户可以继续到 Cloudflare DNS 准备/检查
- Full Wizard 仍然不会自动执行 `apply --yes`

## 8. T20 真实验证流程

### 8.1 启动 Full Wizard

在脏 VPS 上启动 Full Wizard，VPS 协议端口被现有服务占用。

### 8.2 Phase 0 Preflight

Preflight 通过，未检查/阻塞协议端口。用户选择"推荐继续"。

### 8.3 跳过 VPS

用户选择跳过 VPS 配置。Wizard 打印提示：VPS 协议端口可能已被现有服务占用，VPS 阶段已跳过，作为现有部署继续。

### 8.4 Cloudflare DNS 子阶段

用户输入：
- zoneName: `biankai314.uk`
- nodePrefix: `nanobk-t20-pzgk`
- ipv4: `REDACTED_VPS_IPV4`
- ipv6: 跳过

### 8.5 DNS Profile 写入

- 路径：`/etc/nanobk/cloudflare-dns-profile.json`
- 权限：600
- 所有者/组：root/root

## 9. Cloudflare DNS Profile 验证

Profile 文件已正确写入，包含预期的 zoneName、nodePrefix、ipv4 字段，defaultProxied 为 false。

## 10. Validate / Plan 验证

```
$ nanobk cf dns validate-profile --profile /etc/nanobk/cloudflare-dns-profile.json
exit=0

$ nanobk cf dns plan --profile /etc/nanobk/cloudflare-dns-profile.json
exit=0
```

validate-profile 和 plan 均通过。

## 11. GET-only Check 验证

Wizard 内部 `apply --check` 以 GET-only 模式运行。

独立命令验证：

```
$ nanobk cf dns apply --profile ... --api-env ... --check
exit=2
```

退出码 2 符合预期：需要创建记录，但 `--check` 模式不执行变更。

## 12. Summary 验证

Full Wizard Summary 显示：

| 字段 | 值 |
|------|-----|
| dns_profile | written |
| dns_plan | planned |
| dns_check | check_passed_create_needed |
| dns_apply | manual_apply_pending |

Summary 明确说明 Full Wizard 不会自动执行 apply。手动 `apply --yes` 命令仅作为用户指令显示。

## 13. DNS 变更验证

- `apply --yes` 未执行
- `dig A nanobk-t20-pzgk.biankai314.uk +short` 在测试前后均无结果
- 未创建任何 DNS 记录

## 14. 现有服务保全

测试完成后：

- 协议端口仍被占用
- 现有代理服务未停止或损坏
- HY2/TUIC/Reality/Trojan 服务正常运行

## 15. 安全 / 隐私验证

本次测试过程中：

- **无 CF_API_TOKEN 泄露**：令牌未出现在任何输出、日志或文档中
- **无 Authorization 头泄露**：API 请求头未被记录或输出
- **无原始 env 文件内容泄露**：env 文件内容未被打印
- **无订阅链接泄露**
- **无协议链接泄露**（hysteria2 / tuic / vless / trojan）
- **无 Reality 私钥泄露**
- **无 workers.dev URL 泄露**
- **无原始 Cloudflare API 响应泄露**

## 16. 未触及的生产资源

以下生产资源在测试过程中未被修改或影响：

- `node.biankai314.uk` — 未触及
- `panel.biankai314.uk` — 未触及
- `nanok.biankai314.uk` — 未触及
- `nanob.biankai314.uk` — 未触及
- hy2 / tuic / trojan / reality 生产 DNS 记录 — 未触及
- Cloudflare Worker — 未触及
- Cloudflare Tunnel — 未触及
- Cloudflare Access — 未触及
- Cloudflare SSL/TLS 证书 — 未触及
- Cloudflare Worker 自定义域名 — 未触及
- Cloudflare KV — 未触及
- VPS 协议部署模板 — 未触及
- Bot 运行时 — 未触及
- Web 运行时 — 未触及
- Full Wizard 自动 apply --yes 路径 — 未触及

## 17. 剩余产品打磨

### 17.1 版本显示不一致

| 来源 | 显示版本 |
|------|----------|
| Git 提交 | v2.0.19 |
| `nanobk version` | 2.0.11 |
| installer 横幅 | v1.9.58 |

版本显示未随代码提交同步更新。建议下一个任务：`v2.0.21 — Version Display Consistency Polish`

### 17.2 主机名可见性

手动 apply 指令显示配置的主机名。这在交互式输出中可接受。未来的 operation-log / Web / Bot 界面必须继续谨慎处理类地址值。

## 18. 最终结论

**T19: PASS WITH PRODUCT ISSUE** — 发现脏 VPS preflight 阻塞问题。

**T20: PASS** — v2.0.19 修复后，脏 VPS 上 Full Wizard DNS Plan/Check 集成验证通过。

关键确认点：
- v2.0.19 修复了脏 VPS preflight 阻塞问题
- 脏 VPS 上跳过 VPS 后 DNS 阶段正常工作
- DNS profile 正确写入（chmod 600）
- validate / plan / check 均通过
- Summary 正确显示 manual_apply_pending
- 未执行 apply --yes
- 未创建 DNS 记录
- 现有代理服务未受影响
- 无安全/隐私泄露

以下功能仍为未来工作：
- 证书自动化
- Cloudflare Tunnel
- Cloudflare Access
- Worker 自定义域名
- 订阅集成
- `--force` 覆盖功能
- 删除记录功能

## 19. 下一步建议

1. **版本显示一致性打磨**：`v2.0.21 — Version Display Consistency Polish`
2. **继续真实 VPS 验证**：在不同环境（干净 VPS、不同区域）上重复验证
3. **Full Wizard Cloudflare Worker 部署集成**：在 DNS 准备完成后集成 Worker 部署流程
