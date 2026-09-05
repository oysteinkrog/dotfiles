# CHANGELOG.md — Skill Version History

<!-- TOC: 1.2.0 (current) | 1.1.0 | 1.0.0 | Version policy | Upgrade guide -->

## 1.2.0 — Branch / sibling-dir guards, Phase 9.5 polish loop, calibration helper, alarming-headline reframe (2026-05-09)

Driven by the user's cross-project review of cass sessions. Three classes of recurring user-pain after applying the skill:

  1. **Branch creation creep.** Even though the skill never explicitly told agents to create a new branch, several runs ended up on `audit/...` branches. The user explicitly forbids new-branch creation for routine work.
  2. **Sibling-dir creep.** Agents occasionally placed audit artifacts as siblings of the project (`/data/projects/foo_audit/` next to `/data/projects/foo/`) instead of inside it. Sibling layouts get lost or accidentally re-created.
  3. **Alarming-but-wrong headlines.** Reports led with "153 false-closed beads (18.1%)" — and on follow-up ground-truth review, **15/15** of the lowest-scoring beads turned out to be SCORE FALSE POSITIVES (real code, real tests, real fixes shipped). The deterministic-only banner existed but was buried below the alarming flag count.

Plus the user's new explicit requirement: **after Phase 9 writes beads, the skill MUST run a 3-pass polish loop with the user-mandated polish prompt**, routing every edit through `br update` and consulting `bv` for graph diagnostics between sweeps.

### New hard rules (top of SKILL.md)

* **"Stay on `main`. Never create a branch for the audit."** The audit dir has its own `.git/`; the project repo stays exactly where it was.
* **"Audit artifacts live INSIDE the project tree."** The audit dir is `<project>/beads_compliance_audit/`, never `<project>_audit/` or `/tmp/<project>-audit/`.
* **"Don't act on the deterministic-only headline."** Always run `scripts/calibrate-bottom-n.sh` (or the LLM equivalent) on the bottom 5–10 beads BEFORE telling the user the project is broken.
* **"Phase 9.5 is mandatory whenever Phase 9 wrote beads."** Run the 3-pass polish loop with `br` + `bv`.
* **"Reframe the headline."** Don't say "your project has 153 false-closed beads." Say: "The deterministic baseline flagged 153 beads for review; based on prior calibration, plan for 8–15 real items."

### Bootstrap-audit guard rails (bootstrap-audit.sh)

* `AUDIT_DIR_OVERRIDE` is now refused when it resolves outside the project tree — unless `BCV_ALLOW_EXTERNAL_AUDIT_DIR=1` is explicitly set. Prior versions silently allowed sibling layouts.
* The project's branch at bootstrap time is captured into `manifest.json#project_branch_at_pass_start` so post-pass sanity checks can detect drift.
* Manifest schema gains a `9.5: pending` slot in `phase_status` to track the polish loop.

### Run-pass branch sanity check (run-pass.sh)

* `run-pass.sh` snapshots the project's branch at start and verifies it didn't drift at end. On drift it surfaces a loud `⚠️ BRANCH DRIFT DETECTED` banner with restore instructions; does NOT auto-revert.
* New flags: `--no-polish`, `--no-calibration`, `--calibration-n N`.

### Calibration helper (NEW: calibrate-bottom-n.sh)

* Read-only spot-check against the real codebase: lists commits referencing each flagged bead's ID, verifies cited files exist, prints first/last commit per file, and surfaces the scorecard's missing-items checklist as a ground-truth checklist.
* Always runs by default after master-report.py (set `--no-calibration` to skip).
* Output at `<pass-dir>/calibration.md` — read this BEFORE acting on REPORT.md.

### Phase 9.5 polish loop (NEW: polish-remediation-beads.sh)

* Mandatory whenever Phase 9 wrote/reopened beads (skipped only with explicit `--no-polish`).
* Runs the user-mandated polish prompt VERBATIM over each new/reopened bead, three sweeps in a row, with up to two extra sweeps if Sweep 3 still produces meaningful edits.
* Captures `bv --robot-suggest` / `--robot-priority` / `--robot-alerts` per sweep into `<pass-dir>/polish_bv_sweep_<N>.json` and writes one markdown entry per (bead, sweep) into `<pass-dir>/polish_log.md`.
* All edits routed through `br update` / `br comment` — never hand-edits JSONL or SQLite.
* `remediate.sh` writes a `## Phase 9.5 hand-off` section into `remediation.md` whenever it acted on ≥ 1 bead, instructing the orchestrator to run the polish driver.

### Master report reframing (master-report.py)

* Headline now leads with **"flagged for review"** language and an explicit calibration prior ("plan for ~K–N real false-closed, NOT all M flagged") whenever the pass is deterministic-only.
* New always-on bullet recommends `scripts/calibrate-bottom-n.sh` BEFORE acting on the false-closed list.
* Full-pipeline reports also recommend the calibration step now (previously skipped this advice).

### Theater detection (theater-scan.sh)

* **`#[cfg(test)]` no longer flagged as theater on Rust files.** This is idiomatic Rust for compile-time test-only code; flagging it tanked four beads in the user's prior runs (`11n3`, `2f4x`, `9yw1`, `dwec`). New rule: Rust files only flag *runtime* `if cfg!(test)` branches; the `#[cfg(test)]` attribute is excluded. Other languages unchanged.
* **`.beads/` and `beads_compliance_audit/` paths now excluded from theater scans.** When a bead happened to cite a path inside `.beads/`, the JSONL bead store was scanned as if it were source code, producing categorically-wrong "hardcoded_return" / "todo_comment" findings (notably affecting `11n3`, `149j`).

### SKILL.md additions

* New "STOP — Read This First (The Five Hard Rules)" section at the top.
* New Phase 9.5 documentation immediately after the 10-Phase Loop, including the verbatim polish prompt.
* Anti-Patterns table extended with: branch creation, sibling-dir creation, alarming headline, skipping Phase 9.5, hand-editing the bead store.
* End Checklist extended with: Phase 9.5 sweep log, calibration spot-check, branch/dir hygiene.

### Anti-drift safeguard for the polish prompt

* New canonical text: **`assets/polish-prompt.txt`**. Single source of truth.
* New validator: **`scripts/validate-polish-prompt-consistency.py`** — fails when the prompt has drifted between `assets/polish-prompt.txt`, the SKILL.md blockquote, and the `POLISH_PROMPT='...'` bash variable in `polish-remediation-beads.sh`. Prints a unified diff identifying the drifted source. Pre-commit / CI ready.

### New reference docs

* **`references/PHASE-9-5-POLISH-LOOP.md`** — deep-dive: when it fires, the loop diagram, operational rules, worked example with three sweeps, bv interaction patterns, non-convergence handling, edge cases, anti-patterns.
* **`references/CALIBRATION-FRAMING.md`** — deep-dive: the 15/15 case study from `beads_rust`, the empirical 10–25% prior, headline reframing examples, `calibrate-bottom-n.sh` walkthrough, decision tree for interpreting calibration.md outputs.
* **`references/PHASES.md`** updated with a full Phase 9.5 entry between Phase 9 and Phase 10 (matching the existing per-phase format).
* **`references/CASE-STUDIES.md`** added Case Study #11: "The 15/15 false-positive cohort" with the full root-cause cluster table and remediation lessons.

### Self-test improvements

* **SELF-TEST.md** trigger phrases extended with v1.2 capabilities: "audit said 153 false-closed but most look fine", "calibrate the bottom-N", "polish the new beads from Phase 9", "Phase 9.5 polish loop", "the audit dir got created as a sibling — fix it", and others.
* **SELF-TEST.md** smoke-test expectations updated for the v1.1 stub-WAIVED scoring behavior — the smoke-test bead now scores high (~970) because Phase 4 / 6 are stubbed in run-pass.sh, with a note that triggering false-closed requires the LLM evidence-gatherer + compliance-verifier subagents.

### Fresh-eyes self-review fixes (round 2 — post-onboarding)

The v1.2 changes were re-reviewed AGAIN after the initial ship; the following additional issues were caught and fixed:

* **polish-remediation-beads.sh** — `--max-extra-sweeps` no-op flag handling was buggy. Original `shift 2` crashed under `set -e` if the flag was the last arg (no value), and the first fix greedily consumed the next token even if it was another flag (e.g. `--max-extra-sweeps --force` lost the `--force`). Final fix: shift the flag, then conditionally shift a value only if it doesn't start with `--`.
* **validate-polish-prompt-consistency.py** — regex used `re.DOTALL` + `.+?` which would silently fold multiple blockquote lines into one capture if a future edit made the polish prompt multi-line. Tightened to `[^\n]+?` (no DOTALL) so the validator fails loudly on multi-line drift instead of corrupting the comparison.
* **SKILL.md Hard Rule #1** — original wording "Stay on `main`" was too strict (a user legitimately on a feature branch would read it as forbidding their setup). Reworded to "Never CREATE a branch and never SWITCH branches; the project repo stays on whatever branch it was on when you started."
* **End checklist branch/dir hygiene** — added explicit `manifest.json#project_branch_at_pass_start` cross-check.
* **manifest version convention** — corrected version-derivation in the inline Python helper to use `first-12-of-entry-checksum` (matching `scripts/generate-checksums.py` convention) instead of `first-12-of-SKILL.md-sha`.

### Fresh-eyes self-review fixes (round 1)

The v1.2 changes were re-reviewed with fresh eyes; the following bugs were caught and fixed before ship:

* **calibrate-bottom-n.sh** — `fi >/dev/null` redirected the empty-IDS message to `/dev/null` instead of the output file (Bug C1); restructured so stderr summary always runs (Bug C2).
* **polish-remediation-beads.sh** — refactored from "snapshot/diff/converge loop" to "pure scaffolding" (Bug P1, P4 — the diff loop only made sense with an orchestrator making `br update` calls *between* snapshot calls; in batch mode it always reported "Converged" misleadingly). The script now writes a 3-section template with Decision slots; the orchestrator drives the actual sweeps in their own conversation.
* **polish-remediation-beads.sh** — `br show --json` returns a JSON ARRAY (not an object); fixed `.title` extraction to handle both shapes via `if type=="array" then .[0] else . end | .title`.
* **polish-remediation-beads.sh** — `bv` signal capture now validates with `jq -e .` and falls back to JSON `null` if bv emits non-JSON (Bug P3).
* **polish-remediation-beads.sh** — idempotency check: refuses to overwrite an existing `polish_log.md` unless `--force` (Bug P5).
* **polish-remediation-beads.sh** — awk filter for the remediation.md Actions table now skips header / separator / non-bead-id rows (Bug P6).
* **run-pass.sh** — stops swallowing stderr from calibrate/polish scripts so failures are visible (Bug R1); passes `--force` to polish scaffold for idempotency-safe re-runs (Bug R2).
* **master-report.py** — calibration prior formula `low = max(1, N//10)`, `high = max(low+1, N//4)` is only emitted when N ≥ 5 (avoids the "plan for ~1–1 NOT 1" nonsense at small counts).

---

## 1.1.0 — Field-feedback bug fixes & tier rebalance (2026-05-07)

First real-world use on a 1,644-closed-bead Rust project (`coding_agent_session_search`) surfaced a tight cluster of bugs and friction. This release fixes all of them. Driven by sample-mode audit feedback documented in the operator's `SKILL_FEEDBACK.md`.

### Scoring (score-bead.py)

* **Implementation dimension now falls back to evidence.json when Phase 4 is stubbed.** Prior versions zeroed Implementation whenever `compliance.json` was a stub pack, even if `evidence.json` had FOUND items for every code artifact. New behavior: if Phase 4 ran in stub mode AND the per-item `verdict` is `MISSING`, fall back to evidence status (FOUND→0.7, AMBIGUOUS→0.4, MISSING→0). The scorecard banner already declares the "DETERMINISTIC-ONLY PASS" upper-bound. (Bug 1 in v1.0.)
* **`is_stub_pack()` now recognizes empty packs and `stub_reason`-bearing packs as auto-WAIVED.** Previously only the magic strings `"stub-wrapper"` / `"single-bead-stub"` triggered the WAIVED branch; an empty `compliance.json` (`{}`) or any handwritten stub recovery file was treated as "phase ran, found nothing" and zeroed the dimension. New signals: any of (a) executor/auditor in `STUB_EXECUTORS`, (b) `stub_reason` field present, or (c) pack file completely missing. (Bug 5.)
* **Atomic write for `scorecard.md`.** Score-bead now writes scorecard.md via tmp-then-`os.replace`, defending against operators who run `python3 score-bead.py BD > BD/scorecard.md` (an attractive recovery anti-pattern that corrupts the file because Python's stdout JSON envelope races the script's own `write_text`). With atomic rename, scorecard.md is replaced by a new inode and external bash redirection lands in the orphaned old inode rather than corrupting on-disk content. (Bugs 8 + 9 — title truncation cascade.)

### Theater detection (theater-scan.sh)

* **Range-scoped scanning.** Patterns now respect `evidence.json` `line_start`/`line_end`; a bead citing `src/lib.rs:12994-15068` no longer surfaces findings from line 8756. Beads without explicit ranges still get whole-file scans (legacy behavior). (Bug 2f.)
* **Idiomatic-Rust exclusions for `hardcoded_return`.** `return None;` (Option early-return) and `return Ok(());` (Result unit) are valid Rust, not theater. Pattern is now language-aware: `.rs` files only flag `Default::default()`; `.py`/`.js`/`.ts` keep their language-appropriate trivial-return sets. Field-tested ~1100-finding noise reduction per Rust bead. (Bug 2a.)
* **`sleep_as_fake_work` now requires non-trivial duration AND no retry/backoff context.** Sub-second sleeps and sleeps inside loops/retry blocks are NOT theater — they're production-correct backoff. New rule: flag only when duration is parseable AND ≥ 1 second AND the surrounding 3 lines don't contain `retry`/`backoff`/`attempt`/`poll`/`wait_for`/`interval`/`debounce`/`throttle`/`jitter`. Severity downgraded from BLOCKING to MAJOR. (Bug 2b.)
* **`api_501_stub` now requires HTTP-status context.** `\b501\b` matched SQL `VALUES (501, ...)` and bare numeric literals like `Some(501)`. New pattern requires `Status`/`StatusCode`/`status`/`status_code`/`response`/`HTTP/1.x`/explicit framework decoration near the 501. (Bug 2c.)
* **`todo_comment` requires comment marker on code files.** A string literal `"TODO"` inside a CLI usage example is not a TODO comment. New rule: in code files, the keyword must follow `//`, `#`, `/*`, `*`, or `;`. Doc-style files keep the existing fenced-code-block / inline-backtick stripping. (Bug 2d.)
* **`skipped_test` no longer matches comments referencing `#[ignore]`.** `is_in_comment_or_string()` heuristic was extended (carefully — a `#` followed by `[` is a Rust attribute, not a comment marker). (Bug 2e.)
* **All findings now include the `pattern` field.** Downstream tooling can `jq '.findings | group_by(.pattern)'` to filter findings by detector pattern. Schema documented in EVIDENCE-SCHEMAS.md. (Bug 6.)
* **No more `Argument list too long` on beads with many cited paths.** The final assembly step reads findings from a JSONL temp file and scanned-files from a `--slurpfile` rather than passing both inline as `--argjson`. Field-tested past 47 cited paths (the previous failure threshold). (Bug 4.)

### Evidence gathering (gather-evidence.sh)

* **Directory citations no longer crash the script.** When `expected_path_hints` resolves to a directory, `wc -l < <directory>` errors and leaves `LINES` empty/unset. Subsequent `--argjson e ""` raised `jq: invalid JSON text` and `set -e` aborted. New defense: file-vs-directory check, then a final `LINES="${LINES:-0}"` and numeric-regex coerce. Previously caused 8 of 15 beads to fail Phase 3 deterministic gather in field testing. (Bug 3.)

### Spec extraction (extract-spec.py)

* **Stderr warning when deterministic extraction is too sparse.** When the deterministic parser produces < 3 items from a body of ≥ 200 chars, emit a warning suggesting the operator dispatch `subagents/bead-spec-extractor.md` for richer LLM-driven extraction. Field tests: deterministic 0–7 items vs LLM 10–49 on prose-style ACs. (Friction 11.)

### Anomaly detection (anomaly-scan.sh + inventory-beads.sh)

* **Project-wide git xref convention gap detection.** `inventory-beads.sh` now writes `<pass-dir>/git_xref_coverage.json` summarizing what fraction of closed beads have any commit referencing their ID. When < 30%, the project's commit-message convention doesn't include bead IDs (topic-style commits like `feat: add X`) — this is a project-wide convention gap, not a per-bead defect. `anomaly-scan.sh` then DEMOTES `anomaly_no_git_xref` from MAJOR to NOTE in this case. Avoids penalizing every closed bead with -15 anti-theater points for a project-wide convention. (Friction 12.)

### Synthesis (synthesize.py)

* **The 500-bead probe cap is now visible.** `synthesize.py` emits a stderr warning at run time when `MAX_PROBES` clips the probe count, and writes `synthesis_coverage.json` with structured coverage data so master-report and validators can read this programmatically. The cap is also overridable via `SYNTHESIZE_MAX_PROBES=<n>`. (Bug 10.)

### Tier rebalance (SKILL.md, README.md, MODES-AND-TIERS.md)

* **Hard cap: 10 concurrent agents, regardless of project size.** Field testing past 10 agents showed Agent Mail file-reservation thrash, NTM pane jank, and prompt-cache fragmentation that *reduced* throughput. Past this point, more agents make audits slower and more confused.
* **Gentler tier ramp**: Solo (<20 → 1) → Pair (20–150 → 2–3) → Squad (150–500 → 4–5) → Battalion (500–1000 → 6–7) → Swarm (1000–1500 → 8–9) → Mega-swarm (1500+ → 10 hard cap). Replaces the prior Solo/Pair/Squad/Swarm-with-16+-agents shape.
* **New mode: `Sample`** — recommended default for 1500+ closed beads. Stratified sample of 15–50 beads (5 keystones + 5 bottlenecks + 5–40 random recents), full 10-phase pipeline against the sample only. Headline signal preserved at ~100× lower cost than comprehensive. Sample audits get a "Sample audit — N of M closed beads audited" banner so reports aren't mistaken for comprehensive passes.

### Friendly errors

* `inventory-beads.sh` now prints a friendly usage message instead of bash's terse `inventory-beads.sh: line 18: 2: pass dir` when called with too few args. (Bug 7.)

### Migration

No data migration required. Existing audit dirs continue to work. To re-score under the new rubric, run `scripts/run-pass.sh` again — score-bead.py reads the same evidence packs and the new fallback logic applies automatically. To benefit from the new theater patterns, regenerate `theater.json` files with `scripts/theater-scan.sh`.

---

## 1.0.0 — Initial release (2026-05-06)

**Phases.** Full 10-phase audit loop (inventory → spec → evidence → compliance → theater → depth → synthesis → scoring → remediation → fresh-eyes).

**Modes.** Triage, Standard, Comprehensive, Tripwire, Single-bead, Re-verification, Onboarding, Time-machine, Post-mortem, Release-gating.

**Tiers.** Solo, Pair, Squad, Swarm.

**Operators (25 cognitive moves).** ★ ENUMERATE, ✦ EXECUTE, ⚖ MEAN, ◐ MEASURE, ⊕ INTEGRATE, ⚑ CONTRACT, § ANCHOR, ⊿ DISCRIMINATE, ⌖ TARGET, ↻ RETRY, ⌀ ZERO, ⊠ PIN, ⟴ AMORTIZE, ⊳ DELEGATE, ⌥ ROLLBACK-PROOF, ⊡ FRAME, ⌬ HARMONIZE, ⊙ DE-SLOP, ⊞ TRIANGULATE, ⊘ SELF-POLICE, ⟳ REPEAT-UNTIL-QUIET, ⌂ CONSEQUENCE, ⤵ DECOMPOSE, ☖ STAKE-RUBRIC, ☍ DISCLAIMER-WINDOW, ⌘ REDUCE.

**Failure-mode catalog.** 30 patterns documented in FAILURE-MODES.md.

**Subagents.** 12 — bead-spec-extractor, evidence-gatherer, compliance-verifier, theater-detector, test-depth-auditor, cross-bead-synthesizer, scorer, remediator, fresh-eyes-rubric-auditor, audit-reviewer, bead-author-feedback, trauma-guard.

**Scripts.** 17 — bootstrap-audit.sh, check-skills.sh, inventory-beads.sh, extract-spec.py, gather-evidence.sh, theater-scan.sh, anomaly-scan.sh, synthesize.py, score-bead.py, master-report.py, remediate.sh, convergence-check.py, dashboard.py, portfolio-audit.sh, portfolio-rollup.py, run-pass.sh, trauma-guard.sh, metrics-export.sh, migrate-audit-dir.sh.

**References.** 32 documents covering kernel axioms, design philosophy, jargon, case studies, walkthrough, per-skill integration, debugging, post-mortem mode, time-machine mode, release-gating, closer-defense, anti-corruption, compliance evidence packs, audit-as-code DSL, fixture library, pre-audit checks, FAQ, comparison, this changelog, etc.

**Validated:** `validate-skill.py` returns valid; pipeline tested end-to-end on synthetic projects with mixed verdicts (clean / theater / WIP / sloppy session).

---

## Version policy

The skill follows semver:

- **Major (X.0.0)** — incompatible scoring changes (e.g., 0-1000 → 0-100 scale; rubric becomes non-comparable across versions).
- **Minor (1.X.0)** — new patterns, new operators, new modes, new references. Existing audits continue to work; convergence-check flags rubric drift.
- **Patch (1.0.X)** — bug fixes, doc improvements, no behavioral change.

Bumps to `rubric_version` in audit dir's `rubric.md` are independent of the skill's version (per project, per pass).

---

## Upgrade guide

### Within 1.x

1. Re-run the audit. The new version's rubric drift will be flagged in `convergence.json#rubric_changed_since_prior_pass`.
2. Read this CHANGELOG to understand what changed.
3. The next pass on the new version becomes the new baseline.

### Across major versions (1.x → 2.0)

Major versions change scoring scales / kernel axioms / artifact schemas. Migration:

1. **Final pass on prior version** — capture state.
2. **Read 2.0 release notes** in this CHANGELOG.
3. **Bootstrap a fresh audit dir** for 2.0 (don't try to migrate prior passes).
4. **Cite the 1.x audit dir's REPORT.md** in the new audit dir's README as historical baseline.

Convergence semantics restart on major version bumps.

---

## Roadmap (not yet implemented)

These are placeholder ideas for future versions. Not promises.

- **2.0** — Hypothetical major refactor: rubric DSL becomes its own file (rubric.yaml instead of rubric.md frontmatter); scoring scale 0-100 (cleaner percentages); audit dir layout v2.
- **1.1** — Rubric inheritance (extends: ~/.../assets/rubric-templates/saas-strict.md).
- **1.1** — Validation script for rubric.md.
- **1.1** — More fixture projects covering bead-graph cycles, custom-type beads, multi-language polyglot.
- **1.1** — Native MCP tool for bead-author-feedback (integrate with `/agent-mail`).
- **1.1** — Scheduled audit via `/schedule` skill.
- **1.2** — Compose with `/multi-agent-swarm-workflow` for swarm-tier audits with `/ntm` panes.
- **1.2** — Live HTML dashboard with WebSocket updates instead of static html.

---

## Migration notes from earlier (pre-1.0) experiments

The skill was iteratively built across 3 rounds:

- **Round 1 (initial)** — 22 references, 9 subagents, 12 scripts. Skeletal structure with all 10 phases.
- **Round 2 (expansion)** — Added Operator Library, Kickoff Prompts, Bead-Type Playbooks, Modes-and-Tiers, Project-Types, CASS-Mining, CI-Tripwire, Multi-Pass-Flow, Quote Bank, Multi-Repo, Dashboard, Portfolio, Anomaly Scan; ~50K added.
- **Round 3 (this release)** — JARGON, DESIGN-PHILOSOPHY, CASE-STUDIES, WALKTHROUGH, OPERATOR-LIBRARY (25 ops), REMEDIATION-PRIORITIZATION, BEAD-GRAPH-ANALYSIS, DEBUGGING-THE-AUDIT, METRICS-PIPELINE, CONTRIBUTING-PATTERNS, VERIFICATION-UNDER-UNCERTAINTY, COST-OPTIMIZATION, EXTENDED-INTEGRATION, AUDIT-SMELLS, POST-MORTEM-MODE, TIME-MACHINE-MODE, RELEASE-GATING, CLOSER-DEFENSE, ANTI-CORRUPTION, COMPLIANCE-EVIDENCE-PACK, AUDIT-AS-CODE, AUDIT-FIXTURE-LIBRARY, PRE-AUDIT-CHECKS, FAQ, COMPARISON, this CHANGELOG, plus README.md, MIGRATION.md, BADGE.md, CROSS-SKILL-COMPOSITION.md, KNOWN-LIMITATIONS.md.

**Critical bugs fixed across rounds:**

- Round 1: 11 bugs in initial scripts (missing imports, wrong arg names).
- Round 2: 8 bugs (bead-id regex too narrow, datetime double-strip, score-bead synthesis precedence, bootstrap doctor exit-code, dead LIMIT variable, etc.).
- Round 3: 7 more bugs (br pagination via --limit 0, parse_synthesis precedence cleanup, gather-evidence trailing slash, bullet alternation order edge case, dashboard min-height, synthesize.py actual deps via `br dep list`, gawk-only awk syntax).

**Total artifact count at 1.0:** SKILL.md + 32 references + 12 subagents + 19 scripts + 4 assets + SELF-TEST + README + this CHANGELOG.

---

## Contribution attribution

The skill was authored by an AI agent under direction of the human owner of the parent skills repository. Pattern inheritance is documented in [DESIGN-PHILOSOPHY.md § Inheritance from sibling skills](DESIGN-PHILOSOPHY.md). Cross-references to sibling skills indicate the patterns this skill stands on.

For external contributors: see [CONTRIBUTING-PATTERNS.md](CONTRIBUTING-PATTERNS.md) for the contribution flow on adding new failure-mode patterns.
