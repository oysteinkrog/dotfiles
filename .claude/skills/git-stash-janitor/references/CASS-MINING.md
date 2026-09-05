# CASS Mining — Learning From Prior Sessions

`cass` (Cross-Agent Session Search) indexes prior agent conversations across Claude Code, Codex, Cursor, Gemini, ChatGPT. The skill uses it in Phase 0.5 to surface prior runs of this skill, related stash-archaeology sessions, or relevant incidents on the same project.

Adapted from saas-billing's CASS-MINING.md.

---

## When to mine

- **Always for Comprehensive runs.** A 200-stash repo has likely been touched by prior agents whose sessions contain useful context (e.g., "user previously rolled back a recovered keeper because it broke staging").
- **Before high-stakes phases.** Before Phase 6 commits to the recovery branch in production-critical code, mine for "stash-recovery" + project name to see if any prior runs went wrong.
- **When confidence is low.** If Phase 4 has >15% confidence-below-0.75, mining sometimes surfaces project-specific message conventions the rubric is missing.

---

## What to mine for

| Query | Use case |
|-------|----------|
| `"stash janitor" project:<basename>` | Prior runs of this skill on this exact project |
| `"git stash" <basename>` | Any prior agent session that worked with stashes here |
| `"<beads-id>"` | Sessions that referenced a particular beads issue (often indicates the stash's origin) |
| `"<unique-fingerprint-symbol>"` | Sessions that introduced or discussed a specific symbol (helps reconstruct intent) |
| `"<error-message-from-stash>"` | Sessions that debugged the underlying issue (often the stash is a half-fix attempt) |

---

## How to mine

```bash
# Always use --robot or --json; bare `cass` launches a TUI that blocks the agent.
cass health --json   # verify cass is indexed and ready

cass search "stash janitor ${BASENAME}" \
  --robot --limit 10 \
  --days 90 \
  --fields minimal

cass search "git stash" \
  --robot --limit 20 \
  --project "$PROJECT_ABS"
```

Output is a JSON array of session matches with file paths and line offsets. The Phase 0.5 cass-miner subagent reads each match's relevant excerpts via:

```bash
cass view /path/to/session.jsonl -n 42 --json
cass expand /path/to/session.jsonl -n 42 -C 5 --json   # 5 lines of context around the match
```

---

## Findings categories

The cass-miner subagent classifies findings into:

### `prior-run-on-this-project`

**What it means:** the skill (or a similar workflow) was run before. May explain current state.

**Action:** read the prior run's `handoff_report.md` (often committed under `.beads/` or referenced in beads issues). Check:
- Did the prior run authoring keepers? Were they merged or reverted?
- Are any backup refs from the prior run still in `.git/refs/stash-backup/`?
- Did the prior run identify message conventions that should auto-classify garbage?

If prior keepers were *reverted*, surface a warning to the user. The current run shouldn't re-recover content the user already rejected.

### `related-incident`

**What it means:** a session referenced an incident or bug whose fix is in one of the current stashes.

**Action:** that fingerprint's verdict gets a confidence boost; the commit message can cite the incident.

### `convention-discovery`

**What it means:** a session shows the user's preferred stash-message conventions or project-specific garbage labels.

**Action:** augment `project_profile.json:stash_message_prefixes` with the discovered patterns. This improves auto-classification on the current run.

### `domain-knowledge`

**What it means:** a session contains domain context (architecture decisions, business rules) that informs intent reconstruction.

**Action:** feed to Phase 6 commit-message-author for richer commit prose.

### `irrelevant`

**What it means:** the match was lexical, not semantic.

**Action:** ignore. Don't accumulate noise.

---

## Privacy and scope

- `cass` indexes the user's own session history (per-machine). It does not exfiltrate to any external service.
- Findings stay in the workspace; they're not pushed.
- If the user has set up `cass` to exclude sensitive sessions, those exclusions are respected.

---

## Output: `cass_findings.md`

The cass-miner subagent writes `<workspace>/cass_findings.md` with:

```markdown
# CASS findings — Phase 0.5

Mined: 2026-05-06T14:32:00Z
Queries: ["stash janitor asupersync", "git stash asupersync", "BACK-1742"]

## Findings (3)

### F1: prior-run-on-this-project (high relevance)

Source session: ~/.claude/projects/asupersync/sessions/2026-04-12.jsonl
Date: 2026-04-12

The skill was run on this project once before, on 2026-04-12. Recovered 2 keepers
(stashes 8 and 23 of that run's inventory). Both were merged via PR #234.
Current run's inventory may include stashes that postdate that run (likely
agents stash-after-the-skill ran).

Action: ignore the merged keepers' content when verifying-on-main; they're
already merged. Treat as expected supersession.

### F2: convention-discovery (medium relevance)

Source: ~/.codex/projects/asupersync/sessions/2026-03-28.jsonl

User mentioned: "stashes prefixed `wip-BACK-1742` were experimental concurrent
agent attempts; the canonical landing is the version with the most recent date
that has a corresponding closed beads issue."

Action: augment project_profile with this convention. The triage worker should
treat all but the latest dated `wip-BACK-1742-*` as `superseded-by-newer-stash`.

### F3: irrelevant

Source: ~/.gemini/sessions/2026-04-30.jsonl
Match was on the word "stash" in a discussion about kitchen pantries. Skipping.

---

## Skill-state summary

- 1 prior stash-janitor run on this project (2026-04-12, 2 keepers merged)
- 0 prior runs that authored reverted keepers
- 0 incidents in the last 90 days that map to current-run fingerprints
- 1 convention discovered (wip-BACK-1742 family handling)
```

This file feeds Phase 4 (the convention discovery) and Phase 5 (the prior-run context for the user gate).

---

## CASS unavailable

If `cass` isn't installed, isn't indexed, or returns errors:
- Log `cass_skipped: true; reason: <reason>` in the workspace
- Continue without Phase 0.5
- Don't block the run

The skill is fully functional without CASS — mining is enrichment, not requirement.

---

## Anti-Patterns in CASS Mining

| ✗ | Why |
|---|-----|
| Running bare `cass` (launches TUI) | Blocks the agent session |
| Mining without `--days N` filter | Returns years of history; usually noise |
| Trusting findings without re-verification | Sessions can be stale; verify against current repo state |
| Acting on `irrelevant` findings | Keyword matches in unrelated contexts |
| Skipping the cass-skipped log entry | Future runs lose the audit trail |
