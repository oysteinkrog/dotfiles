# surface-gap-found

> FeatureUniverse reports `Missing` (or unhealthy `Partial`) on a release-blocking feature. Decide: implement, exclude with rationale, or downgrade the release claim.

## Trigger

Any of:

- `scripts/compute-feature-coverage.sh` per-family verdict drops below the per-class floor.
- A FeatureUniverse loader entry has `status = Missing` AND the feature is in a category with `release_blocker = true`.
- The coverage dashboard flips a family from `Pass` to `Fail` (or `Partial → Missing`).
- An upstream reference release added a new public surface item that's not yet in `parity_taxonomy.rs`.
- A user-reported bug bisects to "we don't implement this opcode/command/function."

Do NOT enter this recipe if the gap is on an item already marked `Excluded` — excluded items are tracked as coverage debt but don't require triage unless someone wants to flip to `Present`.

## Operator Pipeline

```
✦ ENUMERATE-SURFACE        is this gap really new, or did the reference move?
↓
★ PIN-REFERENCE-VERSION    (if the reference moved) re-pin contract version + audit
↓
🧪 EXPERIMENT-DESIGN       file a SURFACE_PARITY_HYPOTHESIS_LEDGER.md entry
↓
⊕ ISOMORPHIC-REWRITE       enumerate ≥2 implementation strategies OR exclusion rationale
↓
⚖ RATCHET-LOWER-BOUND     does the new feature raise the surface lower bound?
↓
🪟 FRESH-EYES              the exclusion rationale is the most adversarial code review target
```

The exclusion-with-rationale path is symmetric to the implement path; both must reach the ratchet step with evidence. Half-implemented features that round up to "present" are the most common surface-parity lie.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
FEATURE_ID=<the failing Feature, e.g., "pragma:auto_vacuum" or "command:OBJECT" or "function:torch.fft.fft2">
CATEGORY=<the category, from parity_score_contract.toml>

# 1. Confirm gap is current (reference version may have moved)
cd "$PORT"
"$WORKSPACE/scripts/compute-feature-coverage.sh" "$WORKSPACE" \
  --matrix "$WORKSPACE/docs/contracts/supported_surface_matrix.toml"
# Inspect: status + exclusion_rationale + weight

# 2. Re-enumerate against the live reference (verifies it's still a real gap)
case "$(jq -r '.detected_class' "$WORKSPACE/phase0_project_class.json")" in
  SQL-class)
    "$WORKSPACE/scripts/run-tcl-tests.sh" "$PORT" "$WORKSPACE" --filter "$FEATURE_ID"
    ;;
  RESP-class)
    "$WORKSPACE/scripts/verify-resp-protocol.sh" "$PORT" "$WORKSPACE" --command "$FEATURE_ID"
    ;;
  Numerical-Python-class)
    "$WORKSPACE/scripts/run-numpy-all-check.sh" "$PORT" "$WORKSPACE" --symbol "$FEATURE_ID"
    ;;
  ML-System-class)
    "$WORKSPACE/scripts/gradcheck.sh" "$PORT" "$WORKSPACE" --op "$FEATURE_ID"
    ;;
  HTTP-Protocol-class)
    "$WORKSPACE/scripts/openapi-schema-diff.sh" "$PORT" "$WORKSPACE" --endpoint "$FEATURE_ID"
    ;;
esac

# 3. File the hypothesis (implement OR exclude — both are hypotheses)
cat >> "$WORKSPACE/SURFACE_PARITY_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — surface-gap-$FEATURE_ID — investigating
- feature_id: $FEATURE_ID
- category: $CATEGORY
- weight: $(jq -r ".features[] | select(.id == \"$FEATURE_ID\") | .weight" $PORT/parity_taxonomy.json)
- status_now: $(jq -r ".features[] | select(.id == \"$FEATURE_ID\") | .status" $PORT/parity_taxonomy.json)
- hypothesis: implement-via-<strategy> | exclude-because-<rationale>
- expected_signal: <which test would go green | what the rationale will reference>
- falsifiability: <what would invalidate the implementation plan OR the exclusion rationale>
- one_line_invocation: <the test command that would show present>
- results_inline: <fill after decision>
EOF

# 4. Create the bead
br create \
  --title "surface-gap-$FEATURE_ID" \
  --priority 2 \
  --type feature \
  --labels "pillar:surface,lane:cc_3,recipe:surface-gap-found,feature:$FEATURE_ID,category:$CATEGORY"

# 5a. If implementing: enumerate isomorphic strategies (e.g., port reference, write from spec, polyfill via existing ops)
# Score each on rubric: Impact × Confidence / Effort >= 2.0

# 5b. If excluding: write the rationale ≥1 sentence; it must reference the reason class
# (out-of-scope-for-version, requires-external-dep, perf-cost-vs-benefit, ...) listed in
# taxonomy/FEATURE-UNIVERSE.md § Exclusion Rationale Classes.

# 6. Update parity_taxonomy.rs
$EDITOR "$PORT/crates/*/src/parity_taxonomy.rs"
# Either: change Feature::status to Present + add the implementation,
# OR: change to Excluded { rationale: "<sentence>", rationale_class: <enum> }.
# Loader will fail on sum(weights) != 1.0 — re-normalize if you changed weights.

# 7. Re-compute coverage + ratchet
"$WORKSPACE/scripts/compute-feature-coverage.sh" "$WORKSPACE"
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
"$WORKSPACE/scripts/apply-ratchet.sh" "$WORKSPACE"

# 8. Fresh-eyes — exclusion rationales especially
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --bead "surface-gap-$FEATURE_ID" --adversarial
```

## Beads to claim (or create)

- `surface-gap-<feature-id>` (this recipe creates it).
- Dependency: `pattern:105-FEATURE-UNIVERSE` — the loader-enforced `sum(weights) == 1.0` invariant.
- Dependency: `pattern:120-VERIFICATION-CONTRACT` — verification contract must close on the new evidence.
- If implementing — dependency: `pattern:115-CLOSURE-WAVE` — coordinated closure of related Missing items.
- Dependency (test): `test-surface-<feature-id>-oracle-e2e` — oracle test that goes from red to green.
- Dependency (bench): `bench-surface-<feature-id>-perf-floor` — confirms the implementation hits a floor throughput.
- Dependency (doc): `doc-surface-<feature-id>-rationale` (excluded path) OR `doc-surface-<feature-id>-implementation` (implement path).

## Exit Criteria

- [ ] Gap confirmed against live reference (not a stale FeatureUniverse).
- [ ] If reference moved: contract version re-pinned; affected categories audited.
- [ ] Hypothesis ledger entry filed with all six fields.
- [ ] Decision made: `implement` OR `exclude` (the latter requires a rationale referencing one of the documented rationale classes).
- [ ] If implementing: ≥2 isomorphic strategies enumerated; chosen one passes its oracle E2E.
- [ ] If excluding: rationale is ≥1 full sentence, references a rationale class, and is reviewed by an independent fresh-eyes pass.
- [ ] `parity_taxonomy.rs` updated; loader rejects no longer.
- [ ] `sum(weights) == 1.0` per category preserved (loader catches violations).
- [ ] `apply-ratchet.sh` emits `Allow`; surface lower bound at or above the pre-gap floor.
- [ ] Two fresh-eyes clean rounds before close.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| "It's partial, that's basically present." | `Partial` never rounds up to `Present`. Excluded-as-debt still counts against a strict-100% claim. |
| Exclusion rationale: "TODO" or "later" or "out of scope." | All three are vocabulary failures. The rationale must reference one of the documented rationale classes from `taxonomy/FEATURE-UNIVERSE.md`. |
| Implementing the feature without the oracle E2E. | The implementation hasn't been verified against the reference; you've added code, not coverage. |
| Bumping `weight` to hide the gap. | `sum(weights) == 1.0` per category is loader-enforced; rebalancing without a version bump trips the `FeatureUniverse loader rejects on sum(weights) != 1.0` escalation rule. |
| Closing the bead before the `doc-*` dep. | The next maintainer re-discovers the gap because the rationale lives in chat. |
| Self-signing an exclusion. | Exclusions need a SECOND-PARTY fresh-eyes review; the author cannot rationalize their own deferral. |
| Implementing a polyfill that calls into the reference at runtime. | That's not implementing — it's wrapping. The Feature stays `Partial` until the implementation is in-port code. |
| Hand-editing `parity_taxonomy.json` instead of the `.rs` source. | The JSON is a build artifact; the `.rs` is the source of truth. Edits to JSON evaporate on next build. |

## Cross-references

- [../patterns/105-FEATURE-UNIVERSE.md](../patterns/105-FEATURE-UNIVERSE.md) — FeatureUniverse spec.
- [../patterns/110-INVARIANT-CATALOG.md](../patterns/110-INVARIANT-CATALOG.md) — paired invariant entries.
- [../patterns/115-CLOSURE-WAVE.md](../patterns/115-CLOSURE-WAVE.md) — coordinated multi-feature closure.
- [../patterns/120-VERIFICATION-CONTRACT.md](../patterns/120-VERIFICATION-CONTRACT.md) — pass/fail × allowed/blocked matrix.
- [../taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md) — exclusion-rationale classes.
- [../taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md) — per-class enumeration rules.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — surface-pillar ratchet.
- Related motions: [dependency-version-bump.md](dependency-version-bump.md), [oracle-divergence-triage.md](oracle-divergence-triage.md), [cross-pillar-regression.md](cross-pillar-regression.md).
