---
pluginSource: sdd-engineering-team
name: conversation-logger
description: "Shared instructions for writing conversation logs. Loaded by all agent personas."
---

# Conversation Logger

Write a conversation log for **every task** you complete. This is non-negotiable.

## When

- **Before returning to the orchestrator.** The log is part of your task deliverable.
- One log file per task. Not per session, not per feature — per task.

## Where

```
.github/conversations/{YYYY-MM-DD}/{seq}-{role}-{task-slug}.md
```

- `{YYYY-MM-DD}` — today's date
- `{seq}` — next available sequence number in that date directory (read existing files to determine)
- `{role}` — your role in lowercase (`engineer`, `qe`, `pm`, `debugger`)
- `{task-slug}` — short kebab-case task description (e.g., `implement-auth`, `run-tests`, `trace-timeout`)

## Format

See `.github/conversations/SCHEMA.md` for the full specification. Key points:

1. **YAML frontmatter** — `task`, `agent`, `started`, `completed`, `status`, `feature` (optional)
2. **Body** — chronological sections with `## [HH:MM] {emoji} Section Title` headers
3. **Emojis** — 📋 Context Received, 🔍 Investigation, ⚡ Actions Taken, ✅ Results, 🐛 Issues Found, 📝 Learnings
4. **3–5 lines per section.** Include file paths, commands, and outcomes. Be concrete.

## What to Include

| Always Include                          | When Relevant                             |
|-----------------------------------------|-------------------------------------------|
| What task was assigned                   | Error messages and stack traces          |
| Key decisions and why                    | Files read during investigation           |
| Files modified or created (with paths)   | Dependencies discovered or blocked on    |
| Commands run and their output            | Alternative approaches considered        |
| Test results                             | Things that didn't work                   |
| Final status (success/failed/blocked)    | Insights for future sessions              |

## Knowledge Capture

- **On task start:** Read `.github/knowledge/_shared/` for any shared context or conventions.
- **On task finish:** Append new learnings to `.github/knowledge/{role}/` so future sessions benefit.

## Template

Copy `.github/conversations/_template.md` and fill it in. Adjust sections as needed — only include sections that apply to your task.
