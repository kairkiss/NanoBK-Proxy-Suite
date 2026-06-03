# NanoBK v1.8 CLI Visual Comparison Guide

## 1. Purpose

This is a **human visual comparison acceptance test**, NOT a real deployment test.

This guide is used to compare four CLI display modes:

- **Default mode** — full product UI with brand banner, stage cards, box drawing.
- **Compact mode** (`NANOBK_COMPACT=1`) — shorter output, single-line banner and cards.
- **Plain mode** (`NANOBK_PLAIN=1`) — no ANSI, no emoji, no box drawing, suitable for logs/CI.
- **UI=0 mode** (`NANOBK_UI=0`) — legacy minimal output, traditional script style.

The goal is to judge whether the CLI is:

- Polished and product-like
- Clean and concise
- Beginner-friendly
- Safe (no secret leakage)
- Non-misleading (dry-run is clear)
- Suitable for small SSH screens
- Suitable for log/CI capture
- Backward-compatible

## 2. Scope

### Covered

- Banner
- Stage cards
- Token safety reminder
- Recovery block
- Dry-run notice
- Summary
- Control-plane warning
- Compact density
- Plain output
- UI=0 fallback

### Not Covered

- Real VPS installation
- Real Cloudflare deploy
- Real Worker verify
- Rotate sync
- Bot / Web real startup
- Real subscription availability

## 3. Safety Rules

**Read before running any command.**

- Do NOT input real tokens.
- Do NOT paste real env contents.
- Do NOT `cat bot/.env`.
- Do NOT `cat web/.env`.
- Do NOT `cat .cloudflare.local.env`.
- Do NOT `cat .nanob.local.env`.
- Do NOT `cat /root/.nanok-cf-admin.env`.
- Do NOT share real VPS IP, real workers.dev subdomain, or real subscription URL in chat, issues, or logs.
- Do NOT paste Reality private keys anywhere.
- Check screenshots for tokens / IPs / Worker URLs / env contents before sharing.

## 4. Commands

### Default mode

```bash
NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash installer/install.sh --mode full --dry-run --defaults --lang zh \
    2>&1 | tee /tmp/nanobk-v1.8-default.txt
```

### Compact mode

```bash
NANOBK_COMPACT=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash installer/install.sh --mode full --dry-run --defaults --lang zh \
    2>&1 | tee /tmp/nanobk-v1.8-compact.txt
```

### Plain mode

```bash
NANOBK_PLAIN=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash installer/install.sh --mode full --dry-run --defaults --lang zh \
    2>&1 | tee /tmp/nanobk-v1.8-plain.txt
```

### UI=0 mode

```bash
NANOBK_UI=0 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash installer/install.sh --mode full --dry-run --defaults --lang zh \
    2>&1 | tee /tmp/nanobk-v1.8-ui0.txt
```

> These commands use mock + dry-run + defaults. They should NOT execute real deployment and should NOT require real tokens.

## 5. Quick Safety Grep

Run this after generating all four outputs:

```bash
grep -E 'SECRET_TEST_BOT_TOKEN|TOKEN=|SECRET=|ADMIN_TOKEN=|SUB_TOKEN=|NANOB_TOKEN=|NANOBK_CF_API_TOKEN|status: success' \
  /tmp/nanobk-v1.8-default.txt \
  /tmp/nanobk-v1.8-compact.txt \
  /tmp/nanobk-v1.8-plain.txt \
  /tmp/nanobk-v1.8-ui0.txt || true
```

**Expected**: No matches. If any match appears, it is a BLOCKED issue.

### Additional safety checks

```bash
# Check dry-run is clearly stated
grep -c 'planned / dry-run' /tmp/nanobk-v1.8-default.txt
grep -c '没有执行真实部署' /tmp/nanobk-v1.8-default.txt

# Check control-plane wording preserved
grep -c '控制端' /tmp/nanobk-v1.8-default.txt
```

## 6. Human Review Checklist

### Default mode

- [ ] Banner has brand identity (box drawing, product name, tagline)
- [ ] Stage cards are clear and informative
- [ ] Feels like a product wizard, not a scattered script
- [ ] Not too long for first-time users
- [ ] Beginners can understand what each step does
- [ ] Not too much shell-style noise

### Compact mode

- [ ] Noticeably shorter than default
- [ ] Still understandable per-stage
- [ ] Suitable for small SSH screens
- [ ] Token safety / dry-run / control-plane info preserved
- [ ] Not so compressed that it becomes confusing

### Plain mode

- [ ] No ANSI escape codes
- [ ] No emoji
- [ ] No box drawing characters
- [ ] Suitable for saving to log files
- [ ] Still clear and readable

### UI=0 mode

- [ ] Close to traditional script output
- [ ] Backward-compatible
- [ ] No complex UI elements
- [ ] Still no fake success

### Summary

- [ ] VPS / Cloudflare / Bot / Web status is clear
- [ ] `planned / dry-run` is obvious
- [ ] `skipped` / `failed` / `manual_pending` is honest
- [ ] Bot/Web control-plane warning is NOT weakened

## 7. PASS / NEEDS POLISH / BLOCKED

### PASS

- Default looks like a product
- Compact is noticeably shorter
- Plain is clean
- UI=0 is compatible
- No secrets leak
- No fake success
- Dry-run is honest
- Control-plane warning preserved

### NEEDS POLISH

- Default is too long
- Compact is too cramped
- Banner is not polished enough
- Stage cards are too verbose
- Summary still looks like a script
- Mock output is still too test-like
- Needs dynamic progress / mascot enhancement

### BLOCKED

- Secret leakage (token, IP, Worker URL, env contents)
- Dry-run looks like real successful deployment
- Status words beautified into `success`
- Control-plane warning disappeared
- Plain mode still has ANSI / emoji / box drawing
- UI=0 broken
- Flow hangs or crashes
- Real deployment was triggered

## 8. Feedback Template

```
NanoBK v1.8 CLI Visual Comparison Feedback

Commit:
  (paste git commit hash)

Terminal:
  (e.g., iTerm2, Terminal.app, tmux, SSH)

Screen size:
  (e.g., 80x24, 120x40, fullscreen)

Mode tested: default / compact / plain / UI=0

Overall:
  PASS / NEEDS POLISH / BLOCKED

Default mode:
  Looks good:
  Needs polish:
  Too noisy:
  Too long:
  Confusing:

Compact mode:
  Looks good:
  Needs polish:
  Too compressed:
  Better than default? yes/no

Plain mode:
  Clean enough for logs? yes/no
  Problems:

UI=0:
  Legacy-compatible? yes/no
  Problems:

Safety:
  Any token/IP/URL/env leak?
  Any fake success?
  Is dry-run clear?

Next direction:
  - dynamic progress / mascot
  - operation-log integration
  - more CLI static polish
  - move to Telegram Bot polish
```

## 9. Decision Matrix

Use the feedback to decide the next version direction:

| Scenario | Next Step |
|----------|-----------|
| Default and Compact both look good | Enter operation-log low-risk pilot, or Telegram Bot productization |
| Default good, Compact bad | v1.8.15 fix compact density |
| Both too static | v1.8.15 try dynamic progress / mascot pilot |
| Output still has complex logs | v1.8.15 or v1.8.16 operation-log low-risk pilot |
| CLI is sufficient | Pause v1.8, enter v1.9 Telegram Bot menu polish |

## 10. v1.8.14 Acceptance Result and v1.8.15 Fix

### v1.8.14 Acceptance

- **Overall**: BLOCKED
- **Security**: PASS (no token/secret leakage)
- **Dry-run honesty**: PASS (planned / dry-run, no real deployment disclaimer)
- **Fake success guard**: PASS (no status: success)
- **Default mode**: PASS with polish
- **Compact mode**: NEEDS POLISH
- **Plain mode**: BLOCKED — full installer output still contained `╔║╚═✓■□──` characters
- **UI=0 mode**: NEEDS POLISH — still showed large box banner

### v1.8.15 Fix

- Plain mode full installer output: banner, preflight, tools status, section headers all converted to plain ASCII.
- UI=0 mode: main banner uses plain text, no box drawing.
- Compact mode: main banner uses single-line format.
- All Unicode box drawing, checkmarks, progress bars, and section borders in `installer/install.sh` are now gated by PLAIN/UI=0 mode checks.
- Added full-output mode boundary tests (`tests/unified-cli-mode-boundaries-v1.8.sh`).

### v1.8.16 Plain ANSI Boundary Fix

- v1.8.15 fixed visible Unicode mode boundaries but missed ANSI escape checks.
- v1.8.16 adds `installer_has_color()` helper that checks `NANOBK_PLAIN`, `NANOBK_UI`, and `CI`.
- All display helpers (`log`, `ok`, `warn`, `err`, `print_cmd`, `preflight_pass/fail/warn`, `section_line`, `mock_log`, `prompt`, `confirm`, `prompt_menu_choice`, Summary disclaimers, config confirmation headers) now use `installer_has_color()`.
- Full-output ANSI boundary tests added for PLAIN/UI=0/CI modes.
- Compact+Plain combined mode test added.
- Plain/UI=0/CI full installer output now contains 0 ANSI escapes.

### v1.8.17 Interactive Plain ANSI Cleanup

- v1.8.16 fixed no-ANSI for automated `--defaults` paths, but interactive validation warnings still had direct colored `echo -e`.
- v1.8.17 gates those interactive warning paths: VPS domain warnings, Cloudflare URL warnings, KV warnings, port conflict, Preflight summary, select_language prompt, show_menu header, test menu prompt.
- Added interactive Plain ANSI regression tests.
- Plain/UI=0/CI interactive paths now contain 0 ANSI escapes.
