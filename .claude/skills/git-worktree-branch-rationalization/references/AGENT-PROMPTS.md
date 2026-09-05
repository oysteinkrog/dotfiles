# Agent Prompts — Verbatim Templates

Each subagent invocation uses one of the prompts below verbatim. Substitute `{PROJECT}`, `{CANONICAL}`, `{WORKSPACE}`, `{BUNDLE}`, `{RATIONALIZATION_BRANCH}`, `{RUN_ID}`, `{WORKER_ID}`, `{MODE}` with concrete values before sending.

> **Why:** Per [SKILL.md Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Authorization is per-plan, verbatim, recorded." — and per AGENTS.md "Mandatory explicit plan", every parallel subagent runs from a self-contained spec so its outputs can be cross-checked deterministically. A prompt that depends on conversational context cannot be re-issued on resumption or run on a different model for triangulation.

Each entry below has: **inputs the agent expects**, the **prompt template** (verbatim), **outputs it produces**, **exit criteria**, **common-mistake hints**.

Cross-links: each subagent's full card is in `subagents/<name>.md`; this file is the prompt-text-only quick reference for the orchestrator. The phase-by-phase playbook is [PHASES.md](PHASES.md). Operator definitions are [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md). Reading-stance tags (`[MODE: Literal]` etc.) are defined in [MODES-OF-REASONING.md](MODES-OF-REASONING.md).

---

## Phase 1 — Project Profiler

**Inputs:** `{PROJECT}` path; `{WORKSPACE}` path; `{MODE}` (Quick/Standard/Comprehensive/Council).

**Outputs:** `{WORKSPACE}/project_profile.json`; one-paragraph human summary.

**Prompt template:**

> First read ALL of the AGENTS.md file (or AGENT.md, CLAUDE.md, .cursor/rules/*, .github/copilot-instructions.md — whatever the project uses) and the README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code and technical architecture and purpose of the project at `{PROJECT}`.
>
> Detect and write to `{WORKSPACE}/project_profile.json`:
>
> - **canonical_branch** — try `git -C {PROJECT} symbolic-ref refs/remotes/origin/HEAD` first (strip the `refs/remotes/origin/` prefix), then `git config init.defaultBranch`, then look for `main`/`master`/`develop`/`trunk`/`default` in `git branch -a` (in that priority order). **Never** assume `main` (Axiom 5).
> - **branching_model** — `trunk-based` | `gitflow` (long-running `develop`) | `release-branches` | `monorepo-multi-head` | `unknown`. Detected from the canonical branch's relationship to other long-lived branches.
> - **merge_style** — `squash` | `rebase` | `merge-commit` | `merge-no-ff`. Sample `git log --merges --oneline -50` on canonical for `Squash merge of #...` patterns; check `.github/workflows/*.yml` for `merge_method` hints; check CONTRIBUTING.md / AGENTS.md for explicit policy. Drives whether `⊟ SQUASH-MERGE` or `⊠ REBASE-AND-MERGE` is the default Phase 8 strategy.
> - **protected_by_convention_patterns** — list of regex patterns of branch names the project considers permanent: `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`, `production`, `staging`. Drives Phase 4 auto-protection.
> - **commit_message_convention** — `conventional` (`feat:`, `fix:` etc.) | `ticket-id` (`BACK-1234:` etc.) | `gitmoji` | `freeform`. Sample the last 50 commits on canonical.
> - **branch_name_conventions_actually_used** — list of `(prefix_regex, count)` pairs sampled from existing local branches (e.g., `agent-cc-*`, `agent-cod-*`, `wip-BACK-*`, `feature/*`). This drives the family-grouping in Phase 2's `inventory_grouped.md`.
> - **test_command** — full command, e.g. `cargo test --workspace`. Inspect `package.json`/`Cargo.toml`/`Makefile`/CI workflows. Empty string if not detected.
> - **typecheck_command** — e.g. `bun tsc --noEmit` / `cargo check` / `mypy .` / `go vet ./...`. Empty string if not detected.
> - **lint_command** — e.g. `cargo clippy -- -D warnings` / `eslint .` / `ruff check`.
> - **format_command** — e.g. `cargo fmt --check` / `prettier --check .`.
> - **ubs_available** — bool (does the project use UBS? Check for `.ubsignore` or `ubs` invocations in CI).
> - **dcg_available** — bool (is dcg active in this environment? `command -v dcg`).
> - **pre_commit_hooks** — list of detected hook configs (husky, lefthook, pre-commit, simple-git-hooks).
> - **submodules** — list of `.gitmodules` entries if present.
> - **lfs_used** — bool (is `git lfs` configured? Look for `.gitattributes` filter=lfs entries).
> - **architecture_summary** — 200-word prose summary of what the project does and how it's structured.
>
> Output ONLY the path to `project_profile.json` and a one-paragraph human summary. No other side effects.

**Exit criteria:** `project_profile.json` exists with non-empty `canonical_branch`, `merge_style`, `protected_by_convention_patterns`, `test_command`, `typecheck_command`, `lint_command`. Empty gate-command strings mean detection failed and the orchestrator surfaces them to the user for correction (don't hallucinate commands).

**Common-mistake hints:**
- Don't assume `main` (Axiom 5). Run `git symbolic-ref refs/remotes/origin/HEAD` first.
- Don't infer `merge_style` from a single recent merge — sample at least 20 merges or read CONTRIBUTING.md.
- Don't treat `dependabot/*` as triage candidates — those are auto-protected by convention.

---

## Phase 2 — Inventory Agent (Worktree Role + Branch Role)

**Inputs:** `{PROJECT}` path; `{CANONICAL}` (from `project_profile.json`); `{WORKSPACE}` path.

**Outputs:** `{WORKSPACE}/worktrees.tsv`, `{WORKSPACE}/branches.tsv`, `{WORKSPACE}/inventory_grouped.md`.

**Prompt template:**

> Inventory every git worktree AND every local branch in `{PROJECT}`. Two passes; one TSV per pass; one markdown grouping. Both TSVs share the join key `branch_name`.
>
> ## Pass A — Worktree role
>
> 1. `git -C {PROJECT} worktree list --porcelain > {WORKSPACE}/worktrees.raw` — never use the human-readable format; locked/prunable flags only appear in `--porcelain`.
> 2. For each `worktree <path>` block, capture: `path`, `branch` (or `detached` if HEAD is detached), `head_sha`, `locked` (bool), `prunable` (bool).
> 3. Per-worktree dirty state — run inside the worktree path:
>    ```
>    (cd <path> && git status --porcelain=v2 > {WORKSPACE}/wt_status_<slug>.txt)
>    (cd <path> && git diff --stat | tail -1)              # tracked changes summary
>    (cd <path> && git diff --cached --stat | tail -1)     # staged changes summary
>    (cd <path> && git ls-files --others --exclude-standard | wc -l)  # untracked count
>    (cd <path> && git submodule status 2>/dev/null)       # per-worktree submodule init state
>    ```
> 4. Write `worktrees.tsv` with columns:
>    `path`, `branch`, `head_sha`, `locked`, `prunable`, `tracked_changed`, `staged`, `untracked`, `submodules`.
>
> ## Pass B — Branch role
>
> 1. `git -C {PROJECT} for-each-ref refs/heads/ --format='%(refname:short)|%(objectname)|%(committerdate:iso-strict)|%(authorname)|%(subject)|%(upstream:short)|%(upstream:track)' > {WORKSPACE}/branches.raw`.
> 2. For each branch (skip `{CANONICAL}` itself for ahead/behind purposes — it's its own merge-base):
>    - `merge_base = git merge-base {CANONICAL} <branch>`
>    - `ahead/behind = git rev-list --left-right --count {CANONICAL}...<branch>`
>    - `cherry_summary = git cherry -v {CANONICAL} <branch>` — count `+` lines (commits whose patch-id is NOT on canonical) and `-` lines (commits whose patch-id IS on canonical via squash/rebase/cherry-pick). **Why:** [Axiom 17](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git cherry -v` is the canonical 'is this content already on canonical' check."
>    - `files_touched = git diff --name-only <merge_base> <branch> | wc -l`
>    - `worktree_path` — backlink from worktrees.tsv (parse `git worktree list --porcelain` again or join via the branch name).
> 3. Write `branches.tsv` with columns:
>    `name`, `sha`, `merge_base`, `ahead`, `behind`, `cherry_pluses`, `cherry_minuses`, `files_touched`, `upstream_track`, `worktree_path`.
>
> ## Cross-pass — Grouping
>
> 4. Group branches by name-prefix family using `project_profile.json:branch_name_conventions_actually_used`. Write `inventory_grouped.md` — markdown tables per family, ordered by family size desc; each row shows the worktree backlink inline.
>
> Output: counts per family + the three file paths.

**Exit criteria:** row count of `worktrees.tsv` equals `git worktree list --porcelain | grep -c '^worktree '`; row count of `branches.tsv` equals `git for-each-ref refs/heads --format='%(refname:short)' | wc -l`; `inventory_grouped.md` enumerates every family.

**Common-mistake hints:**
- A worktree pointing at `detached` HEAD has no branch backlink — that's normal; record `branch=detached`.
- A branch with no worktree backlink is fine — most local branches don't have a worktree.
- A `[gone]`-tracking branch may have unique commits the upstream never saw; never use `[gone]` as a verdict on its own (per [FAILURE-MODES.md F12](FAILURE-MODES.md)).
- Locked worktrees on stale paths may not appear in plain `git worktree list`; always use `--porcelain`.

---

## Phase 3 — Bundle Builder

**Inputs:** `{PROJECT}`, `{CANONICAL}`, `{WORKSPACE}/worktrees.tsv`, `{WORKSPACE}/branches.tsv`, `{BUNDLE}` (default `<project-parent>/<basename>-branch-worktree-archive-<YYYY-MM-DD>/`).

**Outputs:** `{BUNDLE}/` populated; `{WORKSPACE}/bundle_path.txt`; `{WORKSPACE}/bundle_verification.log`.

**Prompt template:**

> Build the recovery bundle at `{BUNDLE}`. The bundle MUST be byte-equality verified AND `git bundle list-heads` round-trip verified before this phase exits — any mismatch halts the run.
>
> > **Why:** [Axiom 3](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Plan for irreversibility first, classification second." [Axiom 4](../SKILL.md#the-rationalization-kernel-universal-axioms) — "All five layers tell the same story." If a Phase 3 byte-equality check disagrees on even one entry, the run is unsafe.
>
> ## Steps
>
> 1. `mkdir -p {BUNDLE}/{branches,worktrees}` and write the absolute path to `{WORKSPACE}/bundle_path.txt`.
>
> 2. **Per branch** in `{WORKSPACE}/branches.tsv` (skip `{CANONICAL}` itself):
>    ```
>    slug=$(echo "$name" | tr '/' '_' | tr -c '[:alnum:]_.-' '_')
>    mkdir -p {BUNDLE}/branches/$slug/format-patch
>
>    # Layer 1: backup ref (inside .git/, byte-identical to live branch)
>    git -C {PROJECT} update-ref refs/branch-rationalization-backup/$slug $sha
>
>    # Layer 3: per-branch unified diff
>    git -C {PROJECT} diff --binary $merge_base...$sha \
>      > {BUNDLE}/branches/$slug/diff-vs-merge-base.diff
>
>    # Layer 4: per-branch format-patch series — VALID for branches (Axiom 7).
>    # NOTE: do NOT generalize git-stash-janitor's "format-patch is wrong" rule
>    # here — that rule is stash-specific. Branches are normal commit chains.
>    git -C {PROJECT} format-patch $merge_base..$sha \
>      -o {BUNDLE}/branches/$slug/format-patch/ \
>      --binary --no-renames
>
>    # Meta + per-branch commit list
>    git -C {PROJECT} log -1 --format='%H%n%P%n%ci%n%an%n%s' $sha \
>      > {BUNDLE}/branches/$slug/meta.txt
>    git -C {PROJECT} log $merge_base..$sha \
>      --format='%H%t%ci%t%an%t%s' \
>      > {BUNDLE}/branches/$slug/commits.tsv
>    ```
>
> 3. **Per worktree** in `{WORKSPACE}/worktrees.tsv`:
>    ```
>    wt_slug=$(echo "$path" | tr '/' '_' | tr -c '[:alnum:]_.-' '_')
>    mkdir -p {BUNDLE}/worktrees/$wt_slug
>
>    (cd $path && git status --porcelain=v2)            > {BUNDLE}/worktrees/$wt_slug/status.txt
>    (cd $path && git diff --binary --cached)            > {BUNDLE}/worktrees/$wt_slug/staged.diff
>    (cd $path && git diff --binary)                     > {BUNDLE}/worktrees/$wt_slug/unstaged.diff
>
>    # Untracked tarball — only if untracked content exists
>    untracked=$(cd $path && git ls-files --others --exclude-standard)
>    if [[ -n "$untracked" ]]; then
>      (cd $path && tar -czf {BUNDLE}/worktrees/$wt_slug/untracked.tar.gz \
>         --null --files-from=<(git ls-files --others --exclude-standard -z))
>    fi
>
>    cat > {BUNDLE}/worktrees/$wt_slug/meta.txt <<EOF
>    path: $path
>    branch: $branch
>    head_sha: $head_sha
>    locked: $locked
>    prunable: $prunable
>    captured_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
>    EOF
>    ```
>
> 4. **Object bundle** (Layer 2 across the whole backup namespace):
>    ```
>    git -C {PROJECT} bundle create {BUNDLE}/object-bundle.pack \
>      --stdin <<< "refs/branch-rationalization-backup/*"
>    ```
>
> 5. **Index** — `{BUNDLE}/index.tsv` with one row per branch AND per worktree:
>    ```
>    kind     name                       sha     merge_base  verdict_pending  bundle_paths
>    branch   <name>                     <sha>   <mb>        (pending)        branches/<slug>/diff-vs-merge-base.diff,branches/<slug>/format-patch/,refs/branch-rationalization-backup/<slug>
>    worktree <path>                     -       -           (pending)        worktrees/<wt_slug>/staged.diff,worktrees/<wt_slug>/unstaged.diff,worktrees/<wt_slug>/untracked.tar.gz
>    ```
>
> 6. **README** — `{BUNDLE}/README.md` with verbatim recovery recipes from [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md) AND a footgun warning that `format-patch` IS valid for branches (Axiom 7) so future readers don't import the stash-janitor rule.
>
> 7. **Verify** via `scripts/verify-bundle.sh`:
>    - For every branch: `git rev-parse refs/heads/<name>` == `git rev-parse refs/branch-rationalization-backup/<slug>` (byte-equality).
>    - For every branch: `sha256sum` of regenerated `git diff --binary <merge_base>...<sha>` == `sha256sum` of `{BUNDLE}/branches/<slug>/diff-vs-merge-base.diff` (round-trip).
>    - `git bundle list-heads {BUNDLE}/object-bundle.pack` enumerates every backup ref (no missing, no extra).
>    - For every worktree: re-run `git diff --binary --cached` / `git diff --binary` and compare hashes against staged/unstaged captures.
>    - Write all results to `{WORKSPACE}/bundle_verification.log`. ANY mismatch must halt the run.
>
> Output: bundle path + verification status + count of artifacts (branches, worktrees, total bundle size in MB).

**Exit criteria:** every branch has backup ref + diff + format-patch + meta + commits.tsv; every worktree has staged.diff + unstaged.diff + (optionally) untracked.tar.gz + status + meta; `object-bundle.pack` is non-empty and round-trips; `bundle_verification.log` has zero `MISMATCH` lines.

**Common-mistake hints:**
- The bundle lives **outside** the repo (per SKILL.md Workspace Layout) — it survives `git clean -fdx`.
- Don't use `git format-patch -1 stash@{N}` semantics here — branches use `format-patch <merge-base>..<branch>`. Per [Axiom 7](../SKILL.md#the-rationalization-kernel-universal-axioms), `format-patch` IS valid for branches.
- `--no-renames` on format-patch ensures full file content is captured even when paths moved during the branch's history.
- Concurrent agents may modify worktrees during capture; re-snapshot after capture and append a `wt_capture_drift.log` if any worktree's status changed mid-run (don't fail — drift is normal per Axiom 12).

---

## Phase 5 — Triage Worker (parallel)

**Inputs:** `{PROJECT}`, `{CANONICAL}`, `{WORKSPACE}`, `{BUNDLE}`, `{WORKER_ID}`, `{ENTRIES}` (slice of `branches.tsv` + `worktrees.tsv` minus `protected.tsv`, ~10 entries per worker).

**Outputs:** `{WORKSPACE}/triage/batch_{WORKER_ID}.tsv`.

**Prompt template:**

> You are triage worker `{WORKER_ID}`. You triage `{ENTRIES}` (a slice of branches and worktrees from `{WORKSPACE}/branches.tsv` and `{WORKSPACE}/worktrees.tsv`, minus anything in `{WORKSPACE}/protected.tsv`).
>
> Read `{WORKSPACE}/project_profile.json` for `canonical_branch`, `merge_style`, gate commands. Read `{WORKSPACE}/bundle_path.txt` for `{BUNDLE}`.
>
> [MODE: Literal] is the default reading stance for branches whose fingerprint coverage is high (≥0.85). Switch to [MODE: Forensic] for `novel-but-stale` candidates (files referenced no longer exist on canonical) — see [MODES-OF-REASONING.md](MODES-OF-REASONING.md) for the prompt augmentation.
>
> ## Per branch
>
> For each branch row:
>
> 1. **`✦ FINGERPRINT`** — read `{BUNDLE}/branches/<slug>/diff-vs-merge-base.diff`. Extract introduced symbols:
>    - Function/method names introduced in `+` lines NOT matched by a `-` line
>    - Type names, struct/enum/interface declarations
>    - Test names (functions whose names start with `test_`/`#[test]`/`it(`/`describe(`)
>    - Fixture string literals ≥10 chars
>    - File paths (every `diff --git a/X b/X` where `b/X` is new)
> 2. **`◐ VERIFY-ON-CANONICAL`** — for each fingerprint:
>    - Path-scoped first: `git -C {PROJECT} grep -F '<symbol>' {CANONICAL} -- <expected_path>`
>    - Whole-repo grep fallback: `git -C {PROJECT} grep -F '<symbol>' {CANONICAL}`
>    - If the file no longer exists on `{CANONICAL}`: tag `file-missing`
>    - **Sample same-signature** on at least 3 introduced symbols. If ≥30% of sampled signatures diverge, flip the verdict candidate to `divergent-refactor`. **Why:** [Axiom 16](../SKILL.md#the-rationalization-kernel-universal-axioms): "Same-name on canonical is not always supersession."
> 3. **`git cherry -v {CANONICAL} <branch>`** — already in `branches.tsv`. If all `-` lines: candidate `already-merged` with confidence 0.99 (this is the most reliable verdict; per Axiom 17 it detects content even when SHAs differ).
> 4. **APPLY-CHECK PROBE** — on a throwaway branch:
>    ```
>    git -C {PROJECT} switch --detach {CANONICAL}
>    git -C {PROJECT} cherry-pick --no-commit -X theirs <sha>
>    apply_check_exit=$?
>    git -C {PROJECT} cherry-pick --abort 2>/dev/null
>    ```
>    Record `clean` (exit 0) or `reject` (non-zero) or `fail` (gave up partway). Do NOT actually commit.
> 5. **VERDICT** — per [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md):
>    - `protected-preserve` — pre-tagged, skipped here
>    - `already-merged` — `cherry -v` is all `-` lines
>    - `superseded` — every fingerprint resolves on canonical with same semantics; ≥70% of sampled signatures match
>    - `superseded-by-newer-branch` — superseded specifically by another branch's tip in the same family (e.g., `agent-cc-12-feat-parser-v2` supersedes `agent-cc-12-feat-parser`)
>    - `garbage` — message matches a known-garbage pattern AND fingerprint adds no novel surface (e.g., `agent-XX-broken-attempt`, `temp/`, `wip-revert-`)
>    - `novel-and-accretive` — fingerprint absent on canonical AND apply-check clean AND diff is focused/defensive
>    - `novel-but-stale` — fingerprint absent on canonical BUT files referenced no longer exist OR apply-check rejects every hunk
>    - `partially-novel` — apply-check finds rejects only on the superseded subset of commits/hunks; novel ones would still apply
>    - `divergent-refactor` — branch refactors files that another branch also refactored differently; harmonization candidate (Phase 7)
>    - `dirty-worktree-only` — only relevant for worktree rows; see below
>    - `unknown` — confidence < 0.5; surface to user
>
> ## Per worktree
>
> For each worktree row whose underlying branch is NOT protected:
>
> 1. Read `{BUNDLE}/worktrees/<wt_slug>/staged.diff` + `unstaged.diff`. If both empty AND no `untracked.tar.gz`: this worktree is a clean checkout — its verdict piggybacks on the underlying branch's verdict (write `worktree-mirrors-branch` and the underlying branch name).
> 2. If non-empty: `✦ FINGERPRINT` the dirty state independently. Verdict candidates:
>    - `dirty-worktree-only` — fingerprints not on the underlying branch nor on canonical; the dirty state is genuinely new content
>    - `dirty-worktree-superseded` — fingerprints already on canonical or the rationalization branch (lift nothing)
>    - `dirty-worktree-novel-stale` — fingerprints novel but files referenced no longer exist
>
> ## Output
>
> Append a row to `{WORKSPACE}/triage/batch_{WORKER_ID}.tsv` with columns:
>
> ```
> kind | name | verdict | confidence | evidence_on_canonical | apply_check | fingerprint_summary | strategy | files_touched
> ```
>
> Where `strategy` is one of `cherry-pick` | `squash-merge` | `rebase-and-merge` | `harmonized-synthesis-via-Edit` | `split-commits` | `worktree-dirty-state` | `skip`. The strategy must agree with `project_profile.json:merge_style` for non-harmonized keepers.
>
> Reserve your batch tsv via Agent Mail before writing (`thread_id=branch-rationalization-{RUN_ID}`, `reason="triage-batch-{WORKER_ID}"`). Release on exit.
>
> Do NOT modify the working tree of any worktree. Do NOT commit. Do NOT modify any other batch's tsv.
>
> Output: counts per verdict + path to your batch tsv.

**Exit criteria:** every entry in `{ENTRIES}` has exactly one row in the batch TSV with non-empty verdict + confidence + strategy + evidence; no row has `verdict=unknown` without a `confidence` value below 0.5 explaining why.

**Common-mistake hints:**
- A `superseded` verdict requires same-signature verification on ≥3 introduced symbols. Same-name without same-signature is `divergent-refactor`, not supersession (Axiom 16).
- The APPLY-CHECK PROBE must abort the cherry-pick — never leave a half-applied state in the working tree.
- A worktree whose dirty diffs are empty just mirrors its branch; don't duplicate triage work.
- A branch with `cherry_minuses > 0` but `cherry_pluses > 0` is `partially-novel`, not `already-merged`.

---

## Phase 6 — Triage Merger

**Inputs:** all `{WORKSPACE}/triage/batch_*.tsv`; `{WORKSPACE}/protected.tsv`.

**Outputs:** `{WORKSPACE}/triage.tsv` (merged); `{WORKSPACE}/triage_decision.md`; `{WORKSPACE}/user_overrides.tsv`.

**Prompt template:**

> Merge all `{WORKSPACE}/triage/batch_*.tsv` files into `{WORKSPACE}/triage.tsv`. Sanity-check by row count: `cat triage/batch_*.tsv | grep -v '^kind' | wc -l` must equal `(branches.tsv rows + worktrees.tsv rows) - protected.tsv rows`. If mismatch: name the missing entries and halt.
>
> Build `{WORKSPACE}/triage_decision.md` for the user — a markdown table sorted by verdict bucket, with `<details>` blocks for the long DROP tail. Bucket order:
>
> 1. `KEEP-AS-PROTECTED` (frozen at Phase 4; included for completeness)
> 2. `KEEP — novel-and-accretive`
> 3. `KEEP-WITH-SPLIT — partially-novel`
> 4. `HARMONIZE — files touched by ≥2 non-protected branches` (a roll-up by file, not by branch)
> 5. `DROP — already-merged`
> 6. `DROP — superseded` (and `superseded-by-newer-branch`)
> 7. `DROP — garbage`
> 8. `MANUAL — novel-but-stale`
> 9. `MANUAL — divergent-refactor` (no auto-resolution; surfaces to harmonization gate)
> 10. `MANUAL — dirty-worktree-only`
> 11. `MANUAL — unknown` (flagged for user)
>
> Within each bucket, sort by confidence ascending — the most ambiguous rows are most prominent.
>
> **Present the table to the user verbatim** and wait for explicit go-ahead.
>
> Capture per-row overrides into `{WORKSPACE}/user_overrides.tsv` with columns:
>
> ```
> kind | name | original_verdict | new_verdict | new_strategy | user_reason
> ```
>
> Apply overrides to `triage.tsv` (the merged file is the source of truth from this point).
>
> If overrides change >5 verdicts, re-ask confirmation as a sanity check (an unexpectedly large override count usually means the user is reading a different bucket than intended).
>
> NO destructive actions in this phase. NO commits. NO worktree removals. NO branch deletions.
>
> Output: the markdown table to the user; the path to `triage.tsv`; the count of overrides applied; the verdict-bucket counts.

**Exit criteria:** user explicitly typed "go" / "proceed" / "approved" (or a phrase that includes one of those words); `triage.tsv` reflects user-confirmed verdicts; main agent shows the user the next-step plan ("I'll now build the harmonization plan for the N file-groups, present it for your review, then apply M keepers...").

**Common-mistake hints:**
- The HARMONIZE bucket is a roll-up by file (one entry per contested file), not by branch — multiple branches per row is the point.
- Don't auto-promote `divergent-refactor` to harmonization without user OK; it's surfaced as MANUAL because the synthesis is non-trivial (per [HARMONIZATION.md § 5](HARMONIZATION.md)).
- "Yes" is too vague; require a phrase that quotes a verdict or a count.

---

## Phase 7 — Harmonization Planner (the conceptual centerpiece)

**Inputs:** `{WORKSPACE}/triage.tsv`, `{BUNDLE}`, `{WORKSPACE}/branches.tsv`, `{WORKSPACE}/worktrees.tsv`, `project_profile.json`. The harmonization-planner subagent's full card is at [`subagents/harmonization-planner.md`](../subagents/harmonization-planner.md).

**Outputs:** `{WORKSPACE}/harmonization_plan.md`.

**Prompt template:**

> [MODE: Forensic + Adversarial composed — Forensic to identify each variant's intent; Adversarial to stress-test the proposed synthesis. See [MODES-OF-REASONING.md](MODES-OF-REASONING.md).]
>
> You are the harmonization planner. Your job is the **`◇ HARMONIZE` operator**. You are NOT picking a winner branch. You are recovering the strongest current implementation of every contested file by inspecting every variant, identifying each part's intent, and synthesizing them on top of canonical's architecture.
>
> > **Why:** Per [SKILL.md Axiom 1](../SKILL.md#the-rationalization-kernel-universal-axioms): "Harmonize, don't pick. For any file touched by more than one non-protected branch, the job is NOT to choose between competing variants. The job is to inspect every variant (canonical's, each branch's, each dirty worktree's), reason about each part's intent, and synthesize the strongest current implementation on top of canonical's architecture."
> >
> > Per [HARMONIZATION.md § 1](HARMONIZATION.md): "Picking is the wrong primitive." Five `agent-cleanup-pass-*` branches all touching `src/util/logger.rs` typically each contribute a different defensive check. Pick-or-drop loses four of the five.
>
> ## Step 1 — Identify colliding-file groups
>
> From `{WORKSPACE}/triage.tsv`, filter to rows whose verdict is in `{novel-and-accretive, partially-novel, novel-but-stale, divergent-refactor, dirty-worktree-only}`. Build a multi-map: `file -> set(variant)` where variant is a branch-name OR `worktree:<sanitized-path>`.
>
> Any file with set size ≥ 2 is a **colliding file**. The dirty-worktree variants count toward the set size only if their staged/unstaged diffs touch the same file.
>
> ## Step 2 — Per-file variant matrix
>
> For each colliding file, read every variant's content for that file:
>
> - **canonical's version:** `git -C {PROJECT} show {CANONICAL}:<path>` (the synthesis base)
> - **each branch's version:** `git -C {PROJECT} show <branch_sha>:<path>` AND `git -C {PROJECT} diff <merge_base>..<branch> -- <path>` (the per-branch hunks)
> - **each dirty worktree's version:** the working-tree state at that path PLUS the captured staged.diff/unstaged.diff in `{BUNDLE}/worktrees/<wt_slug>/`
>
> Build the variant matrix per [HARMONIZATION.md § 2](HARMONIZATION.md):
>
> | variant | head sha | signatures | hunk summary | tests/fixtures | identified intent | proposed synthesis | confidence | risks |
> |---|---|---|---|---|---|---|---|---|
>
> The **identified intent** column uses the 8-intent taxonomy from [HARMONIZATION.md § 3](HARMONIZATION.md): `defensive` / `refactor` / `test` / `fixture` / `type-narrowing` / `error-handling` / `performance` / `naming`.
>
> ## Step 3 — Apply synthesis principles
>
> Per [HARMONIZATION.md § 4](HARMONIZATION.md):
>
> 1. Preserve the strongest example of each intent (tightest guarantee → most-recently-authored → tested → no-canonical-regression).
> 2. **Defensive checks compose** — three branches each adding a different defensive check produce a synthesis with all three at function entry, ordered most-permissive → most-restrictive (cheap rejections first).
> 3. **Refactors do NOT compose** — pick one structural base; rebase the others' content (defensive checks, tests, fixtures) into the chosen refactor's shape.
> 4. **Tests are additive** — lift every novel test from every variant; resolve name collisions by giving each test a distinct, intent-named name (`test_log_null_arg`, `test_log_length_cap`, `test_log_redacts_secrets`).
> 5. **Fixtures are additive for new files**; for modifications to existing fixtures, examine carefully — the modification usually evidences a real semantic change.
> 6. **Type-narrowing usually composes** — strictly increases guarantees.
> 7. **Error-handling composes if compatible** — typed enum > anyhow > unwrap.
> 8. **Performance composes only when independent** — same-code-path with incompatible strategies does not compose; require benchmark evidence or surface to user.
> 9. **Naming picks one** — prefer canonical-aligned name.
>
> ## Step 4 — Surface non-harmonizable cases
>
> Per [HARMONIZATION.md § 5](HARMONIZATION.md), flag a file as `divergent-refactor` (NOT auto-synthesized; surfaced to user) when:
>
> - Two branches use fundamentally different state machines for the same feature
> - Two branches use different storage layouts for the same data
> - Two branches use incompatible concurrency primitives for the same shared resource
> - Two branches introduce different external dependencies for the same purpose
> - Branch A deletes a module that Branch B extends with ≥3 commits of meaningful work
> - The collision is on generated code or auto-formatted regions
>
> When in doubt, **flag rather than synthesize**. Confidence < 0.7 forces user review before Phase 8.
>
> ## Step 5 — Write `harmonization_plan.md`
>
> Top of file: a summary table — one row per colliding file with synthesis strategy + confidence.
>
> Per file: the variant matrix; the proposed synthesis (showing the intended diff fragment, NOT auto-applied); the proposed commit message citing source branches and intents (per [HARMONIZATION.md § 6.2](HARMONIZATION.md)); the confidence score; risks; cross-link to `{BUNDLE}/branches/<slug>/diff-vs-merge-base.diff` for each cited variant.
>
> ## Step 6 — Block until user reviews
>
> The plan is the spec for Phase 8. Phase 8 must NOT mutate anything until the user has reviewed `harmonization_plan.md` and either:
>
> - Typed an explicit OK
> - Edited the plan in-place via the Edit tool (the document IS the spec — capture user edits as the new plan)
> - Flagged specific rows as `divergent-refactor`-skip (recorded in `user_overrides.tsv`)
>
> Output: path to `harmonization_plan.md`; counts per synthesis strategy; counts of low-confidence rows requiring user decision.

**Exit criteria:** `harmonization_plan.md` exists with one block per colliding-file group; every block has variant matrix + proposed synthesis + commit message + confidence + risks; user has explicitly OK'd the plan or applied overrides; no row has confidence < 0.7 without an explicit user decision recorded.

**Common-mistake hints:**
- The plan is text. Phase 8 does the actual Edit-tool synthesis — Phase 7 only proposes. Per AGENTS.md "No Script-Based Changes", synthesis is hand-edited per file, never sed/awk/regex.
- A branch row in the matrix that has `divergent-refactor` intent does NOT compose — surface it; don't try to merge it.
- The dirty-worktree variant is a first-class row. Per [Axiom 12](../SKILL.md#the-rationalization-kernel-universal-axioms), the skill never disturbs the dirty state, but the planner CAN read it and propose lifting it.
- Same-name-different-signature symbols across variants are the #1 source of bad syntheses. Always sample signatures (Axiom 16) before composing.
- For Council mode, run the per-file matrix through Codex AND Gemini in addition to Claude (per [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md)) and surface unanimous-agreement vs. disagreement to the user.

---

## Phase 8 — Keeper Applier (sequential)

**Inputs:** `{WORKSPACE}/triage.tsv`, `{WORKSPACE}/harmonization_plan.md`, `{BUNDLE}`, `project_profile.json`, `{RATIONALIZATION_BRANCH}` (default `branch-rationalization-<YYYY-MM-DD>`).

**Outputs:** `{WORKSPACE}/apply_log.tsv`, commits on `{RATIONALIZATION_BRANCH}`, `{WORKSPACE}/conflicts/branch_<slug>.context.md` per conflict.

**Prompt template:**

> You are the keeper-applier. Phase 8 is sequential by definition — each apply changes the 3-way base for later applies and can flip downstream verdicts.
>
> ## Setup (once at start of phase)
>
> 1. Cut the rationalization branch off canonical's tip. **Resume-aware** — never `checkout -B`:
>    ```
>    if git -C {PROJECT} show-ref --verify --quiet refs/heads/{RATIONALIZATION_BRANCH}; then
>      git -C {PROJECT} checkout {RATIONALIZATION_BRANCH}    # resume; existing work preserved
>    else
>      git -C {PROJECT} checkout -b {RATIONALIZATION_BRANCH} {CANONICAL}
>    fi
>    ```
>    > **Why:** [Axiom 6](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Land on a rationalization branch, not on canonical."
>
> ## Per row (in dependency order)
>
> Process each row of `triage.tsv` whose verdict is in `{novel-and-accretive, partially-novel, novel-but-stale (user-OK only), dirty-worktree-only}` plus every harmonization group from `harmonization_plan.md`. Order: chronological by branch tip date by default; user can override.
>
> For each row:
>
> 1. **`↺ WORKING-TREE-DRIFT` check** — re-snapshot `git status` in every active worktree:
>    ```
>    scripts/snapshot-worktrees.sh {PROJECT} pre-apply-<row-id>
>    ```
>    If changes appeared since Phase 0's `wt_phase0.txt`, treat them as if you made them. Per AGENTS.md "Note for Codex/GPT-5.5", **never** stash, revert, or overwrite. Capture the drift in `apply_log.tsv:pre_apply_drift`.
>
> 2. **`⊞ RE-FINGERPRINT`** — re-run FINGERPRINT/VERIFY-ON-CANONICAL against the rationalization branch's tip (which has accumulated previous keepers). If the candidate now has fingerprint coverage ≥ 0.8 on the rationalization branch, mark `superseded-during-apply` and skip — append the row to `apply_log.tsv` with `gates_status=skipped-superseded-by-prior-apply`.
>
> 3. **Pick the apply strategy** from `triage.tsv:strategy` (matched against the harmonization plan if applicable):
>
>    - **`cherry-pick`** (`✧ CHERRY-PICK`): single-commit and small-coherent branches.
>      ```
>      git -C {PROJECT} cherry-pick --no-commit <sha>
>      # if clean, commit with focused message; if conflict, surface and abort
>      ```
>    - **`squash-merge`** (`⊟ SQUASH-MERGE`): when `merge_style == "squash"`.
>      ```
>      git -C {PROJECT} merge --squash <branch>
>      # single focused commit follows
>      ```
>    - **`rebase-and-merge`** (`⊠ REBASE-AND-MERGE`): when `merge_style == "rebase"` AND the branch is large/meaningful.
>      ```
>      merge_base=$(git -C {PROJECT} merge-base {CANONICAL} <branch>)
>      git -C {PROJECT} cherry-pick $merge_base..<branch>
>      ```
>    - **`harmonized-synthesis-via-Edit`**: per `harmonization_plan.md` for this file group — open the file in the rationalization branch's working tree, use the Edit tool to construct the synthesis (per AGENTS.md "No Script-Based Changes", **Edit tool only — never sed/awk/regex/script**), commit.
>    - **`split-commits`** (`⇄ SPLIT-COMMITS-HUNKS`): for partially-novel; cherry-pick only the novel commit subset (Phase 8b — partial-splitter).
>    - **`worktree-dirty-state`**: `git apply --3way` the worktree's `staged.diff` + `unstaged.diff` from `{BUNDLE}/worktrees/<wt_slug>/`; copy untracked files from `untracked.tar.gz`.
>
> 4. **`⊕ RECOVER` — run quality gates** from `project_profile.json`. **Why:** [Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Run the project's actual `test`, `typecheck`, `lint`, `ubs` after every Phase 8 apply, not just at the end."
>
>    All commands must exit 0:
>    ```
>    {test_command}
>    {typecheck_command}
>    {lint_command}
>    {format_command}      # check mode; do not auto-format
>    ubs <changed-files>   # if ubs_available
>    ```
>    If any gate fails:
>    - Attempt `git apply -R` (the reverse) on a non-merge / non-cherry-pick apply, OR `git reset --merge` for cherry-pick mid-state if the working tree has only this apply's changes.
>    - If revert succeeds: mark `conflict-skipped`, log `gates_status=failed-<gate>`, continue to the next row.
>    - If revert fails: HALT. Surface the dirty state to the user honestly per [INCIDENT-PLAYBOOK.md I3](INCIDENT-PLAYBOOK.md#i3). **NEVER** silently `2>/dev/null` the failure.
>    - **NEVER** run `git reset --hard` or `git clean -fd` (DCG-blocked AND unsafe to concurrent agents).
>
> 5. **Stage only the paths touched by this apply** plus any files copied from `worktrees/<wt_slug>/untracked/`. Never run repository-wide `git add -A`.
>
> 6. **Commit** with a focused message that explains *why* this content is being recovered, naming source branches and variant intents:
>    ```
>    recover {one-line summary} {from <branch> | harmonized from {N} branches}
>
>    {Source-citation block: which hunks came from which branch and the
>    identified intent of each. For harmonized commits, name every source
>    branch and every cited fixture/test.}
>
>    {2–4 sentence explanation of motivation drawn from the triage evidence
>    and a re-read of the diff.}
>
>    Recovered via: {strategy}
>    Source-branch backups:
>      refs/branch-rationalization-backup/<slug-1>
>      refs/branch-rationalization-backup/<slug-2>
>    ```
>    Do NOT add `Co-Authored-By` lines unless the user asks.
>
> 7. **Append to `apply_log.tsv`:**
>    ```
>    kind | name | new_commit_sha | files_changed | gates_status | strategy | duration_s | pre_apply_drift
>    ```
>    For harmonization-folded source branches, append rows with `new_commit_sha=(folded-into <other-sha>)` and `files_changed=0`.
>
> ## On apply-check / cherry-pick conflict
>
> 1. Do NOT force the apply.
> 2. Surface to user: branch's diff vs canonical, current state of affected files on the rationalization branch, hypothesis (refactor / rename / file move), proposed Edit-tool resolution.
> 3. Wait for explicit user OK.
> 4. If "skip": mark `conflict-skipped`. If "fix it like that": apply via Edit tool, run gates, commit.
> 5. Write the conflict context to `{WORKSPACE}/conflicts/branch_<slug>.context.md` so it survives compaction.
>
> ## Hard rules
>
> - Never `git stash` to defer concurrent agents' work — it interleaves with the user's stash list (cf. git-stash-janitor as a separate skill).
> - Never bypass pre-commit hooks (`--no-verify`).
> - Never push.
> - Never directly modify the source branch — only its content lands on the rationalization branch.
> - Never run `git rebase` on a branch that's checked out in a worktree (the worktree pins the branch).
>
> Output: count of applied / folded / skipped / conflict-resolved + the rationalization branch's tip SHA.

**Exit criteria:** every row in `triage.tsv` with a non-skip strategy has either a `new_commit_sha` (or `(folded-into ...)`) or a `conflict-skipped` / `superseded-during-apply` mark in `apply_log.tsv`; quality gates passed on the rationalization branch's tip.

**Common-mistake hints:**
- A branch with verdict `novel-but-stale` ONLY applies if the user explicitly OK'd it (the default is to drop). Don't auto-apply.
- A `harmonized-synthesis-via-Edit` commit must cite ≥2 source branches in its message — that's how the user can answer "where did this hunk come from?".
- The "(folded)" rows in `apply_log.tsv` are part of the safety story; don't omit them — they prove the source branches' content was incorporated rather than dropped.
- Resume-aware setup: `git checkout -B` would discard existing work. Always use `show-ref --verify --quiet` first.

---

## Phase 8b — Partial Splitter

**Inputs:** all `triage.tsv` rows with verdict `partially-novel`; `{BUNDLE}`; `project_profile.json`.

**Outputs:** `{WORKSPACE}/partial_split_log.tsv`; commits on `{RATIONALIZATION_BRANCH}`.

**Prompt template:**

> For each `partially-novel` row in `{WORKSPACE}/triage.tsv`:
>
> 1. Open `{BUNDLE}/branches/<slug>/diff-vs-merge-base.diff` AND the per-commit format-patch series at `{BUNDLE}/branches/<slug>/format-patch/`.
> 2. Identify which commits are novel vs. superseded (the per-hunk evidence column from `triage.tsv` if present; otherwise re-fingerprint per-commit).
> 3. Build the cherry-pick subset:
>    ```
>    # If novel commits are a contiguous range:
>    git -C {PROJECT} cherry-pick <start_sha>..<end_sha>
>    # If novel commits are scattered:
>    git -C {PROJECT} cherry-pick <novel_sha_1> <novel_sha_2> <novel_sha_5>
>    ```
> 4. If a single commit is itself partially novel (some hunks novel, others superseded): `git cherry-pick --no-commit <sha>`, then use the **Edit tool** to remove the superseded hunks from the working tree before committing. Per AGENTS.md "No Script-Based Changes", never sed/awk this.
> 5. Run gates per `⊕ RECOVER`. Commit with a message that explicitly notes split-apply:
>    ```
>    recover novel <subject> from <branch> (split-apply)
>
>    The <other portion> of <branch> already landed on canonical via
>    {squash-merge | rebase | cherry-pick PR #N} (cherry -v shows commits
>    1–3 as `-`). This commit recovers only the novel <subject> additions
>    (commits {list-of-shas} of the original branch).
>
>    Recovered via: split-apply per partial_split_log.tsv
>    Source branch backed up at: refs/branch-rationalization-backup/<slug>
>    ```
> 6. Append to `partial_split_log.tsv` with columns: `name`, `commits_kept`, `commits_dropped`, `hunks_kept`, `hunks_dropped`, `new_commit_sha`, `gates_status`.
>
> If the apply-check fails on the cherry-pick subset: surface to user with the same conflict-resolution flow as Phase 8.
>
> Output: count of split-applied + count of partial-skipped.

**Exit criteria:** every `partially-novel` row has either a `new_commit_sha` or a `conflict-skipped` mark; gates pass on the rationalization branch's tip.

**Common-mistake hints:**
- The format-patch series at `{BUNDLE}/branches/<slug>/format-patch/0001-...patch` etc. are valid for branches (per [Axiom 7](../SKILL.md#the-rationalization-kernel-universal-axioms)) — `git am` them if cherry-pick is awkward for non-linear histories.
- A "partially-novel" branch where the superseded commits are at the tip and the novel commits are at the base is best done via `git rebase --onto {RATIONALIZATION_BRANCH} <last-superseded-sha> <branch>` followed by cherry-pick of the result.
- Never reorder commits silently — if the user expects the original ordering, preserve it.

---

## Phase 9 — Fresh Eyes (run each prompt separately, different agent each round)

**Inputs:** the rationalization branch tip; `apply_log.tsv`; `project_profile.json`.

**Outputs:** `{WORKSPACE}/fresh_eyes_log.md`.

**Prompt templates** (each round runs independently; different reading stance per round; main agent runs gates between rounds):

**Round 1 prompt** ([MODE: Literal]):

> Carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.

**Round 2 prompt** ([MODE: Forensic] for Standard / Comprehensive; [MODE: Adversarial] for Council):

> Sort of randomly explore the code files in this project, choosing code files to deeply investigate and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes. Comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in AGENTS.md.

**Round 3 prompt** ([MODE: Adversarial]):

> Turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep. Pay particular attention to harmonized-synthesis commits that combined hunks from multiple source branches — those are the most likely place for subtle integration bugs (a defensive check that assumes a type the refactor didn't preserve, a fixture that the test no longer covers, etc.).

**Between rounds**, the main agent runs:

```
{test_command}
{typecheck_command}
{lint_command}
ubs .                      # if ubs_available
```

All must exit 0. Log each round + outcome to `{WORKSPACE}/fresh_eyes_log.md`.

**Termination rule:** Two consecutive full rounds produce only trivial findings (typo, wording polish) AND test + typecheck + lint + UBS all green.

**Scope:** only the rationalization branch's commits. Do NOT modify `{BUNDLE}/`. Do NOT touch the canonical branch. Do NOT touch protected branches.

**Mode-variant termination:**
- Quick: 1 round, 1 model
- Standard: ≥2 clean rounds, 1 model
- Comprehensive: ≥3 rounds, 3 independent models adjudicated (Path A — `/multi-model-triangulation` skill; or Path B — same-Claude with multi-stance; per [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md))
- Council: ≥3 rounds, multi-model adjudicated, fresh-eyes review of fresh-eyes findings

**Exit criteria:** Fresh-eyes log shows ≥2 clean rounds (per mode); gates green on `HEAD`.

**Common-mistake hints:**
- Each round runs as an INDEPENDENT subagent — fresh context, no recall of prior rounds. Repeating the same finding across rounds means the fix didn't take.
- A finding that repeats 3 rounds is blocking-unresolvable; escalate to user per [INCIDENT-PLAYBOOK.md I4](INCIDENT-PLAYBOOK.md#i4).
- Don't run gates inside the fresh-eyes prompt; the main agent runs them between rounds and posts the result back to the next round.

---

## Phase 10 — Cleanup Conductor (gated)

**Inputs:** `triage.tsv` (final), `apply_log.tsv`, `protected.tsv`, the user's verbatim authorization phrase.

**Outputs:** `{WORKSPACE}/cleanup_authorization.txt`, `{WORKSPACE}/cleanup_log.tsv`.

**Prompt template:**

> The user has authorized destructive cleanup. Read `{WORKSPACE}/cleanup_authorization.txt`. If the file doesn't exist OR doesn't include a literal command from the plan you'll restate, REFUSE and re-ask the user.
>
> > **Why:** [Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Authorization is per-plan, verbatim, recorded." Per AGENTS.md "Mandatory explicit plan": "Even after explicit user authorization, restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct."
>
> ## Cleanup order (NON-NEGOTIABLE)
>
> Worktrees first; branches second. Within branches: garbage → superseded / superseded-by-newer-branch → already-merged → novel-but-stale (user-opt-in only) → divergent-refactor (user-opt-in only) → applied-keepers.
>
> > **Why:** [Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Worktrees are removed first, branches second. A worktree pinned to a branch protects that branch from `git branch -d`."
>
> ## Per worktree
>
> 1. Restate the verbatim command:
>    ```
>    About to run: git worktree remove <path>
>    (Row in worktrees.tsv: branch=<branch>, dirty=<tracked> tracked + <staged> staged + <untracked> untracked, captured in {BUNDLE}/worktrees/<wt_slug>/)
>    ```
> 2. Execute. If `git worktree remove` refuses (dirty): surface to user; `--force` only after explicit user OK that the dirty state may be lost (it's still in the bundle).
> 3. **Never** the currently-active worktree (the user's CWD). Per [Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms): "the currently-active worktree (the user's CWD) is NEVER removed by the skill."
> 4. Append to `cleanup_log.tsv`.
> 5. After all worktrees removed: run `git -C {PROJECT} worktree prune` to clean residual `.git/worktrees/<id>/` admin metadata. Per [Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms): "Never run `git worktree prune` as a substitute for explicit `git worktree remove` — `prune` only cleans up admin metadata for worktrees already deleted out-of-band." Use it AS A FOLLOW-UP, not as a replacement.
>
> ## Per branch
>
> 1. Restate the verbatim command. Use `git branch -d` (lowercase) by default — it refuses to delete branches not fully merged into HEAD. Per [Axiom 8](../SKILL.md#the-rationalization-kernel-universal-axioms): "After Phase 8 lands every keeper onto the rationalization branch, every 'applied-keeper' branch IS fully merged from that branch's perspective — `-d` will succeed."
>    ```
>    About to run: git branch -d <name>
>    (Row in branches.tsv: verdict=<verdict>, sha=<sha>, applied as <new_commit_sha> on {RATIONALIZATION_BRANCH})
>    ```
>    For branches with verdict `garbage` or `novel-but-stale` that the user has explicitly acknowledged as unmerged-and-discardable: use `git branch -D` (uppercase). Mixing them up is forbidden — the refusal is a built-in safety check.
> 2. Never `git branch -D` on a protected branch (per [Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms) and the workspace's `protected.tsv` from Phase 4). Cross-check `protected.tsv` before every deletion.
> 3. Append to `cleanup_log.tsv`.
>
> ## Hard constraints
>
> - **NEVER** run `git branch | xargs git branch -D` or any mass-delete primitive (Axiom 10).
> - **NEVER** run `git push --delete`, `git push --force` (Axiom 15).
> - **NEVER** run `rm -rf <worktree-path>` (Axiom 11; DCG blocks it).
> - **NEVER** delete `refs/branch-rationalization-backup/*`.
> - **NEVER** delete the bundle (Axiom 18; user manages bundle lifecycle).
> - **NEVER** remove the currently-active worktree from inside (Axiom 11).
>
> If a removal/deletion fails (e.g., the worktree was already removed by a concurrent agent OR the branch was already deleted): HALT, keep all backup refs and bundle artifacts intact, rebuild the cleanup plan from the current state before continuing. Do not continue on stale assumptions.
>
> Output: counts removed/deleted per bucket; the `cleanup_log.tsv` path.

**Exit criteria:** `git worktree list` matches the expected count (typically: protected worktrees + the active one); `git branch` matches expected count (canonical + protected + rationalization branch); every backup ref still resolves; `cleanup_log.tsv` has one row per operation; `cleanup_authorization.txt` exists with verbatim user text + UTC timestamp.

**Common-mistake hints:**
- The plan changes order of operations within branches (garbage first, applied-keepers last) but worktrees ALWAYS come before branches. A branch with an active worktree pinning it cannot be deleted by `git branch -d`/`-D`.
- "Yes" / "go ahead" is too vague. The authorization phrase MUST quote a literal command from the plan or include explicit counts ("yes I understand and want to remove 44 worktrees and delete 181 branches per the plan above"). Per [INCIDENT-PLAYBOOK.md I5](INCIDENT-PLAYBOOK.md#i5).
- A branch deleted by `-D` is recoverable via `refs/branch-rationalization-backup/<slug>` AND via the bundle. The skill never destroys both layers (Axiom 18).
- After the run: `git worktree prune` once; never as a replacement for explicit `git worktree remove`.

---

## Phase 11 — Handoff Reporter

**Inputs:** all workspace artifacts; `project_profile.json`; rationalization branch tip; bundle path.

**Outputs:** `{WORKSPACE}/handoff_report.md`; a beads issue (if `br` available); a Mail thread update.

**Prompt template:**

> Emit `{WORKSPACE}/handoff_report.md` per the template in [PHASES.md § Phase 11](PHASES.md#phase-11-handoff--follow-ups-1020-min). Include:
>
> - Project, run date, mode, rationalization branch, bundle path
> - Counts per verdict (initial → triaged → applied → folded → dropped → user-resolved)
> - Recovered commit SHAs from `apply_log.tsv` + `partial_split_log.tsv`, with strategy + source branches per row
> - Harmonization summary — one row per file, listing variants merged + result
> - Recovery recipes (verbatim shell snippets from [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md)) — at minimum: recover by backup ref, recover by bundle fetch, recover by per-branch diff, recover by format-patch series, recover a worktree's dirty state
> - Active-worktree note — the user's CWD wasn't removed; the user removes it themselves from a different working directory if they want to (per [Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms))
> - Push instructions — the skill never pushes; print `git push origin {RATIONALIZATION_BRANCH}` for the user
> - Bundle lifecycle note — keep for at least one release cycle; user manages deletion
>
> Then:
>
> - File a beads issue: `br create --title "branch+worktree rationalization on {basename} ({W} worktrees, {B} branches)" --type=task --priority=4`. Body links to the report, the bundle, and the rationalization branch.
> - Update the Agent Mail thread (`thread_id=branch-rationalization-{RUN_ID}`) with: `[{beads-id}] Branch+worktree rationalization complete; see handoff_report.md`.
> - If `bv` is available: `bv --robot-triage` to surface follow-up items the recovered commits may unblock; append a brief summary to the report.
>
> Print the push command verbatim. Do NOT push. Do NOT delete the bundle.

**Exit criteria:** `handoff_report.md` exists with all sections filled; beads issue filed (or `beads_skipped: true; reason: <reason>` recorded); Mail thread updated; user told the push command verbatim.

**Common-mistake hints:**
- Counts in the report come from `.tsv` files, not from agent memory. Per [KEY-INSIGHTS.md §I-14](KEY-INSIGHTS.md): "If `cleanup_log.tsv` doesn't exist, no cleanup happened."
- The active-worktree note matters — users frequently expect the skill to "clean everything" and don't realize their CWD survived. Be explicit.
- Bundle deletion is NEVER suggested (Axiom 18). The user decides bundle lifecycle.

---

## Phase 12 — User-Lens Reviewer (optional)

**Inputs:** `handoff_report.md`, `apply_log.tsv`, `cleanup_log.tsv`, `conflicts/*.context.md`, `harmonization_plan.md`.

**Outputs:** `{WORKSPACE}/skill_feedback.md`.

**Prompt template:**

> [MODE: Forensic + Adversarial]
>
> A fresh agent reviews the entire run from the perspective: "Did this branch+worktree rationalization save the user time? Where did it surface friction? Was the harmonization plan readable? Were the verbatim authorization gates the right amount of friction? What would have made it better?"
>
> Read `handoff_report.md`, `apply_log.tsv`, `cleanup_log.tsv`, any `conflicts/*.context.md`, and `harmonization_plan.md`. Identify:
>
> - Phases where the user had to wait or repeat themselves
> - Decisions where the rubric or harmonization principles were ambiguous
> - Missing operators or unclear failure-mode coverage
> - Any silent fallbacks the user didn't realize happened (e.g., a `divergent-refactor` skipped without explicit user OK; a fingerprint match that should have been flagged for same-signature verification)
> - Whether the harmonization commits' messages successfully answered "where did this hunk come from?" without requiring the user to leave the commit message
> - Whether the verbatim-authorization gates felt like meaningful safety or like friction
>
> Write findings to `{WORKSPACE}/skill_feedback.md` with one section per friction point. For each, propose a concrete change to this skill's SKILL.md, references/, scripts/, or subagents/.
>
> Optionally, file beads issues against this skill itself for skill maintainers.

**Exit criteria:** `skill_feedback.md` exists with one section per friction point; each section has a concrete proposed change + the artifact that would change.

**Common-mistake hints:**
- This phase is for skill maintainers, not for the end user's repo cleanup. Don't run by default.
- Don't propose changes that would break the kernel axioms — the kernel was learned the hard way (per [KEY-INSIGHTS.md §I-25](KEY-INSIGHTS.md)).
- Compare the user's experience here against past sessions in cass when available; recurring friction across runs is the strongest signal.

---

## Cross-References

- Phase-by-phase playbook + exit criteria: [PHASES.md](PHASES.md)
- Operator definitions and prompt modules: [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md)
- Triage verdict catalogue + confidence calibration: [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md)
- Harmonization methodology + worked example: [HARMONIZATION.md](HARMONIZATION.md)
- Reading stance tags: [MODES-OF-REASONING.md](MODES-OF-REASONING.md)
- Multi-model paths: [MULTI-MODEL-TRIANGULATION.md](MULTI-MODEL-TRIANGULATION.md)
- Mid-run incidents: [INCIDENT-PLAYBOOK.md](INCIDENT-PLAYBOOK.md)
- The verbatim mode kickoff text: [KICKOFF-PROMPTS.md](KICKOFF-PROMPTS.md)
