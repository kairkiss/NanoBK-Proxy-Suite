# v2.2.9 — DNS Apply UX Integration Scope Decision

## 1. Purpose

This document records the integration scope decision for DNS apply beginner
UX. It evaluates four options and selects the path forward for v2.2.9. It
does not implement any wrapper, console integration, or DNS mutation.

---

## 2. Baseline

**v2.2.7 delivered:** DNS apply execution design gate — a 10-step flow
defining readiness, plan preview, conflict check, beginner Summary,
advanced details, explicit confirmation, mutation, post-check, final
Summary, and recovery guidance.

**v2.2.8 delivered:** Mock fixture files and static tests capturing target
beginner/advanced output contracts. These fixtures are output contracts
only — they do not execute DNS apply or call Cloudflare.

**Current low-level `cf dns apply`** exists as a CLI helper with useful
safety properties but is not beginner-console-ready.

---

## 3. Current Foundation

The v2.2 line has built the following foundation for DNS apply productization:

| Component | Status |
|-----------|--------|
| DNS readiness report | Implemented (read-only) |
| DNS plan preview | Implemented (read-only) |
| DNS target preview | Implemented (read-only) |
| DNS availability check | Implemented (GET-only) |
| DNS profile preview | Implemented (read-only) |
| DNS profile generate | Implemented (temp-output, fake-root) |
| Low-level `cf dns apply` | Implemented (dry-run/check/apply) |
| Fake transport | Implemented (test-only) |
| Ownership marker model | Implemented |
| Conflict detection | Implemented (conservative) |
| Execution gate design | Documented (v2.2.7) |
| Beginner UX mock fixtures | Created (v2.2.8) |
| Beginner UX static tests | Created (v2.2.8) |
| Beginner renderer | Not implemented |
| Typed confirmation gate | Not implemented |
| Post-check contract | Not implemented |
| Partial failure UX | Not implemented |
| Redaction wrapper | Not implemented |

---

## 4. Scope Decision

**v2.2.9 chooses Option A: docs-only integration scope decision.**

No real DNS mutation is allowed in v2.2.9.
No real Cloudflare mutation is allowed in v2.2.9.
No beginner console apply button is allowed in v2.2.9.
No Bot/Web apply button is allowed in v2.2.9.

v2.2.8 fixtures are output contracts only, not executable DNS apply
behavior.

Current low-level `cf dns apply` is not beginner-console-ready.

---

## 5. Why Real DNS Mutation Is Still Rejected

Real DNS mutation (calling Cloudflare POST/PATCH to create or update DNS
records) is rejected for v2.2.9 and v2.2.10 for the following reasons:

**Output safety gaps:**

- Low-level text formatter shows raw record name (`action.name`) and raw
  planned content (`action.planned_content`) at line 759 of
  `lib/nanobk_cf_dns_apply.py`.
- JSON output shows raw `name`, `plannedContent`, `existingContent`,
  `recordId`.
- No beginner-safe renderer exists.

**Confirmation gaps:**

- No typed confirmation gate (`apply dns records`).
- No numbered menu.
- `--yes` alone is not enough for product UX.

**Post-check gaps:**

- No post-check contract after mutation.
- No verification that expected records exist with correct content and
  proxied=false.

**Partial failure gaps:**

- No partial failure UX model.
- No honest state taxonomy (applied/uncertain/partial).
- No recovery guidance for partial states.

**Redaction gaps:**

- No redaction wrapper for record names, planned content, or record IDs.
- No masking of domain, hostname, or IP in apply output.

Until these gaps are filled, real DNS mutation must not enter the product
console.

---

## 6. Option A — Docs-only Continuation

**Selected for v2.2.9.**

**Characteristics:**

- Lowest risk.
- Freezes the integration decision before any implementation.
- Defines acceptance criteria for v2.2.10 wrapper.
- Preserves all existing safety properties.
- No runtime code changes.

**What it delivers:**

- This document.
- Clear decision: real mutation is rejected.
- Clear path: v2.2.10 may implement fake-transport-only wrapper.

**Why selected:**

- v2.2.7 defined the gate. v2.2.8 defined the output contracts. v2.2.9
  should freeze the integration decision before touching code.
- The decision to reject real mutation is important enough to document
  explicitly.

---

## 7. Option B — Mock-only Continuation

**Not selected for v2.2.9.**

**Characteristics:**

- Safe but not enough.
- v2.2.8 already covers the main fixture states (beginner summary,
  advanced details, confirmation, post-check success/failure, partial
  failure).
- Additional fixtures can happen later but do not answer integration
  mechanics.

**Why not selected:**

- v2.2.8 already delivered the core fixtures.
- More fixtures without answering "how do we integrate?" is incremental
  without strategic value.

---

## 8. Option C — Fake-transport-only Wrapper

**Candidate for v2.2.10.**

**Characteristics:**

- Feasible after v2.2.9 scope decision.
- Hidden/test-only wrapper that renders fixture-style output.
- Requires `NANOBK_CF_DNS_FAKE_TRANSPORT` environment variable.
- Fails closed if fake transport is missing.
- Makes real transport impossible (no real HTTP calls).
- Supports post-check success/failure and partial failure in fake mode.
- Does not call real Cloudflare.

**Guardrails:**

- Must require fake transport env var.
- Must fail closed if fake transport missing.
- Must make real transport impossible.
- Should not integrate into `bin/nanobk` public console initially.
- Should render fixture-style masked output.
- Must support post-check success/failure and partial failure in fake mode.
- Must not call real Cloudflare.

**Why not selected for v2.2.9:**

- Implementation step should follow scope decision, not overlap with it.
- v2.2.9 should freeze the decision; v2.2.10 should implement the wrapper.

---

## 9. Option D — Real Cloudflare Mutation UX

**Rejected for now.**

**Characteristics:**

- High risk.
- Blocked by lack of executable beginner renderer, post-check, typed
  confirmation, partial-failure model, and redaction wrapper.
- Would require real Cloudflare API calls.
- Would create real DNS records.

**Why rejected:**

- All gaps listed in section 5 apply.
- No beginner-safe output exists.
- No post-check exists.
- No partial failure model exists.
- No typed confirmation exists.
- `--yes` alone is insufficient for product UX.

**When it might be reconsidered:**

- After v2.2.10 fake-transport wrapper proves the UX model.
- After post-check, partial failure, and redaction are implemented.
- After explicit Owner approval.

---

## 10. Selected Direction for v2.2.9

**v2.2.9 selects Option A: docs-only integration scope decision.**

This means:

- No code changes.
- No wrapper implementation.
- No console integration.
- No real DNS mutation.
- Clear documentation of why real mutation is rejected.
- Clear path to v2.2.10 as the next possible implementation step.

---

## 11. Future v2.2.10 Candidate Scope

**Possible v2.2.10: Fake-transport-only DNS Apply UX Wrapper**

Allowed future characteristics:

- Hidden/test-only wrapper.
- No public beginner console apply button.
- No Bot/Web button.
- No real transport.
- No Cloudflare call.
- No DNS mutation outside fake transport.
- Fixture-style output.
- Fake post-check.
- Fake partial failure.
- Fail-closed on missing fake transport.

Possible future files (not created in v2.2.9):

- `lib/nanobk_cf_dns_apply_ux_mock.py`
- `tests/v2.2.10-dns-apply-ux-fake-wrapper.sh`
- `CHANGELOG.md`

---

## 12. Fake-transport-only Wrapper Guardrails

If v2.2.10 implements Option C, the following guardrails are required:

| Guardrail | Requirement |
|-----------|-------------|
| Fake transport required | `NANOBK_CF_DNS_FAKE_TRANSPORT` must be set |
| Missing fake transport | Must fail closed with safe error |
| Real transport impossible | No real HTTP calls under any condition |
| Public console button | Not integrated initially |
| Output style | Fixture-style masked output |
| Post-check | Simulated success/failure |
| Partial failure | Simulated partial state |
| Real Cloudflare | Never called |

---

## 13. Product Boundary

**Beginner console should not expose real DNS apply yet.**

- `apply --yes` must not appear in beginner copy.
- Installer must not run DNS apply silently.
- Full Wizard must not silently run DNS apply.
- Bot/Web must not directly invoke DNS apply mutation.
- Bot/Web may only invoke approved CLI flow after CLI gates exist.
- Manual `--yes` guidance, if present in legacy/manual contexts, remains
  outside beginner UX and should be reviewed later.

---

## 14. Runtime Touch Decision

**v2.2.9 does not touch any runtime files.**

No changes to:

- `lib/nanobk_cf_dns_apply.py`
- `lib/nanobk_cf_dns.py`
- `bin/nanobk`
- `installer/`
- `bot/`
- `web/`
- `tests/`

This is a docs-only decision document.

---

## 15. Stop-on-first-failure vs Continue-and-report-partial

**For future beginner product UX, stop-on-first-failure is the safer default
unless fake-transport tests prove continue-and-report-partial is clearer and
recoverable.**

**Why stop-on-first-failure is safer:**

- Reduces mixed state (some records created, some not).
- Simpler recovery guidance (either it happened or it didn't).
- Avoids "partial success" confusion for beginners.
- Post-check is simpler when all-or-nothing.

**When continue-and-report-partial might be useful:**

- A/AAAA dual-stack: IPv4 succeeds, IPv6 fails. User may want the IPv4
  record even if IPv6 fails.
- Multiple hostnames: proxy succeeds, web fails. User may want partial
  progress.

**Requirements for continue-and-report-partial:**

- Fake-transport tests must cover: A succeeds / AAAA fails.
- Post-check must verify each record independently.
- Partial must never be reported as success.
- Recovery guidance must be per-record, not global.
- User must understand which records were created and which weren't.

**Decision:** Stop-on-first-failure is the default for future beginner UX.
Continue-and-report-partial requires explicit approval and fake-transport
proof before adoption.

---

## 16. Future Test Strategy

If v2.2.10 implements Option C, future tests must assert:

| Assertion | Description |
|-----------|-------------|
| Fake transport required | Wrapper fails closed without env var |
| Missing fake transport | Safe error, no crash |
| Real transport impossible | No real HTTP calls under any condition |
| No `--yes` in beginner copy | `apply --yes` not exposed |
| Masked domain/hostname/IP | No raw values in output |
| Numbered menu + typed phrase | Confirmation gate exists |
| Dry-run/check/apply simulated | Fake transport handles all modes |
| Post-check success | `Status: applied` |
| Post-check failure | `Status: uncertain` |
| Partial failure | `Status: partial`, not success |
| No raw token/env/API body/response | Redaction enforced |
| No raw record ID | Redacted in output |
| No raw domain/hostname/IP | Masked in output |
| No Bot/Web invocation | Not exposed to control planes |
| No public console apply button | Not in beginner menu |
| No Cloudflare call | Never called |

---

## 17. Risk Map

**High risk:**

| Risk | Description |
|------|-------------|
| Accidentally enabling real mutation | Wrapper could leak real transport |
| Beginner output leaking raw values | Domain/IP/record ID exposure |
| Exposing `--yes` as beginner path | Single flag insufficient for product |
| No post-check | Mutation without verification |
| Partial failure confusion | Users don't understand partial state |

**Medium risk:**

| Risk | Description |
|------|-------------|
| Touching `bin/nanobk` too early | Console integration before wrapper proven |
| Wrapper duplicating apply logic | Maintenance burden |
| Fake transport drift | Fake behavior diverges from real apply |
| Legacy `--yes` guidance | Mistaken for beginner UX |

**Low risk:**

| Risk | Description |
|------|-------------|
| Static fixtures exist | v2.2.8 output contracts |
| Fake transport exists | Test infrastructure ready |
| No delete/force | Conservative existing behavior |
| Conflict behavior | Already conservative |

---

## 18. Bot/Web Boundary

**Bot/Web must not:**

- Directly call Cloudflare.
- Directly perform DNS apply mutation.
- Directly write DNS profile/env/secrets.

**Future Bot/Web may only:**

- Invoke approved CLI flow after CLI safety gates exist.

**v2.2.9:**

- No Bot/Web apply button.
- No Bot/Web runtime change.

---

## 19. Installer and Full Wizard Boundary

**Installer must not:**

- Run DNS apply silently.
- Auto-apply DNS after profile generation.
- Surface `apply --yes` as a default action.

**Full Wizard must not:**

- Silently run DNS apply.
- Auto-apply DNS after DNS preparation stage.
- Skip confirmation for DNS mutation.

**Both remain:**

- Guidance-only for DNS apply.
- "Run these commands explicitly when ready."

---

## 20. Explicit Non-goals

v2.2.9 does **not**:

- Implement a fake-transport-only wrapper.
- Implement real DNS mutation.
- Implement beginner console apply button.
- Implement Bot/Web apply button.
- Modify `lib/nanobk_cf_dns_apply.py`.
- Modify `lib/nanobk_cf_dns.py`.
- Modify `bin/nanobk`.
- Modify installer scripts.
- Modify Bot/Web runtime.
- Implement DNS-01.
- Implement Tunnel/Access.
- Implement real `/etc` writes.
- Implement real rollback.
- Create a release tag.

---

## 21. Acceptance Criteria

This document is accepted when:

1. All 21 sections are present and complete.
2. Scope decision is explicit: Option A, docs-only.
3. Real DNS mutation is explicitly rejected for v2.2.9.
4. Option C (fake-transport wrapper) is defined as v2.2.10 candidate.
5. Option D (real mutation) is explicitly rejected for now.
6. Product boundary is clear: no beginner apply button, no Bot/Web button.
7. Stop-on-first-failure is the default for future beginner UX.
8. Risk map covers high/medium/low risks.
9. Future test strategy is defined.
10. Non-goals are explicit.
11. No runtime code is changed.
12. No secrets or protocol links are printed.
