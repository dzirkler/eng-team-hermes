---
pluginSource: sdd-engineering-team
name: speckit-expert
description: 'Expert on GitHub Spec Kit (github/spec-kit) — the open-source Spec-Driven Development toolkit. Use when: working with speckit commands (speckit.specify, speckit.plan, speckit.tasks, speckit.implement, speckit.clarify, speckit.analyze, speckit.checklist, speckit.constitution, speckit.taskstoissues); understanding SDD methodology; creating or reviewing specs, plans, or tasks; initializing a specify project; troubleshooting Specify CLI; choosing extensions or presets; explaining spec-driven development concepts.'
argument-hint: 'Describe what you need: e.g. "explain the SDD workflow", "help with speckit.plan", "troubleshoot specify init"'
user-invocable: true
---

# Spec Kit Expert

Expert guidance on GitHub's [Spec Kit](https://github.com/github/spec-kit) — the open-source toolkit for **Spec-Driven Development (SDD)**. SDD inverts traditional development: specifications become executable artifacts that generate working implementations rather than just guiding them.

## When to Use

- Running or explaining any `/speckit.*` slash command
- Creating, reviewing, or debugging spec artifacts (`spec.md`, `plan.md`, `tasks.md`, `data-model.md`, `contracts/`, `quickstart.md`, `research.md`)
- Initializing a project with `specify init`
- Understanding the SDD methodology and philosophy
- Choosing or configuring extensions and presets
- Troubleshooting Specify CLI issues
- Writing or updating a project constitution
- Converting tasks to GitHub issues (`speckit.taskstoissues`)

## The SDD Workflow

The workflow follows a strict sequence. Each step builds on the previous one's output.

```
idea → constitution → specify → clarify → plan → tasks → analyze → implement
```

### Step-by-Step Process

| Step | Command | Input | Output | Location |
|------|---------|-------|--------|----------|
| 0 | `speckit.constitution` | Project principles | `memory/constitution.md` | Project root |
| 1 | `specify init` | Project name + agent | `.specify/` config, agent integration files | Project root |
| 2 | `speckit.specify` | Feature description (WHAT & WHY) | `spec.md` with user stories, acceptance criteria | `specs/{NNN-name}/` |
| 3 | `speckit.clarify` | Existing `spec.md` | Refined `spec.md` (resolves `[NEEDS CLARIFICATION]` markers) | Same spec dir |
| 4 | `speckit.plan` | `spec.md` + tech stack (HOW) | `plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md` | Same spec dir |
| 5 | `speckit.tasks` | `plan.md` + design docs | `tasks.md` with dependency-ordered, parallelizable tasks | Same spec dir |
| 6 | `speckit.analyze` | All artifacts | Cross-artifact consistency & coverage report | Console/stdout |
| 7 | `speckit.checklist` | All artifacts | Custom quality checklist | Console/stdout |
| 8 | `speckit.implement` | `tasks.md` | Working code (executes all tasks) | Source tree |
| 9 | `speckit.taskstoissues` | `tasks.md` | GitHub issues in the repo | GitHub |

## Spec Directory Structure

Every feature creates a numbered directory:

```
specs/{NNN-feature-name}/
├── spec.md          # Feature specification (from speckit.specify)
├── plan.md          # Implementation plan (from speckit.plan)
├── tasks.md         # Task list (from speckit.tasks)
├── research.md      # Technical research (from speckit.plan)
├── data-model.md    # Data schemas (from speckit.plan)
├── quickstart.md    # Validation scenarios (from speckit.plan)
├── contracts/       # API/interface contracts (from speckit.plan)
└── checklists/      # Quality checklists (from speckit.checklist)
```

## Key Principles to Enforce

### Spec vs Plan Separation
- **spec.md** = WHAT and WHY (user-facing, technology-agnostic)
- **plan.md** = HOW (tech stack, architecture, file-level detail)
- Never mix these — spec must remain implementable with any technology

### Quality Markers
- `[NEEDS CLARIFICATION]` — must be resolved before `speckit.plan`
- No speculative or "might need" features
- Every requirement traces to an acceptance scenario
- All user stories are independently testable

### Constitutional Gates
The plan must pass constitutional compliance checks before tasks can be generated. Common gates:
- Using ≤3 projects (simplicity)
- Using framework directly, no unnecessary wrappers (anti-abstraction)
- Contracts defined before implementation (test-first)
- No future-proofing

## Specify CLI Reference

### Installation
```bash
# Requires uv (https://docs.astral.sh/uv/)
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@vX.Y.Z
```

### Common Commands
```bash
specify init <project-name> --integration <agent>   # Initialize project
specify integration list                             # List supported agents
specify extension search                             # Browse extensions
specify extension add <name>                         # Install extension
specify preset search                                # Browse presets
specify preset add <name>                            # Install preset
```

### Supported Agents (30+)
Copilot, Claude, Cursor, Windsurf, Codex, Augment, Aider, Cline, Continue, and more.
Run `specify integration list` for the full list.

## Extensions vs Presets

| Need | Use |
|------|-----|
| New command or workflow | Extension |
| Customize spec/plan/task format | Preset |
| Integrate external tool | Extension |
| Enforce organizational standards | Preset |

Priority resolution (highest → lowest):
1. Project-local overrides (`.specify/templates/overrides/`)
2. Presets (`.specify/presets/templates/`)
3. Extensions (`.specify/extensions/templates/`)
4. Spec Kit Core defaults

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `specify` command not found | Run `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.8.17` |
| Slash commands not appearing | Run `specify init` with correct `--integration` flag; check agent's command directory |
| Templates not applying | Check priority: overrides > presets > extensions > core |
| `[NEEDS CLARIFICATION]` in output | Run `speckit.clarify` to resolve before proceeding to `speckit.plan` |
| Tasks missing parallel markers | Ensure `speckit.tasks` has access to `plan.md` and `contracts/` |

## Anti-Patterns to Avoid

1. **Skipping clarify** — unresolved ambiguities propagate into code
2. **Tech details in spec** — spec must be technology-agnostic
3. **Monolithic tasks** — tasks should be small, independently testable units
4. **Skipping analyze** — cross-artifact consistency catches contradictions early
5. **Editing generated code without updating spec** — spec is source of truth
6. **Overriding templates without understanding priority** — can break the workflow

## Resources

- [GitHub Repository](https://github.com/github/spec-kit) — source code, issues, releases
- [Documentation Site](https://github.github.io/spec-kit/) — full reference docs
- [SDD Methodology](https://github.com/github/spec-kit/blob/main/spec-driven.md) — deep dive into the philosophy
- [Community Extensions](https://github.github.io/spec-kit/community/extensions.html) — browse available extensions
- [Community Presets](https://github.github.io/spec-kit/community/presets.html) — browse available presets