# Unblocked Work — What the Recovered Commits Free Up

A successful rationalization run lands N keeper commits on the rationalization branch. Each one closes work, unblocks downstream work, exposes new opportunities, or invalidates prior assumptions. Phase 11's job isn't just "tell the user what landed" — it's "tell the user what the recovered work means for everything else they're tracking."

This file is the per-run discovery layer adapted from [/idea-wizard](../../idea-wizard/SKILL.md) and [/beads-bv](../../beads-bv/SKILL.md). The cognitive move is: **the rationalization branch is the diff that everything else should be re-evaluated against.**

> **Why this matters.** A user who runs branch-rationalization on a project with 200 branches typically also has 50+ open beads issues, 5–10 open PRs, and several stalled investigations. Some of those are now *moot* (the recovered work closes them); some are now *actionable* (a blocker just got unblocked); some are *new opportunities* (the recovered code surfaces a pattern that suggests a follow-up). The Phase 11 handoff that doesn't surface these forces the user to discover them later, by accident.

---

## 1. The premise

Every recovered commit is a state change. Treat it as one:

| Recovered commit shape | What it changes |
|---|---|
| Single-source recovery (`recover X from branch Y`) | Adds X to canonical's surface |
| Harmonized synthesis | Adds the synthesis (NEW work) + closes intent that lived only on the source branches |
| Split-apply (Phase 8b) | Adds the novel subset; the rest was redundant |
| Dirty-worktree-only | Adds dormant work that never made it onto a branch |
| Conflict-resolved | Adds work + records the architectural reconciliation in the commit message |

For each, the unblocked-work discovery loop asks four questions:

1. **What was waiting on this?** (newly-actionable)
2. **What is now broken because of this?** (newly-blocked — should be rare but happens)
3. **What new beads should be filed because of this?** (suggested-new)
4. **What can be closed because of this?** (ready-to-close)

The answers feed `unblocked_work.md`, which is appended to `handoff_report.md` at Phase 11.

---

## 2. Per-keeper unblock detection

For each keeper-commit on the rationalization branch, run `bv` against the diff. This is **/bv robot mode**, not the interactive TUI (per AGENTS.md "CRITICAL: Use ONLY `--robot-*` flags").

### 2.1 Newly-actionable beads

```bash
RAT_BRANCH="branch-rationalization-$DATE"
PRE_TIP=$(git rev-parse "$RAT_BRANCH"~$(git rev-list --count "$CANONICAL..$RAT_BRANCH"))   # canonical's tip when run started

# Beads that became unblocked since pre-tip:
bv --robot-triage --diff-since "$PRE_TIP" --json > "$WS/post_run_bv_triage.json"

# Filter to "newly actionable" — items whose blockers became done in the diff:
jq '.recommendations[] | select(.unblock_info.unblocks_were_blocking_count > 0)' "$WS/post_run_bv_triage.json" \
    > "$WS/unblocked/newly_actionable.json"
```

Format the output as a table for the handoff:

```markdown
| Bead ID | Title | Was blocked by | Now unblocked because |
|---|---|---|---|
| beads-1234 | Add length-cap test for parser_v2 | wip-BACK-1742 (now landed as commit aa11bb22) | recovery includes the parser_v2 length-cap |
| beads-1567 | Wire redact_secrets into LogEvent::Trace | feature/redact-secrets (now landed) | harmonized synthesis includes the LogEvent::Trace arm |
```

### 2.2 Newly-blocked beads

Rare but possible: a recovered commit may invalidate prior work or expose a regression. `bv --robot-alerts` surfaces this:

```bash
bv --robot-alerts --diff-since "$PRE_TIP" --json > "$WS/unblocked/alerts.json"
jq '.alerts[] | select(.alert_type == "blocking_cascade" or .alert_type == "newly_blocked")' \
    "$WS/unblocked/alerts.json" > "$WS/unblocked/newly_blocked.json"
```

If `newly_blocked` is non-empty, the handoff escalates: "the recovered commit X may have broken assumption Y of beads-Z; user should review."

### 2.3 PR-state shift detection

```bash
# Per open PR (from github_state.json captured at Phase 0.5):
for pr in $(jq -r '.open_prs[].number' "$WS/github_state.json"); do
  pr_base=$(jq -r --arg n "$pr" '.open_prs[] | select(.number == ($n|tonumber)) | .base_ref' "$WS/github_state.json")

  # Was the PR mergeable before the run?
  pre_mergeable=$(jq -r --arg n "$pr" '.open_prs[] | select(.number == ($n|tonumber)) | .mergeable' "$WS/github_state.json")

  # Is it mergeable now?
  current_mergeable=$(gh pr view "$pr" --json mergeable -q '.mergeable')

  if [ "$pre_mergeable" = "CONFLICTING" ] && [ "$current_mergeable" = "MERGEABLE" ]; then
    echo "$pr now mergeable — recovered work resolved the conflict" >> "$WS/unblocked/pr_shifts.tsv"
  fi
done
```

The skill **never auto-merges PRs**; it only surfaces the shift. The user merges at their own pace. Cross-link to AGENTS.md "Irreversible Git Actions" — `gh pr merge` is a remote mutation, out of scope per Axiom 15.

---

## 3. Idea generation — per /idea-wizard

The recovered commits' fingerprints suggest follow-ups. Per [/idea-wizard](../../idea-wizard/SKILL.md), this is "what should we build next, given what we just built?"

### 3.1 Pattern-matching recovered commits to idea seeds

For each keeper-commit, the idea-wizard subagent looks for known patterns:

| Recovered pattern | Suggested idea |
|---|---|
| Recovered a "log redaction" hunk | "Audit ALL log call sites for redaction coverage" — file as beads issue |
| Recovered a "defensive guard" hunk | "Audit related call sites for similar guards" |
| Recovered a "type-narrowing" hunk | "Apply the same narrowing pattern to sibling types in the same module" |
| Recovered a test for an edge case | "Add a fuzz target covering this edge case class" — cross-link to /testing-fuzzing |
| Recovered a config option | "Document the option in README + add to default config schema" |
| Recovered a perf-improvement hunk | "Add a benchmark guarding against regression" — cross-link to /profiling-software-performance |
| Harmonized synthesis citing 3+ sources | "Document the harmonized API in the architecture docs to prevent future divergence" |

The seed-table lives in `assets/idea-wizard-patterns.tsv`. The Phase 11 idea-wizard subagent matches each keeper against the patterns and emits suggested-new beads with priority:

```markdown
## Suggested New Beads (per /idea-wizard pattern matching)

| Priority | Title | Reason | Source commit |
|---|---|---|---|
| P2 | Audit all log call sites for redaction coverage | Recovered log-redaction implies a wider audit; aa11bb22 added redact_secrets() to LogEvent::Trace but other LogEvent variants were not touched | aa11bb22 |
| P3 | Add fuzz target for OK-packet length-cap edge case | Recovered defensive guard; fuzzing protects against regressions and finds adjacent vulnerabilities | bb22cc33 |
| P4 | Document harmonized logger API in architecture docs | Synthesis cited 3 source branches; preventing future divergence requires explicit docs | cc33dd44 |
```

The user reviews the table; per /idea-wizard, the user either accepts (skill files via `br create`) or skips (skill records the suggestion but doesn't file).

### 3.2 Deeper /idea-wizard integration

If `/idea-wizard` is available as a skill (probed at Phase 0.5 by `check-skills.sh`), the audit invokes it directly:

```bash
if grep -q '"idea-wizard"' "$WS/phase0_skill_inventory.json"; then
    # Run /idea-wizard against the rationalization branch's diff vs canonical:
    /idea-wizard --target-diff "$CANONICAL..$RAT_BRANCH" \
                 --output "$WS/unblocked/idea_wizard_output.md" \
                 --priority-floor P3 \
                 --max-ideas 10
fi
```

The output is a markdown file with 5–10 follow-up ideas with priority + rationale. The handoff appends this section to `unblocked_work.md`.

---

## 4. Reverse-impact detection — what the recovery closes

Some open beads were filed because the user wanted X, and X just got recovered. Close them.

```bash
# For each open bead, check whether its description's keywords appear in the rationalization-branch diff:
bv --robot-list --status open --json > "$WS/unblocked/open_beads.json"

for bead in $(jq -c '.beads[]' "$WS/unblocked/open_beads.json"); do
  bead_id=$(echo "$bead" | jq -r '.id')
  bead_keywords=$(echo "$bead" | jq -r '.title + " " + .description' | tr -s '[:punct:][:space:]' '\n' | sort -u | grep -E '^[a-zA-Z]{4,}$')

  # Quantify keyword overlap with the rationalization-branch diff:
  diff_text=$(git diff "$CANONICAL..$RAT_BRANCH")
  overlap_count=0
  for kw in $bead_keywords; do
    echo "$diff_text" | grep -qi "$kw" && overlap_count=$((overlap_count + 1))
  done
  total_keywords=$(echo "$bead_keywords" | wc -l)
  overlap_ratio=$(echo "scale=2; $overlap_count / $total_keywords" | bc)

  # Threshold: ≥0.6 overlap suggests the bead's described work is in the diff
  if (( $(echo "$overlap_ratio >= 0.6" | bc -l) )); then
    echo -e "$bead_id\t$overlap_ratio\thigh" >> "$WS/unblocked/closeable_candidates.tsv"
  fi
done
```

The handoff renders these as candidates the user reviews:

```markdown
## Beads Candidates for Closure (recovered work appears to satisfy them)

| Bead ID | Title | Overlap | Recovered commits |
|---|---|---|---|
| beads-789 | Implement OK-packet length capping | 0.83 | aa11bb22, bb22cc33 |
| beads-1042 | Add log redaction for trace events | 0.78 | aa11bb22 (LogEvent::Trace arm of harmonized synthesis) |

For each, the user can:
  br close beads-789 --reason "closed by branch-rationalization run; recovered as aa11bb22 + bb22cc33"

  OR skip (keep open) if the bead intended different scope.
```

The skill **never auto-closes beads**; it surfaces candidates. Per AGENTS.md "Beads Workflow Integration", the user closes via `br close` themselves.

> **Why surface but not auto-close?** A bead's description might use the same keywords but mean something subtly different. Auto-closing would silently lose context. Per [/beads-bv](../../beads-bv/SKILL.md) and AGENTS.md "Beads Workflow Integration", status changes are user decisions.

---

## 5. Output: `unblocked_work.md`

The unblocked-work discovery emits a single markdown file that's appended to `handoff_report.md` at Phase 11.

```markdown
# Unblocked Work — branch-rationalization-2026-05-07

Generated: 2026-05-07T16:08:32Z
Rationalization branch tip: aa11bb22 (23 keepers landed)

## 1. Newly Actionable

| Bead ID | Title | Was blocked by | Now unblocked because |
|---|---|---|---|
| beads-1234 | Add length-cap test for parser_v2 | wip-BACK-1742 | recovery includes the length-cap (commit aa11bb22) |
| beads-1567 | Wire redact_secrets into LogEvent::Trace | feature/redact-secrets | harmonized synthesis covers it (commit cc33dd44) |

→ Run `bv --robot-next` to claim the highest-priority newly-actionable bead.

## 2. Newly Blocked (review carefully)

| Bead ID | Title | Was actionable until | Why now blocked |
|---|---|---|---|
| beads-2010 | Refactor LogEvent::Trace API | now | harmonized synthesis recovered the existing API; refactor would break callers |

→ User decides: re-prioritize, close as obsolete, or proceed with a wider refactor.

## 3. Beads Candidates for Closure

| Bead ID | Title | Overlap | Recovered commits | Suggested close reason |
|---|---|---|---|---|
| beads-789 | Implement OK-packet length capping | 0.83 | aa11bb22, bb22cc33 | "closed by branch-rationalization run; recovered as aa11bb22 + bb22cc33" |

→ For each, run: `br close <id> --reason "<reason>"`.

## 4. Suggested New Beads (per /idea-wizard pattern matching)

| Priority | Title | Reason | Source commit |
|---|---|---|---|
| P2 | Audit all log call sites for redaction coverage | Recovered log-redaction implies a wider audit | aa11bb22 |
| P3 | Add fuzz target for OK-packet length-cap edge case | Recovered defensive guard; fuzzing protects against regressions | bb22cc33 |
| P4 | Document harmonized logger API in architecture docs | Synthesis cited 3 source branches; explicit docs prevent future divergence | cc33dd44 |

→ For each, run: `br create --title "..." --type=task --priority=P<N>`.

## 5. PR Shifts

| PR | Title | Pre-run | Now | Reason |
|---|---|---|---|---|
| #234 | Length-cap parser hardening | CONFLICTING | MERGEABLE | recovered work resolved the conflict on src/parser.rs |

→ User reviews PR #234; if accurate, mark it for merge.

## 6. /idea-wizard Output (full)

[appended verbatim from idea_wizard_output.md if /idea-wizard was invoked]
```

---

## 6. Optional /bv full report

If the user wants a deeper post-run analysis, the skill optionally runs `/bv --robot-insights` and `/bv --robot-plan` against the post-rationalization state:

```bash
bv --robot-insights --diff-since "$PRE_TIP" --json > "$WS/post_run_bv_insights.json"
bv --robot-plan --diff-since "$PRE_TIP" --json > "$WS/post_run_bv_plan.json"
```

These richer JSON outputs are kept in the workspace for the user's later perusal but not rendered in `unblocked_work.md` (too verbose). The handoff has a single line: "Full bv post-run analysis at `<workspace>/post_run_bv_*.json`."

> **Why optional?** Per AGENTS.md "bv — Graph-Aware Triage Engine": "bv handles *what to work on* (triage, priority, planning)." For some users, the post-run triage is the entire point of running the skill (it lets them re-plan their next sprint). For others, they just want the cleanup done. The skill provides the data; the user opts in to using it.

---

## 7. When unblocked-work discovery is skipped

| Condition | Skip behavior |
|---|---|
| `bv` not installed | Skip Sections 1, 2, 4; record `bv_skipped: true` in handoff |
| `gh` not authenticated | Skip Section 5 (PR shifts); record `pr_shifts_skipped: true` |
| `/idea-wizard` skill not present | Skip Section 4's "/idea-wizard Output (full)" sub-section; the pattern-matching from § 3.1 still runs (it's local) |
| `--triage-only` mode | Skip the entire file (no rationalization branch to analyze) |
| `--dry-run` mode | Skip the unblocked-work discovery; the dry-run report has its own summary callouts |
| Beads database unwritable | Skip Sections 1, 2, 3 (which depend on `br` queries); idea-wizard pattern matching still runs |

The handoff `unblocked_work.md` always has the section headings; sub-sections that were skipped have a single-line note explaining why ("Section 5 skipped because gh is not authenticated; re-run with `gh auth login` to populate").

---

## 8. Cumulative discovery — across multiple runs

If the project has had prior rationalization runs (detected via `cass-mine.sh` at Phase 0.5), the skill builds a **cumulative discovery profile**:

- Track which patterns from § 3.1 have suggested ideas in this project before
- Filter against already-filed beads (don't re-suggest something the user already filed)
- Surface "patterns that keep recurring" as a meta-suggestion: "this is the third run that recovered a log-redaction hunk; consider adding a lint to prevent un-redacted log call sites"

```bash
# At Phase 0.5, cass-mine.sh records prior unblocked-work output paths:
prior_unblocked=$(jq -r '.prior_runs[].unblocked_work_path' "$WS/cass_findings.json")

# At Phase 11, idea-wizard cross-references prior suggested-new beads:
for prior in $prior_unblocked; do
    [ -f "$prior" ] && jq -s '.[0] + .[1]' "$prior" "$WS/unblocked/idea_wizard_output.md" \
        > "$WS/unblocked/cumulative_ideas.md"
done

# Suggestions that appeared in 2+ runs get priority bumps:
awk -F'\t' '$1 ~ /^P[34]$/ {seen[$2]++} END {for (s in seen) if (seen[s] >= 2) print s}' \
    "$WS/unblocked/cumulative_ideas.md" > "$WS/unblocked/recurring_patterns.txt"
```

Cross-link to [CASS-MINING.md](CASS-MINING.md) for the prior-run discovery mechanism.

---

## 9. Worked example — synthetic 8-scenario SELF-TEST

After running on the synthetic SELF-TEST repo (8 scenarios → 4 keepers landed):

```markdown
# Unblocked Work — branch-rationalization-2026-05-07 on dcg-self-test

## 1. Newly Actionable
(none — the synthetic repo has no beads)

## 2. Newly Blocked
(none)

## 3. Beads Candidates for Closure
(none — no beads database on the synthetic repo)

## 4. Suggested New Beads (per /idea-wizard pattern matching)

| Priority | Title | Reason | Source commit |
|---|---|---|---|
| P3 | Add fuzz target for harmonized parser | Synthesis covered 2 variants (defensive + type-narrowing) of parse_v2; fuzz protects the harmonization | parser-synthesis-sha |
| P4 | Document the parse_v2 harmonization decision | Synthesis combined scenario-F's defensive + scenario-G's narrowing; future agents need the rationale | parser-synthesis-sha |

## 5. PR Shifts
(none — synthetic repo has no remote)

## 6. /idea-wizard Output
[5 idea-wizard suggestions appended]
```

The user reviews this and decides which to file.

---

## 10. Cross-links

- [/idea-wizard](../../idea-wizard/SKILL.md) — source skill for follow-up idea generation
- [/beads-bv](../../beads-bv/SKILL.md) — source skill for triage / unblock detection (use ONLY `--robot-*` flags)
- [/beads-br](../../beads-br/SKILL.md) — issue tracker the unblock detection queries
- [PHASES.md § Phase 11](PHASES.md) — handoff phase that emits `unblocked_work.md`
- [CASS-MINING.md](CASS-MINING.md) — prior-run discovery for cumulative profile (Section 8)
- [INTEGRATION.md § 1 Beads](INTEGRATION.md) — `br create`, `br close` patterns
- [AUDIT-AFTER-RUN.md](AUDIT-AFTER-RUN.md) — runs before unblocked-work discovery; audit findings inform what's "really" unblocked
- [DRY-RUN-MODE.md](DRY-RUN-MODE.md) — predicts which beads would be unblocked; the unblock detection here is the post-run verification
- [AGENTS.md "Beads Workflow Integration"](../../../../AGENTS.md) — `br ready`, `br close` semantics
- [AGENTS.md "bv — Graph-Aware Triage Engine"](../../../../AGENTS.md) — `bv --robot-*` discipline
