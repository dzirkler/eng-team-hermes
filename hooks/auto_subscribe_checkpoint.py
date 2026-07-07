#!/usr/bin/env python3
"""auto_subscribe_checkpoint.py — post_tool_call hook, orchestrator only.

Root-cause fix (2026-07-06/07): the orchestrator's own SOUL.md instruction to
call `kanban notify-subscribe` after creating a checkpoint failed twice in a
row, even with concrete Discord IDs baked in — replaced by a mechanical
version of this hook (`.js`, first cut). That first cut always subscribed to
the fixed DISCORD_HOME_CHANNEL, which delivers correctly but as a bare
channel message — not into whichever Discord thread the human has actually
been having this feature's conversation in.

Investigated live (2026-07-07) why *some* checkpoints already land in-thread
correctly and others don't: every kanban task records the `session_id` that
created it, and Hermes's own session store (`state.db`) persists that
session's `source`/`chat_id`/`thread_id` permanently. A checkpoint created by
an orchestrator session that was ITSELF triggered by a live Discord message
carries real chat_id/thread_id. A checkpoint created by an autonomous
dispatcher re-spawn (nothing the human said directly triggered it) shows
`source=cli` with no chat/thread at all — confirmed by querying both DBs
directly against two real checkpoints from the same feature.

Fix: walk the new checkpoint's parent chain (task_links) back through its
whole ancestry, and reuse the EARLIEST Discord thread found anywhere in that
lineage — i.e. the thread the feature's conversation actually started in.
Falls back to the fixed home channel only if no such thread exists anywhere
in the ancestry (e.g. a feature that was never kicked off via Discord).

Contract (agent/shell_hooks.py): post_tool_call receives on stdin:
  {"hook_event_name": "post_tool_call", "tool_name": ..., "tool_input": {...},
   "extra": {"result": "<json-string>", "status": "ok"|"error"|"blocked", ...}}
Nothing this hook returns can block or alter the already-completed tool
call — it's purely a side-effect point. Declared with `matcher:
"kanban_create"` in config.yaml so it's only invoked for that one tool.

Declared ONLY in profiles/orchestrator/config.yaml under hooks.post_tool_call
— never a specialist profile (they can't call kanban_create at all, see
no_kanban_escalation_guard.js).
"""
from __future__ import annotations

import json
import subprocess
import sqlite3
import sys

# Concrete IDs from docker-compose.yml's DISCORD_HOME_CHANNEL /
# DISCORD_ALLOWED_USERS (see profiles/orchestrator/SOUL.md for the full
# writeup on where these come from) — fallback only, used when no Discord
# thread is found anywhere in the checkpoint's ancestry.
FALLBACK_CHAT_ID = "1523396477504979104"
USER_ID = "812401151098093599"

KANBAN_DB = "/opt/data/kanban/boards/socialcampaignmanager/kanban.db"
SESSION_DB = "/opt/data/profiles/orchestrator/state.db"


def find_feature_thread(task_id: str) -> tuple[str, str] | None:
    """Return (chat_id, thread_id) of the earliest Discord session anywhere
    in task_id's ancestry, or None if this feature never touched Discord."""
    try:
        kconn = sqlite3.connect(KANBAN_DB)
        rows = kconn.execute(
            """
            WITH RECURSIVE ancestors(id) AS (
                SELECT ?
                UNION
                SELECT tl.parent_id FROM task_links tl
                JOIN ancestors a ON tl.child_id = a.id
            )
            SELECT DISTINCT t.session_id FROM ancestors a
            JOIN tasks t ON t.id = a.id
            WHERE t.session_id IS NOT NULL
            """,
            (task_id,),
        ).fetchall()
        session_ids = [r[0] for r in rows]
        if not session_ids:
            return None

        sconn = sqlite3.connect(SESSION_DB)
        placeholders = ",".join("?" * len(session_ids))
        match = sconn.execute(
            f"""
            SELECT chat_id, thread_id FROM sessions
            WHERE id IN ({placeholders})
              AND source = 'discord'
              AND thread_id IS NOT NULL AND thread_id != ''
            ORDER BY started_at ASC LIMIT 1
            """,
            session_ids,
        ).fetchone()
        return (match[0], match[1]) if match else None
    except Exception as e:
        print(f"auto_subscribe_checkpoint: thread lookup failed: {e}", file=sys.stderr)
        return None


def main() -> int:
    try:
        event = json.loads(sys.stdin.read() or "{}")
    except Exception:
        return 0

    if event.get("tool_name") != "kanban_create":
        return 0

    extra = event.get("extra") or {}
    if extra.get("status") != "ok":
        return 0

    tool_input = event.get("tool_input") or {}
    if tool_input.get("assignee") != "orchestrator":
        return 0

    try:
        result = extra.get("result")
        result = json.loads(result) if isinstance(result, str) else (result or {})
    except Exception:
        return 0

    task_id = result.get("task_id")
    if not task_id:
        return 0

    thread = find_feature_thread(task_id)
    chat_id, thread_id = thread if thread else (FALLBACK_CHAT_ID, None)

    cmd = [
        "hermes", "kanban", "notify-subscribe",
        "--platform", "discord",
        "--chat-id", chat_id,
        "--user-id", USER_ID,
    ]
    if thread_id:
        cmd += ["--thread-id", thread_id]
    cmd.append(task_id)

    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
    except Exception as e:
        print(f"auto_subscribe_checkpoint: notify-subscribe failed: {e}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
