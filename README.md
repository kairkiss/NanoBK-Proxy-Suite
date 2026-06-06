# NanoBK Proxy Suite

<p align="center">
  <strong>中文优先 · 新手友好 · 安全脱敏 · VPS 四协议代理自动化套件</strong>
</p>

<p align="center">
  <img alt="Stable" src="https://img.shields.io/badge/stable-v1.9.60-blue">
  <img alt="Linux" src="https://img.shields.io/badge/Linux-Ubuntu%2024.04%20%7C%20Debian-green">
  <img alt="Control Plane" src="https://img.shields.io/badge/Bot%20%2B%20Web-Control%20Plane-purple">
  <img alt="Language" src="https://img.shields.io/badge/UI-ZH%20%7C%20EN-orange">
</p>

<p align="center">
  <a href="#-三分钟开始">三分钟开始</a> ·
  <a href="#-你会得到什么">功能概览</a> ·
  <a href="#-新手部署步骤">新手部署</a> ·
  <a href="#-bot--web-控制面">Bot / Web</a> ·
  <a href="#-安全边界">安全边界</a> ·
  <a href="#-常用命令">常用命令</a>
</p>

---

## 这是什么？

**NanoBK Proxy Suite** 是一个面向新手的 VPS 代理自动化套件。

它的目标不是让你手动复制一堆复杂命令，而是让你在一台全新 VPS 上运行一个入口命令，然后跟着中文向导完成：

- VPS 四协议服务部署；
- Cloudflare nanok / nanob 订阅服务配置；
- Telegram Bot 控制面；
- Web Panel 控制面；
- 安全状态查看；
- Doctor 诊断摘要；
- Raw JSON / 高级诊断安全门控；
- 中文默认界面与英文切换。

当前稳定版：**v1.9.60 — Control Plane Stable**

> 本 README 面向 v1.9.60 稳定版。不要把正在开发中的 2.0 内容和本稳定版混用。

---

## 图片预留

后续可以把截图放到 `docs/assets/screenshots/`，再替换下面的占位图路径。

<p align="center">
  <img src="docs/assets/screenshots/hero.png" alt="NanoBK Proxy Suite Preview" width="880">
</p>

<p align="center">
  <img src="docs/assets/screenshots/web-dashboard.png" alt="Web Dashboard" width="420">
  <img src="docs/assets/screenshots/bot-control-center.png" alt="Telegram Bot Control Center" width="420">
</p>

---

## 三分钟开始

在一台新的 Ubuntu / Debian VPS 上，用 root 登录后运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/v1.9.60/installer/bootstrap.sh) --branch v1.9.60 -- --lang zh
```

然后跟着中文菜单走即可。

如果你只想先看看环境是否合适，可以运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/v1.9.60/installer/bootstrap.sh) --branch v1.9.60 -- --mode doctor --lang zh
```

如果你想看可用命令：

```bash
nanobk help
```

> 重点：上面命令显式固定 `--branch v1.9.60`，确保你安装的是稳定 tag，而不是 main 分支上的后续开发版本。

---

## 新手准备清单

部署前建议准备：

| 项目 | 是否必须 | 说明 |
| --- | --- | --- |
| 一台 VPS | 必须 | 推荐 Ubuntu 24.04 / Debian，root 权限，系统干净更好 |
| 一个域名 | 推荐 | 用于 TLS、订阅服务和更稳定的客户端配置 |
| Cloudflare 账号 | 推荐 | 用于 nanok / nanob 订阅服务 |
| Telegram Bot Token | 可选 | 如果你要启用 Telegram Bot 控制面 |
| Web 管理密码 / Token | 可选 | 如果你要启用 Web Panel 控制面 |

你不需要提前懂 systemd、Nginx、Xray、Hysteria、TUIC 或 Cloudflare Worker。安装器会尽量用中文一步一步引导。

---

## 你会得到什么

### VPS 四协议

NanoBK 的稳定部署核心来自 v1.7.27 Full Wizard Productization Final，v1.9.60 不破坏该核心。

支持的协议组合：

- **Hysteria2 / HY2**
- **TUIC v5**
- **Reality**
- **Trojan TLS**

安装器会尽量保持：

- 菜单清楚；
- 状态诚实；
- 失败可恢复；
- 敏感信息不乱打印；
- 关键步骤可解释。

### Cloudflare nanok / nanob 订阅服务

用于生成和维护订阅入口。v1.9.60 的 README 只面向稳定使用，不建议新手手动改 Worker 核心。

### Telegram Bot 控制面

Bot 是手机上的控制中心：

- `/start` 中文控制中心；
- `/status` 安全状态摘要；
- `/doctor` 新手诊断摘要；
- `/advanced on/off/status` 临时高级诊断；
- `/status_json` 高级模式下查看脱敏 Raw JSON；
- `/language` 查看语言说明；
- 按钮菜单用于状态、恢复、诊断、Web Panel 引导。

Bot 默认中文。命令名保持英文，便于兼容 Telegram 命令体系。

### Web Panel 控制面

Web 是浏览器里的状态面板：

- Dashboard 安全卡片；
- Status 安全状态；
- Doctor 摘要诊断；
- Raw JSON 高级门控；
- 中文默认；
- 登录后可在中文 / English 间切换；
- logout 后恢复默认语言。

v1.9.60 中 Web 推荐通过本地绑定和 SSH tunnel 访问，不建议直接裸露公网。

---

## 新手部署步骤

### 第 1 步：登录 VPS

在你的电脑上连接 VPS：

```bash
ssh root@你的VPS地址
```

### 第 2 步：运行稳定版安装命令

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/v1.9.60/installer/bootstrap.sh) --branch v1.9.60 -- --lang zh
```

安装器会把项目放到默认目录：

```text
/opt/NanoBK-Proxy-Suite
```

并启动中文向导。

### 第 3 步：选择 Full Wizard

新手建议选择完整向导。它会按阶段引导你完成：

1. VPS 协议部署；
2. Cloudflare 订阅服务；
3. Telegram Bot 控制面；
4. Web Panel 控制面；
5. 最终 Summary。

如果某一步失败，先看 Summary 和恢复提示，不要直接乱改配置文件。

### 第 4 步：检查状态

安装完成后可以运行：

```bash
nanobk --version
nanobk --json status
```

v1.9.60 稳定版中，版本显示应为：

```text
nanobk 1.9.58
```

说明：`v1.9.60` 是稳定 tag；`1.9.58` 是 CLI version display 修复后的内部显示版本。两者不冲突。

### 第 5 步：打开 Web Panel

Web Panel 默认建议本地访问或通过 SSH tunnel 访问。

示例：如果 Web 监听 VPS 本机 `127.0.0.1:8080`，你可以在本地电脑运行：

```bash
ssh -L 8080:127.0.0.1:8080 root@你的VPS地址
```

然后浏览器打开：

```text
http://127.0.0.1:8080
```

> 不建议把 Web Panel 直接暴露到公网。请优先使用 SSH tunnel 或你明确理解的反向代理方案。

### 第 6 步：使用 Telegram Bot

如果你启用了 Bot，进入你的 Telegram Bot 聊天窗口，发送：

```text
/start
```

常用命令：

```text
/status
/doctor
/advanced on
/status_json
/advanced off
/language
/help
```

---

## Bot / Web 控制面

### Web 页面结构

| 页面 | 用途 |
| --- | --- |
| Dashboard | 总览，适合新手查看当前系统是否健康 |
| Status | 更完整的安全状态卡片 |
| Doctor | 默认显示新手诊断摘要，高级模式下显示完整脱敏诊断 |
| Rotate | 密钥轮换入口，默认有确认 / dry-run 保护 |
| Language | 导航栏中可切换中文 / English |

### Bot 菜单结构

| 按钮 / 命令 | 用途 |
| --- | --- |
| 状态总览 | 查看安全摘要 |
| 恢复帮助 | 查看安全恢复建议 |
| 诊断检查 | 引导使用 Doctor / Advanced / Raw JSON |
| 高级模式 | 临时开启高级诊断，15 分钟后过期 |
| 轮换密钥 | 显示轮换命令和确认提醒，不直接乱执行 |
| Web Panel | 显示 Web 使用引导，不暴露原始 URL |
| 帮助 | 显示命令说明 |

---

## 安全边界

NanoBK v1.9.60 的设计原则是：**默认安全，新手不直接看到危险细节，高级诊断也必须脱敏。**

### 默认不会展示

- 原始 VPS IP；
- 原始域名；
- workers.dev URL；
- 订阅 URL / path；
- Telegram Bot token；
- Cloudflare token；
- Admin token；
- Reality private key；
- `.env` 原文内容。

### Advanced mode 不是“解除脱敏”

高级模式只代表：你临时允许看到更多诊断结构。

它不代表可以显示 secrets。Raw JSON 和完整 Doctor 输出仍应脱敏。

### 不要这样做

不要把下面内容发给别人，也不要粘贴到公开聊天里：

```text
bot/.env
web/.env
.cloudflare.local.env
.nanob.local.env
/root/.nanok-cf-admin.env
/etc/nanobk/secrets.private.env
```

不要随便执行网上陌生人给你的 rotate、repair、Cloudflare 修改命令。

---

## 常用命令

### 查看版本

```bash
nanobk --version
```

### 查看帮助

```bash
nanobk help
```

### 查看 JSON 状态

```bash
nanobk --json status
```

### 运行 Doctor

```bash
nanobk doctor
```

### 安装 / 恢复全局 CLI

```bash
nanobk install-cli
```

### 只运行 Web 安装向导

```bash
bash installer/install.sh --mode web --lang zh
```

### 只运行 Bot 安装向导

```bash
bash installer/install.sh --mode bot --lang zh
```

### 英文界面安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/v1.9.60/installer/bootstrap.sh) --branch v1.9.60 -- --lang en
```

---

## 目录结构

```text
NanoBK-Proxy-Suite/
├── bin/                    # nanobk CLI
├── bot/                    # Telegram Bot 控制面
├── web/                    # Web Panel 控制面
├── installer/              # 安装器、Full Wizard、Doctor
├── lib/                    # 共享安全逻辑，例如 redaction helper
├── workers/                # Cloudflare Worker 相关内容
├── tests/                  # 静态 / mock / 回归测试
└── docs/                   # 验证、规划、维护文档
```

---

## 维护文档

v1.9.60 已经为后续维护准备了“无记忆 AI 也能定点修复”的文档：

- [`docs/maintenance-map.md`](docs/maintenance-map.md) — 子系统归属、保护区、测试矩阵；
- [`docs/ai-handoff-template.md`](docs/ai-handoff-template.md) — 给后续 AI / 协作者的任务交接模板；
- [`docs/stable-tag-gate-v1.9.md`](docs/stable-tag-gate-v1.9.md) — v1.9 稳定版 gate 记录；
- [`docs/validation-v1.9.60-stable-closeout-checkpoint.md`](docs/validation-v1.9.60-stable-closeout-checkpoint.md) — 稳定版收口验收。

如果你要继续开发，请先阅读维护地图，不要直接大改安装器和部署核心。

---

## v1.9.60 包含什么

v1.9.60 是 **Control Plane Stable**，重点是稳定、安全、中文默认和可维护：

- 保护 v1.7.27 部署核心；
- 中文默认 Bot/Web 控制面；
- Web 中文 / English session 切换；
- Bot `/language` 引导；
- 安全状态摘要；
- Doctor 新手摘要；
- Advanced mode 临时高级诊断；
- Raw JSON gate；
- Web/Bot 脱敏输出；
- 多轮真实 VPS 控制面 smoke test；
- AI maintenance handoff 文档。

---

## v1.9.60 不包含什么

这些不是 v1.9.60 stable 的目标，后续可进入 v2.0 定点增强：

- Bot/Web systemd 产品化；
- Web production runner；
- 更漂亮的 Web UI redesign；
- fingerprint/hash redaction policy；
- raw subscription delivery；
- subscription QR delivery；
- repair/restart 真实操作流；
- Cloudflare mutation 控制面；
- 完整干净 VPS 发布回归。

---

## 故障排查

### 命令不存在：nanobk not found

进入项目目录后恢复 CLI：

```bash
cd /opt/NanoBK-Proxy-Suite
bash installer/install.sh --mode commands --lang zh
nanobk install-cli
```

### Web 打不开

优先检查：

```bash
cd /opt/NanoBK-Proxy-Suite/web
bash run.sh
```

然后使用 SSH tunnel：

```bash
ssh -L 8080:127.0.0.1:8080 root@你的VPS地址
```

### Bot 不响应

优先检查 Bot 是否启动：

```bash
cd /opt/NanoBK-Proxy-Suite/bot
bash run.sh
```

如果你更换过 Bot Token，请重新运行 Bot 安装向导，不要把 token 粘贴到公开聊天。

### 状态看起来不对

先运行：

```bash
nanobk doctor
nanobk --json status
```

然后看 Web Dashboard / Doctor 或 Bot `/status` / `/doctor`。

---

## 版本说明

- 稳定 tag：`v1.9.60`
- 推荐安装：固定 `--branch v1.9.60`
- CLI 显示版本：`nanobk 1.9.58`
- 默认语言：中文
- 英文支持：`--lang en` 或 `NANOBK_LANG=en`

---

## 免责声明

本项目用于你自己的 VPS 自动化部署与控制面管理。请遵守你所在地区、VPS 服务商和网络服务的相关规则。

不要泄露 token、私钥、订阅链接、env 文件内容。遇到问题时，优先提供脱敏后的截图或摘要。

---

## License

See [`LICENSE`](LICENSE).
