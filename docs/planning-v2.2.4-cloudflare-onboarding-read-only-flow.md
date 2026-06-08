# v2.2.4 — Cloudflare Onboarding Read-only Flow Design

## 1. Purpose

This document defines the read-only-first Cloudflare onboarding target flow
for the future `nanobk` console. It covers credential discovery, zone/domain
selection, VPS IPv4/IPv6 detection, subdomain proposal, availability checks,
DNS profile preview, DNS plan preview, readiness report, beginner Summary,
advanced detail boundary, mutation boundary, fallback states, redaction rules,
and future mock/static test strategy.

This is a design document. It does not implement any new behavior. No Cloudflare
API calls are made. No DNS records are created. No runtime code is changed.

---

## 2. Baseline

**Existing read-only DNS preparation commands (v2.1.4–v2.1.12):**

| Command | Behavior |
|---------|----------|
| `nanobk cf zones list` | GET-only zone listing, masked output |
| `nanobk cf dns readiness` | Read-only readiness report |
| `nanobk cf dns target preview` | Fixture-backed IP + zone target preview |
| `nanobk cf dns availability check` | GET-only single subdomain availability |
| `nanobk cf dns availability summary` | GET-only multi-subdomain summary |
| `nanobk cf dns report` | Combined target + availability report |
| `nanobk cf dns plan` | Local dry-run DNS plan |
| `nanobk cf dns validate-profile` | Local profile validation |

**Existing profile commands (v2.1.14–v2.1.17):**

| Command | Behavior |
|---------|----------|
| `nanobk cf dns profile preview` | In-memory validation, no file write |
| `nanobk cf dns profile generate` | Temp-output writer, chmod 600, no overwrite |
| `nanobk cf dns profile generate --allow-production-output` | Fake-root production writer (test only) |

**Existing IP detection (v2.1.6):**

| Command | Behavior |
|---------|----------|
| `nanobk vps ip detect` | Fixture-first, classified, masked output |

**Existing apply (v2.0.9):**

| Command | Behavior |
|---------|----------|
| `nanobk cf dns apply --check` | GET-only, no mutation |
| `nanobk cf dns apply --yes` | POST/PATCH mutation (explicit, not in onboarding) |

**Key properties of existing commands:**

- All zone/list/readiness/availability/target commands are GET-only.
- No POST/PATCH/DELETE Cloudflare calls from any read-only command.
- All output is masked/redacted (IPs, domains, zone IDs, tokens).
- Fake transport hooks exist for testing without real API calls.
- Profile generate writes to temp/test paths only (fake-root for production).

---

## 3. Product Goal

Cloudflare onboarding should feel like a guided wizard that discovers,
detects, and plans — but does not change anything until the user explicitly
confirms. The user should leave onboarding knowing exactly what will happen
when they choose to apply, without any surprise mutations having occurred.

---

## 4. Read-only-first Rule

**The entire onboarding flow is read-only.** No Cloudflare POST/PATCH/DELETE
calls. No DNS record creation. No DNS record update. No DNS record deletion.
No DNS apply. No DNS-01 TXT creation. No Tunnel creation. No Access policy
creation.

The onboarding flow produces a **plan**, not an **action**. The user reviews
the plan and decides whether to proceed with mutation in a separate, explicit
step.

**Cloudflare was not called unless explicitly stated.** If the flow performs
a GET-only check, the copy says "checked existing records (read-only)". It
does not say "connected to Cloudflare" or "configured Cloudflare".

---

## 5. Beginner Flow Overview

The beginner flow is the default. It uses numbered menus, concise status
lines, emoji indicators, and beginner-friendly copy. Engineering details
are hidden.

**Beginner flow steps:**

1. Open `nanobk` console.
2. Select "Cloudflare onboarding" (menu option 4).
3. Console checks whether Cloudflare credentials are available (without
   printing them).
4. If credentials missing: show safe setup guidance (how to create env file).
5. If credentials exist: list zones using GET-only behavior.
6. User selects a zone from the list (or enters domain manually as fallback).
7. Console detects VPS IPv4/IPv6 using safe detection.
8. If IP detection is ambiguous or unavailable: ask for manual IP input.
9. Console proposes `proxy.<domain>` for proxy and `web.<domain>` for Web Panel.
10. Console checks availability for proposed subdomains.
11. If occupied: refuse overwrite, offer custom subdomain input.
12. Console shows DNS profile preview (read-only, no file write).
13. Console shows DNS plan preview (read-only, no mutation).
14. Console shows readiness report.
15. Console shows beginner Summary:
    - What was detected
    - What was planned
    - What was not changed
    - What requires explicit future confirmation

**No step in this flow performs DNS mutation.** Step 15 is a Summary of
what was planned, not what was done.

---

## 6. Advanced Flow Overview

Advanced flow reveals additional detail but does not bypass safety gates.
It is opt-in (advanced mode must be enabled).

**Advanced flow additions:**

- Zone list shows masked zone IDs alongside domain names.
- IP detection shows classification scope (global, private, documentation,
  etc.) for each candidate.
- Availability check shows record ownership status (nanobk-owned, conflict,
  manual-review).
- DNS profile preview shows full field list (still masked).
- DNS plan preview shows planned record types and targets (still masked).
- Readiness report shows all individual check results.
- Summary includes additional diagnostic context.

**Advanced flow does NOT:**

- Print raw zone IDs, account IDs, or API tokens.
- Print raw IP addresses or domain names.
- Print raw env file content.
- Bypass confirmation gates for dangerous operations.
- Auto-enable (must be explicitly toggled).

---

## 7. Cloudflare Credential Discovery Policy

The onboarding flow must discover whether Cloudflare credentials are
available without printing them.

**Discovery steps:**

1. Check whether a Cloudflare API env file exists at the expected path.
2. If found: validate file permissions (must be chmod 600).
3. If permissions valid: parse allowed keys only (`CF_API_TOKEN`,
   `CF_ZONE_ID`, `CF_ZONE_NAME`).
4. If `CF_API_TOKEN` is present: credentials are available.
5. If `CF_ZONE_ID` and `CF_ZONE_NAME` are present: zone binding is available.

**What is NOT done:**

- The token value is never printed.
- The env file content is never printed.
- The env file path is not shown in beginner mode (advanced mode may show
  a masked reference).
- No shell `source`, `eval`, or `cat` on the env file.

**Beginner copy if credentials missing:**

> Cloudflare credentials not found.
> To connect NanoBK to Cloudflare, you need to create an API token.
> Would you like to see the setup guide?
>
> 1) Show setup guide
> 2) Back

**Beginner copy if credentials found:**

> Cloudflare credentials found.
> Checking your zones...

(The copy does not say which file or where — just that credentials exist.)

---

## 8. Zone List and Domain Selection

**Zone listing uses GET-only API calls.** The existing `cf zones list`
command already implements this.

**Beginner display:**

```
  Your Cloudflare zones:
  1) ex***e.com
  2) ex***le.org
  3) Enter domain manually
  4) Back
```

Domain names are masked (middle characters hidden). Zone IDs are not shown
in beginner mode.

**Advanced display:**

```
  Your Cloudflare zones:
  1) ex***e.com  (zone: abc1…345)
  2) ex***le.org (zone: def6…789)
  3) Enter domain manually
  4) Back
```

Zone IDs are shown masked (first 4 + last 3 characters) in advanced mode.

**Manual domain input is fallback only.** If the user selects "Enter domain
manually", the console asks for the full domain name. The domain is validated
(must be a valid DNS name, no URL/slash/space/wildcard). The console does
not verify that the domain exists in Cloudflare — that happens during
availability check.

---

## 9. VPS IPv4 / IPv6 Detection

**VPS IP detection uses safe detection policy.** The existing `vps ip detect`
command implements fixture-first detection with classification.

**Detection policy:**

1. Attempt auto-detection using safe methods (fixture-first in test mode,
   well-known IP echo services in production).
2. Classify each detected IP: global, private, documentation, loopback,
   link-local, multicast, reserved, ula.
3. Only global IPs are usable for DNS targets.
4. If exactly one usable IPv4 and/or one usable IPv6: auto-select.
5. If multiple usable candidates or no usable candidates: require manual
   input.

**Beginner display (auto-detected):**

```
  VPS IP detected:
  IPv4: 203.0.11x.xxx (auto-detected)
  IPv6: 2001:db8:… (auto-detected)
```

**Beginner display (manual required):**

```
  Could not auto-detect VPS IP.
  Please enter your VPS IPv4 address:
  > _
```

**Advanced display:**

```
  VPS IP candidates:
  IPv4: 203.0.11x.xxx (scope: global, source: eth0)
  IPv6: 2001:db8:… (scope: global, source: eth0)
  Other candidates: 10.0.0.xxx (scope: private, skipped)
```

**What is NOT done:**

- Raw IP addresses are never printed (always masked).
- Private/loopback/link-local IPs are never proposed as DNS targets.
- IP detection does not call Cloudflare.
- IP detection does not write to any file.

---

## 10. proxy.\<domain\> and web.\<domain\> Proposal

**The onboarding flow proposes two subdomains:**

- `proxy.<domain>` — for proxy protocols (HY2, TUIC, Reality, Trojan)
- `web.<domain>` — for Web Panel

**Proposal rules:**

- `proxy.<domain>` is the default for proxy services.
- `web.<domain>` is the default for Web Panel.
- Both are proposed automatically after zone selection and IP detection.
- The user can accept defaults or enter custom subdomains.
- Custom subdomain input validates the same way as zone labels.

**Beginner display:**

```
  Proposed subdomains:
  proxy.ex***e.com  →  proxy services (HY2, TUIC, Reality, Trojan)
  web.ex***e.com    →  Web Panel

  1) Accept defaults
  2) Customize subdomains
  3) Back
```

**Critical rule: existing records must not be overwritten.** The availability
check (step 10) determines whether the proposed subdomains are available.
If occupied, the flow refuses overwrite and offers custom subdomain input.

---

## 11. DNS Availability Check

**Availability check uses GET-only API calls.** The existing
`cf dns availability check` and `cf dns availability summary` commands
implement this.

**Check behavior:**

1. Query Cloudflare for existing A/AAAA records at each proposed subdomain.
2. Classify each result:
   - `available` — no existing record, safe to create.
   - `nanobk_owned` — existing record with nanobk ownership marker.
   - `conflict` — existing record without nanobk ownership, must not overwrite.
   - `manual_review` — ambiguous state, needs human review.
   - `failed` — check failed (API error, network issue).

**Beginner display:**

```
  Checking DNS availability...
  proxy.ex***e.com  🟢 available
  web.ex***e.com    🟢 available
```

Or if occupied:

```
  proxy.ex***e.com  🔴 occupied (existing record found)
  web.ex***e.com    🟢 available

  proxy.ex***e.com is already in use.
  NanoBK will NOT overwrite existing records.

  1) Choose a different subdomain for proxy
  2) Skip proxy subdomain
  3) Back
```

**Critical rule: no overwrite.** If a subdomain is occupied by a record
that nanobk does not own, the flow refuses to overwrite it. The user must
choose a different subdomain or skip.

**Proxy DNS records must be DNS-only (proxied=false).** This is enforced
at the profile level and at the apply level. The onboarding flow does not
change this requirement.

---

## 12. DNS Profile Preview vs Generate

The onboarding flow must clearly distinguish between profile preview and
profile generate.

**Profile preview:**

- Read-only.
- No file write.
- Validates in-memory profile candidate.
- Shows masked summary of what would be written.
- Safe for beginner flow.
- Already implemented: `nanobk cf dns profile preview`.

**Profile generate to temp output:**

- Local file write to temp/test path.
- chmod 600 expected.
- No overwrite of existing file.
- Atomic write (temp + hard link or os.replace).
- Still not DNS applied.
- Already implemented: `nanobk cf dns profile generate`.

**Production profile write:**

- Writes to `/etc/nanobk/cloudflare-dns-profile.json`.
- Dangerous. Out of scope for v2.2.4 onboarding.
- Requires metadata/provenance, lock, backup, explicit approval.
- Only under fake-root test mode in current codebase.

**Onboarding flow uses profile preview only.** The flow shows what the
profile would contain, without writing it. If the user wants to generate
the profile, that is a separate explicit step after onboarding.

**Critical distinction:**

- "Profile previewed" is **not** "profile generated".
- "Profile generated" is **not** "DNS applied".
- "DNS plan previewed" is **not** "DNS updated".

---

## 13. DNS Plan Preview

**DNS plan preview is read-only.** The existing `cf dns plan` command
implements this.

The plan shows:

- Planned A record for `proxy.<domain>` (IPv4, DNS-only)
- Planned AAAA record for `proxy.<domain>` (IPv6 if available, DNS-only)
- Planned A record for `web.<domain>` (IPv4, DNS-only)
- Planned AAAA record for `web.<domain>` (IPv6 if available, DNS-only)
- Reserved hostnames (panel, nanok, nanob)
- Explicit statement: "no mutation performed"

**Beginner display:**

```
  DNS plan for ex***e.com:
  proxy.ex***e.com  →  203.0.11x.xxx (DNS-only)
  web.ex***e.com    →  203.0.11x.xxx (DNS-only)

  No changes have been made.
  This is a preview only.
```

**Advanced display adds:**

```
  Record types: A, AAAA
  Proxied: false (DNS-only, mandatory for proxy)
  Reserved: panel, nanok, nanob (not created)
  No Cloudflare API call was made.
```

---

## 14. Readiness Report

**Readiness report is read-only.** The existing `cf dns readiness` command
implements this.

The report checks:

- API env file: present, permissions, parsing, allowed keys
- Zone discovery: successful, zone bound
- DNS profile: present, valid schema
- Local plan metadata: present
- DNS availability: checked, all available

**Beginner display:**

```
  Readiness report:
  🟢 Cloudflare credentials    ready
  🟢 Zone detected             ex***e.com
  🟢 VPS IP                    detected
  🟢 DNS availability          all available
  🟢 DNS profile               planned
  Overall: ready for DNS apply
```

**Advanced display adds individual check details and any warnings.**

---

## 15. Beginner Summary Contract

The beginner Summary is the final screen of the onboarding flow. It
summarizes what was detected, what was planned, and what was NOT changed.

**Summary must include:**

- What was detected:
  - Cloudflare zone: masked domain
  - VPS IPv4: masked IP
  - VPS IPv6: masked IP (if available)
  - Proposed subdomains: masked

- What was planned:
  - DNS profile: planned (not generated)
  - DNS plan: previewed (not applied)
  - Readiness: ready / not ready

- What was NOT changed:
  - No DNS records created
  - No DNS records updated
  - No DNS records deleted
  - No Cloudflare API mutation calls
  - No production profile written
  - No Bot/Web configuration changed

- What requires explicit future confirmation:
  - DNS apply is a separate future flow with its own preview, confirmation, post-check, and recovery guidance.
  - Profile generation is a separate explicit step and is not DNS applied.
  - These are separate explicit steps, not part of onboarding.

**Beginner Summary mock:**

```
  ════════════════════════════════════════
  Cloudflare Onboarding Summary
  ════════════════════════════════════════

  Detected:
    Zone:     ex***e.com
    IPv4:     203.0.11x.xxx
    IPv6:     2001:db8:…
    Proxy:    proxy.ex***e.com  🟢 available
    Web:      web.ex***e.com    🟢 available

  Planned:
    DNS profile:  previewed (not written)
    DNS plan:     previewed (not applied)
    Readiness:    ready

  Not changed:
    ✗ No DNS records created
    ✗ No Cloudflare mutation
    ✗ No production files written

  Next steps (explicit, not automatic):
    1. Review this plan in Advanced mode if needed
    2. Continue to the separate DNS apply flow when you are ready

  DNS apply is NOT part of onboarding.
  NanoBK will show a separate preview, confirmation,
  and recovery summary before any DNS changes.
  ════════════════════════════════════════
```

---

## 16. Advanced Detail Contract

Advanced mode adds detail to each screen but does not bypass safety gates.

**Advanced additions per screen:**

| Screen | Advanced addition |
|--------|-------------------|
| Credential discovery | Masked env file reference, key presence flags |
| Zone list | Masked zone IDs |
| IP detection | Classification scope, source interface |
| Subdomain proposal | Record type details (A, AAAA) |
| Availability check | Ownership status, record count |
| Profile preview | Full field list, schema version |
| DNS plan | Record type breakdown, proxied status |
| Readiness report | Individual check details, warnings |

**Advanced does NOT add:**

- Raw zone IDs, account IDs, or API tokens
- Raw IP addresses or domain names
- Raw env file content
- Auto-confirmation for dangerous operations

---

## 17. Mutation Boundary

**Read-only onboarding stops before mutation.** The following are NOT part
of v2.2.4 onboarding:

- `nanobk cf dns apply --yes` (DNS mutation)
- DNS record create/update/delete
- Cloudflare POST/PATCH/DELETE
- DNS-01 TXT record creation
- Cloudflare Tunnel creation
- Cloudflare Access policy creation
- Real `/etc/nanobk/cloudflare-dns-profile.json` write
- Bot/Web exposed mutation button

**Future mutation gate requirements:**

| Gate | Description |
|------|-------------|
| preview | Show what would happen before doing it |
| dry-run | Validate inputs and show plan without executing |
| read-only check | Query current state without mutation |
| explicit confirmation | Require typed confirmation or button press |
| beginner Summary | Show clear summary of what was done |
| backup / metadata | Create backup and record provenance where applicable |
| post-check | Validate state after mutation |
| rollback/recovery guidance | Provide clear recovery instructions on failure |
| redaction | Mask sensitive values in output |
| advanced-mode-only detail | Show detailed output only in advanced mode |

**These gates apply to future mutation steps, not to the read-only
onboarding flow.**

---

## 18. Error and Fallback States

The onboarding flow must handle errors gracefully.

| Error state | Behavior |
|-------------|----------|
| Credentials not found | Show setup guidance, offer to show guide |
| Credentials invalid (bad token) | Show safe error, suggest re-setup |
| Zone list empty | Show message, offer manual domain input |
| Zone list API error | Show safe error, offer manual domain input |
| IP detection failed | Ask for manual IP input |
| IP detection ambiguous (multiple candidates) | Show masked candidates, ask user to choose |
| IP detection returned private-only | Show warning, ask for manual IP input |
| Availability check failed | Show safe error, suggest retry |
| Availability check shows conflict | Refuse overwrite, offer custom subdomain |
| Profile validation failed | Show safe error, suggest checking inputs |
| Network error | Show safe error, suggest checking connectivity |

**Error copy must not:**

- Print raw API responses
- Print raw error messages from Cloudflare
- Print raw IP addresses, domain names, or zone IDs
- Print env file content or token values
- Suggest running `apply --yes` as a fix for errors

---

## 19. State Vocabulary

The following states apply to each onboarding component:

| Component | Possible states |
|-----------|----------------|
| Cloudflare credentials | `not_configured`, `ready`, `action_needed` |
| Zone/domain | `not_configured`, `detected`, `manual_pending`, `unknown` |
| VPS IPv4 | `detected`, `manual_pending`, `unknown` |
| VPS IPv6 | `detected`, `manual_pending`, `unknown` |
| Proxy subdomain | `available`, `conflict`, `manual_pending`, `planned` |
| Web subdomain | `available`, `conflict`, `manual_pending`, `planned` |
| DNS profile | `planned`, `dry_run`, `failed`, `unknown` |
| DNS plan | `planned`, `dry_run`, `failed`, `unknown` |
| Readiness report | `ready`, `action_needed`, `failed`, `unknown` |

**Critical distinctions:**

- `planned` means "a plan exists" — not "the plan was executed".
- `available` means "the subdomain is free" — not "the DNS record was created".
- `detected` means "an IP was found" — not "the IP was written to a profile".
- `ready` means "all checks passed" — not "DNS was applied".

---

## 20. Safety and Redaction Rules

The onboarding flow follows the same redaction rules as Bot, Web, and Console.

**Never print:**

- Raw API tokens
- Raw private keys
- Protocol links (`hysteria2://`, `tuic://`, `vless://`, `trojan://`)
- Subscription URLs
- `workers.dev` URLs
- Raw env file content
- Raw Authorization headers
- Full SHA-256 hashes

**Mask:**

- IP addresses: `203.0.113.xxx` (last octet hidden)
- Domain names: `ex***e.com` (middle characters hidden)
- Zone IDs: `abc1…345` (first 4 + last 3 characters)
- Tokens: `sha256:abcd1234` (fingerprint only)

**Onboarding-specific rules:**

- Env file path is not shown in beginner mode.
- Cloudflare API implementation details are hidden in beginner mode.
- Record type jargon (A, AAAA, CNAME, TXT) is hidden in beginner mode
  (advanced mode may show it).
- Zone ID and Account ID are never shown in beginner mode.

---

## 21. Future Mock Test Strategy

Future tests should verify the onboarding flow design without implementing
the full flow. The following test files are planned:

### tests/v2.2.4-cloudflare-onboarding-flow-design.sh

**Purpose:** Verify the onboarding flow structure matches the design spec.

**Assertions (future/mock):**

- Onboarding entry is read-only (no POST/PATCH/DELETE in source).
- Zone listing uses GET-only behavior.
- IP detection uses safe classification.
- Subdomain proposal includes proxy and web.
- Availability check uses GET-only behavior.
- Profile preview is read-only (no file write).
- DNS plan preview is read-only.
- Readiness report is read-only.
- Summary states "no DNS records created".
- Summary states "no Cloudflare mutation".
- Summary states "next steps require explicit confirmation".

### tests/v2.2.4-cloudflare-onboarding-copy-safety.sh

**Purpose:** Verify beginner copy does not contain engineering jargon.

**Assertions (future/mock):**

- Beginner onboarding does not mention Zone ID.
- Beginner onboarding does not mention Account ID.
- Beginner onboarding does not mention API env file path.
- Beginner onboarding does not mention A/AAAA/CNAME record types.
- Beginner onboarding does not contain `apply --yes`.
- Beginner onboarding does not contain raw token patterns.
- Beginner onboarding does not contain raw IP addresses.
- Beginner onboarding does not contain raw domain names.

### tests/v2.2.4-cloudflare-onboarding-redaction-static.sh

**Purpose:** Verify no raw secrets appear in onboarding output.

**Assertions (future/mock):**

- Onboarding output does not contain `CF_API_TOKEN=`.
- Onboarding output does not contain `BOT_TOKEN=`, `SUB_TOKEN=`, `ADMIN_TOKEN=`.
- Onboarding output does not contain `PRIVATE KEY`.
- Onboarding output does not contain `workers.dev`.
- Onboarding output does not contain `hysteria2://`, `tuic://`, `vless://`, `trojan://`.
- Onboarding output does not contain raw IP addresses.
- Onboarding output does not contain raw domain names.

### tests/v2.2.4-cloudflare-onboarding-mutation-boundary.sh

**Purpose:** Verify onboarding does not perform mutation.

**Assertions (future/mock):**

- Onboarding source code does not call `apply` with `--yes`.
- Onboarding source code does not call Cloudflare POST/PATCH/DELETE.
- Onboarding source code does not call DNS mutation functions.
- Onboarding source code does not write to `/etc/nanobk/`.
- Onboarding source code does not create DNS records.
- Onboarding Summary says "no mutation".
- Onboarding Summary says "not DNS applied".

---

## 22. Explicit Non-goals

v2.2.4 does **not**:

- Implement Cloudflare onboarding runtime.
- Implement DNS mutation.
- Implement Cloudflare POST/PATCH/DELETE.
- Implement DNS-01.
- Implement Tunnel/Access.
- Implement real `/etc` writes.
- Implement real rollback.
- Modify runtime code.
- Modify `bin/nanobk`.
- Modify installer scripts.
- Modify Bot/Web runtime.
- Call real Cloudflare API.
- Create a release tag.

---

## 23. Acceptance Criteria

This document is accepted when:

1. All 23 sections are present and complete.
2. Read-only-first rule is explicit and comprehensive.
3. Beginner flow is defined with 15 numbered steps.
4. Advanced flow additions are defined without bypassing safety.
5. Credential discovery does not print secrets.
6. Zone list and domain selection are GET-only.
7. VPS IP detection is safe and classified.
8. Subdomain proposal includes proxy and web.
9. Availability check refuses overwrite.
10. Profile preview vs generate is clearly distinguished.
11. DNS plan preview is read-only.
12. Readiness report is read-only.
13. Beginner Summary is comprehensive and honest.
14. Mutation boundary is explicit.
15. Error and fallback states are covered.
16. State vocabulary is defined with critical distinctions.
17. Safety/redaction rules are comprehensive.
18. Future test strategy covers flow, copy, redaction, and mutation.
19. Non-goals are explicit.
20. No runtime code is changed.
21. No secrets or protocol links are printed.
