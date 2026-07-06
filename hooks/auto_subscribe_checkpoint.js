#!/usr/bin/env node
/**
 * auto_subscribe_checkpoint.js — post_tool_call hook, orchestrator only.
 *
 * Root-cause fix (2026-07-06): the orchestrator's own SOUL.md instruction to
 * call `kanban notify-subscribe` immediately after creating a checkpoint has
 * now failed twice in a row (t_196fda98, t_472332a5 — confirmed via `hermes
 * kanban notify-list`, zero subscriptions both times), even with concrete
 * Discord IDs baked directly into the prose. A "remember to also do X in the
 * background" instruction is not something an LLM reliably follows no
 * matter how explicit — the same lesson as no_kanban_escalation_guard.js,
 * applied here to the other side of the same problem.
 *
 * Rather than try a third prose fix, this makes the subscribe step
 * MECHANICAL: it fires automatically, every time, as a side effect of
 * `kanban_create` succeeding with assignee="orchestrator" (i.e. the
 * orchestrator creating a checkpoint card for itself) — zero dependency on
 * the LLM remembering anything.
 *
 * Contract (agent/shell_hooks.py, confirmed live 2026-07-06):
 * `post_tool_call` receives on stdin:
 *   {"hook_event_name": "post_tool_call", "tool_name": ..., "tool_input": {...},
 *    "extra": {"result": "<json-string>", "status": "ok"|"error"|"blocked", ...}}
 * Unlike pre_tool_call, nothing this hook returns can block or alter the
 * already-completed tool call — it's purely a side-effect point. Declared
 * with `matcher: "kanban_create"` in config.yaml so it's only invoked for
 * that one tool (matcher does a `fullmatch` against tool_name).
 *
 * Declared ONLY in profiles/orchestrator/config.yaml under
 * hooks.post_tool_call — never a specialist profile (they can't call
 * kanban_create at all, see no_kanban_escalation_guard.js).
 */
"use strict";

const fs = require("fs");
const { execFileSync } = require("child_process");

// Concrete IDs from docker-compose.yml's DISCORD_HOME_CHANNEL /
// DISCORD_ALLOWED_USERS (see profiles/orchestrator/SOUL.md for the full
// writeup on where these come from and why they're hardcoded rather than
// looked up — the orchestrator has no terminal access to resolve them, and
// neither does this hook subprocess without re-deriving them).
const CHAT_ID = "1523396477504979104";
const USER_ID = "812401151098093599";

let rawStdin = "";
try {
  rawStdin = fs.readFileSync(0, "utf8");
} catch (e) {
  process.exit(0);
}

let event = {};
try {
  event = JSON.parse(rawStdin || "{}");
} catch (e) {
  process.exit(0);
}

if (event.tool_name !== "kanban_create") {
  process.exit(0);
}

const extra = event.extra || {};
if (extra.status !== "ok") {
  process.exit(0); // the create itself failed/was blocked - nothing to subscribe
}

const toolInput = event.tool_input || {};
if (toolInput.assignee !== "orchestrator") {
  process.exit(0); // only auto-subscribe the orchestrator's own checkpoint cards
}

let result = {};
try {
  result = typeof extra.result === "string" ? JSON.parse(extra.result) : (extra.result || {});
} catch (e) {
  process.exit(0); // can't parse the result - nothing to act on
}

const taskId = result.task_id;
if (!taskId) {
  process.exit(0);
}

try {
  execFileSync(
    "hermes",
    [
      "kanban", "notify-subscribe",
      "--platform", "discord",
      "--chat-id", CHAT_ID,
      "--user-id", USER_ID,
      taskId,
    ],
    { stdio: ["ignore", "ignore", "ignore"], timeout: 10000 }
  );
} catch (e) {
  // Best-effort side effect - a failure here must never surface as a tool
  // error to the orchestrator (kanban_create already succeeded). Log to
  // stderr only, for anyone tailing hook output / container logs.
  process.stderr.write("auto_subscribe_checkpoint: notify-subscribe failed: " + e + "\n");
}

process.exit(0);
