# Recovery Commit Message Template

Use this template for Phase 8 commits on the rationalization branch.

---

## Standard recovery commit (single-source — cherry-pick / squash-merge / rebase-and-merge)

```
{prefix} recover {one-line summary} from branch {BRANCH_NAME}

Originally drafted in {BRANCH_NAME} (head: {sha}, dated {date},
{commit_count} commits ahead of {merge_base_sha}).

{2-3 sentences explaining the change's motivation: what problem does it
solve, what would break without it, why does it matter}

The polished version of this branch never landed because {reason — e.g.,
the agent that authored it crashed; the PR was abandoned; the upstream
ref was deleted; the work was superseded by a different approach that
didn't preserve all of this branch's defensive checks}.

Recovered via: {STRATEGY} from <bundle>/branches/{SLUG}/
{Optional: noting any manual conflict resolution + cross-link to
<workspace>/conflicts/branch_{SLUG}.context.md}
```

Where `{prefix}` is one of (per `project_profile.json:commit_message_convention`):
- `feat:` for new functionality
- `fix:` for bug fixes
- `test:` for test-only recovery
- `perf:` for performance improvements
- `refactor:` for structure changes that don't add behavior
- A ticket-id prefix like `BACK-1742:`
- No prefix for freeform projects

---

## Harmonized-synthesis commit (multiple sources — ◇ HARMONIZE)

```
{prefix} harmonize {SYMBOL_OR_FEATURE} across {N} sources

This commit synthesizes complementary work for {SYMBOL_OR_FEATURE} that was
developed in separate branches/worktrees but never landed together. Per the
harmonization plan in <workspace>/harmonization_plan.md, the strongest
example of each identified intent is preserved on top of {CANONICAL}'s
current structure.

Sources and intents:

- `{BRANCH_A}` (sha {sha_A}, {date}) — {intent_A, e.g., defensive null-check}
- `{BRANCH_B}` (sha {sha_B}, {date}) — {intent_B, e.g., length-cap}
- `{BRANCH_C}` (sha {sha_C}, {date}) — {intent_C, e.g., redaction-pattern}
- worktree `{WT_PATH}` (staged + unstaged) — {intent_D, e.g., type-narrowing}

The composition order matters:
  {ordered list of how the intents compose}

Tests included from each source:
  - {test_file::test_name from BRANCH_A}
  - {test_file::test_name from BRANCH_B}
  - ...

Recovered via:
- harmonization plan: <workspace>/harmonization_plan.md (variant matrix for
  {FILE_PATH})
- source variants:
  - <bundle>/branches/{SLUG_A}/diff-vs-merge-base.diff
  - <bundle>/branches/{SLUG_B}/diff-vs-merge-base.diff
  - <bundle>/branches/{SLUG_C}/diff-vs-merge-base.diff
  - <bundle>/worktrees/{WT_SANITIZED}/staged.diff +
    <bundle>/worktrees/{WT_SANITIZED}/unstaged.diff
```

---

## Split-apply commit (Phase 8b — partial-novel branch, novel commits only)

```
{prefix} recover {summary} from partial branch {BRANCH_NAME}

Originally {BRANCH_NAME} mixed {what landed via PR/squash} with {what's novel};
the {what landed} portion already merged via {PR/commit} on {date}. This commit
recovers only the novel commits.

Commits cherry-picked: {kept_count} of {total_count}.
- {sha_1}: {short subject}
- {sha_2}: {short subject}

Commits dropped (already on {CANONICAL}, per `git cherry -v`):
- {sha_3}: superseded by {citation}
- {sha_4}: superseded by {citation}

Recovered via: cherry-pick of the {kept_count} novel commits from
<bundle>/branches/{SLUG}/format-patch/.
```

---

## Conflict-resolved commit

```
{prefix} recover {summary} ported through {CANONICAL}'s {refactor description}

Originally {BRANCH_NAME}'s diff modifies {old structure} at {file:line of
branch's merge-base}. On {CANONICAL} today, that structure has been refactored
into {new structure} at {current file:line}.

A direct cherry-pick / squash-merge would have produced syntactically broken
code or silently applied wrong content. Instead, the branch's *intent*
({the actual goal}) was ported into {CANONICAL}'s current structure via the
Edit tool.

Recovered via: manual resolution; see
<workspace>/conflicts/branch_{SLUG}.context.md for the full surface diff and
the user-confirmed resolution.
```

---

## Dirty-worktree-only commit

```
{prefix} recover {summary} from worktree dirty state at {WT_PATH}

Originally staged + unstaged + untracked content in worktree at {WT_PATH}
(branch: {BRANCH_NAME}, last commit: {sha}). The work was never committed
because {reason — e.g., the agent's session was interrupted; the user
switched branches without committing; the agent crashed mid-edit}.

Content recovered:
- staged: {file_count} files, {hunk_count} hunks
- unstaged: {file_count} files, {hunk_count} hunks
- untracked: {file_count} files (test fixtures / new modules / sample data)

Recovered via:
- <bundle>/worktrees/{WT_SANITIZED}/staged.diff
- <bundle>/worktrees/{WT_SANITIZED}/unstaged.diff
- <bundle>/worktrees/{WT_SANITIZED}/untracked.tar.gz
```

---

## Bug-fix recovery

```
fix: recover {bug guard / fix} for {affected component}

Originally {BRANCH_NAME} (sha {sha}, dated {date}). Discovered while
{context}: {short bug description}.

The polished version landed in PR #{X}, but only for {covered case};
this commit applies the same {fix} to {missed case}.

Recovered via: cherry-pick of {sha} from <bundle>/branches/{SLUG}/.
Tests: {test command} passed; gates: typecheck + lint + UBS clean.
```

---

## Authoring checklist

- [ ] Subject ≤72 chars
- [ ] Subject is present-tense verb + concrete object (not "cherry-pick branch X")
- [ ] Body has Context, Why-not-landed, How-recovered sections
- [ ] Source branch name(s) + sha(s) cited
- [ ] Bundle paths cited
- [ ] Convention compliance (Conventional / ticket-id / gitmoji / freeform)
- [ ] No `Co-Authored-By` (unless user requested)
- [ ] Stand-alone readable (future-you in 6 months)
- [ ] For harmonized-synthesis commits: ALL source variants cited; intents named; composition order explained; tests from all sources enumerated
- [ ] For conflict-resolved commits: link to <workspace>/conflicts/branch_<slug>.context.md
- [ ] Never includes `Co-Authored-By` lines unless the user asked
- [ ] Never bypasses pre-commit hooks (`--no-verify`)
