# v2.2.3 — Branded nanobk Console/TUI Mock Design and Tests

## 1. Purpose

This document defines the target branded `nanobk` console/TUI UX, the
beginner/advanced mode boundary, menu structure, status cards, state vocabulary,
logs policy, safety/redaction rules, and future mock/static test strategy.

This is a design document. It does not implement any new behavior. The current
`bin/nanobk` console (v2.1.1) remains unchanged.

---

## 2. Baseline

**Current console (v2.1.1):**

- `nanobk` with no args on TTY opens interactive console with branded header.
- Header: "NanoBK Proxy Suite — VPS Proxy Automation Console"
- Menu: Status, Doctor, Full Wizard, Cloudflare DNS tools, Export, Rotate,
  Install/repair CLI, Advanced help, Exit.
- Safety labels: `[safe]`, `[explicit]`, `[advanced]` on menu actions.
- DNS submenu: read-only guidance (plan, validate, check, readiness).
- Deployment is explicit (confirmation-gated Full Wizard).
- Non-TTY: safe entry screen, exits 0.

**Current Bot (v1.1.0):**

- Control center with buttons: Status, Recovery, Diagnostics, Rotate, Language.
- Advanced mode: `/advanced on` enables 15-minute diagnostic window.
- Advanced mode still redacts secrets, raw addresses, subscription URLs.
- All Bot commands call CLI subprocess — never direct config writes.

**Current Web (v1.2.1):**

- Dashboard, Status, Doctor, Rotate, Language, Login.
- Advanced mode: session-level, 15-minute window.
- Raw JSON gated by advanced mode.
- All Web actions call CLI subprocess.

**Current UI helpers (ui.sh v1.8.13):**

- Banner with box-drawing, color, emoji, compact mode, plain mode.
- Capability detection: color, emoji, TTY, terminal width.
- Environment overrides: `NANOBK_PLAIN`, `NANOBK_NO_EMOJI`, `NANOBK_VERBOSE`,
  `NANOBK_UI`, `NANOBK_COMPACT`.

---

## 3. Product Goal

`nanobk` should feel like a product, not a script wrapper. The user installs
once, types `nanobk`, and enters a calm, branded, beginner-friendly console
that guides them through setup, deployment, and maintenance.

The console is the primary product interface. Bot and Web are secondary control
planes.

---

## 4. Console Design Principles

1. **Calm.** No wall of engineering output. Concise status, clear labels.
2. **Branded.** The user always knows they are inside NanoBK.
3. **Beginner-first.** Default mode hides engineering internals.
4. **Safe by default.** Read-only is the default. Dangerous operations require
   explicit confirmation.
5. **Numbered menus.** All choices use numbered menus, not `[y/N]` for important
   decisions.
6. **Progress indicators.** Small emoji and concise status lines are allowed for
   clarity (e.g., `🟢 healthy`, `🔴 failed`).
7. **Auditable.** Engineering logs exist but are hidden by default. Advanced
   mode can reveal them.
8. **Consistent.** Bot, Web, and Console share the same state vocabulary and
   safety rules.

---

## 5. Beginner Mode

Beginner mode is the default. It:

- Shows status cards with emoji indicators and concise labels.
- Uses numbered menus for all navigation.
- Hides engineering details (zone IDs, account IDs, record types, raw JSON).
- Does not mention DNS-01, A/AAAA records, Cloudflare Access, or Tunnel unless
  the user explicitly enters an advanced path.
- Shows `[safe]`, `[explicit]`, `[advanced]` labels on menu items.
- Guides the user through: Install → Status → Doctor → Deploy → Cloudflare.
- Recovery/Doctor is a first-class beginner path.

**Beginner copy must not contain:**

- Zone ID, Account ID
- DNS-01, A/AAAA, CNAME (unless inside a clearly labeled advanced detail view)
- `apply --yes` (never shown in beginner copy)
- Raw env file paths (e.g., `/etc/nanobk/cloudflare-api.env`)
- Raw Cloudflare API terminology

---

## 6. Advanced Mode

Advanced mode reveals extra diagnostics, but never raw secrets. It:

- Is opt-in (explicit command or menu selection).
- Expires automatically (15-minute window, matching Bot/Web pattern).
- Shows additional diagnostic detail (e.g., full doctor output, raw JSON keys).
- Still redacts: tokens, private keys, subscription URLs, protocol links,
  workers.dev URLs, raw IP addresses, raw env content.
- Can be toggled off explicitly.

**Advanced mode does NOT:**

- Print raw secrets or protocol links.
- Bypass confirmation gates for dangerous operations.
- Auto-enable on any path.
- Persist across sessions (console is session-level).

---

## 7. Main Screen Mock

The following is a design mock for the target console main screen. It is not
implemented.

```
╔════════════════════════════════════════════════════╗
║              NanoBK Proxy Suite                   ║
║        VPS Proxy Automation Console               ║
╚════════════════════════════════════════════════════╝

  Status overview:
  🟢 NanoBK        installed
  🖥  VPS           detected / needs setup / unknown
  🌐 Cloudflare    not connected / ready / action needed
  🔐 Proxy         not deployed / healthy / failed
  📱 Bot           disabled / healthy / action needed
  🌍 Web Panel     disabled / healthy / action needed

  1) 🚀 Start guided setup
  2) 📊 View status
  3) 🩺 Doctor / recovery
  4) 🌐 Cloudflare onboarding
  5) 🔐 Proxy services
  6) 📱 Bot / Web control planes
  7) 🛠 Backups / recovery
  8) ⚙️ Advanced mode
  9) Exit
```

**Notes:**

- Status overview is read-only, concise, emoji-indicated.
- Each status line shows a single word or short phrase.
- Menu items are numbered and emoji-labeled.
- "Start guided setup" is the first option for new users.
- "Advanced mode" is last before Exit, clearly separated.
- The mock is a design target. Implementation may adjust wording and layout.

---

## 8. Menu Structure

### Main menu

| # | Label | Safety | Description |
|---|-------|--------|-------------|
| 1 | Start guided setup | explicit | Walks through: status → doctor → Cloudflare → deploy |
| 2 | View status | safe | Read-only status cards |
| 3 | Doctor / recovery | safe | Read-only diagnostics, recovery guidance |
| 4 | Cloudflare onboarding | safe | Read-only-first zone/domain/IP flow |
| 5 | Proxy services | explicit | Deploy, rotate, export (confirmation-gated) |
| 6 | Bot / Web control planes | explicit | Enable/disable Bot, Web (confirmation-gated) |
| 7 | Backups / recovery | safe | List backups, preview rollback (read-only) |
| 8 | Advanced mode | advanced | Toggle advanced mode, full help |
| 9 | Exit | — | Goodbye |

### Submenus

**Cloudflare onboarding (option 4):**

| # | Label | Safety |
|---|-------|--------|
| 1 | List Cloudflare zones | safe |
| 2 | Detect VPS IP | safe |
| 3 | Check DNS availability | safe |
| 4 | Generate DNS profile | safe |
| 5 | Preview DNS plan | safe |
| 6 | Readiness report | safe |
| 7 | Back | — |

All Cloudflare onboarding submenu items are read-only. DNS mutation
(`apply --yes`) is not surfaced in this submenu.

**Proxy services (option 5):**

| # | Label | Safety |
|---|-------|--------|
| 1 | View proxy status | safe |
| 2 | Rotate keys | explicit |
| 3 | Export protocol links | explicit |
| 4 | Start Full Wizard | explicit |
| 5 | Back | — |

**Bot / Web (option 6):**

| # | Label | Safety |
|---|-------|--------|
| 1 | View Bot status | safe |
| 2 | View Web status | safe |
| 3 | Enable Bot | explicit |
| 4 | Enable Web | explicit |
| 5 | Back | — |

---

## 9. Status Cards

Status cards are the primary read-only display. Each card shows:

- Emoji indicator (🟢 🟡 🔴 ⚪)
- Component name
- Status word (from state vocabulary)
- Optional one-line detail

**Card layout:**

```
  🟢 NanoBK        installed · v2.1.1
  🖥  VPS           detected · 203.0.11x.xxx
  🌐 Cloudflare    ready · ex***e.com
  🔐 Proxy         healthy · 4 protocols active
  📱 Bot           disabled
  🌍 Web Panel     disabled
```

**Card rules:**

- IP addresses are masked (last octet hidden).
- Domain names are masked (middle characters hidden).
- No raw zone IDs, account IDs, or API tokens.
- Status words come from the state vocabulary (see section 14).
- In advanced mode, cards may show one additional detail line.

---

## 10. Cloudflare Onboarding Entry

Cloudflare onboarding enters as read-only-first. The flow:

1. User selects "Cloudflare onboarding" (option 4).
2. Console checks for Cloudflare API credentials (env file).
3. If credentials found: lists zones (GET-only, read-only).
4. If credentials not found: shows guidance on how to set up credentials.
5. User selects a zone (or enters manually if needed).
6. Console detects VPS IP (auto-detect or manual fallback).
7. Console proposes `proxy.<domain>` and `web.<domain>`.
8. Console checks DNS availability for proposed subdomains.
9. Console shows a plan preview (read-only, no mutation).
10. Console shows readiness report.

**No step in this flow calls Cloudflare POST/PATCH/DELETE.**
DNS mutation is a separate explicit step, not part of onboarding.

---

## 11. Deployment Entry

Deployment remains explicit and confirmation-gated.

- "Start guided setup" (option 1) walks through the full flow but requires
  confirmation at each dangerous step.
- "Proxy services → Start Full Wizard" (option 5.4) launches the legacy Full
  Wizard with explicit confirmation.
- Neither path auto-deploys without user confirmation.
- `apply --yes` is never surfaced in beginner copy.

---

## 12. Doctor / Recovery Entry

Doctor/recovery is a first-class beginner path. It:

- Runs read-only diagnostics (`nanobk doctor`).
- Shows a summary with emoji indicators.
- Provides clear next-step guidance for each issue found.
- Does not require advanced mode for basic recovery guidance.
- In advanced mode, shows full diagnostic output.

**Recovery guidance should cover:**

- Service not running → how to restart
- Port conflict → how to check and resolve
- Cloudflare not connected → how to set up credentials
- DNS not applied → how to apply (explicit command, not auto)
- Certificate expired → guidance (future, not implemented)

---

## 13. Logs and Verbose Output Policy

**Default (beginner mode):**

- Engineering logs are hidden.
- Only summary status and clear next steps are shown.
- Progress uses concise emoji lines, not verbose output.

**Advanced mode:**

- Engineering logs are available through explicit verbose paths.
- `NANOBK_VERBOSE=1` environment variable enables verbose output.
- Full doctor output is available.
- Raw JSON (redacted) is available.

**Rules:**

- No `set -x` or shell trace output in beginner mode.
- No raw command output in beginner mode (use summary instead).
- No Python tracebacks in beginner mode (use friendly error messages).
- All verbose paths are opt-in.

---

## 14. Summary and State Vocabulary

The following state words are the canonical vocabulary for status display:

| State | Meaning | Emoji |
|-------|---------|-------|
| `installed` | Component is installed and ready | 🟢 |
| `healthy` | Component is running and functioning | 🟢 |
| `verified` | Component has been checked and passed | 🟢 |
| `planned` | Component has a plan but not yet executed | 🟡 |
| `dry_run` | Component was tested in dry-run mode | 🟡 |
| `manual_pending` | Component needs manual action | 🟡 |
| `skipped` | Component was intentionally skipped | ⚪ |
| `failed` | Component failed or is not working | 🔴 |
| `unknown` | Component status cannot be determined | ⚪ |
| `action_needed` | Component needs user action | 🟡 |
| `not_configured` | Component has not been set up | ⚪ |

**Critical distinctions:**

- "Profile generated" is **not** "DNS applied".
- "Cloudflare GET/read-only check passed" is **not** "DNS updated".
- "Bot files installed" is **not** "Bot healthy".
- "Web files installed" is **not** "Web safely exposed".
- "Cloudflare was not called unless explicitly stated."

These distinctions must be reflected in all status display and copy.

---

## 15. Security and Redaction Rules

The console must follow the same redaction rules as Bot and Web:

**Never print:**

- Raw API tokens (`CF_API_TOKEN`, `BOT_TOKEN`, `SUB_TOKEN`, `ADMIN_TOKEN`)
- Private keys (Reality private key, TLS private key)
- Protocol links (`hysteria2://`, `tuic://`, `vless://`, `trojan://`)
- Subscription URLs
- `workers.dev` URLs
- Raw env file content
- Raw Authorization headers
- Full SHA-256 hashes (show fingerprint only)

**Mask:**

- IP addresses: `203.0.113.xxx` (last octet hidden)
- Domain names: `ex***e.com` (middle characters hidden)
- Zone IDs: `abc1…345` (first 4 + last 3 characters)
- Tokens: `sha256:abcd1234` (fingerprint only)

**Advanced mode does NOT bypass redaction.** Advanced mode shows more
diagnostic detail, but secrets remain hidden.

---

## 16. Bot/Web Relationship

**Bot and Web remain secondary control planes.** They:

- Call CLI subprocess only — never direct config writes.
- Share the same state vocabulary as the console.
- Share the same redaction rules as the console.
- Have their own advanced mode (15-minute window).

**Console is the primary interface.** It:

- Is the recommended daily entry point.
- Has the most complete guided flows.
- Is the only interface that can launch Full Wizard interactively.

**Bot and Web must not:**

- Write configs, systemd, DNS, env, secrets, Worker env, or protocol files.
- Bypass CLI safety gates.
- Auto-enable without user action.

---

## 17. Mock Test Strategy

Future tests should verify the console design without implementing the full
TUI. The following test files are planned:

### tests/v2.2.3-console-tui-design.sh

**Purpose:** Verify the current console structure matches the design spec.

**Assertions (future/mock):**

- `nanobk console` on TTY shows branded header ("NanoBK Proxy Suite").
- Non-TTY entry shows safe entry screen and exits 0.
- Main menu contains all required options (status, doctor, deployment,
  Cloudflare, proxy, Bot/Web, backups, advanced, exit).
- Menu items are numbered (1-9).
- Safety labels are present (`[safe]`, `[explicit]`, `[advanced]`).
- DNS submenu contains only read-only items.
- Deployment requires explicit confirmation (no auto-deploy).
- `apply --yes` does not appear in console output.

### tests/v2.2.3-console-copy-safety.sh

**Purpose:** Verify beginner copy does not contain engineering jargon.

**Assertions (future/mock):**

- Beginner console output does not contain "Zone ID", "Account ID".
- Beginner console output does not contain "DNS-01", "A/AAAA", "Access policy".
- Beginner console output does not contain `apply --yes`.
- Beginner console output does not contain raw env file paths.
- Beginner console output does not contain raw Cloudflare API terminology.
- Advanced mode toggle is available but does not auto-enable.

### tests/v2.2.3-console-redaction-static.sh

**Purpose:** Verify no raw secrets appear in console output.

**Assertions (future/mock/static):**

- Console output does not contain `CF_API_TOKEN=`.
- Console output does not contain `BOT_TOKEN=`, `SUB_TOKEN=`, `ADMIN_TOKEN=`.
- Console output does not contain `PRIVATE KEY`.
- Console output does not contain `workers.dev`.
- Console output does not contain `hysteria2://`, `tuic://`, `vless://`, `trojan://`.
- Console output does not contain raw IP addresses (check for non-masked patterns).
- Console output does not contain raw domain names (check for non-masked patterns).

---

## 18. Static Test Strategy

In addition to the mock tests above, static source checks should verify:

- `bin/nanobk` does not contain `apply --yes` in beginner-facing copy.
- `bin/nanobk` does not print raw env file paths in beginner mode.
- `bin/nanobk` does not contain `set -x` or trace output in console loop.
- `bin/nanobk` redaction functions are called before displaying status data.
- Console menu structure matches the design spec (all required options present).

These checks can be implemented as grep-based source checks in the test
scripts, similar to existing v2.1 source check patterns.

---

## 19. Explicit Non-goals

v2.2.3 does **not**:

- Implement new console/TUI behavior.
- Modify `bin/nanobk`.
- Modify installer scripts.
- Modify Bot/Web runtime.
- Add DNS mutation.
- Add Cloudflare mutation.
- Implement real `/etc` writes.
- Implement real rollback.
- Implement DNS-01.
- Implement Tunnel/Access.
- Create a release tag.

---

## 20. Acceptance Criteria

This document is accepted when:

1. All 20 sections are present and complete.
2. Main screen mock is included and clearly labeled as design-only.
3. Menu structure covers all required entries.
4. State vocabulary is defined with clear distinctions.
5. Beginner/advanced mode boundary is explicit.
6. Security/redaction rules are comprehensive.
7. Test strategy covers design, copy safety, and redaction.
8. Non-goals are explicit.
9. No runtime code is changed.
10. No secrets or protocol links are printed.
