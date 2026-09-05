# Scorecard Example — `br doctor` after Pass 1

A worked example of what `<workspace>/scorecard_pass_1.md` looks like for a mature project after one full upgrade pass. Numbers are realistic but synthetic for clarity.

This file is referenced from [WORKED-EXAMPLE.md](../references/methodology/WORKED-EXAMPLE.md) and shows the *shape* of the scorecard.

---

# Doctor Scorecard

**Tool:** `br + bv` | **Tool version:** `0.5.0` | **Doctor version:** `1.0.0`
**Pass:** `1` | **Run-id:** `2026-05-06T20-00-00Z__a3f9b2`
**Started at:** `2026-05-06T20:00:00Z` | **Target SHA:** `cb1c49e7...`

---

## Aggregate

**Aggregate score:** `893` (median per-FM, weighted by frequency × blast_radius)

| Threshold | Met? |
|-----------|------|
| All fixers reversible | yes |
| All fixers idempotent | yes |
| All fixers crash-recoverable | yes (after K=5ms regression fixed in iteration 2) |
| All fixers concurrency-safe | yes |
| `validate-doctor.sh` exit 0 | yes |
| Two clean fresh-eyes passes | yes (rounds 2 and 3) |
| `tests/doctor_fixtures/run_all.sh` exit 0 | yes |

---

## Per-failure-mode scores

| FM | Median | int | erg | aut | safe | idem | rev | spec | blast | obs | test |
|----|--------|-----|-----|-----|------|------|-----|------|-------|-----|------|
| fm-state-files-jsonl-tombstone-drift                | 950 | 950 | 950 | 1000 | 950 | 950 | 950 | 900 | 950 | 950 | 1000 |
| fm-schemas-db-version-mismatch                      | 940 | 950 | 940 | 900 | 1000 | 950 | 950 | 900 | 940 | 950 | 1000 |
| fm-state-files-db-family-partial-presence (NEW)     | 910 | 900 | 910 | 850 | 1000 | 1000 | 1000 | 850 | 900 | 950 | 1000 |
| fm-concurrency-primitives-stale-doctor-lock          | 890 | 900 | 890 | 1000 | 900 | 900 | 900 | 850 | 850 | 900 | 1000 |
| fm-configs-mcp-drift                                 | 870 | 900 | 870 | 950 | 900 | 850 | 850 | 850 | 850 | 850 | 1000 |
| fm-caches-stale-completion                           | 850 | 900 | 850 | 1000 | 800 | 850 | 850 | 850 | 850 | 800 | 1000 |
| fm-userland-state-config-dir-missing                 | 750 | 850 | 750 | 0    | 950 | 950 | 950 | 750 | 950 | 750 | 250  |
| fm-permissions-credential-too-permissive             | 880 | 900 | 880 | 1000 | 900 | 900 | 900 | 850 | 850 | 850 | 1000 |
| fm-external-artifacts-completion-script-stale        | 820 | 850 | 820 | 950 | 800 | 850 | 850 | 800 | 800 | 800 | 1000 |
| ... (19 more rows) ... |

---

## Heatmap

See `heatmap.svg`. Hot (low) cells cluster in:
- `automation_degree` for the 5 manual_remediations FMs (expected; correctly listed)
- `test_coverage_of_repair` for `fm-userland-state-config-dir-missing` (250) — fixture-author noted this is detect-only, scoring 250 reflects "fixture exists but no fix to test"

---

## Top improvements vs. previous pass

| FM | pass-0 (baseline) | pass-1 | Δ |
|----|-------------------|--------|---|
| fm-state-files-db-family-partial-presence | 0 (was missing) | 910 | +910 |
| fm-schemas-db-version-mismatch | 350 (existing detector only) | 940 | +590 |
| fm-state-files-jsonl-tombstone-drift | 720 | 950 | +230 |
| fm-concurrency-primitives-stale-doctor-lock | 580 (no auto-fix) | 890 | +310 |
| fm-configs-mcp-drift | 0 (was missing) | 870 | +870 |

---

## Regressions (each requires explicit acknowledgment)

| FM | pass-0 | pass-1 | Δ | ACK |
|----|--------|--------|---|-----|
| fm-state-files-cleanup-symlink (P3) | 600 | 570 | -30 | No ACK required (< 50pts) |

---

## Manual remediations (FMs we detect but cannot auto-fix)

| FM | Reason | User action |
|----|--------|-------------|
| fm-userland-state-config-dir-missing | Doctor doesn't create dirs it doesn't manage | run `br init` first |
| fm-secrets-token-expired | Auth credentials require user OAuth | run `br auth login` |
| fm-state-files-db-family-shm-without-wal-edge | Recovering from this state requires sqlite3 hand-edit | manually with `sqlite3 .beads/beads.db-shm` |
| fm-network-anthropic-api-key-missing | Doctor cannot generate API keys | `export ANTHROPIC_API_KEY=...` |
| fm-permissions-system-files-need-sudo | Chown changes require root | `sudo chown user:user <file>` |

---

## What's next

- See `recommendations.jsonl` for ranked recommendations (Phase 4 input).
- See `HANDOFF.md` for the next-pass summary.
- See `agent_simulations/post_pass_1/notes.md` for cold-prober findings (br-209: `--robot-triage::recommended_command` lists only one; br-210: `--explain --evidence-bytes`).

---

## Methodology footnote

Score derivation:
- Each (FM, dimension) cell scored 0–1000 against the 10-dim rubric anchors.
- Per-FM **median** is the cell-level median of the 10 dimension scores.
- **Aggregate** is the per-FM median weighted by `frequency × blast_radius`, capped at [0.5, 2.0] each.
- Frequency derived from CASS mining (counts per query) + bug-tracker counts.
- Blast_radius from severity per [PRIORITY-FORMULA.md](../references/rubric/PRIORITY-FORMULA.md): cosmetic=0.25 (P3), nuisance=0.5 (P2), degrades_correctness=1.0 (P1), corrupts_state=2.0 (P0 default), loses_data=4.0 (P0 catastrophic).

Computed by `scripts/scorecard.py render <workspace>` against `<workspace>/failure_mode_scores.jsonl`.
