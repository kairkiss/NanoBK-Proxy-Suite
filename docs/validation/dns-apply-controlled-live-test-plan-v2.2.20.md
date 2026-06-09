# v2.2.20 — Controlled Live Cloudflare DNS Test Plan and Safety Gate

## 1. Scope

v2.2.20 is docs/gate-only.

- No real Cloudflare calls.
- No DNS mutation.
- No helper invocation.
- No public CLI integration.
- No Bot apply.
- No Web apply.
- No installer apply.

This document defines the minimum safety gate before any controlled live
Cloudflare DNS test. Actual live mutation remains blocked until a future
version explicitly removes this gate with owner approval.

---

## 2. Purpose

Before any code touches real Cloudflare DNS, a safety gate must exist that
ensures:

- The test scope is minimal and disposable.
- The owner explicitly approves the risk.
- Credentials are handled safely and never printed.
- Pre-check and post-check are required.
- Output is redacted before display.
- Manual rollback is documented.
- Public UX remains blocked until a separate review.

This document and its companion static test (`v2.2.20-controlled-live-gate-contract.sh`)
serve as that gate.

---

## 3. Minimum live test scope

Any future controlled live Cloudflare DNS test must satisfy all of the
following constraints:

- **one disposable test record only** — no batch, no multi-record, no multi-zone.
- **owner-controlled zone** — the zone must be owned/controlled by the
  repository owner, not a shared or production zone.
- **single record type first** — test one record type (A or AAAA) before
  considering both.
- **create-only first** — no update, no overwrite, no delete in the initial
  controlled test.
- **no production subscription/proxy/web/Bot/Worker hostnames** — the test
  record must not affect any live service.
- **no delete** — the controlled test must never delete DNS records.
- **no overwrite of unmanaged records** — the test must not touch records
  not created by the test itself.
- **no public UX** — no beginner console, no Bot/Web apply, no installer
  integration during the controlled test phase.

---

## 4. Required owner approval phrase

Before any live mutation, the owner must explicitly approve by providing the
following exact phrase:

```
I UNDERSTAND THIS WILL CHANGE CLOUDFLARE DNS FOR A TEST RECORD
```

Before collecting this approval, the system must show the owner:

- **safe/redacted test record identity** — record type and safe category
  only, no raw domain/hostname/IP.
- **planned action category** — create, update, or noop.
- **no-delete policy** — confirmation that no records will be deleted.
- **manual rollback instruction** — how to manually remove the test record
  if needed.
- **post-check requirement** — explanation that post-check will verify the
  record after mutation.
- **redacted output policy** — confirmation that output will be scanned
  for forbidden patterns before display.

Do not show the raw mutation command to the user.

---

## 5. Credential handling policy

- **credential file path may be accepted but never printed** — the path to
  the api-env file can be passed as an argument but must never appear in
  output.
- **never cat/source/eval real env** — the env file must be parsed
  key-by-key, never sourced into the shell.
- **never echo token** — the API token must never appear in stdout, stderr,
  or logs.
- **chmod 600 required** — the credential file must have 600 permissions
  before reading.
- **raw helper stdout/stderr captured internally** — helper output must be
  captured by the integration layer, never forwarded to the user.
- **redaction scan before output** — all output must pass a forbidden-pattern
  scan before being printed.
- **only safe summary printed** — the user sees only the beginner-safe
  summary, never raw API responses or helper messages.

---

## 6. Pre-check gate

Before any live mutation, the following pre-checks must pass:

- **test record is absent or managed-test-only** — the target record must
  not exist, or must be a record previously created by the test and marked
  as managed-test-only.
- **same-name CNAME conflict is absent** — no CNAME record exists at the
  same name as the planned A/AAAA record.
- **record type is expected** — the planned record type (A or AAAA) is valid.
- **no unmanaged overwrite** — the test must not overwrite records not
  created by the test.
- **dry-run/preview before live** — a dry-run or preview must be shown to
  the owner before any live mutation.
- **owner approval after preview** — the owner must approve after seeing
  the preview.

---

## 7. Live mutation gate

Actual live mutation remains blocked in v2.2.20.

When a future version removes this block, the following rules must apply:

- **create-only** — only create operations are allowed in the initial
  controlled test.
- **single test record** — only one record is created per test run.
- **no delete** — no records are deleted.
- **no overwrite** — no existing records are overwritten.
- **stop-on-first-failure** — if the single create fails, the test stops.
- **raw output captured** — helper stdout/stderr are captured internally.
- **safe summary only** — only the beginner-safe summary is printed.

---

## 8. Post-check gate

After any future live mutation, the following post-checks must verify:

- **API accepted mutation** — the API response indicates success.
- **GET observes record** — a subsequent GET request finds the record.
- **record exists** — the record is present in the zone.
- **type matches** — the record type (A or AAAA) matches the plan.
- **content matches internally** — the record content matches the planned
  value (comparison done internally, not printed).
- **proxied is false** — the record is DNS-only (proxied: false).
- **no same-name CNAME conflict** — no CNAME record exists at the same name.
- **expected safe subset count matches** — the number of records matches
  the planned count.
- **no unexpected delete** — no records were deleted.
- **verified only after post-check** — the `verified` status is only
  assigned after post-check confirms all of the above.

Output must not show raw domain, IP, record ID, API response, token, or
env path.

---

## 9. Rollback / recovery

- **manual rollback instruction exists before mutation** — before any live
  mutation, the system must document how to manually remove the test record
  via the Cloudflare dashboard.
- **initial phase has no automatic delete** — the controlled test does not
  automatically delete records. Deletion is manual only.
- **owner manually removes/reverts test record in Cloudflare dashboard if
  needed** — if the test produces unexpected results, the owner manually
  removes the test record.
- **update test requires safe metadata backup first** — if a future test
  includes update operations, the existing record metadata must be backed
  up (in safe, redacted form) before mutation.
- **failed/partial/uncertain state must not tell beginner to blindly retry**
  — recovery guidance must be safe and specific, not "try again."

---

## 10. Stop conditions

The controlled live test must hard-stop if any of the following conditions
are true:

- **repo dirty** — the git working tree is not clean.
- **unexpected HEAD** — the commit hash does not match the expected value.
- **credential file permission not 600** — the api-env file does not have
  600 permissions.
- **test record name not disposable** — the planned record name does not
  match the expected disposable pattern.
- **pre-check sees unmanaged existing record** — a record exists at the
  target name that was not created by the test.
- **CNAME conflict exists** — a CNAME record exists at the target name.
- **preview cannot be generated** — the dry-run/preview step fails.
- **owner phrase missing** — the owner has not provided the exact approval
  phrase.
- **post-check cannot run** — the post-check step fails to execute.
- **redaction scan fails** — the output contains forbidden patterns.
- **any raw secret/address/API text would be printed** — the output would
  leak sensitive information.

---

## 11. Redacted output contract

### Allowed output

- status bucket (applied, verified, partial, failed, conflict, uncertain, ready)
- mode (fake_only, dry_run, check_only, live_pending, live_applied)
- safe action category (create, update, noop, conflict, skip)
- safe record type (A, AAAA)
- counts (planned, applied success, applied failed, verified, post-check failed, unknown)
- fake/live honesty statement
- no-delete statement
- post-check result category
- manual rollback reminder

### Forbidden output

- raw domain name
- raw hostname
- raw IP address (IPv4 or IPv6)
- record ID
- zone ID or account ID
- API token or Authorization header
- env file path
- profile file path
- raw API response body
- API endpoint path
- helper stderr/stdout message
- workers.dev URL
- subscription URL
- protocol URI (vless://, trojan://, hysteria2://, tuic://)
- private key or Reality private key
- full sha256-like hex hash
- `apply --yes` or any raw CLI invocation instruction
- raw mutation command

---

## 12. Public UX block

Even if the controlled live test passes, do not expose public beginner apply
yet.

- No `bin/nanobk` integration.
- No Bot apply.
- No Web apply.
- No installer apply.

A separate review is required after the live proof is validated before any
public UX integration is considered.

---

## 13. Remaining future steps

- **v2.2.21** — controlled live test wrapper planning (tentative label).
- **v2.2.22** — controlled live fake-placeholder wrapper (tentative label).
- **v2.2.23** — owner-approved one-record live test (tentative label).
- **later** — public UX only after separate review.

Version numbers are tentative labels and may change.
