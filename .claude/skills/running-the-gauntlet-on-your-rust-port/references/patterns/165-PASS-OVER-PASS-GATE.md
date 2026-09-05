# Pattern 165 — Pass-Over-Pass Gate

## What

The non-negotiable composition rule for perf claims: both the focused gate (targeted workload) and the broad gate (`comprehensive_bench` primary score) must move in the *same run window* — same git state, same `target/`, same machine, same wall-clock minute. Improving the focused gate while regressing the broad gate is a rejection; passing the broad gate without a focused gate proving where the win came from is also a rejection. The rule is the K-4 axiom; the implementation is the file-based ratchet ([pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md)).

## Why

> "Both gates must move in the same run window" — MINING-1 §1 (verbatim)
>
> "Same run = same git state, same `target/`, same machine, same minute." — MINING-1 §1

Failure mode prevented: "single-cell extraction" wins where one workload improves while hidden cells regress, or "focused improved, broad worsened" where local cleverness creates global drag. Without the same-window rule, an author can iterate focused-only on the dev loop, then submit a PR whose broad-gate result happens to be from a friendly run captured days earlier. The rule forces both to be evidence from one compile, one machine, one minute.

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/perf_loop.rs` — the gate evaluator reads both files and asserts the same-window invariant.
- `.bench-history/*.latest.json` — every per-bench history file embeds `generated_at` timestamp + `git_sha` + `host_id`; the gate refuses inconsistent triples.
- CI workflow: `.github/workflows/verification-gates.yml` runs both benches in the same job (same runner, same checkout) so the triples match by construction.

## Verbatim shape

### The rule (verbatim)

"Both gates must move in the same run window." (MINING-1 §1)

"Same run = same git state, same `target/`, same machine, same minute." (MINING-1 §1)

### Four-coordinate match

| Coordinate | Source field | Tolerance |
|---|---|---|
| Git state | `detected_environment.git_sha` | exact match required |
| `target/` | `detected_environment.cargo_profile` + checkout timestamp | profile must match exactly; checkout within window |
| Machine | `detected_environment.host_id` (CPU model + kernel + memory + OS) | exact match within run |
| Minute | `generated_at` ISO timestamp | within 5 minutes of paired bench's generated_at |

The 5-minute window is implementation: physically "same minute" is impractical when the broad bench takes 4 minutes and the focused bench takes 1; the actual gate is "both started within a 5-minute window from the same git checkout on the same host."

### Focused-only and broad-only rejections

- **Focused-only win**: focused JSON shows improvement; broad JSON unchanged (or worsened). The win is invisible at the production-relevant aggregate; reject.
- **Broad-only win without focused evidence**: broad shows improvement; no focused bench paired. Attribution is impossible; the win could be measurement noise. Reject pending focused evidence.
- **Cross-machine mismatch**: focused captured on host A, broad on host B. Machine-relative speedups differ by 20–40% routinely; reject.
- **Cross-minute mismatch**: focused captured Friday, broad Monday; intervening commit history makes attribution ambiguous; reject.

### Composition with K-4 (Kernel axiom)

[methodology/KERNEL.md § K-4](../methodology/KERNEL.md) makes this the load-bearing axiom: the K-4 axiom is the *policy*; this pattern is the *mechanism*.

## Per-class instantiation

| Class | Focused gate | Broad gate | Window source |
|---|---|---|---|
| SQL | One of: `mt_mvcc_bench`, `mt_oltp_bench`, `perf_update_delete`, `swarm_multiprocess` | `comprehensive_bench` primary score | Both within 5 min, same git_sha, same host |
| RESP | One of: `pipeline_throughput_bench`, `pubsub_fanout_bench`, `cluster_redirect_bench` | `redis-comprehensive-bench` primary score | Same |
| Numerical-Python | One of: `ufunc_elementwise_bench`, `reduction_axis_bench`, `linalg_blas_thread_bench` | `numpy-comprehensive-bench` | Same |
| ML-System | One of: `aten_dispatch_bench`, `autograd_step_bench`, `transformer_block_bench` | `torch-comprehensive-bench` | Same |
| HTTP-Protocol | One of: `route_match_bench`, `extractor_validation_bench`, `concurrent_request_pool_bench` | `http-comprehensive-bench` | Same |

The "one of" reflects that a typical perf bead targets one focused workload but must additionally not regress the broad aggregate.

## Composition

- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — the file-based committed ratchet that makes same-window enforceable.
- [pattern:125-COMPREHENSIVE-BENCH](125-COMPREHENSIVE-BENCH.md) — the broad-gate primary score source.
- [pattern:130-FOCUSED-BENCHES](130-FOCUSED-BENCHES.md) — every focused gate option.
- [pattern:150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md) — the card's `comparator` field names which broad and which focused gates the bead targets.
- [pattern:170-ROBUST-REGRESSION-DETECTOR](170-ROBUST-REGRESSION-DETECTOR.md) — applies median + MAD across paired same-window runs; cross-window pairs are filtered out.
- [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — MT8 profile is captured in the same run window as the bench numbers.
- [pattern:175-CONCURRENT-MODE-GUARD](175-CONCURRENT-MODE-GUARD.md) — guard file is dropped per-artifact-lane; same-window enforcement requires guard timestamps to match.
- See [methodology/KEEP-GATE-RULES.md § same run window](../methodology/KEEP-GATE-RULES.md).

## Pitfalls

- **"It's a small change; the focused win is obviously correct"** — even one-line changes can have global effects (inlining, cache pressure, RSS). The broad gate is the audit.
- **Running broad once at the start of the bead and re-using its result for the rest of the work** — the broad gate must be from *this commit*, not from yesterday's snapshot of the same branch.
- **Different `cargo bench` invocations between focused and broad** — different `--features` flags, different `RUSTFLAGS`, different `--profile`. Both must use the same profile contract ([pattern:140-RELEASE-PERF-PROFILE](140-RELEASE-PERF-PROFILE.md)).
- **Using a `rch` worker pool that load-balances mid-run to a different host** — invalidates `host_id`. Pin to a specific worker for the full pair.
- **Generated-at timestamp from system clock that drifted** — NTP-sync the host; the 5-minute gate is wall clock, drift matters.
- **CI workflow that runs focused and broad in parallel matrix jobs on different runners** — each runner has different `host_id`; the gate rejects. Either run sequentially on one runner or pin via labels.
- **Tolerating a 30-minute window because "the broad bench took longer than expected"** — the implementation-detail tolerance (5 min) is generous; if broad takes 30 min, restructure to run it on `rch` while focused runs locally, or accept that the bead's bench time is 30+ min wall.
- **Skipping the rule for "documentation-only" perf beads** — docs about perf still touch examples; benches must run to validate. The rule applies to any bead that *claims* perf, regardless of code change size.
- **Substituting a previous-run JSON when one of the two runs failed** — both must succeed in the same window. A failed run is a failed pair; rerun both.
- **Running broad without committing its `.bench-history` file because "the focused was the goal"** — the ratchet stales; the next bead sees an old broad baseline and underestimates its own regression. Always commit both.
