# NanoBK Proxy Suite — Release Notes

## v1.0.3 — Installed Rotate and Reality Rotation Hotfix

v1.0.2 修复了生产安装，但暴露了安装后 rotate 的两个问题，v1.0.3 已修复：

- `/opt/nanobk/bin/rotate-keys.sh` 找不到 lib → 安装器现在复制 lib 到 `/opt/nanobk/lib/`
- `rotate all` / `rotate reality` Reality private key empty → 统一 x25519 parser 支持新版 Xray 输出

如果用户已安装 v1.0.2，升级到 v1.0.3 后重新执行 install-vps.sh --force 以复制新 lib。

## v1.0.2 — Production Installer Hotfix

v1.0.0 在真实 Ubuntu 24.04 VPS 上安装时发现以下问题，v1.0.2 已修复：

- Hysteria 最新 release 是裸二进制，不是 tar.gz → 已支持
- TUIC 最新 release 是裸二进制，不是 zip → 已支持
- Xray x25519 输出格式解析失败 → 已改为大小写/空格容错
- TUIC v1.0.0 不兼容 `udp_relay_mode` 和整数 `gc_interval` → 已移除

如果用户已经使用 v1.0.0 手动安装成功但 TUIC 失败，升级到 v1.0.2 后重新运行安装器即可。

## v1.0.0 — CLI Core Release

## v1.0 是什么

NanoBK Proxy Suite v1.0.0 是 CLI Core 版本。

它提供了一套基于脚本/CLI 的产品化工作流，用于 VPS 代理部署、Cloudflare 订阅生成、聚合和密钥轮换。

所有核心能力通过 Bash 脚本和 `nanobk` 统一 CLI 实现，可在任何 Linux VPS 上独立运行，不依赖数据库或外部服务（除 Cloudflare API）。

## v1.0 包含

- 一行 bootstrap 安装器
- 交互式安装向导
- VPS 四协议配置生成与安装器
- Cloudflare nanok 主订阅 Worker 部署
- 可选 nanob 聚合 Worker 部署
- 可选 edgetunnel 聚合兼容
- `nanobk` 统一 CLI（status / doctor / install / cf deploy / rotate / test）
- `nanobk --json status` JSON 输出（为未来 Bot/Panel 准备）
- 全部/单协议换密钥
- 本地安全测试套件

## v1.0 不包含

- Telegram Bot
- Web Panel
- 自动流量图表
- Let's Encrypt 自动证书
- edgetunnel 自动部署
- 真实 VPS + Cloudflare 的公共 CI E2E 测试

以上功能属于 1.x 后续控制层，会调用 `nanobk` CLI 命令，不复制底层逻辑。

## 推荐安装路径

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/bootstrap.sh)
```

或手动：

```bash
git clone https://github.com/kairkiss/NanoBK-Proxy-Suite.git
cd NanoBK-Proxy-Suite
bash installer/install.sh
```

## 推荐验收命令

```bash
# Version check
bash bin/nanobk --version

# Status (text)
bash bin/nanobk status

# Status (JSON)
bash bin/nanobk --json status

# Dry-run tests
bash bin/nanobk test --dry-run

# Full test suite
bash tests/render-install-vps.sh
bash tests/rotate-render-only.sh
bash tests/nanobk-cli-dry-run.sh
bash tests/nanobk-status-cloudflare.sh
```

## 发布 tag 建议

只输出建议命令，不自动执行：

```bash
git tag -a v1.0.0 -m "NanoBK Proxy Suite v1.0.0 CLI Core Release"
git push origin v1.0.0
```

## 安全提醒

以下文件包含真实密钥，绝不能提交到 Git：

- `.cloudflare.local.env`
- `.nanob.local.env`
- `/etc/nanobk/secrets.private.env`
- `/root/.nanok-cf-admin.env`
- `/root/proxy-key-rotation-latest.private.md`

## 后续规划

| 版本 | 内容 |
|------|------|
| v1.1 | Telegram Bot（调用 nanobk CLI） |
| v1.2 | Web Panel（调用 nanobk CLI） |
| v1.3 | 流量监控 |
| v1.4 | 单协议换密钥审计、日志与权限增强 |
| v1.5 | Cloudflare 配置向导 |
| v1.6 | 操作日志 |
| v1.7 | 权限控制 |
