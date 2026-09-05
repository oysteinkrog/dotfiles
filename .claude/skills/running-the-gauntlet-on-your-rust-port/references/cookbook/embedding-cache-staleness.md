# embedding-cache-staleness

> The semantic-embedding cache is returning stale vectors after the source document changed. Diagnose, prove the staleness, fix the cache-key derivation. Eidetic-specific but generalizes to any project with a content-addressed embedding cache (vector DBs, retrieval-augmented systems, semantic search).

This is the eidetic-engine-cli's instance of the cache-key-eviction-audit pattern. The fix shape is identical to FrankenSQLite's prepared-statement cache bug — per [Q-237](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-237--ccmd-772--biggest-aggregate-wins-from-architectural-bugs), the highest-leverage perf and correctness wins live in cache-key bugs, not in micro-optimizations.

## Trigger

Any of:

- `embed-cache-stale` warning in eidetic logs.
- A user reports "I edited a document but the search results still match the old text".
- The cache hit rate looks suspicious — too high after a known document churn event.
- A regression test (`tests/cache_consistency.rs` or equivalent) flagged a returned-vector inconsistency.
- `bv --robot-insights | jq '.CacheStaleness'` lists a new entry.
- Post-commit hook ran `cache-audit` and reported `Key components missing: <field>` for the embedding-cache.

For generalized projects: any cache whose key is derived from a *subset* of the source data, and whose source data evolves under the cache. Examples beyond eidetic: bytecode caches (FrankenSQLite's prepared-statement cache — [Q-064](../exemplars/QUOTE-BANK.md)), compiled-template caches (Tera / Liquid / handlebars-rs), search-index caches, AST/JIT caches.

## Why "Just Invalidate Everything On Any Change" Is Wrong

A blanket invalidation on every source change defeats the cache's purpose — semantic-embedding computations are slow (10ms–1s+ per document) and the cache often achieves 90%+ hit rates in practice. The right fix is to ensure the cache *key* reflects every input the *value* depends on, no more, no less. Per [Q-063](../exemplars/QUOTE-BANK.md):

> Audit discipline: for every cache, list which inputs it ACTUALLY depends on; for every invalidation, list which inputs SHOULD invalidate it; gap = bug.

The bug is *always* the gap. The fix is *always* to close the gap.

## Operator Pipeline

```
⊙ DEBOUNCE-FALSE-POSITIVE     classify: is the staleness reproducible or a one-off?
↓
⌘ REDUCE/MINIMIZE             produce the minimal source-document edit that triggers staleness
↓
⬡ INSTRUMENT-HOT-PATH         dump the cache-key inputs vs. the value-computation inputs side-by-side
↓
⤴ ATTRIBUTE-TO-MT8 (analog)   identify the missing key component(s) — which input feeds the value but not the key?
↓
🧪 EXPERIMENT-DESIGN          hypothesis: "key derivation is missing <component X>; including it closes the staleness"
↓
⊕ ISOMORPHIC-REWRITE          options: (a) include missing component in key; (b) separate key for bytecode vs data per [Q-064](../exemplars/QUOTE-BANK.md); (c) explicit version field bumped on mutation
↓
⚖ RATCHET-LOWER-BOUND         hit-rate must not collapse to <80% on the realistic-workload corpus
↓
🪟 FRESH-EYES                three reviewers, two clean rounds, with explicit invariant-catalog entry
```

## Scripts (literal, in order)

```bash
WORKSPACE=<absolute path>
EIDETIC=<absolute path to eidetic install>     # or generic <PROJECT> for non-eidetic instances
CACHE_DIR=<absolute path to the cache>          # e.g., ~/.eidetic/embed-cache/
CORPUS=<absolute path to a known-stale corpus>  # if not yet known, generate one in step 2

# 1. Confirm staleness is reproducible.
"$EIDETIC/scripts/embed-cache-audit.sh" "$CACHE_DIR" --verbose > "$WORKSPACE/embed-stale/audit_pre.txt"

# 2. If no known-stale corpus exists, build the minimal one.
# The minimal one: 1 doc that produces a different embedding before and after edit, with the cache returning the pre-edit vector.
mkdir -p "$WORKSPACE/embed-stale/repro/"
cp <source-doc-known-to-have-shifted> "$WORKSPACE/embed-stale/repro/doc.md"

# Compute the embedding fresh (bypassing cache):
"$EIDETIC/scripts/embed.sh" --no-cache "$WORKSPACE/embed-stale/repro/doc.md" \
  > "$WORKSPACE/embed-stale/repro/fresh.json"

# Read from cache:
"$EIDETIC/scripts/embed.sh" --cache-only "$WORKSPACE/embed-stale/repro/doc.md" \
  > "$WORKSPACE/embed-stale/repro/cached.json"

# Diff:
diff <(jq '.embedding' "$WORKSPACE/embed-stale/repro/fresh.json") \
     <(jq '.embedding' "$WORKSPACE/embed-stale/repro/cached.json")
# Non-empty = confirmed staleness.

# 3. Dump the cache-key components AND the value-computation inputs.
"$EIDETIC/scripts/cache-key-trace.sh" "$WORKSPACE/embed-stale/repro/doc.md" \
  > "$WORKSPACE/embed-stale/key_components.json"
"$EIDETIC/scripts/value-input-trace.sh" "$WORKSPACE/embed-stale/repro/doc.md" \
  > "$WORKSPACE/embed-stale/value_inputs.json"

# 4. Compute the gap — what's in value_inputs but not in key_components?
"$EIDETIC/scripts/diff-key-vs-value-inputs.sh" \
  "$WORKSPACE/embed-stale/key_components.json" \
  "$WORKSPACE/embed-stale/value_inputs.json" \
  > "$WORKSPACE/embed-stale/gap.json"

cat "$WORKSPACE/embed-stale/gap.json"
# Expected output: { "missing_from_key": ["model_version", "tokenizer_revision", "chunk_boundary_policy"] }
# (Real bugs are usually 1-2 missing components; large gaps mean the key is fundamentally underspecified.)

# 5. File the hypothesis BEFORE attempting a fix.
cat >> "$WORKSPACE/PERF_HYPOTHESIS_LEDGER.md" <<EOF

### $(date -u +%Y-%m-%d) — embed-cache-stale — investigating
- target_workload: semantic-embedding cache hit/miss correctness
- minimal_repro: $WORKSPACE/embed-stale/repro/doc.md
- gap_summary: $(jq -c '.missing_from_key' "$WORKSPACE/embed-stale/gap.json")
- hypothesis: "cache key is missing $(jq -r '.missing_from_key | join(", ")' "$WORKSPACE/embed-stale/gap.json"); including these closes the staleness"
- expected_signal: "after key fix, fresh vs cached diff goes empty for the minimal repro"
- falsifiability: "if the gap is closed and staleness persists, the value computation also depends on a non-deterministic input — escalate"
- one_line_invocation: "$EIDETIC/scripts/embed.sh --no-cache vs --cache-only and diff"
- results_inline: <fill after step 7>
EOF

# 6. Apply the fix. Three canonical options (per [Q-063](../exemplars/QUOTE-BANK.md)):
#
#    (a) Include the missing component(s) in the key:
#         OLD: key = sha256(doc_text || lang)
#         NEW: key = sha256(doc_text || lang || model_version || tokenizer_revision || chunk_boundary_policy)
#
#    (b) Two-tier key per [Q-064](../exemplars/QUOTE-BANK.md):
#         schema-bound key (model_version + tokenizer + policy) → bytecode cache
#         data-bound key (doc_text + lang)                       → vector cache
#         Compose: lookup the schema key to find the bytecode, then the data key under that bytecode
#
#    (c) Explicit version field, bumped on any mutation to non-key inputs:
#         NEW: key = sha256(doc_text || lang || global_cache_version)
#         When model_version or tokenizer revs, bump global_cache_version atomically; old entries become unreachable.
#
# Pick (a) for clean fixes; (b) when the missing component is high-cardinality but rarely changes; (c) when external config drift is the source.

# 7. Re-run the minimal-repro verifier; confirm fix.
"$EIDETIC/scripts/embed.sh" --cache-only "$WORKSPACE/embed-stale/repro/doc.md" \
  > "$WORKSPACE/embed-stale/repro/cached_postfix.json"
diff <(jq '.embedding' "$WORKSPACE/embed-stale/repro/fresh.json") \
     <(jq '.embedding' "$WORKSPACE/embed-stale/repro/cached_postfix.json")
# Empty = fix works.

# 8. Run the realistic-workload corpus to check hit-rate hasn't collapsed.
"$EIDETIC/scripts/embed-bench.sh" --corpus "$CORPUS" --report-hit-rate \
  > "$WORKSPACE/embed-stale/hit_rate_post.json"
HIT_RATE=$(jq -r '.hit_rate_pct' "$WORKSPACE/embed-stale/hit_rate_post.json")
[ "$(echo "$HIT_RATE > 80" | bc)" -eq 1 ] || echo "WARN: hit rate $HIT_RATE% below 80% floor"

# 9. Add the cache-key vs value-input gap check as a permanent invariant.
# See pattern:245-CACHE-KEY-EVICTION-AUDIT.md — install the audit as a `cargo test` invariant.
"$EIDETIC/scripts/install-cache-key-invariant.sh" embed-cache

# 10. Create the bead.
br create \
  --title "embed-cache-stale-$(date -u +%Y%m%d)" \
  --priority 1 \
  --type bug \
  --labels "pillar:conformance,lane:cc_3,recipe:embedding-cache-staleness,cache:embed"

# 11. Three fresh-eyes reviewers, two clean rounds.
"$WORKSPACE/scripts/run-fresh-eyes-pass.sh" "$PORT" "$WORKSPACE" --bead "embed-cache-stale-$(date -u +%Y%m%d)"
```

## Beads to claim (or create)

- `embed-cache-stale-<date>` (this recipe creates it).
- Dependency: [`pattern:245-CACHE-KEY-EVICTION-AUDIT`](../patterns/245-CACHE-KEY-EVICTION-AUDIT.md) — the canonical pattern this recipe instantiates.
- Dependency: [`pattern:110-INVARIANT-CATALOG`](../patterns/110-INVARIANT-CATALOG.md) — the new "cache-key covers all value inputs" invariant goes here.
- Dependency (test): `test-embed-cache-key-covers-value-inputs` — the regression test that fails if a future change adds a value input without adding a key component.
- Dependency (test): `test-embed-cache-stale-${date}-minimal-repro` — pins the minimal repro from this recipe.
- Dependency (bench): `bench-embed-cache-hit-rate-post-fix` — confirms hit rate stays ≥80% on the realistic corpus.
- Dependency (doc): `doc-embed-cache-stale-${date}` — entry in `docs/progress/cache-fixes/` summarizing the gap + chosen fix shape.

The bead graph validator blocks close until all five dependency classes are linked.

## Exit Criteria

- [ ] Staleness confirmed reproducible via minimal-repro fixture (saved under `<workspace>/embed-stale/repro/`).
- [ ] Gap between key components and value inputs explicitly enumerated.
- [ ] Hypothesis-ledger entry filed with all six fields; gap summary verbatim.
- [ ] ≥2 isomorphic-rewrite options enumerated; chosen one has an isomorphism proof (cache hit returns vector ≡ no-cache computation).
- [ ] Minimal-repro fresh vs cached diff is empty post-fix.
- [ ] Hit rate on realistic-workload corpus ≥ 80% (or explicit waiver with bead + rationale).
- [ ] Cache-key-vs-value-input gap check installed as a `cargo test` invariant.
- [ ] Three fresh-eyes reviewers ran; two consecutive clean rounds.
- [ ] If the fix was rejected as "deferred until model layer rev", a negative-ledger entry with the architectural-defer predicate per [Q-235](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-235--ccmd-43--architectural-defer-is-a-valid-retry-predicate) was filed.

## Anti-patterns

| Pattern | Why it's a fail |
|---|---|
| "Just blow away the cache." | Defeats the cache's purpose. Per [Q-237](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-237--ccmd-772--biggest-aggregate-wins-from-architectural-bugs), the win is in the *key*, not in invalidation policy. |
| Adding `current_timestamp` to the key. | Hit rate immediately collapses to ~0%. The key must be deterministic over the *content*, not the time. |
| Skipping the gap enumeration step. | Without explicitly listing missing components, you'll fix one and miss another; the bug returns next quarter. |
| Hashing the entire document for the key when only chunks matter. | Inflates the key footprint and still misses non-content inputs (model_version, tokenizer). |
| Closing without installing the invariant test. | Per [Q-237](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-237--ccmd-772--biggest-aggregate-wins-from-architectural-bugs), the next refactor adds another input; the test is what catches it. |
| Quoting the hit rate from a synthetic-uniform corpus. | Synthetic uniform corpora hide cache-key bugs; use a realistic distribution. |
| "It's just an embedding cache; doesn't really need invariants." | Cache-key bugs are architectural bugs (per [Q-237](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-237--ccmd-772--biggest-aggregate-wins-from-architectural-bugs)); the invariant catalog is precisely where they belong. |
| Treating embedding-cache as a perf-pillar issue. | Cache *staleness* is a *conformance* issue (wrong vector returned); cache *hit-rate* is perf. This recipe is conformance-first. |

## Cross-references

- [../patterns/245-CACHE-KEY-EVICTION-AUDIT.md](../patterns/245-CACHE-KEY-EVICTION-AUDIT.md) — the canonical pattern; this recipe is one instantiation.
- [../patterns/110-INVARIANT-CATALOG.md](../patterns/110-INVARIANT-CATALOG.md) — where the "key covers value inputs" rule lands.
- [../patterns/120-VERIFICATION-CONTRACT.md](../patterns/120-VERIFICATION-CONTRACT.md) — the bead-close gate that requires the new invariant test.
- [../patterns/240-ONCELOCK-DERIVATION-CACHE.md](../patterns/240-ONCELOCK-DERIVATION-CACHE.md) — related: derivation caches with similar key-gap risks.
- [../methodology/KEEP-GATE-RULES.md](../methodology/KEEP-GATE-RULES.md) — behaviour-preserving claim for cache fixes.
- [../exemplars/QUOTE-BANK.md § Q-063](../exemplars/QUOTE-BANK.md) — audit discipline.
- [../exemplars/QUOTE-BANK.md § Q-064](../exemplars/QUOTE-BANK.md) — the two-tier key pattern (FrankenSQLite's exact win).
- [../exemplars/QUOTE-BANK-V2-ADDITIONS.md § Q-237](../exemplars/QUOTE-BANK-V2-ADDITIONS.md#q-237--ccmd-772--biggest-aggregate-wins-from-architectural-bugs) — cache-key bugs are the highest-leverage architectural wins.
- [`asupersync-cancel-leak.md`](asupersync-cancel-leak.md) — sibling recipe for the cancel-correctness side of the eidetic infrastructure.
- Related motions: [`oracle-divergence-triage.md`](oracle-divergence-triage.md), [`cross-pillar-regression.md`](cross-pillar-regression.md), [`new-fault-class-discovered.md`](new-fault-class-discovered.md).
