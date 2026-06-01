# NanoBK Proxy Suite — Roadmap

## 0.x 系列：核心层（CLI/脚本）— Completed

| 版本 | 内容 |
|------|------|
| v0.1 | 工程整理、产品化结构、文档骨架 |
| v0.2 | VPS 一键部署（install-vps.sh） |
| v0.3 | Cloudflare nanok 自动部署（install-cloudflare.sh） |
| v0.3.1-0.3.3 | 部署路径修复、密钥轮换集成、回滚安全加固 |
| v0.4 | nanob 聚合器自动部署 + edgetunnel 可选整合 |
| v0.5 | 小白化交互入口（install.sh） |
| v0.5.1-0.5.2 | 安全修复、文档完善 |
| v0.6 | 远程一行命令 bootstrap（bootstrap.sh） |
| v0.6.1 | Bootstrap dry-run 行为优化 |
| v0.7 | nanobk 统一 CLI foundation（bin/nanobk） |
| v0.7.1 | CLI dry-run 和 JSON 输出加固 |
| v0.8 | install-cli + status Cloudflare 可见性 |
| v0.8.1-0.8.2 | CLI safety patch + env parser 安全测试 |
| v0.9 | 单协议换密钥（nanobk rotate hy2/tuic/reality/trojan） |
| v0.9.1 | 单协议 profile 测试加固 |
| **v1.0.0** | **CLI Core Release** — 0.x 核心能力封版 |
| v1.0.1-1.0.3 | Release docs polish + production installer hotfixes |

## 1.x 系列：控制层（Bot / Panel）

1.x 在 0.x 稳定 CLI 之上构建控制层。1.x 不复制底层逻辑，只调用 `nanobk` CLI 命令。

| 版本 | 内容 |
|------|------|
| **v1.1.0** | ✅ Telegram Bot foundation（状态查询、换密钥确认、dry-run） |
| v1.1.1-1.1.2 | Bot safety polish + output ANSI stripping |
| **v1.2.0** | ✅ Web Panel foundation（Flask 面板、token 登录、rotate 确认） |
| v1.2.1 | Web Panel security polish (CSRF, secret key validation, JSON redaction) |
| **v1.3.0** | ✅ Cloudflare full automation validation (preflight, profile safety, nanob fallback) |
| v1.3.1 | Cloudflare preflight hotfix (--preflight, --validate-profile-only) |
| v1.3.2 | Wrangler 4 + nanob Service Binding hotfix |
| v1.3.3 | Wrangler KV parser hotfix |
| **v1.4.0** | ✅ Unified beginner installer foundation (language, modes, Bot/Web config) |
| v1.4.1-1.4.3 | Installer safety, CF sync consistency, status polish |
| **v1.5.0** | ✅ Unified beginner installer practical flow (preflight, guided CF/Bot/Web, summary) |
| v1.5.1 | Unified installer safety and fidelity hotfix |
| v1.5.2 | Dry-run preflight safety hotfix |
| **v1.6.0** | ✅ Clean VPS full wizard validation prep |
| v1.6.1 | Validation plan safety polish |
| v1.6.2 | Unified installer recovery and noninteractive hotfix |
| v1.6.3 | Unified installer dependency and test failure hotfix |
| v1.6.4 | Test failure propagation verification hotfix |
| v1.6.5 | Noninteractive test timeout guard hotfix |
| **v1.7.0** | ✅ Clean full wizard productization |
| v1.7.1 | Full wizard behavior hardening |
| v1.7.2 | Full wizard retry flow hardening |
| v1.7.3 | Full wizard command execution state hardening |
| v1.7.4 | Full wizard control plane state propagation |
| v1.7.5 | Real VPS full wizard UX hardening |
| v1.7.6 | Full wizard critical state and admin env hardening |
| v1.7.7 | Full wizard review, resume, and existing resource recovery |
| v1.7.8 | Full wizard interaction harness and real review flow |
| v1.7.9 | Full wizard real interaction mock hardening |
| v1.7.10 | Full wizard flow wiring cleanup |
| v1.7.11 | Full wizard dynamic mock and Cloudflare UX completion |
| v1.8 | 操作日志 |
| v1.7 | 权限控制 |

### 1.x 架构原则

1.x 的 Bot / Panel **不直接修改配置文件**，而是调用 `nanobk` CLI 命令：

```bash
nanobk status
nanobk doctor
nanobk rotate all
nanobk rotate hy2
nanobk cf sync
```

如果 `nanobk` 命令失败，1.x 应该显示错误而不是尝试自己修复。

### 分层边界

```
┌─────────────────────────────────────────┐
│  1.x 控制层                             │
│  Telegram Bot / Web Panel / API         │
│  调用 nanobk CLI 命令                   │
├─────────────────────────────────────────┤
│  0.x 核心层 (v1.0.0)                    │
│  bin/nanobk CLI                         │
│  installer/ scripts                     │
│  vps/scripts/                           │
│  workers/nanok + nanob                  │
└─────────────────────────────────────────┘
```
