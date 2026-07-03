#!/usr/bin/env node
/**
 * no_merge_guard.js — unconditional pre_tool_call veto on PR-merge mutations.
 *
 * Ported from the intent of D:\code\eng-team-plugin\scripts\no-op-guard.js,
 * but structurally different in one important way: the V2 hook was
 * best-effort (relied on the calling persona self-reporting via
 * SDD_PERSONA env / event.session?.persona, and fell back to ALLOW when it
 * couldn't tell who was calling). This hook does not read or care about
 * which profile issued the call — it fires on the tool_input content alone.
 * That closes the exact gap that caused the PR #172 incident (see
 * orchestrator profile.md): the rule lived only in prose before, and a
 * model that "forgot" the rule had nothing mechanical stopping it.
 *
 * Contract (VERIFIED against https://hermes-agent.nousresearch.com/docs/user-guide/features/hooks,
 * 2026-07-02 — this differs from V2's Claude Code hook contract, which used
 * exit codes; that assumption was wrong and is corrected here):
 *
 *   Hermes shell hooks receive a JSON event on stdin:
 *     {"hook_event_name": "pre_tool_call", "tool_name": ..., "tool_input": {...},
 *      "session_id": ..., "cwd": ..., "extra": {"task_id": ..., "tool_call_id": ...}}
 *
 *   To BLOCK, print JSON to stdout (either shape is accepted):
 *     {"action": "block", "message": "<reason>"}      <- used here (Hermes-canonical)
 *     {"decision": "block", "reason": "<reason>"}      <- Claude-Code-style, also accepted
 *
 *   To ALLOW: print nothing meaningful (or any non-block JSON) to stdout.
 *   Exit code is NOT the mechanism — non-zero exit / malformed JSON / timeout
 *   all just log a warning and are treated as a no-op, NOT a block. Do not
 *   rely on process.exit(2) the way V2's no-op-guard.js did; it would
 *   silently fail open here.
 *
 * Declared in config.yaml under hooks.pre_tool_call — see config/config.yaml.
 */
"use strict";

const fs = require("fs");

function allow() {
  // No output = no block directive = allow. Exiting 0 explicitly for
  // clarity, but per the contract above, exit code plays no role.
  process.exit(0);
}

function block(reason) {
  process.stdout.write(JSON.stringify({ action: "block", message: reason }));
  process.exit(0); // exit code is irrelevant to the block decision — see contract note above
}

let rawStdin = "";
try {
  rawStdin = fs.readFileSync(0, "utf8");
} catch (e) {
  // No stdin — not running under the hook runtime (e.g. standalone test
  // invocation). Nothing to inspect, so allow.
  allow();
}

let event = {};
try {
  event = JSON.parse(rawStdin || "{}");
} catch (e) {
  // Malformed event JSON. Can't inspect tool_input, so nothing to match
  // against — allow, but this state is worth investigating if seen
  // frequently (Hermes itself logs a warning on malformed hook output;
  // this is the inbound side, worth the same suspicion).
  allow();
}

const toolName = event.tool_name || "";
const toolInput = event.tool_input || {};

// Only bash-style tool calls carry a shell command string worth matching.
// Also check any MCP github tool name directly, independent of tool_input
// shape, since a merge/close mutation there isn't expressed as a shell
// command at all.
const MERGE_MCP_PATTERN = /mcp_github(_mcp_se)?_(merge|mergepr|close)/i;

if (MERGE_MCP_PATTERN.test(toolName)) {
  block(
    "Merge/close authorization belongs to the human owner. " +
      "This tool call (" +
      toolName +
      ") is a forbidden PR merge/close mutation. " +
      "The team's authorization ends at `gh pr ready` (draft -> ready-for-review). " +
      "The human approver merges via the GitHub UI themselves."
  );
}

const command =
  typeof toolInput.command === "string"
    ? toolInput.command
    : Array.isArray(toolInput.command)
    ? toolInput.command.join(" ")
    : "";

// Matches: gh pr merge [N] [--merge|--squash|--rebase|--delete-branch ...]
// in any argument order, plus gh pr close as the audit-trail-equivalent
// mutation (closing without merging still bypasses the human decision
// point if used to force a re-open/re-merge cycle).
const GH_MERGE_PATTERN = /\bgh\s+pr\s+(merge|close)\b/i;

if (command && GH_MERGE_PATTERN.test(command)) {
  block(
    "Merge authorization belongs to the human owner. " +
      "`gh pr merge` / `gh pr close` are forbidden, unconditionally, " +
      "regardless of which worker profile issued this call. " +
      "Use `gh pr ready` instead — that converts draft to ready-for-review " +
      "without merging. The human approver merges via the GitHub UI " +
      "themselves once they've smoke-tested."
  );
}

allow();
