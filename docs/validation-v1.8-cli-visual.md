# NanoBK v1.8 CLI Visual Acceptance Guide

## 1. Purpose

This is a **CLI page visual and beginner experience acceptance test**.

It does NOT verify real VPS installation, real Cloudflare deployment, real Worker verification, or real subscription availability.

The goal is to judge whether the Full Wizard dry-run page looks clear, clean, product-like, and non-misleading to a beginner user.

## 2. Scope

### Covered

- Full Wizard entry page (banner, subtitle, step overview)
- Stage headers (阶段 1/2/3/4)
- VPS / Cloudflare / Bot / Web Panel page ordering
- dry-run Summary
- Token safety reminder
- Recovery block
- Control-plane warning
- Excessive background log noise
- Raw command noise
- PLAIN mode (`NANOBK_PLAIN=1`)
- NO_EMOJI mode (`NANOBK_NO_EMOJI=1`)

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
- Do NOT share real VPS IP, real workers.dev subdomain, or real subscription URL in chat or issues.
- Do NOT paste Reality private keys anywhere.

The commands below use `--dry-run --defaults` and mock mode. They should NOT contain real secrets.

## 4. Recommended Commands

### Standard dry-run (default mode)

```bash
NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash installer/install.sh --mode full --dry-run --defaults --lang zh
```

### PLAIN mode (no color, no emoji, no Unicode bars)

```bash
NANOBK_PLAIN=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash installer/install.sh --mode full --dry-run --defaults --lang zh
```

### NO_EMOJI mode (color kept, emoji disabled)

```bash
NANOBK_NO_EMOJI=1 NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash installer/install.sh --mode full --dry-run --defaults --lang zh
```

### Save output to file for review

```bash
NANOBK_TEST_MOCK=1 NANOBK_ASSUME_PORTS_FREE=1 \
  bash installer/install.sh --mode full --dry-run --defaults --lang zh \
    2>&1 | tee /tmp/nanobk-v1.8-cli-visual.txt
```

> This command uses mock + dry-run + defaults. It should NOT contain real secrets.

### Run automated snapshot tests

```bash
bash tests/unified-cli-visual-snapshot-v1.8.sh
bash tests/unified-cli-dry-run-layout-v1.8.sh
bash tests/unified-cli-ui-v1.8.sh
```

## 5. Human Review Checklist

### Entry Page

- [ ] Can you immediately tell this is NanoBK?
- [ ] Can you tell this is "Full Recommended"?
- [ ] Can you tell it will guide VPS + Cloudflare + Bot + Web Panel?
- [ ] Is the token safety reminder clear?

### Stage Pages

- [ ] Are stages 1/2/3/4 in clear order?
- [ ] Are VPS / Cloudflare / Bot / Web Panel easy to understand?
- [ ] Is there too much background command noise?
- [ ] Are recovery commands clear when a stage fails?

### dry-run

- [ ] Does it clearly say `planned / dry-run`?
- [ ] Does it clearly state no real deployment was performed?
- [ ] Does it NOT look like "successfully deployed"?

### Security

- [ ] Is there no token / SECRET / ADMIN_TOKEN / SUB_TOKEN / NANOB_TOKEN in the output?
- [ ] Is the token safety reminder clear?
- [ ] Does it NOT ask you to `cat` env files?

### Summary

- [ ] Can you clearly see VPS / Cloudflare / Bot / Web status?
- [ ] Are `skipped` / `dry-run` / `control plane only` honest?
- [ ] Is there no `status: success` that could mislead?

### Overall Feel

- [ ] Does the page look clean?
- [ ] Does it feel like a product wizard, not a scattered script?
- [ ] Which wording still feels unnatural?
- [ ] Which parts are too verbose?
- [ ] Which parts don't look polished enough?

## 6. PASS / NEEDS POLISH / BLOCKED Criteria

### PASS

- Page structure is clear.
- dry-run does not mislead.
- Summary is honest.
- Secrets do not leak.
- A beginner can understand what to do next.

### NEEDS POLISH

- Wording feels unnatural.
- Page feels too crowded.
- Stage transitions are not obvious.
- Recovery commands feel abrupt.
- Summary doesn't look like a product page.
- PLAIN / NO_EMOJI mode looks messy.

### BLOCKED

- Secret leakage (token, IP, Worker URL, env contents).
- dry-run looks like real successful deployment.
- Control-plane warning is missing.
- Status words are beautified into `success`.
- Flow hangs or crashes.
- Real deployment behavior is triggered.

## 7. Feedback Template

```
NanoBK v1.8 CLI Visual Feedback

Test command:
  (paste the command you ran)

Terminal:
  (e.g., iTerm2, Terminal.app, tmux, SSH)

Mode:
  default / plain / no-emoji

Overall:
  PASS / NEEDS POLISH / BLOCKED

Looks good:
  -

Needs polish:
  -

Confusing wording:
  -

Too noisy:
  -

Possible safety issue:
  -

Screenshots:
  (Do NOT include tokens, real IPs, real Worker URLs, or env contents.)
```
