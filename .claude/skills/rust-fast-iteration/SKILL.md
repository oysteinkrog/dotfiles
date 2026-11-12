---
name: rust-fast-iteration
description: >-
  How to lay out, configure and build a Rust workspace so the edit, check and test
  loop stays fast, with the measured reasons from the tasklens build study
  (2026-11-01). Use when starting or restructuring a Rust workspace, adding or
  splitting a crate, when Rust builds or tests are slow, when adding test hooks or
  feature flags for tests, when editing Cargo profiles or .cargo/config.toml, when
  target/ grows too big, when adding or changing cargo aliases or --target flags,
  when several teams share one Cargo workspace, and when reviewing a Rust PR for
  build cost.
---

# Rust workspaces built for fast iteration

This skill sets one layout and one build setup for every Rust project on this
machine. The numbers come from the tasklens study on 2026-11-01 (13 crates, GPUI
desktop app, one UI crate of 222k source lines plus 141k test lines). Raw logs, while they last:
`/var/tmp/claude/tl-bp-logs/` (`results.txt`, `results2.txt`, `llvm-lines.txt`). Timings were taken on a loaded machine,
so trust the ratios more than the seconds.

Reference files in this folder:

- `cargo-config-template.md`: the Cargo profiles and `.cargo/config.toml` to copy, with a
  comment per line.
- `layout-and-measuring.md`: the crate-layout checklist, the upward-edge check, and the
  edit-loop measuring method with its table.

This skill does not replace `heavy-build` or `job-system`. Every cargo command below
still runs as `heavy-build cargo ...`. Load `heavy-build` before your first build.

## 1. What costs the most

In a 40.8 hour window of tasklens agent lanes (507 jobs, 11.1 h of run time):

| Where the time went | Hours |
|---|---|
| Test-profile compiles, mostly the one big UI crate and its one test binary | 6.14 |
| Test execution | about 2.6 |
| Release and LTO builds inside lanes | about 2.65 (0.83 as release jobs) |
| Dev clippy and check | 1.58 |
| Waiting in the queue | 2.8 (extra) |

49% of jobs failed, and the same command was re-run after a failure 107 times.
Lanes ran workspace clippy 75 times though told not to. So the biggest gains are,
in order: incremental builds, not recompiling the big crate twice per edit, smaller
crates and test binaries, and lane discipline (section 6).

## 2. Workspace layout

### Layers with a one-way rule

Put crates in layers. A crate may depend only on crates in lower layers.

```text
bin crates (thin)        app, cli, helper binaries
feature crates           ui-pages, engine, server
kit / service crates     ui-kit, collectors, storage
base crates              model / types, small and stable
dev-only                 testkit (dev-dependency only)
```

- **A machine check rejects upward edges.** Write it as an `xtask check-deps` that
  reads `cargo metadata` and fails on any direct dependency not in the crate's
  allowed row. tasklens has one (`~/projects/tasklens/xtask/src/check_deps.rs`, rules in
  `docs/ARCHITECTURE.md` ADR-001). Also check source paths inside a big crate:
  an `rg` for `crate::<upper module>::` in lower modules catches cycles before a
  split. `layout-and-measuring.md` has a minimal version.
- **Cycles block splits.** Cargo can only skip work along the dependency graph. tasklens
  had six module cycles inside its UI crate (the foundation reached up into the app
  shell, 46 files called `window::main`), so nothing could be split off without
  untangling first. Cycles inside a crate are free to write and expensive to undo.

### A small, stable model crate

Every crate depends on it, so every edit to it rebuilds the whole graph. tasklens:
an edit in `tl-model` rebuilt 9 crates (141 s at INCR=0). Its two busiest files were
settings types used only by the UI (202 commits to tl-model since 2026-09-01; the
engine used two settings types out of 3.9k lines).

- Keep only shared contracts in it: wire types, IDs, units, traits other crates
  implement.
- **App-only and UI-only settings go in their own crate above the model** (for
  example `ui-settings` depending on `model`). An edit then rebuilds only the UI side.
- No heavy dependencies in it (no GUI toolkit, no runtime).

### Thin binary crates

`main.rs` wires things together and parses arguments. Logic lives in libraries.
A thin binary relinks in seconds; logic in the binary crate cannot be tested
without building the binary.

### Crate size

These are rules of thumb from this study, not hard limits:

- **Split when** one crate takes over about 30 s of the warm edit loop, passes
  about 50k lines, or holds areas that are edited separately. tasklens's UI crate
  (222k lines) cost 95 s per cold compile and about 50 s of LLVM time per edit.
- **Split by what changes together**, not by file type. tasklens's planned split was
  12 UI crates of 6k to 44k lines each, so a widget edit rebuilds a 25k-line kit
  instead of 2 x 222k plus a 141k-line test binary.
- **Too many crates costs too.** Each crate adds metadata, a link step for each test
  binary, and per-crate overhead on clean builds. The study estimated that past
  about 12 crates for one app, clean builds slow down (inferred, not measured). Do
  not split below about 5k lines unless the crate exists to stop a rebuild cascade.
- Big single crates on this machine for contrast: `cass-gpu` (636k lines, one
  crate) and `frankenterm-core` (1.37M lines in one crate of a 33-crate workspace).
  Both pay the full crate cost on every edit. `agent-hub` (16 crates plus a
  testkit) and `grove` (one 17k-line crate) are sized well.

### Test binaries and the testkit

- Each crate has its own `tests/` with a few test binaries. Never one giant
  integration test binary for the whole app. tasklens's `tests/ui` was one binary of
  79 modules and 140.7k lines (366 MB); any edit to any test file relinked all of it
  (37 s for a new test function at INCR=1).
- A shared `testkit` crate (dev-dependency only, about 1k lines) holds fakes and
  harness code. Keep it small: every test binary depends on it.
- Most UI tests need a small page host, not the full app shell. In tasklens, 39 of
  78 test files booted the full shell; the rest did not need it.
- `cargo test -p X` compiles the library twice: once normally for `tests/*.rs`, once
  under `cfg(test)` for unit tests. In big crates keep `#[cfg(test)]` modules small,
  and run `--lib` or `--test <name>` to build only the one you need.

## 3. Test hooks and features

**Never add a feature that changes a library between `cargo build` and `cargo test`.**

Cargo builds each feature set as a separate copy. tasklens gated test hooks on
`feature = "test-hooks"` (822 gates in 94 files), enabled through a
dev-dependency. So each edit compiled the UI crate twice: once for the app build,
once for tests, about 120 s each at INCR=0.

Do this instead, in order of preference:

1. **`cfg(debug_assertions)`** for hooks that are cheap to keep in all debug
   builds. `cargo build`, `check` and `test` then see the same code. Use
   `cfg(any(debug_assertions, feature = "test-hooks"))` if a release test run must
   also reach them.
2. **One always-on dev feature set.** If a feature must exist, every dev command uses
   it. Put the commands in `.cargo/config.toml` aliases (`cargo t`, `cargo c`, `cargo
   b`) so nobody types the flags by hand.
3. Never let a dev-dependency turn on a feature of a normal dependency. GPUI's
   `test-support` came in as a dev-dependency feature, so app builds and test builds
   compiled the whole GPUI stack in two variants. Either enable it in the normal
   dependency in all dev builds, or keep it out.

**Keep one package set for dev commands.** The resolver unifies features per package
selection. In tasklens, about 25 dependencies resolved to different feature sets for
`-p tl-engine` than for the workspace, and 29 back-to-back job pairs rebuilt workspace
crates only because the `-p` set or feature set changed. Fixes:

- Few crates (up to about 8): use the aliases above with a fixed feature list.
- Many crates: measure before you add a `cargo-hakari` workspace-hack crate
  (`cargo-hakari` 0.9.39 is in `~/.cargo/bin`). It pins one feature set for every
  dependency regardless of `-p`, but it also makes every crate depend on the union
  of the workspace's third-party crates. In a 30-crate company workspace
  (2026-11-12) the hack made a small no_std-leaning protocol crate and a shipped
  DLL depend on tokio, rustls and clap, and the 11-step edit-loop run went from
  111 s to 102 s, within the noise. It was dropped. A `-p` feature split costs a
  rebuild of third-party crates once per package set per worktree, and after that
  an edit rebuilds only workspace crates. Hakari pays off when lanes switch package
  sets often in a workspace whose crates already share most heavy dependencies.

**Every change of flags is a different build.** Cargo keys its cached work on the
target, the profile, the feature set and the package set. In the same 30-crate
workspace:

- **An explicit `--target` equal to the host moves the output** to
  `target/<triple>/debug` instead of `target/debug`, and builds build scripts and
  proc macros separately. One alias passed `--target x86_64-unknown-linux-gnu`
  while every other command did not. A lane that ran both paid a second full build
  (302 crates, 43 to 49 s) and kept a second 9.9 GB folder beside the 7.3 GB
  `target/debug`. Without the flag, switching between the two aliases took 0.2 to
  0.4 s. Pass `--target` only for real cross targets. If CI wants the host target
  named, CI appends it at its own call site.
- **`check -p X` and `check -p X --all-targets` resolve features differently**,
  because only the second includes dev-dependencies. Running one after the other
  re-checked about 120 dependencies. Pick one form for the project and put it in the
  alias.
- **A test file behind a feature that the test command does not pass is absent,
  not skipped.** It compiles to nothing, and the run reports zero tests for it with
  no warning. If a test-only feature must exist, every test alias passes it, and a
  new feature gate on a test file goes into the alias the same day.

## 4. Generics and monomorphization

Rust compiles a generic function again for each type it is used with.

- **Write a non-generic core with a thin generic or `dyn` shell.** The public
  function is generic, converts its argument (`impl AsRef<Path>` to `&Path`, a
  delegate to `&dyn Delegate`), and calls a private non-generic function that holds
  the logic.
- tasklens example: `TlTreeTable<D: TreeTableDelegate>` had 2.4k generic lines and
  17 delegate impls, so it was compiled about 17 times. A `dyn` delegate cuts that to
  one copy. Splitting crates does not help here.
- **Find it with `cargo llvm-lines`** (installed in `~/.cargo/bin`):
  `heavy-build cargo llvm-lines -p <crate> --lib | head -40`. Look at the `Copies`
  column. A function with many copies and many lines is the target. A flat profile
  (tasklens UI: 6.4M IR lines, largest function 3.6k lines, no hot generic) means the
  cost is plain code volume, and only splitting the crate helps.
- Closures in builder-style UI code are generics too. In the tasklens UI crate,
  closures were 53% of IR lines. Long `render` functions full of closures are a
  reason to split a view into smaller functions or crates.

## 5. Cargo profiles and linker

The template with comments is in `cargo-config-template.md`. The decisions:

| Setting | Value | Measured reason |
|---|---|---|
| `incremental` (dev, test) | `true` | 5 to 10x faster edit loops: leaf edit then `build -p app` 122 s to 16 s, `test --no-run` 259 s to 23 s, `check` 23 s to 7 s |
| `opt-level` for dependencies | 2 | GUI and GPU stacks are too slow to use at 0. Deps compile once, so the cost is paid once |
| `opt-level` for workspace crates, dev | 0, or 1 for apps that are slow to run at 0 | tasklens test profile at 0: edit compile 71 s to 22 s, tests ran 1.6x slower (34 s to 54 s). Pick by which is bigger in your loop |
| `debug` | `"line-tables-only"`, deps `false` | Dependency debuginfo was most of a 424 MiB test binary in tasklens; agent-hub test binaries passed 200 GB with full debuginfo |
| Bench and profiling profile | `inherits = "release"`, `lto = "thin"`, `debug = "line-tables-only"` | Thin LTO rebuilds much faster than fat and keeps A/B comparisons valid when both arms use it |
| `lto = "fat"`, `codegen-units = 1` | release packaging only | Never built in a lane (section 6) |
| Linker | mold | tasklens UI test binary linked in 0.6 s against 1.1 s for rust-lld at the same 1.5 GiB peak |

Notes:

- `CARGO_INCREMENTAL` in the environment overrides the profile. jobd sets
  `CARGO_INCREMENTAL=0` on jobs it routes to the other desktop
  (`~/projects/job-system/jobd/remote.py`), so a routed job compiles without
  incremental state. That is jobd's choice; do not work around it.
- makepkg sets `RUSTFLAGS`, which replaces the mold flag in `.cargo/config.toml`.
  Packages then link with the default linker. That is fine for release.
- Nightly `-Zthreads=8` cut the tasklens UI crate from 81 to 97 s down to 64 s (20 to
  30%). Use it only in projects already on nightly (frankenterm uses
  `-Z threads=4`). Do not move a stable project to nightly for this alone.
- Tested and not worth it here: sccache, nextest (as a build speedup), the wild linker,
  the Cranelift backend, and Relax (the makepad hot-reload JIT, evaluated
  2026-11-12: bit-exact after two local fixes, but 2 to 3 times slower per edit,
  and its live mode did not pick up edits in a Cargo workspace).
- Put mold under `[target.x86_64-unknown-linux-gnu]` in `.cargo/config.toml`, not
  under `[build]`. Then a Windows DLL, a cross build for a board and a wasm build
  keep their own linkers. Every CI job that builds that target needs mold
  installed.

## 6. The edit loop for agents and lanes

Put these rules in each project's `AGENTS.md`.

1. **`cargo check -p <crate>` first.** It skips codegen. Build or test only when check
   is clean.
2. **Only the packages you touched.** `-p <crate>`, never `--workspace` in a lane. The
   final full run belongs to the gate or the leader.
3. **One test filter.** `cargo test -p <crate> --test <file> <name>`. Fix, rerun the
   same filter, then run the crate's tests once.
4. **Clippy once, when green.** `cargo clippy -p <crate> --all-targets -- -D warnings`
   at the end, not after each edit.
5. **No release, LTO or makepkg builds in a lane.** They cost about 2.65 h in the
   40.8 h window and test nothing the dev build does not.
6. **Read the error before re-running.** 107 same-command re-runs after a failure
   in the window. heavy-build's rerun guard (exit 76) stops the third try.
7. **Use the project's aliases** so the feature set and package set match every other
   lane (section 3). tasklens gives its lane clippy and lane test aliases
   (`lclippy`, `ltest`) one shared `-p` list, so a lane builds one variant of each
   heavy dependency. The leader's gate (`gclippy`) runs clippy on the app crate
   without dev-dependencies.
8. Every command goes through `heavy-build`; long ones through `job submit --detach`.
9. **No wall-clock asserts under 2 s in tests.** Under build load a 200 ms timeout
   fails at random. tasklens bans them with `xtask check-timing`, and a lot of
   flaky tests went away with it.
10. **Once the compile loop is under a few seconds, look at test run time.** In a
    15-crate workspace with small crates, a warm loop was 0.3 to 0.75 s per edit,
    and two tests (25 s and 49 s in a debug build) were the slowest part of the
    loop. Find them with `cargo test -p <crate> -- --report-time -Z
    unstable-options` on nightly, or by timing each test binary.

## 7. Disk: target/ size

Incremental state is what grows. tasklens turned incremental off once because
target/ reached 131 GiB. Turning it off cost 5 to 10x on every loop. Cap the
directory instead.

- **One target/ per checkout, always.** Never set `CARGO_TARGET_DIR`,
  `CARGO_BUILD_BUILD_DIR` or `build.build-dir`. `~/.cargo/config.toml` already points
  `build-dir` at `{workspace-root}/target`. Per-agent target dirs added about 200 GiB
  to this disk in one day (2026-10-02).
- **A cap with a timer.** Repos under `~/work/*` are covered by
  `cargo-target-prune.timer` (every 30 min, default cap 60 GiB, per-repo caps in
  `~/.config/cargo-target-prune.conf`). It does not look in `~/projects`. tasklens has
  its own `tl-target-cap.timer`: every 30 min, only when no tasklens job is queued,
  delete incremental sessions older than 6 h, `cargo sweep --time 1`, and above
  80 GiB clear `target/debug/incremental`. For another repo in `~/projects`, run
  `cargo-target-prune --targets <repo>/target` from a timer, or copy the tasklens
  script. Never sweep while that repo's build runs.
- `debug = "line-tables-only"` and dependency `debug = false` are the cheapest disk
  win (section 5).
- Each extra feature set or `-p` set is another full copy of the affected crates in
  target/ (tasklens had four 365 to 392 MB copies of the UI rlib at once).

## 8. Measuring

Measure before and after a change, through heavy-build, on the same commit.

- **`cargo build --timings -p <bin>`** writes `target/cargo-timings/cargo-timing.html`.
  It shows which units are slow and which ones block others. tasklens cold build:
  381 s, 873 units, slowest dependency 193 s.
- **`cargo llvm-lines`**: codegen volume per function (section 4).
- **`-Ztime-passes`** (nightly): `RUSTFLAGS=-Ztime-passes cargo +nightly build -p X`
  splits one crate's time into frontend and LLVM. The tasklens UI crate: about 30 s
  frontend, about 50 s LLVM.
- **The edit-loop table.** Pick four edits (a comment in a leaf file, a body change
  in a leaf, an edit in the model crate, a new test function), run `check`, `build`
  and `test --no-run` after each, and record seconds and the crates rebuilt. Do it
  with incremental on and off if that is in question. The method and the table are
  in `layout-and-measuring.md`.

## 9. Checklists

### New Rust project

- [ ] Workspace from the start, even with one library: `crates/<name>-model`,
      `crates/<name>` (logic), `crates/<name>-cli` or `-app` (thin bin).
- [ ] Layer table written in `docs/ARCHITECTURE.md` and an `xtask check-deps`
      that enforces it, run in the gate.
- [ ] Profiles and `.cargo/config.toml` from `cargo-config-template.md`.
- [ ] Test hooks on `cfg(debug_assertions)`; no test-only feature on a library.
- [ ] Dev aliases (`cargo c`, `cargo t`) with the one feature set.
- [ ] `testkit` crate when the second crate needs shared fakes.
- [ ] `AGENTS.md` carries the edit-loop rules from section 6.
- [ ] target/ cap: under `~/work`, the prune timer covers it; under `~/projects`, add one.

### Audit of an existing project

- [ ] Run the edit-loop table once (warm, incremental on). Anything over about 30 s
      for a leaf edit with `build` is worth fixing.
- [ ] `cargo build --timings`: which workspace crates are over about 30 s?
- [ ] Any `[features]` used only by tests or enabled from `[dev-dependencies]`?
      `rg -n 'cfg\(feature = "test' crates/`.
- [ ] A feature split shows when `cargo build` then `cargo test` recompiles a
      workspace library that did not change.
- [ ] Does the model crate hold app-only or UI-only types?
- [ ] One giant test binary? `ls -S target/debug/deps | head`.
- [ ] `cargo llvm-lines` on the biggest crate: any generic with many copies?
- [ ] Profiles: incremental on, `line-tables-only`, deps at 2, no fat LTO outside
      release, mold.
- [ ] Is there an upward-edge check, and does it run?
- [ ] target/ size and whether a timer caps it. More than one `target/<triple>/`
      folder for the host triple means some command passes `--target` for the host.
- [ ] Do all dev aliases and CI commands use the same target, feature list and
      `--all-targets` choice? Run each alias twice in a row, then switch: a switch
      that rebuilds workspace or third-party crates is a split (section 3).

**Measure before you restructure.** A workspace of small crates can already be
fast. The 30-crate company workspace above, with no crate over 20k lines, rebuilt
a base-crate edit and relinked the top binary's tests in 1.5 s. Its only real cost
was the alias with an explicit host target. When the edit-loop table shows a few
seconds per edit, fix the splits and leave the layout alone.

Write findings as beads, one change each, in this order: profiles, test-hook gating,
module cycles, crate splits, test binary split. Profile and gating fixes are small
and pay off at once; splits take many beads.

## 10. One workspace, several owners

A company monorepo can hold one Cargo workspace that several teams and lanes work
in at once. Then the workspace-level files are shared: the root `Cargo.toml`
(members, `[profile.*]`, `[workspace.dependencies]`), `.cargo/config.toml` (aliases,
linker, target flags) and `xtask`.

- **Ask the other owners before you edit a shared file.** Find them with
  `ListAgents` and `git log` on the file, and check unmerged branches too: a long
  local branch may already change the same lines. On 2026-11-12 a branch 537
  commits ahead of master already carried the profile, mold and `check-deps` work,
  so a second copy on master would only have produced conflicts.
- **Agree who lands what.** A fix that helps master lanes and CI now goes to master
  as its own small PR, and the owner of the long branch resolves the conflict when
  it merges. A fix that only matters inside the branch stays there.
- **Give each area its own aliases with an explicit `-p` list**, and make every
  `--workspace` alias exclude the other areas (`--exclude '<area>-*'` matches package
  names by glob). Then a run in one area never rebuilds another area's crates.
- **One project guide for the workspace** (`AGENTS.md` beside the root
  `Cargo.toml`) carries the section 6 rules and names each area's aliases.
