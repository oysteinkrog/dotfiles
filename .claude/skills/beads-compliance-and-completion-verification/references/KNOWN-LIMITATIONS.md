# KNOWN-LIMITATIONS.md — What This Skill Can't Do

<!-- TOC: Architectural limits | Tooling limits | Domain limits | Scale limits | When to use a different tool -->

> Honest limits, documented up front. The skill does many things well — and some things not at all. If your use case hits one of these, plan around it.

---

## Architectural limits

### 1. Can't audit non-beads issue trackers

The skill assumes `br` and a `.beads/` directory. JIRA / Linear / GitHub Issues / Asana — none of these expose data in a form the skill can consume.

**Workaround:** Migrate to beads (one-time pain, ongoing benefit) OR adapt the skill's kernel ideas (not the implementation) to your tracker.

### 2. Can't measure "did the user benefit?"

The audit verifies that the bead's *claim* is true. It can't tell whether the user saw an improvement. A perfectly-implemented feature that nobody uses is still a "verified" bead.

**Workaround:** Compose with `/saas-customer-analytics` for behavioral metrics; the audit handles the bead-graph layer.

### 3. Can't generate beads from scratch

The audit verifies existing beads; it doesn't create them. For new work, use `/beads-workflow` + `/idea-wizard`.

### 4. Can't fix code

Phase 9 reopens or creates completion-debt beads — it doesn't write code. Implementation happens in a separate session by an agent that picks up the new bead.

### 5. Can't replace human judgment

For decisions like "should we tighten the rubric?", "is this defense valid?", "should we tombstone this bead?" — humans are required.

---

## Tooling limits

### 6. Can't audit if `br doctor` fails

If the bead store is corrupt, the audit hands off to `/fixing-beads-problems`. Until that's resolved, no audit.

### 7. Can't always run language-specific tests

For Phase 4 to actually re-execute tests, the project's test runner must be on PATH and the project must be in a testable state. If `cargo test` fails because deps aren't fetched, the audit reports MISSING — accurately, but unhelpfully.

**Workaround:** Run `cargo build` (or equivalent) once before invoking the audit.

### 8. Can't handle non-text artifacts

The skill scans text files. Binary artifacts (compiled WASM, JPEGs in goldens, ML model files) can be cited as evidence but not internally inspected for theater.

**Workaround:** For binary goldens, use checksum stability checks. For other binaries, the audit accepts them at face value.

### 9. Can't detect compiler-level theater

If the project is in Rust and the closer used `#[cfg(test)]` impl blocks that the compiler optimizes out, Phase 5's grep-based scan may miss it.

**Workaround:** Use `cargo expand` to inspect post-macro code; not yet integrated into the audit.

### 10. Can't verify cross-machine reproducibility

The audit runs on one machine. If a test passes on this machine but would fail on the deploy machine (due to env differences), the audit reports PASS.

**Workaround:** Run the audit in CI on the same OS/arch as deployment.

---

## Domain limits

### 11. Can't deeply audit ML-model beads

A bead claiming "trained model achieves 95% accuracy on dataset X" can be checked via test runs (model file exists, accuracy script outputs 95%) but not for whether the *training procedure* was sound, the *dataset* is representative, or the *95%* is gameable.

**Workaround:** Use a domain-expert review for the training-procedure / dataset / metric-gameability audit; this skill verifies the bead's surface claims.

### 12. Can't audit infrastructure beads end-to-end

A bead claiming "deployed to AWS region us-east-1" can be checked via Terraform plan output, but the audit can't confirm the deployment is actually live and serving traffic.

**Workaround:** Compose with monitoring (Prometheus/Datadog); this skill verifies the artifact, not the live state.

### 13. Can't audit beads about external services

A bead claiming "integrated with Stripe webhook" can be checked via signature verification + Stripe sandbox; it can't be checked against Stripe's *production* behavior.

**Workaround:** Per [BEAD-TYPE-PLAYBOOKS.md](BEAD-TYPE-PLAYBOOKS.md), use `/testing-real-service-e2e-no-mocks` patterns; the audit verifies the test exists and runs against real-mode endpoints.

### 14. Can't audit beads about UX / design quality

A bead claiming "improved checkout UX" doesn't have a numeric verification. The audit can confirm files changed and tests pass; it can't confirm users find the new UX better.

**Workaround:** Compose with `/ux-audit` and A/B test results; this skill audits the implementation surface.

### 15. Can't audit beads where the spec is non-falsifiable

A bead saying "improved code quality" can't be falsified by the audit. The spec is too vague.

**Workaround:** Use `bead-author-feedback` subagent at bead-creation time to push for falsifiable ACs.

---

## Scale limits

### 16. Linear cost in bead count

Each bead adds ~30 seconds to a Standard-mode pass at Squad tier. A 5000-bead project = ~40 hours of audit time. This is impractical without:

- **Aggressive caching** (per `COST-OPTIMIZATION.md`).
- **Tier upgrade** (Swarm with `/multi-agent-swarm-workflow`).
- **Mode downgrade** (Triage or Tripwire instead of Standard).

### 17. Sub-linear synthesis cost

Phase 7 reads every per-bead report. For 1000+ beads, this exceeds a single subagent's context. The synthesizer falls back to per-domain syntheses + meta-synthesis (the `⌬ HARMONIZE` operator), which works but loses some cross-domain integration signal.

### 18. Convergence takes 3-5 passes

Real convergence requires multiple passes spread over weeks. For projects expecting "one-shot" audit results, this is a structural mismatch — the skill is designed for sustained verification, not point-in-time snapshots.

### 19. Audit dir grows monotonically

Every pass adds a `passes/<UTC>/` directory. After 100 passes, the audit dir is ~100MB-1GB depending on bead count. No automatic pruning.

**Workaround:** Manually archive old passes (pre-1.0 ones, say) to S3; symlink them back if needed for time-machine queries.

### 20. Tripwire can't be too frequent

Sub-15-minute tripwire intervals risk overlap with prior passes (pre-flight lockfile prevents concurrency, but daemons may queue indefinitely). Practical floor: hourly.

---

## Methodological limits

### 21. Deterministic ≠ correct

The rubric is *deterministic* — same inputs, same score. That doesn't mean the rubric is *right*. A bad rubric deterministically produces bad scores.

**Mitigation:** Periodically Phase-10 spot-check; tune rubric per [POST-MORTEM-MODE.md](POST-MORTEM-MODE.md) when incidents reveal gaps.

### 22. False positives are inevitable

The audit will sometimes flag beads that are actually fine. The closer-defense flow exists for this; not all false positives have defenses.

**Mitigation:** Track false-positive rate per pass; if > 10%, tighten the patterns.

### 23. False negatives are also inevitable

The audit will sometimes miss real false-closures. Phase 5's pattern catalog isn't exhaustive.

**Mitigation:** Per `CONTRIBUTING-PATTERNS.md`, add new patterns when they're discovered. The catalog grows over time.

### 24. Can't catch what the bead doesn't claim

If a bead body says nothing about security, the audit can't dock the bead for missing security tests. The implicit-requirement injection (`⊡ FRAME` operator) helps but isn't comprehensive.

**Mitigation:** Use `bead-author-feedback` at bead-creation to push for more complete specs.

---

## Cultural / process limits

### 25. Requires team buy-in

If the team doesn't act on remediation beads, the audit becomes noise. A pile of completion-debt beads with no assignees is not the skill's failure — but it's the symptom of low buy-in that limits skill value.

### 26. Surfaces unpleasant truths

The audit's output can be uncomfortable — naming agents whose closures were sloppy, naming sessions with theater patterns, naming the project's drift. Cultures that punish messengers will reject the audit.

**Mitigation:** Frame results as graph maintenance, not blame. The skill is the messenger; the message is "the bead graph drifted; let's fix it."

### 27. Doesn't replace process discipline

A team that closes beads without verification will close fast and get audited slowly. The audit catches drift after the fact; better discipline (pre-merge bead audits, bead-author-feedback at creation) prevents drift in the first place.

---

## When to use a different tool

| You want | Use this | Not this |
|----------|----------|----------|
| Find a specific stub by grep | `/mock-code-finder` | this skill |
| Test runtime behavior | dynamic analyzer | this skill |
| Verify a single PR | `/multi-pass-bug-hunting` per-file | this skill (single-bead mode is also valid) |
| Architecture review | senior engineer | this skill |
| Customer-impact analysis | `/saas-customer-analytics` | this skill |
| Track agent-efficiency over time | this skill (trauma-guard) | none of the above |
| Bead-graph triage / prioritization | `/bv` | this skill |

---

## What's improving in the next versions

Planned for the next versions (a future `CHANGELOG.md` will track this):

- 1.1 — Rubric inheritance (less per-project boilerplate).
- 1.1 — Validation script for rubric.md (catches typos pre-bootstrap).
- 1.2 — `/multi-agent-swarm-workflow` integration for true Swarm-tier audits.
- 1.2 — Live HTML dashboard with WebSocket updates.
- 2.0 — Hypothetical scoring scale change (0-1000 → 0-100).

---

## How to file a real limitation

If you hit a limitation not listed here:

1. Confirm it's not a bug (try [DEBUGGING-THE-AUDIT.md](DEBUGGING-THE-AUDIT.md)).
2. Confirm it's not just a misuse (re-read [DESIGN-PHILOSOPHY.md](DESIGN-PHILOSOPHY.md)).
3. Add it to this file with a workaround if any.
4. If applicable, add a fixture to [AUDIT-FIXTURE-LIBRARY.md](AUDIT-FIXTURE-LIBRARY.md) that demonstrates the limit.
5. Bump the rubric / skill version per [CONTRIBUTING-PATTERNS.md](CONTRIBUTING-PATTERNS.md) flow.

The skill is itself a project — its limitations should be cataloged the same way it catalogs project limitations.
