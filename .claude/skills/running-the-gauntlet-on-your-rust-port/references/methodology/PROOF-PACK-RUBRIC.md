# Proof-Pack Rubric

What separates a "perf claim" from a "perf evidence". Every kept perf change ships with a proof pack at `artifacts/<bead_id>/proof_pack/`; this rubric is what reviewers check.

## The 13 required artifacts

| # | Artifact | Owner | Verification |
|---|---|---|---|
| 1 | `card.md` | proposing agent | All 19 fields filled per `pattern:150-PROFILE-FIRST-CARD` |
| 2 | `baseline_profile.flame.svg` | bench dispatcher | rendered from samply trace at the candidate's parent commit |
| 3 | `baseline_profile.samply.json` | bench dispatcher | top-10 self-time frames extracted to `mt8_top_frames.json` |
| 4 | `candidate_profile.flame.svg` | bench dispatcher | rendered at the candidate commit |
| 5 | `candidate_profile.samply.json` | bench dispatcher | top-10 self-time frames; the cited frame must show shrinkage |
| 6 | `delta_summary.json` | proposing agent | well-formed per `assets/proof-pack-skeleton/delta_summary.json` |
| 7 | `correctness.txt` | proposing agent | one line: "all oracle E2E pass; selections= byte-identical" + bead-IDs of regression tests |
| 8 | `invariant_check.txt` | proposing agent | one line per monitored invariant: e-value < 1/α |
| 9 | `rerun.sh` | proposing agent | paste-ready; reproduces delta numbers within `cv_pct` band |
| 10 | `rollback.md` | proposing agent | exact `git revert` / `git checkout` commands |
| 11 | `criterion/` | bench dispatcher | `cargo criterion` output for the affected micros |
| 12 | `hyperfine/` | bench dispatcher | `hyperfine --warmup 3 --runs 10` for CLI-level (if applicable) |
| 13 | `alloc_census/` | bench dispatcher | dhat-rs or heaptrack output proving allocator delta is intentional |
| 14 | `syscalls/` | bench dispatcher | `strace -c` syscall counts (proves no unexpected syscall added) |
| 15 | `smoke/` | bench dispatcher | minimal CI-replayable smoke test outputs |

## Reviewer checklist (12 questions)

A reviewer reading a proof pack asks:

1. **Card complete?** All 19 fields per `pattern:150-PROFILE-FIRST-CARD`; no `<TBD>` anywhere.
2. **Both gates moved same window?** `baseline_profile.samply.json#/env/GIT_SHA` equals candidate's parent commit; both ran on the same `PLATFORM`; the timestamps are within the same minute.
3. **MT8 frame attribution?** The cited frame (`delta_summary.json#/mt8_attribution.frame`) appears at >0.1% self-time in baseline AND <0.1% in candidate (or measurably reduced). Below 0.1% means the citation is below noise floor (micro-lever trap).
4. **cv_pct < 5?** Every micro in `criterion/<bench>/base/estimates.json` and `change/estimates.json` reports `cv_pct < 5`. Otherwise the result is flake-territory.
5. **release-perf profile?** Both `baseline_profile.samply.json#/env/MODE` and `candidate_profile.samply.json#/env/MODE` equal `"release-perf"`. Never `release` (size-optimized).
6. **concurrent_mode_default_guard.txt present?** (Or class-equivalent.) The artifact lane proves the project's defining mode was on.
7. **Correctness preserved?** `correctness.txt` cites the regression test bead-IDs. `cargo test --workspace` passes at the candidate commit.
8. **Invariants intact?** Every e-process invariant's e-value is below `1/α`. `invariant_check.txt` enumerates each.
9. **rerun.sh reproduces?** Reviewer can run `bash artifacts/<bead_id>/proof_pack/rerun.sh` and reproduce the delta numbers within `cv_pct` band.
10. **rollback.md complete?** Exact `git revert` (or sequence of operations) that fully undoes the change. Reviewer mentally walks the rollback.
11. **EV score ≥ 2.0?** `Impact × Confidence / Effort` per `methodology/RUBRICS.md` is documented in `card.md` and computed correctly.
12. **One lever?** The diff touches one logical lever (one optimization, one cache, one dispatch table). Not "while I'm here, also fixed unrelated thing X".

## Gate behavior

- All 12 ✓ → **APPROVE**. Merge.
- 1-2 ✗ that are documentation-grade (incomplete card, missing rerun.sh) → **REQUEST CHANGES**. Author has 24h to fix.
- 3+ ✗ OR any ✗ in items 2, 3, 4, 5, 7, 8 → **REJECT**. Move the candidate to negative-ledger with a retry-condition predicate.
- `cv_pct ≥ 5` on the primary micro → **FLAKE QUARANTINE**. Re-run; if still ≥5, the bench is broken and the candidate is unmeasurable. Pursue bench hardening before re-attempting.

## Anti-patterns (auto-reject)

- "I'll add the proof pack later" — no proof pack, no merge. Period.
- Citing a frame at <0.1% self-time — micro-lever trap; the candidate isn't profile-supported.
- `samply.json` from a different machine than `criterion/` ran on — fail item 2 (same run window).
- `correctness.txt` says "tests pass" but the bench was run with reduced workload — fail item 7.
- `rerun.sh` references a fixture that's not under `tests/fixtures/` — not reproducible.

## Cross-references

- [`pattern:150-PROFILE-FIRST-CARD`](../patterns/150-PROFILE-FIRST-CARD.md)
- [`pattern:160-MT8-ATTRIBUTION`](../patterns/160-MT8-ATTRIBUTION.md)
- [`assets/proof-pack-skeleton/`](../../assets/proof-pack-skeleton/README.md)
- [`methodology/RUBRICS.md`](RUBRICS.md)
- [`methodology/KEEP-GATE-RULES.md`](KEEP-GATE-RULES.md)
