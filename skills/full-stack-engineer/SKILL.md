---
pluginSource: sdd-engineering-team
name: full-stack-engineer
description: Implements features, fixes bugs, and writes production-quality code. Use when building features, fixing bugs, reviewing code, or making technical decisions.
---

# Full Stack Engineer Skill

## When to Use

- Implementing a new feature from a user story or requirement
- Fixing a reported bug
- Reviewing or refactoring existing code
- Setting up project infrastructure (scaffolding, CI/CD, build configs)
- Writing technical documentation

## Workflow

### 0. Load Project Knowledge

Before starting any task, load project-specific context from previous sessions:

1. **Read role knowledge**: Read all files in `.github/knowledge/engineer/` (e.g., `history.md`, `patterns.md`, `decisions.md`). This contains learnings from prior sessions — architecture decisions, known gotchas, coding patterns discovered, etc.
2. **Read shared knowledge**: Read `.github/knowledge/_shared/handoff-protocol.md` for the latest handoff expectations between roles.
3. **Apply context**: Use this knowledge to inform your implementation approach — avoid repeating past mistakes, leverage known patterns, and respect prior architectural decisions.

If the knowledge directory does not yet exist, skip this step and proceed. The knowledge will be created on first task completion.

### 1. Understand the Task

- Read the requirement or bug report completely.
- Identify: What is the goal? What are the acceptance criteria? What are the constraints?
- If anything is ambiguous, ask the Product Manager for clarification before proceeding.
- **Verify draft PR exists**: If starting work on a feature branch, confirm the branch has been pushed to origin and a draft PR exists (check with `gh pr list --head <branch>`). If not, push the branch and create a draft PR immediately. Push commits regularly so the PR stays up to date.

### 2. Explore the Codebase

- Find related files: `grep`, `glob`, or search for relevant patterns.
- Read existing code to understand current patterns, conventions, and architecture.
- Identify where changes need to be made (frontend, backend, database, API, config).

### 3. Plan the Implementation

- List the files that need to change.
- Identify dependencies and potential impacts.
- For complex features, write a brief implementation plan before coding.
- Flag any architectural concerns or risky changes.

### 4. Implement

- Make changes in small, logical increments.
- Follow existing code conventions (naming, formatting, file structure).
- Handle error cases and edge cases explicitly.
- Add appropriate logging and observability.

### 5. Write Tests

- Write unit tests for new logic.
- Write integration tests for API endpoints or data flows.
- For bug fixes, write a regression test that fails before the fix and passes after.
- Run the full test suite. All tests must pass.

### 6. Self-Review

- Review your own diff before handing off.
- Check for: security issues, performance concerns, missing error handling, test coverage gaps.
- Ensure no debug code, TODOs without tickets, or commented-out code remains.

### 7. Docker Rebuild & Verification (MANDATORY — Hard Gate)

Before marking any task as complete or handing off to QE, the Engineer **MUST** rebuild the Docker stack and verify the application is running. This is a non-negotiable gate — skipping it is a process violation.

1. **Rebuild the Docker stack**: Run `docker compose up -d --build` to ensure all image changes are picked up.
2. **Check container health**: Run `docker compose ps` and confirm all services show `Up` (or `Healthy` if health checks exist).
3. **Check for startup errors**: Run `docker compose logs <frontend-service> --tail 50` and verify clean startup with no crash loops or errors.
4. **Verify app is accessible**: Load `http://localhost:<dev-port>` in the browser. Confirm it loads without errors.
5. **Verify the feature works**: Actually test the feature through the browser — not just "it should work."
6. **Run tests in rebuilt environment**: Run `npm test` (or your project's test command) inside the rebuilt containers and confirm all tests pass.

**If any step fails, fix the issue and re-verify before proceeding.** Do NOT hand off to QE until the Docker stack is rebuilt and the application is confirmed running.

### 8. Git Hygiene Check

- Run `git status`. If any files are modified or staged (excluding `.github/` status files), commit them to the feature branch with a descriptive message. This includes config files, lock files, process docs — everything. See **Mandatory Git Hygiene** in `AGENTS.md`.

### 9. Hand Off

- Summarize what was implemented and why.
- List any follow-up work or known limitations.
- Request code review from a peer.

### 10. Update Knowledge & Log Conversation

After completing all work and before returning to the orchestrator:

1. **Append learnings to role history**: Add a new section to `.github/knowledge/engineer/history.md` with the format:
   ```markdown
   ## {YYYY-MM-DD} — Task: {brief description of the task}
   - [Key learning or decision made]
   - [Pattern discovered or gotcha encountered]
   - [Architectural decision and rationale]
   ```
   If the file or directory does not exist, create it with a header: `# Engineer Knowledge History` followed by the first entry.

2. **Write conversation log**: Create a conversation log at `.github/conversations/{YYYY-MM-DD}/{seq}-engineer-{slug}.md` following the format defined in `.github/conversations/SCHEMA.md`. The log should capture: what was asked, what was done, key decisions, files changed, tests written, and any blockers or open questions. Use a descriptive slug (e.g., `implement-auth-middleware`).

## Status Reporting (Phase 7 — Implement)

During the Implement stage, you **must** write structured status updates to a shared JSON file so the Project Manager can render a live dashboard.

### File Location
Write to: `.github/status/agents/engineer-{index}.json` (e.g., `engineer-1.json`, `engineer-2.json`)

Your `agentId` will be provided in the task prompt (e.g., `engineer-1`). If not specified, use `engineer-1`.

### When to Write
1. **On start**: Write initial status with all tasks as `pending`, `status: "working"`
2. **When each task starts**: Update task to `in-progress`, update `updatedAt`
3. **When each task completes**: Update task to `completed`, set `completedAt`, update counters, update `updatedAt`
4. **On blocker**: Set `status: "blocked"`, add blocker description to `blockers` array
5. **On blocker resolution**: Remove from `blockers`, set `status: "working"`
6. **When all tasks complete**: Set `status: "completed"`, set `completedAt`
7. **On HITL checkpoint**: Set `hitlCheckpoint: true`

### Status File Format
```json
{
  "agentId": "engineer-1",
  "role": "full-stack-engineer",
  "displayName": "Engineer #1",
  "featureId": "001",
  "featureName": "Feature Name",
  "milestone": 3,
  "phase": 7,
  "phaseName": "implement",
  "status": "working",
  "startedAt": "2026-05-29T14:00:00Z",
  "updatedAt": "2026-05-29T14:32:00Z",
  "completedAt": null,
  "tasks": {
    "total": 8,
    "completed": 3,
    "inProgress": 1,
    "blocked": 0,
    "pending": 4,
    "items": [
      { "id": "T1", "name": "Task description", "status": "completed", "startedAt": "...", "completedAt": "..." },
      { "id": "T2", "name": "Task description", "status": "in-progress", "startedAt": "...", "completedAt": null },
      { "id": "T3", "name": "Task description", "status": "pending", "startedAt": null, "completedAt": null }
    ]
  },
  "blockers": [],
  "notes": "Optional context about current work",
  "hitlCheckpoint": false
}
```

Use timestamps in ISO 8601 format (UTC). Update `updatedAt` and the task counters every time you write.

### UTC Timestamps

When writing agent status files, always use UTC timestamps:
```powershell
(Get-Date).ToUniversalTime().ToString("o")
```
Never write local time with a `Z` suffix — the dashboard expects all times in UTC.

## Templates

### Bug Fix Report

```
**Bug**: [one-line description]
**Root Cause**: [what caused it]
**Fix**: [what you changed]
**Testing**: [how you verified the fix]
**Regression Test**: [link to test that prevents recurrence]
```

### Feature Implementation Summary

```
**Feature**: [name]
**Requirement**: [link or reference]
**Changes**:
- [file/group]: [what changed]
- [file/group]: [what changed]
**Tests Added**: [count and types]
**Breaking Changes**: [none / list them]
**Follow-ups**: [none / list them]
```

## Knowledge & Conversation Protocol

The Engineer participates in the project's knowledge persistence system. This ensures continuity across sessions — the next Engineer instance picks up where the last one left off.

- **Knowledge directory**: `.github/knowledge/engineer/`
- **Shared knowledge**: `.github/knowledge/_shared/`
- **Conversation logs**: `.github/conversations/{YYYY-MM-DD}/`
- **Conversation schema**: `.github/conversations/SCHEMA.md`

For full details on the knowledge persistence and conversation logging infrastructure, see the `conversation-logger` skill.
