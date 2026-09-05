# Repo Archetypes — How Each Repo Shape Affects the Pipeline

Different repo shapes change the skill's defaults and discipline. This file maps archetypes to their adjustments.

---

## A1 — Single-package single-language repo

**Detection:** one of `Cargo.toml` / `package.json` / `pyproject.toml` / `go.mod` at root; no `workspaces` / `members` / `packages` config.

**Adjustments:** none. Default pipeline.

---

## A2 — Cargo workspace

**Detection:** root `Cargo.toml` has `[workspace]`; member crates in `crates/*` or `members = [...]`.

**Adjustments:**
- Phase 1: profile each member crate; common test command is `cargo test --workspace`
- Phase 4: stashes that span multiple crates may have heterogeneous fingerprints; classify per-crate, not per-stash
- Phase 6: `cargo check --workspace` + `cargo test --workspace` are the gates; if any crate's tests are slow, document in project_profile

---

## A3 — Monorepo (Turborepo / Nx / pnpm workspaces / Yarn workspaces)

**Detection:** `package.json` at root with `"workspaces"` array, `pnpm-workspace.yaml`, `turbo.json`, or `nx.json`.

**Adjustments:**
- Phase 1: enumerate packages; identify which have stashes via per-path-spec stash inspection
- Phase 4: stashes that touch multiple packages need cross-package coherence checks
- Phase 6: gate command depends on the monorepo tool:
  - Turborepo: `turbo run test`
  - Nx: `nx affected:test`
  - pnpm: `pnpm test --recursive`
- Phase 8 fresh-eyes: scope per-package; don't review the whole monorepo at once

---

## A4 — Polyrepo (multiple separate repos that should be triaged together)

**Detection:** the user is invoking the skill against `/data/projects/foo` and mentions related sibling repos.

**Adjustments:**
- The skill operates on ONE repo at a time. For polyrepo cleanup, the user runs the skill once per repo.
- Each run gets its own bundle (`<basename>-stash-archive-<DATE>/` per repo).
- If beads + Mail are configured across repos, beads issues can cross-link.
- Do NOT try to cherry-pick across repos via the skill; that's a separate workflow.

---

## A5 — Worktree

**Detection:** `git rev-parse --git-dir` returns a path like `<main>/.git/worktrees/<name>` rather than `<repo>/.git`.

**Adjustments:**
- Phase 0: detect worktree mode; warn the user that stashes are repo-wide, not worktree-scoped (a stash drop in this worktree affects other worktrees on the same repo)
- Phase 3: backup refs at `refs/stash-backup/*` are visible from all worktrees
- Phase 6: recovery branch is created in the current worktree; user may need to `git fetch` or `git push` to use it from the main checkout
- Phase 10: handoff includes worktree-specific guidance

---

## A6 — Submodule

**Detection:** `.git` is a file with `gitdir: ...` content, OR the project's parent has a `.gitmodules` file referencing it.

**Adjustments:**
- Phase 0: confirm with user — operating against the submodule's primary branch or the parent's?
- Phase 6: recovered commits land on the submodule's recovery branch; the parent repo's submodule pointer is unchanged (that's a separate decision)
- Phase 10: handoff includes "to update parent repo's submodule pointer: `git -C <parent> add <submodule-path> && git commit`"

---

## A7 — Repo with Git LFS

**Detection:** `git config --get-all filter.lfs.process` is non-empty, OR `.gitattributes` has `filter=lfs` lines.

**Adjustments:**
- Phase 3: bundle's diffs may contain LFS pointer text rather than actual binary content; the recovery story works only if `git lfs fetch` is functional
- Phase 6: applying an LFS-pointer diff requires `git lfs pull` after; recovery branch may have stale pointers
- Phase 10: handoff includes "ensure `git lfs fetch` works before relying on recovered LFS file content"

---

## A8 — Repo with sparse checkout

**Detection:** `git config core.sparseCheckout` is `true`.

**Adjustments:**
- Phase 3: bundle's diffs may reference paths NOT in the current sparse-checkout cone; verification still works because we use SHA-based ref comparison
- Phase 6: applying may fail because the file isn't materialized; surface to user with "expand sparse-checkout to include `<path>`?" suggestion

---

## A9 — Bare repo

**Detection:** `git config core.bare` is `true`.

**Adjustments:**
- Phase 0: REFUSE. The skill needs a working tree to apply diffs into.
- Suggest: clone into a working dir, run skill there, then push the recovery branch.

---

## A10 — Initial repo (no commits yet)

**Detection:** `git log` returns "no commits yet".

**Adjustments:**
- Phase 0: REFUSE. Stashes need a base; with no commits, no base.
- Suggest: investigate how stashes exist with no commits (likely manual `.git/refs/stash` manipulation).

---

## A11 — Detached HEAD

**Detection:** `git status` shows `HEAD detached at <sha>`.

**Adjustments:**
- Phase 0: ask user to checkout primary branch first
- The recovery branch logic needs a target

---

## A12 — Repo with pre-commit hooks

**Detection:** `.husky/`, `.git/hooks/pre-commit`, `lefthook.yml`, `.pre-commit-config.yaml` present.

**Adjustments:**
- Phase 1: profile records hook framework
- Phase 6: NEVER bypass hooks (`--no-verify`)
- If hook fails on a recovery commit, surface the failure with the hook's output; let user decide

---

## A13 — Repo with required signed commits

**Detection:** `git config commit.gpgsign` is `true`, OR repo's CI requires signed commits.

**Adjustments:**
- Phase 6: commits are signed automatically if user's GPG key is configured
- If signing fails, surface; never `--no-gpg-sign`

---

## A14 — Repo with CODEOWNERS / branch protection

**Detection:** `.github/CODEOWNERS`, branch protection rules visible via `gh api`.

**Adjustments:**
- Phase 10: handoff includes "the recovery branch will need PR approval from `<codeowners>`"
- The skill never pushes; user opens PR

---

## A15 — Repo with very-old git (<2.20)

**Detection:** `git --version` returns < 2.20.

**Adjustments:**
- Phase 0: warn; recommend upgrade
- `git stash show -p --binary` semantics are stable on the git versions this skill supports; `git apply --3way` since 1.x; ok in practice
- `git update-ref` is stable in ancient git; ok

---

## A16 — Repo with custom merge strategies / drivers

**Detection:** `.gitattributes` has `merge=` rules.

**Adjustments:**
- Phase 6: the merge strategy may affect 3-way apply; if applies fail unexpectedly, check `.gitattributes`

---

## A17 — Repo with submodules + LFS + sparse-checkout (the works)

Combine adjustments from A6 + A7 + A8.

This is the hardest archetype. Comprehensive mode is recommended; the user should expect more conflict-skipped rows.

---

## A18 — CI checkout

**Detection:** working dir matches `/__w/<repo>/...` (GitHub Actions), `/cloudbuild/...` (Cloud Build), `/builds/...` (GitLab), etc.

**Adjustments:**
- Phase 0: REFUSE with explanation. CI checkouts shouldn't have stashes; if they do, investigate the cause.

---

## A19 — Throwaway / scratch clone

**Detection:** path matches `/tmp/...` or user identifies it as throwaway.

**Adjustments:**
- Phase 0: warn the bundle goes to `/tmp/` too (also throwaway); if user wants persistent recovery, point at a non-`/tmp` path
- Otherwise: run normally

---

## A20 — Repo with CASS / NTM / agent infrastructure visible

**Detection:** `cass health` succeeds; NTM panes active; beads + Mail configured.

**Adjustments (all optional enrichments — none required):**
- Phase 0.5: CASS mining enabled (if `cass` is healthy)
- Phase 4: NTM swarm topology *available* if user wants it; default remains in-session parallel Task subagents
- Phase 8: triangulation via NTM cod/gmi panes *if* the user has them; otherwise via the multi-model-triangulation skill or skipped
- Phase 10: post-run bv triage if `bv` is available

The skill works fine in a vanilla Claude Code session with none of these tools. They are detected and used opportunistically when present.

---

## Detection Cheat-Sheet (Phase 0)

```bash
detect_archetype() {
  local p="$1"
  local types=()

  # A2 Cargo workspace
  grep -q '\[workspace\]' "$p/Cargo.toml" 2>/dev/null && types+=(cargo-workspace)

  # A3 monorepo
  jq -e '.workspaces' "$p/package.json" >/dev/null 2>&1 && types+=(npm-workspaces)
  [[ -f "$p/pnpm-workspace.yaml" ]] && types+=(pnpm-workspaces)
  [[ -f "$p/turbo.json" ]] && types+=(turborepo)
  [[ -f "$p/nx.json" ]] && types+=(nx)

  # A5 worktree
  case "$(git -C "$p" rev-parse --git-dir)" in
    *worktrees*) types+=(worktree) ;;
  esac

  # A6 submodule
  [[ -f "$p/.git" ]] && types+=(submodule)

  # A7 LFS
  git -C "$p" config --get-all filter.lfs.process >/dev/null 2>&1 && types+=(lfs)

  # A8 sparse
  [[ "$(git -C "$p" config core.sparseCheckout 2>/dev/null)" == "true" ]] && types+=(sparse)

  # A9 bare
  [[ "$(git -C "$p" config core.bare 2>/dev/null)" == "true" ]] && types+=(bare)

  # A12 hooks
  [[ -d "$p/.husky" ]] && types+=(husky)
  [[ -f "$p/lefthook.yml" || -f "$p/lefthook.yaml" ]] && types+=(lefthook)
  [[ -f "$p/.pre-commit-config.yaml" ]] && types+=(pre-commit)

  # A20 agent infra
  command -v cass >/dev/null 2>&1 && types+=(cass-available)
  command -v ntm >/dev/null 2>&1 && types+=(ntm-available)
  command -v br >/dev/null 2>&1 && types+=(beads-available)

  printf '%s\n' "${types[@]}"
}
```

The result feeds `project_profile.json:archetypes` and informs subagent selection.
