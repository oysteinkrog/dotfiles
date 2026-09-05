# Operator Library

Each operator is a reusable cognitive move with explicit triggers, a prompt module, and exit criteria. Adapted from [`operationalizing-expertise`](../../operationalizing-expertise/SKILL.md) Track A.

Agents invoke operators by tag. Every Polish-Bar failure maps to exactly one operator.

---

## How to use this file

1. When designing a phase or polishing a step, walk it against the Polish Bar (see [POLISH-BAR.md](POLISH-BAR.md) and [SKILL.md](../SKILL.md#the-polish-bar-non-negotiable)).
2. For each failing dimension, find the operator whose tag matches.
3. Paste the operator's *prompt module* into your working context (or inline into a subagent invocation).
4. Do what it says. Exit criteria are in the module.

---

## ★ INVENTORY

**Definition:** Capture every stash's identity (ref + sha + parent + date + message + shortstat) into a single TSV that becomes the source of truth for the rest of the run.

**Triggers:**
- Phase 2 — once per run
- Resumption mid-run (re-inventory cheaply because a concurrent agent may have created or dropped a stash)

**Failure modes:**
- Inventorying via `git stash list` alone — misses untracked-files presence
- Inventorying twice from different snapshot points — index drift between the two inventories

**Prompt module:**
```
[OPERATOR: ★ INVENTORY]
1) git -C {PROJECT} stash list --format='%gd|%H|%P|%ci|%an|%s' > inventory.raw
2) For each line, capture:
   - shortstat: git stash show --stat stash@{N}
   - has_untracked: bool from git rev-parse stash@{N}^3 2>/dev/null
3) Write inventory.tsv with columns: n, ref, sha, parent_sha, date, author,
   message, files, insertions, deletions, has_untracked.
4) Group by message-prefix family; emit inventory_grouped.md.

Required: row count == git stash list | wc -l (sanity check).
Output: inventory.tsv, inventory_grouped.md, count summary.
```

**Canonical tag:** `inventory`

---

## ✦ FINGERPRINT

**Definition:** Identify the symbols a stash *introduces* — function names, type names, fixture strings, test names, file paths added by the stash. The fingerprint is the input to VERIFY-ON-MAIN.

**Triggers:**
- Phase 4, per-stash, before any "is it on main?" check
- Phase 6, between applies (re-fingerprint downstream candidates)

**Failure modes:**
- Fingerprinting only function names — misses test/fixture/string-only stashes
- Fingerprinting via `+` line text alone — picks up modified lines as if they were added; false positives
- Treating a moved-but-unchanged function as "introduced"

**Prompt module:**
```
[OPERATOR: ✦ FINGERPRINT]
For diff at {BUNDLE}/diffs/{n}.diff:

1) For each chunk header (^@@), check whether the file is new (`new file mode`)
   or existing. New-file diffs: every `+` line is added. Existing-file diffs:
   only `+` lines that are NOT followed by a corresponding `-` line are added.

2) Extract introduced symbols by language:
   - Rust: `^\+\s*(pub )?(unsafe )?(async )?fn (\w+)`,
           `^\+\s*(pub )?(struct|enum|trait|type) (\w+)`
   - TypeScript/JS: `^\+\s*(export )?(async )?function (\w+)`,
                    `^\+\s*(export )?(const|let) (\w+) =`,
                    `^\+\s*(export )?(class|interface|type) (\w+)`
   - Python: `^\+\s*(async )?def (\w+)`, `^\+\s*class (\w+)`
   - Go: `^\+func (\w+)`, `^\+func \(\w+ \*?\w+\) (\w+)`,
         `^\+type (\w+) (struct|interface|...)`
   - Tests: language-appropriate, e.g.,
            Rust: `^\+\s*#\[test\]` then capture next `fn (\w+)`
            JS: `^\+\s*(it|test)\(['"]([^'"]+)`
            Python: `^\+\s*def (test_\w+)`
   - Fixture strings: literal strings ≥10 chars in `+` lines (deduplicated)
   - File paths: every `^diff --git a/(.*) b/`

3) Output the fingerprint as a JSON object:
   {
     "files": [...],
     "new_files": [...],
     "functions": [...],
     "types": [...],
     "tests": [...],
     "fixture_strings": [...]
   }

Required: union of all introduced symbols. Empty fingerprint == garbage candidate.
```

**Canonical tag:** `fingerprint`

---

## ◐ VERIFY-ON-MAIN

**Definition:** For each fingerprint, search the primary branch and decide: is it already there with equivalent semantics?

**Triggers:**
- Phase 4, immediately after FINGERPRINT
- Phase 6, between applies (re-verify with the latest recovery-branch tip)

**Failure modes:**
- Whole-repo grep when a path-scoped grep would suffice — slow + noisy
- Treating "symbol present" as "semantically equivalent" — needs a quick read of both implementations
- Ignoring branch-divergence (running grep against `HEAD` instead of `origin/{primary}`)

**Prompt module:**
```
[OPERATOR: ◐ VERIFY-ON-MAIN]
Inputs: fingerprint (json), primary_branch (e.g., "main"), expected file paths.

For each function/type/test name F in fingerprint:
  if F's expected file path P exists on primary_branch:
    git -C {PROJECT} grep -F 'F' {primary_branch} -- 'P'
  else:
    git -C {PROJECT} grep -F 'F' {primary_branch}

  Record per-symbol:
    - found_on_main: bool
    - file:line where found (or "n/a")
    - same_signature: bool — quick re-read of the line; does the param list match?

For each fixture_string S:
  git -C {PROJECT} grep -F 'S' {primary_branch}
  Record found_on_main bool.

For each new_file F:
  if git -C {PROJECT} ls-tree {primary_branch} -- F succeeds: file exists, mark file_already_on_main.

Verdict input from this operator (consumed by TRIAGE-RUBRIC):
  - fingerprint_coverage: fraction of symbols found on primary
  - hunk_coverage: fraction of `+` lines that match content already on primary
  - file_existence_coverage: fraction of files referenced still exist on primary

Output: a json object per stash, written to triage/batch_*.tsv as the
"evidence_on_main" + "fingerprint_coverage" columns.
```

**Canonical tag:** `verify-on-main`

---

## ⬡ BUNDLE

**Definition:** Materialize a complete, byte-equality-verified recovery bundle for every stash *before* any classification or destructive action runs.

**Triggers:**
- Phase 3 — once, the irreversibility gate

**Failure modes:**
- Using `git format-patch -1` instead of `git stash show -p --binary` — it is not the stash recovery diff and can be empty or wrong for merge stash commits. Plain `git stash show -p` also omits tracked binary payloads. **This was a real bug in the asupersync session.**
- Skipping untracked files (the third-parent commit) — silently drops new-file content
- Verifying only the diff and not the backup ref — diffs can be regenerated; backup refs cannot if the live stash is dropped first
- "Sampling" verification (checking only 10 random stashes) — every entry must be verified

**Prompt module:**
```
[OPERATOR: ⬡ BUNDLE]
For every stash row in inventory.tsv, use n plus the row's stable sha:

1) git update-ref refs/stash-backup/{n} {sha}
   # Creates a permanent ref that survives `git stash clear`.

2) git stash show -p --binary {sha} > {BUNDLE}/diffs/{n}.diff
   # NOT `git format-patch` — that is not the stash recovery diff.

3) git log -1 --format='%H%n%P%n%ci%n%an%n%s' {sha} > {BUNDLE}/meta/{n}.txt

4) If git rev-parse {sha}^3 succeeds:
     git archive --format=tar {sha}^3 | tar -x -C {BUNDLE}/stashed-untracked/{n}/

5) Verify:
   - index.tsv sha == git rev-parse refs/stash-backup/{n}
   - sha256sum of git stash show -p --binary {sha} == sha256sum of bundle's diff
   ANY mismatch HALTS the run.

6) Write {BUNDLE}/index.tsv (mirror of inventory.tsv + bundle_artifacts column).
7) Write {BUNDLE}/README.md with recovery recipes and the format-patch footgun warning.

Required: zero MISMATCH lines in bundle_verification.log. The bundle is the
only thing standing between the user and lost work — treat it like radiation
shielding.
```

**Canonical tag:** `bundle`

---

## ⚠ CONFIRM

**Definition:** Restate the destructive command verbatim, wait for an explicit user-typed authorization in the same message, record the authorization text. From AGENTS.md: "even after explicit user authorization, restate the command verbatim, list exactly what will be affected, and wait for a confirmation that your understanding is correct."

**Triggers:**
- Phase 5 (gate) — before any commits would be authored
- Phase 9 (gate) — before any `git stash drop` runs
- Mid-Phase 6 — when an apply-check fails and the user is asked to OK a manual resolution

**Failure modes:**
- "I'll proceed if you say yes" — implicit; user might say "yes please continue with phase 6" without realizing they authorized 89 destructive operations
- Listing the count but not the verbatim commands — user can't audit what was authorized
- Assuming a prior authorization extends to a changed cleanup plan — if the bucket scope or command list changes, rebuild the plan and re-confirm

**Prompt module:**
```
[OPERATOR: ⚠ CONFIRM]

Output to user EXACTLY:

> I'm about to {action}. Here are the verbatim commands in execution order:
>
>   {command_1}
>   {command_2}
>   ...
>
> {What will be affected, in plain English: "127 stashes dropped; backup refs
>  at refs/stash-backup/* and the bundle at {BUNDLE} stay intact."}
>
> To proceed, paste this verbatim:
>   {authorization phrase including a literal command from above}

Then WAIT. Do not continue until the user types text that includes the
authorization phrase. If they type something different, REFUSE and re-ask.

On receipt: write the user's exact text + UTC timestamp to
{WORKSPACE}/cleanup_authorization.txt (or _confirmation.txt for non-cleanup
gates).

Required: the file contains the user's literal text. Without that file,
treat the action as un-authorized.
```

**Canonical tag:** `confirm`

---

## ✧ APPLY-3WAY

**Definition:** Apply a stash's diff via `git apply --3way`, NOT `git stash pop` / `git stash apply`. Always dry-run with `--check` first.

**Triggers:**
- Phase 6, per keeper
- Phase 7, per partial-split

**Failure modes:**
- `git stash pop` — succeeds → drops the stash → if the apply was wrong, you're now relying on the bundle (fine, but slower)
- `git stash pop` — fails → leaves the working tree dirty AND the stash still in the list AND a half-applied state
- Skipping `--check` and going straight to apply — same end state as a failed pop
- `--3way` not specified — silent failure on context-drifted hunks; rejects file gets created and you might miss it

**Prompt module:**
```
[OPERATOR: ✧ APPLY-3WAY]
Inputs: stash index n, bundle path BUNDLE.

1) git apply --3way --check {BUNDLE}/diffs/{n}.diff
   - exit 0: clean, proceed.
   - exit non-zero: STOP. Do NOT apply. Engage the conflict-surface flow:
     - Show the user the diff
     - Show the user the affected files' current state
     - Hypothesize the cause (refactor / rename / file move)
     - Propose an Edit-tool resolution that preserves the stash's INTENT
       (not its surface form — the surface form is from before the refactor)
     - Wait for explicit OK before proceeding.

2) If clean check, apply: git apply --3way {BUNDLE}/diffs/{n}.diff
3) If {BUNDLE}/stashed-untracked/{n}/ exists, copy contents into {PROJECT}.
4) Run quality gates from project_profile.json:
   {test_command}
   {typecheck_command}
   {lint_command}
   ubs .   # if available
   ALL must exit 0.
5) git add (only the changed files; NOT the workspace).
6) Commit with a focused, why-explaining message.

Never use `git stash pop` or `git stash apply`. Never bypass pre-commit hooks.
Required: exit-0 on all gates before commit; commit message explains the WHY.
```

**Canonical tag:** `apply-3way`

---

## ⇄ SPLIT-HUNKS

**Definition:** For partially-novel stashes, create a split copy of the diff that drops superseded hunks and keeps only novel ones, then apply that smaller diff.

**Triggers:**
- Phase 7, per partially-novel row in triage.tsv

**Failure modes:**
- Trying to use `git apply --include=<path>` for hunk-level filtering — `--include` is path-level, not hunk-level
- Editing the diff with ad hoc sed/awk/regex transformations — brittle; per AGENTS.md, no script-based code mutation. The bundled `partial-split.sh` is the only mechanical exception, and only when exact hunk IDs are already known.
- Forgetting to run apply-check on the split diff before actually applying — same risk as raw APPLY-3WAY

**Prompt module:**
```
[OPERATOR: ⇄ SPLIT-HUNKS]
Inputs: stash n, per-hunk evidence (which hunks are novel, which superseded).

1) Open {BUNDLE}/diffs/{n}.diff for inspection.
2) Identify hunk boundaries (^@@) and which are novel.
3) Create a COPY at {BUNDLE}/diffs/{n}.split.diff. Use the Edit tool for
   semantic/manual splits; use scripts/partial-split.sh only for exact
   hunk-number filtering. Remove the superseded hunks completely. Each remaining hunk's `@@` header
   stays intact (don't renumber). Each remaining hunk's context lines stay
   intact.
4) git apply --3way --check {BUNDLE}/diffs/{n}.split.diff — must be clean.
5) Apply via APPLY-3WAY operator. Run gates. Commit.
6) Append to partial_split_log.tsv: hunks_kept, hunks_dropped, new_commit_sha.

Required: the split diff applies cleanly; commit message explicitly states
"split-apply: novel hunks only".
```

**Canonical tag:** `split-hunks`

---

## ⊕ RECOVER

**Definition:** Run the project's actual quality gates (test + typecheck + lint + UBS) on every Phase 6 / Phase 7 apply. Catch compounding errors per-keeper, not at the end.

**Triggers:**
- Phase 6, after every successful apply
- Phase 7, after every successful split-apply

**Failure modes:**
- Running gates only at the end of Phase 6 — by the time something fails, you don't know which apply caused it
- Running a subset of gates ("we'll skip clippy this time") — UBS or clippy might be the only thing that catches an unwrap that passed the test suite
- Silent fallback when a gate isn't installed — record `skipped` in the log, surface to the user; don't pretend the gate ran

**Prompt module:**
```
[OPERATOR: ⊕ RECOVER]
After every successful apply, in this exact order:

1) {test_command}
2) {typecheck_command}
3) {lint_command}
4) ubs .   # if available
5) Any project-specific gate from project_profile.json (e.g., a regression
   harness, golden-file diff).

Each must exit 0. Capture exit code + duration in apply_log.tsv:gates_status.

If any gate fails:
- Do NOT commit.
- Try to reverse only the applied tracked diff via `git apply -R --3way <bundle>/diffs/{n}.diff`.
- If that fails, halt and surface the exact dirty paths. Do not use blanket
  checkout/clean/reset commands.
- Surface to the user with the gate's output and the affected stash.
- Wait for direction.

Required: gates_status == "passed" before commit. No "we'll fix it later".
```

**Canonical tag:** `recover`

---

## ⊙ DROP

**Definition:** Drop a stash by its current index, **highest first** within each verdict bucket (because indexes shift down after each drop). Backup ref stays.

**Triggers:**
- Phase 9, per stash, in order garbage → superseded / superseded-by-newer-stash → novel-but-stale → applied-keeper

**Failure modes:**
- Dropping by lowest index first — every subsequent index shifts; you drop the wrong stash
- Trusting an index from a stale inventory — concurrent agents can shift the list
- Running `git stash clear` — drops everything at once; per-stash recovery from the bundle still works but operationally noisy

**Prompt module:**
```
[OPERATOR: ⊙ DROP]
Inputs: triage.tsv with verdicts; cleanup_authorization.txt with verbatim user OK.

1) Build the drop plan: bucket-ordered (garbage → superseded /
   superseded-by-newer-stash → novel-but-stale → applied-keeper), each bucket sorted descending by `n` (current stash list
   index). Materialize as cleanup_plan.tsv before executing.

2) For each row in cleanup_plan.tsv:
   a) Re-resolve the current ref: the message in stash@{n} should match the
      message in inventory.tsv. If not, the list has shifted unexpectedly —
      HALT and ask the user.
   b) Restate the verbatim command to the user:
        About to run: git stash drop stash@{n}
        (n={n} in inventory.tsv: "{message}", verdict={verdict})
   c) git stash drop stash@{n}
   d) Append to cleanup_log.tsv: n, pre_drop_index, ref_dropped, verdict,
      timestamp_utc.

3) NEVER `git stash clear`. NEVER touch refs/stash-backup/*. NEVER touch
   {BUNDLE}.

Required: at end, git stash list returns the expected count (typically 0);
every backup ref still resolves; cleanup_log.tsv has one row per drop.
```

**Canonical tag:** `drop`

---

## ⌘ HANDOFF

**Definition:** Emit the final report with everything the user needs to (a) understand what changed, (b) push the recovery branch, (c) recover from any drop they regret.

**Triggers:**
- Phase 10 — once, at end of run

**Failure modes:**
- Reporting counts only, no SHAs — user can't see what landed
- Forgetting the recovery recipes — user has the bundle but no idea how to use it
- Pushing the recovery branch — every example skill in this repo treats deployment as the user's call

**Prompt module:**
```
[OPERATOR: ⌘ HANDOFF]
Read apply_log.tsv, partial_split_log.tsv, cleanup_log.tsv, triage.tsv.

Emit handoff_report.md with these sections (in order):
  1. Project + run date + mode + recovery branch + bundle path
  2. Counts per verdict (initial → triaged → applied → dropped → final stash list)
  3. Recovered commits table (sha, from-stash, message)
  4. Conflict resolutions (if any) — context paths
  5. Recovery recipes (verbatim cherry-pick + apply commands, per-stash)
  6. Push instructions: `git push origin {recovery_branch}`; the user pushes.
  7. Bundle lifecycle: keep for ≥1 release cycle; user manages deletion.

File a beads issue: br create --title "stash janitor pass on {project}".
Update Mail thread.
If bv available: bv --robot-triage; append summary.

Print the push command verbatim. NEVER push.
```

**Canonical tag:** `handoff`

---

## ⊞ RE-FINGERPRINT

**Definition:** After every successful Phase 6 apply, re-run FINGERPRINT/VERIFY-ON-MAIN on downstream keep candidates. Some now flip to `superseded` because the just-applied content covers their fingerprint.

**Triggers:**
- Phase 6, between applies

**Failure modes:**
- Skipping re-fingerprint — apply two stashes that introduce the same symbol, get a duplicate-definition build break
- Re-fingerprinting against `origin/{primary}` instead of the recovery branch's HEAD — misses the just-applied content

**Prompt module:**
```
[OPERATOR: ⊞ RE-FINGERPRINT]
After committing keeper k, before apply-checking keeper k+1:

For every remaining novel-and-accretive row in triage.tsv:
  Run VERIFY-ON-MAIN with primary_branch = HEAD (the recovery branch's tip).
  If fingerprint_coverage now ≥ 0.8: flip verdict to `superseded-during-apply`.
  Append the flip to apply_log.tsv with a note.

This ensures dependency-ordered duplicates don't both apply.
Required: no two keepers introduce the same fingerprint.
```

**Canonical tag:** `re-fingerprint`

---

## ↺ WORKING-TREE-DRIFT

**Definition:** Re-snapshot `git status` + `git diff` before each Phase 6 apply. If changes appear from concurrent agents, treat as if you made them. Per AGENTS.md "Note for Codex/GPT-5.5": never stash, revert, or overwrite.

**Triggers:**
- Phase 6, every iteration

**Failure modes:**
- Asking the user "I see unexpected changes, please advise" — explicitly prohibited by AGENTS.md
- Stashing concurrent agents' changes "to clean up" — destroys their work
- Running `git checkout -- .` — same destruction with extra steps

**Prompt module:**
```
[OPERATOR: ↺ WORKING-TREE-DRIFT]

Before each Phase 6 apply:

1) git status --porcelain=v2 > {WORKSPACE}/wt_pre_apply_{n}.txt
2) git diff --stat >> {WORKSPACE}/wt_pre_apply_{n}.txt

If new files / changes appear that you did not author this iteration:
  - These are concurrent agents' work. Per AGENTS.md, treat as if you made them.
  - DO NOT stash, revert, or overwrite.
  - Proceed with the apply. The 3-way merge will handle context.
  - Note in apply_log.tsv:pre_apply_drift = "concurrent: <files>".

If the apply CONFLICTS with concurrent changes:
  - Surface to the user. Don't auto-resolve; the user knows context you don't.

Required: never disturb concurrent agents' state.
```

**Canonical tag:** `working-tree-drift`

---

## Operator Composition Cheat-Sheet

For each phase, the canonical operator order:

| Phase | Operator sequence |
|-------|-------------------|
| 2 | `★ INVENTORY` |
| 3 | `⬡ BUNDLE` (no other operators — bundle is the gate) |
| 4 | `✦ FINGERPRINT` → `◐ VERIFY-ON-MAIN` (per stash) |
| 5 | `⚠ CONFIRM` (the user gate) |
| 6 | `↺ WORKING-TREE-DRIFT` → `⊞ RE-FINGERPRINT` → `✧ APPLY-3WAY` → `⊕ RECOVER` (per keeper) |
| 7 | `⇄ SPLIT-HUNKS` → `✧ APPLY-3WAY` → `⊕ RECOVER` (per partial) |
| 8 | (no operators — fresh-eyes prompts are themselves the methodology) |
| 9 | `⚠ CONFIRM` (gate) → `⊙ DROP` (per stash, highest-index-first per bucket) |
| 10 | `⌘ HANDOFF` |

Operators are deliberately overlapping — a single Phase 6 apply typically deserves four (`↺`, `⊞`, `✧`, `⊕`). When composing, run them in the order above; each consumes the previous one's output.
