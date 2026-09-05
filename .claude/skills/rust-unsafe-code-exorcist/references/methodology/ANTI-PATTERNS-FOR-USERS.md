# ANTI-PATTERNS-FOR-USERS.md — Common Mistakes When Running This Skill

Anti-patterns the skill itself avoids are documented in many places (SKILL.md, individual pattern bundles). This file is for USERS — common mistakes when invoking, configuring, or interpreting the audit.

---

## During invocation

### ✗ Running the audit on your project before reading AUDIT_SUMMARY.md from a prior audit

**Why it's a mistake:** Each audit produces a snapshot at a specific commit. Running multiple audits without reading the first's summary means losing the prior context.

**Fix:** Before re-auditing, read the prior `<audit-dir>/AUDIT_SUMMARY.md`. Understand what changed since.

---

### ✗ Pointing the skill at your project root expecting it to "figure out the structure"

**Why it's a mistake:** Workspaces, single crates, and polyrepos need different scope handling. The skill asks at Phase 0 about scope; if you skip the dialog, defaults may not match your project.

**Fix:** Answer the Phase 0 questions (project type, mode, perf budget). Or skim [OPERATING-MODES.md](OPERATING-MODES.md) first.

---

### ✗ Running in `audit-and-refactor` mode without reviewing the plans first

**Why it's a mistake:** `audit-and-refactor` can edit your active checkout and may create an ordinary branch/PR if you ask for that workflow. If you haven't reviewed the per-cluster plans, you're approving changes sight-unseen.

**Fix:** Always run `audit-only` first. Read `audit/plans/cluster-*.md`. THEN, if happy, re-invoke with `--mode audit-and-refactor`.

---

### ✗ Treating `triage` output as a full audit

**Why it's a mistake:** `triage` (60-second mode) enumerates + risk-scores. It does NOT classify, plan, or verify. The output tells you WHERE the unsafe is, not WHAT to do about it.

**Fix:** Use `triage` for exploration; promote to `audit-only` once you've decided the project warrants a full pass.

---

### ✗ Skipping the smoke test on a new install

**Why it's a mistake:** A subtle missing tool (`cargo expand`, `ast-grep`, …) makes the audit produce empty / wrong output without obviously failing.

**Fix:** Run `scripts/check-prerequisites.sh` first. Run the toy-project smoke test in [README.md § Try it on a toy project first](../../README.md). Verify the inventory has rows.

---

## During configuration

### ✗ Setting perf budget too strict (0% / 1%)

**Why it's a mistake:** Most refactors have some measurement noise. 0% strict budget will reject perfectly-equivalent rewrites because of bench-run-to-bench-run variance.

**Fix:** 5% is the default for good reason. Use 1% only when you've measured baseline variance is sub-1% (rare on modern OSes).

---

### ✗ Configuring continuous-mode to fire on EVERY drift

**Why it's a mistake:** Active development naturally produces drift (new code → new sites). If every PR triggers a drift bead, the user loses signal in the noise.

**Fix:** Default thresholds (in `continuous-mode.toml`) are tuned for production projects. For active dev, raise `geiger_increase_alarm` to 5 or 10. Re-baseline more often.

---

### ✗ Treating the `safe-only` feature as production-ready immediately

**Why it's a mistake:** The (B) site's safe-only branch is a SAFE alternative — but it may have its own bugs that the perf-path's tests didn't exercise.

**Fix:** Verify CI matrix is green on BOTH default and `safe-only` for at least one release cycle before recommending safe-only to users.

---

### ✗ Skipping the maintainer-empathy review (Phase 10)

**Why it's a mistake:** Phase 10 is where a fresh agent reads the audit cold and answers "would I land this as maintainer?" This catches plans that are technically correct but practically unmergeable.

**Fix:** Always run Phase 10. Read `REVIEWER_RESPONSES.md` before landing any refactor.

---

## During interpretation

### ✗ Assuming (A) means "this can never change"

**Why it's a mistake:** (A) means "no safe formulation exists TODAY in current Rust." As the language evolves (strict provenance stabilization, generic associated types, etc.), some (A) sites may become (C).

**Fix:** Re-audit periodically. The audit's iterative nature catches when language evolution unlocks new safe patterns.

---

### ✗ Reading the geiger count as the only metric

**Why it's a mistake:** Geiger counts SITES, not RISK. A project with 100 fully-justified (A) sites is in a better state than one with 10 unclassified (C) sites.

**Fix:** Read the risk-summary.md (sum-of-risk-scores) alongside geiger. The risk number is what matters; geiger is the side metric.

---

### ✗ Ignoring `pre-existing-ub-N` beads because "they weren't in scope"

**Why it's a mistake:** They're not in the CURRENT refactor's scope, but they're real UB. Letting them accumulate is technical debt with no expiration.

**Fix:** Triage each pre-existing-ub bead. Decide: address now / next cycle / never (and document why). Track in `audit/synthesis/pre-existing-ub.md`.

---

### ✗ Treating risk scores as exact

**Why it's a mistake:** Risk scores are HEURISTIC (1-5 per dimension × 3 dimensions = 1-125 range). They prioritize; they don't replace judgment.

**Fix:** Use scores to order beads; sanity-check the top 10 against your gut. If a site you think is high-risk scores low, refine the rubric (per [RISK-SCORING.md § Calibration](RISK-SCORING.md)).

---

### ✗ Assuming "verify.sh GREEN" means "no UB anywhere"

**Why it's a mistake:** verify.sh tests miri + careful + loom + fuzz + mutants + geiger on what we've configured. It's a strong signal, not a proof.

**Fix:** Read the harness's section in TESTING.md. Understand what each tool covers + doesn't cover. A "GREEN" run means "we couldn't find UB with these tools on these inputs."

---

## During refactoring

### ✗ Cherry-picking plans without addressing the whole cluster

**Why it's a mistake:** Refactor clusters share an invariant. Fixing 2 sites in a 5-site cluster might leave the project in an INCONSISTENT state where 2 paths are safe and 3 still aren't.

**Fix:** Land whole clusters at a time. Use `br ready --json` to see cluster boundaries via the bead graph.

---

### ✗ Bypassing Phase 7 fresh-eyes review

**Why it's a mistake:** The three verbatim review prompts are calibrated. Skipping them leaves bugs in the proposed safe rewrites that would have been caught.

**Fix:** Always run Phase 7. The two-clean-rounds gate exists for a reason.

---

### ✗ Modifying the project repo while audit is in progress

**Why it's a mistake:** The audit dir is a snapshot. If you edit project files mid-audit, the per-site write-ups become inconsistent with the actual code.

**Fix:** Either pause development during a full audit, OR use a frozen branch as the audit's input. Restart the audit if the source moves significantly.

---

### ✗ Landing (B) refactors that change perf characteristics without telling downstream users

**Why it's a mistake:** A `safe-only` build that's 20% slower is fine if users opt-in knowing the cost. If you flip the default to safe-only without warning, downstream perf regressions are surprise.

**Fix:** Document feature behavior in CHANGELOG + SECURITY.md. Default stays at perf path; opt-in `safe-only` for the security-conscious.

---

## During continuous operation

### ✗ Treating drift beads as "nice to have"

**Why it's a mistake:** Drift = new unsafe slipped in. Each ignored drift bead is potential UB that will eventually bite.

**Fix:** Triage every drift bead within 7 days. Either address it or explicitly defer with a written reason.

---

### ✗ Never re-baselining

**Why it's a mistake:** Baselines age. Continuous mode compares against an older state forever; eventually the comparison loses meaning.

**Fix:** Re-baseline after each major refactor wave (quarterly typical). See [CONTINUOUS-MODE.md § Bootstrapping continuous mode](CONTINUOUS-MODE.md).

---

### ✗ Disabling continuous mode "because too many alerts"

**Why it's a mistake:** Disabling means losing all signal. The problem is usually thresholds, not the mode.

**Fix:** Raise thresholds (`continuous-mode.toml § continuous.thresholds`) until alerts are actionable. Don't disable — tune.

---

## When asking for help

### ✗ "It didn't work; how do I fix it?" (without details)

**Why it's a mistake:** The skill has many moving parts. Without specifics, no one can diagnose.

**Fix:** Run `scripts/check-prerequisites.sh` first. Report your output + the exact command that failed + the error message. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for known failure modes.

---

### ✗ "I expected (C), got (A) — the skill is wrong"

**Why it's a mistake:** The classifier's job is to be conservative + adversarial. If it says (A), it survived three failed alternative attempts. Maybe the alternative you have in mind is the FOURTH one to fail — or maybe the classifier is right.

**Fix:** Read the (A) JUSTIFICATION block. Identify which alternative wasn't considered. If your alternative survives the falsification test (cited Rust Reference / nomicon section), the site SHOULD be (C); file feedback or refine your alternative.

---

### ✗ Reporting "AUDIT_SUMMARY says X but I expected Y" without context

**Why it's a mistake:** Audit outputs depend on perf budget, mode, scope, included crates. Same project can produce different summaries.

**Fix:** Share the `phase0_scope_decision.md` alongside the summary. The configuration determines the output.

---

## When extending the skill

### ✗ Adding new pattern bundles without exemplar citations

**Why it's a mistake:** The skill's value is its grounding in real shipped patterns. A pattern with no `[E-NNN]` citation has no evidence backing it.

**Fix:** Before adding a pattern bundle, identify at least one exemplar repo entry. Add to EXEMPLAR-CATALOG.md first.

---

### ✗ Modifying CLASSIFICATION-RUBRIC.md without bumping the kernel version

**Why it's a mistake:** The rubric is marker-bounded (`<!-- KERNEL_START v1.0 -->`). Changes to the kernel must increment the version + go through validation.

**Fix:** Edit only within the markers. Bump version. Re-run `validate-corpus.py`. Document the change in the kernel-version log.

---

### ✗ Adding operators without the required sections

**Why it's a mistake:** `validate-operators.py` enforces operator card structure (trigger / question / failure modes / prompt module / fix section). Missing sections break the validator.

**Fix:** Use the existing cards as templates. Run `validate-operators.py` after edits.

---

## What you SHOULD do (the inverse)

For balance — the inverse anti-patterns:

- ✓ Read README.md → check-prerequisites → smoke-test → full audit (in order).
- ✓ Use `triage` to scope before running full audit.
- ✓ Read `AUDIT_SUMMARY.md` first; drill into details only if needed.
- ✓ Address top-N risk-score sites first (Pareto principle baked in).
- ✓ Land refactor clusters whole.
- ✓ Run Phase 7 fresh-eyes + maintainer-empathy review.
- ✓ Re-baseline after major refactor waves.
- ✓ Re-audit before each `cargo publish`.
- ✓ When in doubt, file feedback on the audit output (helps the skill improve).
- ✓ Default classification DOWNWARD (A → B → C).

---

## Where to learn more

- Operating modes: [OPERATING-MODES.md](OPERATING-MODES.md)
- Classification rubric: [CLASSIFICATION-RUBRIC.md](CLASSIFICATION-RUBRIC.md)
- Phase loop: [PHASES.md](PHASES.md)
- Per-pattern anti-patterns: each `references/patterns/*.md` has its own anti-patterns section.
- Per-subagent constraints: each `subagents/*.md` has a "What you do NOT do" section.

This file is the user-facing anti-pattern summary. For machine-facing constraints (what subagents should NOT do), see the individual subagent files.
