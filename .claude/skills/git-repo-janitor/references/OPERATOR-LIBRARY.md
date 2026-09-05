# Operator Library — Cognitive Moves

Each operator is a reusable verb with explicit triggers, prompt module, exit criteria, and failure modes. These are *what to think about*, not just *what to do*. Adapted from [`operationalizing-expertise`](../../operationalizing-expertise/SKILL.md) Track A and from [`git-stash-janitor`'s OPERATOR-LIBRARY](../../git-stash-janitor/references/OPERATOR-LIBRARY.md).

**Categorization** (5 lifecycle categories: Discovery → Classification → Hygiene → Execution → Recovery):

| Category | Operators |
|----------|-----------|
| **Discovery** | ★ INVENTORY, 🔗 REFERENCE-GREP, 🧮 PATTERN-EXTRACT, ⊞ COVERAGE-MATRIX, ↻ RE-FINGERPRINT |
| **Classification** | 🔍 CLASSIFY-PURPOSE, 💎 ASSESS-VALUE, 📍 LOCATE-PROPER-HOME, ⌖ FALSE-POSITIVE-CHECK, ⩚ VULNERABLE-FILE-FILTER, ⟳ CROSS-ARCHETYPE-CHECK |
| **Hygiene** | 🛡 SHADOWING-AUDIT, ↺ WORKING-TREE-DRIFT, ◑ VERIFY-LIVE, ⊠ NEGATIVE-DECISION |
| **Execution** | ⬡ BUNDLE, ✦ MOVE-WITH-RENAME, ⊟ REMOVE-WITH-RM, ↪ REWRITE-REFERENCES, ⚠ CONFIRM, ⊕ GATE-RUN |
| **Recovery** | ⊛ LAYERED-DEFENSE, ⊙ PROVENANCE-WRAP, ⧗ TIME-BOXED-PIVOT, ✸ PIN-THE-CONTRACT, ⌘ HANDOFF |

---

## ★ INVENTORY

**Trigger:** Phase 2.

**Question:** "What's the complete list of files in this repo that match at least one junk-smell rule? Capture path, blob SHA, size, mtime, smell-tags into one TSV that becomes the source of truth."

**Prompt module:**
> Walk every tracked file via `git ls-files`. For each, run the filename rules from FILE-SMELLS.md and content fingerprints (only on files matching ≥1 filename rule, to keep it cheap). Emit one row per candidate to candidates.tsv with `id, blob_sha, path_at_HEAD, size_bytes, mtime_iso, smell_tags, first_committed_in`. Group by smell category in candidates_grouped.md so the user can see the shape of the cleanup before any verdict is computed. **Do not** classify yet — that's Phase 4. Inventory is just enumeration.

**Exit criteria:** Every candidate has exactly one row; smell-tags column is non-empty for every row.

**Failure modes:**
- Submodule subtree pollution: skip `.gitmodules` paths.
- Files with non-UTF-8 names: stringify safely, don't error.
- Repo with 100k tracked files: limit candidate detection to top-level + known-junky subdirs first; only deepen on user request.

**Quote bank:** "An inventory you don't trust is worse than no inventory."

---

## 🔍 CLASSIFY-PURPOSE

**Trigger:** Phase 4, per-candidate.

**Question:** "What is this file *for*? Source code, test fixture, build artifact, ephemeral output, plan document, scratch tool, runtime data?"

**Prompt module:**
> Read the bundle's working-tree-copy of the candidate. For text files, scan first 50 lines + filename + last-commit-message. For binary files, run `file <path>` to confirm magic bytes. Check the file size — 0-byte files are stubs; >100KB markdown is almost always a planning doc; <1KB shell scripts are often scratch. Output: a single-line purpose label (e.g., "ephemeral skill output", "canonical architecture spec", "abandoned scratch helper").

**Exit criteria:** Each candidate has a `purpose` field that informs the verdict choice.

**Failure modes:**
- Binary file with no magic bytes (e.g., custom format): label as `unknown-binary`, force surface-to-user.
- Multi-purpose file (e.g., `README.md` at root that ALSO has 5000 lines of architecture): purpose = "documentation"; verdict = `keep-in-place` (root-level README is archetype-protected).

**Quote bank:** "Classification by name is gossip; classification by content is evidence."

---

## 📍 LOCATE-PROPER-HOME

**Trigger:** Phase 4, when verdict is `move`.

**Question:** "Where should this file actually live?"

**Prompt module:**
> Check `project_profile.json` for existing destination dirs (`docs/`, `docs/planning/`, `docs/progress/`, `scripts/`, `tests/`, `tools/`). Match against the destination heuristic table (TRIAGE-RUBRIC.md § LOCATE-PROPER-HOME). Prefer existing dirs over new ones. If a new dir is needed, propose its name explicitly so the user can rename before Phase 6.

**Exit criteria:** Each `move` candidate has a `proposed_dest` path that's plausible given the archetype.

**Failure modes:**
- Multiple plausible homes (e.g., `RECOVERY_RUNBOOK.md` could go to `docs/operations/` OR `docs/`): pick the more-specific one; surface alternatives in Phase 5 plan.
- Destination dir already has a file with the same basename: surface as a collision; user picks the resolution.

**Quote bank:** "A move that breaks no references is a move that wasn't really needed; the right move makes the future structure obvious."

---

## 💎 ASSESS-VALUE

**Trigger:** Phase 4, after CLASSIFY-PURPOSE.

**Question:** "Does this file have unique content not derivable from elsewhere?"

**Prompt module:**
> For text files: is the content unique design intent (worth preserving) or transient state (deletable)? Plan documents YES; auto-generated reports usually NO; binary DBs almost never. For binaries: is it reproducible from source via the build system? If yes → delete; if no AND it's referenced by tests/build → keep.

**Exit criteria:** A delete-vs-move decision can be justified per-candidate.

**Failure modes:**
- A "report" file is actually unique (it captured a one-time benchmark run with no reproducible source data): mark `move` to `docs/benchmarks/` rather than delete.
- A binary "build artifact" is actually a hand-curated WASM file: archetype-protected; keep.

**Quote bank:** "Plan docs explain WHY; reports document WHAT happened. The first is precious; the second is usually replaceable."

---

## 🔗 REFERENCE-GREP

**Trigger:** Phase 4 every candidate; Phase 6 again before each move; Phase 7 again before each delete.

**Question:** "Does any other file in this repo reference this candidate's basename or relative path?"

**Prompt module:**
> Run a comprehensive multi-extension grep across the repo for the candidate's basename + relative path. Excludes: `.git/`, `node_modules/`, `target/`, `dist/`, `build/`, `.venv/`, `__pycache__/`, `.next/`, `docs/` (if the candidate is in `docs/`, to avoid self-reference). Includes: `*.rs`, `*.toml`, `*.sh`, `*.py`, `*.md`, `*.json`, `*.yml`, `*.yaml`, `*.go`, `*.js`, `*.ts`, `*.tsx`, `*.html`, `Makefile`, `Dockerfile`, `*.lock` (when the lock file is in scope, e.g., `Cargo.lock`). For each match, capture file:line. Surface to the user any match that's NOT in another candidate (refs from candidates being deleted in the same batch don't block the delete).

**Exit criteria:** Every candidate has an `inbound_refs` list (possibly empty); any non-empty list is surfaced to user.

**Failure modes:**
- False positive: `test_ptr` matches `test_ptrmap_*` because `_` is a word character. Manual context-check resolves this — surface the line content, not just the path.
- The reference is in code that's been commented out (e.g., `// see X.md` in a `//!` doc string): still surface; don't auto-decide that doc-comments are safe to leave stale.
- The reference is in another file that's also being deleted: ignore for blocking purposes, but log it so the user sees the dependency.

**Quote bank:** "A grep without context is a snitch with no follow-through; surface the line, not just the file."

---

## 🧮 PATTERN-EXTRACT

**Trigger:** Phase 5, plan composition.

**Question:** "When 5+ candidates share a glob, generate a single `.gitignore` rule + a single batched delete commit instead of N separate commits."

**Prompt module:**
> Group candidates by smell-tag and by extension. If ≥5 share a directory + extension (e.g., 5 `progress_bd-*.md` at root), propose a single glob (`/progress_bd-*.md`) for `.gitignore` AND a single batched `git rm` commit. Don't over-aggregate: if 5 share a tag but live in different dirs, still glob them carefully (`progress_bd-*.md` at root vs. `subdir/progress_bd-*.md`).

**Exit criteria:** The Phase 5 delete plan has fewer commits than candidates when batching is sensible.

**Failure modes:**
- Glob is too broad: `*.json` matches `package.json`. SHADOWING-AUDIT catches this.
- Glob is too narrow: `progress_bd-12.md` matches only one — defeats the purpose.

**Quote bank:** "A `.gitignore` rule replaces a Phase 7 delete; a Phase 7 delete replaces a `.gitignore` rule. Prefer the rule when the pattern will recur."

---

## 🛡 SHADOWING-AUDIT

**Trigger:** Phase 5 (when proposing the gitignore plan); Phase 8 (before the actual `.gitignore` commit).

**Question:** "Does this proposed `.gitignore` line shadow any currently-tracked file?"

**Prompt module:**
> For each proposed addition, run `git ls-files <pattern>`. Any non-empty result means the pattern would mask future visibility of those tracked files. Surface every shadowed file in the gitignore_plan.md. Two outcomes:
> 1. The shadowing is intended — the user wants to *both* untrack AND ignore. Pair the addition with `git rm --cached <files>` in the same commit.
> 2. The shadowing is unintended — narrow the glob OR add a negation rule (`!path/to/specific/file`).
>
> Run `git check-ignore -v <fake-test-path>` after the commit to verify the new pattern fires correctly.

**Exit criteria:** No surprise tracked-file shadowing in the final `.gitignore`.

**Failure modes:**
- `*.json` ignores `package.json`. Fix: `!/package.json` exception OR narrow to `temp_*.json`.
- `temp_*` ignores `temp_module.py` (legitimate code file). Fix: surface to user; user picks narrower glob.

**Quote bank:** "An ignore rule that hides a tracked file is silent sabotage."

---

## ⬡ BUNDLE

**Trigger:** Phase 3 — the irreversibility gate.

**Question:** "Have I captured a byte-identical, hash-verified copy of every candidate before any destructive operation?"

**Prompt module:**
> Copy every candidate's working-tree content to `<bundle>/working-tree-copies/<path>`. Preserve mtime/perms (`cp -p`). Compute SHA-256 of both source and copy; compare. Any mismatch = HALT. Smudge LFS pointers explicitly. Snapshot `.gitignore` to `<bundle>/gitignore-before.txt`. Snapshot `reference_graph.json` to `<bundle>/reference-graph.json`. Update backup ref `refs/repo-janitor-backup/<DATE>-pre-cleanup`.

**Exit criteria:** `bundle_verification.log` shows zero mismatches; backup ref exists.

**Failure modes:**
- File changed mid-Phase-3 (concurrent agent): re-run from Phase 2.
- LFS pointer that wasn't smudged: bundle copy is the pointer text, not the blob. Verify by checking file size — if it's <200 bytes and the original was MB, it's an unsmudged pointer.

**Quote bank:** "The recovery story has to outlive the run. If you can't undo it byte-for-byte, you can't run it."

---

## ⚠ CONFIRM

**Trigger:** Phases 5, 7, 8.

**Question:** "Has the user typed the literal authorization phrase that quotes the destructive command(s)?"

**Prompt module:**
> Restate the exact commands that will run. Wait for the user to paste a verbatim authorization phrase that includes the literal commands (or a phrase the skill explicitly defined). Refuse if the user types anything different. Record the exact text + UTC timestamp in `cleanup_authorization.txt`.

**Exit criteria:** `cleanup_authorization.txt` contains the verbatim user text before any irreversible action runs.

**Failure modes:**
- User types "yes go ahead" without the literal phrase: refuse; re-ask with the exact phrase.
- User skips approval entirely (e.g., bot-mode): the skill never proceeds; halt and ask.

**Quote bank:** "Per AGENTS.md: 'When running any approved destructive command, record the exact user text that authorized it. If that record is absent, the operation did not happen.'"

---

## ✦ MOVE-WITH-RENAME

**Trigger:** Phase 6, per move.

**Question:** "Will git's rename detection survive this move?"

**Prompt module:**
> Always `git mv <src> <dest>` (never `mv <src> <dest>` + `git add -A`). Verify the move appeared as a `R` line in `git status -s`, not as `D` + `??`. If `git mv` fails because `<dest>` exists, escalate per INCIDENT-PLAYBOOK § "git mv collision".

**Exit criteria:** `git status -s` shows `R` (rename) for every move.

**Failure modes:**
- Cross-filesystem move (rare): `git mv` may degrade to copy+delete. If rename detection threshold is met, history still follows.
- File renamed AND content changed substantially in the same commit: rename detection threshold may be missed. Solution: split the commit — move first, edit second.

**Quote bank:** "`git mv` is a contract: 'this is the same file at a new path'. `mv` + `git add` is two separate facts that git has to guess about."

---

## ↪ REWRITE-REFERENCES

**Trigger:** Phase 6, after every move.

**Question:** "Have all references to the moved path been updated, and was every update done via the Edit tool with explicit old/new pairs?"

**Prompt module:**
> Read `reference_rewrite_log.tsv` (built from `reference_graph.json` for the moved path). For each (file, line, old_string) row:
> 1. Read the file via the Read tool to confirm context.
> 2. Use the Edit tool with old_string = the literal old reference (with surrounding context if needed for uniqueness) and new_string = the new path reference.
> 3. Append `(file, line, old → new, ts)` to `reference_rewrite_log.tsv`.
>
> NEVER use `sed -i`, `awk`, regex transforms, or any script-based change (per AGENTS.md "No Script-Based Changes"). Brittle multi-occurrence files break.

**Exit criteria:** Every reference from the graph has either been rewritten (logged) or surfaced to the user as un-rewritable.

**Failure modes:**
- Reference uses an alias / re-export / Python `__init__` indirection: surface to user; never auto-rewrite imports without lexical match.
- Reference is in a comment that should also be updated: do it. Comments rot; rewriting them is part of the cleanup.
- Multi-line reference (e.g., a list of paths in a Rust array literal across 5 lines): use Edit tool with enough context to make the old_string unique.

**Quote bank:** "A reference rewrite via sed is a regex playing pretend; via the Edit tool it's a contract."

---

## ⊟ REMOVE-WITH-RM

**Trigger:** Phase 7, per delete batch.

**Question:** "Is this delete using `git rm` (not filesystem `rm`), and is the path still tracked at the moment of the call?"

**Prompt module:**
> `git rm <paths>` — never `rm`, never `find -delete`. Verify each path is still tracked first (`git ls-files <path>`); concurrent agents may have already removed it. If `git rm` reports "did not match any files", check `git ls-files` and `git status` to confirm — then mark `applied-by-other-agent` and continue.
>
> For "untrack but keep local copy" cases: `git rm --cached <path>` — the file stays on disk but is no longer tracked. Pair with a `.gitignore` add in the same commit (Phase 8).

**Exit criteria:** Every Phase-7 row has either `new_commit_sha` or `applied-by-other-agent` in `apply_log.tsv`.

**Failure modes:**
- `git rm` blocked because the file has uncommitted local changes from another agent: don't force; surface to user.
- Filename with spaces or unicode: quote properly (`git rm 'file with spaces.md'`).

**Quote bank:** "`git rm` writes a deletion to git history; `rm` writes a regret to the future."

---

## ⊕ GATE-RUN

**Trigger:** Phase 6, 7, 8 — after every commit.

**Question:** "Do the project's actual quality gates pass on this commit?"

**Prompt module:**
> Read `project_profile.json` for `test_command`, `typecheck_command`, `lint_command`, `build_command`, and UBS availability. Run each. Capture exit codes + tail of output. All must pass; if any fail and the user hasn't pre-approved a known pre-existing failure, halt the phase, surface the error, ask for guidance.

**Exit criteria:** Every commit on the recovery branch has passing gates above it (or a documented user-approved failure).

**Failure modes:**
- A gate is slow (e.g., `cargo test --workspace` takes 5 min): scope it (`cargo check -p <crate>`) for per-commit; full gate runs in Phase 9.
- A gate is flaky: capture the failure, surface it; if the user says "known flake", record it in `apply_log.tsv` and continue.

**Quote bank:** "Gates between commits catch compounding errors before they compound. Gates only at the end catch them after they've made debugging hard."

---

## ↺ WORKING-TREE-DRIFT

**Trigger:** Before each Phase 6 / 7 / 8 mutation.

**Question:** "Has the working tree changed since the last snapshot? If so, are those changes from concurrent agents?"

**Prompt module:**
> Re-snapshot `git status` and `git diff` to `wt_phase<N>.txt`. Compare to the last snapshot. If new modified/untracked paths appeared:
> - Per AGENTS.md "Note for Codex/GPT-5.5": treat them as if you made them.
> - NEVER `git stash`, `git restore`, `git checkout --`, or any other operation that disturbs the agent's work.
> - Continue with your mutation. If your mutation conflicts (e.g., concurrent agent already moved your candidate): mark `applied-by-other-agent` and skip.

**Exit criteria:** Every mutation has a `wt_pre.txt` snapshot recorded for forensic auditability.

**Failure modes:**
- Concurrent agent committed your candidate (it's no longer in the working tree): the candidate is "done" by their action; skip with `applied-by-other-agent`.
- Concurrent agent committed a CHANGE to your candidate (different content than what bundle captured): re-snapshot and re-classify; the smell-tag may have changed.

**Quote bank:** "Concurrent agents are not adversaries; they're you with amnesia."

---

## ⌘ HANDOFF

**Trigger:** Phase 10.

**Question:** "Does the user have everything they need to push, audit, or undo this run?"

**Prompt module:**
> Emit `handoff_report.md` with: counts per verdict, recovery commit SHAs, bundle path, `.gitignore` diff, reference-rewrite log, recovery recipes (per-mutation), push commands (`git push origin <branch>` and synonym pushes if applicable). File a beads issue. Update Agent Mail thread. Run `bv --robot-triage` if available. Tell the user explicitly that the skill never pushes.

**Exit criteria:** `handoff_report.md` exists, fully populated; user has been told what to do next.

**Failure modes:**
- Beads database locked: skip beads issue creation; record `beads_skipped: true` in the report.
- User asks the skill to push: refuse, re-explain the boundary, print the command.

**Quote bank:** "The handoff is not the end of the run; it's the start of the user's next decision."

---

## ↻ RE-FINGERPRINT  (Discovery; Comprehensive variant)

(Glyph note: this operator originally used `⊞` in stash-janitor, but `⊞` is now `COVERAGE-MATRIX` here; the rename to `↻` keeps both visible without collision.)

**Trigger:** Phase 6, between applies.

**Question:** "After the previous move + reference rewrite, do any downstream candidates' verdicts now flip?"

**Prompt module:**
> If candidate A was moved and its reference rewrite touched candidate B's file (e.g., updating `package.json` build script), B's reference graph just changed. Re-run REFERENCE-GREP for any candidate whose file was edited as part of an earlier move's rewrite. If B's inbound-ref count flipped from 0 → 1 or 1 → 0, its verdict may flip too.

**Exit criteria:** Phase 6 is monotonic — verdicts only get safer (more conservative), never more aggressive, mid-phase.

**Failure modes:**
- Cycle of dependencies: A's rewrite changes B's refs; B's rewrite changes A's refs. Resolve sequentially; verdict ties go to `surface-to-user`.

**Quote bank:** "A move's reference rewrites change the very graph you used to plan future moves. Re-fingerprint or be surprised."

---

## Additional operators (introduced in expansion)

### `◑` VERIFY-LIVE  (Hygiene)

**Trigger:** Any time a recommendation depends on volatile git behavior (filter-repo, rename detection threshold, LFS pointer interaction, partial-clone interaction). Phase 1, Phase 2.5 secret scan, harden-secret-leak Step 5.

**Question:** "Have I verified the live tool's behavior on this machine BEFORE making the recommendation?"

**Prompt module:**
> Run `git --version`, capture relevant `git config --get` values, capture `git lfs --version` if applicable, capture `git filter-repo --version` if applicable. Check if any aspect of the recommendation depends on a version-specific behavior. If yes, write a verification log entry per VERIFICATION-FIRST.md § Evidence envelope template. If the live state contradicts the recommendation, halt and surface to user.

**Exit criteria:** `verification_log.md` entry exists for any recommendation that depends on volatile behavior.

**Failure modes:**
- Skipping: recommendation passes "should work" without verification.
- Stale assumption: recommendation cites a behavior that changed in a recent git version.

**Composes with:** ⚠ CONFIRM, ⊞ COVERAGE-MATRIX.

**Quote bank:** §7.1 (volatile git behavior must be verified live), §7.5 (if you can't carry an evidence envelope, halt instead of fabricating).

---

### `⌖` FALSE-POSITIVE-CHECK  (Classification)

**Trigger:** After any REFERENCE-GREP returns ≥1 hit and the smell rule would otherwise auto-classify the candidate as `delete-*` or `move`.

**Question:** "Is this an actual reference, or a substring false positive?"

**Prompt module:**
> For each REFERENCE-GREP hit, read the surrounding line context (3 lines before, 3 after). Distinguish:
> - **True reference**: a deliberate use of the path/basename
> - **False positive**: substring overlap (e.g., `test_ptr` matching `test_ptrmap_*`)
> - **Comment-only**: a doc-comment mentioning the path (treat as low-impact)
> - **Aliased**: a reference via re-export, alias, or string concatenation (treat as high-risk; can't auto-rewrite)
>
> If ≥1 hit is true: flip verdict toward `keep-in-place` or `surface-to-user`.

**Exit criteria:** Every REFERENCE-GREP hit's context is examined; the verdict reflects the genuine refs only.

**Failure modes:**
- Trusting all hits: false-positive substring matches force surface-to-user when they shouldn't, OR
- Dismissing all hits: missing a real reference and breaking the build.

**Composes with:** 🔗 REFERENCE-GREP.

**Quote bank:** §2.4 (a file's importance is not visible from name alone).

**Source:** Apr-27 frankensqlite `test_ptr` matching `test_ptrmap_*` incident (cass).

---

### `⊞` COVERAGE-MATRIX  (Discovery)

**Trigger:** Phase 2.5, after candidate inventory + secret scan. Run once.

**Question:** "Did the skill consider every smell rule against this repo, even rules that didn't fire?"

**Prompt module:**
> For each smell rule in FILE-SMELLS.md, emit a row with status `present | partial | missing | n/a`. Use COVERAGE-MATRIX.md "Should this rule apply?" archetype heuristics to distinguish `missing` (rule should apply but no candidates tagged) from `n/a` (rule doesn't apply to this archetype). For `missing` rows, write a brief investigation note.

**Exit criteria:** `coverage_matrix.md` has one row per smell rule; no blank cells.

**Failure modes:**
- Blank cells (rule was forgotten).
- Lazy `n/a` (every rule marked n/a without checking).
- False `present` (rule fired but with low-quality matches).

**Composes with:** ★ INVENTORY, ⊠ NEGATIVE-DECISION.

**Quote bank:** §7.2 (coverage matrices reveal what the agent didn't consider), §7.3 (a blank cell is a bug, not a default).

**Source:** saas-billing's `phase2_coverage_matrix.md` pattern.

---

### `⊠` NEGATIVE-DECISION  (Hygiene)

**Trigger:** Whenever the agent excludes a smell rule, skips a phase, or defers a category. Throughout the run.

**Question:** "Is this exclusion documented with a rationale a future maintainer could audit?"

**Prompt module:**
> When a smell rule, candidate, or category is skipped, write a row to `negative_decisions.md` with:
> - What was skipped
> - The rationale (rule, user override, archetype default, MEMORY.md policy)
> - When to revisit (specific condition or "never")
>
> Examples:
> - "Cat C TOML moves DEFERRED — refs too pervasive (≥10 hardcoded paths each); revisit when user has time for the larger refactor"
> - "`legacy/` subdir excluded — user MEMORY.md says 'frozen archive'; never revisit (user must override)"

**Exit criteria:** Every silent skip is now documented.

**Failure modes:**
- Silent skip (no record). Future runs don't know what was deferred.
- Stale rationale (the reason no longer applies; the skip persists).

**Composes with:** ⊞ COVERAGE-MATRIX.

**Quote bank:** §2.6 (when references are too pervasive, defer the move).

**Source:** wills's OVERLAY-RESOLVER.md "explicit negative decisions" pattern; Apr-27 frankensqlite Cat-C deferral.

---

### `⩚` VULNERABLE-FILE-FILTER  (Classification)

**Trigger:** Any candidate flagged with `secret-suspect`, `secret-leak`, `referenced-by-tests`, `referenced-by-build`, `archetype-protected`. Phase 4.

**Question:** "Does this candidate have special handling that overrides the generic verdict logic?"

**Prompt module:**
> Some candidates aren't just files — they're *vulnerable* in the sense that the wrong verdict has outsized impact. Treat:
> - Secrets → halt + escalate to `harden-secret-leak`
> - Referenced-by-tests → keep-in-place; surface even if smell rules say delete
> - Archetype-protected → never modify
> - Phantom-deletions → restore-do-not-commit
>
> Apply the special-case verdict BEFORE the generic verdict logic.

**Exit criteria:** Vulnerable files exit Phase 4 with the right special-case verdict.

**Failure modes:**
- Treating a referenced-test fixture as `coverage-output` smell → false-positive delete.
- Missing the secret escalation because the rule didn't fire on the right path component.

**Composes with:** 🔍 CLASSIFY-PURPOSE, 🔗 REFERENCE-GREP.

**Quote bank:** §4.1 (a secret in the working tree halts the cleanup), §10.1 (a phantom-deletion is a restoration request).

**Source:** wills's ⩚ Vulnerable-Beneficiary Filter.

---

### `⟳` CROSS-ARCHETYPE-CHECK  (Classification)

**Trigger:** When the repo matches 2+ archetypes (e.g., a Rust crate inside a Next.js app's `crates/native/`). Phase 1.

**Question:** "Does any sub-tree of this repo have a different archetype than the parent? If so, do they conflict on protected_globs or smell rules?"

**Prompt module:**
> Walk top-level directories. For each, run lightweight archetype detection (presence of Cargo.toml, package.json, etc.). If multiple archetypes appear:
> - Build per-subtree protected_globs.
> - Union the global protected_globs.
> - Surface conflicts (e.g., parent says `*.json` is junk, subtree says `*.json` is required).
> - Decide: parent archetype overrides for top-level files; subtree archetype overrides within its tree.

**Exit criteria:** Final protected_globs reflects all relevant archetypes; no false-positive deletes due to single-archetype thinking.

**Failure modes:**
- Picking one archetype "best fit" and ignoring sub-archetypes.
- Letting a subtree's archetype override parent-level protections.

**Composes with:** 📍 LOCATE-PROPER-HOME (different archetypes → different destination structures).

**Source:** wills's ⟳ Cross-State Domicile.

---

### `⧗` TIME-BOXED-PIVOT  (Recovery)

**Trigger:** Phase 9 (cleanup). Defines a rollback window after the user types verbatim auth.

**Question:** "Until what time can the user cleanly revert this run via `git revert`?"

**Prompt module:**
> Compute the rollback window (default: 30 minutes after the user types verbatim auth, OR until the user pushes to origin, whichever comes first). Surface the window prominently in the handoff:
>
> > "If you change your mind in the next 30 minutes (before pushing), you can revert via:
> >   git revert <range>"
>
> After the window, recovery requires the bundle (Layer 2) — still possible but more work.

**Exit criteria:** Handoff contains an explicit rollback window with revert commands.

**Failure modes:**
- No window: user feels locked in.
- Window too long: implies the skill expects rollback (creates anxiety).

**Composes with:** ⌘ HANDOFF.

**Source:** wills's ☍ Disclaimer Window (the 9-month window for inheritance disclaimers).

---

### `⊛` LAYERED-DEFENSE  (Recovery)

**Trigger:** Every destructive verdict at Phase 5 plan composition.

**Question:** "Which recovery layer would catch this if it goes wrong?"

**Prompt module:**
> For each `delete-*` or `move` verdict, document the recovery path:
> - Layer 1 (backup ref): `git checkout refs/repo-janitor-backup/<DATE>-pre-cleanup -- <path>`
> - Layer 2 (bundle): `cp <bundle>/working-tree-copies/<path> <project>/<path>`
> - Layer 3 (git history): `git revert <commit>`
> - Layer 4 (mirror): only for harden-secret-leak; not normally relevant
>
> Include in the row's "recovery_path" column. Surface in the handoff "Recovery recipes" section.

**Exit criteria:** Every destructive verdict has at least 2 documented recovery paths.

**Failure modes:**
- Single-layer recovery: if Layer 1 fails, the user is stuck.
- Vague recovery: "use the bundle" without commands.

**Composes with:** ⬡ BUNDLE, ⌘ HANDOFF.

**Source:** saas-billing's ⊕ LAYERED-DEFENSE (renamed `⊛` here to avoid collision with `⊕ GATE-RUN`).

---

### `⊙` PROVENANCE-WRAP  (Recovery)

**Trigger:** Every workspace artifact write.

**Question:** "Will a fresh agent re-entering the workspace know what produced this artifact, when, and from what inputs?"

**Prompt module:**
> Every artifact in `<workspace>/` opens with a header:
>
> ```
> ---
> produced_at: <UTC timestamp>
> produced_by: <subagent name>
> source_phase: <phase number>
> confidence: <0.0-1.0 if applicable>
> inputs_hash: <sha256 of input files>
> ---
> ```
>
> The header makes "stale artifact mistaken for authoritative" impossible.

**Exit criteria:** Every workspace file opens with a provenance header.

**Failure modes:**
- Bare artifacts (no header): on resume, the skill can't tell if `triage.tsv` is from this run or last week's.
- Header without `inputs_hash`: re-running with different inputs produces silently-divergent results.

**Composes with:** all artifact-producing operators.

**Quote bank:** §13.1 (provenance is an artifact-level invariant), §13.2 (artifact header format).

**Source:** saas-billing's 🪟 PROVENANCE; SKILL.md Axiom 22.

---

### `✸` PIN-THE-CONTRACT  (Recovery)

**Trigger:** After any non-trivial Phase 6/7/8 commit, especially deletes that prevent recurrence.

**Question:** "Will a future maintainer know not to undo this cleanup?"

**Prompt module:**
> For commits that establish a contract (e.g., `delete-and-gitignore` of `nohup.out` + add `nohup.out` to `.gitignore`), pin the contract via:
> - A comment in the relevant code/config explaining why
> - A drift-guard test if the project supports them (e.g., a CI test that fails if `nohup.out` is ever committed again)
> - A pre-commit hook entry (covered by INCIDENT-PLAYBOOK Step 7 for secrets)
>
> Document the pinning in `pinned_contracts.md`.

**Exit criteria:** Recurring-pattern verdicts have a drift-guard or document.

**Failure modes:**
- One-shot fix: the cleanup works once but recurs on the next swarm cycle.
- Implicit contract: future maintainers don't know what to preserve.

**Composes with:** 🛡 SHADOWING-AUDIT (the pre-commit hook test is a form of contract pinning).

**Source:** saas-billing's 🧪 PIN-THE-CONTRACT.

---

## Composition examples (extended)

The operators compose:

### Phase 2 (inventory + coverage)
- **`★ INVENTORY` → `⊞ COVERAGE-MATRIX` → `⊠ NEGATIVE-DECISION`**: enumerate, classify, document gaps.

### Phase 4 (triage)
- **`🔗 REFERENCE-GREP` + `⌖ FALSE-POSITIVE-CHECK`**: validate ref hits before flipping verdicts.
- **`🔍 CLASSIFY-PURPOSE` + `💎 ASSESS-VALUE` + `⩚ VULNERABLE-FILE-FILTER`**: classify each candidate; route vulnerable ones to special handling.

### Phase 5 (plan composition)
- **`🧮 PATTERN-EXTRACT` + `🛡 SHADOWING-AUDIT`**: aggregate patterns into `.gitignore` rules without shadowing tracked files.
- **`⊛ LAYERED-DEFENSE`**: document the recovery path per verdict.

### Phase 6 (apply moves)
- **`✦ MOVE-WITH-RENAME` + `↪ REWRITE-REFERENCES` + `⊕ GATE-RUN`**: per-move three-step.
- **`↺ WORKING-TREE-DRIFT`**: re-snapshot before each.

### Phase 7 (apply deletes)
- **`⚠ CONFIRM` → `⊟ REMOVE-WITH-RM` → `⊕ GATE-RUN`**: verbatim auth → delete → gate.

### Phase 8 (gitignore)
- **`🛡 SHADOWING-AUDIT` → `⚠ CONFIRM` (if shadowing) → `⊕ GATE-RUN`**.

### Phase 9 (fresh-eyes)
- **`◑ VERIFY-LIVE` + `⊞ COVERAGE-MATRIX` + `⌖ FALSE-POSITIVE-CHECK`**: verify version-sensitive behaviors didn't drift; check coverage; cross-check false positives.

### Phase 10 (handoff)
- **`⊛ LAYERED-DEFENSE` + `⧗ TIME-BOXED-PIVOT` + `✸ PIN-THE-CONTRACT` + `⌘ HANDOFF`**: document recovery, rollback window, pinned contracts, push commands.

### Across modes
- **`◑ VERIFY-LIVE` + `⊙ PROVENANCE-WRAP`**: every recommendation carries verified context AND artifact-level provenance.
- **`⟳ CROSS-ARCHETYPE-CHECK` + `📍 LOCATE-PROPER-HOME`**: multi-archetype repos get correct destinations per subtree.

When you find yourself wanting to skip an operator: that's the signal to slow down, not speed up.
