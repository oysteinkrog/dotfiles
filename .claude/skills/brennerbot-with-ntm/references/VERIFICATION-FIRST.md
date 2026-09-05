# VERIFICATION-FIRST.md — Live-Source Verification Discipline

<!-- TOC: When this applies | The discipline | Source classes | Verification recipes | Audit trail | Anti-patterns -->

Mirrors saas-billing's VERIFICATION-FIRST.md. The patterns in this skill are evergreen. Live source state is volatile. Read this before finalizing any recommendation that depends on volatile data.

---

## When this applies

This protocol applies when ANY of these are true:

- The question of record names a specific external system whose state could change between Phase 1 and Phase 9 (live API surface, third-party benchmark, online published paper, ongoing production incident, in-flight regulatory ruling)
- Phase 4 evidence cites a URL or DOI that could be updated/retracted
- A `H-*` claim depends on the current behavior of a tool/library/service
- The session is T4+ where the cost of acting on stale information is severe
- The session is `code-investigation` mode and the target codebase is under active development

It does NOT apply for:

- Pure corpus-distillation over a frozen corpus (content-hash pinned)
- First-principles synthesis (no external source dependence)
- Methodology drift checks (analyzing past sessions, not live state)

---

## The discipline

**Core rule:** Do not give a live recommendation that depends on a volatile field UNTIL it has been verified read-only against the live source AND logged in `analyses/official-source-log.md`.

In practice:

1. At Phase 1, identify which claims would depend on volatile sources. Flag them in `intake/question_of_record.md § Volatile-source dependencies:`.
2. At Phase 4, every `EV-*` from a volatile source must include `imported_at:` (already in schema) AND `source_freshness:` (NEW field — `live | frozen | stale-by-<duration>`).
3. At Phase 7 audit, every `confirmed` H whose evidence has `source_freshness:` older than 24h MUST be re-verified before Phase 8 freeze.
4. At Phase 9 handback, the `## Volatile-source caveat` section explicitly lists volatile dependencies and their freshness at freeze time.
5. RESUME.md `volatile_sources_to_recheck:` field lists what would need re-verification on resume.

---

## Source classes

| Class | Volatility | Freshness window | Verification cost |
|-------|------------|------------------|-------------------|
| Frozen text (PDF, archived web) | none | infinite | one-time pin |
| Versioned source (specific commit, tagged release) | none until the operator decides to bump | infinite while pinned | one-time pin |
| Mainline branch / `latest` tag | hours | 24h | re-fetch + diff |
| Live API surface | seconds-minutes | minutes | re-call |
| Live benchmark / leaderboard | hours-days | 24h | re-fetch |
| In-flight discussion (issue tracker, mailing list) | continuous | <1h | manual re-read |
| Ongoing incident state | continuous | minutes | live monitoring |
| Regulatory / legal | weeks-months but with cliff events | 1 week + watchlist | check primary sources |

For each class in the corpus_index.md, record the class. `corpus-curator.md` updates the index per source.

---

## Verification recipes

### Recipe V1 — Frozen sources (papers, PDFs, archived pages)

**One-time:** content-hash at ingestion. Per CORPUS-CURATION.md.

**Re-verify:** never required during the session.

### Recipe V2 — Versioned source code

**One-time:** pin via `git rev-parse HEAD` + dirty status.

**Re-verify:** before Phase 8 freeze, run `git rev-parse HEAD` and confirm SHA matches the pinned value. If drift, log + decide: re-pin to current OR stop for explicit operator approval before any rollback toward the original SHA.

### Recipe V3 — Live URL / API

**One-time at ingestion:** fetch + record `etag`/`last-modified` headers if available.

**Re-verify (Phase 4 → Phase 7):** re-fetch and compare. If content drifted:

1. Diff the change against current `EV-*` excerpts
2. If excerpts still match → update `source_freshness: live`
3. If excerpts no longer match → mark `EV-*.verified=false` with `verification_notes: "source drift on YYYY-MM-DD"`
4. File audit-finding if any `confirmed` H depends on the drifted EV

### Recipe V4 — Live benchmark / leaderboard

**One-time:** snapshot the leaderboard table + URL + access timestamp.

**Re-verify:** before Phase 6 distillation, re-fetch leaderboard. Distillations cite specific rank/value at access time, not "the current top".

### Recipe V5 — In-flight discussion

**One-time:** snapshot + record permalink (e.g., GitHub issue comment ID).

**Re-verify:** if the discussion is foundational to the question, monitor periodically; treat new comments as potential new evidence (file as `EV-*` if material).

### Recipe V6 — Regulatory / legal

**One-time:** cite primary source (statute, regulation, court ruling) with version date.

**Re-verify:** if the regulatory landscape shifts during the session, file as `anomaly` and possibly trigger Phase 4 reopen.

---

## Audit trail

`<workspace>/analyses/official-source-log.md` (append-only) records every verification event:

```markdown
# Official Source Log

| Timestamp | Source ID | Class | Action | Verifier (pane) | Outcome | Notes |
|-----------|-----------|-------|--------|-----------------|---------|-------|
| 2026-05-06T15:32:00Z | S-007 | live-API | re-fetch | p3 | match | etag unchanged |
| 2026-05-06T16:15:00Z | S-012 | live-leaderboard | re-fetch | p4 | drift | rank changed; updated EV-027 |
```

Phase 7 audit reads this log and checks:

- Every volatile source has at least one re-verification event after its first ingestion
- No `confirmed` H depends on stale evidence
- The drift events were appropriately handled

Phase 10 drift-check uses the log as input — operator overusing "frozen" classification when source is actually volatile is a methodology drift to flag.

---

## Phase 9 handback caveat

If the session has any volatile-source dependency, HANDBACK.md MUST include:

```markdown
## Volatile-source caveat

This recommendation depends on the following volatile sources, last verified at freeze time:
- S-007 (live API): verified 2026-05-06T16:00Z
- S-012 (leaderboard): verified 2026-05-06T16:30Z

If you act on this recommendation more than 7 days from freeze, re-verify these sources OR re-run the relevant Phase 4 round on resume.
```

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Pin everything as "frozen" to avoid re-verification | Skips real drift; recommendations age silently |
| Re-verify only at Phase 7 audit, not periodically | A 6-hour Phase 4 against a 1-hour-volatile API gives stale answers |
| Treat re-verification as Phase 7's responsibility alone | Investigators (Phase 4) should re-verify their own EVs every round if volatile |
| Skip the official-source-log.md | Phase 10 drift-check can't reconstruct what was verified |
| HANDBACK without volatile-source caveat | User acts on the recommendation as if it were timeless |
| Pin a "latest" tag and treat it as frozen | The tag advances; pin the resolved SHA instead |
| Cite a URL without etag/last-modified or content-hash | No way to detect drift; verification is just hopes |

---

## When verification is impossible

Sometimes the source is genuinely impossible to verify (down, paywalled, deleted). Options:

1. Mark `verified:false` permanently; downgrade any `confirmed` H that depended on it to `deferred`
2. Find an alternative corroborating source (Phase 4 reopen)
3. Add explicit "this claim depended on now-unavailable source" caveat in HANDBACK.md
4. Escalate tier — if the question is T4+ and verification is genuinely impossible, the conclusion may not be defensible

Don't pretend verification happened when it didn't. Per Brenner discipline, hidden uncertainty corrupts all downstream reasoning.
