# cross-architecture-determinism-failure

> `truncate_score(.., 6)` is supposed to make every parity score bytewise-identical across x86, ARM, and WASM. A CI matrix run shows them differing anyway. Diagnose, fix, and prevent the rare LSB cascade that defeats the truncation guard.

This is the cousin of [oracle-divergence-triage.md](oracle-divergence-triage.md), but the divergence is *between runners executing the same code*, not between subject and oracle. The bug is structurally different and the fix lands in a different place.

## Trigger

Any of:

- The `parity-score-ratchet` GitHub Actions workflow shows divergent scorecards across `runs-on: ubuntu-latest` (x86_64) and `runs-on: ubuntu-latest-arm64` (aarch64) on the same git SHA.
- Local repro on a Mac M-series box (aarch64) produces a different `scorecards.json` than the CI baseline (x86_64).
- A WASM-target build (`wasm32-wasi`) emits a parity score that `diff`s against native — even after `truncate_score` to 6 decimal places.
- The release-certification CI lane fails with `cross_platform_byte_identical: FAIL` even though both runners returned `Allow`.
- A maintainer reports "my local scorecards differ from CI by a few LSBs in one category".

If the divergence is *only* in the perf pillar (i.e., wall-clock numbers), this is *not* a determinism failure — that's host-variance and routes through [cv-pct-flake.md](cv-pct-flake.md). This recipe is for divergence in *normalized/scored fields* that are supposed to be deterministic by construction.

## Why `truncate_score(.., 6)` Usually Suffices (and When It Doesn't)

Per [Q-053](../exemplars/QUOTE-BANK.md):

> x86, ARM, and WASM floating-point arithmetic differ at the LSB; truncating to 6 decimal places ensures that two runs produce bytewise identical scores regardless of CPU architecture.

The truncation works because IEEE-754 differences across architectures typically appear in the last 1–3 mantissa bits — well below the 6th decimal place for scores in `[0, 1]`. **But** when a score is itself derived from a *chain* of floating-point operations (Beta posterior sampling → conformal band → arithmetic-mean e-process → final score), LSB differences can *cascade*. Specifically:

1. Two intermediate values differ at the 16th decimal place (architectural LSB difference).
2. They flow through a `> threshold` comparison that goes different ways on the two architectures (one says "include", the other says "exclude").
3. The downstream aggregation now operates on *different subsets of inputs* — not on the same inputs with different LSBs.
4. The final score now differs at, say, the 4th decimal place — *above* the truncation boundary.

This is the **LSB cascade**. It's rare (the threshold-flip step is what makes it rare), but when it happens, `truncate_score` doesn't catch it because the inputs to the final aggregation already disagree.

Per [Q-201](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-201--ccmd-75--math-toolkit-has-a-file-not-just-a-paper), every theorem has a file; an LSB cascade always traces to *one specific* threshold-flip in *one specific* file. Find that file; the fix follows.

## Operator Pipeline

```
⊙ DEBOUNCE-FALSE-POSITIVE     classify: is the divergence in scored fields or wall-clock?
↓
⚠ ESCALATE-TO-FRESH-REPRO   build a deterministic fixture that reproduces the divergence on a single host
↓
⌘ REDUCE/MINIMIZE             delta-debug the inputs to a 1-minimal divergence: which row of the matrix?
↓
⬡ INSTRUMENT-HOT-PATH         dump intermediate values (pre-truncation, pre-aggregation, pre-threshold) per arch
↓
⟁ TRIANGULATE-PROFILE         pin the cascade: which threshold-flip diverged?
↓
🧪 EXPERIMENT-DESIGN           hypothesis: "the cascade originates at <file:line>; widening tolerance there fixes it"
↓
⊕ ISOMORPHIC-REWRITE          options: (a) integer arithmetic for the comparator; (b) truncate *before* threshold; (c) replace threshold with a saturating clamp
↓
⚖ RATCHET-LOWER-BOUND         re-baseline with cross-arch matrix as a CI gate; preserve floor
```

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
ARCH_A=x86_64               # the host the ratchet baseline was set on
ARCH_B=aarch64              # the host showing divergence
GIT_SHA=$(git -C "$PORT" rev-parse HEAD)

# 1. Confirm: divergence is in scored fields (deterministic), not perf fields (non-deterministic).
diff <(jq 'del(.environment, .timing, .wall_clock_ns, .cv_pct)' \
            "$WORKSPACE/scorecards-from-${ARCH_A}.json") \
     <(jq 'del(.environment, .timing, .wall_clock_ns, .cv_pct)' \
            "$WORKSPACE/scorecards-from-${ARCH_B}.json")

# If diff is empty, the alleged divergence is wall-clock noise; route through cv-pct-flake.md.

# 2. Identify which categories diverge.
DIVERGENT_CATS=$(jq -r '
  .categories | to_entries[]
  | select(.value.score_${ARCH_A} != .value.score_${ARCH_B})
  | .key' "$WORKSPACE/diff_per_category.json")
echo "Divergent categories: $DIVERGENT_CATS"

# 3. For each divergent category, dump intermediate values on BOTH arches.
# The compute-parity-score.sh script supports --emit-intermediates for this.
for CAT in $DIVERGENT_CATS; do
  for ARCH in $ARCH_A $ARCH_B; do
    rch exec --worker xarch-intermediates-$ARCH -- \
      "$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE" \
        --category "$CAT" \
        --emit-intermediates "$WORKSPACE/xarch-debug/${ARCH}_${CAT}_intermediates.json"
  done
done
wait

# 4. Diff the intermediates. The first place they disagree at the 7th-decimal-place-or-later is
#    suspicious; the first place they disagree at the 6th-decimal-or-earlier IS the cascade origin.
for CAT in $DIVERGENT_CATS; do
  "$WORKSPACE/scripts/diff-intermediates.sh" \
    "$WORKSPACE/xarch-debug/${ARCH_A}_${CAT}_intermediates.json" \
    "$WORKSPACE/xarch-debug/${ARCH_B}_${CAT}_intermediates.json" \
    --bisect-to-first-divergence \
    > "$WORKSPACE/xarch-debug/${CAT}_first_divergence.json"
done

# 5. Identify the file:line of the first sub-truncation-tolerance divergence per category.
# This is the cascade origin.
jq -r '.first_divergence.source_file + ":" + (.first_divergence.source_line|tostring)' \
  "$WORKSPACE/xarch-debug/"*_first_divergence.json | sort -u

# 6. File the hypothesis BEFORE attempting a fix.
cat >> "$WORKSPACE/PERF_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — xarch-determinism-${GIT_SHA:0:7} — investigating
- target_workload: parity-scoring chain
- baseline_arch: $ARCH_A
- divergent_arch: $ARCH_B
- divergent_categories: $DIVERGENT_CATS
- cascade_origin_files: $(jq -r '.first_divergence.source_file' "$WORKSPACE/xarch-debug/"*_first_divergence.json | sort -u)
- hypothesis: "the threshold comparator at <file:line> flips sign on LSB-different inputs; cascade defeats truncate_score downstream"
- expected_signal: "if we replace the > with a 6-decimal-truncating comparator, the divergence vanishes; if we replace it with a saturating-clamp comparator that maps LSB-different inputs to the same bucket, also vanishes"
- falsifiability: "if the fix preserves the comparator but tightens upstream truncation, divergence still appears (because the threshold is what flips)"
- one_line_invocation: "$WORKSPACE/scripts/cross-arch-determinism-test.sh $PORT"
- results_inline: <fill after step 8>
EOF

# 7. Apply the fix (per the chosen isomorphic rewrite). Three canonical options:
#
#    (a) Integer arithmetic in the comparator:
#         OLD: if score > threshold { include } else { exclude }
#         NEW: let i_score = (score * 1_000_000.0) as u64;
#              let i_threshold = (threshold * 1_000_000.0) as u64;
#              if i_score > i_threshold { include } else { exclude }
#
#    (b) Truncate before threshold (move the truncation upstream):
#         NEW: if truncate_score(score, 6) > truncate_score(threshold, 6) { include } else { exclude }
#
#    (c) Saturating clamp (collapse LSB-different inputs to the same bucket):
#         NEW: let bucketed = (score * 1_000_000.0).round() / 1_000_000.0;
#              if bucketed > threshold { include } else { exclude }
#
# Pick the option whose isomorphism proof is cleanest for the specific call site.

# 8. Re-run the cross-arch matrix; confirm scorecards are now byte-identical.
for ARCH in $ARCH_A $ARCH_B; do
  rch exec --worker xarch-verify-$ARCH -- \
    "$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE" \
    > "$WORKSPACE/xarch-verify/scorecards-from-${ARCH}.json"
done
wait

diff "$WORKSPACE/xarch-verify/scorecards-from-${ARCH_A}.json" \
     "$WORKSPACE/xarch-verify/scorecards-from-${ARCH_B}.json"
# Empty diff = fix works.

# 9. Add the cross-arch matrix gate to CI permanently.
# See assets/github-workflows/parity-score-ratchet.yml — add a `strategy.matrix.runner` row.

# 10. Create the bead.
br create \
  --title "xarch-determinism-${GIT_SHA:0:7}" \
  --priority 1 \
  --type bug \
  --labels "pillar:conformance,lane:cc_3,recipe:cross-architecture-determinism-failure,arch-pair:${ARCH_A}+${ARCH_B}"

# 11. Two fresh-eyes clean rounds before close.
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --bead "xarch-determinism-${GIT_SHA:0:7}"
```

## Beads to claim (or create)

- `xarch-determinism-<short-sha>` (this recipe creates it).
- Dependency: [`pattern:155-BENCH-HISTORY-RATCHET`](../patterns/155-BENCH-HISTORY-RATCHET.md) — cross-arch baselines must be byte-identical.
- Dependency: [`pattern:75-BAYESIAN-CONFORMAL-SCORE`](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md) — the chain producing the score.
- Dependency: [`pattern:35-NORMALIZED-VALUE`](../patterns/35-NORMALIZED-VALUE.md) — the comparator layer where the fix lands.
- Dependency (test): `test-xarch-byte-identical-scorecards` — the regression test that asserts byte-identical scorecards on the cross-arch matrix.
- Dependency (CI): `ci-add-xarch-matrix-to-parity-ratchet` — the CI gate that catches regressions of *this* fix.
- Dependency (doc): `doc-xarch-cascade-${GIT_SHA:0:7}` — entry in `docs/progress/cross-arch-determinism/` naming the cascade origin file and the chosen isomorphic-rewrite.

## Exit Criteria

- [ ] Divergence reproduced on a single host (deterministic fixture; not arch-flaky).
- [ ] Cascade origin pinned to a specific `file:line` per divergent category.
- [ ] Hypothesis-ledger entry filed with all six fields; cascade-origin files named.
- [ ] ≥2 isomorphic rewrites enumerated; the chosen one has an isomorphism proof.
- [ ] Cross-arch scorecards re-diff to empty after fix.
- [ ] Cross-arch matrix gate added to `parity-score-ratchet.yml`; the new gate ran green on both arches in CI.
- [ ] `.bench-history` updated atomically with source change; no per-arch baselines (per the byte-identical invariant, one baseline is enough).
- [ ] Two fresh-eyes clean rounds.
- [ ] Documentation entry under `docs/progress/cross-arch-determinism/` summarizing cascade + fix.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| "Just truncate to 5 decimals instead of 6." | Doesn't address the cascade; just shifts the threshold-flip lower. The cascade can still happen at the 4th decimal under sufficient input chains. |
| Per-architecture baseline files. | Defeats the cross-arch byte-identical invariant. Per [Q-053](../exemplars/QUOTE-BANK.md), the *point* is one baseline across all arches. |
| Adding `#[cfg(target_arch = "x86_64")]` paths in the scoring chain. | Architecture-conditional scoring is what we're trying to avoid. The fix must be arch-uniform. |
| Treating wall-clock divergence as determinism failure. | Wall-clock is *expected* to differ across architectures; routes through `cv-pct-flake.md`. This recipe is for *scored* / *normalized* fields only. |
| "It's a floating-point thing; can't really be deterministic." | The whole point of `truncate_score` is that it *can*. A residual divergence is a cascade with a specific origin; find it. |
| Skipping the intermediate-dump step. | Without intermediates you can't pin the cascade; you'll fix the wrong site and the divergence re-appears in the next round. |
| Closing without adding the CI matrix gate. | Six months from now another agent will re-introduce the bug. The CI gate is the anti-repeat mechanism. |
| Using `--release` instead of `--profile release-perf` for the cross-arch tests. | Per [Q-032](../exemplars/QUOTE-BANK.md), the size-optimized profile produces different codegen and can mask the cascade. Always `release-perf`. |

## Cross-references

- [../patterns/35-NORMALIZED-VALUE.md](../patterns/35-NORMALIZED-VALUE.md) — comparator layer where the fix usually lands.
- [../patterns/75-BAYESIAN-CONFORMAL-SCORE.md](../patterns/75-BAYESIAN-CONFORMAL-SCORE.md) — the scoring chain that can host a cascade.
- [../patterns/155-BENCH-HISTORY-RATCHET.md](../patterns/155-BENCH-HISTORY-RATCHET.md) — the cross-arch byte-identical baseline invariant.
- [../methodology/IDENTITY-AND-REPRODUCIBILITY.md](../methodology/IDENTITY-AND-REPRODUCIBILITY.md) — broader cross-arch reproducibility doctrine.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — lower-bound math; cascade can move the lower bound discontinuously.
- [../exemplars/QUOTE-BANK.md § Q-053](../exemplars/QUOTE-BANK.md) — the `truncate_score` doctrine.
- [../exemplars/QUOTE-BANK-V2-ADDITIONS.md § Q-203](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-203--ccmd-75--conformal-prediction-citation) — conformal-band rationale.
- [../../assets/github-workflows/parity-score-ratchet.yml](../../assets/github-workflows/parity-score-ratchet.yml) — the CI workflow that gets the matrix-row addition.
- Related motions: [`cv-pct-flake.md`](cv-pct-flake.md) (wall-clock variance, not the same problem), [`oracle-divergence-triage.md`](oracle-divergence-triage.md) (subject vs oracle, not arch vs arch), [`ratchet-block.md`](ratchet-block.md).
