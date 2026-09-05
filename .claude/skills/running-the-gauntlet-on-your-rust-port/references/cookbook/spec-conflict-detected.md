# spec-conflict-detected

> Two (or more) spec sources cited in `spec_version_contract.toml#/[[spec_sources]]` make contradictory assertions about the same behavior. Phase 2 cannot complete; Phase 3 cannot start. Canonicalize one source-of-truth before any further oracle wiring.

This is a Greenfield-Rust-class-specific motion — it doesn't exist for ports (the upstream reference IS the canonical spec). For greenfield projects with multiple spec sources (`AGENTS.md § Hard Requirements`, `docs/spec/v1/specification.md`, `COMPREHENSIVE_PLAN_*.md`, `README.md § Hard Requirements`), this recipe handles the contradiction that surfaces when the spec-extractor finds two assertions about the same behavior that disagree.

Cross-link: [`methodology/SPEC-PINNING-FOR-GREENFIELD.md § 4 Spec-conflict detection`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md), [`methodology/GREENFIELD-ADAPTATION.md`](../methodology/GREENFIELD-ADAPTATION.md), [`first-bug-hunt/greenfield-rust-class.md § 1`](../first-bug-hunt/greenfield-rust-class.md).

## Trigger

Any of:

- `scripts/check-spec-coherence.sh` exits nonzero with output listing conflicting `[SPEC-NNN]` pairs.
- The Phase 2 scope-decider subagent writes `<workspace>/phase2_spec_conflict.md` with one or more contradiction entries.
- `oracle_preflight_doctor.rs` (greenfield variant) refuses to certify with `failures: ["spec_conflict_detected"]`.
- After a spec edit, `scripts/bless-spec.sh` detects a verifier in `spec_oracle.rs` that now disagrees with another verifier on the same scenario class.
- A `MismatchClassification::SpecConflict { source_a, source_b, tag }` surfaces in a conformance run (per the greenfield-specific MismatchClassification extension documented in [`first-bug-hunt/greenfield-rust-class.md § 1`](../first-bug-hunt/greenfield-rust-class.md)).

Do NOT enter this recipe for a single-source spec inconsistency (e.g., one document with two contradictory paragraphs) — that's an editing bug; the user resolves it inline. This recipe is for the harder case of **inter-document** contradiction where one document was authored without knowledge of another.

## Operator Pipeline

```
⚠ ESCALATE-TO-FRESH-REPRO     bundle every contradiction pair with verbatim quotes
↓
⌘ REDUCE / MINIMIZE           narrow each conflict to the minimal disagreeing assertion pair
↓
✦ ENUMERATE-SURFACE          map the conflict to its FeatureUniverse rows (which behaviors are ambiguous?)
↓
🧪 EXPERIMENT-DESIGN         file the canonicalization hypothesis BEFORE editing the spec
↓
★ PIN-REFERENCE-VERSION      bump spec_version_contract.toml#/meta.revision after resolution
↓
🪟 FRESH-EYES                second reviewer confirms the canonical version IS unambiguous
```

The pipeline is shorter than `oracle-divergence-triage` because there's no engine-fix step — the engine is correct relative to one source; the fix is in the spec, not in the code.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>

# 1. Detect every contradiction pair
"$WORKSPACE/scripts/check-spec-coherence.sh" "$PORT" \
  > "$WORKSPACE/phase2_spec_conflict.md"

# Inspect: each entry has source_a + source_b + verbatim assertions + resolution_needed_from_user.
test -s "$WORKSPACE/phase2_spec_conflict.md" || { echo "no conflicts; exit recipe"; exit 0; }

# 2. For each conflict, minimize to the smallest disagreeing pair
for CONFLICT_ID in $(jq -r '.conflicts[].id' "$WORKSPACE/phase2_spec_conflict.md"); do
  "$WORKSPACE/scripts/minimize-spec-conflict.sh" \
    --workspace "$WORKSPACE" \
    --conflict-id "$CONFLICT_ID" \
    --output "$WORKSPACE/spec_conflicts/$CONFLICT_ID.minimized.md"
done

# 3. Map each conflict to its FeatureUniverse rows
"$WORKSPACE/scripts/map-conflicts-to-features.sh" \
  --conflict-dir "$WORKSPACE/spec_conflicts/" \
  --feature-universe "$PORT/src/parity_taxonomy.rs" \
  --output "$WORKSPACE/spec_conflicts/feature_impact_map.json"

# 4. File the canonicalization hypothesis ledger entry BEFORE editing
cat >> "$WORKSPACE/CONFORMANCE_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — spec-conflict-canonicalize — investigating
- conflict_count: $(jq -r '.conflicts | length' "$WORKSPACE/phase2_spec_conflict.md")
- conflict_ids: $(jq -r '.conflicts[].id' "$WORKSPACE/phase2_spec_conflict.md" | tr '\n' ',' | sed 's/,$//')
- hypothesis: <one-sentence canonical-source proposal; e.g., "AGENTS.md § Hard Requirements is authoritative; docs/spec/v1/ amended to defer">
- expected_signal: phase2_spec_conflict.md empty after edits
- falsifiability: re-running check-spec-coherence.sh after edits still surfaces conflicts
- one_line_invocation: "$WORKSPACE/scripts/check-spec-coherence.sh $PORT"
- results_inline: <fill after canonicalization>
EOF

# 5. Create the epic + sub-beads
br create \
  --title "spec-conflict-canonicalize-r$(cat $WORKSPACE/.round)" \
  --priority 0 \
  --type epic \
  --labels "pillar:conformance,lane:cc_0,recipe:spec-conflict-detected,phase:2"

EPIC_ID=$(br list --label "recipe:spec-conflict-detected" --json --limit 1 | jq -r '(.issues // .)[0].id')

# One bead per conflict pair — each may have different canonicalization story
for CONFLICT_ID in $(jq -r '.conflicts[].id' "$WORKSPACE/phase2_spec_conflict.md"); do
  br create \
    --title "spec-conflict-$CONFLICT_ID-canonicalize" \
    --priority 0 \
    --type task \
    --labels "pillar:conformance,lane:cc_0,recipe:spec-conflict-detected,conflict-id:$CONFLICT_ID" \
    --depends-on "$EPIC_ID"
done

# 6. ESCALATE TO USER — the canonicalization decision is HUMAN territory.
#    Do NOT silently pick a winner; do NOT delete either source; do NOT
#    refactor both to agree on a third version without authorization.
cat > "$WORKSPACE/USER_DECISION_NEEDED.md" <<EOF
# Spec-conflict canonicalization needed

Phase 2 cannot complete; Phase 3 cannot start. The following spec sources
disagree on these assertions:

$(cat $WORKSPACE/spec_conflicts/*.minimized.md)

Please choose ONE of these resolutions per conflict:

1. CANONICALIZE source A; amend source B to defer.
2. CANONICALIZE source B; amend source A to defer.
3. REFINE both into a NEW shared assertion (write the new version inline).
4. SPLIT into two non-overlapping assertions (specify the disjoint domains).

Then signal resolution by editing each conflict entry's \`canonical_source\`
field in phase2_spec_conflict.md and running:

  "$WORKSPACE/scripts/bless-spec.sh" --apply-canonicalization
EOF

# 7. USER edits the spec sources per their resolution. Then:
"$WORKSPACE/scripts/bless-spec.sh" --apply-canonicalization

# This script:
#   - Recomputes every spec source's SHA-256
#   - Bumps spec_version_contract.toml#/meta.revision (e.g., 1 → 2)
#   - Re-runs check-spec-coherence.sh; refuses to proceed if any conflict remains
#   - Re-extracts [SPEC-NNN] tags; flags any tags that lost their source as deletion-candidates

# 8. Verify the conflict is gone
"$WORKSPACE/scripts/check-spec-coherence.sh" "$PORT"
# Expect: zero output (or "no conflicts detected").

# 9. Re-run the preflight doctor
"$WORKSPACE/scripts/oracle-preflight-doctor.sh" "$PORT" --workspace "$WORKSPACE"
# Expect: certifying: true, aggregate_outcome: green.

# 10. Fresh-eyes pass: a second reviewer reads the canonicalized spec end-to-end
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --bead "$EPIC_ID" --domain spec-canonicalization
```

## Beads to claim (or create)

- Epic: `spec-conflict-canonicalize-r<round>`.
- Sub-beads: `spec-conflict-<conflict-id>-canonicalize` (one per conflict pair).
- Dependency: `pattern:10-REFERENCE-PINNING` — the original pin pattern; greenfield analog applies.
- Dependency: `methodology/SPEC-PINNING-FOR-GREENFIELD § 4` — the canonicalization protocol.
- Dependency (CI): `gate-spec-coherence` — `scripts/check-spec-coherence.sh` runs in CI on every PR touching spec sources.
- Dependency (doc): `doc-spec-conflict-<id>-resolution` — entry under `docs/progress/spec-conflicts/` summarizing the conflict, the user's chosen resolution, and the canonical version.

## Exit Criteria

- [ ] `phase2_spec_conflict.md` is empty (no remaining contradiction entries).
- [ ] `spec_version_contract.toml#/meta.revision` bumped; every `[[spec_sources]]` SHA-256 reflects the post-canonicalization content.
- [ ] `docs/spec/SPEC-TAGS.md` regenerated; every `[SPEC-NNN]` tag has exactly ONE source.
- [ ] `oracle_preflight_doctor.rs` returns green.
- [ ] User's chosen resolution recorded in `docs/progress/spec-conflicts/<conflict-id>.md` with verbatim before/after text and the user's authorizing message.
- [ ] CI gate `scripts/check-spec-coherence.sh` wired into `.github/workflows/` so future spec edits don't reintroduce contradictions silently.
- [ ] Fresh-eyes reviewer confirms the canonicalized version is unambiguous and matches the user's expressed intent.
- [ ] Phase 3 (`greenfield-oracle-wirer`) can now proceed.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| Picking the "newer" source automatically. | Recency is not authority. The user authored both at different times; only the user knows which was meant to supersede. |
| Editing one source to match the other without asking. | This is an unauthorized canonicalization. The lost version may have been the correct one. |
| Treating the conflict as a `TrueDivergence` and routing to `oracle-divergence-triage`. | Engine is fine; spec is broken. The triage queue is for engine bugs; this is a contract bug. |
| Disabling one verifier to "pass CI". | This hides the contradiction. The conflict reasserts on the next round and is now harder to find because the audit trail is shorter. |
| Adding a third spec source to "explain" the conflict. | Increases the conflict surface from 2-way to 3-way. Canonicalize, don't add. |
| Skipping the fresh-eyes pass because "the fix was small". | Canonicalization decisions look small but reshape the entire FeatureUniverse downstream. A second reviewer catches the unintended scope changes. |
| Promoting Charter-only assertions (aspirational, non-testable) into `[SPEC-NNN]` tags to "resolve" the conflict by making both verifiable. | Verifiability is the entry criterion for `[SPEC-NNN]`; if the assertion remains aspirational, move BOTH versions to `docs/CHARTER.md` and remove the tag entirely. See [`methodology/SPEC-PINNING-FOR-GREENFIELD § 5`](../methodology/SPEC-PINNING-FOR-GREENFIELD.md). |
| Treating an `AGENTS.md` "Hard Requirement" as override-able by a later `docs/spec/v1/` revision without the user's say-so. | `AGENTS.md` is typically the user's standing standing-order; the user must explicitly bless any de-prioritization. |

## Cross-references

- [../methodology/SPEC-PINNING-FOR-GREENFIELD.md § 4 Spec-conflict detection](../methodology/SPEC-PINNING-FOR-GREENFIELD.md)
- [../methodology/GREENFIELD-ADAPTATION.md § 5 Spec-as-Oracle authoring](../methodology/GREENFIELD-ADAPTATION.md)
- [../first-bug-hunt/greenfield-rust-class.md § 1](../first-bug-hunt/greenfield-rust-class.md)
- [../taxonomy/PROJECT-CLASSES.md § Greenfield-Rust-class](../taxonomy/PROJECT-CLASSES.md)
- [../patterns/10-REFERENCE-PINNING.md](../patterns/10-REFERENCE-PINNING.md) — the original port-style pin; this recipe is the greenfield analog for the spec-pinning case.
- [../patterns/105-FEATURE-UNIVERSE.md](../patterns/105-FEATURE-UNIVERSE.md) — feature rows affected by the canonicalization.
- [../../subagents/greenfield-oracle-wirer.md](../../subagents/greenfield-oracle-wirer.md) — blocked until this recipe completes.
- Related motions: [spec-tag-orphan-cleanup.md](spec-tag-orphan-cleanup.md), [single-crate-vs-workspace-decision.md](single-crate-vs-workspace-decision.md), [dependency-version-bump.md](dependency-version-bump.md).
