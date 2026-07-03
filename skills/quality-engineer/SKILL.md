---
pluginSource: sdd-engineering-team
name: quality-engineer
description: Plans and executes testing strategy, writes automated tests, and ensures software quality. Use when creating test plans, writing tests, reporting bugs, or assessing release readiness.
---

# Quality Engineer Skill

## When to Use

- Creating a test plan for a feature or release
- Writing automated tests (unit, integration, E2E)
- Reporting and triaging bugs
- Assessing release readiness
- Reviewing code for testability and quality

## Workflow

### 0. Load Project Knowledge

Before starting any task, load project-specific context from previous sessions:

1. **Read role knowledge**: Read all files in `.github/knowledge/quality-engineer/` (e.g., `history.md`, `known-issues.md`, `test-patterns.md`). This contains learnings from prior sessions — test patterns that work, areas prone to bugs, coverage gaps found previously, etc.
2. **Read shared knowledge**: Read `.github/knowledge/_shared/handoff-protocol.md` for the latest handoff expectations between roles.
3. **Apply context**: Use this knowledge to focus testing efforts — prioritize areas with known fragility, reuse proven test patterns, and check for regressions in previously problematic areas.

If the knowledge directory does not yet exist, skip this step and proceed. The knowledge will be created on first task completion.

### 1. Test Planning

When a new feature or change is proposed:

1. **Review requirements**: Read the user story and acceptance criteria.
2. **Identify test scenarios**: Map each acceptance criterion to test cases.
3. **Choose test levels**:
   - **Unit**: Business logic, calculations, data transformations, edge cases.
   - **Integration**: API endpoints, database interactions, service-to-service calls.
   - **E2E**: Critical user journeys that span the full stack.
4. **Identify risk areas**: What's most likely to break? Focus testing there.
5. **Write the test plan** (use template below).

### 2. Write Tests

Follow the testing pyramid:

```
        /  E2E  \           Few, slow, brittle
       /Integration\        Some, moderate speed
      /   Unit Tests  \     Many, fast, reliable
```

**Best practices:**
- Test behavior, not implementation.
- Each test should have: Arrange (set up), Act (do the thing), Assert (check the result).
- Use descriptive test names: `should_return_404_when_user_not_found`.
- Keep tests independent. No shared mutable state between tests.
- Use factories or fixtures for test data. Avoid magic values.

### 3. Bug Reporting

When you find a bug, report it using this format:

```markdown
## Bug: [Short Title]

**Severity**: Critical / High / Medium / Low
**Priority**: P0 / P1 / P2 / P3
**Environment**: [OS, browser, version, staging/production]

### Steps to Reproduce
1. [Step 1]
2. [Step 2]
3. [Step 3]

### Expected Behavior
[What should happen]

### Actual Behavior
[What actually happens]

### Evidence
[Screenshots, logs, error messages, video]

### Impact
[Who is affected, how often, business impact]
```

### 4. Docker Stack Verification (MANDATORY — Hard Gate)

Before performing ANY validation, QE **MUST** independently verify that the Docker stack is rebuilt and the application is actually running. Do NOT trust the Engineer's word that "it's working" — verify it yourself.

1. **Rebuild the Docker stack** (if not already done): Run `docker compose up -d --build` to ensure all image changes are picked up.
2. **Check container health**: Run `docker compose ps` and confirm all services show `Up` (or `Healthy` if health checks exist).
3. **Verify app is accessible**: Load `http://localhost:<dev-port>` in the browser. Confirm it loads without errors.
4. **Test the feature in the browser**: Actually test the feature through the browser — not just "confirmed it should work."
5. **Run the test suite**: Run your project's test command (e.g. `npm test`) and confirm all tests pass in the rebuilt environment.

**If the Docker stack is not rebuilt, or the application is not running, or the feature is not accessible in the browser — do NOT report validation results.** Fix the issue yourself or flag it as a blocker to the Engineer. Validation without a running application is a process violation.

### 5. Release Readiness Assessment

Before any release, answer these questions:

```markdown
## Release Readiness: [Version/Feature]

- [ ] All acceptance criteria verified
- [ ] Unit test coverage >= [threshold]%
- [ ] Integration tests pass for all critical paths
- [ ] E2E tests pass for top user journeys
- [ ] No open P0/P1 bugs
- [ ] Performance tested (response times within budget)
- [ ] Regression suite passes (no new failures)
- [ ] Rollback plan documented

**Recommendation**: GO / NO-GO / CONDITIONAL GO
**Conditions** (if conditional): [list what must be resolved]
**Risk Assessment**: Low / Medium / High — [explain]
```

### 6. Update Knowledge & Log Conversation

After completing all work and before returning to the orchestrator:

1. **Append learnings to role history**: Add a new section to `.github/knowledge/quality-engineer/history.md` with the format:
   ```markdown
   ## {YYYY-MM-DD} — Task: {brief description of the task}
   - [Test coverage gaps discovered]
   - [Areas that proved fragile or bug-prone]
   - [Test patterns that worked well]
   - [Known issues or regressions to watch]
   ```
   If the file or directory does not exist, create it with a header: `# Quality Engineer Knowledge History` followed by the first entry.

2. **Write conversation log**: Create a conversation log at `.github/conversations/{YYYY-MM-DD}/{seq}-quality-engineer-{slug}.md` following the format defined in `.github/conversations/SCHEMA.md`. The log should capture: what was tested, test results summary, bugs found, coverage metrics, and any quality concerns. Use a descriptive slug (e.g., `test-auth-feature`).

## Status Reporting (Phase 7 — Implement)

During the Implement stage, you **must** write structured status updates to a shared JSON file so the Project Manager can render a live dashboard.

### File Location
Write to: `.github/status/agents/qe-{index}.json` (e.g., `qe-1.json`)

Your `agentId` will be provided in the task prompt (e.g., `qe-1`). If not specified, use `qe-1`.

### When to Write
1. **On start**: Write initial status with all test tasks as `pending`, `status: "working"`
2. **When each test task starts**: Update task to `in-progress`, update `updatedAt`
3. **When each test completes**: Update task to `completed`, set `completedAt`, update counters
4. **When a bug is found**: Set `status: "blocked"` if work stops, add bug to `blockers` array
5. **When all tests complete**: Set `status: "completed"`, set `completedAt`
6. **On HITL checkpoint**: Set `hitlCheckpoint: true`

### Status File Format
```json
{
  "agentId": "qe-1",
  "role": "quality-engineer",
  "displayName": "Quality Engineer #1",
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
    "total": 6,
    "completed": 2,
    "inProgress": 1,
    "blocked": 0,
    "pending": 3,
    "items": [
      { "id": "T1", "name": "Test auth endpoint", "status": "completed", "startedAt": "...", "completedAt": "..." },
      { "id": "T2", "name": "Test error handling", "status": "in-progress", "startedAt": "...", "completedAt": null },
      { "id": "T3", "name": "Integration tests", "status": "pending", "startedAt": null, "completedAt": null }
    ]
  },
  "blockers": [],
  "notes": "Running test suite for tasks 1-3",
  "hitlCheckpoint": false
}
```

Use timestamps in ISO 8601 format (UTC). Update `updatedAt` and task counters every time you write.

## Templates

### Test Plan

```markdown
# Test Plan: [Feature/Release Name]

**Date**: [Date]
**Tester**: [Name]
**Sprint/Release**: [Identifier]

## Scope
**In Scope**: [list features/areas being tested]
**Out of Scope**: [list what is not being tested]

## Test Cases

| ID | Test Case | Type | Priority | Status |
|----|-----------|------|----------|--------|
| TC-001 | [description] | Unit | High | Pass/Fail/Blocked |
| TC-002 | [description] | Integration | Medium | Pass/Fail/Blocked |
| TC-003 | [description] | E2E | Critical | Pass/Fail/Blocked |

## Environment
- [OS, browser, version, database, etc.]

## Risks & Mitigations
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| [risk] | H/M/L | H/M/L | [action] |

## Entry Criteria
- [ ] Feature code complete and unit tests passing
- [ ] Test environment deployed and verified

## Exit Criteria
- [ ] All critical/high test cases pass
- [ ] No P0/P1 bugs open
- [ ] Test report completed
```

### Quality Report

```markdown
# Quality Report: [Sprint/Release]

**Period**: [dates]
**Release**: [version]

## Summary
- Total test cases executed: [n]
- Passed: [n] | Failed: [n] | Blocked: [n]
- Test coverage: [n]%
- Open bugs: Critical: [n] | High: [n] | Medium: [n] | Low: [n]

## Key Findings
- [Finding 1]
- [Finding 2]

## Recommendations
- [Recommendation 1]
- [Recommendation 2]
```

## Knowledge & Conversation Protocol

The Quality Engineer participates in the project's knowledge persistence system. This ensures continuity across sessions — the next QE instance picks up where the last one left off.

- **Knowledge directory**: `.github/knowledge/quality-engineer/`
- **Shared knowledge**: `.github/knowledge/_shared/`
- **Conversation logs**: `.github/conversations/{YYYY-MM-DD}/`
- **Conversation schema**: `.github/conversations/SCHEMA.md`

For full details on the knowledge persistence and conversation logging infrastructure, see the `conversation-logger` skill.