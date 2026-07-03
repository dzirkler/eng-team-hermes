#!/usr/bin/env node
/**
 * no_write_guard.js — block file mutations for read-only worker profiles.
 *
 * CONFIRMED DESIGN (2026-07-02, verified against a live container's source
 * at /opt/hermes, not docs):
 *
 * A Kanban "worker profile" IS a real Hermes profile (`hermes profile
 * create <name>`, living at /opt/data/profiles/<name>/ with its own
 * SOUL.md and optional config.yaml). This hook is declared in the
 * config.yaml of every profile that must read files for context but never
 * write them (orchestrator, product-manager, debugger, qa-analyst) — see
 * each profile's config.yaml hooks.pre_tool_call list. It never needs to
 * identify which profile is calling; if it's running, it's already scoped
 * to a read-only profile by construction.
 *
 * There is no fine-grained "toolsets:" allow-list key anywhere in the
 * config schema (confirmed by reading hermes_cli/config.py directly).
 * File operations are one coarse toolset ("file") covering four real
 * registered tool names: read_file, write_file, patch, search_files
 * (see tools/file_tools.py registry.register() calls). Disabling the
 * whole "file" toolset via platform_toolsets would also block reads,
 * which these profiles need for context — so the mutating pair
 * (write_file, patch) can only be excluded via this pre_tool_call hook,
 * not via toolset config. This hook is the primary enforcement for that
 * pair, not a second layer on top of a toolset restriction.
 *
 * Contract (verified against agent/shell_hooks.py): print
 * {"action":"block","message":"..."} JSON to stdout to block; anything
 * else allows. Exit code is not the mechanism.
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

// Real registered tool names for the "file" toolset's mutating operations
// (verified against tools/file_tools.py registry.register() calls).
// read_file and search_files are intentionally excluded — profiles wiring
// this hook still need those to gather context before delegating/reporting.
const WRITE_TOOLS = new Set(["write_file", "patch"]);

if (WRITE_TOOLS.has(event.tool_name)) {
  block(
    "This profile does not edit or write files. Create/assign a Kanban " +
      "task to the appropriate specialist profile instead."
  );
}

allow();
