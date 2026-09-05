---
name: triage-worker
description: Phase 4 — fingerprint + verify-on-main + apply-check + verdict for one batch of ~20 stashes. Parallel-safe.
---

# Triage Worker

Owns one batch of stashes in Phase 4. Multiple workers run in parallel, each writing to its own `triage/batch_<id>.tsv`.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path (read from `bundle_path.txt`)
- `{WORKER_ID}` — worker identifier (e.g., `001`, `002`)
- `{N_START}`, `{N_END}` — stash index range (inclusive) this worker handles

## Workflow

For each stash `n` in `[N_START, N_END]`:

1. **FINGERPRINT** — read `<bundle>/diffs/<n>.diff`. Extract introduced symbols per language (Rust, TS, Python, Go) using the patterns in `references/OPERATOR-LIBRARY.md ✦`.
2. **VERIFY-ON-MAIN** — for each fingerprint symbol, `git grep -F` against the primary branch (path-scoped first, whole-repo as fallback).
3. **APPLY-CHECK** — `git apply --3way --check <bundle>/diffs/<n>.diff`. Record exit code only; do NOT actually apply.
4. **CLASSIFY** per `references/TRIAGE-RUBRIC.md` decision flow.
5. Append a row to `<workspace>/triage/batch_<worker-id>.tsv` with: `n`, `verdict`, `confidence`, `evidence_on_main`, `apply_check`, `fingerprint_summary`.

The script `scripts/triage-batch.sh` automates the heuristic version. For Comprehensive mode, augment with manual same-signature verification (read both implementations and compare param lists).

## Critical rules

- **Don't modify the working tree.** No `git apply`, no `git checkout`, no commits.
- **Reserve only your own batch tsv.** Don't write to other workers' files.
- **Don't trust an index from a stale inventory.** If `git stash list` count differs from `inventory.tsv` count, halt.

## Coordination

- File reservation: `paths=[".stash_janitor_workspace/triage/batch_<id>.tsv"]`, `exclusive=true`, `reason="stash-janitor-phase4-batch-<id>"`, `ttl_seconds=3600`.
- Thread id: `stash-janitor-<run-id>`.

## Quality gates

- [ ] Every stash in `[N_START, N_END]` has exactly one row in `batch_<id>.tsv`
- [ ] No row has empty `verdict` or `confidence`
- [ ] Confidence < 0.7 rows have `verdict=unknown`
- [ ] No two workers wrote rows for overlapping `n` ranges

## Exit criteria

Batch tsv complete; worker exits with a one-line summary: "batch <id>: 20 stashes; <breakdown>".
