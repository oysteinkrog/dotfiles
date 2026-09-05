# TROUBLESHOOTING.md — Common Issues + Fixes

When something doesn't work, look here first.

---

## Skill loading issues

### "Skill never triggers on phrases like 'audit my unsafe'"

Check the description (in SKILL.md frontmatter):
- ≤200 chars: yes (currently ~180).
- Third person ("Audit and refactor..."): yes.
- Front-loaded triggers: yes.

If still not triggering:
1. Confirm Claude is loading skills from the right path: `~/.claude/skills/` (global) or `.claude/skills/` (project).
2. Try a more explicit phrase: "Run the rust-unsafe-code-exorcist on this project."
3. Confirm SKILL.md starts with `---` (no blank line before).

### "Subagent skills aren't inheriting"

In `subagents/<name>.md`, ensure the frontmatter:
```yaml
---
name: ...
description: ...
tools:
  - Read
  - Write
  - ...
---
```

If the subagent needs access to other skills, add `skills:` to its frontmatter explicitly (some Claude Code versions don't auto-inherit).

---

## Toolchain issues

### "`cargo +nightly miri test` says 'no override and no default toolchain set'"

```bash
rustup toolchain install nightly
rustup +nightly component add miri rust-src
cargo +nightly miri setup
```

### "miri panics with stack overflow on my test"

```bash
RUST_MIN_STACK=8388608 cargo +nightly miri test
```

### "miri test takes forever"

- Scope the test: `cargo +nightly miri test --test equivalence_site_NNNN` (single test target).
- Skip miri on FFI tests: `#[cfg_attr(miri, ignore)]`.
- Use cargo-careful instead for FFI-heavy code (faster; less coverage).

### "miri can't run my FFI test"

Expected. miri can't execute native code. Two options:
1. Mark with `#[cfg_attr(miri, ignore)]` and rely on cargo-careful for those paths.
2. Wrap the FFI behind a mock for miri-only builds.

Document the gap in `audit/phase9_toolchain_skips.md`.

### "cargo expand fails on a build-script-heavy crate"

```bash
# Build first to ensure build.rs has run
cargo build
# Then expand
cargo expand
```

If still failing: file the issue in your audit dir as `phase1/expand-failure-<crate>.md` and proceed with ast-grep alone (loses macro-generated unsafe visibility).

### "loom test times out at preemption_bound"

Either:
1. Reduce the model size (test fewer threads / fewer atomic ops per thread).
2. Expand the bound:
   ```rust
   loom::model::Builder::new()
       .preemption_bound(3)
       .max_branches(20_000)
       .check(|| { ... })
   ```
3. Accept the partial coverage and document the bound used.

### "kani says 'unwind bound exceeded'"

Add `#[kani::unwind(N)]` with a larger N. The proof time grows roughly linearly with unwind bound; experiment.

---

## jq / JSONL issues

### "jq -s on two JSONL files returns wrong shape"

Use `--slurpfile` instead. `jq -s` slurps EVERY object from EVERY input file into ONE array. To preserve file boundaries:

```bash
# WRONG — these are equivalent and both wrong:
jq -s '.[0]' a.jsonl b.jsonl    # .[0] is the first OBJECT from a.jsonl, not a.jsonl itself

# CORRECT
jq -n --slurpfile a a.jsonl --slurpfile b b.jsonl '$a + $b'
```

### "jq returns 'null' but I expected 0"

Use `// 0` to fold null into 0:
```jq
[.packages[]?.metric] | add // 0
```

### "Aggregating per-crate geiger files"

Per-crate files at `phase1/<crate>__geiger.json`. Aggregate via:

```bash
for f in phase1/*__geiger.json; do
  jq '[.packages[]?.package.metrics.counters | objects | .[] | numbers] | add // 0' "$f"
done | paste -sd+ - | bc
```

---

## Bead / br issues

### "br ready returns nothing after Phase 8"

Check:
1. `cd <audit-dir>` first; beads are per-directory.
2. `ls .beads/` should show `beads.db` + `beads.jsonl`.
3. `br list --status open --json` to see all open beads (not just ready ones).
4. If still empty, run `br sync --flush-only` then retry.

### "br create rejects my title length"

Long titles are auto-truncated in some terminals. If `br` itself errors: shorten the title; put the long details in `--description`.

### "Bead graph has cycles"

`bv --robot-insights | jq '.Cycles'`. Cycles indicate the dependency chain is malformed. Run:
```bash
bv --robot-suggest    # surfaces hygiene issues
```

Fix by removing the redundant dependency edge.

---

## CI / GH Actions issues

### "Soundness workflow fails on geiger-delta even though I didn't add unsafe"

The workflow compares PR's geiger count to main's. If the count increased, even from a dep upgrade (Cargo.lock changes pulling in new unsafe-bearing deps), the gate fires.

Options:
1. Add the `soundness:opt-in-geiger-up` label to the PR (with rationale in PR description).
2. Investigate the dep — sometimes new unsafe is added in patch releases of trusted deps.
3. Roll back the dep upgrade if intentional.

### "Cache miss every run"

The cache key includes `Cargo.lock` hash. Any dep change busts the cache. Acceptable; recompilation takes 10-30 min.

To improve: cache `~/.cache/miri` separately (the miri sysroot rarely changes); see the template.

### "GH Actions runner OOM on miri test"

miri uses lots of RAM. Options:
1. Scope miri to specific tests: `cargo +nightly miri test --test equivalence`.
2. Use `ubuntu-latest-large` runners (4-8x CPU/RAM).
3. Skip miri in CI; run nightly via separate workflow.

---

## Continuous-mode issues

### "Cron runs but no beads filed"

Check `<audit-dir>/drift/<date>/summary.md`. If `Drift events: 0`, the script saw no new unsafe sites, no modified unsafe sites, no geiger increase, and no `verify.sh` regression against the baseline.

If `Drift events` is nonzero but `0 drift bead(s)` were filed, the drift exists but automatic bead creation failed or `br` was unavailable in the cron environment. Use the summary, `diff.json`, and `verify.log` to file the drift bead manually from the audit dir.

If you expected drift but none fired:
- Did the baseline match the current state? (No drift = good.)
- Did `unsafe-inventory.jsonl` actually change? Inspect `diff.json`.
- Did `enumerate-unsafe.sh` miss the site? Re-run it manually and inspect `<audit-dir>/drift/<date>/phase1/`.

### "Drift cron fails with 'br: command not found'"

Cron's PATH is minimal. Add to the crontab line:
```
0 6 * * * PATH=$HOME/.cargo/bin:/usr/local/bin:/usr/bin /path/to/cron-drift-check.sh ...
```

### "Drift baseline is stale (project moved on)"

After a major refactor wave, re-baseline:
```bash
mkdir -p <audit-dir>/baseline.new
cp -r <audit-dir>/{unsafe-inventory.jsonl,audit/classification,phase1} \
      <audit-dir>/baseline.new/
# Verify it looks right, then:
mv <audit-dir>/baseline <audit-dir>/baseline.old.$(date +%Y%m%d)
mv <audit-dir>/baseline.new <audit-dir>/baseline
```

The old baseline is preserved (per AGENTS.md no-delete rule) for historical reference.

---

## Workflow issues

### "Phase 4 keeps flipping classifications; never converges"

The classifier is iterating but not stabilizing. Investigate which specific sites keep flipping:

```bash
ls <audit-dir>/audit/classification/pass*_summary.jsonl
diff <audit-dir>/audit/classification/pass3_summary.jsonl \
     <audit-dir>/audit/classification/pass4_summary.jsonl
```

Common causes:
- An (A) justification depends on missing tool output (e.g., bench numbers absent → can't tell (A) vs (B)).
- A site is on the edge between buckets; bias DOWN by default.
- The rubric needs project-specific clarification (add to `<audit-dir>/risk-rubric-override.md`).

If unresolvable: spawn a single-site investigation agent to resolve.

### "Phase 7 fresh-eyes never goes clean"

Possible causes:
- The plans have real bugs the reviewer keeps catching → good, fix them, iterate.
- The plans are fine but the reviewer is generating false-positives → the prompts may need recalibration; check that the reviewer is reading from the audit dir, not the project source.

If iterating for >5 rounds: spawn a different model via multi-model triangulation; sometimes a fresh perspective unsticks.

### "Audit-and-refactor changes fail CI"

The audit dir's `verify.sh` ran clean; the project's CI is different. Compare:
- Project's CI matrix vs `audit/ci-matrix.yml.template`. Project CI may have stricter / different gates.
- Project's Cargo.toml dependencies vs audit dir's. A dep upgrade between audit and final closeout can cause divergence.

Fix: align CI in `audit/ci-matrix.yml` with the project's actual workflow.

---

## Validator issues

### "validate-corpus.py fails: E-NNN cited but not defined"

The catalog (`references/source/EXEMPLAR-CATALOG.md`) doesn't have a definition for an `[E-NNN]` cited elsewhere. Either:
1. Add the missing entry to the catalog.
2. Remove the citation if the pattern no longer applies.

### "validate-operators.py fails: missing required section"

A new operator card was added without all 5 required fields (Trigger, Question, Failure modes, Prompt module, Fix section). Fill in the missing one.

### "A third-party skill validator warns about nested references"

The skill intentionally has cross-linked references (per the saas-billing exemplar pattern). The warnings are advisory; not blocking. If they bother you, the strict alternative is to flatten cross-references into SKILL.md, but that bloats the body.

---

## Inverse-audit issues

### "cargo fuzz init fails with 'libfuzzer-sys not compatible'"

```bash
rustup toolchain install nightly
cargo +nightly install --force cargo-fuzz
cd <project>
cargo +nightly fuzz init
```

### "Fuzz target builds but finds nothing in 60s"

Either:
1. The pub fn is well-validated (good signal).
2. The fuzz input isn't reaching the unsafe site (check via `cargo fuzz coverage`).
3. Need longer runtime (`-max_total_time=3600` for 1h).

---

## Triangulation issues

### "Multi-model triangulation: only Claude available"

Use single-model fallback per [TRIANGULATION.md § Single-model fallback](TRIANGULATION.md). Run 4 perspective passes (literal / skeptical / junior-engineer / adversarial); aggregate.

The result is lower signal than true multi-model but better than single-model single-pass.

### "Codex / Gemini API calls fail"

Check:
1. API key in env (`OPENAI_API_KEY`, `GEMINI_API_KEY`).
2. Rate limits (back off + retry).
3. Output JSON is valid (sometimes models return prose; parse defensively).

The manual fallback per [TRIANGULATION.md § Manual multi-model](TRIANGULATION.md) shows the exact curl commands.

---

## Audit dir issues

### "Audit dir's git push fails: branch not tracking remote"

The audit dir is a NEW git repo (per Phase 0 bootstrap). It doesn't have a remote by default. Either:

1. Add a remote: `git -C <audit-dir> remote add origin <url>; git -C <audit-dir> push -u origin main`.
2. Or keep the audit dir local-only (it's not the project repo; doesn't need to be shared).

Per AGENTS.md: do NOT push the audit dir to the same remote as the project repo unless explicitly intended.

### "Audit dir has too many files; hard to navigate"

The skill's design IS large. Use the [QUICK-REFERENCE.md § Key files](QUICK-REFERENCE.md) table to jump to the file you need.

For aggregate views:
- AUDIT_SUMMARY.md — the tally.
- REVIEWER_RESPONSES.md — the review.
- risk-summary.md — what to do first.

---

## When all else fails

1. Read the audit dir's `phase0_scope_decision.md` — did you set up scope correctly?
2. Read `phase0_toolchain.json` — are all tools installed?
3. Check `phase0_skill_inventory.json` — are helper skills available?
4. Look at the most-recent log in `audit/phase<N>/` — what was the last successful step?
5. Run this skill's `validate-corpus.py` + `validate-operators.py`.

If you find a NEW issue not in this file: append it. The TROUBLESHOOTING file grows by adding entries.
