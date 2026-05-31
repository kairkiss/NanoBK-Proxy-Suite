# NanoBK Proxy Suite

> VPS 四协议节点 + Cloudflare Clash/Mihomo 订阅 + 自动换密钥 + 可选 edgetunnel 聚合

**v1.6.4** — CLI Core + Telegram Bot + Web Panel + Unified Beginner Installer。

## 最快开始

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/bootstrap.sh)
```

或手动 clone：

```bash
git clone https://github.com/kairkiss/NanoBK-Proxy-Suite.git
cd NanoBK-Proxy-Suite
bash installer/install.sh
```

## 核心能力

| 能力 | 说明 |
|------|------|
| **VPS 四协议** | HY2 (UDP 443) / TUIC v5 (UDP 9443) / VLESS Reality (TCP 8443) / Trojan TLS (TCP 2443) |
| **Cloudflare nanok** | 主订阅 Worker，从 KV profile 生成 Clash/Mihomo YAML |
| **nanob 聚合** | 可选聚合 Worker，合并 nanok + edgetunnel backup |
| **edgetunnel 兼容** | 可选增强，edgetunnel 失败不影响主订阅 |
| **nanobk CLI** | 统一入口：status / doctor / install / cf deploy / rotate / test |
| **全部/单协议换密钥** | `nanobk rotate all` / `nanobk rotate hy2` / `nanobk rotate reality` 等 |
| **status JSON** | `nanobk --json status` — 为 Bot/Panel 准备的稳定输出 |
| **Telegram Bot** | Owner-only 授权、状态查询、换密钥二次确认、dry-run 模式 |
| **Web Panel** | 本地 Flask 面板、token 登录、状态/诊断/换密钥、默认 127.0.0.1 |

## 不包含在 v1.0

- Telegram Bot（计划 v1.1）
- Web Panel（计划 v1.2）
- Let's Encrypt 自动证书
- edgetunnel 自动部署

TG Bot / Web Panel 属于后续控制层，会调用 `nanobk` CLI 命令，不复制底层逻辑。

## nanobk CLI 用法

```bash
nanobk status                          # 显示 VPS / Cloudflare 状态
nanobk --json status                   # JSON 输出
nanobk doctor                          # 环境诊断
nanobk install                         # 交互式安装器
nanobk install-cli                     # 安装到 /usr/local/bin
nanobk cf deploy --create-kv ...       # 部署 Cloudflare Workers
nanobk rotate all                      # 全部换密钥
nanobk rotate hy2                      # 只换 HY2
nanobk rotate reality --skip-cloudflare # 只换 Reality，不同步 CF
nanobk test                            # 运行测试
nanobk test --all                      # 包含 wrangler bundle 测试
```

## 文档

| 文档 | 说明 |
|------|------|
| [docs/quickstart.md](docs/quickstart.md) | 快速开始 |
| [docs/key-rotation.md](docs/key-rotation.md) | 换密钥指南 |
| [docs/cloudflare-setup.md](docs/cloudflare-setup.md) | Cloudflare 部署 |
| [docs/test-matrix.md](docs/test-matrix.md) | 测试矩阵 |
| [docs/release-v1.0.md](docs/release-v1.0.md) | v1.0 Release Notes |
| [docs/roadmap.md](docs/roadmap.md) | Roadmap |
| [docs/troubleshooting.md](docs/troubleshooting.md) | 故障排查 |

## 安全提醒

以下文件包含真实密钥，绝不能提交到 Git：

- `.cloudflare.local.env` / `.nanob.local.env`
- `/etc/nanobk/secrets.private.env`
- `/root/.nanok-cf-admin.env`

## License

Private use only.
