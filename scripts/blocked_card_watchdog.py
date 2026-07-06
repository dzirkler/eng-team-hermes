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
    --deliver discord --name blocked-card-watchdog "every 5m"

`--no-agent` means Hermes runs this script directly and delivers its stdout
verbatim — no LLM turn, no tool-calling loop, zero added cost per tick.
Empty stdout = cron delivers nothing (documented contract), so this only
speaks up when there's a genuinely NEW, human-relevant blocked card since
the last tick.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

STATE_FILE = Path(__file__).parent / ".blocked-alert-state.json"

# kind="dependency" blocks are routine "waiting on parents" state, not a
# human decision point (per docs/ARCHITECTURE-OVERVIEW.md — only
# needs_input/capability reach a human). Don't page Damon for these.
SILENT_BLOCK_KINDS = {"dependency"}


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

    alert_lines: list[str] = []
    for t in blocked:
        if t["id"] not in new_ids:
            continue
        kind, reason = describe_block(t["id"])
        if kind in SILENT_BLOCK_KINDS:
            continue
        alert_lines.append(f"⚠️ {t['id']}  @{t['assignee']}  {t['title']}")
        if reason:
            alert_lines.append(f"   {reason}")
        else:
            alert_lines.append("   (no reason found — check `hermes kanban log <id>`)")

    if alert_lines:
        print("New blocked Kanban card(s) — needs your attention:\n" + "\n".join(alert_lines))

    # Drop cleared cards from state (so a future re-block on the same id
    # alerts again) but keep everything still blocked (so it isn't
    # re-announced on every tick).
    save_alerted(current_ids)
    return 0


if __name__ == "__main__":
    sys.exit(main())
