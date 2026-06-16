# Production Command Map

All commands in this map are safe to inspect by default. Commands marked dangerous require their own dry-run first and controlled confirmation before any real execution.

## Beginner Commands

| Command | Purpose | Default mutation | Dangerous | Next command | Notes |
|---|---|---|---|---|---|
| `nanobk beginner production` | Open the guided production flow | no | no | shown by guide | Main beginner entrypoint |
| `nanobk beginner production --json` | Guided production flow JSON | no | no | shown by JSON | Same schema as setup production guide |
| `nanobk beginner production guide` | Open the guided production flow | no | no | shown by guide | Human-readable guidance |
| `nanobk beginner production review` | Production owner review | no | no | `nanobk beginner production next` | Read-only readiness report |
| `nanobk beginner production status` | Current production progress | no | no | `nanobk beginner production next` | Read-only status view |
| `nanobk beginner production next` | Show the next recommended step | no | no | command shown by output | Does not execute the step |
| `nanobk beginner production dns apply --dry-run` | Preview DNS record creation | no | yes | controlled DNS apply command | Real DNS creation requires exact confirmation |
| `nanobk beginner production worker deploy --dry-run` | Preview subscription Worker deployment | no | yes | controlled Worker deploy command | Real deploy requires exact confirmation and guard |
| `nanobk beginner production cert issue --dry-run` | Preview HTTPS certificate request | no | yes | controlled cert issue command | Real issue requires exact confirmation and guard |
| `nanobk beginner production vps install --dry-run` | Preview VPS four-protocol install | no | yes | controlled VPS install command | Real install requires exact confirmation and guard |
| `nanobk beginner production subscription publish --dry-run` | Preview subscription profile publish | no | yes | controlled subscription publish command | Real publish requires exact confirmation and guard |

## Advanced Setup Commands

| Command | Purpose | Default mutation | Dangerous | Next command | Notes |
|---|---|---|---|---|---|
| `nanobk setup production` | Open the guided production flow | no | no | shown by guide | Read-only one-command setup spine |
| `nanobk setup production --json` | Guided production flow JSON | no | no | shown by JSON | Same guided-flow schema as beginner production |
| `nanobk setup production guide` | Open the guided production flow | no | no | shown by guide | Supports step and auto dry-run modes |
| `nanobk setup production guide --auto-dry-run` | Run the current stage dry-run only | no | no | shown by guide | Calls only read-only dry-run wrappers |
| `nanobk setup production review` | Production owner review | no | no | `nanobk setup production next` | Keeps release blockers visible |
| `nanobk setup production status` | Current production progress | no | no | `nanobk setup production next` | Read-only status alias |
| `nanobk setup production next` | Show next recommended step | no | no | command shown by output | Does not execute the step |
| `nanobk setup production dns apply --dry-run` | Preview DNS record creation | no | yes | controlled DNS apply command | Real DNS creation requires exact confirmation |
| `nanobk setup production worker deploy --dry-run` | Preview subscription Worker deployment | no | yes | controlled Worker deploy command | Real deploy requires exact confirmation and guard |
| `nanobk setup production cert issue --dry-run` | Preview HTTPS certificate request | no | yes | controlled cert issue command | Real issue requires exact confirmation and guard |
| `nanobk setup production vps install --dry-run` | Preview VPS four-protocol install | no | yes | controlled VPS install command | Real install requires exact confirmation and guard |
| `nanobk setup production subscription publish --dry-run` | Preview subscription profile publish | no | yes | controlled subscription publish command | Real publish requires exact confirmation and guard |

## Safety Notes

- The guide and review commands never run DNS, Worker, certificate, VPS, subscription publish, token rotation, protocol key rotation, or service restart/reload actions.
- Dangerous commands must be run as dry-runs first.
- Real operations stay behind exact confirmation phrases and environment guards.
- Raw secrets, raw profile contents, provider identifiers, and provider responses must not be printed.
