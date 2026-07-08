# Proposal — Getting Discord reactions to reach the orchestrator profile

**Status:** Researched only, **not yet approved to build**. This answers "is it
feasible" and "what would it take," not "how should reactions be used" — that's
a separate decision once the plumbing question is settled.

**Date:** 2026-07-08
**Owner:** Damon Zirkler

---

## 1. Problem

Today, reacting to a message in a Hermes-managed Discord thread is a dead end.
Confirmed by direct investigation of this repo plus Hermes's own docs:

- Hermes's Discord adapter uses emoji reactions **outbound only** — it adds
  👀 (processing), ✅ (done), ❌ (error) to its own messages as status
  indicators (`discord.reactions` / `DISCORD_REACTIONS`, default `true`,
  <https://hermes-agent.nousresearch.com/docs/user-guide/messaging/discord>).
- The checkpoint/approval flow that exists today (`profiles/orchestrator/SOUL.md:169-194`)
  is entirely text-based: Damon replies with an `@mention`, the orchestrator
  is re-invoked, and interprets the reply text ("approved," "go ahead,"
  "ship it" → `kanban_unblock`; anything else → `kanban_comment`).
- There is no inbound reaction listener anywhere — not in this repo (no
  webhook, poller, or hook script receives Discord events at all; the gateway
  is opaque, running inside the vendored `nousresearch/hermes-agent` image
  via `command: gateway run`, `docker-compose.yml:2-6`) and not in Hermes
  itself as currently released.

So the honest starting point is: this isn't a config flag we're missing, it's
a feature Hermes's Discord adapter doesn't have yet.

## 2. Upstream state (nousresearch/hermes-agent)

Checked the actual gateway source repo, since the binary we run is opaque
from inside this repo. Good news: this is a recognized, actively-discussed
gap, not something we'd be first to hit.

- **[#46855 — "Discord inbound reactions as confirmation/input signals"](https://github.com/NousResearch/hermes-agent/issues/46855)**
  (open). This is close to word-for-word our ask: reacting ✅/❌ on a pending
  Hermes message should route as an approve/deny signal, same as typing it.
  Explicitly scoped to respect `DISCORD_ALLOWED_USERS` and ignore
  bot/unrelated-message reactions.
- **[#8379 — "feat(gateway): add inbound reaction event routing for Discord"](https://github.com/NousResearch/hermes-agent/pull/8379)**
  (open PR, **already implemented and tested**). This is the actual
  plumbing: adds `on_raw_reaction_add`/`on_raw_reaction_remove` listeners to
  the Discord adapter, filters bot-self/unauthorized/non-bot-message
  reactions, and emits a synthetic text event (`reaction:added:👍` /
  `reaction:removed:👍`) through the *same* message pipeline normal text
  goes through. Reuses the existing `DISCORD_REACTIONS` toggle — no new
  config surface. Small (2 files, +381/-1), 21 passing tests covering the
  exact edge cases that matter (self-reactions, unauthorized users, stale
  messages, DM vs. guild, uncached channels). Last updated 2026-07-07 —
  actively touched as of yesterday. Labeled `P3`, no milestone, no reviews
  yet — real, but not on a committed release timeline.
- **[#21893 — "reaction-based option selection for clarify tool"](https://github.com/NousResearch/hermes-agent/issues/21893)**
  (open, design sketch only, no PR) — the natural next layer once #8379
  lands: 👍/👎 and 1️⃣–4️⃣ reactions to answer the `clarify` tool's
  multiple-choice prompts instead of typing a number.
  Cross-referenced under umbrella **[#503 — "Platform-Native Rich Interactions"](https://github.com/NousResearch/hermes-agent/issues/503)**
  (closed — broader vision doc for buttons/menus/reactions across all
  platforms; superseded by the smaller, scoped issues above, not evidence
  the idea was rejected).

Net: the hard part — actually getting a reaction to become an event the
gateway routes through the normal pipeline — is written and tested. It just
hasn't merged or shipped in a release.

## 3. What "reaching the orchestrator" actually requires

Two independent pieces, one theirs and one ours:

**Upstream (gateway):** #8379 needs to land in a released
`nousresearch/hermes-agent` image. As of this writing that's not on a
committed timeline (P3, unreviewed).

**Ours (prompt):** Once inbound reactions exist as synthetic text events
(`reaction:added:✅` etc.), the orchestrator needs to be told what they mean.
This is a `profiles/orchestrator/SOUL.md` edit, not new code — extend the
existing checkpoint-interpretation instructions (SOUL.md:169-194) to
recognize `reaction:added:✅`/`👍` as equivalent to an explicit-approval
reply, and `❌`/`👎` as equivalent to rejection, alongside the existing
free-text interpretation. Cheap once the upstream half exists.

## 4. Options

### 4a. Wait for upstream merge — lowest effort, no timeline control
Do nothing until #8379 (or a successor) ships in a tagged
`nousresearch/hermes-agent` release, then bump `HERMES_IMAGE_TAG` and make
the SOUL.md edit from §3. Zero build/maintenance cost, but P3 + unreviewed
means "whenever," not "soon."

### 4b. Build our own patched image off the PR branch — moderate effort, now
The PR (`feat/discord-reaction-events` branch) is small, self-contained, and
already has a real test suite passing. We could fork `nousresearch/hermes-agent`,
cherry-pick that branch, build our own image, and point
`docker-compose.yml`'s `image:` at it instead of upstream `latest`. Gets us
the feature today. Cost: we now own a fork that needs manual rebasing every
time we want to pick up upstream's other changes, until/unless #8379
actually merges upstream (at which point we could drop the fork and go back
to 4a). This is the same build-vs-wait shape as the Copilot CLI proposal's
OpenCode fallback (`docs/temp/Copilot-CLI-Rate-Limit-Mitigation-Proposal.md`
§2c) — a real, working option with an ongoing maintenance tax attached.

### 4c. Bespoke workaround without touching the vendored image — not feasible
Ruled out. Confirmed in investigation: nothing in this repo has any inbound
path to Discord events (no webhook, no poller) to intercept independently of
the gateway binary. There's no side-channel available; it's 4a or 4b or
nothing.

## 5. Recommendation

Lean toward **4a (wait), with 4b as a deliberate escalation** if reactions
turn out to matter enough to justify fork maintenance. Reasoning: this is a
UX/ergonomics improvement on top of a checkpoint flow that already works via
text reply — not a blocked capability. The PR being feature-complete and
tested lowers the risk of 4b if we do pick it up (it's not "write this
ourselves," it's "carry a small, well-tested patch"), but forking a vendor
image we otherwise track at `latest` is a standing cost worth avoiding unless
the ergonomics win is worth it to you.

Worth reacting (no pun intended) to whether you actually want this before
committing either way — see open items below.

## 6. Open items before deciding

- **How would you actually want to use reactions?** Two upstream-sketched
  modes are ready-made if we build on #8379: (a) ✅/❌ on a pending checkpoint
  message as approve/deny (matches #46855, directly extends the existing
  SOUL.md flow), and (b) 👍/👎/numbered reactions to answer `clarify`
  multi-choice prompts (matches #21893, no upstream PR yet — would be
  additional work beyond #8379 alone). Worth deciding which of these (or
  both) is worth having before picking 4a vs. 4b, since 4b's "is it worth
  forking" calculus depends on how much reaction UX you'd actually use.
- If 4b: confirm buildable — the branch is on `NousResearch/hermes-agent`,
  not a fork we own; would need to actually pull and build it against our
  Dockerfile setup to confirm no hidden dependency drift from the `latest`
  tag we currently track.
- If 4a: no action needed beyond periodically checking #8379's status — it's
  quiet (P3, unreviewed) but was touched as recently as 2026-07-07, so it's
  not abandoned.
