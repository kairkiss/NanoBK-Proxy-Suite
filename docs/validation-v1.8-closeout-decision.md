# NanoBK v1.8 Closeout Decision

## 1. Purpose

This document records the closeout decision for the v1.8 line.

It decides whether v1.8 should stop at CLI UI + operation-log groundwork, whether another final review is needed, and whether v1.9 planning should begin.

It does not add new behavior.
It does not tag a release.
It does not approve production status wrapper.
It does not approve dirty VPS status.
It does not approve run_cmd/run_critical_step rollout.
It does not start v1.9 implementation.

## 2. Current accepted v1.8 status

v1.8.44 accepted status:

PASS FOR CLI UI + OPERATION-LOG GROUNDWORK

Breakdown:

- PASS FOR STATIC CLI UI PRODUCTIZATION.
- PASS FOR LOW-RISK OPERATION-LOG GROUNDWORK.
- PASS FOR FOCUSED TEST SPEED STRATEGY.
- PASS FOR MOCK FILESYSTEM STATUS OPLOG PROTOTYPE.

## 3. Closeout decision

Decision:

CLOSE v1.8 FEATURE DEVELOPMENT AFTER v1.8.45, pending optional final manual review.

Reasoning:

- v1.8 has achieved its intended UI/operation-log groundwork scope.
- continuing status pilot work now has diminishing returns and higher risk.
- production deploy logic remains protected.
- next major product value is Bot/Web control-plane UX, not more CLI status experiments.
- v1.8 should not keep accumulating micro-versions indefinitely.

Feature development closeout recommendation, not release tag approval.

## 4. Optional final manual review

Before any tag or public release decision, optionally run a final manual review:

- default Full Wizard dry-run visual review.
- compact mode dry-run.
- Plain mode dry-run.
- UI=0 dry-run.
- safe grep for secrets.
- Summary honesty.
- no status: success.
- no TOKEN=.
- no SECRET=.
- no ADMIN_TOKEN.
- no real VPS/Cloudflare deploy required.
- no dirty VPS status required.

This manual review is optional for closeout decision, required only before tag/release approval.

## 5. What v1.8 delivered

- product-like CLI default mode.
- compact SSH-friendly mode.
- Plain log/CI mode.
- UI=0 legacy mode.
- stage cards.
- brand identity.
- token safety copy.
- recovery copy.
- visual acceptance docs.
- focused test strategy.
- operation-log redaction.
- hidden output.
- verbose redacted output.
- chmod 600 logs.
- failure propagation.
- harmless real command pilots.
- status mock/oplog proof.
- no fake success.
- secret safety gates.

## 6. What v1.8 intentionally did NOT deliver

- production status wrapper.
- dirty VPS status wrapping.
- NANOBK_OPLOG_STATUS_PILOT.
- full run_cmd rollout.
- full run_critical_step rollout.
- real deploy output hiding.
- real healthcheck wrapping.
- real Cloudflare verify wrapping.
- rotate sync wrapping.
- Bot UX polish.
- Web Panel UX polish.
- v1.9 implementation.
- release tag.

## 7. v1.9 recommendation

Recommended next line:

v1.9 — Bot/Web Control Plane Productization

v1.9 should focus on:

- Telegram Bot UX polish.
- Web Panel UX polish.
- dashboard/status clarity.
- safe action confirmations.
- role of Bot/Web as control plane only.
- Bot/Web must call nanobk CLI.
- Bot/Web must not directly write configs/systemd/secrets.
- token redaction.
- operation-log reuse only where safe.
- no raw env cat.
- no real token/IP/subscription URL leakage.
- preserve v1.7 deployment stability.
- preserve v1.8 display/logging safety.

## 8. v1.9 planning guardrails

v1.9 planning should begin with documents, not code.

First v1.9 step should likely be:

v1.9.0-planning or v1.9.0 scope proposal

but do not tag unless user explicitly approves.

Guardrails:

- no broad Bot/Web rewrite.
- no direct systemd/config/secrets writes.
- no changing deployment core.
- no changing rotate sync.
- no changing Cloudflare Worker core.
- no changing VPS protocol templates.
- no raw secrets in Bot/Web logs.
- preserve strict numbered menus in CLI.
- preserve Summary honesty.

## 9. Closeout result

v1.8 closeout result:

READY TO STOP v1.8 FEATURE DEVELOPMENT AFTER v1.8.45

but:

NOT A RELEASE TAG RECOMMENDATION

Tagging requires explicit user approval and broader manual review.

## 10. Still forbidden

Do NOT tag automatically.
Do NOT add NANOBK_OPLOG_STATUS_PILOT.
Do NOT wrap dirty VPS status.
Do NOT full-rollout run_cmd.
Do NOT full-rollout run_critical_step.
Do NOT wrap deploy/healthcheck/cf verify/rotate/Bot/Web.
Do NOT expose raw env or status JSON.
Do NOT begin v1.9 implementation without explicit approval.
