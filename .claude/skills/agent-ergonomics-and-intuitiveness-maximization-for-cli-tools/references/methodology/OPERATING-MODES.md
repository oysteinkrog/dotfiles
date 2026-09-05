# Operating Modes

Five modes; same phase loop, different stop conditions and artifact requirements.

> **Path convention.** Every `audit/...` path below is shorthand for `<SIBLING>/audit/...`. **`<SIBLING>` now resolves to `<TARGET>/agent_ergonomics_audit/`** — a folder INSIDE the target repo, not a sibling directory next to it. The variable name is legacy; the location is in-tree, committed to the same branch as the code (typically `main`). See `IO-CONTRACTS.md § Path convention` for the full rule.

## `mini`

**Use when.** Skeptical first-time user; smallest commitment that produces a scorecard + heatmap. Useful as a 5-minute "is this worth it?" check before committing to `audit-only` or `full`.

**Phases run.** 0, 1, 2 only. No intent corpus, no recommendations, no apply, no simulation, no handoff.

**Required artifacts.**
- `audit/manifest.json`, `audit/phase0_*`
- `audit/surface_inventory.jsonl`
- `audit/agent_surfaces.jsonl`
- `audit/scorecard_pass_<N>.md`
- `audit/heatmap.svg`

**Forbidden.** Anything Phase 3+. The point is "show me what you'd score; don't spend tokens generating recs I might not act on."

**Stop condition.** Phase 2 aggregator emits the final row(s); render_scorecard + render_heatmap finish; print "mini pass complete: N surfaces scored. Run with mode=audit-only to add recommendations, or mode=full to apply."

**Wall-time budget.** ~5–15 min on a small CLI (≤ 100 surfaces); much longer on a 1000-surface tool — use `scripts/estimate.sh --mode mini` to project.

---

## `audit-only`

**Use when.** User wants a scorecard + recommendations only. No code changes. Often a triage step before committing to a full pass.

**Phases run.** 0, 1, 2, 3, 4 (synthesis only — no triangulation required).

**Required artifacts.**
- `audit/manifest.json`, `audit/phase0_*`
- `audit/surface_inventory.jsonl`
- `audit/agent_surfaces.jsonl`
- `audit/scorecard.md`
- `audit/heatmap.svg`
- `audit/intent_inference_corpus.jsonl`
- `audit/recommendations.jsonl` (with `applied:false` for all)
- `audit/playbook.md`
- `audit/agent_simulations/pre_pass_<N>/` baseline transcripts

**Forbidden.** Source-code changes (anything outside `<target>/agent_ergonomics_audit/`). Feature branch creation. Switching off the current branch. (The audit workspace IS inside `<target>/`, so `audit-only` writes there and `git add agent_ergonomics_audit/` on the current branch — that's expected and not a violation. What's forbidden is touching `src/`, `cmd/`, `lib/`, etc.)

**Stop condition.** Phase 4 completes; HANDOFF.md is brief: "audit-only pass; no remediation. Top-N recs ranked. Run with mode=full to apply."

---

## `full`

**Use when.** User wants the gaps fixed with measurable uplift. **The default mode** for any "apply / improve / harden / make agent-friendly" intent. Only fall back to `audit-only` when the user explicitly asked for a review/score/report.

**Phases run.** All 10, plus the Ambition Bar self-prompt round before Phase 10.

**Branch policy.** All applied commits land on the target's **currently checked-out branch** (typically `main`). This mode never creates a new branch and never asks about one — see the SKILL.md "Branch Policy" section.

**Required artifacts.** Everything in `audit-only` plus:
- `audit/applied_changes.jsonl`
- `audit/regression_tests/` populated, all green
- `audit/scorecard_pass_<N+1>.md`
- `audit/uplift_diff.md`
- `audit/regression_alerts.md` (may be empty — that's fine)
- `audit/agent_simulations/post_pass_<N>/`
- `audit/HANDOFF.md`
- Applied commits on the **current branch of the target** (no new branch)
- `recommendations.jsonl` `applied:true` for every applied rec
- `audit/ambition_bar_check.md` — record of the self-prompt outcome (number of substantive commits, dimensions touched, items deferred)

**Stop condition.** All of:
- Two consecutive Phase 7 fresh-eyes rounds clean.
- Phase 6 uplift threshold met (median ≥ 25 pts; no surface regressed > 50 pts).
- Phase 9 simulations show net improvement.
- Ambition Bar self-prompt round was run; either the soft target is met or the HANDOFF.md explicitly lists deferred items with rationale.

Phase 10 lands the plane.

---

## `re-score-only`

**Use when.** Resumed run; user changed surfaces in the target since the last pass and wants the new score with no other work.

**Phases run.** 0 (verify SHA changed), 2 (re-run scoring against current HEAD), 6 (compute uplift vs prior pass).

**Required artifacts.**
- New `audit/agent_surfaces.jsonl` overwriting prior (preserving prior at `agent_surfaces_pass_<N-1>.jsonl`)
- `audit/scorecard_pass_<N+1>.md`
- `audit/uplift_diff.md`
- `audit/regression_alerts.md`

**Forbidden.** New recommendations (Phase 4 not run). Code changes (Phase 5 not run). Fresh-eyes (Phase 7 not run). New simulations (Phase 9 not run).

**Stop condition.** Re-score complete; uplift_diff.md committed. If a regression > 50 pts is detected, switch to a single-surface `full` pass focused on that surface (use `full` mode with the surface_id passed via `--focus <SID>` to phase scripts where supported, otherwise constrain Phase 4 recommender input to that one surface). The skill no longer defines a separate `harden-regression` mode — the workflow is the same as `full`, just narrowed to one surface.

---

## `simulate-only`

**Use when.** Validation run; user wants a fresh-eyes agent to attempt canonical tasks against the current binary, e.g. "did Pass 3 actually fix the thing I cared about?"

**Phases run.** 0, 9.

**Required artifacts.**
- `audit/agent_simulations/post_pass_<N>/` with all canonical-task transcripts
- `audit/agent_simulations/post_pass_<N>/summary.md`

**Forbidden.** Anything except simulation. No scoring, no recommendations, no code changes.

**Stop condition.** All canonical tasks attempted; summary.md written.

---

## `single-surface-rescore`

**Use when.** User changed one surface (e.g. "I just added `--json` to `<tool> list`") and wants to know the new score for that one surface only.

**Phases run.** 0 (validate `surface_id` exists), 2 (single surface), 6 (compute single-surface uplift).

**Required artifacts.**
- One row appended to `<SIBLING>/audit/agent_surfaces_pass_<N+1>.jsonl` for the named `surface_id`
- One row in `audit/uplift_diff.md` for the surface

**Forbidden.** Touching any other surface. Triangulation (overkill for single surface).

**Stop condition.** Single surface re-scored; uplift recorded.

---

## Auto-detect heuristics

> **Intent wins over state.** If the user's prompt expresses an "apply / improve / harden / make it agent-friendly" intent, the default is `full` regardless of workspace state. The signals below are tiebreakers only when the prompt is silent on intent. See SKILL.md § "Mode-default heuristic."

`scripts/discover-cli.sh` runs and produces signals; the main agent picks a default mode + presents reasoning to the user:

| Signal (when prompt intent is silent) | Suggested mode |
|--------|----------------|
| User explicitly asked for a "review", "audit", "scorecard", "report", or "score" | `audit-only` |
| User asks about a single named flag/subcommand | `single-surface-rescore` |
| User asks "did the changes work?" / "what changed?" | `simulate-only` (if prior pass exists) or `re-score-only` |
| `audit/manifest.json` exists with `pass_N+1_ready: false` | `re-score-only` (didn't end cleanly; check status first) |
| Target HEAD ≠ manifest's `target_sha` AND prior pass complete | `re-score-only` first (compute uplift; then `full` Pass N+1 if regressions or new gaps) |
| `audit/manifest.json` exists with `pass_N+1_ready: true` | `full` (resuming pass N+1) |
| No `audit/manifest.json` exists AND prompt asks for improvements | **`full`** (the default — start scoring + apply on the same pass) |
| No `audit/manifest.json` exists AND prompt is genuinely ambiguous | `full` (be active by default; the user can downshift to `audit-only` once they see what's happening) |
| Target HEAD == manifest's `target_sha` AND user asks again | propose `audit-only` to refresh recs without redoing work |

The user can always override at intake.

---

## Mode crosswalk: which artifacts end up where

| Artifact | audit-only | full | re-score-only | simulate-only | single-surface-rescore |
|----------|------------|------|---------------|---------------|------------------------|
| `manifest.json` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `surface_inventory.jsonl` | ✓ | ✓ | – (reuse) | – | – (reuse, unless surface is new) |
| `agent_surfaces.jsonl` | ✓ | ✓ | ✓ | – | ✓ (single line) |
| `intent_inference_corpus.jsonl` | ✓ | ✓ | – | – | – |
| `recommendations.jsonl` | ✓ (applied:false) | ✓ (applied:true for top-N) | – | – | – |
| `playbook.md` | ✓ | ✓ | – | – | – |
| `applied_changes.jsonl` | – | ✓ | – | – | – |
| `regression_tests/` | – | ✓ | – | – | – |
| `scorecard.md` | ✓ | ✓ | ✓ | – | ✓ |
| `heatmap.svg` | ✓ | ✓ | ✓ | – | – |
| `uplift_diff.md` | – | ✓ | ✓ | – | ✓ |
| `regression_alerts.md` | – | ✓ | ✓ | – | ✓ |
| `agent_simulations/pre_pass_N/` | ✓ | ✓ | – | – | – |
| `agent_simulations/post_pass_N/` | – | ✓ | – | ✓ | – |
| `ambition_bar_check.md` | – | ✓ | – | – | – |
| `HANDOFF.md` | brief | full | brief | brief | brief |
| Commits on target's current branch | – | ✓ | – | – | ✓ (single commit) |

---

## Mode-specific kickoff prompts

See `KICKOFF-PROMPTS.md` for the verbatim text to send the user once mode is chosen.
