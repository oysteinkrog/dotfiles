# Priority Formula

```
priority(fm) = frequency(fm) × score_gap(fm) × blast_radius(fm)
```

Highest-priority failure modes are the ones the doctor should detect + fix first. Phase 4's bead backlog is sorted by this score.

## frequency(fm)

How often this FM is hit, measured across three signals:

1. **CASS mention count.** `cass search "<symptom>" --robot --limit 50 --days 90` — count of session matches.
2. **Bug tracker.** `br list --json | jq '.issues[]? | select(.title | test("<symptom>"))' | wc -l` and `gh issue list --search "<symptom>" --json number --jq length`.
3. **Git log.** `git log --all --grep="<symptom>" --since=90.days --oneline | wc -l`.

Final value is `(0.5 × normalized_cass + 0.3 × normalized_tracker + 0.2 × normalized_log)`, clamped to [0.5, 2.0]. Normalization is per-tool (divide by max in the tool's set).

## score_gap(fm)

```
score_gap(fm) = (1000 - fm_score(fm)) / 1000
```

Range [0.0, 1.0]. A perfectly-handled FM has gap 0; a completely-unhandled FM has gap 1.0.

## blast_radius(fm)

How bad is it to leave this FM unfixed? Calibrated 0.25 → 4.0:

| Severity | Blast radius | Description |
|----------|--------------|-------------|
| `cosmetic` | 0.25 | UI-only annoyance; no data risk; no agent confusion |
| `nuisance` | 0.5 | Wastes agent round-trips; recoverable with one command |
| `degrades_correctness` | 1.0 | Subtly wrong output; agent might trust it |
| `corrupts_state` | 2.0 | Corrupts the project's state file or DB; recovery requires the manual playbook this skill is replacing |
| `loses_data` | 4.0 | Permanently loses user data without backup; reputation event |

P0 ⇒ `corrupts_state` or `loses_data`. P1 ⇒ `degrades_correctness`. P2 ⇒ `nuisance`. P3 ⇒ `cosmetic`. The synthesizer in Phase 3 sets blast_radius based on the failure-mode catalog and the project-specific `safety_envelope.md`.

## Composition example

| FM | frequency | score_gap | blast_radius | priority |
|----|-----------|-----------|--------------|----------|
| `fm-db-schema-version-mismatch` | 1.8 | 1.0 | 4.0 | 7.20 |
| `fm-jsonl-tombstone-drift`      | 1.2 | 0.7 | 2.0 | 1.68 |
| `fm-stale-completion-script`    | 0.6 | 0.5 | 0.5 | 0.15 |

Implementer beads are pulled in descending priority order. CI fails any pass whose top-3-priority FMs aren't all addressed (or explicitly deferred with a written reason).
