# EXTENDED-INTEGRATION.md — Per-Skill Integration Playbooks

<!-- TOC: lean-formal-feedback-loop | extreme-software-optimization | security-audit-for-saas | admin-page-for-nextjs-sites | saas-customer-analytics | multi-model-triangulation | deadlock-finder-and-fixer | profiling-software-performance | de-slopify | gh-actions | testing-* family -->

> `INTEGRATION-WITH-OTHER-SKILLS.md` covers the high-level integration map. This file goes **deep** on each major partner skill: when to invoke, exactly which audit phase calls it, what evidence the partner skill produces, and how the audit folds it into scoring.

---

## /lean-formal-feedback-loop — formally proven beads

**When to invoke.** Bead's spec mentions "proof", "Lean", "formal verification", "invariant", "theorem".

**Audit phase that calls it.** Phase 4 (compliance verification) — the proof IS the compliance evidence.

**Evidence produced by partner skill.**
- `lean_proof.lean` — the proof text.
- `lean_check.stdout` — the Lean checker's output, must contain "✓ proven" or equivalent.
- `runtime_match.json` — verification that the Lean theorem's preconditions match the Rust code's actual runtime behavior (per `/lean-formal-feedback-loop` discipline).

**How the audit folds it in.**

```json
// compliance.json#checks[N]
{
  "spec_item_id": "tests.formal.invariant_X",
  "command": "lean --make src/proofs/invariant_X.lean",
  "exit_code": 0,
  "verdict": "PASS",
  "delegated_to": "/lean-formal-feedback-loop",
  "raw_path": "raw/lean_check.stdout",
  "summary": "Theorem invariant_X proved; runtime check confirms preconditions match Rust impl"
}
```

**Phase 8 weighting.** A formally-verified bead gets dimension 1 (implementation) full credit if the proof passes AND the runtime-match check confirms the proof's preconditions are realistic. If the proof passes but the runtime-match shows the preconditions are stronger than Rust's actual constraints, the bead's dimension 1 is reduced (the proof is over-approximating).

**Failure mode unique to this integration.** A bead claims "formally proven" but the Lean code only proves a trivial theorem (e.g., `theorem foo : True := trivial`). Phase 5 should detect this via the `⚖ MEAN` operator: read the Lean theorem text and verify it actually states the property the bead claimed.

---

## /extreme-software-optimization — performance-budget beads

**When to invoke.** Bead has type=feature/perf with a numeric budget (latency, throughput, memory).

**Audit phase that calls it.** Phase 4 (compliance) AND Phase 6 (depth) — measurement methodology + statistical significance.

**Evidence produced.**
- `bench_runs.json` — N samples per benchmark (N ≥ 30).
- `confidence_interval.json` — mean ± CI.
- `flamegraph.svg` — profile if hotspot diagnostics are needed.

**How the audit folds it in.**

The skill's "Behavior Proof" pattern: the optimization claim is verified end-to-end, not just at the micro-benchmark level. Per `BEAD-TYPE-PLAYBOOKS.md` performance recipe:

1. Phase 4 runs the benchmark per `/extreme-software-optimization` methodology.
2. Phase 6 verifies statistical significance (CI doesn't overlap the budget).
3. If measured > budget, dimension 1 → 0 regardless of code-existence.

**Special case.** Performance regressions caught via `/extreme-software-optimization` produce *flamegraph evidence* — a much higher-quality signal than wall-time alone. The auditor includes the flamegraph path in scorecard citations.

---

## Math-heavy / formally-rigorous beads

**When this applies.** Bead's spec mentions advanced math: "conformal", "Bayesian", "convex", "submodular", "queueing", "PID", "MPC", "graph theory", "control theory", etc.

**Audit phases.** Phase 5 (anti-theater for the math), Phase 6 (depth — does the implementation match the math?).

**Evidence the bead must produce.**
- `math_spec.md` — the precise mathematical spec the bead claims to implement.
- `derivation.md` — the derivation showing implementation correctly realizes the math.
- `tests/math_property_test.rs` — property tests that verify mathematical invariants (e.g., for a convex optimizer: solution is in the feasible region; objective decreases monotonically).

**How the audit folds it in.**

The bead's primary deliverable is *mathematically correct code*. The audit checks:

1. **Math spec is concrete.** Phase 5 catches "implements gradient descent" without specifying step size, convergence criterion, etc.
2. **Property tests verify invariants.** Phase 6 requires at least one property test per mathematical invariant.
3. **Behavior matches spec.** The `⚖ MEAN` operator: read the implementation, verify it does what the math says.

`VERIFICATION-UNDER-UNCERTAINTY.md` formalizes this with a Bayesian / conformal layer.

---

## /security-audit-for-saas — security-sensitive beads

**When to invoke.** Bead has `security` label OR mentions auth, RBAC, CSRF, XSS, SQLi, crypto, secrets, sessions.

**Audit phase that calls it.** Phase 5 (extended theater patterns) + Phase 7 (cross-bead — does this fix expose a related attack surface?).

**Evidence produced.**
- `threat_model.md` — what attack class the bead defends against.
- `regression_test.py` (or .rs / .ts) — BISECT-verifies the vulnerability existed before the fix.
- `fuzz_target.rs` — for input-handling attack classes.
- `adjacent_audit.md` — `/security-audit-for-saas` patterns adjacent to the fix.

**How the audit folds it in.**

Per `BEAD-TYPE-PLAYBOOKS.md` security recipe:

1. Phase 4: BISECT-verify the regression test fails before fix, passes after.
2. Phase 5: extended pattern set:
   - Hardcoded secrets in the diff.
   - `if !user.is_admin` patterns without actual permission check.
   - Mock auth in tests where real auth was claimed.
   - Silent disclosure (vulnerability info in error message / log).
3. Phase 7: adjacent attack-class check — if bead fixed CSRF on route A, is route B similarly protected?

**Special case.** A security bead with no fuzzer for an input-handling attack class is automatically downgraded to `🟡 Partial` regardless of the regression test passing. Fuzz-coverage is the differentiator between "fixed this one input" and "fixed this attack class."

---

## /admin-page-for-nextjs-sites — admin-route audits

**When to invoke.** Bead touches `/admin/*` routes OR `/api/admin/*` routes.

**Audit phase that calls it.** Phase 5 (privilege-escalation theater) + Phase 6 (admin-only access enforcement).

**Evidence produced.**
- `admin_route_audit.md` — per-route IA, permissions, audit trail.
- E2E test that confirms a non-admin user cannot reach the route.

**How the audit folds it in.**

Admin routes have a unique theater pattern: the route exists, the test passes (because the test user is admin), but the production middleware doesn't actually check admin status. The auditor:

1. Phase 4: e2e test with a non-admin user MUST receive 403.
2. Phase 5: search the route handler for `if (!session.isAdmin) return 403`. If absent OR if admin status comes from a request header (forgeable), BLOCKING.
3. Phase 7: cross-reference with audit-log emission — admin actions must emit an audit entry.

---

## /saas-customer-analytics — business-metric beads

**When to invoke.** Bead claims to compute MRR, churn, behavioral score, retention curve.

**Audit phase that calls it.** Phase 5 (hardcoded-score theater) + Phase 6 (statistical correctness of the metric).

**Evidence produced.**
- `metric_definition.md` — exact formula.
- `tests/metric_property_test.py` — property tests for the metric (e.g., MRR aggregation: sum of customer MRRs equals total MRR; churn rate: cohort logic correct).
- `comparison_to_baseline.md` — if replacing an existing metric, comparison values.

**How the audit folds it in.**

Per FAILURE-MODES.md Pattern 2 (hardcoded happy-path returns): a bead that "computes risk score" but always returns `3` is BLOCKING. The auditor:

1. Phase 5: search for hardcoded numeric returns in metric-claiming functions.
2. Phase 6: property test exists AND passes.
3. Phase 7: cross-bead — if another bead claims to consume this metric, verify the consumed shape matches.

---

## /multi-model-triangulation — Phase 10 cross-validation

**When to invoke.** Phase 10 of high-stakes audits (Comprehensive mode); when scorer disagreement is suspected.

**Audit phase that calls it.** Phase 10 (`⊞ TRIANGULATE` operator).

**Evidence produced.**
- `triangulation_results.json` — per-bead per-model derived score.

**How the audit folds it in.**

```bash
# In Phase 10 spot-check
SAMPLE=$(shuf -n 5 -e $(ls "$PASS_DIR/beads/"))
for ID in $SAMPLE; do
  # Spawn 3 independent agents to re-derive the score
  CLAUDE_SCORE=$(claude_agent score-bead "$ID")
  CODEX_SCORE=$(codex_agent score-bead "$ID")
  GEMINI_SCORE=$(gemini_agent score-bead "$ID")
  SCORER_SCORE=$(jq '.score' "$PASS_DIR/beads/$ID/score-summary.json")
  # Triangulation: if all 3 within ±50 of each other AND of scorer → calibrated
  # If any disagree by > 50 → flag for human review
done
```

The convergence.json gets a `triangulation_consensus` field showing per-bead agreement.

---

## /deadlock-finder-and-fixer — concurrency beads

**When to invoke.** Bead mentions: lock, mutex, deadlock, race, concurrency, atomic, RwLock.

**Audit phase that calls it.** Phase 4 (loom / shuttle / TLA+ checker invocations) + Phase 6 (deadlock-test depth).

**Evidence produced.**
- `loom_runs.json` — exhaustive interleaving search results.
- `tests/concurrency_test.rs` — tests using loom or shuttle.

**How the audit folds it in.**

Concurrency theater: a regression test that "passes" in a single-threaded harness but the bug only manifests under contention. Phase 6 requires the test be run under loom (Rust) / shuttle / pthread fuzzing for at least N iterations.

```rust
// What the bead's test should look like
#[test]
fn test_no_deadlock() {
    loom::model(|| {
        // Test body — loom explores all possible thread interleavings
    });
}
```

If the test isn't wrapped in `loom::model`, it doesn't actually verify deadlock-freedom.

---

## /profiling-software-performance — perf-budget enforcement

**When to invoke.** Bead has performance budget; complement to `/extreme-software-optimization`.

**Audit phase that calls it.** Phase 4 + Phase 6.

**Evidence produced.**
- `perf_profile.json` — flamegraph + hotspot summary.
- `regression_alert.json` — if perf regressed since prior pass.

**How the audit folds it in.**

This skill does the *measurement*. `/extreme-software-optimization` does the *fixing*. The audit cares about whether the measurement was done correctly:

1. Phase 4: bench is statistically significant (N ≥ 30, CI computed).
2. Phase 6: per-bead profile shows the bead's code is exercising the optimization (not the test harness).
3. Pass-over-pass: if median perf regressed since prior pass, flag in `synthesis.md`.

---

## /de-slopify — scorecard polish

**When to invoke.** Phase 8 final polish on every scorecard + `REPORT.md`.

**Audit phase that calls it.** Phase 8 (`⊙ DE-SLOP` operator).

**What it does.**
- Removes "comprehensive", "robust", "thorough", "extensive", "world-class" without numeric backing.
- Removes hedging adjectives ("kind of", "sort of", "fairly").
- Trims redundant prose.

The `subagents/scorer.md` includes `/de-slopify` in its discipline section. Every scorecard is run through the slop filter before being committed.

---

## /gh-actions — CI integration

**When to invoke.** Tripwire mode + when configuring per-project audit CI.

**Audit phase that calls it.** Bootstrap (write CI workflow) + Phase 4 (verify the bead's CI workflow exists if claimed).

**Evidence produced.**
- `.github/workflows/beads-tripwire.yml` — daily tripwire workflow.
- (For per-bead audits) `.github/workflows/pre-merge-bead-audit.yml`.

The per-bead pre-merge audit is the most powerful use: it prevents false-closures from happening in the first place by blocking PRs that close beads scoring < threshold. See `CI-TRIPWIRE.md`.

---

## /testing-* family (5 skills)

**When to invoke.** Per-test-type Phase 4 + Phase 6 verification.

| Skill | Phase 4 use | Phase 6 use |
|-------|-------------|-------------|
| `/testing-fuzzing` | Run fuzzer for stated duration | Verify corpus exists + no crashes + coverage of fuzzed code ≥ 60% |
| `/testing-conformance-harnesses` | Run conformance harness | Verify MUST clauses ≥ 0.95 pass |
| `/testing-golden-artifacts` | Regenerate goldens, diff | Verify artifacts fresh + scrubbing applied |
| `/testing-metamorphic` | Run MR tests | Verify each cited MR has a test |
| `/testing-real-service-e2e-no-mocks` (and synonym `/testing-perfect-e2e-...`) | Hit real DB / Stripe / Supabase | Verify structured-log evidence in raw/ |

Each skill's "what makes it real" rubric becomes a per-test-type depth check in `test_depth.json`.

---

## /idea-wizard — between-pass ambition rounds

**When to invoke.** Between Pass N and Pass N+1, on completion-debt beads.

**What it does.** Per `MULTI-PASS-FLOW.md`:

Round 1 ambition: "What ELSE is needed beyond the audit's missing items?"
Round 2 ambition: "What about edge cases / observability / downstream consumers?"
Round 3 ambition: "What testing techniques would catch the original gap?"

Output: revised `acceptance_criteria` on the completion-debt beads. Often produces 2-3× more comprehensive remediation than the audit alone identifies.

---

## /codebase-archaeology + /codebase-report

**When to invoke.** Onboarding mode (first audit on an unfamiliar project).

**What it does.** Builds a project-wide architecture model that informs Phase 3 evidence-gathering. With archaeology output, the auditor's spec-extractor knows where to look for canonical files.

Output: `phase0_archaeology.md` in the audit dir. Subsequent passes reference it but don't re-run.

---

## /agent-mail — multi-agent coordination

**When to invoke.** Squad / Swarm tier (when multiple subagents run in parallel).

**What it does.** File reservations for shared resources:
- The audit dir's `passes/<UTC>/` (only the orchestrator writes; each subagent reads + writes its bead's subdir).
- Shared test fixtures.
- DB ports (each compliance-verifier reserves a unique port).

The reservation reason is always the audit-pass thread ID: `audit-<PASS_ID>-bead-<bead-id>`.

---

## /commit-and-release — post-audit commits

**When to invoke.** End of every pass, when committing to the audit dir.

**What it does.** A single audit-pass commit with the format:

```
audit pass <ISO-UTC>: <total> beads, <fc> false-closed, score median <X>

Phase 1: <bead count + status breakdown>
Phase 9: created <N> completion-debt beads, reopened <M>
Convergence: <true|false>

🤖 Generated with /beads-compliance-and-completion-verification
```

---

## Skill family hierarchy

```
beads-compliance-and-completion-verification (this skill)
├── stands ON TOP of
│   ├── /beads-br + /beads-bv + /beads-workflow (the bead substrate)
│   ├── /mock-code-finder (Phase 5 primary tool)
│   ├── /multi-pass-bug-hunting (Phase 10 fresh-eyes pattern)
│   ├── /reality-check-for-project (synthesis pattern)
│   └── /operationalizing-expertise (operator-card framework)
├── DELEGATES TO
│   ├── /testing-* (per-test-type depth)
│   ├── /lean-formal-feedback-loop (formal proofs)
│   ├── /security-audit-for-saas (security beads)
│   ├── /extreme-software-optimization (perf beads)
│   ├── /deadlock-finder-and-fixer (concurrency beads)
│   └── /profiling-software-performance (perf measurement)
├── COMPOSES WITH
│   ├── /agent-mail (parallel coordination)
│   ├── /multi-agent-swarm-workflow (Swarm tier)
│   ├── /multi-model-triangulation (Phase 10 cross-validation)
│   ├── /cass (project-specific pattern mining)
│   └── /ru-multi-repo-workflow (portfolio audits)
├── INVOKES BETWEEN PASSES
│   ├── /idea-wizard (ambition rounds)
│   ├── /beads-workflow (plan-space refinement)
│   └── /de-slopify (scorecard polish)
└── BORROWS FROM
    ├── /documentation-website-for-software-project (mode variants)
    ├── /saas-billing-patterns (workspace dir + scope governor)
    └── /wills-and-estate-planning-skill (kernel + operators format)
```

---

## When to skip a delegation

Sometimes invoking the partner skill would cost more than the verification value:

- Delegating to `/testing-fuzzing` for a single fuzz-test verification: just run the fuzzer directly with `cargo fuzz run`. The skill's deeper analysis isn't needed.
- Delegating to `/security-audit-for-saas` for a typo fix in an auth comment: overkill.
- Delegating to `/multi-model-triangulation` in tripwire mode: cost > value.

The partner skills are *available*; invoke them when stakes warrant. The default audit pipeline doesn't auto-invoke them all — it lets the user / orchestrator decide based on bead type and audit mode.