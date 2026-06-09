# v2.2.13 — Fake-only DNS Apply Helper Boundary Design

## 1. Purpose

This document defines the safety boundary for a future hidden/test-only
fake-only DNS Apply helper invocation prototype. It documents the low-level
helper transport risk, raw output risk, strict fake transport preflight,
sterile subprocess isolation, captured stdout/stderr, strict JSON allowlist,
failure contract, and forbidden output fields.

This is a design document. It does not implement anything. No helper
invocation. No fake-helper prototype. No real DNS mutation.

---

## 2. Baseline

**v2.2.12 closeout accepted** the fake wrapper line as hidden/test-only,
pure simulated, fake-transport-only UX validation layer.

**Current fake wrapper** (`lib/nanobk_cf_dns_apply_ux_mock.py`) is
closeout-ready only as a simulated UX validation layer. It renders
fixture-style output programmatically and does not call the low-level
`lib/nanobk_cf_dns_apply.py` helper.

**This does not approve** real DNS mutation or public console integration.

---

## 3. Current Low-level Helper Transport Boundary

The low-level helper (`lib/nanobk_cf_dns_apply.py`) selects transport as
follows:

```
fake_path = os.environ.get("NANOBK_CF_DNS_FAKE_TRANSPORT")
if fake_path:
    return _make_fake_transport(fake_path)
return _real_transport
```

**Key facts:**

- Missing or empty `NANOBK_CF_DNS_FAKE_TRANSPORT` falls back to real
  Cloudflare transport.
- Malformed/nonexistent fake fixture fails in the helper path but must
  still be captured by any wrapper.
- `--dry-run` avoids API calls, but the helper can still construct/select
  transport.
- `--check` performs GET-only calls.
- `--yes` permits POST/PATCH create/update.
- DELETE is not implemented.
- `--force` is rejected.

**Critical risk:** If a wrapper calls the helper without validating the
fake transport env var first, the helper will silently fall back to real
Cloudflare transport.

---

## 4. Current Low-level Helper Output Risk

**Text output can expose raw:**

- Record type (A, AAAA)
- Record name (e.g., `proxy.example.com`)
- Planned content (e.g., `203.0.113.10`)
- Existing content in messages
- Conflict details
- Mutation result name

**JSON output can expose raw:**

- `name`
- `plannedContent`
- `existingContent`
- `recordId`
- Helper messages

**Current helper is not beginner-safe**, not a redaction wrapper, and has
no post-check contract.

---

## 5. Current Fake UX Wrapper Boundary

The current fake wrapper (`lib/nanobk_cf_dns_apply_ux_mock.py`):

- Requires `NANOBK_CF_DNS_FAKE_TRANSPORT` and validates it.
- Renders fixture-style output programmatically.
- Does NOT call `lib/nanobk_cf_dns_apply.py`.
- Is NOT referenced by `bin/nanobk`.
- Has no network imports.
- Keeps output masked/redacted.

This is the safe starting point for any future helper invocation design.

---

## 6. Design Decision

**v2.2.13 is docs-only.**

Do not implement helper invocation yet.

Future helper invocation, if approved later, must be fake-only,
hidden/test-only, and never public beginner UX.

---

## 7. Approved Boundary for Future Fake-only Helper Invocation

For a future fake-only helper prototype, the following requirements are
approved as design targets:

1. Fake transport validated before helper import/call.
2. Missing fake env fails closed.
3. Empty fake env fails closed.
4. Nonexistent/directory/malformed/empty fake fixture fails closed.
5. Sterile environment for subprocess/helper invocation.
6. Use fake profile/api-env fixtures only.
7. No production paths.
8. No real env files.
9. No shell invocation.
10. Timeout required.
11. Helper stdout/stderr captured.
12. Helper text output discarded.
13. Helper stderr treated as failure unless explicitly sanitized/allowlisted.
14. Helper JSON parsed through strict allowlist only.
15. Any unexpected JSON key fails closed.
16. Any JSON parse failure fails closed.
17. Any nonzero unexpected exit fails closed.
18. Traceback-like output fails closed.
19. Fake transport usage must be proven with sentinel/fake calls artifact.
20. No public `bin/nanobk` integration.
21. No Bot/Web/installer integration.
22. No real DNS mutation.
23. No real Cloudflare call.

---

## 8. Explicitly Rejected Paths

The following paths are explicitly rejected:

- Real Cloudflare mutation.
- Public `bin/nanobk` integration.
- Beginner console apply button.
- Bot/Web apply button.
- Installer silent apply.
- In-process helper import as first prototype, unless helper is refactored
  into safe pure functions.
- Printing helper stdout/stderr.
- Forwarding helper messages verbatim.
- Redacting raw output after printing.

---

## 9. Fake Transport Preflight Requirements

Before any helper call, the wrapper must validate:

1. `NANOBK_CF_DNS_FAKE_TRANSPORT` is set and non-empty.
2. Path exists.
3. Path is a regular file (not a directory).
4. Path content is valid JSON.
5. JSON top-level structure is expected (dict, not list/string/number).

**Failure at any step:** fail closed, no helper call, safe error message.

**Safe error message style:**

```
NanoBK DNS Apply helper boundary: fake transport validation failed.
No DNS changes were made.
```

Do not print the actual fake transport path. Do not print JSON content.
Do not print env values.

---

## 10. Runtime Isolation Requirements

Future helper invocation must use sterile runtime isolation:

- No shell invocation (`shell=False` if subprocess).
- Clean environment: only required env vars passed.
- `NANOBK_CF_DNS_FAKE_TRANSPORT` must be set.
- No parent env leakage.
- Timeout required (e.g., 30 seconds).
- Capture both stdout and stderr.
- Discard text output (not forwarded to user).
- Parse only JSON output through strict allowlist.

---

## 11. Helper Output Capture Rules

- Helper stdout is captured, not printed.
- Helper stderr is captured, not printed.
- Helper text output is discarded.
- Only structured JSON output is parsed.
- JSON parsing uses strict allowlist (see section 12).
- Any parse failure fails closed.
- Any unexpected output format fails closed.

---

## 12. Strict JSON Allowlist Contract

After parsing helper JSON output, only these internal categories are
allowed to be extracted:

| Category | Allowed values |
|----------|---------------|
| Action counts | create_count, update_count, noop_count, conflict_count, failed_count |
| Record type buckets | A, AAAA |
| Action buckets | create, update, nochange, conflict, failed |
| Status bucket | ready, applied, uncertain, partial, conflict, failed |
| Safe booleans | proxied_false_verified, ownership_marker_verified (fake mode only) |

**Any unexpected JSON key fails closed.**

---

## 13. Forbidden Output Fields

The following fields must never be forwarded to beginner output:

- `name`
- `plannedContent`
- `existingContent`
- `recordId`
- `message`
- `zoneId`
- `accountId`
- API request body
- API response body
- Endpoint URL
- Headers
- Token
- Env path
- Env content
- Raw domain
- Raw hostname
- Raw IP

---

## 14. Beginner-safe UX Mapping

Output may include only:

- Masked placeholders (e.g., `ex***e.com`, `203.0.113.xxx`)
- Counts (create/update/noop/conflict/failed)
- A/AAAA buckets
- Status bucket (applied/uncertain/partial/conflict/failed)
- Confirmation wording
- Fake/test-only notice
- Safe recovery guidance

**No raw value.**

---

## 15. Post-check Policy

- Real post-check is NOT part of this design implementation.
- Fake-only prototype may simulate post-check only.
- Simulated post-check must say "not live Cloudflare verification".
- Real post-check requires separate design before real mutation.

---

## 16. Failure Contract

Every unsafe condition must fail closed with:

- No mutation.
- No raw output.
- No raw helper output.
- Safe generic message.
- Nonzero exit if executable.
- Explicit "not reported as success."

---

## 17. In-process vs Subprocess Decision

**Future first prototype should prefer no-shell subprocess isolation with
sterile env and captured stdout/stderr, not in-process import.**

**Reason:**

- In-process import risks side effects and internal `print`/`sys.exit`
  behavior.
- Subprocess allows total output capture.
- Subprocess is still dangerous unless fake env is validated before
  invocation.

**Also state:** No helper call remains the safest current state.

---

## 18. Test Strategy for Future Prototype

If a future prototype is approved, tests must assert:

| Assertion | Description |
|-----------|-------------|
| Fake transport required | Wrapper fails closed without env var |
| Missing fake transport | Safe error, no crash |
| Empty fake transport | Safe error, no crash |
| Nonexistent path | Safe error, no crash |
| Directory path | Safe error, no crash |
| Malformed JSON | Safe error, no crash |
| Empty file | Safe error, no crash |
| Valid fixture | Allows helper call |
| Real transport impossible | No real HTTP calls under any condition |
| No `--yes` in beginner copy | Not exposed |
| Masked domain/hostname/IP | No raw values in output |
| Numbered menu + typed phrase | Confirmation gate exists |
| Post-check success | Simulated, says fake only |
| Post-check failure | Uncertain, not success |
| Partial failure | Partial, not success |
| No raw token/env/API body/response | Redaction enforced |
| No raw record ID | Redacted in output |
| No Bot/Web invocation | Not exposed |
| No public console apply button | Not in beginner menu |
| No Cloudflare call | Never called |

---

## 19. Fixture Wording Drift

**Current status:**

- v2.2.11-polish fixed the runtime wrapper success output to say
  "Simulated DNS create/update flow completed under fake transport" instead
  of "Cloudflare was called for DNS create/update only".
- The v2.2.8 fixture file `tests/fixtures/v2.2.8/dns-apply-postcheck-success.txt`
  still contains the old wording: "Cloudflare was called for DNS create/update only."

**Impact:**

- This is NOT a runtime blocker because the closeout wrapper output is safe.
- The fixture is a documentation/test contract, not runtime output.
- Before any future helper invocation prototype, the v2.2.8 fixture wording
  should be polished or explicitly superseded to avoid documentation/test
  drift.

**Do not edit the fixture in this task.** Just document the drift.

---

## 20. Product Boundary

**No public `bin/nanobk` integration.**

- The wrapper is not imported by `bin/nanobk`.
- The wrapper is not exposed as a CLI command.

**No beginner console apply button.**

- The console does not surface a DNS apply action.
- `apply --yes` is not exposed in beginner copy.

**No Bot/Web apply button.**

- Bot and Web do not reference the wrapper.
- Bot and Web do not invoke DNS apply mutation.

**No installer silent apply.**

- The installer does not run DNS apply.
- The Full Wizard does not silently run DNS apply.

**Advanced/manual `cf dns apply --yes` remains outside beginner UX.**

**Future prototype, if implemented, is hidden/test-only direct test path.**

---

## 21. Real Application Status

**DNS apply UX has not entered real beginner application.**

Real Cloudflare mutation is not exposed by the fake wrapper or this design.

No real DNS records are created, updated, or deleted.

---

## 22. Remaining Gates Before Real DNS Apply

| Gate | Description |
|------|-------------|
| Executable beginner renderer | Renders masked summary, confirmation, post-check, partial failure |
| Real redaction wrapper | Masks domain, hostname, IP, record ID in all apply output |
| No raw helper output | Low-level helper must not expose raw values in any mode |
| Strict helper JSON allowlist | Only safe fields extracted from helper output |
| Post-check contract | GET-only verification after mutation, honest state taxonomy |
| Conflict UX | Guided resolution for unowned/multiple/CNAME/proxied conflicts |
| Stop-on-first-failure policy | Safer default for beginner UX |
| Confirmation gate | Numbered menu + typed phrase |
| Fake-helper prototype proof | Hidden/test-only helper invocation proven safe |
| Hidden test-only path | If needed, test-only entrypoint for integration testing |
| Controlled live test approval | Explicit approval for real Cloudflare API calls |
| Owner explicit approval | Final approval before real mutation enters product |

---

## 23. Risk Map

**High risk:**

| Risk | Description |
|------|-------------|
| Real Cloudflare mutation before post-check/redaction | Could create records without verification |
| Public `bin/nanobk` entrypoint too early | Could expose mutation to users before UX is ready |
| Low-level helper raw output leaking | Could expose raw domain/IP/record ID in beginner output |
| Fake post-check mistaken for live verification | Users could think records are verified when they aren't |
| `--yes` exposed as beginner path | Single flag insufficient for product UX |

**Medium risk:**

| Risk | Description |
|------|-------------|
| In-process helper import side effects | `print`/`sys.exit` in helper could break wrapper |
| Helper output capture incomplete | Stderr/traceback could leak to user |
| Fake transport drift from real apply | Fake behavior diverges from real apply behavior |
| Fixture wording drift | v2.2.8 fixture still has live-call-like wording |

**Low risk:**

| Risk | Description |
|------|-------------|
| Pure simulated wrapper now hardened | Fake transport validation, wrapper isolation, redaction |
| No network imports | Cannot call Cloudflare even by accident |
| No public entrypoint | Cannot be invoked by users |
| Tests cover main boundaries | 150+ assertions across 3 test files |

---

## 24. Explicit Non-goals

v2.2.13 does **not**:

- Implement helper invocation.
- Implement fake-helper prototype.
- Implement public CLI integration.
- Implement hidden `bin/nanobk` entrypoint.
- Implement beginner console apply button.
- Implement Bot/Web apply button.
- Implement real DNS mutation.
- Implement real Cloudflare mutation.
- Implement DNS-01.
- Implement Tunnel/Access.
- Implement real `/etc` writes.
- Implement real rollback.
- Modify any runtime or test files.
- Create a release tag.

---

## 25. Acceptance Criteria

This document is accepted when:

1. All 26 sections are present and complete.
2. Current helper transport boundary is documented.
3. Current helper output risk is documented.
4. Design decision is explicit: docs-only, no implementation.
5. Approved boundary for future fake-only helper invocation is comprehensive.
6. Explicitly rejected paths are listed.
7. Fake transport preflight requirements are strict.
8. Runtime isolation requirements are sterile.
9. Helper output capture rules are complete.
10. Strict JSON allowlist contract is defined.
11. Forbidden output fields are listed.
12. Beginner-safe UX mapping is defined.
13. Post-check policy is honest.
14. Failure contract is fail-closed.
15. In-process vs subprocess decision is documented.
16. Test strategy is defined.
17. Fixture wording drift is documented.
18. Product boundary is clear.
19. Real application status is honest.
20. Remaining gates are listed.
21. Risk map covers high/medium/low.
22. Non-goals are explicit.
23. No runtime code is changed.
24. No secrets or protocol links are printed.

---

## 26. Next Gate Recommendation

**v2.2.14-polish — Fix v2.2.8 DNS Apply Fixture Live-call Wording Drift**

The v2.2.8 fixture `tests/fixtures/v2.2.8/dns-apply-postcheck-success.txt`
still contains "Cloudflare was called for DNS create/update only." This
should be fixed to match the v2.2.11-polish wrapper wording before any
future helper invocation prototype.

This is the safer next step: fix the documentation/test drift before
building the prototype.
