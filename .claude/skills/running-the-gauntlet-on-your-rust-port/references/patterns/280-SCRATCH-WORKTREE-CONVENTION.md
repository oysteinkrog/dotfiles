# 280-SCRATCH-WORKTREE-CONVENTION

**Family:** Negative-Ledger + Reproducibility. No glyph (operational convention).

**When to apply:** a perf or conformance candidate has been REJECTED but the code is worth preserving for possible future revisit. Don't pollute `main` with reverted commits or `// FIXME later` markers; keep rejected code in a structured scratch worktree per [`AGENTS.md § Code Editing Discipline`](../../../../../AGENTS.md) "No File Proliferation" rule.

## The pattern

```bash
# When a candidate is rejected (not kept on main):
PROJECT="$(basename "$PWD")"
FEATURE="<short-slug-describing-the-candidate>"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
SCRATCH="/data/tmp/${PROJECT}-${FEATURE}-${TIMESTAMP}"

# Move the rejected branch + commits into the scratch worktree
git worktree add --detach "$SCRATCH" HEAD
cd "$SCRATCH"
git checkout -b "rejected/${FEATURE}-${TIMESTAMP}"
# Apply the rejected diff
git apply < /tmp/rejected.patch
git add . && git commit -m "rejected: ${FEATURE} — see <ledger entry path> for retry-condition"

# Document the scratch in the ledger
cat >> docs/progress/perf-negative-results.md <<EOF

### $(date +%Y-%m-%d) — ${FEATURE} — REJECTED (rolled back from main; preserved in scratch)
- target_workload: <bench>
- files_touched: reverted-uncommitted-kept-in-scratch (path: ${SCRATCH})
- ... (full negative-ledger entry shape per pattern:180)
- scratch_branch: rejected/${FEATURE}-${TIMESTAMP}
- retry_condition_predicate: "<concrete predicate over future evidence>"
EOF
```

The convention is verbatim from the FrankenSQLite bibles (`CC.md PART VII`, especially §37–§39 ledger vocabulary): scratch worktrees live under `/data/tmp/<project>-<feature>-<timestamp>/`. The timestamp is mandatory (UTC ISO 8601 sortable form) so multiple scratch attempts on the same feature don't collide.

## Variants

### Status markers

The `files_touched` field in the ledger entry uses one of these standardized status markers (verbatim per FrankenSQLite's ledger discipline):

- `reverted-uncommitted` — rejected before any commit landed; nothing to preserve.
- `reverted-uncommitted-kept-in-scratch` — rejected before commit, but code worth preserving in a scratch worktree.
- `kept-in-scratch-only` — never on `main`; lived its whole life in a scratch worktree (e.g., a wild experimental rewrite).
- `kept-durable-infra` — kept on `main` because the harness/instrumentation/contracts are durable infra even if the optimization itself was rejected (e.g., a new HotPathProfileSnapshot field whose initial use was a perf-rejection but the field stays).
- `no-source-patch-attempted` — analysis-only rejection (e.g., "the profile shows this hotspot isn't worth optimizing"); no code was ever written.
- `behavior-preserving-check-verified` — the candidate's behavior-preservation was rigorously verified (e.g., `selections=` byte-identical) before perf rejection.
- `reverted-at-SHA-X-after-commit-SHA-Y` — was on `main` briefly (commit SHA-Y, reverted at SHA-X); scratch preserves the reverted-state code.

### Scratch worktree retention policy

- Scratch worktrees under `/data/tmp/` are NOT version-controlled; they're ephemeral on the host filesystem.
- The branch `rejected/<feature>-<timestamp>` inside the scratch IS git-tracked locally but is NOT pushed to origin.
- To resurrect: `git worktree add /data/tmp/<project>-<feature>-<new-timestamp> rejected/<feature>-<old-timestamp>` from any clone with the local branch.
- Retention: scratch worktrees may be removed when the disk fills up, BUT only after the operator confirms the ledger entry contains enough to recreate (per `retry_condition_predicate`).

## Failure modes

- **Scratch worktree never cleaned + accumulating** — `/data/tmp/` fills up; operator runs `df -h` and panics. Mitigation: `scripts/scratch-worktree-audit.sh` enumerates all `<project>-*-*` directories; flags ones older than 90 days for review.
- **Rejected code reappearing in main commits** — agent re-discovers the rejected idea, doesn't grep the ledger, and re-commits. Mitigation: `pattern:180-NEGATIVE-LEDGER` mandate paragraph in `AGENTS.md` requires ledger grep before every perf candidate.
- **Missing timestamp** — two simultaneous rejections of the same feature collide on `/data/tmp/<project>-<feature>/`. Mitigation: `TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"` is mandatory; the convention name says "timestamp" not "optional".
- **Scratch branch pushed to origin** — pollutes the remote with rejected branches. Mitigation: `.gitignore`-equivalent for branches via `git config branch.rejected/*.skip-push true` (or just discipline).
- **Ledger entry without scratch path** — entry says "rejected; preserved in scratch" but doesn't say WHERE. The whole point is recoverability; missing path = unrecoverable.

## Concrete example

From FrankenSQLite's actual ledger:

```markdown
### 2026-04-23 — htv-cache-lookup-by-blake3-hash — REJECTED (microbench faster, MT8 unchanged)
- target_workload: comprehensive-bench primary score
- files_touched: reverted-uncommitted-kept-in-scratch (path: /data/tmp/frankensqlite-htv-cache-blake3-20260423T143015Z)
- correctness_proof: "all oracle E2E pass + selections= byte-identical across mt-mvcc baseline + candidate"
- evidence_artifact_paths:
  - tests/artifacts/perf/20260423T143015Z-htv-cache-blake3/baseline.json
  - tests/artifacts/perf/20260423T143015Z-htv-cache-blake3/candidate.json
- baseline_configuration: {CARGO_TARGET_DIR=/data/tmp/cargo-target-frankensqlite, MODE=release-perf, GIT_SHA=abc123, PLATFORM=linux-x86_64-2.8GHz}
- candidate_configuration: {same as baseline + cfg=blake3-htv-cache}
- measured_result: microbench htv_lookup_p99 -23% (8.2ns → 6.3ns, cv_pct 2.1%); comprehensive-bench primary score +0.001 (within ±0.003 noise band)
- mt8_attribution: "no attributable frame ≥0.1% self-time for htv-cache lookup on MT8"
- retry_condition_predicate: "Retry only if a profiler attributes a clearly-above-noise share to htv_cache_lookup_time_ns on the 8-writer shared-table workload (e.g., from a new feature that increases htv-cache pressure)"
- scratch_branch: rejected/htv-cache-blake3-20260423T143015Z
- bead_id: bd-1dp9.5.2
```

The scratch worktree at `/data/tmp/frankensqlite-htv-cache-blake3-20260423T143015Z/` contains the rejected code; the ledger entry points to it; the retry-condition predicate names exactly the future evidence that would justify revisiting.

## Cross-references

- [`pattern:180-NEGATIVE-LEDGER`](180-NEGATIVE-LEDGER.md) — ledger entry shape.
- [`pattern:185-RETRY-CONDITION-PREDICATE`](185-RETRY-CONDITION-PREDICATE.md) — the load-bearing predicate.
- [`methodology/RETRY-CONDITION-VOCABULARY.md`](../methodology/RETRY-CONDITION-VOCABULARY.md) — the 8 verbatim forms.
- [`exemplars/RITUALS.md § WRITE-THE-REJECTION-ENTRY`](../exemplars/RITUALS.md) — the operator ritual that produces this pattern's output.
- [`cookbook/perf-regression-triage.md`](../cookbook/perf-regression-triage.md) — operator-facing recipe.
- [`scripts/mine-ledger.sh`](../../scripts/mine-ledger.sh) — searches for prior scratch entries before approving new perf work.
- AGENTS.md "Code Editing Discipline § No File Proliferation" — the rationale for keeping rejected variants OUT of `main`.
