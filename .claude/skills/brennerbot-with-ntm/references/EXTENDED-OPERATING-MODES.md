# EXTENDED-OPERATING-MODES.md — Niche / Advanced Operating Modes

<!-- TOC: When to use | Mode: academic-paper-replication | Mode: peer-review | Mode: hypothesis-pre-registration | Mode: meta-analysis | Mode: living-review | Mode: continuous-monitoring | Mode: red-team-only | Mode: corpus-update | Mode: post-mortem-formalization | Authoring new modes -->

OPERATING-MODES.md ships 6 core modes (`fresh-question`, `code-investigation`, `corpus-distillation`, `resume-session`, `methodology-drift-check`, `incident-investigation`). This file documents niche modes for unusual workflows. Each mode is a *configuration* of the same 10-phase loop with mode-specific exit criteria and required artifacts.

---

## When to use this catalog

Use one of these modes when the standard 6 modes don't capture the workflow. Don't invent ad-hoc modes; pick the closest documented one or extend the catalog.

---

## Mode: `academic-paper-replication`

**Use when:** verifying a published claim by independently re-running the experiment / re-deriving the conclusion / checking the mathematics.

**Phases run:** 1–9 (skip 10 unless replication is itself novel).

**Mode-specific Phase 1:**
- Question of record: "Does <PAPER>'s claim that <X> hold under independent replication?"
- Falsifier: "If our independent replication contradicts <X> by ≥<threshold>, the claim is not robust under our conditions."
- Corpus pinned to specific paper version (DOI + content-hash); all related supplementary materials.

**Mode-specific Phase 4:**
- Investigator must reproduce method end-to-end. If method requires resources we lack, escalate.
- Devil's-Advocate looks for replication-failure precedent (cass-mining recommended).

**Mode-specific Phase 6:**
- Distillation explicitly compares our finding to the paper's claim with deltas tabulated.

**Mode-specific Phase 9 form:** "Replication report" instead of HANDBACK.md:
- Reproduction successful / partial / failed
- Discrepancies catalog (with magnitudes)
- Methodology critique (where the paper's method was unclear)
- Recommended action (cite, cite with caveats, contact authors, retract reliance)

---

## Mode: `peer-review`

**Use when:** reviewing a manuscript / proposal / design document on behalf of someone else (academic peer review, design review, RFP evaluation).

**Phases run:** 1, 3 (compressed), 4 (focused on critique), 5 (debate compression), 7, 9.

**Mode-specific Phase 1:**
- Question of record: "Should this manuscript / proposal / design be accepted? What changes would make it accept-worthy?"
- Falsifier: "If a critical methodology flaw or load-bearing claim cannot be supported, recommend rejection."

**Mode-specific Phase 3:**
- Hypotheses are *evaluation criteria* not research claims (e.g., "the methodology is sound", "the conclusions follow from the data", "the literature review is complete").

**Mode-specific Phase 4:**
- Investigator role becomes "reviewer" — search the corpus (the manuscript) for support and counter-support of each evaluation criterion.
- Devil's-Advocate looks for what the manuscript downplays or omits.

**Mode-specific Phase 9 form:** "Review report":
- Recommendation (accept / accept-with-revisions / reject)
- Per-criterion evaluation with cited passages
- Specific change requests (line-numbered)
- Open questions for the authors

Suitable for academic peer review, design doc review, RFP evaluation, code review at high stakes.

---

## Mode: `hypothesis-pre-registration`

**Use when:** committing to a falsifier BEFORE running the investigation, to defend against post-hoc rationalization.

**Phases run:** 1, 3, then PAUSE; later phases run after data collection.

**Mode-specific Phase 1:**
- Question of record + falsifier are committed PUBLICLY (or to immutable storage).
- A pre-registration hash is computed and recorded in `intake/pre-registration.md` with timestamp.

**Mode-specific Phase 3:**
- Hypothesis slate locked with timestamp BEFORE Phase 4 begins.
- Any hypothesis added after the pre-registration is marked `origin:post-hoc` and treated with reduced weight.

**Phase 4 typically runs separately:**
- Data collection happens (could be days/weeks/months later).
- Resume the session via RESUME.md when data is available.

**Mode-specific Phase 9:**
- HANDBACK explicitly compares pre-registered vs post-registered hypotheses.
- Any deviation from pre-registered methodology is flagged.

**Anti-bias property:** the hash + timestamp at pre-registration prevents quietly editing the hypothesis after seeing data. Akin to scientific pre-registration norms.

---

## Mode: `meta-analysis`

**Use when:** synthesizing across multiple prior brennerbot sessions OR multiple external studies.

**Phases run:** all 10, with Phase 1 + 4 specialized.

**Mode-specific Phase 1:**
- Question of record: "What does the body of evidence across <N> prior studies / sessions say about <X>?"
- Corpus is the set of prior studies / sessions, content-hashed.

**Mode-specific Phase 4:**
- Investigators don't generate new evidence; they extract claims from each prior source and tabulate.
- The "evidence pack" per H is a meta-EV-pack: a table of `(source, claim, weight)` rather than verbatim quotes.

**Mode-specific Phase 6:**
- Distillation reports effect-size or claim-frequency across the corpus.
- Disagreement register catalogs the points of cross-study disagreement.

**Mode-specific Phase 9 form:** "Meta-analysis report":
- Pooled finding (with confidence interval if quantitative)
- Heterogeneity assessment (do studies agree?)
- Methodological quality grading per source
- Recommendations for primary vs derivative reliance

---

## Mode: `living-review`

**Use when:** maintaining an ongoing review of a fast-moving topic; the brennerbot session is intentionally re-run on a cadence (weekly, monthly).

**Phases run:** all 10, in a loop.

**Mode-specific Phase 1:**
- Question of record is stable (the topic doesn't change).
- Volatile-source caveat is mandatory (per VERIFICATION-FIRST.md).
- Initial framing notes which sources will be re-checked on each iteration.

**Mode-specific Phase 8 + Phase 10:**
- RESUME.md includes a `next_resume_due:` ISO timestamp.
- DRIFT-CHECK.md compares current iteration to prior iterations of the SAME living review.

**Mode-specific deliverable:** `deliverables/CURRENT-VIEW.md` (latest snapshot, replaces `HANDBACK.md`).

**Workflow:** operator schedules via `/loop` or `/schedule` if those slash tools are available, otherwise CronCreate or shell cron, to re-run on cadence.

Useful for: regulatory monitoring, competitive intelligence, ongoing benchmarking, weekly literature scans.

---

## Mode: `continuous-monitoring`

**Use when:** the question is "what's currently true about <X>?" and the answer changes faster than session wall time.

**Phases run:** continuous tick + periodic full passes.

**Mode-specific roster:** persistent ntm session that survives across phases. Operator runs ticks (per tick.sh) every 15-30 min.

**Mode-specific Phase 4:**
- Investigators run continuously on volatile sources.
- New EVs file in real time.
- Anomalies flag immediately.

**Mode-specific Phase 6:**
- Periodic re-distillations (e.g., daily) produce snapshots.

**Heaviest mode**; rare. Typically T4+ with significant infrastructure investment.

Use cases: monitoring an active production incident in long-form, ongoing security threat tracking, real-time market analysis.

---

## Mode: `red-team-only`

**Use when:** the artifact (system, design, methodology, paper) already exists; the question is "find every way it could fail."

**Phases run:** 1, 3 (compressed), 4 (Devil's-Advocate-heavy), 7 (red-team subagent), 9.

**Mode-specific roster:** pair of devil's-advocates + one synthesizer; no proposers/investigators in the standard sense.

**Mode-specific Phase 1:**
- Question of record: "Find every way <ARTIFACT> could fail." Falsifier: "If exhaustive search produces zero load-bearing weaknesses, the artifact is unusually robust (confirm via independent red team)."

**Mode-specific Phase 4:**
- Devil's-Advocates work in parallel, each on a different attack class (e.g., correctness, performance, security, scale, regulatory).
- `subagents/red-team.md` runs novel-attack search.

**Mode-specific Phase 9 form:** Threat catalog (per A6 archetype). Use `assets/templates/threat-catalog-template.md`.

Compatible with archetype A6.

---

## Mode: `corpus-update`

**Use when:** an existing brennerbot session needs new corpus added mid-session (e.g., a relevant new paper was published).

**Phases run:** 1 (compressed; corpus update only), then resume original phases.

**Mode-specific Phase 1:**
- Skip question framing (question of record unchanged).
- Run `MO-corpus-update.md` to ingest new sources, content-hash, assign anchors.
- Decide: do new sources warrant Phase 4 reopen on existing Hs?

If yes, resume Phase 4 with a `corpus_updated_at:` annotation. New EVs cite the new sources.

If no, document the decision and proceed.

---

## Mode: `post-mortem-formalization`

**Use when:** an incident has been resolved (perhaps via incident-investigation mode); now formalizing the post-mortem.

**Phases run:** all 10, but Phase 4 is largely retrospective.

**Mode-specific Phase 1:**
- Question of record: "What is the load-bearing root cause of <INCIDENT>, and what would prevent recurrence?"
- Corpus pinned to incident timeline + logs + comms.

**Mode-specific Phase 9 form:** Post-mortem report (5-whys structure):
- Timeline
- Root cause (with EV-cited evidence)
- Contributing factors
- Action items (with owners)
- Updates to runbook / monitoring / process

---

## Authoring new modes

When extending the catalog:

1. Document trigger phrasings (≥2)
2. Specify which phases run + which are compressed/skipped
3. Specify mode-specific Phase 1 framing
4. Specify mode-specific Phase 9 form (e.g., "report" vs "handback" vs "verdict")
5. Note which archetype(s) compose with this mode
6. Add to OPERATING-MODES.md mode-router-table

Don't add modes that are subtly different versions of an existing mode. Only add modes that have *distinct* exit criteria or required artifacts.
