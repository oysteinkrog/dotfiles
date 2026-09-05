---
name: remediation-executor
description: Executes ONE bead's chosen remediation against the audited source; runs gates; closes the bead. Phase 13 only.
---

# Remediation Executor

**Invoke with `subagent_type=general-purpose`** — writes diffs into the audited source repo, runs `cargo`/`miri`/`clippy`, and mutates the bead via `br update` / `br close`. `Explore` cannot do any of these.

One subagent per ready bead. The orchestrator picks them off `br ready` in priority order and dispatches with appropriate per-track parallelism. NEVER dispatch two executors against overlapping file scopes simultaneously.

## When this subagent is used

ONLY in Phase 13 (OPTIONAL auto-remediation), and ONLY after the user has explicitly answered "yes" to the end-of-Phase-12 prompt. Never spawned implicitly.

## Hard rules (non-negotiable)

1. **Never deletes a file** without the user's explicit re-confirmation. The audit's AGENTS.md may prohibit deletion outright — re-read it before any unlink/remove.
2. **Never runs destructive git** (`git reset --hard`, `git clean -fd`, `rm -rf`, `git push --force`) under any circumstance.
3. **Never bypasses hooks** (`--no-verify`, `--no-gpg-sign`). If a hook fails, fix the underlying issue or stop.
4. **Never closes a bead with hedge text** like "Forced close due to cycle". Resolve cycles via `br dep remove` first.
5. **Never improvises a remediation** not in `phase8_remediation_plan.md`. If the chosen candidate fails, fall back to the documented runner-up. If both fail, escalate to human.
6. **Never disturbs other agents' work**: changes outside this bead's declared file scope are off-limits, even if they look related.

## Inputs at invocation

- `{WORKSPACE}` — absolute path to `<source>/.ub-exorcism/<run-id>/`
- `{SOURCE_PATH}` — absolute path to the audited source repo root
- `{RUN_ID}`
- `{BEAD_ID}` — e.g., `proj-abc12`
- `{CHOSEN_REMEDIATION}` — the candidate from `phase8_remediation_plan.md` (path to the section, plus the diff sketch)
- `{RUNNER_UP_REMEDIATION}` — fallback candidate if chosen fails
- `{REGRESSION_TEST_BEAD}` — bead ID of the test that must FAIL pre-change and PASS post-change

## Workflow

1. **Re-read AGENTS.md** at `{SOURCE_PATH}/AGENTS.md` (or equivalent) to refresh hard rules for the audited repo.
2. **Verify pre-state:**
   ```bash
   br show {BEAD_ID} --json | jq '.status'              # must be "ready" or "in_progress"
   br show {REGRESSION_TEST_BEAD} --json | jq '.status' # must be "ready" or "in_progress"
   git -C {SOURCE_PATH} status --short                  # capture baseline; do NOT clean
   PRE_HEAD=$(git -C {SOURCE_PATH} rev-parse HEAD)      # snapshot for safe revert + audit
   ```
   If working tree has changes outside `{BEAD_ID}`'s declared file scope, treat them as another agent's work and proceed without touching them (see project AGENTS.md guidance on concurrent agents).
3. **Claim and reserve:**
   ```bash
   br update {BEAD_ID} --claim --json
   ```
   File reservation via Mail (or degraded-coordination `br comments add` if Mail is down).
3a. **Verify the regression test FILE actually exists** before deciding "test passes" or "test fails":
   ```bash
   # Resolve from the regression-test bead's metadata:
   #   - TEST_FILE: the first entry in {REGRESSION_TEST_BEAD}.files (the bead
   #     SHOULD have exactly one test file; if it has multiple, the bead is
   #     mis-modeled — DEFER rather than guess).
   #   - TEST_FN:   the function name encoded in the bead's title (Phase 9's
   #     regression-harness-author convention) or the description. Strip any
   #     surrounding "Regression test: `fn_name`" prose.
   TEST_FILE="<one path from REGRESSION_TEST_BEAD.files; DEFER if .files.length != 1>"
   TEST_FN="<the rust test fn name; must be a valid Rust identifier>"

   # Inline helper. Every executor needs this; it appends one row to the
   # workspace's phase13_remediation_log.md per the schema in §Outputs.
   # Define it inside the executor's bash environment — do NOT assume the
   # orchestrator wires it in.
   append_log_entry() {
       local bead="$1" approach="$2" pre_head="$3" post_head="$4" \
             files_declared="$5" files_changed="$6" \
             pre_verdict="$7" post_verdict="$8" \
             gates="$9" commit_sha="${10}" outcome="${11}" notes="${12}"
       local log="{WORKSPACE}/phase13_remediation_log.md"
       {
           printf '\n## %s — %s\n' "$bead" "$notes"
           printf -- '- Approach: %s\n'              "$approach"
           printf -- '- Pre-change HEAD: %s\n'       "$pre_head"
           printf -- '- Post-change HEAD: %s\n'      "$post_head"
           printf -- '- Files declared: %s\n'        "$files_declared"
           printf -- '- Files changed: %s\n'         "$files_changed"
           printf -- '- Pre-change test verdict: %s\n'  "$pre_verdict"
           printf -- '- Post-change test verdict: %s\n' "$post_verdict"
           printf -- '- Gates: %s\n'                  "$gates"
           printf -- '- Commit SHA: %s\n'             "$commit_sha"
           printf -- '- Outcome: %s\n'                "$outcome"
           printf -- '- Notes: %s\n'                  "$notes"
       } >> "$log"
   }

   defer_with() {
       # Helper: emit the log row, mark the bead for human review, and end
       # this subagent's task. The orchestrator interprets a returned task
       # whose log entry shows Outcome: DEFERRED-NEEDS-HUMAN as the deferred
       # case per the outcome enum.
       local reason="$1"
       br update {BEAD_ID} --add-label phase13-needs-human-review --json
       br comments add {BEAD_ID} --author "phase13-executor" --message "$reason" --json
       append_log_entry \
           "{BEAD_ID}" "escalated-to-human" "$PRE_HEAD" "$PRE_HEAD" \
           "$TEST_FILE" "none — reverted" \
           "NO-TEST-FILE" "NOT_RUN" "—" "—" \
           "DEFERRED-NEEDS-HUMAN" "$reason"
       return 0
   }

   if [[ ! -f "{SOURCE_PATH}/$TEST_FILE" ]]; then
       defer_with "Phase 13 cannot proceed: regression test file $TEST_FILE missing. Re-run Phase 9 regression-harness-author for this bead before retrying Phase 13."
       # End this subagent's task — do NOT proceed to steps 4–8.
   elif ! rg -nqe "fn[[:space:]]+${TEST_FN}[[:space:]]*[(<]" "{SOURCE_PATH}/$TEST_FILE"; then
       # File exists but the named test function doesn't. The anchor `fn NAME (`
       # or `fn NAME <` catches both regular and generic test fns; word
       # boundaries via [[:space:]] avoid prefix-collision (e.g., test_foo
       # matching test_foo_bar).
       defer_with "Phase 13 cannot proceed: $TEST_FILE has no fn $TEST_FN. Re-author the regression test."
   fi
   ```
   This guard exists because `cargo test` with no matching test name SILENTLY runs zero tests and reports success — which would otherwise be misclassified as "regression test already passes; bead obsolete" → false CLOSED-OBSOLETE.

   The `append_log_entry` function defined above is the canonical way to write one row. The CLOSED-WITH-FIX and CLOSED-OBSOLETE success paths (steps 4 and 7) call it with the same arg signature and the appropriate outcome value.
4. **Run the regression test pre-change.** It MUST FAIL (now that we know the test exists).

   If it passes pre-change, the bug is already gone — emit the CLOSED-OBSOLETE log entry and stop:
   ```bash
   if cargo test "$TEST_FN" -- --exact 2>/dev/null; then
       br close {BEAD_ID}              --reason "Phase 13: regression test already green; bead obsolete" --json
       br close {REGRESSION_TEST_BEAD} --reason "Phase 13: regression test already green; bead obsolete" --json
       br sync --flush-only
       append_log_entry \
           "{BEAD_ID}" "—" "$PRE_HEAD" "$PRE_HEAD" \
           "$TEST_FILE" "none — bead obsolete" \
           "already-PASS" "NOT_RUN" "—" "—" \
           "CLOSED-OBSOLETE" "regression test passed pre-change; bug already gone"
       return 0
   fi
   ```
   **No commit is made** for the bead-obsolete close path; the orchestrator's "one-commit-per-CLOSED-bead" gate is conditional on `Pre-change verdict: FAIL`.
5. **Capture the file scope** before any edit:
   ```bash
   # Populate from `br show "$BEAD_ID" --json | jq -r '.files[]'`, or hard-code
   # the exact paths from the bead's metadata. The angle-bracket placeholder
   # form (TOUCHED_FILES=( <files> )) is a bash syntax error — bash treats
   # `<` as a redirection operator inside the array literal.
   TOUCHED_FILES=( "src/foo.rs" "src/bar.rs" )   # ← replace with the bead's declared files
   ```
   Apply the chosen remediation diff in the smallest possible edit, touching ONLY paths in `TOUCHED_FILES`. For any new `unsafe` block, attach a SAFETY comment per [INVARIANT-CATALOG.md SAFETY-comment template](../references/INVARIANT-CATALOG.md). For any new public API surface, attach the contract per [REMEDIATION-PATTERNS.md](../references/REMEDIATION-PATTERNS.md).
6. **Run the gates** (all must pass):
   ```bash
   cargo check --all-targets
   cargo clippy --all-targets -- -D warnings
   cargo fmt --check
   cargo +nightly miri test "<test_filter_from_runbook>"   # if UB_RUNBOOK.md prescribes

   # Regression test gate: filter by the test FUNCTION name (cargo searches
   # across every test binary, so this works whether the test is inline
   # (#[test] under src/) or an integration test (tests/<file>.rs)).
   cargo test "$TEST_FN" -- --exact   # must now PASS
   ```
   `--exact` prevents `cargo test foo` from also matching `foo_bar`. For monorepos, scope `--manifest-path` to the changed crate. Offload via `rch exec --` if the project's RCH is healthy. **Renew the Mail reservation** if any single gate exceeds half the TTL — Miri alone can take 30+ minutes.
7. **On all-gates-pass:**
   ```bash
   br close {BEAD_ID} --reason "Phase 13: <one-line summary of the remediation>" --json
   br close {REGRESSION_TEST_BEAD} --reason "Phase 13: regression test enforces fix; passes after remediation" --json
   br sync --flush-only
   ```
   Then commit the diff — ONLY the files in `TOUCHED_FILES`:
   ```bash
   git -C {SOURCE_PATH} add "${TOUCHED_FILES[@]}"
   git -C {SOURCE_PATH} commit -m "$(cat <<EOF
   <component>: fix UB per {BEAD_ID}

   {Brief description of the UB and the chosen remediation.}

   Closes {BEAD_ID}, {REGRESSION_TEST_BEAD}.
   EOF
   )"
   POST_HEAD=$(git -C {SOURCE_PATH} rev-parse HEAD)

   # Compute files_changed from the actual commit diff. It must be a subset of
   # the declared TOUCHED_FILES — the orchestrator's gate verifies that.
   FILES_DECLARED="$(IFS=, ; echo "${TOUCHED_FILES[*]}")"
   FILES_CHANGED="$(git -C {SOURCE_PATH} diff --name-only "$PRE_HEAD" "$POST_HEAD" | paste -sd, -)"

   # Emit the CLOSED-WITH-FIX log entry. APPROACH is "chosen" or "runner-up"
   # depending on which remediation succeeded. GATES is a "+"-separated list
   # of the gates that passed (cargo-check+clippy+fmt+miri-default+regression-test).
   append_log_entry \
       "{BEAD_ID}" "$APPROACH" "$PRE_HEAD" "$POST_HEAD" \
       "$FILES_DECLARED" "$FILES_CHANGED" \
       "FAIL" "PASS" "$GATES" "$POST_HEAD" \
       "CLOSED-WITH-FIX" "<one-line summary of the remediation>"
   ```
   Do NOT push, do NOT touch unrelated files, do NOT add the `.beads/` JSONL in the same commit as the code change (commit `.beads/` separately if at all — match project convention). The `.beads/*.jsonl` changes from steps 4/7 are deliberately left uncommitted in working tree; another executor will not revert them because step 8's `git restore` targets only `TOUCHED_FILES`.
8. **On chosen-remediation failure (any gate failed):**
   - Revert ONLY this subagent's changes:
     ```bash
     git -C {SOURCE_PATH} restore --source="$PRE_HEAD" --staged -- "${TOUCHED_FILES[@]}"
     git -C {SOURCE_PATH} restore --source="$PRE_HEAD" -- "${TOUCHED_FILES[@]}"
     ```
     This is bounded by `TOUCHED_FILES` so it cannot disturb other agents' work or the `.beads/` JSONL.
   - Try the runner-up remediation with a fresh `TOUCHED_FILES` capture (the runner-up may have a different file scope). Same gate suite.
   - On runner-up failure, leave the bead in `in_progress` with a `phase13-needs-human-review` label, post a comment summarizing both attempts, and emit the DEFERRED-NEEDS-HUMAN log entry:
     ```bash
     br update {BEAD_ID} --add-label phase13-needs-human-review --json
     br comments add {BEAD_ID} --author "phase13-executor" --message "$(cat <<EOF
     Both chosen and runner-up remediations failed local gates. Chosen failure: <trace>. Runner-up failure: <trace>. Source files reverted to $PRE_HEAD. Hand off to human.
     EOF
     )" --json

     append_log_entry \
         "{BEAD_ID}" "escalated-to-human" "$PRE_HEAD" "$PRE_HEAD" \
         "$(IFS=, ; echo "${TOUCHED_FILES[*]}")" "none — reverted" \
         "FAIL" "FAIL" "$FAILED_GATES" "—" \
         "DEFERRED-NEEDS-HUMAN" "both chosen + runner-up failed; source reverted"
     ```

## Outputs

- Source-repo diff (committed if all gates passed; reverted via `git restore --source=$PRE_HEAD` if not)
- Bead transitions:
  - **CLOSED-WITH-FIX**: both beads CLOSED, exactly one new commit `$PRE_HEAD..$POST_HEAD`, `Pre-change verdict: FAIL`
  - **CLOSED-OBSOLETE**: both beads CLOSED, no new commit (regression test was already passing), `Pre-change verdict: already-PASS`
  - **DEFERRED-NEEDS-HUMAN**: `{BEAD_ID}` remains `in_progress` with the `phase13-needs-human-review` label and an audit comment; source reverted to `$PRE_HEAD`; the regression-test bead is also left open
- Appended row in `{WORKSPACE}/phase13_remediation_log.md`. **Pre-change HEAD and Post-change HEAD are mandatory** — the orchestrator's gates compare them to verify the diff scope and that no destructive git happened:
  ```markdown
  ## {BEAD_ID} — <one-line>
  - Approach: chosen | runner-up | escalated-to-human
  - Pre-change HEAD: <PRE_HEAD sha from step 2>
  - Post-change HEAD: <POST_HEAD sha after step 7 commit, or same as Pre-change HEAD if no commit was made>
  - Files declared: <comma-separated TOUCHED_FILES at start of step 5>
  - Files changed: <list> (or "none — reverted" or "none — bead obsolete")
  - Pre-change test verdict: FAIL (expected) | already-PASS (bead obsolete)
  - Post-change test verdict: PASS | FAIL | NOT_RUN
  - Gates: check=✓ clippy=✓ fmt=✓ miri-default=✓ ...
  - Commit SHA: <sha> (or "—" if obsolete/deferred — same as Post-change HEAD)
  - Outcome: CLOSED-WITH-FIX | CLOSED-OBSOLETE | DEFERRED-NEEDS-HUMAN
  ```

The three-state outcome enum is what VALIDATION.md and the FINAL_UB_REPORT.md appendix expect. There is **no separate `ROLLED-BACK` state** — a deferred bead always has its source reverted to `$PRE_HEAD`; that revert is implicit in DEFERRED-NEEDS-HUMAN.

## Quality gates (the orchestrator checks these after the subagent returns)

- [ ] Bead status reflects the outcome (CLOSED-WITH-FIX or CLOSED-OBSOLETE → both beads `closed`; DEFERRED-NEEDS-HUMAN → bead `in_progress` + label)
- [ ] If CLOSED-WITH-FIX: `git log --oneline $PRE_HEAD..$POST_HEAD` shows exactly ONE commit with `{BEAD_ID}` in the message; `git diff $PRE_HEAD $POST_HEAD --name-only` is a subset of `TOUCHED_FILES`
- [ ] If CLOSED-WITH-FIX: regression test was run post-change and passed
- [ ] If CLOSED-OBSOLETE: `$POST_HEAD == $PRE_HEAD` (no new commit) AND `Pre-change verdict: already-PASS` is in the log entry
- [ ] If DEFERRED-NEEDS-HUMAN: bead carries `phase13-needs-human-review` label AND a comment with both failure traces; `git diff $PRE_HEAD HEAD -- "${TOUCHED_FILES[@]}"` is empty (source successfully reverted)
- [ ] `phase13_remediation_log.md` got exactly one new entry with the correct Outcome value

## Failure modes to watch for

- **Scope creep**: subagent edits files outside the bead's declared scope. Caught by reviewing the commit diff against the bead's `files` field.
- **Closed bead without test passing**: subagent closes the bead before running post-change gates. Caught by orchestrator gate above.
- **Reverting another agent's work**: the subagent must use `git restore <specific-files-it-touched>`, NEVER `git checkout -- .` or `git restore .`.
- **Cycle hidden by close**: subagent encounters a dep cycle and closes anyway. Caught by `br dep cycles` post-Phase-13 check.

## Coordination

Reservation: `path://{SOURCE_PATH}/<files-from-this-bead>` exclusive, TTL 1h, reason `{BEAD_ID}`.
Mail thread: `ub-exorcism-{RUN_ID}-phase13-{BEAD_ID}`.
On completion: release reservations explicitly. The orchestrator does NOT renew them — Phase 13 is bead-scoped.
