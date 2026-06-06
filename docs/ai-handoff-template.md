# NanoBK Proxy Suite AI Handoff Template

> **Purpose:** Copy-paste this template into a new task prompt for any future AI agent.
> Fill in the blanks. The agent must read `docs/maintenance-map.md` first.

---

## Task name

{vX.Y.Z — Short description}

## Current base commit

Commit: `{full hash}`
Message: `{commit message}`

**Before doing anything, run:**
```
git fetch origin
git status -sb
git rev-parse HEAD
git rev-parse origin/main
git log -1 --format='%H%n%s'
```
If HEAD or origin/main is not `{expected hash}`, stop and report the mismatch.

## Scope

{What this task approves — be specific.}

## Explicit non-goals

{What this task does NOT approve — list explicitly.}

## Protected files

Read `docs/maintenance-map.md` section 3 before making any change.

Do not modify:
* `installer/install.sh` deployment logic (unless task specifically approves)
* `vps/scripts/` protocol templates
* `cloudflare/` Worker core
* `vps/scripts/rotate-keys.sh` rotate sync
* `lib/nanobk_redaction.py` (unless redaction task)
* Bot/Web direct write restrictions
* Env files and secrets

## Files to inspect

* `docs/maintenance-map.md`
* `docs/ai-handoff-template.md` (this file)
* {Additional files relevant to the task}

## Allowed changes

* {List specific files that may be modified}
* Add validation document: `docs/validation-vX.Y.Z-{description}.md`
* Update `CHANGELOG.md`
* Update `docs/roadmap.md`

## Required tests

Consult `docs/maintenance-map.md` section 11 (Standard test matrix by change type).

For this task:
* {List specific tests to run}

## Security rules

**Never:**
* `cat bot/.env`, `cat web/.env`, or any real env file
* Output real tokens, keys, IPs, domains, URLs, subscription paths
* Run real deploy/rotate/status/doctor unless task approves
* Bypass redaction in Bot/Web output

**Always:**
* Run `git diff --cached --name-only | xargs grep -nE 'TOKEN=|SECRET=|PRIVATE_KEY=|...' || true`
* Verify no real secrets in changed files

## Expected final report format

```
1. Branch
2. Commit
3. Files changed
4. install.sh changes (should be none unless approved)
5. Core code changes
6. Tests run
7. Security checks
8. Known limitations
9. git log -1 verification
10. Push status
11. Recommendation for next step
```

## Stop conditions

Stop and report if:
* Base commit does not match expected
* A real secret would be exposed
* A protected file needs modification without task approval
* Tests fail and fix is not obvious
* Scope creep beyond task boundaries

## User approval requirements

* Tag/release: NEVER without explicit user approval
* Protected file changes: only if task specifically approves
* Real deploy/rotate: only if task specifically approves

## Secret-handling reminder

Env files contain real tokens and keys. Never:
* Read them with `cat`, `source`, or similar
* Output their contents
* Commit them
* Paste them into chat

## Stable tag reminder

Stable tag requires:
* All gate items resolved (see `docs/stable-tag-gate-v1.9.md`)
* Closeout checkpoint passed
* Final focused tests pass
* No P0/P1 issues
* Explicit user approval
