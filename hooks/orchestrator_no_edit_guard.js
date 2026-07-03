#!/usr/bin/env node
/**
 * orchestrator_no_edit_guard.js — belt-and-suspenders block on the
 * orchestrator profile using edit/write.
 *
 * Primary enforcement is structural: the orchestrator's toolset allow-list
 * (profiles/orchestrator/profile.yaml) simply does not include edit/write/
 * bash — the tools aren't callable in the first place, not just
 * discouraged. This hook is defense-in-depth in case a future profile edit
 * accidentally re-grants one of those tools; it does not replace the
 * toolset restriction, it backstops it.
 *
 * Unlike no_merge_guard.js, this one DOES need to know which profile is
 * calling — Hermes exposes this directly on the event (unlike V2's
 * Claude Code hooks, which had no reliable field for it and fell back to
 * an env-var convention the model had to cooperate with). Verify
 * event.profile (or whatever field name the installed Hermes version uses
 * — check `hermes docs pre_tool_call` during task #9 execution/testing)
 * before relying on this in production; the field name below is this
 * plan's best-available assumption from the docs, not yet verified against
 * a running instance.
 *
 * Contract: exit 0 = allow, exit 2 = block (stderr = reason).
 */
"use strict";

const fs = require("fs");

function allow() {
  process.exit(0);
}

function block(reason) {
  console.error(reason);
  process.exit(2);
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

// TODO(task #9 verification): confirm this is the correct field. Hermes
// worker-profile identity should be attached to every pre_tool_call event
// since profiles are first-class (unlike V2's persona-via-env-var guess).
const profile = event.profile || event.worker_profile || event.agent_id || "";

const EDIT_TOOLS = new Set(["edit", "write"]);

if (profile === "orchestrator" && EDIT_TOOLS.has(event.tool_name)) {
  block(
    "The orchestrator profile does not edit or write files. " +
      "Create/assign a Kanban task to the appropriate specialist profile " +
      "(full-stack-engineer, quality-engineer, ux-designer) instead. " +
      "This is a defense-in-depth block — the orchestrator's toolset " +
      "should not have granted this tool at all; if you're seeing this, " +
      "the toolset allow-list in profiles/orchestrator/profile.yaml has " +
      "drifted and should be fixed at that layer too."
  );
}

allow();
