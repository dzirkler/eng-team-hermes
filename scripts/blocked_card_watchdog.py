#!/usr/bin/env python3
"""Blocked-card watchdog — a `hermes cron --no-agent` job, deliberately not LLM-driven.

Real incident (2026-07-06, socialcampaignmanager): independent-reviewer's
worker process crashed twice in a row (Z.AI rate-limit, then a hard 401)
without ever calling `kanban_complete` or `kanban_block`. The DISPATCHER's
own "give up after repeated failures" safety net marked the card `blocked`
— not an agent's `kanban_block` call. Nobody was subscribed to that card
(only checkpoint cards get a notify-subscribe wired, and only when the
orchestrator remembers to), and the orchestrator's own downstream
checkpoint can never promote to re-engage it, because it's parent-gated on
the crashed card reaching `done`, which a `blocked` card never does.
Nothing short of a human manually checking the dashboard would ever have
surfaced this.

Second incident, same day: even a LEGITIMATE `kanban_block(kind="needs_input")`
call by the orchestrator itself — its actual intended job — still wasn't
subscribed (`hermes kanban notify-list` showed zero subscriptions, confirmed
twice now). The concrete Discord IDs baked into orchestrator/SOUL.md did not
fix this; the orchestrator just doesn't reliably run the notify-subscribe
step. This watchdog is now the PRIMARY reliable delivery path, not just a
crash-only safety net — so it pulls the actual block reason (not just "a
card is blocked, go look") so Damon gets the decision-relevant content
directly in Discord.

Registered as:
  hermes cron create --script blocked_card_watchdog.py --no-agent \
    --deliver local --name blocked-card-watchdog "every 5m"

`--no-agent` means Hermes runs this script directly. `--deliver local` keeps
stdout in the cron job's own output log (for audit/debugging) WITHOUT also
forwarding it to a platform — this script does its own platform delivery
below, per blocked card, so it can route each alert into the right Discord
thread instead of cron's single static delivery target.

Root-cause fix (2026-07-08): this watchdog was originally registered with
`--deliver discord` (bare, no chat_id/thread_id). That's a single static
target baked into the cron job at registration time — it can't vary per
alert, so EVERY blocked-card alert landed in the fixed home channel no
matter which feature/thread the human was actually discussing it in. This
defeated the thread-aware notify-subscribe fix (auto_subscribe_checkpoint.py)
entirely, since this watchdog fires independently of — and typically faster
than — that subscription path, and is the one that actually wins the race
to Discord. Confirmed live: checkpoint t_c41cd839 ([Spec 022] Checkpoint 3
final) had zero rows in kanban_notify_subs (its owning session's hook
registration was stale, see auto_subscribe_checkpoint.py), yet this
watchdog delivered the full checkpoint text to the home channel at
2026-07-08 00:21:44 regardless — bypassing threading altogether by design,
not just as a side-effect of the stale-hook bug.

Fix: reuse auto_subscribe_checkpoint.py's ancestry-walk (earliest Discord
thread found anywhere in a blocked task's kanban parent chain) and deliver
each alert directly via `hermes send -t discord:<chat_id>:<thread_id>`,
falling back to the bare home channel only when no thread exists anywhere
in that task's lineage.
"""
from __future__ import annotations

import json
import sqlite3
import subprocess
import sys
from pathlib import Path

STATE_FILE = Path(__file__).parent / ".blocked-alert-state.json"

# Same DBs auto_subscribe_checkpoint.py reads — this script also runs under
# the orchestrator profile (see bootstrap.ps1's registration comment).
KANBAN_DB = "/opt/data/kanban/boards/socialcampaignmanager/kanban.db"
SESSION_DB = "/opt/data/profiles/orchestrator/state.db"

# kind="dependency" blocks are routine "waiting on parents" state, not a
# human decision point (per docs/ARCHITECTURE-OVERVIEW.md — only
# needs_input/capability reach a human). Don't page Damon for these.
SILENT_BLOCK_KINDS = {"dependency"}


def find_feature_thread(task_id: str) -> tuple[str, str] | None:
    """Return (chat_id, thread_id) of the earliest Discord session anywhere
    in task_id's ancestry, or None if this feature never touched Discord.

    Duplicated from auto_subscribe_checkpoint.py rather than imported: hooks
    and cron scripts are deployed to separate directories in the container
    (/opt/hooks/ vs each profile's ~/.hermes/scripts/), so there's no shared
    import path between them — see that file's module docstring for the
    full root-cause writeup of why ancestry (not just the task's own
    session) has to be walked.
    """
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
        print(f"blocked_card_watchdog: thread lookup failed: {e}", file=sys.stderr)
        return None


def deliver_target(task_id: str) -> str:
    thread = find_feature_thread(task_id)
    if thread:
        chat_id, thread_id = thread
        return f"discord:{chat_id}:{thread_id}"
    return "discord"


def send(target: str, text: str) -> None:
    try:
        subprocess.run(
            ["hermes", "send", "--to", target, "--quiet", text],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15,
        )
    except Exception as e:
        print(f"blocked_card_watchdog: delivery to {target} failed: {e}", file=sys.stderr)


def load_previously_alerted() -> set[str]:
    if not STATE_FILE.exists():
        return set()
    try:
        return set(json.loads(STATE_FILE.read_text()))
    except Exception:
        return set()


def save_alerted(ids: set[str]) -> None:
    STATE_FILE.write_text(json.dumps(sorted(ids)))


def _run_json(*args: str) -> object | None:
    try:
        result = subprocess.run(
            ["hermes", *args], capture_output=True, text=True, timeout=30, check=True,
        )
        return json.loads(result.stdout or "null")
    except Exception:
        return None


def describe_block(task_id: str) -> tuple[str | None, str | None]:
    """Return (kind, reason) for a blocked task, or (None, None) if unknown.

    Prefers the most recent explicit `blocked` event (a real kanban_block
    call, with a real reason an agent wrote). Falls back to the board's
    diagnostics feed for the dispatcher-crash-giveup case, which has no
    `blocked` event at all — just a `gave_up` transition.
    """
    detail = _run_json("kanban", "show", task_id, "--json")
    if isinstance(detail, dict):
        for event in reversed(detail.get("events") or []):
            if event.get("kind") == "blocked":
                payload = event.get("payload") or {}
                return payload.get("kind"), payload.get("reason")

    diagnostics = _run_json("kanban", "diagnostics", "--task", task_id, "--json")
    if isinstance(diagnostics, list) and diagnostics:
        diag = diagnostics[0]
        reason = None
        if isinstance(diag, dict):
            reason = diag.get("message") or (diag.get("data") or {}).get("last_error")
        return "crash", reason or "worker crashed without completing or blocking — see `hermes kanban log <id>`"

    return None, None


def main() -> int:
    blocked = _run_json("kanban", "list", "--status", "blocked", "--json")
    if not isinstance(blocked, list):
        # Fail silent, not loud: a transient CLI/board hiccup shouldn't page
        # Damon every 5 minutes. A genuine board-connectivity problem will
        # still surface next time someone checks the dashboard directly.
        print("(blocked-card-watchdog: could not read board state, suppressed)", file=sys.stderr)
        return 0

    current_ids = {t["id"] for t in blocked}
    previously_alerted = load_previously_alerted()
    new_ids = current_ids - previously_alerted

    # Group by resolved delivery target rather than one flat digest: each
    # new blocked card can belong to a different feature/thread, and cron's
    # own --deliver is a single static target set at job-registration time
    # — it can't route per-alert, so this script sends each group directly.
    lines_by_target: dict[str, list[str]] = {}
    for t in blocked:
        if t["id"] not in new_ids:
            continue
        kind, reason = describe_block(t["id"])
        if kind in SILENT_BLOCK_KINDS:
            continue
        lines = lines_by_target.setdefault(deliver_target(t["id"]), [])
        lines.append(f"⚠️ {t['id']}  @{t['assignee']}  {t['title']}")
        if reason:
            lines.append(f"   {reason}")
        else:
            lines.append("   (no reason found — check `hermes kanban log <id>`)")

    all_lines: list[str] = []
    for target, lines in lines_by_target.items():
        text = "New blocked Kanban card(s) — needs your attention:\n" + "\n".join(lines)
        send(target, text)
        all_lines.extend(lines)

    if all_lines:
        # Kept for the cron job's own local output log (--deliver local) —
        # not forwarded anywhere; the send() calls above already delivered
        # each group to its actual thread-aware target.
        print("New blocked Kanban card(s) — needs your attention:\n" + "\n".join(all_lines))

    # Drop cleared cards from state (so a future re-block on the same id
    # alerts again) but keep everything still blocked (so it isn't
    # re-announced on every tick).
    save_alerted(current_ids)
    return 0


if __name__ == "__main__":
    sys.exit(main())
