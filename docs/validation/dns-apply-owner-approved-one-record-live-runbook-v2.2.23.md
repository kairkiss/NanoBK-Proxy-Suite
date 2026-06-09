# v2.2.23 — Owner-Approved One-Record Live Test Runbook

v2.2.23 is docs-only.
This runbook does not execute Cloudflare calls.
This runbook does not mutate DNS.
This runbook does not read real env files.
This runbook does not enable public CLI/Bot/Web/installer apply.
Actual live mutation remains blocked until a later owner-approved phase.

---

## 1. Scope and non-goals

**Scope:** Define the human and technical gates for a future one-record
controlled live Cloudflare DNS test. This runbook documents the exact
steps, approval flow, credential handling, pre-check, preview, mutation
rules, post-check, rollback, stop conditions, and success/failure criteria.

**Non-goals:**

- No implementation of live wrapper or live mutation.
- No public UX integration (CLI, Bot, Web, installer).
- No DNS-01, Tunnel/Access, or certificate changes.
- No release or tag.
- No real Cloudflare API calls from this document.
- No real env file reading.

---

## 2. Required human-provided placeholders

The following placeholders must be filled in by the owner before any
live test can proceed. They are safe categories only — real values must
never be printed in reports, pasted to AI, or stored in logs.

- `SAFE_ZONE_CATEGORY` — e.g. "owner-controlled disposable test zone"
- `SAFE_TEST_RECORD_CATEGORY` — e.g. "disposable test subdomain"
- `SAFE_RECORD_TYPE` — "A" or "AAAA"
- `SAFE_EXPECTED_CONTENT_CATEGORY` — e.g. "test IPv4 address" or "test IPv6 address"
- `SAFE_CREDENTIAL_FILE_REFERENCE` — local path reference only, never printed
- `OWNER_APPROVAL_PHRASE` — exact phrase defined in section 3

These are placeholders only.
Real values must never be printed in reports.
Real env file content must never be pasted to AI.
Real tokens must never be pasted to AI.
Raw domains, hostnames, IPs, record IDs, zone IDs, and account IDs must
never be pasted to AI.

---

## 3. Owner approval phrase

Before any live mutation, the owner must explicitly approve by providing
the following exact phrase:

```
I UNDERSTAND THIS WILL CHANGE CLOUDFLARE DNS FOR A TEST RECORD
```

Approval occurs:

- **after safe preview** — the owner has seen the safe preview summary.
- **after rollback instructions** — the owner has received manual rollback
  instructions.
- **after post-check explanation** — the owner understands that post-check
  will verify the record after mutation.
- **before any mutation** — no mutation may proceed without this phrase.

The system must not show a raw mutation command.

---

## 4. Credential handling

- Owner creates credential file locally or on VPS.
- Credential reference may be provided as input but **never printed**.
- `chmod 600` required on the credential file.
- **Never** cat/source/eval real env files.
- Never echo token.
- **Never** print raw API output.
- Helper stdout/stderr must be captured internally.
- Redaction scan required before final output.
- No secret persistence in profile, current directory, or logs.

---

## 5. Repo state gate

Before any live test:

- Must be on `main` branch.
- Expected HEAD must be explicitly verified.
- Worktree must be clean (no uncommitted changes).
- No release tag on current commit.
- No public integration enabled.

---

## 6. Test record identity policy

- **one record only** — no batch, no multi-record, no multi-zone.
- **disposable test record only** — the record must be safe to delete or
  leave as-is without affecting any service.
- **owner-controlled zone** — the zone must be owned/controlled by the
  repository owner.
- **create-only first** — no update, no overwrite, no delete in the initial
  controlled test.
- **DNS-only only** — proxied must be false (DNS-only mode).
- **no delete** — the controlled test must never delete DNS records.
- **no overwrite** — the test must not overwrite existing unmanaged records.
- **no production names** — the test record name must not match any
  production subscription, proxy, web, Bot, or Worker hostname.
- **no subscription/proxy/web/Bot/Worker hostnames** — the test record
  must not affect any live service.
- **absent or managed-test-only** — the target record must not exist, or
  must be a record previously created by the test and marked as managed.
- **same-name CNAME absent** — no CNAME record exists at the same name.
- **record type expected** — the planned record type (A or AAAA) is valid.
- **safe preview generated before approval** — a safe preview must be shown
  to the owner before approval.

No raw domain or IP.

---

## 7. Pre-check steps

Before any live mutation:

1. Validate placeholder completeness — all placeholders in section 2 are filled.
2. Validate safe record category — the record is disposable and test-only.
3. Validate no production category — the record name does not match any
   production hostname.
4. Validate absent or managed-test-only — the target record does not exist
   or is managed by the test.
5. Validate same-name CNAME absent — no CNAME conflict at the target name.
6. Validate no unmanaged overwrite — the test will not overwrite records
   not created by the test.
7. Validate no delete — the test will not delete any records.
8. Validate safe preview availability — a safe preview can be generated.

---

## 8. Preview steps

The safe preview must include:

- Safe zone category (not raw domain).
- Safe test record category (not raw hostname).
- Safe record type (A or AAAA).
- Safe action category (create, update, noop).
- No-delete statement.
- Post-check requirement explanation.
- Manual rollback reminder.

The safe preview must **forbid**:

- Raw domain name.
- Raw hostname.
- Raw IP address.
- Record ID.
- Zone ID or account ID.
- API token or env path.
- API response body.
- Raw mutation command.

---

## 9. Mutation execution rules

Even though this runbook does not execute mutation, the following rules
define future mutation behavior:

- **single record only** — one record per test run.
- **create-only first** — only create operations in the initial test.
- **DNS-only proxied false** — the record must be DNS-only.
- **no delete** — no records are deleted.
- **no overwrite** — no existing records are overwritten.
- **stop-on-first-failure** — if the single create fails, the test stops.
- **helper stdout/stderr captured** — helper output is captured internally,
  never printed.
- **helper JSON/schema gate required** — helper JSON must pass schema
  validation.
- **safe renderer required** — the safe renderer must produce a safe summary.
- **redaction scan before stdout** — output must pass a forbidden-pattern
  scan before being printed.

No raw mutation command is included in this runbook.

---

## 10. Post-check steps

After any future live mutation, the following post-checks must verify:

- **API accepted mutation** — the API response indicates success.
- **GET observes record** — a subsequent GET request finds the record.
- **record exists** — the record is present in the zone.
- **type matches** — the record type (A or AAAA) matches the plan.
- **content matches internally** — the record content matches the planned
  value (comparison done internally, not printed).
- **proxied is false** — the record is DNS-only (proxied: false).
- **same-name CNAME absent** — no CNAME record exists at the same name.
- **expected safe subset count matches** — the number of records matches
  the planned count.
- **no unexpected delete** — no records were deleted.
- **verified only after post-check** — the `verified` status is only
  assigned after post-check confirms all of the above.
- **redacted output passes** — the final output passes a forbidden-pattern
  scan.
- **manual rollback instruction remains available** — the owner can still
  manually remove the test record if needed.

---

## 11. Success criteria

Success is only if **all** of the following are true:

1. Pre-check passed.
2. Safe preview passed.
3. Owner approval phrase matched.
4. Mutation accepted by API.
5. Post-check verified.
6. Redacted output passed.
7. Manual rollback instruction available.
8. No raw output printed.
9. No public integration enabled.

**Failure, partial, uncertain, manual_pending, or rollback_unverified must not be called success.**

No fake success.
No success without post-check verification.

---

## 12. Failure / uncertain criteria

The following statuses are defined for non-success states:

- `precheck_failed` — a pre-check condition was not met.
- `approval_missing` — the owner approval phrase was not provided.
- `mutation_failed` — the API rejected the mutation or the mutation timed out.
- `postcheck_failed` — post-check could not verify the record.
- `redaction_failed` — the output contained forbidden patterns.
- `rollback_unverified` — the rollback could not be verified.
- `manual_pending` — the test requires manual intervention.
- `uncertain` — the state is ambiguous or cannot be determined.

No blind retry.
No fake success.
No success without post-check verification.

---

## 13. Manual rollback / recovery

- **initial phase does not auto-delete** — the controlled test does not
  automatically delete records. Deletion is manual only.
- **manual rollback instruction exists before mutation** — before any live
  mutation, the system must document how to manually remove the test record
  via the Cloudflare dashboard.
- **owner manually removes or reverts test record** — if the test produces
  unexpected results, the owner manually removes the test record via the
  Cloudflare dashboard.
- **rollback verification should be recorded as safe category only** — if
  rollback is verified, the status is recorded using safe categories only
  (no raw domain/IP/record ID).
- **if rollback cannot be verified, status is uncertain or manual_pending,
  not success** — if the rollback state cannot be confirmed, the test
  does not report success.

No raw dashboard URL with account/zone IDs.

---

## 14. Stop conditions

The controlled live test must **hard-stop** if any of the following
conditions are true:

- dirty repo (uncommitted changes).
- unexpected HEAD (commit hash does not match expected value).
- credential file permission not 600.
- placeholder missing (any placeholder in section 2 is not filled).
- unsafe record category (record is not disposable/test-only).
- production category detected (record name matches production hostname).
- pre-check unavailable (pre-check cannot run).
- unmanaged existing record (a record exists that was not created by the test).
- same-name CNAME conflict (a CNAME record exists at the target name).
- preview unavailable (safe preview cannot be generated).
- owner phrase missing (approval phrase not provided).
- helper capture failure (helper output cannot be captured).
- helper JSON/schema failure (helper JSON does not pass schema validation).
- post-check unavailable (post-check cannot run).
- redaction scan failure (output contains forbidden patterns).
- raw output risk (output would leak sensitive information).
- rollback instruction missing (manual rollback instructions not available).
- public integration detected (public CLI/Bot/Web/installer apply is enabled).

---

## 15. Redacted output contract

### Allowed output

- Status bucket (applied, verified, partial, failed, conflict, uncertain, ready).
- Mode (fake_only, dry_run, check_only, live_pending, live_applied).
- Safe zone category (not raw domain).
- Safe test record category (not raw hostname).
- Safe record type (A, AAAA).
- Safe action category (create, update, noop, conflict, skip).
- Counts (planned, applied success, applied failed, verified, post-check failed, unknown).
- Fake/live honesty statement.
- No-delete statement.
- Post-check result category.
- Manual rollback reminder.
- First failed gate/reason (if blocked).

### Forbidden output

- raw domain name.
- raw hostname.
- raw IP address (IPv4 or IPv6).
- record ID.
- zone ID or account ID.
- API token or Authorization header.
- env file path.
- profile file path.
- raw API response body.
- API endpoint path.
- workers.dev URL.
- subscription URL.
- protocol URI (vless://, trojan://, hysteria2://, tuic://).
- private key or Reality private key.
- full sha256-like hex hash.
- `apply --yes` or any raw CLI invocation instruction.
- raw mutation command.
- raw helper stdout/stderr.

---

## 16. What not to do

- **Do not** paste real env files to AI.
- **Do not** paste tokens to AI.
- **Do not** paste real domain/IP/record ID/zone ID/account ID to AI.
- **Do not** run live mutation from this runbook.
- **Do not** expose public apply.
- **Do not** add Bot/Web/installer apply.
- **Do not** tag or release.

---

## 17. Public UX block

Public `bin/nanobk` live apply remains blocked.
No Bot apply.
No Web apply.
No installer apply.
All remain blocked until separate public UX review.
Release/tag remains blocked.

Public UX needs:

- Owner-approved controlled live proof.
- Redacted live summary proof.
- Rollback proof.
- Repeatable gate script.
- Separate public UX review.

---

## 18. Future phase labels

Tentative only — no live mutation is approved by v2.2.23:

- **v2.2.24-mock** — one-record runbook validator using placeholders.
- **v2.2.25-skeleton** — non-public wrapper skeleton with fake transport.
- **v2.2.26-live-plan** — owner-approved manual live test plan, no public UX.

Labels are tentative and no live mutation is approved by v2.2.23.
