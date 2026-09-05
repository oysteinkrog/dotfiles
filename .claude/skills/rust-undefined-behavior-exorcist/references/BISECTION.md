# Bisection — When Was This UB Introduced?

When a Phase 3 dynamic sweep surfaces UB that *wasn't there in v1.2.0*, the question becomes: which commit introduced it? `git bisect` is the right tool, but UB bisection has its own gotchas.

This file is the bisection playbook.

---

## When to bisect

You should bisect when:
- A specific Miri/sanitizer/loom test fails reproducibly in HEAD but used to pass
- A fuzz crash reproduces in HEAD but not in a known-good earlier version
- A `CONFIRMED_UB` finding's root cause is unclear and the diff history of the affected file is large
- A downstream user reports UB after a specific version bump

You should NOT bisect when:
- The UB is brand-new (no previous version was tested)
- The bug is intermittent under the chosen tool (flaky test = useless bisection signal)
- The build doesn't compile at one of the intermediate commits (you'll just thrash)

---

## Bisection target script — `scripts/bisect-ub.sh`

The standard pattern:

```bash
#!/usr/bin/env bash
# Bisection script. Exit 0 = good, 1 = bad, 125 = skip.
set -euo pipefail
SOURCE="$1"        # Repo path (passed by `git bisect run <script> <repo>`)
EXP_ID="$2"        # Experiment ID from UNDEFINED_BEHAVIOR_EXPERIMENT_DESIGNS.md

cd "$SOURCE"

# Step 1: Try to build at this commit. If it fails, skip.
if ! cargo +nightly check --all-targets 2>/dev/null; then
    exit 125  # skip — this commit doesn't compile
fi

# Step 2: Run the experiment's invocation
LOG=$(mktemp)
trap "rm -f $LOG" EXIT

# Copy the EXP_ID invocation from EXPERIMENT-DESIGNS.md
case "$EXP_ID" in
  EXP-001)
    MIRIFLAGS="-Zmiri-tree-borrows" cargo +nightly miri test --test exp_001 2>&1 > "$LOG"
    ;;
  EXP-007)
    MIRIFLAGS="-Zmiri-symbolic-alignment-check" cargo +nightly miri run --bin exp_007 2>&1 > "$LOG"
    ;;
  # add per-experiment cases here
  *)
    echo "Unknown EXP_ID: $EXP_ID" >&2
    exit 125
    ;;
esac

# Step 3: Check the experiment's expected signal
if grep -q "Undefined Behavior" "$LOG"; then
    exit 1  # bad — UB present
else
    exit 0  # good — no UB
fi
```

Then bisect:

```bash
cd "$SOURCE"
git bisect start
git bisect bad HEAD          # current HEAD has the UB
git bisect good v1.2.0       # v1.2.0 was clean
git bisect run /path/to/scripts/bisect-ub.sh "$(pwd)" EXP-007
```

When bisect terminates, the offending commit prints. Save its hash in `phase5_experiment_results/EXP-NNN-bisection.log`.

---

## Bisection gotchas

### G1 — Commit compiles but tests don't

If the test file (`tests/exp_007.rs`) was added in a later commit, it won't compile in earlier commits. **Fix:** include the test file *out-of-tree* in `experiments/EXP-NNN/repro.rs` with a standalone Cargo.toml — and run that, not an in-tree test. Then bisection only needs the *source crate* to compile.

### G2 — Flaky test under the tool

If Miri or TSan is flaky on this test, bisection hits `125` (skip) or worse, false-positives "bad". **Fix:** Run the test 5 times at each commit; require 5/5 to call "good", 3+/5 to call "bad".

```bash
runs=5; pass=0
for i in $(seq 1 $runs); do
    if MIRIFLAGS="..." cargo +nightly miri ...; then pass=$((pass+1)); fi
done
[[ $pass -eq $runs ]] && exit 0
[[ $pass -le 2 ]] && exit 1
exit 125  # ambiguous
```

### G3 — Bisection range crosses a Rust toolchain bump

If the project upgraded its `rust-toolchain.toml` mid-bisection, the older commits may need an older Miri. **Fix:** Set `RUSTUP_TOOLCHAIN=nightly-2024-01-01` explicitly in the bisect script to pin the tool; commit it as `phase5_experiment_results/EXP-NNN-rustup-pin.txt`.

### G4 — Bisection range crosses a dependency bump

If a dep version was bumped mid-range, the UB may have been in the dep, not your code. **Resolution:** Note the dep-bump commit; once bisection lands on it, follow up by re-running with the *old* dep version pinned to confirm the UB lives in the dep.

### G5 — Bisection lands on a merge commit

When bisect terminates on a merge, the actual introducer is on one of the parent branches. **Fix:** `git bisect log` shows the trail; re-run bisect with `--first-parent` to ignore merge content, or manually `git bisect bad <parent>` to dig in.

### G6 — Tool version drift during bisection

Tools (Miri, sanitizers, clippy) can change behavior across versions. A bisection running today against commits from a year ago may produce different verdicts than the original CI did at the time. **Resolution:** Note this in the bisection log; consider the finding's verdict as "introduced at or before commit X" rather than "introduced *at* X".

---

## Bisection alternatives

When `git bisect` isn't the right tool:

### Alt 1 — `cargo-deny` advisory bisection

If the UB is in a dependency, `cargo deny check advisories --features all-features` may already know. Check the RustSec advisory database before bisecting.

### Alt 2 — `cargo-careful` differential

`cargo careful test` enables runtime checks libstd normally hides. If a test passes under regular `cargo test` but fails under `cargo careful`, the regression may be in `libstd`'s interaction with your code — bisect against `rust-toolchain.toml` upgrades, not your code.

### Alt 3 — `git log -S<pattern>`

If you know the symptom (a specific function name, a removed assert), pickaxe-search the history:
```bash
git log -S'unsafe { *m = 99 }' --all
```

This finds commits that *added* or *removed* the literal string. Often faster than bisection.

### Alt 4 — Reverse bisection

If the UB existed for a while and was recently *fixed accidentally*, you can reverse-bisect to find the fix:
```bash
git bisect start
git bisect bad v0.1.0    # was UB-bearing
git bisect good HEAD     # is currently clean
git bisect run scripts/bisect-ub.sh "$(pwd)" EXP-007
```

The result is the commit that fixed the UB. Useful for backporting (see [BACKPORTING.md](BACKPORTING.md)).

---

## After bisection

Once you have the introducing commit:

1. **Record it** in the EXP-NNN block under "**Notes:**" — `Introduced in <commit-hash> (date: ...)`.
2. **Read the commit message** — sometimes the author *knew* about the trade-off and documented it. The fix may be a feature flag instead of a rewrite.
3. **Check if the commit also fixed a different bug** — if yes, the remediation must preserve the fix and fix the UB.
4. **Backport candidacy** — if the UB exists in v1.2..HEAD and v1.2 is still supported, the remediation likely needs backporting. See [BACKPORTING.md](BACKPORTING.md).
5. **CVE candidacy** — if the introducing commit is in a shipped release, the UB may be CVE-grade. See [DISCLOSURE.md](DISCLOSURE.md).

---

## Bisection subagent

The `bisection-runner` subagent (Phase 8 helper) automates this. See `subagents/bisection-runner.md`.
