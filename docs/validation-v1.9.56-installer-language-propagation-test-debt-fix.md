# v1.9.56 — Installer Language Propagation Test Debt Fix

> 验证类型：安装器语言传播测试债务修复
> 日期：2026-06-06
> 基线 commit：`c1bfda6336a87632fd4dc021cc9e539122ed61d0`
> 基线信息：`docs: add v1.9.55 chinese english smoke validation`

---

## 1. 本轮目标与结论

**v1.9.56 修复了 T17 已知的安装器语言传播测试假阳性（T17-TEST-002）。**

- ✅ 测试债务修复，无安装器运行时行为变更
- ✅ 无 Bot/Web/CLI 行为变更
- ✅ 无 env 文件读写
- ✅ 无 tag/release

**结论：测试现在只检测可执行的 env 读取命令，不再对安全警告文本产生假阳性。**

---

## 2. Root cause

### 失败现象

`tests/installer-language-propagation-v1.9.49.sh` 在 Linux 环境（GNU grep + PCRE 支持）下报告 2 个失败：

- `install.sh reads bot/.env`
- `install.sh reads web/.env`

### 根本原因

测试使用 `grep -P 'cat\s+["\047]?bot/\.env'` 搜索 `installer/install.sh` 中的 `cat bot/.env` 模式，仅过滤 `cat >`（写入 heredoc）。

`installer/install.sh` 中有 3 行匹配此模式，但均为安全警告文本，不是可执行的 env 读取：

| 行号 | 内容 | 类型 |
|------|------|------|
| 2009 | `echo "    - 不要执行 cat bot/.env"` | echo 警告文本 |
| 2229 | `echo "    - 不要 cat web/.env，不要把内容贴到聊天或日志"` | echo 警告文本 |
| 4382 | `⚠ Do NOT cat bot/.env — prints tokens to terminal/logs` | heredoc 文档内容 |

### 为什么在 macOS 上未复现

macOS 的 `grep` 不支持 `-P`（PCRE），`grep -qP` 返回错误码 2，被 `2>/dev/null` 静默处理，导致测试走入 `else` 分支直接通过。Linux 上 GNU grep 支持 PCRE，实际匹配到警告文本行，导致假阳性失败。

---

## 3. Test fix summary

### 变更文件

`tests/installer-language-propagation-v1.9.49.sh`

### 新的检测方法

旧方法：
```bash
grep -P 'cat\s+["\047]?bot/\.env' "$INSTALL_SH" | grep -v 'cat >'
```

新方法：
```bash
grep -n 'cat.*bot/\.env' "$INSTALL_SH" \
  | grep -v 'cat >' \
  | grep -v '^[[:space:]]*[0-9]*:[[:space:]]*#' \
  | grep -v '^[[:space:]]*[0-9]*:[[:space:]]*echo[[:space:]]' \
  | grep -v '^[[:space:]]*[0-9]*:[[:space:]]*printf[[:space:]]' \
  | grep -vE '^[[:space:]]*[0-9]*:[[:space:]]*[^a-zA-Z_0-9[:space:]/$({]'
```

### 过滤层级

| 层级 | 过滤内容 | 原因 |
|------|----------|------|
| `grep -v 'cat >'` | 写入 heredoc | 已有 |
| `grep -v '...#...'` | 注释行 | 新增 |
| `grep -v '...echo...'` | echo 警告文本 | 新增 |
| `grep -v '...printf...'` | printf 文本 | 新增 |
| `grep -vE '...[^a-zA-Z_0-9...]'` | heredoc/文档内容（非命令起始字符） | 新增 |

### 安全保证

- 真实可执行 `cat bot/.env` 仍然会被检测到
- 真实可执行 `cat web/.env` 仍然会被检测到
- 子 shell 读取 `$(cat bot/.env)` 仍然会被检测到
- 管道读取 `cat bot/.env | head` 仍然会被检测到
- 无断言被削弱

### 兼容性改进

- 旧方法使用 `grep -P`（PCRE），在无 PCRE 支持的系统上静默跳过检查
- 新方法使用 `grep -vE`（ERE），POSIX 兼容，所有系统均可正确执行

---

## 4. Installer language propagation verification

| 特性 | 验证方式 | 结果 |
|------|----------|------|
| Bot env heredoc 包含 NANOBK_LANG | 源码 grep | ✅ |
| Web env heredoc 包含 NANOBK_LANG | 源码 grep | ✅ |
| LANG_CODE:-zh 回退 | 源码 grep | ✅ |
| Bot env chmod 600 | 源码 grep | ✅ |
| Web env chmod 600 | 源码 grep | ✅ |
| 无 cat bot/.env 可执行读取 | 过滤后 grep | ✅ |
| 无 cat web/.env 可执行读取 | 过滤后 grep | ✅ |
| --lang zh 行为 | 源码检查 | ✅ |
| --lang en 行为 | 源码检查 | ✅ |
| 默认回退 zh | 源码检查 | ✅ |
| zh/en 别名 | 源码检查 | ✅ |
| 无 env 内容打印 | 安全检查 | ✅ |
| 无 token 泄露 | 安全检查 | ✅ |
| VPS 部署逻辑不变 | 源码检查 | ✅ |
| Cloudflare 逻辑不变 | 源码检查 | ✅ |
| rotate 逻辑不变 | 源码检查 | ✅ |

---

## 5. Safety boundaries

| 边界 | 状态 |
|------|------|
| 不读 env 文件 | ✅ |
| 不写 env 文件 | ✅ |
| 不打印密钥 | ✅ |
| 不改变安装器运行时行为 | ✅ |
| 不改变 Bot/Web/CLI 行为 | ✅ |
| 不改变 redaction/gating/advanced/rotate | ✅ |
| 不改变部署核心 | ✅ |

---

## 6. Tests run

| 测试 | 结果 |
|------|------|
| `bash tests/installer-language-propagation-v1.9.49.sh` | ✅ 22 passed |
| `python3 tests/chinese-default-v1.9.48.py` | ✅ 75 passed |
| `python3 tests/web-language-switch-v1.9.51.py` | ✅ 57 passed |
| `python3 tests/bot-language-command-v1.9.52.py` | ✅ 90 passed |
| `python3 tests/i18n-checkpoint-v1.9.32.py` | ✅ 167 passed |
| `bash tests/bot-cli-mock.sh` | ✅ 228 passed |
| `bash tests/web-panel-mock.sh` | ✅ 118 passed |
| `python3 bot/nanobk_bot.py --self-test` | ✅ 228 passed |
| `python3 web/app.py --self-test` | ✅ 118 passed |

---

## 7. Stable tag impact

- ✅ T17-TEST-002 已修复
- ✅ 稳定 tag 门控项"安装器语言传播测试债务"可标记为已解决
- 稳定 tag 仍被以下项阻塞：
  - Web 中文残留修复（T17-P2-003）
  - CLI 版本显示处理（T17-P2-011）
  - AI 维护接口文档（T17-P2-012）
  - 最终聚焦测试通过
  - 用户明确批准

---

## 8. Known limitations

| 限制 | 说明 |
|------|------|
| 未执行真实安装 | 测试环境无完整 VPS 安装条件 |
| 未重新执行真实 Bot/Web 冒烟 | 仅运行静态/聚焦测试 |
| 未变更语言运行时行为 | 仅修复测试 |
| 下一个稳定门控项 | Web 中文 Copy/i18n 覆盖修复 |

---

## 9. Next step

**推荐：v1.9.57 — Web Chinese Copy Polish / i18n Coverage Fix**

仅在 ChatGPT 审核后实施。
