# NanoBK v1.8 CLI and Operation Log Checkpoint

## 1. Purpose

This checkpoint summarizes the accepted v1.8 CLI UI, operation-log, test speed, and status mock/oplog work.

It does not add new behavior.
It does not approve production status wrapper.
It does not approve dirty VPS status.
It does not approve run_cmd/run_critical_step rollout.
It does not start v1.9 yet.

## 2. v1.7 stable baseline

- v1.7.27 is the stable Full Wizard Productization Final baseline.
- Full Wizard stage logic remains protected.
- strict numbered menus remain protected.
- Summary honesty remains protected.
- VPS protocol templates remain protected.
- Cloudflare Worker core remains protected.
- rotate sync remains protected.
- Bot/Web business logic remains protected.
- v1.8 builds UI/operation-log groundwork on top of v1.7.27.

## 3. v1.8 CLI UI accepted work

v1.8.0–v1.8.19 accepted CLI UI work:

- brand banner.
- stage cards.
- compact mode.
- Plain mode.
- UI=0 mode.
- CI/non-TTY mode.
- dry-run layout.
- token safety copy.
- recovery block copy.
- visual guide.
- visual comparison guide.
- static UI checkpoint.

Current verdict:

PASS FOR STATIC CLI UI PRODUCTIZATION

Status:

- Default mode is product-like.
- Compact mode is suitable for small SSH screens.
- Plain mode is log/CI friendly.
- UI=0 is legacy minimal.
- dry-run honesty preserved.
- no fake success.
- no secret leakage.

## 4. v1.8 Operation-log accepted work

v1.8.20–v1.8.31 accepted operation-log work:

- operation-log library pilot.
- redaction.
- hidden output.
- verbose redacted output.
- chmod 600 logs.
- PLAIN/UI=0/CI no ANSI.
- failure propagation.
- test-mode pilot.
- safe test wrapper.
- harmless real command pilot: bin/nanobk --version.
- harmless real command pilot: bin/nanobk --help.
- operation-log checkpoint.

Current verdict:

PASS FOR LOW-RISK OPERATION-LOG GROUNDWORK

Status:

- hidden output works.
- verbose redacted output works.
- failure propagation works.
- harmless real commands are proven.
- full run_cmd/run_critical_step rollout remains unapproved.

## 5. v1.8 Test speed accepted work

v1.8.32–v1.8.33 accepted speed work:

- focused fast tests.
- no-trigger fast tests.
- Tier 0 / Tier 1 / Tier 2 / Tier 3 strategy.
- full suite not required every cycle.
- skipped full suite must be reported honestly.

Current verdict:

PASS FOR FOCUSED TEST SPEED STRATEGY

## 6. v1.8 Status mock/oplog accepted work

v1.8.34–v1.8.43 accepted status work:

- status JSON planning.
- sanitized fixture.
- fixture test polish.
- mock filesystem root design.
- feasibility gate.
- hook planning.
- NANOBK_STATUS_TEST_ADMIN_ENV_PATH hook.
- mock-root status operation-log prototype.
- command path polish.
- status mock oplog checkpoint.

Current verdict:

PASS FOR MOCK FILESYSTEM STATUS OPLOG PROTOTYPE

Status:

- mock status code path can be captured.
- default output can hide JSON.
- verbose output can show sanitized JSON.
- log JSON valid.
- PLAIN/UI=0/CI no ANSI.
- systemctl shim proof.
- failure propagation.
- full log avoids real HOME/repo path.
- dirty VPS status remains unapproved.
- production status wrapper remains unapproved.
- NANOBK_OPLOG_STATUS_PILOT remains unadded.

## 7. Current v1.8 overall status

v1.8 status:

PASS FOR CLI UI + OPERATION-LOG GROUNDWORK

v1.8 has delivered:

- better product CLI.
- safer display modes.
- clearer beginner UX.
- focused tests.
- operation-log groundwork.
- mock status logging proof.

v1.8 has NOT delivered:

- production status wrapper.
- full run_cmd/run_critical_step log hiding.
- real deploy output hiding.
- dirty VPS status wrapping.
- Bot polish.
- Web Panel polish.

## 8. What remains forbidden

- Do NOT add NANOBK_OPLOG_STATUS_PILOT yet.
- Do NOT wrap dirty VPS status.
- Do NOT full-rollout run_cmd.
- Do NOT full-rollout run_critical_step.
- Do NOT wrap VPS deploy output.
- Do NOT wrap Cloudflare deploy output.
- Do NOT wrap rotate sync output.
- Do NOT wrap real healthcheck.
- Do NOT wrap real cf verify.
- Do NOT wrap Bot/Web operations.
- Do NOT read real env.
- Do NOT expose raw status JSON.
- Do NOT tag without explicit approval.

## 9. Recommended next direction

Recommended next direction:

v1.8.45 — v1.8 Closeout Decision

Goal:

- decide whether to stop v1.8 at CLI/operation-log groundwork.
- decide whether v1.9 should begin Bot/Web polish.
- decide whether any final visual/manual review is needed.
- no new code behavior.

Alternative options:

Option A — v1.8.45 Closeout Decision (recommended).
Option B — Status Pilot Gate Planning.
Option C — Manual Visual Revalidation.
Option D — Start v1.9 Bot/Web Roadmap.

Recommended: Option A.

## 10. v1.9 outlook

v1.9 should likely focus on control-plane productization:

- Telegram Bot UX polish.
- Web Panel UX polish.
- status/dashboard clarity.
- safe command execution through nanobk CLI.
- no direct config/systemd/secret writes from Bot/Web.
- preserve v1.7 deployment logic.
- preserve v1.8 display/logging safety.
- continue strict secret redaction.
- no raw env cat.
- no real token/IP/subscription URL leakage.

## 11. Still not a tag

This checkpoint is not a release tag recommendation.

Tagging requires explicit approval and likely a broader manual review.

## 12. v1.8.45 Closeout Decision

v1.8.45 records closeout decision.

- recommends stopping v1.8 feature development after v1.8.45.
- no release tag approval.
- next recommended line is v1.9 Bot/Web control-plane productization planning.
