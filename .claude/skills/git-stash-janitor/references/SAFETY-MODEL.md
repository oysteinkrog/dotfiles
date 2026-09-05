# Safety Model — Reversibility Chain Per Destructive Action

This file enumerates every action the skill takes that *could* lose work, and the reversibility chain that backs it up.

---

## Threat Model

The user gives this skill access to a repo with valuable, possibly-fragile work in stashes. The skill's job is to keep useful content and drop the rest. Things that could go wrong:

1. **Mis-classification** — a useful stash gets verdict `garbage` or `superseded`.
2. **Wrong drop** — index drift causes the wrong stash to be dropped.
3. **Corrupted bundle** — the bundle's diffs don't match the live stashes.
4. **Lost backup refs** — `git gc` runs aggressively and prunes unreachable stash commits before backup refs are made.
5. **Bypassed authorization** — destructive action runs without explicit user OK.
6. **Concurrent agent destruction** — the skill stashes/reverts concurrent agents' work.
7. **Bypassed quality gates** — a recovered keeper introduces a regression.
8. **Compounding errors** — multiple keepers applied in sequence, each subtly broken; only the final test run catches it.
9. **Ambiguous user authorization** — user said "yes" but didn't realize what they authorized.
10. **Bundle deletion** — the bundle and backup refs both get destroyed before recovery is needed.

---

## Reversibility Chain

The skill builds a multi-layer safety net. Each destructive action has at least two independent reversibility paths:

### Layer 1: Backup Refs

Created by `⬡ BUNDLE`:

```
.git/refs/stash-backup/000  → stash@{0}'s commit SHA
.git/refs/stash-backup/001  → stash@{1}'s commit SHA
...
.git/refs/stash-backup/126  → stash@{126}'s commit SHA
```

These are **inside the repo** (in `.git/`). They survive:
- `git stash drop` (the dropped stash's commit becomes unreachable from the stash log, but the backup ref keeps it reachable)
- `git stash clear`
- `git gc --prune=now` (because they're real refs, garbage collection sees them as roots)

They do NOT survive:
- Manual `git update-ref -d refs/stash-backup/<n>` followed by `git gc --prune=now`
- `git push --force-with-lease` to a remote that doesn't have these refs (but that doesn't affect the local copy)
- `rm -rf .git` (catastrophic; nothing survives this)

### Layer 2: Bundle Diffs

Created by `⬡ BUNDLE`:

```
<project-parent>/<basename>-stash-archive-<DATE>/
  diffs/000.diff  ← git stash show -p --binary <index.tsv:sha>
  diffs/001.diff
  ...
  meta/<NNN>.txt
  index.tsv
  README.md
  stashed-untracked/<NNN>/  (only when stash was -u)
```

These are **outside the repo** (in the parent directory). They survive:
- Anything that happens to `.git/`
- `git gc`
- Repository corruption
- Project relocation (the diffs use relative paths)

They do NOT survive:
- Explicit `rm` of the bundle directory
- Filesystem corruption / disk loss

### Layer 3: Per-Action Authorization

Every destructive action requires explicit user OK with a verbatim phrase per AGENTS.md "Mandatory explicit plan":

```
Phase 5 gate: user OK to start applying keepers
Phase 6 conflict: user OK on each manual conflict resolution
Phase 9 gate: user pastes the verbatim authorization phrase
```

The phrase is recorded with timestamp in `cleanup_authorization.txt` (or the analogous file for other gates). If that file doesn't exist, the action did not happen.

### Layer 4: Per-Apply Quality Gates

Every Phase 6 / Phase 7 commit goes through `⊕ RECOVER`:

```
{test_command}
{typecheck_command}
{lint_command}
ubs .   # if available
```

All must exit 0 BEFORE commit. If any fail, the apply is rolled back via `git apply -R` (which doesn't need DCG-blocked operations). The keeper can then be:
- Skipped (`conflict-skipped`)
- Adapted via Edit tool and re-tried
- Surfaced to user

### Layer 5: Phase Gates

Each phase has an exit criteria that must hold before the next phase can run:

| Phase | Gate |
|-------|------|
| 3 | Byte-equality verified for every backup ref AND every diff |
| 5 | User explicitly typed approval |
| 6 | Quality gates passed for every applied keeper (per-apply, not at end) |
| 8 | Two consecutive clean fresh-eyes rounds |
| 9 | User typed the verbatim authorization phrase |

A failure at any gate halts the run. The user investigates.

### Layer 6: Recovery Branch Isolation

Phase 6 / Phase 7 commits land on `stash-recovery-<DATE>`, not on the primary branch. Even if every gate passed wrong, the user can:

```bash
git branch -D stash-recovery-<DATE>   # only after explicit user confirmation
```

The primary branch is untouched.

---

## Per-Action Mapping

| Action | Layer 1 | Layer 2 | Layer 3 | Layer 4 | Layer 5 | Layer 6 |
|--------|---------|---------|---------|---------|---------|---------|
| Phase 3 backup ref creation | ✓ | — | — | — | — | — |
| Phase 6 apply keeper | ✓ | ✓ | — | ✓ | ✓ | ✓ |
| Phase 6 commit | ✓ | ✓ | — | ✓ | — | ✓ |
| Phase 6 manual conflict resolution | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| Phase 7 split-apply | ✓ | ✓ | — | ✓ | ✓ | ✓ |
| Phase 9 stash drop | ✓ | ✓ | ✓ | — | ✓ | — |
| Phase 9 multi-stash drop | ✓ | ✓ | ✓ | — | ✓ | — |

Every drop has at least two independent recovery paths for tracked/index changes (backup ref + bundle diff), plus materialized untracked files when applicable. Applied keepers also have recovery branch isolation. The only single-point-of-failure is Layer 5 — if the user authorizes incorrectly. That's mitigated by:

- The verbatim authorization requirement (the user has to type a specific phrase)
- The Phase 5 decision table (the user reviews verdicts before any destructive action)
- The "no `git stash clear`" rule (every drop is per-stash, surfaced verbatim)

---

## What's NOT Recoverable

To set expectations: the skill is robust against typical agent / human errors, but not invulnerable.

| Catastrophe | Recoverable? |
|------------|--------------|
| User runs `git stash clear` after Phase 9 | Yes (backup refs still exist; bundle still exists) |
| User runs `rm -rf .git` | No (catastrophic; only the bundle survives, but .git includes refs) |
| User runs `rm -rf <bundle>` | Layer 1 still works; recovery via backup refs |
| User runs `rm -rf .git AND <bundle>` | NOT RECOVERABLE — the user explicitly destroyed both safety nets |
| Disk failure | Recoverable from backups (off-skill) |
| `git gc --prune=now` after manual `git update-ref -d refs/stash-backup/*` | Layer 1 gone; Layer 2 still works |
| `git gc --prune=now` after `rm -rf <bundle>` | Layer 2 gone; Layer 1 still works |
| Both refs deleted AND bundle deleted AND `git gc --prune=now` | NOT RECOVERABLE |

The skill never destroys both layers. Layer 1 lives in `.git/refs/`; the skill never deletes anything under `.git/` except via specifically-authorized `git stash drop` commands (which only affect the stash log, not backup refs). Layer 2 lives outside the repo; the skill never deletes the bundle.

---

## Layer 1+2 Independence

A key design property: Layer 1 (backup refs) and Layer 2 (bundle) are independent. Damage to one doesn't damage the other.

| Action affecting Layer 1 | Affects Layer 2? |
|-----------------------|------------------|
| `git stash drop stash@{N}` | No (bundle is on disk outside `.git/`) |
| `git stash clear` | No |
| `git gc --prune=now` | No |
| `git update-ref -d refs/stash-backup/<n>` | No |
| `rm -rf .git` | No |

| Action affecting Layer 2 | Affects Layer 1? |
|-----------------------|------------------|
| `rm -rf <bundle>` | No (refs are in `.git/refs/`) |
| `mv <bundle> /tmp/` | No |
| Filesystem corruption on `<bundle>`'s parent | No |

---

## Security Properties

**Confidentiality:** the bundle contains the full content of every stash. If the repo's stashes have secrets (API keys, passwords) — which they shouldn't, but might — the bundle inherits them. The bundle's path should not be world-readable on shared systems. The skill writes the bundle with default umask permissions; the user controls the parent directory's permissions.

**Integrity:** the bundle's `index.tsv` records SHA + parent SHA + date for every stash. If a malicious actor modifies a diff in the bundle, byte-equality verification (Phase 3) catches it on a re-run. The bundle's `README.md` documents this property so the user can re-verify after the run completes.

**Availability:** the recovery story works as long as either Layer 1 or Layer 2 survives. The skill leaves both intact at end-of-run.

---

## Failure Recovery Sequence

If the skill detects an inconsistency at any point:

1. **HALT.** Do not proceed.
2. **Surface.** Tell the user what was detected and what state the run is in.
3. **Document.** Write the failure to `<workspace>/halt_reason.txt`.
4. **Wait.** Don't ask "should I continue anyway?" — the user investigates first.

Examples:

- Phase 3 byte-equality mismatch → halt; tell user to investigate `bundle_verification.log`.
- Phase 9 list-shift detected (message doesn't match inventory) → halt; tell user a concurrent agent may have changed the stash list.
- Phase 6 apply succeeds but `cargo test` fails AND the failure isn't a known pre-existing one → halt; surface the test output; ask user direction.

The skill always errs toward not-doing, not toward proceeding-and-hoping.
