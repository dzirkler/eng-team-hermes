# Mount / volume layout

Three tiers, each with a different persistence and mutability contract.
See `docker-compose.yml` for the concrete mount lines this document
explains.

## Tier 1 — read-only, host-versioned, curated

| Host path | Container path | Contents |
|---|---|---|
| `./skills/` | `/home/node/.hermes/skills/curated` (via `config.yaml` `skills.external_dirs`) | 14 skills ported from `D:\code\eng-team-plugin\skills\` |
| `./profiles/` | `/home/node/.hermes/profiles-src` | Worker-profile `profile.yaml` (toolset) + `instructions.md` (persona) per profile |
| `./hooks/` | `/home/node/.hermes/hooks` | `no_merge_guard.js`, `orchestrator_no_edit_guard.js` |
| `./config/config.yaml` | `/home/node/.hermes/config.yaml` | Model, kanban, skills, hooks, dashboard, gateway config |

**Why read-only:** two reasons, not one.

1. **Reproducibility.** Everything here is what `bootstrap.sh` (Tier 0,
   below) provisions from — if it were writable, the running container's
   actual behavior could drift from what's committed to git, and the
   "torn down and recreated" property Damon asked for would stop being
   true (you'd be recreating from a stale snapshot, not the real source).
2. **Guardrail integrity.** The two hook scripts are the mechanical
   enforcement layer (§4 of the migration plan). If they lived somewhere
   the agent could write to, the self-improving skill loop — or a
   sufficiently confused model — could edit its own guardrails. Read-only
   makes that structurally impossible, not just discouraged.

**Change process:** edit on host, `git commit`, restart the container
(`docker compose up -d` picks up mount content changes on restart; it does
not hot-reload while running).

## Tier 2 — writable, host-backed, survives recycle

| Host path | Container path | Contents |
|---|---|---|
| `./state/kanban/` | `/home/node/.hermes/kanban` | SQLite board DB, task workspaces |
| `./state/memory/` | `/home/node/.hermes/memory` | Worker-profile persistent memory / embeddings |
| `./state/learned-skills/` | `/home/node/.hermes/skills/learned` | `skill_manage` output — separate from curated, see promotion workflow below |
| `./state/credentials/` | `/home/node/.hermes/credentials` | Platform integration credentials, if/when gateway is enabled |
| `./state/logs/` | `/home/node/.hermes/logs` | Runtime logs |

**Why writable + host-backed (not a Docker-internal named volume):** host-
backed means Damon can inspect, back up, or `git diff` the learned-skills
directory directly, without going through `docker exec`. Not committed to
git wholesale (see `.gitignore`) — this is runtime state, not authored
content, and a repo that accumulates one instance's task history isn't a
clean "how to build the team" description anymore.

**Persistence contract:** survives `docker compose restart` / `up` / `down`
(without `-v`). Only wiped by `docker compose down -v` — which is exactly
what the Phase-0 teardown/recreate test (task #21) deliberately does, to
prove `bootstrap.sh` can rebuild working state from nothing. Day-to-day
operation should never need `-v`.

### Skill promotion workflow

`skill_manage` (with `write_approval: true`, set for `orchestrator` and
`quality-engineer` in `config.yaml`) writes to `state/learned-skills/`, not
`skills/`. To review: `hermes skills pending` / `hermes skills diff <id>`
inside the container. To promote something worth keeping into the
permanent, versioned baseline: copy the file from
`state/learned-skills/<name>/SKILL.md` into `skills/<name>/SKILL.md` on the
host and commit it. That's the entire mechanism — there is no automatic
promotion, on purpose, so nothing crosses from "agent-authored, unreviewed"
to "curated, shared baseline" without a human copy-and-commit in the
middle.

## Tier 3 — target project source

| Host path | Container path |
|---|---|
| `$PROJECT_REPO_PATH` (from `.env`) | `/workspace/$PROJECT_NAME` |

Read/write bind mount of the actual codebase the team works on. Kanban task
workspaces default to `dir:/workspace/$PROJECT_NAME` (the shared checkout)
but individual tasks should claim `worktree:/workspace/$PROJECT_NAME/.worktrees/<task-id>`
for isolation when multiple tasks run concurrently — `git worktree add`
runs worker-side, scoped to a subdirectory of the same mount, so no
additional host mount is needed per task.

**Why bind-mount instead of a container-managed clone:** live host-side
visibility (your editor, `git log`, `git diff` all see the same tree the
agents are working in) plus no need for the container to hold its own git
credentials for this repo. The tradeoff is weaker isolation than a fully
container-managed clone — accepted deliberately for this single-project
trial; revisit if/when the multi-project topology (migration plan §8)
needs stronger separation between concurrent projects sharing a host.

## Tier 0 — provisioning, not a mount

`bootstrap.sh` isn't a volume at all — it's the script that turns Tiers 1–3
into a running profile + board (creates the Hermes profile, the Kanban
board, registers the 8 worker profiles, wires notification scope). It's
idempotent and takes `<project-name> <repo-path>` as arguments specifically
so a second project is one invocation, not a repeat of manual setup — see
the "parameterize bootstrap for per-project reuse" task.

**Caveat carried over honestly:** the exact `hermes` CLI subcommand names
used in `bootstrap.sh` (`profile create`, `kanban boards create`, `kanban
worker-profile apply`, `kanban notify-subscribe`) are this plan's
best-available reading of the public CLI reference, not yet verified
against a running instance. First real run (task #7, dry run) is where
that gets checked and the script gets corrected if the surface differs.
