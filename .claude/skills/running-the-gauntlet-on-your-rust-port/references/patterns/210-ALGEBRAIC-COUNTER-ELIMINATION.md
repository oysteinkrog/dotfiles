# pattern:210-ALGEBRAIC-COUNTER-ELIMINATION

## What

If a counter is provably equal to an algebraic combination of other counters, drop the write-time counter and *derive it at read-time*. The motivating identity is **`validations_total == commits_total + aborts_total`** — every SSI validation either commits or aborts, so the validation-count is structurally a sum of the other two. Maintaining it separately doubles the AtomicU64 cost on every hot call without adding any information.

## Why

> "Counter writes = every-hot-call cost; counter reads = report-time cost (orders of magnitude rarer)." — MINING-3 §7

Failure mode prevented: *paying for the same information twice on every hot call*. Atomic counters are not free — even `fetch_add(1, Relaxed)` is a contended cache line in a multi-thread workload. Doubling them for derivable values doubles the contention without doubling the information. The right place for derivable values is the report renderer, which runs once per second or once per scrape, not once per commit.

The general rule (CC.md §55): when adding a counter, ask "is this algebraically derivable from existing counters?" If yes, derive at read time.

## Where in FrankenSQLite

- `FSQLITE_SSI_VALIDATIONS_TOTAL` (the dropped counter) — was a `static AtomicU64` incremented on every SSI commit
- `commits_total` + `aborts_total` (the remaining counters) — their sum equals what the dropped counter measured
- Commit: `36504496`
- Per-class equivalents under `HotPathProfileSnapshot` in `crates/fsqlite-core/src/connection.rs:686-835`

## Verbatim shape

Before (hot path runs both counter updates):

```rust
// On every SSI commit path:
COMMITS_TOTAL.fetch_add(1, Ordering::Relaxed);
VALIDATIONS_TOTAL.fetch_add(1, Ordering::Relaxed);  // ← redundant; equals commits + aborts
```

After (hot path runs one; derive at report time):

```rust
// Hot path:
COMMITS_TOTAL.fetch_add(1, Ordering::Relaxed);

// Report renderer (called once per scrape):
let validations_total = COMMITS_TOTAL.load(Ordering::Relaxed)
                      + ABORTS_TOTAL.load(Ordering::Relaxed);
```

## Measurement proof (verbatim)

**3.91 → 1.90 ns/call (−51.5%, ~2x)** at commit `36504496`.

## Spot the shape

In an unfamiliar codebase, look for:

1. Counters that update in the same code path with a 1:1 relationship (e.g., every `X` increments both `total_X` and `total_X_subtype`).
2. Multiple counters named `*_total` that are obviously sums of other `*_subtype_total` counters.
3. Metric scrape endpoints that already compute the same sum at read time — meaning the write-time counter is duplicate work.
4. A profile sample showing `fetch_add` instructions accounting for ≥0.1% self-time in the hot path.

If those hold, the counter is a Pattern 3 candidate.

## Per-class transferability

| Class | Algebraically-derivable counters to drop |
|---|---|
| **SQL** | `validations_total ≡ commits + aborts`; `retries_total ≡ retried_commits + retried_inserts`; `bytecode_executions ≡ Σ per-opcode counters` |
| **RESP** | `total_commands ≡ read_commands + write_commands + admin_commands`; AOF append count ≡ a quantity already tracked in replication offset; `total_responses ≡ Σ per-type response counters` |
| **Numerical** | Allocation counts split by dtype that already sum to `total_alloc_bytes`; per-axis-reduce counters that sum to `total_reduces` |
| **ML** | Per-op call counts where the dispatcher already tracks `total_dispatches`; per-device-memory counts whose sum equals `total_allocated_bytes` |
| **HTTP** | Per-status-code counter where `total_responses ≡ 2xx + 3xx + 4xx + 5xx`; per-method counter where `total_requests ≡ GET + POST + PUT + DELETE + PATCH + ...` |

## Composition

- Pairs with [pattern:145-HOT-PATH-COUNTERS](145-HOT-PATH-COUNTERS.md) — this is the *correction* pattern; HotPathProfileSnapshot's counter table should be audited for algebraic redundancy at every release.
- Pairs with [pattern:205-ATOMIC-BOOL-EMPTY-GATE](205-ATOMIC-BOOL-EMPTY-GATE.md) — both invert "every-call cost vs rare-read cost"; this one targets atomic-counter writes specifically.
- Pairs with [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — the 2x win required attribution to the `fetch_add` self-time frame on MT8.
- Pairs with [pattern:250-ISOMORPHISM-PROOF](250-ISOMORPHISM-PROOF.md) — the derived value must equal the dropped value exactly; golden output for the metrics report is the proof.

## Pitfalls

- **Dropping a counter that isn't actually a perfect sum.** If `validations_total` ever incremented for reasons other than commit-or-abort (e.g., a validation that was retried and counted twice), the drop changes observable metrics. Audit the call sites before dropping.
- **Moving the cost to the reader without paying attention to reader contention.** If the metrics endpoint is hit at 1Hz from 100 scrape clients, the read might be hotter than expected. Measure both ends.
- **Forgetting that downstream alerts may key on the dropped counter name.** Renaming/removing a metric is an API change; either rename gracefully (keep both for one release) or document the migration.
- **Per-class trap (RESP): operators' Grafana dashboards often reference dropped counters by name.** RESP deployments are very metrics-coupled; even a derivable counter may need to remain exposed as a virtual metric in the scrape output.
- **Per-class trap (HTTP): per-status counters look algebraically redundant but operators want them for SLO math.** Drop the *write-time* maintenance, but keep the *read-time* derivation; don't drop the exposed metric.
- **Adding the audit only for new counters.** The win is in *existing* counters; the audit applies to the whole counter table on every major refactor.
- **Calling `load(SeqCst)` in the report renderer.** Relaxed is correct; the report is a snapshot, not a transactional view.
