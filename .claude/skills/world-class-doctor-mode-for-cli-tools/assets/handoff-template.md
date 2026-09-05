# HANDOFF — Pass `<N>`

**Tool:** `<tool>` | **Doctor version:** `<doctor-version>`
**Target SHA at start:** `<sha-before>` | **Target SHA at end:** `<sha-after>`
**Branch:** `doctor-mode-pass-<N>` | **Started:** `<ISO8601>` | **Finished:** `<ISO8601>`
**Duration:** `<HH:MM:SS>`

---

## Pass summary

- Mode: `add` | `upgrade` | `audit-only` | `re-score-only` | `single-failure-mode-rescore` | `absorb-playbook`
- Failure modes inventoried: `<N>`
- Repair specs written: `<N>`
- Implementations landed: `<N>` (`<applied_changes.jsonl>` for line-by-line)
- Phase 5 five-test run: `<N pass>` / `<N fail>` (failures investigated and fixed before phase-6)
- Fresh-eyes rounds run: `<N>` (last `<K>` clean)
- Fixtures added: `<N>` (`tests/doctor_fixtures/`)

---

## Scorecard before / after

| Metric | Before | After | Δ |
|--------|--------|-------|---|
| Aggregate | `<0-1000>` | `<0-1000>` | `<+/-N>` |
| FMs P0 | `<n>` | `<n>` | `<+/-n>` |
| FMs P1 | `<n>` | `<n>` | `<+/-n>` |
| FMs P2 | `<n>` | `<n>` | `<+/-n>` |
| FMs P3 | `<n>` | `<n>` | `<+/-n>` |

### Top 5 improvements

| FM | Before | After | Δ |
|----|--------|-------|---|
|    |        |       |   |

### Top 5 regressions (or "_none_")

| FM | Before | After | Δ | ACK |
|----|--------|-------|---|-----|
|    |        |       |   |     |

---

## What changed (commits on `doctor-mode-pass-<N>`)

```
<git log --oneline doctor-mode-pass-<N> ^main>
```

Highlights:
- `<sha>` `doctor: introduce mutate() chokepoint`
- `<sha>` `doctor(state_files): fm-jsonl-tombstone-drift: detect + fix + fixture`
- `<sha>` `doctor(schemas): fm-db-schema-version-mismatch: detect + fix + fixture`
- ...

---

## Open issues (beads filed during this pass)

| Bead | Priority | Title | Owner |
|------|----------|-------|-------|
| br-NNN | 0 | doctor: ... | ... |
| br-NNN | 1 | doctor: ... | ... |

(Run `br ready --json | jq '.[] | select(.title | startswith("doctor:"))'` for the live view.)

---

## Next pass recommendations

1. **<title>** — `<rationale>`. Expected uplift: `<+N pts>` on `<dimension>`. Complexity: S/M/L.
2. **<title>** — ...
3. **<title>** — ...
4. ...
5. ...

---

## Files of interest

- `<workspace>/scorecard_pass_<N>.md` — full scorecard
- `<workspace>/heatmap.svg` — visual
- `<workspace>/uplift_diff.md` — pass-(N-1) → pass-N deltas
- `<workspace>/regression_alerts.md` — any regression > 50 pts (with ACKs)
- `<workspace>/agent_simulations/post_pass_<N>/notes.md` — cold-prober findings
- `<workspace>/applied_changes.jsonl` — line-by-line of every implementation change
- `<target>/.doctor/runs/<latest>/` — most recent in-tree run artifact
- `<target>/tests/doctor_fixtures/` — fixture suite

---

## Hand-off note

The most important context for the next pass: `<one paragraph naming the
single most surprising finding, the choice that needs reviewing, or the
regression that wasn't yet addressed>`.
