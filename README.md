# NanoBK Proxy Suite

> 一键部署 VPS 四协议节点 + Cloudflare Clash/Mihomo 订阅 + 自动换密钥 + 可选 edgetunnel backup 聚合。

## 适用用户

- 有一台 VPS（Linux）
- 有 Cloudflare 域名和 Workers
- 想要私有的 Clash/Mihomo 订阅链接
- 不想手动维护多协议配置和密钥轮换

## 核心能力

| 能力 | 说明 |
|------|------|
| **四协议部署** | HY2 (443) / TUIC v5 (9443) / VLESS Reality (8443) / Trojan TLS (2443) |
| **一键换密钥** | 一个脚本生成新凭据、更新 VPS 配置、同步 Cloudflare KV |
| **Cloudflare KV 动态订阅** | 纳米级 Worker 从 KV profile 生成 Clash/Mihomo YAML |
| **YAML 安全输出** | 严格 control character 检查，避免 `yaml: control characters are not allowed` |
| **edgetunnel 可选增强** | 没有 edgetunnel 也能完整运行，配置后追加 backup 节点 |
| **Geo 自动识别** | 使用 ipwho.is 自动识别节点国家/地区，缓存到 KV |

## 架构

```
VPS 四协议 ──rotate-keys.sh──▶ nanok KV Worker ──fetch──▶ nanob Aggregator ──▶ Clients
  (HY2/TUIC/Reality/Trojan)     (profile:main)            (optional merge)
                                     │                          │
                                     │ admin API                │ edgetunnel (optional)
                                     ▼                          ▼
                               Cloudflare KV              edgetunnel Worker
```

## 快速开始

> ⚠️ **当前为 v0.1 productization scaffold。** 以下为规划中的最终命令，尚未完全一键可用。

### 1. 检查 VPS 环境

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/doctor.sh)
```

### 2. 部署 VPS 四协议节点

```bash
sudo bash installer/install-vps.sh --yes \
  --domain proxy.example.com \
  --cert-mode existing \
  --cert-file /etc/letsencrypt/live/proxy.example.com/fullchain.pem \
  --key-file /etc/letsencrypt/live/proxy.example.com/privkey.pem
```

预览模式（不修改系统）：

```bash
sudo bash installer/install-vps.sh --dry-run \
  --domain proxy.example.com --cert-mode self-signed
```

### 3. 部署 Cloudflare Workers

```bash
wrangler login

bash installer/install-cloudflare.sh --yes \
  --create-kv \
  --profile /etc/nanobk/profile.current.json \
  --route-url https://nanok.yourdomain.com
```

### 4. 换密钥

```bash
bash /root/rotate-proxy-keys.sh
```

## 当前状态

- ✅ 完整链路已跑通（VPS 四协议 → nanok Worker → nanob 聚合 → Clash/Mihomo 导入）
- ✅ Shadowrocket 和 Clash/Mihomo 导入验证通过
- 🔄 仓库正在产品化整理中（v0.1 scaffold）
- 📦 现有代码为脱敏模板，不包含真实密钥

## 仓库结构

```
├── README.md
├── docs/                          # 文档
│   ├── architecture.md            # 完整链路架构
│   ├── quickstart.md              # 快速开始
│   ├── vps-setup.md               # VPS 部署指南
│   ├── cloudflare-setup.md        # Cloudflare 部署指南
│   ├── key-rotation.md            # 换密钥指南
│   ├── edgetunnel-optional.md     # edgetunnel 可选说明
│   ├── geo-labeling.md            # Geo 自动识别说明
│   └── troubleshooting.md         # 故障排查
├── installer/                     # 安装脚本
│   ├── install.sh                 # 主入口
│   ├── install-vps.sh             # VPS 安装
│   ├── install-cloudflare.sh      # Cloudflare 安装
│   └── doctor.sh                  # 环境诊断
├── vps/
│   ├── lib/
│   │   ├── common.sh              # 共享函数（日志、dry-run、模板渲染）
│   │   ├── os.sh                  # OS 检测、依赖安装
│   │   ├── download.sh            # 二进制下载（GitHub releases）
│   │   └── profile.sh             # Geo 检测、凭证生成、profile JSON
│   ├── scripts/
│   │   ├── rotate-keys.sh         # 一键换密钥
│   │   ├── healthcheck.sh         # 健康检查
│   │   └── rollback.example.sh    # 回滚示例
│   ├── templates/                 # 配置模板（__PLACEHOLDER__ 语法）
│   └── systemd/                   # systemd 服务模板
├── workers/
│   ├── nanok/src/index.js         # 主订阅 Worker
│   ├── nanob/src/index.js         # 聚合 Worker (edgetunnel 可选)
│   └── shared/
│       ├── yaml-safe.js           # YAML 安全工具
│       └── geo.js                 # Geo 识别模块
├── tests/
│   ├── render-install-vps.sh      # VPS 渲染集成测试
│   ├── rotate-render-only.sh      # 密钥轮换测试
│   ├── wrangler-nanok-dry-run.sh  # nanok bundle 测试
│   └── wrangler-nanob-dry-run.sh  # nanob bundle 测试
├── examples/
│   ├── profile.example.json       # KV profile 示例
│   ├── env.vps.example            # VPS 环境变量示例
│   ├── env.cloudflare.example     # Cloudflare 环境变量示例
│   └── client-import.md           # 客户端导入说明
└── legacy/                        # 原始文件存档
```

## 安全说明

- **不提交真实密钥。** 所有示例使用占位符。
- **admin token 只在 VPS 本地。** 存储在 `/root/.nanok-cf-admin.env`，权限 600。
- **Reality private key 不进入 Cloudflare KV。** 只有 publicKey 和 shortId 存入 KV。
- **换密钥私有记录。** 全量密钥只写入 `chmod 600` 的本地文件，不提交 Git。
- **token 分离。** 公开订阅 token 和 admin token 是不同的密钥。

## Roadmap

| 版本 | 目标 |
|------|------|
| **v0.1** | ✅ 工程整理、产品化结构、文档骨架 |
| **v0.2** | ✅ VPS 一键部署（install-vps.sh 已实现） |
| **v0.3** | ✅ Cloudflare nanok 自动部署（install-cloudflare.sh 已实现） |
| **v0.4** | ✅ nanob 聚合器自动部署 + edgetunnel 可选整合 |
| **v0.5** | 小白化交互向导 |

## License

Private use only.
