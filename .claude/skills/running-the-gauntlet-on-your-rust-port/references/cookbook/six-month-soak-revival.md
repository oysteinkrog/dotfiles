# six-month-soak-revival

> The gauntlet workspace has been idle ≥6 months. Toolchain drifted, dependencies drifted, the reference moved, AGENTS.md changed under the maintainer's feet. Restart without losing what the previous campaign learned.

This recipe is *not* a Phase 0 cold start — that path is covered by [`PHASES.md § Phase 0`](../PHASES.md). This recipe is a *warm restart* on a workspace whose Phase 0–15 ran to completion months ago but whose convergence has rotted under it.

## Trigger

Any of:

- A `<workspace>/reports/convergence_tracker.json` exists but its `last_session_id` (or `generated_at` fallback) is older than `6 months` per `mtime`.
- A `<workspace>/MEMORY.md` index references session files whose dates are all in the prior calendar half-year.
- Cold `cargo check` against the target port fails with toolchain-version errors (`feature gated`, `unstable`, `MSRV mismatch`).
- The reference impl shipped ≥1 major release since the workspace's last `version_contract.toml` stamp.
- The target port's `AGENTS.md` has been edited by another agent and the gauntlet's mandate paragraph no longer matches [`assets/agents-md-mandate-paragraph.md`](../../assets/agents-md-mandate-paragraph.md).
- The CASS index has rolled past the workspace's last `cass health --robot` timestamp.

If only *one* of these triggers, route through the more specific recipe ([dependency-version-bump.md](dependency-version-bump.md), [bocpd-shift-detected.md](bocpd-shift-detected.md), etc.). Use this recipe when ≥3 triggers fire together — that's a *cumulative-drift* state, not a single-cause issue.

## Operator Pipeline

```
⊕ ISOMORPHIC-REWRITE         (no — there's nothing to rewrite; first establish what still works)
↓
★ PIN-REFERENCE-VERSION       re-stamp every contract with the reference's current version
↓
🗄 LEDGER-RETIRE (mine)       6 months of post-idle commits + cass — what changed in the world?
↓
◐ WIRE-ORACLE                 re-run oracle preflight; expect failure; repoint binaries
↓
⚠ ESCALATE-TO-FRESH-REPRO    confirm the last-known-good baselines still reproduce; expect divergence
↓
🧪 EXPERIMENT-DESIGN         per-pillar hypothesis: "no-regression-since-idle" + falsifiability
↓
⚖ RATCHET-LOWER-BOUND        re-baseline with rationale per category; preserve floor where untouched
↓
🪟 FRESH-EYES                two clean rounds before re-opening Phase 11 cycle
```

The most common failure mode of this recipe is "rebaseline silently because the world moved". Re-baselining a stale ratchet without a per-category rationale is indistinguishable from quietly accepting regressions accumulated during the idle period. Per [Q-243](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-243--codexmd-1611--ratchets-make-progress-monotone), ratchets are what *make progress monotone*; a silent rebaseline breaks that invariant.

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path to workspace>
PORT=<absolute path to subject port>
SINCE=$(jq -r '.last_session_timestamp // .last_update_utc // .generated_at' "$WORKSPACE/reports/convergence_tracker.json")    # ISO 8601
TODAY=$(date -u +%FT%TZ)
DRIFT_DAYS=$(( ($(date -u +%s) - $(date -u -d "$SINCE" +%s)) / 86400 ))
echo "Workspace idle for $DRIFT_DAYS days since $SINCE"

# 1. Snapshot the pre-revival state so we can compute the drift diff later.
mkdir -p "$WORKSPACE/pre-revival"
cp "$WORKSPACE/scorecards.json"             "$WORKSPACE/pre-revival/scorecards_${SINCE}.json"
cp -r "$WORKSPACE/.bench-history"           "$WORKSPACE/pre-revival/.bench-history.snapshot" 2>/dev/null || true
cp "$PORT/parity_taxonomy.json"             "$WORKSPACE/pre-revival/parity_taxonomy_${SINCE}.json"
cp "$PORT/docs/contracts/"*.toml            "$WORKSPACE/pre-revival/" 2>/dev/null || true

# 2. Toolchain drift audit.
echo "--- Toolchain drift ---"
rustup show active-toolchain
cat "$PORT/rust-toolchain.toml" 2>/dev/null || cat "$PORT/rust-toolchain" 2>/dev/null
# If MSRV in Cargo.toml is below current stable by ≥3 versions, route through [library-updater] skill first.
cargo --version
cargo check --workspace --no-default-features 2>&1 | tee "$WORKSPACE/pre-revival/cargo_check_cold.log"

# 3. Dependency drift audit (no resolves yet — just observe).
cargo tree --no-default-features 2>&1 | head -60 > "$WORKSPACE/pre-revival/cargo_tree_pre.txt"
cargo outdated --workspace --depth 1 > "$WORKSPACE/pre-revival/cargo_outdated.txt" 2>&1 || true

# 4. Reference-version drift audit.
for CONTRACT in "$PORT/docs/contracts/"*_version_contract.toml; do
  REFERENCE=$(basename "$CONTRACT" _version_contract.toml)
  PINNED=$(grep -E '^version' "$CONTRACT" | head -1 | cut -d'"' -f2)
  # Per-reference upstream-version probe (each sibling defines its own probe script)
  CURRENT=$("$WORKSPACE/scripts/probe-reference-version.sh" "$REFERENCE")
  echo "$REFERENCE: pinned=$PINNED current=$CURRENT" >> "$WORKSPACE/pre-revival/reference_drift.txt"
done

# 5. AGENTS.md drift audit — does the target port still carry the gauntlet mandate paragraph?
EXPECTED_HASH=$(sha256sum "$WORKSPACE/skill/assets/agents-md-mandate-paragraph.md" | cut -d' ' -f1)
ACTUAL_HASH=$(awk '/<!-- gauntlet-mandate-begin -->/,/<!-- gauntlet-mandate-end -->/' "$PORT/AGENTS.md" 2>/dev/null | sha256sum | cut -d' ' -f1)
[ "$EXPECTED_HASH" = "$ACTUAL_HASH" ] || echo "AGENTS.md mandate paragraph drifted; re-install via subagents/ledger-seeder.md"

# 6. CASS health + 6-month mining for the idle window.
cass health --robot > "$WORKSPACE/pre-revival/cass_health.json"
"$WORKSPACE/scripts/mine-cass-cross-machine.sh" "$WORKSPACE" --since "$SINCE" --until "$TODAY" \
  > "$WORKSPACE/pre-revival/cass_idle_window.json"
# Mining the IDLE window matters: external agents may have committed to the target during the gap.

# 7. Reference-version re-pin (per dependency-version-bump.md, but batched across multiple references).
# For each reference whose drift is ≥1 minor version, follow that recipe.
for REFERENCE_LINE in $(cat "$WORKSPACE/pre-revival/reference_drift.txt"); do
  OLD=$(echo "$REFERENCE_LINE" | sed -E 's/.*pinned=([^ ]+).*/\1/')
  NEW=$(echo "$REFERENCE_LINE" | sed -E 's/.*current=([^ ]+).*/\1/')
  [ "$OLD" = "$NEW" ] && continue
  # Sub-recipe: dependency-version-bump.md per reference. Tracked as one sub-bead each.
done

# 8. Re-run oracle preflight; expect failure on every pillar; repoint binaries.
"$WORKSPACE/scripts/oracle-preflight-doctor.sh" "$PORT" || true     # expected red

# 9. Per-pillar baseline re-run AFTER all reference repoints.
for PILLAR in perf conformance surface; do
  rch exec --worker revival-baseline-$PILLAR -- \
    "$WORKSPACE/scripts/run-baseline-${PILLAR}.sh" "$PORT" &
done
wait

# 10. Compute drift diff: per-category, what moved during the idle window?
"$WORKSPACE/scripts/compute-parity-score.sh" "$WORKSPACE"
"$WORKSPACE/scripts/diff-scorecards.sh" \
  --baseline "$WORKSPACE/pre-revival/scorecards_${SINCE}.json" \
  --candidate "$WORKSPACE/scorecards.json" \
  > "$WORKSPACE/pre-revival/drift_diff.md"

# 11. Per-category triage: any category whose lower bound dropped during idle gets its OWN bead.
# Do NOT bulk-rebaseline. Per [Q-244], silent rebaselines defeat the lower-bound gate.

# 12. File the hypothesis-ledger entry covering the whole revival.
cat >> "$WORKSPACE/PERF_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — six-month-soak-revival-${SINCE//[:-]/} — investigating
- target_workload: ALL (revival)
- idle_window: $SINCE -> $TODAY ($DRIFT_DAYS days)
- toolchain_delta: $(rustup show active-toolchain | awk '{print $1}')
- dependency_drift_summary: $(wc -l < "$WORKSPACE/pre-revival/cargo_outdated.txt") crates outdated
- reference_drift_summary: $(wc -l < "$WORKSPACE/pre-revival/reference_drift.txt") references moved
- agents_md_status: $([ "$EXPECTED_HASH" = "$ACTUAL_HASH" ] && echo "intact" || echo "drifted-needs-reseed")
- hypothesis: "no-regression-attributable-to-our-code; all drift is exogenous and re-baseline-able with per-category rationale"
- falsifiability: "if ratchet returns Block on ≥1 category that the version-bump recipe doesn't explain, then the hypothesis is wrong"
- one_line_invocation: $WORKSPACE/scripts/diff-scorecards.sh --baseline pre-revival/scorecards_${SINCE}.json --candidate scorecards.json
- results_inline: <fill after step 13>
EOF

# 13. Create the bead.
br create \
  --title "six-month-soak-revival-${SINCE//[:-]/}" \
  --priority 1 \
  --type investigation \
  --labels "pillar:all,lane:cc_0,recipe:six-month-soak-revival,drift-days:$DRIFT_DAYS"

# 14. Two fresh-eyes clean rounds gate the close (see Ritual: PHASE-14-FRESH-EYES-LOOP).
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --bead "six-month-soak-revival-${SINCE//[:-]/}"
```

## Beads to claim (or create)

- `six-month-soak-revival-<SINCE>` (this recipe creates it; epic with per-pillar sub-beads).
- Sub-beads as needed:
  - `refbump-<old>-<new>` per [dependency-version-bump.md](dependency-version-bump.md) (one per drifted reference).
  - `agents-md-reseed` per [`subagents/ledger-seeder.md`](../../subagents/ledger-seeder.md) (if AGENTS.md mandate drifted).
  - `toolchain-bump-<old>-<new>` if Rust toolchain moved ≥1 minor version.
  - `cass-reindex` if cass health reports stale indexes.
- Dependency: [`pattern:10-REFERENCE-PINNING`](../patterns/10-REFERENCE-PINNING.md) — every contract re-stamped.
- Dependency: [`pattern:155-BENCH-HISTORY-RATCHET`](../patterns/155-BENCH-HISTORY-RATCHET.md) — new baselines committed with per-category rationale.
- Dependency: [`pattern:180-NEGATIVE-LEDGER`](../patterns/180-NEGATIVE-LEDGER.md) — the revival itself earns a ledger entry naming all drift sources.
- Dependency (test): `test-revival-${SINCE}-baseline-green` — first green run on the revived workspace.
- Dependency (doc): `doc-revival-${SINCE}-narrative` — short note in `docs/progress/revival-notes/` summarizing what drifted, what was repointed, what was re-baselined with rationale.

The bead graph validator (`scripts/bead-graph-validator.sh`) blocks close until every sub-bead's dependencies are met.

## Exit Criteria

- [ ] Pre-revival snapshot captured (every contract, scorecards, parity_taxonomy, .bench-history).
- [ ] Toolchain drift audited; if ≥1 minor version, `toolchain-bump-*` sub-bead filed.
- [ ] Dependency drift audited; `cargo outdated` log committed under `pre-revival/`.
- [ ] Every reference re-pinned via [dependency-version-bump.md](dependency-version-bump.md) with its own sub-bead.
- [ ] Oracle preflight passes for every pillar on the re-pointed reference binaries.
- [ ] AGENTS.md mandate paragraph re-installed if drifted; hash matches [`assets/agents-md-mandate-paragraph.md`](../../assets/agents-md-mandate-paragraph.md).
- [ ] CASS index health-checked and re-built if stale.
- [ ] Per-pillar baseline re-run; scorecards generated.
- [ ] Drift diff written to `<workspace>/pre-revival/drift_diff.md` showing every category that moved.
- [ ] Per-category rationale for every re-baseline (no silent rebaselines, per [Q-244](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-244--codexmd-1643--lower-bound-not-vanity-score)).
- [ ] Hypothesis-ledger entry filed with all six fields; "no-regression-attributable-to-our-code" is *one* hypothesis, not a foregone conclusion.
- [ ] Two fresh-eyes clean rounds.
- [ ] Convergence tracker updated; `last_session_id` re-stamped; `revival_count` incremented.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| `cargo update` first, then audit. | The pre-revival snapshot needs the *old* `Cargo.lock` for repro. Audit first; bump under sub-beads. |
| Bulk-accept new baselines because "the world moved." | A six-month gap doesn't authorize silent rebaselines. Per-category rationale or [`ratchet-block.md`](ratchet-block.md). |
| Treat AGENTS.md drift as cosmetic. | The mandate paragraph IS the discipline. Re-installing it is non-optional. |
| Skip the cass idle-window mining. | Other agents may have committed during the gap; their changes carry context only cass surfaces. |
| Re-run the whole gauntlet under one bead. | The graph becomes unparseable. One epic bead + per-pillar / per-reference sub-beads. |
| Skip the toolchain audit. | A stable-toolchain bump quietly turns warnings into errors; clippy lint sets evolve; MIR layout changes affect benches. Catch it now. |
| File the revival under "maintenance — no findings". | The drift diff IS the finding. Document it. |
| Skip the fresh-eyes pass because "nothing changed in our code." | Per [Q-211](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-211--ccmd-902--mutation-testing-as-mr-validator), validation is mandatory. The world changed; verify our gates still catch what they did before. |
| Close the revival without writing the narrative doc. | Six months from now the next maintainer reads `docs/progress/revival-notes/` first; without a narrative they re-derive the drift. |

## Cross-references

- [../PHASES.md § Phase 0](../PHASES.md) — cold-start intake; this recipe is the warm-restart counterpart.
- [../methodology/COMPACTION-SURVIVAL.md](../methodology/COMPACTION-SURVIVAL.md) — single-session resume; not the same as multi-month revival.
- [../methodology/CASS-MINING.md](../methodology/CASS-MINING.md) — the 6-month idle window mining recipe.
- [../methodology/CONFORMAL-RATCHET.md](../methodology/CONFORMAL-RATCHET.md) — the lower-bound-only release rule that makes "silent rebaseline" forbidden.
- [../methodology/CONVERGENCE.md](../methodology/CONVERGENCE.md) — when to re-enter Phase 11 vs. exit straight to Phase 16.
- [../exemplars/QUOTE-BANK-V2-ADDITIONS.md § Q-256](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-256--ccmd-82--spec-edits-are-commits) — spec-edit-as-commit discipline; verifies spec-drift is in git history.
- [`dependency-version-bump.md`](dependency-version-bump.md) — the per-reference sub-recipe invoked from step 7.
- [`ratchet-block.md`](ratchet-block.md) — what to do if any per-category re-baseline gets Blocked by the ratchet.
- [`cross-pillar-regression.md`](cross-pillar-regression.md) — what to do if a revival surfaces a cross-pillar drift not attributable to a single reference.
- Related rituals: [`RITUALS-V2.md § BEFORE-CONFORMANCE-WORK`](../exemplars/RITUALS-V2.md), [`RITUALS-V2.md § DAILY-RATCHET-AUDIT`](../exemplars/RITUALS-V2.md).
