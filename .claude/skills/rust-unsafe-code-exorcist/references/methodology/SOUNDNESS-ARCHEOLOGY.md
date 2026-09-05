# SOUNDNESS-ARCHEOLOGY.md — Mining the Project's Git History

Audit-time analysis sees CURRENT source. Archeology sees the PATH the source took to get here — what was tried, what was rejected, what's been forgotten.

Sometimes the right refactor for today is the one that was tried and abandoned in 2019 for reasons that no longer apply.

---

## What archeology finds

Per git log + git show + bead history + cass mining:

### 1. Birth-of-site analysis

For each unsafe site:
- **When** was it introduced? (`git log -p -- <file> | grep -B5 'unsafe'`)
- **Who** wrote it? (`git blame <file>`)
- **Why** (per the commit message / linked PR / bead at the time)?
- **What** else was changed in the same commit? (related context)
- **Was the SAFETY comment** added in the same commit, or later?

### 2. Refactor history

- Commits that ADDED unsafe (often hidden in big feature PRs).
- Commits that REMOVED unsafe (refactor wins; we want to learn from these).
- Commits that MODIFIED unsafe (subtle drift).
- PRs that ATTEMPTED a refactor and reverted (the unsafe came back; understand why).

### 3. Per-cluster pattern recognition

If a refactor pattern came up multiple times in history (same kind of (C) refactor in different places, different years), it's a SIGNATURE — the project has a recurring shape that the audit can systematize.

### 4. Abandoned PRs

PRs that proposed refactoring unsafe + were closed without merge. The discussion thread often has WHY-WE-DON'T reasons that are still valid (and which the current audit must respect).

---

## How to mine

The script `scripts/git-history-soundness-mine.sh`:

```bash
1. git log --all --diff-filter=A -p -- '*.rs' | grep -B 5 -A 20 'unsafe' > history/added-unsafe.diff
2. git log --all --diff-filter=D -p -- '*.rs' | grep -B 5 -A 20 'unsafe' > history/removed-unsafe.diff
3. For each commit hash extracted:
     git show --stat <hash> > history/commit-<hash>.stat
     git show <hash> > history/commit-<hash>.full
4. git log --all --grep='unsafe\|miri\|loom\|UB\|soundness\|safety' --pretty=format:'%H %s' > history/related-commits.txt
5. If gh CLI available + project on GitHub:
     For each related commit, fetch the linked PR + discussion (gh pr view).
6. If beads installed in project:
     br list --status closed --json | jq '.[] | select(.title | test("unsafe|safety|miri"; "i"))' > history/related-beads.json
```

Output: `<audit-dir>/audit/archeology/`.

---

## Per-site birth analysis

For each site in the inventory, the archeologist subagent produces:

`<audit-dir>/audit/archeology/sites/<site-id>__birth.md`:

```markdown
# site-NNNN — Birth Analysis

## File: src/parse.rs:142

## Born
- Commit: <hash>
- Date: 2023-04-15
- Author: <author>
- PR: #1234 — "Add JWT parsing support"

## SAFETY comment
- Born in same commit? YES
- Original comment (verbatim from commit <hash>):
  > "// SAFETY: token is verified to be at least 16 bytes before this call."
- Current comment (in HEAD):
  > "// SAFETY: see parse_header for null-termination invariant"
- DRIFT: YES — the comment was rewritten in commit <hash2>; the new comment is generic + less specific.

## Original PR context
- PR #1234 review comments (extracted via `gh pr view 1234`):
  - "@reviewer: should we add length check before transmute?"
  - "@author: the test exercises both paths; the SAFETY claim holds via length precondition."
  - "@reviewer: agreed; merging."
- Reviewers' concerns documented; concerns were addressed before merge.

## Subsequent modifications
- Commit <hash3> (2024-01-20): refactored to use slice indexing; the unsafe block became dead code.
- Commit <hash4> (2024-01-22): UNDID the refactor; rationale in PR #5678: "miri was clean but perf regressed 18%."

## Conclusions
- The site has a documented + addressed history.
- The (C) refactor was attempted and rejected for measured perf reasons → confirms (B) classification.
- The SAFETY drift is concerning; the current generic comment doesn't capture the original specific invariant.

## Recommended action
- The (B) classification is correct (rejected (C) refactor on measured perf grounds).
- The SAFETY comment should be HARDENED back to the specific length-precondition wording (per [safety-comment-skeleton.md](../../assets/safety-comment-skeleton.md)).
```

---

## Refactor-wins extraction

For commits that REMOVED unsafe (the wins):

```bash
git log --all --diff-filter=D -p -- '*.rs' | rg -B 5 'unsafe' | head -200
```

For each "win" commit, extract:
- What unsafe was removed.
- What it was replaced with.
- The author's rationale (commit message / PR body).
- Whether the replacement is still in HEAD.

Output: `<audit-dir>/audit/archeology/refactor-wins.md`:

```markdown
# Refactor Wins Catalog

Extracted from project's git history.

## Total commits that removed unsafe: <N>

### Win #1 — commit <hash>
Date: <date>
Pattern: raw `*mut LruEntry` → `slab::Slab<LruEntry>` indices
Rationale: "Use-after-free under heavy load; pointer math too brittle. slab gives stable indices with no perf loss measured."
Still in HEAD: YES (verified — `slab::Slab<LruEntry>` still in src/cache/lru.rs)
Pattern bundle: [10-POINTER-MIGRATIONS.md § Pattern P-1](../patterns/10-POINTER-MIGRATIONS.md)

### Win #2 — commit <hash>
...
```

The catalog teaches: "the project has shipped these (C) refactors successfully; the current audit should look for similar opportunities."

---

## Rejected-refactor catalog

For PRs that proposed refactoring + were closed without merge:

```markdown
# Rejected Refactors Catalog

## Rejection #1 — PR #999 (closed 2023-08-12)
Proposed: Replace `core::arch::x86_64::_mm_loadu_si128` with `std::simd::u8x16`.
Closed: "perf cliff on x86_64-v2 was 23%; not within budget."
Discussion: 14 comments documenting per-target benches.
Status: Documented in `audit/synthesis/rejected-patterns.md § perf-cliff-on-old-targets`.

## Rejection #2 — PR #1043
Proposed: Replace `unsafe impl Send` with `Arc<Mutex<...>>`.
Closed: "Mutex contention became the new bottleneck; reverted to unsafe impl Send."
Status: Pattern documented as known-unsuccessful.
```

The audit's plans should NOT propose these patterns without addressing the original rejection's reasons.

---

## Cross-reference with cass

The archeologist also queries cass for the project's history:

```bash
cass search "<crate-name> unsafe" --robot --limit 30 --host localhost
cass search "<crate-name> refactor safety" --robot --limit 30
```

Sessions where the user / past agents discussed the project's unsafe. These are tribal-knowledge captures that don't appear in git history.

---

## Pattern signatures

Looking at the win + rejected catalogs together, the archeologist identifies pattern signatures:

```markdown
# Pattern Signatures

## Signature: "raw pointer doubly-linked list → slab indices"
Wins: 3 (commits <hash1>, <hash2>, <hash3>)
Rejections: 0
Confidence: HIGH — this is a winning pattern for this project.
Recommendation: any current site matching this signature → (C) with high confidence.

## Signature: "transmute repr-cast → zerocopy::Ref"
Wins: 5
Rejections: 0
Confidence: HIGH.

## Signature: "manual SIMD → std::simd"
Wins: 2
Rejections: 1 (perf cliff on older targets)
Confidence: MEDIUM — works on newer targets; budget-bench before deciding.

## Signature: "unsafe impl Send → Arc<Mutex<...>>"
Wins: 0
Rejections: 1
Confidence: REJECTED — don't propose this for this project.
```

The audit's plans gain calibration from these signatures.

---

## Tribal-knowledge file

`<audit-dir>/audit/archeology/tribal-knowledge.md`:

```markdown
# Tribal Knowledge

Extracted from git history + cass + author comments. Things "everyone on the team knows but isn't written down."

## "We don't use Arc<Mutex<...>> in the hot path"
Source: PR #1043, multiple cass sessions.
Reason: measured Mutex contention bottleneck in 2023; project standardized on lock-free patterns.

## "miri can't run our FFI tests"
Source: AGENTS.md (yes, it IS written down), but worth surfacing.
Reason: most FFI tests have `#[cfg(not(miri))]`; rely on cargo-careful for those paths.

## "panic = abort is non-negotiable"
Source: commit <hash>; the team had a production incident from unwind-through-FFI.
Reason: any PR that proposes `panic = "unwind"` for this crate is rejected.

## "We don't depend on `lazy_static`"
Source: PR #234; deprecated in favor of `OnceLock`.
Reason: lazy_static's unsafe is older; OnceLock is std + simpler.
```

These are the things the audit's classifier should know but might not see in source.

---

## Acceptance signal

Archeology is healthy when:

1. Every unsafe site has a `birth.md` analysis.
2. Refactor-wins catalog has >0 entries (proves the project has a refactor culture).
3. Rejected-refactor catalog has its entries cross-referenced in plans (audit doesn't propose rejected patterns).
4. Pattern signatures are integrated into Phase 4 classification.
5. Tribal-knowledge file is referenced by the per-site classifications.

Archeology turns the project's institutional history into actionable audit input.
