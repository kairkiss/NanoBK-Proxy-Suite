# v2.2.18 — DNS Apply Post-check Contract and Failure Policy

## 1. Scope

v2.2.18 is docs/mock-only.

- No real Cloudflare calls.
- No real DNS mutation.
- No public CLI integration.
- No Bot apply.
- No Web apply.
- No installer apply.
- No helper invocation.
- No subprocess execution.

This document defines the post-check contract and failure policy that must be
implemented before any controlled live test (v2.2.20 or later).

---

## 2. Why post-check exists

API success is not enough.

A Cloudflare API response saying `success: true` for a POST or PATCH only means
the API accepted the request. It does not prove the record is visible in DNS,
that TTL has propagated, or that the record content matches the intended value.

The beginner-safe DNS Apply Summary must distinguish between the following states:

- **applied** — mutations returned success, but post-check has not verified live state.
- **verified** — all intended records exist in DNS, content matches expected, proxied is false (DNS-only).
- **partial** — some intended records are verified, some failed or are missing.
- **failed** — all attempted mutations failed, or post-check observes missing/wrong records for all intended changes.
- **conflict** — pre-check conflict exists; no mutation should have happened.
- **uncertain** — helper returned ambiguous state, post-check unavailable, or safety cannot be proven.
- **ready** — dry-run or check-only plan exists; no mutation occurred.

Fake transport success must not be described as live verification.

Raw helper messages and raw API responses must not be shown in beginner output.

---

## 3. Post-check input model

Future internal input shape for post-check classification.

```
DnsApplyPostcheckInput:
  planned_records:
    - record_type: A | AAAA
      action: create | update | noop | conflict | skip
      target_class: ipv4 | ipv6 | unknown

  apply_results:
    - record_type: A | AAAA
      action: create | update | noop | skipped
      success: true | false | unknown

  observed_records:
    - record_type: A | AAAA
      exists: true | false | unknown
      content_matches_expected: true | false | unknown
      proxied_is_dns_only: true | false | unknown

  mode:
    fake_only | dry_run | check_only | live_pending | live_applied
```

### Forbidden in model

The following must never appear in the post-check input model or output:

- raw domain name
- raw hostname
- raw IP address (IPv4 or IPv6)
- record ID
- zone ID
- account ID
- API token
- Authorization header
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

---

## 4. Status mapping

### 4.1 Status definitions

**conflict**: Pre-check detected a conflict (CNAME collision, unmanaged record,
proxied record, multiple records). No mutation should have happened.

**failed**: All attempted mutations failed, or post-check observes missing or
wrong records for all intended changes.

**partial**: Some intended records are verified as correct, but some failed,
are missing, or are unknown.

**applied**: Mutations returned success from the API, but post-check has not
verified the live DNS state. This is the default after successful fake-only or
live-pre-check execution.

**verified**: All intended records exist in DNS, content matches expected value,
and proxied is false (DNS-only). This status requires a real post-check against
live Cloudflare DNS.

**ready**: A dry-run or check-only plan exists. No mutation occurred.

**uncertain**: Helper returned an ambiguous state, post-check is unavailable,
or safety cannot be proven from available data.

### 4.2 Critical semantic rules

- **verified must require post-check.** A status of `verified` is only valid
  when live DNS records have been queried and confirmed to match the plan.
- **applied must not mean verified.** API success alone does not prove DNS
  state. The Summary must not imply verification when only API success was
  observed.
- **fake_only must never claim live verified.** Fake transport success is
  simulated; it does not touch real Cloudflare and must not be described as
  live verification.

---

## 5. Stop-on-first-failure policy

### Default policy

The default future live apply behavior should be to stop on first mutation failure.

If record A succeeds but record AAAA fails, the apply should stop. The
beginner-safe Summary should report the partial state clearly and recommend
manual review.

### Rationale

Beginners are safest when they see a clear, honest status. Continuing after
a failure and reporting "partial success" can be confusing if the user does
not understand which records succeeded and which failed. Stopping early
limits blast radius and makes recovery simpler.

### Future exception

Continue-and-report-partial may only be allowed after:

1. Fake tests prove the partial Summary is safe and clear.
2. The partial Summary explicitly lists what succeeded and what failed
   (in safe, non-raw terms).
3. The recovery guidance is tested and verified to be unambiguous.

This exception should not be implemented before the controlled live test gate.

---

## 6. Post-check requirements

A future live post-check must verify each planned record independently:

1. **Record exists**: Query Cloudflare DNS for the record type and name.
2. **Record type matches**: The returned record type must match the planned type (A or AAAA).
3. **Content matches expected**: The record content (IP address) must match the planned content.
4. **Proxied is false**: The record must have `proxied: false` (DNS-only mode).
5. **no CNAME conflict**: Verify no CNAME record exists at the same name.
6. **No unexpected delete**: The post-check must not delete any records.
7. **Record count matches**: The number of observed records for each type/name
   must match the planned safe subset (typically 1 A and/or 1 AAAA).
8. **A and AAAA independently verified**: Each record type is verified
   independently. A failure in AAAA verification does not invalidate a
   successful A verification, but the overall status reflects the worst case.

---

## 7. Safe beginner output contract

### Allowed output fields

The beginner-safe Summary may include:

- Status bucket (applied, verified, partial, failed, conflict, uncertain, ready)
- Action counts (Create, Update, No change, Conflict, Failed)
- Record type counts (A, AAAA)
- Verified count (future: number of records confirmed by post-check)
- Failed count (number of records that failed)
- Fake/live honesty statement
- DNS-only statement (proxied: false)
- No-delete statement (no records were deleted)
- Safe recovery tip (see section 8)
- Mode (fake_only, dry_run, check_only, live_pending, live_applied)

### Forbidden output

The beginner-safe Summary must not include:

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

---

## 8. Failure recovery policy

### conflict

Safe recovery text:

> Existing records need manual resolution. Do not retry blindly.

### partial

Safe recovery text:

> Some records could not be verified. Do not retry blindly.
> Review Cloudflare DNS manually.

### failed

Safe recovery text:

> Apply failed. Do not retry blindly.

### uncertain

Safe recovery text:

> The current state could not be determined. Do not retry blindly.
> Review Cloudflare DNS manually.

### post-check unavailable

Safe recovery text:

> Post-check could not verify the final state.
> Review Cloudflare DNS manually.

### Rules

- Do not tell the beginner to blindly retry.
- Do not show `apply --yes` or any raw CLI invocation.
- Suggest manual Cloudflare DNS review only as a safe generic instruction.
- Mention "no DNS records were deleted" if true or known.
- Mention "fake-only" or "no live verification" in fake mode.

---

## 9. What remains before live test

The following gates must pass before any controlled live test:

1. **Mock post-check classifier**: A fake-only module that classifies
   post-check input into the correct status bucket.
2. **Fake transport post-check fixture**: A fixture that simulates
   observed DNS records (matching, mismatching, missing).
3. **Controlled live test plan**: A documented plan for running a single
   controlled live DNS apply against a test domain with explicit rollback.
4. **Owner explicit approval**: The repository owner must explicitly approve
   the controlled live test.
5. **Manual rollback/recovery**: A documented manual rollback procedure
   in case the controlled live test produces unexpected results.
6. **No public UX until live gate passes**: No public CLI, Bot, Web, or
   installer integration of DNS apply until the controlled live test
   passes and is verified safe.

---

## 10. Summary

v2.2.18 establishes the post-check contract and failure policy as a safety gate
before any real Cloudflare interaction. The contract ensures:

- Status semantics are precise and honest.
- `verified` requires post-check proof.
- `applied` does not imply `verified`.
- `fake_only` never claims live verification.
- Beginner output is safe and non-leaky.
- Failure recovery is clear and non-dangerous.
- Stop-on-first-failure is the default.
