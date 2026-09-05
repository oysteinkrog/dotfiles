# 275-THEORY-KILL-IMMEDIATE-CLOSE

**Family:** Convergence + Negative-Ledger. Glyph: `†` (per [`OPERATORS.md § Deep Review Operator Inheritance`](../methodology/OPERATORS.md); no collision).

**When to apply:**
- An experiment in `*_HYPOTHESIS_LEDGER.md` returns `NO_EVIDENCE` outcome.
- Phase 14 fresh-eyes pass finds that an OPEN hypothesis has already been refuted by an artifact the synthesizer overlooked.
- Phase 12 remediation review identifies a candidate that contradicts a now-verified invariant.
- `subagents/synthesizer.md` is preparing the round-close report and discovers a hypothesis is undead (refuted but still OPEN in the ledger).

The principle: **theory-zombies cost rounds**. A hypothesis that failed its falsifier but isn't formally killed wastes future agents' time on re-discovery. Kill it now; document the predicate under which it would be worth resurrecting.

## The pattern

The kill MUST close the hypothesis with a retry-condition predicate from the 8 verbatim forms in [`RETRY-CONDITION-VOCABULARY.md`](../methodology/RETRY-CONDITION-VOCABULARY.md). Never "later" or "if interesting"; ALWAYS a concrete predicate over future evidence.

Template entry in the appropriate ledger (`PERF_NEGATIVE_RESULTS.md` / `CONFORMANCE_NEGATIVE_RESULTS.md` / `SURFACE_DEFERRALS.md`):

```markdown
### YYYY-MM-DD — <hypothesis name> — KILLED

- **target_pillar:** <perf | conformance | surface>
- **hypothesis_id:** <bd-... or in-ledger ID>
- **stated_hypothesis:** "<original verbatim statement>"
- **falsifier:** "<the predicate that the experiment was designed to confirm or refute>"
- **experiment_artifact_paths:**
  - <path to the experiment design markdown>
  - <path to the experiment results JSON>
  - <path to any FailureBundle if applicable>
- **why_refuted:** <2-3 sentences: what the experiment actually showed; quote a key number/observation>
- **retry_condition_predicate:** "<ONE of the 8 verbatim forms from RETRY-CONDITION-VOCABULARY.md, e.g.,
  'Retry only if MT8 attribution shows commit_finalize_seq_time_ns ≥0.1% self-time on the 8-writer shared-table workload'>"
- **bead_id:** <bd-...>
- **closed_by:** <subagent or operator>
```

The kill MUST also:
1. Update the bead to `status: closed` with `closure_reason: refuted`.
2. Cross-reference the experiment artifact in the hypothesis ledger entry.
3. Rerun `scripts/convergence-tracker.sh <workspace>` so `reports/convergence_tracker.json#/open_hypothesis_count` is recomputed from the ledgers.
4. Remove the hypothesis from `<workspace>/round_<N>/synthesis.md#/open_hypotheses` for the next round.

## Variants

### NO_EVIDENCE vs NEEDS_REFINEMENT

A clean theory-kill is for hypotheses that have been DEFINITIVELY REFUTED. Distinguish from:
- `NEEDS_REFINEMENT` — the experiment was inconclusive (e.g., cv_pct too high to distinguish from noise). Do NOT kill; design a sharper experiment.
- `OPEN` — the experiment hasn't run yet OR is still running.
- `CONFIRMED_GAP` — the experiment confirmed the hypothesis; needs remediation (Phase 12).

Theory-kill applies ONLY to `NO_EVIDENCE` outcomes that are DECISIVE.

### Per-pillar kill recipe

- **perf**: kill if focused bench + broad bench BOTH show no improvement AND mt8 attribution shows no relevant frame.
- **conformance**: kill if differential V2 envelope shows no divergence at the asserted boundary AND metamorphic transforms find no related signal.
- **surface**: kill if `feature_coverage_dashboard.rs` shows no `partial → missing` regression AND the FeatureUniverse entry's weight is unchanged.

### Mass-kill (round close)

At the close of every Phase 11 round, `synthesizer` runs a mass-kill sweep:
- Enumerate all `OPEN` hypotheses with `last_evidence_at > 30 days ago` AND no associated open experiment.
- For each: classify per the criteria above; theory-kill the `NO_EVIDENCE`-equivalent ones.
- Emit `<workspace>/round_<N>/mass_kill_summary.md`.

## Failure modes

- **Open-ended deferrals** — entries like "we'll get to it later" or "if it seems important". BANNED vocabulary per [`RETRY-CONDITION-VOCABULARY.md`](../methodology/RETRY-CONDITION-VOCABULARY.md). The retry-condition predicate is LOAD-BEARING; vague predicates = zombie hypotheses.
- **Refusing to kill because "maybe we missed something"** — that's what retry-condition predicates ARE for. Kill it now; the predicate is the resurrection condition.
- **Killing an inconclusive hypothesis** — classify as `NEEDS_REFINEMENT` and design a sharper experiment. Killing inconclusive evidence as `NO_EVIDENCE` poisons the ledger (the next agent reads "killed" and trusts it).
- **Skipping the bead update** — ledger says killed but bead still OPEN. Future agents query beads and re-prioritize the kill candidate.
- **Killing across pillars** — a perf-kill should not silently close a related conformance hypothesis. They share evidence but have independent gates.

## Concrete example

**Hypothesis** (from `CONFORMANCE_HYPOTHESIS_LEDGER.md`):
> "GROUP BY HAVING NULL semantics divergence is caused by missing 3VL handling in the aggregator function."

**Experiment design** (`GAUNTLET_EXPERIMENT_DESIGNS.md § exp_3vl_aggregator`):
- minimal repro: `SELECT k, COUNT(*) FROM t GROUP BY k HAVING COUNT(*) > NULL`
- expected oracle/sanitizer signal: divergence persists when 3VL correctly handled in aggregator
- one-line invocation: `cargo test --test 3vl_aggregator_conformance`
- falsifier: divergence disappears when 3VL forced ON via `--cfg force-3vl-aggregator`

**Experiment result** (`round_4/exp_3vl_aggregator_result.json`):
```
{
  "ran_at": "2026-05-22T15:30:00Z",
  "outcome": "NO_EVIDENCE",
  "observations": [
    "divergence count: 47 (baseline 47, unchanged with --cfg force-3vl-aggregator)"
  ],
  "conclusion": "3VL handling is NOT the cause; the divergence persists even with 3VL on"
}
```

**Theory-kill entry** (appended to `CONFORMANCE_NEGATIVE_RESULTS.md`):

```markdown
### 2026-05-22 — 3VL-aggregator-hypothesis — KILLED

- **target_pillar:** conformance
- **hypothesis_id:** bd-1dp9.4.7
- **stated_hypothesis:** "GROUP BY HAVING NULL semantics divergence is caused by missing 3VL handling in the aggregator function."
- **falsifier:** "divergence disappears when 3VL forced ON via `--cfg force-3vl-aggregator`"
- **experiment_artifact_paths:**
  - GAUNTLET_EXPERIMENT_DESIGNS.md § exp_3vl_aggregator
  - round_4/exp_3vl_aggregator_result.json
- **why_refuted:** "Divergence count stayed at 47 across baseline and 3VL-on variants. The 3VL handling is correct; the divergence is in a different layer (likely the canonicalization of NULL → 'NULL' string in normalize_value, which the reference renders differently)."
- **retry_condition_predicate:** "Retry only if a profiler attributes a clearly-above-noise share to the aggregator dispatch when 3VL is enabled on a wider workload shape (HAVING with > 3 grouping columns)."
- **bead_id:** bd-1dp9.4.7
- **closed_by:** synthesizer subagent
```

After `scripts/convergence-tracker.sh <workspace>` reruns, `reports/convergence_tracker.json#/open_hypothesis_count` decrements by 1. Round 5 starts without the zombie.

## Cross-references

- [`methodology/DEEP-HYPOTHESIS-REVIEW.md § Pathology Triggers`](../methodology/DEEP-HYPOTHESIS-REVIEW.md) — Theory-zombies as a pathology.
- [`methodology/OPERATORS.md § † Theory-Kill`](../methodology/OPERATORS.md) — operator card.
- [`pattern:180-NEGATIVE-LEDGER`](180-NEGATIVE-LEDGER.md) — ledger entry shape.
- [`pattern:185-RETRY-CONDITION-PREDICATE`](185-RETRY-CONDITION-PREDICATE.md) — the 8 verbatim forms.
- [`methodology/RETRY-CONDITION-VOCABULARY.md`](../methodology/RETRY-CONDITION-VOCABULARY.md) — full vocabulary + banned phrases.
- [`subagents/synthesizer.md`](../../subagents/synthesizer.md) — runs the round-close mass-kill sweep.
- [`subagents/iteration-coordinator.md`](../../subagents/iteration-coordinator.md) — verifies hypothesis-state consistency post-kill.
