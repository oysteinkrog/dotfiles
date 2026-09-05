# Subagent Prompts

Verbatim prompt scripts for each subagent, organized by phase. The main agent injects `<project>`, `<workspace>`, `<bundle>`, `<run-id>` etc. before spawning.

---

## Phase 0.5 — `cass-miner.md` (optional)

```
You are mining prior agent sessions for context relevant to this repo cleanup.

Run:
  cass search "<repo-basename>" --robot --limit 30 --fields minimal --days 180
  cass search "cleanup <repo-basename>" --robot --limit 10 --fields minimal --days 180

For any hit that mentions:
- a previously-failed cleanup attempt
- a known protected file ("don't move X, it's referenced by Y")
- a tracked secret remediation
- a deferred refactor that touched root-level files

— extract the lesson into <workspace>/cass_findings.md.

Output a short summary to the main agent: "Found N relevant prior sessions:
[list of takeaways]" or "No relevant prior sessions found."

DO NOT modify any project files. This is read-only research.
```

---

## Phase 1 — `project-profiler.md`

```
You are profiling <project> to detect its archetype, build commands, and protected globs.

First read ALL of the AGENTS.md file (or AGENT.md, CLAUDE.md, .cursor/rules/*,
.github/copilot-instructions.md — whatever the project uses) and the README.md
file super carefully and understand ALL of both!

Then use your code investigation agent mode to fully understand the code, technical
architecture, and purpose of the project.

Detect:
1. Primary branch — `git symbolic-ref refs/remotes/origin/HEAD` first, then
   `git config init.defaultBranch`, then a heuristic. Never assume "main".
2. Repo archetype — match against REPO-ARCHETYPES.md catalogue:
   single-rust-crate, polyglot-monorepo, claude-skill-repo, nextjs-saas,
   python-package, go-cli, mixed-rust-and-frontend, unknown.
3. Test command, typecheck command, lint command, build command, formatter.
4. CI gates — UBS, dcg, pre-commit hooks.
5. Existing destination dirs — docs/, docs/planning/, docs/progress/, scripts/, tools/.
6. Protected globs — seed from archetype + AGENTS.md/README mentions of
   "intentionally tracked" files.
7. Branch synonyms — does the repo push main → master?

Write all of this to <workspace>/project_profile.json. Format:
{
  "primary_branch": "main",
  "archetype": "polyglot-monorepo",
  "test_command": "cargo test --workspace",
  "typecheck_command": "cargo check --workspace",
  "lint_command": "cargo clippy --workspace -- -D warnings",
  "build_command": "cargo build --workspace --release",
  "formatter": "cargo fmt",
  "ci_gates": ["ubs", "dcg"],
  "existing_dest_dirs": ["docs", "docs/planning", "scripts"],
  "protected_globs": ["Cargo.toml", "Cargo.lock", "src/**", ...],
  "branch_synonyms": ["master"]
}

Then post a one-paragraph summary to the user that confirms the detected archetype
and asks for any corrections.
```

---

## Phase 2 — `inventory-agent.md`

```
You are building the candidate inventory for <project>.

Steps:
1. Run scripts/inventory-candidates.sh <project> > <workspace>/candidates.tsv
2. Verify every candidate has at least one smell-tag.
3. Build candidates_grouped.md grouping by smell category.
4. Build reference_graph.json by reading reference_graph.json from inventory-candidates.sh
   OR running a fresh comprehensive grep across:
   *.rs, *.toml, *.sh, *.py, *.md, *.json, *.yml, *.yaml, *.go, *.js, *.ts,
   *.tsx, *.html, Makefile, Dockerfile, *.lock (when in scope)
   Excludes: .git/, node_modules/, target/, dist/, build/, .venv/, __pycache__/, .next/

For each candidate, record inbound_refs as a list of {ref_path, line, ref_form,
rewrite_eligibility} objects. Use FILE-SMELLS.md and REPO-ARCHETYPES.md for
classifying smell tags and protected globs.

DO NOT classify yet (no verdicts). DO NOT modify any project files.

Output a short summary: "Found N candidates across M smell categories: ..."
```

---

## Phase 2.5 — `leak-scanner.md`

```
You are scanning for committed secrets in <project>. Phase 2.5 is non-negotiable
and must run on every invocation.

Steps:
1. Read <workspace>/candidates.tsv.
2. For each candidate, apply secret-smell rules (FILE-SMELLS.md § Secret leakage):
   - Filename match: signing-*.key, *.pem, id_rsa*, *.token, *credentials*.json,
     .env (without .example/.template), etc.
   - Content fingerprint (only on filename hits): 32/64-byte raw, BEGIN PRIVATE KEY,
     known prefix patterns (xoxb-, sk-, ghp_, AKIA[A-Z]{16}, AIza[A-Za-z0-9_-]{35}).
3. For each suspect, capture provenance:
   git log --oneline --all --diff-filter=A -- <path>     # introducing commit
   git rev-parse origin/<branch> 2>/dev/null              # was it pushed?

Output:
- <workspace>/secret_findings.tsv with columns: path, smell, content_hash,
  introduced_in_sha, last_touched_at, pushed_to_origin, exposure_window_days

If ANY entry has a real-secret hit (filename + content fingerprint match):
- HALT the routine cleanup flow.
- Surface the finding with full context to the user.
- Switch to INCIDENT-PLAYBOOK.md § Secret Leak.

If only filename-only suspects (e.g., 0-byte placeholder, .pub without .key):
- Tag as `secret-suspect` smell.
- Continue to Phase 3 with deferred user-confirm at Phase 5.
```

---

## Phase 3 — `bundle-builder.md`

```
You are building the recovery bundle for <project>.

Steps (per BUNDLE-FORMAT-SPEC.md):
1. Create <bundle> directory: <project>/.repo_janitor_workspace/recovery-bundle-<DATE>/
   mkdir -p <bundle>/{meta,working-tree-copies}
2. For every row in <workspace>/candidates.tsv:
   - Copy <project>/<path> → <bundle>/working-tree-copies/<path> (cp -p)
   - Smudge LFS if applicable
   - Write <bundle>/meta/<id>.txt with provenance
3. Write <bundle>/index.tsv with full schema (see BUNDLE-FORMAT-SPEC.md).
4. Copy <project>/.gitignore → <bundle>/gitignore-before.txt
5. Copy <workspace>/reference_graph.json → <bundle>/reference-graph.json
6. Write <bundle>/README.md from the auto-generated template.
7. Update backup ref:
   git -C <project> update-ref refs/repo-janitor-backup/<DATE>-pre-cleanup HEAD
8. Run scripts/verify-bundle.sh — must report 0 mismatches.

If any verification mismatch: HALT the run. Investigate.

Output: bundle path + verification log summary.
```

---

## Phase 4 — `triage-worker.md` (one per batch)

```
You are triaging candidates batch_<NNN> from <workspace>/candidates.tsv.

For each candidate in your assigned batch (typically rows N to N+29):

1. CLASSIFY-PURPOSE — read <bundle>/working-tree-copies/<path>; determine
   purpose (source / fixture / artifact / plan / scratch / log / db / config).
2. REFERENCE-GREP — read reference_graph.json[<id>].inbound_refs; if non-empty,
   bias toward keep-in-place or surface-to-user.
3. LOCATE-PROPER-HOME — for `move` candidates, propose a destination from the
   TRIAGE-RUBRIC.md heuristic table.
4. ASSESS-VALUE — does this file have unique content not derivable from
   elsewhere? Plan docs YES; auto-generated reports usually NO.
5. VERDICT — apply the TRIAGE-RUBRIC.md decision flow. Output one of:
   delete-and-gitignore, delete-no-gitignore, gitignore-only, move,
   keep-in-place, protected, surface-to-user.
6. CONFIDENCE — [0, 1]. <0.7 forces surface-to-user.
7. EVIDENCE — compact string the user can scan; e.g.:
   "smell=skill-output;refs=0"
   "smell=plan-doc;refs=2:README.md,scripts/build.sh"

Write one row per candidate to <workspace>/triage/batch_<NNN>.tsv with columns:
id, verdict, confidence, evidence, proposed_dest, gitignore_pattern.

DO NOT modify any project files. DO NOT run any destructive command.
DO NOT operate outside your assigned batch range.
```

---

## Phase 4 (Comprehensive only) — `archaeologist.md`

```
You are doing forensic intent reconstruction for "looks important but mislocated"
candidates that confused the triage workers (rows where verdict=surface-to-user
AND confidence in [0.5, 0.7]).

For each such candidate:
1. Read the file's full content + every inbound reference's surrounding context.
2. Run `git log --follow -- <path>` to see the file's history.
3. Run `git log --grep "<basename>" --oneline` to see references in commit
   messages.
4. Read AGENTS.md and README.md for any mention of the file's purpose.
5. Synthesize: what was this file FOR when it was committed? Has its purpose
   been fulfilled by something else now?

Output a per-candidate forensic report at
<workspace>/forensics/<id>_report.md with:
- File purpose hypothesis
- Recommended verdict (which the triage merger may override)
- Confidence in the hypothesis
- Risks of getting it wrong

Output to main agent: "Forensic reports filed for N candidates: <id list>"
```

---

## Phase 4 (Comprehensive only) — `triangulator.md`

```
You are doing multi-stance verification of borderline triage rows.

If /multi-model-triangulation skill is available: invoke it, passing the borderline
rows from triage.tsv for cross-model verification.

Otherwise, run 3 same-session re-classifications with different stances:
- Stance A (literal): trust the smell tags; verdict by rules only.
- Stance B (skeptical): assume the smell tags are wrong; force a content-based
  re-classification.
- Stance C (forensic): treat each candidate as if it might be a hidden test fixture
  or load-bearing config.

For rows where stances disagree on verdict, flag for surface-to-user.

Output to <workspace>/triangulation_results.tsv with columns:
id, verdict_A, verdict_B, verdict_C, agreement, recommended_verdict.
```

---

## Phase 5 — `triage-merger.md`

```
You are merging the per-batch triage tsvs and presenting a categorized plan
to the user.

Steps:
1. Concatenate all <workspace>/triage/batch_*.tsv → <workspace>/triage.tsv
   (deduplicate by id; per-id rows should be unique).
2. Apply user_overrides.tsv if it exists from a previous interrupted run.
3. Group rows by category (the cat-letter pattern from WORKED-EXAMPLES.md):
   - A. KEEP IN ROOT — verdict in {keep-in-place, protected}
   - B. MOVE to docs/planning/ — smell in {planning-doc, multi-llm-plan-cluster, ...}
   - C. MOVE to docs/contracts/ — when applicable; flag DEFERRED if reference
        count >= 10 with hardcoded paths
   - D. MOVE to docs/progress/ — smell == progress-report
   - E. MOVE to scripts/visualization/ — smell == visualization-script
   - F. MOVE to scripts/ — smell == deploy-script or other
   - G. DELETE — verdict in {delete-and-gitignore, delete-no-gitignore}
   - H. .gitignore additions
   - MANUAL — verdict == surface-to-user
4. For each MOVE category, build move_plan.md with full (src → dst, refs to
   rewrite, refs to surface).
5. For DELETE category, build delete_plan.md grouped by glob.
6. For .gitignore, build gitignore_plan.md with SHADOWING-AUDIT for each rule.
7. Output triage_decision.md with the categorized plan formatted as in
   WORKED-EXAMPLES.md.

Present triage_decision.md to the user verbatim. Wait for explicit "go" /
"proceed" / "approved" / "sounds good".

If user requests an override: capture in user_overrides.tsv and apply to
triage.tsv. If overrides change >5 verdicts, re-ask for confirmation.
```

---

## Phase 6 — `move-applier.md`

```
You are applying moves for category <X> in move_plan.md (one category per
spawn invocation).

For each move (src → dst) in this category, in plan order:

1. Run scripts/snapshot-tree.sh phase6 → <workspace>/wt_phase6_<seq>.txt
2. Re-run REFERENCE-GREP on <src> — if drift, surface and ask.
3. mkdir -p <dst-parent-dir> if it doesn't exist.
4. git mv <src> <dst>
5. For each reference rewrite in reference_graph.json[<id>].inbound_refs:
   - Read the file via Read tool to confirm context.
   - Use Edit tool with the documented old_string / new_string.
   - Append (file, line, old → new, ts) to reference_rewrite_log.tsv.
   - Skip refs marked rewrite_eligibility=surface-only — surface them and ask.
6. Re-grep the repo for any stale references to <src>. If found, fix or surface.

After all moves in this category:
7. Run quality gates from project_profile.json. All must pass (or user-approved
   pre-existing failure).
8. git add -A
9. git commit with focused message naming the category, count, destination,
   and rationale (see PHASES.md § Phase 6).

If apply-check fails: do NOT force. Surface to user with full context.
Mark conflicts in apply_log.tsv.

DO NOT use sed/awk/regex transforms for reference rewrites. Edit tool only.
```

---

## Phase 6 / 9 — `reference-checker.md`

```
You are verifying that no broken references survive the move category just
applied.

For each (path, new_dest) just moved:
1. Run a comprehensive grep across the repo for the basename and the original
   relative path.
2. For each hit that is NOT the moved file's new location and NOT in the bundle
   directory:
   - If it's in a moved-and-rewritten file: confirm rewrite landed.
   - If it's in a not-yet-rewritten file: surface to main agent for an
     immediate Edit-tool fix.
3. Run the project's `cargo check` (or equivalent typecheck command).
4. If anything fails: surface with full context.

Output: surveys clean OR list of surviving references with file:line.
```

---

## Phase 7 — `delete-applier.md`

```
You are applying deletes for the user-authorized plan in delete_plan.md.

Pre-condition: cleanup_authorization.txt must already contain the user's
verbatim authorization for the delete plan. If not present, refuse to proceed
and ask the cleanup-conductor to re-collect it.

For each delete batch (grouped by glob in delete_plan.md):

1. Run scripts/snapshot-tree.sh phase7 → wt_phase7_<seq>.txt.
2. Pre-flight: confirm each path is still tracked. Concurrent agents may have
   removed one already.
3. git rm <paths-in-batch>
4. Run quality gates. All must pass.
5. git add -A
6. git commit with focused message ("chore: remove <category-name>" + body
   explaining each file's role + why it shouldn't have been tracked).

Append to apply_log.tsv per delete:
  id, ref, new_commit_sha, gates_status, duration_s

NEVER run git stash clear. NEVER delete the bundle. NEVER delete
refs/repo-janitor-backup/*.
```

---

## Phase 7 / 8 — `cleanup-conductor.md`

```
You are gating the destructive phases (7 and 8).

Build a verbatim authorization request from delete_plan.md / gitignore_plan.md
that lists every command in the order it will run:

  I'm about to run the following destructive commands in this order:

    [Phase 7]
    git rm <files-batch-1>
    git rm <files-batch-2>
    ...

    [Phase 8]
    git rm --cached <previously-tracked-files-now-shadowed-by-new-ignore-rules>
    # then append to .gitignore:
    <pattern-1>
    <pattern-2>
    ...

  The bundle at <bundle> stays intact; backup ref refs/repo-janitor-backup/<DATE>
  stays intact.

  To proceed, paste this verbatim:
    yes I understand and want to delete N files and add M .gitignore rules
    per the plan above

Wait for that exact text. If the user types anything different, refuse and
re-ask.

Record the exact user text + UTC timestamp in cleanup_authorization.txt.
```

---

## Phase 8 — `gitignore-author.md`

```
You are applying the `.gitignore` plan.

Pre-condition: cleanup_authorization.txt has the user's verbatim auth for the
gitignore plan (or the plan adds NO patterns that shadow tracked files).

Steps:
1. Read gitignore_plan.md.
2. For each proposed addition, run final SHADOWING-AUDIT:
   git ls-files <pattern>
3. If any pattern shadows a tracked file AND the auth doesn't cover it: refuse
   and re-ask the cleanup-conductor.
4. If user authorized "untrack and ignore" for shadowed files: pair the
   addition with `git rm --cached <files>` in the same commit.
5. Edit .gitignore to add the proposed patterns, preserving existing thematic
   grouping. Group new additions thematically too.
6. git add .gitignore (+ any --cached removals)
7. Run quality gates.
8. git commit with focused message (see GITIGNORE-CRAFT.md § "A clean
   .gitignore reads top-down").
9. Verify each new pattern fires:
   git check-ignore -v <fake-test-path-matching-pattern>
```

---

## Phase 9 — `fresh-eyes.md`

```
You are doing fresh-eyes verification of the cleanup. Run THREE review prompts
across at least 2 rounds (3 for Comprehensive variant):

PROMPT 1: "Carefully read over all of the new file moves, deletes, .gitignore
changes, and reference rewrites you (and your fellow agents) just made with
'fresh eyes' looking super carefully for any obvious bugs, errors, broken
references, broken builds, missed cleanup. Carefully fix anything you uncover."

PROMPT 2: "Sort of randomly explore the code files in this project, choosing
files to deeply investigate and tracing whether any of them reference paths
that may have been moved or deleted in this run. Once you understand the
purpose of the file in the larger context, do a super careful, methodical, and
critical check with 'fresh eyes' to find any obvious broken-reference bugs,
silent test fixture losses, or build-system effects from the cleanup."

PROMPT 3: "Turn your attention to reviewing the cleanup decisions made by your
fellow agents and checking for any false-positive deletes (a deleted file may
have been a referenced test fixture), bad moves (a moved file's new location
may not be findable from a build script with hardcoded paths), or .gitignore
additions that silently mask important files. Diagnose underlying root causes
using first-principle analysis. Don't restrict yourself to the latest commits
— cast a wider net and go super deep."

Between rounds, run the project's full quality gate suite from
project_profile.json. All must pass.

TERMINATION: Two consecutive full rounds (all three prompts) produce only
trivial findings (typo, wording polish) AND test + typecheck + lint + build +
UBS all green.

Log each round + outcome to fresh_eyes_log.md.
```

---

## Phase 10 — `handoff-reporter.md`

```
You are emitting the final handoff report for the cleanup run.

Steps:
1. Read all logs: apply_log.tsv, reference_rewrite_log.tsv,
   cleanup_authorization.txt, fresh_eyes_log.md, secret_findings.tsv.
2. Run scripts/polish-bar-check.sh; capture results.
3. Build handoff_report.md per the template (see PHASES.md § Phase 10):
   - Counts (initial, final, per-verdict)
   - Per-commit summary table
   - Skipped categories with rationale
   - Recovery recipes (per-mutation)
   - Push commands (and synonym pushes if applicable)
   - Bundle lifecycle reminder
4. File a beads issue:
   br create --title "repo janitor pass on <project> (<N> candidates)" --type=task --priority=4
5. Reply in the Agent Mail thread with a final completion message.
6. If bv is available: bv --robot-triage to surface follow-ups.
7. Print the push command(s) to the user.

DO NOT push. DO NOT delete the bundle.
```

---

## Mid-run — `incident-responder.md`

```
You are responding to an incident detected mid-run. The triggering condition
will be passed by the main agent as the prompt suffix.

For the most common incidents, follow INCIDENT-PLAYBOOK.md:
- Secret-leak detected → § Secret Leak Recovery
- Working-tree mid-run conflict → § Working-tree mid-run conflict
- git mv collision → § A `git mv` collision
- Reference rewrite breaks the build → § A reference rewrite breaks the build
- .gitignore shadowing surprise → § A `.gitignore` change shadows tracked files
- Bundle byte-equality drift → § A bundle's working-tree-copy doesn't match

For unusual incidents not in the playbook:
1. Snapshot the current state to <workspace>/incident_<ts>.md.
2. Surface to the user with full context.
3. Halt the run. Wait for instructions.

DO NOT take any destructive action without user authorization.
```

---

## Phase 11 (optional) — `idea-wizard-reviewer.md`

```
You are doing a user-lens review of the just-completed cleanup run.

Read everything in <workspace>/ and the handoff_report.md. Then answer:

1. Did this cleanup save the user time? Where?
2. Where did it surface friction? (verbatim authorization too noisy?
   triage decision table too long? gates too slow?)
3. What patterns recurred across multiple categories (suggesting an operator
   or rule that should be promoted)?
4. What surprised the user (per their override comments in user_overrides.tsv)?
5. What did the agent miss (per fresh_eyes_log.md round 2/3 findings)?

Output: skill_feedback.md with concrete suggestions for SKILL.md / references/
improvements. Optionally: open beads issues against this skill itself for the
top 3 suggestions.
```
