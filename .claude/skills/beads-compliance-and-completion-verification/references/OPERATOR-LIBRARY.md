# OPERATOR-LIBRARY.md — Cognitive Moves For Verification

Adapted from [`/operationalizing-expertise`](../../operationalizing-expertise/SKILL.md) Track A. Each operator is a **named cognitive move** with explicit triggers, failure modes, and a paste-ready prompt module.

The phase loop in `PHASES.md` says *what* to do; this file says *how* a verifier thinks. Verification is reproducible only when the moves are named — otherwise auditor agents drift into vibes.

> **Composition rule.** Each phase has a recommended operator pipeline (the cheat-sheet at the bottom). Apply the operators *in order*; if an operator fails, do not skip — record the failure, then continue. Skipping operators is how phase outputs end up under-cited.

---

## Operator card format

```
NAME (glyph)
  Trigger:           when this move fires
  Inputs:            what you read
  Outputs:           what you write
  Failure modes:     how this move goes wrong
  Prompt module:     paste-ready prompt fragment
  Cite as:           how to reference this move in scorecard "why" lines
```

---

## ★ ENUMERATE — "name every checklist item literally"

```
Trigger:        Phase 2 spec extraction; any time you read a bead body.
Inputs:         show.json (description, design, acceptance_criteria, notes).
Outputs:        spec.json#checklist with one item per literal requirement.
Failure modes:  Paraphrasing AC bullets; inventing implicit items the bead
                didn't state; missing duration/count/percentage thresholds
                buried in prose.
Prompt module:
  > Read the bead body (description + design + acceptance_criteria + notes).
  > For EVERY bullet, EVERY "must include", EVERY explicit duration, count,
  > or percentage — emit a checklist item with `verbatim` field that quotes
  > the source text. Do NOT paraphrase. Do NOT invent items not stated.
Cite as:        "spec.json#<item-id> (verbatim from bead body)"
```

## ✦ EXECUTE — "actually run the proof"

```
Trigger:        Phase 4 compliance; never trust self-reported "tests pass".
Inputs:         evidence.json#citations + the project test runner.
Outputs:        compliance.json with raw stdout/stderr/exit-code per check.
Failure modes:  Reading prior CI logs instead of re-running; allowing tests
                that exit 0 with zero assertions to count as PASS; running
                with --release when bead spec assumed debug; stale checkout.
Prompt module:
  > Re-run the proof. Capture stdout, stderr, exit code, duration. Cap each
  > test command at ~10× its stated budget; record TIMEOUT cleanly when
  > exceeded. NEVER reuse prior pass outputs. NEVER mark UNVERIFIED_INFRA
  > as PASS because the service "would have worked".
Cite as:        "compliance.json#<spec-item> verdict=<X> exit=<N> raw=<path>"
```

## ⚖ MEAN — "does the artifact mean what it claims?"

```
Trigger:        Phase 5 anti-theater; any "PASS" verdict from Phase 4.
Inputs:         evidence files cited in evidence.json.
Outputs:        theater.json findings with severity + invalidates_phase4_check.
Failure modes:  Flagging legitimate `pass` in Python protocols; missing
                tests-in-test-mode short-circuits; ignoring sleep() in
                production paths; treating MAJOR as BLOCKING (or vice versa).
Prompt module:
  > Apply /mock-code-finder to every file in evidence.json#citations (NOT
  > the whole project). For each match: classify severity per RUBRIC.md §3,
  > and if it invalidates a Phase 4 check, set `invalidates_phase4_check`.
Cite as:        "theater.json#<finding-id> [<severity>] <path>:<line>"
```

## ◐ MEASURE — "does it cover the surface?"

```
Trigger:        Phase 6 test depth; any test-type required by spec.
Inputs:         compliance.json + project coverage tool + fuzzer/golden state.
Outputs:        test_depth.json with PASS/PARTIAL/FAIL/WAIVED per check.
Failure modes:  Reporting project-global coverage instead of bead-scoped;
                counting fuzz-target-compiles as fuzz PASS; treating golden
                "exists" as golden "fresh"; missing branch coverage.
Prompt module:
  > Coverage MUST be scoped to the bead's files (filter the coverage tool
  > by paths in evidence.json#code_artifacts). Project-global numbers are
  > meaningless for per-bead scoring. For fuzz: corpus_size>0 AND ran for
  > stated duration AND no crashes. For goldens: regenerate + diff.
Cite as:        "test_depth.json#<check> verdict=<X> value=<N> threshold=<M>"
```

## ⊕ INTEGRATE — "do the pieces fit?"

```
Trigger:        Phase 7 cross-bead synthesis; whenever bead A references B.
Inputs:         every spec.json + every evidence.json + dag.json.
Outputs:        synthesis.md with integration gaps, contract drift, orphans.
Failure modes:  Treating unrelated beads as integrated; missing transitive
                contracts (A→B→C); ignoring shared invariants; failing to
                cite specific bead pairs.
Prompt module:
  > Walk the bead DAG. For each producer→consumer edge, compare the
  > producer's evidence.json#code_artifacts.citations against the consumer's
  > spec.json#code_artifacts.expected_path_hints AND any AC bullets that
  > reference the producer. Record contract drifts with EXACT shape
  > differences (e.g., "B emits {user_id} but A parses {userId}").
Cite as:        "synthesis.md#integration-gaps bd-A↔bd-B"
```

## ⚑ CONTRACT — "does this bead break a sibling?"

```
Trigger:        Phase 6→7 boundary; any change-by-this-bead that touches a
                shared module.
Inputs:         git log of the bead's commits + dependents from dag.json.
Outputs:        synthesis.md#contradictions or scorecard cross-bead penalty.
Failure modes:  Missing implicit contracts (constants, error codes, schema
                column names); accepting "tests pass" as proof that
                downstream still works.
Prompt module:
  > For each downstream bead, check that its spec.json's expectations of
  > the upstream still hold given the upstream's current evidence. If any
  > expectation is now invalid, record a contradiction.
Cite as:        "synthesis.md#contradictions bd-X claims P; bd-Y assumed ¬P"
```

## ⊙ DE-SLOP — "strip auto-generated padding from artifacts"

```
Trigger:        Phase 8 scorecard authoring; any markdown output.
Inputs:         draft scorecard.md.
Outputs:        scorecard with no slop ("comprehensive", "robust", "clean
                solution"), only citations.
Failure modes:  Generating prose to fill the "why" column; padding the
                executive summary with hedging; turning citations into
                paragraphs.
Prompt module:
  > Apply /de-slopify. Every dimension's "why" line must be ≤ 1 sentence
  > AND end with a file:line citation. No hedging adjectives. No
  > "comprehensive" / "robust" / "extensive" / "thorough" without numeric
  > backing.
Cite as:        N/A (this is a polish move, not an evidence move)
```

## ⌂ CONSEQUENCE — "what happens if this bead is missing?"

```
Trigger:        Triage mode (when scoring all 1000 beads is too expensive);
                Phase 9 priority bumping for severe theater.
Inputs:         dag.json + spec.json + downstream blocked work.
Outputs:        Priority adjustment in remediation.md.
Failure modes:  Treating high-PageRank beads as automatically high-impact
                (they may be done correctly); ignoring beads that have no
                downstream deps but are user-facing.
Prompt module:
  > If this bead is fictional, what user-visible / production-visible
  > behavior is broken or absent? If the answer is "nothing" → low
  > consequence; if "user-facing primary path" → critical consequence.
Cite as:        "scorecard.md#consequence: <user-visible behavior>"
```

## ⤵ DECOMPOSE — "split a large bead into auditable pieces"

```
Used in:        Phase 2 (spec extraction; epic / large-bead splitting).
Trigger:        Spec extraction on an epic / >1000-line bead body.
Inputs:         show.json with sprawling description.
Outputs:        spec.json with checklist items grouped by sub-deliverable.
Failure modes:  Producing a single mega-checklist item; failing to attach
                weights to differentiate big-ticket from minor items.
Prompt module:
  > If the bead's body has >5 logical chunks (sub-features, sub-systems,
  > rollout phases), produce one checklist item per chunk with explicit
  > weights summing to 100. Use `parent_chunk` field to record grouping.
Cite as:        "spec.json#chunk.<name>"
```

## ⊞ TRIANGULATE — "second-model audit of the scoring"

```
Trigger:        Phase 10 fresh-eyes spot-check; high-stakes audits.
Inputs:         scorecard.md + evidence pack.
Outputs:        convergence.json#criteria.rubric_consistency_pass and a list
                of deviations.
Failure modes:  Same-model triangulation (you'll get the same blind spots);
                comparing only one dimension; ignoring the rubric in favor
                of vibes.
Prompt module:
  > Use /multi-model-triangulation. Spawn a Codex AND Gemini agent reading
  > the same evidence pack with rubric.md. Each independently derives the
  > 6 dimension scores. Compare to the scorer's. Flag any dimension where
  > triangulated agents disagree by > 50 points.
Cite as:        "convergence.json#triangulation: <model> derived <X>; scorer <Y>"
```

## ⌘ REDUCE — "compress the report without losing evidence"

```
Used in:        Phase 8 (master report generation, trends.md aggregation).
Trigger:        Master report generation; trends.md updates.
Inputs:         many per-bead scorecards.
Outputs:        REPORT.md exec summary that fits in one Slack message.
Failure modes:  Dropping the false-closed list; aggregating P0 with P4;
                losing the ranked scoreboard.
Prompt module:
  > The exec summary is paste-ready: 5–7 bullets, numeric, name the worst
  > offender + best in class + score median. Do NOT replace the false-
  > closed list with a count — the list is the headline.
Cite as:        N/A (presentational)
```

## ⊘ SELF-POLICE — "audit the audit itself"

```
Trigger:        Phase 10 fresh-eyes review.
Inputs:         the entire pass dir.
Outputs:        convergence.json#criteria.generosity_flags.
Failure modes:  Trusting that the scorer applied the rubric uniformly;
                missing whole bead-types that were skipped; spot-checking
                only "safe" looking beads.
Prompt module:
  > Sample 5 random beads (use `shuf -n 5`). For each, re-derive the score
  > from the evidence WITHOUT looking at the scorer's output first. Then
  > compare. Deviations > 50 points → rubric inconsistency. Also: scan all
  > scorecards for "n/a" usage; if used > 30% of the time on a single
  > dimension, the rubric weights need revisiting.
Cite as:        "convergence.json#criteria.generosity_flags[i]"
```

## ⟳ REPEAT-UNTIL-QUIET — "iterate phases 4-6 until findings stabilize"

```
Trigger:        Phases 4/5/6 sometimes find each other's gaps. Phase 7
                routinely changes the dimension-6 score. Run an inner loop.
Inputs:         per-bead artifacts after one pass through 4-6.
Outputs:        same artifacts, stabilized.
Failure modes:  Infinite loops if convergence delta is too tight; missing
                that Phase 4 results changed because Phase 5 redrew the
                evidence boundary.
Prompt module:
  > Re-run Phase 4 → 5 → 6 for the bead. If theater.json changed,
  > re-run Phase 4 (since some PASS verdicts may now be invalidated).
  > Stop when two consecutive iterations produce no new findings.
Cite as:        N/A (presentational)
```

## ☖ STAKE-RUBRIC — "freeze the rubric mid-pass"

```
Used in:        Phase 0.5 (bootstrap-time rubric pinning) and Phase 8/10
                (anywhere the rubric is referenced after pass start).
Trigger:        Mid-pass realization that the rubric needs tuning.
Inputs:         current rubric.md and proposed change.
Outputs:        Either: stake the change for next pass (preferred) OR
                bump rubric_version, document, and re-score everything.
Failure modes:  Tuning mid-pass without bumping rubric_version (corrupts
                convergence-check); re-scoring some but not all beads.
Prompt module:
  > Do NOT modify rubric.md mid-pass. If a tuning is needed, log it in
  > rubric.md#tunings table for the NEXT pass. Mid-pass tuning corrupts
  > the convergence delta for every bead.
Cite as:        "rubric.md#tunings <date> <field> <old>→<new>"
```

## ☍ DISCLAIMER-WINDOW — "give the closer one chance to defend"

```
Trigger:        Severe-theater finding (score < 250) where the closer is
                still active.
Inputs:         scorecard with theater findings.
Outputs:        Optional /agent-mail thread to the closer summarizing the
                gap before Phase 9 reopens.
Failure modes:  Treating this as required (it's optional politeness, not
                policy); waiting indefinitely for a response.
Prompt module:
  > Optional: post a one-paragraph note to the bead's `closed_by_session`
  > via /agent-mail, summarizing the audit finding and asking if there's
  > a fix in flight. If no response within 24h, proceed with Phase 9.
Cite as:        "remediation.md#disclaimer: notified <closer> at <UTC>"
```

---

## § ANCHOR — "every score has a citation"

```
Trigger:        Phase 8 — every dimension score line in scorecard.md.
Inputs:         scorecard draft.
Outputs:        scorecard with file:line / commit-SHA / test-name / raw-log
                anchor for every numeric claim.
Failure modes:  "Looks bad" without citation; aggregate "see evidence" rather
                than concrete pointer; missing raw log path for executed
                checks.
Prompt module:
  > Every dimension's "why" line MUST end with at least one of:
  >   - file:line  (`src/parser.rs:312`)
  >   - commit SHA (`def5678abc`)
  >   - test name  (`test_parser_handles_empty`)
  >   - raw path   (`raw/tests_unit.stdout`)
  >   - artifact   (`evidence.json#code.parser`, `theater.json#finding.4`)
  > A scorecard with no anchors is invalid; reject and re-derive.
Cite as:        N/A — this is the discipline FOR citations
```

## ⊿ DISCRIMINATE — "PASS vs PASS-with-theater are different"

```
Trigger:        Phase 5 cross-references with Phase 4.
Inputs:         compliance.json#PASS verdicts + theater.json#findings.
Outputs:        theater.json findings with `invalidates_phase4_check` field.
Failure modes:  Treating exit-0 as proof; missing the impl-short-circuits
                pattern that makes a test PASS without exercising real code.
Prompt module:
  > For every PASS verdict in compliance.json, ask: did the test exercise
  > the production code path, or did it short-circuit through a stub /
  > hardcoded return / cfg(test) guard? If the latter, set
  > `invalidates_phase4_check: <spec_item_id>` on the BLOCKING finding.
Cite as:        "theater.json#<finding> invalidates compliance.json#<check>"
```

## ⌖ TARGET — "pick the highest-impact bead to remediate first"

```
Trigger:        Phase 9 priority assignment.
Inputs:         All false-closed scorecards + DAG + PageRank.
Outputs:        Ordered remediation list (priority_score per
                REMEDIATION-PRIORITIZATION.md).
Failure modes:  Sorting by score alone (misses graph centrality); sorting
                by priority alone (misses score severity); ignoring
                consequence weighting.
Prompt module:
  > For each false-closed bead, compute:
  >   priority_score = (1000 - score) × consequence_multiplier ×
  >                    downstream_blockers + p0_p1_bonus
  > Sort descending. Surface top 5 in REPORT.md exec summary.
Cite as:        "remediation.md#priority_score <bead> = <value>"
```

## ↻ RETRY — "ambiguous finding → escalate to triangulation"

```
Trigger:        Phase 5 BLOCKING finding the auditor isn't sure about.
Inputs:         Theater finding under review.
Outputs:        Either (a) confirmed BLOCKING, OR (b) demoted MAJOR with
                triangulation note, OR (c) waived NOTE.
Failure modes:  Auto-demoting BLOCKING to MAJOR without justification;
                refusing to escalate when ambiguity is real.
Prompt module:
  > If the BLOCKING classification is ambiguous (e.g., is `pass` in this
  > Python method protocol-required or theater?), spawn a triangulation
  > query: a Codex / Gemini agent reads the same file with the spec.json
  > context and independently classifies. If both models concur with the
  > original, BLOCKING. If both disagree, demote with note. If split, keep
  > BLOCKING + flag for fresh-eyes Phase 10.
Cite as:        "theater.json#<finding>.triangulation: <verdict>"
```

## ⌀ ZERO — "when uncertain, score conservative"

```
Used in:        Phase 4 (compliance), Phase 5 (theater), Phase 6 (test
                depth), Phase 8 (scoring) — anywhere evidence is partial.
Trigger:        Any phase where evidence is incomplete.
Inputs:         Partial / ambiguous evidence pack.
Outputs:        Score reflecting the uncertainty (lower, not higher).
Failure modes:  "Benefit of the doubt" generosity; assuming success when
                the test runner couldn't be reached.
Prompt module:
  > When uncertain (test runner crashed, coverage tool unavailable,
  > evidence file disappeared mid-pass), score CONSERVATIVE. The
  > false-positive cost (minor) is much lower than the false-negative
  > cost (silently letting a bad bead pass).
Cite as:        "Conservative scoring: <verdict> due to <uncertainty source>"
```

## ⊠ PIN — "marker-bound parsable sections"

```
Trigger:        Phase 8 scorecard authoring; rubric versioning; kernel
                axioms.
Inputs:         Section content.
Outputs:        Section delimited by `<!-- NAME_START vM.N -->` ...
                `<!-- NAME_END vM.N -->` markers so it's mechanically
                extractable.
Failure modes:  Free-form prose where parsable structure is needed; loose
                section boundaries that break extract scripts.
Prompt module:
  > For sections that downstream tools must parse (verification kernel,
  > rubric body, scorecard dimension scores), bracket with marker
  > comments. The version suffix (vM.N) lets readers detect format drift.
Cite as:        "<NAME_START vM.N> ... <NAME_END vM.N>"
```

## ⟴ AMORTIZE — "cache evidence packs; only re-verify what changed"

```
Used in:        Phase 1 (inventory), Phase 2 (spec extract), Phase 3
                (evidence) — cross-pass reuse decisions.
Trigger:        Re-verification mode (mode=re-verification); large bead
                universes.
Inputs:         Prior pass's evidence pack + git diff between prior and
                current pass.
Outputs:        Decision per bead: re-run all phases (changed) OR copy
                forward (unchanged).
Failure modes:  Re-running everything every pass (wasteful); copying
                forward when files changed (stale evidence).
Prompt module:
  > For each bead, compute: did any cited file change since prior pass?
  >   git diff <prior-sha>..HEAD -- <evidence files>
  > If unchanged AND prior verdict was PASS → copy forward.
  > If changed OR prior was FAIL → re-run Phases 3-6.
  > Mark provenance in compliance.json#provenance: cached|fresh.
Cite as:        "compliance.json#provenance: cached from passes/<prior>"
```

## ⊳ DELEGATE — "hand off to a specialized skill when bead matches"

```
Trigger:        Bead spec mentions a specialized domain.
Inputs:         spec.json with domain markers.
Outputs:        Phase 4/6 verdicts that defer to the specialized skill.
Failure modes:  Re-implementing the specialized skill's logic inline;
                ignoring the skill's depth criteria.
Prompt module:
  > If the bead's spec mentions:
  >   - "fuzzer", "fuzz", "AFL", "libFuzzer" → delegate to /testing-fuzzing
  >   - "conformance", "RFC", "spec-compliance" → /testing-conformance-harnesses
  >   - "golden", "snapshot", "insta" → /testing-golden-artifacts
  >   - "metamorphic", "MR", "oracle-free" → /testing-metamorphic
  >   - "real services", "no mocks", "Stripe sandbox" → /testing-real-service-e2e-no-mocks
  >   - "performance", "benchmark", "p95" → /profiling-software-performance
  >   - "security", "CVE", "CWE" → /security-audit-for-saas
  >   - "deadlock", "race", "concurrency" → /deadlock-finder-and-fixer
  > The specialized skill's verdict folds into the audit's compliance.json
  > with `delegated_to: <skill>` field.
Cite as:        "compliance.json#delegated_to: /testing-fuzzing#verdict=PASS"
```

## ⌥ ROLLBACK-PROOF — "migrations and infra need reverse + idempotency"

```
Used in:        Phase 4 (compliance verifier — migration / infra recipe).
Trigger:        Bead with type=chore touching schema / infra / migrations.
Inputs:         Migration file or terraform / CDK config.
Outputs:        compliance.json verdict per BEAD-TYPE-PLAYBOOKS.md
                migration / infra recipe.
Failure modes:  Treating "forward applies" as proof of done; ignoring
                rollback path; missing idempotency check.
Prompt module:
  > For migration / infra beads, verify:
  >   1. Forward applies to fresh state.
  >   2. Reverse applies to post-forward state cleanly.
  >   3. Forward applied twice is a no-op (idempotency).
  >   4. Rollback path is documented.
  > Each is a separate compliance.json check; missing any is FAIL.
Cite as:        "compliance.json#migration.{forward,reverse,idempotent}: PASS"
```

## ⊡ FRAME — "context the bead lives in"

```
Trigger:        Phase 2 spec extraction on a bead that references project
                context (existing modules, AGENTS.md conventions, sibling
                beads' patterns).
Inputs:         Bead body + project's AGENTS.md + sibling beads' specs.
Outputs:        spec.json#context with notes on conventions the bead
                inherits.
Failure modes:  Treating bead in isolation; missing AGENTS.md "always do X"
                rules that bind every bead in the project.
Prompt module:
  > Read the project's AGENTS.md / CLAUDE.md / README.md for project-wide
  > conventions ("always run UBS before commit", "no mocks ever",
  > "always populate `closed_by_session`"). Add any that apply to THIS
  > bead's spec as implicit constraints.
Cite as:        "spec.json#context.inherited_from_AGENTS.md"
```

## ⌬ HARMONIZE — "merge per-domain syntheses into the meta-synthesis"

```
Trigger:        Phase 7 on large bead universes (>200 beads); per-domain
                syntheses produced separately.
Inputs:         per-domain synthesis*.md files.
Outputs:        Single synthesis.md with cross-domain findings.
Failure modes:  Concatenating syntheses (loses cross-domain integration);
                missing the cross-domain orphans (an AC in domain A
                delegates to domain B's bead).
Prompt module:
  > Each per-domain synthesis covers within-domain integration. The
  > meta-synthesis additionally walks cross-domain bead references —
  > does an AC in domain A's bead reference a bead in domain B? Are those
  > cross-domain promises kept?
Cite as:        "synthesis.md#cross-domain: <domain-A>↔<domain-B>"
```

---

## Operator pipelines per phase

| Phase | Pipeline (apply in order) |
|------:|---------------------------|
| 2 | ★ ENUMERATE → ⤵ DECOMPOSE (if epic) → ⊡ FRAME |
| 3 | (no ops — read-only lookups; the "operator" is git-grep + ripgrep) → ⟴ AMORTIZE (if re-verification mode) |
| 4 | ✦ EXECUTE → ⊳ DELEGATE (if specialized) → ⌥ ROLLBACK-PROOF (if migration) → (if PASS) ⊿ DISCRIMINATE |
| 5 | ⚖ MEAN → ↻ RETRY (on ambiguous BLOCKING) → ⌀ ZERO (on uncertainty) |
| 6 | ◐ MEASURE → ⌀ ZERO (on tool unavailability) |
| 7 | ⊕ INTEGRATE → ⚑ CONTRACT → ⌬ HARMONIZE (if multi-domain) |
| 8 | (apply RUBRIC.md mechanically) → § ANCHOR → ⊙ DE-SLOP → ⌘ REDUCE → ⊠ PIN |
| 9 | ⌂ CONSEQUENCE → ⌖ TARGET (priority) → ☍ DISCLAIMER-WINDOW (optional) |
| 10 | ⊘ SELF-POLICE → ⊞ TRIANGULATE (high-stakes) → ☖ STAKE-RUBRIC (if rubric drift) |

All phases respect ⟳ REPEAT-UNTIL-QUIET when an inner loop is needed.

---

## Operator failure → Phase 8 dock map

When an operator's *failure mode* is observed in a bead's artifacts, the scorer dings the corresponding rubric dimension:

| Failed operator | Dings dimension | Severity |
|-----------------|----------------:|----------|
| ★ ENUMERATE incomplete (paraphrased AC) | 1 (impl) | -10% per missed AC |
| ✦ EXECUTE skipped (verdict from prior pass) | all | invalid pass; redo |
| ⚖ MEAN missed (BLOCKING theater not flagged) | 3 (anti-theater) | full dock |
| ◐ MEASURE wrong scope (project-global coverage) | 4 (depth) | full dock |
| ⊕ INTEGRATE missed (contract drift) | 6 (cross-bead) | -25 per gap |
| § ANCHOR missed (score without citation) | invalid scorecard | reject; re-score |
| ⊿ DISCRIMINATE missed (PASS-with-theater not invalidated) | 2 (tests) | full dock |
| ⌖ TARGET wrong order (low-impact remediated first) | none | exec summary noise |
| ↻ RETRY skipped (ambiguous BLOCKING auto-demoted) | 3 (anti-theater) | re-classify |
| ⌀ ZERO skipped (generosity bias on uncertainty) | varies | Phase 10 flag |
| ⊠ PIN missed (free-form sections not parsable) | none | downstream tool breaks |
| ⟴ AMORTIZE wrong (cached when files changed) | varies | stale evidence — re-run |
| ⊳ DELEGATE skipped (specialized depth not invoked) | 4 (depth) | partial dock |
| ⌥ ROLLBACK-PROOF skipped (migration without reverse) | 1 (impl) | -50% |
| ⊡ FRAME missed (project conventions ignored) | 1 (impl) | -10% per ignored convention |
| ⌬ HARMONIZE missed (cross-domain orphans uncaught) | 6 (cross-bead) | -25 per orphan |
| ⊙ DE-SLOP missed (slop in scorecard) | none | Phase 10 flag |
| ⊞ TRIANGULATE missed | none | Phase 10 flag |

---

## Why we name the moves

> The cognitive move is what the agent *does*; the rubric is what the result *means*; the artifact is what the score *cites*. Three different things. Conflating them is the most common audit-of-the-audit failure.

When a scorecard says "Dimension 3 docked because TODO at src/x.rs:42", the chain is:
- Operator: `⚖ MEAN`
- Rubric: §3 MINOR penalty
- Artifact: `theater.json#finding.4`

Future auditors can replay the chain. Vibes-based "this looks bad" cannot be replayed.

---

## ✱ ADVERSARIAL — "construct attacks against the rubric before they're real"

  Trigger:    Comprehensive mode; after rubric tightening; quarterly hygiene; pre-release.
  Inputs:     Current rubric.md + scripts/theater-scan.sh + scripts/anomaly-scan.sh + recent passes.
  Outputs:    audit_resilience.json (attempted attacks, those that succeed, patch recommendations + fixtures).
  Failure modes:
    - Generating implausible attacks (zero-day in test runners). Bar = "cheap and would pass current rubric."
    - Reporting every theoretical gap as a real attack. Filter to the ones that PASS today.
    - Producing patches without fixtures (regression risk for the patch itself).
  Phase:      Phase 10 (post-pass), opt-in for Comprehensive mode.
  Prompt module:

    ```
    For each rubric dimension, name the cheapest attack that maxes the
    dimension while shipping actual theater. Score each attack against the
    current rubric. For successful attacks, propose a patch (rubric/script
    change) AND construct a fixture under fixtures/<RA-id>/ so the patch
    has a regression test.
    ```

  Cite as:    audit_resilience.json#attacks[id].rubric_patch

---

## ⊟ BISECT — "git-bisect a regression to a single commit"

  Trigger:    A bead's score regressed pass-over-pass by ≥ 100 points; OR PASS → FALSE-CLOSED across
              two consecutive passes with no remediation between them.
  Inputs:     <audit-dir>/passes/<UTC>/manifest.json#project_sha (good + bad endpoints).
  Outputs:    <audit-dir>/bisect/<bead-id>/{bisect_log.txt, predicate.log, run_<sha>/}.
  Failure modes:
    - Auto-detection fails (manifest didn't record project_sha). Pass --good / --bad explicitly.
    - Predicate flakes; mark as `skip` not `bad` (bisect-regression.sh handles this).
    - Bisecting a regression caused by rubric change, not code change. Check
      convergence.json#rubric_changed_since_prior_pass FIRST.
    - Worktree leaked (cleanup trap not fired). Verify /tmp/<basename>__bisect_* gone.
  Phase:      Post-Phase 10 (after a pass-over-pass regression is detected).
  Prompt module:

    ```
    Locate GOOD and BAD SHAs from passes/*/manifest.json. Run
    bisect-regression.sh in a dedicated worktree (NEVER touch the project's
    main working tree). Predicate is single-bead-audit.sh exit 0 (good) / 2
    (bad) / other (skip). Output offending commit + diff summary.
    ```

  Cite as:    bisect/<bead-id>/bisect_log.txt + the offending commit SHA

---

## ⊧ PROVENANCE — "every artifact citation traces to source"

  Trigger:    Phase 8 scoring; Phase 7 synthesis; any time the audit verdict will be cited externally
              (regulator, customer, exec, post-mortem).
  Inputs:     scorecard.md citations + commit_sha + tool versions in manifest.json.
  Outputs:    Provenance chain readable in 3 hops (score → evidence → source code).
  Failure modes:
    - Citations without commit SHA. The line could have moved or been deleted.
    - Citations to ranges that don't exist at the recorded SHA. `git show <sha>:<path>` test.
    - Storing evidence in CI artifacts that expire. Use the audit dir + git, not GH Actions artifacts.
    - Reusing UTC timestamps as primary keys (collision risk). Add nanos OR content hash.
  Phase:      Phase 8 (scoring) + Phase 7 (synthesis); always-on for high-stakes audits.
  Prompt module:

    ```
    For every score dock, cite path:line_range AND commit_sha. Phase 8
    scorecard must be reproducible by the formula: open scorecard → click
    citation → arrive at exact line in git-show output. Three hops, every
    time.
    ```

  Cite as:    scorecard.md path:line + (commit_sha) + manifest.json#tool_versions

---

## ⌗ ATTRIBUTION — "stratify rates per closer; calibrate priors"

  Trigger:    Phase 7 (post-synthesis); cross-pass when rolling false-closed rate per agent stabilizes.
  Inputs:     Every bead's closed_by + closed_at + final score.
  Outputs:    attribution.json with rolling false-closed rate per agent (with 95% CI), pattern fingerprint.
  Failure modes:
    - Single-pass judgments. < 30 closes per agent = noise. Need ≥ 30 + ≥ 3 passes.
    - Comparing agents across bead-types without normalization. Migration beads false-close more
      often than docs beads regardless of who closes them.
    - Treating the per-agent rate as causal. It's correlation; selection effects matter.
    - Public per-agent leaderboards. Demoralizes; use privately for coaching.
  Phase:      Phase 7 (post-synthesis); cross-pass when N closes per agent ≥ 30.
  Prompt module:

    ```
    For each agent who has closed ≥ 30 beads in the last 90 days, compute
    false-closed rate + 95% CI + pattern fingerprint (which theater patterns
    triggered most). Surface per-agent score-distribution violins in the
    dashboard. Calibrate next-pass priors per audit-policy.yaml#attribution
    rules.
    ```

  Cite as:    attribution.json#agents[id]

---

## ⊻ COMMITTEE — "combine N model verdicts per bead-type rules"

  Trigger:    Comprehensive mode; pre-release; SOC2/HIPAA evidence pack; security-flagged bead requiring
              zero false-negatives.
  Inputs:     Phase 4 raw outputs + N independent model sessions (Anthropic + Gemini + GPT recommended).
  Outputs:    committee.json with per-bead disagreements + final verdict (per combination rules).
  Failure modes:
    - Same-vendor committee. Three Anthropic models share training-data bias. Cross-vendor required.
    - Cross-loading models with shared context. Each member must be a separate session.
    - Treating committee as voting democracy. Security beads = any-failure-wins, not majority.
    - Letting context-asymmetry bias the result (one member with longer context "speaks louder").
      Cap each member at the same token budget per Phase.
  Phase:      Phase 4, Phase 5, Phase 7, Phase 10 (high-stakes opt-in).
  Prompt module:

    ```
    For Phase 4/5/7/10, fan out across N members in parallel sessions.
    Combine per audit-policy.yaml#committee rules: any-failure-wins for
    security/migration; majority for feature/bug; intersection for
    synthesis; tagged-by-detector-count for theater findings. Phase 10
    disagreement rate ≥ 30% → flag rubric ambiguity.
    ```

  Cite as:    committee.json#phase_4_disagreements[bead] + members[]
