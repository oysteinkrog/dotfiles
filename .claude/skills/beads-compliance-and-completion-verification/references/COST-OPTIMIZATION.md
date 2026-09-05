# COST-OPTIMIZATION.md — Audit Performance For Large Projects

<!-- TOC: Why optimize | Differential auditing | Evidence pack caching | Subagent context amortization | Phase-skip heuristics | Cost / time accounting | When NOT to optimize -->

> A 1000-bead Standard-mode audit at Squad tier costs ~$40 in tokens and 2-4 hours wall time. For most projects this is fine — quarterly cadence amortizes it. But for tripwire mode running daily, optimization matters. Pattern adapted from `/extreme-software-optimization`'s profile-driven discipline.

---

## Why optimize

| Audit shape | Cost / pass | Cadence | Annual cost |
|-------------|------------:|---------|------------:|
| 100-bead Standard, Solo tier | $4 | monthly | $50 |
| 500-bead Standard, Squad tier | $20 | monthly | $250 |
| 500-bead Tripwire, Solo tier | $2 | daily | $700 |
| 1000-bead Standard, Swarm tier | $40 | monthly | $500 |
| 1000-bead Tripwire, Solo tier | $4 | daily | $1500 |
| Portfolio (10 × 200 bead) Standard | $80 | weekly | $4200 |

For agents on Claude Max / GPT Pro subscriptions: the marginal cost is ~$0; optimization matters for *wall time*, not money. For pay-as-you-go: optimization matters for both.

---

## Differential auditing

The expensive phases (2, 3, 4, 5, 6) are per-bead. If a bead's evidence files haven't changed since the prior pass, re-running those phases is waste.

### The diff-based skip

In re-verification mode, for each bead:

```bash
# Compute the bead's "evidence file set" from prior pass's evidence.json
PRIOR_FILES=$(jq -r '.checks[].citations[].path' "$PRIOR_PASS/beads/$ID/evidence.json" 2>/dev/null | sort -u)
PRIOR_SHA=$(cat "$PRIOR_PASS/manifest.json" | jq -r '.project_git_sha_at_pass_start')
CURRENT_SHA=$(git -C "$PROJECT" rev-parse HEAD)

# Have any of those files changed?
CHANGED=$(git -C "$PROJECT" diff --name-only "$PRIOR_SHA..$CURRENT_SHA" -- $PRIOR_FILES | wc -l)

if [ "$CHANGED" -eq 0 ]; then
  # Copy forward all phase outputs from prior pass
  cp "$PRIOR_PASS/beads/$ID/"*.json "$PASS_DIR/beads/$ID/"
  cp -r "$PRIOR_PASS/beads/$ID/raw" "$PASS_DIR/beads/$ID/"
  # Mark provenance
  jq '.provenance = "cached_from_prior"' "$PASS_DIR/beads/$ID/compliance.json" \
    > "$PASS_DIR/beads/$ID/compliance.json.tmp" \
    && mv "$PASS_DIR/beads/$ID/compliance.json.tmp" "$PASS_DIR/beads/$ID/compliance.json"
else
  # Re-run Phases 3-6 for this bead
  ...
fi
```

The `⟴ AMORTIZE` operator implements this. Typical re-verification pass: 80%+ of beads can be cached forward; only ~20% need full re-execution. **Wall time drops 5-10×.**

### What the diff must consider

- The bead's cited files (from prior `evidence.json`).
- The bead's *test* files (cited in `compliance.json#stdout_path` ancestors).
- Files added in commits since prior pass that *might* now be cited (run gather-evidence on those even if no other diff).

---

## Evidence pack caching

Even within a single pass, multiple beads may share evidence:

- Bead A and Bead B both depend on `src/util.rs`. Phase 4 runs `cargo test` which exercises `util.rs` for both.
- Coverage measurement of `src/util.rs` is shared.

The compliance-verifier subagent batches across beads:

```bash
# Instead of running cargo test once per bead:
#   cargo test --package <pkg> bead_A_test
#   cargo test --package <pkg> bead_B_test
# Run once over all bead-relevant tests:
ALL_TESTS=$(jq -s '[.[].checks[] | select(.spec_item_id | startswith("tests.")) | .spec_item_id] | unique' "$PASS_DIR"/beads/*/spec.json)
cargo test --package <pkg> "${ALL_TESTS[@]}"
```

The compliance-verifier then attributes per-test PASS/FAIL back to each bead. Wall time drops further.

### Coverage scoping

Coverage measurement is expensive (instrumentation overhead). Run **once per pass** with `cargo llvm-cov --workspace --json --summary-only`, then filter per-bead from the output:

```python
# In test-depth-auditor
global_coverage = json.loads(open("raw/coverage.json").read())
for bead in beads:
    bead_files = set(c["path"] for c in bead.evidence["checks"][...])
    bead_files_data = [f for f in global_coverage["data"][0]["files"] if f["filename"] in bead_files]
    # Compute per-bead coverage from these files
```

Saves ~30 seconds per bead on a Rust project.

---

## Subagent context amortization

Each subagent invocation has a fixed context cost (system prompt + skill files loaded). For 100 beads × 5 phases × 1 subagent = 500 invocations × ~10K tokens = 5M tokens of pure context overhead.

### Batching

Spawn fewer, larger subagents:

| Approach | Subagent count | Context per | Total context |
|----------|---------------:|------------:|--------------:|
| Naive (one per bead per phase) | 500 | 10K | 5M |
| Per-phase batched (one phase, all beads in pool) | 50 | 50K | 2.5M |
| Per-domain (one agent for all bead-X-domain phases) | 20 | 80K | 1.6M |

Per-domain batching: cluster beads by label / module, give one subagent the whole cluster's evidence pack to process across phases 2-6.

### Reusing context with prompt caching

Anthropic's prompt-caching breakpoint at the SKILL.md / rubric.md sections lets you reuse the cached system prompt across many bead invocations:

```python
# Pseudo-Anthropic SDK with cache control
messages = [
    {"role": "system", "content": [
        {"type": "text", "text": skill_md_content, "cache_control": {"type": "ephemeral"}},
        {"type": "text", "text": rubric_md_content, "cache_control": {"type": "ephemeral"}},
    ]},
    {"role": "user", "content": f"Score bead {bead_id}: ..."},
]
```

The SKILL.md + rubric.md context is re-used across all bead-scoring calls. Cost per bead drops 5-10× because the static portion is cached.

---

## Phase-skip heuristics

For tripwire mode, skip phases conservatively:

| Mode | Phase 4 | Phase 6 | Phase 7 | Phase 10 |
|------|:-------:|:-------:|:-------:|:--------:|
| Standard | run | run | run | sometimes |
| Tripwire | **skip if cached** | **skip if cached** | only on changes | skip |
| Triage | skip | skip | skip | skip |
| Re-verification | only changed | only changed | only if synthesis differs | per stakes |
| Comprehensive | always | always | always | always + triangulation |

The skip decisions are recorded in `manifest.json#phase_status`:
```json
"phase_status": {
  "1": "completed",
  "2": "completed_cached_80pct",
  "4": "skipped_tripwire_mode",
  ...
}
```

---

## Cost / time accounting

The manifest records cost actuals for budget projection:

```json
"cost": {
  "wall_time_seconds": 1234,
  "subagent_invocations": 47,
  "estimated_token_cost_usd": 0.85,
  "tier": "squad",
  "mode": "standard",
  "parallelism": 6,
  "cached_beads": 80,
  "fresh_beads": 20,
  "cache_hit_rate": 0.80
}
```

Trends over time (in `trends.md`) let you predict next pass's cost:

```bash
# Last 5 passes wall time
jq '.cost.wall_time_seconds' "$AUDIT_DIR/passes/"*/manifest.json | tail -5
# Average → expected cost for next pass
```

---

## Cost-aware mode selection

Auto-suggest at bootstrap based on cost-budget:

```bash
# User has set BEADS_AUDIT_BUDGET_USD=2.00 in env
if [ "${BEADS_AUDIT_BUDGET_USD:-0}" -gt 0 ]; then
  ESTIMATED_COST=$(estimate_cost "$BEAD_COUNT" "$DEFAULT_MODE" "$DEFAULT_TIER")
  if [ "$ESTIMATED_COST" -gt "$BEADS_AUDIT_BUDGET_USD" ]; then
    SUGGESTED_MODE="tripwire"  # downgrade to fit budget
  fi
fi
```

This prevents accidentally running a $40 Comprehensive audit on a 1000-bead project when the user wanted a daily $2 tripwire.

---

## Token-budget per subagent

Each subagent has an implicit context budget. Optimize by:

1. **Trimming SKILL.md inclusion.** Subagents only need their own subagent.md + the rubric. Don't include the full SKILL.md or all 30 reference files.
2. **Lazy-loading references.** Subagents read references on-demand; the system prompt only loads its own subagent.md.
3. **Context window management.** A subagent processing 50 beads in a batch should chunk: 10 beads → produce 10 outputs → next 10. Don't load all 50 spec.jsons at once.

```python
# In compliance-verifier subagent
for batch in chunks(beads, batch_size=10):
    process_batch(batch)
    flush_to_disk()  # don't accumulate context
```

---

## Profile-driven optimization

Per `/extreme-software-optimization`, measure before optimizing:

```bash
# Per-phase timing across passes
for p in "$AUDIT_DIR/passes"/*/; do
  jq -r '
    .pass_id + ": " + (
      (.cost.wall_time_seconds // 0 | tostring)
      + "s; phases " + ([.phase_status | to_entries[] | select(.value == "completed") | .key] | join(","))
    )
  ' "$p/manifest.json"
done
```

If Phase 4 dominates wall time, the optimization target is test execution (cargo test or vitest run). If Phase 5 dominates, the theater scan's regex set is too broad (or the cited evidence files are too large). Profile, then optimize.

---

## When NOT to optimize

| Scenario | Why not optimize |
|----------|------------------|
| First pass on a project | Need full execution to establish baseline |
| Onboarding mode | CASS mining requires full coverage |
| Comprehensive mode | The whole point is rigor |
| When cost is < $20/pass | Optimization complexity > savings |
| When subagents on Max plans | Marginal token cost is $0 |

Premature optimization here is the same anti-pattern as in any code: it's only valuable when measurement shows it's needed.

---

## Worked example: 1000-bead daily tripwire

Without optimization:
- 1000 beads × Phases 1-9 × naive subagents = 4 hours wall time, $40/day, $14K/year.

With differential auditing:
- ~80 beads change per day (typical churn)
- 920 cached + 80 fresh = 920 × 1s + 80 × 30s = ~40 minutes
- Cost: $4/day → $1.5K/year

10× reduction. The skill ships with this optimization enabled in `mode=tripwire` by default.

---

## Caveats and tradeoffs

- **Cache invalidation risk.** If a project commit changes a file but the file isn't in any bead's evidence list, the diff misses it — but Phase 7 synthesis catches the cross-bead implication next pass. The risk is one-pass-late detection, not silent failure.
- **Calibration drift.** Heavily-cached audits accumulate cached scorecards over many passes. If the rubric changes, every cached scorecard needs re-derivation. The `rubric_sha256` pin in `manifest.json` triggers full re-execution on rubric change.
- **Determinism preserved.** Caching never produces a *different* result than fresh execution — it's an optimization, not an approximation. If you can't prove the cached result equals what fresh execution would produce, don't cache.