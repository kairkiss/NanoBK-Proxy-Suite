# NanoBK Proxy Suite — Roadmap

## 0.x 系列：核心层（CLI/脚本）

0.x 的目标是完成一个稳定、可独立运行的 CLI/脚本产品闭环，不依赖任何外部控制面板。

### 已完成

| 版本 | 内容 |
|------|------|
| v0.1 | 工程整理、产品化结构、文档骨架 |
| v0.2 | VPS 一键部署（install-vps.sh） |
| v0.3 | Cloudflare nanok 自动部署（install-cloudflare.sh） |
| v0.3.1-0.3.3 | 部署路径修复、密钥轮换集成、回滚安全加固 |
| v0.4 | nanob 聚合器自动部署 + edgetunnel 可选整合 |
| v0.5 | 小白化交互入口（install.sh） |
| v0.5.1-0.5.2 | 安全修复、文档完善 |
| v0.6 | ✅ 远程一行命令 bootstrap（bootstrap.sh） |
| v0.7 | ✅ nanobk 统一 CLI foundation（bin/nanobk） |
| v0.8 | ✅ install-cli + status Cloudflare 可见性 |
| v0.8.1 | ✅ CLI safety patch: install-cli dry-run + safe env parsing |

### 计划中

| 版本 | 内容 |
|------|------|
| v0.6 | Let's Encrypt 证书自动申请集成 |
| v0.7 | edgetunnel Worker 自动部署 + internal auth 自动配置 |
| v0.8 | `nanobk` 统一 CLI 入口（status / doctor / rotate / cf sync） |
| v0.9 | 端到端集成测试（Docker 容器内完整流程） |
| v0.10 | 0.x 功能冻结，进入 1.x |

### 0.x 架构原则

- 所有能力通过 Bash 脚本实现，可在任何 Linux VPS 上独立运行
- 不依赖数据库、不依赖外部服务（除 Cloudflare API）
- 所有配置文件为纯文本（JSON / YAML / env）
- 密钥轮换、服务管理、订阅同步全部可通过命令行完成
- 为 1.x 提供稳定可调用的内部命令接口

## 1.x 系列：控制层（Bot / Panel）

1.x 在 0.x 稳定 CLI 之上构建控制层。1.x 不复制底层逻辑，只调用 0.x 的统一命令。

### 规划中

| 版本 | 内容 |
|------|------|
| v1.0 | Telegram Bot：状态查询、一键换密钥、订阅链接推送 |
| v1.1 | Web Panel：可视化管理界面 |
| v1.2 | 流量监控：每个节点的连接数 / 流量统计 |
| v1.3 | 单协议换密钥：只换 HY2 / 只换 TUIC / etc. |
| v1.4 | Cloudflare 配置向导：Web 界面引导 KV / Worker 部署 |
| v1.5 | 操作日志：记录所有管理操作 |
| v1.6 | 权限控制：多用户 / 角色分离 |

### 1.x 架构原则

1.x 的 Bot / Panel **不直接修改配置文件**，而是调用 0.x 的统一 CLI 命令：

```bash
# 状态查询
nanobk status

# 环境诊断
nanobk doctor

# 全量换密钥
nanobk rotate all

# 单协议换密钥
nanobk rotate hy2
nanobk rotate tuic
nanobk rotate reality
nanobk rotate trojan

# Cloudflare 同步
nanobk cf sync

# 流量查看
nanobk traffic
```

这些命令是 0.x 的输出接口，1.x 只是调用者。如果 0.x 命令失败，1.x 应该显示错误而不是尝试自己修复。

### 分层边界

```
┌─────────────────────────────────────────┐
│  1.x 控制层                             │
│  Telegram Bot / Web Panel / API         │
│  调用 nanobk CLI 命令                   │
├─────────────────────────────────────────┤
│  0.x 核心层                             │
│  install.sh / install-vps.sh            │
│  install-cloudflare.sh / rotate-keys.sh │
│  healthcheck.sh / doctor.sh             │
│  workers/nanok / workers/nanob          │
└─────────────────────────────────────────┘
```
