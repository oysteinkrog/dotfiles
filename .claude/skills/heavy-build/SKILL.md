---
name: heavy-build
description: >-
  How to run builds and tests on this machine through heavy-build. Use before the
  first build or test in a session (cargo, dotnet, build.sh, build.cmd,
  tools/wine/run-tests.sh, localbuild build, cmake, ninja), before running Wine
  tests or starting a headless MotionCatalyst, when heavy-build waits, refuses or
  exits 75, 76, 77, 124 or 137, when a build must outlive a tool call, when choosing
  HEAVY_BUILD_PRIORITY, when setting up a Wine prefix for a lane, and when writing a
  subagent prompt that builds.
---

# heavy-build

heavy-build admits each build when it fits the machine's memory and CPU budget, runs it
in its own memory-capped systemd scope, and logs it. This skill is the working
procedure. `heavy-build --help` has the full admission rules.

## 1. What to wrap

Wrap every heavy build or test: `cargo build`, `test`, `check`, `clippy` and `doc`;
`dotnet build` and `test`; `build.sh`, `build.cmd`, `tools/wine/run-tests.sh`;
`localbuild build`, cmake and ninja.

```bash
heavy-build cargo test -p mux --lib
```

A script that calls heavy-build for each of its steps must not itself run under
heavy-build. Inside a build scope, a nested heavy-build runs its command straight away,
with no admission and no estimate of its own.

Stress tests, benchmarks and canaries go through heavy-build too, or through
`systemd-run --user --slice=builds.slice -p CPUQuota=800% ...` with a quota that fits the
job. Never use a bare `systemd-run --user`: it puts the job in app.slice next to
Oystein's apps. On 2026-10-22 a bare systemd-run y-cruncher run used 32 threads, pushed
the load to about 700 and made the UI lag. The `systemd-run-slice-guard.sh` hook warns
when a slice is missing.

## 2. Exit codes

| Code | Meaning | What to do |
|---|---|---|
| the command's own | The build ran | Read its output |
| 75 | Not run: waited 7200 s without moving up in line, or less than 60 GiB free disk | Do not resubmit at once. Try later or tell the manager session. For low disk, stop and tell Oystein or the manager session, and never delete other sessions' build output |
| 76 | Not run: the same command failed twice in a row within 30 min and the git tree did not change | Read the last log and change something first. Set `HEAVY_BUILD_ALLOW_RERUN=1` only when the change is outside the tree (prefix, environment) |
| 77 | Not run: your `--wait-timeout` ran out | Decide whether to wait longer. Nothing started |
| 124 | Stopped by `HEAVY_BUILD_TIMEOUT` or `HEAVY_BUILD_WINE_ORPHAN=stop` | Read the log. Raise the timeout only with a reason |
| 137 | OOM kill | Retry once, then tell the manager session |
| 70 | heavy-build was replaced while your build ran | Run it again |

For 75, 76 and 77, read the last `heavy-build:` line and follow it. Never resubmit in a
loop. Never cancel a waiting build to resubmit it: it goes to the back of the line.

## 3. Long builds

Never run heavy-build as a Claude background shell (`run_in_background`) when the build
can wait in line or take more than 10 minutes. Claude Code kills background shells when
memory runs low, and the build and its place in line are lost.

`heavy-build --detach` is planned but not shipped yet. Until it is, start the build as
its own systemd user unit and wait with a `Monitor` until-loop on the exit file:

```bash
d=/var/tmp/claude/<task>; mkdir -p "$d"; rm -f "$d/run.exit"
systemd-run --user --unit=hb-<task>-$$ --collect --same-dir --quiet -E PATH -E HOME \
  bash -c 'heavy-build "$@" > "$0.log" 2>&1; echo $? > "$0.exit"' "$d/run" <cmd> <args>
# then wait until "$d/run.exit" exists; the build log is "$d/run.log"
```

- Add `-E AgentOutputSuffix` or `-E WINEPREFIX` only when that variable is set. An unset
  one arrives in the unit as an empty string, not as unset.
- To cancel, `systemctl --user stop hb-<task>-<pid>`. A stopped unit writes no exit file.
- Under `systemd-run`, heavy-build cannot find the calling Claude session, so a
  `critical` or `low` priority that comes from your session is lost. A `critical`
  priority that comes from a grove lane still works, because the working directory is
  in the lane.

Tested on 2026-10-20: the unit kept the working directory and PATH, reached the
heavy-build queue and logged its wait lines, and a plain command wrote its exit code
to the exit file.

## 4. The test loop

1. Reproduce the failure with the narrowest filter: one project and
   `--filter FullyQualifiedName~Fixture.Test`.
2. Fix it, then rerun that same filter.
3. When it passes, run the full suite once.

Use `run-tests.sh --no-build` only to rerun tests when no code changed since the last
build (17 s against 111 s for a small fixture). A test that fails sometimes and passes
sometimes is a flaky test. In the monorepo it gets a Jira bug before any rerun (root
`CLAUDE.md`, "Build & Test"). Do not rerun it until it goes green.

## 5. Incremental builds

Never add `--no-incremental`, `-t:Rebuild` or a `clean` step to a normal build. Each one
forces a full rebuild of the project and all its dependencies. Do a clean build once,
and only when an incremental build gives a result you cannot explain.

Never pass `--no-dependencies` to `dotnet build` or `dotnet test` in the monorepo. It
risks stale DLLs. For parallel .NET builds in one checkout, use `AgentOutputSuffix`
(monorepo `docs/dev/recovery.md`).

## 6. Parallel builds of one tree

Do not start a second build of the same tree while one waits or runs. heavy-build makes
it wait anyway, on the same lock key. Do not build after each small edit when the next
test run builds anyway: `build.cmd test`, `build.sh test` and `run-tests.sh` all build
first.

## 7. Chained steps

Give each build or test step its own heavy-build call. Estimates, the rerun guard and
lock keys all work per command, so `heavy-build sh -c 'cargo build && cargo test'`
hides the second step. `heavy-build bash -c 'cd sub && cargo test'` is one step and is
fine.

## 8. Wine prefixes

- Leave `WINEPREFIX` unset when you run `tools/wine/run-tests.sh`. It then uses its own
  prefix copy per worktree and `AgentOutputSuffix`.
- Never run it in a shell that sourced `wine-env.sh`. That sets the shared prefix, and
  every lane that does so waits on the same lock key.
- For a prefix of your own, name it
  `~/.local/share/wineprefixes/motioncatalyst-tests-<tag>`, and `wine-env.sh` clones it
  from the shared prefix. Or copy it yourself:
  `cp -a --reflink=always ~/.local/share/wineprefixes/motioncatalyst <path>`.
- Never let Wine make a fresh prefix. It lacks the `windows.storage.applicationdata`
  override from `setup-prefix.sh`, and every SQLite test then fails in setup.
- Two lanes never share one prefix.

Headless MotionCatalyst has its own rules for display, prefix and memory: load the
`headless-app-ui` skill. Start a headless MC through
`heavy-build --class app-run [--ready-file PATH] [--wait-timeout S] -- <cmd>`.

## 9. Priority

Leave `HEAVY_BUILD_PRIORITY` unset.

- `high` only for a P0 bug or the last local check before a PR, with
  `HEAVY_BUILD_REASON` set. At most 2 high builds run at once.
- `low` for builds that can wait.
- `critical` comes from `~/.config/machine/sessions.toml` (a critical session, or a
  grove lane it owns or works in). It cannot be set by hand.

## 10. Subagent prompts

A subagent prompt that builds must say "use `heavy-build` and load the `heavy-build`
skill". Do not copy the old `flock ... systemd-run ...` line into prompts.

## 11. Where to look

- `heavy-build --help`: the full admission rules, lock keys and environment variables.
- `~/.local/state/heavy-build/live.log`: every admission decision.
- `~/.local/state/heavy-build/history.tsv`: one line per finished build (column 4 is
  wall seconds, not the exit code).
- Limits: up to 6 builds and 28 cores at once. All builds share `builds.slice`, with
  `MemoryHigh=32G` and `MemoryMax=42G`. Each build gets its own scope with MemoryHigh
  16G to 22G from its estimate (it slows down there), MemoryMax twice that but no more
  than 42G, and MemorySwapMax 8G. An OOM kills only that build.
- Admission uses real use (since 2026-10-22, `HEAVY_BUILD_REAL_USE=1`). The slice-cap
  check takes what builds.slice holds now (memory.current) plus the memory young
  builds may still take. A build is young for its first 2 min or 70% of its expected
  wall time, whichever is longer. The cores check takes what builds.slice used over
  the last 30 to 120 s plus the full estimate of each build in its first 2 min. The
  memory reserve is 5 GiB (`HEAVY_BUILD_MEM_RESERVE_GIB` in `~/.config/heavy-build.conf`,
  6 before). Waits now read like "slice-cap: needs 6.0 GiB; builds.slice uses 19.3
  GiB and running builds may take 4.1 more, of the 32.0 GiB cap" or "cores: needs
  8.0, 22.0 of 28 in use (builds.slice used 12.0 over the last 30 s, plus 10.0 for
  builds that started recently)". `HEAVY_BUILD_REAL_USE=0` in the conf file brings back
  the old rule, which charged every build its full estimate.
- The slice-cap check leaves out page cache the kernel can drop at once (`inactive_file`
  in builds.slice `memory.stat`), and the wait reason then says "(4.0 GiB inactive cache
  not counted)". `HEAVY_BUILD_SLICE_EXCLUDE_INACTIVE_FILE=0` in the conf file counts all
  of memory.current again.
- A filtered Wine test run whose tests have fewer than 5 runs is estimated from the
  class p75 (logged as `mem=class-p75`, p90 before 2026-10-22). Set
  `HEAVY_BUILD_WINE_FALLBACK_PCT` in the conf file to change it.
- Pressure level: heavy-build reads `~/.local/state/pressure/level` from the
  pressure coordinator. At `slow` it spaces new normal and low builds: one per 30 s
  while MemAvailable is above 16 GiB, one per 120 s at or below. At `pause` it starts
  none. High and critical builds are not held by either level. The live.log reason
  names the free memory and the gap, for example "pressure: level slow, 23.0 GiB free,
  one new build per 30 s". The settings are `HEAVY_BUILD_SLOW_FAST_GAP_SECS`,
  `HEAVY_BUILD_SLOW_FAST_MIN_GIB` and `HEAVY_BUILD_SLOW_GAP_SECS` in
  `~/.config/heavy-build.conf`. A notice hook tells sessions the level before each Bash
  call.
