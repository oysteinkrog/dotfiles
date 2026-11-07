---
name: job-system
description: How builds and tests run through jobd, the job queue that replaced heavy-build's own queue on the office and home desktops, and how to run a job on another machine with `job run --on`. Use before a build or test that must outlive a tool call (`job submit --detach`), when a job waits, exits 75, 76, 77 or 124, when you need the queue or a job's log, when `job ping` fails, and before running anything on the home desktop or the lab PC (trd-lab-pc, formerly Hawk) as a worker.
---

# job-system (jobd and jobw)

On the office desktop, jobd runs every build and test. `heavy-build` still is
the command you call: with `HEAVY_BUILD_BACKEND=jobd` set (it is, for every
agent shell on this machine, in `~/.claude/settings.local.json`), heavy-build
hands the command to jobd. So the `heavy-build` skill still applies: what to
wrap, exit codes, priority, Wine prefixes, the test loop.

jobd uses heavy-build's admission rules, priorities and lanes file, and gives
the job the same build environment and memory limits. Each job runs as its own
unit, `job-<attempt>.service`, in `builds.slice`.

jobd runs on both desktops (home since 2026-10-29). Each sends routed jobs to
the other one: the office to `home`, home to `office` (`JOBD_PEER`). Home cannot
reach the lab PC, which is on the office LAN.

Code and design: `~/projects/job-system` (README.md has the full command table)
and `/var/tmp/claude/job-system/DESIGN.md`.

## 1. Normal builds and tests

```bash
heavy-build cargo test -p mux --lib
```

Nothing changes for you. If jobd does not answer, heavy-build prints one
warning line and uses its own queue, so a build never fails because jobd is
down.

## 2. Long builds: `job submit --detach`

This replaces the `systemd-run ... heavy-build` wrapper in the heavy-build
skill. The job runs in its own unit, so a Claude background shell that dies
does not stop it.

```bash
job submit --detach -- tools/wine/run-tests.sh SwingCatalyst.Test.Unit.Core
# prints: <request id> <log file> <exit file>
job wait <request id>     # follow the output; returns the job's exit code
```

**After a detached submit, end the turn or do other work. Do not poll.** The
`job-wake` hook (`~/.claude/hooks/job-wake.py`) watches the exit file and wakes
the session when the job ends, with the exit code, the `jobd:` footer and, on
failure, the last 20 log lines. It needs `job submit --detach` in its own
foreground Bash call (not `run_in_background`), one job per call; it wakes at
the first failure and gives up after 3 h. The wake always goes to the main
session: a subagent that submits gets no wake itself, so a subagent should
return the job id and let its parent wait. Plain `claude -p` gets no wake;
there, use `job wait <id>`. Run `job submit` from the directory the build needs, as with
heavy-build. `--class app-run`, `--ready-file` and `--wait-timeout` work as in
heavy-build. A wrapper script that runs Wine or MC on its own prefix must
declare it with `HEAVY_BUILD_WINE_PREFIX=<prefix path>` in the submit environment, or
it takes the shared prefix's lock key and blocks other Wine jobs (heavy-build skill,
section 8).

## 3. Killed clients

If a `job submit` client is killed (SIGKILL, a dead tool call) while its job
waits, the job keeps its place in line. Run the same command again from the
same directory: it attaches to the waiting job instead of starting a second
one. A client stopped with SIGTERM or Ctrl-C cancels its job (exit 130).

## 4. Commands

| Command | What it does |
|---|---|
| `job submit [--detach] -- CMD` | Queue CMD and wait for it (or return at once with `--detach`) |
| `job wait ID` | Follow a request and return its exit code |
| `job cancel ID` | Cancel your own waiting or running request (exit 130) |
| `job queue` | Waiting and running requests, as JSON |
| `job estimate ID GIB` | Operator only: set a waiting job's memory estimate when a class estimate blocks the queue. It keeps its place |
| `job ping` | Exit 0 if jobd answers within 3 s, else 69 |
| `job report [--hours N]` | Faults, lost jobs and jobs run twice in the last N hours (exit 1 if any) |
| `job status [home\|trd-lab-pc]` | A worker's memory, load, frozen state and running jobs |

Cancel only your own requests. Exit codes are heavy-build's: 75 not run (gave
up waiting, or jobd went away while it waited), 76 rerun guard, 77
`--wait-timeout`, 124 `HEAVY_BUILD_TIMEOUT`, 130 cancelled. jobd adds 78
replaced: your session submitted the same argv with the same lock key while
this job still waited, so the newer request runs it. Do not retry on 78.

A job estimated at 10 s or less (`wall=` in its submit line) is interactive:
it skips the line and starts at once while fewer than 3 such jobs run, its
lock key is free, the pressure level is not `pause` and memory allows. It is
charged 1 GiB and 1 core. The `JOBD_INTERACTIVE_*` settings are in the README.

### GPU memory (VRAM)

jobd charges each job the VRAM its command used before (the 90th percentile of
its past runs). A job that starts must leave 4 GiB of VRAM free for the
desktop. Tell jobd what your job needs:

- A job that does not use the GPU: pass `--est-vram 0` to `job submit`. It is
  then charged no VRAM. For a job that is not MotionCatalyst,
  `CUDA_VISIBLE_DEVICES=-1` does the same.
- **MotionCatalyst under Wine: never set `CUDA_VISIBLE_DEVICES=-1`.** MC
  crashes at startup with it (vkCreateDevice exception 0xc0000005, seen
  2026-11-06). For an MC run that does no GPU work, use `--est-vram 0`.
- A GPU job that knows its need: `--est-vram <GiB>`, for example
  `job submit --class app-run --est-vram 6 -- <cmd>`. jobd charges that value
  in place of the history. If an earlier run of the same command declared the
  same or less and used more, jobd charges that run's real peak instead.
  `events.log` shows `event=vram-peak declared_gib= peak_gib= over=1` when a
  run used more than it declared.

## 5. Logs

| File | Contents |
|---|---|
| `~/.local/state/jobd/logs/<id>.log` | The job's own output |
| `~/.local/state/jobd/live.log` | Admission decisions, in heavy-build's live.log format |
| `~/.local/state/jobd/events.log` | Submits, starts, ends, jobd restarts, errors, slow passes |
| `~/.local/state/jobd/history.tsv` | One row per finished job (heavy-build's 14 columns) |

## 6. Jobs jobd sends to the home desktop

Since 2026-10-28 jobd sends some waiting jobs to the home desktop on its own.
You see the same output and exit code as at the office. A job goes home when
all of these hold:

- It is a self-contained test run: `cargo test`, `check`, `clippy` or
  `nextest`, `dotnet test`, or `tools/wine/run-tests.sh` (once home has its
  Wine test prefix), without `--no-build`. Builds never go: their output would
  stay on home.
- Normal priority, not app-run, and it has waited 60 s at the office.
- Home has 8 GiB or more free and is not frozen, and runs no other routed job.
- `job check` accepts the tree.

To keep a job at the office, set `JOB_LOCAL=1` in its environment. If home
cannot take a job, it goes back in line at the office. events.log marks a
routed start with `worker=home`.

## 7. Running a job on another machine yourself

`job run --on home -- CMD` sends the current git tree to a worker, runs CMD
there and brings back the log. `job check DIR` says first whether the tree can
move. Rules, all hard:

- Workers: `home` and `office` (the desktops, each the other's worker) and
  `trd-lab-pc` (the lab PC, renamed from Hawk on 2026-11-05; `hawk` still works as
  an alias for now). rigel and vega are not approved.
- No job may read golf take files or athlete data on a worker.
- Lab PC: on weekends and weekday nights, use it freely when Laben is not
  booked, without asking Oystein (Oystein, 2026-11-07). Weekdays 07:00 to 18:00
  still need his yes for each run (`--lab-ok` records that he said yes). Never
  run during a Laben booking (`job status trd-lab-pc` shows it; never pass
  `--force`). Never overlap someone's testing on the lab PC.
- Home: its guard holds jobs back while the machine is busy (`frozen` in
  `job status home`). That is normal; do not work around it.
- Forward environment variables with `-e NAME`, never a secret.

## 8. When something is wrong

- `job ping` exits 69: `systemctl --user status jobd`. It is an enabled user
  unit (`~/.dotfiles/.config/systemd/user/jobd.service`). Restarting it is
  safe: running jobs carry on and jobd adopts them. Do not stop it to "clear"
  the queue.
- A job waits long: read its last line in `~/.local/state/jobd/live.log`; the
  reason uses heavy-build's wording.
- Tell the job-system session (agent mail, or a cross-session message) about a
  fault, with the request id.
