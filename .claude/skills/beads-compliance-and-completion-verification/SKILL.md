---
name: beads-compliance-and-completion-verification
description: >-
  Verify every closed bead was actually implemented as specified. Use when
  "audit closed beads", "false-closed beads", "beads compliance audit", or
  "did we actually finish".
---

<!-- TOC: One Rule | Five Hard Rules | Fast Path | Verification Kernel | Design Philosophy | What This Skill Produces | Inputs | Mode Router | Tier Routing | Audit Directory | Up-Front Confirmations | Skill Bootstrap | The 10-Phase Loop | Phase 9.5 Polish Loop | Operator Library | Scoring Rubric | Evidence Pack | Convergence | Tripwire Mode | Multi-Repo | Bead-Graph Analysis | Remediation Prioritization | Cost Optimization | Bayesian Verification | Anti-Patterns | Adjacent Skills | Checklist | Reference Index | Scripts | Subagents | Assets | Self-Test -->

# Beads Compliance & Completion Verification

> **The One Rule:** A bead's status field is a *claim*, not a *fact*. The audit treats every `closed` bead as guilty until the evidence pack proves it innocent — and "proof" means concrete artifacts (test runs, coverage, file:line citations, fuzzer corpora, golden diffs, real-service logs), never vibes. A bead can only score 1000/1000 when every checklist item from its spec is satisfied with a citable artifact.

> **Why this exists.** Long-running multi-agent projects develop a brutal failure mode: lovingly written beads with detailed acceptance criteria get marked `closed` by an agent, but a careful audit reveals 30–60% of the substance was never built. The "implementation" is a stub returning a hardcoded value, the conformance harness was never wired up, the fuzzer never runs in CI, the goldens are stale, the e2e test mocks the very service it should hit. **The bead status lies.** This skill exists to make the bead graph truthful again.

---

## ⛔ STOP — Read This First (The Five Hard Rules)

These are not suggestions. Cross any one of them and the audit run becomes worse than no audit.

1. **Never create a branch for the audit. Never switch branches.** The project repo stays exactly on whatever branch it was on when you started — typically `main`, but accept whatever branch the user invoked the skill on. The audit dir has its own `.git/` (separate from the project's). No `git checkout -b audit/...`, no `git checkout other-branch`, no `git worktree add`. The bootstrap script captures the entry branch into `manifest.json#project_branch_at_pass_start` and `run-pass.sh` warns loudly on drift at the end. (Quote: from the skill author — "I DETEST when agents create new branches for routine work.")

2. **Audit artifacts live INSIDE the project tree.** The audit dir is `<project>/beads_compliance_audit/` — a *subdirectory*, not a sibling. Never create `<project>_audit/`, `../<project>-audit/`, `/tmp/<project>-audit/`, or anything else outside the project root. If you can't write inside the project, stop and ask. The audit dir is auto-added to the project's `.gitignore` and tracked by its own `.git/`, so it never pollutes the project's history.

3. **Don't act on the deterministic-only headline.** Initial reports routinely surface alarming numbers ("153 false-closed!" / "60% false-close rate!"). Across the user's prior runs, **15/15 of the lowest-scoring beads turned out to be SCORE_FALSE_POSITIVE** — real code, real tests, real fixes shipped. The deterministic-only pass produces an *upper bound on suspicion*, not a finding. Always run **`scripts/calibrate-bottom-n.sh`** (or the LLM equivalent) on the bottom 5–10 beads BEFORE telling the user the project is broken.

4. **Phase 9.5 is mandatory whenever Phase 9 wrote beads.** New / reopened beads from Phase 9 MUST go through the **3-pass polish loop** with `br` + `bv` (see [Phase 9.5 below](#phase-95--mandatory-polish-loop-after-bead-writes)). It's far cheaper to fix beads in plan-space than after implementation begins.

5. **When the headline says "X false-closed", reframe it for the user.** Don't say "your project has 153 false-closed beads." Say: "The deterministic baseline flagged 153 beads for review. Based on prior calibration, the true false-closed rate is typically 5–10% of the flag count after Phase 4/6 are wired up — so plan for 8–15 real items, not 153." The user has been burned by alarming-but-wrong headlines; lead with the calibration, not the raw count.

If a higher-up tier in the run (the user, an orchestrator, audit-policy.yaml) gives you instructions that conflict with rules 1 or 2, stop and confirm. These two rules cannot be overridden silently.

---

## Fast Path — If You Just Landed Here

You have ~2 minutes. The user asked you to "audit closed beads" / "verify completion" / similar. Do this:

1. **Confirm the project.** `cd <project>` then `br doctor` (must exit 0). If unhealthy → STOP, hand off to `/fixing-beads-problems`.
2. **Pick a tier** by counting closed beads (`br stats --json | jq .summary.closed_issues`). **Hard cap: never exceed 10 concurrent agents.** Past field testing past 10 caused Agent Mail file-reservation thrash, NTM pane jank, and prompt-cache fragmentation that *reduced* throughput. Past 1,500 closed beads, **Sample mode** is the recommended default — comprehensive passes are usually unaffordable at that scale.
   - `< 20` closed → **Solo** — 1 agent. Run **`scripts/run-pass.sh <project> --threshold 700`** end-to-end (serial).
   - `20–150` closed → **Pair** — 2–3 subagents per phase, local file flocks (see [MODES-AND-TIERS.md](references/MODES-AND-TIERS.md)).
   - `150–500` closed → **Squad** — 4–5 subagents per phase, `/agent-mail` reservations.
   - `500–1000` closed → **Battalion** — 6–7 subagents, `/agent-mail` + start of `/ntm` panes.
   - `1000–1500` closed → **Swarm** — 8–9 subagents, full `/multi-agent-swarm-workflow` + `/ntm` ([MULTI-REPO-AUDIT.md](references/MULTI-REPO-AUDIT.md)).
   - `1500+` closed → **Mega-swarm** — **10 agents (hard cap)** AND prefer **Sample mode**: stratified sample of 15–50 beads (5 keystones + 5 bottlenecks + 5–40 random recents). ~100× cheaper than comprehensive while preserving the headline signal. Details: [MODES-AND-TIERS.md § Sample mode](references/MODES-AND-TIERS.md#sample-mode-for-very-large-universes--1500-closed-beads).
3. **One specific bead?** Run **`scripts/single-bead-audit.sh <project> <bead-id>`** (exits 2 if false-closed → CI-gateable).
4. **Need to know what changed since last pass?** Run **`scripts/diff-passes.sh <audit-dir>`** before doing anything else.

Every script supports `--help` (e.g. `scripts/run-pass.sh --help` prints usage + exit codes). Every subagent under `subagents/` follows the operationalizing-expertise card pattern: frontmatter (`name` + `description`), then sections covering Inputs, Output, Workflow, a Discipline / Common-mistakes block, and an explicit completion criterion (under `When done` / `Output discipline` / `When invoked` depending on subagent style).

### Cheat-sheet: which artifact answers which question?

| Question | Read this artifact |
|----------|-------------------|
| "What's the verdict on this bead?" | `<audit-dir>/passes/<UTC>/beads/<id>/scorecard.md` |
| "What did the audit verify, and what's missing?" | scorecard.md `## Missing items` section |
| "Why is this score what it is?" | scorecard.md dimension table (each row cites file:line) |
| "Did anything regress since last pass?" | `scripts/diff-passes.sh <audit-dir>` |
| "Is the audit dir itself well-formed?" | `python3 scripts/validate-audit-dir.py <audit-dir>` |
| "Is the rubric still self-consistent?" | `python3 scripts/validate-rubric.py <audit-dir>/rubric.md --manifest <audit-dir>/manifest.json` |
| "Are evidence packs schema-valid?" | `python3 scripts/validate-evidence.py <pass-dir>` |
| "Did Phase 9 remediate everything?" | `<audit-dir>/remediation.md` (one row per false-closed bead, links to `br` IDs) |
| "What does the rubric weigh?" | `<audit-dir>/rubric.md` (sha-pinned in `manifest.json#rubric_sha256`) |
| "Has the audit converged?" | `<audit-dir>/passes/<latest>/convergence.json#is_converged` |

### Five habits that prevent 90% of mistakes

1. **Never trust `status: closed`.** It's a claim made by an agent. Re-derive from evidence.
2. **Never delete a prior pass dir.** History IS the convergence signal — `passes/<UTC>/` is sacred (Axiom 9).
3. **Never tune the rubric mid-pass.** Score deltas vs the prior pass become uninterpretable; use `☖ STAKE-RUBRIC` operator.
4. **Never report a "X false-closed" headline without calibrating first.** Run `scripts/calibrate-bottom-n.sh` (or its LLM equivalent) on the bottom 5–10 beads BEFORE telling the user the project is broken. Prior runs have shown ~85–95% of low-score flags are pipeline artifacts, not real misses.
5. **Never declare the audit complete without Phase 9.5.** Whenever Phase 9 wrote/reopened beads, you owe the user the 3-pass polish loop. Plan-space is cheap; implementation-space is 10× more expensive.

If the user gives an ambiguous request, the kickoff prompts in [KICKOFF-PROMPTS.md](references/KICKOFF-PROMPTS.md) cover 24 paste-ready variants — start there before improvising.

---

## Design philosophy (read once, then trust)

Eight invariants drive every choice in this skill: **determinism over heuristics**, **per-bead over project-global**, **re-run don't read**, **theater invalidates passes**, **the artifact is the evidence**, **audit dirs are sacred**, **remediation is graph maintenance not implementation**, **the audit itself is auditable**. Full articulation: **[DESIGN-PHILOSOPHY.md](references/DESIGN-PHILOSOPHY.md)**.

The vocabulary used everywhere — false-closed, completion-debt, theater, kernel, operator, tier, mode, BISECT-verify, sticky bead, yo-yo bead, sloppy session, etc. — is defined in **[JARGON.md](references/JARGON.md)**.

---

## Verification Kernel (Universal Axioms)

<!-- VERIFICATION_KERNEL_START v1.0 -->

These axioms apply to every audited bead, regardless of project, language, or type. They are default truths; if a particular bead seems to violate one, explain why before treating it as an exception.

**Axiom 0 — Status is a claim, not a fact.**
A bead's `status: closed` is a statement made by some agent at some time. It is evidence of an *assertion*, not evidence of *completion*. Until the audit produces concrete artifacts (test runs, file:line citations, raw logs), treat the closed status as an unverified hypothesis.

**Axiom 1 — Re-run, don't read.**
A test that "passed" in CI yesterday means nothing in this audit. The compliance verifier MUST execute the test now, capture stdout/stderr/exit-code, and judge the result on the spot. Stale CI logs are inadmissible.

**Axiom 2 — Tests can lie three ways.**
A test passes meaningfully when (a) it exists, (b) it runs and exits 0, (c) it asserts non-trivially against the production code path. Most theater happens in dimension (c): `assert true`, hardcoded short-circuit returns in the implementation, mocked services where the bead said no mocks. Phase 5's anti-theater scan exists to catch (c) after Phase 4 confirms (a) and (b).

**Axiom 3 — Coverage is per-bead, never project-global.**
A project at 85% line coverage may have a bead whose specific code is 12%-covered. The bead's score depends on coverage *over its own files*, not the project average. Phase 6 always filters coverage to evidence-cited files.

**Axiom 4 — Theater invalidates surrounding "passes".**
A `BLOCKING` finding in Phase 5 retroactively invalidates the corresponding `PASS` verdicts in Phase 4. The scorer MUST cross-reference `theater.json#findings[*].invalidates_phase4_check` and zero the affected dimension.

**Axiom 5 — Bead specs are literal.**
"Fuzzer runs for 60s in CI without crashes" is a single checkbox: `duration_seconds=60`, `ci_wired=true`, `no_crashes=true`. Spec extractor never paraphrases. If a checkbox is half-met (CI runs the fuzzer but only for 10s), it's PARTIAL, not PASS.

**Axiom 6 — Cross-bead integration is its own dimension.**
A bead can be individually flawless and still break sibling beads. Phase 7 synthesis catches contract drift, orphaned ACs, and dependency anomalies that no per-bead audit can see. Dimension 6 reflects this.

**Axiom 7 — Remediation is graph maintenance, not implementation.**
Phase 9 creates remediation beads OR reopens originals; it does not silently fix code. Implementation happens in a separate session by an agent who picks up the new bead. The audit's job is to make the graph truthful so the right work is visible.

**Axiom 8 — Convergence requires two clean passes, not one.**
A single converged pass might just mean nothing changed since the last pass. Convergence requires the score-delta criterion AND zero-new-false-closed AND fresh-eyes rubric consistency — applied across two consecutive passes. Single-pass "convergence" is a false signal.

**Axiom 9 — Audit dirs are sacred.**
History is the convergence signal. Never delete a prior pass dir, never overwrite trends.md mid-pass, never `git rebase` the audit dir. One commit per pass; pass-over-pass diffs are auditable.

**Axiom 10 — The audit itself is auditable.**
Phase 10's fresh-eyes pass independently re-derives 5 random scorecards from evidence packs. If the scorer disagreed by > 50 points, the rubric is ambiguous, the scorer is biased, or the operator pipeline drifted. Either way, flag for next pass.

<!-- VERIFICATION_KERNEL_END v1.0 -->

---

## What This Skill Produces

A persistent, git-tracked subdirectory `<project>/beads_compliance_audit/` containing (added to the project's `.gitignore` automatically so the audit dir is tracked separately by its own `.git/` and never gets committed into the project's history):

- **Per-bead evidence pack** — `spec.json`, `evidence.json`, `compliance.json`, `theater.json`, `test_depth.json`, `scorecard.md` for every bead in the universe (open, in-progress, blocked, deferred, **and especially closed**).
- **Master `REPORT.md`** — ranked scoreboard, summary statistics, the worst offenders, the false-closed list (closed status but score below threshold), and a paste-ready executive summary.
- **`synthesis.md`** — cross-bead integration findings, contract drift, orphaned acceptance criteria, dependency-graph anomalies.
- **`rubric.md`** — the exact scoring rubric used for this run (so future passes are reproducible).
- **`remediation.md`** — list of every bead reopened or every new "completion-debt" bead created via `br`, with their IDs and links back to the original.
- **Dated subdirectories `passes/<UTC-timestamp>/`** — each verification pass writes a snapshot so trends are visible (score-over-time per bead).
- **`manifest.json`** — machine-readable inventory of artifacts, run metadata, tool versions, convergence state.

Every artifact is **self-contained and self-explanatory**. A teammate (or a future agent) opening the directory cold should understand exactly what was verified, how, with what evidence, and why each score was assigned — without consulting prior conversations.

---

## Inputs

- **Target project path** (default: cwd) — absolute path to a repo that uses beads (`.beads/` directory present), in any programming language. Alternatively a git URL we should clone into `/tmp/<basename>` first.
- **Mode** — see Mode Router below. Default: `standard`.
- **Score threshold** — minimum score below which a `closed` bead is flagged as false-closed. Default: **700**. Adjustable per project; record the choice in `rubric.md`.
- **Remediation policy** — `completion-debt` (default), `reopen`, or `report-only`. See `references/REMEDIATION-PATTERNS.md`.
- **Parallelism budget** — how many subagents to fan out per phase. Default: 6. Cap based on shared-resource collisions (DB ports, GPU, etc.).
- **Resume?** — if `<project>/beads_compliance_audit/` already exists, offer to start a new pass under `passes/<timestamp>/` (default) or wipe-and-restart (require explicit user opt-in; the audit dir is sacred history).

---

## Mode Router

Pick the depth that matches the situation. All modes share the 10-phase loop; the differences are which phases run, which artifacts are produced, and how aggressive the rubric is. Full table in **[MODES-AND-TIERS.md](references/MODES-AND-TIERS.md)**.

| Mode | Wall time | When to use |
|------|----------:|-------------|
| **Triage** | 5–15 min | Quick "is anything obviously rotten?" — skips Phase 4/6/7/10 |
| **Standard** *(default)* | 30–90 min | Periodic audits; runs Phases 1–9 |
| **Comprehensive** | 2–4 hours | Pre-release; all 10 phases + multi-model triangulation |
| **Tripwire** | 5 min, autonomous | CI/cron mode; report-only, exits non-zero on regression |
| **Single-bead** | 1–5 min | Pre-merge or deep-dive on one bead |
| **Re-verification** | 15–60 min | Subsequent passes; only re-scores changed beads |
| **Onboarding** | 1–3 hours | First audit on a new project; lenient threshold + CASS mining |
| **Red-team** | 30–60 min | Adversarial pass to find rubric-evasion attacks before someone exploits them ([RED-TEAM-MODE.md](references/RED-TEAM-MODE.md)) |
| **Spec-quality-gate** | 1 min / bead | Pre-implementation: score a bead's spec for auditability before claim ([SPEC-QUALITY-GATE.md](references/SPEC-QUALITY-GATE.md)) |
| **Committee** | 1–4 hours | High-stakes triangulation across N independent models ([MULTI-MODEL-COMMITTEE.md](references/MULTI-MODEL-COMMITTEE.md)) |

Auto-suggest at bootstrap: existing audit dir + recent pass → `re-verification`; never audited + > 50 closed beads → `onboarding`; CI context → `tripwire`; pre-release → `comprehensive` + `committee`; otherwise `standard`. Red-team mode is opt-in (recommended after every rubric change, every release, and quarterly).

---

## Tier Routing (by bead universe size)

Pick the parallelism shape from the closed-bead count. **10 concurrent agents is a hard cap** — past this, coordination cost beats parallelism gain (Agent Mail reservation thrash, NTM pane jank, prompt-cache fragmentation). Full playbooks in **[MODES-AND-TIERS.md](references/MODES-AND-TIERS.md)**.

| Tier | Closed beads | Parallelism | Coordination |
|------|:------------:|:-----------:|--------------|
| **Solo**       | < 20      | 1 (serial)         | none |
| **Pair**       | 20–150    | 2–3 subagents      | local file flock |
| **Squad**      | 150–500   | 4–5 subagents      | `/agent-mail` reservations |
| **Battalion**  | 500–1000  | 6–7 subagents      | `/agent-mail` + `/ntm` panes |
| **Swarm**      | 1000–1500 | 8–9 subagents      | `/multi-agent-swarm-workflow` + `/ntm` panes |
| **Mega-swarm** | 1500+     | **10** (hard cap)  | Same as Swarm; **prefer Sample mode** for affordability |

For 1500+ closed beads, **Sample mode** (15–50 stratified beads) is the recommended default; running a comprehensive pass at that scale is usually impractical and rarely justified. See [MODES-AND-TIERS.md § Sample mode](references/MODES-AND-TIERS.md#sample-mode-for-very-large-universes--1500-closed-beads).

---

## Audit Directory (Git Repo, Sacred)

```
<project>/beads_compliance_audit/   # subdir of the project; auto-added to project .gitignore
├── .git/                          # init-ed at bootstrap; every pass = auditable diff
├── manifest.json                  # run metadata, tool versions, parallelism, convergence
├── rubric.md                      # the EXACT scoring rubric for this project
├── REPORT.md                      # latest master report
├── synthesis.md                   # latest cross-bead findings
├── remediation.md                 # latest reopen/follow-up bead list (links to br IDs)
├── passes/
│   ├── 2026-05-05T12-00-00Z/      # one directory per verification pass
│   │   ├── manifest.json          # this pass's metadata
│   │   ├── REPORT.md              # snapshot of master report at pass time
│   │   ├── synthesis.md
│   │   ├── inventory.jsonl        # raw `br list --json` dump for the pass
│   │   ├── doctor.json            # raw `br doctor --json` dump
│   │   └── beads/
│   │       ├── bd-abc123/
│   │       │   ├── spec.json
│   │       │   ├── evidence.json
│   │       │   ├── compliance.json
│   │       │   ├── theater.json
│   │       │   ├── test_depth.json
│   │       │   ├── scorecard.md
│   │       │   └── raw/           # raw command outputs (test logs, coverage, fuzzer logs)
│   │       └── bd-def456/...
│   └── 2026-05-12T08-30-00Z/      # next pass, etc.
└── scripts/                       # symlinks to this skill's runner scripts (optional)
```

**Hard rules:**
- Never delete a prior pass directory. History is the point.
- Each pass commits a single audit-pass commit at the end (no partial commits mid-run).
- The audit dir lives **inside** the project tree but is tracked by its own `.git/` and added to the project's `.gitignore` by `bootstrap-audit.sh`. It is **separate** from the project repo — never push it to the project's remote unless the user explicitly wants to.

Full layout details, naming conventions, and per-file schemas: **[AUDIT-DIRECTORY-LAYOUT.md](references/AUDIT-DIRECTORY-LAYOUT.md)** and **[EVIDENCE-SCHEMAS.md](references/EVIDENCE-SCHEMAS.md)**.

---

## Up-Front Confirmations (Ask Before Starting)

1. **Project path?** Confirm the absolute path. If a git URL, ask whether to clone to `/tmp/<basename>` and operate on that worktree.
2. **Audit dir name?** Default: `<project>/beads_compliance_audit/` as a subdirectory of the project. Confirm it's OK to create + `git init` it (the dir auto-adds itself to the project's `.gitignore` so it never leaks into the project's git history).
3. **Mode?** Show the auto-suggested mode based on `br stats` (e.g., `closed-only` if there are >50 closed beads).
4. **Score threshold?** Default 700. Higher = stricter (more beads will be flagged false-closed). Lower = more lenient.
5. **Parallelism?** Confirm subagent fan-out per phase. Default 6.
6. **Resume?** If audit dir exists, default to a new dated pass under `passes/`.
7. **Remediation policy?** When a closed bead scores below threshold, do we (a) **reopen** the original (`br reopen <id>`), (b) **create new completion-debt beads** that link back to the original, or (c) **report only** (no bead writes)? Default: (b), the most additive and least destructive.
8. **Test execution OK?** Phase 4 will actually run tests, fuzzers, conformance harnesses, and (if configured) hit real services per `/testing-perfect-e2e-integration-tests-with-logging-and-no-mocks`. Confirm the project is in a state where this is safe (e.g., tests don't mutate prod DBs, no rate-limited APIs without sandboxes).
9. **CASS available?** If `/cass` is installed and indexed, run it during Phase 1 to mine prior false-closed examples for this project — they sharpen the per-project rubric.

If any helper skill referenced here is missing (`/operationalizing-expertise`, `/beads-br`, `/beads-bv`, `/beads-workflow`, `/fixing-beads-problems`, `/mock-code-finder`, `/reality-check-for-project`, `/multi-pass-bug-hunting`, `/testing-conformance-harnesses`, `/testing-fuzzing`, `/testing-golden-artifacts`, `/testing-metamorphic`, `/testing-perfect-e2e-integration-tests-with-logging-and-no-mocks`, `/testing-real-service-e2e-no-mocks`, `/codebase-archaeology`, `/codebase-report`, `/cass`, `/agent-mail`, `/multi-agent-swarm-workflow`): if the user has `jsm` installed and authenticated, offer `jsm install <name>` for each. Don't block the run if a helper is missing — note it and use the inline fallback.

---

## Skill Bootstrap (Phase 0.5 — right after inputs, before partition)

```bash
# 1. Verify bead store integrity FIRST. If broken, hand off to /fixing-beads-problems.
br doctor --json > /tmp/doctor_pre.json
# If exit != 0 or doctor reports issues, STOP and run /fixing-beads-problems.
# Do not continue with a corrupt bead store.

# 2. Confirm br is the right vintage and inventory the bead universe.
br --version
br stats --json
br list --json > /tmp/bead_inventory.jsonl

# 3. Bootstrap the audit directory (creates it, git inits, copies rubric, writes manifest).
./scripts/bootstrap-audit.sh <project-path> <score-threshold> <mode>

# 4. Discover helper skills that this run will use, offer to install missing ones.
./scripts/check-skills.sh <audit-dir>
```

The bootstrap script writes `manifest.json` and `rubric.md` into the audit dir, then opens a fresh `passes/<timestamp>/` directory for this run. Every subsequent phase appends to it.

---

## The 10-Phase Loop (Mandatory)

```
Phase 1  INVENTORY        br doctor + br list ALL beads; classify by type/status; build DAG
Phase 2  SPEC EXTRACTION  parse each bead body into structured checklist (spec.json)        ← parallel
Phase 3  EVIDENCE GATHER  locate code/tests/docs/CI claimed to fulfill spec (evidence.json) ← parallel
Phase 4  COMPLIANCE EXEC  actually run tests/fuzzers/harnesses/builds (compliance.json)     ← parallel*
Phase 5  ANTI-THEATER     mock-code-finder over evidence; flag stubs/TODOs (theater.json)   ← parallel
Phase 6  TEST DEPTH       coverage of bead's surface; fuzzer corpus; golden freshness; e2e  ← parallel
Phase 7  SYNTHESIS        cross-bead integration; contract drift; orphaned criteria         ← serial
Phase 8  SCORING          apply rubric; emit scorecard.md per bead + master REPORT.md       ← serial
Phase 9  REMEDIATION      reopen / create completion-debt beads via br; update bead graph   ← serial
Phase 10 FRESH EYES       sanity-check the audit itself; converge or run another pass       ← serial
```

`*` = parallel where safe. Phase 4 must serialize tests that share resources (DB ports, GPU, network rate limits).

**Per-phase one-liners** (full prompts in **[EXACT-PROMPTS.md](references/EXACT-PROMPTS.md)**, full playbook in **[PHASES.md](references/PHASES.md)**):

| Phase | One-liner | Owner | Output |
|------:|-----------|-------|--------|
| 1 | `br doctor` clean → enumerate every bead with full payload + git-history cross-ref | main | `inventory.jsonl`, `doctor.json`, DAG |
| 2 | Parse bead body → structured verification checklist (very literal: "if it says 60s fuzz, that's a checkbox") | `subagents/bead-spec-extractor.md` | `spec.json` per bead |
| 3 | Locate the code/tests/CI/docs that purport to fulfill each checklist item; cite file:line or `MISSING` | `subagents/evidence-gatherer.md` | `evidence.json` per bead |
| 4 | **Re-run the proof.** Tests, builds, fuzzers, conformance harnesses, real-service e2e. Capture stdout/stderr/exit. Never trust self-reports. | `subagents/compliance-verifier.md` | `compliance.json` per bead + raw logs |
| 5 | Apply `/mock-code-finder` to every evidence file; flag TODOs, `unimplemented!()`, hardcoded happy paths, mocks-where-forbidden, `assert true` tests, dead branches | `subagents/theater-detector.md` | `theater.json` per bead |
| 6 | Coverage of the *bead's specific code* (not project global); fuzzer corpus exists + runs without crashes for stated time; goldens present and recently regenerated; e2e hit real services per `/testing-real-service-e2e-no-mocks` | `subagents/test-depth-auditor.md` | `test_depth.json` per bead |
| 7 | Read all per-bead reports; find integration gaps (A consumes B, contract drifted), contradictions, shared invariants nobody owns, orphaned ACs, dependency cycles/orphans | `subagents/cross-bead-synthesizer.md` (1–2 senior agents) | `synthesis.md` |
| 8 | Apply rubric → per-bead `scorecard.md` + ranked `REPORT.md`; flag false-closed (closed but score < threshold) | `subagents/scorer.md` | `scorecard.md` × N + `REPORT.md` |
| 9 | For each false-closed bead: reopen OR create completion-debt bead linking back, copying the missing items verbatim from the scorecard. Update dep graph. | `subagents/remediator.md` | `remediation.md` + new `br` IDs |
| 10 | Fresh agent reviews the audit artifacts: rubric applied consistently? scorer too generous? whole categories missed? Decide convergence or another pass. | `subagents/fresh-eyes-rubric-auditor.md` | `convergence.json` |

**Critical invariant — Phase 4 cannot be skipped or faked.** A test that "passes" because the implementation short-circuits is a Phase 5 fail, not a Phase 4 pass. A bead claiming a fuzzer that doesn't actually compile is theater. Re-run everything; trust nothing.

Full per-phase playbook with exit criteria, exact prompts, and failure-mode rescue paths: **[PHASES.md](references/PHASES.md)**.

### Phase 9.5 — Mandatory polish loop after bead writes

**When Phase 9's policy is `reopen` or `completion-debt` AND it actually wrote one or more beads, you MUST run the 3-pass polish loop before declaring the audit complete.** This step is what turns the audit from "list of complaints" into "actionable plan-space output the next implementation session can pick up cleanly".

The polish loop applies the following prompt **three times in a row** to the set of beads Phase 9 just wrote/reopened. Each pass is one sweep through every new/reopened bead in the order they were created. Pass 1 catches the obvious clarity gaps; Pass 2 catches the cross-bead consistency gaps Pass 1 introduced; Pass 3 catches anything that drifted while polishing the others.

> **Polish prompt (verbatim — do not paraphrase, do not shorten):**
>
> Check over each bead super carefully — are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also make sure that as part of the beads we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Make sure to ONLY use the `br` cli tool for all changes, and you can and should also use the `bv` tool to help diagnose potential problems with the beads.

**Operational rules for Phase 9.5:**

- All edits go through `br update <id>` — never hand-edit the JSONL or the SQLite directly. (`br` writes both atomically.)
- Use `bv --robot-suggest` and `bv --robot-priority` to surface duplicates / missing deps / priority misalignments between sweeps.
- Each sweep must touch every newly-written bead at least once even if the LLM concludes "no changes needed" — record that decision in the comment field via `br comment` so future passes see the deliberation.
- After all 3 sweeps, run `br sync --flush-only` and commit `.beads/` to the project. Do **not** push to the project's remote (the user's call, per [Up-Front Confirmations](#up-front-confirmations-ask-before-starting)).
- Sweep budget: ~30s–2 min per bead per sweep. For ≥ 30 new beads, fan out across subagents (one bead per subagent) but keep the polish prompt verbatim.

**Why three sweeps, not one.** Sweep 1 fixes individual beads. Sweep 2 sees a new (now-coherent) graph and catches "bead A's polished AC contradicts bead B's unchanged AC". Sweep 3 verifies stability — if Sweep 3 still produces meaningful changes, the loop hasn't converged and **you should run a 4th sweep** before stopping. (In practice, Sweep 3 is usually a no-op or near-no-op; a noisy Sweep 3 is itself a signal worth flagging in `remediation.md#polish_loop_log`.)

**Scaffold script:** `scripts/polish-remediation-beads.sh <project> <pass-dir>` writes `<pass-dir>/polish_log.md` — a markdown template with three sweep sections, each pre-populated with the polish prompt verbatim, the per-bead `br show` snapshot, and empty Decision / `br update` fields for the orchestrator to fill in. It also captures one initial `bv` hygiene snapshot into `<pass-dir>/polish_bv_initial.json`. The script is **pure scaffolding** — it does not call any LLM and does not modify beads. The orchestrator agent (Claude / Codex / Gemini, whichever invoked this skill) is responsible for actually applying the polish prompt to each bead in each sweep section and making the `br update` / `br comment` calls. The wrapper `run-pass.sh` invokes the scaffold step automatically when `--policy=reopen|completion-debt` and Phase 9 wrote beads; to skip, pass `--no-polish`.

**Idempotency:** the scaffold script refuses to overwrite an existing `polish_log.md` so orchestrator notes are never silently clobbered. Pass `--force` to overwrite when restarting from scratch.

If you somehow find yourself wanting to skip Phase 9.5 because "the user just wants the report", remind yourself: the user has *already paid the audit cost*. Skipping the polish step means whoever picks up the new beads next will spend the same amount of time figuring out what they mean — except now they're in implementation-space where mistakes are 10× more expensive. **Plan-space is cheap. Implementation-space is expensive. Polish in plan-space.**

### Specialist subagents that supplement specific phases

The 10 above are the *core* — each phase has exactly one. On top of them, **14 more specialist subagents** layer in: 5 per-bead-type augmenters (run alongside the phase subagent for matching beads), 7 cross-cutting / post-pass overlays, and 2 pre-implementation gates. Total: 9 + 14 = 23 subagents in `subagents/`. A fresh agent should route bead-by-bead based on bead type / labels:

| Bead signature | Specialist to invoke (in addition to the phase subagent) | Phase |
|---------------|----------------------------------------------------------|------:|
| `security`, `auth`, `csrf`, `crypto`, `webhook`-signature | [`subagents/security-auditor.md`](subagents/security-auditor.md) — negative tests + OWASP/CWE patterns | 4, 5 |
| `perf`, `latency`, `bench`, numeric budget in spec | [`subagents/performance-auditor.md`](subagents/performance-auditor.md) — ≥30 samples + paired stats | 4, 6 |
| `migration`, `schema`, `ddl`, `backfill` | [`subagents/migration-safety-reviewer.md`](subagents/migration-safety-reviewer.md) — forward+reverse+rehearsal | 4 |
| `api`, `endpoint`, `graphql`, `grpc`, `webhook` payload | [`subagents/api-contract-checker.md`](subagents/api-contract-checker.md) — schema diff + version-bump match | 4, 7 |
| Onboarding / first audit on a new project | [`subagents/cass-pattern-miner.md`](subagents/cass-pattern-miner.md) — mine project-specific theater | 0.5 |

Plus 7 cross-cutting / post-pass subagents that don't bind to a single bead:

- [`subagents/red-team-adversary.md`](subagents/red-team-adversary.md) — adversarially probes the rubric for evasion attacks (Phase 10, opt-in).
- [`subagents/closer-defender.md`](subagents/closer-defender.md) — round-trip with the original closer before remediation (Phase 8.5).
- [`subagents/release-gate-keeper.md`](subagents/release-gate-keeper.md) — applies release policy to the latest pass; emits GO/NO-GO.
- [`subagents/audit-self-explainer.md`](subagents/audit-self-explainer.md) — audience-tailored narration of the *whole pass* (PM / exec / customer / regulator / dev-onboarding).
- [`subagents/human-friendly-explainer.md`](subagents/human-friendly-explainer.md) — translates *individual findings* (one bead, one scorecard) for non-technical stakeholders. Pairs with audit-self-explainer (whole-pass) at finer granularity.
- [`subagents/audit-reviewer.md`](subagents/audit-reviewer.md) — independent third-party review of the entire pass.
- [`subagents/trauma-guard.md`](subagents/trauma-guard.md) — cross-pass repeat-mistake detection by closer / session; emits a trauma report.

And [`subagents/spec-quality-reviewer.md`](subagents/spec-quality-reviewer.md) + [`subagents/bead-author-feedback.md`](subagents/bead-author-feedback.md) run *before* implementation (pre-claim gate), not in the audit pass at all.

Frozen, paste-ready user kickoff prompts (24 variants — Onboarding, Triage, Single-bead, Tripwire, Multi-repo, Performance, Security, Pre-merge gate, Spec-quality gate, Time-machine, Bisect, Reproducibility, Red-team, Release gate, Diff vs prior, Discover stack, Validate, Committee mode, and more): **[KICKOFF-PROMPTS.md](references/KICKOFF-PROMPTS.md)**.

---

## Operator Library (cognitive moves, not just rules)

The phase loop says *what* to do; the operator library says *how* a verifier thinks. Each operator is a named cognitive move with explicit triggers, failure modes, and a paste-ready prompt module. Adapted from `/operationalizing-expertise` Track A.

| Glyph | Name | Used in | Cite as |
|-------|------|---------|---------|
| ★ | ENUMERATE  | Phase 2 — name every checklist item literally | spec.json#item |
| ✦ | EXECUTE    | Phase 4 — actually run the proof | compliance.json#check raw=path |
| ⚖ | MEAN       | Phase 5 — does the artifact mean what it claims? | theater.json#finding |
| ◐ | MEASURE    | Phase 6 — does it cover the surface? | test_depth.json#check |
| ⊕ | INTEGRATE  | Phase 7 — do the pieces fit? | synthesis.md#integration-gaps |
| ⚑ | CONTRACT   | Phase 7 — does this bead break a sibling? | synthesis.md#contradictions |
| ⌂ | CONSEQUENCE| Phase 9 — what happens if this is missing? | scorecard.md#consequence |
| ⊙ | DE-SLOP    | Phase 8 — strip auto-generated padding | (presentational) |
| ⊞ | TRIANGULATE| Phase 10 — second-model audit | convergence.json#triangulation |
| ⊘ | SELF-POLICE| Phase 10 — audit the audit | convergence.json#generosity_flags |
| ⟳ | REPEAT-UNTIL-QUIET | inner loop in 4-6 | (presentational) |
| ☖ | STAKE-RUBRIC | mid-pass — never tune mid-pass | rubric.md#tunings |
| ✱ | ADVERSARIAL | Red-team mode — pre-discover rubric-evasion attacks | audit_resilience.json#attacks |
| ⊟ | BISECT     | Post-pass — git-bisect a bead-score regression | bisect/<bead-id>/bisect_log.txt |
| ⊧ | PROVENANCE | Phase 8 — every score citation traces to source | scorecard.md (path:line + commit_sha) |
| ⌗ | ATTRIBUTION| Phase 7 — stratify rates per closer; calibrate priors | attribution.json#agents[] |
| ⊻ | COMMITTEE  | Comprehensive — combine N model verdicts per bead-type rules | committee.json#phase_4_disagreements |

Each operator's full card (triggers, failure modes, prompt module) and the per-phase pipeline cheat-sheet: **[OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md)**.

> **Why name the moves.** The cognitive move is what the agent *does*; the rubric is what the result *means*; the artifact is what the score *cites*. Three different things. Conflating them is the most common audit-of-the-audit failure.

---

## The Scoring Rubric (0–1000)

The rubric is **published in the audit dir** as `rubric.md` so every score is auditable and reproducible. Default weighting (adjustable per bead type; see **[BEAD-TYPE-WEIGHTS.md](references/BEAD-TYPE-WEIGHTS.md)**):

| Dimension | Max | What it measures |
|-----------|----:|------------------|
| **Implementation completeness vs. spec** | 300 | Every code artifact named in the bead exists and does what the bead says it does (not just exists) |
| **Required tests present and meaningfully passing** | 250 | Each test type the bead names (unit/e2e/fuzz/property/metamorphic/golden/conformance) exists, compiles, runs, and exercises the real code path with non-trivial assertions |
| **Anti-theater / no stubs / no mocks where forbidden** | 150 | Zero TODOs, `unimplemented!()`, hardcoded returns, mocks-where-forbidden, `assert true`, `it.skip`, dead branches, sleep-as-fake-work |
| **Test depth** | 150 | Branch/line coverage over the bead's own code (not project-global); fuzzer ran for stated time without crashes; goldens regenerated recently; e2e hit real services |
| **Documentation, telemetry, migrations, feature flags as required** | 100 | Whatever non-code artifacts the bead enumerated (README updates, migration scripts, observability hooks, feature flags, runbooks) |
| **Cross-bead integration & no contradictions** | 50 | This bead's contract with its dependents/dependencies still holds; it didn't break a sibling bead |
| **TOTAL** | **1000** | A 1000 means every line item is satisfied with cited evidence |

**Score-to-verdict bands** (default; tunable in `rubric.md`):

| Band | Range | Verdict |
|------|------:|---------|
| 🟢 Verified | 950–1000 | Truly done. Ship-ready. |
| 🟢 Substantially complete | 850–949 | Minor gaps; document and move on. |
| 🟡 Partial | 700–849 | Acceptable for now but **not** "closed" caliber if the bead status says closed. |
| 🟠 False-closed (mild) | 500–699 | Status lies. Reopen or create completion-debt bead. |
| 🔴 False-closed (severe) | 250–499 | Substantially fictional. Reopen with high priority. |
| 🚨 Theater | 0–249 | Implementation is essentially absent. Original closer must be flagged. |

**Threshold for false-closed flag:** any bead whose `status == closed` AND `score < <threshold>` (default 700) → goes on the false-closed list and triggers Phase 9 remediation.

Full rubric mechanics, dimension breakdowns with examples, and tie-breakers: **[RUBRIC.md](references/RUBRIC.md)**.

---

## Per-Bead Evidence Pack (file naming)

Every artifact uses **stable IDs** (bead IDs, commit SHAs, file:line ranges, test names) so cross-references survive code churn. Every artifact carries an ISO-8601 UTC timestamp. **Raw command outputs are kept**, not just summaries.

```
passes/<UTC>/beads/<bead-id>/
├── spec.json          # Phase 2: structured checklist parsed from bead body
├── evidence.json      # Phase 3: file:line citations or MISSING per checklist item
├── compliance.json    # Phase 4: actual test/build/fuzz/harness exit codes + summaries
├── theater.json       # Phase 5: mock/stub/todo findings cross-referenced to evidence
├── test_depth.json    # Phase 6: coverage, fuzz duration, golden freshness, e2e realism
├── scorecard.md       # Phase 8: human-readable score breakdown with citations
└── raw/
    ├── tests.stdout   # captured test runner output
    ├── tests.stderr
    ├── coverage.json  # tool-native coverage output
    ├── fuzz.log       # fuzzer output if applicable
    └── ...            # whatever raw output Phase 4 produced
```

Each JSON file's exact schema — including required fields, value enums, and an example — lives in **[EVIDENCE-SCHEMAS.md](references/EVIDENCE-SCHEMAS.md)**. The `scorecard.md` template is in `assets/scorecard-template.md`.

---

## Convergence Criteria

The audit is **converged** (nothing more to do this round) when ALL of these are true:

- [ ] The latest pass produced **zero new false-closed findings** beyond what the prior pass flagged.
- [ ] The score change for every bead between the latest two passes is within **±10 points**.
- [ ] Phase 7 synthesis found **no new** integration gaps, contract drifts, or orphaned criteria.
- [ ] Phase 10 fresh-eyes review confirms the rubric was applied consistently and no whole category of bead was missed.
- [ ] All Phase 9 remediation beads exist in the bead graph (so the *bead graph itself* is now truthful).

If any of these fail, run another pass. The user invokes the skill again; the next pass writes a new `passes/<timestamp>/` subdirectory and `convergence-check.py` compares it to the prior pass.

Full convergence semantics, including handling of intentional rubric tightening between passes: **[CONVERGENCE-CRITERIA.md](references/CONVERGENCE-CRITERIA.md)**.

Multi-pass arc (Pass 1 onboarding → Pass 5 comprehensive → tripwire steady state), including ambition-rounds + plan-space-refinement borrowed from `/reality-check-for-project` and `/beads-workflow`: **[MULTI-PASS-FLOW.md](references/MULTI-PASS-FLOW.md)**.

---

## Tripwire Mode (Continuous Compliance)

After convergence, the audit dir becomes a *tripwire*: a baseline against which every subsequent state of the project can be checked. Periodic re-verification (cron / GitHub Actions / `/loop` / systemd timer) catches regressions early. Full setup including alerting hooks (Slack / email / GitHub issue), pre-merge audit hooks, and HTML dashboard generation: **[CI-TRIPWIRE.md](references/CI-TRIPWIRE.md)**.

| Cadence | Mode |
|---------|------|
| Daily (active development) | Tripwire |
| Weekly (steady-state) | Tripwire |
| Monthly (maintenance) | Standard |
| Per-release | Comprehensive |
| Pre-merge (PR closes a bead) | Single-bead |

---

## Multi-Repo Audit (Portfolio View)

When you maintain N projects, `scripts/portfolio-audit.sh` discovers every repo with `.beads/` under a parent directory, runs an audit pass on each (parallelized, capped at user's parallelism), and rolls up a single `__audit_portfolio_summary.md` with one row per project: closed count, false-closed rate, score median, convergence status. Cross-repo bead dependencies (rare but exists) are surfaced.

Full playbook including swarm-tier portfolio audits with `/ru-multi-repo-workflow` + `/ntm`: **[MULTI-REPO-AUDIT.md](references/MULTI-REPO-AUDIT.md)**.

---

## Bead-Graph Analysis (Centrality-Aware Auditing)

`/beads-bv` computes deterministic graph metrics over the bead DAG: PageRank, betweenness, HITS, eigenvector, critical path, articulation points, slack, k-core. Phase 1 captures these into `dag.json`; Phases 7-9 use them to weight bead importance. A 700-scoring bead at the critical-path bottleneck matters more than a 950-scoring bead in a backwater module — the executive summary surfaces high-PageRank false-closed beads first. Articulation-point beads get tighter convergence thresholds and 3× the Phase 10 spot-check probability. Cycles in the bead graph cause hard-fail of Phase 1. Full integration: **[BEAD-GRAPH-ANALYSIS.md](references/BEAD-GRAPH-ANALYSIS.md)**.

---

## Remediation Prioritization

Beyond the threshold (700) flag, the **`⌖ TARGET` operator** computes per-bead `priority_score = (1000 - score) × consequence_multiplier × downstream_blockers + p0_p1_bonus`. False-closed beads get sorted into 5 tiers (T0 fire, T1 high, T2 medium, T3 low, T4 defer). Stuck-bead trajectories (`600 → 600 → 600`) get classified into 5 stuck-reasons (no assignee, blocked, vague AC, unfix-as-scoped, agent fatigue) — each with a specific intervention. Sloppy-session escalation: when CASS mining identifies a session that batch-closed many false-closed beads, every bead by that session gets a -25 prior penalty. Worked example with 35 false-closed beads triaged into a 4-week remediation calendar: **[REMEDIATION-PRIORITIZATION.md](references/REMEDIATION-PRIORITIZATION.md)**.

---

## Cost Optimization

For daily-tripwire on 1000-bead projects: differential auditing (only re-verify beads whose evidence files changed since prior pass) drops 80%+ of work to cached-forward, reducing wall time 5-10×. Coverage measurement runs once per pass (not per bead). Subagent context amortization via prompt caching at SKILL.md / rubric.md breakpoints. Per-tier cost projections (Solo $0.06/bead, Swarm $0.03/bead) in **[COST-OPTIMIZATION.md](references/COST-OPTIMIZATION.md)**.

---

## Bayesian Verification (Optional, High-Stakes)

For safety-critical / regulatory audits, the deterministic 0-1000 score can be paired with a **Bayesian posterior** `P(bead claim is true | evidence)` and a 95% conformal interval (calibrated from Phase 10 spot-check residuals). A bead with deterministic score 720 might have Bayesian posterior 0.65 [0.55, 0.75] — surfacing residual uncertainty the point estimate hides. Sequential testing (Wald SPRT) reduces tripwire alert noise. Adapted from established conformal-prediction and Bayesian-verification literature. Opt-in per audit; the deterministic rubric remains primary for convergence semantics. Full framework + worked example: **[VERIFICATION-UNDER-UNCERTAINTY.md](references/VERIFICATION-UNDER-UNCERTAINTY.md)**.

---

## Advanced Capabilities (opt-in, audit-of-audit grade)

Five disciplines layer on top of the standard pass to push from "good audit" to "audit you'd cite in a regulatory submission":

| Capability | What it adds | Reference |
|------------|--------------|-----------|
| **Spec quality gate** | Catches the upstream cause of false-closed beads — vague ACs, missing test types, no rollback — *before* implementation begins. Heuristic baseline in `scripts/spec-quality-gate.sh`; LLM review in `subagents/spec-quality-reviewer.md`. | [SPEC-QUALITY-GATE.md](references/SPEC-QUALITY-GATE.md) |
| **Reproducibility verification** | Re-scores every bead from existing evidence packs and asserts identical output. Same evidence + same rubric → same score, every time. Fails CI on drift. | [AUDIT-REPRODUCIBILITY.md](references/AUDIT-REPRODUCIBILITY.md) |
| **Provenance graph** | Every artifact citation traces to project file:line + commit SHA + tool versions + rubric SHA. Regulator-readable; 3-hop walk from score to source code. | [PROVENANCE-GRAPH.md](references/PROVENANCE-GRAPH.md) |
| **Red-team mode** | Adversarial subagent constructs minimal-effort attacks against the rubric (coverage-via-import, panic-as-stub, citation salting, future-dated `closed_at`, …) and proposes patches before someone exploits them. | [RED-TEAM-MODE.md](references/RED-TEAM-MODE.md) |
| **Multi-model committee** | High-stakes Phases 4/5/7/10 run in parallel across N independent models (Anthropic + Gemini + GPT). Per-bead-type combination rules: any-failure-wins for security/migration; majority for general; intersection for synthesis. | [MULTI-MODEL-COMMITTEE.md](references/MULTI-MODEL-COMMITTEE.md) |

Plus three operational disciplines that make the whole thing affordable and trustworthy at scale:

- **Phase 4 environments** — sandbox the test re-runs (native / docker / nix / testcontainers) so blast radius is bounded and Bayesian calibration stays valid: **[PHASE-4-ENVIRONMENTS.md](references/PHASE-4-ENVIRONMENTS.md)**.
- **Prompt-cache amortization** — Anthropic 4-breakpoint cache pattern drops Squad/Swarm cost 70-90% (e.g. daily Tripwire on 1000 beads goes from ~$30k/month to ~$115/month): **[PROMPT-CACHE-AMORTIZATION.md](references/PROMPT-CACHE-AMORTIZATION.md)**.
- **Audit drift detection** — meta-meta watch: when the audit's *own* quality slips over many passes (rubric softened, scorer drift, false-cache from differential auditing), surface it before it rots: **[AUDIT-DRIFT.md](references/AUDIT-DRIFT.md)**.

**Bisection + attribution** close the feedback loop:
- A bead-score regression → `scripts/bisect-regression.sh` localizes to a single commit ([BISECTION-VERIFY.md](references/BISECTION-VERIFY.md)).
- A pattern of regressions by one agent → `scripts/synthesize.py` writes `attribution.json` with rolling false-closed rates per closer; `audit-policy.yaml#attribution.prior_penalty_*` calibrates next-pass priors ([AGENT-ATTRIBUTION.md](references/AGENT-ATTRIBUTION.md)).

---

## Project-Type Defaults

Per-language test commands, coverage scoping, and language-specific theater patterns. The auditor selects the right command set per cited file via `scripts/discover-stack.sh`. Covers Rust workspaces (cargo test / cargo fuzz / cargo-llvm-cov), TypeScript / Next.js (vitest / playwright / tsc), Python (pytest / hypothesis / mypy), Go (go test / go fuzz / go cover), and polyglot monorepos. Full per-language playbook: **[PROJECT-TYPES.md](references/PROJECT-TYPES.md)**.

---

## Bead-Type Verification Playbooks

Different bead types deserve different verification recipes. Bug beads stand or fall on their *regression test* (with BISECT proof: fails on prior commit, passes on fix commit). Feature beads need the *happy-path + error-path + edge-case test trio*. Epic beads need *child completion + integration test*. Migration beads need *forward + reverse + data-integrity*. Performance beads need *statistical-significance benchmarks against the budget*. Per-type implicit-requirement injection rules and verification recipes: **[BEAD-TYPE-PLAYBOOKS.md](references/BEAD-TYPE-PLAYBOOKS.md)**.

---

## CASS Mining (Project-Specific Patterns)

Before Phase 1 of an Onboarding-mode pass, mine `/cass` for project-specific theater patterns the generic `FAILURE-MODES.md` catalog won't catch. One project might have a recurring "agent X always closes beads in batches of 5". Another might have "agent Y always uses `tokio::time::sleep` to fake async I/O". These get folded into `rubric.md#project_specific_patterns` so future passes catch them automatically. Methodology: **[CASS-MINING.md](references/CASS-MINING.md)**.

The session-mined quote bank that anchors each generic pattern with a real verbatim quote (so future auditors recognize the *vibe*, not just the regex): **[QUOTE-BANK.md](references/QUOTE-BANK.md)**.

---

## Anti-Patterns (Never Do)

| ✗ | Why |
|---|-----|
| Create a new branch for the audit (`git checkout -b audit/...`) | The user explicitly forbids this. Audit dir has its own `.git/`; the project repo stays on the same branch it was on (typically `main`) |
| Create the audit dir as a sibling of the project (`/data/projects/foo_audit/`) | The audit dir is a SUBDIRECTORY of the project (`<project>/beads_compliance_audit/`); the project's `.gitignore` excludes it. Sibling layouts get lost, accidentally pushed, or re-created by future runs |
| Lead the report with "X false-closed beads found" before calibration | Across user's prior runs the deterministic-only headline overstated true false-closed by ~10–20× (15/15 of lowest-scoring beads were false positives). Always reframe with the calibration — "flagged for review" not "false-closed" |
| Skip Phase 9.5 polish loop after Phase 9 wrote beads | The polish loop is mandatory whenever Phase 9 wrote/reopened beads. Plan-space is cheap; implementation-space is 10× more expensive |
| Hand-edit `.beads/issues.jsonl` or the `.db` during Phase 9.5 | Use `br update` / `br comment` only — `br` keeps the JSONL and SQLite atomically in sync; manual edits drift |
| Trust `br list --status=closed` as proof of completion | The lying-status problem is the entire reason this skill exists |
| Re-use the previous pass's `compliance.json` instead of re-running tests | Tests rot; stale "pass" output is worse than no output |
| Score Phase 4 from the test runner's exit code alone | A test can exit 0 because it asserted nothing — Phase 5/6 catch this |
| Use mocks in Phase 4 e2e verification | Defeats the entire purpose; if the bead said no mocks, mocks-in-test is theater |
| Silently fix gaps you find during the audit | The audit *finds* gaps; remediation is a separate phase with bead-graph updates |
| Delete or overwrite a prior pass directory | History is the convergence signal; never destroy it |
| Skip Phase 1's `br doctor` check | Auditing on top of a corrupt bead store produces garbage scores; hand off to `/fixing-beads-problems` first |
| Aggregate-score a bead at 1000 without cited evidence | The rubric requires file:line, test names, commit SHAs, raw logs — vibes don't count |
| Commit the audit artifacts into the project's git history | Pollutes git history of the thing being audited; the audit dir lives inside the project tree but is tracked by its own `.git/` and the project's `.gitignore` excludes it (bootstrap-audit.sh maintains the entry) |
| Score generously to "be fair to the implementer" | The whole point is ruthless honesty — false-closed beads cost the project more than a 600 score does |
| Run a pass without committing the prior one | Each pass = one auditable diff; mid-pass commits scramble the history |
| Paraphrase the rubric instead of using `rubric.md` from the audit dir | Rubric drift between phases corrupts the score |
| Tune the rubric mid-pass | Score deltas vs. prior pass become uninterpretable; ⊘ STAKE-RUBRIC operator forbids it |
| Skip Phase 5/6 because Phase 4 said PASS | Theater invalidates Phase 4 verdicts (Axiom 4); skipping leaves false PASSes uncaught |
| Treat WAIVED as PASS in Phase 6 | WAIVED requires explicit reason linked to spec.json; otherwise it's just "skipped" |
| Run Tripwire mode with `--policy completion-debt` | Tripwire is autonomous; bead writes should require human review |
| Push the audit dir to the project's GitHub remote without explicit user opt-in | The audit dir is local-by-default; pushing scatters internal critique |
| Score generously to "be fair to the implementer" | The point is ruthless honesty; false-closed beads cost the project more than a 600 score does |
| Skip CASS mining on Onboarding mode | Generic patterns miss project-specific theater; the first audit's value is calibration |
| Trust a single converged pass | Convergence requires TWO consecutive passes (Axiom 8) |

Full anti-patterns with real session evidence: **[FAILURE-MODES.md](references/FAILURE-MODES.md)**.

---

## Polish Bar (Non-Negotiable)

Borrowed from `/documentation-website-for-software-project` and `/saas-billing-patterns-for-stripe-and-paypal`. Every audit pass must satisfy:

| Dimension | Test |
|-----------|------|
| **Citation discipline** | Every score dock has a file:line citation; no vibes-based "looks bad" |
| **Verbatim evidence** | Spec items quote bead body verbatim; missing-items list quotes scorecard verbatim |
| **Determinism** | Same evidence pack + same rubric → same score across two runs |
| **Operator coverage** | Every phase invokes its prescribed operators (per `OPERATOR-LIBRARY.md` cheat-sheet) |
| **Raw-output capture** | Phase 4's stdout/stderr/exit per check is in `raw/`, not just summarized |
| **No slop** | Apply `/de-slopify` to scorecards: no "comprehensive", "robust", "thorough" without numeric backing |
| **Trend awareness** | Every scorecard cites prior-pass score (when prior exists) |
| **Audit-of-audit** | Phase 10 spot-checks 5 random scorecards independently |

If a pass fails the Polish Bar, do not commit it. Fix and re-run.

---

## When to Use This Skill vs Adjacent Skills

| Situation | Use This | Not This |
|-----------|----------|----------|
| "Are our closed beads actually done?" | **this skill** | reality-check-for-project |
| "Where are we vs. the README vision?" | reality-check-for-project | this skill |
| "Find all stubs and mocks in the codebase" | mock-code-finder | this skill |
| "Audit for security/perf/UX issues" | codebase-audit | this skill |
| "Find all bugs" | multi-pass-bug-hunting | this skill |
| "The bead DB itself is broken" | fixing-beads-problems | this skill |
| "Plan-space refinement of beads before implementation" | beads-workflow / idea-wizard | this skill |
| "Decide what bead to work on next" | bv | this skill |
| "Verify a single PR closed its bead correctly" | this skill in `single-bead <id>` mode | full audit |

This skill **stands on top of**: `/mock-code-finder` (Phase 5), `/multi-pass-bug-hunting` (Phase 4 fresh-eyes loop), `/testing-conformance-harnesses` + `/testing-fuzzing` + `/testing-golden-artifacts` + `/testing-metamorphic` + `/testing-perfect-e2e-integration-tests-with-logging-and-no-mocks` (Phase 6), `/reality-check-for-project` (Phase 7 synthesis), `/fixing-beads-problems` (Phase 1 escape hatch), `/beads-br` + `/beads-workflow` (Phase 9 remediation).

Detailed integration: **[INTEGRATION-WITH-OTHER-SKILLS.md](references/INTEGRATION-WITH-OTHER-SKILLS.md)**.

---

## Pre-Flight & End Checklist

- [ ] **Pre-flight:** `br doctor` exits clean; if not, stop and use `/fixing-beads-problems`
- [ ] **Pre-flight:** Audit dir created as `<project>/beads_compliance_audit/` subdirectory, `git init`-ed, project `.gitignore` updated to exclude it, `manifest.json` (with `rubric_sha256` pinned + `remediation_policy` recorded) and `rubric.md` written
- [ ] **Pre-flight:** Mode + tier auto-suggested; user confirmed
- [ ] **Pre-flight:** Bead universe inventoried (`inventory.jsonl`); count of open/in-progress/blocked/closed/draft confirmed with the user
- [ ] **Pre-flight (Onboarding only):** CASS mining produced `cass_mining/patterns.md`; project-specific patterns folded into `rubric.md`
- [ ] **Phase 2:** Every bead has a `spec.json`; checklist items are literal (every bullet, every "must include", every test type explicitly named); `★ ENUMERATE` operator applied
- [ ] **Phase 3:** Every spec checklist item maps to either a `file:line` citation or `MISSING` in `evidence.json`; `gather-evidence.sh` ran as deterministic baseline
- [ ] **Phase 4:** All claimed tests **actually re-run**; raw logs captured under `raw/`; never trust self-reports; `✦ EXECUTE` operator applied
- [ ] **Phase 5:** `/mock-code-finder` applied to every evidence file via `theater-scan.sh`; non-grep anomalies (apologetic close reason, batch-close, time-to-close, empty PR diff, ignore-list growth, no-git-xref) caught via `anomaly-scan.sh`; theater findings cross-referenced to Phase 4 outputs; `⚖ MEAN` operator applied
- [ ] **Phase 6:** Coverage measured over the bead's own code (not global); fuzzer corpus + duration verified; goldens fresh; e2e hit real services; `◐ MEASURE` operator applied
- [ ] **Phase 7:** Cross-bead `synthesis.md` produced; integration gaps + orphaned ACs + dependency anomalies enumerated; `⊕ INTEGRATE` + `⚑ CONTRACT` operators applied
- [ ] **Phase 8:** Per-bead `scorecard.md` + master `REPORT.md` written; false-closed list explicit; `⊙ DE-SLOP` and `⌘ REDUCE` operators applied
- [ ] **Phase 9:** Every false-closed bead has either been reopened OR has a linked completion-debt bead; new bead IDs recorded in `remediation.md`; `⌂ CONSEQUENCE` operator informed priority
- [ ] **Phase 9.5 (mandatory if Phase 9 wrote beads):** 3-pass polish loop applied to every new/reopened bead via `br update` (NEVER hand-edit JSONL/SQLite); `bv --robot-suggest` consulted between sweeps; sweep log appended to `<pass-dir>/polish_log.md`; if Sweep 3 still produces meaningful edits, ran a Sweep 4
- [ ] **Calibration check (always, before reporting):** Spot-checked the bottom-N (5–10) lowest-scoring beads via `scripts/calibrate-bottom-n.sh` or LLM ground-truth review; reframed the headline accordingly so the user doesn't see a falsely alarming "X false-closed" number
- [ ] **Branch / dir hygiene:** Project repo is still on the same branch it was on at the start of the audit (no `git checkout`, no `git checkout -b`); confirmed via `manifest.json#project_branch_at_pass_start` matching `git rev-parse --abbrev-ref HEAD` at exit; audit dir lives at `<project>/beads_compliance_audit/` (NOT a sibling); `<project>/.gitignore` includes it
- [ ] **Phase 10:** Fresh-eyes review of the audit itself; rubric consistency verified via `⊘ SELF-POLICE`; high-stakes audits add `⊞ TRIANGULATE`
- [ ] **Convergence check:** Compared to prior pass; ±10 deviation; zero new false-closed → converged. Otherwise → schedule next pass.
- [ ] **Dashboard:** `dashboard.html` regenerated for the audit dir
- [ ] **Polish Bar:** Every dimension above passed (citation discipline, verbatim evidence, determinism, operator coverage, raw-output capture, no slop, trend awareness, audit-of-audit)
- [ ] **Commit:** Single audit-pass commit in the audit dir; `git log --oneline` shows one commit per pass.
- [ ] **Tripwire (post-converge):** Wired into CI / cron / `/loop` per `CI-TRIPWIRE.md`

---

## Reference Index

### Foundational
| Need | File |
|------|------|
| Human-facing user README (entry point for non-agents) | [README.md](README.md) |
| Glossary — every term used across the skill | [JARGON.md](references/JARGON.md) |
| Why this skill works the way it does (8 invariants) | [DESIGN-PHILOSOPHY.md](references/DESIGN-PHILOSOPHY.md) |
| 10 worked case studies (false-closed, healthy, epic, perf, security, migration, stuck, yo-yo, contract drift, portfolio find) | [CASE-STUDIES.md](references/CASE-STUDIES.md) |
| Full narrated audit walkthrough (5-bead synthetic project, Phases 1-10, then Pass 2 → convergence) | [WALKTHROUGH-EXAMPLE.md](references/WALKTHROUGH-EXAMPLE.md) |
| Common questions | [FAQ.md](references/FAQ.md) |
| How this skill compares to alternatives (manual review / JIRA / dynamic analyzers / human auditor) | [COMPARISON.md](references/COMPARISON.md) |
| What this skill can't do (honest limits) | [KNOWN-LIMITATIONS.md](references/KNOWN-LIMITATIONS.md) |
| Skill version history + upgrade guide | [CHANGELOG.md](references/CHANGELOG.md) |
| Audit dir migration (project rename / handoff / split) | [MIGRATION.md](references/MIGRATION.md) |
| README badges (convergence, false-closed count, score median, last audit) | [BADGE.md](references/BADGE.md) |

### Core methodology
| Need | File |
|------|------|
| Phase-by-phase playbook with exit criteria | [PHASES.md](references/PHASES.md) |
| Phase 9.5 polish loop (verbatim prompt, worked example, bv interaction, non-convergence handling) | [PHASE-9-5-POLISH-LOOP.md](references/PHASE-9-5-POLISH-LOOP.md) |
| Calibration framing — how to read deterministic-only false-closed counts (15/15 case study, the prior, decision tree) | [CALIBRATION-FRAMING.md](references/CALIBRATION-FRAMING.md) |
| Cognitive operators — 31 named moves (★ ENUMERATE, ✦ EXECUTE, ⚖ MEAN, ◐ MEASURE, ⊕ INTEGRATE, ⚑ CONTRACT, § ANCHOR, ⊿ DISCRIMINATE, ⌖ TARGET, ↻ RETRY, ⌀ ZERO, ⊠ PIN, ⟴ AMORTIZE, ⊳ DELEGATE, ⌥ ROLLBACK-PROOF, ⊡ FRAME, ⌬ HARMONIZE, ⊙ DE-SLOP, ⊞ TRIANGULATE, ⊘ SELF-POLICE, ⟳ REPEAT-UNTIL-QUIET, ⌂ CONSEQUENCE, ⤵ DECOMPOSE, ☖ STAKE-RUBRIC, ☍ DISCLAIMER-WINDOW, ⌘ REDUCE, ✱ ADVERSARIAL, ⊟ BISECT, ⊧ PROVENANCE, ⌗ ATTRIBUTION, ⊻ COMMITTEE) | [OPERATOR-LIBRARY.md](references/OPERATOR-LIBRARY.md) |
| Verbatim user-facing kickoff prompts (24 variants) | [KICKOFF-PROMPTS.md](references/KICKOFF-PROMPTS.md) |
| Phase-internal prompts for each subagent | [EXACT-PROMPTS.md](references/EXACT-PROMPTS.md) |
| Full scoring rubric mechanics with formulas | [RUBRIC.md](references/RUBRIC.md) |
| Bead-type-specific weighting (feature/bug/test/infra/docs/chore) | [BEAD-TYPE-WEIGHTS.md](references/BEAD-TYPE-WEIGHTS.md) |
| Bead-type verification playbooks (per-type implicit reqs + recipes including BISECT-verify) | [BEAD-TYPE-PLAYBOOKS.md](references/BEAD-TYPE-PLAYBOOKS.md) |
| Mode variants (Triage/Standard/Comprehensive/Tripwire/Single/Resume/Onboarding/Sample) and tier routing (Solo/Pair/Squad/Battalion/Swarm/Mega-swarm; 10-agent hard cap) | [MODES-AND-TIERS.md](references/MODES-AND-TIERS.md) |
| Multi-pass arc + ambition rounds + plan-space refinement | [MULTI-PASS-FLOW.md](references/MULTI-PASS-FLOW.md) |
| Remediation prioritization (consequence weighting, T0-T4 tiers, stuck-bead classification, sloppy sessions) | [REMEDIATION-PRIORITIZATION.md](references/REMEDIATION-PRIORITIZATION.md) |
| Bead-graph analysis (PageRank-weighted execution, articulation points, critical path, cycles must be empty) | [BEAD-GRAPH-ANALYSIS.md](references/BEAD-GRAPH-ANALYSIS.md) |

### Artifacts & contracts
| Need | File |
|------|------|
| Audit directory layout, naming conventions | [AUDIT-DIRECTORY-LAYOUT.md](references/AUDIT-DIRECTORY-LAYOUT.md) |
| Per-file JSON schemas with examples | [EVIDENCE-SCHEMAS.md](references/EVIDENCE-SCHEMAS.md) |
| Convergence detection semantics | [CONVERGENCE-CRITERIA.md](references/CONVERGENCE-CRITERIA.md) |

### Failure-mode catalog
| Need | File |
|------|------|
| 46 real-world false-closed patterns (with rubric impact + remediation) | [FAILURE-MODES.md](references/FAILURE-MODES.md) |
| Session-mined verbatim quotes anchoring each pattern | [QUOTE-BANK.md](references/QUOTE-BANK.md) |
| How to remediate (reopen vs. completion-debt vs. report-only) | [REMEDIATION-PATTERNS.md](references/REMEDIATION-PATTERNS.md) |

### Project ergonomics
| Need | File |
|------|------|
| Per-language defaults (Rust / TS / Python / Go / polyglot) | [PROJECT-TYPES.md](references/PROJECT-TYPES.md) |
| Mining cass for project-specific theater patterns | [CASS-MINING.md](references/CASS-MINING.md) |
| CI / cron / loop tripwire setup with alerting | [CI-TRIPWIRE.md](references/CI-TRIPWIRE.md) |
| Multi-repo portfolio audit (rolling up across N projects) | [MULTI-REPO-AUDIT.md](references/MULTI-REPO-AUDIT.md) |
| Telemetry export (Prometheus + OpenTelemetry + Grafana) | [METRICS-PIPELINE.md](references/METRICS-PIPELINE.md) |
| Cost optimization for large projects + tripwire | [COST-OPTIMIZATION.md](references/COST-OPTIMIZATION.md) |
| When the audit results look wrong — troubleshooting flowchart | [DEBUGGING-THE-AUDIT.md](references/DEBUGGING-THE-AUDIT.md) |
| Knock-out pre-flight checks before Phase 1 | [PRE-AUDIT-CHECKS.md](references/PRE-AUDIT-CHECKS.md) |
| The rubric DSL (custom check pipelines, custom theater patterns, per-label overrides) | [AUDIT-AS-CODE.md](references/AUDIT-AS-CODE.md) |
| Synthetic test projects for regression-testing the audit infrastructure itself | [AUDIT-FIXTURE-LIBRARY.md](references/AUDIT-FIXTURE-LIBRARY.md) |
| Patterns indicating the audit *itself* is sick (vs. project theater) | [AUDIT-SMELLS.md](references/AUDIT-SMELLS.md) |

### Specialty modes
| Need | File |
|------|------|
| Incident-driven retro audit (production fire → which beads should have prevented it?) | [POST-MORTEM-MODE.md](references/POST-MORTEM-MODE.md) |
| Re-audit AS-OF a historical commit (would past-rubric have caught past-incident?) | [TIME-MACHINE-MODE.md](references/TIME-MACHINE-MODE.md) |
| Gate a release on the audit verdict (per-milestone or per-PR) | [RELEASE-GATING.md](references/RELEASE-GATING.md) |
| Original closer's evidence response before remediation (Phase 8.5) | [CLOSER-DEFENSE.md](references/CLOSER-DEFENSE.md) |
| Composing audit with reality-check / security-audit / idea-wizard / multi-agent-swarm | [CROSS-SKILL-COMPOSITION.md](references/CROSS-SKILL-COMPOSITION.md) |
| Adversarial probe of the audit itself; pre-discover rubric-evasion attacks | [RED-TEAM-MODE.md](references/RED-TEAM-MODE.md) |
| Pre-implementation gate: score a bead's spec for auditability before claim | [SPEC-QUALITY-GATE.md](references/SPEC-QUALITY-GATE.md) |
| Localize a bead-score regression to a single commit via git-bisect | [BISECTION-VERIFY.md](references/BISECTION-VERIFY.md) |
| Determinism guarantees and reproducibility verification | [AUDIT-REPRODUCIBILITY.md](references/AUDIT-REPRODUCIBILITY.md) |
| Multi-model committee patterns for high-stakes audits | [MULTI-MODEL-COMMITTEE.md](references/MULTI-MODEL-COMMITTEE.md) |
| Sandboxing Phase 4 test re-runs (native / docker / nix / testcontainers) | [PHASE-4-ENVIRONMENTS.md](references/PHASE-4-ENVIRONMENTS.md) |
| Per-agent attribution rates, priors, and constructive feedback patterns | [AGENT-ATTRIBUTION.md](references/AGENT-ATTRIBUTION.md) |
| Provenance graph: every artifact's source chain, regulator-readable | [PROVENANCE-GRAPH.md](references/PROVENANCE-GRAPH.md) |
| Anthropic prompt-cache breakpoints for affordable Squad/Swarm passes | [PROMPT-CACHE-AMORTIZATION.md](references/PROMPT-CACHE-AMORTIZATION.md) |
| Detecting drift in the audit's own quality over time | [AUDIT-DRIFT.md](references/AUDIT-DRIFT.md) |

### Compliance and security
| Need | File |
|------|------|
| Tamper detection for audit dir (rubric_sha256, signed commits, append-only logs) | [ANTI-CORRUPTION.md](references/ANTI-CORRUPTION.md) |
| Bundle audit pass for SOC2 / HIPAA / PCI / ISO27001 evidence delivery | [COMPLIANCE-EVIDENCE-PACK.md](references/COMPLIANCE-EVIDENCE-PACK.md) |

### Advanced (opt-in, high-stakes audits)
| Need | File |
|------|------|
| Bayesian framework for completion-confidence intervals | [VERIFICATION-UNDER-UNCERTAINTY.md](references/VERIFICATION-UNDER-UNCERTAINTY.md) |
| Adding a new failure-mode pattern to the catalog | [CONTRIBUTING-PATTERNS.md](references/CONTRIBUTING-PATTERNS.md) |

### Integration
| Need | File |
|------|------|
| How adjacent skills plug into each phase (high-level) | [INTEGRATION-WITH-OTHER-SKILLS.md](references/INTEGRATION-WITH-OTHER-SKILLS.md) |
| Per-skill deep-dive integration playbooks (lean-formal, security-audit, perf-budget, math-heavy, security, admin-routes, business-metrics, triangulation, deadlock, profiling, de-slopify, gh-actions, testing-* family) | [EXTENDED-INTEGRATION.md](references/EXTENDED-INTEGRATION.md) |

---

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/bootstrap-audit.sh` | Create `<project>/beads_compliance_audit/`, `git init`, add to project `.gitignore`, write `manifest.json` (with `rubric_sha256` pinned) and `rubric.md`, open `passes/<timestamp>/` |
| `scripts/check-skills.sh` | Detect which referenced helper skills are installed; offer `jsm install` for missing ones |
| `scripts/inventory-beads.sh` | `br doctor` + `br list --json` (handles all three br output shapes + pagination) → `inventory.jsonl`; cross-references closed beads against `git log --grep=<bead-id>` |
| `scripts/extract-spec.py` | Parse bead body (description + design + acceptance_criteria + notes) → `spec.json` checklist; honors bullet types (`-`, `*`, `+`, `1.`, `[ ]`, `- [x]`); preserves numeric content |
| `scripts/gather-evidence.sh` | For one bead, find code/tests/CI/docs claimed to fulfill the spec via `git log --grep`, blame, and `rg`; deterministic baseline that runs even without subagents |
| `scripts/theater-scan.sh` | Apply `/mock-code-finder` patterns over evidence files (`-I` ignores binary; handles rg edge cases); emit `theater.json` |
| `scripts/anomaly-scan.sh` | Phase 5 follow-up: check non-grep anomalies (apologetic close reasons, batch-close, time-to-close < 5 min, empty PR diff, ignore-list growth, no-git-xref) and merge into `theater.json` |
| `scripts/synthesize.py` | Produce `synthesis.md` (integration gaps, orphan ACs, dependency anomalies, bead-graph truthfulness flags) from cross-bead reading |
| `scripts/score-bead.py` | Apply rubric to one bead's evidence pack → `scorecard.md`. Reads rubric.md frontmatter overrides, synthesis findings (not always max!), and prior-pass scorecard for trend |
| `scripts/master-report.py` | Aggregate per-bead scorecards into `REPORT.md` with ranking + summary stats + false-closed list + per-bead trends |
| `scripts/remediate.sh` | Reopen or create completion-debt beads via `br` (using `--description=...` equals form to handle leading hyphens), populate `acceptance_criteria` field, re-link dependents |
| `scripts/calibrate-bottom-n.sh` | **Mandatory before acting on REPORT.md.** Spot-check the bottom-N flagged beads against the real codebase: lists commits referencing the bead ID, verifies cited files exist, and prints the scorecard's missing-items checklist for ground-truth review. Read-only against the project. |
| `scripts/polish-remediation-beads.sh` | **Phase 9.5 scaffold writer — mandatory whenever Phase 9 wrote beads.** Reads `remediation.md` to discover the new/reopened bead IDs, captures one initial `bv` hygiene snapshot, and writes `polish_log.md` containing three sweep sections (each with the polish prompt verbatim + per-bead `br show` state + Decision slots). The orchestrator agent fills in the polish_log and routes all edits through `br update` / `br comment` (NEVER hand-edits JSONL/SQLite). Idempotent: refuses to overwrite an existing `polish_log.md` unless `--force`. |
| `scripts/validate-polish-prompt-consistency.py` | Lint that the verbatim Phase 9.5 polish prompt is character-identical across its three homes — `assets/polish-prompt.txt` (canonical), `SKILL.md` blockquote, and the `POLISH_PROMPT='...'` bash variable in `polish-remediation-beads.sh`. Run pre-commit or in CI to catch silent drift (em-dash vs hyphen, smart-quote vs straight-quote, etc.); the user's standing instruction is that the prompt MUST be applied verbatim. |
| `scripts/convergence-check.py` | Compare current pass to prior pass; emit `convergence.json` (rubric-change-aware); decide if another pass is needed |
| `scripts/dashboard.py` | Emit a self-contained HTML dashboard: score distribution histogram, median-over-passes line chart, false-closed-over-passes bar chart, top-20 worst beads with trajectories |
| `scripts/portfolio-audit.sh` | Discover every repo with `.beads/` under a parent dir, run audit on each in parallel (capped), respects `~/.audit_portfolio_excludes` |
| `scripts/portfolio-rollup.py` | Aggregate per-repo audit dirs into `__audit_portfolio_summary.md` (headline KPIs, per-project ranking, worst-of-worst beads) |
| `scripts/trauma-guard.sh` | Cross-pass detection of repeat-mistake patterns by the same agent / session; emits `trauma_report.md` |
| `scripts/metrics-export.sh` | Emit Prometheus textfile-collector metrics for Grafana / Alertmanager |
| `scripts/migrate-audit-dir.sh` | Move an audit dir to follow a project rename / relocate / handoff |
| `scripts/run-pass.sh` | End-to-end wrapper: bootstrap → inventory → extract-spec → gather-evidence → theater + anomaly scan → synthesize → score → master-report → remediate → convergence → dashboard |
| `scripts/single-bead-audit.sh` | Pre-merge / deep-dive: full audit pass scoped to one bead. Phase 1 + 7 still see the full universe (so synthesis can detect cross-bead breakage); Phases 2–6, 8, 9 scoped to the target. Exit 2 on false-closed for CI gating. |
| `scripts/time-machine-audit.sh` | Run an audit pass against a historical commit (worktree-based, never touches the project's main working tree). Tags `manifest.json#as_of_sha`. |
| `scripts/diff-passes.sh` | Compare two audit passes; print headline KPI deltas, top regressors, top improvers, newly false-closed, newly recovered, universe changes. |
| `scripts/bisect-regression.sh` | git-bisect a bead-score regression using `single-bead-audit.sh` as predicate; isolates the offending commit. |
| `scripts/reproducibility-check.py` | Re-score every bead from existing evidence packs; assert match to prior recorded scores (determinism invariant). Exit 1 on drift. |
| `scripts/spec-quality-gate.sh` | Pre-claim hook: score a NEW (open/draft) bead's spec on 6 dimensions; gate or advise. Pairs with `subagents/spec-quality-reviewer.md`. |
| `scripts/discover-stack.sh` | Detect project's primary language(s), build/test/coverage/fuzz/bench commands, monorepo shape, CI presence; emit JSON profile. Bootstrap consumes this for per-language defaults. |
| `scripts/validate-evidence.py` | Lint per-bead evidence pack JSON: required fields, ISO timestamps, bead-id consistency across files, BLOCKING-theater→PASS-compliance cross-check. |
| `scripts/validate-rubric.py` | Lint `rubric.md`: dimension max sum to 1000, score bands cover [0,1000] without gaps/overlaps, threshold in range, marker pairs balance, manifest sha256 cross-check. |
| `scripts/validate-audit-dir.py` | Top-level audit-dir integrity: required files, manifest fields, pass-dir naming, rubric_sha256 cross-check, .git presence, stale-HEAD warning, crud detection. |
| `scripts/validate-operators.py` | Lint `references/OPERATOR-LIBRARY.md`: each card has triggers / failure modes / prompt module / phase reference; glyph uniqueness; cross-check with SKILL.md citations. |
| `scripts/validate-quote-bank.py` | Lint `references/QUOTE-BANK.md`: stable anchors, source attribution, tags, blockquote presence, links to FAILURE-MODES patterns. |
| `scripts/preflight.sh` | Knock-out checks before audit (br doctor, no dep cycles, ≥5 closed beads, git repo, tooling presence, free disk). Exit 2 on abort. Wired into `bootstrap-audit.sh`. |
| `scripts/integrity-check.sh` | Tamper detection on a finished audit dir: rubric_sha256 still matches, no non-standard commit messages, per-pass artifact-tree SHA matches recorded, AUDIT_LOG length consistent. |
| `scripts/closer-respond.sh` | Closer-side: submit a defense response for one bead. Writes `<pass-dir>/beads/<id>/closer_response.md` + appends to `<audit-dir>/closer_responses.jsonl`. Pairs with the closer-defender subagent. |
| `scripts/process-defense.py` | Phase 8.5 deterministic half: scaffolds `defense.json` next to the evidence pack and appends a `## Defense round` section to `scorecard.md` for `subagents/closer-defender.md` to fill in. |
| `scripts/build-compliance-pack.sh` | Bundle one audit pass into a regulator-ready zip with framework-specific controls mapping (SOC2 / HIPAA / PCI / ISO27001 / generic). Optional `COMPLIANCE_GPG_KEY=` to GPG-sign. |
| `scripts/drift-check.py` | Cross-pass quality-drift detector: trends score median, false-closed rate, theater-density, convergence delta over the last N passes (default 8). Exit 1 on `DRIFT_DETECTED`. Gated on rubric_sha256 constancy in the window. |
| `scripts/regression-test.sh` | Run every fixture in `assets/fixtures/`, audit each via `run-pass.sh`, diff REPORT.md against the fixture's `EXPECTED.md`. Exit 1 on any failure. |
| `scripts/compare-to-expected.py` | Structured diff of an actual REPORT.md against a fixture's `EXPECTED.md` (`## Assertions` section). Supported verbs: `total_beads`, `false_closed_count`, `false_closed_includes`, `score_min_for`, `verdict_band_for`, `contains_text`, etc. |
| `scripts/regenerate-fixture.sh` | Regenerate one fixture's `EXPECTED.md` after a deliberate rubric/scorer change. Stashes the prior, re-runs the audit, captures the new ground-truth assertions, prints the diff for review. |
| `scripts/_load-policy.sh` | **Sourced** helper (non-executable). Loads `audit-policy.yaml` for `run-pass.sh`, `single-bead-audit.sh`, `bisect-regression.sh`, `diff-passes.sh`, `spec-quality-gate.sh`. Sets `POLICY_THRESHOLD` and `POLICY_REMEDIATION_POLICY` if the YAML defines them. |

All scripts emit machine-readable JSON to stdout (with `--robot` or default) and human-readable summaries to stderr. Designed so subagents can pipe outputs directly into the next phase. **Every executable script supports `--help`** (e.g. `scripts/run-pass.sh --help`).

---

## Subagents

| Subagent | Phase | Purpose |
|----------|------:|---------|
| `subagents/bead-spec-extractor.md` | 2 | Parse one bead body into a literal verification checklist |
| `subagents/evidence-gatherer.md` | 3 | Locate code/tests/CI/docs that allegedly fulfill the spec |
| `subagents/compliance-verifier.md` | 4 | Re-run the claimed proof and capture raw outputs |
| `subagents/theater-detector.md` | 5 | Scan evidence for stubs, mocks-where-forbidden, hardcoded returns, dead branches |
| `subagents/test-depth-auditor.md` | 6 | Measure coverage of bead's surface, fuzzer depth, golden freshness, e2e realism |
| `subagents/cross-bead-synthesizer.md` | 7 | Read all per-bead reports; find integration gaps and contradictions |
| `subagents/scorer.md` | 8 | Apply rubric to produce per-bead scorecards and the master report |
| `subagents/remediator.md` | 9 | Reopen / create completion-debt beads; update bead graph |
| `subagents/fresh-eyes-rubric-auditor.md` | 10 | Independent review of the audit's own consistency |
| `subagents/audit-reviewer.md` | post-10 | Optional: third-party review of the entire audit pass quality |
| `subagents/bead-author-feedback.md` | pre-implementation | Review a NEW (open) bead's spec quality; help authors write auditable beads |
| `subagents/trauma-guard.md` | post-pass, cross-pass | Detect repeat-mistake patterns by the same agent / session across passes |
| `subagents/closer-defender.md` | 8.5 | Process a closer's defense response and re-derive score |
| `subagents/human-friendly-explainer.md` | post-pass | Translate audit results to PM / exec / customer / regulator audiences |
| `subagents/security-auditor.md` | 4 / 5 | Security-flavored bead specialist: threat model re-derivation, negative test verification, OWASP/CWE patterns, mocks-where-forbidden enforcement |
| `subagents/performance-auditor.md` | 4 / 6 | Perf-flavored bead specialist: ≥30 samples, statistical significance vs prior pass, paired Wilcoxon/t-test, environment normalization |
| `subagents/migration-safety-reviewer.md` | 4 | Migration bead specialist: forward + reverse + idempotency + dry-run + rehearsal + rollback drill + lock-test + post-backfill row count |
| `subagents/api-contract-checker.md` | 4 / 7 | API/wire-format specialist: schema diff via oasdiff/buf-breaking, version-bump-vs-impact match, consumer-surface scan |
| `subagents/red-team-adversary.md` | 10 | Adversarially probe rubric for evasion attacks; emit `audit_resilience.json` with patch recommendations + fixtures |
| `subagents/spec-quality-reviewer.md` | pre-claim | Score a NEW bead's spec on 6 dimensions before any agent claims it; gate or advise |
| `subagents/cass-pattern-miner.md` | 0.5 | Formalized CASS-mining pass; emit `cass_mining/patterns.md` + append `# Project-specific patterns` to rubric.md |
| `subagents/release-gate-keeper.md` | post-pass | Apply release policy to latest pass; emit GO/NO-GO verdict with explicit blocker enumeration |
| `subagents/audit-self-explainer.md` | post-pass | Audience-tailored narration of the whole pass (PM / exec / customer / regulator / dev-onboarding) without losing technical truth |

---

## Assets

| Asset | Purpose |
|-------|---------|
| `assets/manifest-template.json` | Starter `manifest.json` for a fresh audit dir |
| `assets/rubric-template.md` | Default rubric copied into each audit dir as `rubric.md` |
| `assets/scorecard-template.md` | Per-bead scorecard structure |
| `assets/report-template.md` | Master report structure |
| `assets/github-action-tripwire.yml` | Daily tripwire CI workflow: pass + diff + auto-issue on convergence break + Slack notify |
| `assets/github-action-pre-merge.yml` | Pre-merge PR gate: detects bead IDs in PR title/body and runs single-bead-audit per bead |
| `assets/pre-commit-hook.sh` | Local hook: detect newly-closed beads in staged JSONL diff and run quick single-bead audit before allowing the commit |
| `assets/audit-policy.yaml` | Customizable per-project policy: weights_by_type, weights_by_label, project_theater_patterns, release_gate, subagent enable/disable, phase_4_environment, attribution priors, parallelism caps. `threshold` and `remediation_policy` are auto-loaded by the wrapper scripts via `scripts/_load-policy.sh`; other fields are read directly by the owning subagent (the YAML's IMPLEMENTATION STATUS header lists which is which). |
| `assets/case-study-template.md` | Markdown skeleton for documenting a real audit pass — context, findings, lessons learned, reproducibility commands. Drop into your team's docs site or attach to a release. |
| `assets/grafana-dashboard.json` | Importable Grafana dashboard for the Prometheus textfile-collector metrics emitted by `scripts/metrics-export.sh` (false-closed count, score median, pass-age, convergence verdict, theater-by-severity timeseries). |
| `assets/polish-prompt.txt` | **Canonical text of the Phase 9.5 polish prompt.** Single source of truth; SKILL.md and `scripts/polish-remediation-beads.sh` MUST match it character-for-character (verified by `scripts/validate-polish-prompt-consistency.py`). Edit here first, then propagate. |
| `assets/rubric-templates/{security-heavy,perf-heavy,infra-heavy,docs-heavy}.md` | Pre-tuned `rubric.md` variants for projects whose bead-type mix differs from the default. Copy one to `<audit-dir>/rubric.md` and re-run `bootstrap-audit.sh` so the new sha256 is pinned. README in the dir explains when to use each. |
| `assets/fixtures/{README.md,known-good/,theater-only/}` | Synthetic test projects used by `scripts/regression-test.sh`. Each fixture: `seed.sh` (creates a real br project) + `EXPECTED.md` (`## Assertions` block parsed by `compare-to-expected.py`). Currently 2 fixtures shipped; library extends incrementally per the README. |

---

## Self-Test

Trigger phrases that should activate this skill:

- "Audit all our closed beads — did we actually finish them?"
- "I don't trust the bead status field — verify completion for every bead"
- "Run a beads compliance audit on this project"
- "Score every closed bead from 0 to 1000 on actual completion"
- "Find false-closed beads in /data/projects/frankensqlite"
- "Verify bead bd-abc123 was actually completed properly"
- "Re-verify the beads compliance audit — did the agents finish the remediation?"
- "Check whether the conformance harness in bead bd-foo actually runs"
- "Audit beads completion claims; report bead-by-bead with evidence"

Trigger phrases that should NOT activate this skill (route elsewhere):

- "Plan a new feature using beads" → `/beads-workflow`
- "What bead should I work on next?" → `/beads-bv`
- "The bead DB is corrupted, fix it" → `/fixing-beads-problems`
- "Find stubs and mocks in this codebase" → `/mock-code-finder`
- "Are we delivering on the README vision?" → `/reality-check-for-project`

Full self-test including a smoke test on a tiny repo: [SELF-TEST.md](SELF-TEST.md).
