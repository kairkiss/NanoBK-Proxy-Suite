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
| v1.7.12 | Full wizard real stdin mock validation |
| v1.7.13 | Cloudflare stdin mock and KV helper completion |
| v1.7.15 | Full wizard test gate hardening |
| **v1.7.16** | **Full Wizard Test Gate + Version Sync 收口** |
| **v1.7.17** | **Cloudflare mock/dry-run unbound variable fix** |
| **v1.7.18** | **Validation test harness grep stability fix** |
| **v1.7.19** | **Test harness grep stability completion** |
| **v1.7.20** | **Full Wizard state and Summary truth fix** |
| **v1.7.21** | **Full Wizard Cloudflare state callback fix** |
| **v1.7.22** | **Full Wizard verified Summary mock fix** |
| **v1.7.23** | **Test harness mock preflight isolation fix** |
| **v1.7.24** | **Interactive mock timeout diagnostics fix** |
| **v1.7.25** | **Interactive mock input and verified Summary alignment fix** |
| **v1.7.26** | **Existing deployment resume preflight summary fix** |
| **v1.7.27** | **Existing runtime refresh reliability fix** |
| **v1.8.0** | **CLI Product UI and Operation Log Polish** |
| **v1.8.1** | **CLI UI Plain Mode and Log Safety Fix** |
| **v1.8.2** | **CLI UI Test Stability and Log Raw Guard** |
| **v1.8.3** | **CLI Visual Snapshot and Install Output Polish** |
| **v1.8.4** | **CLI Wording and Page Copy Polish** |
| **v1.8.5** | **CLI Dry-run Page Layout Polish** |
| **v1.8.6** | **CLI Manual Dry-run Visual Acceptance Guide** |
| **v1.8.7** | **CLI Dry-run Mock State Wording Polish** |
| **v1.8.8** | **CLI Dry-run Skip Summary Honesty Fix** |
| **v1.8.9** | **CLI Visual Polish Checkpoint and Validation Notes** |
| **v1.8.10** | **NanoBK Brand Banner and CLI Identity** |
| **v1.8.11** | **Brand Banner Width and Snapshot Fix** |
| **v1.8.12** | **CLI Stage Page Cards Polish** |
| **v1.8.13** | **CLI Compact Mode and Visual Density Polish** |
| **v1.8.14** | **CLI Manual Visual Comparison Guide** |
| **v1.8.15** | **Plain and UI=0 Mode Boundary Fix** |
| **v1.8.16** | **Plain ANSI Boundary Fix** |
| **v1.8.17** | **Interactive Plain ANSI Cleanup** |
| **v1.8.18** | **UI=0 Summary Boundary Final Fix** |
| **v1.8.19** | **CLI Static UI Acceptance Checkpoint** |
| **v1.8.20** | **Operation Log Low-risk Pilot** |
| **v1.8.21** | **Operation Log UI=0 Boundary Fix** |
| **v1.8.22** | **Operation Log Install.sh Pilot Hook** |
| **v1.8.23** | **Operation Log Pilot Defaults Boundary Fix** |
| **v1.8.24** | **Operation Log Single Test Path Pilot** |
| **v1.8.25** | **Operation Log Test Wrapper Failure Proof** |
| **v1.8.26** | **Operation Log Pilot Acceptance Checkpoint** |
| **v1.8.27** | **Operation Log One Low-risk Real Command Pilot** |
| **v1.8.28** | **Operation Log Real Pilot UI=0/CI Test Fix** |
| **v1.8.29** | **Operation Log Real Command Pilot Checkpoint** |
| **v1.8.30** | **Operation Log second real command planning** |
| **v1.8.31** | **Operation Log second real command pilot: bin/nanobk --help** |
| **v1.8.32** | **Operation Log focused test speed split** |
| **v1.8.33** | **Focused test no-trigger speed polish** |
| **v1.8.34** | **Status JSON mock/sanitized planning** |
| **v1.8.35** | **Status JSON sanitized fixture prototype** |
| **v1.8.36** | **Status JSON fixture test polish** |
| **v1.8.37** | **Status JSON mock filesystem root design** |
| **v1.8.38** | **Status JSON mock filesystem feasibility gate** |
| **v1.8.39** | **Status JSON mock isolation hook planning** |
| **v1.8.40** | **Status JSON admin env path test hook** |
| **v1.8.41** | **Status JSON mock filesystem operation-log prototype** |
| **v1.8.42** | **Status mock operation-log command path polish** |
| **v1.8.43** | **Status mock operation-log prototype checkpoint** |
| **v1.8.44** | **v1.8 CLI and operation-log checkpoint** |
| **v1.8.45** | **v1.8 closeout decision** |
| **v1.9.0-planning** | **Bot/Web Control Plane Productization Scope Proposal** |
| **v1.9.1** | **Bot/Web Current-State Safety Audit** |
| **v1.9.2** | **Telegram Bot UX/Menu Spec** |
| **v1.9.3** | **Web Dashboard UX Spec** |
| **v1.9.4** | **Bot/Web Command Allowlist Spec and Static Tests** |
| **v1.9.5** | **Redaction Layer Audit and Address-Class Redaction Tests** |
| **v1.9.6** | **Shared Redaction Helper Design / Prototype Review** |
| **v1.9.7** | **Bot Redaction Helper Integration** |
| **v1.9.8** | **Web Redaction Helper Integration** |
| **v1.9.9** | **Redaction Integration Checkpoint / Bot-Web Safety Gate** |
| **v1.9.10** | **Bot Safe Status Summary Minimal Implementation** |
| **v1.9.11** | **Web Safe Status Cards Minimal Implementation** |
| **v1.9.12** | **Raw JSON / Advanced Diagnostics Policy Planning** |
| **v1.9.13** | **Bot /status_json Warning and Help Classification** |
| **v1.9.14** | **Web Raw JSON Warning Copy Minimal Implementation** |
| **v1.9.15** | **Advanced Diagnostics Mode Planning** |
| **v1.9.16** | **Bot Advanced Mode Minimal Implementation** |
| **v1.9.17** | **Web Advanced Mode Minimal Implementation** |
| **v1.9.18** | **Advanced Diagnostics Mode Checkpoint** |
| **v1.9.19** | **Raw JSON Gating Policy Planning** |
| **v1.9.20** | **Bot /status_json Soft Gate Minimal Implementation** |
| **v1.9.21** | **Web Raw JSON Soft Gate Minimal Implementation** |
| **v1.9.22** | **Raw JSON Gating Checkpoint** |
| **v1.9.23** | **Bot Control Center Menu Planning** |
| **v1.9.24** | **Bot Control Center Static Menu Minimal Implementation** |
| **v1.9.25** | **Bot Control Center Callback Polish** |
| **v1.9.26** | **Bot Control Center Checkpoint** |
| **v1.9.27** | **Limited Real Bot/Web Smoke Test Plan** |
| **v1.9.28** | **Real Bot/Web Smoke Test Validation** |
| **v1.9.29** | **Bot/Web i18n Planning** |
| **v1.9.30** | **Bot i18n Minimal Implementation** |
| **v1.9.31** | **Web i18n Minimal Implementation** |
| **v1.9.32** | **Bot/Web i18n Checkpoint** |
| **v1.9.33** | **Doctor Output Productization Planning** |
| **v1.9.34** | **Doctor Output Current-State Audit** |
| **v1.9.35** | **Doctor Summary Contract / Fixture Tests** |
| **v1.9.36** | **Bot Doctor Summary Minimal Implementation** |
| **v1.9.37** | **Web Doctor Summary Minimal Implementation** |
| v1.9 | Bot/Web 控制面产品化 |

v1.7.21 fixes Cloudflare deploy status callback mismatch and admin env auto-install. v1.7.22 disables legacy admin env in Full Wizard, writes mock verified env, and tightens dynamic Summary checks. v1.7.23 fixes mock preflight port isolation so interactive mock tests are not affected by already-running NanoBK services. v1.7.24 adds hard timeouts and diagnostics to dynamic mock tests so Phase A cannot hang indefinitely. v1.7.25 fixes mock input flows so tests don't fall into placeholder URL rejection loops and ensures Summary shows nanok/nanob verified. v1.7.26 refreshes existing deployment runtime state and skips core port preflight when resuming from Cloudflare/BotWeb. v1.7.27 fixes healthcheck --quiet removal and preserves refreshed installed/verified state through resume choices. None claims real VPS validation, Cloudflare validation, or production pass. v1.8.0 adds CLI product UI polish (ui.sh, operation-log.sh) without changing deployment logic, protocol templates, Worker core, Bot/Web business logic, or rotate sync.

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
