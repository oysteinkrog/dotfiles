# Pattern 150 — Profile-First Card

## What

No code-changing performance bead starts without a profile-first card: a 19-field structured artifact that names the hotspot (with profile evidence), names the technique lineage (which advanced-methods pattern, which paper, which prior FrankenSQLite win this is being adapted from), names the EV-rubric score (`Impact × Confidence / Effort ≥ 2.0`), names *one* lever (not three) with explicit rollback recipe, and names the benchmark commands that will verify the win. The card lives in a versioned proof-pack directory the bead points at. A bead without a card cannot be opened; a card without a top-5 hotspot citation cannot be scored.

## Why

> "No code-changing performance bead starts without measured hotspot evidence, an EV-scored recommendation card, a one-lever scope, and a proof pack." — CC.md lines 710–713 (MINING-3 §5)

Failure mode prevented: the "plausible hypothesis without profile" anti-pattern — "the parser is slow, let me rewrite the parser" with no ranked hotspot table. After 30 hours the rewrite lands and the broad gate moves by 1.2% (within noise band). The card forces the question *before* the work: where is the evidence, what is the score, what is the rollback if it doesn't pan out?

## Where in FrankenSQLite

- `crates/fsqlite-harness/src/perf_loop.rs` — defines the proof-pack layout and the card schema.
- `artifacts/{bead_id}/profile_first_card.json` — one per perf bead.
- `artifacts/{bead_id}/proof_pack/` — the evidence directory the card points at.

## Verbatim shape

### The 19 required fields

1. **hotspot artifact** — path to the flamegraph/samply/dhat output that motivated the bead.
2. **baseline artifact** — path to the bench JSON (or `.bench-history/...latest.json`) the bead targets.
3. **mapped primitive/technique lineage** — the advanced-methods / frontier-math / FrankenSQLite prior-win pattern this is an instance of.
4. **EV score** — `Impact × Confidence / Effort`. Must be ≥ 2.0 to open.
5. **relevance score** — does this hotspot map to the project's current frontier? (1–5 scale, rubric in CC.md).
6. **priority tier** — A / B / C (A = ship-blocker, B = roadmap, C = nice-to-have).
7. **score formula** — `Impact × Confidence / Effort ≥ 2.0` (literal; documents the gate).
8. **hotspot rank** — *rank in the top 5* by time / tail-latency / allocations / named metric. If not in top 5, do not open.
9. **comparator** — what defines "won"? Per-category geomean delta, p99 delta, throughput delta, counter delta. Be specific.
10. **rollout posture** — feature-gated, on by default, off by default, opt-in via env var.
11. **budgeted mode** — wall-time budget for the bead (e.g., 8h investigation, 4h impl, 2h verify).
12. **fallback trigger** — what condition triggers automatic revert? (e.g., "if MT8 p99 regresses >5% on `.bench-history`").
13. **benchmark/profile commands** — exact invocations (one line each, copy-pasteable).
14. **p50/p95/p99 targets** — numeric, per the comparator.
15. **throughput targets** — numeric, per the comparator.
16. **primary failure risk** — what is most likely to go wrong? (e.g., "MVCC abort rate spikes under concurrent writer mix").
17. **proof artifact** — path the proof-pack directory will be populated at on close.
18. **rerun command** — single command to reproduce the bench from scratch.
19. **rollback recipe** — the exact git operation (revert, reset, branch-delete) plus any cleanup (drop `.bench-history` line, delete generated files).

### Score formula (literal)

```
Score = Impact × Confidence / Effort
Gate:  Score ≥ 2.0
```

Impact: 1 (cosmetic) → 5 (ship-blocking).
Confidence: 1 (speculative) → 5 (prior win on adjacent code).
Effort: 1 (one-day) → 5 (multi-week refactor).

A 5×5/3 = 8.33 bead is high priority; a 2×3/4 = 1.5 bead does not open.

### One-lever scope

The card must name *one* lever — one named change to one named subsystem. "Optimize the planner" is not a lever; "memoize `find_rowid_equality_term` via OnceLock" is a lever. "Mixed-pile" beads (two or more unrelated optimizations in one card) cannot claim a perf win because attribution becomes ambiguous — if the broad gate moved, which change moved it?

### Proof-pack layout

```
artifacts/{bead_id}/proof_pack/
  baseline_profile.{flame.svg,samply.json}
  candidate_profile.*
  delta_summary.json
  correctness.txt
  invariant_check.txt
  rerun.sh
  rollback.md
```

Every file is required for a bead to close on the `pass` half of [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md).

## Per-class instantiation

| Class | Typical "Impact" reference | Typical "Confidence" anchors | Typical "Effort" budget |
|---|---|---|---|
| SQL | Per-category geomean improvement on `ReadSingle` (0.35 weight) or `WriteSingle` (0.30 weight). | Prior FrankenSQLite ledger entry on adjacent code; advanced-methods pattern with proof numbers. | 1–5 days (1: counter elimination; 5: cracking / cooling integration). |
| RESP | RPS p99 improvement on `pipeline_throughput_bench` or GET/SET hot path. | Prior Redis-perf paper; RESP parser fast-path patterns from KeyDB / Dragonfly. | 1–5 days (1: dispatch table; 5: full-event-loop redesign). |
| Numerical-Python | `ufunc_elementwise_bench` improvement on dispatch overhead or reduction fast-path. | NumPy upstream PR with matching hotspot; NumPy `ufunc` source for the targeted op. | 1–4 days (1: dtype-promotion lookup; 4: vectorization-loop redesign). |
| ML-System | `aten_dispatch_bench` improvement or `transformer_block_bench` end-to-end. | PyTorch upstream PR; CUDA kernel-fusion paper; prior Torch perf experiment. | 1–6 days (1: tape-append fast path; 6: nccl-protocol micro-optimization). |
| HTTP-Protocol | `route_match_bench` p99 or `extractor_validation_bench` throughput. | hyper / axum upstream PR; tower middleware fast path. | 1–3 days (1: header-case-insensitive lookup; 3: extractor cache redesign). |

Per-class card templates live in `templates/profile_first_card_{class}.json` and pre-fill class-specific defaults.

## Composition

- [pattern:145-HOT-PATH-COUNTERS](145-HOT-PATH-COUNTERS.md) — counter deltas constitute valid hotspot evidence alongside flamegraph frames.
- [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — hotspot frame must be ≥0.1% self-time; rank in top 5; quoted citation in the card.
- [pattern:165-PASS-OVER-PASS-GATE](165-PASS-OVER-PASS-GATE.md) — the card's "comparator" field maps to which gate must move (focused + broad both required).
- [pattern:155-BENCH-HISTORY-RATCHET](155-BENCH-HISTORY-RATCHET.md) — the baseline artifact field points at `.bench-history/<bench>.latest.json`.
- [pattern:120-VERIFICATION-CONTRACT](120-VERIFICATION-CONTRACT.md) — closing the bead requires the proof-pack populated.
- [pattern:180-NEGATIVE-LEDGER](180-NEGATIVE-LEDGER.md) — if the bead does not pan out, the rejection lands in the perf negative ledger with the card preserved (lineage for future attempts).
- [pattern:250-ISOMORPHISM-PROOF](250-ISOMORPHISM-PROOF.md) — the `correctness.txt` proof-pack entry uses the 5-line isomorphism template.

## Pitfalls

- **"It looks like the parser is hot"** — that is a hypothesis without a profile. Card refuses to open without a rank-in-top-5 citation from a named artifact.
- **EV score with Confidence=5 because "I'm sure this will work"** — Confidence anchors on prior evidence (an advanced-methods pattern, a prior FrankenSQLite ledger entry, a published paper), not on author intuition. Self-assessed 5s without anchors are downgraded to 2.
- **Mixed-pile bead disguised as "related changes"** — even if two changes touch the same file, they need two cards. The keep-gate post-mortem cannot attribute a win to one of them otherwise.
- **`rerun.sh` that references an env var that doesn't exist** — the rerun command is *literal*; copy-paste reproducible from a clean machine. CI runs it as part of bead-close.
- **`rollback.md` that says "git revert <SHA>"** — fine for a single-commit bead; for multi-commit beads include the cleanup of `.bench-history` line, the deletion of cached artifacts, and the bumped `parity_taxonomy_schema_version` if applicable.
- **Skipping `invariant_check.txt`** — perf wins must preserve invariants (e-process never crossed `1/α`; MVCC INV-1..7 unviolated under MT8 soak). The check produces a one-line `Met` or `Violated`; absence is `fail-missing-evidence`.
- **"primary failure risk" left blank** — bead can't open. Naming the risk forces the author to design the fallback_trigger; without it, automatic-revert can't fire.
- **Card score gamed by setting Effort=1 on a multi-day change** — the audit during close compares actual wall-time to budgeted; chronic underestimation downgrades the author's confidence weight in future scores.
- **Card written *after* the work as documentation** — the card is the *pre-flight* artifact. Writing it after defeats the gate. CI checks card timestamp vs first-commit timestamp on the bead branch.
