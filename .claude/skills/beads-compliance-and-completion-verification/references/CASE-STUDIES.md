# CASE-STUDIES.md — Worked Examples

<!-- TOC: 1. Classic false-closed feature | 2. Healthy bead that nearly scored low | 3. Epic with abandoned children | 4. Performance bead with regression | 5. Security bead missing fuzz | 6. Migration without rollback | 7. Stuck bead across 4 passes | 8. Yo-yo bead | 9. Cross-bead contract drift | 10. Multi-repo portfolio find -->

> These are realistic narratives, not literal session transcripts. Bead IDs / file paths are illustrative. Read these to *prime your pattern recognition* before running an audit on an unfamiliar project.

---

## 1. Classic false-closed feature

**Context.** Project: `frankensqlite`. Bead `bd-parser01`, type=feature, P1, closed two weeks ago by session `2026-04-15-claude-code-abc`.

**Bead body.**
> Implement parser at `src/parser.rs` supporting the SQL `WITH RECURSIVE` clause. Tests at `tests/parser_recursive_test.rs`. 80% line coverage. Add a fuzz target that runs for 60s in CI.
>
> Acceptance criteria:
> - parses `WITH RECURSIVE` with CTE join
> - parses `WITH RECURSIVE` with column-list
> - rejects `WITH RECURSIVE` without anchor query
> - fuzz target runs 60s in CI without crashes

**Phase 4 verdict.** Unit tests PASS (3/3 assertions). Build PASS. Fuzz target compiles AND runs for 60s with zero crashes.

**Phase 5 finding.** `theater.json` flags `src/parser.rs:312` returning `Ok(Default::default())` in the error-recovery branch (the third AC: "rejects without anchor query"). Severity: BLOCKING. `invalidates_phase4_check: tests.unit.test_parse_no_anchor`.

**Phase 6 finding.** Coverage of `src/parser.rs` is 78% line — under the 80% threshold. PARTIAL.

**Phase 8 score.**
- Implementation completeness: 240/300 (the error-recovery path returns Default rather than the partial AST the spec required)
- Tests present + passing: 100/250 (the third AC's test "passes" only because the impl short-circuits; theater invalidates it)
- Anti-theater: 50/150 (one BLOCKING finding × 50 + miscellaneous TODOs)
- Test depth: 90/150 (78% line, fuzz corpus is 0)
- Docs / etc: 80/100
- Cross-bead: 50/50
- **Total: 612/1000** → 🟠 False-closed (mild)

**Remediation.** Completion-debt bead `bd-parser01.1` created with the verbatim missing items: implement real error-recovery, seed fuzz corpus with 50 inputs, fix line coverage to 80%.

**Lesson.** The bead "looked done" by every count: the tests existed and passed, the fuzz target ran without crashes, the file was at the cited path. But the third AC's test passed *trivially* because the implementation never failed. This is the prototypical theater pattern — and the prototypical use case for this skill.

---

## 2. Healthy bead that nearly scored low

**Context.** Same project, bead `bd-parser02`, type=docs, closed yesterday.

**Bead body.**
> Add README section explaining the `WITH RECURSIVE` parser usage with two code examples.

**Phase 3 finding.** `evidence.json` finds `README.md` updated in the closing commit (`def5678`) — section "Recursive CTEs" added at lines 142-180.

**Phase 4 finding.** `cargo build` for `cargo run --example recursive_basic` PASS. The two doc-block code examples compile and run without error. Docs link-check PASS.

**Phase 5 finding.** No theater. The two code examples have no `// TODO` markers, no `// might not work` hedges.

**Phase 6 finding.** Docs WAIVED for line coverage; the two examples were verified runnable.

**Phase 8 score.**
- For docs beads, dimension 5 (docs) is weighted 750/1000.
- Docs items present: 3/3 (section, example 1, example 2).
- Docs depth (link-check, code-runs): PASS.
- **Total: 875/1000** → 🟢 Substantially complete.

**Lesson.** Docs beads are scored on docs-dimension dominance. If we'd applied the default feature/bug rubric, this bead would have scored ~600 (no tests, no implementation file). Per-bead-type weighting matters.

---

## 3. Epic with abandoned children

**Context.** Project: `ntm`. Bead `bd-mux-rewrite`, type=epic, P0, closed last month.

**Bead body.**
> Epic: rewrite tmux session manager from bash to Go. See child beads bd-mux-1 through bd-mux-7.

**Phase 1 finding.** `git_xref.txt` shows zero commits mentioning `bd-mux-rewrite`. Children:
- `bd-mux-1`: closed
- `bd-mux-2`: closed
- `bd-mux-3`: open
- `bd-mux-4`: open
- `bd-mux-5`: blocked (by bd-mux-3)
- `bd-mux-6`: deferred
- `bd-mux-7`: tombstoned

**Phase 7 synthesis.** Anomaly: epic claims done but 4 of 7 children are not closed. Bead-graph truthfulness flag.

**Phase 8 score.**
- Epic dimension 6 (cross-bead) max is 500.
- 3/7 children closed, 4/7 not closed → -200 penalty.
- No integration test exists.
- **Total: 280/1000** → 🔴 False-closed (severe).

**Remediation.** Reopen the epic. Open beads must close (or be tombstoned with rationale) before the epic can re-close.

**Lesson.** Epic beads can't be "done" if their children aren't. The per-type rubric makes this automatic.

---

## 4. Performance bead with regression

**Context.** Project: `frankensqlite`. Bead `bd-perf-04`, type=feature with `perf` label, P1.

**Bead body.**
> Optimize `parse_query()` to be 1.5x faster than current. Bench in `benches/parser_bench.rs`. p95 latency must be < 2ms.

**Phase 4 finding.** Bench runs successfully. Reported median 1.7ms, p95 2.3ms.

**Phase 5 finding.** No theater.

**Phase 6 finding.** Statistical significance: 30 samples, CI [1.6, 1.9] for median. p95 of 2.3ms exceeds the budget of 2ms. The 1.5x improvement claim measured against an ambiguous baseline.

**Phase 8 score.**
- Per `BEAD-TYPE-PLAYBOOKS.md` performance recipe: missed budget → dimension 1 score → 0.
- **Total: 290/1000** → 🔴 False-closed (severe).

**Remediation.** The bead is *technically* implemented but doesn't satisfy its budget. Completion-debt bead requires either (a) further optimization to hit the 2ms p95, or (b) explicit rebaseline with rationale.

**Lesson.** Performance beads have hard numeric gates. "It's faster" is not "it meets the budget."

---

## 5. Security bead missing fuzz

**Context.** Project: webapp. Bead `bd-csrf-fix`, type=bug with `security` label.

**Bead body.**
> Fix CSRF token validation in `src/auth/middleware.ts`. Add a regression test. Add a fuzz target for the auth-cookie parser.

**Phase 4 finding.** Regression test PASS. BISECT-verify: test fails on parent commit, passes on fix commit. ✓ Real regression test.

**Phase 5 finding.** No theater in the implementation.

**Phase 6 finding.** No fuzz target exists at the expected path. The bead's implicit security requirement (fuzz coverage of attack class) is unmet.

**Phase 8 score.**
- Per security-bead playbook: implicit fuzz requirement weighted into dimension 2.
- Test dimension: 175/250 (regression test ✓, but fuzz missing).
- Other dimensions full.
- **Total: 825/1000** → 🟢 Substantially complete.

**Remediation.** Not flagged as false-closed (above threshold) but completion-debt bead created for the missing fuzzer. Lower priority since the regression is verified.

**Lesson.** Security beads have implicit requirements (fuzz coverage). The score reflects partial fulfillment but doesn't punish below threshold when the *primary* fix is verified.

---

## 6. Migration without rollback

**Context.** Project: SaaS app. Bead `bd-schema-migrate`, type=chore.

**Bead body.**
> Migrate `users` table to add `last_login_at` column. Migration in `db/migrations/20260415_add_last_login_at.sql`.

**Phase 4 finding.** Forward migration applies cleanly to a fresh DB.

**Phase 5 finding.** Theater pattern 29: migration's `down()` is empty. BLOCKING per migration-bead playbook.

**Phase 6 finding.** Reverse migration: not testable (empty). FAIL.

**Phase 8 score.**
- Implementation: 200/300 (forward exists; reverse missing).
- Tests: 100/250 (forward verified; reverse unverified).
- Anti-theater: 80/150 (one BLOCKING for empty down).
- **Total: 580/1000** → 🟠 False-closed (mild).

**Remediation.** Completion-debt bead requires implementing reverse migration OR documenting one-way intent with `// IRREVERSIBLE: <reason>` comment.

**Lesson.** Migration beads have specific implicit requirements. An empty `down()` is theater unless explicitly justified.

---

## 7. Stuck bead across 4 passes

**Context.** Bead `bd-foo` scored 612 in Pass 1, 615 in Pass 2, 608 in Pass 3, 612 in Pass 4. Trajectory: stuck.

**Synthesis finding.** The completion-debt bead `bd-foo.1` exists but has no assignee and is blocked by `bd-prereq` which is also open.

**Recommendation.** Per `MULTI-PASS-FLOW.md` cross-pass diagnostic: either assign bd-foo.1 to a specific agent OR resolve bd-prereq first OR mark the original as won't-fix-tombstoned.

**Lesson.** Stuck beads are a *triage* signal, not an audit failure. The audit's job is to surface them; humans (or higher-level orchestrators) decide what to do.

---

## 8. Yo-yo bead

**Context.** Bead `bd-bar` scored 950 in Pass 1, 600 in Pass 2, 920 in Pass 3, 580 in Pass 4. Trajectory: yo-yo.

**Synthesis finding.** The bead's primary file `src/x.rs` is being modified by every other recent commit. The score oscillates because un-related changes regularly break + restore the bead's expected behavior.

**Recommendation.** Either (a) tighten the bead's scope so the audit doesn't catch unrelated drift, or (b) accept that this bead is now functioning as a "regression sentinel" and the alerts are working as intended.

**Lesson.** Yo-yo trajectories are noise + signal mixed. The scoring is correct; what to do about it is a project-management question.

---

## 9. Cross-bead contract drift

**Context.** Bead A (`bd-emit-events`) emits `{user_id, score: float}`. Bead B (`bd-consume-events`) consumes events, parses `{userId, rating: int}`. Both closed; both individually pass their per-bead audits.

**Phase 7 synthesis finding.** Integration gap: producer emits `score: float`, consumer parses `rating: int`. Field name mismatch + type mismatch. The system doesn't actually function end-to-end.

**Phase 8 dimension 6 impact.** Both beads receive a -25 penalty on dimension 6 (cross-bead).

**Remediation.** Completion-debt bead created on whichever side the team decides to fix. The synthesis recommends the producer (since its naming `score: float` was the original design intent).

**Lesson.** This is the failure that no per-bead audit can find. Phase 7 is the only line of defense; without it, both beads remain "closed and passing" while the integration is broken.

---

## 10. Multi-repo portfolio find

**Context.** Portfolio audit across 18 repos. The roll-up shows:
- 17 of 18 projects: false-closed rate < 10%.
- 1 project (`midas-edge`): false-closed rate 36%.

**Drilling in.** `midas-edge`'s false-closed beads concentrate around `closed_by_session=2026-04-15-cod-789` — that single session closed 23 beads in one hour, 19 of which scored < 700.

**Pattern.** Batch-close anomaly. The session was likely ending and the agent cleared the active list.

**Recommendation per `CASS-MINING.md`.** Add `2026-04-15-cod-789` to `~/.audit/sloppy_sessions`. Future audits start every bead closed by that session with a -25 penalty.

**Bigger recommendation.** Have a human conversation with the operator who ran that session (or, if it's an automated agent, retrain the prompt on close-quality standards).

**Lesson.** The portfolio view surfaces patterns that per-project audits miss. One agent / one session can corrupt the bead graph at scale; the portfolio audit catches the concentrated damage.

---

## 11. The 15/15 false-positive cohort (calibration evidence)

**Project.** beads_rust, ~844 closed beads, May 2026.

**Initial pass output.** Run-pass.sh emitted:

```
Beads audited: 844
False-closed: 153 (18.1%)
Recommendation: DO NOT reopen the 153 flagged beads yet — this pass is
deterministic-only (Phase 4/6 stub).
```

The deterministic-only banner was correctly present, but a user skimming the headline would still file 153 reopen tickets.

**Ground-truth investigation.** The user manually audited the **15 lowest-scoring** beads (scores 200–505), reading specs, cited files, test runs, and git log for fix commits.

**Result: 15 / 15 were SCORE FALSE POSITIVES.** Every one of the lowest-band beads had real code, real tests, and real fixes shipped. The audit pipeline simply couldn't see them.

**Root causes (clustered):**

| Cohort size | Root cause | Fix |
|------------:|------------|-----|
| 3 beads | Spec extractor parsed prose-style example data ("field_name=123") as required source paths | LLM evidence-gatherer subagent (the deterministic baseline can't disambiguate prose) |
| 4 beads | Idiomatic Rust `#[cfg(test)] mod tests { ... }` flagged as `conditional_skip_in_test_mode` MAJOR theater | v1.2 theater-scan: language-aware cfg(test) pattern; `.rs` files only flag *runtime* `if cfg!(test)`, not the compile-time attribute |
| 1 bead | Bash `return 0` in helper script flagged as `hardcoded_return` MAJOR theater | v1.1 hardcoded-return language fix already covered this; bead pre-dated the fix |
| 3 beads | Bead's `.beads/issues.jsonl` runtime data file scanned as source code → false BLOCKING findings | v1.2 theater-scan: `.beads/`, `beads_compliance_audit/`, `.git/` paths excluded from scans |
| 1 bead | Cross-project bead pollution — `19my.*` references `/data/projects/ntm` paths in another repo | Audit-policy: project-scoped path allowlist (one of the few cases where prose-style ACs accidentally cite paths outside the project) |
| 3 beads | Spec-vs-evidence ID-scheme mismatch (`code.primary` vs `ac.X`) | v1.1 score-bead.py `_evidence_supersedes_spec()` fallback |

**Extrapolation.** Of the 153 flagged beads, ~5–10 are plausibly true false-closed (the "Forced close due to cycle" cohort and the snapshot-drift cohort); the other ~143 are pipeline artifacts. **The deterministic baseline overstated true false-closed by ~15–30×.**

**Remediation.** Phase 9 was overridden to `report-only` for this pass — autonomously creating 153 completion-debt beads would itself have been theater. The user wrote up `AUDIT_FINDINGS.md` documenting the case, and the lessons informed:

- v1.1 bug fixes (hardcoded-return language-aware patterns, evidence-supersedes-spec fallback, theater-scan range filtering, ARG_MAX disk-backed approach, gather-evidence directory guard)
- v1.2 calibration framing (master-report.py reframe headline + always-on calibration recommendation)
- v1.2 theater-scan tightening (`.beads/` exclusion, idiomatic Rust `#[cfg(test)]` exclusion)
- The new `scripts/calibrate-bottom-n.sh` helper and Hard Rule #3 ("Don't act on the deterministic-only headline")

**Lesson.** **The deterministic baseline produces an upper bound on suspicion, not a list of findings.** Always calibrate the bottom-N before recommending remediation. The ratio of "flagged" to "actually false-closed" varies by project (depending on spec style and language idioms), but is reliably 4–20× across observed runs. See [CALIBRATION-FRAMING.md](CALIBRATION-FRAMING.md) for the full prior and decision tree.

---

## How to use these case studies

When auditing a new project:

1. Read the case studies first to prime your pattern recognition.
2. As Phase 5 / 7 findings come in, ask: "Which case study does this resemble?"
3. If it matches one, apply that case study's remediation pattern.
4. If it doesn't match any, you may have discovered a new pattern — document it in `FAILURE-MODES.md` and add it here as case study #N+1.

**Adding a new case study.** Use the template at `assets/case-study-template.md` (if present) or copy the structure of any case above. Anchor every claim with the artifact path (`evidence.json#code.parser`, etc.). Real audits are far more useful than synthetic ones, but anonymize bead IDs and file paths if the project is sensitive.