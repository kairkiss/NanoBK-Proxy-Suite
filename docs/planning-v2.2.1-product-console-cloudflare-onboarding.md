# v2.2.1 — Product Console + Cloudflare Onboarding Scope Proposal

## 1. Purpose

This document defines the product scope for the v2.2 line. It is a planning
document, not an implementation spec. It captures the owner's product direction
for NanoBK Proxy Suite: install-only default, `nanobk` as daily entry point,
beginner-friendly console UX, read-only-first Cloudflare onboarding, and
production safety gates for dangerous operations.

v2.2.1 is docs-only. No runtime behavior is added or changed.

---

## 2. Product North Star

NanoBK Proxy Suite should feel like a single product, not a collection of
scripts. The user installs once and then interacts through `nanobk`. The
experience should be:

- **Calm.** No wall of engineering output by default.
- **Branded.** The user always knows they are inside NanoBK.
- **Safe by default.** Read-only operations are the default. Dangerous
  operations require explicit confirmation.
- **Beginner-friendly.** New users should not see engineering internals unless
  they opt in.
- **Auditable.** Engineering logs exist but are hidden by default. Advanced
  mode can reveal them.

---

## 3. Current Baseline

As of v2.1.26, the repo has delivered:

- **Install-only bootstrap.** `bootstrap.sh` without arguments clones the repo,
  prepares the `nanobk` CLI, and exits. It does not auto-deploy.
- **Interactive console.** `nanobk console` (or `nanobk` with no args on TTY)
  shows a branded numbered menu with safe beginner-friendly navigation.
- **Read-only DNS preparation.** Zone listing, readiness, target preview,
  availability, combined report, plan dry-run, profile validation.
- **Profile management skeleton.** Preview, generate, backup, replace preview,
  rollback preview, rollback execute — all under fake-root test mode.
- **Production safety policy.** Real `/etc` rollback is deferred. Metadata/
  provenance is required before real production profile operations.
- **Bot/Web control planes.** Owner-only, CLI-subprocess architecture, advanced
  mode gating, Chinese/English i18n.
- **VPS IP detection skeleton.** Fixture-first, classified, masked output.
  Live detection is deferred.

---

## 4. Owner Target for This Product Line

The owner wants NanoBK to become a product that a non-engineer can install and
use. The target user:

1. Installs NanoBK with one command.
2. Opens `nanobk` to see a clean branded console.
3. Follows guided flows to set up Cloudflare DNS for their VPS.
4. Manages their proxy and web panel through the console.
5. Never sees engineering internals unless they choose Advanced mode.

This is a product direction, not just a feature list.

---

## 5. Scope Decision

**v2.2 scope is: Product Console + Cloudflare Onboarding + Production Safety.**

This is not only a "Production Profile Management" scope decision. Production
profile management remains a required safety track inside v2.2, especially
metadata/provenance before real `/etc` runtime. But the broader v2.2 scope
includes:

- Product console / TUI redesign
- Cloudflare onboarding read-only flow
- Install behavior documentation alignment
- Production safety gates for DNS mutation, certificates, Tunnel, Access

The v2.2 line should deliver a product experience, not just safety scaffolding.

---

## 6. Install Does Not Equal Deploy

**Product rule:** One-line install installs NanoBK only.

- `bootstrap.sh` without arguments clones the repo, prepares `nanobk`, and
  exits.
- Install does not auto-deploy VPS protocols.
- Install does not auto-run Full Wizard by default.
- The user decides when and what to deploy, through `nanobk`.

This is the v2.1.1 direction and should be preserved and documented clearly.

---

## 7. nanobk as the Daily Entry Point

**Product rule:** User starts and maintains product through `nanobk`.

- `nanobk` with no arguments should open the interactive console on TTY.
- `nanobk` with no arguments in non-TTY should show a safe entry screen and
  exit.
- All product capabilities should be reachable through `nanobk`.
- The installer is a one-time tool. `nanobk` is the ongoing interface.

---

## 8. Beginner Mode vs Advanced Mode

**Product rules:**

- Beginner mode should hide engineering details.
- Advanced mode may reveal details safely.
- The default experience should be beginner mode.
- Engineering logs should be hidden by default but auditable.

The existing Bot/Web advanced mode gating (`/advanced on`, `/advanced off`)
establishes this pattern. The console should follow the same model.

---

## 9. Product Console Target UX

**Product rules:**

- Default CLI/TUI should be prettier, calmer, concise, and brand-forward.
- Progress bars, concise status, and small emoji can be used for product
  clarity.
- The console should feel like a product, not a script wrapper.
- Menu items should use clear labels, not engineering jargon.
- Safety labels (`[safe]`, `[explicit]`, `[advanced]`) should be preserved and
  extended.

The v2.1.2 branded console is the starting point. v2.2 should refine the
visual design, reduce noise, and add guided flows.

---

## 10. Cloudflare Onboarding Target Flow

**Product rules:**

- Cloudflare onboarding should be read-only-first.
- Zone detection should happen before manual domain input.
- User should select domain from Cloudflare zones when possible.
- VPS IPv4/IPv6 should be auto-detected when safe.
- Manual IP input should only be fallback.

**Target flow:**

1. User opens `nanobk` console.
2. Selects "Cloudflare Onboarding" or similar guided flow.
3. Console checks Cloudflare API credentials (env file).
4. Console lists available zones (GET-only, read-only).
5. User selects a zone from the list (or enters manually if needed).
6. Console detects VPS IP addresses (auto-detect or manual fallback).
7. Console proposes `proxy.<domain>` for proxy services and `web.<domain>`
   for Web Panel.
8. Console checks DNS availability for proposed subdomains.
9. Console shows a plan preview (read-only, no mutation).
10. User reviews and confirms (separate step for actual DNS mutation).

---

## 11. DNS and Domain Automation Policy

**Product rules:**

- `proxy.<domain>` should be proposed for proxy services.
- `web.<domain>` should be proposed for Web Panel.
- Existing proxy or web records must not be overwritten.
- DNS-only is mandatory for proxy records (proxied=false).
- DNS profile generation is not DNS applied.
- Cloudflare was not called unless explicitly stated.
- DNS apply/check must remain separate from profile generation.

The v2.1 read-only DNS preparation commands already implement most of this.
The console should present them as a guided flow.

---

## 12. VPS IP Detection Policy

**Product rules:**

- VPS IPv4/IPv6 should be auto-detected when safe.
- Manual IP input should only be fallback.

The v2.1.6 IP detection skeleton is fixture-first. v2.2 should add live
detection as a safe default, with manual fallback when auto-detection is
ambiguous or unavailable.

**Safety:** Live IP detection should use well-known public IP echo services.
Results should be classified (global, private, documentation, etc.) and masked
in output. Private or loopback results should not be proposed as DNS targets.

---

## 13. proxy.\<domain\> and web.\<domain\> Policy

**Product rules:**

- `proxy.<domain>` should be proposed for proxy services (HY2, TUIC, Reality,
  Trojan).
- `web.<domain>` should be proposed for Web Panel.
- Existing proxy or web records must not be overwritten.
- DNS-only is mandatory for proxy records (proxied=false).
- Cloudflare HTTP proxy (orange-cloud) is not suitable for non-standard proxy
  ports.

The v2.1 availability check already detects existing records and ownership.
The console should surface this as a clear pass/conflict/manual-review status.

---

## 14. Certificate / DNS-01 Policy

**Product rule:** DNS-01 certificate automation is future design, not v2.2.1
implementation.

DNS-01 certificate automation requires:

- Cloudflare API token with zone DNS edit permissions
- TXT record creation and verification
- Certificate request and renewal
- ACME client integration

This is a significant feature with its own safety surface. It should be designed
separately, with its own safety gates, dry-run model, and confirmation flow.

**v2.2.1 does not implement DNS-01.** The v2.2 roadmap reserves a design slot
for it after explicit approval.

---

## 15. Cloudflare Tunnel + Access Policy

**Product rule:** Cloudflare Tunnel + Access are future design, not v2.2.1
implementation.

Cloudflare Tunnel would expose the Web Panel (or other services) through
Cloudflare's network without opening ports on the VPS. Cloudflare Access would
add authentication in front of the tunnel.

These are significant features with their own safety surfaces:

- Tunnel creation modifies Cloudflare infrastructure
- Access policies affect who can reach the service
- Both require Cloudflare API calls with specific permissions
- Misconfiguration could expose services unintentionally

**v2.2.1 does not implement Tunnel or Access.** The v2.2 roadmap reserves
design slots for them after explicit approval.

---

## 16. Production Profile Management Relationship

**Product rule:** Production Profile Management remains a required safety track
inside v2.2, especially metadata/provenance before real `/etc` runtime.

The v2.1 line delivered fake-root profile management (preview, generate, backup,
replace preview, rollback preview, rollback execute). The v2.1.25 policy defines
the production safety requirements for real `/etc` rollback.

v2.2 should deliver:

- Metadata/provenance design (v2.2.5)
- Fake-root metadata implementation (v2.2.6)
- DNS apply execution design gate (v2.2.7)

Real `/etc` rollback implementation should only proceed after these are complete
and explicitly approved.

---

## 17. Bot/Web Control Plane Boundary

**Product rules:**

- Bot/Web remain control planes and must call CLI only.
- Bot/Web must not directly write configs, systemd, DNS, env, secrets, Worker
  env, or protocol files.

This boundary is established in v1.9 and must be preserved in v2.2. The console
is the primary product interface. Bot and Web are secondary control planes that
delegate to the CLI.

---

## 18. Safety Gates for Dangerous Operations

The following table defines the safety gates required before implementing
dangerous operations in v2.2+.

| Operation | Risk | v2.2.1 Status | Required Gates |
|-----------|------|---------------|----------------|
| DNS record create/update/delete | Cloudflare mutation, service disruption | Not implemented | preview, dry-run, read-only check, explicit confirmation, Summary, post-check, rollback/recovery guidance |
| Certificate DNS-01 automation | Cloudflare mutation, certificate management | Not implemented | preview, dry-run, read-only check, explicit confirmation, Summary, backup, metadata/provenance, post-check, rollback/recovery guidance |
| Cloudflare Tunnel creation | Cloudflare infrastructure change, service exposure | Not implemented | preview, dry-run, read-only check, explicit confirmation, Summary, metadata/provenance, post-check, rollback/recovery guidance |
| Cloudflare Access policy creation | Access control change, service exposure | Not implemented | preview, dry-run, read-only check, explicit confirmation, Summary, metadata/provenance, post-check, rollback/recovery guidance |
| Production /etc/nanobk/cloudflare-dns-profile.json write | Local production file mutation | Not implemented | preview, dry-run, read-only check, explicit confirmation, Summary, backup, metadata/provenance, lock, atomic write, post-check, rollback/recovery guidance |
| Real rollback | Local production file replacement | Not implemented | preview, dry-run, read-only check, explicit confirmation, Summary, backup, metadata/provenance, lock, atomic write, post-check, rollback/recovery guidance, advanced-mode visibility |
| systemd changes | Service management, system state | Not implemented | preview, dry-run, read-only check, explicit confirmation, Summary, backup, metadata/provenance, rollback/recovery guidance |
| protocol config changes | Service disruption, connectivity loss | Not implemented | preview, dry-run, read-only check, explicit confirmation, Summary, backup, metadata/provenance, rollback/recovery guidance |
| Bot/Web-exposed operations | Unauthorized access, automated misuse | Not implemented | preview, dry-run, read-only check, explicit confirmation, Summary, redaction, advanced-mode visibility |

**Gate definitions:**

- **preview**: Show what would happen before doing it.
- **dry-run**: Validate inputs and show plan without executing.
- **read-only check**: Query current state without mutation.
- **explicit confirmation**: Require typed confirmation phrase or button press.
- **Summary**: Show a clear summary of what was done after completion.
- **backup**: Create a backup before mutation.
- **metadata/provenance**: Record origin, timestamp, and checksum of changes.
- **lock**: Acquire file lock to prevent concurrent writes.
- **atomic write**: Use temp file + hard link or os.replace() for safe writes.
- **post-check**: Validate state after mutation.
- **rollback/recovery guidance**: Provide clear recovery instructions on failure.
- **redaction**: Mask sensitive values in output.
- **advanced-mode visibility**: Show detailed output only in advanced mode.

---

## 19. Explicit Non-goals for v2.2.1

v2.2.1 does **not**:

- Implement DNS mutation
- Implement Cloudflare mutation
- Implement DNS-01 certificate automation
- Implement Cloudflare Tunnel
- Implement Cloudflare Access
- Implement real `/etc` writes
- Implement real rollback
- Implement live IP detection
- Modify runtime code
- Modify installer scripts
- Modify Bot/Web runtime
- Modify protocol templates
- Modify Cloudflare Worker code
- Run deployment
- Call real Cloudflare API
- Print secrets, tokens, or protocol links
- Create a release tag

---

## 20. Proposed v2.2 Roadmap

```
v2.2.0-planning
  Product Console + Cloudflare Onboarding + Production Safety Scope Decision

v2.2.1
  Docs-only product console/onboarding scope proposal

v2.2.2
  Install behavior documentation alignment and README/bootstrap wording plan

v2.2.3
  Branded nanobk console/TUI mock design and tests

v2.2.4
  Cloudflare onboarding read-only flow design:
  zone list, domain selection, VPS IP detection, proxy/web availability, DNS plan preview

v2.2.5
  Metadata/provenance design for production profile backups

v2.2.6
  Fake-root metadata/provenance implementation

v2.2.7
  DNS apply execution design gate

v2.2.8+
  Only after explicit approval:
  controlled DNS mutation UX integration,
  DNS-01 certificate design/implementation,
  Cloudflare Tunnel/Access planning
```

This roadmap is conservative. Each step builds on the previous. No step expands
scope beyond what is explicitly approved.

---

## 21. Future Test Strategy

v2.2 testing should follow the v2.1 pattern:

- **Fake-root test model.** Real production paths remain blocked in tests.
  Test hooks simulate production paths under fake-root.
- **Source checks.** Tests verify that runtime code does not contain forbidden
  patterns (real Cloudflare API calls, real `/etc` writes, secret leakage).
- **Fixture-first.** External dependencies (Cloudflare API, IP echo services)
  are replaced with fixtures in tests.
- **Focused test scripts.** Each new capability gets a focused test script with
  comprehensive assertions.
- **`nanobk test --all`.** All focused tests are included in the unified test
  suite.

---

## 22. Acceptance Criteria

This document is accepted when:

1. All 30 product rules are recorded.
2. The scope decision is explicitly stated.
3. The v2.2 roadmap is conservative and staged.
4. The safety gate table covers all dangerous operations.
5. The non-goals are explicit.
6. No runtime code is changed.
7. No secrets or protocol links are printed.
