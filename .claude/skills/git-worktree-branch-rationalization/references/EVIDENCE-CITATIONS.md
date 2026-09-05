# Evidence Citations — How to Cite What You Found

Every triage row in `triage.tsv` has an `evidence` column. Every variant-matrix entry in `harmonization_plan.md` has a `risks` and `signatures` column. Every conflict resolution has a context.md file. Every handoff statement has a workspace artifact backing it. This file is the citation style guide.

Adapted from [git-stash-janitor's EVIDENCE-CITATIONS.md](../../git-stash-janitor/references/EVIDENCE-CITATIONS.md). The forms are similar; the *required citation density* is higher because each branch generates more evidence than each stash (multiple commits, possibly multiple files, possibly conflicting with multiple other branches), and because harmonization syntheses must cite *every* source variant.

> **The standard:** Per [SKILL.md "Polish Bar"](../SKILL.md#the-polish-bar-non-negotiable), "every triage row cites concrete evidence on canonical — `file.rs:317` showing the symbol exists, or `git cherry -v` showing patch-id equivalence, or grep-empty proving 'novel'. 'I think it's superseded' is never acceptable." This file makes that standard operationalized.

---

## Why citations matter

The user reviews the triage table in Phase 6. Their default question on every row is *"how do you know?"* If the agent can answer with a `file:line` citation that takes the user straight to the evidence, the verdict is trustworthy. If the agent can only say "it looks superseded", it isn't.

For harmonization plans, the citations are even more load-bearing: the user is being asked to approve a *synthesis* that combines hunks from multiple branches. Each combination decision must be backed by an inspectable artifact (the per-branch diff, the per-file ast-grep result, the cherry-summary). Without citations, the harmonization plan reads as "trust me"; with citations, it reads as a reviewable proposal.

---

## Citation forms

### Form A: file:line (preferred for code)

```
src/mutex.rs:317
src/mysql/protocol.rs:218-245
canonical:src/util/logger.rs:42 (post-PR-#234 introduction)
```

Use when:
- Verifying a symbol exists on canonical
- Pointing at a line that proves supersession
- Citing a refactor that obsoleted the branch's work
- Naming a hunk's location in a variant for the harmonization matrix

The line number is to canonical (not the branch). If you cite a range, the range is the surrounding context the user would want to see. When `<branch>` matters (e.g., the line range is on a non-canonical branch's tip), prefix with `<branch>:` (`feature/length-cap:src/util/logger.rs:30-45`).

**Strong:** `src/mutex.rs:317` — directly inspectable.
**Weak:** `src/mutex.rs` — line not given; user has to scan.

---

### Form B: cherry-summary (`git cherry -v`)

```
git cherry -v master wip-BACK-1742: 12 lines, all `-` (patch-id-equivalent)
git cherry -v master feature/parse-hardening: 8 lines, 5 `-` 3 `+`
```

Use when:
- Verifying `already-merged` verdict (all `-` lines means every commit's patch-id is on canonical)
- Detecting partial overlap (`+` count = novel commits, `-` count = already-applied commits) for `partially-novel` verdict
- Per [SKILL.md Axiom 17](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git cherry -v` is the canonical 'is this content already on canonical' check." Patch-id equivalence detects squash-merged and rebase-landed content even when SHAs differ.

**Strong:** `git cherry -v master agent-fix-2026-04-29-attempt-3: all 4 lines are `-`; SHAs differ from canonical's PR #234 commits but patch-ids match.` — explicit, reproducible.
**Weak:** `looks like it's been merged` — no command, no verifiability.

---

### Form C: ast-grep / grep on canonical

```
ast-grep --pattern 'fn lock_until($$$)' canonical -- 'src/**/*.rs': 3 matches
git grep -F 'fn redact_secrets' canonical: src/util/logger.rs:42, tests/log_test.rs:88
```

Use when:
- Verifying the introduced symbol IS or IS NOT on canonical
- For Comprehensive mode where ast-grep gives more accurate matches than regex (multi-line constructs, generic types)
- When the same symbol exists on canonical with the same name but possibly different signature (input to Form F)

**Strong:** `git grep -nE '^\s*(pub )?fn redact_secrets' master -- 'src/**/*.rs'` returned `src/util/logger.rs:42` — explicit query, explicit hit.
**Weak:** `the function is on master` — without the query, can't reproduce.

---

### Form D: grep-empty (proves novel)

```
grep-empty: git grep -F 'fn cap_payload_length' canonical -- 'src/**' tests/**': 0 matches
```

Use when:
- Asserting the introduced symbol does NOT appear on canonical
- Required citation for `novel-and-accretive` verdict per [TRIAGE-RUBRIC.md §"Verdicts"](TRIAGE-RUBRIC.md#verdicts)

The exact query and the empty result are both part of the citation. Future-reader sees what was searched and that nothing came back.

**Strong:** `grep-empty: git grep -F 'fn cap_payload_length' master -- '**/*.rs': 0 matches; same query against branch tip: 1 match (src/mysql/protocol.rs:142).` — definitively novel.
**Weak:** `couldn't find it on master` — without the query, the absence is unverifiable.

---

### Form E: bundle artifact path

```
<bundle>/branches/agent-cleanup-pass-3/diff-vs-merge-base.diff
<bundle>/branches/wip-back-1742/format-patch/0001-add-payload-cap.patch
<bundle>/worktrees/data-projects-foo--wt-3/untracked.tar.gz
<workspace>/conflicts/branch_wip-back-1742.context.md
<workspace>/harmonization_plan.md#H-7-src-util-logger-rs
```

Use when:
- Pointing at the original branch's content (the diff is the truth, not the agent's recall)
- Referencing the recovery context for a manual conflict resolution
- Linking the handoff report to its supporting workspace files
- Citing harmonization-plan entries by id

**Strong:** `<bundle>/branches/wip-back-1742/format-patch/0001-add-payload-cap.patch` — fully-qualified path; the file exists at that location after Phase 3.
**Weak:** `the bundle has it` — without the path, user can't open the file.

---

### Form F: signature-divergence (forces verdict away from `superseded`)

```
signature-divergence: branch wip-BACK-1742 has cap_payload_length(buf: &[u8]) -> Result<&[u8], MysqlError>;
                     canonical:src/mysql/protocol.rs:142 has cap_payload_length(buf: Vec<u8>) -> Vec<u8>
```

Use when:
- A symbol exists on canonical with the same name but different signature
- Per [SKILL.md Axiom 16](../SKILL.md#the-rationalization-kernel-universal-axioms): "When ≥30% of sampled signatures diverge, flip the verdict to `divergent-refactor` (a candidate input to harmonization) and surface to user."

The citation MUST show both signatures verbatim so the user can see the divergence directly.

**Strong:** the example above — both signatures verbatim, both with file:line citations.
**Weak:** `signatures differ` — what differs? Not auditable.

---

### Form G: same-signature (validates `superseded`)

```
same-signature: branch wip-BACK-1742 and canonical:src/mysql/protocol.rs:142 agree on cap_payload_length(buf: &[u8]) -> Result<&[u8], MysqlError>
```

The converse of Form F. Use when validating a `superseded` verdict — the symbol exists on canonical AND the signatures match.

---

### Form H: reflog (force-push detection)

```
reflog: branches.tsv:wip-BACK-1742's upstream was force-pushed at 2026-04-25 14:22:11 UTC (sha 8a3d2c9 → sha 7d2e3f4); local branch retains pre-push history
```

Use when:
- Verifying that a branch's upstream was force-pushed and the local branch retains content the remote no longer has
- Required citation form for `[gone]`-tracking branches that have unique commits per [SKILL.md "Failure Modes"](../SKILL.md#failure-modes-table--branch--worktree-footguns) — "A branch with `[gone]` upstream has unique commits"

The exact reflog line(s) and the timestamp are the citation. See [TIMELINE-RECONSTRUCTION.md](TIMELINE-RECONSTRUCTION.md) for how to discover this.

---

### Form I: bead / issue id

```
BACK-1742
PR-234
fixes #2071
br-1m86f
```

Use when:
- The branch's name or commit messages reference a ticket
- The polished version landed via a specific PR
- The recovery commit closes a related issue

Cross-link with `br show <id>` in the workspace if that's available; the issue's status (closed / in-progress) is itself evidence.

---

### Form J: prefix-match (for garbage / convention verdicts)

```
prefix-match: name=other-agent-broken; matches garbage-prefix pattern
prefix-match: name=release/14.x; matches release/* protected-pattern
```

Use when:
- The verdict is `garbage` or `protected-preserve` based on name pattern alone
- No fingerprint analysis was needed (the prefix is sufficient)

Per [BRANCH-WORKTREE-SMELLS.md](BRANCH-WORKTREE-SMELLS.md), some patterns are strong enough priors that the prefix alone suffices for the verdict; the citation just records the matched pattern.

---

### Form K: worktree-state

```
worktree-state: data-projects-foo--wt-3 has 217 untracked files in tests/fuzz/corpus/, 0 staged, 0 unstaged tracked changes; branch=agent-fuzz-pass-2 (detached); last-activity=2026-04-19 (per .git/worktrees/<id>/HEAD mtime)
```

Use when:
- Citing the dirty state of a worktree as evidence for `dirty-worktree-only` verdict
- Naming the specific files that constitute the novel content
- Required for any worktree whose verdict isn't trivially `applied-keeper` or `protected-preserve`

---

## Per-verdict required citations

| Verdict | Required citation form(s) |
|---------|---------------------------|
| `canonical` | None (it's the canonical branch by definition) |
| `protected-preserve` | J (the matched protection pattern) OR explicit user-flag from `protected.tsv` |
| `already-merged` | B (cherry-summary, all `-` lines) |
| `superseded` | A or C (file:line on canonical where the symbol resolves) AND G (same-signature on ≥1 sampled symbol) |
| `novel-and-accretive` | D (grep-empty proving symbols absent) AND apply-check status (clean) |
| `partially-novel` | B with mixed `+`/`-` AND per-hunk: A for the superseded hunks, D for the novel hunks |
| `novel-but-stale` | A or E showing files no longer exist OR apply-check failed; H (force-push reflog) if applicable |
| `divergent-refactor` | F (signature-divergence) AND, ideally, A pointing at canonical's current implementation |
| `dirty-worktree-only` | K (worktree-state) AND, optionally, A on canonical where the worktree's content would land if recovered |
| `garbage` (by prefix) | J (prefix-match: <pattern>) |
| `garbage` (by content) | A or B citing the polished version that superseded the entire branch |
| `unknown` | Honest description of why: "empty fingerprint", "binary diff", "language not supported by rubric" |

If the required citation form is missing, the verdict is invalid; the row goes to `unknown` and Phase 6 surfaces it for user override.

---

## How to discover citations

### For `superseded` verdicts

```bash
# Path-scoped grep first (faster, more accurate; uses canonical name from project_profile.json)
git grep -nE 'fn lock_until' "$CANONICAL" -- 'src/**/*.rs'
# Returns: src/mutex.rs:317:    pub fn lock_until(deadline: Instant) -> Result<()>

# Whole-repo if path-scoped finds nothing
git grep -nF 'lock_until' "$CANONICAL"
```

The output gives you the file:line citation directly.

For Comprehensive mode, ast-grep:

```bash
ast-grep --pattern 'fn lock_until($$$ARGS)' --lang rust .
```

### For `already-merged` verdicts

```bash
git cherry -v "$CANONICAL" "<branch>"
# - 8a3d2c9 add payload cap
# - 6c2d4e3 add overflow test
# - 2f1a3b9 update changelog
# All `-` lines: every commit's patch-id is on canonical → already-merged
```

### For `partially-novel` per-hunk evidence

```bash
git cherry -v "$CANONICAL" "<branch>"
# - 8a3d2c9 add payload cap            (already on canonical)
# + 4f5e6d7 add new fuzz corpus        (novel)
# + 1a2b3c4 add v2_overflow test        (novel)
# Mixed: some `-`, some `+` → partially-novel; recover the `+` commits via Phase 8b
```

### For `novel-but-stale` evidence

```bash
# Show the file's history on canonical
git log --all --oneline -- src/cli/legacy.rs | head -5
# If the file appears, find when it was removed
git log --diff-filter=D --all --oneline -- src/cli/legacy.rs
# Returns: deadbeef src/cli/legacy.rs deleted in PR #198
```

The deletion commit is the citation: "B: deadbeef removed src/cli/legacy.rs; branch's content is now stale".

### For signature-divergence

```bash
# Pull the signature from the branch (from the bundle's diff)
grep -E '^\+.*fn lock_until' <bundle>/branches/<slug>/diff-vs-merge-base.diff
# Pull the signature from canonical
git grep -nE 'fn lock_until' "$CANONICAL" -- 'src/**/*.rs'
# Compare param lists; if they differ, signature-divergence is real
```

### For `[gone]`-upstream branches with unique commits

```bash
# The branch's tracking ref is gone, but local has commits
git log --oneline "$CANONICAL"..<branch>
# Returns commits that are local-only

# Reflog shows when the upstream was force-pushed (if it was)
git reflog show "<branch>@{upstream}" 2>&1 | head
# Or if upstream is fully gone:
git reflog show <branch> | head
```

### For dirty-worktree state

Already captured by `scripts/discover-branches-worktrees.sh` Pass A; live values are in `worktrees.tsv`. The bundle's per-worktree `meta.txt` and `status.txt` are the persistent citation source.

---

## Citation density per phase

| Phase | Typical citation density |
|-------|-------------------------|
| 4 (protection confirmation) | Form J for each auto-protected entry |
| 5 (triage) | One required citation per row in `triage.tsv:evidence` (per the per-verdict table above) |
| 6 (decision table) | Same citations as Phase 5, surfaced for the user in markdown |
| 7 (harmonization plan) | A or C for every variant's signatures column; F or G for cross-variant signature comparisons; E for source paths in the bundle |
| 8 (apply commits) | Per-keeper: source-branch slug + sha + bundle path in the commit body; for syntheses also the harmonization-plan entry id |
| 8b (split-apply) | Per-hunk: A or D for each hunk's verdict in the commit body |
| 9 (fresh-eyes findings) | One citation per finding (which file, which line, which keeper sha) |
| 10 (cleanup_log.tsv) | Self-citation: the deleted ref's backup-ref name + bundle path |
| 11 (handoff report) | Recovered commits → SHA citations; recovery recipes → bundle paths; counts → tsv-row references; harmonization summary → `harmonization_plan.md` entry ids |

---

## Anti-patterns in citation

| Anti-pattern | Why bad |
|--------------|---------|
| "looks superseded" with no citation | Unverifiable; user can't audit |
| Citing only the symbol name | User has to grep themselves; do the grep for them and cite the result |
| Citing without verifying the path/sha exists | Breaks user trust on first dead link; verify before citing |
| Citing the WORKSPACE files for the user but not in your own reasoning | Self-discipline matters; cite for your own future-readability too |
| Multi-line citations in TSV files | TSV is one row; truncate or reference an external file (`see <workspace>/conflicts/branch_<slug>.context.md`) |
| Stale citations (file:line that pointed somewhere relevant 3 commits ago but no longer does) | Cite against the canonical SHA at run-start, not against `HEAD` which may have moved during the run |
| Missing harmonization-plan entry id when committing a synthesis | The plan is the source of truth for the synthesis decision; the commit must point back to it |
| Form A without the file existing on canonical at run-start | The file:line must resolve at the moment of citation. If canonical drifted mid-run, re-cite |
| Naming a branch slug that's already been deleted at the time the citation is read | Use the SHA, not just the slug; SHAs survive `git branch -D` for the reflog window AND are preserved in the bundle |
| Citing `git cherry -v` with no lines shown | Show at least the count summary (`12 lines, all -`) or, ideally, the full output truncated to first/last 5 |

---

## Example: full citation chain for a recovered commit

In `triage.tsv`:
```
wip-BACK-1742  novel-and-accretive  0.92  grep-empty: cap_payload_length not on master; apply-check clean  cherry-pick  src/mysql/protocol.rs
```

In `triage_decision.md`:
```markdown
| wip-BACK-1742 | 0.92 | novel-and-accretive | grep-empty: `git grep -F 'fn cap_payload_length' master -- 'src/**/*.rs'` returned 0; apply-check clean | cherry-pick |
```

In `harmonization_plan.md` (entry §H-3 for src/mysql/protocol.rs):
```markdown
### Variant: wip-BACK-1742 (head sha 8a3d2c9)

- **Signatures introduced**: `fn cap_payload_length(buf: &[u8]) -> Result<&[u8], MysqlError>`
- **Citation**: <bundle>/branches/wip-back-1742/diff-vs-merge-base.diff lines 14-22
- **Hunk summary**: adds payload-length cap with fail-closed semantics
- **Intent**: defensive
- **Proposed synthesis**: adopt verbatim onto canonical's current Logger structure
- **Risks**: none; canonical's MysqlError enum already has PayloadTooLarge variant (verified at canonical:src/mysql/error.rs:8)
- **Confidence**: 0.92
```

In the resulting commit message:
```
recover defensive MySQL OK-packet length-cap from wip-BACK-1742

Originally drafted on branch `wip-BACK-1742` (sha 8a3d2c9, last commit
2026-04-29). [...]

Recovered via: git cherry-pick 8a3d2c9 onto branch-rationalization-2026-05-07
              (clean apply against canonical's current structure).

Source: <bundle>/branches/wip-back-1742/diff-vs-merge-base.diff
        <bundle>/branches/wip-back-1742/format-patch/0001-add-payload-cap.patch

Harmonization plan: harmonization_plan.md §H-3 (src/mysql/protocol.rs)
```

In `apply_log.tsv`:
```
wip-BACK-1742  cherry-pick  8a3d2c9  def987  passed  78  none
```

In `handoff_report.md`:
```markdown
## Recovered commits

| sha | from branch | message |
|-----|-------------|---------|
| def987 | wip-BACK-1742 | recover defensive MySQL OK-packet length-cap from wip-BACK-1742 |
```

Every step has a citation that the next step can verify against. The chain is auditable end-to-end. Per [POLISH-BAR.md §"Verdict evidence"](POLISH-BAR.md#verdict-evidence), this end-to-end auditability is what makes a "successful run" different from a "completed run that destroyed something we didn't realize we needed."
