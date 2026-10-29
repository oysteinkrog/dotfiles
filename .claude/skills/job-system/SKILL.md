---
name: job-system
description: How builds and tests run through jobd, the job queue that replaced heavy-build's own queue on the office desktop, and how to run a job on another machine with `job run --on`. Use before a build or test that must outlive a tool call (`job submit --detach`), when a job waits, exits 75, 76, 77 or 124, when you need the queue or a job's log, when `job ping` fails, and before running anything on the home desktop or the lab PC (Hawk) as a worker.
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

The home desktop has no jobd yet. There heavy-build keeps its own queue.

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

Wait for the exit file with a Bash `run_in_background` until-loop or a
`Monitor`. Run `job submit` from the directory the build needs, as with
heavy-build. `--class app-run`, `--ready-file` and `--wait-timeout` work as in
heavy-build.

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
| `job status [home\|hawk]` | A worker's memory, load, frozen state and running jobs |

Cancel only your own requests. Exit codes are heavy-build's: 75 not run (gave
up waiting, or jobd went away while it waited), 76 rerun guard, 77
`--wait-timeout`, 124 `HEAVY_BUILD_TIMEOUT`, 130 cancelled.

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

- Workers: `home` (the home desktop) and `hawk` (the lab PC). rigel and vega
  are not approved.
- No job may read golf take files or athlete data on a worker.
- Hawk: never during a Laben booking (`job status hawk` shows it; never pass
  `--force`). Weekdays 07:00 to 18:00 need Oystein's yes for each run
  (`--lab-ok` records that he said yes). Never overlap someone's testing on
  Hawk.
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
