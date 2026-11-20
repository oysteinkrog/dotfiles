---
name: herdr-sessions
description: Find, inspect, freeze and thaw the Claude sessions that run in herdr-core (hc) and the herdr-app window, on the office and home desktops. Use when listing which sessions run where, finding the session in a space or terminal, freezing an idle space to free memory or thawing one, when a manager loop looks for spaces to freeze, when memory is tight because of many idle Claude processes, or when the user says "freeze", "thaw", "park this session", "frozen spaces" or "snowflake".
---

# Herdr sessions: find, freeze, thaw

Every Claude session on both desktops runs in a herdr-core terminal (`hc`), shown in the
herdr-app window. The window groups terminals into spaces and tabs. This skill covers
finding sessions and the Freeze and Thaw feature of Oystein's krog layout.

## Find sessions

```sh
hc ls --json                     # every terminal on both desktops: address, name, agent, cwd, status, where
hc get t13 --json                # one terminal, with labels (herdr.space, herdr.tab, where, herdr.frozen)
herdr-app ls                     # spaces and tabs with ids, and which are active in the window
```

- Addresses like `t13` are on this desktop, `home/t1n` on the home desktop (from the office).
  They change after a reboot. Store space ids and Claude session ids, not addresses or names.
- A Claude session maps to its terminal, space and tab through
  `~/.local/state/claude-persist/sessions/<sid>@<project-dir>.json` (field `.hc`), refreshed
  every 30 s. Each desktop has its own folder.
- `status` is `working`, `blocked` (waiting for the user), `idle`, `done` or `error`.

## Freeze and Thaw

Freeze stops the programs in one space: Claude exits cleanly and the other programs get TERM.
The shells, tabs and the space stay, and nothing is lost. Thaw starts each program again in its
own pane, with Claude resumed through `--resume <session>`. A frozen space keeps a snowflake in
the spaces list and stays frozen across reboots and core restarts until someone thaws it.

This is not the cgroup freeze of `freeze-job.sh`. That one keeps a process in memory, stopped.
Here the programs exit and their memory is freed.

The engine is a script on each desktop:

```sh
F=~/.config/herdr-app/mods/space-freeze/freeze.sh
bash $F plan SPACE           # JSON: each terminal's kind, status, session, resume command, pid
bash $F freeze SPACE [NAME]  # stop the programs, save how to resume them, label the terminals
bash $F thaw SPACE           # start them again, clear the saved state and labels
bash $F list                 # JSON: frozen spaces on this desktop
```

- SPACE is the space id as this desktop's core knows it (`sp…`, without `home/`). Get it from
  a terminal's `herdr.space` label.
- Run it on the desktop that owns the space. For a home space from the office:
  `ssh home 'bash ~/.config/herdr-app/mods/space-freeze/freeze.sh plan SPACE'`.
- Freeze refuses when an agent in the space is `working` or `blocked`.
- State lives in `~/.local/state/space-freeze/<SPACE>.json`. Frozen terminals carry the label
  `herdr.frozen=<kind>`; that label is what the window shows, on both desktops, within a second.
- Oystein can also Freeze and Thaw by right-clicking a space, and hide frozen spaces with the
  snowflake button in the spaces header or `ctrl-alt-h`.

What a freeze loses: anything that lives only in the Claude process. That is a running `/loop`
and its pending wakeup, a `/goal`, background shells and Monitors, and an unanswered question.
Thaw resumes the conversation, not those. So a session that has any of them must not be frozen
by anyone but Oystein.

## Auto-freeze (manager-resources and manager-home)

Oystein, 2026-11-20: idle Claude sessions use too much memory on both desktops, and he wants
spaces he is not using frozen automatically instead of closed, so he can find and resume them
later. manager-resources does this for the office desktop (manager-office is not running) and manager-home for home, as part of
their loop. Each manager only freezes spaces on its own desktop.

A space may be frozen when **all** of these hold:

1. Every terminal in it is either a Claude session or a plain shell (`freeze.sh plan`: `kind`
   is `claude` or `shell`). A space running anything else (a server, a build, a tail, a REPL)
   is skipped.
2. Every Claude in it is `idle` or `done`, and has been for at least **4 hours** (2 hours while
   memory is tight: MemAvailable under 20% of RAM or swap use rising). Measure with the
   transcript's last write time (`.transcript` in the claude-persist entry).
3. Nothing would be lost: for each Claude, `python3 ~/.claude/hooks/claude-persist-resume.py
   <transcript> idle` prints nothing. Any output means a pending `/loop` wakeup, a `/goal`, an
   open question or a cut-off turn, so skip the space.
4. No jobd job from that session is queued or running, and the session has no background
   shell or Monitor still running (child processes of `claude_pid` other than MCP servers).
5. The space is not shown in either herdr-app window right now (`herdr-app ls` on office, and
   `ssh home herdr-app ls`, `active` space), and Oystein has not typed in it for 4 hours.
6. It is not a protected space: the manager-* sessions, agentic-oystein, the session in space
   "herdr mods", and any space with a terminal labelled `herdr.nofreeze=1`
   (`hc label tXX herdr.nofreeze=1` protects it).

How to run it:

- At most 5 freezes per loop tick, one at a time, re-checking `plan` right before each freeze.
- Never thaw automatically. Thaw is Oystein's call.
- Report every freeze in the tick report: space name, the sessions in it, how long they were
  idle, and the memory freed (RSS of the Claude processes before the freeze, from `/proc`).
- If a freeze reports `failed` terminals, leave the space alone and report it.

## Keep a session from being frozen

`hc label <address> herdr.nofreeze=1` on any terminal in the space. Remove with
`hc label <address> herdr.nofreeze=`.
