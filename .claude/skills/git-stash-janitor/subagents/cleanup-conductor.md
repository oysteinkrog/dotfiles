---
name: cleanup-conductor
description: Phase 9 — gated destructive cleanup. Drops stashes individually in correct order with verbatim user authorization. Never `git stash clear`.
---

# Cleanup Conductor

Owns Phase 9. The skill's only destructive phase. Heavily gated. Per AGENTS.md "Mandatory explicit plan".

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir

## Pre-conditions (HARD GATES)

- [ ] Phase 8 termination rule met (≥2 clean fresh-eyes rounds, gates green)
- [ ] `<workspace>/cleanup_authorization.txt` does NOT yet exist
- [ ] `triage.tsv` and `apply_log.tsv` are present and complete
- [ ] Every backup ref in `refs/stash-backup/*` exists for every stash to be dropped (no missing backups)

If any pre-condition fails, refuse to start.

## Workflow

1. **Build cleanup plan**:
   - Bucket-ordered: garbage → superseded / superseded-by-newer-stash → novel-but-stale → applied-keeper
   - Within each bucket: descending by `n` (highest index first; indexes shift after drops)
   - Materialize as `<workspace>/cleanup_plan.tsv` with columns `n, current_ref, verdict, message`

2. **Build verbatim authorization request**:
   ```
   I'm about to run the following destructive commands in this order:

     git stash drop stash@{<highest-garbage>}      # garbage: <message>
     git stash drop stash@{...}
     ... (all garbage drops, descending) ...
     git stash drop stash@{<highest-superseded>}    # superseded: <message>
     ...
     (all superseded drops)
     ...
     git stash drop stash@{<applied-keeper>}        # applied-keeper: <message>

   Backup refs at refs/stash-backup/* and the bundle at <BUNDLE> stay intact.

   To proceed, paste this verbatim:
     yes I understand and want to drop all <N> stashes per the plan above
   ```

3. **Wait for verbatim authorization.** If the user types something different ("yes", "ok", "go ahead"), refuse and re-ask. If the user objects to the verbatim requirement, explain it's per AGENTS.md.

4. **Record authorization** with timestamp:
   ```bash
   echo "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > <workspace>/cleanup_authorization.txt
   echo "<user's exact authorization text>" >> <workspace>/cleanup_authorization.txt
   ```

5. **Execute drops** one per line, using `scripts/drop-confirmed.sh`:
   ```bash
   for row in cleanup_plan.tsv:
     n = row.n
     ./scripts/drop-confirmed.sh {PROJECT} $n confirm=YES_DROP_$n
   ```
   The script restates the verbatim command before executing and records to `cleanup_log.tsv`.

6. **Post-cleanup verification**:
   - `git stash list | wc -l` matches expected count (typically 0 if everything dropped)
   - Every backup ref `refs/stash-backup/<NNN>` still resolves
   - `cleanup_log.tsv` has one row per drop

## Critical rules

- **NEVER run `git stash clear`.** Every drop is per-stash.
- **NEVER delete the bundle.** User manages bundle lifecycle.
- **NEVER delete `refs/stash-backup/*`.** They survive `git stash clear` only because they're separate refs.
- **Highest-index-first within each bucket.** Lower-first causes index drift.
- **If a drop fails** (e.g., the stash was already gone because a concurrent agent dropped it), HALT and rebuild the cleanup plan from the current stash list before continuing. Do not continue on stale stack indexes.
- **If the stash list shifts unexpectedly** (the message at `stash@{n}` doesn't match `inventory.tsv`), HALT and ask the user.

## Coordination

- File reservation: `paths=[".git/refs/stash/**", ".git/logs/refs/stash"]`, `exclusive=true`, `reason="stash-janitor-phase9"`.

## Quality gates

- [ ] `cleanup_authorization.txt` exists with verbatim user text
- [ ] `cleanup_plan.tsv` has descending-index order within each bucket
- [ ] Every dropped stash has a corresponding row in `cleanup_log.tsv`
- [ ] All `refs/stash-backup/*` refs still exist
- [ ] Bundle directory still exists

## Exit criteria

Final state: `git stash list` matches expected count; every backup ref intact; bundle intact; main agent proceeds to Phase 10.
