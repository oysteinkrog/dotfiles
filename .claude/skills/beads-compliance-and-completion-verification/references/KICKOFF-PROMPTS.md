# KICKOFF-PROMPTS.md — User-Facing Prompts To Start An Audit

<!-- TOC: Variant A (Full audit) | Variant B (Closed-only delta) | Variant C (Single bead) | Variant D (Re-verification) | Variant E (Tripwire/CI) | Variant F (Label-scoped) | Variant G (Mega ambition) | Variant H (Onboarding) | Variant I (Multi-repo) | Variant J (Performance) | Variant K (Security) | Variant L (Closer-scoped) | Up-front confirmations | Inline-fallback prompts | Polish-pass prompts -->

Frozen verbatim templates the user (or an orchestrator agent) can paste to invoke this skill. The variants below have been refined to match the prompt patterns mined from `/cass` for similar audit-style skills (`/reality-check-for-project`, `/mock-code-finder`, `/multi-pass-bug-hunting`).

> **The first 50 chars of any kickoff prompt are what the skill description matches against.** Front-load the trigger phrase; the rest of the prompt provides scope.

---

## Variant A — Full audit (first time on a project)

```
First read ALL of AGENTS.md and README.md and any plan/spec markdown documents
in this project SUPER carefully. Then run the beads compliance and completion
verification skill on this project.

I want a thorough audit of EVERY closed/completed/done bead. I do not trust the
status field. For each closed bead, I want to know:
  1. Did it actually get implemented?
  2. Are the tests it claimed actually passing AND meaningful?
  3. Is there theater (stubs, hardcoded returns, mocks-where-forbidden,
     `assert true`)?
  4. Does coverage meet the bead's threshold over the bead's specific code?
  5. Did the bead break any sibling beads?

Score each bead 0–1000 with cited evidence. Flag every false-closed (status
closed but score < 700). Then create completion-debt beads for the gaps.

Use ultrathink. Do all phases (1–10). Use parallel subagents for phases 2–6.
```

---

## Variant B — Closed-only delta (periodic re-verification)

```
Run the beads compliance audit on this project, but only for beads closed
since <git-ref or date>. Skip the open/in-progress universe.

I want the false-closed list and remediation beads — that's it. Skip Phase 7
synthesis if it would slow us down. Use threshold 700.
```

---

## Variant C — Single bead deep-dive

```
Verify bead <bd-XXX> was actually completed properly. Run the beads compliance
skill in single-bead mode.

Show me the full evidence pack: spec.json, evidence.json, compliance.json
(with raw test output), theater.json, test_depth.json, scorecard.md. I want
to be able to point at file:line for every claim.

If false-closed, propose the remediation bead but don't create it yet — let
me review first.
```

---

## Variant D — Re-verification (resume an existing audit dir)

```
Run another beads compliance audit pass on this project. The audit dir
already exists at <project>/beads_compliance_audit/. Write the new pass
to passes/<UTC>/.

For every false-closed bead from the prior pass, check whether the
remediation bead is now closed and the original re-passes the threshold.
Update trends.md. Re-check convergence.

If converged, tell me. If not, list the next-pass tasks.
```

---

## Variant E — Tripwire / CI mode (autonomous)

```
Re-run the beads compliance audit (re-verification mode) on this project.
Compare to the prior pass. If max_score_delta > 10 OR new_false_closed > 0,
exit non-zero so the CI gate fires. Otherwise exit 0.

No human in the loop. policy=report-only (do not write new beads from CI).
Save the convergence.json and the latest REPORT.md as artifacts.
```

---

## Variant F — Targeted subsystem audit (label-scoped)

```
Run the beads compliance audit, but scope it to beads with label "<label>".
For example: only the "billing" subsystem, only "auth", only "indexing".

I want to know: of the X closed beads tagged with this label, how many are
actually done? Use the standard rubric and threshold 700.
```

---

## Variant G — Mega-prompt (chains audit → ambition rounds → remediation beads in one shot)

```
Run the beads compliance audit on this project. THEN, for every false-closed
bead, do TWO ambition rounds — that is, after generating the missing-items
list for each, ask:
  1. "Is this missing-items list comprehensive? What did I miss?"
  2. "What's the cleverest, most thorough way to remediate this gap?"

THEN create the completion-debt beads with the refined missing items as
acceptance criteria. Then run /beads-workflow polish prompt 3 times on the
new beads.

Do not implement anything — implementation happens in a separate session.
This is plan-space refinement only.
```

---

## Variant H — Onboarding audit (first audit on a project that has never been audited)

```
This project has never had a beads compliance audit before. Run the audit
in onboarding mode:
  - threshold 600 (lenient for first pass — we'll tighten over passes)
  - mode=full-audit
  - policy=completion-debt

I expect a high false-closed rate (40-60%). That's normal for a first audit.
The point is to discover the project's specific patterns and tighten the
rubric over the next 2-3 passes.

Pre-Phase-1: mine /cass for prior agent sessions on this project. Identify
which agents close beads frequently and which patterns of theater are
common in this codebase. Add those to the project's rubric.md as
project-specific patterns.
```

---

## Variant I — Multi-repo workspace roll-up

```
Run the beads compliance audit on every repo under <PROJECTS_DIR> that has
a .beads/ directory. Use /ru to discover and parallelize.

Produce a portfolio summary at <PROJECTS_DIR>/__audit_portfolio_summary.md
with one row per repo: project_name, total_beads, false_closed_count,
score_median, convergence_status.

Use threshold 700 unless the repo has a rubric.md with its own threshold.
Use policy=report-only (don't write beads across N repos in one go).
```

---

## Variant J — Performance regression hunt (audit beads with performance budgets)

```
Run the beads compliance audit, but ONLY on beads that mention a performance
budget (latency, throughput, p50/p95/p99, memory ceiling). For each:

  1. Find the benchmark cited in the bead.
  2. Re-run it with /profiling-software-performance methodology.
  3. Compare the measured value to the bead's stated budget.
  4. If exceeded, mark the bead false-closed regardless of the standard rubric.

Output a perf-regression-list.md with the magnitude of each regression.
```

---

## Variant K — Security-bead audit

```
Run the beads compliance audit, but ONLY on beads with type=bug AND label
"security" OR labels "auth" / "rbac" / "csrf" / "xss" / "injection" /
"crypto". For each:

  1. Confirm the regression test actually fails on the prior commit (BISECT).
  2. Confirm the fix is present on HEAD.
  3. Check for /security-audit-for-saas patterns adjacent to the fix that
     might have been missed.
  4. Cross-reference with /testing-fuzzing — was a fuzzer added for the
     attack class?
```

---

## Variant L — "I don't trust this agent" (closer-scoped audit)

```
Audit every bead closed by session <session-id> OR by agent <agent-name>.
I have reason to believe this agent has been status-flipping without
implementing.

Use the standard rubric. Bonus: cross-reference closed_by_session in
each bead's history; if the same session closed multiple beads in the
same minute, flag for batch-close investigation.
```

---

## Up-front confirmation prompts (for the SKILL to ask the user)

The skill itself should confirm:

```
Before I start the audit, please confirm:

1. Project path: <auto-detected absolute path>. OK?
2. Audit dir name: <project>/beads_compliance_audit (subdirectory of the
   project; auto-added to project .gitignore). OK to create + git init?
3. Mode: <auto-suggested mode based on br stats>. Want a different mode?
4. Score threshold: 700 (default). Tighter / looser?
5. Parallelism: 6 subagents per parallel phase. Different cap?
6. Resume? <if existing audit dir>. New dated pass under passes/, or fresh
   restart (requires opt-in)?
7. Remediation policy: completion-debt (default), reopen, or report-only?
8. Test execution OK? (Phase 4 actually runs tests, fuzzers, real-service
   e2e per /testing-real-service-e2e-no-mocks. Confirm this is safe — no
   prod DBs touched, no rate-limited APIs without sandboxes.)
9. CASS available + indexed? (If yes, I'll mine prior sessions for
   project-specific false-closed patterns before Phase 1.)
```

---

## Inline-fallback prompts (when a referenced skill isn't installed)

If a helper skill is missing and `jsm` cannot install it (no subscription /
no auth), the orchestrator should still continue. The fallback prompt for
each missing skill:

```
The helper skill /<name> is not installed. I'll use an inline fallback for
the corresponding phase:

  /mock-code-finder       → use the rg/ast-grep patterns in FAILURE-MODES.md
  /testing-conformance-*  → use the bead's stated MUST-clause threshold only
  /testing-fuzzing        → check corpus + duration + crashes only
  /testing-golden-*       → check existence + freshness + diff only
  /testing-real-service-* → require evidence in raw/ logs that real services
                            were hit (any line containing "200 OK" / SDK
                            method names / etc.); do NOT mark UNVERIFIED
  /multi-model-triangulation → skip Phase 10 triangulation; record as
                               "unverified by independent model"

The audit will still complete; it just loses richness in the corresponding
phase. The manifest records what tooling was/wasn't available so trends
across passes are interpretable.
```

---

## Polish-pass prompts (between phases)

**After Phase 1 inventory** (orient the user before fan-out):

```
Inventoried <N> beads (<X> open, <Y> in-progress, <Z> closed). The closed
universe is <Z>. False-closed risk: <Z * historical-rate>% ≈ <est> beads.
Estimated wall time for full audit: <bead_count * 30s parallel> minutes.
Proceed with Phase 2?
```

**After Phase 8 master report** (orient the user before remediation):

```
Phase 8 complete. <N> false-closed beads identified.

Top 5 worst:
1. <bd-XXX> (score <S>) — <one-line-reason>
2. ...

Phase 9 will <reopen | create completion-debt for | only report> these per
the policy you chose. Proceed with Phase 9, or change the policy first?
```

**After Phase 10 convergence**:

```
Pass complete. Convergence verdict: <true | false>.

If converged: the bead graph is now truthful. Recommended cadence going
forward: weekly during active development, monthly during maintenance.

If not converged: <next_pass_tasks>. Re-invoke this skill after the
remediation work has landed (typically 1-2 weeks).
```

---

## Variant 13 — Pre-merge gate (single bead from a PR)

```
A PR claims to close `<bd-XXX>`. Before merge, run a single-bead audit:
  scripts/single-bead-audit.sh <project-path> <bd-XXX> --threshold 700 \
    --policy report-only
Exit 0 = green-light merge; exit 2 = block + paste the report into the PR.
```

## Variant 14 — Spec quality gate (pre-claim)

```
About to claim `<bd-XXX>` for implementation. First, score its spec for
auditability:
  scripts/spec-quality-gate.sh <project-path> <bd-XXX> --policy advise

If verdict is REWRITE BEFORE CLAIM, hand the bead back to the author with
the heuristic notes. If verdict is GOOD ENOUGH or better, proceed.
```

## Variant 15 — Time-machine audit (production fire)

```
Production incident at <SHA>. Run an audit AS-OF that commit to identify
which closed beads SHOULD have caught the failure mode:
  scripts/time-machine-audit.sh <project-path> <SHA> --mode comprehensive
Then read the resulting REPORT.md filtered to beads with the affected
feature label.
```

## Variant 16 — Bisect a regression

```
Bead `<bd-XXX>` regressed from <prior-score> to <current-score> across the
last two passes. Localize the offending commit:
  scripts/bisect-regression.sh <project-path> <bd-XXX>
Output: a single SHA + the diff that introduced the regression.
```

## Variant 17 — Reproducibility check (audit-of-audit)

```
Verify the latest pass is deterministic by re-scoring every bead from the
existing evidence packs:
  python3 scripts/reproducibility-check.py <audit-dir>/passes/<latest>
Drift = score-bead.py is reading non-deterministic input. Fix before next
pass.
```

## Variant 18 — Red-team the rubric

```
Pre-discover ways a clever closer could fool the audit:
  Invoke subagents/red-team-adversary.md against the latest pass.
Read audit_resilience.json and tighten the rubric per the BLOCKING patches.
```

## Variant 19 — Release gate (GO / NO-GO)

```
We're cutting release v<X.Y.Z>. Apply our release policy to the latest
audit pass:
  Invoke subagents/release-gate-keeper.md
Returns GO with a green light, or NO-GO with explicit blocker enumeration.
```

## Variant 20 — Audience explanation (PM/exec/customer/regulator)

```
Translate the latest audit pass for <audience>:
  Invoke subagents/audit-self-explainer.md --audience <pm|exec|customer|regulator|dev-onboarding>
Output: an audience-tailored markdown that preserves technical truth.
```

## Variant 21 — Diff vs prior pass

```
What changed since last pass?
  scripts/diff-passes.sh <audit-dir>
Returns headline KPI deltas, top regressors, top improvers, newly false-
closed, newly recovered, universe changes.
```

## Variant 22 — Discover stack profile

```
Before configuring per-language defaults, scan the project's stack:
  scripts/discover-stack.sh <project-path>
Returns a JSON profile: primary language, build/test/coverage/fuzz/bench
commands, monorepo shape, CI presence, container hygiene.
```

## Variant 23 — Validate the audit dir itself

```
Sanity-check the audit dir before consumption:
  python3 scripts/validate-audit-dir.py <audit-dir>
  python3 scripts/validate-rubric.py <audit-dir>/rubric.md \
    --manifest <audit-dir>/manifest.json
  python3 scripts/validate-evidence.py <audit-dir>/passes/<latest>
Three errors = stop and fix; 0 errors = safe to score / report / publish.
```

## Variant 24 — Multi-model committee (high-stakes pre-release)

```
Pre-release / regulator-bound audit. Run committee mode:
  Configure audit-policy.yaml#subagents to enable parallel model fan-out
  for Phase 4, 5, 7, 10. Combine per the rules in MULTI-MODEL-COMMITTEE.md.
Output: committee.json with per-bead disagreements + final verdict.
```
