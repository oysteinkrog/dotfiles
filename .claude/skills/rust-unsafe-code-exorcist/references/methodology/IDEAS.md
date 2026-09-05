# IDEAS.md — /idea-wizard Output Applied to This Skill

This file is the meta-application of /idea-wizard to the skill itself. Each idea names: the gap, the proposed addition, the cost, the benefit, and (where implemented in v2) the file paths that ship it.

The unifying narrative across these ideas: **transform the skill from a one-shot audit into a continuous safety platform for Rust projects.** A single audit is a snapshot. The skill's accretive value comes from the snapshots compounding over time.

The audit IS the artifact; but the audit's value extends only as far as the project's drift away from it. Ideas below close that drift gap, multiply the audit's test coverage, surface decisions that were always there but invisible, and turn the audit into a vocabulary the project's team can use daily.

---

## How to read this file

- **STATUS** column: `shipped` (implemented in v2), `partial` (skeleton in place; deepening welcome), `proposed` (not yet built; would extend the skill if added).
- **LEVERAGE** column: estimate of value-per-effort. `★★★★★` = highest leverage; `★` = niche.
- Each idea has a one-paragraph elaboration. The "Cost" line names the realistic implementation effort; the "Benefit" line names what changes for the user.

---

## Mega-ideas (the unifying narrative)

### IDEA-001 — Continuous mode (drift detection)
**STATUS:** shipped → [CONTINUOUS-MODE.md](CONTINUOUS-MODE.md), [subagents/drift-detector.md](../../subagents/drift-detector.md), [scripts/cron-drift-check.sh](../../scripts/cron-drift-check.sh)
**LEVERAGE:** ★★★★★

The skill currently runs as a one-shot audit. But unsafe sites accrete over time — every refactor, every new feature, every dep upgrade. A snapshot audit is fresh today and stale in 3 months.

Continuous mode runs the enumerator + classifier nightly against the project. Compares the new state to the audit's baseline. Files `drift-<N>` beads for new unsafe sites that arrived since the baseline (not yet classified). Emits a one-page weekly drift report.

The audit dir becomes a persistent partner to the project, not a write-once-read-once artifact.

**Cost.** A cron job + a small drift-comparison script. The agent runs are short (~5 min) because they only need to enumerate + diff, not re-audit.

**Benefit.** The audit's lifetime extends indefinitely. The project's soundness budget stays maintained.

---

### IDEA-002 — Quantified risk scoring
**STATUS:** shipped → [RISK-SCORING.md](RISK-SCORING.md), [subagents/risk-scorer.md](../../subagents/risk-scorer.md), [scripts/compute-risk-score.mjs](../../scripts/compute-risk-score.mjs), [assets/risk-score-rubric.md](../../assets/risk-score-rubric.md)
**LEVERAGE:** ★★★★★

The current bead priority is qualitative (P0/P1/P2/P3 by heuristic). Better: a quantified score per site = **blast_radius × likelihood × discoverability**, each measured on a 1-5 scale with documented rubric.

A site reachable from a `pub` API used by 100K downstream crates (blast = 5) AND a SAFETY claim that's stale (likelihood = 4) AND a public fuzz target (discoverability = 5) scores 100. A site internal to a private module with bench-only callers scores 8. The bead ordering becomes dramatically more useful.

**Cost.** A scoring rubric + a script that computes scores from the inventory + soundness-surface + dep-graph data. A subagent that reviews ambiguous scores.

**Benefit.** Beads ordered by ACTUAL impact, not heuristic. Stakeholders read a single number per site. The "20% effort for 80% improvement" path becomes obvious.

---

### IDEA-003 — Soundness debt dashboard
**STATUS:** shipped → [SOUNDNESS-DEBT.md](SOUNDNESS-DEBT.md), [assets/soundness-debt-dashboard.md.template](../../assets/soundness-debt-dashboard.md.template)
**LEVERAGE:** ★★★★

Soundness obligations are a form of technical debt — except they're harder to surface than test coverage or build flakiness. The skill produces a debt dashboard with: total (A) sites (deferred obligations), (B) sites (paid down on feature flag), (C) sites in progress, pre-existing-UB beads, and a trend line over time.

The dashboard format follows tech-debt visualization conventions: heat map by module, debt-velocity per week, top 10 highest-risk items.

**Cost.** A dashboard template + a daily/weekly auto-generation step.

**Benefit.** Stakeholders (managers, security teams, customers) get a single artifact that communicates soundness posture. Engineering team has a target to drive down over time.

---

### IDEA-004 — CI integration (auditor-in-CI)
**STATUS:** shipped → [CI-INTEGRATION.md](CI-INTEGRATION.md), [assets/gh-actions-auditor.yml.template](../../assets/gh-actions-auditor.yml.template)
**LEVERAGE:** ★★★★★

The audit's adoption pathway. The skill ships a GitHub Actions workflow that, on every PR:

- Re-enumerates unsafe; computes the delta vs main.
- Auto-classifies new sites (best-effort) and posts a PR comment.
- Fails CI if a new unsafe site lacks a SAFETY comment.
- Fails CI if `cargo +nightly geiger` count exceeds the project's configured budget.

The skill goes from "tool we used once" to "guardrail we live with."

**Cost.** A `gh-actions-auditor.yml.template`; documentation.

**Benefit.** Soundness drift is gated by CI. PR reviews include a soundness scorecard. Onboarding new contributors gets easier (CI teaches them what's expected).

---

## Mode-extension ideas

### IDEA-005 — Differential audit (version A vs B)
**STATUS:** shipped → [DIFFERENTIAL-AUDIT.md](DIFFERENTIAL-AUDIT.md), [scripts/diff-audit-vs-baseline.sh](../../scripts/diff-audit-vs-baseline.sh)
**LEVERAGE:** ★★★★

Audit `crate@v1.0` and `crate@v2.0`. Diff the inventory + classifications. Surface:
- New unsafe sites (in v2, not in v1).
- Reclassified sites (e.g., a v1 (A) became v2 (B) via a new lint config).
- Closed sites (refactored away).
- Soundness-surface deltas (new `pub` items reaching unsafe).

Use cases:
- Upgrade-decision: "should we adopt v2.0 of this dep?"
- Regression-detection: "did this release accidentally add unsafe?"
- Migration planning: "what's involved in upgrading from v1 to v2?"

**Cost.** Two audits + a diff script that pairs sites by file/line/heuristic.

**Benefit.** Upgrades become evidence-based, not vibes-based.

---

### IDEA-006 — Inverse audit (fuzz-guided from pub API)
**STATUS:** shipped → [INVERSE-AUDIT.md](INVERSE-AUDIT.md), [subagents/inverse-auditor.md](../../subagents/inverse-auditor.md)
**LEVERAGE:** ★★★★

The forward audit starts from `unsafe { ... }` and asks "who calls this?" The inverse audit starts from `pub fn ...` and asks "what input would trigger UB through this?"

Drive a structured fuzzer (cargo-fuzz with `arbitrary`) at every pub function. Look for: panics, miri-detected UB, allocator-pressure spikes, async-cancellation leaks. Any finding either (a) confirms the forward audit found the site, or (b) surfaces a site the forward audit missed.

The inverse audit is a SECOND DIRECTION — a different angle on the same question.

**Cost.** A subagent that generates fuzz harnesses for pub API + runs them + triages findings.

**Benefit.** Bugs the forward audit missed. Coverage of the soundness surface from the OUTSIDE.

---

### IDEA-007 — Soundness archeology (git history mining)
**STATUS:** shipped → [SOUNDNESS-ARCHEOLOGY.md](SOUNDNESS-ARCHEOLOGY.md), [subagents/archeologist.md](../../subagents/archeologist.md), [scripts/git-history-soundness-mine.sh](../../scripts/git-history-soundness-mine.sh)
**LEVERAGE:** ★★★★

Mine the project's entire git history for soundness-relevant decisions: commits that added/removed `unsafe`, PRs with `miri` / `loom` / `UB` keywords, commit messages explaining "why we kept this unsafe."

Surfaces:
- The team's tribal knowledge about unsafe (often known only to original authors).
- Refactors that were attempted and abandoned (don't repeat them).
- The actual evolution of the soundness surface over time.

Sometimes the right refactor for today is the one that was tried and abandoned in 2019 for reasons that no longer apply.

**Cost.** A `git log` + `git show` mining script + a subagent that builds a soundness timeline.

**Benefit.** The audit benefits from the project's full history, not just current source. Cross-validates the audit's classifications against past team decisions.

---

### IDEA-008 — Cross-crate soundness contracts
**STATUS:** shipped → [CROSS-CRATE-CONTRACTS.md](CROSS-CRATE-CONTRACTS.md), [subagents/contract-verifier.md](../../subagents/contract-verifier.md)
**LEVERAGE:** ★★★

In a workspace, soundness contracts often cross crate boundaries: crate A's pub fn relies on crate B's invariant. The audit formalizes these contracts as a separate doc + verifies they hold via property tests + types.

**Cost.** A workspace-only methodology + a contract-verifier subagent.

**Benefit.** Workspaces stop being a soundness-surface gap; cross-crate refactor PRs are auditable.

---

### IDEA-009 — Audit-driven test generation
**STATUS:** shipped → [AUDIT-DRIVEN-TEST-GEN.md](AUDIT-DRIVEN-TEST-GEN.md), [subagents/test-generator.md](../../subagents/test-generator.md)
**LEVERAGE:** ★★★★

For every (A) site, generate property tests that EXERCISE the proof obligation. The audit doesn't just classify the site — it multiplies the project's test surface.

Example: an (A) `unsafe fn open_safe(path: &CStr)` has the obligation "path is null-terminated." The audit auto-generates `proptest! { fn always_safe(path in arb_path()) { open_safe(path); } }` — proving every CStr-derived path is acceptable.

**Cost.** A subagent that reads (A) JUSTIFICATIONs + auto-generates test scaffolds.

**Benefit.** Test surface grows automatically. The audit's value compounds.

---

### IDEA-010 — SECURITY.md generation
**STATUS:** shipped → [SECURITY-MD-GENERATION.md](SECURITY-MD-GENERATION.md), [assets/SECURITY.md.template](../../assets/SECURITY.md.template), [subagents/security-md-author.md](../../subagents/security-md-author.md)
**LEVERAGE:** ★★★

After the audit, auto-generate the project's `SECURITY.md` with:
- How to report soundness concerns.
- The audit baseline (version, geiger count, verification harness).
- The project's soundness commitments (e.g., "every release passes verify.sh").
- Known limitations (e.g., "we don't formally verify the FFI surface; we wrap each surface").

A standardized, user-facing artifact.

**Cost.** A template + auto-fill subagent.

**Benefit.** Downstream users have a clear picture of the project's soundness posture. Coordinated-disclosure pathways exist by default.

---

### IDEA-011 — Project-level soundness CHANGELOG
**STATUS:** shipped → [PROJECT-LEVEL-CHANGELOG.md](PROJECT-LEVEL-CHANGELOG.md), [assets/project-level-changelog.md.template](../../assets/project-level-changelog.md.template)
**LEVERAGE:** ★★★

Beyond the per-release CHANGELOG, a dedicated `audit/SOUNDNESS-LOG.md` that accumulates every audit's findings + outcomes over the project's lifetime. Builds institutional memory at the project level (not just within a single audit's audit-dir).

**Cost.** A template + an auto-append step at the end of each audit.

**Benefit.** Cross-audit pattern memory. New contributors read the soundness log and learn the project's history.

---

### IDEA-012 — Incident-forward-propagation
**STATUS:** shipped → [INCIDENT-FORWARD-PROPAGATION.md](INCIDENT-FORWARD-PROPAGATION.md)
**LEVERAGE:** ★★★★

Given an incident (CVE / miri finding / production crash), work BACKWARDS from the symptom to the SAFETY obligation, then FORWARD from the obligation to find every other site with similar obligations.

Example: incident was "FFI null-termination violated in `open_safe`." The forward propagation finds every other `unsafe { libc::*(path.as_ptr(), ...) }` call and verifies each has the CStr boundary. If a sibling site doesn't, file a follow-up bead.

**Cost.** A methodology + cross-site grep + an analyst pass.

**Benefit.** One incident produces multiple fixes — institutional learning is forced.

---

## Specialty / niche ideas

### IDEA-013 — Tagged-pointer migration deep dive
**STATUS:** shipped → [patterns/130-TAGGED-POINTER-MIGRATION.md](../patterns/130-TAGGED-POINTER-MIGRATION.md)
**LEVERAGE:** ★★

Many older codebases use tagged pointers via `as usize` arithmetic. Strict-provenance prefers `with_addr` / `map_addr`. The skill has a deep dive on this specific migration — high niche value for codebases that use it, low value otherwise.

**Cost.** One pattern bundle.

**Benefit.** Specialty audit guidance.

---

### IDEA-014 — Cryptography audit overlay
**STATUS:** shipped → [patterns/100-CRYPTOGRAPHY-AUDIT.md](../patterns/100-CRYPTOGRAPHY-AUDIT.md)
**LEVERAGE:** ★★★

Cryptography crates have unsafe with cryptography-specific concerns: constant-time, secret-zeroing, side-channel resistance. The skill adds a domain overlay for crypto audits.

**Cost.** One pattern bundle + extension to the operator library.

**Benefit.** Crypto audits get crypto-specific bar.

---

### IDEA-015 — Domain-specific audit modes
**STATUS:** partial → [DOMAIN-MODES.md](DOMAIN-MODES.md) (skeleton; cryptography + tagged-pointer ship today; kernel-driver + database-engine documented as proposed)
**LEVERAGE:** ★★★

The mode router has 7 modes today. Domain-specific modes (cryptography-audit, kernel-driver-audit, database-engine-audit) bring domain expertise. Each mode is a thin overlay on the base 7 modes.

**Cost.** Per-mode: one methodology overlay + extension to PROJECT-TYPES.md.

**Benefit.** Domain-specific gravitational pull. Users in those domains get a much faster start.

---

## Proposed-but-not-implemented (the deeper roadmap)

These are recorded so future agents (or the user) can implement them. They are NOT placeholders for missing skill content; they're the next leverage frontier.

### IDEA-016 — Per-target soundness matrix
**STATUS:** proposed
**LEVERAGE:** ★★★

For SIMD-heavy or embedded crates, soundness can differ by target. The audit produces a matrix: x86_64-v3 PASS, aarch64 PASS, wasm32 PARTIAL (`-Zmiri-strict-provenance` not supported on wasm). Stakeholders see per-target risk.

### IDEA-017 — Audit replay / regression
**STATUS:** proposed
**LEVERAGE:** ★★★

Periodically re-run the FULL audit on sampled commits in the project's history. Bisect to find any regression-introducing commit. Useful for high-stakes projects.

### IDEA-018 — Audit as a service / hosted mode
**STATUS:** proposed (outside skill scope, but useful framing)
**LEVERAGE:** ★

The skill could be operated as a hosted service. Out of scope for the skill itself; flagged here for completeness.

### IDEA-019 — Auto-PR generation for trivial (C) refactors
**STATUS:** proposed
**LEVERAGE:** ★★★★

For (C) refactors with risk=Low + small diff + verified miri-clean, the orchestrator could AUTONOMOUSLY open the PR. The user reviews + merges. Reduces the user's review-queue load.

The discipline: requires `execution_authorization: refactor-on-approve` AND additional safety checks (no API change; geiger delta == expected; cluster's beads all closed).

### IDEA-020 — Per-PR soundness scorecard (CI bot)
**STATUS:** proposed
**LEVERAGE:** ★★★★

A GitHub bot that comments on every PR with: "+N new unsafe sites; M closed; net delta +K; risk score change +R." Helps human reviewers gate.

### IDEA-021 — Cross-project pattern memory
**STATUS:** proposed
**LEVERAGE:** ★★★

A central database (jeffreys-skills.md hosted?) of audit patterns across many users' audits. Each new audit consults the central memory: "this same pattern came up in N other projects; here's what worked."

Anonymized; opt-in. Strong privacy guarantees.

### IDEA-022 — Quantified soundness "calorie counter"
**STATUS:** proposed
**LEVERAGE:** ★★

Daily/weekly auto-summary: "this week we landed 4 (C) refactors closing 12 unsafe sites; new unsafe added in 2 PRs (both (B) feature-flagged)." Gamification with care.

### IDEA-023 — TUI / interactive audit explorer
**STATUS:** proposed
**LEVERAGE:** ★★

A TUI that lets the user navigate the audit interactively. "Show me all (A) sites in soundness surface." "Why is site-0142 (A)?" Drill-down via keyboard shortcuts. Built on `ratatui`.

### IDEA-024 — Refactor risk forecasting
**STATUS:** proposed
**LEVERAGE:** ★★

For a proposed cluster refactor, forecast: estimated time to land, likelihood of regression, downstream impact. Based on historical data from `git log` (similar past refactors).

### IDEA-025 — Audit gamification (sparingly)
**STATUS:** proposed
**LEVERAGE:** ★

Track agent-level metrics: refactors closed per session, false (A) classifications caught in adversarial pass, etc. Useful for tuning agent prompts, NOT for ranking developers.

### IDEA-026 — Soundness contracts as types (advanced)
**STATUS:** proposed
**LEVERAGE:** ★★

Use the type system (newtypes + zero-sized markers + GhostCell-like patterns) to encode soundness obligations. The compiler enforces; the audit verifies the encoding is correct.

### IDEA-027 — Auto-generated "Why is this safe?" user docs
**STATUS:** proposed
**LEVERAGE:** ★★

From the audit's (A) JUSTIFICATIONs, generate user-facing docs: "This crate uses unsafe in N places; here's why each is safe; here's the proof obligation we satisfy."

### IDEA-028 — Reverse documentation: from SAFETY comment to test
**STATUS:** proposed
**LEVERAGE:** ★★★

For every SAFETY comment, generate a property test that exercises the stated obligation. The test SAYS what the comment CLAIMS.

### IDEA-029 — Per-cluster historical analysis (cross-audit memory)
**STATUS:** partial — touched by IDEA-007 SOUNDNESS-ARCHEOLOGY but project-internal; the cross-project version is IDEA-021
**LEVERAGE:** ★★★

### IDEA-030 — Soundness "trust ledger"
**STATUS:** proposed
**LEVERAGE:** ★★

A signed, append-only ledger of audit findings + verifications. Downstream users can verify the project's soundness claims cryptographically.

---

## Operator-library extensions (post-v2)

The current 24 operators cover the common ground. Post-v2 expansions:

- **⊿ Refactor-Risk-Forecast** — given a proposed (C) plan, forecast the implementation cost from historical data.
- **⌬ Cross-Repo-Pattern** — does this site match a pattern documented in another audited project?
- **⌭ Type-Contract-Encode** — can the obligation be encoded as a type-level constraint (newtype + marker)?
- **⊕↻ Recurring-Refactor** — is this a pattern the project keeps re-introducing? (signal for a deeper architectural fix).

---

## How to use this file

This file is the skill's **OPEN BACKLOG**. When the user asks "what could we add to this skill?", the orchestrator reads this file, surfaces ideas matching the user's interest, and either:

- Drafts a plan for an unshipped idea, or
- Points to the existing implementation for a shipped one.

The file is also the skill's RECRUITING DOCUMENT — contributors can pick an idea from the proposed list and implement it.

---

## Anti-ideas (we've considered and rejected)

For audit hygiene: ideas that look attractive but we've explicitly rejected.

### ANTI-001 — Train an LLM to auto-classify
**Why rejected.** Classification is what humans + multi-model agents do well; training a single model risks ossifying judgment. The skill's strength is its iterative, adversarial Phase 4/6.

### ANTI-002 — Bypass the polish-bar for "fast mode"
**Why rejected.** A fast mode without the polish-bar produces work the user can't trust. The cost of trust-building is the polish-bar.

### ANTI-003 — "Just delete the unsafe and call it (C)"
**Why rejected.** The (C) discipline requires an equivalence proof, not a delete. The audit's value is the proof.

### ANTI-004 — Skip miri because "tests already pass"
**Why rejected.** Tests find what tests test. Miri finds UB. They're complementary.

### ANTI-005 — Single-model triangulation as default
**Why rejected.** Multi-model is the calibration. Single-model has lower signal; documented as fallback per [TRIANGULATION.md](TRIANGULATION.md), not the default.

---

## Idea contribution protocol

To propose a new idea: add an entry to the next available IDEA-NNN number with the same structure (STATUS, LEVERAGE, paragraph, Cost, Benefit). Open a discussion / PR with the user. If accepted, implement and update STATUS to `shipped` or `partial`.

The skill grows by accretion. Each idea, once shipped, lifts the floor for the next.
