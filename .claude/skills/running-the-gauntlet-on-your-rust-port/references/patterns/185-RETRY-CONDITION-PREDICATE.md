# pattern:185-RETRY-CONDITION-PREDICATE

## What

Every negative-ledger entry must end with a **retry-condition predicate**: a single sentence in one of eight verbatim forms that names exactly what evidence — workload, gate, profile attribution, architectural dependency — would justify re-opening the candidate. The predicate is itself a discipline: writing it forces the rejecter to specify the boundary between "this won't work" and "this might work later under named conditions." Without that boundary, "rejected" is a wish, not a decision.

## Why

> "the predicate is itself a discipline" — MINING-1 §2

Failure mode prevented: *the ledger entry that means nothing*. An entry that says "rejected — didn't help" tells a future agent nothing about when the situation might change. Six months later, an agent looking at a profile and seeing the same hotspot has no way to know whether the prior attempt is still binding. The retry-condition predicate is the rejection's expiration condition. Without it, every rejection is either permanently dead (which throws away upside) or invisibly alive (which wastes effort re-attempting).

The verbatim quote anchor (CC.md line 567, MINING-1 §2):

> "Reverted — within-noise. Reusing find_rowid_equality_term for the RowidLookup probe (vs 2nd scan in extract_access_path_probe) was behavior-preserving (identical selection counts; 13 probe/21 rowid/35 access_path tests pass) but point-lookup gain ~2% sits in the ±3-5% bench noise band."

This entry *names the gate* (point-lookup), *names the noise band* (±3–5%), and implicitly defines the retry condition: a workload whose cv_pct shrinks below 2%.

## Where in FrankenSQLite

- `docs/progress/perf-negative-results.md` — 380 entries, every one with a predicate
- `CC.md` PART VII §39 — the verbatim eight-form catalog
- `CODEX.md` §11 — operational notes
- `CC.md` line 1921 — example of the "Blocked until <architectural_dependency> lands; track as <beads_id>" form

## Verbatim shape — the eight predicate templates

From MINING-1 §2 (each verbatim or near-verbatim):

1. **"Retry only if a profiler attributes a clearly-above-noise share to `<specific counter>` on `<wider workload shape>`."**
2. **"Reconsider only inside the broader `<X>` redesign."** (e.g., "the broader DML mutation operator redesign")
3. **"Worth reconsidering when `<specific gate moves>`."** (e.g., "when MT16 shared-table ratio crosses 5x")
4. **"Not worth retrying as a standalone patch."**
5. **"Do not retry from a cold read; use comprehensive-bench attribution instead."**
6. **"Retry condition not applicable — the gain is structural, not numerical."**
7. **"Retry only if this workload class exhibits measurable `<property>` below `<threshold>`."**
8. **"Blocked until `<architectural_dependency>` lands; track as `<beads_id>`."**

## Forbidden phrases

The following phrases, if they appear in a retry-condition field, fail the ledger linter:

```
later
if it seems important
we should revisit
tracked elsewhere
TBD
maybe
eventually
when we have time
if circumstances change
```

Each of these is a wish, not a predicate. The rejection of "later" in particular is load-bearing: "later" is exactly when the next agent will re-discover the same dead-end.

## Per-class instantiation

| Class | Concretized example (form 1) |
|---|---|
| SQL | "Retry only if a profiler attributes ≥0.15% MT8 self-time to `vdbe::step_inner` under the `wal_heavy_oltp` workload at 16 threads." |
| RESP | "Retry only if a profiler attributes ≥0.15% RPS p99 to `respCmdDispatch` under the `mixed_64c_keyspace_1m` workload at 256 concurrent clients." |
| Numerical-Python | "Retry only if PCG64DXSM RNG-stream divergence within `np.testing.assert_allclose(rtol=1e-12, atol=1e-15)` is provably the bottleneck on `linalg.solve` at N=10000." |
| ML-System | "Retry only if `torch.use_deterministic_algorithms(True)` is held AND `aten::native_layer_norm` attributes ≥0.2% MT8-equivalent inclusive self-time on the `transformer_encoder_block` workload at batch 8." |
| HTTP-Protocol | "Retry only if `route_match_time_ns` attributes ≥0.1% p99 on the `100-route-tree` workload at 8 concurrent connections via wrk2." |

| Class | Concretized example (form 8) |
|---|---|
| SQL | "Blocked until the DML mutation operator (bd-DML.0001) lands; track as bd-1dp9.dml.7." |
| RESP | "Blocked until the I/O thread split (bd-IO.0001) lands; track as bd-7q.io.3." |
| Numerical-Python | "Blocked until the `__array_function__` dispatch protocol parity (bd-AF.0001) lands; track as bd-np.af.2." |
| ML-System | "Blocked until the autograd graph capture parity bead (bd-AG.0001) lands; track as bd-tr.ag.4." |
| HTTP-Protocol | "Blocked until the typed-extractor codegen (bd-EX.0001) lands; track as bd-fa.ex.5." |

## Composition

- Pairs with [pattern:180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) — the predicate is a mandatory field of every ledger entry.
- Pairs with [pattern:190-CASS-MINING](190-CASS-MINING.md) — cass mining searches the predicate text to find live conditions; e.g., grepping for "Blocked until bd-DML.0001" finds every entry waiting on that bead.
- Pairs with [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — form 1 explicitly cites MT8 (or per-class equivalent) self-time.
- Pairs with [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — form 3's "specific gate" almost always means one of the pass-over-pass gates.

## Pitfalls

- **Predicate without a number.** "Retry when MT8 shows it again" is too soft; the number is what makes the predicate falsifiable.
- **Predicate referencing a workload that doesn't exist.** "Retry on the 16-thread mixed-OLTP workload" — except that workload isn't in the bench matrix. The predicate is useless until the workload is added; pair with a bead to add it.
- **Form 6 ("not applicable — gain is structural") used as a dodge.** This form is legitimate when the rejected idea was a misframe (the architecture, not the micro-op, is the lever); it's an anti-pattern when the agent just couldn't write a number.
- **Form 8 ("blocked until X lands") without the beads id.** Without the id, the unblock condition is unfindable; the entry is then effectively forms 4 ("never").
- **Copying the same predicate across many entries.** A copy-paste retry-condition usually means the agent didn't actually think; each entry's predicate should be specific to its measurement.
- **Mixing two forms in one entry.** Pick one. If both apply, the entry is two separate rejections and should be two separate entries.
