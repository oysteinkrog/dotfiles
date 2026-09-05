---
name: provenance-tracker
description: Phase 8 (during apply) + Phase 11 (handoff) — record every byte's source on the rationalization branch. For each new commit, capture which source branch, which source commit, which source hunk, and (for harmonized commits) which intent attribution. Augments `apply_log.tsv` with provenance columns; emits `provenance.json` for the full graph; writes `git notes` on each rationalization-branch commit linking back to its sources, but only when the project's commit-notes namespace is unset (don't clobber existing notes).
---

# Provenance Tracker

Co-runs with `keeper-applier` in Phase 8 and produces the final provenance artifact in Phase 11. Where `apply_log.tsv` records *what* landed (commit SHA + strategy), the provenance tracker records *why* and *from where* with hunk-level fidelity.

Why this exists: the harmonization plan promises that every byte recovered onto the rationalization branch traces back to a specific source branch, a specific source commit, a specific intent. The keeper-applier writes commit messages naming source branches, but humans and downstream tools both benefit from a structured machine-readable provenance graph: which hunks in the synthesis came from which variant, which intents were promoted, which were dropped. A future incident — "this defensive null-check got dropped, where was it from originally?" — is answered by the provenance graph, not by re-reading commit messages.

The tracker runs read-mostly. It never mutates source files. It writes structured artifacts and (with strict guardrails) one git note per rationalization-branch commit.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{RATIONALIZATION_BRANCH}` — branch with the keeper commits
- `{APPLY_LOG}` — `<workspace>/apply_log.tsv` (live; gets columns appended)
- `{HARMONIZATION_PLAN}` — `<workspace>/harmonization_plan.md`
- `{NOTES_NAMESPACE}` — default `refs/notes/branch-rationalization-provenance`

## Outputs

- `<workspace>/provenance.json` — schema-versioned graph: per-commit entries with `new_sha`, `subject`, `strategy`, `provenance_method` (∈ `direct-cherry-pick` | `squash-attribution` | `rebase-chain` | `harmonized-attribution` | `split-attribution` | `dirty-archive`), `provenance_confidence`, `source_branches`, `source_commits`, `source_hunk_refs[]` (with `source_bundle_ref`, `intent`), `intents_dropped[]` (for harmonized), `git_notes_written`, plus run-level `summary`.
- **Side effects:** appends `provenance_method`, `provenance_confidence`, `source_commits`, `source_hunk_refs` columns to `apply_log.tsv` (one row per applied keeper). Writes structured JSON-body git notes under `{NOTES_NAMESPACE}` for each rationalization-branch commit IFF no pre-existing notes namespace is detected. Never mutates source files. Never amends commits. Never rewrites commit messages. Never pushes notes (user pushes them with `git push origin {NOTES_NAMESPACE}` if desired). Resume-aware: re-runs only append entries for commits whose `new_sha` isn't already in `provenance.json`.
- **Decision contract:** `provenance.json:summary.notes_skipped_reason` non-null indicates the existing-notes-namespace guardrail tripped (silent-data-loss prevention) — the structured JSON is then the durable record. The handoff-reporter consumes `provenance.json` and surfaces it in `handoff_report.md`'s "Recovered commits" section.

## Workflow

### Phase 8 mode — invoked after each successful keeper-applier commit

The keeper-applier writes the commit and updates `apply_log.tsv`. The provenance tracker is invoked next, before the next keeper-applier iteration.

1. **Identify the new commit.** Read the latest row in `apply_log.tsv` (`new_commit_sha`, `strategy`, `paths_committed`, `source_branches`).

2. **Compute hunk-level provenance.** For each path in `paths_committed`:

   | Strategy | Method |
   |----------|--------|
   | `cherry-pick` (`✧ CHERRY-PICK`) | The new commit's diff against its parent equals (modulo path renames) the source SHA's diff against its parent. Record source-SHA + source-paths + source-hunks 1:1. |
   | `squash-merge` (`⊟ SQUASH-MERGE` — note the `⊟` glyph; `⊞` is reserved for `⊞ RE-FINGERPRINT`) | The squash collapses N source commits; record the per-commit attribution by intersecting the new commit's diff hunks with each source commit's diff hunks. |
   | `rebase-and-merge` (`⊠ REBASE-AND-MERGE`) | Each new commit corresponds 1:1 to a source commit; record the chain. |
   | `harmonized-synthesis` | The harmonization plan named which hunks come from which branch. Read `harmonization_plan.md`'s `proposed_synthesis` for each affected file; map each hunk in the new commit to a source-branch + source-hunk via the plan's intent attribution. Confidence < 1.0 unless the plan was explicit about every line. |
   | `split-commits` (`⇄ SPLIT-COMMITS-HUNKS`) | Per the partial-splitter's record; each hunk maps to a source commit's hunk. |
   | `dirty-worktree-only` | Source = the worktree's bundle capture path (`<bundle>/worktrees/<sanitized-path>/staged.diff` or `unstaged.diff` or `untracked.tar.gz`). |

3. **Append provenance columns to `apply_log.tsv`.** Add (or update) columns:
   - `provenance_method` — one of `direct-cherry-pick`, `squash-attribution`, `rebase-chain`, `harmonized-attribution`, `split-attribution`, `dirty-archive`
   - `provenance_confidence` — 0.0–1.0
   - `source_commits` — comma-separated SHAs (multi-source for harmonized)
   - `source_hunk_refs` — comma-separated `<bundle-path>:<line-range>` citations

4. **Write `git notes` on the new commit** — guardrails first:
   - Read `git -C {PROJECT} config notes.displayRef` and `git -C {PROJECT} config notes.rewriteRef`. If either points at any namespace OR if `git -C {PROJECT} for-each-ref refs/notes/` returns any pre-existing notes ref, halt the notes-write step. Why: clobbering an existing notes namespace is silent data loss; surface to the user instead.
   - If clean, write a structured note to `{NOTES_NAMESPACE}` for the new commit:
     ```bash
     git -C {PROJECT} notes --ref={NOTES_NAMESPACE} add -m "<JSON-body>" <new_commit_sha>
     ```
     The JSON body mirrors the row in `provenance.json`.
   - If a project's existing notes namespace conflicts, record `notes_skipped: <reason>` in `apply_log.tsv` and proceed without writing notes. The structured artifact in `provenance.json` is the durable record; git notes are convenience.

5. **Update the running graph.** Append the new commit's provenance to `<workspace>/provenance.json` (see Phase 11 mode for format).

### Phase 11 mode — final emission for the handoff

After Phase 8 + Phase 8b complete, emit `<workspace>/provenance.json`:

```json
{
  "schema_version": "1.0",
  "rationalization_branch": "{RATIONALIZATION_BRANCH}",
  "rationalization_branch_tip": "<SHA>",
  "canonical_base": "<SHA>",
  "commits": [
    {
      "new_sha": "abc1234",
      "subject": "recover wider grammar from feat/parser-hardening",
      "strategy": "cherry-pick",
      "provenance_method": "direct-cherry-pick",
      "provenance_confidence": 1.0,
      "source_branches": ["feat/parser-hardening"],
      "source_commits": ["aaa1111"],
      "source_hunk_refs": [
        {
          "path": "src/parse.rs",
          "new_lines": "60-95",
          "source_path": "src/parse.rs",
          "source_lines": "60-95",
          "source_bundle_ref": "branches/feat-parser-hardening-aaa111/diff-vs-merge-base.diff:142-187",
          "intent": "refactor"
        }
      ],
      "git_notes_written": true
    },
    {
      "new_sha": "def5678",
      "subject": "harmonize src/redact.rs from agent-cleanup-pass-3 + feature/parse-hardening + wip/null-checks",
      "strategy": "harmonized-synthesis",
      "provenance_method": "harmonized-attribution",
      "provenance_confidence": 0.85,
      "source_branches": ["agent-cleanup-pass-3", "feature/parse-hardening", "wip/null-checks"],
      "source_commits": ["bbb2222", "ccc3333", "ddd4444"],
      "source_hunk_refs": [
        {"path": "src/redact.rs", "new_lines": "142-148", "source_path": "src/redact.rs", "source_lines": "142-148", "source_bundle_ref": "branches/agent-cleanup-pass-3/diff-vs-merge-base.diff:90-100", "intent": "defensive"},
        {"path": "src/redact.rs", "new_lines": "134-134", "source_path": "src/redact.rs", "source_lines": "134-134", "source_bundle_ref": "branches/wip-null-checks/diff-vs-merge-base.diff:55", "intent": "type-narrowing"},
        {"path": "tests/redact_test.rs", "new_lines": "5-25", "source_path": "tests/redact_test.rs", "source_lines": "5-25", "source_bundle_ref": "branches/feature-parse-hardening/diff-vs-merge-base.diff:200-225", "intent": "test"}
      ],
      "intents_dropped": [
        {"source_branch": "feature/parse-hardening", "intent": "defensive", "reason": "superseded by stronger version in agent-cleanup-pass-3"},
        {"source_branch": "agent-cleanup-pass-3", "intent": "type-narrowing-experiment", "reason": "superseded by cleaner approach in wip/null-checks"}
      ],
      "git_notes_written": true
    }
  ],
  "summary": {
    "total_commits": <N>,
    "by_strategy": {"cherry-pick": ..., "harmonized-synthesis": ..., ...},
    "by_provenance_method": {...},
    "mean_confidence": 0.93,
    "git_notes_written_count": <M>,
    "notes_skipped_reason": null
  }
}
```

The handoff-reporter consumes `provenance.json` and surfaces the summary in `handoff_report.md`'s "Recovered commits" section.

## Critical rules

- **Never clobber an existing git-notes namespace.** Detect via `notes.displayRef` / `notes.rewriteRef` config + `for-each-ref refs/notes/`; if any prior notes ref exists, skip notes-write entirely. Why: silent data loss in the user's existing tooling.
- **Provenance confidence is honest.** A harmonized synthesis is ~0.85, not 1.0; a partially-attributed hunk surfaces as 0.5–0.7. Don't inflate.
- **Don't mutate source files.** Provenance is derived from existing artifacts (apply_log + harmonization_plan + bundle diffs + git diff against parent). The tracker reads; it never edits the working tree or rewrites commits.
- **Don't rewrite commit messages.** The keeper-applier and commit-message-author own commit text. The provenance tracker writes notes (additive), never amends.
- **Resume-aware.** On re-invocation, read the existing `provenance.json` and only append rows for commits whose `new_sha` doesn't already appear.
- **Per AGENTS.md "No Script-Based Changes":** never run sed/awk on source files.
- **Per AGENTS.md "Note for Codex/GPT-5.5":** never disturb concurrent agents' working-tree state in any worktree.
- **Per AGENTS.md RULE NUMBER 1:** never delete files without express user permission.
- **Never bypass pre-commit hooks** (no commits in this subagent's own actions; notes are written via `git notes add` which doesn't run hooks).
- **Never run mass-delete primitives.**
- **Never push.** Notes are local; the user pushes them with `git push origin {NOTES_NAMESPACE}` if they want to.
- **Never run `git push --delete` or force-push.**

## Coordination

- File reservation (Phase 8 mode): `paths=["<workspace>/provenance.json", "<workspace>/apply_log.tsv"]`, `exclusive=true`, `reason="branch-rationalization-provenance-<commit-sha>"`, `ttl_seconds=600`.
- Phase 8 mode coordinates with `keeper-applier`: invoked after each keeper's commit; never runs concurrently with the keeper-applier on the same commit.
- Phase 11 mode coordinates with `handoff-reporter`: writes `provenance.json` before `handoff-reporter` reads it.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] Every row in `apply_log.tsv` with `gates_status=passed` has a corresponding entry in `provenance.json`
- [ ] Every harmonized-synthesis entry has `intents_dropped` populated (if any intents were dropped per the harmonization plan)
- [ ] Every `source_hunk_refs[*].source_bundle_ref` resolves to a real file in the bundle
- [ ] `provenance_confidence` is in [0.0, 1.0] for every entry
- [ ] Either every commit has `git_notes_written: true` OR the run-level `notes_skipped_reason` is populated explaining why
- [ ] No existing git-notes namespace was clobbered (verify by re-reading `notes.displayRef` / `notes.rewriteRef` post-run; values match pre-run)

## Exit criteria

`provenance.json` written; `apply_log.tsv` has provenance columns for every applied row; git notes written under `{NOTES_NAMESPACE}` (or skipped with reason recorded). The handoff-reporter consumes the artifact and surfaces it to the user; the user can `git log --notes={NOTES_NAMESPACE}` to see attribution alongside commit messages.
