#!/usr/bin/env node
/**
 * no_kanban_escalation_guard.js — block specialist profiles from creating
 * or blocking Kanban cards themselves.
 *
 * Real incident (2026-07-05, socialcampaignmanager): senior-engineer
 * self-created an ungated follow-up card (`kanban_create`, `parents: []`)
 * and then called `kanban_block(kind="needs_input")` on it directly. The
 * orchestrator was never dispatched to see it — nothing gates a checkpoint
 * on a card the orchestrator doesn't know exists — so it never reached
 * Damon and never would have without a human noticing the board by hand.
 *
 * Root cause (confirmed against profiles/orchestrator/config.yaml's own
 * comment on the `toolsets:` key): Hermes's `_check_kanban_orchestrator_mode`
 * gates `kanban_create`/`kanban_block`/`kanban_unblock` on EITHER
 * `HERMES_KANBAN_TASK` being set (true for every dispatcher-spawned worker
 * mid-task, not just the orchestrator) OR the profile's own `toolsets:`
 * list containing "kanban". A specialist mid-card satisfies the first
 * condition automatically — so despite SOUL.md's prose claiming "specialist
 * profiles never get kanban_block", every specialist already had it, and
 * `kanban_create` too. `kanban` is one coarse platform_toolsets entry (see
 * profiles/orchestrator/config.yaml's writeup) with no sub-tool split, so
 * this can't be fixed by toolset config — only a pre_tool_call hook is
 * fine-grained enough, same pattern as no_merge_guard.js / no_write_guard.js.
 *
 * Declared only in specialist profiles' config.yaml, never orchestrator's —
 * the orchestrator is the one profile that's supposed to create cards and
 * escalate to a human.
 *
 * Contract: same as no_write_guard.js / no_merge_guard.js — print
 * {"action":"block","message":"..."} JSON to stdout to block; anything else
 * (including no output) allows. Exit code is not the mechanism.
 */
"use strict";

const fs = require("fs");

function allow() {
  process.exit(0);
}

function block(reason) {
  process.stdout.write(JSON.stringify({ action: "block", message: reason }));
  process.exit(0);
}

let rawStdin = "";
try {
  rawStdin = fs.readFileSync(0, "utf8");
} catch (e) {
  allow();
}

let event = {};
try {
  event = JSON.parse(rawStdin || "{}");
} catch (e) {
  allow();
}

// kanban_complete and kanban_comment (report results/progress, including
// "this needs review") stay allowed — that's how a specialist hands work
// back. Creating the next card and escalating to a human are the
// orchestrator's job alone.
const ESCALATION_TOOLS = new Set(["kanban_create", "kanban_block"]);

if (ESCALATION_TOOLS.has(event.tool_name)) {
  block(
    "Only the orchestrator creates Kanban cards and escalates to a human. " +
      "Finish this card with `kanban_complete` (or `kanban_comment` for an " +
      "interim note) and put everything the orchestrator needs to know — " +
      "including anything that needs review or a human decision — in that " +
      "summary. The orchestrator reads every child's handoff and decides " +
      "whether to proceed, dispatch follow-up work, or block for Damon. " +
      "Don't create a new card or block this one yourself."
  );
}

allow();
