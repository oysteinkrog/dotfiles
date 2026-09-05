# JARGON.md — Glossary

<!-- TOC: Bead-graph terms | Audit primitives | Severity vocabulary | Operator vocabulary | Phase outputs | Convergence | Cross-references -->

## Bead-graph terms

**bead** — a single tracked unit of work in `beads_rust`. Has `id`, `title`, `description`, `design`, `acceptance_criteria`, `notes`, `status`, `priority`, `issue_type`, plus close metadata. Stored in `.beads/<name>.db` and exported to `.beads/issues.jsonl` via `br sync --flush-only`.

**bead store** — the `.beads/` directory at a project root. Two files matter: `<name>.db` (SQLite, primary) and `issues.jsonl` (git-trackable export). Health is checked by `br doctor`; corruption is fixed via `/fixing-beads-problems`.

**closed bead** — a bead whose `status` is `closed`. The audit's central object of suspicion: closed status is a *claim*, not a *fact*.

**bead universe** — every bead in the project, regardless of status. Phase 1 inventories the universe; the audit verifies a configurable subset (default: every closed bead).

**bead-id prefix** — the per-project prefix br applies to auto-generated IDs. Default `bd-` but commonly auto-generated as `<project>-<timestamp>-<suffix>` (e.g., `audit-r2-1778043366-fyy`). Every regex in the audit matches both forms.

**dependency edge** — an edge in the bead DAG. `br dep add A B` means A blocks B (A must close before B is ready).

**ready bead** — an open bead with no open blockers. Surfaced by `br ready`.

**tombstone** — a soft-delete bead state (`status: tombstone`). Cannot be reopened. Audits skip tombstoned beads; their dependents become orphaned-edge candidates.

**closed_by_session** — the agent session that issued the close. Used by anomaly-scan to detect batch-close patterns.

---

## Audit primitives

**audit** — one application of this skill to a project. Produces a `<project>/beads_compliance_audit/` subdirectory inside the project (auto-added to the project's `.gitignore`).

**audit dir** — the persistent git-tracked subdirectory at `<project>/beads_compliance_audit/`. Has its own `.git/` so it's tracked separately from the project; the project's `.gitignore` excludes it. Contains `manifest.json`, `rubric.md`, `REPORT.md`, `synthesis.md`, `remediation.md`, `trends.md`, `dashboard.html`, and `passes/<UTC>/`. **Sacred**: never delete a prior pass.

**pass** — one execution of the 10-phase loop. Always produces `passes/<UTC>/`. One pass = one audit-dir commit.

**evidence pack** — the per-bead artifact bundle inside `passes/<UTC>/beads/<id>/`: `show.json`, `spec.json`, `evidence.json`, `compliance.json`, `theater.json`, `test_depth.json`, `scorecard.md`, plus `raw/` log captures. Self-contained; future readers can re-derive the score.

**spec** — `spec.json`. The structured, literal verification checklist extracted from a bead's body. Produced by Phase 2 via the `★ ENUMERATE` operator.

**evidence** — `evidence.json`. File-path / commit-SHA citations mapping each spec checklist item to actual code, tests, CI workflows, or `MISSING`. Produced by Phase 3.

**compliance** — `compliance.json`. The output of actually re-running tests, builds, fuzzers, conformance harnesses, and e2e flows. Produced by Phase 4 via `✦ EXECUTE`.

**theater** — implementation that *looks done* but isn't. Stubs, hardcoded happy-path returns, mocks where forbidden, `assert true`, sleep-as-fake-work, conditional skips in test mode. Catalogued in `FAILURE-MODES.md`.

**theater scan** — Phase 5. `scripts/theater-scan.sh` plus `scripts/anomaly-scan.sh`. Output: `theater.json`.

**test depth** — Phase 6. Coverage *over the bead's surface*, fuzzer corpus + duration + crash-free run, golden freshness, e2e realism. Output: `test_depth.json`.

**synthesis** — Phase 7's cross-bead findings: integration gaps, contradictions, orphaned ACs, dependency anomalies, bead-graph truthfulness flags. Output: `synthesis.md`.

**scorecard** — `scorecard.md`. The per-bead human-readable score breakdown, citing every dimension's evidence. Phase 8 output.

**master report** — `REPORT.md`. Aggregates all scorecards into executive summary, distribution, ranked scoreboard, and the headline **false-closed list**. Phase 8 output.

**remediation** — `remediation.md`. The list of Phase 9 actions: which beads were reopened or had completion-debt children created.

**convergence** — Phase 10's formal "is the audit done?" check. See `CONVERGENCE-CRITERIA.md`. The audit converges only when two consecutive passes show no material change.

**rubric** — `rubric.md` in the audit dir. The deterministic scoring formula. Pinned by SHA in `manifest.json#rubric_sha256` so convergence checks know if the rubric drifted.

**threshold** — the score below which a closed bead is flagged false-closed. Default 700. Per-project override in `rubric.md`.

**manifest** — `manifest.json`. Per-pass + top-level metadata: project path, project SHA at pass start, mode, threshold, policy, parallelism, tools (with versions), bead counts, phase status, convergence verdict.

---

## Severity vocabulary

**FALSE-CLOSED** — `status == closed AND score < threshold`. The headline finding.

**BLOCKING** (theater) — invalidates the bead's primary deliverable; zeros a rubric dimension. Examples: `unimplemented!()` in claimed implementation; `assert true` in claimed test; mock where bead said no-mocks.

**MAJOR** (theater) — significant gap; docks 50–75% of a dimension. Examples: hardcoded trivial return in non-primary function; cfg(test) guard; 501 stub.

**MINOR** (theater) — small but real; docks 5–15%. Examples: `TODO` comment in unrelated function.

**NOTE** (theater) — flagged but no score impact. Examples: stylistic nit, harmless `pass` in Python protocol.

**verdict bands** — score ranges in `RUBRIC.md`: 🟢 Verified (950+), 🟢 Substantially complete (850-949), 🟡 Partial (700-849), 🟠 False-closed (mild) (500-699), 🔴 False-closed (severe) (250-499), 🚨 Theater (0-249).

---

## Operator vocabulary

(see [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md) for full cards)

**operator** — a named cognitive move with explicit triggers, failure modes, and a paste-ready prompt module. Auditors invoke operators in prescribed pipelines per phase.

**★ ENUMERATE** — name every spec checklist item literally.

**✦ EXECUTE** — actually re-run the proof.

**⚖ MEAN** — does the artifact mean what it claims?

**◐ MEASURE** — does it cover the surface?

**⊕ INTEGRATE** — do the pieces fit?

**⚑ CONTRACT** — does this bead break a sibling?

**⊙ DE-SLOP** — strip auto-generated padding from artifacts.

**⊞ TRIANGULATE** — second-model audit.

**⊘ SELF-POLICE** — audit the audit itself.

**⟳ REPEAT-UNTIL-QUIET** — iterate inner phase loop until findings stabilize.

**⌂ CONSEQUENCE** — what happens if this bead is missing?

**⤵ DECOMPOSE** — split a large bead into auditable pieces.

**☖ STAKE-RUBRIC** — never tune the rubric mid-pass.

**☍ DISCLAIMER-WINDOW** — give the closer one chance to defend before reopening.

**⌘ REDUCE** — compress the report without losing evidence.

---

## Phase outputs

| Phase | Output |
|------:|--------|
| 1 | inventory.jsonl, doctor.json, dag.json, cycles.json, per-bead show.json + git_xref.txt |
| 2 | per-bead spec.json |
| 3 | per-bead evidence.json |
| 4 | per-bead compliance.json + raw/ logs |
| 5 | per-bead theater.json |
| 6 | per-bead test_depth.json |
| 7 | synthesis.md (cross-bead) |
| 8 | per-bead scorecard.md + master REPORT.md + trends.md update |
| 9 | remediation.md + new/reopened beads in project's `.beads/` |
| 10 | convergence.json + REPORT.md verdict update |

---

## Convergence

**converged** — two consecutive passes show: max score delta ≤ ±10, zero new false-closed, zero new synthesis findings, rubric consistency pass, all prior remediation beads exist. See `CONVERGENCE-CRITERIA.md`.

**delta** — score change between this pass and prior for the same bead.

**false-closed delta** — beads newly false-closed since prior pass. Should be 0 for convergence.

**rubric drift** — `rubric_sha256` differs between passes. Score deltas are not directly comparable; flagged in `convergence.json`.

**stuck bead** — score trajectory shows no movement (`600 → 600 → 600`). Indicates remediation isn't being picked up.

**yo-yo bead** — score oscillates pass-to-pass (`600 → 900 → 600`). Indicates unstable code.

---

## Cross-references

**bead-id prefix** — see Bead-graph terms.

**`/cass`** — cross-agent session search; mined for project-specific theater patterns. See `CASS-MINING.md`.

**`/bv`** — bead-graph triage TUI. We use `--robot-*` flags only; never bare `bv`. See `BEAD-GRAPH-ANALYSIS.md`.

**`/agent-mail`** — file-reservation coordination for parallel subagents. Used in Squad/Swarm tier. See `MODES-AND-TIERS.md`.

**`/mock-code-finder`** — Phase 5's primary tool. Wrapped by `theater-scan.sh`.

**`/fixing-beads-problems`** — escape hatch when `br doctor` fails at Phase 1.

**`/multi-pass-bug-hunting`** — fresh-eyes loop pattern that Phase 10 borrows.

**`/multi-model-triangulation`** — Phase 10's `⊞ TRIANGULATE` operator.

**`/reality-check-for-project`** — adjacent skill (vision-vs-code), not bead-vs-spec. Different purpose.

**`/beads-workflow`** — adjacent skill (creating beads), not auditing them.

**Tier (Solo/Pair/Squad/Swarm)** — parallelism shape, picked from closed-bead count. See `MODES-AND-TIERS.md`.

**Mode (Triage/Standard/Comprehensive/Tripwire/Single-bead/Re-verification/Onboarding)** — depth + phase selection. See `MODES-AND-TIERS.md`.

**Policy (completion-debt / reopen / report-only)** — Phase 9 remediation strategy. See `REMEDIATION-PATTERNS.md`.

**Tripwire** — periodic autonomous re-verification post-convergence. See `CI-TRIPWIRE.md`.

**Portfolio** — multi-repo audit roll-up. See `MULTI-REPO-AUDIT.md`.