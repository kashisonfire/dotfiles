#!/usr/bin/env python3
"""Publish Claude Code's per-window state onto the tmux pane it runs in.

Wired to seven Claude Code hooks in ~/.claude/settings.json. Each run writes
pane options, which ~/.tmux.conf renders in the window list:

    @claude_state   busy | done | idle
    @claude_tasks   N     background subagents and workflows still running

State must come from hooks. Claude Code used to animate its OSC 0 title glyph
(◐/◑ busy, ✳ idle), and that was a continuous busy light with no gap. Build
2.1.236 added the gate tengu_static_title_under_mux, on by default, which pins
the glyph to ✳ whenever $TMUX is set. There is no user override for it. The
title now says only "this is a Claude pane", never what the pane is doing.

Hooks announce edges, so one gap is unavoidable: Esc fires no hook, and an
interrupted turn would stay busy for good. Notification closes it. Claude Code
raises idle_prompt after 60s at an idle prompt, so an interrupt self-corrects
within a minute. Other notification types are ignored on purpose: a permission
prompt arrives mid-turn and the turn goes on after it, so the honest state
there is still busy.

The task count comes from the list Claude Code hands the Stop and SubagentStop
hooks, so it is read rather than inferred. Tallying SubagentStart against
SubagentStop looks equivalent and is not: Claude Code runs unannounced internal
agents that emit a SubagentStop with no matching start, so a tally drifts, and a
session killed mid-turn leaks its count for good.

Pane options rather than a state file: they are addressed by pane id, they have
no concurrent writers, and tmux discards them with the pane, so a closed window
cannot leave a stale mark behind.

stdout stays empty on purpose. Claude Code feeds a hook's stdout back into the
session as context.
"""

import json
import os
import subprocess
import sys

# What counts as work worth waiting for. Background *shells* are in the same list
# and deliberately left out: a dev server or a file watcher never finishes, so
# counting them would pin those windows to a permanent mark and cost the mark
# its meaning.
WAITED_ON = ("subagent", "workflow")

# Every entry seen so far is "running" -- Claude Code drops a task from the list
# once it is done rather than restating it with a new status. Matching on "not
# finished" rather than on "running" is the direction that fails safe: an
# unfamiliar status from a later version then reads as work in flight instead of
# quietly reporting an idle window.
FINISHED = ("completed", "complete", "failed", "cancelled", "canceled", "done", "killed")


def live_tasks(payload):
    """Count the background work this session is still waiting on.

    SubagentStop is dispatched before its own agent leaves the list, so the agent
    that just finished is discounted by id or the window keeps showing it. Stop
    carries no agent_id, which makes the same pass correct for both hooks.
    """
    finished_id = payload.get("agent_id")
    n = 0
    for task in payload.get("background_tasks") or []:
        if task.get("type") not in WAITED_ON:
            continue
        if task.get("status") in FINISHED:
            continue
        if finished_id and task.get("id") == finished_id:
            continue
        n += 1
    return n


def options(payload):
    """Return the pane options this event changes, as (name, value) pairs.

    A value of None unsets the option.
    """
    event = payload.get("hook_event_name")

    if event == "SessionStart":
        # Background work does not survive a restart, and a session opening on a
        # pane owns both marks -- including a pane whose previous session was
        # killed before it could clean up after itself.
        return [("@claude_state", "idle"), ("@claude_tasks", "0")]
    if event == "SessionEnd":
        return [("@claude_state", None), ("@claude_tasks", None)]
    if event == "UserPromptSubmit":
        return [("@claude_state", "busy")]
    if event in ("Stop", "StopFailure"):
        return [("@claude_state", "done"), ("@claude_tasks", str(live_tasks(payload)))]
    if event == "SubagentStop":
        return [("@claude_tasks", str(live_tasks(payload)))]
    if event == "Notification" and payload.get("notification_type") == "idle_prompt":
        return [("@claude_state", "done")]
    return []


def main():
    pane = os.environ.get("TMUX_PANE")
    if not pane:
        return

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
        return

    argv = ["tmux"]
    for name, value in options(payload):
        if argv != ["tmux"]:
            argv.append(";")
        if value is None:
            argv += ["set-option", "-p", "-t", pane, "-u", name]
        else:
            argv += ["set-option", "-p", "-t", pane, name, value]
    if argv == ["tmux"]:
        return

    # One invocation for the writes and the redraw, so the bar reflects the
    # change now rather than waiting out status-interval.
    argv += [";", "refresh-client", "-S"]
    try:
        subprocess.run(argv, timeout=5, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        pass


if __name__ == "__main__":
    # A hook that raises is a hook that interrupts the session it is reporting on,
    # and nothing here is worth that.
    try:
        main()
    except Exception:
        pass
