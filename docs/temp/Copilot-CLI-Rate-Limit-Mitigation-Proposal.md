# Proposal — Copilot CLI as delegated task-executor for Z.AI rate-limit mitigation

**Status:** Researched and recommended, **not yet approved to build**. Damon wants
this on record before deciding when to pick it up. No config/container changes
have been made as of this writing.

**Date:** 2026-07-07
**Owner:** Damon Zirkler

---

## 1. Problem

Every Hermes profile currently runs `model.provider: zai` (see
`profiles/*/config.yaml`), routed through the team's LiteLLM proxy
(`https://litellm.home.zirkler.com/v1`) to Z.AI's GLM Coding Plan endpoint.
100% of Hermes's model traffic depends on that one pool.

Z.AI explicitly deprioritizes Hermes's traffic. Confirmed against Z.AI's own
docs (<https://docs.z.ai/devpack/tool/others>), fetched live 2026-07-07:

- **First-class "Coding Agent Tools"** (full support, no stated restrictions):
  Claude Code, Claude for IDE, OpenCode, Cursor, Cline, TRAE, Qoder, Droid,
  Kilo Code, Roo Code, Crush, Goose, Eigent.
- **"General-purpose Agent Tools," explicit best-effort tier**: OpenClaw,
  **Hermes Agent**, SillyTavern. Quoted from the page: *"will continue to be
  served on a best-effort basis. Under high inference load (typically around
  2–6 PM Singapore time, though this may shift), some requests may face
  temporary rate limits."*

Hermes Agent is named, by product name, in the second-class bucket. This is
root-caused, not inferred: it's client/tool identification, not a
concurrency or burst-pattern issue (ruled out — Damon confirmed running two
VS Code teams concurrently on distinct repos against the same upstream
key/endpoint with no rate limits, which a concurrency-based theory can't
explain).

This is distinct from the **5-hour rolling-window quota** every account
shares — that one isn't addressed by anything in this note; the only fix for
it is waiting out the window. This proposal is only about the
second-class-citizen deprioritization.

Note also (self-correction from earlier in this exploration): GitHub
Copilot, in any form (VS Code extension or CLI), does **not** appear on
Z.AI's list at all — not in either tier. That earlier read this as a risk
("unlisted could mean untested/worse treatment"). Damon's own production
history overrides that speculation: he ran real work through Copilot CLI for
an extended period and never hit this rate limit. Working theory: Z.AI's
deprioritization logic only fires on the three explicitly-named
general-purpose tools; being invisible to that classifier means the
throttle never triggers, rather than triggering worse. This is empirically
evidenced, not just theorized, but it is also **incidental, not a documented
guarantee** the way OpenCode's first-class listing is — Z.AI could start
fingerprinting Copilot CLI specifically in the future without notice. Worth
periodically re-checking that page.

## 2. Options considered

### 2a. Hermes's built-in `copilot` model provider — rejected
Hermes ships a real, separate `copilot` inference provider (`hermes_cli/auth.py`,
confirmed live, auth via `GITHUB_TOKEN`/`GH_TOKEN`) that would call GitHub
Copilot's own backend models directly. Rejected because Damon does not want
Copilot's native models — the goal is Copilot CLI's own harness/tooling
quality (its "glue"), still pointed at the team's own LiteLLM/GLM backend via
BYOK, not a model swap.

### 2b. Full Copilot CLI as an alternate runtime replacing Hermes — rejected
Hermes provides Kanban dispatch, force-loaded SpecKit skills (the actual
enforcement mechanism for SDD adherence — see `docs/ARCHITECTURE-OVERVIEW.md`
§4), hooks, holographic memory, checkpoint/blocked-card flow, Discord gateway.
None of that exists in Copilot CLI. Replacing the runtime wholesale means
rebuilding all of it. Not worth it for a rate-limit problem.

### 2c. OpenCode (via LiteLLM) instead of Copilot CLI — considered, deprioritized
OpenCode is explicitly first-class on Z.AI's list (a documented guarantee,
not incidental), has a native LiteLLM integration
(<https://docs.litellm.ai/docs/tutorials/opencode_integration>), and a real
declarative permission system (`opencode.json`: `permission.task` glob rules,
`allow`/`ask`/`deny`, `doom_loop: deny`, `external_directory: deny` — see
<https://opencode.ai/docs/agents/>, <https://opencode.ai/docs/config/>).

Initially favored for lower friction and zero rate-limit uncertainty. Walked
back after a key correction from Damon: V1 (OpenWork harness, running
OpenCode underneath), V2 (VS Code/Copilot/Copilot CLI), and V3 (Hermes) all
ran **the same orchestration style/design** — only the harness changed. V1
still underperformed at parallel-subagent coordination and rule-following
*despite* having the same orchestration scaffolding V2/V3 have. That rules
out the theory that OpenCode's weakness was an artifact of missing
Hermes-style top-level orchestration (and would therefore disappear once
Hermes does the coordinating instead). It's a harness-quality property of
OpenCode itself, and there's no strong reason to expect it not to resurface
here. Kept as a documented fallback (see §5) given its rate-limit posture is
the more durable, explicit one of the two options — worth revisiting if
Copilot CLI's incidental protection ever regresses.

### 2d. Copilot CLI as a delegated per-card task executor — **recommended**
Hermes stays the orchestrator (Kanban, skills, hooks, memory, checkpoints).
Copilot CLI is invoked non-interactively, per already-scoped card, as one
more tool in a profile's toolbox — not a runtime replacement. Wins on both
axes that matter here: proven output quality/rule-following across three of
Damon's own team generations, and real (if incidental) evidence of dodging
the exact rate-limit problem this note exists to solve.

## 3. Recommended approach (2d), concrete shape

**BYOK wiring** — Copilot CLI supports pointing at any OpenAI-compatible
endpoint via env vars (confirmed:
<https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/use-byok-models>):

```
COPILOT_PROVIDER_BASE_URL=https://litellm.home.zirkler.com/v1
COPILOT_MODEL=<litellm model alias, e.g. glm-5.2-coding-max>
COPILOT_PROVIDER_API_KEY=<a LiteLLM virtual key, ideally separate from GLM_API_KEY>
```

Requirement: model must support tool-calling + streaming (128k+ context
recommended). GLM-5.2/4.7 already clear this bar and this repo has already
proven tool-calling/`reasoning_content` streaming works cleanly through this
exact LiteLLM instance (`docs/temp/V3-Supplement-Model-and-Key-Binding.md` §9).

**Non-interactive invocation** — `copilot -p "<prompt>" --allow-tool=... -s`
is GitHub's documented automation path, not a hack
(<https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/run-cli-programmatically>).

**Auth for the terminal subprocess** — Copilot CLI checks
`COPILOT_GITHUB_TOKEN` → `GH_TOKEN` → `GITHUB_TOKEN` → OS keychain, in that
order (<https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/authenticate-copilot-cli>).
Note this repo's `terminal.env_passthrough` unconditionally blocklists
`GITHUB_TOKEN`/`GH_TOKEN` specifically because those names collide with
Hermes's own built-in `copilot` provider credential vars (see
`profiles/senior-engineer/config.yaml` for the full incident writeup).
`COPILOT_GITHUB_TOKEN` is a different name and not the name that collision
is about — plausible clean passthrough path, but **needs live verification**
before relying on it; this specific BYOK flow doesn't actually need this
token for the model calls (that's what `COPILOT_PROVIDER_API_KEY` is for) —
it would only matter if Copilot CLI still phones home to GitHub for
licensing/telemetry even in BYOK mode (undocumented; `COPILOT_OFFLINE=true`
exists to suppress this but only guarantees isolation if the model provider
is also local/in the same isolated network).

**Guardrails** — Hermes's `pre_tool_call` hooks (`no_merge_guard.js`,
`no_write_guard.js`) cannot see inside an opaque `copilot -p` subprocess.
Real guardrail equivalent: `.github/agents/*.agent.md` custom agent files —
YAML frontmatter with an explicit `tools:` allowlist, enforced by Copilot CLI
itself, and Copilot is hard-blocked from editing its own `.github/agents/`
directory (tamper-resistant by design). Source material already exists and
is battle-tested: `D:\code\eng-team-plugin\agents\*.agent.md` (the V2 Claude
Code plugin repo) has real incident-driven hardline rules — e.g. the
"never `gh pr merge`/`gh pr close`" rule (spec-023 incident) and "never
hand-author SDD artifacts, always delegate to `speckit.<stage>`" rule
(spec-028 incident) in `senior-engineer.agent.md`. This needs **translation**,
not a drop-in port — V2's format is Claude Code's plugin subagent schema
(`agents:` delegation lists, `{{MODEL_FLAGSHIP}}` templating), not Copilot
CLI's actual `.github/agents/` schema.

**`/fleet` mode** — real, decomposes a prompt into parallel subagent
subtasks (<https://docs.github.com/en/copilot/concepts/agents/copilot-cli/fleet>).
No documented concurrency cap — GitHub's own docs warn it "may cause more
AI Credits to be consumed" from independent per-subagent LLM calls. Gate its
use to genuinely parallelizable multi-file work, not every card; don't
enable it blanket.

**Two-tier LiteLLM key split** — keep Hermes's own native profile calls
(orchestrator dispatch, coordination — low volume, latency-sensitive) on a
**commercial, pay-per-token** LiteLLM/Z.AI key rather than the Coding Plan,
since that traffic is permanently second-class per Z.AI's own docs
regardless of what else changes here, and its volume is low enough that
per-token cost is trivial. Route Copilot CLI's bulk implement-phase work
through its own **separate** Coding Plan key (prepaid, appropriate for
high-volume work, and the one actually avoiding the deprioritization per §1).

**Cost consciousness** — Copilot CLI/`/fleet` traffic through the Coding Plan
key is metered per-token (unlike Hermes's own current prepaid-and-idle
capacity), and fleet's fan-out is explicitly uncapped by GitHub's own
admission. Put a LiteLLM spend alert/cap on the new Copilot virtual key
before any broad rollout.

## 4. Pilot scope, when this is picked up

Start narrow: `implementation-engineer` profile only (least dependent on
Hermes's own memory/context of the 10 profiles — its well-scoped
Implement-stage tasks are the most "execute this diff" shaped). Dispatch via
`copilot --agent=<translated-guardrail-agent> -p "<task>"`, `/fleet` gated
to multi-file work only. Validate end-to-end on one real card before
considering wider rollout.

## 5. Fallback

If Copilot CLI's incidental rate-limit protection ever regresses (Z.AI
starts fingerprinting it, or adds it to the second-class list), OpenCode
(§2c) is the documented, lower-friction fallback — same LiteLLM-BYOK shape,
explicit first-class Z.AI guarantee instead of an incidental one. Its
weaker rule-following track record is the tradeoff to re-litigate at that
point, not a reason to build it preemptively now.

## 6. Open items before building

- Verify `COPILOT_GITHUB_TOKEN` passthrough live (or confirm it's unneeded
  if BYOK mode never phones home to GitHub at all).
- Confirm whether Copilot CLI's non-interactive mode reports enough
  structured output/exit-code detail for Kanban card status to reflect
  success/failure reliably (not confirmed in research — GitHub's
  programmatic-reference doc wasn't fully accessible during this pass).
- Author and test the translated `.agent.md` guardrail file(s) against a
  throwaway task before wiring into a real Kanban card.
- Confirm LiteLLM virtual-key issuance/spend-cap workflow for the new
  Copilot-specific key.
