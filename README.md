# eng-team-hermes

V3 of Damon's multi-persona "engineering team" — orchestrator + 7
specialists running on Nous Research's Hermes Agent, containerized. This
repo is the versioned source of truth for that team: everything needed to
stand it up from nothing lives here.

Companion documents (not in this repo):
- `eng-team-plugin-portability.md` — why a straight port from the V2
  Claude Code plugin (`D:\code\eng-team-plugin`) wasn't viable
- `eng-team-plugin-hermes-migration-plan.md` — the full architecture
  rearchitecture this repo implements (§1–10), including the §9 trial plan
  this repo exists to run

Both live in the "SWE Team v3" project folder.

## What's in here

```
docker-compose.yml     Container definition, all three mount tiers
.env.example            Copy to .env, fill in project name / repo path / API key
bootstrap.sh             Idempotent provisioning: profile, board, worker profiles
config/config.yaml       Model, kanban, skills, hooks, dashboard, MCP config
skills/                  Hand-authored skills ported from D:\code\eng-team-plugin\skills\
speckit/                 Vendored, version-pinned SpecKit speckit-* skills (generated,
                           committed, RO-mounted) — see speckit/README.md
scripts/                 update-speckit-skills.* (regenerate the pinned SpecKit skills)
                           and check-speckit-drift.* (fail on hand-edits)
profiles/                8 worker profiles (orchestrator + 7 specialists):
                           profile.yaml (toolset allow-list) + instructions.md (persona)
hooks/                   Two pre_tool_call guardrail hooks (no_merge_guard,
                           orchestrator_no_edit_guard)
state/                   Writable runtime state (gitignored except .gitkeep) —
                           kanban DB, memory, learned skills, credentials, logs
docs/MOUNTS.md            Why the mount layout looks the way it does
```

See `docs/MOUNTS.md` for the full read-only-vs-writable rationale before
changing anything under `skills/`, `profiles/`, `hooks/`, `config/`, or
`state/` — the short version: Tier 1 (skills/profiles/hooks/config) is
read-only and host-versioned on purpose; Tier 2 (state/) is writable and
survives a container recycle on purpose; don't move things between them
without reading why first.

## Quickstart — first time, one project

```bash
git clone <this repo>   # or you're already in it
cp .env.example .env
# edit .env: set Z_AI_API_KEY at minimum

./bootstrap.sh my-project /absolute/path/to/my-project/repo
```

This builds `.env`, ensures `state/` exists, starts the container, creates
the Hermes profile + Kanban board, registers all 8 worker profiles, and
scopes notifications to the orchestrator's top-level task only.

**Interface:** `docker exec -it <project>-hermes hermes` — a terminal chat
session with the orchestrator. That's the only thing you talk to; per the
single-point-of-contact design, specialist worker profiles cannot notify or
block you directly (see `docs/MOUNTS.md` Tier 1 / the migration plan §3).

**Watching the work:** the dashboard at `http://127.0.0.1:9119` (basic auth —
`HERMES_DASHBOARD_USERNAME` / `HERMES_DASHBOARD_PASSWORD` from `.env`) includes
the full **Kanban board UI** — lanes by profile, card detail, comments,
filters, "nudge dispatcher". That's where you watch progress and catch the
orchestrator's checkpoint (`kanban_block(needs_input)`) cards. Bound to
`127.0.0.1` only.

**Notifications:** for early runs, docker-exec + the board are enough — the
checkpoint blocks show up on the board (pull). For push notifications, Hermes
supports messaging platforms (Discord/Slack/Telegram/WhatsApp/Weixin) via
`hermes gateway setup`, then subscribe a card with `hermes kanban
notify-subscribe --platform <p> --chat-id <you> <task-id>`. Note: each bot
allows only one active connection, so running two teams needs one bot per team.

## Repeatability — tearing down and starting over

Two different operations, don't confuse them:

- **Restart** (`docker compose restart` or `up -d`): picks up any edits to
  Tier-1 files (skills/profiles/hooks/config), preserves Tier-2 state
  (kanban history, memory, learned skills). This is the normal operation
  for iterating on a persona's instructions or a hook's logic.
- **Full reset** (`docker compose down -v` then `./bootstrap.sh <project> <repo-path>`
  again): wipes Tier-2 state and rebuilds the profile + board from
  scratch. Use this to prove the provisioning process itself is correct
  (task: "verify teardown/recreate cycle") or to genuinely start a
  project's team over. Tier-1 assets are never affected either way — they
  aren't part of what gets torn down, they're just re-mounted.

## Second (and Nth) project

```bash
./bootstrap.sh another-project /absolute/path/to/another-project/repo
```

Same script, different arguments. Per the migration plan §8, running
multiple projects concurrently needs one Hermes profile *per project* for
skill/memory isolation — this repo's `bootstrap.sh` handles the per-project
profile + board creation, but running two projects' containers side by
side (separate `docker compose` stacks, non-overlapping ports) isn't wired
up yet. Out of scope for the single-project trial this repo currently
targets; revisit once the trial's decision gate (migration plan §9) says
to proceed toward multi-project.

## Known gaps / verify-before-trusting

- **`bootstrap.sh` CLI surface is unverified.** The `hermes profile create`
  / `hermes kanban boards create` / `hermes kanban worker-profile apply` /
  `hermes kanban notify-subscribe` invocations are this plan's best
  reading of the public CLI docs, not yet run against a live instance.
  First real dry run (task #7) is where this gets corrected.
- **Test-file / design-brief path scoping is not yet enforced.**
  `quality-engineer` and `ux-designer` toolsets grant `edit` broadly; the
  intent (test files only / design-brief paths only) is noted in each
  `profile.yaml` but not mechanically scoped — verify whether Hermes
  toolsets support path-glob restriction, or whether this needs a
  dedicated hook, before relying on it.
- **`Z_AI_API_KEY` rotation.** The key that used to be hardcoded in
  `D:\code\eng-team-plugin\.mcp.json` is committed to that repo's git
  history in plaintext. Don't reuse it here — generate a new one and put
  it only in `.env` (gitignored).
- **Orchestrator profile-identity field name in the edit-guard hook.**
  `hooks/orchestrator_no_edit_guard.js` assumes the pre_tool_call event
  exposes the calling profile as `event.profile` (or falls back to a
  couple of guesses) — confirm the actual field name against a real event
  payload during task #9's negative test and fix the hook if it's wrong.
