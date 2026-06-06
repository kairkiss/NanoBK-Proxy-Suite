# v1.9.58 — CLI Version Display Strategy / Minimal Fix

> 验证类型：CLI 版本显示修复
> 日期：2026-06-06
> 基线 commit：`c0660ef4e183f4bb1d27d96b0560022264599580`
> 基线信息：`fix: polish web chinese copy`

---

## 1. 本轮目标与结论

**v1.9.58 修复了 CLI 版本显示仍为 `nanobk 1.8.45` 的问题。**

- ✅ `nanobk --version` 现在显示 `nanobk 1.9.58`
- ✅ 三个版本常量保持一致
- ✅ 最小 CLI 显示修复
- ✅ 无部署行为变更
- ✅ 无安装器部署逻辑变更
- ✅ 无 Bot/Web 运行时变更
- ✅ 无 tag/release

**结论：版本常量从 `1.8.45` 更新为 `1.9.58`，三个文件保持一致。版本命令不执行任何状态/诊断/安装/轮换操作。**

---

## 2. Root cause

### 版本定义位置

版本在三个文件中定义：

| 文件 | 变量 | 旧行 |
|------|------|------|
| `bin/nanobk` | `NANOBK_VERSION` | `NANOBK_VERSION="1.8.45"` |
| `installer/install.sh` | `VERSION` | `VERSION="1.8.45"` |
| `installer/bootstrap.sh` | `BOOTSTRAP_VERSION` | `BOOTSTRAP_VERSION="1.8.45"` |

### 为什么仍显示 1.8.45

v1.8.45 是 v1.8 系列的收口版本。之后的 v1.9.x 工作（Bot/Web 控制面产品化）没有更新版本常量，因为当时关注点在功能实现而非版本管理。版本常量在整个 v1.9 开发周期中保持不变。

### 为什么具有误导性

在 T14/T15/T16/T17 真实 VPS 测试中，`nanobk --version` 始终报告 `1.8.45`，但项目实际已进入 v1.9 控制面产品化阶段。这对用户和维护者来说是不诚实的状态显示。

---

## 3. Changed paths

| 文件 | 变更 |
|------|------|
| `bin/nanobk` | `NANOBK_VERSION="1.8.45"` → `NANOBK_VERSION="1.9.58"` |
| `installer/install.sh` | `VERSION="1.8.45"` → `VERSION="1.9.58"` |
| `installer/bootstrap.sh` | `BOOTSTRAP_VERSION="1.8.45"` → `BOOTSTRAP_VERSION="1.9.58"` |
| `tests/unified-cli-ui-v1.8.sh` | 版本断言从 `1.8.45` 更新为 `1.9.58` |
| `tests/cli-version-display-v1.9.58.sh` | 新增聚焦测试（28 项） |
| `docs/validation-v1.9.58-cli-version-display.md` | 本文档 |
| `CHANGELOG.md` | 新增 v1.9.58 条目 |
| `docs/roadmap.md` | 新增 v1.9.58 版本行 |

---

## 4. Version behavior

| 特性 | 说明 |
|------|------|
| 新版本输出 | `nanobk 1.9.58` |
| 旧输出已移除 | `nanobk 1.8.45` 不再出现 |
| `--version` 安全 | 不执行 status/doctor/install/rotate |
| `version` 子命令安全 | 不执行 status/doctor/install/rotate |
| `--help` 包含版本 | 帮助文本显示 v1.9.58 |
| 三文件一致 | nanobk/install.sh/bootstrap.sh 版本相同 |

---

## 5. Protected baseline

| 基线 | 状态 |
|------|------|
| v1.7.27 部署核心 | 受保护，未变更 |
| v1.8.45 历史收口 | 历史记录，未变更 |
| v1.9.58 版本显示 | 不暗示 release tag |
| 稳定 tag | 仍需最终收口和用户批准 |

---

## 6. Safety boundaries

| 边界 | 状态 |
|------|------|
| 不读 env 文件 | ✅ |
| 不写 env 文件 | ✅ |
| 不运行真实 status/doctor/install/rotate | ✅ |
| 不运行 Cloudflare 命令 | ✅ |
| 不改变 redaction/gating/advanced/rotate/deployment | ✅ |
| 不改变 Bot/Web 运行时 | ✅ |

---

## 7. Tests run

| 测试 | 结果 |
|------|------|
| `bash tests/cli-version-display-v1.9.58.sh` | ✅ 28 passed |
| `bash tests/unified-cli-ui-v1.8.sh` | ✅ 100 passed |
| `bash tests/bot-cli-mock.sh` | ✅ passed |
| `bash tests/web-panel-mock.sh` | ✅ passed |
| `bash tests/installer-language-propagation-v1.9.49.sh` | ✅ passed |
| `python3 tests/chinese-default-v1.9.48.py` | ✅ 75 passed |
| `python3 tests/web-language-switch-v1.9.51.py` | ✅ 57 passed |
| `python3 tests/bot-language-command-v1.9.52.py` | ✅ 90 passed |
| `python3 tests/web-chinese-copy-polish-v1.9.57.py` | ✅ 76 passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 228 passed |
| `python3 web/app.py --self-test` | ✅ 118 passed |

---

## 8. Stable tag impact

- ✅ CLI 版本显示稳定门控项可标记为已解决
- 稳定 tag 仍被以下项阻塞：
  - AI 维护接口文档（T17-P2-012）
  - 最终收口检查点
  - 最终聚焦测试通过
  - 用户明确批准

---

## 9. Known limitations

| 限制 | 说明 |
|------|------|
| 不 tag/release | 版本更新不等于发布 |
| 不实现 systemd | 未来任务 |
| 不实现 Web 生产运行器 | 未来任务 |
| 不实现指纹脱敏策略 | 未来任务 |
| 不改变部署核心 | 仅版本显示 |

---

## 10. Next step

**推荐：v1.9.59 — AI Maintenance Interface / Handoff Map**

仅在 ChatGPT 审核后实施。
