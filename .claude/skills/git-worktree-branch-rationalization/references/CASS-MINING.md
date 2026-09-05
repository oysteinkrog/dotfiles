# CASS Mining — Learning From Prior Sessions

`cass` (Cross-Agent Session Search) indexes prior agent conversations across Claude Code, Codex, Cursor, Gemini, and ChatGPT. The skill uses it in **Phase 0.5** to surface prior runs of this skill on the same project, prior manual branch/worktree rationalization sessions, past collisions on contested files (informs the harmonization plan), and branch-creation context (informs intent attribution at Phases 5 and 7).

Adapted from [git-stash-janitor's CASS-MINING.md](../../git-stash-janitor/references/CASS-MINING.md). Two extensions vs. stash-janitor:

1. **Per-branch intent reconstruction.** Stashes are anonymous text fragments; branches have author + creation date + commit messages, and prior agent dialogues often record *what the agent was trying to do when the branch was created*. CASS turns this into actionable intent attribution for the harmonization plan.
2. **Per-file collision archaeology.** When ≥2 branches collide on the same file, CASS can surface prior agent dialogues that touched that file — the most direct evidence of competing intents.

---

## 1. When to mine

| Always | When to additionally deepen |
|---|---|
| Phase 0.5 of every Standard / Comprehensive / Council run | Comprehensive: per `divergent-refactor` and `novel-but-stale` branch, mine for the branch's author + creation date to reconstruct intent |
| | Council: also mine for every contested file in the harmonization plan (Phase 7 deepening) |

Quick mode: mine once at Phase 0.5 with a short query rotation; skip per-branch deepening.

> **Why this order:** Per [SKILL.md "Skill Bootstrap (Phase 0.5)"](../SKILL.md#skill-bootstrap-phase-05--right-after-inputs-before-inventory): bootstrap runs "right after inputs, before inventory." That positions cass-mining to inform the rubric BEFORE Phase 5 triage starts, not after.

---

## 2. What to mine for — query rotation

```bash
# Always use --robot or --json; bare `cass` launches a TUI that blocks the agent.
cass health --json   # verify cass is indexed and ready

# Phase 0.5 default rotation (Standard mode):
cass search "$BASENAME" --robot --limit 50 --days 90
cass search "branch rationalization" --robot --limit 20 --days 90
cass search "git worktree" --robot --limit 20 --days 90
cass search "git branch -D" --robot --limit 20 --days 90  # past mass-cleanup attempts (good or bad)
```

Comprehensive / Council adds:

```bash
# Per-branch intent reconstruction (run for each `divergent-refactor` and
# `novel-but-stale` candidate identified in Phase 5):
cass search "<branch-name>" --robot --limit 20 --days 180
cass search "<branch-author>" --robot --limit 20 --days 180   # author from `git log <branch>`

# Per-file collision archaeology (run for each contested file in Phase 7):
cass search "<contested-file-path>" --robot --limit 20 --days 180
cass search "<introduced-symbol-name>" --robot --limit 20 --days 180
```

| Query | Use case |
|---|---|
| `"<basename>"` | Prior agent activity on this exact project (broad sweep) |
| `"branch rationalization"` | Prior runs of this skill (across any project) — finds methodology drift |
| `"git worktree"` | Prior manual worktree-management sessions (often the user fighting with worktrees, leading to this run) |
| `"git branch -D"` | Past mass-cleanup attempts; if any went badly, that's a high-value lesson for the current run |
| `"<branch-name>"` | The original session that created or worked on `<branch>` — the most direct evidence of intent |
| `"<branch-author>"` | When the branch's commit author is an agent (`agent-cc-12`, `agent-cod-3`), find the swarm session that spawned it |
| `"<contested-file-path>"` | Sessions that worked on the contested file — informs harmonization intent attribution |
| `"<introduced-symbol-name>"` | Sessions that introduced or discussed a specific symbol in the file (helps reconstruct *why* this variant added what it added) |

---

## 3. How to mine

```bash
# Each search returns a JSON array of session matches with file paths and line offsets.
cass search "branch rationalization $BASENAME" \
  --robot --limit 10 \
  --days 90 \
  --fields minimal \
  > "$WS/cass_raw_phase05.jsonl"

# Per-match expansion (5 lines of context around each hit):
cass view /path/to/session.jsonl -n 42 --json
cass expand /path/to/session.jsonl -n 42 -C 5 --json
```

The Phase 0.5 cass-miner subagent reads each match's relevant excerpts and classifies them per Section 4. Output is `<workspace>/cass_findings.md`.

> **Why per-match expansion?** The raw search returns lexical hits, many of which are noise (the word "branch" appears in unrelated programming contexts). The expand step gives the cass-miner enough context to classify per Section 4 and discard noise.

---

## 4. Findings categories

The cass-miner subagent classifies each match into one of:

### 4.1 `prior-run-on-this-project`

**What it means:** the skill (or a similar workflow) was run before. May explain current state.

**Action:**
1. Read the prior run's `handoff_report.md` (often committed under `.beads/` or in the bundle dir at `<project-parent>/<basename>-branch-worktree-archive-<earlier-date>/README.md`).
2. Check whether prior keepers were merged or reverted.
3. Check whether `refs/branch-rationalization-backup/*` from the prior run still exists (a sign the bundle wasn't cleaned up — informational only; the skill doesn't touch them).
4. **If prior keepers were *reverted***, surface a high-priority warning to the user. The current run shouldn't re-recover content the user already rejected.

Note in `cass_findings.md`: "this is the second rationalization run on this project; prior run authored 3 keepers, of which 2 merged + 1 reverted (don't re-recover the reverted commit's intent)."

### 4.2 `prior-manual-rationalization-session`

**What it means:** the user previously did a manual cleanup of branches/worktrees on this project (without this skill).

**Action:**
- Read the session for what the user struggled with (likely the branches they couldn't classify, the worktrees that turned out to have unsaved work).
- Augment `project_profile.json:branch_message_prefixes` with conventions the user mentioned.
- The triage rubric inherits any project-specific conventions discovered.

### 4.3 `agent-swarm-aftermath`

**What it means:** a session shows the user explicitly asking an agent swarm to "spawn N agents on this problem in parallel branches/worktrees" — i.e., this run is cleaning up *that* swarm's output.

**Action:**
- The branches matching the swarm's naming convention (e.g., `agent-cc-*`, `agent-cod-*`) are **expected to collide on the same files** — pre-flag them as harmonization candidates in Phase 7.
- The intent of each branch is whatever the user's original swarm prompt said; capture verbatim into `harmonization_plan.md` as "swarm-prompt intent".

### 4.4 `branch-intent-attribution` (per-branch deepening)

**What it means:** a session shows an agent working on `<branch-name>` — the dialogue records *what the agent was trying to do*.

**Action:** for the branch's harmonization-plan row (Phase 7's variant matrix), set `identified intent` based on the cass-mined dialogue rather than from the diff alone. The diff says *what* changed; cass says *why*. Both inputs make the synthesis defensible.

Example:

```
Branch: agent-cc-12-feat-parser
File: src/parse/mod.rs
Diff: + adds null-arg guard at parse() entry
CASS finding (session 2026-04-18): "User asked: 'parser is crashing on
empty input from stdin; can you add a null-check?' — agent attempted
fix in agent-cc-12-feat-parser branch but the project lead asked for
a different approach (return Err instead of guarding) and abandoned
the branch."

Harmonization plan annotation:
  intent = defensive (guard against empty stdin)
  attribution = cass-mined: project lead requested Err-return approach;
    canonical's current approach IS Err-return; this branch's null-arg
    guard is *additionally* useful at the call-site level (defensive
    in-depth) but the project lead's preferred shape lives on canonical.
  proposed synthesis = adopt the null-arg guard at the entry boundary
    AS a defensive layer on TOP of canonical's Err-return; both can
    coexist (compose-additively per HARMONIZATION.md § 3 defensive).
```

> **Why this matters:** Per [HARMONIZATION.md § 1](HARMONIZATION.md): "the job is NOT to choose between competing variants. The job is to ... reason about each part's intent." Without intent attribution, "reason about intent" becomes "guess at intent." CASS turns guesses into evidence.

### 4.5 `per-file-collision-archaeology` (per-contested-file deepening)

**What it means:** a session shows multiple agents working on the same file at the same time — direct evidence of the swarm's collision shape.

**Action:** for the contested file's harmonization-plan variant matrix (Phase 7), add a "prior-session context" row at the top citing the swarm session. The synthesis can then say: "Per swarm session 2026-04-18, four agents were each tasked with hardening `src/util/logger.rs` — agent-cc-3 added null-arg guard, agent-cod-2 added length cap, etc. Each had a distinct intent; the synthesis layers all four."

### 4.6 `convention-discovery`

**What it means:** a session shows the user's preferred branch-name conventions or project-specific garbage labels.

**Action:** augment `project_profile.json:branch_message_prefixes` and `protected_by_convention_patterns`. Improves auto-classification on the current run AND future runs (cass picks up this run's session for next time).

### 4.7 `domain-knowledge`

**What it means:** a session contains domain context (architecture decisions, business rules) that informs the harmonization plan.

**Action:** feed to the harmonization-planner subagent for richer "proposed synthesis" prose in the variant matrix.

### 4.8 `irrelevant`

**What it means:** the match was lexical, not semantic.

**Action:** ignore. Don't accumulate noise in `cass_findings.md`.

---

## 5. Privacy and scope

- `cass` indexes the user's own session history (per-machine). It does not exfiltrate to any external service.
- Findings stay in the workspace; they're not pushed.
- If the user has set up `cass` to exclude sensitive sessions, those exclusions are respected.
- The cass-miner subagent never copies session content verbatim into the bundle's persistent artifacts (which the user might share via `tar`); it only summarizes findings into `cass_findings.md` (which lives in the transient `.worktree_branch_rationalization_workspace/`).

---

## 6. Output: `cass_findings.md`

The cass-miner subagent writes `<workspace>/cass_findings.md` with:

```markdown
# CASS findings — Phase 0.5

Mined: 2026-05-07T14:32:00Z
Queries: ["asupersync", "branch rationalization", "git worktree", "git branch -D"]
Days back: 90
Sessions inspected: 47 (32 hit; 15 expanded)

## Summary

- 1 prior rationalization run on this project (2026-04-12, 3 keepers; 2 merged, 1 reverted)
- 1 agent-swarm-aftermath: user spawned 12 agents on parser hardening on 2026-04-18
- 4 branch-intent-attribution findings (agent-cc-12, agent-cc-13, agent-cod-2, agent-cod-7)
- 2 per-file collision archaeology hits (src/parse/mod.rs, src/util/logger.rs)
- 1 convention discovery (`agent-cc-*` family is the cc swarm's output; `agent-cod-*` is the codex swarm's)
- 0 reverted-keeper warnings beyond the 1 above
- 12 irrelevant matches (skipped)

## Findings (8)

### F1: prior-run-on-this-project (high relevance)

Source session: ~/.claude/projects/asupersync/sessions/2026-04-12.jsonl
Date: 2026-04-12

The skill ran on this project once before. Recovered 3 keepers:
- agent-cc-7-feat-parse-stdin → MERGED via PR #1234
- agent-cod-1-mysql-fix → MERGED via PR #1235
- agent-cc-9-feat-redact-secrets → REVERTED (PR #1236 → revert PR #1240)

The reverted commit's intent was "redact API keys in log output". The user
explicitly rejected the redaction-via-regex approach in PR #1240 review.

ACTION: when the current run encounters branches whose intent is "redact
secrets in log output via regex", DOWNGRADE confidence to <0.5 and surface
to user for explicit decision; do not auto-recover.

### F2: agent-swarm-aftermath (high relevance)

Source session: ~/.claude/projects/asupersync/sessions/2026-04-18.jsonl
Date: 2026-04-18

User prompt verbatim: "spawn 12 agents on parser hardening; each gets one
of the 12 known crash inputs; create a branch agent-cc-N-feat-parse-<crash-id>
each. Don't merge; I'll triage later."

The 12 branches `agent-cc-1-feat-parse-*` through `agent-cc-12-feat-parse-*`
are the result. The user EXPECTED to triage them (which is the current run).
Each branch has a distinct intent (one crash input each); they SHOULD all
compose-additively in the harmonization plan.

ACTION: pre-classify all 12 as harmonization candidates for `src/parse/mod.rs`;
each contributes one defensive guard; the synthesis composes all 12.

### F3: branch-intent-attribution (medium relevance)

Source session: ~/.claude/projects/asupersync/sessions/2026-04-23.jsonl
Branch: agent-cod-2-mysql-deadlock-fix
Diff: + serialize transaction order via mutex around prepare()

Session shows: agent-cod-2 was investigating a deadlock observed in prod;
proposed mutex around prepare() as a defensive measure; project lead asked
for a benchmark before merging; benchmark not run; branch abandoned.

ACTION: harmonization plan should NOT auto-include this; the intent is
"defensive" but unverified-perf (per HARMONIZATION.md § 3 performance:
"pick the one with measured benchmarks"). Surface to user.

### F8: irrelevant
... (discard count: 12)
```

This file feeds:

| Phase | How |
|---|---|
| Phase 1 | `project_profile.json` is augmented with discovered conventions (Section 4.6) |
| Phase 5 | The triage worker reads `cass_findings.md` for branch-intent attribution; verdicts are evidence-cited from cass dialogues, not just diffs |
| Phase 7 | The harmonization-planner subagent reads `cass_findings.md` for per-file collision archaeology and intent attribution |
| Phase 11 | The handoff report includes a "Prior-run context" section noting findings like F1 ("this is the second run; prior run authored 3 keepers"); F2 ("12-agent swarm aftermath; harmonized into 1 keeper"); F3 ("agent-cod-2 abandoned without benchmark; user-skipped per cass evidence") |

---

## 7. CASS unavailable

If `cass` isn't installed, isn't indexed, or returns errors:
- Log `cass_skipped: true; reason: <reason>` in the workspace's `integration.log`
- Continue without Phase 0.5 cass mining
- Record `cass_skipped: true` in the handoff report

The skill is fully functional without CASS — mining is **enrichment, not requirement**. Per [SKILL.md "Up-Front Confirmations"](../SKILL.md#up-front-confirmations-ask-before-starting): "Don't block a phase if a polish skill is missing — note it and proceed with the inline fallback."

> **Why a graceful skip rather than a refusal?** The skill's safety story (the bundle, byte-equality, verbatim authorization) is unaffected by missing cass. Cass enriches the *narrative* (intent attribution, prior-run context) but does not change the *correctness* of recovery. The bundle is the source of truth for "is this reversible"; cass is the source of truth for "what was the intent."

---

## 8. Anti-Patterns in CASS Mining

| Why |
|---|
| Running bare `cass` (launches TUI) | Blocks the agent session — always use `--robot` or `--json` |
| Mining without `--days N` filter | Returns years of history; usually noise |
| Trusting findings without re-verification | Sessions can be stale; verify against current branch state via `git log <branch>` |
| Acting on `irrelevant` findings | Keyword matches in unrelated contexts |
| Skipping the cass-skipped log entry | Future runs lose the audit trail (and the cass-miner subagent for the *next* run won't know whether prior runs had cass available) |
| Quoting cass-mined session content verbatim into commit messages | Violates the user's privacy expectation; summarize instead |
| Letting cass findings override the diff evidence | Cass is *additive* evidence — when cass and diff disagree (e.g., cass says "abandoned" but diff is non-trivial), surface to user, don't auto-resolve |
