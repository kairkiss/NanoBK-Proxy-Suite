# v2.2.7 — DNS Apply Execution Design Gate

## 1. Purpose

This document defines the future DNS apply execution gate for product-console
integration. It documents the current low-level `cf dns apply` safety
properties, why it is not yet beginner-console-ready, and what the future
execution gate requires before DNS mutation can enter the product console.

This is a design document. It does not implement any new behavior. No DNS
mutation. No Cloudflare API calls. No runtime code changes.

---

## 2. Baseline

**Current DNS apply helper (v2.0.9):**

- `nanobk cf dns apply --dry-run` — validates profile and api-env format only,
  no Cloudflare API calls.
- `nanobk cf dns apply --check` — GET-only mode, queries existing records but
  no mutation.
- `nanobk cf dns apply --yes` — POST/PATCH mutation for create/update.
- `--force` is reserved and rejected.
- DELETE is not implemented.
- Fake transport exists for tests (`NANOBK_CF_DNS_FAKE_TRANSPORT`).
- Ownership marker: `managed-by=nanobk; component=cf-dns-apply; hostname=...`.
- `defaultProxied` must be `false` or omitted; create/update payloads use
  `proxied: false`.

**Current console exposure:**

- DNS submenu shows read-only guidance only.
- `apply --check` is surfaced as a guidance command.
- `apply --yes` is NOT surfaced in the console menu.
- The console says: "Run these commands explicitly when ready."

**Current output:**

- Text output shows raw record name and raw planned content.
- JSON output shows raw `name`, `plannedContent`, `existingContent`, `recordId`.
- No beginner-safe Summary.
- No redaction of record names or planned content.

---

## 3. Current DNS Apply Reality

The current `cf dns apply` helper is a low-level CLI tool with useful safety
properties. It is NOT a product feature. It is NOT ready for beginner console
integration.

**What it does well:**

- Separate dry-run/check/apply modes.
- GET-only check mode.
- Ownership marker model.
- Conflict detection (unowned, multiple, CNAME, proxied).
- No delete support.
- No force support.
- Fake transport for tests.

**What it lacks for product use:**

- No beginner-safe Summary.
- No advanced detail toggle.
- No numbered confirmation gate.
- No typed phrase gate.
- No post-check contract.
- No partial failure recovery model.
- No final honest state taxonomy.
- No conflict-resolution UX.
- No custom subdomain fallback UX.
- Raw record name/content in output.

---

## 4. Scope Decision

**v2.2.7 is a docs-only DNS apply execution design gate.**

No DNS mutation implementation is allowed in v2.2.7.

Current low-level `cf dns apply` is not ready for beginner console integration.

Future DNS apply productization requires a separate implementation step after
this design is accepted.

---

## 5. Why v2.2.7 Is Docs-only

DNS mutation is the highest-risk operation in the product. It changes
Cloudflare infrastructure. A mistake could break proxy connectivity for all
users of a domain.

Before DNS mutation can enter the product console, the execution gate must be
designed, reviewed, and accepted. The gate defines:

- What steps must happen before mutation.
- What the user must see and confirm.
- What must happen after mutation.
- What recovery looks like on failure.

v2.2.7 designs the gate. Implementation follows only after acceptance.

---

## 6. Current Low-level Safety Properties

The existing `cf dns apply` helper has these useful safety properties:

| Property | Status |
|----------|--------|
| Unowned existing record conflict | Fails closed |
| Multiple records conflict | Fails closed |
| CNAME same-name conflict | Fails closed |
| Proxied=true conflict | Fails closed |
| Owned update requires NanoBK ownership marker | Yes |
| Ownership marker must match hostname | Yes |
| No delete support | Yes (conservative) |
| No force support | Yes (conservative) |
| Dry-run/check/apply are separate modes | Yes |
| Tests use fake transport | Yes |
| `defaultProxied` must be false | Yes |
| Create/update payloads use `proxied: false` | Yes |

These properties are the foundation for the future execution gate.

---

## 7. Current Product UX Gaps

The current helper has these product UX gaps:

| Gap | Risk |
|-----|------|
| No beginner-safe Summary | High |
| No advanced detail toggle | Medium |
| No numbered confirmation gate | High |
| No typed phrase gate | High |
| `--yes` alone is not enough for product UX | High |
| No post-check contract | High |
| No partial failure recovery model | High |
| No final honest state taxonomy | High |
| No conflict-resolution UX | Medium |
| No custom subdomain fallback UX | Medium |
| Raw record name/content in text output | High |
| Raw name/plannedContent/existingContent/recordId in JSON output | High |
| Beginner mode must not expose `apply --yes` | High |
| Bot/Web must not get direct mutation access | High |

---

## 8. Beginner Mode Requirements

Beginner mode for DNS apply must:

- Hide `apply --yes` entirely.
- Show masked zone, hostname, and IP.
- Show action counts (create/update/noop/conflict).
- Show a clear sentence: "Cloudflare DNS will be changed only after
  confirmation."
- Use numbered menus, not `[y/N]`.
- Show a beginner Summary before confirmation.
- Show a final honest Summary after mutation.
- Never expose Zone ID, Account ID, record ID, API token, raw env, raw API
  body, or raw API response.

---

## 9. Advanced Mode Requirements

Advanced mode for DNS apply may show:

- Record types (A, AAAA).
- Action classes (create, update, noop, conflict).
- Masked hostname and IP.
- Redacted record ID or short fingerprint.
- Ownership marker present/absent.
- GET/POST/PATCH count.
- Fake transport marker in tests.

Advanced mode still must NOT:

- Print raw domain, hostname, or IP.
- Print Zone ID, Account ID, or record ID.
- Print API token or Authorization header.
- Print raw env content.
- Print raw API request body or response.
- Bypass confirmation gates.
- Auto-enable.

---

## 10. DNS Apply Execution Gate

The future DNS apply execution gate is a 10-step flow:

1. Readiness confirmed
2. DNS plan preview
3. GET-only conflict check
4. Beginner Summary
5. Advanced details available
6. Explicit confirmation
7. Apply mutation
8. Post-check
9. Final honest Summary
10. Recovery guidance

Each step is defined below.

---

## 11. Readiness Step

**What it does:** Confirms that all prerequisites for DNS apply are satisfied.

**Checks:**

- Cloudflare API credentials available.
- Zone bound (CF_ZONE_ID, CF_ZONE_NAME).
- DNS profile valid.
- DNS plan computed.
- VPS IP detected or manually provided.
- All required confirmations available.

**Allowed output:**

- Readiness status per check.
- Masked zone name.
- Overall ready/not-ready status.

**Forbidden output:**

- Raw API token.
- Raw zone ID.
- Raw env content.

**Failure behavior:** If not ready, show what is missing and how to fix it.
Do not proceed to mutation.

**Read-only:** Yes.

---

## 12. DNS Plan Preview Step

**What it does:** Shows what DNS records would be created or updated.

**Allowed output:**

- Masked hostname.
- Masked IP.
- Record type (A, AAAA).
- Action class (create, update, noop).
- Proxied status (must be false).

**Forbidden output:**

- Raw hostname.
- Raw IP.
- Raw record content.

**Failure behavior:** If plan cannot be computed, show safe error.

**Read-only:** Yes.

---

## 13. GET-only Conflict Check Step

**What it does:** Queries Cloudflare for existing records at the target
hostnames. GET-only, no mutation.

**Allowed output:**

- Conflict status per hostname (available, nanobk_owned, conflict,
  manual_review).
- Masked existing content if conflict.
- Action recommendation (create, update, manual resolution needed).

**Forbidden output:**

- Raw record ID.
- Raw existing content.
- Raw API response.

**Failure behavior:** If check fails, show safe error. Do not proceed to
mutation.

**Read-only:** Yes.

---

## 14. Beginner Summary Step

**What it does:** Shows a beginner-friendly summary of what will happen.

**Must include:**

- Masked zone.
- Masked hostname.
- Masked IP.
- Action counts: N create, N update, N noop, N conflict.
- Clear sentence: "Cloudflare DNS will be changed only after confirmation."
- What will NOT happen: no delete, no force, no proxied conversion.

**Forbidden output:**

- Raw domain, hostname, IP.
- Zone ID, Account ID, record ID.
- API terminology (A/AAAA, POST/PATCH).

**Failure behavior:** If any conflict exists, say "Some records need manual
resolution. DNS will not be changed until conflicts are resolved."

**Read-only:** Yes.

---

## 15. Advanced Details Step

**What it does:** Shows additional diagnostic detail for advanced mode users.

**May show:**

- Record types (A, AAAA).
- Action classes.
- Masked existing content.
- Redacted record IDs.
- Ownership marker status.
- GET/POST/PATCH counts.

**Must NOT show:**

- Raw values.
- Secrets.
- API internals.

**Read-only:** Yes.

---

## 16. Explicit Confirmation Step

**What it does:** Requires the user to explicitly confirm before mutation.

**Confirmation model:**

1. Numbered menu: "Apply DNS records?" with options:
   - 1) Apply now
   - 2) Review again
   - 3) Cancel

2. If "Apply now" selected, require typed phrase:
   ```
   apply dns records
   ```

3. Only after both steps does mutation proceed.

**Forbidden:**

- `[y/N]` prompt for important decisions.
- Single keystroke confirmation.
- Auto-confirmation.

**Read-only:** Yes (confirmation is not mutation).

---

## 17. Apply Mutation Step

**What it does:** Executes DNS record create/update via Cloudflare API.

**Allowed operations:**

- POST: create new A/AAAA record.
- PATCH: update existing owned A/AAAA record.

**Forbidden operations:**

- DELETE.
- Force overwrite.
- Create when unowned record exists.
- Update when unowned record exists.
- Convert proxied=true to proxied=false.
- Replace CNAME records.

**Failure behavior:**

- Per-record failure does not abort other records.
- Each record result is tracked independently.
- Partial failure is reported honestly.

**Mutation:** Yes.

---

## 18. Post-check Step

**What it does:** Verifies the final state after mutation.

**Checks:**

- Expected A/AAAA records exist.
- Records have `proxied: false`.
- Ownership markers are present.
- Record content matches planned content.

**Allowed output:**

- Post-check status per record (verified, mismatch, missing).
- Overall post-check status.

**Forbidden output:**

- Raw record ID.
- Raw API response.

**Failure behavior:** Post-check failure means the final state is uncertain,
not success. Report `post_check_failed` or `uncertain`.

**Read-only:** Yes (GET-only).

---

## 19. Final Honest Summary Step

**What it does:** Shows the final state honestly.

**Must include:**

- What was done (N created, N updated, N noop).
- What was NOT done (no delete, no force).
- Post-check result (verified, mismatch, missing, not run).
- Overall status (applied, partial, failed, uncertain).

**Forbidden output:**

- Raw values.
- Claiming success when post-check failed.
- Claiming success when partial failure occurred.

**Read-only:** Yes.

---

## 20. Recovery Guidance Step

**What it does:** Provides recovery guidance for each failure state.

**Recovery guidance for:**

| State | Guidance |
|-------|----------|
| Dry-run only | "No changes were made. Review the plan and run apply when ready." |
| Check conflict | "Existing records need manual resolution. Check Cloudflare dashboard." |
| Unowned record conflict | "An existing record is not managed by NanoBK. Resolve manually." |
| Multiple record conflict | "Multiple records exist. Resolve manually in Cloudflare dashboard." |
| CNAME conflict | "A CNAME record exists. Resolve manually." |
| Proxied=true conflict | "A proxied record exists. Resolve manually." |
| API unavailable | "Cloudflare API was not reachable. Check credentials and network." |
| Rate limited | "Cloudflare rate limit reached. Wait and retry." |
| Credential failure | "Cloudflare credentials are invalid. Check api-env file." |
| Partial apply failure | "Some records failed. Check Cloudflare dashboard for current state." |
| Post-check failure | "Post-check could not verify final state. Check Cloudflare dashboard." |
| Successful apply | "DNS records applied successfully. No further action needed." |

**Default:** No automatic DNS rollback. No blind retry. No delete. No force.
Manual Cloudflare review may be required after partial/uncertain states.

---

## 21. Conflict Handling Policy

| Conflict type | Behavior |
|---------------|----------|
| No existing record | Create (safe) |
| Existing owned by nanobk, same content | Noop (safe) |
| Existing owned by nanobk, different content | Update (safe) |
| Existing unowned by nanobk | Fail closed (manual resolution) |
| Multiple existing records | Fail closed (manual resolution) |
| Existing CNAME at same name | Fail closed (manual resolution) |
| Existing proxied=true | Fail closed (manual resolution) |

**No automatic overwrite. No automatic delete. No force.**

---

## 22. Redaction and Display Policy

**Never print in beginner output:**

- Raw domain
- Raw hostname
- Raw IP
- Zone ID
- Account ID
- Record ID
- API token
- Authorization header
- Raw env
- Raw profile secret
- Raw API request body
- Raw API response
- `workers.dev` URL
- Subscription URL
- Protocol link
- Private key
- Reality private key
- Full sha256

**Advanced mode may show:**

- Record type
- Action class
- Masked hostname
- Masked IP
- Redacted record ID or short fingerprint
- Ownership marker present/absent
- GET/POST/PATCH count
- Fake transport marker in tests

**Advanced mode still must not bypass redaction.**

---

## 23. Confirmation Model

**Future confirmation for DNS apply:**

1. Numbered menu first, not `[y/N]`.
2. Then require typed phrase: `apply dns records`.
3. Beginner mode shows:
   - Masked zone.
   - Masked hostname.
   - Masked IP.
   - Action counts.
   - Action classes: create/update/noop/conflict.
   - Clear sentence: "Cloudflare DNS will be changed only after confirmation."
4. Advanced mode may show:
   - Record types.
   - Ownership marker status.
   - Redacted record IDs/fingerprints.
   - Still no secrets or raw API data.
5. `--yes` must not be exposed in beginner copy.

---

## 24. Mutation Boundary

**Readiness, preview, check, Summary, and confirmation are NOT mutation.**

**Apply mutation begins only after explicit confirmation.**

**Post-check is GET-only.**

**Future product apply may create/update A/AAAA records only.**

**Forbidden:**

- No delete.
- No force.
- No overwrite of unowned records.
- No conversion of proxied=true records.
- No CNAME replacement.
- No automatic rollback by default.

---

## 25. Bot/Web Boundary

**Bot/Web must not:**

- Directly call Cloudflare.
- Directly perform DNS apply mutation.
- Directly write DNS profile/env/secrets.

**Future Bot/Web may only:**

- Invoke approved CLI flow after CLI safety gates exist.

**v2.2.7:**

- No Bot/Web apply button.
- No Bot/Web runtime change.

---

## 26. Future Test Strategy

Future tests should verify the DNS apply execution gate without calling real
Cloudflare API.

### tests/v2.2.7-dns-apply-gate-doc.sh

**Purpose:** Verify the execution gate design is documented.

**Assertions (future/mock):**

- Gate has 10 steps.
- Each step is defined with allowed/forbidden output.
- Mutation boundary is explicit.
- Confirmation model requires numbered menu + typed phrase.
- Post-check is required after mutation.
- Recovery guidance covers all failure states.

### tests/v2.2.7-dns-apply-beginner-copy-safety.sh

**Purpose:** Verify beginner copy does not expose engineering details.

**Assertions (future/mock):**

- Beginner copy does not contain `apply --yes`.
- Beginner copy does not expose raw domain/hostname/IP.
- Beginner copy does not expose Zone ID, Account ID, record ID.
- Beginner copy does not expose token, env path, raw API body, raw API
  response.

### tests/v2.2.7-dns-apply-redaction-static.sh

**Purpose:** Verify output redaction.

**Assertions (future/mock):**

- Text output does not contain raw record names.
- JSON output does not contain raw `name`, `plannedContent`, `existingContent`.
- JSON output does not contain raw `recordId`.
- Output does not contain API token or Authorization header.

### tests/v2.2.7-dns-apply-mutation-boundary.sh

**Purpose:** Verify mutation boundary.

**Assertions (future/mock):**

- Dry-run performs no API calls.
- Check is GET-only.
- Apply requires explicit confirmation gate.
- Apply supports create/update only.
- No DELETE.
- No force.
- Unowned conflict fails closed.
- Proxied=true conflict fails closed.
- CNAME conflict fails closed.
- Multiple record conflict fails closed.
- Owned update only with ownership marker and matching hostname.

### tests/v2.2.7-dns-apply-postcheck-design.sh

**Purpose:** Verify post-check design.

**Assertions (future/mock):**

- Post-check is required after mutation.
- Post-check is GET-only.
- Post-check failure produces `uncertain` or `action_needed`, not success.
- Post-check verifies record existence, content, proxied status, ownership
  marker.
- Bot/Web do not directly invoke mutation.

---

## 27. Risk Map

**High risk:**

| Risk | Description |
|------|-------------|
| Raw hostname/IP leakage | Current apply formatter shows raw record name and planned content |
| `--yes` insufficient for product | Single CLI flag is not enough for beginner product confirmation |
| No post-check contract | No verification after mutation |
| No partial failure model | No honest reporting of partial success |

**Medium risk:**

| Risk | Description |
|------|-------------|
| Beginner/advanced boundary | Not implemented for apply |
| Conflict UX not guided | No step-by-step conflict resolution |
| Custom subdomain fallback | Not integrated |

**Low risk:**

| Risk | Description |
|------|-------------|
| No delete support | Already conservative |
| No force support | Already conservative |
| Fake transport exists | Test pattern established |
| Ownership marker model | Update model exists |

---

## 28. Explicit Non-goals

v2.2.7 does **not**:

- Implement DNS mutation.
- Implement Cloudflare API calls.
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

## 29. Acceptance Criteria

This document is accepted when:

1. All 29 sections are present and complete.
2. Scope decision is explicit (docs-only, no mutation).
3. Current reality is documented honestly.
4. Low-level safety properties are documented.
5. Product UX gaps are documented.
6. Execution gate has 10 defined steps.
7. Each step has allowed/forbidden output and failure behavior.
8. Mutation boundary is explicit.
9. Confirmation model requires numbered menu + typed phrase.
10. Post-check is required after mutation.
11. Recovery guidance covers all failure states.
12. Conflict handling policy is comprehensive.
13. Redaction policy is comprehensive.
14. Bot/Web boundary is explicit.
15. Risk map covers high/medium/low risks.
16. Future test strategy covers gate, copy, redaction, mutation, post-check.
17. Non-goals are explicit.
18. No runtime code is changed.
19. No secrets or protocol links are printed.
