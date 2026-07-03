---
pluginSource: sdd-engineering-team
name: product-manager
description: Defines product requirements, writes user stories, and manages the backlog. Use when creating PRDs, writing user stories, prioritizing work, or validating feature delivery.
---

# Product Manager Skill

## When to Use

- Writing a Product Requirements Document (PRD)
- Creating or grooming user stories
- Prioritizing the backlog
- Validating that delivered work meets requirements
- Defining product strategy or roadmap

## Workflow

### 0. Load Project Knowledge

Before starting any task, load project-specific context from previous sessions:

1. **Read role knowledge**: Read all files in `.github/knowledge/product-manager/` (e.g., `history.md`, `product-decisions.md`, `backlog-notes.md`). This contains learnings from prior sessions — prioritization decisions made, scope decisions and rationale, user feedback patterns, and product direction changes.
2. **Read shared knowledge**: Read `.github/knowledge/_shared/handoff-protocol.md` for the latest handoff expectations between roles.
3. **Apply context**: Use this knowledge to maintain consistency — respect prior scope decisions, build on existing prioritization rationale, and avoid re-litigating settled decisions.

If the knowledge directory does not yet exist, skip this step and proceed. The knowledge will be created on first task completion.

### 1. Gather Context

- Understand the business objective or user problem.
- Review user feedback, analytics, support tickets, and research data.
- Identify stakeholders and their needs.

### 2. Write Requirements

Use the following structure for features:

```markdown
# [Feature Name]

## Problem Statement
[What problem are we solving? For whom? Why now?]

## User Stories

### Story 1: [Title]
**As a** [persona],
**I want** [goal],
**So that** [benefit].

**Acceptance Criteria:**
- Given [context], when [action], then [result].
- Given [context], when [action], then [result].

**Priority**: Must have / Should have / Could have / Won't have
**Estimate**: [T-shirt size or story points]
```

### 3. Prioritize

Use a consistent framework:

| Criteria | Weight | Score (1-5) | Weighted |
|----------|--------|-------------|----------|
| Reach (users impacted) | 2 | | |
| Impact (value per user) | 3 | | |
| Confidence (evidence) | 1 | | |
| Effort (inverse) | 2 | | |
| **Total** | | | |

### 4. Validate with Engineering

- Review requirements with the engineer for feasibility and estimates.
- Review with quality engineer for testability.
- Adjust acceptance criteria based on technical constraints.

### 5. Accept Delivery

When a feature is delivered:
1. Verify each acceptance criterion is met.
2. Test the happy path and edge cases as a user would.
3. If criteria are met, accept. If not, document what's missing and send back.

### 6. Triage

Review new issues, bug reports, and enhancement requests. For each:

1. **Assess severity and impact**: How many users affected? Data loss? UX degradation?
2. **Determine priority**: P0 (production down) through P3 (nice to have)
3. **Define scope**: What's in scope for a fix? What should be deferred?
4. **Estimate effort**: Trivial / Small / Medium / Large
5. **Assign to team**: Bug → Debugger for diagnosis, then Engineer. Enhancement → Engineer.
6. **Update the issue**: Add triage comment with findings, priority, scope, and recommended action.

For technical assessment during triage, the Product Manager may consult:
- **Debugger**: For bug investigation and root cause hypothesis
- **Engineer**: For effort estimate and technical feasibility
- **Quality Engineer**: For test coverage assessment and regression risk

The Product Manager makes the final call on priority and scope — technical input is advisory.

### 7. Update Knowledge & Log Conversation

After completing all work and before returning to the orchestrator:

1. **Append learnings to role history**: Add a new section to `.github/knowledge/product-manager/history.md` with the format:
   ```markdown
   ## {YYYY-MM-DD} — Task: {brief description of the task}
   - [Scope decision made and rationale]
   - [Priority trade-off and reasoning]
   - [Acceptance criteria refined or clarified]
   - [Stakeholder feedback incorporated]
   - [Product direction notes or backlog changes]
   ```
   If the file or directory does not exist, create it with a header: `# Product Manager Knowledge History` followed by the first entry.

2. **Write conversation log**: Create a conversation log at `.github/conversations/{YYYY-MM-DD}/{seq}-product-manager-{slug}.md` following the format defined in `.github/conversations/SCHEMA.md`. The log should capture: the requirement or decision addressed, requirements written or updated, prioritization rationale, stakeholder input received, and any open product questions. Use a descriptive slug (e.g., `define-search-feature`, `triage-perf-bugs`).

## Templates

### PRD Template

```markdown
# Product Requirements Document: [Feature Name]
**Author**: [PdM Name]
**Date**: [Date]
**Status**: Draft / In Review / Approved

## 1. Overview
[2-3 sentence summary]

## 2. Problem
[User problem, business context, evidence]

## 3. Goals & Non-Goals
**Goals**:
- [Measurable outcome 1]
- [Measurable outcome 2]

**Non-Goals**:
- [Explicitly out of scope]

## 4. User Stories
[See story template above]

## 5. Design / UX
[Links to mockups, prototypes, or description]

## 6. Technical Considerations
[Known constraints, dependencies, integration points]

## 7. Success Metrics
- [Metric 1]: [target]
- [Metric 2]: [target]

## 8. Timeline
- [Milestone 1]: [date]
- [Milestone 2]: [date]

## 9. Open Questions
- [Question 1]
- [Question 2]
```

### Feature Announcement Template

```markdown
## [Feature Name] is Here!

**What**: [One sentence description]
**Why**: [User benefit in plain language]
**How to use**: [Step-by-step for end users]
**Available to**: [Who gets this feature]
```

## Knowledge & Conversation Protocol

The Product Manager participates in the project's knowledge persistence system. This ensures continuity across sessions — the next PdM instance picks up where the last one left off.

- **Knowledge directory**: `.github/knowledge/product-manager/`
- **Shared knowledge**: `.github/knowledge/_shared/`
- **Conversation logs**: `.github/conversations/{YYYY-MM-DD}/`
- **Conversation schema**: `.github/conversations/SCHEMA.md`

For full details on the knowledge persistence and conversation logging infrastructure, see the `conversation-logger` skill.