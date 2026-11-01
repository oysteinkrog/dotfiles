# Crate layout checklist and edit-loop measuring

Companion to `SKILL.md`. Section A is for designing or reviewing a crate layout.
Section B is the method behind the timings in the skill.

## A. Crate layout checklist

### Per crate

- [ ] It sits in one layer and depends only on lower layers.
- [ ] Its row in the allowed-dependency table names every direct workspace and
      external dependency.
- [ ] It is roughly 5k to 50k lines. Bigger: check whether its parts are edited
      separately. Smaller: check that it stops a rebuild cascade.
- [ ] It has no `[features]` used only by tests.
- [ ] Its `[dev-dependencies]` turn on no feature of a normal dependency.
- [ ] Its tests live in its own `tests/` folder, a few binaries, not in another
      crate's test binary.
- [ ] Generic public functions hand off to a non-generic inner function.

### Workspace

- [ ] The model or types crate holds only shared contracts. App-only and UI-only
      types sit in a crate above it.
- [ ] Binary crates are thin: argument parsing and wiring.
- [ ] A `testkit` crate (dev-only, small) holds the fakes and harness code.
- [ ] One `[workspace.dependencies]` table; every crate uses `workspace = true`.
- [ ] `xtask check-deps` runs in the gate.
- [ ] Before a split: no module inside the crate reaches up into a module that will
      land in a higher crate (check with the `rg` below).

### The upward-edge check

tasklens's full version is `~/projects/tasklens/xtask/src/check_deps.rs`. A minimal
version does two things.

1. **Crate edges:** read `cargo metadata --format-version 1 --no-deps`. For each
   workspace member, list its `dependencies` with `kind` null (normal) or `"build"`.
   Fail if one is not in the member's allowed row. Keep the rows in the xtask as a
   `const` table and in `docs/ARCHITECTURE.md` as the readable copy.
2. **Module edges inside a crate that will be split:** give each module a layer
   number and fail on any `use crate::<higher module>` in a lower one:

   ```bash
   # lower module "components" must not reach into "pages" or "window"
   rg -n 'crate::(pages|window)::' crates/<crate>/src/components
   ```

   Turn this into an xtask check while the split is in progress, so no new upward
   edges land.

Rules for the check:

- Read `cargo tree` output lines, not its exit status (`cargo tree -i X` exits 0
  when X is absent).
- Check direct normal and build edges only. Dev-dependencies and transitive
  dependencies stay outside the rows.
- Add a deliberate failing case once when the check lands and record the output.

## B. Edit-loop measuring

### Setup

- Your own worktree under `/var/tmp/claude/`, never a checkout other agents work in
  (the edits and reverts below would land in their builds). One commit, warm
  target/ (run each command once first).
- Every command through `heavy-build`. Record wall time and the crates rebuilt.
- Note the machine load. tasklens numbers were taken at load 13 to 44 on 32 threads,
  so compare ratios, not seconds, across runs.
- Run incremental on and off only when that is the question:
  `CARGO_INCREMENTAL=0` or `=1` in the environment.

### The edits

| Id | Edit | Why |
|---|---|---|
| a-comment | add a comment line in a leaf file of the biggest crate | floor cost of touching that crate |
| a-body | change a function body in the same file | real code change, same crate |
| b | change a body in the model crate | rebuild cascade through the graph |
| c | add a test function in a test file | test binary relink cost |
| d | edit a widely used module (a shared component) | worst common case |

After each edit run these, in order, each as its own heavy-build call:

```bash
heavy-build cargo check -p <crate>
heavy-build cargo build -p <bin>
heavy-build cargo test -p <crate> --no-run
```

Count rebuilt crates from the `Compiling` and `Checking` lines:

```bash
grep -E '^\s+(Compiling|Checking) ' <log> | grep -c '(/'   # workspace crates only
```

Revert the edit with `git checkout -- <file>` before the next one, then rebuild once
so the next measure starts warm.

### The table

Write it like this, one row per edit and command:

| edit | command | INCR=0 s | INCR=1 s | crates rebuilt |
|---|---|---|---|---|
| a-comment | check -p tl-ui | 23 | 7 | 1 |
| a-comment | build -p tl-app | 122 | 16 | 2 |
| a-comment | test --no-run | 259 | 23 | 1 |
| a-body | build -p tl-app | 125 | 24 | 2 |
| a-body | test --no-run | 223 | 34 | 1 |
| b | build -p tl-app | 141 | 17 | 9 |
| c | test --no-run | 85 | 37 | 1 |
| d | test --no-run | 186 | 71 | 1 |

(tasklens, 2026-11-01. Raw logs: `/var/tmp/claude/tl-bp-logs/results.txt`.)

How to read it:

- `test --no-run` much slower than `build` for the same edit: a feature split or a big
  test binary.
- `crates rebuilt` high for a model edit: the model crate holds types that most
  dependents do not use.
- `check` fast but `build` slow: codegen cost. Look at `cargo llvm-lines` and the
  opt-level of the workspace crates.
- Same edit, same command, two runs differ by more than 2x: machine load. Measure
  again later.

### Feature-split test

To see if build and test compile a library twice:

```bash
heavy-build cargo build -p <bin>
heavy-build cargo test -p <crate> --no-run   # watch for "Compiling <crate>"
heavy-build cargo build -p <bin>             # should rebuild nothing
```

If the second `build` or the `test` recompiles a workspace crate you did not touch,
the two commands use different feature sets. Find the feature with
`cargo tree -e features -i <crate>` for both commands.
