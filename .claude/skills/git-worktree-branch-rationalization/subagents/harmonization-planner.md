---
name: harmonization-planner
description: Phase 7 — for every file touched by ≥2 non-protected branches with verdict ∈ {novel-and-accretive, partially-novel, divergent-refactor, dirty-worktree-only}, build a per-file variant matrix grouping hunks by intent (defensive, refactor, test, fixture, type-narrowing, error-handling, performance, naming) and propose a best-of-all-worlds synthesis on top of canonical. Writes harmonization_plan.md. USER GATE before Phase 8.
---

# Harmonization Planner

Owns Phase 7. **The conceptual centerpiece of this skill.** A stash is a single diff: pick or drop. Branches collide on the same files in incompatible ways — and the cognitive move that distinguishes this skill from git-stash-janitor is to inspect every variant, identify each part's intent, and synthesize a best-of-all-worlds version on top of canonical's architecture (Axiom 1, ◇ HARMONIZE).

Without this phase, this skill is just stash-janitor with extra steps.

Why an explicit user gate before Phase 8: the synthesis is novel content the skill is proposing to author. The user must see the plan before any mutation happens — which hunks come from which branch, which intents survive, which variants are dropped, what the projected combined result looks like.

## Inputs

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BUNDLE}` — bundle path
- `{CANONICAL}` — canonical branch from `project_profile.json`
- `{TRIAGE}` — `<workspace>/triage.tsv`

## Outputs

- `<workspace>/harmonization_plan.md` — per-file variant matrix (file_path, canonical_version, branch_<slug>_variant per contributor, tests_fixtures_affected, intents_per_variant, proposed_synthesis, confidence, risks), Cross-file invariants section, Risks summary, Open questions for the user. When zero file collisions exist, contains a single line: `# No file-level collisions detected. Harmonization plan is empty; Phase 8 proceeds to direct apply.`
- `<workspace>/phase7_user_authorization.txt` — UTC timestamp + user's verbatim approval text.
- **Side effects:** read-only on canonical, bundle, source branches. Never mutates anything in the working tree. The actual synthesis lands in Phase 8 via the Edit tool.
- **Decision contract:** Phase 8 (keeper-applier) refuses to start without `phase7_user_authorization.txt` present and approved. The plan is the apply blueprint for harmonized-synthesis rows; if user requests edits, the planner re-presents and re-captures authorization.

## Workflow

### 1. Identify colliding-file groups

Scan `triage.tsv` for entries with verdict ∈ {`novel-and-accretive`, `partially-novel`, `divergent-refactor`, `dirty-worktree-only`}. From each entry's `files_touched` list (and the corresponding bundle diff for ground truth), build a `file -> [contributors]` index. Keep only files where `len(contributors) ≥ 2`. These are the harmonization candidates.

If zero files collide, write `harmonization_plan.md` with `# No file-level collisions detected. Harmonization plan is empty; Phase 8 proceeds to direct apply.` and exit successfully.

### 2. Build the per-file variant matrix

For each candidate file, build a row:

| Column | Content |
|--------|---------|
| `file_path` | path on canonical (or path-as-of-merge-base if file was renamed; record the rename in a `rename_history` sub-row) |
| `canonical_version` | key signatures and symbols extracted from `{CANONICAL}:<file>` (read with the Read tool; do NOT use grep alone — extract function signatures, type definitions, public exports) |
| `branch_<slug>_variant` | one column per contributing branch — diff hunks against canonical summarized as `(line N: hunk-purpose-1) (line M: hunk-purpose-2) …` |
| `tests_fixtures_affected` | which tests under `tests/`, `__tests__/`, `*_test.rs`, etc. each variant modifies; which fixtures (snapshots, golden files, JSON) are touched |
| `intents_per_variant` | classification of each hunk into: `defensive` (null check, bounds check, retry), `refactor` (extract function, rename), `test` (new test or modified assertion), `fixture` (snapshot/golden/json), `type-narrowing` (Optional → required, generic → specific), `error-handling` (try/catch, Result wrapping, sentinel propagation), `performance` (caching, batching, hoisting), `naming` (rename without behavior change) |
| `proposed_synthesis` | the plan: which hunks to keep, which to merge, which to drop. Plain English: "take canonical's structure; add the defensive null-check from agent-cleanup-pass-3 (introduced at line 142 there); replace canonical's `parse` with feature/parse-hardening's wider-grammar version (lines 60–95 there) but keep canonical's error-message phrasing; add wip/null-checks's type-narrowing on the return type" |
| `confidence` | 0.0–1.0; <0.7 surfaces in MANUAL section |
| `risks` | identified risks: "two variants both rename `redact` → `redact_secrets` but with different parameter orders — must pick one", "feature/X's defensive check assumes a struct field that doesn't exist on canonical's struct — needs adaptation", "test coverage drops if branch B's deleted assertion isn't replaced" |

### 3. Group variants by intent

Within each row, identify the strongest example of each intent across all variants. Why: the synthesis preserves *one* defensive null-check (the strongest), *one* refactor (the cleanest), *one* type-narrowing (the safest), etc. — not all of them. Multiple variants attempting the same intent is the most common collision pattern in agent-swarm aftermath.

**Worked example, paste verbatim into the plan when relevant:**

> File: `src/redact.rs`
> - `agent-cleanup-pass-3` adds defensive null-check at the top of `redact_secrets` (lines 142–148): the strongest defensive variant — handles the empty-string case canonical misses.
> - `feature/parse-hardening` adds parser-fixture coverage in tests (lines 5–25 of `tests/redact_test.rs`): the strongest test variant — covers a regex backtrack edge canonical's tests miss.
> - `wip/null-checks` adds type-narrowing on the return type from `String` → `Result<String, RedactError>` (line 134 of `src/redact.rs`): the strongest type-narrowing variant — propagates errors instead of silently returning empty.
> - **Synthesis**: keep canonical's structure. Add defensive null-check from agent-cleanup-pass-3. Adopt return-type narrowing from wip/null-checks (and update callers, which both `feature/parse-hardening` and canonical already partially do — list each call site). Adopt parser-fixture from feature/parse-hardening. Drop the redundant defensive checks from feature/parse-hardening (covered by agent-cleanup-pass-3's stronger version) and the redundant type-narrowing experiments from agent-cleanup-pass-3 (superseded by wip/null-checks's cleaner approach).

This is the language that goes into the keeper-applier's commit message in Phase 8 ("recover defensive null-check from agent-cleanup-pass-3 + parser-fixture from feature/parse-hardening + type-narrowing from wip/null-checks, harmonized on top of canonical's current structure").

### 4. Write `harmonization_plan.md`

Structure:

```markdown
# Harmonization Plan

Canonical: <name> @ <SHA>
Generated: <UTC timestamp>
Files-with-collisions: <count>

## Summary

<one paragraph: how many files, how many variants, the dominant intent groups>

## File: src/redact.rs

(variant matrix as above)

## File: src/parse.rs

...

## Cross-file invariants to preserve

<callouts: "if redact.rs returns Result, all callers in src/main.rs and src/api.rs must be updated; agent-cleanup-pass-3 already updates src/main.rs's caller but not src/api.rs's; the synthesis must update both">

## Risks summary

<the union of all per-file `risks`, deduped, sorted by severity>

## Open questions for the user

<things the planner couldn't resolve and needs user input on, e.g., "two variants disagree on parameter order; which is canonical?">
```

### 5. Present to user, wait for review

Print the plan path. Tell the user: "I've written the harmonization plan to `<path>`. Please review it. Phase 8 (apply) will not start until you approve the plan or request specific edits to it."

Capture user response into `<workspace>/phase7_user_authorization.txt` with UTC timestamp + the user's verbatim approval text. If the user requests edits ("for src/redact.rs, take the type-narrowing from agent-cleanup-pass-3 instead of wip/null-checks"), update the plan accordingly and re-present.

## Critical rules

- **No mutations of any kind in this phase.** Read-only on canonical. Read-only on bundle. Only writes to `<workspace>/harmonization_plan.md` and `<workspace>/phase7_user_authorization.txt`.
- **Cite specific source branches and line numbers.** Polish Bar: harmonization fidelity requires every entry to cite source branches and explain *why* the combination beats any single variant.
- **Group by intent, not by branch.** A file with three branches all attempting "defensive null-check" should produce *one* defensive synthesis, not three stacked checks.
- **Surface unresolved tensions.** If two variants are genuinely incompatible (different parameter orders, mutually-exclusive type signatures), put it in "Open questions for the user" — don't silently pick one.
- **Read each variant's actual hunks, don't just summarize from `files_touched`.** The variant matrix needs ground-truth content from `<bundle>/branches/<slug>/diff-vs-merge-base.diff` (and worktree dirty diffs for `dirty-worktree-only` rows).
- **Never bypass pre-commit hooks** (no commits in this phase).
- **Never use sed/awk on source files.** All synthesis is described in plain English in the plan; the actual mutation happens in Phase 8 via the Edit tool.
- **Never disturb concurrent agents' working-tree state.** Reading dirty diffs from the bundle is safe; running anything inside another worktree is forbidden in this phase.
- **Never delete files without express user permission.**
- **Never run mass-delete primitives.**

## Coordination

- File reservation: `paths=[".worktree_branch_rationalization_workspace/harmonization_plan.md", ".worktree_branch_rationalization_workspace/phase7_user_authorization.txt"]`, `exclusive=true`, `reason="branch-rationalization-phase7"`.
- Thread id: `branch-rationalization-<run-id>`.

## Quality gates

- [ ] Every file with ≥2 contributing branches in `triage.tsv` has a row in `harmonization_plan.md`
- [ ] Every row's variants are sourced from concrete hunks in the bundle (not summarized from `files_touched`)
- [ ] Every row groups hunks by intent and proposes a single synthesis
- [ ] Every row cites source branches by slug and line ranges
- [ ] `phase7_user_authorization.txt` exists with explicit user approval

## Exit criteria

`harmonization_plan.md` exists; user has approved the plan (or last-edited revision of it); main agent proceeds to Phase 8 with the plan as the apply blueprint for files-with-collisions.
