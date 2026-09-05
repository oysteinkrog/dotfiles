# CI Workflow Awareness — Updating CI YAML When Canonical Branches Change

When a branch is deleted in Phase 10, anything that **references** that branch by name breaks: GitHub Actions workflow YAML, GitLab CI YAML, Jenkinsfiles, README install URLs, dependabot config, dockerfile branch references, mergify rules. This file is the discovery + update workflow.

Cass-mined source session: a real run that deleted `master` (because it was redundant with `main`) broke the CI workflow because `.github/workflows/ci.yml` still triggered on `branches: [master, main]`. The README's curl-pipe-bash install URL also referenced `master/install.sh`. Both broke silently — the next push to `main` ran fine, but PRs targeting `master` (which no longer existed) failed mysteriously.

> **The premise.** Deleting a branch isn't just `git branch -d`. It's a graph operation that touches every file referencing the branch by name. The skill's job is to **discover every reference**, **propose every update**, and **refuse the deletion** until references are reconciled.

---

## 1. The problem

A user has two canonical-shaped branches: `master` (the old name) and `main` (the new name). They've decided `main` is the real canonical and `master` is redundant. Phase 5 triage classifies `master` as `superseded`. Phase 10 prepares to delete `master`.

What still references `master`?

| Reference type | Example file | What breaks |
|---|---|---|
| GitHub Actions trigger | `.github/workflows/ci.yml` `on: push: branches: [master, main]` | CI no longer triggers on `master` (because the ref is gone), but worse, agents looking for the trigger get confused |
| GitLab CI rules | `.gitlab-ci.yml` `only: [master]` | The pipeline rule never matches |
| README install URL | `README.md` `curl https://raw.githubusercontent.com/owner/repo/master/install.sh` | 404; users hitting the URL get errors |
| package.json repository | `"repository": "https://github.com/owner/repo/tree/master"` | npm/cargo metadata points to a dead URL |
| Dependabot config | `.github/dependabot.yml` `target-branch: master` | Dependabot opens PRs against a non-existent branch |
| Mergify rules | `.mergify.yml` `base: master` | Merge automation never matches |
| Dockerfile | `FROM ghcr.io/owner/repo:master` (image tag derived from branch) | Image pull fails |
| GitHub Actions matrix | `branch: [master, main, develop]` | matrix job fails for the deleted branch |
| Jenkinsfile | `branch: 'master'` in pipeline definition | Job fails to checkout |
| CHANGELOG.md | "fixed in [master @ abc123]" | Hyperlink goes to a 404 |
| GitHub branch protection | `master` branch protection rule | Stale rule (harmless but messy) |
| Webhooks / bots that filter by branch | external systems | varies |

The skill **discovers every one of these** at Phase 4 (PROTECTION CONFIRMATION) and **refuses Phase 10 cleanup** of any branch whose deletion would break references that haven't been reconciled.

---

## 2. Detection at Phase 4

After Phase 4 produces `protected.tsv` (the confirmed protection list) and the cleanup plan is taking shape, `scripts/ci-workflow-discovery.sh` runs:

### 2.1 Discovery patterns

```bash
# Per branch scheduled for deletion (read from triage.tsv where verdict ∈ {superseded, garbage, already-merged} AND the branch is NOT in protected.tsv):
deletion_candidates=$(awk -F'\t' '$3=="superseded" || $3=="garbage" || $3=="already-merged" {print $2}' "$WS/triage.tsv" \
    | grep -vFxf <(awk -F'\t' '{print $2}' "$WS/protected.tsv"))

for branch in $deletion_candidates; do
    # 1. GitHub Actions workflows:
    rg -n -F "$branch" "$PROJECT/.github/workflows/" 2>/dev/null > "$WS/ci_refs/$branch.gh_actions.tsv"

    # 2. GitLab CI:
    [ -f "$PROJECT/.gitlab-ci.yml" ] && rg -n -F "$branch" "$PROJECT/.gitlab-ci.yml" >> "$WS/ci_refs/$branch.gitlab.tsv"

    # 3. Jenkinsfile / Jenkinsfiles:
    rg -n -F -t jenkins "$branch" "$PROJECT/" >> "$WS/ci_refs/$branch.jenkins.tsv" 2>/dev/null

    # 4. CircleCI:
    [ -f "$PROJECT/.circleci/config.yml" ] && rg -n -F "$branch" "$PROJECT/.circleci/config.yml" >> "$WS/ci_refs/$branch.circle.tsv"

    # 5. README and docs:
    rg -n -F "$branch" "$PROJECT/" -g 'README*' -g 'docs/**' -g 'CHANGELOG*' >> "$WS/ci_refs/$branch.docs.tsv"

    # 6. Package metadata:
    rg -n -F "$branch" "$PROJECT/" -g 'package.json' -g 'Cargo.toml' -g 'pyproject.toml' -g 'go.mod' >> "$WS/ci_refs/$branch.pkg.tsv"

    # 7. Dependabot / renovate:
    rg -n -F "$branch" "$PROJECT/.github/dependabot.yml" "$PROJECT/.github/renovate.json" "$PROJECT/renovate.json" >> "$WS/ci_refs/$branch.deps.tsv" 2>/dev/null

    # 8. Mergify:
    [ -f "$PROJECT/.mergify.yml" ] && rg -n -F "$branch" "$PROJECT/.mergify.yml" >> "$WS/ci_refs/$branch.mergify.tsv"

    # 9. Dockerfile:
    rg -n -F "$branch" "$PROJECT/" -g 'Dockerfile*' >> "$WS/ci_refs/$branch.docker.tsv"

    # 10. Generic catch-all (in case the above missed something):
    rg -n -F "$branch" "$PROJECT/" --type-not git --type-not lock >> "$WS/ci_refs/$branch.other.tsv"
done
```

The output is a per-branch directory of TSVs:

```
<workspace>/ci_refs/
├── master/
│   ├── gh_actions.tsv      .github/workflows/ci.yml:7    branches: [master, main]
│   ├── docs.tsv            README.md:142                 curl https://.../master/install.sh
│   ├── pkg.tsv             package.json:8                 "repository": ".../tree/master"
│   ├── deps.tsv            (empty)
│   ├── mergify.tsv         (empty)
│   ├── docker.tsv          (empty)
│   └── other.tsv           (empty)
└── feature-old-name/
    └── ...
```

> **Why fixed-string match (`rg -F`)?** Branch names with regex-special characters (`feature/redact-secrets` has `/`, `release/2.x` has `.`, `bugfix-#123` has `#`) need fixed-string matching. `rg -F` is faster than `rg` with escaping, and avoids accidental over-matching.

### 2.2 False-positive filtering

Some matches are false positives:

| Match | Likely false positive | Filter |
|---|---|---|
| `master` in a branch name like `master-key-rotation` | The match is part of a longer name | Use `rg -w` (word boundaries) for short branch names |
| `master` in a comment like `// previously called master` | Documentation, not a live reference | Surface but mark as "doc-only" — user decides |
| `main` in `_main.rs` or `main.go` | Code identifier, not branch reference | Use `rg -F` with line-context inspection |

The skill's `ci-workflow-discovery.sh` post-processes with these filters and emits a **confidence column**:

```
file:line  match_text  confidence
.github/workflows/ci.yml:7  branches: [master, main]  high
README.md:142  master/install.sh  high
src/main.rs:1  fn main() {  none (filtered out)
```

Only `confidence: high` rows feed the update plan.

---

## 3. Update strategy

For each branch with at least one `confidence: high` reference, `ci-workflow-discovery.sh` emits an update proposal at `<workspace>/ci_workflow_updates.md`:

```markdown
# CI Workflow Updates Required

Generated: 2026-05-07T15:08:32Z
Branches with breaking references: 1

## Branch: `master` (scheduled for deletion as `superseded`)

References found: 4

### .github/workflows/ci.yml:7

  Current:  on: push: branches: [master, main]
  Proposed: on: push: branches: [main]
  Diff:
    -  branches: [master, main]
    +  branches: [main]
  Why: master is being deleted; remove its trigger; main remains the canonical

### .github/workflows/release.yml:23

  Current:  if: github.ref == 'refs/heads/master'
  Proposed: if: github.ref == 'refs/heads/main'
  Diff:
    -  if: github.ref == 'refs/heads/master'
    +  if: github.ref == 'refs/heads/main'

### README.md:142

  Current:  curl -fsSL https://raw.githubusercontent.com/owner/repo/master/install.sh | bash
  Proposed: curl -fsSL https://raw.githubusercontent.com/owner/repo/main/install.sh | bash
  Diff:
    -  curl -fsSL https://raw.githubusercontent.com/owner/repo/master/install.sh | bash
    +  curl -fsSL https://raw.githubusercontent.com/owner/repo/main/install.sh | bash

### package.json:8

  Current:  "repository": "https://github.com/owner/repo/tree/master"
  Proposed: "repository": "https://github.com/owner/repo/tree/main"
  Diff:
    -  "repository": "https://github.com/owner/repo/tree/master"
    +  "repository": "https://github.com/owner/repo/tree/main"

## Authorization required

The skill will apply these updates ONLY after explicit user authorization per AGENTS.md
"Mandatory explicit plan". To authorize, type:

  yes I understand and want to apply 4 CI workflow updates for branch master per ci_workflow_updates.md

The updates will be applied via the Edit tool (NOT a script — per AGENTS.md "No Script-Based Changes").
After applying, the skill will commit the updates with message:
  "ci: update branch references for branch-rationalization 2026-05-07 (master → main)"

If you decline, Phase 10 cleanup will REFUSE to delete branch master.
```

> **Why apply via Edit and not sed?** Per AGENTS.md "No Script-Based Changes": "NEVER run a script that processes/changes code files in this repo. Brittle regex-based transformations create far more problems than they solve. Always make code changes manually." Each update goes through the Edit tool one match at a time, with the agent reading the surrounding context to verify the change is correct.

---

## 4. Refusal mode

Phase 10 cleanup is **blocked** for any branch whose deletion would leave broken references that haven't been reconciled.

### 4.1 The check

```bash
# In scripts/drop-retire-confirmed.sh, before each branch deletion:
branch="$1"
ci_refs_file="$WS/ci_refs/$branch"
if [ -d "$ci_refs_file" ] && [ "$(ls -A "$ci_refs_file"/*.tsv 2>/dev/null | xargs cat | grep -c high)" -gt 0 ]; then
    # Check the user authorized the updates:
    if ! grep -q "yes I understand and want to apply.*CI workflow updates for branch $branch" "$WS/cleanup_authorization.txt"; then
        echo "REFUSED: branch $branch has unresolved CI workflow references; see ci_workflow_updates.md"
        exit 1
    fi
fi
```

### 4.2 Bypass: user explicitly excludes a file

A user may want to delete the branch even though a file references it (e.g., a generated file the user doesn't care about, or a file the user maintains separately). In that case the user adds the file to `<workspace>/ci_refs_excluded.tsv`:

```
file:line  reason
auto-generated-docs.md:42  generated; rebuilt on deploy
legacy-CHANGELOG.md:1027  historical reference; intentional
```

Refuses to add: any file that the skill would itself need to modify (the workspace + the workflow YAML + active CI files). The exclusion list is for **truly generated** or **truly historical** content that the user can't or won't change.

```bash
# In ci-workflow-discovery.sh:
if [ -f "$WS/ci_refs_excluded.tsv" ]; then
    excluded_count=$(grep -cF "$file:$line" "$WS/ci_refs_excluded.tsv")
    [ "$excluded_count" -gt 0 ] && continue   # skip this match
fi
```

### 4.3 If the user maintains the file separately

Some files are maintained by external tooling (e.g., a renovate.json that's auto-generated by Renovate, or a CHANGELOG that's bumped by release-please). Updating these in-place would be overwritten by the next tool run.

The skill **detects** these via project_profile.json:

```json
{
    "ci_workflow_externally_managed": [
        ".github/dependabot.yml",
        "renovate.json",
        "CHANGELOG.md"
    ]
}
```

For files in this list, the skill **doesn't propose an update** but **does include a callout** in `ci_workflow_updates.md`:

```markdown
## Externally Managed Files (no update proposed)

The following files reference branches scheduled for deletion, but they're externally managed
(per project_profile.json:ci_workflow_externally_managed). The skill does not propose updates
for these files. The user should:
  - Configure the external tool to use the new branch name
  - Or accept that these files will be inconsistent until the next external regen

| File | Line | Match | External tool | Suggested action |
|---|---|---|---|---|
| .github/dependabot.yml | 7 | target-branch: master | Dependabot | Update Dependabot config to target main; the file will regenerate on next sync |
| CHANGELOG.md | 142 | [master](https://...) | release-please | Wait for next release; release-please will rebuild the changelog with the new branch name |
```

---

## 5. Application — apply via Edit only

After user authorization, the skill applies updates via the Edit tool, **one match at a time**:

```
For each row in ci_workflow_updates.md:
  1. Read the file (Read tool)
  2. Verify the current text matches expectation
  3. Apply Edit with old_string and new_string from the proposal
  4. Verify the file's hash changed
  5. Re-run any project-specific validators (e.g., yamllint on YAML files)
  6. If the file passes, continue; if not, halt and surface
```

After all updates land, the skill commits them:

```bash
git add <each-updated-file>
git commit -m "ci: update branch references for branch-rationalization-$DATE

Branches affected:
  - master (scheduled for deletion in Phase 10 as superseded by main)

Files updated (4):
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - README.md
  - package.json

Authorization: see <workspace>/cleanup_authorization.txt
Beads-Issue: $RUN_ID"
```

> **Why a separate commit and not bundled with Phase 10?** The CI workflow update is a normal code change with normal review needs. Bundling it with the rationalization-branch tip would obscure it. A separate commit on the rationalization branch (or on canonical, if the user explicitly directs) makes the change reviewable and auditable.

---

## 6. Beyond CI workflows — full reference catalog

The discovery covers more than CI:

### 6.1 Code references

```bash
# Branch names mentioned in source code (rare but happens — e.g., a Python script that
# does subprocess.run(["git", "checkout", "master"])):
rg -n -F "$branch" "$PROJECT/" -t py -t rs -t js -t ts -t go -t sh > "$WS/ci_refs/$branch.code.tsv"
```

These are usually high-priority — code references break runtime behavior, not just CI.

### 6.2 Submodule pointers

```bash
# Submodules can pin to a branch via .gitmodules:
[ -f "$PROJECT/.gitmodules" ] && rg -n -F "$branch" "$PROJECT/.gitmodules" >> "$WS/ci_refs/$branch.submod.tsv"
```

### 6.3 GitHub Actions workflow_dispatch defaults

```bash
# workflow_dispatch inputs sometimes default to a branch name:
rg -n -B 5 "default: $branch" "$PROJECT/.github/workflows/" >> "$WS/ci_refs/$branch.gh_dispatch.tsv"
```

### 6.4 Branch protection rules

Via `gh api`:
```bash
if command -v gh >/dev/null && [ -f "$WS/github_state.json" ]; then
    if jq -e --arg b "$branch" '.branch_protection_rules[] | select(.branch == $b)' "$WS/github_state.json" >/dev/null; then
        echo "branch protection rule exists for $branch (will become stale on deletion)" >> "$WS/ci_refs/$branch.gh_protection.tsv"
    fi
fi
```

The skill **never modifies branch protection rules** (per Axiom 15: "remote cleanup out of scope"). It surfaces the stale rule so the user can clean it up manually.

---

## 7. Cumulative reference report

The full reference catalog for the run is rolled up into `ci_workflow_updates.md` as a summary:

```markdown
## Summary

| Branch | References | Updates proposed | Externally-managed | Excluded |
|---|---|---|---|---|
| master | 6 | 4 | 1 (CHANGELOG.md) | 1 (auto-generated-docs.md) |
| feature-old-name | 0 | 0 | 0 | 0 |
| agent-noop-pass-3 | 1 | 1 | 0 | 0 |

Total updates the user must authorize: 5

Branches that will REFUSE deletion if updates are not authorized:
  - master  (4 active references)
  - agent-noop-pass-3  (1 active reference: stale comment in src/utils.rs:142 that says "agent-noop-pass-3 introduced this")
```

---

## 8. Worked example — the cass-mined session

The motivating session: deleting `master` broke `.github/workflows/ci.yml` and `README.md`'s install URL.

```markdown
# CI Workflow Updates Required

Generated: 2026-05-07T15:08:32Z

## Branch: `master`

### .github/workflows/ci.yml:7

  Current:  on:
              push:
                branches: [master, main]
  Proposed: on:
              push:
                branches: [main]
  Why: master being deleted; the workflow should only trigger on main from now on

### README.md:142

  Current:  curl -fsSL https://raw.githubusercontent.com/owner/repo/master/install.sh | bash
  Proposed: curl -fsSL https://raw.githubusercontent.com/owner/repo/main/install.sh | bash
  Why: master being deleted; the install URL must point at main

## Authorization required

  yes I understand and want to apply 2 CI workflow updates for branch master per ci_workflow_updates.md
```

The user types the authorization phrase. The skill applies via Edit:

1. Edit `.github/workflows/ci.yml`: `branches: [master, main]` → `branches: [main]`
2. Edit `README.md`: `master/install.sh` → `main/install.sh`

Commits the changes:

```
ci: update branch references for branch-rationalization-2026-05-07 (master → main)

Branches affected:
  - master (scheduled for deletion in Phase 10 as superseded by main)

Files updated:
  - .github/workflows/ci.yml
  - README.md

Authorization: see <workspace>/cleanup_authorization.txt
Beads-Issue: beads-1234
```

Phase 10 cleanup of `master` now proceeds.

---

## 9. Cross-links

- [PHASES.md § Phase 4 PROTECTION CONFIRMATION](PHASES.md) — where CI discovery slots in
- [PHASES.md § Phase 10 DESTRUCTIVE CLEANUP](PHASES.md) — where the refusal gate enforces
- [ANTI-PATTERNS.md](ANTI-PATTERNS.md) — anti-pattern: deleting branches without checking references
- [DRY-RUN-MODE.md § 3.6 CI workflow callouts](DRY-RUN-MODE.md) — dry-run surfaces these BEFORE the run
- [REMOTE-AS-WORKTREE-FOOTGUN.md](REMOTE-AS-WORKTREE-FOOTGUN.md) — sibling footgun: remote URLs that point at local paths
- [INTEGRATION.md § GitHub PR awareness](INTEGRATION.md) — Phase 0.5 captures `github_state.json` which feeds branch-protection-rule detection
- [AGENTS.md "Mandatory explicit plan"](../../../../AGENTS.md) — verbatim auth required for the apply
- [AGENTS.md "No Script-Based Changes"](../../../../AGENTS.md) — apply via Edit, not sed
- [AGENTS.md Axiom 15](../../../../AGENTS.md) — remote cleanup out of scope (we don't modify branch protection rules)
- [/gh-actions](../../gh-actions/SKILL.md) — companion skill for CI workflow construction (the skill we'd consult to verify a proposed YAML edit is well-formed)
- [/gh-cli](../../gh-cli/SKILL.md) — companion skill for `gh api` queries against branch protection rules
