# insta-snapshot-explosion

> A refactor touched 200+ `insta` snapshots and the diff is a wall of green. Some are *intentional* layer-internal regenerations; some are *unintentional* drift hiding a bug. Bisect them apart without `cargo insta accept`-ing the bugs along with the wins.

This recipe is the conformance-pillar cousin of [perf-regression-triage.md](perf-regression-triage.md). Snapshots are *internal* oracles per [Q-042](../exemplars/QUOTE-BANK.md) ("Three-tier equivalence rule"), so a snapshot change is a layer-level regression candidate, not a behavioural regression — but it can be the *cause* of one.

## Trigger

Any of:

- `cargo insta pending-snapshots` shows ≥50 pending updates after a single feature branch.
- A refactor (commonly: planner-layout change, codegen optimization, format-string consolidation) regenerates `>10%` of all `.snap` files.
- A reviewer comment "this PR has too many snapshot changes to review individually" appears on the PR.
- The `conformance-suite.yml` workflow shows snapshot tests passing with `INSTA_UPDATE=auto` env var leaked in.
- A bisect on a behavioural regression points back to a commit whose only changes are snapshot updates (a clear sign an unintentional snapshot got accepted).

If the snapshot change is `<20` snapshots and confined to one module, this recipe is overkill — review each one individually and `cargo insta review` them. This recipe is for the *explosion* case where individual review is impractical.

## Why "Just Accept Them All" Is Wrong

Per [Q-042](../exemplars/QUOTE-BANK.md):

> Encode the distinction; never paper over it.

A snapshot is a *layer-level oracle*. Per [Q-072](../exemplars/QUOTE-BANK.md), you enumerate the universe of behaviours and observe which the engine handles. A bulk `cargo insta accept` says "the new behaviour is the right behaviour" *without examining whether it is*. For a 200-snapshot batch, the probability that all 200 are intentional is small; the probability that ≥1 hides a regression is, empirically, high.

The discipline: **bisect into small batches, capture rationale per batch, accept the batch only after the rationale is filed.**

## Operator Pipeline

```
⊙ DEBOUNCE-FALSE-POSITIVE     classify snapshots by module/category; group structurally-similar ones
↓
⌘ REDUCE/MINIMIZE             pick the smallest batch (typically 5-15) that represents one rationale
↓
🧪 EXPERIMENT-DESIGN          per batch: what changed in the source, why should the snapshot follow?
↓
⊕ ISOMORPHIC-REWRITE          for any batch whose rationale is "minor reorg, behaviour unchanged" — accept; for any whose rationale is unclear — split further
↓
⚖ RATCHET-LOWER-BOUND         after all batches accepted, the conformance score must not drop
↓
🪟 FRESH-EYES                three reviewers MUST sample-review at least 10% of accepted snapshots
```

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
cd "$PORT"

# 1. Enumerate the pending snapshots.
PENDING=$(cargo insta pending-snapshots --workspace 2>&1 | wc -l)
echo "Pending snapshots: $PENDING"
# If <20, exit this recipe and review individually.
[ "$PENDING" -lt 20 ] && { echo "Use individual review, not this recipe."; exit 0; }

# 2. Bucket pending snapshots by directory (== module/crate).
cargo insta pending-snapshots --workspace 2>&1 \
  | awk '/^---/{f=1;next} f' \
  | awk -F'/snapshots/' '{print $1}' \
  | sort | uniq -c | sort -rn \
  > "$WORKSPACE/insta-explosion/buckets-by-module.txt"

cat "$WORKSPACE/insta-explosion/buckets-by-module.txt"
# Look at the top buckets; each is one batch candidate.

# 3. For each bucket, dump the diff as a single batch file.
mkdir -p "$WORKSPACE/insta-explosion/batches/"
for MODULE in $(awk '{print $2}' "$WORKSPACE/insta-explosion/buckets-by-module.txt"); do
  BATCH_NAME=$(echo "$MODULE" | tr '/' '_')
  for SNAP in $(find "$MODULE/snapshots/" -name '*.snap.new'); do
    ORIG="${SNAP%.new}"
    echo "=== $ORIG ===" >> "$WORKSPACE/insta-explosion/batches/${BATCH_NAME}.diff"
    diff -u "$ORIG" "$SNAP" >> "$WORKSPACE/insta-explosion/batches/${BATCH_NAME}.diff" 2>/dev/null
    echo >> "$WORKSPACE/insta-explosion/batches/${BATCH_NAME}.diff"
  done
  echo "Batch $BATCH_NAME: $(grep -c '^=== ' "$WORKSPACE/insta-explosion/batches/${BATCH_NAME}.diff") snapshots"
done

# 4. Per batch, capture rationale BEFORE running `cargo insta accept`.
# Use the rationale template:
for BATCH_FILE in "$WORKSPACE/insta-explosion/batches/"*.diff; do
  BATCH_NAME=$(basename "$BATCH_FILE" .diff)
  COUNT=$(grep -c '^=== ' "$BATCH_FILE")

  RATIONALE_FILE="$WORKSPACE/insta-explosion/rationales/${BATCH_NAME}.md"
  mkdir -p "$(dirname "$RATIONALE_FILE")"
  cat > "$RATIONALE_FILE" <<EOF
# Snapshot batch rationale: $BATCH_NAME

- **Snapshot count:** $COUNT
- **Module:** $BATCH_NAME
- **Source change(s) that caused the regeneration:** <commit shas + one-line each>
- **Categorical change:** <one of: format-only | order-only | new-fields | removed-fields | type-changed | semantic-change>
- **Behaviour-preserving claim:** <verbatim — what oracle / property / invariant proves behaviour didn't change>
- **Per-snapshot sampling:** <names of 3 snapshots from this batch the author read end-to-end>
- **Sample diffs are consistent with the rationale:** <yes | no — if no, split the batch>
- **Accept decision:** <accept | split-further | reject + reopen>
EOF
  echo "Wrote rationale template: $RATIONALE_FILE"
done

# 5. Iterate batches one at a time. For each:
#    a. Open the diff in your reviewer.
#    b. Sample 3 random snapshots; read them end-to-end.
#    c. Fill out the rationale (do NOT accept anything until the rationale is written).
#    d. If sample diffs are inconsistent with the rationale, split the batch further.
#    e. Once rationale is satisfying, accept ONLY this batch's snapshots.
#       Use `cargo insta accept` with a glob, NOT --all:
cargo insta accept --glob "crates/<module>/tests/snapshots/**/*.snap"

# 6. After each batch acceptance, re-run the conformance suite.
"$WORKSPACE/scripts/run-conformance-suite.sh" "$PORT" "$WORKSPACE"
# Any new red? STOP. The last batch hid a regression. Reset and split.
git restore --source=HEAD --staged --worktree crates/<module>/tests/snapshots/

# 7. After all batches accepted, recompute parity score; the ratchet must not drop.
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
"$WORKSPACE/scripts/apply-ratchet.sh" "$WORKSPACE"
# If Block: a batch regressed something. Bisect with `git bisect run`.

# 8. File the bead.
br create \
  --title "insta-explosion-$(date -u +%Y%m%d)" \
  --priority 2 \
  --type refactor \
  --labels "pillar:conformance,lane:cc_2,recipe:insta-snapshot-explosion,batch-count:$(ls "$WORKSPACE/insta-explosion/rationales/" | wc -l)"

# 9. Three fresh-eyes reviewers MUST sample-review ≥10% of accepted snapshots from each batch.
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --bead "insta-explosion-$(date -u +%Y%m%d)" \
  --sample-rate 0.10
```

## Beads to claim (or create)

- `insta-explosion-<date>` (this recipe creates it; epic with one sub-bead per batch).
- Sub-beads: `insta-batch-<module>` per module, each containing the rationale file and the accepted snapshots' SHAs.
- Dependency: [`pattern:55-INSTA-GOLDEN-SNAPSHOTS`](../patterns/55-INSTA-GOLDEN-SNAPSHOTS.md) — snapshot discipline.
- Dependency: [`pattern:50-THREE-TIER-EQUIVALENCE`](../patterns/50-THREE-TIER-EQUIVALENCE.md) — where snapshots fit in the equivalence hierarchy.
- Dependency: [`pattern:30-DIFFERENTIAL-V2-ENVELOPE`](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) — the differential oracle that MUST stay green across all batches.
- Dependency (test): `test-insta-explosion-conformance-green` — the full conformance suite passes post-acceptance.
- Dependency (doc): `doc-insta-explosion-<date>` — entry in `docs/progress/snapshot-changes/` summarizing every batch + its rationale.

## Exit Criteria

- [ ] Bucketing complete; every pending snapshot in exactly one batch.
- [ ] Every batch has a rationale file with all eight fields filled.
- [ ] No batch was accepted before its rationale was written.
- [ ] Each batch's acceptance was followed by a conformance-suite green check; no regression slipped in.
- [ ] Final ratchet check returns `Allow` (or `Quarantine` with explicit waiver and bead).
- [ ] Three fresh-eyes reviewers each sample-reviewed ≥10% of accepted snapshots; their findings are recorded.
- [ ] Documentation entry under `docs/progress/snapshot-changes/` summarizes batch boundaries + rationales.
- [ ] If any batch was split-further or rejected, the original source-change PR was updated accordingly (the snapshot drift surfaced a real bug).

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| `cargo insta accept --all` (or equivalent bulk-accept) at any point. | The whole recipe exists to avoid this. Per [Q-042](../exemplars/QUOTE-BANK.md), encode the distinction, don't paper over it. |
| `INSTA_UPDATE=auto` in CI. | This silently accepts snapshots on CI; turns the snapshot oracle into a no-op. Per [Q-224](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-224--ccmd-20--honesty-in-harness-not-reviewer), the harness encodes discipline; auto-accept removes it. |
| Filing one bead for all 200 snapshots. | The graph becomes unparseable; per-batch sub-beads give the right granularity. |
| Skipping the per-snapshot sample reads. | The bug hides in *one* snapshot in the batch; the only way to catch it is to actually read sample diffs. |
| Accepting batches without re-running the conformance suite between batches. | A regressed snapshot in batch N can mask a regressed snapshot in batch N+1; per-batch verification breaks the masking. |
| "It's just a format change." | Per [Q-213](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-213--ccmd-921--static-pattern-false-positive-rule), grep-based audits produce pattern matches not proofs; "looks like format only" without reading end-to-end is the same fallacy. |
| Closing the bead before the docs/progress/snapshot-changes/ entry exists. | The next maintainer who sees a snapshot pattern they don't understand has no context; the doc IS the rationale archive. |
| Not splitting a batch whose sample diffs disagree with the rationale. | A batch you can't write a coherent rationale for is two batches in a trench coat. |

## Cross-references

- [../patterns/55-INSTA-GOLDEN-SNAPSHOTS.md](../patterns/55-INSTA-GOLDEN-SNAPSHOTS.md) — snapshot discipline.
- [../patterns/50-THREE-TIER-EQUIVALENCE.md](../patterns/50-THREE-TIER-EQUIVALENCE.md) — where snapshots sit in the equivalence hierarchy.
- [../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) — the differential oracle that catches behavioural regressions a snapshot might miss.
- [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) — "behaviour preserved" requires more than "snapshot updated".
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — the ratchet that catches a regression even after snapshots get accepted.
- [../exemplars/QUOTE-BANK.md § Q-042](../exemplars/QUOTE-BANK.md) — "encode the distinction, never paper over it".
- [../exemplars/QUOTE-BANK.md § Q-072](../exemplars/QUOTE-BANK.md) — closure-wave enumeration discipline.
- [../exemplars/QUOTE-BANK-V2-ADDITIONS.md § Q-224](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-224--ccmd-20--honesty-in-harness-not-reviewer) — auto-accept defeats the harness's honesty.
- Related motions: [`oracle-divergence-triage.md`](oracle-divergence-triage.md), [`cross-pillar-regression.md`](cross-pillar-regression.md), [`surface-gap-found.md`](surface-gap-found.md).
