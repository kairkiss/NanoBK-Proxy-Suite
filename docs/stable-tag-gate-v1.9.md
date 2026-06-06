# v1.9 Stable Tag Gate

> **Purpose:** Track what is required before a stable v1.9 tag can be created.
> No tag without explicit user approval and all gate items resolved.

---

## 1. Current stable tag status

**No stable tag yet.**

Version display: `1.9.58` (not a release tag).

---

## 2. Completed gate items

| Item | Version | Status |
|------|---------|--------|
| Bot/Web redaction and Raw JSON gating | v1.9.5–v1.9.9 | ✅ Complete |
| Bot safe status summary | v1.9.10 | ✅ Complete |
| Web safe status cards | v1.9.11 | ✅ Complete |
| Raw JSON / advanced diagnostics policy | v1.9.12–v1.9.14 | ✅ Complete |
| Advanced diagnostics mode (Bot/Web) | v1.9.15–v1.9.18 | ✅ Complete |
| Doctor summary (Bot/Web) | v1.9.35–v1.9.38 | ✅ Complete |
| Bot/Web i18n (en/zh, default zh) | v1.9.30–v1.9.32 | ✅ Complete |
| Bot/Web default Chinese | v1.9.48 | ✅ Complete |
| Installer language propagation | v1.9.49 | ✅ Complete |
| Web session language switch | v1.9.51 | ✅ Complete |
| Bot /language guidance | v1.9.52 | ✅ Complete |
| T17 real Chinese/English smoke test | v1.9.53–v1.9.55 | ✅ Passed with polish |
| Installer language test debt fix | v1.9.56 | ✅ Complete |
| Web Chinese copy residue fix | v1.9.57 | ✅ Complete |
| CLI version display fix | v1.9.58 | ✅ Complete |
| AI maintenance interface | v1.9.59 | ✅ Complete |

---

## 3. Remaining gate items

| Item | Target version | Status |
|------|---------------|--------|
| v1.9.60 closeout checkpoint | v1.9.60 | ⏳ Pending |
| Final focused tests | v1.9.60 | ⏳ Pending |
| Final user approval | v1.9.60 | ⏳ Pending |
| Optional final real smoke retest | v1.9.60 | ⏳ Optional (user decides) |

---

## 4. Not required for v1.9 stable

These items are explicitly NOT required before the v1.9 stable tag:

* systemd productization
* Web production runner (Gunicorn/uvicorn)
* Fingerprint redaction policy implementation
* Raw subscription delivery
* Subscription QR delivery
* Repair/restart implementation
* Cloudflare mutating operations in control plane
* Full clean VPS redeployment regression
* UI redesign
* v2.0 features

---

## 5. Stable tag recommendation

**Do not tag in v1.9.59.**

Prepare for v1.9.60 closeout checkpoint. Tag only after:
1. v1.9.60 closeout checkpoint document created
2. Final focused tests pass
3. No P0/P1 issues remain
4. Explicit user approval for tag/release

---

## 6. How to use this document

1. Before creating a stable tag, verify all items in section 2 are ✅.
2. Verify all items in section 3 are ✅ or explicitly waived by user.
3. Create a closeout checkpoint document summarizing final state.
4. Get explicit user approval.
5. Only then create the tag.
