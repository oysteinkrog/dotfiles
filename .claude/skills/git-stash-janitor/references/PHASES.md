# Phases 1–11 Playbook

Detailed exit criteria, deliverables, and agent fan-out for each phase. The main agent is the orchestrator; subagents do work in parallel where independent.

---

## Mode Variants

The skill ships three run modes. Pick at Phase 0 (Up-Front Confirmations) based on stash count, time budget, and the presence of stash-references-deleted-files signals. Each mode keeps the same 11 phases but varies *depth* — fan-out width and review pass counts.

| Phase | Quick (5–9 stashes by default; <5 only after warning override) | Standard (10–80) | Comprehensive (80+) |
|-------|---------------------|------------------|---------------------|
| 1 Profile | Main agent reads AGENTS.md + README.md, 5 min | + codebase-report subagent, 10 min | + multi-model triangulation on architecture summary, 15 min |
| 2 Inventory | Main agent | Main agent | Main agent |
| 3 Bundle | Main agent | Main agent | Main agent + verify pass redundantly via two methods |
| 4 Triage | 1 worker, serial | 2–4 workers, ~20 stashes each | 5+ workers, archaeology subagent for novel-but-stale candidates |
| 5 Merge | Main agent | Main agent | Main agent + idea-wizard cross-check on borderline verdicts |
| 6 Apply | 1 applier | 1 applier (sequential by definition) | 1 applier; multi-model review of conflict resolutions |
| 7 Split | 1 splitter | 1 splitter | 1 splitter + dedicated archaeology |
| 8 Fresh-eyes | 1 round, 1 model | ≥2 rounds, 1 model | ≥3 rounds, 3 independent models, adjudicated |
| 9 Cleanup | Single gated authorization | Single gated authorization | Single plan-level authorization with commands grouped by bucket |
| 10 Handoff | Brief report | Standard report + beads issue | Full report + beads issue + bv triage of newly-unblocked work |
| 11 User-lens | Skipped | Skipped | Optional fresh agent reviews the run for skill-improvement notes |

Mode is recorded in `project_profile.json` at Phase 1. Phase gates (especially Phase 8 termination) adjust based on mode.

---

## Phase 0: Up-Front Confirmations (5 min, main agent)

Before any subagent fans out:

1. **Confirm inputs** with user: target path, mode, output mode, recovery branch name, bundle path. See SKILL.md § Up-Front Confirmations.
2. **Clone if URL** — clone to `/tmp/<basename>` and treat the cloned path as the source from then on.
3. **Refuse non-git paths** — `git -C <path> rev-parse --is-inside-work-tree` must return `true`.
4. **Refuse mid-rebase / mid-merge** — `git -C <path> status` shows `interactive rebase in progress` or unmerged paths → ask user to finish first.
5. **Initialize workspace**:
   ```bash
   mkdir -p <project>/.stash_janitor_workspace/{triage,conflicts}
   ```
   The scripts exclude `.stash_janitor_workspace/` explicitly when staging or auditing; do not auto-edit `.git/info/exclude` during setup.
6. **Snapshot working tree state** to `wt_phase0.txt`:
   ```bash
   scripts/snapshot-tree.sh <project> phase0
   ```
7. **Stash count up front**:
   ```bash
   git -C <project> stash list | wc -l
   ```
   Tell the user the count *before* asking them to commit time. The asupersync user thought `*127` meant 127 commits.

**Exit criteria:** User confirmed inputs; workspace exists; working-tree state captured.

---

## Phase 1: Project Reconnaissance (5–15 min, single subagent)

Spawn the project-profiler subagent (see `subagents/project-profiler.md`). Its prompt is the **Brennerian opener**:

> "First read ALL of the AGENTS.md file (or AGENT.md, CLAUDE.md, .cursor/rules/*, .github/copilot-instructions.md — whatever the project uses) and the README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code and technical architecture and purpose of the project."

The subagent then detects:

- **Primary branch** — `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null` first, then `git config init.defaultBranch`, then a heuristic against the actual ref list (look for `main`, `master`, `develop`, `trunk`, `default` in that priority order).
- **Branching model** — trunk-based (only the primary branch and ephemeral feature branches), GitFlow (long-running `develop`), release-branches, etc.
- **Commit-message conventions** — Conventional Commits (`feat:`, `fix:`), ticket-id prefixes (`BACK-1234:`), gitmoji, free-form. Sample 50 recent commits.
- **The phrase the project uses for "ready to land"** — "PR", "MR", "patch series".
- **Test command** — `cargo test`, `bun test`, `pnpm test`, `pytest`, `go test ./...`, etc. Parsed from CI workflows + `package.json` scripts + `Makefile`.
- **Type-check command** — `cargo check`, `bun tsc --noEmit`, `mypy .`, `tsc --noEmit`, `go vet ./...`.
- **Lint command** — `cargo clippy`, `eslint`, `ruff`, `golangci-lint`.
- **Formatter** — `cargo fmt`, `prettier`, `ruff format`, `gofmt`.
- **CI gates** — UBS (presence of `.ubsignore`), dcg (presence of `dcg` in PATH or settings), pre-commit / husky / lefthook.
- **Stash message conventions actually used** — sample the existing stashes for prefix patterns. (The asupersync repo had `wip-<ticket>`, `<ticket>-wip-<feature>`, `autostash`, `pre-deadlock-fix`, `temp-pre-push`, `other-agent-broken`, `full-tree-reset-stash`.)

All of this is written to `project_profile.json`.

**Exit criteria:** `project_profile.json` exists with a non-empty `primary_branch`, and with `test_command`, `typecheck_command`, `lint_command`, and `format_command` keys present. Empty gate-command strings mean no command was detected and should be summarized to the user for correction.

---

## Phase 2: Stash Inventory (5 min, single subagent)

Spawn the inventory-agent subagent. It runs:

```bash
git -C <project> stash list \
  --format='%gd|%H|%P|%ci|%an|%s' > .stash_janitor_workspace/inventory.raw
```

For each stash:

```bash
git -C <project> stash show --stat "stash@{N}" >> .stash_janitor_workspace/inventory.shortstats
git -C <project> stash show -p --binary "stash@{N}" | wc -l >> .stash_janitor_workspace/inventory.diff_lines
git -C <project> log -1 --format='%P' "stash@{N}^3" 2>/dev/null  # detect untracked-files commit
```

The agent then writes `inventory.tsv` with one row per stash:

```
n  ref          sha           parent_sha    date                 author              message              files  insertions  deletions  has_untracked
0  stash@{0}    abc123...     def456...     2026-04-29T10:14:22  agent-cc-12         wip-BACK-1234        4      120         3          false
1  stash@{1}    ...
```

It also produces `inventory_grouped.md` — a markdown table grouping stashes by message-prefix family (extracted by regex over the message field):

```markdown
## Stash families (grouped by message prefix)

### `wip-BACK-*` (47 stashes)
- stash@{0}: wip-BACK-1234 (2026-04-29)
- stash@{3}: wip-BACK-1234-followup (2026-04-29)
- ...

### `autostash` (12 stashes)
- ...

### `other-agent-broken` (8 stashes — likely garbage)
- ...
```

**Exit criteria:** `inventory.tsv` has one row per stash; `inventory_grouped.md` enumerates every family; main agent posts a one-paragraph summary ("found 127 stashes across 7 families: 47 wip-BACK-*, 12 autostash, 8 other-agent-broken, ...") and asks for any patterns the user already knows about.

---

## Phase 3: Recovery Bundle (10–30 min, single subagent — gate)

This phase MUST complete with byte-equality verified before any classification logic runs. If the bundle is wrong, the entire run is unsafe.

Spawn the bundle-builder subagent. Steps:

1. **Create the bundle directory** outside the repo:
   ```bash
   BUNDLE="<project-parent>/<basename>-stash-archive-$(date -u +%Y-%m-%d)"
   mkdir -p "$BUNDLE"/{diffs,meta,stashed-untracked}
   echo "$BUNDLE" > .stash_janitor_workspace/bundle_path.txt
   ```

2. **For every stash**, write four artifacts from the stable `sha` captured in `inventory.tsv`:
   ```bash
   n=0
   N=$(printf '%03d' "$n")  # zero-padded; matches inventory ordering
   sha="$sha_from_inventory_tsv"
   git update-ref refs/stash-backup/$N "$sha"
   git stash show -p --binary "$sha" > "$BUNDLE/diffs/$N.diff"
   git log -1 --format='%H%n%P%n%ci%n%an%n%s' "$sha" > "$BUNDLE/meta/$N.txt"
   # If the stash had untracked files (third parent), materialize them:
   if git rev-parse "${sha}^3" >/dev/null 2>&1; then
     git -C <project> archive --format=tar "${sha}^3" | \
       tar -x -C "$BUNDLE/stashed-untracked/$N/"
   fi
   ```

3. **Write `index.tsv`** — one row per stash with: n, sha, parent_sha, date, message, shortstat. Columns match `inventory.tsv` plus a `bundle_artifacts` column listing `diffs/$N.diff,meta/$N.txt,refs/stash-backup/$N`.

4. **Write `README.md`** at the bundle root explaining:
   - What every file contains
   - How to recover from each: `git cherry-pick -m 1 refs/stash-backup/$N` (selects HEAD-at-stash as the merge mainline; stash backup refs ARE merge commits) or `git apply <bundle>/diffs/$N.diff`
   - **The `git format-patch` footgun** — explicitly document that `git format-patch -1 stash@{N}` is not the stash recovery diff and must NOT be used as a recovery source; the tracked/index diffs in this bundle came from `git stash show -p --binary <inventory-sha>`, while untracked files came from `<inventory-sha>^3`.

5. **Verify byte-equality** via `scripts/verify-bundle.sh`. For every stash:
   ```bash
   inventory_sha="$sha_from_index_tsv"
   backup_sha=$(git rev-parse refs/stash-backup/$N)
   [[ "$inventory_sha" == "$backup_sha" ]] || die "MISMATCH: stash $N"

   # Also verify the diff round-trips:
   live_diff=$(git stash show -p --binary "$inventory_sha" | sha256sum | awk '{print $1}')
   bundle_diff=$(sha256sum $BUNDLE/diffs/$N.diff | awk '{print $1}')
   [[ "$live_diff" == "$bundle_diff" ]] || die "DIFF MISMATCH: stash $N"
   ```
   Write all results to `bundle_verification.log`. Any mismatch halts the run.

**Exit criteria:** Every stash has a backup ref AND a diff AND a meta file; byte-equality verified for every entry; `bundle_verification.log` has zero `MISMATCH` lines; main agent posts the bundle path to the user and asks them to keep it safe.

---

## Phase 4: Triage Fan-Out (parallel, 20–60 min)

Partition `inventory.tsv` into batches of ~20 stashes each. Spawn one triage-worker subagent per batch.

**Each worker, for every stash in its batch:**

1. Read `<bundle>/diffs/$N.diff`.
2. **FINGERPRINT** — extract the introduced symbols:
   - Function/method names: `^\+.*\bfn (\w+)|^\+.*\bdef (\w+)|^\+.*\bfunction (\w+)|^\+.*\b(\w+) :=|^\+.*\bconst (\w+)`
   - Type names: `^\+.*\bstruct (\w+)|^\+.*\bclass (\w+)|^\+.*\benum (\w+)|^\+.*\binterface (\w+)|^\+.*\btype (\w+)`
   - Test names: `^\+.*\b#\[test\]|^\+.*\bit\(['"]([^'"]+)|^\+.*\btest\(['"]([^'"]+)`
   - Fixture strings: literal strings ≥10 chars in `+` lines
   - File paths: every `diff --git a/X b/X` line
3. **VERIFY-ON-MAIN** — for each fingerprint:
   - `git -C <project> grep -F <symbol> <primary-branch> -- <expected-file-path>` (path-scoped grep is faster and more accurate)
   - Fall back to `git -C <project> grep -F <symbol> <primary-branch>` (whole-repo) if path is gone
   - If file no longer exists on primary: tag as `file-missing` (likely `novel-but-stale` or `garbage`)
4. **APPLY-CHECK PROBE** — `git apply --3way --check <bundle>/diffs/$N.diff` (no actual apply); record exit code.
5. **VERDICT** — by rubric:
   - `superseded` — every fingerprint resolves on primary with same semantics
   - `garbage` — message matches a known-garbage prefix (`other-agent-broken`, `temp-pre-push`, `full-tree-reset-stash`, `autostash` and reflog has the rebase that produced it) AND the fingerprint adds no novel surface
   - `novel-and-accretive` — fingerprint doesn't appear on primary AND apply-check is clean AND the diff looks like a focused, defensive, or test-only addition
   - `novel-but-stale` — fingerprint doesn't appear on primary BUT files referenced no longer exist (or the surrounding context has drifted so far that 3-way apply fails)
   - `partially-novel` — some hunks superseded, some not (apply-check finds rejects only on the superseded hunks)
6. **Write a row** to `.stash_janitor_workspace/triage/batch_<NNN>.tsv`:
   ```
   n  verdict           confidence  evidence_on_main           apply_check  fingerprint_summary
   0  superseded        0.95        src/mutex.rs:317           clean        lock_until field, recover_lock fn
   1  garbage           0.99        n/a                        clean        message=other-agent-broken
   34 novel-and-accretive   0.90    none                       clean        defensive_ok_packet_length_cap fn (mysql)
   ```

**See `references/TRIAGE-RUBRIC.md` for the full classification rubric.**

**Coordination:** Workers reserve their batch tsv via Agent Mail (`thread_id=stash-janitor-<run-id>`, `reason="triage-batch-NNN"`). They write only to their own batch tsv; the merger (Phase 5) reads all of them.

**Exit criteria:** Every stash has exactly one row across all `batch_*.tsv` files; no row has empty `verdict` or `confidence`; main agent merges into `triage.tsv` and posts batch-level summary counts.

---

## Phase 5: Triage Merge & Confirm (USER GATE)

Spawn the triage-merger subagent. It:

1. Reads all `batch_*.tsv` and writes the unified `triage.tsv`.
2. Builds `triage_decision.md` — a markdown table for the user, sorted by verdict and confidence:

   ```markdown
   ## Triage decision (127 stashes, sorted by verdict)

   ### KEEP — novel-and-accretive (1)
   | n  | message              | files | evidence | proposed action |
   |----|----------------------|-------|----------|-----------------|
   | 34 | wip-BACK-1742-mysql  | 1     | none on main | apply --3way (1 hunk) |

   ### KEEP-WITH-SPLIT — partially-novel (3)
   | n  | message | hunks novel / total | proposed action |
   ...

   ### DROP — superseded (89)
   <details><summary>Click to expand 89 entries</summary>

   | n  | message | superseded by |
   ...
   </details>

   ### DROP — garbage (28)
   ...

   ### MANUAL — novel-but-stale (6)
   | n  | message | reason | proposed action |
   ...
   ```

3. **Presents the table to the user verbatim** and waits for explicit go-ahead.
4. Captures any user overrides — "actually keep stash@{47} too, that pre-dates the refactor I'm about to redo" — into `user_overrides.tsv`. Apply overrides to `triage.tsv` (the merged file is the source of truth from now on).
5. Re-asks confirmation if overrides change >5 verdicts (sanity check).

**No destructive actions yet.** This phase produces zero commits, zero drops.

**Exit criteria:** User explicitly typed "go" / "proceed" / "approved" (or a phrase that includes one of those words); `triage.tsv` has the user-confirmed verdicts; main agent shows the user the next-step plan ("I'll now apply the 1 keeper and 3 partials, then run the test suite, then come back for cleanup authorization").

---

## Phase 6: Apply Keep Candidates (sequential, 30–90 min)

Each apply changes the 3-way base for later applies, so this is sequential by definition.

The keeper-applier subagent:

1. **Create or resume the recovery branch** off the primary without resetting an existing branch:
   ```bash
   rb=stash-recovery-$(date -u +%Y-%m-%d)
   if git show-ref --verify --quiet "refs/heads/$rb"; then
     git checkout "$rb"   # resume; do not reset existing work
   else
     git checkout -b "$rb" origin/<primary-branch>
   fi
   ```
2. For each `novel-and-accretive` stash in `triage.tsv`, in chronological order (earliest stash first, so dependencies between stashes are honored if any exist):
   1. **WORKING-TREE-DRIFT check** — `git status` now; capture in `apply_log.tsv`. If any unexpected files appeared from concurrent agents, treat them as committed-by-you per AGENTS.md.
   2. **Re-fingerprint** — re-run VERIFY-ON-MAIN against the recovery branch (which has accumulated previous keepers). If now superseded, mark `superseded-during-apply` in the log and skip.
   3. **`git apply --3way --check <bundle>/diffs/$N.diff`** — exit 0 only.
   4. If clean: `git apply --3way <bundle>/diffs/$N.diff`. If untracked files were in the stash (`stashed-untracked/$N/`), copy them in.
   5. **Run quality gates** from `project_profile.json`:
      - test command (e.g., `cargo test`)
      - typecheck command (e.g., `bun tsc --noEmit`)
      - lint command (e.g., `cargo clippy -- -D warnings`)
      - UBS if available (`ubs <changed-files>`)
      - All must exit 0 OR the user has explicitly OK'd a known pre-existing failure.
   6. `git add -A -- <touched paths>` (only the changed files; not the workspace).
   7. **Commit** with a focused message that explains *why* this hunk is being recovered:
      ```
      recover defensive MySQL OK-packet length-cap from stashed WIP

      Originally drafted in stash@{34} (sha abc123, dated 2026-04-29).
      The fail-closed guard limits OK-packet length to MAX_PAYLOAD before
      the consumer reads it; without the cap, a malformed packet from an
      upstream proxy could trigger a panic in the framing parser. The
      polished version of this stash never landed because the agent that
      authored it crashed before pushing.

      Recovered via: git apply --3way <bundle>/diffs/034.diff
      ```
      The skill never adds `Co-Authored-By` lines unless the user asks.
   8. Append to `apply_log.tsv`:
      ```
      n  ref          new_commit_sha  files_changed  gates_status  duration_s
      34 stash@{34}   def987...       1              passed         42
      ```
3. If apply-check fails on a stash:
   1. **DO NOT** force the apply.
   2. Surface to the user with full context:
      - The stash's diff
      - The current state of the affected files on the recovery branch
      - A hypothesis for why they conflict (often a refactor — `if/else if` → `match`, function rename, file move)
      - A proposed manual resolution (the Edit tool would do *this*)
   3. Wait for user OK. If the user says "skip", mark the row `conflict-skipped`. If the user says "fix it like that", apply the resolution via the Edit tool, then continue from step 5 (run gates).
   4. Write the conflict context to `.stash_janitor_workspace/conflicts/stash_$N.context.md` so it survives compaction.

**Exit criteria:** Every `novel-and-accretive` row in `triage.tsv` has either a `new_commit_sha` or a `conflict-skipped` / `superseded-during-apply` mark in `apply_log.tsv`; quality gates passed on the recovery branch's tip.

---

## Phase 7: Partial-Novel Split-Apply (20–45 min, single subagent)

The most error-prone phase. Gets its own subagent so it doesn't compete with Phase 6's working tree.

The partial-splitter subagent, for each `partially-novel` row:

1. Open `<bundle>/diffs/$N.diff` for inspection.
2. Identify which hunks are novel (the triage rubric's per-hunk evidence column).
3. **Create a split copy** of the diff (`<bundle>/diffs/$N.split.diff`) to remove the superseded hunks. Use the Edit tool for any semantic/manual split. `scripts/partial-split.sh` is allowed only for exact hunk-number filtering after Phase 5 evidence names the hunks to keep; never use ad hoc sed/awk/regex transformations.
4. `git apply --3way --check <bundle>/diffs/$N.split.diff` — must be clean.
5. Apply, run quality gates, commit with a message that explicitly notes "split-apply: novel hunks only; superseded hunks dropped per triage row":
   ```
   recover novel `tests/parser_fuzz_corpus.rs` additions from partial stash

   Originally stash@{47} mixed a parser refactor (already landed via PR #234)
   with new fuzz corpus entries. This commit recovers only the corpus entries;
   the refactor portion was dropped as superseded.

   Hunks recovered: 3 of 8 (see <bundle>/diffs/047.split.diff).
   ```
6. Append to `partial_split_log.tsv` with hunks-kept / hunks-dropped counts.

**Exit criteria:** Every `partially-novel` row resolved (applied, conflict-skipped, or marked `partial-skipped`).

---

## Phase 8: Fresh-Eyes Verification (≥2 rounds, 30–60 min)

Spawn the fresh-eyes subagent. It runs three review prompts (verbatim from the documentation-website skill — they're calibrated):

1. *"Carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover."*
2. *"Sort of randomly explore the code files in this project, choosing code files to deeply investigate and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes."*
3. *"Turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep."*

Between rounds, the main agent runs:

```bash
# Project-specific (read from project_profile.json):
cargo test               # or bun test, pytest, go test ./...
cargo check              # or bun tsc --noEmit, mypy ., go vet ./...
cargo clippy -- -D warnings  # or eslint, ruff, golangci-lint
ubs .                    # if available
```

All must exit 0. Log each round + outcome to `fresh_eyes_log.md`.

**Termination rule:** Two consecutive full rounds (all three prompts) produce only trivial findings (typo, wording polish) AND test + typecheck + lint + UBS all green.

**Exit criteria:** Fresh-eyes log shows ≥2 clean rounds; gates green on `HEAD`.

---

## Phase 9: Destructive Cleanup (GATED)

Only after Phase 8 comes up clean ≥2 times AND the user has explicitly typed an authorization phrase that includes the literal commands to be run (per AGENTS.md "Mandatory explicit plan" rule).

The cleanup-conductor subagent:

1. **Build the verbatim authorization request**:
   ```
   I'm about to run the following destructive commands in this order:

     git stash drop stash@{126}
     git stash drop stash@{125}
     ... (87 garbage drops, in descending index order)
     git stash drop stash@{N}    # last garbage
     git stash drop stash@{M}    # first superseded (descending)
     ...
     (89 superseded drops)
     ...
     (6 novel-but-stale drops)
     ...
     (1 applied-keeper drop — stash@{34})

   Backup refs at refs/stash-backup/* and the bundle at <bundle> stay intact.

   To proceed, paste this verbatim:
     yes I understand and want to drop all 124 stashes per the plan above
   ```
2. **Wait for that exact authorization text** from the user. If they type anything different, refuse and re-ask.
3. **Record** the user's authorization text + timestamp in `cleanup_authorization.txt`.
4. **Drop in order**: garbage → superseded / superseded-by-newer-stash → novel-but-stale → applied-keeper. Within each bucket, **highest index first** (because indexes shift down after each drop).
5. **Before each drop**, restate the verbatim command:
   ```
   About to run: git stash drop stash@{126}
   (This is row n=126 in inventory.tsv: "other-agent-broken", verdict garbage)
   ```
6. After each drop, append to `cleanup_log.tsv`:
   ```
   n   pre_drop_index  ref_dropped     verdict   timestamp_utc
   126 stash@{126}     refs/stash-backup/126     garbage   2026-05-06T17:42:11Z
   ...
   ```
7. **Never** run `git stash clear`. **Never** delete the bundle. **Never** delete `refs/stash-backup/*`.

**Exit criteria:** `git stash list` matches the expected count (typically 0); every dropped stash's backup ref is still intact; `cleanup_log.tsv` is one row per drop.

---

## Phase 10: Handoff & Follow-Ups (5–15 min)

The handoff-reporter subagent emits `handoff_report.md` with:

```markdown
# Stash Janitor — Handoff Report

**Project:** /data/projects/asupersync
**Run date:** 2026-05-06
**Mode:** Comprehensive
**Recovery branch:** stash-recovery-2026-05-06
**Bundle path:** /data/projects/asupersync-stash-archive-2026-05-06/

## Counts
- Initial stashes: 127
- Triaged: 127
  - novel-and-accretive: 1 (applied)
  - partially-novel: 0
  - superseded: 89 (dropped)
  - garbage: 28 (dropped)
  - novel-but-stale: 6 (dropped, per user)
  - conflict-skipped: 0
  - applied-keeper: 1 (dropped after apply)
- Final stashes: 0
- Recovery commits authored: 1 on `stash-recovery-2026-05-06`

## Recovered commits
| sha       | from stash    | message                                                |
|-----------|---------------|--------------------------------------------------------|
| def987... | stash@{34}    | recover defensive MySQL OK-packet length-cap from WIP  |

## Recovery recipes
If you regret any drop, every stash is recoverable:

  # By backup ref (preferred)
  git cherry-pick -m 1 refs/stash-backup/034

  # By bundle diff (when ref already pruned)
  git apply --3way /data/projects/asupersync-stash-archive-2026-05-06/diffs/034.diff
  # If index.tsv says has_untracked=true, also copy stashed-untracked/034/.

  # The bundle's index is at:
  cat /data/projects/asupersync-stash-archive-2026-05-06/index.tsv

## Push instructions
The skill never pushes. To land the recovered work:

  git push origin stash-recovery-2026-05-06
  # Then open a PR against <primary-branch> for review

## Bundle lifecycle
The bundle lives at /data/projects/asupersync-stash-archive-2026-05-06/.
Keep it for at least one release cycle. Once you're sure nothing was
accidentally lost, move it to your normal archive/trash location with `mv`.
The skill never advises bypassing DCG or deleting the bundle itself.
```

The subagent also:

- Files a **beads issue** summarizing the run (`br create --title "stash janitor pass on <project> (<N> stashes)" --type=task --priority=4`); the issue body links to the report, the bundle, and the recovery branch.
- Updates the Agent Mail thread (`thread_id=<beads-id>`) with a final reply: "[<beads-id>] Stash janitor run complete; see handoff_report.md".
- If `bv` is available, runs `bv --robot-triage` to surface any new follow-up items the recovered commits unblock.
- Reminds the user to push.

**Exit criteria:** `handoff_report.md` exists with all sections filled; beads issue filed; user told the push command.

---

## Phase 11: User-Lens Review (OPTIONAL, off by default)

Only runs if the user explicitly asks ("review the run from a user perspective"). A fresh agent or `/idea-wizard` reviews the entire run from the perspective:

> "Did this stash janitor save the user time? Where did it surface friction? What would have made it better?"

Files improvement notes to `.stash_janitor_workspace/skill_feedback.md` and (optionally) opens beads issues against this skill itself.

This phase is for skill maintainers, not for the end user's stash cleanup.

---

## Idempotence & Resumability

**Idempotent on a clean repo.** If you run the skill on a repo with zero stashes and a clean `triage.tsv`, Phases 1, 2, 3 still produce their artifacts (project profile, empty inventory, empty bundle). Phases 4+ short-circuit with "nothing to do." No commits, no drops.

**Resumable mid-run.** Every phase writes its artifacts before exiting. On re-entry:

- Phase 1 — re-uses `project_profile.json` if present and ≤7 days old.
- Phase 2 — re-runs from scratch (cheap; produces fresh `inventory.tsv`).
- Phase 3 — checks if the bundle directory exists and verifies byte-equality; if yes, skips re-creation.
- Phase 4 — re-runs only the batches without a `batch_NNN.tsv`.
- Phase 5 — re-presents the merged table; user can re-confirm or override.
- Phase 6 — reads `apply_log.tsv` and skips already-applied stashes (matched by `n`).
- Phase 7 — analogous via `partial_split_log.tsv`.
- Phase 8 — always re-runs (verification cost is cheap relative to risk).
- Phase 9 — refuses to re-run; if `cleanup_log.tsv` exists, it's done; the user must explicitly archive the workspace and start fresh.
- Phase 10 — re-emits `handoff_report.md` from the latest log files.
