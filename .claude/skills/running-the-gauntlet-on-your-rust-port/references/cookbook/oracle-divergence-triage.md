# oracle-divergence-triage

> An oracle test went red. Classify, minimize, bundle, propose a fix, ratchet — without rewriting half the planner because one query returned `[]` instead of `[(1)]`.

## Trigger

Any of:

- `scripts/run-conformance-suite.sh` reports a new `TrueDivergence` (not `Order` / `TypeAffinity` / `NullHandling` / `FloatingPoint` / `FalsePositive`).
- A `FailureBundle v1.0.0` was emitted under `<workspace>/round_<N>/conformance/failure_bundles/`.
- `bv --robot-insights | jq '.ConformanceDivergences[] | select(.classification == "TrueDivergence")'` is non-empty.
- Upstream reference version bump caused a previously-green test to go red (see [dependency-version-bump.md](dependency-version-bump.md) first — but if the divergence is on a behavior NOT covered by version notes, route here).

Do NOT enter this recipe if the divergence is classified `Order` / `TypeAffinity` / etc — those route through `⊙ Debounce-False-Positive` and the triage queue, not the conformance ledger.

## Operator Pipeline

```
⊙ DEBOUNCE-FALSE-POSITIVE   classify the divergence: is it TrueDivergence?
↓
⌘ REDUCE / MINIMIZE        delta-debug to 1-minimal with schema preservation
↓
⚠ ESCALATE-TO-FRESH-REPRO  emit FailureBundle with all 14 fields populated
↓
🧪 EXPERIMENT-DESIGN       file the hypothesis in CONFORMANCE_HYPOTHESIS_LEDGER.md
↓
⊕ ISOMORPHIC-REWRITE       enumerate ≥2 fixes that don't break adjacent behavior
↓
⚖ RATCHET-LOWER-BOUND     does the chosen fix raise the conformance lower bound?
↓
🪟 FRESH-EYES              two consecutive clean rounds before close
```

For ML-class projects with floating-point divergence under N ULP, also apply `🎚 Raise-ULP-Tolerance` BEFORE `⊕` — but only after `⌘` proves the divergence really is below the threshold and not a structural bug masquerading as a numerical one.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
SIGNATURE=<MismatchSignature hash from the failing run>
TEST_NAME=<the failing test, e.g., oracle_e2e::select_with_compound_subquery>

# 1. Classify the divergence
cd "$PORT"
"$WORKSPACE/scripts/run-conformance-suite.sh" "$PORT" "$WORKSPACE" --no-fuzz
# Inspect: the test report's MismatchClassification field. If not TrueDivergence, exit this recipe.

# 2. Minimize to 1-minimal
"$WORKSPACE/scripts/run-conformance-suite.sh" "$PORT" "$WORKSPACE" --no-fuzz
# Run the project's mismatch minimizer against the emitted FailureBundle.

# 3. Compute (or look up) the MismatchSignature for dedup
"$WORKSPACE/scripts/compute-mismatch-signature.sh" \
  "$WORKSPACE/round_$(cat $WORKSPACE/.round)/conformance/minimized/$TEST_NAME.json" \
  > "$WORKSPACE/mismatch_sigs/$TEST_NAME.sig"
# If this signature matches an existing bead, LINK don't open new
EXISTING_BEAD=$(br list --label "mismatch-sig:$(cat $WORKSPACE/mismatch_sigs/$TEST_NAME.sig)" --json --limit 1 | jq -r '(.issues // .)[0].id // empty')
if [[ -n "$EXISTING_BEAD" ]]; then
  echo "Same root cause as $EXISTING_BEAD — link instead of open."
  exit 0
fi

# 4. Verify the FailureBundle has all 14 fields
jq -r '
  .failure_type, .seed, .fixture_id, .schedule_fingerprint,
  .artifact_sha256, .db_page_previews, .wal_state_at_failure,
  .expected_vs_actual, .first_divergence_jsonptr, .git_sha,
  .toolchain_version, .platform, .feature_flags,
  .engines.subject_identity, .engines.reference_identity
' "$WORKSPACE/round_$(cat $WORKSPACE/.round)/conformance/failure_bundles/$TEST_NAME.json"
# Any null without an explicit "why partial" note is a fail.

# 5. File hypothesis BEFORE the fix
cat >> "$WORKSPACE/CONFORMANCE_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — oracle-div-${SIGNATURE:0:12} — investigating
- test: $TEST_NAME
- signature: $SIGNATURE
- classification: TrueDivergence
- hypothesis: <one-sentence proximate-cause guess>
- expected_signal: <which oracle-emitter field will change>
- falsifiability: <what minimal input would still diverge if the hypothesis is wrong>
- one_line_invocation: "$WORKSPACE/scripts/replay-failure.sh $TEST_NAME"
- results_inline: <fill after fix>
EOF

# 6. Create the bead
br create \
  --title "oracle-div-${SIGNATURE:0:12}" \
  --priority 1 \
  --type bug \
  --labels "pillar:conformance,lane:cc_1,recipe:oracle-divergence-triage,mismatch-sig:$SIGNATURE"

# 7. After fix, replay the bundle to confirm
"$WORKSPACE/scripts/replay-failure.sh" \
  "$WORKSPACE/round_$(cat $WORKSPACE/.round)/conformance/failure_bundles/$TEST_NAME.json"
# Expect: passed (was: failed). If shape-changed, the fix mutated the failure not eliminated it.

# 8. Ratchet
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
"$WORKSPACE/scripts/apply-ratchet.sh" "$WORKSPACE"

# 9. Fresh-eyes
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --bead "oracle-div-${SIGNATURE:0:12}"
```

## Beads to claim (or create)

- `oracle-div-<short-signature>` (this recipe creates it, OR you link to the existing bead with the same `mismatch-sig` tag).
- Dependency: `pattern:30-DIFFERENTIAL-V2-ENVELOPE` — every reproducer carries content-addressed `artifact_id`.
- Dependency: `pattern:45-MISMATCH-MINIMIZER` — minimization was applied with schema-preservation.
- Dependency: `pattern:90-FAILURE-BUNDLE` — bundle has all 14 fields (or a documented partial).
- Dependency: `pattern:95-FIRST-FAILURE-EXPLAINER` — `first_divergence_jsonptr` populated.
- Dependency (test): `test-oracle-div-<signature>` — non-regression test that loads the minimized fixture.
- Dependency (bench): `bench-oracle-div-<signature>-perf-neutral` — confirms the fix didn't regress the bench corresponding to the touched code path.
- Dependency (doc): `doc-oracle-div-<signature>-resolution` — entry under `docs/progress/conformance-resolutions/`.

## Exit Criteria

- [ ] Divergence classified as `TrueDivergence` (other classes go to triage queue, not the ledger).
- [ ] Minimized to 1-minimal with schema preserved; minimized fixture committed.
- [ ] `MismatchSignature` computed; dedup check passed (linked to existing OR new bead opened).
- [ ] `FailureBundle v1.0.0` with all 14 fields (or explicit "why partial" annotations).
- [ ] Hypothesis ledger entry filed; all six fields populated.
- [ ] ≥2 isomorphic rewrites enumerated; chosen one passes the 5-line proof.
- [ ] `replay-failure.sh` reports `passed (was: failed)` on the bundled fixture.
- [ ] `apply-ratchet.sh` emits `Allow`; conformance lower bound at or above the pre-divergence floor.
- [ ] Two fresh-eyes clean rounds before close.
- [ ] If the fix is rejected as "not worth it" (rare for `TrueDivergence`), the conformance negative-ledger entry names a retry-condition predicate AND the test is marked `#[ignore = "conformance-deferred:<bead_id>"]` (never silently disabled).

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| "Both engines returned an error — they agree." | Agreement-by-error-message-string. Both-error counts as agreement regardless of message; one-error-one-OK is a hard fail; same-error-different-class is `TrueDivergence`. |
| Classifying as `FalsePositive` because "it's only one query." | `FalsePositive` requires evidence. Defaulting to `TrueDivergence` and documenting the doubt is correct. |
| Skipping minimization because the repro "is already small." | If you didn't run the minimizer, you don't know it's 1-minimal. Five statements often reduce to one. |
| Disabling the test to make CI green. | Use `#[ignore = "conformance-deferred:<bead_id>"]` with the bead id, never bare `#[ignore]`. |
| Fixing the symptom in the comparator instead of the engine. | If the canonicalization step is hiding a real bug, you have an oracle-leak in the comparator. Audit `pattern:35-NORMALIZED-VALUE`. |
| Re-running the test until it passes once and calling it flaky. | Deterministic divergence stays deterministic across reruns. Flake-class divergences are still `TrueDivergence` if they reproduce >0% of the time on the same seed. |
| Skipping the FailureBundle because the fix was "obvious." | The bundle exists for the next agent. The fix was obvious to you in week-three context; in month-six it won't be. |
| Closing without the `bench-*-perf-neutral` dependency. | Many conformance fixes regress perf; the bench dep confirms the rewrite didn't pay for correctness with throughput. |

## Cross-references

- [../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md](../patterns/30-DIFFERENTIAL-V2-ENVELOPE.md) — content-addressed artifact_id.
- [../patterns/35-NORMALIZED-VALUE.md](../patterns/35-NORMALIZED-VALUE.md) — per-class normalized type.
- [../patterns/45-MISMATCH-MINIMIZER.md](../patterns/45-MISMATCH-MINIMIZER.md) — binary partition + schema guard.
- [../patterns/90-FAILURE-BUNDLE.md](../patterns/90-FAILURE-BUNDLE.md) — 14-field bundle.
- [../patterns/95-FIRST-FAILURE-EXPLAINER.md](../patterns/95-FIRST-FAILURE-EXPLAINER.md) — `first_divergence_jsonptr`.
- [../patterns/15-ENGINE-IDENTITY.md](../patterns/15-ENGINE-IDENTITY.md) — subject ≠ oracle guard.
- [../methodology/IDENTITY-AND-REPRODUCIBILITY.md](../methodology/IDENTITY-AND-REPRODUCIBILITY.md) — run identity stack.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — lower bound math.
- [../tooling/ORACLE-TOOLCHAIN.md](../tooling/ORACLE-TOOLCHAIN.md) — `MismatchClassification` schema + minimizer harness.
- Related motions: [e-process-rejection.md](e-process-rejection.md), [cross-pillar-regression.md](cross-pillar-regression.md), [dependency-version-bump.md](dependency-version-bump.md), [new-fault-class-discovered.md](new-fault-class-discovered.md).
