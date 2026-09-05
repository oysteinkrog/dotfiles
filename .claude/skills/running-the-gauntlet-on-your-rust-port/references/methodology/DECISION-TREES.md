# Decision Trees

Flowcharts for the most common decisions the orchestrator or operator has to make. Each tree compresses what would otherwise be 200-400 lines of prose conditional logic into a one-page navigation aid. Cross-link from cookbook recipes + phase docs.

---

## DT-1: Which mode? (kickoff)

When you (operator or orchestrator) start a gauntlet run, pick a mode FIRST.

```
START: kickoff request received
├── Is the target a sibling Rust port (frankensqlite / frankenredis / etc.)?
│   ├── YES → Has a `<workspace>__gauntlet_workspace/` existed before?
│   │   ├── YES + last completed phase < 16
│   │   │   ├── code has moved forward since last round → incremental-rebase
│   │   │   └── code unchanged → audit-only (re-certify against current evidence)
│   │   ├── YES + last completed phase = 16 (certification exists)
│   │   │   ├── user wants release certification refresh → compliance-pass
│   │   │   ├── user reports a regression → red-team
│   │   │   └── reference version bumped → migration
│   │   └── NO (fresh sibling) → gauntlet-full
│   └── NO
│       ├── Target is a tiny self-test fixture → quick-smoke
│       ├── Target is a novel non-port Rust project (no upstream reference)
│       │   → gauntlet-greenfield  (see DT-5 for Oracle-mode selection)
│       └── Target is a port-shape but for a project class not in the standard 5
│           → escalate: propose new project class (see PROJECT-CLASSES.md "When to Escalate")
```

Cross-ref: [`MODE-ROUTER.md`](MODE-ROUTER.md).

---

## DT-2: Which project class?

```
START: detect-project-class.sh returned <CLASS_GUESS>
├── CLASS_GUESS == SQL-class
│   └── Verify: ports a SQLite-style relational database (rusqlite-linked oracle works)
│       ├── YES → SQL-class
│       └── NO  → re-run with `--debug`; check for "sqlite" / "sqlmodel" markers
├── CLASS_GUESS == RESP-class
│   └── Verify: subject speaks RESP3 (Redis-protocol-compatible)
│       ├── YES → RESP-class
│       └── NO  → check for `redis-server`-shaped binary; if absent → escalate
├── CLASS_GUESS == Numerical-Python-class
│   └── Verify: PyO3 bridge to a numpy/scipy/pandas/networkx-equivalent
│       ├── YES → Numerical-Python-class (and pick sub-row per CC.md PART XXIII)
│       └── NO  → maybe ML-System-class adjacent; check for torch/jax shape
├── CLASS_GUESS == ML-System-class
│   └── Verify: PyO3 bridge to a torch/jax/whisper-equivalent; ULP-tolerance table needed
│       ├── YES → ML-System-class
│       └── NO  → check for HTTP-Protocol-class (fastmcp_rust is often misclassified)
├── CLASS_GUESS == HTTP-Protocol-class
│   └── Verify: subject is an HTTP-shaped framework (FastAPI / FastMCP / Axum-like)
│       ├── YES → HTTP-Protocol-class
│       └── NO  → fall through to UNKNOWN
└── CLASS_GUESS == UNKNOWN
    └── Greenfield project? (no upstream reference; spec is the Oracle source)
        ├── YES → Greenfield-Rust-class (see DT-5 for Oracle-mode selection)
        └── NO  → escalate per PROJECT-CLASSES.md "When to Escalate to a New Class"
```

Cross-ref: [`../taxonomy/PROJECT-CLASSES.md`](../taxonomy/PROJECT-CLASSES.md), [`../../scripts/detect-project-class.sh`](../../scripts/detect-project-class.sh).

---

## DT-3: Which pattern should I apply?

By symptom — the most common entry points:

| Symptom | First pattern to check |
|---|---|
| Subject and reference disagree on a SQL output | [`pattern:35-NORMALIZED-VALUE`](../patterns/35-NORMALIZED-VALUE.md) |
| Same divergence in 50+ different scenarios → likely same root cause | [`pattern:45-MISMATCH-MINIMIZER`](../patterns/45-MISMATCH-MINIMIZER.md) |
| Perf result fluctuates run-to-run | check cv_pct first; if > 5% see [`pattern:170-ROBUST-REGRESSION-DETECTOR`](../patterns/170-ROBUST-REGRESSION-DETECTOR.md) |
| Bench is faster but tests fail | [`pattern:150-PROFILE-FIRST-CARD`](../patterns/150-PROFILE-FIRST-CARD.md) — proof pack should have caught this |
| Considering reverting a kept change | [`pattern:185-RETRY-CONDITION-PREDICATE`](../patterns/185-RETRY-CONDITION-PREDICATE.md) — write the predicate |
| Random run-to-run variation > 5% on a stable bench | [`pattern:175-CONCURRENT-MODE-GUARD`](../patterns/175-CONCURRENT-MODE-GUARD.md) (or class-equivalent) |
| Adversarial search returns 0 counterexamples for 5+ rounds | [`pattern:85-ADVERSARIAL-SEARCH`](../patterns/85-ADVERSARIAL-SEARCH.md) — rotate the lens list |
| Phase 11 stalled with no new findings for 3 rounds | escalate to deep review per [`DEEP-HYPOTHESIS-REVIEW.md § 6`](DEEP-HYPOTHESIS-REVIEW.md) |
| Spec sources contradict | [`SPEC-PINNING-FOR-GREENFIELD.md § 4`](SPEC-PINNING-FOR-GREENFIELD.md) |
| Two equally-scored Phase-12 remediation candidates | apply deep-review tie-break per [`DEEP-HYPOTHESIS-REVIEW.md § 1`](DEEP-HYPOTHESIS-REVIEW.md) |
| Insta snapshot explosion after refactor | [`cookbook/insta-snapshot-explosion.md`](../cookbook/insta-snapshot-explosion.md) |
| `apply-ratchet.sh` flickers Allow/Block | [`cookbook/ratchet-block.md`](../cookbook/ratchet-block.md) |

Cross-ref: [`../patterns/00-INDEX.md`](../patterns/00-INDEX.md).

---

## DT-4: When to escalate to deep review?

```
START: orchestrator faces a contested situation
├── Convergence stalled (3+ consecutive rounds with new_findings >= clean_threshold)
│   → escalate (trigger = stall)
├── Phase-12 has 2 equally-scored remediation candidates (score within 1 point)
│   → escalate (trigger = tie-break)
├── Adversarial search surfaced a counterexample that reveals a GATE flaw
│   (not just a bug; the gate itself was wrong)
│   → escalate (trigger = gate-flaw)
├── A specific question keeps getting re-asked across rounds without resolution
│   AND has fewer than 3 candidate hypotheses
│   → escalate (trigger = adversarial-followup)
└── ELSE → DO NOT escalate
    Deep-review escalations burn 5+ panes × multi-hour budget. Reserve them
    for genuine deadlocks; routine investigation should use the standard
    Phase 11 loop.
```

Required pre-flight before escalating:
1. The question is **specific enough to falsify**.
2. The user has signed off (orchestrator NEVER self-authorizes).
3. The orchestrator has either an NTM pipeline or an inline three-role fallback plan.

Cross-ref: [`DEEP-HYPOTHESIS-REVIEW.md`](DEEP-HYPOTHESIS-REVIEW.md), [`../../subagents/deep-hypothesis-reviewer.md`](../../subagents/deep-hypothesis-reviewer.md).

---

## DT-5: Which Oracle modes for a greenfield project?

Greenfield's 5-mode Oracle (Spec / Property / Self / Round-trip / External-tool) is **mix-and-match**. Few projects use all 5; most use 3-4.

```
START: greenfield project, choose enabled modes
├── Does the project have a published spec doc (docs/spec/, README "Hard Requirements", AGENTS.md "Hard Requirements", etc.)?
│   ├── YES → Spec-as-Oracle = TRUE
│   └── NO  → user must author one first (Phase 2 BLOCKER); else skip
├── Are there pure functions / kernel-shape APIs amenable to property testing?
│   ├── YES → Property-Oracle = TRUE (target ≥ 5 properties per behavior class)
│   └── NO  → SKIP
├── Are there stable output formats (text, JSON, markdown emission)?
│   ├── YES → Self-Oracle = TRUE (insta snapshots)
│   └── NO  → SKIP
├── Are there (encode, decode) or (serialize, parse) pairs?
│   ├── YES → Round-trip-Oracle = TRUE (one round-trip per pair)
│   └── NO  → SKIP
└── External tools available (Miri, Clippy, cargo-deny, cargo-audit)?
    ├── YES → External-tool-Oracle = TRUE (mandatory baseline)
    └── NO  → SKIP (rare — most Rust projects ship these)
```

Decision matrix per project type:

| Project type | Spec | Property | Self | Round-trip | External-tool |
|---|:---:|:---:|:---:|:---:|:---:|
| Storage backend (eidetic-shape) | ✓ | ✓ | ✓ | ✓ | ✓ |
| CLI tool (clap-shape) | ✓ | ◐ | ✓ | ◐ | ✓ |
| Library / SDK (no CLI) | ✓ | ✓ | ◐ | ✓ | ✓ |
| Network protocol (custom RPC) | ✓ | ✓ | ✓ | ✓ | ✓ |
| Algorithm / kernel library | ◐ | ✓ | ◐ | ◐ | ✓ |
| Embedded firmware-shape | ✓ | ✓ | ✗ | ✓ | ◐ |

`✓ = mandatory`, `◐ = recommended`, `✗ = not applicable`.

Cross-ref: [`GREENFIELD-ADAPTATION.md`](GREENFIELD-ADAPTATION.md), [`../case-studies/eidetic_engine_cli.md`](../case-studies/eidetic_engine_cli.md), [`../../subagents/greenfield-oracle-wirer.md`](../../subagents/greenfield-oracle-wirer.md).

---

## DT-6: Single-crate vs workspace?

```
START: Phase 3 starting; need to decide where to put harness modules
├── Does `<target>/Cargo.toml` declare `[workspace]` with `members = [...]`?
│   ├── YES (true workspace) → harness goes in `crates/<project>-harness/src/`
│   └── NO
├── Does `<target>/Cargo.toml` declare `[workspace]` with `exclude = [...]` ONLY?
│   ├── YES (single-crate that opts OUT of containing workspace)
│   │   → harness goes in `src/harness/` GATED by cargo feature `harness`
│   └── NO
├── Does `<target>/Cargo.toml` have NO `[workspace]` block?
│   ├── YES + has `[package]` → single-crate package
│   │   → harness goes in `src/harness/` GATED by cargo feature `harness`
│   └── NO → escalate (unrecognized Cargo.toml shape)
└── Does `<target>/AGENTS.md` mention "NO WORKTREES" or "single binary crate"?
    ├── YES → respect; stay single-crate
    └── NO  → still default to single-crate UNLESS user signs off on workspace promotion
```

Promoting a single-crate project to a workspace requires:
1. User signoff (never auto).
2. A documented bead with rationale (why workspace is needed; what features were
   previously impossible).
3. An AGENTS.md update if the project's discipline explicitly forbade it.

Cross-ref: [`pattern:13-SINGLE-CRATE-VS-WORKSPACE-DECISION`](../patterns/13-SINGLE-CRATE-VS-WORKSPACE-DECISION.md), [`cookbook/single-crate-vs-workspace-decision.md`](../cookbook/single-crate-vs-workspace-decision.md).

---

## DT-7: Loop-back or proceed?

End of Phase 9 / 11 / 14 / 15 — decide whether to loop back or proceed:

```
START: phase X completion verifier just ran
├── Phase X is 9 (BASELINE)
│   ├── conformance_findings.json shows TrueDivergence count > 0 → Phase 12 (don't iterate yet)
│   ├── perf_findings.json shows ratchet shows Block → Phase 12 OR waiver
│   ├── surface_findings.json shows Missing count > 0 → Phase 11 (iterate to close)
│   └── ELSE → Phase 10 (idea-wizard for additional coverage)
├── Phase X is 11 (ITERATE)
│   ├── round_count < 10 → run another round
│   ├── clean_last_two != true → run another round
│   ├── open_hypothesis_count > 0 → run another round (resolve hypotheses)
│   └── ELSE → Phase 12 (REMEDIATION DESIGN)
├── Phase X is 14 (FRESH-EYES)
│   ├── any static gate red (cargo check / clippy -D warnings / fmt / test) → fix + re-run
│   ├── any variant produced > 3 material-change lines → run another round
│   ├── consecutive clean rounds < 2 → run another round
│   ├── T3+ triangulation produced CRITICAL finding → fix + re-run
│   └── ELSE → Phase 15 (SOAK)
└── Phase X is 15 (SOAK)
    ├── any soak runner produced TrueDivergence / UB / data-race / ShiftDetected /
    │   CRITICAL adversarial → loop back to Phase 12 (reopen affected hypothesis)
    ├── BOCPD regime not Stable → wait for stabilization OR loop back to Phase 12
    └── ELSE → Phase 16 (FINAL ARTIFACTS)
```

Cross-ref: [`PHASES.md`](../PHASES.md), [`DEFINITION-OF-DONE.md`](DEFINITION-OF-DONE.md).

---

## DT-8: When to write a waiver vs fix?

```
START: apply-ratchet.sh returned Block on the current round
├── Is the regression < 5% AND in a non-primary category?
│   ├── YES → fix-or-waiver judgment call:
│   │   ├── time-to-fix < 1h → fix (default)
│   │   └── time-to-fix > 4h AND release pressure high → waiver (with bead for fix)
│   └── NO
├── Is the regression a known temporary artifact of a feature flag rollout?
│   ├── YES → waiver (dated; tied to flag-ramp completion date)
│   └── NO
├── Is the regression a measurement artifact (cv_pct > 5% on the primary micro)?
│   ├── YES → bench hardening first; waiver during the hardening period
│   └── NO
└── Otherwise (regression is real + significant) → FIX (no waiver path)
```

Waivers REQUIRE:
- User signoff (orchestrator NEVER self-signs).
- Structured dated waiver per [`subagents/waiver-author.md`](../../subagents/waiver-author.md).
- An open bead with the fix and a calendar deadline.
- An entry in `<workspace>/waivers/<date>-<slug>.md`.

Cross-ref: [`cookbook/ratchet-block.md`](../cookbook/ratchet-block.md), [`subagents/waiver-author.md`](../../subagents/waiver-author.md), [`CONFORMAL-RATCHET.md`](CONFORMAL-RATCHET.md).

---

## How to add a new decision tree

Add a `## DT-N: <one-line topic>` block above the cross-references. Use the same format: question → branches → leaf-action. Cross-link from at least 2 cookbook recipes or phase docs. Add a row to the decision-tree index in [`SKILL.md § Decision Trees`](../../SKILL.md).
