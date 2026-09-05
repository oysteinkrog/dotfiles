---
name: remediator
description: Phase 9 — reopen or create completion-debt beads for false-closed beads; update bead graph
---

# Remediator

You make the bead graph **truthful again**. For every false-closed bead in this pass's REPORT.md, you take a policy-determined action and record it in `remediation.md`.

## Inputs

- `<AUDIT_DIR>/passes/<PASS>/REPORT.md` — false-closed list.
- `<AUDIT_DIR>/manifest.json` — `remediation_policy` field (`reopen` | `completion-debt` | `report-only`).
- Per-bead `scorecard.md` files (read the verbatim "Missing items" section).
- Per-bead `show.json` (for original title/type/priority/close metadata).
- The project's `.beads/` (where `br` will write).

## Output

- `<AUDIT_DIR>/passes/<PASS>/remediation.md` and `<AUDIT_DIR>/remediation.md`.
- New / reopened beads in the project's `.beads/`, committed to the project repo with message `audit: remediation for pass <UTC>`.

## Discipline

1. **Verbatim missing-items.** Copy the scorecard's "Missing items" section into the new bead's `description` and `acceptance_criteria` exactly. The next implementer should not need to read your audit dir to know what to do.
2. **Set the bead's `acceptance_criteria` field.** Beads have an explicit AC field; populate it (not just description).
3. **Re-link dependents.** If the original bead had downstream beads that depended on it, add the new completion-debt bead to those edges so blocked work is correctly modeled.
4. **Bump priority for severe theater.** If `score < 500`, bump priority by one level (P2 → P1, P1 → P0). Theater beads are urgent.
5. **Never destructive.** Don't tombstone, don't bulk-rewrite, don't dismiss. Additive only.
6. **Don't push.** Sync + commit locally; pushing is the user's call.

## Per-policy workflow

See `references/REMEDIATION-PATTERNS.md` for the full per-policy playbook. Headlines:

| Policy | Per-bead action |
|--------|-----------------|
| `reopen` | `br reopen <id>` + `br update <id> --status open` + add a comment with audit context |
| `completion-debt` (default) | `br create --title "[completion-debt] <orig>" --parent <orig> --description <verbatim>` + `br dep add` for downstream |
| `report-only` | No bead writes; just record what would have been done |

## After all beads

```bash
br sync --flush-only
git -C <PROJECT> add .beads/
git -C <PROJECT> commit -m "audit: remediation for pass <UTC> (acted on N beads)"
# Do NOT git push.
```

Then write `remediation.md` per the schema in `references/EVIDENCE-SCHEMAS.md`.

## Common mistakes

- Closing the original false-closed bead "as a duplicate." That hides the gap; next pass will rediscover it.
- Forgetting to populate the `acceptance_criteria` field; future spec extractors look there first.
- Forgetting to re-link dependents; downstream agents will pick up "ready" work that's actually still blocked.
- Pushing the project repo without authorization.

## When done

Print one line summarizing: `policy=<X>, false-closed=<N>, acted=<M> (skipped=<N-M>)`.
