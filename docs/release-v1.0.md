# NanoBK Proxy Suite v1.0.0 — CLI Core Release

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
bash bin/nanok status

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
| v1.4 | 单协议换密钥 CLI 完善 |
| v1.5 | Cloudflare 配置向导 |
| v1.6 | 操作日志 |
| v1.7 | 权限控制 |
