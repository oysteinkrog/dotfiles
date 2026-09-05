# beads-compliance-and-completion-verification

> **Verify every closed bead was actually implemented as specified — not just status-flipped.**

[`SKILL.md`](SKILL.md) is the agent-facing instruction set. This README is for humans installing or evaluating the skill.

---

## What it does

Audits a project that uses [`beads_rust`](https://github.com/Dicklesworthstone/beads_rust) issue tracking. For every bead marked `closed`, the skill verifies — with re-executed proofs and cited evidence — whether the bead's claim is true. False-closed beads are flagged, scored 0–1000, and remediated via reopen or completion-debt beads.

Use it when:

- You suspect agents are status-flipping beads without finishing the work.
- You're cutting a release and want to audit beads in the milestone.
- You're auditing a project for SOC2 / HIPAA / PCI evidence packs.
- You want continuous compliance monitoring (CI tripwire mode).
- You're inheriting a project with a long bead history and want to know what's truthful.

Don't use it when:

- The project doesn't use beads (audit `/reality-check-for-project` instead).
- You want to *write* beads (use `/beads-workflow`).
- The bead store itself is corrupt (use `/fixing-beads-problems`).
- You want to find code stubs in general (use `/mock-code-finder`).

---

## Install

The skill ships in this repo. To install on your machine:

```bash
# Via jsm (recommended; requires jeffreys-skills.md subscription):
jsm install beads-compliance-and-completion-verification

# Or copy directly into your skills tree:
cp -r .claude/skills/beads-compliance-and-completion-verification ~/.claude/skills/
```

Dependencies (must be on PATH):

- `br` ([beads_rust](https://github.com/Dicklesworthstone/beads_rust)) — required.
- `jq` — required.
- `rg` (ripgrep) — required.
- `bv` ([beads_viewer](https://github.com/Dicklesworthstone/beads_viewer)) — recommended (graph metrics).
- `git` — required.
- `python3` — required.

Optional (improves richness):

- `cass` — for project-specific theater pattern mining.
- `ast-grep` — for AST-level theater detection.
- `cargo`, `npm` / `pnpm` / `bun`, `pytest`, `go`, etc. — whatever runs the project's tests.
- `cargo-llvm-cov`, `vitest --coverage`, `pytest-cov`, `go cover` — coverage tools.
- `cargo-fuzz`, `jazzer.js`, `atheris` — fuzz tools if the project has fuzz beads.

---

## Quick start

```bash
# 1. Activate the skill in a Claude Code session:
> Run a beads compliance audit on /data/projects/myproject

# Claude reads SKILL.md, asks 9 up-front confirmation questions
# (project path, mode, threshold, policy, parallelism, etc.).

# 2. Or run the wrapper script directly (single-agent smoke):
~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
  /data/projects/myproject --threshold 700 --policy completion-debt

# 3. Read the results:
ls /data/projects/myproject/beads_compliance_audit/
cat /data/projects/myproject/beads_compliance_audit/REPORT.md
open /data/projects/myproject/beads_compliance_audit/dashboard.html
```

The audit creates a subdirectory `<project>/beads_compliance_audit/` (auto-added to the project's `.gitignore` so it never bloats the project's commit history) containing:

**Top-level (rolled up from latest pass):**

- `manifest.json` — current pass metadata, rubric SHA, mode, threshold.
- `rubric.md` — the deterministic scoring rubric (project-tunable).
- `REPORT.md` — master report with executive summary + false-closed list.
- `remediation.md` — what Phase 9 did with the false-closed beads (latest).
- `trends.md` — score-over-time per bead, all passes.
- `dashboard.html` — visual score distribution + per-bead trajectories.

**Per pass (`passes/<UTC>/`):**

- `manifest.json`, `REPORT.md`, `remediation.md` — that pass's snapshot.
- `inventory.jsonl`, `doctor.json`, `cycles.json` — Phase 1 captures.
- `synthesis.md` — Phase 7 cross-bead integration findings (per-pass only).
- `convergence.json` — Phase 10 verdict vs prior pass.
- `beads/<id>/` — per-bead evidence pack: `spec.json`, `evidence.json`, `compliance.json`, `theater.json`, `test_depth.json`, `scorecard.md`, plus `raw/` test logs.

> The agent's [`SKILL.md`](SKILL.md) opens with a **Fast Path** block that maps common questions to the right artifact — start there if you're spelunking an unfamiliar audit dir.

---

## Architecture

10 phases, each with a deterministic baseline script and a richer subagent variant:

```
Phase 1  INVENTORY        br doctor + br list + git xref
Phase 2  SPEC EXTRACTION  bead body → structured checklist (per bead)
Phase 3  EVIDENCE GATHER  citations: file:line per checklist item
Phase 4  COMPLIANCE EXEC  re-run tests / fuzzers / harnesses
Phase 5  ANTI-THEATER     stubs / mocks / hardcoded returns / etc.
Phase 6  TEST DEPTH       coverage scoped to bead's surface
Phase 7  SYNTHESIS        cross-bead integration / contract drift
Phase 8  SCORING          rubric → 0–1000 + scorecard
Phase 9  REMEDIATION      reopen / create completion-debt beads
Phase 10 FRESH EYES       audit the audit itself
```

**Modes:** Triage (5–15 min), Standard (30–90 min), Comprehensive (2–4 hr), Tripwire (5 min CI), Single-bead, Re-verification, Onboarding, **Sample** (15–50 stratified beads — recommended for 1500+ closed beads).

**Tiers (parallelism shape):** Solo (<20 closed), Pair (20–150), Squad (150–500), Battalion (500–1000), Swarm (1000–1500), Mega-swarm (1500+, **hard cap of 10 agents**, prefer Sample mode).

**Convergence:** the audit is "done" when two consecutive passes show ±10 score deltas, zero new false-closed, and rubric consistency.

---

## What "false-closed" means

A bead is false-closed when:

- Its `status` is `closed`, AND
- Its audit score is below the configured threshold (default 700/1000).

Score docks accumulate from:

- `Implementation completeness vs. spec` (max 300)
- `Required tests present and meaningfully passing` (max 250)
- `Anti-theater / no stubs / no mocks where forbidden` (max 150)
- `Test depth (coverage / fuzz / golden / e2e realism)` (max 150)
- `Documentation, telemetry, migrations, feature flags as required` (max 100)
- `Cross-bead integration & no contradictions introduced` (max 50)

Per-bead-type weighting reshapes these (bug beads weight tests higher; epics weight cross-bead higher; docs beads weight docs at 750/1000).

See [`references/RUBRIC.md`](references/RUBRIC.md) and [`references/BEAD-TYPE-WEIGHTS.md`](references/BEAD-TYPE-WEIGHTS.md).

---

## Where the skill came from

This skill is a composition of patterns from many sibling skills:

- Operator framework: `/operationalizing-expertise`
- Phase loop: `/saas-billing-patterns-for-stripe-and-paypal`
- Mode variants: `/documentation-website-for-software-project`
- Theater catalog: `/mock-code-finder`
- Multi-pass refinement: `/reality-check-for-project`
- Fresh-eyes review: `/multi-pass-bug-hunting`
- Tripwire patterns: `/release-preparations`, `/cc-hooks`
- Per-bead-type recipes: `/testing-fuzzing`, `/testing-conformance-harnesses`, `/testing-golden-artifacts`, `/testing-metamorphic`, `/testing-real-service-e2e-no-mocks`
- Graph metrics: `/bv`
- Multi-repo audit: `/ru-multi-repo-workflow`

See [`references/DESIGN-PHILOSOPHY.md`](references/DESIGN-PHILOSOPHY.md) for the full inheritance map.

---

## Documentation map

| You want to | Read |
|-------------|------|
| Understand what the skill is and why | This file + [`DESIGN-PHILOSOPHY.md`](references/DESIGN-PHILOSOPHY.md) |
| Run your first audit | [`SKILL.md`](SKILL.md) Quick Start + [`WALKTHROUGH-EXAMPLE.md`](references/WALKTHROUGH-EXAMPLE.md) |
| Understand the vocabulary | [`JARGON.md`](references/JARGON.md) |
| See real-ish audit narratives | [`CASE-STUDIES.md`](references/CASE-STUDIES.md) |
| Set up CI / tripwire mode | [`CI-TRIPWIRE.md`](references/CI-TRIPWIRE.md) |
| Wire metrics / Grafana | [`METRICS-PIPELINE.md`](references/METRICS-PIPELINE.md) |
| Audit when an incident happened | [`POST-MORTEM-MODE.md`](references/POST-MORTEM-MODE.md) |
| Gate a release on the audit | [`RELEASE-GATING.md`](references/RELEASE-GATING.md) |
| Audit at a historical commit | [`TIME-MACHINE-MODE.md`](references/TIME-MACHINE-MODE.md) |
| Ship results to a regulator | [`COMPLIANCE-EVIDENCE-PACK.md`](references/COMPLIANCE-EVIDENCE-PACK.md) |
| Compare to alternatives | [`COMPARISON.md`](references/COMPARISON.md) |
| Common questions | [`FAQ.md`](references/FAQ.md) |
| Track skill version history | [`CHANGELOG.md`](references/CHANGELOG.md) |
| Honest limits | [`KNOWN-LIMITATIONS.md`](references/KNOWN-LIMITATIONS.md) |

Full reference index in [`SKILL.md`](SKILL.md).

---

## Status badge

For your project's README:

```markdown
[![Beads compliance](https://img.shields.io/badge/beads--audit-converged-green)](./BEADS_COMPLIANCE_REPORT.md)
[![False-closed](https://img.shields.io/badge/false--closed-3-orange)](./BEADS_COMPLIANCE_REPORT.md)
```

See [`BADGE.md`](references/BADGE.md) for auto-updating shield.io endpoints.

---

## License

Same license as the parent skills repo.

---

## Contributing

To add a new theater pattern: see [`CONTRIBUTING-PATTERNS.md`](references/CONTRIBUTING-PATTERNS.md).
To debug an unexpected audit result: see [`DEBUGGING-THE-AUDIT.md`](references/DEBUGGING-THE-AUDIT.md).
To upgrade the skill version: see [`CHANGELOG.md`](references/CHANGELOG.md).
