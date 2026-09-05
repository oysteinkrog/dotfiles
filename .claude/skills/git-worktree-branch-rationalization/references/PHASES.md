# Phases 0–12 Playbook

Detailed exit criteria, deliverables, and agent fan-out for each phase. The main agent is the orchestrator; subagents do work in parallel where independent. The phase loop is mandatory; gates (Phases 3, 6, 7, 10) cannot be skipped.

> **Why:** Per [SKILL.md Axiom 3](../SKILL.md#the-rationalization-kernel-universal-axioms), "Plan for irreversibility first, classification second." Phase 3 is the irreversibility gate; everything destructive depends on it having completed cleanly.

---

## Mode Variants

The skill ships four run modes. Pick at Phase 0 (Up-Front Confirmations) based on the worktree count `W`, branch count `B`, presence of dirty worktrees, monorepo / submodule complexity, and whether content is production-critical or security-sensitive. Each mode keeps the same 13 phases (Phase 0 through Phase 12) but varies *depth* — fan-out width and review pass counts.

| Phase | Quick (W<5, B<30) | Standard (W 5–20, B 30–100) | Comprehensive (W 20+, B 100+) | Council (production-critical) |
|-------|-------------------|------------------------------|-------------------------------|-------------------------------|
| 0 Intake | Single agent, 5 min | Single agent, 5 min | Single agent, 10 min | Single agent + double-checked confirmation, 15 min |
| 1 Profile | Main agent reads AGENTS.md + README, 5 min | + `/codebase-report` subagent, 10 min | + `/codebase-archaeology` for branching/merge style, 15 min | + multi-model triangulation on architecture summary, 20 min |
| 2 Inventory | Main agent | Main agent | Main agent | Main agent + double-pass verify |
| 3 Bundle | Main agent | Main agent | Main agent + redundant byte-equality + bundle-round-trip verification | Main agent + redundant verification + offline copy of `object-bundle.pack` |
| 4 Protection | User confirms initial list | User confirms + reviews auto-detected protected-by-convention patterns | + reviews stale-locked worktrees, `[gone]`-tracking branches | + multi-model adjudicates ambiguous candidates |
| 5 Triage | 1 worker, serial | 2–4 workers, ~10 entries each | 5+ workers; archaeology subagent for `novel-but-stale` candidates | 12+ workers; multi-model triangulation on every borderline verdict |
| 6 Merge | Main agent | Main agent | Main agent + idea-wizard cross-check on borderline verdicts | Main agent + multi-model adjudication |
| 7 Harmonization | Skipped unless ≥2 branches collide on the same file | Activated when ≥2 branches collide on same file | Dedicated harmonization-planner subagent; one fan-out per colliding-file group | Council triangulation on the variant matrix |
| 8 Apply | 1 applier (sequential) | 1 applier (sequential by definition) | 1 applier; multi-model review of conflict resolutions | 1 applier; multi-model review of conflict + harmonized-synthesis commits |
| 8b Partial-split | 1 splitter | 1 splitter | 1 splitter + dedicated archaeology | 1 splitter + multi-model review |
| 9 Fresh-eyes | 1 round, 1 model | ≥2 rounds, 1 model | ≥3 rounds, 3 independent models, adjudicated | ≥3 rounds, multi-model adjudicated |
| 10 Cleanup | Single gated authorization | Single gated authorization | Single plan-level authorization with commands grouped by bucket | Plan-level authorization + per-bucket re-confirmation |
| 11 Handoff | Brief report | Standard report + beads issue | Full report + beads issue + bv triage | Full report + beads issue + bv triage + retro |
| 12 User-lens | Skipped | Skipped | Optional | Optional fresh-agent retrospective |

Mode is recorded in `project_profile.json` at Phase 1. Phase gates (especially Phase 9 termination) adjust based on mode.

> **Why:** Per [SKILL.md "Mode Variants"](../SKILL.md#mode-variants), "Mode is recorded in `project_profile.json` at Phase 1. Phase gates (especially Phase 9 termination) adjust based on mode." Single source of truth; never re-derived.

---

## Phase 0: Intake (5–15 min, main agent)

Before any subagent fans out:

1. **Confirm inputs** with user via `assets/intake-prompt.md`: target path, mode, output mode, rationalization-branch name, bundle path, initial protection list, remote-cleanup scope. See SKILL.md § Up-Front Confirmations.
2. **Clone if URL** — clone to `/tmp/<basename>` and treat the cloned path as the source from then on.
3. **Refuse non-git paths** — `git -C <path> rev-parse --is-inside-work-tree` must return `true`. Bare repos refused.
4. **Refuse mid-rebase / mid-merge / mid-cherry-pick / mid-bisect** on the active worktree — `git -C <path> status` shows `interactive rebase in progress` or unmerged paths or `BISECT_LOG` exists → ask user to finish first. Only the active worktree is checked here; in-flight state in *other* worktrees is captured in Phase 2 inventory.
5. **Initialize workspace**:
   ```bash
   mkdir -p <project>/.worktree_branch_rationalization_workspace/{triage,conflicts}
   ```
   The skill ensures `.worktree_branch_rationalization_workspace/` is excluded from staging via the workspace's own `.gitignore`; do not auto-edit `.git/info/exclude` during setup. (The directory name itself starts with `.` so most tools ignore it by default.)
6. **Snapshot working tree state** in *every* worktree to `wt_phase0.txt`:
   ```bash
   scripts/snapshot-tree.sh <project> phase0
   ```
   This captures `git status --porcelain=v2` per worktree path so concurrent-agent drift is detectable later (Axiom 12).
7. **Counts up front:**
   ```bash
   git -C <project> worktree list --porcelain | grep -c '^worktree '
   git -C <project> branch | wc -l
   ```
   Tell the user the magnitudes *before* asking them to commit time. >20 worktrees or >100 branches is rare enough that users genuinely don't know they have that many.
8. **Resume vs fresh:** if `.worktree_branch_rationalization_workspace/` already exists, offer (a) resume from saved state, (b) archive old workspace under timestamped suffix and start fresh, or (c) abort.

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | Skip the per-worktree snapshot if W < 2 (just the active one) |
| Standard | Standard intake |
| Comprehensive | + read AGENTS.md / CLAUDE.md / `.cursor/rules/*` carefully before profiling |
| Council | + multi-model triangulation on the intake summary; record consensus in `project_profile.json` |

**Exit criteria:** User confirmed inputs; workspace exists; per-worktree working-tree state captured; counts surfaced; resume decision made.

**Deliverables:** `project_profile.json` (skeleton; Phase 1 fills in), `wt_phase0.txt`, `bundle_path.txt` (placeholder).

**Agent fan-out:** Main agent only.

---

## Phase 1: Project Reconnaissance (5–20 min, single subagent)

Spawn the project-profiler subagent (see `subagents/project-profiler.md`). Its prompt is the **Brennerian opener** verbatim:

> "First read ALL of the AGENTS.md file (or AGENT.md, CLAUDE.md, .cursor/rules/*, .github/copilot-instructions.md — whatever the project uses) and the README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code and technical architecture and purpose of the project."

The subagent then detects:

- **Canonical branch** — `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null` first, then `git config init.defaultBranch`, then a heuristic against the actual ref list (look for `main`, `master`, `develop`, `trunk`, `default` in that priority order). **Never** assume `main` (Axiom 5).
- **Branching model** — trunk-based (only the canonical branch + ephemeral feature branches), GitFlow (long-running `develop`), release-branches, monorepo with multiple long-lived heads.
- **Merge style preference** — squash-merge / rebase-and-merge / merge-commit / merge-with-no-ff. Detected from CI `.github/workflows/*.yml` "merge_method" hints, recent `git log --merges` patterns on canonical, and project conventions in AGENTS.md / CONTRIBUTING.md. Drives whether `⊟ SQUASH-MERGE` or `⊠ REBASE-AND-MERGE` is the default Phase 8 strategy.
- **Protected-by-convention patterns** — regex patterns of branch names the project considers permanent: `release/*`, `hotfix/*`, `dependabot/*`, `renovate/*`, `gh-pages`, `production`, `staging`. Drives Phase 4 auto-protection.
- **Commit-message conventions** — Conventional Commits (`feat:`, `fix:`), ticket-id prefixes (`BACK-1234:`), gitmoji, free-form. Sample 50 recent commits.
- **Test command** — `cargo test`, `bun test`, `pnpm test`, `pytest`, `go test ./...`. Parsed from CI workflows + `package.json` scripts + `Makefile`.
- **Type-check command** — `cargo check`, `bun tsc --noEmit`, `mypy .`, `tsc --noEmit`, `go vet ./...`.
- **Lint command** — `cargo clippy`, `eslint`, `ruff`, `golangci-lint`.
- **Formatter** — `cargo fmt`, `prettier`, `ruff format`, `gofmt`.
- **CI gates** — UBS (presence of `.ubsignore`), dcg (presence of `dcg` in PATH or settings), pre-commit / husky / lefthook.
- **Branch name conventions actually used** — sample existing branches for prefix patterns. (Hypothetical asupersync repo had `agent-cc-12-*`, `agent-cod-3-*`, `wip-BACK-*`, `feature/*`, `hotfix/*`, `release/2.x`, `gh-pages`, `dependabot/*`.)

All written to `project_profile.json`.

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | Just AGENTS.md + README.md scan; commands detected from `package.json`/`Cargo.toml` headers |
| Standard | + `/codebase-report` subagent for architecture context |
| Comprehensive | + `/codebase-archaeology` deep-dive on branching model and merge style |
| Council | + multi-model triangulation on the architecture summary and merge-style detection |

**Exit criteria:** `project_profile.json` exists with non-empty `canonical_branch`, `merge_style`, `protected_by_convention_patterns`, `test_command`, `typecheck_command`, `lint_command`, `format_command`. Empty gate-command strings mean no command was detected and should be summarized to the user for correction.

**Deliverables:** `project_profile.json`.

**Agent fan-out:** 1 subagent (Quick/Standard) → 1 subagent + multi-model (Council).

---

## Phase 2: Branch/Worktree Inventory (5–15 min, single subagent — two passes)

Spawn the inventory-agent subagent. It runs **two passes** so the worktree and branch namespaces produce independent TSVs that share a join key (the branch name).

### Pass A — Worktrees

```bash
git -C <project> worktree list --porcelain > <ws>/worktrees.raw
```

For each worktree block (`worktree <path>` / `HEAD <sha>` / `branch <ref>` / optional `locked` / optional `prunable`):

```bash
# Per-worktree dirty state (from inside the worktree)
git -C <wt-path> status --porcelain=v2 > <ws>/wt_status_<slug>.txt
git -C <wt-path> diff --stat                            # tracked changes summary
git -C <wt-path> diff --cached --stat                   # staged changes summary
git -C <wt-path> ls-files --others --exclude-standard | wc -l  # untracked count
git -C <wt-path> submodule status 2>/dev/null           # per-worktree submodule init state
```

Write `worktrees.tsv`:

```
path                          branch                   head_sha   locked  prunable  tracked_changed  staged  untracked  submodules
/data/projects/foo            main                     abc123…    false   false     0                0       0          inited
/data/projects/foo-wt-cc-12   agent-cc-12-feat-parser  def456…    false   false     3                1       2          inited
/data/projects/foo-wt-cod-3   agent-cod-3-mysql-fix    789abc…    false   false     0                0       0          uninit
/data/projects/foo-wt-stale   detached                 (none)     true    true      0                0       0          n/a
```

### Pass B — Branches

```bash
git -C <project> for-each-ref refs/heads/ \
  --format='%(refname:short)|%(objectname)|%(objectname:short)|%(committerdate:iso-strict)|%(authorname)|%(subject)|%(upstream:short)|%(upstream:track)' \
  > <ws>/branches.raw
```

For each branch:

```bash
# Ahead/behind vs canonical
git -C <project> rev-list --left-right --count <canonical>...<branch>
# Patch-id-equivalence detector (Axiom 17): which commits are already on canonical?
git -C <project> cherry -v <canonical> <branch>
# Touched files since merge-base
git -C <project> diff --name-only $(git merge-base <canonical> <branch>) <branch>
# Worktree backlink: is this branch checked out in any worktree?
worktree_path=$(git -C <project> worktree list --porcelain | awk -v b="<branch>" '
  /^worktree / {wt=$2}
  /^branch refs\/heads\// {if (substr($2, 12) == b) print wt}
')
```

Write `branches.tsv` — 20 columns, in this exact order (the script `scripts/discover-branches-worktrees.sh` is the source of truth; if this doc and the script disagree, the script wins):

```
name  slug  head_sha  last_date  author  subject  ahead  behind  commits_ahead  cherry_plus  cherry_minus  upstream  upstream_status  worktree_path  touched_files  insertions  deletions  files_changed  age_days  prefix_family
```

Sample rows (illustrative; canonical itself is excluded from `branches.tsv` — it's the baseline, not a candidate):

```
agent-cc-12-feat-parser  agent-cc-12-feat-parser  def45...  2026-04-15T...  alice  feat: parser  4  2  4  3  1  origin/agent-cc-12-feat-parser  gone  /data/projects/foo-wt-cc-12  src/parse.rs,tests/parse_test.rs  142  18  7  22  agent
agent-cod-3-mysql-fix    agent-cod-3-mysql-fix    789ab...  2026-04-12T...  bob    fix: mysql    2  0  2  0  2  (none)  none  /data/projects/foo-wt-cod-3  src/db/mysql.rs  60  12  2  25  agent
release/2.x              release-2-x              1f2e3...  2026-03-01T...  carol  release 2.x   0  0  0  0  0  origin/release/2.x  present  (none)            (empty)              0    0    0  68  release
```

Notes:
- `merge_base` is **not** a column in `branches.tsv` — the script computes it for diffstats but doesn't persist it. The merge-base is captured per-branch in `<bundle>/branches/<slug>/meta.txt` (see [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md)).
- `cherry_plus` / `cherry_minus` (singular, not `cherry_pluses` / `cherry_minuses`) come straight from `git cherry -v <canonical> <branch>`: `+` lines are commits whose patch-id is *not* present on canonical; `-` lines are commits whose patch-id IS present (already-merged via squash, rebase, or cherry-pick). A branch with all `-` lines is the slam-dunk `already-merged` verdict. **Why:** [SKILL.md Axiom 17](../SKILL.md#the-rationalization-kernel-universal-axioms): "`git cherry -v` is the canonical 'is this content already on canonical' check."
- `touched_files` is comma-separated (newlines would break the TSV row); empty when the branch has no commits past the merge-base.
- `upstream_status` is one of `present` / `none` / `gone` (NOT a free-form `[gone]` marker).

### Cross-pass: Inventory grouping

Write `inventory_grouped.md` — a markdown table grouping branches by name-prefix family, with worktree-backlinks rendered inline:

```markdown
## Inventory (grouped by name-prefix family)

### `agent-cc-*` (47 branches, 23 worktrees)
- agent-cc-12-feat-parser      → /data/projects/foo-wt-cc-12   ahead 4 / behind 2
- agent-cc-13-feat-fixtures    → /data/projects/foo-wt-cc-13   ahead 1 / behind 0
- ...

### `agent-cod-*` (38 branches, 12 worktrees)
- ...

### `feature/*` (8 branches, 0 worktrees)
- ...

### `dependabot/*` (12 branches, 0 worktrees) — auto-protected by convention
- ...

### `release/*` (3 branches, 0 worktrees) — auto-protected by convention
- ...

### Detached HEAD worktrees (4)
- /data/projects/foo-wt-stale (detached, locked, prunable)
- ...
```

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | Single-pass; small repos only |
| Standard | Two-pass; serial |
| Comprehensive | Two-pass + concurrency-tolerant re-inventory if any worktree's `git status` changes between passes |
| Council | + redundant inventory via second method (`git worktree list --porcelain` parsed by an independent script) |

**Exit criteria:** `worktrees.tsv` has one row per worktree (including the active one); `branches.tsv` has one row per local branch; `inventory_grouped.md` enumerates every family; main agent posts a one-paragraph summary ("found 213 branches across 9 families and 47 worktrees, 12 of which are dirty: …") and asks for any patterns the user already knows about.

**Deliverables:** `worktrees.tsv`, `branches.tsv`, `inventory_grouped.md`.

**Agent fan-out:** 1 subagent.

---

## Phase 3: Recovery Bundle (15–60 min, single subagent — HARD GATE)

This phase MUST complete with byte-equality + bundle-round-trip verified before any classification logic runs. **If the bundle is wrong, the entire run is unsafe.**

> **Why:** [SKILL.md Axiom 3](../SKILL.md#the-rationalization-kernel-universal-axioms) — "An incorrect verdict is recoverable; an unrecorded removal is not. Build the safety net first."

Spawn the bundle-builder subagent. Steps:

1. **Create the bundle directory** outside the repo:
   ```bash
   BUNDLE="<project-parent>/<basename>-branch-worktree-archive-$(date -u +%Y-%m-%d)"
   mkdir -p "$BUNDLE"/{branches,worktrees}
   echo "$BUNDLE" > <ws>/bundle_path.txt
   ```

2. **Per branch in `branches.tsv`**, emit four artifacts:
   ```bash
   slug=$(echo "$name" | tr '/' '_' | tr -c '[:alnum:]_.-' '_')
   mkdir -p "$BUNDLE/branches/$slug/format-patch"

   # Layer 1: backup ref (inside .git/, byte-identical to live branch)
   git -C <project> update-ref "refs/branch-rationalization-backup/$slug" "$sha"

   # Layer 3: per-branch diff (human-readable backstop)
   git -C <project> diff --binary "$merge_base"..."$sha" \
     > "$BUNDLE/branches/$slug/diff-vs-merge-base.diff"

   # Layer 4: per-branch format-patch series (NOTE: VALID for branches — see Axiom 7)
   git -C <project> format-patch "$merge_base".."$sha" \
     -o "$BUNDLE/branches/$slug/format-patch/" \
     --binary --no-renames
   # Use --no-renames to ensure full file content is captured even when paths moved.

   # Meta + per-branch commit list
   git -C <project> log -1 --format='%H%n%P%n%ci%n%an%n%s' "$sha" \
     > "$BUNDLE/branches/$slug/meta.txt"
   git -C <project> log "$merge_base".."$sha" \
     --format='%H%t%ci%t%an%t%s' \
     > "$BUNDLE/branches/$slug/commits.tsv"
   ```

3. **Per worktree in `worktrees.tsv`**, capture dirty state:
   ```bash
   wt_slug=$(echo "$path" | tr '/' '_' | tr -c '[:alnum:]_.-' '_')
   mkdir -p "$BUNDLE/worktrees/$wt_slug"

   # Status snapshot
   (cd "$path" && git status --porcelain=v2 > "$BUNDLE/worktrees/$wt_slug/status.txt")

   # Staged diff (Layer 1 for worktree dirty state)
   (cd "$path" && git diff --binary --cached) > "$BUNDLE/worktrees/$wt_slug/staged.diff"

   # Unstaged diff (Layer 2 for worktree dirty state)
   (cd "$path" && git diff --binary) > "$BUNDLE/worktrees/$wt_slug/unstaged.diff"

   # Untracked tarball (Layer 3 for worktree dirty state) — only if untracked content exists
   git -C "$path" ls-files --others --exclude-standard -z > "$BUNDLE/worktrees/$wt_slug/.untracked.list"
   if [ -s "$BUNDLE/worktrees/$wt_slug/.untracked.list" ]; then
     tar --null -czf "$BUNDLE/worktrees/$wt_slug/untracked.tar.gz" \
       -C "$path" \
       -T "$BUNDLE/worktrees/$wt_slug/.untracked.list"
   fi

   # Meta
   cat > "$BUNDLE/worktrees/$wt_slug/meta.txt" <<EOF
   path: $path
   branch: $branch
   head_sha: $head_sha
   locked: $locked
   prunable: $prunable
   captured_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
   EOF
   ```

4. **Object bundle (Layer 2 across all branches)** — a single git-bundle-pack file over the entire backup namespace:
   ```bash
   git -C <project> bundle create "$BUNDLE/object-bundle.pack" \
     --stdin <<< "refs/branch-rationalization-backup/*"
   # Survives gc, repo relocation, even total .git/ corruption.
   ```

5. **Write `index.tsv`** — one row per branch AND per worktree:
   ```
   kind     name                       sha     merge_base  verdict_pending  bundle_paths
   branch   agent-cc-12-feat-parser    def45   abc12       (pending)        branches/agent-cc-12-feat-parser/diff-vs-merge-base.diff,branches/agent-cc-12-feat-parser/format-patch/,refs/branch-rationalization-backup/agent-cc-12-feat-parser
   worktree /data/projects/foo-wt-cc-12 -      -           (pending)        worktrees/_data_projects_foo-wt-cc-12/staged.diff,worktrees/_data_projects_foo-wt-cc-12/unstaged.diff,worktrees/_data_projects_foo-wt-cc-12/.untracked.list,worktrees/_data_projects_foo-wt-cc-12/untracked.tar.gz
   ```

6. **Write `README.md`** at the bundle root with recovery recipes verbatim (see [RECOVERY-RECIPES.md](RECOVERY-RECIPES.md)) AND a cross-link to the **`format-patch` IS valid for branches** axiom: a future reader who came from `git-stash-janitor` should not assume the "format-patch is wrong" rule generalizes (Axiom 7).

7. **Verify byte-equality + bundle round-trip** via `scripts/verify-bundle.sh`:
   ```bash
   # Layer 1 byte-equality: live branch SHA must equal backup ref
   for slug in $(ls "$BUNDLE/branches"); do
     live_sha=$(git -C <project> rev-parse "refs/heads/$(unslug $slug)")
     backup_sha=$(git -C <project> rev-parse "refs/branch-rationalization-backup/$slug")
     [[ "$live_sha" == "$backup_sha" ]] || die "MISMATCH: branch $slug"

     # Layer 3 round-trip: regenerate diff from live branch, sha256-compare
     live_diff=$(git -C <project> diff --binary "$(git merge-base <canonical> $live_sha)..$live_sha" | sha256sum | awk '{print $1}')
     bundle_diff=$(sha256sum "$BUNDLE/branches/$slug/diff-vs-merge-base.diff" | awk '{print $1}')
     [[ "$live_diff" == "$bundle_diff" ]] || die "DIFF MISMATCH: branch $slug"
   done

   # Layer 2 round-trip: bundle list-heads should enumerate every backup ref
   git bundle list-heads "$BUNDLE/object-bundle.pack" \
     | awk '{print $2}' \
     > "$BUNDLE/_bundle_heads.txt"
   diff <(sort "$BUNDLE/_bundle_heads.txt") <(git -C <project> for-each-ref refs/branch-rationalization-backup/ --format='%(refname)' | sort) \
     || die "BUNDLE HEAD MISMATCH"
   ```
   Write all results to `bundle_verification.log`. **Any mismatch halts the run.**

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | Single byte-equality pass; bundle round-trip |
| Standard | Same; verbose log |
| Comprehensive | Redundant verification: regenerate diffs from `object-bundle.pack` → byte-compare against on-disk `branches/<slug>/diff-vs-merge-base.diff` |
| Council | + offline copy of `object-bundle.pack` to a second filesystem path (e.g., `/tmp/`) |

**Exit criteria:** Every branch has backup ref + diff + format-patch series + meta + commits.tsv; every worktree has staged.diff + unstaged.diff + `.untracked.list` + untracked.tar.gz (if applicable) + status + meta; `object-bundle.pack` is non-empty and round-trips; `bundle_verification.log` has zero `MISMATCH` lines; main agent posts the bundle path to the user and asks them to keep it safe.

**Deliverables:** `<bundle>/` with all artifacts; `bundle_path.txt`; `bundle_verification.log`.

**Agent fan-out:** 1 subagent (the bundle-builder).

---

## Phase 4: Protection Confirmation (USER GATE — 5–15 min, main agent)

Now that the inventory exists, present the user with the **full inventory + auto-protection list** and capture additions/removals. The user's initial protection list from Phase 0 was a heuristic; this phase grounds it in real data.

The cleanup-conductor subagent (or main agent in Quick mode):

1. Compute the auto-protected set from `project_profile.json`'s `protected_by_convention_patterns` + the canonical branch + the currently-checked-out branch + every branch with an active worktree the user already flagged in Phase 0.
2. Display:
   ```markdown
   ## Auto-protected (will NEVER be deleted or removed):
   - main (canonical)
   - release/2.x (matches release/* convention)
   - dependabot/cargo-1.234 (matches dependabot/* convention)
   - gh-pages (matches gh-pages convention)
   - agent-cc-12-feat-parser (currently checked out by user in /data/projects/foo)

   ## User-flagged at Phase 0:
   - agent-jeff-active-rewrite (user's note: "still working on this")

   ## NOT protected (will enter triage):
   - 198 other branches across the families …
   - 46 other worktrees including 11 dirty ones (see worktrees.tsv)
   ```
3. Ask: "Add anything to the protected list? Remove anything?" — capture into `protected.tsv`:
   ```
   kind      name                              reason
   branch    main                              canonical
   branch    release/2.x                       matches release/* (project_profile.json)
   branch    dependabot/cargo-1.234            matches dependabot/* (project_profile.json)
   branch    gh-pages                          matches gh-pages (project_profile.json)
   branch    agent-cc-12-feat-parser           currently-checked-out (cwd)
   branch    agent-jeff-active-rewrite         user-flagged at Phase 0: "still working on this"
   worktree  /data/projects/foo                active (user's CWD)
   worktree  /data/projects/foo-wt-cc-12       checked-out branch is protected
   ```
4. Re-display the post-confirmation list and wait for explicit user OK.

**No destructive actions yet.** This phase produces zero commits, zero removals.

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | Auto-protected list only; quick yes/no |
| Standard | Auto-protected + user review of protected-by-convention candidates |
| Comprehensive | + review of stale-locked worktrees and `[gone]`-tracking branches (these have unique commits per the failure-modes table) |
| Council | + multi-model adjudication on ambiguous candidates (e.g., long-lived feature branches that look semi-active) |

**Exit criteria:** `protected.tsv` reflects the user-confirmed protection set; main agent has explicit user OK; no protected entry will enter Phase 5 triage.

**Deliverables:** `protected.tsv`.

**Agent fan-out:** Main agent only (Quick) → main agent + reviewer subagent (Council).

---

## Phase 5: Triage Fan-Out (parallel, 30–120 min)

Partition the non-protected entries (from `branches.tsv` + `worktrees.tsv` minus `protected.tsv`) into batches of ~10 each. Spawn one triage-worker subagent per batch.

**Each worker, for every entry in its batch:**

1. **For a branch:**
   1. Read `<bundle>/branches/<slug>/diff-vs-merge-base.diff`.
   2. **`✦ FINGERPRINT`** — extract introduced symbols (functions, types, tests, fixture strings, file paths). See [OPERATOR-LIBRARY.md § ✦ FINGERPRINT](OPERATOR-LIBRARY.md#-fingerprint).
   3. **`◐ VERIFY-ON-CANONICAL`** — for each fingerprint, search canonical and decide: is it already there with equivalent semantics? Sample same-signature on at least 3 introduced symbols. **Why:** [Axiom 16](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Same-name on canonical is not always supersession."
   4. **`git cherry -v <canonical> <branch>`** — already in `branches.tsv`. If all `-` lines: candidate `already-merged`.
   5. **APPLY-CHECK PROBE** — `git cherry-pick --no-commit -X theirs <sha>` on a throwaway branch from canonical, then `git cherry-pick --abort`. Record exit code as `apply_check`.
   6. **VERDICT** — by [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md). Includes evidence + confidence + strategy + files-touched.
2. **For a worktree:**
   1. Read `<bundle>/worktrees/<wt-slug>/staged.diff` + `unstaged.diff`.
   2. If the diffs are empty AND no `.untracked.list` / `untracked.tar.gz`: this worktree is just a checkout of a branch — its verdict piggybacks on the underlying branch's verdict.
   3. If the diffs are non-empty: **`✦ FINGERPRINT`** the dirty state independently. The verdict is `dirty-worktree-only` if the dirty state introduces fingerprints not on the underlying branch nor on canonical.
3. **Write a row** to `.worktree_branch_rationalization_workspace/triage/batch_<NNN>.tsv`:
   ```
   kind     name                        verdict             confidence  evidence_on_canonical   apply_check  fingerprint_summary                              strategy             files_touched
   branch   agent-cc-12-feat-parser     novel-and-accretive 0.92        none                    clean        Parser::parse_v3, test_parse_v3_overflow         cherry-pick          src/parser.rs,tests/parser.rs
   branch   agent-cod-3-mysql-fix       already-merged      0.99        cherry -v all "-"       n/a          n/a                                              skip                 (none)
   branch   agent-cc-77-feature         superseded          0.95        src/auth.rs:317,412     clean        validate_token, refresh_jwt                      skip                 src/auth.rs
   worktree /data/projects/foo-wt-stale dirty-worktree-only 0.80        none                    clean        debug_dump_state fn (only in unstaged.diff)      worktree-dirty-state src/debug.rs
   ```

**See [TRIAGE-RUBRIC.md](TRIAGE-RUBRIC.md) for the full verdict catalogue, confidence calibration, and worked examples.**

**Coordination:** Workers reserve their batch TSV via Agent Mail (`thread_id=branch-rationalization-<run-id>`, `reason="triage-batch-NNN"`). They write only to their own batch TSV; the merger (Phase 6) reads all of them.

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | 1 worker, serial |
| Standard | 2–4 workers; archaeology subagent for `novel-but-stale` candidates |
| Comprehensive | 5+ workers; multi-pass through borderline (confidence < 0.8) verdicts |
| Council | 12+ workers; multi-model triangulation on every borderline verdict |

**Exit criteria:** Every non-protected entry has exactly one row across all `batch_*.tsv` files; no row has empty `verdict` or `confidence`; main agent merges into `triage.tsv` and posts batch-level summary counts ("47 already-merged, 89 superseded, 23 novel-and-accretive, 12 partially-novel, 18 garbage, 4 unknown").

**Deliverables:** `triage/batch_*.tsv` (worker outputs), `triage.tsv` (merged).

**Agent fan-out:** N workers parallel (per mode tier).

---

## Phase 6: Triage Merge & Confirm (USER GATE)

Spawn the triage-merger subagent. It:

1. Reads all `batch_*.tsv` and writes the unified `triage.tsv`.
2. Builds `triage_decision.md` — a markdown table for the user, sorted by verdict and confidence:

   ```markdown
   ## Triage decision (213 branches + 47 worktrees, sorted by verdict)

   ### KEEP-AS-PROTECTED (6) — frozen at Phase 4
   <details><summary>protected entries</summary> ... </details>

   ### KEEP — novel-and-accretive (23)
   | name                          | files | evidence | proposed strategy |
   |-------------------------------|-------|----------|-------------------|
   | agent-cc-12-feat-parser       | 2     | none on canonical | cherry-pick |
   | agent-cc-15-feat-fixtures     | 1     | none on canonical | cherry-pick |
   | …                             |       |          |                   |

   ### KEEP-WITH-SPLIT — partially-novel (12)
   | name | hunks novel / total | proposed strategy |
   | …    |                     |                   |

   ### HARMONIZE — files touched by ≥2 non-protected branches (Phase 7) (8 file-groups)
   - `src/parser.rs` ← agent-cc-12-feat-parser, agent-cc-77-feat-parser-v2, agent-cod-3-parser-fix
   - `src/auth.rs`   ← agent-cc-44-jwt, agent-cc-66-jwt-v2
   - …

   ### DROP — already-merged (47)
   <details><summary>47 entries</summary>
   | name | merge_base evidence |
   |------|---------------------|
   | agent-cod-3-mysql-fix | git cherry -v: all `-` lines |
   | …    |                     |
   </details>

   ### DROP — superseded (89)
   <details><summary>89 entries</summary> ... </details>

   ### DROP — garbage (18)
   <details><summary>18 entries</summary> ... </details>

   ### MANUAL — novel-but-stale (4)
   | name | reason | proposed action |
   | …    |        |                 |

   ### MANUAL — divergent-refactor (3)
   | name | colliding-files | proposed action |
   | …    |                 |                 |

   ### MANUAL — dirty-worktree-only (5)
   | path | fingerprints | proposed action |
   | …    |              |                 |

   ### MANUAL — unknown (4) — flagged for user
   | name | confidence | reason |
   | …    |            |        |
   ```

3. **Presents the table to the user verbatim** and waits for explicit go-ahead.
4. Captures any user overrides — "actually keep `agent-cc-77-feature`, I'm going to revisit it" — into `user_overrides.tsv`. Apply overrides to `triage.tsv` (the merged file is the source of truth from now on).
5. Re-asks confirmation if overrides change >5 verdicts (sanity check).

**No destructive actions yet.** This phase produces zero commits, zero deletions.

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | Single agent; minimal table |
| Standard | + idea-wizard cross-check on any verdict the user overrode (sanity check on the override) |
| Comprehensive | + multi-model adjudication on borderline (confidence 0.6–0.8) verdicts before user sees them |
| Council | All Comprehensive + the user-facing table is reviewed by a fresh-eyes subagent before display |

**Exit criteria:** User explicitly typed "go" / "proceed" / "approved" (or a phrase that includes one of those words); `triage.tsv` has the user-confirmed verdicts; main agent shows the user the next-step plan ("I'll now build the harmonization plan for the 8 file-groups, present it for your review, then apply 23 keepers + 12 partial-splits + 8 harmonized syntheses, then come back for cleanup authorization").

**Deliverables:** `triage_decision.md`, `user_overrides.tsv`, finalized `triage.tsv`.

**Agent fan-out:** 1 subagent (merger) + main agent.

---

## Phase 7: Harmonization Plan (USER GATE — the conceptual centerpiece)

This is the cognitive move that distinguishes this skill from `git-stash-janitor`. **Why:** [Axiom 1](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Harmonize, don't pick. For any file touched by more than one non-protected branch, the job is NOT to choose between competing variants. The job is to inspect every variant, reason about each part's intent, and synthesize the strongest current implementation on top of canonical's architecture."

Spawn the harmonization-planner subagent (Comprehensive/Council) or run inline (Quick/Standard).

### Step 1: Identify colliding-file groups

From `triage.tsv` filtered to non-protected, non-already-merged, non-garbage entries, build a multi-map: file → set of branches touching that file. Any file with set size ≥ 2 is a colliding-file group. (Plus any dirty-worktree-only entry that touches a file also touched by a branch.)

### Step 2: Per-file variant matrix

For each colliding file, build the variant matrix:

```markdown
## File: src/parser.rs

| Variant            | Source                                        | Touched lines | Intent                                                |
|--------------------|-----------------------------------------------|---------------|-------------------------------------------------------|
| canonical (main)   | abc12 — `Parser::parse` baseline              | 1–500         | current architecture; baseline                        |
| agent-cc-12        | def45 — `Parser::parse_v3`                    | 120–145, 200–218 | introduces v3 parser with proper error handling     |
| agent-cc-77        | 789ab — `Parser::parse_v3_alt`                | 120–145, 250–280 | alternative v3 with stricter validation              |
| agent-cod-3        | f1e2c — `Parser::parse_v2_fix`                | 120–145       | defensive null-check for empty input                  |
| dirty:foo-wt-stale | unstaged — `Parser::parse_v3` + tracing logs  | 120–145, 320  | adds tracing instrumentation for debugging           |

### Intent groups

- **Defensive null-check** (cod-3 lines 120–145) — concrete bug fix; should always land
- **v3 architecture** (cc-12 lines 120–145, 200–218) — the more complete version; the one to base the synthesis on
- **Stricter validation** (cc-77 lines 250–280) — useful additional check, can be grafted onto cc-12's structure
- **Tracing instrumentation** (dirty lines 320) — useful but separable; goes in its own commit OR is dropped if the user doesn't want runtime tracing landed

### Proposed synthesis (lands on branch-rationalization-<DATE> as one focused commit)

  Take cc-12's `Parser::parse_v3` as the structural base.
  Graft cod-3's defensive null-check at line 122–124 (verbatim).
  Graft cc-77's stricter validation block at line 252–262 (re-flowed for v3 error type).
  Drop the tracing instrumentation (separable concern; user can add later).

### Why this beats any single variant

- cc-12 alone is missing cod-3's null-check (concrete bug fix).
- cc-77 alone has the stricter validation but on top of v2's structure (the wrong base).
- cod-3 alone fixes one bug but doesn't bring v3's improved error handling.
- Synthesis combines the strongest current implementation of each concern on top of canonical's architecture.

### Source-branch credit (for the commit message)

  cc-12 (v3 base), cod-3 (defensive null-check), cc-77 (stricter validation),
  rebased onto canonical's tip.
```

### Step 3: Write `harmonization_plan.md`

The full file is a sequence of these per-file blocks, plus a summary table at the top:

```markdown
# Harmonization Plan — branch-rationalization-2026-05-07

8 colliding-file groups identified. Synthesis lands as 8 focused commits on
`branch-rationalization-2026-05-07`.

| File                    | Variants | Synthesis strategy   | Phase 8 strategy        |
|-------------------------|----------|----------------------|-------------------------|
| src/parser.rs           | 4        | base=cc-12 + grafts  | harmonized-synthesis-via-Edit |
| src/auth.rs             | 2        | base=cc-44 + check   | harmonized-synthesis-via-Edit |
| tests/parser_corpus.rs  | 3        | union of fixtures    | harmonized-synthesis-via-Edit |
| …                       |          |                      |                         |

## Per-file variant matrices

[8 sections like above]
```

### Step 4: Present to user; wait for review BEFORE Phase 8 mutates anything

The user reviews the plan. Common overrides:
- "Drop cc-77's stricter validation; that was abandoned for a reason."
- "The tracing instrumentation should land in its own commit on the rationalization branch — keep it."
- "src/auth.rs synthesis is too ambitious; just take cc-44 verbatim."

Capture overrides into `harmonization_plan.md` directly via the Edit tool — the document is the spec for Phase 8.

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | Skipped unless ≥2 branches collide on the same file (rare in Quick scope) |
| Standard | Activated; single planner |
| Comprehensive | Dedicated harmonization-planner subagent; one fan-out per colliding-file group (≥3 groups = parallel) |
| Council | Council triangulation on the variant matrix; fresh-eyes review of the proposed syntheses before user sees them |

**Exit criteria:** `harmonization_plan.md` exists with one block per colliding-file group; user has explicitly OK'd the plan (or applied overrides via Edit); the plan is the spec Phase 8 follows.

**Deliverables:** `harmonization_plan.md`.

**Agent fan-out:** Main agent (Quick/Standard) → 1 planner subagent (Comprehensive) → planner + multi-model triangulation (Council).

---

## Phase 8: Rationalization + Apply (sequential, 60–240 min)

Each apply changes the 3-way base for later applies, and the rationalization branch's tip can flip downstream verdicts (`⊞ RE-FINGERPRINT`). This phase is sequential by definition.

The keeper-applier subagent:

1. **Cut the rationalization branch off canonical's tip:**
   ```bash
   rb=branch-rationalization-$(date -u +%Y-%m-%d)
   if git -C <project> show-ref --verify --quiet "refs/heads/$rb"; then
     git -C <project> checkout "$rb"   # resume; do not reset existing work
   else
     git -C <project> checkout -b "$rb" "<canonical>"
   fi
   ```

   > **Why:** [Axiom 6](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Land on a rationalization branch, not on canonical."

2. **For each row in `triage.tsv`** with verdict in `{novel-and-accretive, partially-novel, novel-but-stale, dirty-worktree-only}` AND any harmonization-plan group that includes this row, in dependency order (chronological by branch tip date by default; user-overridable):

   1. **`↺ WORKING-TREE-DRIFT` check** — re-snapshot `git status` in every active worktree; if changes appeared from concurrent agents, treat as if you made them. Per AGENTS.md "Note for Codex/GPT-5.5", never stash, revert, or overwrite. Capture in `apply_log.tsv:pre_apply_drift`.

   2. **`⊞ RE-FINGERPRINT`** — re-run FINGERPRINT/VERIFY-ON-CANONICAL against the rationalization branch's tip (which has accumulated previous keepers). If the candidate now has fingerprint coverage ≥ 0.8 on the rationalization branch, mark `superseded-during-apply` in the log and skip.

   3. **Pick the apply strategy** from `triage.tsv:strategy`:
      - **`cherry-pick`** (`✧ CHERRY-PICK`): single-commit and small-coherent branches.
        ```bash
        git cherry-pick --no-commit "$sha"
        # If clean, commit the staged result with source-branch credit.
        # If conflicted, write conflict context and git cherry-pick --abort.
        ```
      - **`squash-merge`** (`⊟ SQUASH-MERGE`): when `project_profile.json:merge_style == "squash"`.
        ```bash
        git merge --squash "$branch"
        # Single focused commit follows.
        ```
      - **`rebase-and-merge`** (`⊠ REBASE-AND-MERGE`): when `project_profile.json:merge_style == "rebase"` AND the branch is large/meaningful. Replay commits onto the rationalization branch; do not mutate the source branch.
        ```bash
        merge_base=$(git merge-base "$canonical" "$branch")
        git cherry-pick "$merge_base..$branch"
        # Source branch remains byte-identical to its backup ref.
        ```
      - **`harmonized-synthesis-via-Edit`**: per `harmonization_plan.md` — open the file in the rationalization branch's working tree, use the Edit tool to construct the synthesis (per AGENTS.md "No Script-Based Changes", Edit tool only — never sed/awk/regex), commit.
      - **`split-commits`** (`⇄ SPLIT-COMMITS-HUNKS` — Phase 8b): for `partially-novel`; cherry-pick only the novel commit subset.
      - **`worktree-dirty-state`**: apply the worktree's `staged.diff` + `unstaged.diff` via `git apply --3way`; copy untracked files through `.untracked.list` + `untracked.tar.gz`.

   4. **`⊕ RECOVER` — run quality gates** from `project_profile.json`:
      - test command (e.g., `cargo test`)
      - typecheck command (e.g., `bun tsc --noEmit`)
      - lint command (e.g., `cargo clippy -- -D warnings`)
      - UBS if available (`ubs <changed-files>`)
      - All must exit 0 OR the user has explicitly OK'd a known pre-existing failure.

      > **Why:** [Axiom 13](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Run the project's actual `test`, `typecheck`, `lint`, `ubs` after every Phase 8 apply, not just at the end. Compounding errors across recoveries are an order of magnitude harder to debug than per-keeper failures."

   5. **Commit** with a focused message that explains *why* this content is being recovered, naming source branches and variant intents:
      ```
      recover defensive null-check + v3 parser architecture, harmonized

      Synthesizes:
      - agent-cc-12 (Parser::parse_v3 base structure)
      - agent-cod-3 (defensive null-check at line 122–124)
      - agent-cc-77 (stricter validation block at line 252–262)

      The cc-12 v3 architecture is the right base — it improves the error type
      and adds the v3 entry point. Cod-3's null-check fixes a real panic on
      empty input that we're picking up here. Cc-77's stricter validation block
      is grafted on top of v3's structure (re-flowed to use the new error type).

      Recovered via: harmonized-synthesis-via-Edit per harmonization_plan.md
      Source branches: backed up at refs/branch-rationalization-backup/{agent-cc-12,agent-cod-3,agent-cc-77}
      ```
      The skill never adds `Co-Authored-By` lines unless the user asks.

   6. **Append to `apply_log.tsv`:**
      ```
      kind     name              new_commit_sha  files_changed  gates_status  strategy                       duration_s
      branch   agent-cc-12       def987…         2              passed        harmonized-synthesis-via-Edit  340
      branch   agent-cod-3       (folded)        0              passed        harmonized-synthesis-via-Edit  0
      branch   agent-cc-77       (folded)        0              passed        harmonized-synthesis-via-Edit  0
      ```
      "(folded)" means this branch's content was incorporated into another commit per the harmonization plan.

3. **If apply-check fails on a candidate:**
   1. **DO NOT** force the apply.
   2. Surface to the user with full context:
      - The branch's diff vs. canonical
      - The current state of the affected files on the rationalization branch
      - A hypothesis for why they conflict (often a refactor — `if/else if` → `match`, function rename, file move)
      - A proposed manual resolution (the Edit tool would do *this*)
   3. Wait for user OK. If the user says "skip", mark the row `conflict-skipped`. If the user says "fix it like that", apply the resolution via the Edit tool, then continue from the gates step.
   4. Write the conflict context to `.worktree_branch_rationalization_workspace/conflicts/branch_<slug>.context.md` so it survives compaction.

### Phase 8b: Partial-Novel Split-Apply

For each `partially-novel` row (the most error-prone variant). Gets its own pass so it doesn't compete with Phase 8's working tree.

The partial-splitter subagent, for each `partially-novel` row:

1. Identify which commits / hunks are novel (the triage rubric's per-hunk evidence).
2. Build the cherry-pick subset:
   ```bash
   # If novel commits are a contiguous range:
   git cherry-pick "$start_sha".."$end_sha"
   # If novel commits are scattered:
   git cherry-pick "$novel_sha_1" "$novel_sha_2" "$novel_sha_5"
   ```
3. If a single commit is itself partially novel: `git cherry-pick --no-commit <sha>` then use the Edit tool to remove the superseded hunks from the working tree before committing.
4. Run gates per `⊕ RECOVER`. Commit with a message that explicitly notes "split-apply: novel commits only; superseded commits dropped per triage row":
   ```
   recover novel fuzz-corpus additions from agent-cc-44-parser-refactor

   The parser refactor portion of agent-cc-44 already landed via PR #234 (cherry -v shows
   commits 1–3 as `-`). This commit recovers only the novel fuzz-corpus and overflow
   test additions (commits 5, 7, 8 of the original branch).

   Recovered via: split-apply per partial_split_log.tsv
   Source branch backed up at: refs/branch-rationalization-backup/agent-cc-44
   ```
5. Append to `partial_split_log.tsv` with commits-kept / commits-dropped counts.

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | 1 applier, sequential |
| Standard | 1 applier; conflicts surfaced one-at-a-time |
| Comprehensive | + multi-model review of any harmonized-synthesis commit |
| Council | + multi-model review of every commit + multi-model adjudication on every conflict |

**Exit criteria:** Every row in `triage.tsv` with a non-skip strategy has either a `new_commit_sha` (or `(folded)`) or a `conflict-skipped` / `superseded-during-apply` mark in `apply_log.tsv`; quality gates passed on the rationalization branch's tip.

**Deliverables:** `apply_log.tsv`, `partial_split_log.tsv`, `conflicts/branch_<slug>.context.md` (per conflict).

**Agent fan-out:** 1 applier + 1 splitter (sequential by definition).

---

## Phase 9: Fresh-Eyes Verification (≥2 rounds clean, 30–90 min)

Spawn the fresh-eyes subagent. It runs three review prompts (verbatim — they're calibrated):

1. *"Carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover."*
2. *"Sort of randomly explore the code files in this project, choosing code files to deeply investigate and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes."*
3. *"Turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep."*

Between rounds, the main agent runs:

```bash
# Project-specific (from project_profile.json):
cargo test               # or bun test, pytest, go test ./...
cargo check              # or bun tsc --noEmit, mypy ., go vet ./...
cargo clippy -- -D warnings  # or eslint, ruff, golangci-lint
ubs .                    # if available
```

All must exit 0. Log each round + outcome to `fresh_eyes_log.md`.

**Termination rule:** Two consecutive full rounds (all three prompts) produce only trivial findings (typo, wording polish) AND test + typecheck + lint + UBS all green.

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | 1 round, 1 model |
| Standard | ≥2 rounds, 1 model |
| Comprehensive | ≥3 rounds, 3 independent models, adjudicated |
| Council | ≥3 rounds, multi-model adjudicated, fresh-eyes review of fresh-eyes findings |

**Exit criteria:** Fresh-eyes log shows ≥2 clean rounds (per mode); gates green on `HEAD`.

**Deliverables:** `fresh_eyes_log.md`.

**Agent fan-out:** N fresh-eyes subagents (per mode tier).

---

## Phase 10: Destructive Cleanup (GATED)

Only after Phase 9 comes up clean ≥2 times AND the user has explicitly typed an authorization phrase that includes the literal commands to be run.

> **Why:** Per AGENTS.md "Mandatory explicit plan": "Even after explicit user authorization, restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct."

The cleanup-conductor subagent:

### Step 1: Build the verbatim authorization request

The cleanup plan has a strict order: **worktrees first, branches second**. Within branches: garbage → superseded → already-merged → novel-stale → divergent-refactor (opt-in only) → applied-keepers.

> **Why:** [Axiom 9](../SKILL.md#the-rationalization-kernel-universal-axioms) — "Worktrees are removed first, branches second. A worktree pinned to a branch protects that branch from `git branch -d`."

```
I'm about to run the following destructive commands in this order:

  ## Phase A — Worktree removal (44 worktrees; 3 protected stay)
  git worktree remove /data/projects/foo-wt-cc-12
  git worktree remove /data/projects/foo-wt-cc-13
  ... (44 git worktree remove invocations, dirty ones flagged)
  git worktree prune                                # cleans residual admin metadata

  ## Phase B — Branch deletion: garbage (18)
  git branch -D agent-cc-77-broken-attempt
  git branch -D agent-cod-7-other-agent-broken
  ... (18 git branch -D invocations)

  ## Phase C — Branch deletion: superseded (89)
  git branch -d agent-cod-3-mysql-fix          # -d (lowercase) because fully merged into rationalization branch
  ... (89 git branch -d invocations)

  ## Phase D — Branch deletion: already-merged (47)
  git branch -d agent-cc-44-followup           # -d (lowercase)
  ... (47 git branch -d invocations)

  ## Phase E — Branch deletion: novel-stale (4 — user opted in)
  git branch -D agent-old-cli-flags
  ... (4 git branch -D invocations)

  ## Phase F — Branch deletion: divergent-refactor (NOT included by default; opt-in only)
  (skipped this run — user did not opt in)

  ## Phase G — Branch deletion: applied-keepers (23)
  git branch -d agent-cc-12-feat-parser        # now fully merged into rationalization branch
  ... (23 git branch -d invocations)

Backup refs at refs/branch-rationalization-backup/* and the bundle at
<bundle-path> stay intact. Worktree dirty state is captured in
<bundle>/worktrees/*/. The currently-active worktree (your CWD) is NOT
removed — you remove that yourself from a different working directory if
you want to.

To proceed, paste this verbatim:
  yes I understand and want to remove 44 worktrees and delete 181 branches per the plan above
```

### Step 2: Wait for verbatim authorization

If the user types anything different, refuse and re-ask.

### Step 3: Record the authorization

Write user's exact text + UTC timestamp to `cleanup_authorization.txt`.

> **Why:** [Axiom 14](../SKILL.md#the-rationalization-kernel-universal-axioms) — "If that file doesn't exist, the action did not happen."

### Step 4: Execute, restating verbatim per item

For each command, before running:

```
About to run: git worktree remove /data/projects/foo-wt-cc-12
(This is row in worktrees.tsv: branch=agent-cc-12-feat-parser, dirty=3 tracked + 1 staged + 2 untracked, captured in <bundle>/worktrees/_data_projects_foo-wt-cc-12/)
```

For dirty worktrees that refuse `git worktree remove`: surface to user; `--force` only after explicit user OK that the dirty state may be lost (it's still in the bundle).

> **Why:** [Axiom 11](../SKILL.md#the-rationalization-kernel-universal-axioms) — "`git worktree remove` refuses on dirty worktrees — that refusal is a feature."

After each operation, append to `cleanup_log.tsv`:

```
phase  kind      name                              command_run                                      timestamp_utc
A      worktree  /data/projects/foo-wt-cc-12       git worktree remove /data/projects/foo-wt-cc-12  2026-05-07T18:42:11Z
A      worktree  (prune)                           git worktree prune                               2026-05-07T18:55:33Z
B      branch    agent-cc-77-broken-attempt        git branch -D agent-cc-77-broken-attempt         2026-05-07T18:56:00Z
…
```

### Constraints

- **Never** run `git branch | xargs git branch -D` (Axiom 10).
- **Never** run `git push --delete`, `git push --force` (Axiom 15).
- **Never** run `rm -rf <worktree-path>` (Axiom 11; DCG blocks it).
- **Never** delete `refs/branch-rationalization-backup/*`.
- **Never** delete the bundle.
- **Never** remove the currently-active worktree from inside (Axiom 11; the user does that from a different CWD).

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | Single gated authorization |
| Standard | Single gated authorization; verbose verbatim restatement |
| Comprehensive | Plan-level authorization + per-bucket re-confirmation |
| Council | Plan-level authorization + per-bucket re-confirmation + post-cleanup audit |

**Exit criteria:** `git worktree list` matches the expected count (typically: only protected worktrees + the active one); `git branch` matches the expected count (canonical + protected + rationalization branch); every backup ref still resolves; `cleanup_log.tsv` has one row per operation; `cleanup_authorization.txt` exists with verbatim user text.

**Deliverables:** `cleanup_authorization.txt`, `cleanup_log.tsv`.

**Agent fan-out:** 1 subagent (cleanup-conductor) + main agent (gating).

---

## Phase 11: Handoff & Follow-Ups (10–20 min)

The handoff-reporter subagent emits `handoff_report.md` with:

```markdown
# Branch + Worktree Rationalization — Handoff Report

**Project:** /data/projects/asupersync
**Run date:** 2026-05-07
**Mode:** Comprehensive
**Rationalization branch:** branch-rationalization-2026-05-07
**Bundle path:** /data/projects/asupersync-branch-worktree-archive-2026-05-07/

## Counts
- Initial branches: 213 (incl. canonical)
- Initial worktrees: 47 (incl. active)
- Auto-protected (untouched): 6 branches, 3 worktrees
- Triaged: 207 branches, 44 worktrees
  - novel-and-accretive: 23 (applied)
  - partially-novel: 12 (split-applied)
  - novel-but-stale: 4 (dropped, per user)
  - divergent-refactor: 3 (skipped — user did not opt in)
  - dirty-worktree-only: 5 (3 applied, 2 dropped per user)
  - already-merged: 47 (deleted)
  - superseded: 89 (deleted)
  - garbage: 18 (deleted)
  - unknown → user-resolved: 4
- Final branches: 6 protected + canonical + rationalization branch = 8
- Final worktrees: 3 protected + active = 4
- Recovery commits authored: 8 harmonized syntheses + 23 cherry-picks + 12 split-applies + 3 dirty-state applies = 46 on `branch-rationalization-2026-05-07`

## Recovered commits
| sha       | source(s)                                          | strategy             | message                                                |
|-----------|----------------------------------------------------|----------------------|--------------------------------------------------------|
| def987... | agent-cc-12 + agent-cod-3 + agent-cc-77            | harmonized-synthesis | recover defensive null-check + v3 parser, harmonized   |
| …         | …                                                  | …                    | …                                                      |

## Harmonization summary
| File                    | Variants merged | Result                                              |
|-------------------------|-----------------|-----------------------------------------------------|
| src/parser.rs           | 4               | v3 base + null-check + stricter validation grafted  |
| src/auth.rs             | 2               | cc-44 base + extra check from cc-66                 |
| …                       |                 |                                                     |

## Recovery recipes
[See RECOVERY-RECIPES.md — every kind of removal/deletion is reversible.]

  # Recover a deleted branch by backup ref (preferred)
  git branch agent-cc-12-feat-parser refs/branch-rationalization-backup/agent-cc-12-feat-parser

  # Recover a deleted branch by bundle (when ref already pruned)
  git fetch /data/projects/asupersync-branch-worktree-archive-2026-05-07/object-bundle.pack \
    refs/branch-rationalization-backup/agent-cc-12-feat-parser:refs/heads/agent-cc-12-feat-parser

  # Recover a deleted branch by per-branch diff
  git apply /data/projects/asupersync-branch-worktree-archive-2026-05-07/branches/agent-cc-12-feat-parser/diff-vs-merge-base.diff

  # Recover a deleted branch by per-branch format-patch series
  git am /data/projects/asupersync-branch-worktree-archive-2026-05-07/branches/agent-cc-12-feat-parser/format-patch/*.patch

  # Recover a removed worktree's dirty state (re-checkout the branch in a new path, then apply)
  git worktree add /data/projects/foo-wt-recovered <branch>
  cd /data/projects/foo-wt-recovered
  git apply /data/projects/asupersync-branch-worktree-archive-2026-05-07/worktrees/_data_projects_foo-wt-cc-12/staged.diff
  git apply /data/projects/asupersync-branch-worktree-archive-2026-05-07/worktrees/_data_projects_foo-wt-cc-12/unstaged.diff
  tar --null -xzf /data/projects/asupersync-branch-worktree-archive-2026-05-07/worktrees/_data_projects_foo-wt-cc-12/untracked.tar.gz \
    -T /data/projects/asupersync-branch-worktree-archive-2026-05-07/worktrees/_data_projects_foo-wt-cc-12/.untracked.list

  # Bundle index:
  cat /data/projects/asupersync-branch-worktree-archive-2026-05-07/index.tsv

## Push instructions
The skill never pushes. To land the rationalized work:

  git push origin branch-rationalization-2026-05-07
  # Then open a PR against main for review

## Active worktree note
You are currently in /data/projects/asupersync (the main repo). The skill
did not remove this worktree — you do that yourself if you want to. The
remaining unprotected worktrees were all removed in Phase 10.

## Bundle lifecycle
The bundle lives at /data/projects/asupersync-branch-worktree-archive-2026-05-07/.
Keep it for at least one release cycle. Once you're sure nothing was
accidentally lost, move it to your normal archive/trash location with `mv`.
The skill never advises bypassing DCG or deleting the bundle itself.
```

The subagent also:

- Files a **beads issue** summarizing the run (`br create --title "branch+worktree rationalization on <project> (<W> worktrees, <B> branches)" --type=task --priority=4`); the body links to the report, the bundle, and the rationalization branch.
- Updates the Agent Mail thread (`thread_id=branch-rationalization-<run-id>`) with a final reply: "[<beads-id>] Branch+worktree rationalization complete; see handoff_report.md".
- If `bv` is available, runs `bv --robot-triage` to surface any new follow-up items the recovered commits unblock.
- Reminds the user to push.

**Mode-variant differences:**

| Mode | Difference |
|------|------------|
| Quick | Brief report; no beads |
| Standard | Standard report + beads |
| Comprehensive | Full report + beads + bv triage |
| Council | Full report + beads + bv triage + retro |

**Exit criteria:** `handoff_report.md` exists with all sections filled; beads issue filed; user told the push command.

**Deliverables:** `handoff_report.md`.

**Agent fan-out:** 1 subagent.

---

## Phase 12: User-Lens Review (OPTIONAL, off by default)

Only runs if the user explicitly asks ("review the run from a user perspective"). A fresh agent or `/idea-wizard` reviews the entire run from the perspective:

> "Did this branch+worktree rationalization save the user time? Where did it surface friction? What would have made it better? Was the harmonization plan readable? Were the verbatim authorization gates the right amount of friction?"

Files improvement notes to `.worktree_branch_rationalization_workspace/skill_feedback.md` and (optionally) opens beads issues against this skill itself.

This phase is for skill maintainers, not for the end user's repo cleanup.

---

## Idempotence & Resumability

**Idempotent on a clean repo.** If you run the skill on a repo with one canonical branch + zero non-protected branches + zero non-active worktrees, Phases 0–4 still produce their artifacts (project profile, empty inventory, empty bundle, protection list = canonical only). Phases 5+ short-circuit with "nothing to rationalize." No commits, no removals, no deletions.

> **Why:** [POLISH-BAR.md § P9 "Idempotent on a clean repo"](POLISH-BAR.md#p9-idempotent-on-a-clean-repo) — "running the skill twice in succession on a freshly-cleaned repo produces no new commits and reports 'nothing to rationalize.'"

**Resumable mid-run.** Every phase writes its artifacts before exiting. On re-entry:

- **Phase 0** — re-uses `project_profile.json` if present and ≤7 days old; offers resume vs fresh.
- **Phase 1** — re-uses `project_profile.json` if present and the canonical branch hasn't moved.
- **Phase 2** — re-runs from scratch (cheap; produces fresh `worktrees.tsv` + `branches.tsv`). The previous TSVs are renamed with a `.prev` suffix for diff inspection.
- **Phase 3** — checks if the bundle directory exists and verifies byte-equality + bundle round-trip; if yes, skips re-creation. If new branches/worktrees appeared since, the bundle is *augmented* (new entries appended to `index.tsv`); existing entries are NOT regenerated (they're frozen with their original SHAs).
- **Phase 4** — re-presents the protected list; user can re-confirm or override.
- **Phase 5** — re-runs only the batches without a complete `batch_NNN.tsv`.
- **Phase 6** — re-presents the merged table; user can re-confirm or override.
- **Phase 7** — re-uses `harmonization_plan.md` if present; user can edit it; the document IS the spec.
- **Phase 8** — reads `apply_log.tsv` and skips already-applied entries (matched by `kind|name`).
- **Phase 8b** — analogous via `partial_split_log.tsv`.
- **Phase 9** — always re-runs (verification cost is cheap relative to risk).
- **Phase 10** — refuses to re-run; if `cleanup_log.tsv` exists, it's done; the user must explicitly archive the workspace and start fresh.
- **Phase 11** — re-emits `handoff_report.md` from the latest log files.
- **Phase 12** — always optional.

When a concurrent agent creates or deletes a branch mid-run, the bundle's `index.tsv` is authoritative for that *snapshot point*; the resume logic detects the new branch via Phase 2 re-inventory and either includes it in a fresh triage round (if the user OKs) or freezes it under protection.
