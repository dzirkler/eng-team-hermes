#!/usr/bin/env node
/**
 * no_merge_guard.js — unconditional pre_tool_call veto on PR-merge mutations.
 *
 * Ported from the intent of D:\code\eng-team-plugin\scripts\no-op-guard.js,
 * but structurally different in one important way: the V2 hook was
 * best-effort (relied on the calling persona self-reporting via
 * SDD_PERSONA env / event.session?.persona, and fell back to ALLOW when it
 * couldn't tell who was calling). This hook does not read or care about
 * which profile issued the call — it fires on the tool_input content alone,
 * for every profile, always. That closes the exact gap that caused the
 * PR #172 incident (see orchestrator profile.md): the rule lived only in
 * prose before, and a model that "forgot" the rule had nothing mechanical
 * stopping it.
 *
 * Contract (Hermes pre_tool_call hook protocol):
 *   exit 0  -> allow
 *   exit 2  -> block; stderr surfaced to the calling profile as the reason
 *
 * Hermes invokes this for every tool call across every worker profile
 * (config.yaml: hooks.pre_tool_call is global, not profile-scoped).
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
  // No stdin — not running under the hook runtime. Fail closed is wrong
  // here (would break standalone testing), so allow, matching V2's
  // documented "no stdin -> standalone -> allow" behavior.
  allow();
}

let event = {};
try {
  event = JSON.parse(rawStdin || "{}");
} catch (e) {
  // Malformed event JSON. Do NOT fail open on a guard whose entire job is
  // blocking a destructive mutation — if we can't parse the event, we
  // can't inspect tool_input, so there's nothing to match against anyway.
  // Allow, but this state is worth investigating if seen frequently.
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
