# v2.2.2 — Install Behavior Documentation Alignment

## 1. Purpose

This document records the wording alignment between the actual install behavior
(bootstrap.sh) and the user-facing documentation (README.md).

As of v2.1.1, `bootstrap.sh` default behavior is install-only: it clones or
updates the repo, prepares the `nanobk` CLI, and exits. It does not auto-launch
the deployment installer. The README, however, still presents a flow where the
install command leads directly to deployment. This document corrects that
alignment.

v2.2.2 is docs-only. No runtime behavior is added or changed.

---

## 2. Baseline

**bootstrap.sh (v2.1.1) actual behavior:**

- Default (no `--` arguments): clones/updates repo, prepares `nanobk` CLI,
  prints "NanoBK is ready. Start here: nanobk", exits.
- With `--` arguments (e.g., `-- --mode full`): passes arguments to
  `installer/install.sh` (legacy path).
- The completion message says: "Deployment is no longer started automatically."

**README.md (pre-v2.2.2) wording:**

- Presents v1.9.60 as the stable version.
- Quick install section shows commands that imply deployment starts after install.
- "安装注意事项" says "安装完成后，Bot 和 Web 控制台会自动启动" (Bot and Web
  auto-start after install) — this is no longer true for the default path.
- No clear separation between "install" and "deploy".

**bin/nanobk (v2.1.1) actual behavior:**

- `nanobk` with no args on TTY opens interactive console.
- `nanobk` with no args in non-TTY shows safe entry screen and exits.
- Console menu provides access to status, doctor, deployment, DNS tools, etc.

---

## 3. Product Rule: Install Does Not Equal Deploy

**Rule:** One-line install installs NanoBK repository and prepares the `nanobk`
command. It does not deploy VPS protocols, configure Cloudflare, or start
services.

This rule is already implemented in bootstrap.sh (v2.1.1). The documentation
must reflect it clearly.

---

## 4. One-line Install Contract

The one-line install command:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kairkiss/NanoBK-Proxy-Suite/main/installer/bootstrap.sh)
```

**Does:**

- Clones or updates the NanoBK repository
- Prepares the `nanobk` CLI command (symlink to `/usr/local/bin/nanobk`)
- Prints "NanoBK is ready" with instructions to start with `nanobk`

**Does not:**

- Deploy VPS protocols (HY2, TUIC, Reality, Trojan)
- Configure Cloudflare
- Start Bot or Web services
- Auto-run Full Wizard
- Modify system services

---

## 5. nanobk Daily Entry Contract

After install, the user types `nanobk` to enter the product.

- On TTY: opens interactive branded console with numbered menu
- On non-TTY: shows safe entry screen and exits

The console provides:

- Status and Doctor
- Deployment options (explicit, confirmation-gated)
- Cloudflare DNS tools (read-only submenu)
- Key rotation guidance
- Advanced help

`nanobk` is the ongoing daily interface. The installer is a one-time tool.

---

## 6. Legacy Full Wizard Contract

The legacy Full Wizard remains available through explicit command:

```bash
nanobk install --mode full
```

Or through the bootstrap passthrough:

```bash
bash installer/bootstrap.sh -- --mode full
```

This is documented as legacy/explicit, not default behavior. The Full Wizard
still works as before — it is not removed or broken. It is simply not the
default entry point.

---

## 7. README Alignment Policy

The README should:

1. Present a clear Quick Start with three steps: Install → Open → Deploy
2. Make it obvious that install does not deploy
3. Point users to `nanobk` as the daily entry point
4. Preserve advanced/legacy install modes in a separate section
5. Not imply that Bot/Web auto-start after install
6. Not make claims about features that are not yet implemented

The README should not:

1. Remove any existing capabilities
2. Break any existing links or references
3. Make false claims about v2.2 features
4. Remove the v1.9.60 stable version information entirely (it remains valid)

---

## 8. Bootstrap Wording Policy

The bootstrap.sh wording is already product-correct (v2.1.1). No changes to
bootstrap.sh are needed or allowed in v2.2.2.

The README must match the bootstrap.sh wording, not the other way around.

---

## 9. Beginner-facing Wording

Beginner-facing wording should be:

- Clear and direct
- Focused on what the user does, not what the system does
- Separated into distinct steps
- Free of engineering jargon where possible

Example:

> **Step 1: Install NanoBK**
> This installs the NanoBK repository and prepares the `nanobk` command.
> It does not deploy proxy services automatically.
>
> **Step 2: Open NanoBK**
> Type `nanobk` to open the console.
>
> **Step 3: Start deployment**
> From the console, choose the deployment option.

---

## 10. Advanced / Legacy Wording

Advanced and legacy commands should be preserved but clearly labeled:

- "Advanced / legacy explicit commands"
- "These commands bypass the console and run directly."
- "Most users should use `nanobk` instead."

Legacy modes include:

- `nanobk install --mode full`
- `nanobk install --mode vps`
- `nanobk install --mode bot`
- `nanobk install --mode web`
- `bash installer/bootstrap.sh -- --mode full`

---

## 11. Explicit Non-goals

v2.2.2 does **not**:

- Change bootstrap.sh behavior
- Change installer/install.sh behavior
- Change bin/nanobk behavior
- Add new CLI commands
- Implement DNS mutation, Cloudflare mutation, DNS-01, Tunnel, or Access
- Implement real /etc writes or rollback
- Create a release tag

---

## 12. Acceptance Criteria

This document is accepted when:

1. README Quick Start clearly separates Install / Open / Deploy
2. README does not imply install auto-deploys
3. README points to `nanobk` as daily entry point
4. Legacy Full Wizard is preserved as explicit/advanced
5. No runtime behavior is changed
6. No false claims about unimplemented features
