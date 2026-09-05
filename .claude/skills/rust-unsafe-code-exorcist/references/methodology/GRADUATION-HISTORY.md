# GRADUATION-HISTORY.md — Tracking Bucket Changes Across Audit Runs

When a (B) site graduates to (C) on measurement, when a (C) site is promoted back to (B) because a property test failed, when an (A) was successfully defeated by an adversarial reviewer — these decisions matter beyond the audit that made them. A year later, the next audit shouldn't re-litigate them blind; it should consult the history and decide whether anything has changed.

This document defines the artifact: `<audit-dir>/audit/synthesis/graduation-history.md`. It's append-only, cross-run, and persists across re-audits of the same project.

---

## File schema

Markdown with a single chronological table at the top, optionally followed by per-event narrative sections.

```markdown
# graduation-history.md — site bucket changes across audits

## Chronological table

| Audit run | Date | Site ID | From | To | Reason | Evidence |
|-----------|------|---------|------|----|----|----------|
| audit-001 | 2026-02-14 | site-0142 | (B) | (C) | std::simd at parity on x86_64-v3 | benches in audit-001/plans/site-0142.md |
| audit-002 | 2026-04-20 | site-0142 | (C) | (C) | confirmed; std::simd still at parity | benches in audit-002/plans/site-0142.md |
| audit-003 | 2026-05-14 | site-0157 | (A) | (B) | rustix wrapper exists; perf within budget | adversarial pass 2, audit-003 |
| audit-003 | 2026-05-14 | site-0203 | (C) | (B) | property test found input class the rewrite mishandles | audit-003/plans/site-0203.md § regression |

## Per-event narrative

### audit-003 / site-0203 — (C) → (B)

The Phase 6 adversarial reviewer constructed an input where `bumpalo::Vec` ran out of arena and the safe rewrite panicked while the original unsafe rolled back gracefully via a sentinel pointer. The (C) was demoted to (B) pending a property-test extension.

Resolution path: extend the property test to model the OOM path; if the (C) handles it equivalently, re-promote.

### audit-002 / site-0142 — (C) → (C) (CONFIRMED)

Re-benched on a newer std::simd implementation. Still at parity. (C) confirmed.
```

---

## How the artifact is filled

### Per-audit-run, at Phase 4 / 6 exit

After classification converges:

1. Read the prior audit's `graduation-history.md` (if any) — typically at `<prior-audit-dir>/audit/synthesis/graduation-history.md` OR committed in the project's own `.audit-history/` directory.
2. For each site whose bucket DIFFERS from its prior-audit bucket, append a row.
3. For each site whose bucket MATCHES but where the decision was re-examined (e.g., (C) re-confirmed on bench), optionally append a "confirmed" row.
4. Site IDs in different runs may differ (line numbers move). Use the audit's stable-ID lookup: match by `(file, enclosing_fn, kind, source_excerpt-hash)`.

### Per-run, at the verify-only / drift-check tick

`scripts/cron-drift-check.sh` produces a daily snapshot. If any site's bucket has changed since baseline (rare during cron — usually drift surfaces NEW sites, not reclassifications), the change is appended.

### At skill-update time

When the skill itself adds a new pattern bundle, the graduation-history file gains a row noting "audit-NNN graduated site-NNNN to (C) using pattern from new bundle ZZ-NEW.md."

---

## Cross-audit ID stability

Site IDs are stable WITHIN an audit (Phase 1 assigns them in sort order). They're NOT stable ACROSS audits because line numbers move.

The cross-audit lookup uses `(file, enclosing_fn, kind, sha1(source_excerpt))` as the stable key. The graduation-history.md table includes both the audit-run-local ID and a stable-key fingerprint:

```markdown
| audit-003 | 2026-05-14 | site-0203 | (C) | (B) | ... |  // stable-key: a3f2:src/cache/lru.rs:LruEntry::insert:block
```

The `stable-key` enables a future audit to match `(file, enclosing_fn, kind, ...)` even when its `line_start` differs.

---

## Why this exists

Three real audit scenarios:

1. **The "didn't we already decide this?" scenario.** A new audit lands. The Phase 6 reviewer proposes graduating site-XXX from (B) to (C) using std::simd. Without this artifact, the reviewer doesn't know that audit #1 already tried this and rejected it. Wasted audit budget.
2. **The "what changed?" scenario.** A site that was (A) in audit #1 is now (B) in audit #3. The maintainer asks why. The graduation-history tells them: the adversarial reviewer found a rustix wrapper that satisfies the (A) attack.
3. **The "monitoring drift" scenario.** A site holds (C) classification for 4 quarterly audits, then suddenly fails the equivalence property test in audit #5. The history shows when the (C) was first established and lets the team trace what changed in between (probably an upstream dep update).

---

## Where to put it across runs

Two conventions:

1. **Within the audit dir.** `<audit-dir>/audit/synthesis/graduation-history.md`. Each audit has its own snapshot. The new audit reads the prior one explicitly.
2. **In the project repo.** `<project>/.audit-history/graduation-history.md`. Committed to the project. Survives audit-dir deletions; visible to all maintainers in PRs.

The skill recommends convention (2) for projects under sustained audit (continuous mode, quarterly cadence, or both). Convention (1) is the default; the orchestrator copies the file from prior runs when it detects them.

---

## Cross-references

- [CLASSIFICATION-RUBRIC.md § Iteration discipline](CLASSIFICATION-RUBRIC.md) — the rule for when bucket changes are allowed.
- [REJECTED-PATTERNS.md](REJECTED-PATTERNS.md) — the cousin artifact at the corpus-level (these patterns were tried + rejected across multiple audits + projects).
- [CONTINUOUS-MODE.md](CONTINUOUS-MODE.md) — drift detection that may surface graduation events.
- [DIFFERENTIAL-AUDIT.md](DIFFERENTIAL-AUDIT.md) — when comparing two versions of a project, the graduation history is the audit-history baseline.
- [SOUNDNESS-ARCHEOLOGY.md](SOUNDNESS-ARCHEOLOGY.md) — the git-history mining cousin; together they form the project's soundness-decision audit trail.
