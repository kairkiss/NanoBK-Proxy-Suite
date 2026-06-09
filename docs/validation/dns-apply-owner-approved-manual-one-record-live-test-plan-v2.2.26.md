# NanoBK DNS Apply — Owner-Approved Manual One-Record Live Test Plan v2.2.26

v2.2.26 is docs-only.
This document does not permit live mutation.
This document does not implement a live wrapper.
This document does not call Cloudflare.
This document does not read real env files.
This document does not expose public CLI, Bot, Web, or installer apply.
Actual live mutation remains blocked.

---

## 1. Scope and non-goals

**Scope:** Define the complete owner-approved manual one-record live test
plan for a future controlled Cloudflare DNS live test. This document
specifies the human gates, credential handling, pre-check, preview,
approval, post-check, redacted evidence, rollback, stop conditions,
success/failure criteria, and public UX block.

**Non-goals:**

- No implementation of live wrapper or live mutation in this version.
- No public UX integration (CLI, Bot, Web, installer).
- No DNS-01, Tunnel/Access, or certificate changes.
- No release or tag.
- No real Cloudflare API calls from this document.
- No real env file reading.
- No raw mutation commands.

---

## 2. Absolute safety boundaries

The following boundaries are absolute and must never be violated:

- No real Cloudflare API calls from this document.
- No real DNS mutation from this document.
- No real env file reading from this document.
- No raw domain, hostname, IP, record ID, zone ID, account ID, token,
  or API response in AI chat/report.
- No raw mutation commands in this document.
- No public CLI/Bot/Web/installer integration.
- No tag or release.
- Actual live mutation remains blocked until a future owner-approved phase.

---

## 3. Required owner-only placeholders and categories

The following placeholders must be filled in by the owner before any
live test can proceed. They are safe categories only — real values must
never be printed in reports, pasted to AI, or stored in logs.

- `SAFE_ZONE_CATEGORY` — e.g. "owner-controlled disposable test zone"
- `SAFE_TEST_RECORD_CATEGORY` — e.g. "disposable test subdomain"
- `SAFE_RECORD_TYPE` — "A" or "AAAA"
- `SAFE_EXPECTED_CONTENT_CATEGORY` — e.g. "test IPv4 address" or "test IPv6 address"
- `SAFE_CREDENTIAL_FILE_REFERENCE` — local path reference only, never printed
- `SAFE_LOCAL_RUN_CONTEXT` — e.g. "owner local machine, owner-controlled VPS"
- `SAFE_ROLLBACK_CATEGORY` — e.g. "manual dashboard deletion of test record"
- `OWNER_APPROVAL_PHRASE` — exact phrase defined in section 10

These are placeholders only.
Real values must never be printed in reports.
Real env file content must never be pasted to AI.
Real tokens must never be pasted to AI.

---

## 4. Three-layer separation model

The test plan uses a three-layer separation model:

1. **Human owner local preparation** — the owner prepares credentials,
   zones, records, and context locally. Real values stay local.
2. **Future non-public controlled command execution** — a future non-public
   command may use real local values only after all gates pass. This command
   does not exist in v2.2.26.
3. **AI review layer** — AI receives only safe categories and redacted
   summaries. AI never receives real token/domain/IP/record IDs/env
   paths/API bodies.

Required rule:
The owner keeps real values local.
The future command may use real local values only after all gates pass.
AI receives only safe categories and redacted summaries.

---

## 5. Owner-only local preparation

The owner must complete the following locally before any future execution:

- Identify the safe zone category.
- Identify the safe test record category.
- Identify the safe record type (A or AAAA).
- Identify the safe expected content category.
- Prepare the credential file locally.
- Verify credential file permissions.
- Verify the zone is owner-controlled and disposable.
- Verify the test record is disposable and not in production.
- Verify no same-name CNAME conflict exists.
- Verify the test record is absent or managed-test-only.
- Prepare rollback instructions.

All of this happens locally. No real values are shared with AI.

---

## 6. Credential file handling

- Credential file reference is provided locally only.
- Credential file contents must never be pasted.
- Credential file path must not be printed in AI chat/report.
- Credential file permission must be restricted, preferably `chmod 600`.
- No `cat`/`source`/`eval` of env files.
- No token echo.
- No raw API output in final user-facing output.
- Helper stdout/stderr must be captured internally in future phases.
- Redaction must happen before output.

---

## 7. One-record identity policy

- Exactly one record.
- Disposable test record category only.
- Owner-controlled safe zone category only.
- Create-only-first.
- DNS-only / proxied false.
- No delete.
- No overwrite.
- No production names.
- No service hostnames.
- Same-name CNAME must be absent.
- Existing unmanaged record means stop.

---

## 8. Pre-check checklist

Before any future execution:

- [ ] repo clean
- [ ] expected HEAD
- [ ] public integration absent
- [ ] credential reference present
- [ ] credential permission restricted
- [ ] safe zone category
- [ ] safe test record category
- [ ] safe record type
- [ ] safe expected content category
- [ ] same-name CNAME absent
- [ ] record absent or managed-test-only
- [ ] no delete planned
- [ ] no overwrite planned
- [ ] safe preview available

---

## 9. Safe preview checklist

Before approval:

- [ ] safe summary only
- [ ] one-record action only
- [ ] create-only-first
- [ ] DNS-only / proxied false
- [ ] no raw mutation command
- [ ] no raw domain/IP/token/record ID/zone ID/account ID
- [ ] rollback instructions shown before approval
- [ ] post-check criteria shown before approval

---

## 10. Owner approval phrase and timing

The exact approval phrase is:

```
I UNDERSTAND THIS WILL CHANGE CLOUDFLARE DNS FOR A TEST RECORD
```

The phrase is only valid after:

1. owner-only local preparation is complete;
2. credential handling is verified locally;
3. one-record identity policy passes;
4. pre-check passes;
5. safe preview is available;
6. rollback instructions are available;
7. post-check criteria are understood.

The phrase must appear before any future mutation.
The phrase must not be requested by public CLI/Bot/Web/installer.

---

## 11. Manual execution boundary

v2.2.26 does not execute mutation.
This document only defines future owner-approved manual test conditions.
Any future execution must be non-public and owner-approved.
Public CLI/Bot/Web/installer must remain blocked.

---

## 12. Post-check checklist

After any future execution:

- [ ] future non-public action accepted
- [ ] post-check GET observes the record
- [ ] record exists
- [ ] record type matches
- [ ] content matches internally
- [ ] proxied false
- [ ] same-name CNAME absent
- [ ] expected count matches
- [ ] no unexpected delete
- [ ] no unexpected overwrite
- [ ] verified only after post-check
- [ ] redacted output passed
- [ ] manual rollback instruction available

---

## 13. Redacted evidence checklist

Safe evidence categories only:

- `repo_gate_passed`
- `credential_gate_passed`
- `precheck_passed`
- `safe_preview_passed`
- `owner_approval_phrase_matched`
- `future_action_accepted`
- `postcheck_observed`
- `record_type_matched`
- `content_matched_internally`
- `dns_only_confirmed`
- `same_name_cname_absent`
- `redaction_passed`
- `rollback_instruction_available`

No raw values.

---

## 14. Manual rollback checklist

- manual dashboard rollback path described in safe categories.
- owner must perform rollback locally if needed.
- No automatic delete in current plan.
- Rollback unverified means uncertain or manual_pending.
- Blind retry forbidden.
- Rollback evidence must be redacted.

---

## 15. Stop conditions

The test must hard-stop if any of the following conditions are true:

- repo dirty
- unexpected HEAD
- public integration detected
- credential permission not restricted
- credential reference missing
- credential value printed
- real env content displayed
- production zone/category
- non-disposable record category
- same-name CNAME exists
- unmanaged existing record
- planned action includes delete
- planned action includes overwrite
- preview unavailable
- approval phrase missing
- approval phrase mistimed
- raw command displayed
- raw helper output displayed
- post-check unavailable
- post-check mismatch
- redaction failure
- rollback instructions missing
- uncertain state

---

## 16. Success criteria

Success is only possible in a future execution phase, not v2.2.26 itself.

Success requires all of the following:

- repo gate passed
- credential permission gate passed
- pre-check passed
- safe preview passed
- exact owner approval phrase matched
- future non-public action accepted
- post-check GET observes record
- record type matches
- content matches internally
- proxied false
- same-name CNAME absent
- no unexpected delete
- no unexpected overwrite
- redacted summary passed
- manual rollback instruction available
- verified only after post-check

v2.2.26 itself cannot claim verified.

---

## 17. Failure and uncertain criteria

Defined statuses:

- `approval_missing` — approval phrase not provided.
- `approval_mistimed` — approval phrase provided before prerequisites.
- `precheck_failed` — a pre-check condition was not met.
- `preview_failed` — safe preview could not be generated.
- `mutation_failed` — the future action was rejected or timed out.
- `postcheck_failed` — post-check could not verify the record.
- `redaction_failed` — output contained forbidden patterns.
- `rollback_unverified` — rollback could not be verified.
- `manual_pending` — the test requires manual intervention.
- `uncertain` — the state is ambiguous or cannot be determined.

No fake success.
No partial success is reported as verified.
No mutation-only result is reported as verified.

---

## 18. What must never be pasted into AI chat

The following must never be pasted into AI chat or included in reports:

- real zone name
- real domain
- real hostname
- real IP address
- record ID
- zone ID
- account ID
- Cloudflare token
- credential file path
- env file path
- raw API request
- raw API response
- Authorization header
- workers.dev URL
- subscription URL
- protocol URI
- private key
- Reality private key
- raw helper stdout
- raw helper stderr
- raw mutation command

---

## 19. Public UX block

- Public CLI integration: blocked.
- Bot apply: blocked.
- Web apply: blocked.
- Installer apply: blocked.
- Tag/release: blocked.

---

## 20. Not allowed by this version

v2.2.26 does not allow:

- actual live mutation
- real Cloudflare API calls
- real DNS record creation/update/deletion
- real env file reading
- public CLI/Bot/Web/installer integration
- tag or release
- raw mutation commands
- raw helper output

---

## 21. Future transition criteria

Before actual live execution, the following are needed:

- non-public controlled live wrapper
- real credential-reference permission gate
- real pre-check
- real safe preview from helper output
- exact approval prompt
- captured helper output
- controlled Cloudflare mutation
- real post-check
- redacted live summary proof
- manual rollback proof
- owner-provided disposable record details locally
- separate public UX review
