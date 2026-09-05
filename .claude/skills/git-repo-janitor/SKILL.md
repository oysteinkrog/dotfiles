---
name: git-repo-janitor
description: >-
  Safely triage committed-but-junky files in a git repo — ephemeral SQLite DBs,
  stray JSON artifacts, intermediate skill outputs, plan documents at the
  project root — moving keepers to a sensible home, deleting the rest with
  `git rm` plus `.gitignore` updates, never disturbing source. Use when
  "clean up my repo", "the repo junk cleaner", "tidy up the project root",
  "random `.db` / `.md` files committed", or when an agent swarm leaves
  ephemeral artifacts in the working tree.
---

<!-- TOC: Top 5 Mistakes | Quick Start | Kernel (25 axioms, 0–24) | Decision Tree | Quickref | What This Produces | Inputs | Workspace Layout | Up-Front Confirmations | Skill Bootstrap | The Phase Loop | Mode Router | Parallelism | Operator Library | The Polish Bar | Failure Modes | Anti-Patterns | When NOT to Use | Pre-Flight & End Checklist | Source Corpus | Reference Index | Scripts | Subagents | Asset Templates | Self-Test -->

# Git Repo Janitor — Triage, Move, Delete, Gitignore

> **The One Rule.** Every move, every `git rm`, every `.gitignore` change must be reversible **byte-for-byte** at the moment it's authorized. The recovery bundle (full pre-mutation file content + path manifest + content hashes + `.gitignore` snapshot + reference graph) is the gold standard; the git history backstop catches anything missed. If both aren't in place and verified, no destructive action runs. Period.

> **Scope.** A repo's working tree has accumulated files that shouldn't be there — SQLite DBs and their `-wal`/`-shm` siblings, stray JSON artifacts, intermediate `.md` outputs from agent skills, scratch scripts, plan documents stranded at the project root, debug logs, build leakage. The skill triages each candidate into one of seven verdicts (`delete-and-gitignore`, `delete-no-gitignore`, `move`, `keep-in-place`, `gitignore-only`, `protected`, `surface-to-user`), executes the moves and deletions in the right order with byte-equality verification, lands the cleanup as focused commits on a recovery branch, and never touches actual source code without a verbatim user OK.

> **Mandatory framing.** This skill operates on REAL files in REAL git history with REAL teammates and REAL CI/CD pipelines watching. Every recommendation is a contract: the bundle preserves a recoverable state; the per-commit gates prove the cleanup didn't break the build; the verbatim authorization records the user's consent. Skip any layer and the skill is unsafe.

---

## Top 5 Mistakes (read this even if you read nothing else)

| # | Mistake | Why it's wrong | What to do instead |
|---|---------|----------------|--------------------|
| 1 | Use `rm` (or `find -delete`, `xargs rm`) to remove tracked files | Bypasses git history; loses the rename/delete record; survives no audit | `git rm <path>` only — every delete is a committed git operation |
| 2 | Treat `.gitignore` as if it untracks files | `.gitignore` only affects *untracked* files. Adding `*.bak` does NOT untrack already-tracked `*.bak` files. They keep accumulating commits silently | Pair `.gitignore` adds with `git rm --cached <files>` if shadowing tracked files. Always run SHADOWING-AUDIT (`git ls-files <pattern>`) first |
| 3 | Auto-rewrite source-code references with `sed -i` | Brittle; over-matches partial substrings; no audit trail; per AGENTS.md "No Script-Based Changes" | Edit-tool one occurrence at a time, logged in `reference_rewrite_log.tsv` |
| 4 | Skip Phase 2.5 secret scan ("it's a private repo") | Private becomes public; teammates leave; backups exist. The mcp_agent_mail Apr-27 incident found a real Ed25519 key in a public repo, undetected for 30 days | Phase 2.5 is non-negotiable. Always runs. Costs ~3 minutes |
| 5 | Trust filename alone for verdict | A `scratch.py` may be a tracked test helper; a `verify` script may be a top-level entrypoint; a `data/seed.db` may be a curated fixture | Always REFERENCE-GREP first. ≥1 inbound ref → `surface-to-user`, regardless of how junky the name looks |

If you avoid these five, ~80% of the bad outcomes are off the table.

---

## Quick Start (the 60-second flow for a fresh agent)

When the user asks for a repo cleanup, run these in order. Each step has more detail later in this doc; this is the orientation:

```bash
cd <project>
SKILL=/path/to/.claude/skills/git-repo-janitor

# 1. Pre-flight: refuse if mid-rebase, bare repo, etc.
bash $SKILL/scripts/git-doctor.sh .

# 2. Detect archetype, build commands, branch policy → project_profile.json
mkdir -p .repo_janitor_workspace
bash $SKILL/scripts/discover-project.sh . > .repo_janitor_workspace/project_profile.json
bash $SKILL/scripts/verify-git-version.sh .   # captures verification_log.md

# 3. Preview candidates (cheap; fast feedback for the user)
bash $SKILL/scripts/inventory-candidates.sh . --preview | wc -l   # → N

# 4. Tell the user the candidate count, then pick BOTH a variant and a mode:
#    - Variant (Quick / Standard / Comprehensive) — auto-suggested by candidate count
#    - Mode (one of 9; default `full`) — see § Mode Router
#    Use assets/intake-prompt.md as the verbatim Q&A template (Q3 = Variant, Q4 = Mode).

# 5. Run Phase 1 (project-profiler subagent) → Phase 2 (inventory-agent) → Phase 2.5 (leak-scanner)
#    If Phase 2.5 finds a real secret: HALT and switch to harden-secret-leak mode (Axiom 15)

# 6. Phase 3 (bundle-builder) → Phase 4 (triage workers, ~30 candidates each) → Phase 5 (triage-merger; USER GATE)

# 7. After Phase 5 user "go": Phase 6 (move-applier) → Phase 7 (delete-applier; verbatim auth) → Phase 8 (gitignore-author)

# 8. Phase 9 fresh-eyes (≥2 clean rounds) → Phase 10 handoff (NEVER push)
```

**The full per-phase playbook is in [PHASES.md](references/PHASES.md). The verbatim subagent prompts are in [AGENT-PROMPTS.md](references/AGENT-PROMPTS.md).**

**Mode picking, if the user hasn't said:** Although `full` is the formal default in the mode catalogue, when the user gives a generic "clean up the repo" without specifics, **suggest `triage-only` first** (most cautious — produces the categorized plan with zero mutations). The user reviews the plan, then either approves the same skill in `move-only` / `delete-only` / `full`, or escalates to `harden-secret-leak`. This avoids gating Phase 7 verbatim authorization on a user who hasn't yet seen what would be deleted.

---

## THE REPO-JANITOR KERNEL (Universal Axioms)

<!-- KERNEL_START v1.0 -->

Almost every serious repo-janitor decision should be stress-tested against these axioms. They are default truths, not mindless scripts: if an edge case seems to break one, explain why before treating it as an exception.

**Axiom 0 — The unit of management is a content-hash + canonical-path pair, not a filename.**
Two files with the same path can have different SHAs across history; two files with the same SHA can live at different paths. Triage decisions are stored against `(blob_sha, path_at_HEAD)` so that re-runs after a partial cleanup don't double-classify a file that already moved. `.gitignore` patterns are stored against canonical paths (forward slashes, no `./` prefix, repo-root anchored where appropriate).

**Axiom 1 — One coherent recovery story is told by every artifact.**
Bundle file copies + path manifest + content hashes + `.gitignore` before/after diffs + reference graph + per-file rationale must point at the same candidates, in the same order, with byte-equality verified. Silos produce the deepest failures: a bundle copy whose hash disagrees with the inventory it claims to back up is worse than no backup at all.

**Axiom 2 — Plan for irreversibility first, classification second.**
The `⬡ BUNDLE` operator (Phase 3) is a hard gate before any destructive logic runs. An incorrect verdict is recoverable; an unrecorded delete is not. Build the safety net first, then triage.

**Axiom 3 — `git rm` is reversible from history; an `rm` is not.**
Always use `git rm <path>` (or `git rm --cached <path>` for un-tracking without deleting from the working tree). Never `rm`, never `find … -delete`, never `git ls-files | xargs rm`. The git history is the ultimate backstop — but only for paths that were ever committed. Untracked files in the bundle are recovered from the bundle's `working-tree-copies/` directory.

**Axiom 4 — `main` is not the universal default.**
Many projects use `master`, `develop`, `trunk`, `default`. Detect the primary branch via `git symbolic-ref refs/remotes/origin/HEAD` first, then `git config init.defaultBranch`, then a heuristic against the actual ref list. Never assume.

**Axiom 5 — A move is not a delete-and-recreate.**
Use `git mv <src> <dst>` so that git's rename detection survives. Followers of the file (PRs, blame, history) only work cleanly when the move is recorded as a rename, not as a delete + add. If the user's git is configured with low rename-detection thresholds, a copy + delete + commit can show up as unrelated commits — always `git mv`.

**Axiom 6 — A `.gitignore` glob can shadow tracked files.**
Adding `*.json` to `.gitignore` does NOT remove already-tracked JSON files from the index — but it DOES make new instances of those files invisible to `git status`, which silently masks future regressions. Every `.gitignore` change is paired with a `git ls-files <pattern>` audit before the change is applied; pre-existing tracked matches are surfaced to the user.

**Axiom 7 — `.gitignore` patterns are not equivalent to delete patterns.**
A file may be deleted-from-this-repo without being added to `.gitignore` (it's a one-off, not a recurring artifact). A file may be added to `.gitignore` without being deleted (it's already removed from the working tree but the pattern needs to be there to prevent future check-ins). The two operations are decoupled in the verdicts.

**Axiom 8 — Concurrent agents' working-tree changes are normal.**
Per AGENTS.md, never stash, revert, or overwrite changes made by parallel agents. Snapshot once at Phase 0; re-snapshot before each Phase 6 / Phase 7 mutation; treat all observed drift as "you committed it" and proceed. Don't ask the user about drift you didn't cause.

**Axiom 9 — Authorization is per-plan, verbatim, recorded.**
Every destructive phase (Phase 7 deletes, Phase 8 `.gitignore` rewrites that shadow tracked files) requires the user to type a phrase that quotes a literal command from the plan (per AGENTS.md "Mandatory explicit plan"). The verbatim text is recorded in `cleanup_authorization.txt` with a UTC timestamp. If that file doesn't exist, the action did not happen. Moves (Phase 6) get a single bulk authorization at the start of Phase 5 because they are reversible via `git revert` of a single commit; per-file verbatim authorization is reserved for deletes.

**Axiom 10 — Per-mutation gates are non-negotiable.**
Run the project's actual `test`, `typecheck`, `lint`, `build`, `ubs` after every Phase 6 / Phase 7 / Phase 8 commit, not just at the end. Compounding errors across many small cleanups (a broken markdown link from a move, a typecheck failure because a moved file was imported by code, a `.gitignore` rule that hid a config file the build needs) are an order of magnitude harder to debug than per-commit failures.

**Axiom 11 — A file's importance is not visible from its name alone.**
`scratch.py` may be a documented one-off harness referenced in `tests/conftest.py`. `notes.md` may be the ADR for the auth subsystem. A `.db` file may be a hand-curated test fixture required by the test suite. Every "delete" candidate is reference-checked against the rest of the repo (grep for the basename, the relative path, and a glob match) before the verdict is final. When `≥1` reference is found, the verdict flips to `surface-to-user` regardless of how junky the file looks.

**Axiom 12 — A move can break references — surface every one.**
After a move is proposed but before it executes, the skill greps the entire repo for the old path (relative, basename, with-and-without leading `./`, in markdown, in code, in shell scripts, in YAML configs). Every match is enumerated in the move plan; the user signs off on either (a) the skill rewrites the references along with the move, or (b) the user will fix them. Silent broken references are the most common follow-up bug.

**Axiom 13 — The user owns deployment and bundle lifecycle.**
The skill never pushes the recovery branch; the user pushes. The skill never deletes the bundle; the user manages it. Both are deliberate: the recovery story has to outlive the run.

**Axiom 14 — Some files look like junk but are deliberately tracked.**
Examples: a `data/seed.db` SQLite file used as a portable seed; a binary `assets/font.woff2`; a `tests/fixtures/sample.log` regression input; a `.example.env` template; a `CHANGELOG.md` at the project root (root-level on purpose). The repo-archetype profile (Phase 1) plus the reference graph (Phase 2) plus the `protected_globs` field of the project profile combine to keep these in `keep-in-place` regardless of how junky they look. When in doubt, escalate.

**Axiom 15 — A secret in the working tree halts the cleanup and switches modes.**
If the inventory walk surfaces what looks like a real secret (`*.key` with 32–64 byte content, `*.pem` with `BEGIN PRIVATE KEY`, `.env` with non-placeholder values, `id_rsa*`, `id_ed25519*`, `*credentials*.json`, `*.token`, `service-account*.json`, etc.), the skill **STOPS the routine cleanup flow**, surfaces the finding with full provenance (commit SHA that introduced it, public exposure window if pushed), and switches to the secret-rotation playbook ([INCIDENT-PLAYBOOK.md § Secret Leak](references/INCIDENT-PLAYBOOK.md#secret-leak-recovery)): **mirror-backup → user generates new key → `git filter-repo` → force-push with lease → `.gitignore` hardening → pre-commit hook scaffold → AGENTS.md documentation**. A force-pushed history rewrite is the only delete this skill *ever* recommends, and only with explicit user authorization, **only after** the user confirms key rotation, and **never** for non-secret content. The skill specifically watches for the "force-add-bypass" footgun: a `*.key` rule already in `.gitignore` that someone overrode with `git add -f`. The pre-commit hook is the belt-and-suspenders.

**Axiom 16 — A shallow / partial clone silently corrupts a `git filter-repo` run.**
Local clones can have fewer commits than `origin/<branch>` (shallow clones, partial fetches, or just an old checkout that hasn't been synced). If `git filter-repo` runs against a local subset of history, only the subset is rewritten — the rest of the history on origin still contains the secret. Before any `filter-repo` run, the skill verifies `git rev-list --count <branch> == git rev-list --count origin/<branch>` and, if not, syncs via `git update-ref refs/heads/<branch> refs/remotes/origin/<branch>` first. The mirror backup also covers any exotic refs that the working clone doesn't see.

**Axiom 17 — Volatile git behavior must be verified live, not assumed.**
Git's defaults shift across versions: rename-detection thresholds (default ~50% but configurable; changed under `diff.renames` semantics in 2.18 and again in 2.40+), `git filter-repo` plugin contract (changed in 2.36), partial-clone interaction with `git rev-list` (changed in 2.40+), `merge.renameLimit` defaults, LFS pointer behavior. The kernel is *evergreen*; the operational details are *volatile*. Phase 1 captures `git --version`, `core.autocrlf`, `diff.renames`, `merge.renameLimit`, LFS version, presence of `.git/shallow`, and `git config rerere.enabled` into `project_profile.json`. Any operator that depends on a version-sensitive behavior verifies live before recommending. See [VERIFICATION-FIRST.md](references/VERIFICATION-FIRST.md).

**Axiom 18 — Coverage matrices reveal what the agent didn't consider.**
Every smell rule in [FILE-SMELLS.md](references/FILE-SMELLS.md) must produce a row in `coverage_matrix.md` for this run, marked `present | partial | missing | n/a`. A blank cell is a bug, not a default. This forces explicit consideration of every rule, not just the ones that fired. Source: saas-billing's coverage matrix pattern. See [COVERAGE-MATRIX.md](references/COVERAGE-MATRIX.md).

**Axiom 19 — Confidence is per-recommendation, computed from four dimensions, lowest-dimension caps.**
Every triage row carries a confidence score in [0, 1] derived from: (a) Evidence Quality, (b) Smell Specificity, (c) Reference-Graph Completeness, (d) Reversibility. The lowest dimension caps the overall confidence — verdicts with confidence < 0.7 always flip to `surface-to-user`. See [CONFIDENCE-SCORING.md](references/CONFIDENCE-SCORING.md).

**Axiom 20 — A clean run produces the same artifacts as a busy run, just with empty bodies.**
Re-running on a freshly-cleaned repo produces `project_profile.json`, an empty `candidates.tsv` (header only), an empty bundle (header but no working-tree-copies), an empty `secret_findings.tsv`, and a handoff that says "nothing to do." This is the resumability invariant. See [RESUMABILITY.md](references/RESUMABILITY.md).

**Axiom 21 — Mode handoffs are explicit; mode escalation is a recorded decision, not a drift.**
A `triage-only` run that reveals a secret leak does NOT silently switch to `harden-secret-leak`. It writes `mode_escalation_decision.md` and asks the user to confirm before proceeding. Drift between modes is the most common way users lose context. See [OPERATING-MODES.md](references/OPERATING-MODES.md).

**Axiom 22 — Provenance is an artifact-level invariant.**
Every artifact in `.repo_janitor_workspace/` opens with a header carrying `produced_at: <UTC> | produced_by: <subagent> | source_phase: <N> | confidence: <0-1> | inputs_hash: <sha>`. Catches "stale `triage.tsv` from last week's run" failures. See [SOURCE-COVERAGE-MAP.md](references/SOURCE-COVERAGE-MAP.md).

**Axiom 23 — Multi-repo runs are skip-list-first, not allow-list-first.**
On a fleet of N repos, the orchestrator first decides which whole repos are EXCLUDED (submodules-only, external-primary-dev, third-party forks, mid-rebase). Only then per-file Cat-A through Cat-G triage runs on the survivors. See [BATCH-MODE.md](references/BATCH-MODE.md).

**Axiom 24 — A phantom-deletion is a restoration request, not a commit-me-up request.**
Many real cleanup runs encounter `D <path>` lines (file deleted from working tree but still tracked at HEAD) without any corresponding intent in recent commits — they came from `rm -rf` outside git or a `git checkout` of the wrong tree. The naive cleanup would commit those deletions, destroying user work. The skill detects this by cross-referencing each ` D` line with `git log --diff-filter=D HEAD -1 -- <path>`; if the file's last commit didn't delete it, the verdict flips to `restore-do-not-commit` with `git checkout HEAD -- <path>` as the proposed action.

<!-- KERNEL_END v1.0 -->

These 25 axioms (numbered 0 through 24) compose. Selected combinations:

- Axiom 2 + Axiom 1 → byte-equality bundle gate (Phase 3)
- Axiom 9 + Axiom 11 → verbatim-authorization-with-evidence (Phases 5, 7, 8)
- Axiom 5 + Axiom 12 → move + grep + rewrite-or-surface (Phase 6)
- Axiom 6 + Axiom 7 → decoupled `.gitignore` / `git rm` ordering (Phases 7+8)
- Axiom 8 + Axiom 10 → per-commit working-tree-snapshot + gates (Phases 6/7/8)
- Axiom 15 + Axiom 16 → secret-leak escape hatch with the shallow-clone guard
- Axiom 17 + Axiom 19 → verify-then-recommend with calibrated confidence
- Axiom 18 + Axiom 22 → coverage matrices + provenance headers expose the entire decision space, including negative decisions
- Axiom 20 + Axiom 21 → idempotent re-runs that survive mode escalation
- Axiom 23 + Axiom 13 → multi-repo orchestration with per-repo skip-list and per-repo branch-policy
- Axiom 14 + Axiom 18 → archetype-protected globs + coverage matrix prove the skill considered every relevant smell against this archetype
- Axiom 24 + Axiom 8 → phantom deletions are surfaced even amid concurrent-agent drift

When you find yourself wanting to break one, slow down and check whether you've actually identified an exception or whether the kernel is right. The three most-broken-in-real-runs axioms are 15 (secret halt), 8 (concurrent agents), and 24 (phantom deletions) — be especially careful around those.

---

## Decision Tree — Should the Skill Run?

```
# (assumes $SKILL is set; see Quick Start above)
N=$(bash "$SKILL/scripts/inventory-candidates.sh" <project> --preview | wc -l)

├── N < 5
│     └── Suggest manual inspection (`git status` + `git ls-files`); skill is overkill
│
├── 5 ≤ N < 25
│     └── Quick variant (single-agent, ~20–40 min)
│
├── 25 ≤ N < 150
│     └── Standard variant (Pair or Squad tier; ~1–4 h)
│
├── 150 ≤ N < 500
│     └── Comprehensive variant (Squad/Swarm; ~4–10 h)
│
└── N ≥ 500
      └── Comprehensive variant + Council tier (12+ workers, multi-model triangulation)

(Variants are orthogonal to the 9 named modes — see § Mode Router. The variant decides orchestration depth; the mode decides which phases run and what's allowed.)

Pre-conditions (refuse if any fail):
  - git work tree (not bare)
  - has commits
  - not mid-rebase / merge / cherry-pick / revert / bisect
  - writable filesystem
  - no in-flight `git lfs` operations

Soft-warnings (proceed but flag):
  - detached HEAD (need recovery branch base)
  - working tree non-empty (concurrent agents per AGENTS.md — don't disturb)
  - no remote (push instructions degrade gracefully)
  - submodules present (their working trees are out of scope)
  - very old git (<2.20)
  - `.gitignore` already very large (>200 lines) — risk of ordering bugs
  - LFS-tracked files among candidates (extra recovery care; bundle includes pointer + actual blob)
```

`N` is the count of files that match at least one junk-smell heuristic OR that the user pre-flagged. The skill never grades a clean repo as needing work. See [WHEN-NOT-TO-USE.md](references/WHEN-NOT-TO-USE.md) for the full refusal matrix and `scripts/git-doctor.sh` for the automated check.

---

## Quickref

| Input | Effect | Guarantees |
|-------|--------|------------|
| **Project path** (cwd, absolute path, or git URL → clone to `/tmp/`) | Skill reads `AGENTS.md` / `CLAUDE.md` / `README.md`, detects primary branch, build/test/lint commands, repo archetype (rust crate, polyglot monorepo, skill repo, next.js app, etc.), conventions; all written to `project_profile.json` | No assumptions — `main` is **not** assumed; primary branch is detected. Repo archetype tunes which file patterns count as junk |
| **Candidate count** (`scripts/inventory-candidates.sh`) reported up front | User confirms before any work; mode auto-selects | The user always knows the magnitude of the proposed cleanup before approving any destructive action |
| **Recovery bundle** — `working-tree-copies/<path>` (byte-identical) + `index.tsv` + `meta/<id>.txt` + `gitignore-before.txt` + `reference-graph.json` + `README.md` at `<project-root>/.repo_janitor_workspace/recovery-bundle-<YYYY-MM-DD>/` | Every candidate captured before any classification touches the working tree; byte-equality verified across all bundle copies against live blobs | After Phase 3 every move is reversible via `git revert <commit>` or by reading the bundle copy and `git checkout` the old path; every delete is reversible via `git checkout <pre-commit-sha> -- <path>` or by copying back from `working-tree-copies/` |
| **Triage TSV** (`triage.tsv`) — one row per candidate with verdict, evidence, confidence, proposed destination (for moves), proposed `.gitignore` glob (for deletes) | User reviews, may override individual verdicts; only then does Phase 6 run | No file is moved or deleted without the user signing off on its verdict |
| **Per-commit gates** — full project test/typecheck/lint suite runs on **every** Phase 6/7/8 commit | Quality gates run per mutation, not at the end; broken-link / broken-import errors caught immediately | Compounding errors across many small mutations are caught one-at-a-time |
| **Move execution** — `git mv` (preserves rename detection) → grep for old path across repo → rewrite known reference forms in markdown/code/configs OR surface to user → focused commit | Moves leave history intact; references are not silently broken | Every Phase 6 commit has a non-trivial commit message naming the source path, destination, and rationale |
| **Delete execution** (gated on explicit verbatim authorization) | `git rm <path>` per file in batches grouped by glob; `.gitignore` updates committed separately | No `rm`, no `find -delete`, no `git ls-files \| xargs rm`. The bundle survives. The git history survives |
| **`.gitignore` updates** — proposed globs validated against `git ls-files` for accidental shadowing; user signs off on every newly-added pattern that already matches a tracked file | New ignore rules don't accidentally hide tracked files; if they would, the user is told and the rule is paired with `git rm --cached` first | The `.gitignore` after the run is auditable: every new line traces to a triage row's evidence |
| **Handoff** — counts per verdict, recovery commits authored, bundle path, verbatim recovery recipes, `.gitignore` diff, reference-rewrite log | Skill never pushes; user pushes | The user gets a complete recovery story even after a clean run |

---

## What This Skill Produces

Either:

1. **A cleaner repo tree** plus N focused commits on a recovery branch (default `repo-janitor-<YYYY-MM-DD>`), every commit traceable to a specific candidate (or batch of candidates) via `triage.tsv`, every removed file backed up in the bundle, and a final report showing what moved, what was deleted, and what `.gitignore` rules were added.
2. **An audit report only** (when run in `triage-only` mode) — the recovery bundle plus `triage.tsv` plus a markdown decision table; no moves, no deletes, no `.gitignore` changes.

The skill **never**:

- Runs `rm`, `rm -rf`, `find -delete`, or any non-`git` filesystem deletion
- Runs `git reset --hard`, `git clean -fd`, `git stash clear`
- Pushes to a remote
- Modifies `.git/` directly
- Edits source code (`.rs`, `.py`, `.ts`, etc.) except for **rewriting references to moved files**, and only after the user OKs the rewrite plan
- Mass-rewrites text via shell scripts or regex transforms (per AGENTS.md "No Script-Based Changes") — every reference rewrite goes through the Edit tool with a specific old/new pair
- Stashes, reverts, or overwrites changes from other agents in the working tree (per AGENTS.md "Note for Codex/GPT-5.5")

---

## Inputs

- **Target path** (default: cwd) — absolute path to a git repo, OR a git URL we clone into `/tmp/<basename>` and operate against.
- **Variant** — auto-detected from candidate count (Quick 5–24 / Standard 25–149 / Comprehensive 150+); user-overridable. Variants set orchestration depth (worker count, fresh-eyes round count) and are orthogonal to mode.
- **Mode** — pick one of 9 named modes per [OPERATING-MODES.md](references/OPERATING-MODES.md):
  - `full` (default) | `triage-only` | `move-only` | `delete-only` | `gitignore-only`
  - `harden-secret-leak` (auto-suggested by Phase 2.5 if a real secret is found)
  - `recover-from-bad-cleanup` | `add-archetype-profile` | `maintenance-review`
  Each mode declares its phases-run, required artifacts, stop condition, and forbidden actions. See § Mode Router below for the decision tree.
- **Recovery branch name** — default `repo-janitor-<YYYY-MM-DD>`. The skill creates this branch from the primary branch and lands cleanup commits there, leaving the user to merge or cherry-pick onto the primary.
- **Bundle directory** — default `<project-root>/.repo_janitor_workspace/recovery-bundle-<YYYY-MM-DD>/`. The bundle stays inside the project workspace; scripts reject sibling or absolute paths outside the project.
- **Junk-smell profile** — auto-derived from repo archetype (Phase 1); user-overridable. See [FILE-SMELLS.md](references/FILE-SMELLS.md).
- **Protected globs** — explicit allowlist that always classifies as `protected` regardless of smell. Defaults seed from `AGENTS.md` / `README.md` mentions and from the archetype's known-protected list (e.g., `Cargo.toml`, `package.json`, `LICENSE`).
- **Reference-rewrite policy** — `auto-rewrite-with-confirmation` (default) | `surface-only` (skill never edits source files; user does the rewrites) | `auto-rewrite-trusted-formats` (markdown links and YAML config refs auto; code imports surface to user).

---

## Workspace Layout

A single run creates one workspace directory inside the repo. The recovery bundle is a subdirectory of that workspace, so every run artifact is contained in the audited project.

```
<project-root>/
└── .repo_janitor_workspace/                        ← transient, in repo, .gitignored
    ├── project_profile.json                        ← Phase 1 output (incl. archetype + protected_globs)
    ├── candidates.tsv                              ← Phase 2 — every file matching ≥1 junk smell
    ├── candidates_grouped.md                       ← Phase 2 — by smell category
    ├── reference_graph.json                        ← Phase 2 — every candidate's inbound refs
    ├── wt_phase0.txt                               ← Phase 0 baseline working-tree snapshot
    ├── bundle_path.txt                             ← absolute path to the recovery bundle
    ├── bundle_verification.log                     ← Phase 3 byte-equality results
    ├── triage/
    │   ├── batch_001.tsv                           ← Phase 4 worker output
    │   ├── batch_002.tsv
    │   └── ...
    ├── triage.tsv                                  ← Phase 4/5 merged decision table
    ├── triage_decision.md                          ← Phase 5 user-facing markdown table
    ├── user_overrides.tsv                          ← Phase 5 — verdicts the user overrode
    ├── move_plan.md                                ← Phase 5 — every proposed (src → dst) + reference list
    ├── delete_plan.md                              ← Phase 5 — every `git rm` grouped by glob, with .gitignore proposal
    ├── gitignore_plan.md                           ← Phase 5 — proposed .gitignore additions w/ shadowing audit
    ├── apply_log.tsv                               ← Phase 6/7/8 — what landed, with commit SHAs
    ├── reference_rewrite_log.tsv                   ← Phase 6 — every reference fix done by the skill
    ├── conflicts/
    │   ├── candidate_034.context.md                ← Phase 6 — surfaced conflict + proposed fix
    │   └── ...
    ├── fresh_eyes_log.md                           ← Phase 9 — review rounds
    ├── cleanup_authorization.txt                   ← Phase 7/8 — verbatim user-typed authorization
    ├── handoff_report.md                           ← Phase 10 — final report
    └── skill_feedback.md                           ← Phase 11 (optional) — improvement notes

    └── recovery-bundle-<YYYY-MM-DD>/               ← persistent recovery bundle for this run
        ├── README.md                               ← recovery recipes + footgun warnings
        ├── index.tsv                               ← id  blob_sha  path_at_HEAD  size  mtime  smell  has_lfs_pointer
        ├── meta/
        │   ├── 000.txt                             ← path, blob_sha, last commit, author, date
        │   └── ...
        ├── working-tree-copies/                    ← byte-identical copies of every candidate
        │   ├── <path/at/HEAD/relative/to/repo-root>
        │   └── ...
        ├── gitignore-before.txt                    ← snapshot of repo's .gitignore at start
        ├── gitignore-proposed.diff                 ← diff of proposed additions
        └── reference-graph.json                    ← every candidate's inbound references
```

Backup of the head SHA before any commit lands:

```
.git/refs/repo-janitor-backup/<YYYY-MM-DD>-pre-cleanup     ← byte-identical to primary-branch HEAD before Phase 6
```

The bundle is deliberately inside `.repo_janitor_workspace/`. Keep `.repo_janitor_workspace/` in `.git/info/exclude` (local-only) so recovery artifacts do not pollute normal `git status`, while still staying inside the project being audited.

---

## Up-Front Confirmations (Ask Before Starting)

Use the intake template at `assets/intake-prompt.md` verbatim. The summary:

1. **Target path?** Confirm absolute path. If a git URL, ask whether to clone to `/tmp/<basename>`. Refuse to operate on a path that isn't a git work tree.
2. **Repo size + candidate preview up front.** Run `scripts/inventory-candidates.sh --preview` and tell the user the candidate count *before* asking them to commit time. >100 candidates is rare enough that users genuinely don't know the size.
3. **Repo archetype confirmation.** Show the auto-detected archetype (e.g., "polyglot monorepo with `crates/` + `apps/`", "claude skill repository", "Next.js + Supabase + Drizzle SaaS app", "single Rust crate", "single Python package"). If wrong, the user picks from a known list. The archetype shapes the junk-smell catalogue.
4. **Variant?** Auto-detect from candidate count (Quick 5–24, Standard 25–149, Comprehensive 150+). Variant sets orchestration depth and is orthogonal to mode. User can override.
5. **Mode?** Pick from the 9 named modes (see § Mode Router below). Default `full`. If unsure, suggest `triage-only` first — it produces the categorized plan without any mutations; user can re-run in another mode after seeing the plan.
6. **Recovery branch name?** Default `repo-janitor-<YYYY-MM-DD>`. The skill never lands cleanup commits directly on the primary branch.
7. **Bundle path?** Default `<project-root>/.repo_janitor_workspace/recovery-bundle-<YYYY-MM-DD>/`. Confirm OK; reject sibling directories.
8. **Reference-rewrite policy?** Default `auto-rewrite-with-confirmation`. If the user is paranoid about agents editing source, switch to `surface-only`.
9. **Resuming a prior run?** If `.repo_janitor_workspace/` already exists, run `bash $SKILL/scripts/phase-status.sh "$PROJECT"` first — it reports which phases have completed, which artifacts are present, and the suggested next step. Then offer the user: (a) resume from where phase-status indicates, (b) archive old workspace under a timestamped suffix and start fresh, or (c) abort.
10. **Concurrent agents?** Ask whether other agents are working in this repo right now. If yes, run `agent-mail file_reservation_paths(... ".gitignore", "**/*", reason="repo-janitor-<run-id>")` advisory-only so a parallel agent doesn't kick off a competing run.
11. **Quality gates?** Confirm the auto-detected `cargo test` / `bun tsc --noEmit` / `pytest` / `go test ./...` etc. is correct for this project. Default: run them on every Phase 6/7/8 commit.
12. **Protected-glob review.** Show the user the auto-derived `protected_globs` list (e.g., `Cargo.toml`, `package.json`, `LICENSE*`, `.env.example`, root-level `README.md` and `CHANGELOG.md`). The user can add but not remove.

If any helper skill referenced here is missing (`/operationalizing-expertise`, `/codebase-archaeology`, `/codebase-report`, `/agent-mail`, `/br`, `/bv`, `/ubs`, `/idea-wizard`, `/multi-pass-bug-hunting`, `/dcg`, `/git-stash-janitor`): if `jsm` is installed and authenticated, offer `jsm install <name>` for each missing one. Don't block a phase if a polish skill is missing — note it and proceed with the inline fallback.

---

## Skill Bootstrap (Phase 0.5 — right after inputs, before partition)

These scripts work from any working directory. Set `SKILL` once at the top, then keep `<project>` (an absolute path or `.` if you're cd'd into the project) consistent with what you used in Quick Start.

```bash
SKILL=/path/to/.claude/skills/git-repo-janitor   # same as Quick Start
PROJECT=<absolute-path-or-dot>                   # the repo being cleaned

# Detect helper skills + jsm state; write inventory JSON
bash $SKILL/scripts/check-skills.sh "$PROJECT/.repo_janitor_workspace"

# Optional: mine cass for prior runs against this repo
bash $SKILL/scripts/cass-mine.sh "$PROJECT" "$PROJECT/.repo_janitor_workspace"

# Detect primary branch, archetype, build/test/lint commands, conventions, protected_globs
bash $SKILL/scripts/discover-project.sh "$PROJECT" > "$PROJECT/.repo_janitor_workspace/project_profile.json"

# Detect per-repo branch policy (main only / main:master mirror / master only).
# Emits JSON to stdout AND merges into project_profile.json in-place when present.
bash $SKILL/scripts/branch-policy-detect.sh "$PROJECT" >/dev/null

# VERIFY-LIVE on git/lfs/etc. (Axiom 17); writes verification_log.md and merges into project_profile.json
bash $SKILL/scripts/verify-git-version.sh "$PROJECT"

# Emit phase0_scope_decision.md skeleton (per SCOPE-DECISION.md)
MODE=<mode> INTENT="<one-liner>" bash $SKILL/scripts/scope-decide.sh "$PROJECT"
```

If skills are missing and `jsm` is installed + authenticated:

```bash
bash $SKILL/scripts/install-referenced-skills.sh "$PROJECT/.repo_janitor_workspace"
```

The skill **never blocks** on a missing helper skill — every reference has an inline fallback in this SKILL.md or in `references/`.

---

## The Phase Loop (Mandatory)

```
Phase 0    UP-FRONT CONFIRMATIONS  intake template; user confirms target/mode/policy/gates
Phase 0.5  SKILL BOOTSTRAP         check-skills + scope-decide + verify-git-version + branch-policy
Phase 1    PROJECT RECONNAISSANCE  AGENTS.md, README.md, archaeology → project_profile.json + archetype
Phase 1.5  PHANTOM-DELETION CHECK  detect-phantom-deletions.sh; halt if >5 (Axiom 24)
           SUBMODULE CLASSIFICATION detect-submodule-issues.sh; surface (rewind)/(dirty) markers
Phase 2    CANDIDATE INVENTORY     smell-walk + reference-graph → candidates.tsv + reference_graph.json
Phase 2.5  SECRET-LEAK SCAN        match candidates against secret-smells; halt + escalate if any hit
Phase 3    RECOVERY BUNDLE         working-tree copies + meta + index + byte-equality verify
Phase 4    TRIAGE FAN-OUT          parallel workers (~30 candidates each) → triage.tsv
Phase 4.5  RISK SCORING            score every verdict (exploitability × blast-radius × reversibility)
Phase 5    TRIAGE MERGE & CONFIRM  per-category plan (A/B/C/...); user reviews; verdict overrides
Phase 6    APPLY MOVES             `git mv` + reference rewrites → focused commits + per-commit gates
Phase 7    APPLY DELETES (GATED)   `git rm` per glob batch → focused commits + per-commit gates
Phase 8    APPLY GITIGNORE (GATED) `.gitignore` updates with shadowing audit → focused commit
Phase 9    FRESH-EYES VERIFICATION three review prompts × ≥2 rounds; full test suite + linters
Phase 10   HANDOFF & FOLLOW-UPS    final report, beads issue, recovery recipes; user pushes
Phase 11   USER-LENS REVIEW        (optional, off by default) skill self-improvement notes
```

**Phase 2.5 is non-negotiable.** Every candidate's filename + first-100-bytes is run through the secret-smell rules ([FILE-SMELLS.md § Secret leakage](references/FILE-SMELLS.md#secret-leakage)). A real hit halts the routine flow; the skill switches to the secret-rotation playbook. This is not optional and is not a "Phase 4 verdict" — it's pre-empting the cleanup with a higher-priority remediation.

**Phases 4 and 9 are reapply-until-quiet** — keep spawning passes until an entire pass produces only trivial findings. Phase 9's two clean rounds are the explicit termination gate before the run can be declared complete.

**Phases 3, 5, 7, 8 are gates.** Phase 3 must complete with byte-equality verified before any classification logic runs. Phase 5 must end with explicit user go-ahead before Phase 6 starts. Phase 7 (deletes) must end with explicit user-typed verbatim authorization (per AGENTS.md "Mandatory explicit plan" rule) before any `git rm` executes. Phase 8 (gitignore) requires verbatim authorization for any addition that would shadow tracked files.

Full per-phase playbook with exit criteria + exact subagent prompts: **[PHASES.md](references/PHASES.md)** and **[AGENT-PROMPTS.md](references/AGENT-PROMPTS.md)**.

### Mode Variants (orchestration depth, orthogonal to mode)

| Variant | Candidate count | Wall time | Triage | Phase 9 | When |
|---------|-----------------|-----------|--------|---------|------|
| **Quick** | 5–24 | 20–40 min | Single agent reads each candidate | One round | Hand-curated; user already roughly knows the junk |
| **Standard** | 25–149 | 1–4 h | 2–4 parallel triage workers | ≥2 rounds | Typical repo with accumulated agent-swarm artifacts |
| **Comprehensive** | 150+ | 4–10 h | 5+ parallel workers; archaeology subagent for any "looks important but mislocated" candidate | ≥3 rounds, multi-model triangulation if available | Long-lived repos; production-critical; mixed-language monorepos |

Variant is recorded in `project_profile.json` at Phase 1. Phase gates (especially Phase 9 termination) adjust based on variant.

---

## Mode Router (the 9 named modes)

The skill runs in one of 9 modes. Modes are **orthogonal to variants** (Quick/Standard/Comprehensive) and **orthogonal to tiers** (T1–T5 by file count). Pick a mode at Phase 0; the skill enforces the mode's forbidden-actions and stop condition.

| Mode | Phases run | Stop condition | Forbidden actions |
|------|------------|----------------|-------------------|
| **`full`** (default) | 0, 0.5, 1, 1.5, 2, 2.5, 3, 4, 4.5, 5, 6, 7, 8, 9, 10 | Phase 9 ≥2 clean rounds + Phase 10 handoff filed | Pushing the recovery branch; deleting the bundle; force-pushing; `git filter-repo` |
| **`triage-only`** | 0, 0.5, 1, 1.5, 2, 2.5, 3, 4, 4.5, 5 — then halt | Phase 5 plan presented | Any `git mv` / `git rm` / `.gitignore` edit |
| **`move-only`** | 0–6, then handoff | Phase 6 complete; gates green | Phase 7 deletes; Phase 8 cleanup-pattern adds |
| **`delete-only`** | 0–4, 7, 8, 9, 10 (skip Phase 6 entirely) | Phase 9 ≥2 clean rounds | Any `git mv`; reference rewrites |
| **`gitignore-only`** | 0, 1, 2, 5 (gitignore plan only), 8, 10 | Phase 8 commit lands; `git check-ignore -v` confirms | Any `git rm` or `git mv` |
| **`harden-secret-leak`** | INCIDENT-PLAYBOOK § Secret Leak (10-step flow) | Origin verified clean; pre-commit hook smoke-tested | Any work outside the secret-leak flow until user confirms rotation; `--force` (only `--force-with-lease`); deleting the mirror backup |
| **`recover-from-bad-cleanup`** | Custom: 0, 1, then INCIDENT-PLAYBOOK § appropriate-section | Build green; user confirms recovered files match original intent | Forward cleanup work (this mode is purely backward-looking) |
| **`add-archetype-profile`** | Skill-extension flow | New archetype detected on a sample repo + smoke-tested | Any cleanup operations on the sample repo |
| **`maintenance-review`** | 0, 1, 2, 2.5; if no candidates: short-circuit; if candidates: `full` | "Nothing to do" handoff OR full re-run completes | Re-applying patterns from the previous run without re-confirming |

**Auto-escalation triggers** (each is *suggested*, never silent — user types verbatim auth):
- Phase 2.5 finds a real secret → escalate to `harden-secret-leak`
- Phase 4 finds 200+ broken refs in move plan → escalate from `move-only` / `full` to `triage-only` (re-plan)
- Phase 6 build breaks repeatedly → escalate to `recover-from-bad-cleanup`
- Phase 9 finds 10+ false-positive deletes → escalate to `recover-from-bad-cleanup`
- Phase 1 detects 162-repo workspace and user wants to clean many → escalate to `batch` (multi-repo orchestrator; see [BATCH-MODE.md](references/BATCH-MODE.md))

Full mode catalogue with handoff template, blast-radius escalator, and resumability per-mode: **[OPERATING-MODES.md](references/OPERATING-MODES.md)**.

---

## Parallelism Model

Inventory and bundle creation are serial (one source of truth). Triage is the large parallelizable phase. Apply is sequential per-batch (each commit changes the tree for later commits, but batches grouped by independent globs may run in any order).

```
┌─────────────────────────────────────────────────────────────┐
│  Phase 1 PROFILE  +  Phase 2 INVENTORY  +  Phase 3 BUNDLE   │ serial
│  (single agent — these establish the source of truth)       │
└────────────────────────┬────────────────────────────────────┘
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
     ┌──────────────┐           ┌──────────────┐
     │ Triage A     │   ...     │ Triage N     │   parallel, ~30 candidates each
     │ files 0-29   │           │ files 100+   │
     └──────┬───────┘           └───────┬──────┘
            │                           │
            └─────────────┬─────────────┘
                          ▼
              ┌─────────────────────────┐
              │ Phase 5 MERGE & CONFIRM │   single agent; reads all batches
              │ (USER GATE)             │
              └──────────┬──────────────┘
                         ▼
              ┌─────────────────────────┐
              │ Phase 6 APPLY MOVES     │   sequential per file; gates per commit
              │ Phase 7 APPLY DELETES   │   sequential per glob batch (GATED)
              │ Phase 8 GITIGNORE       │   single commit (GATED)
              └──────────┬──────────────┘
                         ▼
              ┌─────────────────────────┐
              │ Phase 9 FRESH-EYES      │   parallel review prompts
              └──────────┬──────────────┘
                         ▼
              ┌─────────────────────────┐
              │ Phase 10 HANDOFF        │
              └─────────────────────────┘
```

**Default execution: single Claude Code session.** The main agent uses the `Task` tool to spawn parallel subagents for Phase 4 (triage) and Phase 9 (fresh-eyes). No external orchestration is required. Sequential phases (3, 6, 7, 8) run in the main agent. This works in any environment that has Claude Code's Task tool — no NTM, no tmux, no extra setup.

**Coordination** — when [`/agent-mail`](../agent-mail/SKILL.md) is available, use file reservations on `.repo_janitor_workspace/triage/**` so triage workers don't stomp each other (thread id: `repo-janitor-<run-id>`, = the beads issue id once filed). When Agent Mail isn't available, the main agent serializes worker invocations to avoid races.

**Orchestration tier** — pick based on candidate count and stakes (full matrix + per-tier wall-time in [ORCHESTRATION.md](references/ORCHESTRATION.md)):

| Tier | Workers (Phase 4) | Default execution | When |
|------|-------------------|-------------------|------|
| Solo | 1 | Main agent only, no Task fan-out | <25 candidates; routine cleanup |
| Pair | 2 | 2 parallel Task subagents | 25–60 candidates |
| Squad | 4–6 | 4–6 parallel Task subagents | 60–200 candidates |
| Swarm | 8–12 | 8–12 parallel Task subagents | 200–500 candidates |
| Council | 12+ | Task subagents + multi-model triangulation (requires `/multi-model-triangulation` skill OR NTM) | 500+ candidates; production-critical; security-sensitive content |

The default execution at every tier uses Claude via the Task tool. Multi-model triangulation (Codex / Gemini in addition to Claude) is **opt-in** at any tier and required for Council; see [MULTI-MODEL-TRIANGULATION.md](references/MULTI-MODEL-TRIANGULATION.md). NTM swarm panes are an optional alternative orchestration topology useful when the user already runs NTM; see [ORCHESTRATION.md § Optional: NTM Swarm Topology](references/ORCHESTRATION.md#optional-ntm-swarm-topology).

**Modes-of-reasoning composition** — even on a single-model single-stance run, the agent can vary stance per phase (Literal in Phase 4 triage; Forensic in Phase 5 plan composition; Adversarial in Phase 9 round 3). See [MODES-OF-REASONING.md](references/MODES-OF-REASONING.md).

---

## Operator Library — The Cognitive Moves

Each operator is a reusable verb with explicit triggers, a prompt module, and exit criteria. These are *what to think about*, not just *what to do*. Adapted from [`operationalizing-expertise`](../operationalizing-expertise/SKILL.md) Track A.

| Glyph | Name | Question / Action | When to Apply |
|-------|------|------------------|---------------|
| `★` | **INVENTORY** | Walk the working tree; capture every file that matches ≥1 junk smell into one TSV with blob SHA, path, size, mtime, smell-tags | Phase 2 — once, the source of truth |
| `🔍` | **CLASSIFY-PURPOSE** | Determine each candidate's true purpose: source / test fixture / build artifact / agent-skill output / plan doc / scratch / log / DB | Phase 4, per-candidate, before any verdict |
| `📍` | **LOCATE-PROPER-HOME** | For move candidates, propose a destination path that fits the archetype's conventions (e.g., `docs/planning/<file>`, `tests/fixtures/<file>`, `tools/scratch/<file>`) | Phase 4, when verdict is `move` |
| `💎` | **ASSESS-VALUE** | Does this file have unique content not derivable from elsewhere? Plan docs YES; auto-generated reports usually NO; binary DBs almost never. Drive `delete-and-gitignore` vs `move` decision | Phase 4, after CLASSIFY-PURPOSE |
| `🔗` | **REFERENCE-GREP** | Grep the entire repo for the candidate's basename + relative path + glob match before any move/delete; ≥1 hit flips verdict to `surface-to-user` | Phase 4 every candidate; Phase 6 again before each move |
| `🧮` | **PATTERN-EXTRACT** | When 5+ candidates share a glob (e.g., `*.sqlite-wal`), generate a single `.gitignore` rule + a single batched delete commit | Phase 5, plan composition |
| `🛡` | **SHADOWING-AUDIT** | For every proposed `.gitignore` line, run `git check-ignore -v` + `git ls-files <glob>`; surface any tracked file the new rule would mask | Phase 5, before user sign-off; Phase 8, before commit |
| `⬡` | **BUNDLE** | Materialize byte-identical copies + meta + index + reference graph for every candidate; verify byte-equality before allowing destructive phases | Phase 3 — the irreversibility gate |
| `⚠` | **CONFIRM** | Restate the destructive command verbatim; wait for explicit user OK in the same message; record the authorization text | Phases 5, 7, 8 |
| `✦` | **MOVE-WITH-RENAME** | `git mv <src> <dst>` (never `mv` + `git add` — preserves rename detection); copy the bundle's working-tree-copy as a sanity check | Phase 6 |
| `↪` | **REWRITE-REFERENCES** | After every move, fix every reference grep'd in Phase 4 — through the Edit tool, never sed/awk; surface unfixable references to user | Phase 6 |
| `⊟` | **REMOVE-WITH-RM** | `git rm <path>` (or `git rm --cached <path>` if user wants the file kept on disk but un-tracked); never `rm` | Phase 7 |
| `⊕` | **GATE-RUN** | Run the project's actual quality gates (`cargo test`, `bun tsc --noEmit`, `pytest`, build) on every commit; catch compounding errors per-commit, not at the end | Phases 6, 7, 8 — after every commit |
| `↺` | **WORKING-TREE-DRIFT** | Before each Phase 6/7/8 mutation, re-snapshot `git status` + `git diff`; if changes appear from other agents, treat as if you made them; never stash/revert/overwrite | Phases 6, 7, 8, every iteration |
| `⌘` | **HANDOFF** | Final report with: counts per verdict, recovery commit SHAs, bundle path, `.gitignore` diff, reference-rewrite log, verbatim recovery recipes; never push | Phase 10 |

**Plus 11 additional operators** (added in expansion; full cards in [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md)):

| Glyph | Name | When to apply |
|-------|------|---------------|
| `◑` | **VERIFY-LIVE** | Any time a recommendation depends on volatile git behavior (filter-repo, rename detection, LFS interaction); Phase 1 + harden-secret-leak |
| `⌖` | **FALSE-POSITIVE-CHECK** | After REFERENCE-GREP, hand-validate each ref-hit's surrounding context to distinguish substring false-positives from true references |
| `⊞` | **COVERAGE-MATRIX** | Phase 2.5: emit one row per FILE-SMELLS rule × `present \| partial \| missing \| n/a` against this repo |
| `⊠` | **NEGATIVE-DECISION** | Whenever the agent excludes a smell rule, skips a phase, or defers a category — document *why* in `negative_decisions.md` |
| `⩚` | **VULNERABLE-FILE-FILTER** | Treat secrets, referenced-by-tests fixtures, archetype-protected files as having special handling that overrides generic verdict logic |
| `⟳` | **CROSS-ARCHETYPE-CHECK** | When the repo matches 2+ archetypes (Rust crate inside a Next.js app's `crates/native/`), union per-subtree protected_globs |
| `↻` | **RE-FINGERPRINT** | After every Phase 6 apply, re-run REFERENCE-GREP on downstream candidates whose files were touched by ref-rewrites; some verdicts may flip |
| `⧗` | **TIME-BOXED-PIVOT** | Phase 9: define a rollback window (default 30 min after verbatim auth) during which user can cleanly `git revert` |
| `⊛` | **LAYERED-DEFENSE** | Document 3 recovery paths per destructive verdict: bundle copy + git history + (when applicable) mirror clone |
| `⊙` | **PROVENANCE-WRAP** | Every artifact in `.repo_janitor_workspace/` opens with `produced_at | produced_by | source_phase | confidence | inputs_hash` header |
| `✸` | **PIN-THE-CONTRACT** | After non-trivial Phase 6/7/8 commits, write a drift-guard / regression test that future maintainers can't accidentally remove |

Full operator cards (with prompt modules, failure modes, source citations, quote-bank anchors, composition diagrams): **[OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md)**.

---

## The Polish Bar (Non-Negotiable)

A "successful repo janitor run" is not "the junk is gone." Every cleanup commit must satisfy:

| Dimension | Test |
|-----------|------|
| **Recovery completeness** | Every candidate has a working-tree-copy in the bundle AND an index entry AND a meta file; byte-equality verified before any destructive phase |
| **Verdict evidence** | Every triage row cites concrete evidence — smell category, reference-grep result, archetype rule, or AGENTS.md/README mention; "looks like junk" alone is never acceptable |
| **No false-positive deletes** | No file is deleted when REFERENCE-GREP finds ≥1 inbound hit; any such candidate flips to `surface-to-user` |
| **No silently-broken references** | Every move's reference graph was checked; every reference either was rewritten (logged in `reference_rewrite_log.tsv`) or was surfaced to the user |
| **Per-commit gates** | Every Phase 6/7/8 commit has run the project's full test/typecheck/lint/build suite, and they all pass; no "we'll fix it at the end" |
| **`.gitignore` shadowing audit** | Every newly-added `.gitignore` line was run through `git ls-files <glob>` to surface tracked-file shadowing before user sign-off |
| **Focused commit messages** | Each commit explains *why* this change is happening: not "remove junk" but "remove 12 ephemeral SQLite WAL files generated by integration tests; add `*.db-wal` to `.gitignore`" |
| **Order of operations** | moves → deletes → `.gitignore` updates (deletes must precede the `.gitignore` add, otherwise `.gitignore` won't take effect on already-tracked files unless `git rm --cached` ran first) |
| **Verbatim authorization** | Phases 7 and 8 only ran after the user typed the literal commands (or an authorization phrase that quotes them); recorded in `cleanup_authorization.txt` |
| **Idempotent on a clean repo** | Re-running on a freshly-cleaned repo produces no commits and reports "nothing to do" |
| **Resumable** | If interrupted mid-Phase 6/7, re-running picks up from the last successful commit using `apply_log.tsv` + git log |
| **Build still works** | After Phase 9, `<test_command> && <typecheck_command> && <build_command>` succeeds from a clean checkout |
| **Phase 2.5 ran clean** | `secret_findings.tsv` exists; every entry has a documented user resolution (rotation done, public-key-only, false-positive marked) |
| **Audit trail intact** | All required artifacts exist; bundle + backup ref present; `apply_log.tsv` populated; `cleanup_authorization.txt` populated for any gated phase |
| **Verification log written** | If volatile-behavior operators ran (filter-repo, force-with-lease), `verification_log.md` has corresponding entries (Axiom 17) |
| **Coverage matrix complete** | Every FILE-SMELLS rule has a row in `coverage_matrix.md`; no blank cells (Axiom 18) |
| **Phantom deletions handled** | If any phantom deletions were detected, they were resolved (restored or user-confirmed delete) before any cleanup commits landed (Axiom 24) |
| **Mode escalation recorded** | If a mode escalation occurred, `mode_escalation_decision.md` exists with user authorization (Axiom 21) |

If a run can't satisfy these 18 dimensions, it has not "completed successfully" — it has half-finished and needs to flow back through whichever phase failed.

Full rubric: **[POLISH-BAR.md](references/POLISH-BAR.md)**. Literal grep / git command per dimension: **[POLISH-BAR-VERIFICATION-QUERIES.md](references/POLISH-BAR-VERIFICATION-QUERIES.md)**. Run them via `bash "$SKILL/scripts/polish-bar-check.sh" "$PROJECT"`.

---

## Failure Modes Table — The Common Footguns

Every entry below was learned the hard way during real repo-cleanup runs (or from sibling skills' incident logs). Treat them as known-quantity hazards.

| Symptom | Cause | What to do |
|---------|-------|------------|
| Adding `*.json` to `.gitignore` doesn't stop `git status` from seeing already-tracked JSON files | Git's `.gitignore` only affects untracked files; tracked files remain tracked unless `git rm --cached` runs | The skill's SHADOWING-AUDIT (`git ls-files <glob>`) surfaces this before sign-off; the cleanup commit pairs `git rm --cached <files>` with the `.gitignore` add |
| `mv old.md new/path/old.md` followed by `git add` shows up as "delete + add" instead of "rename" | Git's rename detection threshold wasn't met; renames-as-edits are auto-detected only when content similarity ≥ ~50% | Always use `git mv`, which records a rename explicitly. Falls back to delete+add only when content has changed too much to detect |
| Markdown link `[plan](./PLAN.md)` 404s after move to `docs/planning/PLAN.md` | Move didn't update the reference | REFERENCE-GREP catches this in Phase 4. Phase 6 either rewrites the link via the Edit tool or surfaces it to the user — never silently moves without addressing references |
| `tests/conftest.py` imports `import scratch` and Phase 7 deleted `scratch.py` | `scratch.py` looked like junk but was a tracked test helper | REFERENCE-GREP catches this. Even one hit on the basename or path flips verdict to `surface-to-user` |
| A `data/seed.db` SQLite file deleted because `.db` is a junk smell | The archetype profile's `protected_globs` should have included `data/*.db` for this repo type | Phase 1 archetype detection sets defaults; Phase 0 user confirmation lets the user add but not remove protected globs; Phase 4 still flips the verdict if a `data/` parent is in `protected_globs` |
| `.gitignore` entry `temp_*` matches a file the user didn't notice (`temp_module.py`) | Glob too broad; pattern surface area underestimated | SHADOWING-AUDIT runs `git ls-files <glob>` for every proposed addition; matches are listed in `gitignore_plan.md` for user review; user types verbatim auth referencing the matches |
| The bundle's working-tree-copy is corrupted because the file changed mid-Phase 3 (concurrent agent) | A second agent edited the file between snapshot and copy | Phase 3 verifies SHA-256 of every working-tree-copy against the live blob right before sealing the bundle. If hash drifts during Phase 3, the run halts and Phase 3 restarts |
| Working tree shows changes from other agents mid-run | Concurrent agents in the same repo (per AGENTS.md) | Treat as if you made them. Never stash, revert, or overwrite. Re-snapshot `git status` before each Phase 6/7/8 commit |
| `git rm` blocked because the file has uncommitted local changes | Concurrent agent modified the file after Phase 3 snapshot | Don't force. Re-snapshot, re-classify, surface to user — the file may have evolved past "junk" |
| LFS-tracked file deletion leaves a dangling LFS pointer in the bundle | The bundle's working-tree-copy is the pointer, not the actual blob | Phase 3 dereferences LFS pointers via `git lfs smudge` for in-bundle copies; index records both pointer and blob SHA |
| Submodule directory matched a junk glob | Submodule trees are out of scope but their checkout dir is in the parent repo's tree | Phase 1 enumerates `git submodule status`; the inventory walk skips submodule subtrees; submodule-internal junk requires a separate run inside the submodule |
| `rm -rf <bundle>/` blocked by DCG | Destructive Command Guard hook | Don't fight it. The skill **never deletes the bundle** — the user manages bundle lifecycle |
| Phase 6 reference rewrite breaks a code import that doesn't lexically match the path | Reference uses an alias / re-export / Python `__init__` indirection | Surface to user; never auto-rewrite imports without lexical match. The Edit tool's old-string requirement makes this self-enforcing |
| Beads database unwritable during the run | `.beads/beads.db` locked by a parallel `br` process | Skip the beads-issue creation; record `beads_skipped: true` in the handoff report; the run still succeeds |
| User runs the skill on a sub-directory of a larger repo | The skill needs the repo root to walk `git ls-files` correctly | `scripts/git-doctor.sh` resolves to repo root via `git rev-parse --show-toplevel`; the skill always operates from there |
| Phase 2.5 surfaces a real `*.key` private key tracked in a public repo | Secret committed (often `git add -f` despite an existing `.gitignore` rule); public exposure window from push date forward | Halt routine cleanup. Surface the secret with full provenance. Run [INCIDENT-PLAYBOOK.md § Secret Leak](references/INCIDENT-PLAYBOOK.md#secret-leak-recovery): mirror-backup → user rotates key → `git filter-repo --invert-paths --path <secret>` → verify origin/branch synced first (Axiom 16) → `git push --force-with-lease` to main AND any synonym branches (`master`) → broaden `.gitignore` → install `.githooks/pre-commit` → document in AGENTS.md |
| `git filter-repo` rewrote only some of the secret's history | Local clone was shallow / partial; origin had more commits than local (Axiom 16) | Before re-running: `git fetch origin && git update-ref refs/heads/<branch> refs/remotes/origin/<branch>`. Re-verify `git rev-list --count <branch> == git rev-list --count origin/<branch>`. Then re-run filter-repo |
| `.gitignore` already blocks `*.key` but the secret got committed anyway | Someone bypassed `.gitignore` with `git add -f <file>` | Belt-and-suspenders: install `.githooks/pre-commit` that scans staged paths against secret-smells AND content-fingerprints (length, base64-decode-success, etc.). Smoke-test the hook by staging a fake `test-fake.key` and confirming the commit is blocked |
| The same content exists in two file formats (e.g., `repo_illustration.png` AND `repo_illustration.webp`) | One was the predecessor; the README points to one of them | REFERENCE-GREP each separately; the unreferenced format is the deletion candidate, not both |
| A `verify` shell script at root looks like junk | Verification entrypoints are commonly named exactly `verify` and are referenced by docs and tests | REFERENCE-GREP catches the `tests/ext_conformance.rs:4: described in CONFORMANCE.md` and `verify.sh` style mentions; verdict flips to `keep-in-place` |
| A `*.patch` file at root is large but tracked | Often a `git format-patch` output captured for an in-flight migration; usually NOT meant to live in the tree | If user confirms it's no longer needed → delete; if it's a multi-month-old fork-rebase artifact, ask why it's still there |
| `nohup.out` is tracked | Someone ran `nohup <cmd> &` from the repo root and committed the resulting log | Always `delete-and-gitignore`; add `nohup.out` to `.gitignore` |
| `.skill-loop-progress.md` or similar `.<skill>-...md` is tracked | Intermediate output of a slash-skill (e.g., simplify-and-refactor-code-isomorphically) leaked into the working tree | Always `delete-and-gitignore`; add `.skill-loop-progress.md` and other known skill-output globs to `.gitignore` |
| Per-bead progress reports `progress_bd-<id>.md` accumulate at root | Each bead's work session emitted a status file; mostly redundant with `.beads/issues.jsonl` | `move` to `docs/progress/` (preserves history) and add `/progress_bd-*.md` + `/bd-*.md` to `.gitignore` to prevent recurrence |
| 6 PLAN_*.md files at root from different LLMs (`__GPT.md`, `__OPUS.md`, `__GEMINI.md`, etc.) | Multi-model brainstorming pattern leaves multiple drafts | All move to `docs/planning/`; reference-grep first because `__GPT.md` versions sometimes refer to `__OPUS.md` versions |

Full diagnostic playbook with reproductions: **[FAILURE-MODES.md](references/FAILURE-MODES.md)**.

---

## Anti-Patterns (Never Do)

| ✗ | Why | Fix |
|---|-----|-----|
| Use `rm`, `find -delete`, or `git ls-files \| xargs rm` to delete tracked files | Filesystem deletion bypasses git's history; you lose the rename/delete record | `git rm <path>` only |
| Add a glob to `.gitignore` without `git ls-files <glob>` | Could silently shadow a tracked file the user cares about | SHADOWING-AUDIT every addition; pair with `git rm --cached` if shadowing |
| `mv` + `git add` instead of `git mv` | Loses rename detection; `git log --follow` and blame break across the move | Always `git mv` |
| Delete a candidate without REFERENCE-GREP | A "junk-looking" file may be referenced by tests, scripts, or docs | REFERENCE-GREP every candidate; ≥1 hit flips to `surface-to-user` |
| Mass-rewrite references with `sed -i` after a move | Brittle, multi-occurrence files break, no auditability (per AGENTS.md "No Script-Based Changes") | Edit tool, one old/new pair at a time, logged in `reference_rewrite_log.tsv` |
| Land cleanup commits directly on the primary branch | Even with verification, mass cleanups deserve user review | Land on `repo-janitor-<DATE>` branch; user merges/cherry-picks |
| Bypass pre-commit hooks (`--no-verify`) | The user's gates exist for a reason | Fix the underlying issue; if you can't, surface to user |
| `rm -rf` the bundle after a "successful" run | DCG blocks it AND the user owns bundle lifecycle | Leave the bundle in place; report its path in handoff |
| Skip Phase 3 byte-equality verification | If the bundle is wrong, the entire run is unsafe | Phase 3 is a hard gate — refuse to proceed if even one copy doesn't hash-match |
| Auto-rewrite references in source code without surfacing the change | Reference rewriting in `.py`/`.ts`/`.rs` files is a code edit, not just a janitorial chore | The default `auto-rewrite-with-confirmation` policy: surface every rewrite plan; user OKs before the Edit tool runs. `surface-only` policy never edits source |
| Stash, revert, or overwrite changes from other agents in the working tree | Per AGENTS.md "Note for Codex/GPT-5.5" — those are concurrent agents' work | Treat as if you made them; never disturb |
| Push the recovery branch on the user's behalf | Like the documentation-website skill, deployment is the user's call | Print the suggested `git push` command and stop |
| Use the basename to identify files | Two files can share a basename across directories; the canonical key is `(blob_sha, path_at_HEAD)` | Always carry the full repo-relative path |
| Apply `.gitignore` updates BEFORE deleting the matching tracked files | The new ignore rules don't affect already-tracked files; `git status` will still show them | Order is `git rm` first, `.gitignore` update second |
| Treat `.git/` contents as candidates | The skill operates on the working tree, not the git internal store | `scripts/inventory-candidates.sh` excludes `.git/` and `.git*/` by construction |

Full anti-pattern catalogue with worked examples: **[ANTI-PATTERNS.md](references/ANTI-PATTERNS.md)**.

---

## When NOT to Use This Skill

- **Fewer than 5 junk candidates.** Just `git status` + `git ls-files` + manual `git rm`. The recovery-bundle overhead doesn't pay off.
- **A clean repo.** If the inventory walk surfaces zero candidates, the skill exits with "nothing to do." Don't run it just because it's available.
- **A bare repo.** No working tree to walk.
- **Mid-rebase / mid-merge.** `git status` shows `interactive rebase in progress` or unmerged paths — finish the operation first; the skill needs a clean checkout state to snapshot from.
- **A repo that's mid-large-refactor.** If the user is in the middle of restructuring — moving directories around, renaming packages — let them finish; running the janitor concurrently will fight them.
- **Detached HEAD with no recovery branch base.** The skill needs a primary branch to land cleanup onto; if the user is in detached-HEAD state, ask them to check out a branch first.
- **A repo where the "junk" is intentional.** Some repos track build outputs (vendored compiled assets, generated SDKs). The archetype profile should make this clear; if the user contests the candidate list at Phase 5, abort.
- **Submodules' internal trees.** Run a separate skill instance inside the submodule.
- **Repos with active ongoing operations on `.gitignore`.** If the user is mid-edit on `.gitignore`, the skill will see uncommitted changes — pause until they're committed.

Full conditions and rationale: **[WHEN-NOT-TO-USE.md](references/WHEN-NOT-TO-USE.md)**.

---

## Pre-Flight & End Checklist

### Phase 0 / 0.5 (intake + bootstrap)
- [ ] `git-doctor.sh` passed (no mid-rebase / merge / cherry-pick / revert / bisect; HEAD points to a branch)
- [ ] Target path confirmed; primary branch detected (NOT assumed `main`)
- [ ] Repo archetype detected and confirmed; `protected_globs` shown to user
- [ ] Branch policy detected (main only / main:master mirror / master only)
- [ ] `verify-git-version.sh` ran; `verification_log.md` exists with git/lfs/filter-repo versions
- [ ] Candidate count reported to user up front; mode + variant selected (per § Mode Router)
- [ ] Mode confirmed (full / triage-only / move-only / delete-only / gitignore-only / harden-secret-leak / recover-from-bad-cleanup / add-archetype-profile / maintenance-review)
- [ ] Recovery branch name confirmed; bundle path confirmed
- [ ] Reference-rewrite policy confirmed
- [ ] Working tree state snapshotted (`wt_phase0.txt`)
- [ ] `phase0_scope_decision.md` emitted with REQUIRED / CONDITIONAL / NOT-DOING buckets

### Phase 1 / 1.5 (profile + safety)
- [ ] Phase 1 produced `project_profile.json` with primary branch + quality-gate commands + archetype + protected_globs + branch_synonyms
- [ ] Phase 1.5 phantom-deletion check: ≤5 phantoms (or user resolved each via `git checkout HEAD -- <path>`)
- [ ] Submodule classifier ran (if `.gitmodules` exists); `submodule_warnings.tsv` reviewed; rewinds/dirty surfaced

### Phase 2 / 2.5 (inventory + secret scan)
- [ ] Phase 2 produced `candidates.tsv` covering every junk-smell file + `reference_graph.json`
- [ ] Phase 2.5 secret scan ran; `secret_findings.tsv` exists (may be empty)
- [ ] If real secret found: `harden-secret-leak` mode escalation recorded in `mode_escalation_decision.md`
- [ ] Coverage matrix emitted; every FILE-SMELLS rule has a row; no blank cells

### Phase 3 (bundle)
- [ ] Bundle exists with working-tree-copies + meta + index + gitignore-before + reference-graph + README
- [ ] Byte-equality verified across all entries (`bundle_verification.log` shows zero MISMATCH lines)
- [ ] Backup ref `refs/repo-janitor-backup/<DATE>-pre-cleanup` created
- [ ] Recovery drill: sample candidate restoration tested

### Phase 4 / 4.5 (triage + risk score)
- [ ] Phase 4 triage workers all completed; `triage.tsv` is one row per candidate
- [ ] Every row has non-empty `evidence` and `confidence`
- [ ] No verdict `delete-*` with `confidence > 0.7` AND `inbound_refs > 0`
- [ ] Phase 4.5 risk score column added; rows ordered by risk band for Phase 5

### Phase 5 (user gate)
- [ ] User reviewed and confirmed the categorized A/B/C/... plan; `move/delete/gitignore` plans signed off
- [ ] User overrides captured in `user_overrides.tsv`

### Phase 6 / 7 / 8 (mutation phases)
- [ ] Phase 6 move commits each have a passing test/typecheck/lint/build run
- [ ] Phase 6 reference rewrites logged in `reference_rewrite_log.tsv`
- [ ] Phase 7 verbatim authorization in `cleanup_authorization.txt`
- [ ] Phase 7 delete commits each have a passing gates run
- [ ] Phase 8 `.gitignore` commit has SHADOWING-AUDIT captured; verbatim auth for any newly-shadowed pattern

### Phase 9 / 10 (verification + handoff)
- [ ] Phase 9 fresh-eyes ran ≥2 rounds clean; full test suite green; UBS clean (if available); build green
- [ ] `polish-bar-check.sh` passes all 18 dimensions
- [ ] Phase 10 `handoff_report.md` emitted; beads issue filed; recovery recipes verified
- [ ] User informed they need to push (`git push origin repo-janitor-<DATE>` and synonym pushes if applicable)
- [ ] Bundle path reported; left in place; NOT deleted

---

## Source Corpus

Every Anti-Pattern, Failure Mode, Operator card, and File Smell in this skill traces back to a real session, a verified git-internals quirk, or a sibling skill's hard-won lesson.

| Source | Contribution |
|--------|--------------|
| The motivating user prompt ("the repo junk cleaner") | The seven-verdict taxonomy; the bar-for-keeping-binaries discipline; the move-vs-delete-vs-gitignore decoupling |
| The Apr-27 multi-repo cleanup session (frankensqlite 109→45, CASS 46→18, pi_agent_rust 41→16, ntm 36→21, beads_viewer 31→18, mcp_agent_mail 29→24) | The category-letter (A/B/C/...) plan format; the "skip cat C" pattern when references are too pervasive; the per-category atomic-commit cadence; the per-batch `cargo check` discipline; the actual junk-smell catalogue (`nohup.out`, `*.bck.yml`, `*.skill-loop-progress.md`, `progress_bd-*.md`, multi-LLM `PLAN_*__GPT.md` clusters, ELF binaries at root, `*.patch` blobs, dual `.png`/`.webp` formats); the `verify` script false-positive case |
| The same session's mcp_agent_mail Ed25519 key incident | Axiom 15 (secret halts cleanup); Axiom 16 (shallow-clone gotcha); Phase 2.5 secret-leak scan; INCIDENT-PLAYBOOK § Secret Leak; the mirror-backup-first / filter-repo / force-with-lease / pre-commit-hook recovery flow; the "force-add bypass" failure mode |
| `git-stash-janitor` skill | Phase loop structure; recovery-bundle discipline; byte-equality verification; verbatim-authorization gates; orchestration tiers; polish bar; operator-library form; modes-of-reasoning composition |
| `documentation-website-for-software-project` skill | Multi-phase parallel-subagent pipeline; codebase-archaeology opener; three-prompt fresh-eyes loop; resumability discipline |
| `wills-and-estate-planning-skill` | Verification-first overlay; irreversible-action discipline; recovery-bundle mindset; careful audit of pre-existing state |
| `saas-billing-patterns-for-stripe-and-paypal` | Dry-run/preview-before-mutate ergonomics; idempotent re-runnability; structured triage rubric over noisy real-world data; per-phase artifact manifest |
| AGENTS.md "Note for Codex/GPT-5.5" | The working-tree-drift discipline (Axiom 8) |
| AGENTS.md "Mandatory explicit plan" | The verbatim authorization gates (Axiom 9, ⚠ CONFIRM) |
| AGENTS.md "RULE NUMBER 1: NO FILE DELETION" | The bundle-lifecycle rule (Axiom 13); the "skill never deletes" principle for bundle/source |
| AGENTS.md "No Script-Based Changes" | The Edit-tool-only reference-rewrite policy (Axiom 12, ↪ REWRITE-REFERENCES) |
| Pro Git §2 (gitignore semantics) | Axiom 6 (.gitignore doesn't shadow tracked files); SHADOWING-AUDIT operator |
| `git mv` documentation + rename-detection internals | Axiom 5 (move ≠ delete + add); MOVE-WITH-RENAME operator |
| `operationalizing-expertise` (Track A) | Operator card structure; quote-bank pattern; cognitive-move taxonomy |

When extending this skill, every new card needs a source citation. New patterns without traceable provenance are speculation, not knowledge.

---

## Reference Index

### Core playbooks
| Need | File |
|------|------|
| Phase-by-phase playbook with exit criteria | [PHASES.md](references/PHASES.md) |
| Exact prompts for each parallel subagent | [AGENT-PROMPTS.md](references/AGENT-PROMPTS.md) |
| Per-candidate triage rubric (smell, reference-grep, verdicts, evidence) | [TRIAGE-RUBRIC.md](references/TRIAGE-RUBRIC.md) |
| Polish Bar — what "successful" means | [POLISH-BAR.md](references/POLISH-BAR.md) |
| Verbatim kickoff prompts per mode | [KICKOFF-PROMPTS.md](references/KICKOFF-PROMPTS.md) |
| Per-phase SLOs and quality metrics | [MEASUREMENT.md](references/MEASUREMENT.md) |

### Methodology (the high-level reasoning files)
| Need | File |
|------|------|
| Cognitive moves: operator cards + prompt modules | [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md) |
| Reading stances: literal / skeptical / forensic / adversarial | [MODES-OF-REASONING.md](references/MODES-OF-REASONING.md) |
| Orchestration tiers + fan-out (default = single-session Task subagents; NTM optional) | [ORCHESTRATION.md](references/ORCHESTRATION.md) |
| Multi-model triangulation (Claude+Codex+Gemini) | [MULTI-MODEL-TRIANGULATION.md](references/MULTI-MODEL-TRIANGULATION.md) |
| Anti-pattern catalogue with worked examples | [ANTI-PATTERNS.md](references/ANTI-PATTERNS.md) |
| Failure modes & diagnostic playbook | [FAILURE-MODES.md](references/FAILURE-MODES.md) |
| Incident playbook — when things go wrong | [INCIDENT-PLAYBOOK.md](references/INCIDENT-PLAYBOOK.md) |
| Quote bank — distilled invariants | [KEY-INSIGHTS.md](references/KEY-INSIGHTS.md) |
| Structured §n-anchored corpus | [QUOTE-BANK.md](references/QUOTE-BANK.md) |
| Verification-first overlay (volatile vs evergreen) | [VERIFICATION-FIRST.md](references/VERIFICATION-FIRST.md) |
| Operating modes catalogue + decision tree + handoff template | [OPERATING-MODES.md](references/OPERATING-MODES.md) |
| Tier triage (T1-T5 + complexity overlay) | [TIER-TRIAGE.md](references/TIER-TRIAGE.md) |
| Scope decision artifact (`phase0_scope_decision.md` schema) | [SCOPE-DECISION.md](references/SCOPE-DECISION.md) |
| Coverage matrix (smell rule × candidate × status) | [COVERAGE-MATRIX.md](references/COVERAGE-MATRIX.md) |
| Confidence scoring (4 dimensions, lowest caps) | [CONFIDENCE-SCORING.md](references/CONFIDENCE-SCORING.md) |
| Adaptive interview flow | [INTERVIEW-FLOW.md](references/INTERVIEW-FLOW.md) |
| Source corpus map (provenance for every pattern) | [SOURCE-COVERAGE-MAP.md](references/SOURCE-COVERAGE-MAP.md) |
| Polish bar verification queries (literal grep/git per dimension) | [POLISH-BAR-VERIFICATION-QUERIES.md](references/POLISH-BAR-VERIFICATION-QUERIES.md) |
| Multi-repo batch orchestration | [BATCH-MODE.md](references/BATCH-MODE.md) |

### Junk craft (the hands-on cleanup details)
| Need | File |
|------|------|
| Taxonomy of file smells — sqlite, intermediate-md, scratch-script, etc. | [FILE-SMELLS.md](references/FILE-SMELLS.md) |
| Per-language junk patterns | [LANGUAGE-PROFILES.md](references/LANGUAGE-PROFILES.md) |
| Repo-archetype profiles — monorepo, single crate, skill repo, Next.js, etc. | [REPO-ARCHETYPES.md](references/REPO-ARCHETYPES.md) |
| Protected-glob inheritance (base + archetype + extensions + user) | [PROTECTED-GLOB-INHERITANCE.md](references/PROTECTED-GLOB-INHERITANCE.md) |
| `.gitignore` craft: glob semantics, shadowing audit, ordering | [GITIGNORE-CRAFT.md](references/GITIGNORE-CRAFT.md) |
| Commit-message craft for cleanup commits | [COMMIT-MESSAGE-CRAFT.md](references/COMMIT-MESSAGE-CRAFT.md) |
| Evidence citation style guide | [EVIDENCE-CITATIONS.md](references/EVIDENCE-CITATIONS.md) |
| Fresh-eyes prompt extended library | [FRESH-EYES-PROMPTS.md](references/FRESH-EYES-PROMPTS.md) |
| Leak taxonomy (8 secret-leak categories + rotation procedures) | [LEAK-TAXONOMY.md](references/LEAK-TAXONOMY.md) |
| When NOT to use this skill | [WHEN-NOT-TO-USE.md](references/WHEN-NOT-TO-USE.md) |

### Worked examples + recovery
| Need | File |
|------|------|
| Worked examples: 11 cleanup sessions across many archetypes | [WORKED-EXAMPLES.md](references/WORKED-EXAMPLES.md) |
| Recovery recipes — how to undo every kind of move/delete/gitignore | [RECOVERY-RECIPES.md](references/RECOVERY-RECIPES.md) |
| Bundle format spec (for tooling that consumes the bundle) | [BUNDLE-FORMAT-SPEC.md](references/BUNDLE-FORMAT-SPEC.md) |
| Resumability — per-phase re-entry contract | [RESUMABILITY.md](references/RESUMABILITY.md) |
| Mirror backup drill (Layer 4 recovery for history-rewrite ops) | [MIRROR-BACKUP-DRILL.md](references/MIRROR-BACKUP-DRILL.md) |
| Phantom-deletion detection (Axiom 24) | [PHANTOM-DELETIONS.md](references/PHANTOM-DELETIONS.md) |
| Submodule classification (rewind / dirty / fast-forward) | [SUBMODULE-HANDLING.md](references/SUBMODULE-HANDLING.md) |

### Operations
| Need | File |
|------|------|
| Safety model — every destructive action's reversibility chain | [SAFETY-MODEL.md](references/SAFETY-MODEL.md) |
| Beads + Agent Mail integration | [INTEGRATION.md](references/INTEGRATION.md) |
| Mining prior agent sessions via /cass | [CASS-MINING.md](references/CASS-MINING.md) |
| Glossary of skill-specific terms | [GLOSSARY.md](references/GLOSSARY.md) |

---

## Scripts

### Pipeline scripts
| Script | Phase | Purpose |
|--------|-------|---------|
| `scripts/check-skills.sh` | 0 | Detect helper skills + jsm state; write inventory JSON |
| `scripts/install-referenced-skills.sh` | 0 | Bulk-install missing skills via jsm |
| `scripts/git-doctor.sh` | 0 | Pre-flight repo health check (mid-rebase, bare, detached, submodules, LFS) |
| `scripts/check-disk-pressure.sh` | 0 | Halt batch run if /tmp >85% or any cache >5GB |
| `scripts/check-large-repo.sh` | 0 | Warn for T4/T5; suggest sub-tree partitioning |
| `scripts/snapshot-tree.sh` | 0 / 6 / 7 / 8 | Capture working-tree state for drift detection |
| `scripts/cass-mine.sh` | 0.5 | Mine prior agent sessions for context |
| `scripts/scope-decide.sh` | 0.5 | Emit `phase0_scope_decision.md` skeleton |
| `scripts/discover-project.sh` | 1 | Detect primary branch, archetype, build/test/lint commands, conventions, protected_globs |
| `scripts/branch-policy-detect.sh` | 1 | Per-repo branch policy (main only / main:master / master) |
| `scripts/verify-git-version.sh` | 1 | VERIFY-LIVE on git/lfs/etc; capture version into project_profile.json |
| `scripts/detect-phantom-deletions.sh` | 1.5 | Halt cleanup if >5 phantom deletions per Axiom 24 |
| `scripts/detect-submodule-issues.sh` | 1 | Classify submodule states; surface rewinds/dirty per SUBMODULE-HANDLING |
| `scripts/inventory-candidates.sh` | 2 | Walk working tree; emit candidates.tsv with smell tags |
| `scripts/classify-purpose.sh` | 2 / 4 | Heuristic purpose classifier |
| `scripts/generate-coverage-matrix.sh` | 2.5 | Skeleton for coverage_matrix.md (per smell rule × candidate) |
| `scripts/build-bundle.sh` | 3 | Create working-tree-copies + meta + index + reference graph |
| `scripts/verify-bundle.sh` | 3 | Byte-equality + sha256 hash verification (gate before destructive phases) |
| `scripts/bundle-audit.sh` | 3 / 9 | Deep audit beyond byte-equality |
| `scripts/recovery-test.sh` | 3 | Verify recovery recipes actually work on a sample candidate |
| `scripts/mirror-backup.sh` | harden-secret-leak Step 1 | Mirror clone before any history rewrite |
| `scripts/triage-batch.sh` | 4 | Worker — classify + reference-grep + verdict for one batch |
| `scripts/merge-triage.sh` | 5 | Merge batch tsvs; build user-facing decision table |
| `scripts/apply-move.sh` | 6 | `git mv` + reference rewrites + gates + commit (one move) |
| `scripts/apply-delete.sh` | 7 | `git rm` per glob batch + gates + commit |
| `scripts/update-gitignore.sh` | 8 | `.gitignore` updates with shadowing audit + verbatim-auth check |
| `scripts/verify-references.sh` | 6 / 9 | Grep the repo for any reference to a now-moved or deleted path |
| `scripts/run-validators.sh` | 9 / 10 | Run all skill-internal validators (per POLISH-BAR-VERIFICATION-QUERIES.md) |
| `scripts/handoff-report.sh` | 10 | Emit final report |
| `scripts/polish-bar-check.sh` | 10 | Verify run satisfied all 18 Polish Bar dimensions |
| `scripts/phase-status.sh` | * | Inspect workspace and report which phases have completed + suggested next step (useful for resumption / debugging) |
| `scripts/archive-workspace.sh` | 10+ | Archive workspace as tarball at end-of-run |
| `scripts/project-root.sh` | * | Resolve repo root (uses `git rev-parse --show-toplevel`) |
| `scripts/extract-kernel.sh` | * | Extract marker-bounded kernel for embedding in subagent prompts |

Scripts are resume-aware, log to the workspace, and exit non-zero on any irreversible failure (the run halts; the user investigates). Recovery-bundle creation is fail-closed: a non-empty bundle is reused only after verification, or a fresh `BUNDLE_OVERRIDE` path is chosen.

---

## Subagents

### Pipeline subagents
| Subagent | Phase | Purpose |
|----------|-------|---------|
| `subagents/mode-router.md` | 0 | Help user pick a mode via OPERATING-MODES.md decision tree |
| `subagents/scope-decider.md` | 0.5 | Draft `phase0_scope_decision.md` per SCOPE-DECISION.md |
| `subagents/cass-miner.md` | 0.5 | Mine prior agent sessions for context (optional) |
| `subagents/project-profiler.md` | 1 | Project reconnaissance + archetype detection |
| `subagents/phantom-deletion-detector.md` | 1.5 | Halt cleanup if >5 phantom deletions (Axiom 24) |
| `subagents/submodule-classifier.md` | 1 | Classify submodule states; surface rewinds/dirty |
| `subagents/inventory-agent.md` | 2 | Smell-walk + reference-graph build |
| `subagents/coverage-mapper.md` | 2.5 | Build per-smell-rule coverage matrix |
| `subagents/leak-scanner.md` | 2.5 | Detect secrets per FILE-SMELLS § Secret leakage |
| `subagents/leak-handler.md` | INCIDENT | Walk user through secret-leak rotation + filter-repo flow |
| `subagents/bundle-builder.md` | 3 | Working-tree copies + meta + index + verify |
| `subagents/recovery-drill-runner.md` | 3 / 9 | Verify recovery recipes work on sample candidates |
| `subagents/audit-conductor.md` | 3 / 9 / 10 | Deep bundle audit at three checkpoints |
| `subagents/triage-worker.md` | 4 | Per-batch classify + reference-grep + verdict |
| `subagents/risk-scorer.md` | 4.5 | Score every verdict by exploitability × blast-radius × reversibility |
| `subagents/language-specialist.md` | 4 | Language-specific reference-rewrite planning (Comprehensive only) |
| `subagents/archaeologist.md` | 4 | Forensic intent reconstruction for ambiguous candidates |
| `subagents/triangulator.md` | 4 / 6 / 9 | Multi-model independent verification (Comprehensive only) |
| `subagents/multi-model-validator.md` | 4 / 9 | Wrapper for `/multi-model-triangulation` skill |
| `subagents/triage-merger.md` | 5 | Merge batches, present decision table, capture overrides |
| `subagents/move-applier.md` | 6 | `git mv` + reference rewrites + gates + commit per move |
| `subagents/reference-checker.md` | 6 / 9 | Verify no broken references after every move |
| `subagents/delete-applier.md` | 7 | `git rm` per glob batch + gates + commit |
| `subagents/gitignore-author.md` | 8 | `.gitignore` updates with shadowing audit + verbatim-auth |
| `subagents/commit-message-author.md` | 6 / 7 / 8 | Rewrite auto-generated commit messages with proper craft |
| `subagents/fresh-eyes.md` | 9 | Three review prompts × ≥2 rounds |
| `subagents/cleanup-conductor.md` | 7 / 8 | Gated destructive operations |
| `subagents/handoff-reporter.md` | 10 | Final report + beads issue + recovery recipes |
| `subagents/batch-orchestrator.md` | BATCH-MODE | Multi-repo cleanup orchestration |
| `subagents/idea-wizard-reviewer.md` | 11 | User-lens skill-feedback review (optional) |
| `subagents/incident-responder.md` | * | Mid-run incident triage (any phase) |

## Asset Templates

| Template | Used by |
|----------|---------|
| `assets/intake-prompt.md` | Phase 0 up-front confirmations |
| `assets/templates/commit-message-template.md` | commit-message-author (Phases 6/7/8) |
| `assets/templates/triage-decision-template.md` | merge-triage.sh (Phase 5) |
| `assets/templates/move-plan-template.md` | merge-triage.sh (Phase 5 — move plan) |
| `assets/templates/gitignore-diff-template.md` | gitignore-author (Phase 8) |
| `assets/templates/conflict-resolution-template.md` | move-applier (Phase 6 conflicts) |
| `assets/templates/handoff-report-template.md` | handoff-reporter (Phase 10) |

---

## Self-Test

Trigger phrases that should activate this skill:

- "Clean up my repo's tree — there's a bunch of junk committed"
- "I have random `.db` and `.json` files at the project root"
- "An agent left intermediate `.md` reports in the repo root — clean them up"
- "Tidy this repo — get the ad-hoc scripts out of the project root"
- "The repo junk cleaner pass on `<path>`"
- "Move the planning docs to `docs/` and delete the temp files"
- "Audit my repo for files that shouldn't be tracked"
- "What committed files are actually ephemeral artifacts?"
- "Help me figure out which root-level files belong elsewhere"
- "Sweep the repo for SQLite databases, `.wal` files, and other junk that should be `.gitignore`d"

Full trigger list + end-to-end smoke test on a dummy repo: [SELF-TEST.md](SELF-TEST.md).
