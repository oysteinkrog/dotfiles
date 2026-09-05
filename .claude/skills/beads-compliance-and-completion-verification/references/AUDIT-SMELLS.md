# AUDIT-SMELLS.md — Patterns That Indicate The Audit Itself Is Sick

<!-- TOC: Why this is distinct from FAILURE-MODES | The 12 audit smells | Per-smell remediation | When to escalate to audit-reviewer | Self-test -->

> `FAILURE-MODES.md` catalogs theater patterns in the *projects being audited*. This file catalogs theater patterns in the *audit itself*. When the audit's own outputs look suspicious, these are the smells to recognize.

> **Why a separate catalog.** A sick audit is harder to detect than a sick project: the audit produces what looks like authoritative reports, but if its operators are skipping, its rubric is mis-applied, or its scorer is being generous, the entire pipeline produces false confidence. These smells are the meta-level analog of theater.

---

## The 12 audit smells

### Smell 1 — Every bead scored above threshold

**What it looks like.** REPORT.md exec summary: `0 false-closed`. Distribution: every bead 🟢.

**Diagnosis.**
- Threshold too low (rubric.md `score_threshold: 500`)?
- Phase 5 / 6 not running (theater.json + test_depth.json all empty)?
- Generosity bias in scorer subagent?

**Fix.** Read 5 random scorecards. If any has a BLOCKING theater finding but still scored ≥ 850, the scorer is too generous — apply `⊘ SELF-POLICE`.

---

### Smell 2 — Every bead scored at exactly the threshold

**What it looks like.** Score histogram has a giant spike at exactly 700.

**Diagnosis.** The scorer is rounding up to barely-pass. Sub-agent prompt drift; the LLM has learned that "around the threshold" is a safe answer.

**Fix.** Audit-reviewer subagent re-derives 5 random scores; if all derived scores are ~ ± 50 of 700, the scorer is biasing. Re-write the scorer's prompt to require dimension-by-dimension citations.

---

### Smell 3 — Every false-closed bead is from a single closed_by_session

**What it looks like.** REPORT.md false-closed list: 18 of 19 entries have the same `closed_by_session=2026-04-15-cod-789`.

**Diagnosis.** Often a real signal (sloppy session — see Pattern 30 in FAILURE-MODES.md). But sometimes the audit's session-attribution is broken.

**Fix.** Sample one of the false-closed beads. Manually verify its `closed_by_session` matches the report. If yes, escalate to operator (sloppy-session intervention). If no, fix the attribution code in inventory-beads.sh.

---

### Smell 4 — Convergence flips between passes

**What it looks like.** Pass 4: converged ✓. Pass 5: NOT converged. Pass 6: converged ✓ again.

**Diagnosis.** Either:
- The convergence threshold is too tight (±10 default; project noise is ±15).
- A bead is genuinely yo-yoing (real code drift).
- Rubric was tuned mid-pass without bumping `rubric_version`.

**Fix.** Check `manifest.json#rubric_sha256` consistency across the flipping passes. If different, the tuning was undocumented; fix and document. If same, loosen `delta_threshold_for_convergence`.

---

### Smell 5 — Phase 4 verdicts are MISSING for most beads

**What it looks like.** `compliance.json#checks[*].verdict == "MISSING"` dominates.

**Diagnosis.** Either Phase 3 evidence-gather missed everything (no citations to execute against), OR the test runner can't be reached (CI down, dependencies not installed).

**Fix.** Check `manifest.json#tools` — is `cargo` / `npm` / `pytest` listed? Try running the test command manually in the project. If it fails, the audit is correctly reporting that nothing can be verified — but you need to fix the project's runnability before the audit produces useful output.

---

### Smell 6 — Theater scan finds the same finding on every bead

**What it looks like.** `theater.json#findings[0].snippet` is identical across many beads.

**Diagnosis.** A widely-shared utility file (e.g., `src/utils.rs`) has a TODO comment. Phase 5 cited it for every bead because every bead's evidence list includes utils.rs.

**Fix.** Demote the finding to NOTE for "shared infrastructure" files, OR exclude common utility files from per-bead theater scans.

---

### Smell 7 — Scorecards have empty "Missing items" sections despite false-closed verdicts

**What it looks like.** `scorecard.md` says `🚨 FALSE-CLOSED` but the missing-items section is empty.

**Diagnosis.** The scorer applied a dimension dock without recording the source. Phase 9 has nothing to put into the completion-debt bead.

**Fix.** This is a citation-discipline bug. The `§ ANCHOR` operator should have caught it at scorecard-write time. Re-run Phase 8 with the operator's discipline reinforced in the scorer's prompt.

---

### Smell 8 — Synthesis.md is empty across many passes

**What it looks like.** Every `synthesis.md` says "(none)" for every section.

**Diagnosis.** Either the project has zero cross-bead drift (rare, but possible on small projects), OR Phase 7 isn't actually running, OR the synthesizer's bead-id regex doesn't match the project's IDs (Round-1 bug).

**Fix.** Verify by running `synthesize.py` manually and checking output. If still empty, manually grep one bead body for another bead's ID — if there are cross-references in body text, the synthesizer isn't catching them.

---

### Smell 9 — trends.md grows but scores are identical pass-over-pass

**What it looks like.** Every bead's score is the same across 5 passes.

**Diagnosis.** Re-verification mode is too aggressively caching (per `COST-OPTIMIZATION.md` `⟴ AMORTIZE`); evidence files HAVE changed but the cache hit detection is broken.

**Fix.** Force a cache-bust: delete `passes/<latest>/beads/*/compliance.json` and re-run. If scores change, the caching was wrong. Tighten the diff check to include test files + project SHA.

---

### Smell 10 — Audit dir's git log shows commits not labeled "audit pass <UTC>"

**What it looks like.** `git -C <audit-dir> log --oneline` shows random commit messages, not the standard pass-commit format.

**Diagnosis.** Someone (human or a different agent) committed to the audit dir manually. The audit dir's history should be machine-generated only.

**Fix.** Inspect the rogue commits. If benign (e.g., manual rubric tuning), document in `MIGRATION_LOG.md`. If suspicious (tampering — see [ANTI-CORRUPTION.md](ANTI-CORRUPTION.md)), restore from a known-good pass and investigate.

---

### Smell 11 — manifest.json#tools lists empty values

**What it looks like.** `"cargo": ""`, `"go": ""`, `"jq": ""`.

**Diagnosis.** The bootstrap's tool-version probe failed for these tools but didn't error out. Either the tool was installed but doesn't support the probed flag, OR PATH is borked.

**Fix.** Audit the bootstrap script's per-tool VER_CMD logic. Each tool needs a working version-probe command.

---

### Smell 12 — Phase 10 spot-check passes but audit-reviewer subagent flags many disagreements

**What it looks like.** `convergence.json#criteria.rubric_consistency_pass: true` — but when you invoke `subagents/audit-reviewer.md` (10-bead spot-check) it finds deviations on 4 of 10.

**Diagnosis.** Phase 10's 5-sample spot-check is too small for the project's score variance. Increase `spot_check_count` in rubric.md.

**Fix.** Bump `spot_check_count: 10` (or more) and re-run convergence-check. Smaller projects can use 5; larger projects need more.

---

## Per-smell remediation matrix

| Smell | Detection | Severity | Fix in |
|------:|-----------|----------|--------|
| 1 | exec summary `0 false-closed` | HIGH | scorer subagent prompt |
| 2 | score histogram spike at threshold | HIGH | scorer subagent prompt |
| 3 | single closed_by_session dominates | LOW (often real signal) | trauma-guard.sh |
| 4 | convergence flips | MEDIUM | rubric.md threshold |
| 5 | Phase 4 verdicts MISSING | MEDIUM | project test runnability |
| 6 | same finding everywhere | LOW | theater-scan exclusion list |
| 7 | empty missing-items | HIGH | scorer subagent prompt |
| 8 | empty synthesis | MEDIUM | synthesize.py regex |
| 9 | identical scores pass-over-pass | MEDIUM | cache-busting in re-verification |
| 10 | rogue commits in audit dir | HIGH | manual investigation |
| 11 | empty tool versions | LOW | bootstrap-audit.sh |
| 12 | spot-check insufficient | MEDIUM | rubric.md spot_check_count |

---

## When to escalate to audit-reviewer

Three of more of these smells visible in a single pass → invoke `subagents/audit-reviewer.md` for a third-party review. The audit-reviewer's verdict (PASS / MARGINAL / FAIL) tells you whether the pass is salvageable or needs to be discarded.

Discard rules:

- audit-reviewer FAIL → discard the pass; rename `passes/<UTC>/` to `passes/<UTC>.discarded.<reason>/` (rare exception to "never delete a pass") and re-run.
- audit-reviewer MARGINAL → keep the pass but document the smell in `passes/<UTC>/known_issues.md`.
- audit-reviewer PASS → continue normal cadence.

---

## Self-test

After making any change to the audit's own scripts / subagents / rubric, run the audit on the **fixture library** (`AUDIT-FIXTURE-LIBRARY.md`):

```bash
~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
  ~/.claude/skills/beads-compliance-and-completion-verification/assets/fixtures/known-good \
  --threshold 700 --policy report-only
# Expected: 0 false-closed; convergence on second pass.

~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
  ~/.claude/skills/beads-compliance-and-completion-verification/assets/fixtures/known-bad \
  --threshold 700 --policy report-only
# Expected: 1 false-closed (the seeded theater bead).
```

If either fixture audit produces unexpected output, the audit's own logic has regressed. Bisect the recent changes.

---

## Anti-pattern: hiding smells

Don't:

- Loosen the threshold to make false-closed go to 0.
- Disable Phase 5 because it's "too noisy."
- Re-write the scorer to score generously to "respect the implementer."
- Delete passes that have ugly numbers.

Each of these makes the audit useless. The whole point of the skill is to surface unpleasant truths. If the unpleasant truths look wrong, debug them — don't suppress them.