# Architecture overview — Hermes-native terminology and team flow

This is the plain-language map for "what do we call each thing, and how does
work actually move." Written because the terms (profile, worker, skill,
persona, agent) get used loosely in conversation but mean specific, distinct
things in this repo. Where a claim is load-bearing, it points at the file
that proves it — see that file for the full reasoning.

## 1. Terminology: what is each "agent" actually called in Hermes?

There is no Hermes object literally called "agent." What we've been calling
"the 9 agents" (product-manager, senior-engineer, etc.) are **Hermes
profiles**. Nothing in this repo uses "agent" as a first-class Hermes
concept — it only survives in comments as a pointer back to the pre-Hermes
V2 source files (`D:\code\eng-team-plugin\agents\*.agent.md`) each persona
was ported from.

| Term | What it means here | Where it lives |
|---|---|---|
| **Profile** | A real Hermes object: `hermes profile create <name>`. Its own `HERMES_HOME` directory, own `config.yaml`, own `SOUL.md`, own skills/sessions/memory. This is the actual unit of "one team member." | `state/data/profiles/<name>/` inside the container (copied there by `bootstrap.ps1`/`.sh` from `profiles/<name>/` in this repo) |
| **Worker** | Kanban-speak for "a profile while it's running a dispatched card." Not a separate object — a worker *is* a profile, dispatched. `hermes kanban assignees` literally reads the profile list. | n/a — just usage |
| **Orchestrator** | One specific profile (coordinator role). "Orchestrator" is Hermes's own term for this kind of profile, not an invented name. | `profiles/orchestrator/` |
| **SOUL.md** | The persona prose for a profile — identity, responsibilities, working style. Injected into that profile's system prompt automatically. This is where "who is this specialist" lives. | `profiles/<name>/SOUL.md` |
| **config.yaml (per-profile)** | The real Hermes config schema subset for a profile: `model`, `platform_toolsets`, `hooks.pre_tool_call`, `skills.external_dirs`, `mcp_servers`. This is where "what can this specialist do" lives — not SOUL.md. | `profiles/<name>/config.yaml` |
| **profile.yaml** | A different, auto-generated file Hermes itself writes inside each profile's data directory. Contains only `{description, description_auto}`. Read by the Kanban decomposer to route triage tasks by role. Never hand-authored in this repo. | `state/data/profiles/<name>/profile.yaml` (Hermes-managed, not git-tracked) |
| **Skill** | A loadable procedure/knowledge module, force-loaded onto a card via `kanban_create --skill`. Two families: hand-authored ("curated") and SpecKit-generated (`speckit-*`). Skills are *not* personas — a skill is what a profile is told to run, not who is running it. | `skills/` (curated) and `speckit/.claude/skills/` (SpecKit-generated, vendored+pinned) — see §4 |
| **Toolset** | A named bundle of tool capabilities (`file`, `terminal`, `kanban`, `web`, `memory`, ...) turned on/off per profile via `platform_toolsets.cli`. Coarse-grained (whole toolset on/off, no per-tool split within it). | `profiles/<name>/config.yaml` → `platform_toolsets.cli` |
| **Hook** | A shell/JS script matched against specific tool calls within an *enabled* toolset — the fine-grained half of guardrails (e.g. blocks `write_file` even though `file` is on). | `hooks/*.js`, referenced from each profile's `config.yaml` → `hooks.pre_tool_call` |
| **Board** | The Kanban board itself — one per project (`hermes kanban boards create <project>`). Cards are the unit of dispatched work. | Dashboard at `http://127.0.0.1:9119`; underlying data in `state/data/kanban/` |

**So, to directly answer "are they profiles, agents, or skills":** the 10
team members (orchestrator + 9 specialists) are **Hermes profiles**. Each
profile has a persona (`SOUL.md`) and a capability config (`config.yaml`).
**Skills** are a separate, third thing — procedures a profile runs, not an
identity. "Agent" isn't a Hermes noun; it's leftover vocabulary from the
pre-Hermes design this was ported from.

## 2. The team roster (10 profiles)

| Profile | Model tier | Can write code/files? | Notes |
|---|---|---|---|
| `orchestrator` | Flagship (GLM-5.2) | No — `terminal`/`code_execution` toolsets not enabled at all; `no_write_guard.js` also blocks `write_file`/`patch` mechanically | Pure coordinator. Builds the Kanban board, never executes work itself. |
| `product-manager` | Flagship | Yes (spec artifacts only, by convention) | Owns Constitution/Specify/Clarify/Analyze; authors artifacts directly (changed from V2, where a separate writer generated them). |
| `ux-designer` | Flagship | No terminal/code_execution | Owns design system + UX briefs; co-owns Clarify-stage UX questions. |
| `senior-engineer` | Flagship (GLM-5.2) | Yes | Owns Plan/Tasks stages + ad-hoc troubleshooting, fixes, review. Split off from the old `full-stack-engineer`. |
| `implementation-engineer` | Cheap (GLM-4.7) | Yes | Owns Implement stage only, for already-scoped tasks handed down from `senior-engineer`. Split off from `full-stack-engineer`. |
| `quality-engineer` | Cheap | Yes (test files, by convention — not mechanically path-scoped) | Test strategy, automation, pre-Checkpoint-2 quality checklist. |
| `debugger` | Flagship | No — `write_file`/`patch` mechanically blocked | Diagnoses only; hands fixes to `senior-engineer`. |
| `qa-analyst` | Cheap | No `file` toolset at all | Browser-based (Playwright) functional/UX validation; reports via `kanban_comment`. |
| `project-manager` | Cheap | Git/terminal only (no source edits) | Sprint cadence, branch/PR setup, `gh pr ready`, retrospective/cleanup. |
| `independent-reviewer` | Flagship | No — findings only | Fresh-eyes review before Checkpoint 2; deliberately has no `memory` toolset wired in, so it can't be biased by the team's own prior assumptions. |

Full detail (toolsets, hooks, model wiring) is authoritative in each
`profiles/<name>/config.yaml` and `SOUL.md` — this table is a summary, not
a replacement.

## 3. Hardline rules that apply to every profile

- **No profile ever merges a PR.** `no_merge_guard.js` blocks `gh pr
  merge`/`gh pr close` mechanically for every profile, regardless of what a
  dispatch says. `gh pr ready` (draft → ready-for-review) is the team's
  terminal state; a human merges. (Incident precedent: 2026-07-01, PR #172.)
- **Only the orchestrator can reach a human.** Specialists that get stuck can
  only `kanban_comment` on their own card — the orchestrator sees that and
  either re-dispatches with sharper instructions or escalates itself via
  `kanban_block`. No specialist profile has the `kanban_block` tool.

## 4. Where skills come from

Two separate, both read-only-mounted, directories — kept apart deliberately
so the agent (or a self-improving skill loop) can never rewrite either
baseline:

- **Curated** (`./skills/` → `/opt/curated-skills`): hand-authored, ported
  1:1 from `D:\code\eng-team-plugin\skills\`.
- **SpecKit-generated** (`./speckit/.claude/skills/` → `/opt/speckit-skills`):
  the `speckit-<stage>` skills (constitution, specify, clarify, plan, tasks,
  analyze, implement, checklist, taskstoissues), vendored at a pinned
  version and regenerated only via `scripts/update-speckit-skills.*` — never
  installed at container start.

A card force-loads a skill via `kanban_create --skill speckit-<stage>`. This
is the actual enforcement mechanism for "the SDD process is followed": the
skill is injected into the dispatched profile's context structurally, not
left to the profile remembering to invoke it.

## 5. How the team communicates and divides work (Kanban flow)

**There is no in-session sub-agent delegation.** An earlier design
considered a `delegate_task`/in-session-subagent path (V2's model); this repo
deliberately reverted that (see the "Adopt Hermes-native Kanban
orchestration" commit). All team fan-out is **Kanban cards + the gateway's
own dispatcher** — the orchestrator never spawns or polls a worker directly.

### The mechanics

1. The orchestrator decomposes work into **Kanban cards**
   (`kanban_create(assignee=<profile>, skills=[...], parents=[...],
   body="...")`). Each card names one owning profile, one force-loaded
   skill (usually a `speckit-*` stage), and its dependency parents.
2. The **gateway dispatcher** — not the orchestrator — watches the board and
   spawns the assigned profile as its own OS process the moment a card's
   parents are all `done` (card status flips to `ready`). This is a real
   background loop (`kanban.dispatch_interval_seconds: 60` in
   `config/config.yaml`), separate from any profile's own session.
3. The dispatched profile runs with that card's force-loaded skill already
   in context, does the work, and reports completion via `kanban_complete`
   (or `kanban_comment` if it's stuck — see hardline rules above).
4. Completing a card can promote a sibling/child card to `ready`, which
   re-triggers the dispatcher — this is how a whole SDD stage chain runs
   unattended once cards are linked.
5. **`parents=[...]` is the only ordering mechanism.** There's no separate
   "workflow engine" — Constitution→Specify→Clarify→...→Implement is
   enforced purely by the dependency graph between cards, not by prose
   instructions to the orchestrator.

### How the orchestrator "wakes up" without polling

The orchestrator does not sit and watch the board. To learn when a stage
finishes, it creates a **terminal checkpoint card assigned to itself**,
gated on every leaf card of that stage (`parents=[...all leaves...]`).
Hermes only promotes that checkpoint card to `ready` once every parent is
`done` — and promoting it to `ready` is what causes the dispatcher to
re-spawn the orchestrator. So the orchestrator is re-invoked exactly at
completion, reads every child's handoff summary via `kanban_show`, and then
decides whether to advance or block for human input.

### Human checkpoints

The orchestrator is the *only* profile with the `kanban_block` tool.
`kanban_block(kind="needs_input", reason="...")` is the one thing that
surfaces to a human (via the dashboard board, pull-based; or a subscribed
notify channel, push-based, once wired). `kind="dependency"` does not reach
a human — it just represents "waiting on parents," which is what naturally
happens for every other queued card. There are exactly three checkpoints per
feature:

- **Checkpoint 1** — after Clarify.
- **Checkpoint 2** — after Plan/Tasks/Analyze **and** the automatic
  Independent Review loop (Stage 8) comes back CLEAR.
- **Checkpoint 3** — at feature completion (Implement + Retro/Cleanup done).

### Card materialization cadence (why the whole feature isn't on the board at once)

The orchestrator only materializes **one checkpoint segment at a time**:

- **→ CP1**: Constitution → Specify → Clarify (pre-linked linear chain).
- **→ CP2**: Plan → Tasks → Analyze → Independent-Review loop.
- **→ CP3**: Implement (built from `tasks.md`, see below) → Retro/Cleanup.

Later stages are data-derived (Implement's cards come from `tasks.md`, which
doesn't exist until Stage 6 runs) and each checkpoint is a human gate that
can change downstream scope — so pre-building the whole graph up front would
just be wasted/wrong work.

### The Independent Review loop (Stage 8, automatic)

Runs between Analyze and Checkpoint 2, without a human invoking it. The
orchestrator dispatches a **fresh** `independent-reviewer` instance (no
memory carried between rounds — that's deliberate, it stays fresh-eyes) at
the spec folder. Findings route back to the owning persona for revision
(`product-manager` for spec/clarify, `senior-engineer` for plan/tasks,
`ux-designer` for design-brief), then another fresh reviewer instance runs
against the revision. Terminates on: a CLEAR round (proceed to CP2), or
deadlock (same finding unresolved across 3 rounds, or a persona disagrees
and the reviewer holds its finding) — deadlocks escalate straight to Damon.
`[NEEDS HUMAN INPUT]`-labeled findings skip persona routing and escalate
immediately.

### Implement stage — how `tasks.md` becomes cards

Once Checkpoint 2 clears, `tasks.md` already contains a dependency graph
(`Deps:` and `[P]` parallel-safe markers, grouped into phases `G1…`). The
orchestrator **transcribes** this graph rather than re-deciding what's
parallel-safe:

- `Deps:` → `parents=[...]` (enforces ordering, including RED→GREEN
  test-first sequencing).
- Owner column → `assignee` (`engineer`→`implementation-engineer`,
  `qe`→`quality-engineer`), which also **selects the model tier** — there is
  no per-card model override, so routing the assignee correctly is how
  cost/latency get controlled.
- Independent groups → sibling cards in parallel; tasks within one group →
  batched into a single card run sequentially in that worker's context
  (avoids re-paying fixed per-card overhead — orientation, skill text,
  re-reading `plan.md`/`spec.md` — against a shared, budget-capped GLM
  quota). One card per task is reserved for genuinely large, independent
  tasks. A `kanban swarm` shortcut exists for the clean parallel-workers →
  verifier → synthesizer pattern when there's no cross-dependency.
- If `tasks.md` has no parallel-safe work at all, fall back to one Implement
  card that walks every phase sequentially (same as the pre-Hermes design).

### Stage table (for reference)

| Stage | # | Owning profile | Force-loaded skill |
|---|---|---|---|
| Constitution | 1 | `product-manager` | `speckit-constitution` |
| Specify | 2 | `product-manager` | `speckit-specify` |
| Clarify | 3 | `product-manager` (+`ux-designer` for UX Qs) — **CP1** | `speckit-clarify` |
| Design brief | 4 | `ux-designer` | — |
| Plan | 5 | `senior-engineer` | `speckit-plan` |
| Tasks | 6 | `senior-engineer` | `speckit-tasks` |
| Analyze | 7 | `product-manager` | `speckit-analyze` |
| Independent Review | 8 | orchestrator dispatches `independent-reviewer` directly | — |
| — | — | **Checkpoint 2** | |
| Implement | 9 | `implementation-engineer` (scoped) or `senior-engineer` (ad-hoc) | `speckit-implement` |
| Retro & Cleanup | 10 | `project-manager` | `speckit-taskstoissues` (if converting tasks→issues) |
| — | — | **Checkpoint 3** | |

## 6. Non-SDD (ad-hoc) work

Not everything goes through the full 10-stage SDD flow. Bug reports,
ambiguous feature requests, tests, and browser validation are dispatched
directly by the orchestrator to the matching specialist as a single card (or
small dependency chain), per the delegation table in
[`profiles/orchestrator/SOUL.md`](../profiles/orchestrator/SOUL.md#delegation-map)
— e.g. a bug report goes to `debugger` (diagnose) → `senior-engineer` (fix),
tests go to `quality-engineer`, requirements questions go to
`product-manager`. The SDD lifecycle is specifically for "new feature,"
where the orchestrator manages the full stage sequence above.

## 7. Source of truth, if this doc and the code disagree

This document summarizes; it does not override. The load-bearing detail
lives in:

- [`docs/MOUNTS.md`](MOUNTS.md) — mount layout, guardrail mechanism proof,
  per-profile config resolution.
- [`profiles/orchestrator/SOUL.md`](../profiles/orchestrator/SOUL.md) — full
  dispatch recipe, checkpoint logic, Independent Review loop detail.
- Each `profiles/<name>/config.yaml` — actual enabled toolsets/hooks/model
  per profile (comments there explain *why*, verified against a live
  container, not docs).
- [`docs/temp/V3-Supplement-Model-and-Key-Binding.md`](temp/V3-Supplement-Model-and-Key-Binding.md)
  — model-tier-per-profile rationale.

Remember: `profiles/` and `config/config.yaml` in this repo are **copy-in
sources**, not live mounts — editing them has no effect until the next
`bootstrap.ps1`/`.sh` run (see `docs/MOUNTS.md` header).
