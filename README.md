<div align="center">

# NanoBK Proxy Suite

**VPS 四协议节点 + Cloudflare 订阅 + Telegram Bot 控制台 + Web 控制面板**

<br>

![Stable](https://img.shields.io/badge/stable-v1.9.60-blue)
![License](https://img.shields.io/badge/license-private-red)
![Installer](https://img.shields.io/badge/installer-one--click-green)
![Language](https://img.shields.io/badge/language-中文%20%2F%20English-orange)

<br>

> 一个脚本，四条协议，Bot + Web 双控制台。
> 新手也能在全新 VPS 上完成部署。

<br>

[快速安装](#-快速安装) ·
[核心能力](#-核心能力) ·
[Cloudflare 依赖](#-cloudflare-依赖安装) ·
[Cloudflare 隧道登录](#-无图形界面-vps-的-cloudflare-登录隧道) ·
[Bot 命令](#-telegram-bot-命令) ·
[Web 面板](#-web-面板) ·
[安全提醒](#-安全提醒) ·
[常见命令](#-常见命令) ·
[版本说明](#-版本说明)

<br>

<!-- HERO SCREENSHOT PLACEHOLDER -->
<!-- docs/assets/screenshots/hero.png -->

</div>

---

## 稳定版本

| 项目 | 值 |
|------|----|
| **当前稳定 tag** | `v1.9.60` |
| **推荐分支** | `v1.9.60`（不要使用 `main`） |
| **v2.0 开发** | 独立进行中，与本 README 无关 |

> **本 README 仅面向 v1.9.60 稳定版。**
> 所有安装命令均使用 tag `v1.9.60`，确保可复现。
> v2.0 开发内容不在本文档范围内。

---

## 快速安装

### 前置条件

- 一台 **Ubuntu / Debian VPS**（推荐 Ubuntu 22.04+）
- 以 **root** 用户登录（`ssh root@YOUR_VPS_IP`）
- VPS 可正常访问外网

### 一条命令安装（推荐新手）

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/v1.9.60/installer/bootstrap.sh) --branch v1.9.60 -- --lang zh
```

> 安装器会显示中文菜单，选择 **Full Wizard**（完整向导）即可。
> 如果某个阶段失败，阅读 Summary 中的恢复提示。

### 两步安装（更保守）

```bash
curl -fsSL -o /tmp/nanobk-bootstrap.sh https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/v1.9.60/installer/bootstrap.sh
bash /tmp/nanobk-bootstrap.sh --branch v1.9.60 -- --lang zh
```

> 第一步下载脚本，第二步执行。
> 适合需要先检查脚本内容的用户。

### 安装注意事项

- **不要** 混用 `main` 分支或 v2.0 开发内容
- **不要** 在安装过程中中断（Ctrl+C）
- 如果某个阶段失败，查看终端输出的 **Summary**，按照恢复提示操作
- 安装完成后，Bot 和 Web 控制台会自动启动

---

## 核心能力

| 能力 | 说明 |
|------|------|
| **VPS 四协议** | HY2 (UDP 443) · TUIC v5 (UDP 9443) · VLESS Reality (TCP 8443) · Trojan TLS (TCP 2443) |
| **Cloudflare nanok** | 主订阅 Worker，从 KV profile 生成 Clash / Mihomo YAML |
| **nanob 聚合** | 可选聚合 Worker，合并 nanok + edgetunnel backup |
| **edgetunnel 兼容** | 可选增强，edgetunnel 失败不影响主订阅 |
| **nanobk CLI** | 统一入口：status · doctor · install · cf deploy · rotate · test |
| **全部/单协议换密钥** | `nanobk rotate all` / `nanobk rotate hy2` / `nanobk rotate reality` 等 |
| **status JSON** | `nanobk --json status` — 为 Bot / Panel 准备的稳定输出 |
| **Telegram Bot** | Owner-only 授权、状态查询、换密钥二次确认、dry-run 模式 |
| **Web Panel** | 本地 Flask 面板、token 登录、状态/诊断/换密钥、默认 127.0.0.1 |

<!-- WEB DASHBOARD SCREENSHOT PLACEHOLDER -->
<!-- docs/assets/screenshots/web-dashboard.png -->

---

## Cloudflare 依赖安装

Cloudflare 预检（preflight）需要 Node.js、npm 和 Wrangler。
如果 VPS 上没有这些依赖，Cloudflare 阶段会失败。

### 安装 Node.js 22 和 Wrangler

```bash
apt update
apt install -y curl ca-certificates gnupg
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs
node -v
npm -v
npm install -g wrangler
wrangler --version
```

### 两步安装 NodeSource（更保守）

```bash
curl -fsSL -o /tmp/nodesource_setup_22.x https://deb.nodesource.com/setup_22.x
bash /tmp/nodesource_setup_22.x
apt install -y nodejs
```

> 第一步下载安装脚本，第二步执行安装。
> 适合需要先检查脚本内容的用户。

### 验证安装

```bash
node -v      # 应显示 v22.x.x
npm -v       # 应显示 10.x.x
wrangler --version  # 应显示 wrangler 版本号
```

---

## 无图形界面 VPS 的 Cloudflare 登录隧道

Wrangler 登录需要浏览器，但 VPS 通常没有图形界面。
使用 SSH 隧道将 VPS 的 OAuth 回调转发到本地电脑。

<!-- CLOUDFLARE LOGIN SCREENSHOT PLACEHOLDER -->
<!-- docs/assets/screenshots/cloudflare-login.png -->

### 第一步：本地电脑（你的 Mac / Windows）

```bash
ssh -L 8976:127.0.0.1:8976 root@YOUR_VPS_IP
```

> **把 `YOUR_VPS_IP` 替换成你的 VPS 实际 IP 地址。**
> 保持这个终端窗口打开，不要关闭。
> 这条命令让 VPS 的 Wrangler OAuth 回应回到你本地浏览器。

### 第二步：VPS（在上面的 SSH 会话中）

```bash
wrangler login --browser=false
```

### 第三步：本地浏览器

1. 复制 Wrangler 显示的授权 URL
2. 在本地电脑浏览器中打开该 URL
3. 登录 Cloudflare 账号
4. 点击授权（Authorize）

### 第四步：VPS 验证

```bash
wrangler whoami
```

> 如果显示你的 Cloudflare 账户信息，说明登录成功。
> 回到 NanoBK 安装器，继续或重试 Cloudflare 阶段。

---

## Cloudflare Preflight failed 怎么办？

如果 Cloudflare 预检失败，按以下步骤排查：

### 1. 确认 Node.js 已安装

```bash
node -v
```

如果没有版本号，安装 Node.js 22：

```bash
apt update
apt install -y curl ca-certificates gnupg
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt install -y nodejs
```

### 2. 确认 Wrangler 已安装

```bash
wrangler --version
```

如果没有版本号，安装 Wrangler：

```bash
npm install -g wrangler
```

### 3. 运行 SSH 隧道

在本地电脑（不是 VPS）运行：

```bash
ssh -L 8976:127.0.0.1:8976 root@YOUR_VPS_IP
```

保持终端打开。

### 4. 在 VPS 登录 Cloudflare

```bash
wrangler login --browser=false
```

复制显示的 URL，在本地浏览器打开并授权。

### 5. 验证登录

```bash
wrangler whoami
```

### 6. 回到 NanoBK 安装器

返回 NanoBK 安装器，继续或重试 Cloudflare 阶段。

---

## Telegram Bot 命令

<!-- BOT CONTROL CENTER SCREENSHOT PLACEHOLDER -->
<!-- docs/assets/screenshots/bot-control-center.png -->

| 命令 | 说明 |
|------|------|
| `/start` | 启动 Bot，显示欢迎信息 |
| `/status` | 查看 VPS 四协议状态 |
| `/doctor` | 运行环境诊断 |
| `/advanced on` | 开启高级模式（显示更多细节） |
| `/advanced off` | 关闭高级模式 |
| `/advanced status` | 查看高级模式状态 |
| `/status_json` | 查看原始 JSON（受门控保护） |
| `/language` | 切换语言（中文 / English） |
| `/help` | 显示帮助信息 |

> Bot 仅接受 owner 授权的命令。
> 换密钥操作需要二次确认（dry-run 预览 + 确认按钮）。

---

## Web 面板

<!-- WEB LANGUAGE SWITCH SCREENSHOT PLACEHOLDER -->
<!-- docs/assets/screenshots/web-language-switch.png -->

| 功能 | 说明 |
|------|------|
| **Dashboard** | 仪表盘，显示四协议状态概览 |
| **Status** | 详细状态页面 |
| **Doctor** | 环境诊断页面 |
| **Rotate** | 换密钥操作（带 dry-run 预览） |
| **Language** | 语言切换（中文 / English） |
| **Raw JSON** | 原始 JSON 数据（受门控保护，需确认） |

### Web 面板访问（SSH 隧道）

Web 面板默认监听 `127.0.0.1:8080`，不应直接暴露到公网。

在本地电脑运行：

```bash
ssh -L 8080:127.0.0.1:8080 root@YOUR_VPS_IP
```

然后在本地浏览器打开：

```
http://127.0.0.1:8080
```

> **安全建议：** 除非你配置了反向代理并了解安全风险，否则不要将 Web 面板暴露到公网。
> SSH 隧道是最安全的访问方式。

---

## 安全提醒

> **以下内容包含敏感信息，绝不能分享或提交到 Git。**

| 禁止分享 | 说明 |
|----------|------|
| `.nanob.local.env` 文件内容 | 包含真实密钥 |
| `.cloudflare.local.env` 文件内容 | 包含 Cloudflare 凭证 |
| `/etc/nanobk/secrets.private.env` | 系统级密钥文件 |
| Telegram Bot Token | Bot 访问凭证 |
| 订阅 URL | 包含节点信息 |
| Reality 私钥 | 协议加密密钥 |
| Cloudflare 授权结果 | Wrangler 登录凭证 |

### 安全原则

- **不要** `cat` 或 `echo` 任何 env 文件内容
- **不要** 在聊天、论坛、GitHub Issue 中分享上述信息
- **不要** 将 env 文件提交到 Git
- Advanced 模式 **不会** 显示完整密钥（Raw JSON 仍受脱敏保护）
- Bot 和 Web 是 **控制台**，不是数据导出工具

---

## 常见命令

```bash
# 查看版本
nanobk --version

# 查看帮助
nanobk help

# 查看状态（JSON 格式，适合脚本使用）
nanobk --json status

# 交互式安装器
nanobk install

# 仅安装 Bot 模式
nanobk install --mode bot --lang zh

# 仅安装 Web 模式
nanobk install --mode web --lang zh
```

---

## 版本说明

### 当前版本

| 项目 | 值 |
|------|----|
| **Git tag** | `v1.9.60` |
| **CLI 显示** | `nanobk 1.9.58` |
| **是否正常** | 是，这是预期行为 |

> CLI 显示的版本号（`nanobk 1.9.58`）与 Git tag（`v1.9.60`）不同，这是正常的。
> tag 代表发布点，CLI 版本号代表代码快照，两者可以不同步。

### v1.9.60 包含

- 中文优先的 Bot / Web 控制台
- Web 面板中英文切换
- Bot `/language` 语言引导
- Safe status（安全状态显示）
- Doctor summary（诊断摘要）
- Raw JSON 门控（需确认才能查看）
- Advanced mode（高级模式）
- 真实 VPS 冒烟测试
- AI 维护文档

### v1.9.60 不包含

- systemd Bot / Web 产品化
- Web 生产环境运行器
- UI 重新设计
- 订阅二维码投递
- 维修/重启自动化
- Cloudflare 变更工作流
- 指纹脱敏策略
- v2.0 功能

---

## 文档

| 文档 | 说明 |
|------|------|
| [docs/maintenance-map.md](docs/maintenance-map.md) | 维护地图（子系统、保护区域、测试矩阵） |
| [docs/ai-handoff-template.md](docs/ai-handoff-template.md) | AI 交接模板 |
| [docs/stable-tag-gate-v1.9.md](docs/stable-tag-gate-v1.9.md) | v1.9 稳定 tag 门控 |

---

## License

Private use only.
