#!/usr/bin/env python3
"""Publish Claude Code's background work count onto the tmux pane it runs in.

Wired to four Claude Code hooks in ~/.claude/settings.json. Each run writes one
pane option, which ~/.tmux.conf renders in the window list:

    @claude_tasks   N   background subagents and workflows still running

Why only that one number. Claude Code publishes an OSC 0 title of
"<glyph> <topic>", and the glyph is a live busy light for the main loop, so
~/.tmux.conf keeps reading busy and idle straight out of it. What the glyph
cannot express is work that outlives the turn which launched it: hand a job to a
background subagent or a workflow, and the turn ends while the job runs on. That
is the one thing this adds.

Busy is deliberately NOT tracked here as well, even though UserPromptSubmit and
Stop look like a matched pair for it. They are not: interrupting a turn with Esc
fires neither, so a "busy" written on UserPromptSubmit would stick to the window
until that session's next turn happened to end, leaving the bar confidently wrong
about a window sitting at an idle prompt. The glyph has no such gap, because
Claude Code re-emits it continuously rather than announcing edges.

The count comes from the list Claude Code hands the Stop and SubagentStop hooks,
so it is read rather than inferred. Tallying SubagentStart against SubagentStop
looks equivalent and is not: Claude Code runs unannounced internal agents that
emit a SubagentStop with no matching start, so a tally drifts, and a session
killed mid-turn leaks its count for good.

Pane options rather than a state file: they are addressed by pane id, they have
no concurrent writers, and tmux discards them with the pane, so a closed window
cannot leave a stale badge behind.

stdout stays empty on purpose. Claude Code feeds a hook's stdout back into the
session as context.
"""

import json
import os
import subprocess
import sys

# What counts as work worth waiting for. Background *shells* are in the same list
# and deliberately left out: a dev server or a file watcher never finishes, so
# counting them would pin those windows to a permanent badge and cost the badge
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


def main():
    pane = os.environ.get("TMUX_PANE")
    if not pane:
        return

    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
        return

    event = payload.get("hook_event_name")

    if event in ("Stop", "SubagentStop"):
        count = str(live_tasks(payload))
    elif event == "SessionStart":
        # Background work does not survive a restart, so a session opening on a
        # pane owns the badge and starts it from zero -- including a pane whose
        # previous session was killed before it could clean up after itself.
        count = "0"
    elif event == "SessionEnd":
        count = None
    else:
        return

    if count is None:
        command = ["set-option", "-p", "-t", pane, "-u", "@claude_tasks"]
    else:
        command = ["set-option", "-p", "-t", pane, "@claude_tasks", count]

    # One invocation for the write and the redraw, so the bar reflects the change
    # now rather than waiting out status-interval.
    argv = ["tmux"] + command + [";", "refresh-client", "-S"]
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
