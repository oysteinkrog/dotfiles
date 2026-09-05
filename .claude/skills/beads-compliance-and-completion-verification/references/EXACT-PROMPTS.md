# EXACT-PROMPTS.md — Verbatim Prompts For Each Phase / Subagent

Frozen templates. Copy-paste verbatim — the wording has been calibrated. Variables in `<ANGLE_BRACKETS>`.

---

## Phase 1 — Inventory & sanity check (main agent)

```
First, verify the bead store is healthy. Run:

  br doctor --json > <AUDIT_DIR>/passes/<PASS>/doctor.json
  br dep cycles --json > <AUDIT_DIR>/passes/<PASS>/cycles.json

If `br doctor` exits non-zero OR cycles.json is non-empty, STOP and hand off to /fixing-beads-problems. Do not proceed.

Once doctor is clean, enumerate every bead in the project (open, in_progress, blocked, deferred, draft, AND CLOSED) with full payload:

  br list --json > <AUDIT_DIR>/passes/<PASS>/inventory.jsonl
  for each bead id: br show <id> --format json > <AUDIT_DIR>/passes/<PASS>/beads/<id>/show.json

For every closed bead, cross-reference git history:

  git -C <PROJECT> log --all --grep=<bead-id> --format='%H%x09%s' > <AUDIT_DIR>/passes/<PASS>/beads/<id>/git_xref.txt

Then print to the user a count breakdown by status and type, and confirm it matches their expectation before proceeding.
```

---

## Phase 2 — Spec extraction (subagents/bead-spec-extractor.md, one per bead)

```
You are the bead-spec-extractor for bead <BEAD_ID>.

Read the full bead payload from <AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/show.json. Pay particular attention to these fields:

- description
- design
- acceptance_criteria
- notes

Produce <AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/spec.json conforming to the schema in references/EVIDENCE-SCHEMAS.md.

Be EXTREMELY LITERAL. Every bullet, every "must include," every test type explicitly named, every duration, every count threshold becomes its own checklist item. Quote source text in `source_quote` fields — do not paraphrase.

Add implicit requirements based on bead_type using the rules in references/BEAD-TYPE-WEIGHTS.md:
  - feature → at least one happy-path test
  - bug → a regression test in the closing diff
  - epic → every child bead must be closed and pass-grade
  - docs → the doc file must exist and be reachable

Constraints to extract from bead body verbatim:
  - "no mocks" → constraints.no_mocks: true
  - "must hit real <X>" → constraints.allowed_mocks excludes X
  - "<N>% coverage" → constraints.coverage_minimum_line: N/100
  - performance budgets, timeouts, durations

If the bead body is too thin to verify (no acceptance_criteria, vague description), record `coverage_gaps: ["bead body too thin to verify"]` — do NOT invent requirements that weren't there. The Phase 8 scorer will dock the bead-quality dimension.

Output spec.json. Do not modify any other file.
```

---

## Phase 3 — Evidence gathering (subagents/evidence-gatherer.md, one per bead)

```
You are the evidence-gatherer for bead <BEAD_ID>.

Read <AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/spec.json. For each checklist item, locate the actual artifact in <PROJECT> that purports to fulfill it.

Use these tools, in order of preference:
  1. git log --all --grep=<BEAD_ID> --name-only  → commits + files touched for this bead
  2. git -C <PROJECT> blame on those files → who last touched the cited lines
  3. ripgrep / ast-grep over expected_path_hints from spec.json
  4. gh pr list --search "<BEAD_ID>" if the bead has external_ref to a PR
  5. .github/workflows/ for any CI-workflow checklist items
  6. Search docs/ + README.md for documentation items

For each spec item, write a record to <AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/evidence.json with status FOUND | MISSING | AMBIGUOUS. Every FOUND must have at least one citation with path, line range, and (if known) commit SHA.

Do not execute any code. Do not modify any project file. You are read-only.

If you cannot find a spec item, mark MISSING with a brief explanation of what you searched for and where. AMBIGUOUS is allowed when multiple candidates exist; Phase 4 will disambiguate by execution.

Output evidence.json. Conform to the schema in references/EVIDENCE-SCHEMAS.md.
```

---

## Phase 4 — Compliance verification (subagents/compliance-verifier.md, one per bead)

```
You are the compliance-verifier for bead <BEAD_ID>.

Read <AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/{spec,evidence}.json. For every spec item that Phase 3 marked FOUND or AMBIGUOUS, ACTUALLY RE-RUN THE PROOF.

CRITICAL: Never trust a self-reported "tests pass." A test runner exit code of 0 means nothing if you didn't run it yourself in this audit. Capture stdout, stderr, exit code, and duration for every command.

For each test type:
  - unit/integration: run the project's test runner (cargo test / pytest / vitest / go test) on the specific test names cited in evidence.json
  - e2e: per /testing-real-service-e2e-no-mocks, hit real services with structured logging
  - fuzz: run the harness for the bead's stated duration (e.g., `cargo fuzz run target -- -max_total_time=60`); confirm crashes_found == 0 and corpus_size > 0
  - property: run with stated minimum iteration count
  - metamorphic: run the metamorphic relations cited in the bead per /testing-metamorphic
  - golden: regenerate goldens and `git diff --exit-code`; clean diff or documented intentional diff is PASS
  - conformance: run the conformance harness against the reference per /testing-conformance-harnesses; require MUST-clauses ≥ 0.95 pass
  - build: cargo build --release / npm run build / cargo check --workspace; exit 0
  - lint: project's linter; exit 0

Capture EVERYTHING:
  { command 2>&1; echo "EXIT:$?"; } | tee raw/<test-type>.stdout
  cargo llvm-cov --json --summary-only > raw/coverage.json   (or equivalent)

Cap parallelism on shared resources (DB ports, fixed ports, GPU, real-service rate limits). Use /agent-mail file_reservation_paths if multiple compliance-verifiers might collide on a shared file or fixture.

If a required external service (Stripe, Supabase) is unreachable, record verdict=UNVERIFIED_INFRA — do NOT mark PASS by default and do NOT silently skip.

Output compliance.json conforming to the schema in references/EVIDENCE-SCHEMAS.md, plus raw/ files.
```

---

## Phase 5 — Anti-theater scan (subagents/theater-detector.md, one per bead)

```
You are the theater-detector for bead <BEAD_ID>.

Read <AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/{spec,evidence,compliance}.json. Apply /mock-code-finder methodology to every file path cited in evidence.json (and ONLY those files — do not rescan the whole project; that's not your job).

Specifically scan for:
  1. Stubs: `unimplemented!()`, `todo!()`, `panic!("not implemented...")`, `NotImplementedError`, `pass` in non-protocol Python methods
  2. Hardcoded returns: `return 0`, `return None`, `return {}`, `return ""`, `return Default::default()` in functions the bead said should compute something
  3. Mocks where forbidden: if spec.constraints.no_mocks is true, any mock library usage is BLOCKING; mocks of services in spec.constraints.allowed_mocks are allowed
  4. Sleep-as-fake-work: time.sleep / thread::sleep / setTimeout in production code paths simulating real I/O
  5. Hardcoded scores/metrics: `score = 3`, `count = 0` where the bead said "compute from data"
  6. 501 / "Not Implemented" responses in API routes the bead claimed to implement
  7. Test theater: `assert true`, `expect(true).toBe(true)`, `it.skip(...)`, `#[ignore]` on tests the bead required, `#[cfg(not(test))]` guards that mean "skip the real work in test mode"
  8. Dead branches: code paths with no test coverage that contain the actual business logic (the test exercised only the trivial branch)

For each finding, classify severity per references/RUBRIC.md §3 and link to the Phase 4 check it invalidates (if any). A test that "passed" because the implementation short-circuits is BLOCKING in this phase regardless of Phase 4's verdict.

Output theater.json conforming to the schema in references/EVIDENCE-SCHEMAS.md.

If the bead's spec has zero code/test items, output an empty theater.json with summary = {BLOCKING: 0, MAJOR: 0, MINOR: 0, NOTE: 0}.
```

---

## Phase 6 — Test depth audit (subagents/test-depth-auditor.md, one per bead)

```
You are the test-depth-auditor for bead <BEAD_ID>.

Read <AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/{spec,evidence,compliance}.json.

For every test type the bead's spec required, measure depth (NOT just existence) using the table in references/PHASES.md Phase 6.

Coverage must be measured over the BEAD's specific code (the files cited in evidence.json under code_artifacts), not project-global. Filter the coverage tool's output by file path.

For fuzz: confirm corpus_size, ran_for_stated_duration, ci_wired (look in .github/workflows/), no_crashes.
For property: confirm minimum iteration count was reached (parse the runner output).
For metamorphic: confirm every cited metamorphic relation has a corresponding test.
For golden: confirm artifacts exist on disk + last regenerated within freshness window + clean diff (or documented).
For conformance: per /testing-conformance-harnesses, confirm MUST-clauses ≥ 0.95 pass.
For e2e: per /testing-real-service-e2e-no-mocks, confirm real services were hit (structured-log evidence in raw/).

Output test_depth.json conforming to the schema in references/EVIDENCE-SCHEMAS.md.

Do not modify any project file or any other audit artifact.
```

---

## Phase 7 — Cross-bead synthesis (subagents/cross-bead-synthesizer.md, 1–2 senior agents)

```
You are the cross-bead-synthesizer.

Read every <AUDIT_DIR>/passes/<PASS>/beads/<id>/{spec,evidence,compliance,theater,test_depth}.json plus the dependency DAG at <AUDIT_DIR>/passes/<PASS>/dag.json.

Look for:
  1. Integration gaps: bead A consumes bead B's output but the contract drifted (A.spec.json input shape ≠ B.evidence.json output shape).
  2. Contradictions: two closed beads make conflicting claims about the same behavior.
  3. Shared invariants nobody owns: every bead silently assumes invariant X but no single bead owns X.
  4. Orphaned acceptance criteria: bead A's AC says "delegated to bead B" but B's spec.json has no matching item.
  5. Dependency-graph anomalies: cycles (must be empty), orphans (closed bead with no closed parent), stale edges (depended-upon bead is tombstoned).
  6. Bead-graph truthfulness: closed beads whose dependents are still open (sometimes legitimate; often a sign that something downstream broke and nobody noticed).

If your context overflows reading all reports, partition by label or epic and produce per-domain syntheses, then a meta-synthesis that aggregates the per-domain ones.

Output <AUDIT_DIR>/passes/<PASS>/synthesis.md per the structure in references/PHASES.md Phase 7. Every finding must cite specific bead IDs and specific evidence file paths.

Do NOT score beads (that's Phase 8). Do NOT remediate (that's Phase 9). Your output feeds the scorer's dimension 6 (cross-bead integration).
```

---

## Phase 8 — Scoring (subagents/scorer.md, one per bead, then one for the master report)

```
Per-bead scoring (one subagent per bead):

You are the scorer for bead <BEAD_ID>.

Read <AUDIT_DIR>/rubric.md (the project's rubric — NOT references/RUBRIC.md, which is the default; the audit dir's rubric.md is what's actually in force for this project).

Read <AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/{spec,evidence,compliance,theater,test_depth}.json plus <AUDIT_DIR>/passes/<PASS>/synthesis.md (filtered to findings touching this bead).

Apply the rubric mechanically. Be DETERMINISTIC: given the same evidence pack, two runs must produce the same score. Subjective judgment lives in the rubric, not in your scoring.

For each of the 6 dimensions, compute the score per references/RUBRIC.md, citing the specific evidence file and finding ID for every dock or credit.

Write <AUDIT_DIR>/passes/<PASS>/beads/<BEAD_ID>/scorecard.md per assets/scorecard-template.md. Required sections:
  - Header (id, title, claimed status, claimed close reason and date, total score, verdict band)
  - Dimension scores table (6 rows with score / max and one-sentence "why" + citation)
  - Citations (paths to all 5 evidence JSON files + raw/)
  - Missing items (verbatim — Phase 9 copies this into the remediation bead body)
  - Cross-bead links (synthesis findings touching this bead)
  - Score-trend (if a prior pass exists)

Do NOT remediate. Do NOT modify any other artifact.

---

Master report (one subagent, after all per-bead scorecards exist):

You are the master-report writer.

Read every scorecard.md in <AUDIT_DIR>/passes/<PASS>/beads/. Produce <AUDIT_DIR>/passes/<PASS>/REPORT.md and overwrite <AUDIT_DIR>/REPORT.md with the same content.

Required sections:
  - Executive summary (paste-ready, 5–7 bullets)
  - Distribution table (count per verdict band)
  - Ranked scoreboard (id, title, status, score, top-1-missing-item, scorecard link)
  - False-closed list (status=closed AND score<threshold; sorted by score asc; **THIS IS THE HEADLINE**)
  - Trends (if prior pass exists; per-bead score deltas)

Then update <AUDIT_DIR>/trends.md by appending one row per bead per pass: `<UTC>, <bead_id>, <score>`.
```

---

## Phase 9 — Remediation (subagents/remediator.md)

```
You are the remediator.

Read <AUDIT_DIR>/REPORT.md (the false-closed list specifically) and the user's remediation policy from manifest.json#remediation_policy.

For each false-closed bead, take the policy-specified action:

  policy=reopen:
    br reopen <bead-id>
    br update <bead-id> --status open
    Add a comment via br: "Reopened by audit pass <UTC>; score <X>/1000; missing items: <verbatim list from scorecard>"

  policy=completion-debt (default):
    Read the scorecard's "Missing items" section verbatim.
    br create --title "[completion-debt] <original title>" \
      --type task --priority <same-as-original> \
      --parent <original-bead-id> \
      --description "<verbatim missing items from scorecard>" \
      --json
    Capture the new bead ID.
    For each downstream bead that depended on the original (look up in dag.json): br dep add <downstream> <new-bead-id>
    Add a note to the new bead linking the audit pass and scorecard.

  policy=report-only:
    No br writes. Just record what WOULD have been done in remediation.md.

After all actions:
  br sync --flush-only
  git -C <PROJECT> add .beads/
  git -C <PROJECT> commit -m "audit: remediation for pass <UTC> (created/reopened <N> beads)"

Write <AUDIT_DIR>/passes/<PASS>/remediation.md per the structure in references/EVIDENCE-SCHEMAS.md, with one row per action taken.

Then overwrite <AUDIT_DIR>/remediation.md with the same content.

Do NOT push to the project's remote unless the user explicitly authorized that.
```

---

## Phase 10 — Fresh-eyes audit (subagents/fresh-eyes-rubric-auditor.md)

```
You are the fresh-eyes-rubric-auditor. You did NOT participate in earlier phases of this pass; treat the artifacts cold.

Independently verify:

1. Rubric consistency: spot-check 5 random scorecards (use `shuf -n 5` over the bead list). For each, re-derive the score from the evidence pack using rubric.md. If your derived score differs from the scorer's by more than 50 points, flag.

2. Generosity: scan all scorecards for dimension scores that don't match cited evidence. Example: 250/250 on tests when theater.json has a BLOCKING test theater. Flag every mismatch.

3. Category miss: did the audit cover every bead type? Cross-check inventory.jsonl bead types against the set of beads with scorecards. Flag if any whole type was skipped.

4. Convergence criteria: read the criteria in SKILL.md. Compute each one. Run scripts/convergence-check.py for the formal output.

Write <AUDIT_DIR>/passes/<PASS>/convergence.json per the schema in references/EVIDENCE-SCHEMAS.md, with `is_converged: true | false`, the computed criteria values, and a `next_pass_tasks` list if not converged.

Update REPORT.md's executive summary with the convergence verdict at the top:
  > **Convergence: <true|false>**. Max score delta vs prior pass: <X>. New false-closed: <Y>.

If not converged, the user should invoke the skill again later (after remediation work is done) and a new pass will write to passes/<new-UTC>/.
```
