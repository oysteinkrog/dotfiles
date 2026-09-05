# Agent Prompts — Verbatim Templates

Each subagent invocation uses one of these prompts verbatim. Substitute `{PROJECT}`, `{PRIMARY_BRANCH}`, `{WORKSPACE}`, `{BUNDLE}`, `{N}` with concrete values.

---

## Phase 1 — Project Profiler

> First read ALL of the AGENTS.md file (or AGENT.md, CLAUDE.md, .cursor/rules/*, .github/copilot-instructions.md — whatever the project uses) and the README.md file super carefully and understand ALL of both! Then use your code investigation agent mode to fully understand the code and technical architecture and purpose of the project at `{PROJECT}`.
>
> Detect and write to `{WORKSPACE}/project_profile.json`:
>
> - **primary_branch** — try `git symbolic-ref refs/remotes/origin/HEAD` first, then `git config init.defaultBranch`, then look for `main`/`master`/`develop`/`trunk`/`default` in `git branch -a`. Never assume `main`.
> - **branching_model** — `trunk-based` | `gitflow` | `release-branches` | `unknown`
> - **commit_message_convention** — `conventional` (`feat:`, `fix:` etc.) | `ticket-id` (`BACK-1234:` etc.) | `gitmoji` | `freeform`. Sample the last 50 commits.
> - **ready_to_land_phrase** — "PR" / "MR" / "patch series"
> - **test_command** — full command, e.g. `cargo test --workspace`. Inspect `package.json`/`Cargo.toml`/`Makefile`/CI workflows.
> - **typecheck_command** — e.g. `bun tsc --noEmit` / `cargo check` / `mypy .`
> - **lint_command** — e.g. `cargo clippy -- -D warnings`
> - **format_command** — e.g. `cargo fmt --check`
> - **ubs_available** — bool (does the project use UBS?)
> - **dcg_available** — bool (is dcg active in this environment?)
> - **pre_commit_hooks** — list of detected hook configs (husky, lefthook, pre-commit)
> - **stash_message_conventions** — sample existing stash messages, extract prefix patterns; report as a list of `(prefix_regex, count)` pairs.
> - **architecture_summary** — 200-word prose summary of what the project does and how it's structured.
>
> Output ONLY the path to `project_profile.json` and a one-paragraph human summary. No other side effects.

---

## Phase 2 — Inventory Agent

> Inventory every git stash in `{PROJECT}` and write `{WORKSPACE}/inventory.tsv` and `{WORKSPACE}/inventory_grouped.md`.
>
> Steps:
>
> 1. `git -C {PROJECT} stash list --format='%gd|%H|%P|%ci|%an|%s'` — capture all stashes.
> 2. For each stash: `git stash show --stat stash@{N}` for shortstat; record `files`, `insertions`, `deletions`.
> 3. For each stash: detect untracked files via `git rev-parse stash@{N}^3 2>/dev/null`. Set `has_untracked=true|false`.
> 4. Write `inventory.tsv` with columns: `n`, `ref`, `sha`, `parent_sha`, `date`, `author`, `message`, `files`, `insertions`, `deletions`, `has_untracked`.
> 5. Group by message-prefix family. Use `project_profile.json:stash_message_conventions` if populated; otherwise extract by regex (e.g., `^(wip-[\w-]+)`, `^(autostash)`, `^(other-agent-broken)`).
> 6. Write `inventory_grouped.md` — markdown tables per family, ordered by family size desc.
>
> Output: counts per family + path to the two files.

---

## Phase 3 — Bundle Builder

> Build the recovery bundle at `{BUNDLE}` (default `<project-parent>/<basename>-stash-archive-<YYYY-MM-DD>/`). The bundle MUST be byte-equality verified before this phase exits — any mismatch halts the run.
>
> Steps:
>
> 1. `mkdir -p {BUNDLE}/{diffs,meta,stashed-untracked}` and write the absolute path to `{WORKSPACE}/bundle_path.txt`.
> 2. For each stash row in `inventory.tsv` (use the zero-padded `n` and the row's `sha` column):
>    - `git update-ref refs/stash-backup/{n} {sha}` (creates the gold-standard recovery ref pinned to the inventory identity).
>    - `git stash show -p --binary {sha} > {BUNDLE}/diffs/{n}.diff`. **Use `git stash show -p --binary`, NOT `git format-patch`** — `git format-patch -1 stash@{n}` is not the stash recovery diff and can be empty or wrong for merge stash commits, and plain `-p` omits tracked binary payloads.
>    - `git log -1 --format='%H%n%P%n%ci%n%an%n%s' {sha} > {BUNDLE}/meta/{n}.txt`.
>    - If `git rev-parse {sha}^3 >/dev/null 2>&1` succeeds, `git archive --format=tar {sha}^3 | tar -x -C {BUNDLE}/stashed-untracked/{n}/`.
> 3. Write `{BUNDLE}/index.tsv` mirroring `inventory.tsv` with an extra `bundle_artifacts` column.
> 4. Write `{BUNDLE}/README.md` with: what each file contains, how to recover (cherry-pick / apply), the `git format-patch` footgun warning, and the exhaustive list of "if you regret X, run Y" recipes.
> 5. Verify byte-equality (script: `verify-bundle.sh`):
>    - For every n: the `index.tsv` sha == `git rev-parse refs/stash-backup/{n}`.
>    - For every n: `git stash show -p --binary {sha} | sha256sum | awk '{print $1}'` == `sha256sum {BUNDLE}/diffs/{n}.diff | awk '{print $1}'`.
>    - Write all results to `{WORKSPACE}/bundle_verification.log`. ANY mismatch must halt the run with a clear error to the user.
>
> Output: bundle path + verification status + count of artifacts.

---

## Phase 4 — Triage Worker (parallel)

> You are triage worker `{WORKER_ID}`, responsible for stashes `{N_START}..{N_END}` in `{WORKSPACE}/inventory.tsv`. Read `{WORKSPACE}/project_profile.json` for the primary branch and `{BUNDLE}` path.
>
> For each stash `n` in your range:
>
> 1. **FINGERPRINT.** Read `{BUNDLE}/diffs/{n}.diff`. Extract introduced symbols:
>    - Function/method names (added in `+` lines): patterns per `references/TRIAGE-RUBRIC.md`
>    - Type names, test names, fixture string literals (≥10 chars)
>    - File paths (every `diff --git a/X b/X`)
> 2. **VERIFY-ON-MAIN.** For each fingerprint:
>    - `git -C {PROJECT} grep -F '{symbol}' {PRIMARY_BRANCH} -- {expected_path}` (path-scoped first, faster + more accurate).
>    - Fall back to whole-repo grep if path is gone.
>    - If the file no longer exists on `{PRIMARY_BRANCH}`: tag `file-missing`.
> 3. **APPLY-CHECK PROBE.** `git apply --3way --check {BUNDLE}/diffs/{n}.diff`. Record exit code only — do NOT actually apply.
> 4. **VERDICT.** Per `references/TRIAGE-RUBRIC.md`:
>    - `superseded` — every fingerprint resolves on primary with same semantics.
>    - `garbage` — message matches a known-garbage prefix AND fingerprint adds no novel surface.
>    - `novel-and-accretive` — fingerprint absent on primary AND apply-check clean AND diff is focused/defensive.
>    - `novel-but-stale` — fingerprint absent on primary BUT files referenced no longer exist OR apply-check fails on every hunk.
>    - `partially-novel` — apply-check finds rejects only on the superseded hunks; novel hunks would still apply.
>
> 5. Append a row to `{WORKSPACE}/triage/batch_{WORKER_ID}.tsv` with columns: `n`, `verdict`, `confidence` (0.0–1.0), `evidence_on_main` (e.g., `src/mutex.rs:317` or `none`), `apply_check` (`clean`/`reject`/`fail`), `fingerprint_summary` (≤120 chars).
>
> Reserve your batch tsv via Agent Mail before writing (`thread_id=stash-janitor-{RUN_ID}`, `reason="triage-batch-{WORKER_ID}"`). Release on exit.
>
> Do NOT modify the working tree. Do NOT modify any other batch's tsv.
>
> Output: count per verdict + path to your batch tsv.

---

## Phase 5 — Triage Merger

> Merge all `{WORKSPACE}/triage/batch_*.tsv` into `{WORKSPACE}/triage.tsv`. Build `{WORKSPACE}/triage_decision.md` for the user — a markdown table sorted by verdict (KEEP, KEEP-WITH-SPLIT, MANUAL, DROP-superseded, DROP-superseded-by-newer-stash, DROP-garbage, DROP-novel-but-stale), with `<details>` blocks for the long DROP tail.
>
> Present the table to the user and wait for explicit go-ahead. Capture any per-stash overrides into `{WORKSPACE}/user_overrides.tsv` and apply them to `triage.tsv` (the merged file is the source of truth).
>
> If overrides change >5 verdicts, re-ask confirmation as a sanity check.
>
> NO destructive actions in this phase. NO commits. NO drops.
>
> Output: the markdown table to the user; the path to `triage.tsv`; the count of overrides applied.

---

## Phase 6 — Keeper Applier (sequential)

> You are the keeper-applier. Read `{WORKSPACE}/triage.tsv` and apply every `novel-and-accretive` row in chronological order (earliest stash date first).
>
> Sequence per stash:
>
> 1. **Setup once at start of phase**: create the recovery branch only if it does not exist. If it already exists, resume it; never reset it with `checkout -B`.
> 2. **WORKING-TREE-DRIFT check** — `git status --porcelain=v2`. If files appeared from concurrent agents, treat as if you committed them per AGENTS.md. Capture the snapshot in `apply_log.tsv:pre_apply_drift`.
> 3. **Re-fingerprint** — re-run VERIFY-ON-MAIN against the recovery branch's HEAD (which has accumulated previous keepers). If the symbols now resolve, mark `superseded-during-apply` and skip.
> 4. `git apply --3way --check {BUNDLE}/diffs/{n}.diff` — exit 0 only.
> 5. If clean: `git apply --3way {BUNDLE}/diffs/{n}.diff`. If `{BUNDLE}/stashed-untracked/{n}/` is non-empty, copy contents into the working tree.
> 6. **Run quality gates** from `project_profile.json`: test, typecheck, lint, UBS. All must exit 0.
> 7. Stage only the paths touched by `{BUNDLE}/diffs/{n}.diff` plus any files copied from `stashed-untracked/{n}/`; never run repository-wide `git add -A`.
> 8. Commit with a focused message that explains the *why*. Template:
>    ```
>    recover {one-line summary} from stashed WIP
>
>    Originally drafted in stash@{n} (sha {sha}, dated {date}).
>    {2–4 sentence explanation of the change's motivation, drawn from the
>    triage evidence and a re-read of the diff.}
>
>    Recovered via: git apply --3way <bundle>/diffs/{n}.diff
>    ```
>    Do NOT add `Co-Authored-By` lines unless the user asks.
> 9. Append `n`, `ref`, `new_commit_sha`, `files_changed`, `gates_status`, `duration_s` to `apply_log.tsv`.
>
> If apply-check fails:
>
> - Do NOT force the apply.
> - Surface to the user with: the stash's diff, the affected files' current state, a hypothesis (refactor / rename / file move), a proposed Edit-tool resolution.
> - Wait for explicit OK. If user says "skip", mark `conflict-skipped`. If user says "fix it like that", apply via Edit tool, run gates, commit.
> - Write the conflict context to `{WORKSPACE}/conflicts/stash_{n}.context.md` so it survives compaction.
>
> Never run `git stash pop` / `git stash apply`. Never bypass pre-commit hooks. Never push.
>
> Output: count of applied / skipped / conflict-resolved + the recovery branch tip SHA.

---

## Phase 7 — Partial Splitter

> For each `partially-novel` row in `{WORKSPACE}/triage.tsv`:
>
> 1. Open `{BUNDLE}/diffs/{n}.diff` for inspection.
> 2. Identify novel hunks vs. superseded hunks (use the per-hunk evidence column from `triage.tsv` if present; otherwise re-fingerprint per-hunk).
> 3. **Create a split copy** at `{BUNDLE}/diffs/{n}.split.diff` keeping only the novel hunks. Use the Edit tool for semantic/manual splits. You may use `scripts/partial-split.sh` only when the hunk IDs to keep are explicit and mechanical. Never use ad hoc sed/awk/regex transformations.
> 4. `git apply --3way --check {BUNDLE}/diffs/{n}.split.diff` — must be clean.
> 5. Apply, run quality gates, commit. Message must note "split-apply: novel hunks only; superseded hunks dropped per triage row."
> 6. Append to `{WORKSPACE}/partial_split_log.tsv` with `hunks_kept`, `hunks_dropped`.
>
> Output: count of split-applied + count of partial-skipped.

---

## Phase 8 — Fresh Eyes (run each prompt separately, different agents)

> **Round 1 prompt:**
> Carefully read over all of the new code you just wrote and other existing code you just modified with 'fresh eyes' looking super carefully for any obvious bugs, errors, problems, issues, confusion, etc. Carefully fix anything you uncover.
>
> **Round 2 prompt:**
> Sort of randomly explore the code files in this project, choosing code files to deeply investigate and trace their functionality and execution flows through the related code files which they import or which they are imported by. Once you understand the purpose of the code in the larger context of the workflows, do a super careful, methodical, and critical check with 'fresh eyes' to find any obvious bugs, problems, errors, silly mistakes. Comply with ALL rules in AGENTS.md and ensure that any code you write or revise conforms to the best practice guides referenced in AGENTS.md.
>
> **Round 3 prompt:**
> Turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues. Diagnose underlying root causes using first-principle analysis. Don't restrict yourself to the latest commits — cast a wider net and go super deep.
>
> **Between rounds**, the main agent runs:
> ```
> {test_command}
> {typecheck_command}
> {lint_command}
> ubs .                # if available
> ```
> All must exit 0. Log each round + outcome to `{WORKSPACE}/fresh_eyes_log.md`.
>
> **Termination rule:** Two consecutive full rounds (all three prompts) produce only trivial findings (typo, wording polish) AND test + typecheck + lint + UBS all green.
>
> Scope: only the recovery branch's commits. Do NOT modify `{BUNDLE}/`. Do NOT touch the source repo's primary branch.

---

## Phase 9 — Cleanup Conductor (gated)

> The user has authorized destructive cleanup. The verbatim authorization text is in `{WORKSPACE}/cleanup_authorization.txt`. Read it; if it doesn't include the literal commands or an explicit phrase like `yes I understand and want to drop`, REFUSE and re-ask.
>
> Drop in order: garbage → superseded / superseded-by-newer-stash → novel-but-stale → applied-keeper. Within each bucket, **highest index first** (because indexes shift after each drop).
>
> Per stash:
>
> 1. Restate the verbatim command to the user before executing:
>    ```
>    About to run: git stash drop stash@{N}
>    (n={n} in inventory.tsv: "{message}", verdict={verdict})
>    ```
> 2. Execute `git stash drop stash@{N}`.
> 3. Append `n`, `pre_drop_index`, `ref_dropped`, `verdict`, `timestamp_utc` to `{WORKSPACE}/cleanup_log.tsv`.
>
> NEVER run `git stash clear`. NEVER delete `{BUNDLE}`. NEVER delete `refs/stash-backup/*`.
>
> If a drop fails (e.g., the stash was already gone because a concurrent agent dropped it), HALT, keep all backup refs and bundle artifacts intact, and rebuild the cleanup plan from the current stash list before continuing. Do not continue on stale stack indexes.
>
> Final state: `git stash list` should match the expected count (typically 0). All backup refs at `refs/stash-backup/*` remain intact.

---

## Phase 10 — Handoff Reporter

> Emit `{WORKSPACE}/handoff_report.md` per the template in `references/PHASES.md § Phase 10`. Include:
>
> - Project, run date, mode, recovery branch, bundle path
> - Counts per verdict
> - Recovered commit SHAs (read from `apply_log.tsv` + `partial_split_log.tsv`)
> - Recovery recipes (verbatim shell snippets)
> - Push instructions
> - Bundle lifecycle note
>
> File a beads issue: `br create --title "stash janitor pass on {project} ({N} stashes)" --type=task --priority=4` and link the report from the issue body.
>
> Update the Agent Mail thread (`thread_id={beads-id}`) with: `[{beads-id}] Stash janitor run complete; see handoff_report.md`.
>
> If `bv` is available: `bv --robot-triage` to surface follow-up items the recovered commits may unblock; append a brief summary to the report.
>
> Print the push command to the user verbatim. Do NOT push.

---

## Phase 11 — User-Lens Reviewer (optional)

> A fresh agent reviews the entire run from the perspective: "Did this stash janitor save the user time? Where did it surface friction? What would have made it better?"
>
> Read `{WORKSPACE}/handoff_report.md`, `apply_log.tsv`, `cleanup_log.tsv`, and any `conflicts/*.context.md`. Identify:
>
> - Phases where the user had to wait or repeat themselves
> - Decisions where the rubric was ambiguous
> - Missing operators or unclear failure-mode coverage
> - Any silent fallbacks the user didn't realize happened
>
> Write findings to `{WORKSPACE}/skill_feedback.md` with one section per friction point. For each, propose a concrete change to this skill's SKILL.md or references/.
>
> Optionally, file beads issues against this skill itself for skill maintainers.
