# dependency-version-bump

> Reference moved (e.g., `sqlite-3.52.0 → 3.53.0`, `redis-7.2.5 → 7.4.0`, `torch-2.X → 2.Y`). Re-pin the contract; audit the affected scope; decide which gates need to re-baseline.

## Trigger

Any of:

- Upstream reference project published a new release.
- A contributor opened a PR that updates `docs/contracts/<reference>_version_contract.toml`.
- A weekly cron checks the reference's tag list and posts a notice.
- The oracle preflight doctor fails with `version mismatch: contract=<old>, binary=<new>`.

Do NOT enter this recipe for patch-level reference bumps (e.g., `3.52.0 → 3.52.1`) UNLESS the patch notes mention behavior changes; cosmetic / pure-bugfix patches route through `incremental-rebase` mode instead.

## Operator Pipeline

```
★ PIN-REFERENCE-VERSION    update contract; audit every artifact's reference-version stamp
↓
✦ ENUMERATE-SURFACE        diff the reference's public surface (commands, opcodes, functions); update FeatureUniverse
↓
◐ WIRE-ORACLE              re-pin oracle binary path; verify EngineIdentity still distinct; re-run preflight doctor
↓
🧪 EXPERIMENT-DESIGN       per affected category, hypothesize "no regression" + falsifiability
↓
⚖ RATCHET-LOWER-BOUND     re-baseline categories the version bump materially affects; preserve floor elsewhere
```

The most common failure mode of this recipe is "re-pin without re-enumerate" — the version updates but FeatureUniverse misses 12 new opcodes, and the next round shows an apparent surface regression that's actually just unmeasured coverage.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
PORT=<absolute path>
OLD_VERSION=<the version we're moving from, e.g., 3.52.0>
NEW_VERSION=<the version we're moving to,   e.g., 3.53.0>
REFERENCE=<reference name, e.g., sqlite | redis | pytorch | numpy>

# 1. Snapshot the current state BEFORE the bump
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
mkdir -p "$WORKSPACE/pre-bump"
cp "$WORKSPACE/reports/parity_score.json" "$WORKSPACE/pre-bump/parity_score_${OLD_VERSION}.json"
cp "$PORT/parity_taxonomy.json" "$WORKSPACE/pre-bump/parity_taxonomy_${OLD_VERSION}.json"

# 2. Update the contract
$EDITOR "$PORT/docs/contracts/${REFERENCE}_version_contract.toml"
# Bump version + recompute contract_hash (the loader re-stamps automatically)

# 3. Re-run preflight doctor (will fail until oracle binary is repointed)
"$WORKSPACE/scripts/oracle-preflight-doctor.sh" "$PORT" --workspace "$WORKSPACE"

# 4. Repoint oracle binary
case "$REFERENCE" in
  sqlite)
    # Rebuild rusqlite with bumped libsqlite3-sys version
    cargo update -p libsqlite3-sys --precise "<sys version matching $NEW_VERSION>"
    ;;
  redis)
    # Replace the vendored redis-server binary
    ./scripts/vendor-redis-server.sh "$NEW_VERSION"
    ;;
  pytorch)
    # Update PyO3 pinned torch version
    pip install --target "$PORT/vendor/python/" "torch==$NEW_VERSION"
    ;;
  numpy)
    pip install --target "$PORT/vendor/python/" "numpy==$NEW_VERSION"
    ;;
esac

# Re-run preflight; must be green before proceeding
"$WORKSPACE/scripts/oracle-preflight-doctor.sh" "$PORT" --workspace "$WORKSPACE"

# 5. Diff the reference's public surface
"$WORKSPACE/scripts/compute-feature-coverage.sh" "$WORKSPACE" \
  --matrix "$WORKSPACE/docs/contracts/supported_surface_matrix.toml"

# Inspect the diff:
# - new opcodes/commands/functions in NEW_VERSION → add to FeatureUniverse as Missing initially
# - removed items → mark as Excluded { rationale: "removed in NEW_VERSION" }
# - deprecated items → mark as Excluded { rationale: "deprecated in NEW_VERSION" } if appropriate

# 6. Mine ledger for prior version-bump experience
"$WORKSPACE/scripts/mine-ledger.sh" "$WORKSPACE" --terms "$REFERENCE" --filter "version|bump|migration|$OLD_VERSION|$NEW_VERSION"

# 7. File the hypothesis ledger entries per affected category
for CATEGORY in conformance perf surface; do
  cat >> "$WORKSPACE/PERF_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — refbump-${OLD_VERSION}-${NEW_VERSION}-${CATEGORY} — investigating
- pillar: $CATEGORY
- old_version: $OLD_VERSION
- new_version: $NEW_VERSION
- hypothesis: no-regression-in-$CATEGORY | regression-in-<specific-subcategory>
- expected_signal: <which sub-metric or which test changes>
- falsifiability: <what would prove regression>
- one_line_invocation: $WORKSPACE/scripts/compute-parity-score.sh $WORKSPACE
- results_inline: <fill after run>
EOF
done

# 8. Re-run the full baseline pass against the bumped reference
"$WORKSPACE/scripts/run-bench-matrix.sh" "$PORT" "$WORKSPACE"
"$WORKSPACE/scripts/run-conformance-suite.sh" "$PORT" "$WORKSPACE"
"$WORKSPACE/scripts/compute-feature-coverage.sh" "$WORKSPACE"

# 9. Re-baseline ONLY categories materially affected (with rationale per category)
# DO NOT blindly accept the new numbers; rebaseline is a contract change.
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
"$WORKSPACE/scripts/apply-ratchet.sh" "$WORKSPACE"

# If apply-ratchet returns Block, route through ratchet-block.md
# If Allow, persist new state
"$WORKSPACE/scripts/update-ratchet-state.sh" "$WORKSPACE" "$WORKSPACE/reports/parity_score.json"

# 10. Create the bead
br create \
  --title "refbump-${OLD_VERSION}-${NEW_VERSION}" \
  --priority 1 \
  --type migration \
  --labels "pillar:all,lane:cc_1,recipe:dependency-version-bump,reference:$REFERENCE"
```

## Beads to claim (or create)

- `refbump-<old>-<new>` (this recipe creates it; usually epic-level with sub-beads per pillar).
- Sub-beads: `refbump-<old>-<new>-conformance`, `refbump-<old>-<new>-perf`, `refbump-<old>-<new>-surface`.
- Dependency: `pattern:10-REFERENCE-PINNING` — contract version + contract hash.
- Dependency: `pattern:20-ORACLE-PREFLIGHT-DOCTOR` — preflight must be green before re-entering the loop.
- Dependency: `pattern:105-FEATURE-UNIVERSE` — new/removed items reflected.
- For each affected pillar — chain to the appropriate triage cookbook if regressions surface.
- Dependency (test): `test-refbump-<old>-<new>-baseline-green` — first full pass against new version is green.
- Dependency (bench): `bench-refbump-<old>-<new>-baseline` — new `.bench-history` baseline committed.
- Dependency (doc): `doc-refbump-<old>-<new>-migration-notes` — entry under `docs/progress/reference-migrations/` summarizing surface diff + bench delta + conformance delta.

## Exit Criteria

- [ ] Contract updated; contract hash re-stamped on every artifact going forward.
- [ ] Oracle binary repointed; preflight doctor returns green.
- [ ] Surface diff computed; new items added as `Missing`, removed items as `Excluded { rationale: "removed in <NEW>" }`.
- [ ] Per-pillar hypothesis entries filed with falsifiability.
- [ ] Full baseline pass against the bumped reference; new scorecards generated.
- [ ] `apply-ratchet.sh` returns `Allow` or routes through `ratchet-block.md` for any regression.
- [ ] If re-baseline happened: rationale committed per category (no silent re-baselines).
- [ ] New `.bench-history/*.latest.json` committed.
- [ ] Documentation entry summarizes the migration.
- [ ] Two fresh-eyes clean rounds.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| Bumping the contract without repointing the oracle binary. | Preflight catches this; if you skip preflight you ship a self-comparing oracle. |
| Accepting the new bench numbers as the new baseline silently. | Re-baselining is a contract change; needs rationale + ratchet update with `--note`. |
| Skipping FeatureUniverse update. | The surface pillar will report regressions or false-greens that aren't real; the issue is missing rows, not changed behavior. |
| Treating removed items as `Missing`. | Removed items are `Excluded { rationale: "removed in <NEW>" }`, not missing. The distinction matters for strict-100% claims. |
| Not running per-pillar baseline. | If only one pillar gets re-run, the other two lag and the next round flags spurious cross-pillar regressions. |
| Bumping multiple references in one PR. | Each bump deserves its own recipe + bead. Multi-bump PRs make blame-bisecting impossible. |
| Bumping the reference and adding a new feature in the same PR. | Separate the bump (mechanical) from the feature (substantive). |
| Skipping the migration notes doc. | The next maintainer has no context on what the bump moved. |

## Cross-references

- [../patterns/10-REFERENCE-PINNING.md](../patterns/10-REFERENCE-PINNING.md) — contract schema.
- [../patterns/20-ORACLE-PREFLIGHT-DOCTOR.md](../patterns/20-ORACLE-PREFLIGHT-DOCTOR.md) — preflight contract.
- [../patterns/15-ENGINE-IDENTITY.md](../patterns/15-ENGINE-IDENTITY.md) — identity guard.
- [../patterns/105-FEATURE-UNIVERSE.md](../patterns/105-FEATURE-UNIVERSE.md) — surface enumeration.
- [../methodology/MODE-ROUTER.md](../methodology/MODE-ROUTER.md) — `migration` mode runs this recipe end-to-end.
- [../methodology/VERIFICATION-FIRST.md](../methodology/VERIFICATION-FIRST.md) — version-pinned facts vs evergreen facts.
- [../taxonomy/PROJECT-CLASSES.md](../taxonomy/PROJECT-CLASSES.md) — per-class oracle wiring updates.
- Related motions: [surface-gap-found.md](surface-gap-found.md), [ratchet-block.md](ratchet-block.md), [oracle-divergence-triage.md](oracle-divergence-triage.md), [cross-pillar-regression.md](cross-pillar-regression.md).
