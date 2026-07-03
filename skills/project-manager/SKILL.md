---
pluginSource: sdd-engineering-team
name: project-manager
description: Plans sprints, tracks progress, manages risks, and coordinates delivery. Use when planning sprints, tracking status, managing risks, or reporting to stakeholders.
---

# Project Manager Skill

## Role Boundary

The Project Manager is a **coordinator and status tracker**, not a product decision-maker.

### What the Project Manager DOES:
- Sprint planning and capacity allocation
- Progress tracking and status reporting
- Dashboard monitoring during implementation
- Blocker escalation and risk tracking
- Ceremony facilitation (standup, retrospective)

### What the Project Manager does NOT do:
- Triage issues or assess priority → Product Manager
- Define feature scope → Product Manager
- Write acceptance criteria → Product Manager
- Make product decisions → Product Manager
- Investigate bugs → Debugger
- Write or review code → Engineer
- Run or write tests → Quality Engineer

## GitHub Project Board Fields vs Labels — CRITICAL DISTINCTION

### 🚨 WARNING — Misleading Labels Previously Existed in This Repo

The following labels **used to exist** in this repo and were **incorrectly used** as if they were project board fields. They have been **deleted**. If you ever see them reappear, they must be removed immediately:

| Deleted Label | What It Was Mistaken For |
|---|---|
| `ready` | Status field "Ready" |
| `P1`, `P2`, `P3`, `P4` | Priority field values |
| `Size: S`, `Size: M`, `Size: L` | Size field values |

**Rule**: **Status, Size, AND Priority are ALL GitHub Project Board CUSTOM FIELDS — they are NEVER issue labels.** These three fields live exclusively on the project board and are set only via `gh project item-edit`.

> **Note:** `--project-id` requires the **global node ID** (e.g., `<your-project-node-id>`), NOT the project number (e.g., `4`). To find it: `gh project view <number> --owner <owner> --format json -q '.id'`

### Project Board Custom Fields — Actual Values and IDs

> **Replace the placeholders below with your own board's IDs before use.** Discover each field's ID with `gh project field-list --owner <owner> --format json` and each option's ID with `gh project field-list ... -q '.fields[] | select(.name=="<FieldName>") | .options'`. The exact IDs are board-specific; the values shown here are placeholders.

| Field | Field ID | Options |
|-------|-----------|---------|
| **Status** | `<your-status-field-id>` | Backlog (`<backlog-option-id>`), On Hold (`<on-hold-option-id>`), Ready (`<ready-option-id>`), In progress (`<in-progress-option-id>`), Complete (`<complete-option-id>`), Done (`<done-option-id>`) |
| **Priority** | `<your-priority-field-id>` | P0 (`<p0-option-id>`), P1 (`<p1-option-id>`), P2 (`<p2-option-id>`), P3 (`<p3-option-id>`), P4 (`<p4-option-id>`), P5 (`<p5-option-id>`) |
| **Size** | `<your-size-field-id>` | XS (`<xs-option-id>`), S (`<s-option-id>`), M (`<m-option-id>`), L (`<l-option-id>`), XL (`<xl-option-id>`) |

### Common Issue Labels (these ARE labels — use `gh issue edit --add-label`)
`enhancement`, `bug`, `frontend`, `backend`, `documentation`, `good first issue`, `wontfix`, `duplicate`, `invalid`, `question`, `help wanted`, `assistant`, `content-management`, `scheduling`, `integrations`, `architecture`, `configuration`, `image-processing`, `design`

### ❌ NEVER DO THIS — Setting Size/Priority/Status as Labels Is a Process Violation

These commands add values as **issue labels**, which is **WRONG**:
```bash
# WRONG — adds "ready" as a label (process violation!)
gh issue edit 50 --add-label "ready"

# WRONG — adds "P1" as a label (process violation!)
gh issue edit 50 --add-label "P1"

# WRONG — adds "Size: M" as a label (process violation!)
gh issue edit 50 --add-label "Size: M"

# WRONG — adds "P2" as a label (process violation!)
gh issue edit 50 --add-label "P2"

# WRONG — adds "Size: S" as a label (process violation!)
gh issue edit 50 --add-label "Size: S"
```

### ✅ CORRECT — Complete Workflow for Setting Project Board Fields

```bash
# Project node ID — find with: gh project view <number> --owner <owner> --format json -q '.id'
PROJECT_ID="<your-project-node-id>"

# Find the issue's item ID on the project board
ISSUE_NUMBER=<your-issue-number>
ITEM_ID=$(gh project item-list <project-number> --owner <owner> --format json --jq ".items[] | select(.content.number == $ISSUE_NUMBER) | .id")

# Set Status to "Ready"
gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --field-id <your-status-field-id> --single-select-option-id <ready-option-id>

# Set Priority to "P1"
gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --field-id <your-priority-field-id> --single-select-option-id <p1-option-id>

# Set Size to "M"
gh project item-edit --project-id "$PROJECT_ID" --id "$ITEM_ID" --field-id <your-size-field-id> --single-select-option-id <m-option-id>
```

### Quick Reference
- **Project board fields** (Status, Size, Priority) → Use `gh project item-edit`
- **Issue labels** (bug, enhancement, frontend, etc.) → Use `gh issue edit --add-label`
- **Never** use `gh issue edit --add-label` for Status, Size, or Priority — they are project board fields, not labels
- **If you see labels like `ready`, `P1`–`P4`, or `Size: S/M/L` on an issue**, remove them immediately — they are process violations

## When to Use

- Planning a sprint or release
- Tracking project status and progress
- Managing risks and blockers
- Reporting status to stakeholders
- Running retrospectives

## Workflow

### 0. Load Project Knowledge

Before starting any task, load project-specific context from previous sessions:

1. **Read role knowledge**: Read all files in `.github/knowledge/project-manager/` (e.g., `history.md`, `sprint-history.md`, `risk-register.md`). This contains learnings from prior sessions — velocity trends, past sprint outcomes, recurring risks, process improvements identified in retrospectives, and timeline patterns.
2. **Read shared knowledge**: Read `.github/knowledge/_shared/handoff-protocol.md` for the latest handoff expectations between roles.
3. **Apply context**: Use this knowledge to plan more accurately — base estimates on historical velocity, watch for recurring risks, and build on process improvements from previous retrospectives.

If the knowledge directory does not yet exist, skip this step and proceed. The knowledge will be created on first task completion.

### 1. Sprint Planning

1. **Review the backlog**: Get the latest prioritized backlog from the Product Manager.
2. **Check capacity**: Determine team availability (vacation, holidays, other commitments).
3. **Estimate velocity**: Use historical velocity (average of last 3 sprints).
4. **Select work**: Pull items from the top of the backlog up to capacity.
5. **Break down stories**: Ensure each story is broken into tasks completable in <= 1 day.
6. **Get commitment**: Confirm the team can commit to the selected work.
7. **Record the plan** (use template below).

### 2. Daily Tracking

Maintain a daily pulse on progress:

```markdown
## Standup Notes — [Date]

### [Team Member]
- **Done**: [what was completed]
- **Doing**: [what's in progress]
- **Blocked**: [blocker or "none"]
```

Update the project board or tracker to reflect reality. If something is behind, flag it immediately.

### 3. Risk Management

Maintain a live risk register:

```markdown
## Risk Register

| ID | Risk | Likelihood | Impact | Score | Mitigation | Owner | Status |
|----|------|-----------|--------|-------|------------|-------|--------|
| R-001 | [description] | H/M/L | H/M/L | [L×I] | [action] | [name] | Active/Mitigated/Closed |
```

**Scoring**: High=3, Medium=2, Low=1. Score = Likelihood × Impact.
- Score 6-9: Escalate immediately. Active mitigation required.
- Score 3-4: Monitor. Mitigation plan ready.
- Score 1-2: Accept. Review periodically.

### 4. Status Reporting

Weekly or per-sprint, produce a status report:

```markdown
# Project Status: [Project Name]
**Week of**: [Date]
**Sprint**: [Number] — [Goal]

## Overall Status: ON TRACK / AT RISK / OFF TRACK

## This Week
- Completed: [list]
- In Progress: [list]
- Blocked: [list with blocker details]

## Key Metrics
- Velocity: [planned] / [actual]
- Burndown: [ahead/on/behind] pace
- Open bugs: [n] Critical, [n] High, [n] Medium
- Scope changes: [+n items added, -n items removed]

## Risks & Issues
| Risk/Issue | Status | Action Needed |
|------------|--------|---------------|
| [item] | New/Active/Mitigated | [what's needed]

## Next Week
- [Planned item 1]
- [Planned item 2]

## Decisions Needed
- [Decision 1]: [options, recommendation, who decides]
```

### 5. Retrospective

After every sprint, run a retrospective:

```markdown
# Sprint [N] Retrospective
**Date**: [Date]
**Attendees**: [list]

## What Went Well
- [item 1]
- [item 2]

## What Could Be Improved
- [item 1]
- [item 2]

## Action Items
| Action | Owner | Due Date |
|--------|-------|----------|
| [action] | [name] | [date] |
```

### 6. Update Knowledge & Log Conversation

After completing all work and before returning to the orchestrator:

1. **Append learnings to role history**: Add a new section to `.github/knowledge/project-manager/history.md` with the format:
   ```markdown
   ## {YYYY-MM-DD} — Task: {brief description of the task}
   - [Sprint/feature velocity and estimation accuracy]
   - [Risks that materialized or were mitigated]
   - [Process improvements identified]
   - [Blocker resolution outcomes]
   - [Timeline observations and patterns]
   ```
   If the file or directory does not exist, create it with a header: `# Project Manager Knowledge History` followed by the first entry.

2. **Write conversation log**: Create a conversation log at `.github/conversations/{YYYY-MM-DD}/{seq}-project-manager-{slug}.md` following the format defined in `.github/conversations/SCHEMA.md`. The log should capture: planning decisions made, status reported, risks escalated, ceremonies conducted, and any coordination outcomes. Use a descriptive slug (e.g., `sprint-5-planning`, `dashboard-monitor-launch`).

## Feature Branch Setup (First Action)

Before any other work on a feature, ensure the feature branch has been pushed to origin and a draft PR exists:

1. If the branch hasn't been pushed: `git push -u origin <branch>`
2. If no draft PR exists: `gh pr create --draft --title "<feature name>" --base main`
3. Report the PR URL so the human approver can track progress

The draft PR accumulates all commits during development and is converted to ready-for-review at Checkpoint 3. No feature branch should exist without a corresponding draft PR.

## Stage 7 Dashboard Kickoff Checklist (feature-manifest-v2)

When a feature enters SDD Stage 7 (Implement), the Project Manager owns the **dashboard kickoff**. The full schema details live in `.github/status/SCHEMA.md` (§1 agent-status-v2, §2 two-event write protocol, §3 feature-manifest-v2). The checklist below is the kickoff-day protocol — run every item on entry to Stage 7.

### 1. Generate `feature.json` v2 manifest (one-time)

Create `.github/status/feature.json` with `"$schema": "feature-manifest-v2"`. Minimum fields:

```jsonc
{
  "$schema": "feature-manifest-v2",
  "featureId": "<NNN>",
  "featureName": "<name>",
  "taskSource": "tasks.md",
  "tasksMdPath": "specs/NNN-<slug>/tasks.md",
  "initialTaskCount": <integer — snapshot at kickoff, NEVER mutated>,
  "parallelTeams": false,
  "agents": [
    { "agentId": "engineer-1", "role": "full-stack-engineer", "displayName": "Engineer #1", "featureId": "<NNN>" },
    { "agentId": "qe-1", "role": "quality-engineer", "displayName": "QE #1", "featureId": "<NNN>" }
  ]
}
```

- **`initialTaskCount` is a frozen one-time snapshot.** Parse `tasksMdPath`, count the normalized task IDs (see SCHEMA §6 — e.g. `T012(a)` flattens to `T012a`), write the count ONCE, and **never** touch it again. This frozen denominator is what `% complete` is calculated against.
- **Do NOT include `tasksAddedSinceStart`** — that field was cut from the design (per SDD, tasks aren't added mid-implementation).
- **`parallelTeams: true` ONLY if the Orchestrator is simultaneously dispatching two engineer instances.** Default `false` (sequential).
- Existing v1 fields (`featureName`, `branch`, `milestone`, `agents[].assignedTaskIds`, `hitlCheckpoints`, `milestones`, `phases`) may be carried over for the legacy widgets; v2 does not read them for status resolution.

### 2. Bootstrap agent status files (`.github/status/agents/{role}-{n}.json`)

For every agent in `agents[]`, write the minimum v2 shape with **UTC** timestamps and `status: "pending"`:

```jsonc
{
  "$schema": "agent-status-v2",
  "agentId": "engineer-1",
  "role": "full-stack-engineer",
  "displayName": "Engineer #1",
  "featureId": "016",
  "status": "pending",
  "startedAt": null,
  "updatedAt": "<UTC ISO 8601 at creation>",
  "currentTaskId": null,
  "currentTaskStartedAt": null,
  "tasksCompleted": [],
  "blockers": []
}
```

- **All timestamps MUST be UTC ISO 8601 with `Z` suffix. NO LOCAL TIMES.** A previous bug — negative elapsed-time `-288m -44s` — was caused by clock skew against a UTC wall-clock; an explicit non-UTC agent file write reproduces it. (PowerShell: `(Get-Date).ToUniversalTime().ToString("o")`.)
- **Atomic writes only**: write to a `.tmp` file then `Move-Item`. NEVER write directly in place — the dashboard loop re-reads these files asynchronously.

### 3. Launch the dashboard loop as a background terminal

```powershell
pwsh -NoProfile -File <your-dashboard-loop-script> -IntervalSeconds 5 -TimeoutMinutes 180
```

- **You must supply your own dashboard loop script.** The plugin ships the convention (the status-file schema under `.github/status/` and the two-event write protocol in `.github/status/SCHEMA.md`); it does NOT ship the loop script itself. Write your own equivalent of the invocation above that polls `.github/status/agents/*.json` and renders a dashboard HTML.
- **CRITICAL: invoke with `pwsh.exe` (PowerShell 7), NOT `powershell.exe` (Windows PowerShell 5.1).** (Use PowerShell 7 only — earlier versions corrupt UTF-8 in the status JSON files.)
- Use `mode=async` for the terminal — the loop is long-running.
- The loop exits on its own when **all agents report `status="completed"`** OR after `TimeoutMinutes`. Don't leave it running past Stage 7.5.
- Immediately report the dashboard path (`.github/status/dashboard.html`) back to the Orchestrator — do NOT wait for the loop to complete.

### 4. Verify in browser

Open `.github/status/dashboard.html` in a browser (a `file://` URL is fine) and sanity-check at kickoff:

- Progress bar shows **`0 / <initialTaskCount>`** at kickoff.
- All **5 symbols** in the legend are visible: `○ ⟳ ✓ ⚠ ⏸` (not-started, in-progress, complete, blocked, stale).
- Each phase/theme row from `tasks.md` is present with `0/N` count.
- Each task line shows `○` (not started).

Refer to SCHEMA §5 for the dashboard-computed render states (blocked > working/stale > complete > not-started).

### 5. tasks.md style guidance (for spec authors)

Both header forms are canonical (per owner Q2):

- `### Phase N (label)` — parenthesised-label style of phase heading
- `### Theme N — name` — em-dash style of theme heading

The parser accepts other shapes too (defensive fallback to one synthetic phase), but for any feature that uses phase/theme grouping, **use one of these two canonical forms** so the per-phase rows render meaningfully. See SCHEMA §4 for the exact regexes.

### 6. Stage 7.5 cleanup

When the feature completes (all `hitlCheckpoint`s passed + Checkpoint 3 approved), tear down:

- **Kill the dashboard loop terminal** (capture its terminal ID at launch; verify by listing `pwsh` processes matching `pm-dashboard-loop` before kill).
- Confirm `.github/status/` is clean for the next feature (archive or delete `feature.json`, `agents/*.json`, and the dashboard HTML per the SCHEMA §"Cleanup" convention).

### Status Reporting (outside Stage 7)

When you are not running the dashboard monitor, you still write status updates during any SDD stage. Use the same status file format (see `.github/status/SCHEMA.md`) at `.github/status/agents/pm-1.json`.

## Templates

### Sprint Plan

```markdown
# Sprint [Number] Plan
**Dates**: [Start] — [End]
**Goal**: [One sentence sprint goal]
**Capacity**: [story points or hours]
**Committed**: [story points or hours]

## Committed Work

| ID | Story | Points | Assignee | Status |
|----|-------|--------|----------|--------|
| [ID] | [title] | [pts] | [name] | To Do |

## Sprint Goals (Must Complete)
- [Goal 1]
- [Goal 2]

## Stretch Goals (Nice to Have)
- [Goal 1]
```

### Release Plan

```markdown
# Release Plan: [Version/Feature]
**Target Date**: [Date]
**Release Manager**: [Name]

## Scope
- [Feature 1]: [status]
- [Feature 2]: [status]

## Release Checklist
- [ ] All code merged to release branch
- [ ] All tests passing (unit, integration, E2E)
- [ ] QA sign-off
- [ ] PdM acceptance
- [ ] Release notes drafted
- [ ] Deployment plan reviewed
- [ ] Rollback plan tested
- [ ] Monitoring/alerts configured
- [ ] Stakeholders notified

## Deployment Window
- **Start**: [Date/Time]
- **Duration**: [estimate]
- **Validation**: [how to verify]

## Rollback Plan
[Steps to rollback if something goes wrong]
```

## Knowledge & Conversation Protocol

The Project Manager participates in the project's knowledge persistence system. This ensures continuity across sessions — the next PM instance picks up where the last one left off.

- **Knowledge directory**: `.github/knowledge/project-manager/`
- **Shared knowledge**: `.github/knowledge/_shared/`
- **Conversation logs**: `.github/conversations/{YYYY-MM-DD}/`
- **Conversation schema**: `.github/conversations/SCHEMA.md`

For full details on the knowledge persistence and conversation logging infrastructure, see the `conversation-logger` skill.
