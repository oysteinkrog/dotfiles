# Triage Decision Template

Used by `merge-triage.sh` to generate `triage_decision.md` for Phase 5 user surface. See the script for the auto-generated version.

---

```markdown
# Triage decision

{TOTAL} stashes triaged. Review below; reply with "go" to proceed (or override per-row).

## Verdict counts

| verdict | count | proposed action |
|---------|-------|----------------|
| novel-and-accretive | {N_NOVEL} | apply on stash-recovery branch |
| partially-novel | {N_PARTIAL} | split-apply (novel hunks only) |
| superseded | {N_SUPER} | drop after Phase 9 authorization |
| superseded-by-newer-stash | {N_SUPER_NEWER} | drop after Phase 9 authorization |
| garbage | {N_GARBAGE} | drop after Phase 9 authorization |
| novel-but-stale | {N_STALE} | manual decision (default: drop with note) |
| unknown | {N_UNKNOWN} | **surface to user** (must resolve before Phase 6) |

## ⚠ MANUAL — unknown ({N_UNKNOWN}) — needs user verdict

| n | message | conf | evidence | apply_check |
|---|---------|------|----------|-------------|
{rows}

## ✓ KEEP — novel-and-accretive ({N_NOVEL})

| n | message | conf | evidence | apply_check |
|---|---------|------|----------|-------------|
{rows}

## ✂ KEEP-WITH-SPLIT — partially-novel ({N_PARTIAL})

| n | message | conf | evidence | apply_check |
|---|---------|------|----------|-------------|
{rows}

## ? MANUAL — novel-but-stale ({N_STALE})

| n | message | conf | evidence | apply_check |
|---|---------|------|----------|-------------|
{rows}

## 🗑 DROP — superseded ({N_SUPER})

<details><summary>Click to expand {N_SUPER} rows</summary>

| n | message | conf | evidence | apply_check |
|---|---------|------|----------|-------------|
{rows}

</details>

## 🗑 DROP — garbage ({N_GARBAGE})

<details><summary>Click to expand {N_GARBAGE} rows</summary>

| n | message | conf | evidence | apply_check |
|---|---------|------|----------|-------------|
{rows}

</details>

## Triangulation summary (Comprehensive mode only)

- Unanimous: {N_UNANIMOUS} rows
- Majority (2 of 3): {N_MAJORITY} rows
- Disagreement: {N_DISAGREEMENT} rows (surfaced to user above)

## Next step

Reply with one of:
- `go` — proceed to Phase 6 with the verdicts above
- `keep stash@{N} too` (per-row override) — change verdict to novel-and-accretive
- `drop stash@{N}` (per-row override) — change verdict to garbage
- `wait` / `stop` — abort the run; bundle and refs remain intact

The skill will not proceed until you authorize.
```

---

## Sorting within sections

Within each verdict section, rows should be sorted by **confidence ascending** — the most ambiguous rows appear first, where they're most prominent for user attention. The asupersync session showed this is what users want; high-confidence rows can be skimmed.

---

## What to highlight

For Comprehensive mode runs, add a `triangulation` column showing model agreement. For runs with overrides applied, mark overridden rows with `★`.

If `cass_findings.md` has prior-run context, add a "Prior-run context" section above the verdict counts:

```markdown
## Prior-run context

A previous run of this skill on this project (2026-04-12) authored 2 keepers.
Both merged via PR #234. Treat their content as expected supersession.
```
