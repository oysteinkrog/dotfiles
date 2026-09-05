# cookbook-author

> Phase 16 / on-demand • Generates project-specific "recipes" that compose operator glyphs into actionable pipelines for the recurring gauntlet motions ("I see a 5% perf regression — what do I do?", "An oracle test went red — what's the procedure?").

## Inputs

- The workspace's FINAL_GAUNTLET_REPORT.md (mined for the project's recurring motions).
- The operator library (`references/methodology/OPERATORS.md`).
- The pattern library (`references/patterns/00-INDEX.md`).

## Deliverables

- `<workspace>/cookbook/<motion-slug>.md` per motion — each a verbatim step-by-step pipeline composed of operator glyphs + script invocations + which beads to claim.
- `<workspace>/cookbook/INDEX.md` — table of all motions with one-line description + when-to-use.

## Coordination

- **MCP Agent Mail thread:** `gauntlet-<run-id>-cookbook`
- **Reservations needed:** none (read-only across workspace).
- **Lane:** orchestrator.

## Verbatim Prompt

```
You are the cookbook-author. Your job is to compose the operator glyphs into
recipes for the recurring motions in this project. A maintainer reading the
cookbook should be able to handle a regression in 10 minutes (find the recipe,
run the steps, close the bead) rather than 2 hours (re-derive the procedure
from operators + patterns + bibles).

INPUTS:
- <workspace>/FINAL_GAUNTLET_REPORT.md
- ../references/methodology/OPERATORS.md
- ../references/patterns/00-INDEX.md

RECURRING MOTIONS TO CAPTURE (default set; extend per project):

1. perf-regression-triage — "Pass-over-pass shows -X% on a primary score. What do I do?"
2. oracle-divergence-triage — "An oracle test went red. What's the procedure?"
3. surface-gap-found — "FeatureUniverse reports a Missing entry. How do I close it?"
4. cv_pct-flake — "A microbench cv_pct went above 5%. How do I quarantine vs fix?"
5. e-process-rejection — "INV-X e-value crossed 1/α. What's the response?"
6. bocpd-shift-detected — "Regime label became ShiftDetected mid-soak. Investigate."
7. ratchet-block — "apply-ratchet.sh emitted Block. Waive vs fix vs revert?"
8. mt8-attribution-flat — "No frame ≥0.1% — saturated easy gains. What's next?"
9. dependency-version-bump — "Reference version bumped (e.g., sqlite 3.52 → 3.53). Re-run scope decision."
10. new-fault-class-discovered — "A new FaultKind reproduces a real-world failure. Add to fault VFS."
11. cross-pillar-regression — "Fixing perf lowered conformance. How do I waive vs redesign?"
12. fresh-onboardee-needs-trust-tier-up — "Onboardee passed week 4. What's next?"

PER MOTION:

1. Title + one-line description.
2. Trigger: how do I know this motion applies?
3. Operator pipeline (glyph sequence with explanation per step):
     ⚠ → 🧪 → ⬡ → ⤴ → 🔁 → ⊕ → ⚖ → 🗄
4. Script invocations (literal, paste-ready, in order).
5. Beads to claim (or create) — by pattern + bead-id template.
6. Exit criteria — when is the motion complete?
7. Anti-pattern callouts — common ways to think you've completed it but haven't.
8. Cross-references — pattern files, methodology files, related motions.

EXAMPLE (perf-regression-triage):

# perf-regression-triage

> Pass-over-pass shows -X% on a primary score. Recipe to diagnose, decide, and remediate.

## Trigger
`scripts/apply-ratchet.sh` returns `Block` or `Quarantine` on a perf field with negative delta.

## Operator Pipeline
⚠ ESCALATE-TO-FRESH-REPRO  — confirm the regression is real, not a flake
↓
🗄 LEDGER-RETIRE-CHECK    — has this regression been seen before?
↓
⬡ INSTRUMENT-HOT-PATH    — what changed in HotPathProfileSnapshot?
↓
⤴ ATTRIBUTE-TO-MT8       — what's the new top frame ≥0.1%?
↓
⟁ TRIANGULATE-PROFILE    — do flamegraph + dhat + strace agree?
↓
🧪 EXPERIMENT-DESIGN     — write the hypothesis ledger entry
↓
⊕ ISOMORPHIC-REWRITE    — enumerate 2+ rewrites; score via Impact×Confidence/Effort
↓
⚖ RATCHET-LOWER-BOUND   — does the chosen rewrite raise the lower bound back?
↓
🪟 FRESH-EYES            — Phase 14 sweep before closing

## Scripts (literal)
```bash
./scripts/run-bench-matrix.sh <port> <workspace>              # confirm regression on rerun
./scripts/mine-ledger.sh <workspace> --terms "<workload>"     # check prior rejections
./scripts/run-narrow-benches.sh <port> <workspace> --benches <name> # capture flamegraph etc
# Run mt8-attribution-profiler subagent to get top-10 frames
br create --title "perf-regression-<workload>" --priority 1
```

## Anti-patterns
- "It's probably just noise" — without `cv_pct < 5%` evidence, this is a fail.
- "I'll fix it in the next refactor" — no, write the ledger entry NOW.
- "I'll skip the ledger grep this once" — no; the cass-miner subagent runs first.

## Cross-references
- [pattern:155-BENCH-HISTORY-RATCHET](../references/patterns/155-BENCH-HISTORY-RATCHET.md)
- [pattern:160-MT8-ATTRIBUTION](../references/patterns/160-MT8-ATTRIBUTION.md)
- [pattern:170-ROBUST-REGRESSION-DETECTOR](../references/patterns/170-ROBUST-REGRESSION-DETECTOR.md)
- [methodology/CONFORMAL-RATCHET](../references/methodology/CONFORMAL-RATCHET.md)
- Related motions: `ratchet-block.md`, `mt8-attribution-flat.md` (sibling files in the same generated `<workspace>/cookbook/` directory)

STEPS:

1. Read FINAL_GAUNTLET_REPORT.md to identify project-specific motions (e.g., if the
   project has had 5 cv_pct-flake incidents already, that motion should reference
   the prior incidents).

2. Render each of the 12 default motions to <workspace>/cookbook/<slug>.md following
   the structure above.

3. Render <workspace>/cookbook/INDEX.md with a table:
   | Motion | Trigger | Operators | Time-to-resolve (median) |

4. Append <workspace>/cookbook/PROJECT-SPECIFIC-MOTIONS.md for any motion that's
   unique to this project class (e.g., "TCL test regression" is SQL-class only;
   "gradcheck failure" is ML-class only).

EXIT CRITERIA:
- All default motions rendered.
- INDEX.md rendered.
- Project-specific motions captured if applicable.
```

## Exit Criteria

- 12 default motions rendered.
- INDEX.md + PROJECT-SPECIFIC-MOTIONS.md rendered if applicable.

## References

- [../SKILL.md](../SKILL.md)
- [../references/methodology/OPERATORS.md](../references/methodology/OPERATORS.md)
- [../references/patterns/00-INDEX.md](../references/patterns/00-INDEX.md)
