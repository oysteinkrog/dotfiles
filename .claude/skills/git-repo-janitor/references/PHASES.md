# Phases 0–11 Playbook

Detailed exit criteria, deliverables, and agent fan-out for each phase. The main agent is the orchestrator; subagents do work in parallel where independent.

---

## Variants (orchestration depth)

The skill ships three **variants** that decide orchestration depth — fan-out width and review pass counts. Variants are **orthogonal to modes** (the 9 named modes in OPERATING-MODES.md decide which phases run). Pick a variant at Phase 0 based on candidate count, time budget, and the presence of secrets-suspicious filenames. Every variant runs the same phase loop; the variant only changes worker count and round count.

| Phase | Quick (5–24 candidates) | Standard (25–149) | Comprehensive (150+) |
|-------|------------------------|-------------------|----------------------|
| 1 Profile | Main agent reads AGENTS.md + README.md, 5 min | + codebase-report subagent, 10 min | + multi-model triangulation on archetype detection, 15 min |
| 2 Inventory | Main agent | Main agent | Main agent + parallel reference-graph workers per top-level dir |
| 2.5 Secret scan | Always runs | Always runs | Always runs |
| 3 Bundle | Main agent | Main agent | Main agent + verify pass redundantly via two methods |
| 4 Triage | 1 worker, serial | 2–4 workers, ~30 candidates each | 5+ workers, archaeology subagent for "looks important but mislocated" rows |
| 5 Merge | Main agent | Main agent | Main agent + idea-wizard cross-check on borderline verdicts |
| 6 Apply moves | 1 applier | 1 applier (sequential by definition) | 1 applier; multi-model review of reference-rewrite plans |
| 7 Apply deletes | Single gated authorization | Single gated authorization | Single plan-level authorization with batched glob commands |
| 8 Apply gitignore | 1 commit | 1 commit (with shadowing audit shown to user) | 1 commit + verify no Phase 9 regression introduced |
| 9 Fresh-eyes | 1 round, 1 model | ≥2 rounds, 1 model | ≥3 rounds, 3 independent models, adjudicated |
| 10 Handoff | Brief report | Standard report + beads issue | Full report + beads issue + bv triage of newly-unblocked work |
| 11 User-lens | Skipped | Skipped | Optional fresh agent reviews the run for skill-improvement notes |

Variant is recorded in `project_profile.json` at Phase 1. Phase gates (especially Phase 9 termination) adjust based on variant.

---

## Phase 0: Up-Front Confirmations (5 min, main agent)

Before any subagent fans out:

1. **Confirm inputs** with user: target path, mode, output mode, recovery branch name, bundle path, reference-rewrite policy. See SKILL.md § Up-Front Confirmations and `assets/intake-prompt.md`.
2. **Clone if URL** — clone to `/tmp/<basename>` and treat the cloned path as the source from then on.
3. **Refuse non-git paths** — `git -C <path> rev-parse --is-inside-work-tree` must return `true`.
4. **Refuse mid-rebase / mid-merge** — `git -C <path> status` shows `interactive rebase in progress` or unmerged paths → ask user to finish first.
5. **Resolve repo root** — `git -C <path> rev-parse --show-toplevel`; operate from there for the whole run.
6. **Initialize workspace**:
   ```bash
   mkdir -p <project>/.repo_janitor_workspace/{triage,conflicts}
   echo ".repo_janitor_workspace/" >> <project>/.git/info/exclude   # local-only ignore; do not modify .gitignore
   ```
7. **Snapshot working tree state** to `wt_phase0.txt`:
   ```bash
   scripts/snapshot-tree.sh <project> phase0
   ```
8. **Candidate count up front**:
   ```bash
   scripts/inventory-candidates.sh --preview <project> | wc -l
   ```
   Tell the user the count *before* asking them to commit time.

**Exit criteria:** User confirmed inputs; workspace exists; working-tree state captured.

---

## Phase 1: Project Reconnaissance (5–15 min, single subagent)

Spawn the project-profiler subagent (see `subagents/project-profiler.md`). Its prompt is the **Brennerian opener**:

> "First read ALL of the AGENTS.md file (or AGENT.md, CLAUDE.md, .cursor/rules/*, .github/copilot-instructions.md — whatever the project uses) and the README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code and technical architecture and purpose of the project."

The subagent then detects:

- **Primary branch** — `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null` first, then `git config init.defaultBranch`, then a heuristic against the actual ref list (look for `main`, `master`, `develop`, `trunk`, `default` in that priority order).
- **Repo archetype** — choose from the `REPO-ARCHETYPES.md` catalogue: `single-rust-crate`, `polyglot-monorepo`, `claude-skill-repo`, `nextjs-saas`, `python-package`, `go-cli`, `mixed-rust-and-frontend`, etc. The archetype's known-protected list seeds `protected_globs`.
- **Branching model** — trunk-based, GitFlow, release-branches.
- **Commit-message conventions** — Conventional Commits (`feat:`, `fix:`, `chore:`), ticket-id prefixes, gitmoji, free-form. Sample 50 recent commits.
- **Test command** — `cargo test`, `bun test`, `pnpm test`, `pytest`, `go test ./...`, etc. Parsed from CI workflows + `package.json` scripts + `Makefile`.
- **Type-check command** — `cargo check`, `bun tsc --noEmit`, `mypy .`, `tsc --noEmit`, `go vet ./...`.
- **Lint command** — `cargo clippy`, `eslint`, `ruff`, `golangci-lint`.
- **Build command** — `cargo build --workspace`, `bun run build`, `npm run build`, `make`.
- **Formatter** — `cargo fmt`, `prettier`, `ruff format`, `gofmt`.
- **CI gates** — UBS (presence of `.ubsignore`), dcg, pre-commit / husky / lefthook hooks present at `.git/hooks/pre-commit` or `.githooks/`.
- **Existing destination directories** — `docs/`, `docs/planning/`, `docs/progress/`, `docs/contracts/`, `scripts/`, `tools/`, `tests/fixtures/`, `seed/`, `data/`. The skill prefers existing dirs over creating new ones.
- **Protected globs** — seed from archetype + AGENTS.md/README mentions of "intentionally tracked" files. Ask user to confirm.
- **Branches synonym** — does the repo push `main` → `master` for legacy URL compatibility (frankensqlite pattern)? If so, every `git push origin main` is paired with `git push origin main:master`.

All of this is written to `project_profile.json`.

**Exit criteria:** `project_profile.json` exists with non-empty `primary_branch`, `archetype`, `protected_globs`, and `test_command`/`typecheck_command`/`lint_command`/`build_command`. Empty gate-command strings mean no command was detected and should be summarized to the user for correction.

---

## Phase 2: Candidate Inventory (5–15 min, single subagent)

Spawn the inventory-agent subagent. It runs:

```bash
# All tracked files (limit to top-level + known-junky subdirs first)
git -C <project> ls-files > .repo_janitor_workspace/all_tracked.txt

# Top-level tracked files (the 80% case for "junk" surfacing)
git -C <project> ls-files . | grep -v / > .repo_janitor_workspace/toplevel_tracked.txt

# Apply junk-smell heuristics
scripts/inventory-candidates.sh <project> > .repo_janitor_workspace/candidates.tsv
```

For each candidate, the row contains:

```
id  blob_sha   path_at_HEAD   size_bytes  mtime_iso  smell_tags                  first_committed_in
000 abc123...  storage.sqlite3 12288     2026-04-22 sqlite-db,binary,root-only   def987...
001 ...
```

**Smell tags** — see [FILE-SMELLS.md](FILE-SMELLS.md). Multiple tags allowed.

The agent also writes:

- `candidates_grouped.md` — markdown table of candidates grouped by smell category (`sqlite-db`, `skill-output`, `scratch-script`, `progress-report`, `planning-doc`, `agent-output`, `binary-elf`, `nohup-leak`, `secret-suspect`, `compiled-out`, `dual-format-asset`, …).
- `reference_graph.json` — for each candidate, the list of files in the rest of the repo that reference its basename or relative path. Built by:
  ```bash
  for cand in $(awk -F'\t' '{print $3}' candidates.tsv); do
    bn=$(basename "$cand")
    grep -lr -F "$bn" --include="*.rs" --include="*.toml" --include="*.sh" \
      --include="*.py" --include="*.md" --include="*.json" --include="*.yml" \
      --include="*.yaml" --include="*.go" --include="*.js" --include="*.ts" \
      --include="*.tsx" --include="*.html" --include="Makefile" --include="Dockerfile" \
      --exclude-dir={.git,node_modules,target,dist,build,.venv,__pycache__,.next} \
      "<project>" 2>/dev/null
  done
  ```

**Exit criteria:** `candidates.tsv` covers every junk-smelling file; `reference_graph.json` is populated for every candidate; main agent posts a one-paragraph summary ("found 87 candidates across 9 smell categories: 14 planning-doc, 12 progress-report, 8 scratch-script, 5 sqlite-db, 4 skill-output, …") and asks for any patterns the user already knows about.

---

## Phase 2.5: Secret-Leak Scan (1–3 min, single subagent — gate)

This phase is **non-negotiable** and runs on every invocation, even on clean repos.

Spawn the leak-scanner subagent. It runs:

1. **Filename match** against the secret-smell pattern set (see [FILE-SMELLS.md § Secret leakage](FILE-SMELLS.md#secret-leakage)):
   - `signing-*.key`, `*.pem`, `id_rsa*`, `id_ed25519*`, `*.p12`, `*.pfx`, `*.jks`
   - `*credentials*.json`, `service-account*.json`, `*-key.json`
   - `.env` (without `.example`/`.template` suffix)
   - `*.token`, `*_secret*`, `*-secret-*`
   - `.npmrc`, `.pypirc` (when content has `_authToken=` or `password = `)
2. **Content fingerprint** for files matching the filename rules:
   - Length is 32 or 64 bytes (Ed25519 seed/expanded)
   - Length is multiple-of-16 and base64-decodable (AES key)
   - First line matches `BEGIN (RSA|EC|OPENSSH|DSA) PRIVATE KEY`
   - Contains `xoxb-`, `xoxp-`, `sk-`, `ghp_`, `github_pat_`, `AKIA[0-9A-Z]{16}`, `AIza[0-9A-Za-z_-]{35}`, etc. (well-known prefix set)
3. **Provenance** for each suspect:
   ```bash
   git log --oneline --all --diff-filter=A -- <path>     # introducing commit
   git log -1 --format='%H %ci %s' -- <path>             # last touch
   git rev-parse origin/<branch> 2>/dev/null             # was it pushed?
   ```

If **any** real-secret hit (a filename match AND a content-fingerprint match):

- Write `secret_findings.tsv` with columns: `path, smell, content_hash, introduced_in_sha, last_touched_at, pushed_to_origin, exposure_window_days`.
- **HALT** the routine cleanup flow.
- Switch to [INCIDENT-PLAYBOOK.md § Secret Leak](INCIDENT-PLAYBOOK.md#secret-leak-recovery).

If only filename-match without content-fingerprint match (e.g., a 0-byte placeholder, a `*.key` with `BEGIN PUBLIC KEY` content, a `.env.example`):

- Tag with `secret-suspect` smell.
- Surface to user at Phase 5 for explicit confirmation that the file is safe.
- Continue to Phase 3 normally.

**Exit criteria:** Either `secret_findings.tsv` is empty (or contains only filename-only suspects deferred to Phase 5) OR the run has switched to the incident-playbook flow.

---

## Phase 3: Recovery Bundle (10–30 min, single subagent — gate)

This phase MUST complete with byte-equality verified before any classification logic runs. If the bundle is wrong, the entire run is unsafe.

Spawn the bundle-builder subagent. Steps:

1. **Build the in-project bundle**:
   ```bash
   BUNDLE=".repo_janitor_workspace/recovery-bundle-$(date -u +%Y-%m-%d)"
   bash <skill>/scripts/build-bundle.sh "<project>" "$BUNDLE"
   ```
   The helper creates the bundle directory, writes `.repo_janitor_workspace/bundle_path.txt`, copies every candidate into `working-tree-copies/`, writes `index.tsv` and `meta/*.txt`, snapshots `.gitignore`, copies `reference_graph.json` when present, and updates the backup ref. It rejects bundle paths outside `<project>`.

2. **Verify byte-equality** via `scripts/verify-bundle.sh`:
   ```bash
   bash <skill>/scripts/verify-bundle.sh "<project>" "$BUNDLE"
   ```
   Write all results to `bundle_verification.log`. Any mismatch halts the run.

**Exit criteria:** Every candidate has a working-tree-copy AND a meta file; byte-equality verified for every entry; `bundle_verification.log` has zero `MISMATCH` lines; backup ref exists; main agent posts the bundle path to the user.

---

## Phase 4: Triage Fan-Out (parallel, 30–90 min)

Partition `candidates.tsv` into batches of ~30 each. Spawn one triage-worker subagent per batch.

**Each worker, for every candidate in its batch:**

1. Read `<bundle>/working-tree-copies/<path>` (cheap — already on disk).
2. **CLASSIFY-PURPOSE** by inspecting:
   - File header / magic bytes (`file <path>`)
   - First 50 lines if text
   - Filename pattern
   - Last-commit message (from meta)
3. **REFERENCE-GREP** — read `reference_graph.json` row; if ≥1 inbound reference exists, **at minimum surface to user** even if smell is strong. Also do a fresh in-batch grep for any references that may have appeared since Phase 2.
4. **LOCATE-PROPER-HOME** for move candidates — propose a destination based on archetype + existing dir structure:
   - `*PLAN*.md`, `*PROPOSED*.md`, `*ARCHITECTURE*.md`, `*SPEC*.md` → `docs/planning/`
   - `progress*.md`, `bd-*.md`, `*PROGRESS*.md`, `*REPORT*.md` → `docs/progress/`
   - `BENCHMARKS.md`, `BENCHMARK_*.md`, `*PERFORMANCE*.md` → `docs/planning/` (or `docs/benchmarks/` if the archetype has one)
   - `RECOVERY*.md`, `RUNBOOK.md`, `OPERATIONS.md` → `docs/operations/` (or `docs/`)
   - Visualization Python scripts (`*viz*.py`, `*visual*.py`) → `scripts/visualization/`
   - Deploy scripts (`deploy*.sh`) → `scripts/`
   - Reference docs (`SEARCH_PATTERNS_INDEX.md`, `QUICK_REFERENCE.md`, `<NAME>_ARCHITECTURE_SUMMARY.txt`) → `docs/reference/`
5. **VERDICT**:
   - `delete-and-gitignore` — true ephemeral; remove and prevent recurrence
   - `delete-no-gitignore` — one-off junk that won't recur
   - `gitignore-only` — file already removed; pattern needed for prevention
   - `move` — preserve, relocate
   - `keep-in-place` — already correct location, has references or archetype-protected
   - `protected` — explicit allowlist hit
   - `surface-to-user` — ambiguous; needs human decision (default verdict if confidence < 0.7)
6. **Confidence** in [0, 1]. <0.7 forces `surface-to-user`.
7. **Write a row** to `.repo_janitor_workspace/triage/batch_<NNN>.tsv`:
   ```
   id  verdict             confidence  evidence                          proposed_dest         gitignore_pattern
   000 delete-and-gitignore 0.97       file=ELF; no inbound refs         (none)                 (none)
   001 move                 0.92       refs=README.md; smell=plan-doc    docs/planning/         (none)
   002 surface-to-user      0.55       refs=tests/X.py:14; smell=scratch (none)                 (none)
   003 gitignore-only       0.99       file=storage.sqlite3-wal; SQLite WAL  (none)             /storage*.sqlite3*
   ```

**See `references/TRIAGE-RUBRIC.md` for the full classification rubric.**

**Coordination:** Workers reserve their batch tsv via Agent Mail (`thread_id=repo-janitor-<run-id>`, `reason="triage-batch-NNN"`). They write only to their own batch tsv; the merger (Phase 5) reads all of them.

**Exit criteria:** Every candidate has exactly one row across all `batch_*.tsv` files; no row has empty `verdict` or `confidence`; main agent merges into `triage.tsv` and posts batch-level summary counts.

---

## Phase 5: Triage Merge & Confirm (USER GATE)

Spawn the triage-merger subagent. It:

1. Reads all `batch_*.tsv` and writes the unified `triage.tsv`.
2. Builds **the categorized plan** in `triage_decision.md` — the format that worked in the Apr-27 sessions:

   ```markdown
   ## Audit summary: 87 candidates in `<repo>`

   ### A. KEEP IN ROOT — standard project files (12)
   `Cargo.toml` `Cargo.lock` `README.md` `LICENSE` `AGENTS.md` ...
   (All confirmed referenced by build, README, or in protected_globs.)

   ### B. MOVE to `docs/planning/` — long-form planning & spec docs (16)
   | id | path                              | refs (in-repo)        |
   |----|-----------------------------------|-----------------------|
   | 17 | COMPREHENSIVE_PLAN_FOR_X.md       | crates/X/src/main.rs  |
   | 18 | PROPOSED_ARCHITECTURE.md          | (none)                |
   ...

   ### C. MOVE to `docs/contracts/` — DEFERRED, see footnote
   `corpus_manifest.toml` `db300_*.toml` (15 TOML files)
   These are load-bearing config referenced by 20+ Rust files via hardcoded
   path strings. Moving requires updating those refs; recommend skipping
   unless user wants the larger surgery. **Default: leave at root.**

   ### D. MOVE to `docs/progress/` (29)
   ...

   ### E. MOVE to `scripts/visualization/` (8)
   ...

   ### F. MOVE to `scripts/` (3)
   `deploy.sh` `deploy_all.sh` `deploy_fix.sh`

   ### G. DELETE — ephemeral / scratch (8)
   `check_db.py` `find_task.py` `nohup.out` `test_ptr` `rust_out` ...

   ### H. `.gitignore` ADDITIONS (no current file deletion)
   `nohup.out` `.skill-loop-progress.md` `/progress_bd-*.md` `storage*.sqlite3*`

   ### MANUAL — surface-to-user (3)
   | id | path | reason | proposed action |
   ```

3. **Presents the plan to the user verbatim** and waits for explicit go-ahead.
4. **Captures any user overrides** — "actually keep stash@{47} too" — into `user_overrides.tsv`. Apply overrides to `triage.tsv`.
5. **Re-asks confirmation if overrides change >5 verdicts** (sanity check).
6. **For each MOVE category, generate the move plan** showing every (src → dst) plus the reference list for that source. The user can OK rewriting references, request "surface-only" mode for a specific group, or skip the category entirely.

**No destructive actions yet.** This phase produces zero commits, zero deletes.

**Exit criteria:** User explicitly typed "go" / "proceed" / "approved" / "sounds good"; `triage.tsv` has user-confirmed verdicts; `move_plan.md`, `delete_plan.md`, `gitignore_plan.md` exist with full detail.

---

## Phase 6: Apply Moves (sequential per category, 30–90 min)

Each move can change references for later moves, so this is sequential per move (but moves can be batched per logical category for atomic commits).

The move-applier subagent:

1. **Create or resume the recovery branch**:
   ```bash
   rb=repo-janitor-$(date -u +%Y-%m-%d)
   if git show-ref --verify --quiet "refs/heads/$rb"; then
     git checkout "$rb"
   else
     git checkout -b "$rb" origin/<primary-branch>
   fi
   ```
2. **For each MOVE category in the plan**, in dependency-safe order (dest dir created first if new):
   1. **WORKING-TREE-DRIFT check** — `git status` now; capture in `apply_log.tsv`. Treat agent drift as committed-by-you per AGENTS.md.
   2. **Pre-flight reference re-grep** — re-run REFERENCE-GREP for each source in this category; drift since Phase 4 is normal.
   3. **`mkdir -p <dest_dir>`** if it doesn't exist.
   4. **`git mv <src> <dest>`** for each candidate. Preserves rename detection.
   5. **REWRITE-REFERENCES** for each surfaced reference, via the Edit tool (one old/new pair at a time), logged in `reference_rewrite_log.tsv`. Categories of rewrites:
      - Markdown link: `](./X.md)` → `](./docs/planning/X.md)` (or basename-only if README is in the same dir as the new path)
      - Code path constant: `const X_PATH: &str = "X.md";` → `const X_PATH: &str = "docs/planning/X.md";`
      - Shell var: `SPEC_PATH="X.md"` → `SPEC_PATH="docs/planning/X.md"`
      - YAML/TOML: `spec: X.md` → `spec: docs/planning/X.md`
   6. **Re-verify zero stale refs** — full repo grep for the basename; capture the result. If any references survive, surface them, fix or escalate.
   7. **Run quality gates** from `project_profile.json`:
      - test command (e.g., `cargo test`) — limited scope if possible (`cargo check -p <crate>`)
      - typecheck command
      - build command
      - UBS if available
      - All must exit 0 OR the user has explicitly OK'd a known pre-existing failure.
   8. **Stage** `git add -A` (all renames + reference rewrites for this category).
   9. **Commit** with a focused message that names the category, the count, the destination, and the rationale:
      ```
      chore: move long-form planning docs into docs/planning/ + update load-bearing path references

      Sixteen long-form documents at the workspace root were planning, design,
      and architecture artefacts. They retain lasting value as a record of how
      the project was scoped, but their natural home is under docs/planning/.

      Moved (16):
      - COMPREHENSIVE_PLAN_FOR_X.md (846 KB) → docs/planning/...
      - PROPOSED_ARCHITECTURE.md → ...
      ...

      Updated load-bearing path references in 8 files:
      - crates/X-harness/src/bin/spec_audit.rs:19 (workspace_root.join)
      - crates/X-harness/tests/rfc2119_audit.rs:13 (SPEC_REL_PATH)
      ...

      Verified: cargo check passes; no stale path refs found via grep.
      ```
3. **If apply-check fails on a category** (a reference rewrite produces a build error, or a `git mv` collides with an existing file at the destination):
   1. **DO NOT** force the move.
   2. Surface to the user with full context.
   3. Wait for OK. If the user says "skip", mark the category `skipped`.

**Exit criteria:** Every MOVE row has either a `new_commit_sha` or a `conflict-skipped` mark in `apply_log.tsv`; quality gates passed on the recovery branch's tip.

---

## Phase 7: Apply Deletes (GATED)

Only after Phase 6 is clean AND the user has typed verbatim authorization for the delete plan.

The delete-applier subagent:

1. **Build the verbatim authorization request**:
   ```
   I'm about to run the following destructive commands in this order
   (grouped by smell-category, atomic per category):

   # Category G1 — stray binaries (2)
   git rm test_ptr rust_out

   # Category G2 — ad-hoc Python tools (3)
   git rm check_db.py find_task.py refactor_physical_merge.py

   # Category G3 — scratch shell + JS + C stubs (5)
   git rm fix_beads.sh script_to_fix_gemini_cli.sh test.js test_sqlite_ptrmap.c wrangler_version.txt

   # Category G4 — SQLite dev DBs + WAL/SHM siblings (3)
   git rm storage.sqlite3 storage.sqlite3-wal storage.sqlite3-shm

   The bundle at <bundle> stays intact; backup ref refs/repo-janitor-backup/...
   stays intact.

   To proceed, paste this verbatim:
     yes I understand and want to delete all 13 files per the plan above
   ```
2. **Wait for that exact authorization text** from the user. If they type anything different, refuse and re-ask.
3. **Record** the user's authorization text + timestamp in `cleanup_authorization.txt`.
4. **For each category, in plan order**:
   1. WORKING-TREE-DRIFT check.
   2. Pre-flight: confirm each path is still tracked (concurrent agent may have already removed one).
   3. `git rm <files-in-category>`.
   4. Run quality gates.
   5. Commit with focused message ("chore: remove ELF binaries from repo root", body explaining each file's role + why it shouldn't have been tracked + how to reproduce if needed).
5. **Never** `git stash clear`. **Never** delete the bundle. **Never** delete `refs/repo-janitor-backup/*`.

**Exit criteria:** Every DELETE row has `new_commit_sha` in `apply_log.tsv`; gates green; `cleanup_authorization.txt` records the verbatim user text.

---

## Phase 8: Apply `.gitignore` (GATED)

The gitignore-author subagent:

1. **For every proposed addition**, run SHADOWING-AUDIT:
   ```bash
   for pat in $(awk '{print $1}' gitignore_plan.md); do
     git -C <project> ls-files "$pat" 2>&1 | head -20
   done
   ```
   Any non-empty result means the pattern would shadow tracked files.
2. **If shadowing found**, the additions are paired with `git rm --cached <files>` first, surfaced in the user-confirm message, and the user must type a verbatim "yes I understand and want to untrack and ignore X, Y, Z" authorization.
3. **If no shadowing**, the additions go straight to a single `.gitignore` commit:
   ```bash
   # Append to .gitignore (preserve existing structure; group thematically)
   ```
4. **Commit** `chore(gitignore): forbid <category> at repo root` with body documenting each new pattern, the rationale, and any paired `git rm --cached` runs.
5. **Verify** the new patterns work via `git check-ignore -v <fake-path-matching-pattern>`.

**Exit criteria:** `.gitignore` committed; SHADOWING-AUDIT result empty (or all shadowed files explicitly `git rm --cached`'d in the same commit); `cleanup_authorization.txt` records any shadowing-related verbatim auth.

---

## Phase 9: Fresh-Eyes Verification (≥2 rounds, 30–60 min)

Spawn the fresh-eyes subagent. It runs three review prompts (verbatim from the documentation-website skill):

1. *"Carefully read over all of the new code/file moves/deletes/gitignore changes you just made with 'fresh eyes' looking super carefully for any obvious bugs, errors, broken references, broken builds, missed cleanup. Carefully fix anything you uncover."*
2. *"Sort of randomly explore the code files in this project, choosing files to deeply investigate and tracing whether any of them reference paths that may have been moved or deleted in this run. Once you understand the purpose of the file in the larger context, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious broken-reference bugs, silent test fixture losses, or build-system effects from the cleanup."*
3. *"Turn your attention to reviewing the cleanup decisions made by your fellow agents and checking for any false-positive deletes (a deleted file may have been a referenced test fixture), bad moves (a moved file's new location may not be findable from a build script with hardcoded paths), or .gitignore additions that silently mask important files. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep."*

Between rounds, the main agent runs:

```bash
# Project-specific (read from project_profile.json):
<test_command>          # e.g., cargo test
<typecheck_command>     # e.g., bun tsc --noEmit
<lint_command>          # e.g., cargo clippy -- -D warnings
<build_command>         # e.g., cargo build --workspace
ubs .                   # if available
```

All must exit 0. Log each round + outcome to `fresh_eyes_log.md`.

**Termination rule:** Two consecutive full rounds (all three prompts) produce only trivial findings AND test + typecheck + lint + build + UBS all green.

**Exit criteria:** Fresh-eyes log shows ≥2 clean rounds; gates green on `HEAD`.

---

## Phase 10: Handoff & Follow-Ups (5–15 min)

The handoff-reporter subagent emits `handoff_report.md` with:

```markdown
# Repo Janitor — Handoff Report

**Project:** /data/projects/<repo>
**Run date:** 2026-MM-DD
**Mode:** full
**Variant:** Standard
**Recovery branch:** repo-janitor-2026-MM-DD
**Bundle path:** /data/projects/<repo>/.repo_janitor_workspace/recovery-bundle-2026-MM-DD/

## Counts
- Initial tracked top-level files: 109
- Final tracked top-level files: 45 (59% reduction)
- Candidates triaged: 87
  - move: 56 (applied)
  - delete-and-gitignore: 13 (applied + .gitignore updated)
  - delete-no-gitignore: 8 (applied)
  - gitignore-only: 4 (.gitignore updated)
  - keep-in-place: 4
  - surface-to-user: 2 (resolved per user input)
- Recovery commits authored: 8 on `repo-janitor-2026-MM-DD`

## Per-commit summary
| sha       | category                                   | counts |
|-----------|--------------------------------------------|--------|
| 930de276  | DELETE 2 stray ELF binaries                | 2      |
| 236e513d  | DELETE 3 ad-hoc Python tools               | 3      |
| 095801fc  | DELETE 5 scratch files                     | 5      |
| 8e0f012d  | MOVE 3 deploy scripts → scripts/           | 3      |
| 8b94f640  | MOVE 8 viz scripts → scripts/visualization/| 8      |
| 44c77110  | MOVE 27 progress reports → docs/progress/  | 27     |
| b0de8afe  | MOVE 16 planning docs → docs/planning/ + 8 source-file path-rewrites | 16+8 |
| 0c09db32  | gitignore: 6 patterns to prevent recurrence| 6      |

## Skipped categories
- **Cat C (15 TOML contract files)** — load-bearing config referenced by 20+ Rust files via hardcoded path strings. Moving them is a larger surgery; recommended to leave at root unless user wants to tackle separately.

## Recovery recipes
If you regret any move/delete, the bundle has byte-identical copies:

  # By backup ref
  git checkout refs/repo-janitor-backup/2026-MM-DD-pre-cleanup -- <path>

  # By bundle copy
  cp <bundle>/working-tree-copies/<path> <project>/<path>
  git add <path>

  # The bundle's index is at:
  cat <bundle>/index.tsv

## Push instructions
The skill never pushes. To land the cleanup:

  git push origin repo-janitor-2026-MM-DD
  # Then open a PR against <primary-branch> for review

  # If repo pushes main → master synonym (frankensqlite pattern):
  git push origin repo-janitor-2026-MM-DD:master

## Bundle lifecycle
The bundle lives at <bundle>. Keep it for at least one release cycle.
```

The subagent also:

- Files a **beads issue** summarizing the run.
- Updates the Agent Mail thread with a final reply.
- If `bv` is available, runs `bv --robot-triage` to surface follow-ups.
- Reminds the user to push.

**Exit criteria:** `handoff_report.md` exists with all sections filled; beads issue filed; user told the push command(s).

---

## Phase 11: User-Lens Review (OPTIONAL, off by default)

Only runs if the user explicitly asks. A fresh agent or `/idea-wizard` reviews the entire run from the perspective:

> "Did this repo janitor save the user time? Where did it surface friction? What would have made it better? What did the agent miss?"

Files improvement notes to `.repo_janitor_workspace/skill_feedback.md`.

---

## Idempotence & Resumability

**Idempotent on a clean repo.** Phases 1, 2, 2.5, 3 still produce their artifacts (project profile, empty inventory, no secrets, empty bundle). Phases 4+ short-circuit with "nothing to do."

**Resumable mid-run.**

- Phase 1 — re-uses `project_profile.json` if present and ≤7 days old.
- Phase 2 — always re-runs (cheap; produces fresh `candidates.tsv`).
- Phase 2.5 — always re-runs (security regression-check; cheap).
- Phase 3 — checks if the bundle exists and verifies byte-equality; if yes, skips re-creation.
- Phase 4 — re-runs only the batches without a `batch_NNN.tsv`.
- Phase 5 — re-presents the merged table; user can re-confirm or override.
- Phase 6 — reads `apply_log.tsv` and skips already-committed moves (matched by `id`).
- Phase 7 — analogous via `apply_log.tsv`.
- Phase 8 — refuses to re-run if `.gitignore` already has the proposed additions; emit "already done."
- Phase 9 — always re-runs.
- Phase 10 — re-emits `handoff_report.md` from the latest log files.
