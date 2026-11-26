---
name: herdr-sessions
description: Find, inspect, make, freeze, thaw, wake, kill and revive the Claude sessions that run in herdr-core (hc) and the herdr-app window, on the office and home desktops. Use when listing which sessions run where, finding the session in a space or terminal, making a new space for an agent (which sidebar folder it goes in), freezing an idle space to free memory or thawing one, killing a space (closing it and its worktree, keeping the Claude session) or reviving a killed one, waking a frozen session for one job (space-wake, also when a SendMessage says "not reachable"), when a manager loop looks for spaces to freeze, when memory is tight because of many idle Claude processes, or when the user says "freeze", "thaw", "kill", "revive", "killed spaces", "park this session", "frozen spaces" or "snowflake". Also for scheduled agents: running one now, leaving it an inbox message (agent-inbox), its timers and run log (agent-run, agent-schedule).
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

## Make a new space from an agent

Oystein, 2026-11-23: spaces that agents make kept landing at the bottom of the sidebar,
outside every folder. When you make a space for a new agent or task, choose its sidebar
folder on purpose.

Two kinds of "folder", do not mix them up:

- The **working directory** of its first terminal: `herdr-app do space.new --folder DIR`.
- The **sidebar folder** that groups spaces in the window (Managers, Company, Machine and
  tools, Swing Catalyst, ...). The `space-folders` mod keeps these in
  `~/.config/herdr-space-folders.json` (`list` of folders, `of` maps space id to folder id).
  `space.new` knows nothing about them.

Use `herdr-space-new`, never a bare `herdr-app do space.new`:

```sh
herdr-space-new --name eng-123 --cwd ~/work/desktop/eng-123 --argv '["claude"]' \
  --task "Implement ENG-123"                  # same sidebar folder as your own space
herdr-space-new --name ledger-fix --group "Machine and tools" --cwd ~/src/cass ...
herdr-space-new --name scratch --group none ...    # no folder, only when nothing fits
```

Before you run it, decide:

1. **Which folder.** The default is your own space's folder, and it is right when the new
   space is part of your work (a lane, a helper, a follow-up). Pick another when the new
   work belongs to another area: a manager goes in Managers, monorepo and product work in
   Swing Catalyst, company admin in Company, machine, tool and dotfiles work in Machine and
   tools. `--group bogus` lists the folders that exist. Do not make a new folder; ask
   Oystein if none fits.
2. **A clear name** (`--name`, required). Name the task, not the tool.
3. **Focus.** It stays in the background (`--focus false`) unless Oystein asked to see it.

Say in your report which folder you put it in. The script labels the new space's
terminals `herdr.space-folder=<folder id>` and `herdr.space-after=<your space id>`; the
`space-folders` mod files the space from those labels and puts it under yours. It works on
this computer only for now. For a remote space, use `space.new --machine` and tell Oystein
it needs filing by hand.

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
- Freeze keeps a reflink copy of each Claude transcript in
  `~/.local/state/space-freeze/transcripts/<session>/`, and thaw puts a missing transcript back
  from it. If both are gone, thaw keeps the space frozen and names the session in `errors`.
  Spaces frozen before 2026-11-20 evening get their copy with `bash $F backup SPACE`.
- State lives in `~/.local/state/space-freeze/<SPACE>.json`. Frozen terminals carry the label
  `herdr.frozen=<kind>`; that label is what the window shows, on both desktops, within a second.
- Oystein can also Freeze and Thaw by right-clicking a space, and hide frozen spaces with the
  snowflake button in the spaces header or `ctrl-alt-h`.

What a freeze loses: anything that lives only in the Claude process. That is a running `/loop`
and its pending wakeup, a `/goal`, background shells and Monitors, and an unanswered question.
Thaw resumes the conversation, not those. So a session that has any of them must not be frozen
by anyone but Oystein.

## Wake a frozen session for one job

A SendMessage to a frozen session fails with "not reachable". Do not stop there: wake it.

```sh
space-wake SPACE "Check your hub inbox and answer what is there."
```

`space-wake` thaws the space, labels its terminals `herdr.autothawed=1`, types the job into
its Claude once it is ready, waits until the job is done, and then freezes the space again.
It runs in its own user unit and returns at once. It freezes again only if nobody typed in
the session after the job, the session has no `/loop`, `/goal`, open question, jobd job or
background shell, and the label is still there. Otherwise it leaves the space running and
says why. The log ends with one `result:` line: `~/.local/state/space-wake/<SPACE>.log`.

- Find SPACE with `bash $F list` (the frozen spaces, by name). For a home space, run it there:
  `ssh home space-wake SPACE "..."`.
- Hub messages wait in the server inbox, so "check your hub inbox" is enough for hub mail.
- `--terminal tXX` picks the Claude in a space with more than one; `--max-hours N`
  (default 4) is how long it waits for the job.
- Oystein can take a woken space over at any time: anything he types stops the refreeze.

## Kill and Revive

Kill is the deeper sleep below Freeze (Oystein, 2026-11-25). A frozen space keeps its shells,
tabs and worktree. A killed space keeps only what brings the work back: each Claude session
(the transcript stays forever), the space's name, sidebar folder and tab names, and each
worktree's repo, branch and commit. The space closes with its shells.

```sh
space-kill kill SPACE [--dry-run]   # Oystein's kill; also for an agent he asked
space-revive SPACE                  # back: worktree, saved changes, a new space, Claude resumed
space-killed                        # JSON: the killed spaces on this desktop
space-kill drain                    # removes queued worktrees; its timer runs at 22:40
```

- A linked worktree (grove lane or plain `git worktree`) is not removed at once. It waits in a
  queue that `space-kill-drain.timer` empties at 22:40, one at a time under
  `/var/tmp/claude/grove-delete.lock`, because grove deletes stall the disk by day. The branch
  always stays, local and remote. A main checkout (`~`, `~/work/ifkb`) is never removed, and
  neither is a worktree another space's terminal uses.
- Oystein's kill saves uncommitted changes, untracked files too, as a commit on
  `refs/space-kill/<SPACE>/<lane>`, and pins HEAD on `refs/space-kill/<SPACE>/<lane>-head`.
  Gitignored files (build output, a local `.env`) are not saved.
- Revive before 22:40 just reopens the worktree that is still there. After it, the worktree
  comes back at the same path on the same branch, so `claude --resume` finds the transcript,
  and the saved changes are put back.
- Kill refuses what Freeze refuses (an agent working or blocked) and also a `/loop`, `/goal`,
  open question or jobd job, and the protected spaces listed under Auto-freeze.
- State: `~/.local/state/space-kill/` (one record per killed space, `queue/`, and
  `history.jsonl`, which is never cleared).
- Run it on the desktop that owns the space: `ssh home space-kill kill SPACE` for home.
- In herdr-app (krog and krog-next): right-click a space and pick "Kill space…" (it asks once,
  and counts as Oystein's own kill). An "N killed" row under the spaces list opens the Killed
  list (name, folder, when, by whom) with Revive. Both are helm parts (`kill`, `killed`).

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
7. No terminal in it has `herdr.autothawed=1`. That space belongs to a running `space-wake`,
   which freezes it again itself; leave it alone.

How to run it:

- At most 5 freezes per loop tick, one at a time, re-checking `plan` right before each freeze.
- Never thaw automatically. Thaw is Oystein's call.
- Report every freeze in the tick report: space name, the sessions in it, how long they were
  idle, and the memory freed (RSS of the Claude processes before the freeze, from `/proc`).
- If a freeze reports `failed` terminals, leave the space alone and report it.

Auto-kill (Oystein, 2026-11-25): the same managers may kill a space on their own desktop that
has been frozen for 14 days or more: `space-kill kill SPACE --by <manager name>`. The script
refuses a younger freeze, and a worktree with uncommitted changes or unpushed commits; then
tell the session's owner, or Oystein, to commit or push. Report every kill in the tick report:
space name, sessions, how long it was frozen, the worktrees queued for removal.

## Keep a session from being frozen

`hc label <address> herdr.nofreeze=1` on any terminal in the space. Remove with
`hc label <address> herdr.nofreeze=`.

## Which Chrome profile a link opens

Ctrl-click on a web link in a herdr-app terminal opens Chrome through the `chrome-profile` mod
(dotfiles `setup/herdr/files/mods/chrome-profile`):

1. The terminal's label `herdr.browser=work` or `herdr.browser=personal` wins.
2. Otherwise the machine that runs the terminal: a home terminal opens the personal profile,
   an office terminal the work profile.

Chrome opens on the desktop whose window was clicked, through `~/.local/bin/chrome-work` or
`chrome-personal`. Set the label only when a session's links belong to the other profile, for
example personal work in an office session: `hc label <address> herdr.browser=personal`.
Remove it with `hc label <address> herdr.browser=`.

## Scheduled agents

Some long-running agents do not stay alive. They run on a schedule, as a fresh Claude
session in their own space, and end after one round of their loop (since 2026-11-26, first
manager-security). Their memory is a working state file plus an ee store, not the
conversation. The full description is in the life repo, `agents/README.md`, "Scheduled agents".

```sh
agent-schedule list                         # scheduled agents on this desktop, next run, last result
agent-inbox NAME "text" --from ME           # leave a message for its next run
agent-inbox NAME "text" --from ME --urgent  # start a run now, or tell the run that is going
agent-run NAME --why "by hand"              # start one run now
agent-schedule sync                         # rewrite the timers after a Runs: line changed
```

- Never freeze a scheduled agent's space, and never thaw-resume its old session: that loads
  the whole old context again. Its terminal is a shell between runs; that is normal.
- SendMessage cannot reach it between runs. Use `agent-inbox`.
- Its run log is `~/.local/share/agents/NAME/runs.log`. A run that stayed open says why
  (someone typed in it, questions for Oystein, something still running).

Status for the herdr window: `agent-run` sets labels on the agent's terminal.
- `herdr.agent`: the agent's name.
- `herdr.agent-state`: `running`, `open` (left open after a run; read `herdr.agent-last-result`) or `waiting` (between runs).
- `herdr.agent-next-run` and `herdr.agent-run-started`: times as `YYYY-MM-DD HH:MM`.
- `herdr.agent-last-result`: the time and the last line of the run log.

`agent-schedule list --json` prints one JSON line per scheduled agent. Fields: `agent`, `space`, `terminal`, `schedule`, `next_run`, `running`, `inbox_items`, `last_result`, `state_file`, `log`.

In the herdr window (space-folders and space-freeze mods, 2026-11-26), a scheduled space shows
a tag after its name: `running`, `open`, or the next run (`⏲ 17:00`, `⏲ fri 08:00`). Its
right-click menu has "Run agent now" in place of Freeze and Thaw.
