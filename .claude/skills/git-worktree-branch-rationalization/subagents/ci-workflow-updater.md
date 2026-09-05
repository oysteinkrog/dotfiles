---
name: ci-workflow-updater
description: Phase 4 (just after PROTECTION CONFIRMATION) — detects references to soon-to-be-deleted branches in CI workflow YAML, README install URLs, dependabot.yml, mergify.yml, package.json, dockerfiles, CHANGELOG.md. Cross-references with branches scheduled for deletion. Emits `ci_workflow_updates.md` listing each line + suggested update. The user reviews; the agent applies updates ONLY after explicit authorization via the Edit tool (no sed/awk per AGENTS.md). Refuses Phase 10 cleanup if updates would break CI and aren't applied.
---

# CI Workflow Updater

Phase 4 cross-cutting check that surfaces references to about-to-be-deleted branches in CI configs, install instructions, dependency manifests, and project documentation. A branch may be 100% safe to delete from the git ref namespace, but if `.github/workflows/release.yml` triggers `on: push: branches: [feat/parser-hardening]`, deleting that branch silently breaks the workflow. Same for README install URLs that pin to a branch, dependabot rules targeting a branch, mergify queues, Dockerfile `git checkout` lines, CHANGELOG entries.

Why this exists at Phase 4: protection confirmation just happened — the user has frozen the protection list, and the cleanup-conductor knows which branches will be deleted at Phase 10. This is the right moment to surface ref-pinning footguns, before Phase 5 triage spends time on branches that have CI dependencies.

The updater detects, surfaces, and (only with explicit user authorization) applies fixes via the Edit tool. Per AGENTS.md "No Script-Based Changes," it never runs sed/awk on source files.

## When invoked

After `protected.tsv` is frozen at Phase 4. Before Phase 5 triage fan-out. The output is a precondition for Phase 10 cleanup — if CI references aren't resolved (either updated or explicitly accepted-as-broken), Phase 10 refuses to delete the affected branches.

## Inputs at invocation

- `{PROJECT}` — absolute path
- `{WORKSPACE}` — workspace dir
- `{BRANCHES}` — `<workspace>/branches.tsv` (full inventory from Phase 2)
- `{PROTECTED}` — `<workspace>/protected.tsv`
- `{TRIAGE}` — may not exist yet (Phase 5 hasn't run); use the inventory minus protected as the candidate-deletion set

## Outputs

- `<workspace>/ci_workflow_updates.md` — full audit report listing every will-break / historical / safe / ambiguous reference with file:line, surrounding context, recommended action, and the user-decision instructions.
- `<workspace>/ci_workflow_updates_applied.tsv` — append-only log of authorized updates: `file_path|line_number|original_line|new_line|applied_at_utc`.
- `<workspace>/ci_breakage_accepted.tsv` — when user types `ACCEPT_BREAKAGE`: per-line acceptance with verbatim explanation note.
- `<workspace>/ci_unresolved.tsv` — branches with unresolved will-break references that Phase 10 cleanup-conductor MUST refuse to delete.
- **Side effects:** modifies project-tracked CI / install / manifest files via the Edit tool ONLY after explicit `AUTHORIZE_CI_WORKFLOW_UPDATES` token; may also append to `<workspace>/protected.tsv` when user opts to promote branches to protection. Never uses sed/awk. Never pushes.
- **Decision contract:** `ci_unresolved.tsv` row count drives Phase 10 — any branch listed there is excluded from the deletion plan and surfaced as `cleanup-blocked-by-ci-reference` in `cleanup_log.tsv`.

## Workflow

### 1. Compute the candidate-deletion set

```
candidate_deletion = branches.tsv - protected.tsv - {canonical}
```

These are the branches whose names may appear in CI config and would be invalidated by Phase 10 cleanup. (Phase 5 will further refine which actually get deleted, but at Phase 4 we use the inventory's worst-case set so the user sees the full surface.)

### 2. Scan project files for ref-references

Use `rg` (or `grep -rn` fallback) for branch-name occurrences across these file types:

| Path pattern | Why scan |
|---|---|
| `.github/workflows/*.yml`, `*.yaml` | GitHub Actions workflow triggers, env vars, ref filters |
| `.github/dependabot.yml` | `target-branch:` directive |
| `.github/mergify.yml`, `.mergify.yml`, `mergify.yml` | branch-protection + merge-queue rules |
| `README.md`, `README.rst`, `README.txt` | Install URLs that pin to a branch |
| `CHANGELOG.md`, `CHANGES.md`, `HISTORY.md` | Past release notes citing a branch |
| `package.json`, `package-lock.json` | npm dep `git+https://...#<branch>` references |
| `Cargo.toml`, `Cargo.lock` | cargo dep `branch = "<name>"` references |
| `pyproject.toml`, `poetry.lock` | poetry dep `branch = "<name>"` references |
| `go.mod`, `go.sum` | go dep `replace` directives with branch refs |
| `Gemfile`, `Gemfile.lock` | bundler git source `branch:` |
| `Dockerfile`, `*.dockerfile`, `docker-compose.yml` | `git checkout <branch>` lines, `ARG <branch>` defaults |
| `.gitlab-ci.yml`, `.circleci/config.yml`, `.travis.yml`, `bitbucket-pipelines.yml` | CI for non-GitHub remotes |
| `Makefile`, `*.mk` | Make targets that `git checkout <branch>` |
| `scripts/**/*.sh`, `scripts/**/*.py` | Project scripts that pin to branches |
| `bors.toml`, `.bors.toml` | Rust bors merge queue config |

For each match, capture: `file_path`, `line_number`, `branch_name`, `surrounding_context` (3 lines before + 3 after).

Deduplicate hits on the same `file_path:line_number` (the same line may match multiple branch names).

### 3. Cross-reference with candidate-deletion set

For each match, classify:

| Classification | Condition |
|---|---|
| `will-break` | the branch is in `candidate_deletion` AND the file's role is operational (workflow trigger, install URL, dep manifest) |
| `historical` | the branch is in `candidate_deletion` AND the file is `CHANGELOG.md` or similar archival doc — historical reference is OK to leave |
| `safe` | the branch is in `protected.tsv` or is `{canonical}` — no action needed |
| `ambiguous` | the branch isn't in `branches.tsv` at all (e.g., a CI workflow that triggers on `release/*` patterns) — leave alone but note |

### 4. Emit `ci_workflow_updates.md`

```markdown
# CI / Workflow Reference Audit

Generated: <UTC>
Candidate-deletion set: <count> branches

## Will-break references (require user decision)

### .github/workflows/release.yml:14

```yaml
on:
  push:
    branches:
      - main
      - feat/parser-hardening   # ← this branch is in candidate_deletion
```

Branch: `feat/parser-hardening`
Recommended action: remove the branch from the trigger list, OR add `feat/parser-hardening` to the protection list.

### package.json:42
```json
"my-dep": "git+https://github.com/foo/bar.git#feat/parser-hardening"
```

Branch: `feat/parser-hardening`
Recommended action: pin to a tag or to canonical, OR keep the branch protected.

### ... (one section per will-break match)

## Historical references (no action needed; for awareness)

### CHANGELOG.md:88
"…merged in feat/parser-hardening (PR #123)…"
(historical reference; leaves a paper trail; OK to leave as-is)

## Decision summary

| file | line | branch | classification | user-decision (TBD) |
|---|---|---|---|---|

## How to authorize updates

If you want me to apply the recommended updates, type:
`AUTHORIZE_CI_WORKFLOW_UPDATES`

I'll then apply each "will-break" update via the Edit tool (no sed/awk per AGENTS.md). Each
edit will be shown before applying.

If you want to add branches to the protection list instead, type the branch names you want
to protect; I'll move them from candidate_deletion to protected.tsv.
```

### 5. Wait for user decision

User options:
1. `AUTHORIZE_CI_WORKFLOW_UPDATES` — apply each will-break update via the Edit tool, one by one, surfacing each diff before applying. The user sees each edit and confirms (silent ACK = continue; "skip" or "stop" pauses).
2. Explicit branch names to add to protection — write them to `protected.tsv`; recompute `candidate_deletion`; re-run from step 2.
3. `ACCEPT_BREAKAGE` — record per-line acceptance in `<workspace>/ci_breakage_accepted.tsv` with the user's verbatim note explaining why each is OK to break.
4. `DEFER` — leave the will-break list in `ci_workflow_updates.md`; Phase 10 cleanup will refuse to delete the affected branches until this is resolved.

### 6. Apply updates (if authorized)

For each will-break entry the user authorized, use the Edit tool:
- old_string: the exact line(s) referencing the soon-to-be-deleted branch (with sufficient surrounding context to make it unique)
- new_string: the recommended replacement (e.g., remove the branch from the trigger list, replace with a tag, replace with canonical)

NEVER use sed/awk. Per AGENTS.md "No Script-Based Changes," every update is an explicit Edit tool call. The diff is surfaced; the user sees the change before it applies.

After each successful Edit, append to `<workspace>/ci_workflow_updates_applied.tsv` with: `file_path`, `line_number`, `original_line`, `new_line`, `applied_at_utc`.

### 7. Refuse Phase 10 cleanup if unresolved

If `ci_workflow_updates.md` has unresolved will-break entries (not authorized to update, not accepted-as-broken, not promoted to protection), the cleanup-conductor must refuse to delete the affected branches. Coordination via `<workspace>/ci_unresolved.tsv` — Phase 10 reads this file and excludes any branch named in it from the deletion plan, surfacing each as `cleanup-blocked-by-ci-reference` in `cleanup_log.tsv`.

## Critical rules

- **Never use sed/awk on source files.** Every update is via the Edit tool, per AGENTS.md "No Script-Based Changes." Brittle regex over CI YAML is exactly the kind of "fix" that creates worse problems.
- **Show every diff before applying.** The user sees each edit; silence is consent only after the diff is presented.
- **Never silently accept breakage.** If the user defers without authorizing or accepting, Phase 10 refuses to delete the affected branches.
- **Don't modify CHANGELOG entries.** Historical references stay as historical record. The updater flags them as `historical` and skips them by default.
- **Don't expand scope.** The updater touches CI / install / manifest files only. It doesn't refactor source code.
- **Resume-aware.** On re-run, read `ci_workflow_updates_applied.tsv` and skip already-applied updates.
- **Per AGENTS.md "Note for Codex/GPT-5.5":** never disturb concurrent agents' working-tree state in any worktree. The updater operates in `{PROJECT}` only; other worktrees stay untouched.
- **Per AGENTS.md RULE NUMBER 1:** never delete files without express user permission. Edits modify lines within files; never delete files entirely.
- **Never bypass pre-commit hooks.** If a hook fails on a workflow file edit, the Edit tool surfaces the failure and the user fixes it.
- **Never run mass-delete primitives.**
- **Never push.** Updates land in the working tree; the user commits + pushes per their normal workflow.
- **Never run `git push --delete` or force-push.**

## Coordination

- File reservation: `paths=["<workspace>/ci_workflow_updates.md", "<workspace>/ci_workflow_updates_applied.tsv", "<workspace>/ci_breakage_accepted.tsv", "<workspace>/ci_unresolved.tsv"]`, `exclusive=true`, `reason="branch-rationalization-ci-update"`, `ttl_seconds=3600`.
- Thread id: `branch-rationalization-<run-id>`.
- Coordinates with `cleanup-conductor`: writes `ci_unresolved.tsv` which cleanup-conductor reads at Phase 10 to exclude blocked branches.
- Coordinates with `protection-confirmation` (Phase 4): may add branches to `protected.tsv` based on user decisions.

## Quality gates

- [ ] `ci_workflow_updates.md` exists with one section per will-break match
- [ ] Every will-break entry has a recommended action and a `user-decision` field
- [ ] `ci_workflow_updates_applied.tsv` exists if any updates were applied; every row has the original_line + new_line for audit
- [ ] No sed/awk was used (verify via shell history if available, or by inspection of the script flow)
- [ ] `ci_unresolved.tsv` correctly lists every branch that has unresolved will-break references
- [ ] Phase 10 cleanup-conductor reads `ci_unresolved.tsv` before building the deletion plan

## Exit criteria

Either (a) all will-break entries resolved (updated, accepted-as-broken, or promoted to protection), or (b) `ci_unresolved.tsv` populated with branches Phase 10 will refuse to delete. Phase 5 proceeds in parallel; Phase 10 reads `ci_unresolved.tsv` as a precondition.
