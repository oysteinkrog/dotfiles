# Audit After Run — Codebase Audit on the Rationalization Branch

Phase 9 fresh-eyes catches obvious bugs. This file specifies a deeper, **explicit** audit (per [/codebase-audit](../../codebase-audit/SKILL.md)) that runs on the rationalization branch BEFORE Phase 10 cleanup is allowed to proceed. The audit is the final quality gate before the user pushes.

Adapted from [/codebase-audit](../../codebase-audit/SKILL.md) and [/multi-pass-bug-hunting](../../multi-pass-bug-hunting/SKILL.md). The two skills compose: codebase-audit gives the dimension taxonomy; multi-pass-bug-hunting gives the audit-fix-rescan cycle that closes findings.

> **Why audit after fresh-eyes?** The rationalization branch contains synthesized work from many sources — typically 5–30 keeper commits, several of which are harmonized syntheses combining hunks from 3+ source branches. Phase 9 fresh-eyes runs ≥2 review rounds and catches obvious bugs. The audit catches **subtle integration issues**: security regressions hidden in a harmonized commit, performance regressions where a `for` loop became `O(n^2)` after combining variants, API consistency drift where two recovered commits used different conventions for the same surface, test-coverage gaps where a recovered commit lacks an exercising test, commit-message-quality drift where a synthesis commit cites only one of its three sources.

---

## 1. When the audit runs

The audit runs **after Phase 9 fresh-eyes converges** and **before Phase 10 cleanup begins**. It's a hard gate: Phase 10 is BLOCKED until the audit passes.

```
Phase 9 (fresh-eyes ≥ 2 clean rounds)
   ↓
Phase 9.5 — AUDIT (this file)   ← new gate
   ↓
Phase 10 (destructive cleanup, gated on verbatim auth)
```

The phase numbering uses 9.5 because the audit conceptually slots between fresh-eyes (which reviews each commit) and cleanup (which mutates state). Cross-link to [PHASES.md](PHASES.md) for the full phase loop.

> **Why a separate gate from Phase 9?** Fresh-eyes reviews each commit in isolation — "does this commit do what its message says?" The audit reviews the **assembled rationalization branch** as a whole — "does the integrated work meet our quality bar?" These are different questions. Fresh-eyes is bottom-up; audit is top-down.

---

## 2. Audit dimensions

Six dimensions, each with automated checks + escalation paths. Adapted from [/codebase-audit](../../codebase-audit/SKILL.md) § Audit Domains.

| Dimension | What it catches | Automated check | Escalation |
|---|---|---|---|
| **Security** | new credential leaks, SQL injection, path traversal, command injection, weakened crypto | UBS, gitleaks, semgrep (security ruleset), `git diff` regex for known-bad patterns | If found, halt and surface to user with verbatim diff and source-branch attribution |
| **Performance** | new `O(n^2)` loops, allocations on hot paths, sync-in-async, blocking IO in async, dropped indices | clippy (Rust), eslint-plugin-perf (TS/JS), pyflakes (Python), language-specific profilers | If found, surface with the source-branch evidence and ask user whether to re-harmonize |
| **Correctness** | obvious null-pointer dereferences, off-by-one errors, race conditions, missing error paths, double-frees | UBS, clippy, eslint, pylint, language-specific bug scanners | If found, halt; per AGENTS.md "Fix all errors regardless of source", every error is fixed regardless of which source branch introduced it |
| **API consistency** | mixed conventions across recovered commits (e.g., `Result<T, E>` vs `Option<T>` for the same surface; mixed naming), broken backward compat with canonical | ast-grep with project-specific patterns, manual rg + Read | If found, surface for user adjudication; harmonization-planner may need a second pass |
| **Test coverage** | recovered commits without exercising tests; tests recovered without their fixtures; flaky tests that need a deterministic seed | `cargo llvm-cov` / `bun test --coverage` / `pytest --cov` per-commit-touched-file coverage delta | If coverage drops below project_profile.json threshold for a touched file, surface to user |
| **Commit message quality** | syntheses that cite only one of multiple sources; standard recoveries that lack the "why-it-didn't-already-land" section; subjects >72 chars | grep against [COMMIT-MESSAGE-CRAFT.md § the contract](COMMIT-MESSAGE-CRAFT.md) requirements | If found, the commit-message-author subagent rewrites and the user reviews |

> **Why these six and not more?** Per /codebase-audit's domain taxonomy, these are the six dimensions where mass mutations from many sources (the rationalization-branch shape) most often introduce subtle bugs. The seventh dimension /codebase-audit lists — **UX/copy** — is irrelevant for the rationalization-branch context (we're recovering code, not UI text). Skill-specific note: cross-link to [POLISH-BAR.md](POLISH-BAR.md) which has overlapping dimensions but checks structural artifacts, not code quality.

---

## 3. Per-dimension check + auto-fix

For each dimension, the audit runs the automated check first; if findings, decides between auto-fix and escalation.

### 3.1 Security

```bash
# Run on every file touched by a Phase 8 commit:
TOUCHED_FILES=$(git diff --name-only $CANONICAL..branch-rationalization-$DATE)

# UBS (project's primary scanner, per AGENTS.md):
ubs $TOUCHED_FILES > "$WS/audit/ubs.log" 2>&1
UBS_EXIT=$?

# gitleaks for credential leaks:
git -C "$PROJECT" diff $CANONICAL..branch-rationalization-$DATE | gitleaks stdin --report-format json > "$WS/audit/gitleaks.json"

# semgrep with security ruleset:
semgrep --config=auto $TOUCHED_FILES --json > "$WS/audit/semgrep_security.json"
```

Auto-fix policy: **NEVER auto-fix a security finding**. Per AGENTS.md "No Script-Based Changes" + the principle that security fixes need careful judgment, the audit halts on any security finding and surfaces with full context (the diff, the source branch, the proposed fix). The user decides; manual Edit only.

### 3.2 Performance

```bash
# clippy (Rust) — performance lints:
cd "$PROJECT" && cargo clippy --all-targets -- -W clippy::perf -W clippy::pedantic > "$WS/audit/clippy_perf.log" 2>&1

# Language-agnostic: rg for known anti-patterns introduced by the run:
rg -n 'for.*\{.*for.*\{' $TOUCHED_FILES > "$WS/audit/nested_loops.log"  # candidate O(n^2)
rg -n '\.unwrap\(\)' $TOUCHED_FILES > "$WS/audit/unwraps.log"  # candidate panics
rg -n 'block_on|tokio::runtime::Handle::current' $TOUCHED_FILES > "$WS/audit/sync_in_async.log"
```

Auto-fix policy: **escalate** for nested loops and sync-in-async (judgment calls); **auto-flag-for-review** for unwraps (where the user might prefer `expect()` with context).

### 3.3 Correctness

Highest-volume dimension; relies on the project's primary bug scanner (UBS for Rust, eslint for TS, pylint for Python, etc.).

```bash
# Per project_profile.json:bug_scanner_command:
$BUG_SCANNER_COMMAND $TOUCHED_FILES > "$WS/audit/correctness.log" 2>&1
```

Per AGENTS.md "Fix all errors regardless of source": every finding is fixed, not skipped. The audit's auto-fix policy here is **always fix**; commit-message-author subagent appends the fix to the originating recovery commit OR creates a follow-up `audit-fix:` commit, depending on whether the originating commit has been signed (don't re-sign signed commits without rebuilding their auth chain — see [GIT-NOTES-AND-SIGNATURES.md](GIT-NOTES-AND-SIGNATURES.md)).

### 3.4 API consistency

This dimension specifically catches **drift across recovered commits**. Example: branch A used `Result<Foo, FooError>` for the public surface; branch B used `Option<Foo>` for the same surface; both got recovered; the rationalization branch now exports both forms.

```bash
# Per-touched-file, list every public symbol's signature:
ast-grep run -l Rust -p 'pub fn $NAME($$$ARGS) -> $RET' --json $TOUCHED_FILES > "$WS/audit/public_signatures.json"

# Cross-reference with canonical's public surface:
ast-grep run -l Rust -p 'pub fn $NAME($$$ARGS) -> $RET' --json $TOUCHED_FILES_ON_CANONICAL > "$WS/audit/public_signatures_canonical.json"

# Diff: which signatures changed?
jq -s 'difference' "$WS/audit/public_signatures.json" "$WS/audit/public_signatures_canonical.json" > "$WS/audit/signature_drift.json"
```

Auto-fix policy: **always escalate**. API consistency requires user judgment about which convention should win. The audit annotates the drift report with the source-branch attribution per signature and asks the user.

### 3.5 Test coverage

```bash
# Per project's test framework:
case $project_profile_test_framework in
  cargo)   cargo llvm-cov --json --output-path "$WS/audit/coverage.json" ;;
  vitest)  bun test --coverage --reporter=json > "$WS/audit/coverage.json" ;;
  pytest)  pytest --cov --cov-report=json:"$WS/audit/coverage.json" ;;
esac

# Per-touched-file coverage delta:
for f in $TOUCHED_FILES; do
  current=$(jq -r ".files[\"$f\"].lines.pct" "$WS/audit/coverage.json")
  threshold=$(jq -r ".coverage_thresholds[\"$f\"] // .coverage_thresholds.default" "$PROJECT/project_profile.json")
  if (( $(echo "$current < $threshold" | bc -l) )); then
    echo "$f $current $threshold" >> "$WS/audit/coverage_drops.tsv"
  fi
done
```

Auto-fix policy: **escalate** to the user with the list of files whose coverage dropped. The user decides whether to add tests now (user authors, audit verifies) or defer to a beads follow-up.

### 3.6 Commit message quality

```bash
# Per-commit on the rationalization branch:
for sha in $(git log --format=%H "$CANONICAL..branch-rationalization-$DATE"); do
  msg=$(git log -1 --format=%B "$sha")

  # Subject line ≤72 chars:
  subject=$(echo "$msg" | head -1)
  [ ${#subject} -gt 72 ] && echo "$sha SUBJECT_TOO_LONG ${#subject}" >> "$WS/audit/commit_msg_issues.tsv"

  # Body has Context + Why-it-didn't-already-land + How-it-was-recovered (per COMMIT-MESSAGE-CRAFT.md § the contract):
  echo "$msg" | grep -qE '^(Context|Originally drafted)' || echo "$sha MISSING_CONTEXT" >> "$WS/audit/commit_msg_issues.tsv"
  echo "$msg" | grep -qE 'didn.t.*land|never landed|why.*now' || echo "$sha MISSING_WHY_NOT_LANDED" >> "$WS/audit/commit_msg_issues.tsv"

  # Synthesis commits cite ALL sources (cross-check with apply_log.tsv):
  strategy=$(awk -v s="$sha" '$3==s {print $4}' "$WS/apply_log.tsv")
  if [ "$strategy" = "harmonized-synthesis" ]; then
    expected_sources=$(awk -v s="$sha" -F'\t' '$3==s {print $7}' "$WS/apply_log.tsv" | tr ',' '\n' | sort -u)
    cited_sources=$(echo "$msg" | grep -oP '(?<=from )[a-zA-Z0-9/-]+' | sort -u)
    diff <(echo "$expected_sources") <(echo "$cited_sources") || echo "$sha MISSING_HARMONIZATION_SOURCES" >> "$WS/audit/commit_msg_issues.tsv"
  fi
done
```

Auto-fix policy: **auto-rewrite** via the commit-message-author subagent (see [PHASES.md § Phase 8](PHASES.md) for that subagent's contract). The user reviews the rewrite before it lands.

---

## 4. Audit on harmonized syntheses specifically

Harmonized commits get **extra** audit depth, because they compose hunks from multiple sources. Each harmonized commit is checked against:

1. **All its source variants' tests**, not just the project's main suite. The audit identifies the test files in each source branch and runs them against the harmonized synthesis. This is **MR-4 Intent Preservation** from [TESTING-METAMORPHIC.md](../../testing-metamorphic/SKILL.md) (cross-link to that skill's metamorphic-relation taxonomy):
   - For every hunk recovered from branch X, run X's tests on the synthesized file. If X's tests break, the synthesis dropped X's intent.
2. **The harmonization plan's variant matrix**: for every cited variant, verify the synthesis actually contains a recognizable trace of that variant. The audit grep's the synthesized file for variant-fingerprint regexes the harmonization-plan recorded.
3. **The synthesis confidence** (from harmonization_plan.md): if confidence was <0.85, the audit runs an extra adversarial round (per [FRESH-EYES-PROMPTS.md](FRESH-EYES-PROMPTS.md) § Adversarial prompt) on this commit.

```bash
for sha in $(awk -F'\t' '$4=="harmonized-synthesis" {print $3}' "$WS/apply_log.tsv"); do
  # Identify source branches:
  sources=$(awk -F'\t' -v s="$sha" '$3==s {print $7}' "$WS/apply_log.tsv" | tr ',' ' ')

  # For each source, run its tests against the synthesized file:
  for src_branch in $sources; do
    src_test_files=$(git diff --name-only $CANONICAL..refs/branch-rationalization-backup/$src_branch -- 'tests/' '*_test.*')
    git checkout branch-rationalization-$DATE -- $src_test_files 2>/dev/null
    cd "$PROJECT" && $TEST_COMMAND $src_test_files >> "$WS/audit/harmonization_${sha:0:8}.log" 2>&1
  done
done
```

If any source's tests break on the synthesis, the audit halts and surfaces with the failing test name, the source branch, the original variant, and the synthesized file content.

> **Why this depth for syntheses?** Per [HARMONIZATION.md § 1 Intent attribution](HARMONIZATION.md): "every variant has an intent (defensive, refactor, type-narrowing, etc.); the synthesis must preserve every cited intent." The metamorphic check above is the empirical verification of that contract — if X's tests pass on the synthesis, X's intent is preserved. Cross-link to /testing-metamorphic § MR-4: "If input transformation T is performed in code, the corresponding tests must still pass."

---

## 5. Output: `audit_report.md`

The audit emits a single markdown report at `<workspace>/audit_report.md` and appends it as a section to `handoff_report.md` at Phase 11.

```markdown
# Audit Report — branch-rationalization-2026-05-07

Generated: 2026-05-07T15:42:11Z
Commits audited: 23
Audit duration: 12 min 34 sec
Overall status: **PASS** (or FAIL with N findings)

## Per-Dimension Summary

| Dimension | Status | Findings | Auto-fixed | Escalated |
|---|---|---|---|---|
| Security | PASS | 0 | 0 | 0 |
| Performance | PASS | 1 | 0 | 1 (nested loop in src/parser.rs) |
| Correctness | PASS | 3 | 3 | 0 |
| API consistency | FAIL | 2 | 0 | 2 (Result vs Option drift) |
| Test coverage | PASS | 1 | 0 | 1 (src/logger.rs dropped from 89% to 84%) |
| Commit message quality | PASS | 5 | 5 | 0 |

## Per-Commit Status

| SHA | Strategy | Subject | Status | Findings |
|---|---|---|---|---|
| aa11bb22 | cherry-pick | recover defensive OK-packet length-cap from wip-BACK-1742 | PASS | — |
| bb22cc33 | harmonized | harmonize logger hardening from agent-cleanup-pass-3 + feature/length-cap + feature/redact-secrets | PASS | metamorphic round all 3 sources' tests pass |
| cc33dd44 | rebase-and-merge | recover full feature/parse-hardening branch | FAIL | API drift — see Section "API consistency" |

## Findings Detail

### Security
[per-finding sub-sections; empty if no findings]

### Performance
#### F1. Nested loop introduced in src/parser.rs

Source commit: aa22bb33 (`harmonize parser hardening from scenario-F + scenario-G`)
Source variant: scenario-G's type-narrowing hunk
Location: src/parser.rs:L142-L148

```rust
for chunk in input.chunks_exact(8) {
    for byte in chunk {
        // O(n^2) on byte counts; original scenario-G version used .iter().flatten() — O(n)
    }
}
```

Recommendation: re-run harmonization-planner with `--prefer-flat-iteration` flag, OR user manually edits via Edit tool.

### Correctness
[per-finding sub-sections]

### API consistency
[per-finding sub-sections]

### Test coverage
#### F1. src/logger.rs coverage dropped from 89% → 84%

Threshold: 85% (per project_profile.json)
Uncovered lines: L67-L74 (the harmonized `redact_secrets()` body, specifically the `LogEvent::Trace` arm)
Source variant lacking a test: scenario-F's `LogEvent::Trace` defensive guard

Recommendation: add a unit test exercising `LogEvent::Trace { secret_keys: vec!["api_key"] }` to ensure the guard fires.
User decides: add now (user authors test) OR defer (file beads issue).

### Commit message quality
[per-finding sub-sections; empty if all auto-fixed cleanly]
```

The report is structured for both human review and machine consumption. The `polish-bar-check.sh` script (Phase 11) reads the `Overall status` field and refuses to mark the run "complete" if it's FAIL.

---

## 6. When the audit fails

Two cases:

### 6.1 Auto-fixable findings

The audit auto-fixes correctness findings (per AGENTS.md "Fix all errors regardless of source") and commit-message findings. After auto-fix, the audit re-runs to verify the fixes didn't regress other dimensions. Up to 3 audit-fix-rescan cycles per [/multi-pass-bug-hunting](../../multi-pass-bug-hunting/SKILL.md). After 3 cycles without convergence, escalate.

### 6.2 Escalated findings

The audit halts and surfaces to the user. Phase 10 cleanup is BLOCKED. The user has three options:

1. **Fix manually**, then re-run the audit. The audit-fix-rescan converges; Phase 10 unlocks.
2. **Roll back the rationalization branch tip** to the last passing commit. Per [RECOVERY-RECIPES.md R6](RECOVERY-RECIPES.md):
   ```bash
   # The audit identifies the last-passing-commit SHA from per-commit status.
   # User authorizes via verbatim phrase per AGENTS.md "Mandatory explicit plan":
   #   "yes I understand and want to git revert <sha>..HEAD on branch-rationalization-2026-05-07"
   git revert <sha>..HEAD
   ```
   This preserves history (per Axiom 18 — never `git reset --hard` on shared branches). The reverted commits stay in the reflog + bundle for later recovery if the user changes their mind.
3. **Accept the findings and proceed anyway.** Requires verbatim authorization that explicitly cites the unresolved findings: `"yes I understand the audit reported N findings (security: 0, performance: 1, correctness: 0, api: 2, coverage: 1, msg: 0) and I want to proceed to Phase 10 cleanup anyway, recording the findings in the handoff."`. The audit findings are still recorded in `audit_report.md` for the handoff.

> **Why give the user an "accept and proceed" option?** Per AGENTS.md "Mandatory explicit plan", the user always has final say. Some findings are intentional (e.g., a divergent-refactor commit may have known API drift the user wants to land anyway). The audit's job is to **surface**, not to **decide**.

---

## 7. Audit blocks Phase 10 cleanup

The hard gate:

```bash
# In scripts/drop-retire-confirmed.sh, before any worktree removal or branch deletion:
if [ -f "$WS/audit_report.md" ]; then
    audit_status=$(grep -m1 '^Overall status:' "$WS/audit_report.md" | grep -oP '(?<=\*\*).*?(?=\*\*)')
    if [ "$audit_status" = "FAIL" ] && [ -z "$AUDIT_ACCEPTED_FINDINGS" ]; then
        echo "ERROR: audit reported FAIL with unresolved findings; Phase 10 is blocked."
        echo "Either fix the findings (re-run audit) or set AUDIT_ACCEPTED_FINDINGS=1 with verbatim user authorization."
        exit 1
    fi
fi
```

`AUDIT_ACCEPTED_FINDINGS=1` is set only when the user has typed the option-3 verbatim phrase from § 6.2. The user-authorization text is recorded in `cleanup_authorization.txt` next to the standard verbatim cleanup phrase.

> **Why a hard gate?** Per [SKILL.md "Polish Bar"](../SKILL.md#the-polish-bar-non-negotiable): "If a run can't satisfy these, it has not 'completed successfully' — it has half-finished and needs to flow back through whichever phase failed." The audit is the formal version of "successful means quality, not just done."

---

## 8. Resumability + idempotency

The audit is resume-aware:

- `audit_report.md` carries an `audit_checkpoint:` line that names the last completed dimension. On re-run, the audit skips already-completed dimensions and resumes.
- Per-dimension caches live in `<workspace>/audit/`. If a touched file's hash hasn't changed since the last audit, the per-file findings are reused.
- The audit is idempotent — re-running on a clean rationalization branch produces an identical report (modulo timestamps).

---

## 9. Audit on triage-only and apply-only modes

| Mode | Audit runs? | Audit gates Phase 10? |
|---|---|---|
| `full` | Yes | Yes (hard gate) |
| `apply-only` | Yes | n/a (Phase 10 doesn't run anyway) |
| `triage-only` | No (no rationalization branch to audit) | n/a |
| `--dry-run` | No (no real apply has happened) | The dry-run report itself has audit-equivalent prediction in its callouts |

For `apply-only`, the audit still runs and emits `audit_report.md` because the user may want to push the rationalization branch — the audit findings inform whether to push or fix locally first.

---

## 10. Cross-links

- [/codebase-audit](../../codebase-audit/SKILL.md) — source skill for the dimension taxonomy
- [/multi-pass-bug-hunting](../../multi-pass-bug-hunting/SKILL.md) — source skill for the audit-fix-rescan cycle
- [/testing-metamorphic](../../testing-metamorphic/SKILL.md) — MR-4 Intent Preservation, the test-against-source-variants check for harmonized commits
- [PHASES.md](PHASES.md) — the phase loop the audit slots into (Phase 9.5)
- [POLISH-BAR.md](POLISH-BAR.md) — overlapping dimensions (structural artifacts vs. code quality)
- [COMMIT-MESSAGE-CRAFT.md](COMMIT-MESSAGE-CRAFT.md) — the contract the commit-message-quality dimension enforces
- [HARMONIZATION.md](HARMONIZATION.md) — intent-attribution contract harmonized syntheses must preserve
- [FRESH-EYES-PROMPTS.md](FRESH-EYES-PROMPTS.md) — the Phase 9 review (audit is the next layer down)
- [RECOVERY-RECIPES.md R6](RECOVERY-RECIPES.md) — `git revert` recipe for rolling back failed-audit commits
- [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md) — surfacing patterns when audit findings escalate
- [GIT-NOTES-AND-SIGNATURES.md](GIT-NOTES-AND-SIGNATURES.md) — signature implications of audit-fix commits
- [DRY-RUN-MODE.md](DRY-RUN-MODE.md) — forward-looking analogue (predicts findings the audit will catch)
- [UNBLOCKED-WORK.md](UNBLOCKED-WORK.md) — runs after audit; identifies new-actionable beads
- [AGENTS.md "Fix all errors regardless of source"](../../../../AGENTS.md) — the principle that drives auto-fix policy in correctness dimension
- [AGENTS.md "Mandatory explicit plan"](../../../../AGENTS.md) — verbatim auth required for "accept findings and proceed"
