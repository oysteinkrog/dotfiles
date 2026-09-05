# PHASES.md — The 10-Phase Playbook

Every phase has: **goal**, **inputs**, **outputs**, **how to run** (with the exact subagent prompt cross-referenced in `EXACT-PROMPTS.md`), **exit criteria**, and **failure-mode rescue**. Phases that can be parallelized across beads are tagged `★ parallel`. Phases that must serialize are tagged `■ serial`.

---

## Phase 1 — Bead Universe Inventory & Sanity Check ■ serial

**Goal.** Confirm the bead store is intact and produce an exhaustive, machine-readable inventory of every bead in the project, classified by type and status, with the dependency DAG built and closed-bead-to-commit cross-references in hand.

**Inputs.** Project root with `.beads/`.

**Outputs.**
- `passes/<UTC>/doctor.json` — raw `br doctor --json` dump.
- `passes/<UTC>/inventory.jsonl` — one bead per line with full payload.
- `passes/<UTC>/dag.json` — dependency edges + topological order.
- `passes/<UTC>/git_xref.json` — for each closed bead, the candidate commits that mention it (`git log --all --grep=<bead-id>`), plus blame summaries for files those commits touched.
- A summary printed to the user: `N total beads (X open, Y in_progress, Z closed, W blocked, V deferred, U draft)` plus type breakdown.

**How to run.**

```bash
# 1. Doctor MUST be clean before anything else.
br doctor --json > passes/$PASS/doctor.json
if [ $(jq '.healthy // .ok // false' passes/$PASS/doctor.json) != "true" ]; then
  echo "BEAD STORE IS NOT HEALTHY. Aborting. Run /fixing-beads-problems first."
  exit 2
fi

# 2. Inventory every bead.
br list --json > passes/$PASS/inventory.jsonl

# Or, if your br emits a JSON array:
br list --json | jq -c '.[]' > passes/$PASS/inventory.jsonl

# 3. Per-bead full payload (the list view often abbreviates).
mkdir -p passes/$PASS/beads
for id in $(jq -r '.id' passes/$PASS/inventory.jsonl); do
  br show "$id" --format json > "passes/$PASS/beads/$id/show.json" 2>/dev/null \
    || br show "$id" --json > "passes/$PASS/beads/$id/show.json"
done

# 4. Build the DAG.
br dep cycles --json > passes/$PASS/cycles.json   # MUST be empty
# Use bv if available for richer graph metrics:
bv --robot-graph --graph-format json > passes/$PASS/dag.json 2>/dev/null

# 5. Cross-reference closed beads against git history.
for id in $(jq -r 'select(.status == "closed") | .id' passes/$PASS/inventory.jsonl); do
  git -C <project> log --all --grep="$id" --format='%H%x09%s' > "passes/$PASS/beads/$id/git_xref.txt"
done
```

**Exit criteria.**
- `br doctor` exits clean.
- `cycles.json` is empty (`[]`).
- Every bead in `inventory.jsonl` has a corresponding `passes/$PASS/beads/<id>/show.json`.
- The user has confirmed the count breakdown matches their expectation.

**Failure-mode rescue.**
- `br doctor` non-zero → STOP. Hand off to `/fixing-beads-problems`. Do not continue with a corrupt store.
- `cycles.json` non-empty → flag in the report; cycles indicate planning errors that distort dependency-aware scoring.
- A closed bead has zero git-xref hits → strong false-closed signal already; record it now so Phase 8 weights it heavily.

---

## Phase 2 — Per-Bead Specification Extraction ★ parallel (one subagent per bead or per cluster)

**Goal.** Parse each bead's body into a **structured, literal verification checklist** so that "did we do what the bead said" becomes a mechanical question.

**Inputs.** `passes/<UTC>/beads/<id>/show.json` (full bead payload: `description`, `design`, `acceptance_criteria`, `notes`, plus metadata).

**Outputs.** `passes/<UTC>/beads/<id>/spec.json` per bead. Schema in `EVIDENCE-SCHEMAS.md`.

**How to run.** Spawn one `subagents/bead-spec-extractor.md` agent per bead (or per cluster of related beads to amortize context). Each agent reads the bead body and emits `spec.json` with checklist items grouped by category:

```
spec.json categories:
- code_artifacts        (files/modules/functions the bead names)
- tests                 (unit / integration / e2e / fuzz / property / metamorphic / golden / conformance — separately enumerated)
- documentation         (READMEs, ADRs, runbooks, comments — anything explicitly required)
- migrations            (schema changes, data migrations, rollback paths)
- feature_flags         (any flag the bead names + its default state)
- telemetry             (metrics, logs, traces, alerts)
- ci_workflows          (GitHub Actions, gh workflows, cron jobs)
- acceptance_criteria   (verbatim bullets from the bead's AC field)
- implicit_requirements (what follows from the type/category — e.g., a "feature" bead implicitly needs a happy-path test)
```

**Be extremely literal.** If the bead says "the fuzzer must run for 60 seconds in CI without crashes," that is a single checkbox: `tests.fuzz: { duration_seconds: 60, ci_wired: true, no_crashes: true }`. If the bead says "no mocks," that becomes `constraints.no_mocks: true`. Don't paraphrase — quote.

**Exit criteria.**
- Every bead has a `spec.json`.
- Every bullet in the bead's `acceptance_criteria` field appears verbatim under `spec.acceptance_criteria`.
- Implicit requirements added based on bead type (see `BEAD-TYPE-WEIGHTS.md` for what each type implies).

**Failure-mode rescue.**
- Bead body is empty or extremely terse → flag in `spec.json` with `coverage_gaps: ["bead body too thin to verify"]` and let Phase 8 dock the score on the *original-bead-quality* dimension. Don't invent requirements that weren't there.
- Bead body has external links (e.g., to a Notion doc) → record the link, but don't fetch it; verification is against what's *in the bead*.

---

## Phase 3 — Implementation Evidence Gathering ★ parallel

**Goal.** For each `spec.json` checklist item, locate the actual artifact in the repo that purports to fulfill it — or mark it `MISSING`.

**Inputs.** `spec.json` per bead + the project repo.

**Outputs.** `evidence.json` per bead. Schema in `EVIDENCE-SCHEMAS.md`.

**How to run.** `subagents/evidence-gatherer.md` per bead. The agent uses:

```bash
# 1. Closed beads: start with the commits that mention the bead ID.
git -C <project> log --all --grep="<bead-id>" --name-only

# 2. Linked PRs / external refs (if the bead has external_ref).
gh pr list --search "<bead-id>" --json number,title,files,state

# 3. For each named code artifact, find it.
rg --files-with-matches '<symbol>' src/ tests/

# 4. Trace from test names → bead ID conventions (some projects name tests after beads).
rg -n 'bd-abc123|<bead-id-pattern>' tests/

# 5. For required CI workflows: check .github/workflows/.
ls .github/workflows/ | grep -E '<expected-name>'

# 6. For documentation: check README, docs/, runbooks.
rg -l '<expected-doc-keyword>' README.md docs/ runbooks/
```

For every spec checklist item, write a record:

```json
{
  "spec_item_id": "tests.fuzz.duration_seconds:60",
  "status": "FOUND" | "MISSING" | "AMBIGUOUS",
  "citations": [
    {"path": "fuzz/fuzz_targets/parser.rs", "line_start": 1, "line_end": 24,
     "commit_sha": "abc1234", "via": "git log --grep=bd-abc123"}
  ],
  "notes": "Fuzz target compiles; CI duration set in fuzz.yml line 18 (60s)."
}
```

**Exit criteria.**
- Every spec item has either `FOUND` (with at least one citation) or `MISSING` (with a brief explanation).
- `AMBIGUOUS` is allowed but rare; use only when multiple candidates exist and Phase 4 will disambiguate by execution.

**Failure-mode rescue.**
- A spec item maps to a generic concept (e.g., "use `/multi-pass-bug-hunting` methodology") → resolve by checking commit messages and CI logs for evidence of the methodology being applied; don't try to literally find a file.
- Found code in a stale branch only → record the branch name, mark `AMBIGUOUS`, let Phase 4 fail it.

---

## Phase 4 — Compliance Verification (Execution) ★ parallel where safe

**Goal.** **Actually re-run the proof.** Tests, builds, fuzzers (for their stated durations), conformance harnesses, real-service e2e flows. Capture raw stdout/stderr/exit-code. **Never trust a self-reported "tests pass."**

**Inputs.** `evidence.json` per bead + the project's test-runner / build-tool config.

**Outputs.** `compliance.json` per bead + raw logs under `passes/<UTC>/beads/<id>/raw/`. Schema in `EVIDENCE-SCHEMAS.md`.

**How to run.** `subagents/compliance-verifier.md` per bead. Concurrency must be capped by **shared-resource collisions** — DB ports, fixed network ports, GPU, real-service rate limits. Use `/agent-mail` file reservations for any test that touches a shared file.

For each test type:

| Test type | How to verify | "Pass" means |
|-----------|---------------|--------------|
| Unit | `cargo test <test_name>` / `pytest -k <name>` / `vitest run <path>` | Exit 0, **and** the test body is non-trivial (Phase 5 catches `assert true`) |
| Integration | Same runner; ensure DB/service is real, not mocked | Same + Phase 5 confirms no mocks where forbidden |
| E2E | Run end-to-end against real services per `/testing-real-service-e2e-no-mocks` | Same + structured-log evidence of the real service being hit |
| Fuzz | Run for the bead's stated duration without crashes (e.g., `cargo fuzz run target -- -max_total_time=60`) | Exit 0 after stated time + corpus is non-empty |
| Property | Run with stated minimum iterations (e.g., `proptest -- --cases 1000`) | Exit 0 after iterations + shrink history captured |
| Metamorphic | Run the metamorphic relation tests per `/testing-metamorphic` | Exit 0 + the MRs cited in the bead are present |
| Golden | Regenerate goldens and `git diff --exit-code` | Exit 0 (clean diff) OR documented intentional diff |
| Conformance | Run the conformance harness against the reference per `/testing-conformance-harnesses` | Exit 0 + matrix shows MUST clauses ≥ 0.95 pass |
| Build | `cargo build --release` / `npm run build` / `cargo check --workspace` | Exit 0, no warnings (or warnings-allowlist documented) |
| Lint | Whatever the project uses (clippy / eslint / ruff) | Exit 0 |

Capture **everything**:

```bash
cd <project>
{ cargo test --workspace 2>&1; echo "EXIT:$?"; } | tee passes/$PASS/beads/$id/raw/tests.stdout
cargo llvm-cov --json --summary-only > passes/$PASS/beads/$id/raw/coverage.json
```

Then `compliance.json` records:

```json
{
  "bead_id": "bd-abc123",
  "checks": [
    {
      "spec_item_id": "tests.unit.parser_test",
      "command": "cargo test parser_test",
      "exit_code": 0,
      "stdout_path": "raw/tests.stdout",
      "duration_ms": 1234,
      "summary": "1 passed",
      "verdict": "PASS"
    },
    {
      "spec_item_id": "tests.fuzz.duration_seconds:60",
      "command": "cargo fuzz run parser -- -max_total_time=60",
      "exit_code": 0,
      "ran_for_seconds": 61,
      "crashes_found": 0,
      "corpus_size": 1247,
      "verdict": "PASS"
    }
  ]
}
```

**Exit criteria.**
- Every spec item with status `FOUND` in Phase 3 has a `compliance.json` entry with a `verdict` of `PASS`, `FAIL`, or `SKIPPED` (with reason).
- Raw outputs are persisted under `raw/` (not just summaries).
- `MISSING` items from Phase 3 are carried forward as `verdict: MISSING` (no execution attempted).

**Failure-mode rescue.**
- Test runner segfaults → record `verdict: ERROR`, attach stderr, do **not** retry indefinitely; Phase 8 will dock the score and Phase 10 will flag the runner instability.
- Required external service (Stripe, Supabase) unreachable → record `verdict: UNVERIFIED_INFRA`, do not score as `PASS`; user must run again with infra up.
- Test takes too long for the time budget → record `verdict: TIMEOUT`, capture partial output, dock Phase 8 for "didn't finish in budget."

---

## Phase 5 — Anti-Mock / Anti-Stub / Anti-Theater Scan ★ parallel

**Goal.** Confirm that the code/tests claimed in Phase 3 are *real implementations*, not theater (stubs, mocks-where-forbidden, hardcoded happy paths, `assert true`, dead branches, conditional skips in test mode).

**Inputs.** `evidence.json` (file:line citations) + the project repo.

**Outputs.** `theater.json` per bead. Schema in `EVIDENCE-SCHEMAS.md`.

**How to run.** Apply `/mock-code-finder` to every file cited in `evidence.json`. Specifically:

```bash
# 1. Keyword scan over evidence files only.
EVIDENCE_FILES=$(jq -r '.checks[].citations[].path' evidence.json | sort -u)
rg -n "TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER|MOCK|DUMMY|FAKE|TEMP" $EVIDENCE_FILES
rg -n "unimplemented!|todo!|panic!\(\"not implemented|NotImplementedError|raise NotImplementedError" $EVIDENCE_FILES
rg -n "pass$|return None$|return \{\}$|return \[\]$|return \"\"$|return 0$" $EVIDENCE_FILES

# 2. AST scan for suspiciously short functions.
ast-grep run -l <lang> -p 'fn $NAME($$$) { $SINGLE_STMT }' --json
ast-grep run -l <lang> -p 'fn $NAME($$$) -> $RET { todo!() }' --json

# 3. Behavioral patterns: sleep-as-fake-work, hardcoded scores, 501 responses.
rg -n "sleep\(|thread::sleep|time\.sleep" $EVIDENCE_FILES
rg -n "score\s*=\s*[0-9]|count\s*=\s*0[^.]|return\s+501|Not Implemented" $EVIDENCE_FILES

# 4. Test-specific anti-theater patterns.
rg -n "assert\s+true|assert\s*\(\s*true\s*\)|expect\(true\).toBe\(true\)" $EVIDENCE_FILES
rg -n "it\.skip|test\.skip|describe\.skip|#\[ignore\]|#\[cfg\(not\(test\)\)\]" $EVIDENCE_FILES
rg -n "if cfg!\(test\)|if process\.env\.NODE_ENV.*test" $EVIDENCE_FILES

# 5. Mock detection where the bead said no mocks.
NO_MOCKS=$(jq -r '.constraints.no_mocks // false' spec.json)
if [ "$NO_MOCKS" = "true" ]; then
  rg -n "Mock|jest\.mock|sinon|nock|httpmock|mockall" $EVIDENCE_FILES
fi

# 6. Cross-reference Phase 4: a "passing" test whose body is short and asserts trivially is theater.
```

Each finding is recorded with severity:

| Severity | Examples | Rubric impact |
|----------|----------|---------------|
| `BLOCKING` | `unimplemented!()` in claimed implementation; `assert true` in claimed test; mock where bead said no-mocks | Phase 8: zeroes the relevant rubric dimension |
| `MAJOR` | TODO comment in critical path; `return 0` in a function the bead said "compute X" | Phase 8: dock 50–75% of the dimension |
| `MINOR` | TODO comment in an unrelated function; commented-out diagnostic code | Phase 8: dock 5–15% |
| `NOTE` | Style nit, harmless `pass` in a Python protocol method | No impact |

Cross-reference with Phase 4: a test that "passed" only because the implementation short-circuits is a **Phase 5 BLOCKING** finding (mark both phases).

**Exit criteria.**
- Every Phase 3 evidence file has been scanned.
- Every finding has a severity, file:line, and snippet.
- BLOCKING findings are linked back to which Phase 4 check they invalidate.

**Failure-mode rescue.**
- An ast-grep pattern misfires in a language we don't have a parser for → fall back to `rg` heuristics; record `methodology: rg-only` so Phase 10 can flag.
- A "mock" finding is actually an intentional test double for an out-of-scope service (e.g., we mock the email provider in a billing test) → spec.json should have allowed it under `constraints.allowed_mocks: ["email-provider"]`; if not, it's the bead author's problem, not the implementer's.

---

## Phase 6 — Test Artifact Depth Verification ★ parallel

**Goal.** For each bead's required test artifacts, verify they actually exercise the claimed surface — not just exist.

**Inputs.** `evidence.json` + `compliance.json` + `theater.json` + the project repo.

**Outputs.** `test_depth.json` per bead. Schema in `EVIDENCE-SCHEMAS.md`.

**How to run.** `subagents/test-depth-auditor.md` per bead. For each test type the bead requires:

| Test type | Depth check |
|-----------|-------------|
| **Unit / integration** | Branch + line coverage **over the bead's specific code** (not project-global). Use `cargo llvm-cov --json` then filter by file paths in `evidence.json`. Threshold: 80% line, 70% branch (configurable). |
| **Fuzz** | (a) Corpus directory exists and is non-empty. (b) Harness compiles. (c) Re-ran for the bead's stated duration without crashes. (d) Coverage of fuzzed code is ≥ 60% line. |
| **Property** | (a) Stated minimum iteration count was reached. (b) At least one shrink occurred (or a `proptest-regressions` file exists, indicating past failures captured). |
| **Metamorphic** | (a) The metamorphic relations cited in the bead are all implemented (one test per MR). (b) Per `/testing-metamorphic`, the relations are non-trivial. |
| **Golden** | (a) Golden artifacts exist on disk. (b) Last regenerated within the bead's claimed freshness window (default: same commit or within 30 days). (c) `regenerate && git diff --exit-code` exits 0, OR intentional diff is documented in `theater.json`. |
| **Conformance** | (a) Reference implementation/spec is wired up. (b) Compliance matrix is current (date-stamped). (c) MUST-clause pass rate ≥ 0.95 per `/testing-conformance-harnesses`. |
| **E2E** | Per `/testing-real-service-e2e-no-mocks`: (a) Real database hit (transaction rollback isolation OK). (b) Real external service hit (Stripe test mode counts as real; mocks don't). (c) Structured-log evidence of the real service in `raw/`. |

Each check is `PASS` / `FAIL` / `WAIVED` (with reason).

**Exit criteria.**
- Every test type the bead required has a depth check result.
- Coverage data is computed against the bead's surface, not project-global.
- WAIVED requires explicit reason linked back to `spec.json` (e.g., "bead said `coverage_minimum: n/a`").

**Failure-mode rescue.**
- Coverage tool unavailable for the project's language → flag in `test_depth.json` with `methodology: line_count_only` and dock Phase 8 for "depth not measurable."
- Fuzzer infrastructure not installed (e.g., `cargo-fuzz` missing) → install if possible; otherwise record `verdict: INFRA_MISSING` and dock.

---

## Phase 7 — Cross-Bead Consistency & Integration Synthesis ■ serial

**Goal.** With every bead now individually verified, look across them for the gaps that no single bead's audit can see.

**Inputs.** All `spec.json`, `evidence.json`, `compliance.json`, `theater.json`, `test_depth.json` from this pass + the dependency DAG.

**Outputs.** `synthesis.md` (single document for the whole pass). One or two **senior** agents — not parallelized — read all per-bead reports holistically.

**How to run.** `subagents/cross-bead-synthesizer.md`. The agent looks for:

1. **Integration gaps** — Bead A claims to consume bead B's output; check that the contract drift between A's `spec.json` and B's `evidence.json` is zero. Example: B claims to emit `{user_id, score}` but A's evidence shows it parses `{userId, rating}`.
2. **Contradictions between two closed beads** — e.g., bead X says "the parser rejects negative numbers" and bead Y says "the parser handles negative numbers as decrement operators." Both can't be closed.
3. **Shared invariants nobody owns** — every bead silently assumes "the migration ran first" but no single bead owns the migration.
4. **Orphaned acceptance criteria** — bead A's AC mentions a behavior delegated to bead B, but B's `spec.json` has no corresponding item.
5. **Dependency-graph anomalies** — cycles (must be empty), orphans (closed bead with no closed parent), and dependency edges that became stale because the depended-upon bead was tombstoned.
6. **Bead-graph truthfulness** — closed beads whose dependents are still open should raise eyebrows; sometimes legitimate, often a sign that something downstream broke.

**Output structure** (`synthesis.md`):

```markdown
# Cross-Bead Synthesis — Pass <UTC>

## Integration gaps
| Producer | Consumer | Contract drift |
|----------|----------|---------------|
| bd-abc123 | bd-def456 | Producer emits `score: float`; consumer parses `score: int` |

## Contradictions
| Bead A | Bead B | Conflicting claim |
|--------|--------|-------------------|

## Orphaned ACs
| Bead | AC bullet | Where it should have lived |
|------|-----------|----------------------------|

## Dependency-graph anomalies
| Issue | Beads | Severity |
|-------|-------|----------|

## Shared invariants nobody owns
| Invariant | Beads that assume it | Who should own it |
|-----------|---------------------|-------------------|
```

**Exit criteria.**
- Every category above has an explicit "(none found)" or a populated table.
- Each finding is linked to specific bead IDs and specific evidence files.

**Failure-mode rescue.**
- Synthesis agent's context overflows reading all reports → split by domain (group beads by label/epic) and produce per-domain syntheses, then a meta-synthesis.

---

## Phase 8 — Scoring (0–1000) & Master Report ■ serial

**Goal.** Apply the published rubric to every bead, emit per-bead scorecards and the master report.

**Inputs.** All Phase 2–6 artifacts per bead + `synthesis.md` + `rubric.md`.

**Outputs.**
- `passes/<UTC>/beads/<id>/scorecard.md` per bead.
- `passes/<UTC>/REPORT.md` — ranked scoreboard, summary stats, false-closed list, exec summary.
- Top-level `REPORT.md` is updated to point at the latest pass.

**How to run.** `subagents/scorer.md` runs `scripts/score-bead.py` per bead, then `scripts/master-report.py` aggregates. The scorer is **deterministic** — given the evidence pack, two runs must produce the same score. Subjective judgments live in the rubric, not in the scoring code.

For each bead, the scorecard cites:

```markdown
# Scorecard — bd-abc123

**Title:** Implement parser fuzz harness with 60s CI run
**Status (claimed):** closed (closed_at: 2026-04-12, close_reason: "Implemented and tested")
**Score: 612 / 1000**
**Verdict: 🟠 False-closed (mild) — REOPEN**

## Dimension scores

| Dimension | Score | Max | Why |
|-----------|------:|----:|-----|
| Implementation completeness vs. spec | 240 | 300 | Parser exists at `src/parser.rs:1-450` (commit `abc1234`). Missing: error-recovery path the bead's design notes required (`spec.json#code.error_recovery: MISSING`). |
| Required tests present and meaningfully passing | 100 | 250 | Unit tests pass (`compliance.json#unit: PASS`). Fuzz target compiles but **CI does not run it for 60s** (`test_depth.json#fuzz.ci_wired: FAIL` — `.github/workflows/ci.yml` has `-max_total_time=10`). |
| Anti-theater | 50 | 150 | Two BLOCKING findings: `src/parser.rs:312` returns `Ok(Default::default())` on the error-recovery branch (theater.json#1); fuzz target's `harness.rs:14` calls `unimplemented!()` on multi-byte input (theater.json#2). |
| Test depth | 90 | 150 | Coverage of `src/parser.rs` is 78% line (under 80% threshold). Fuzz corpus is 0 — never seeded. |
| Docs / telemetry / migrations | 80 | 100 | README updated (commit `def5678`); no migration needed. |
| Cross-bead integration | 52 | 50 | Capped at 50; bead is well-integrated. |

## Citations
- spec.json: `passes/<UTC>/beads/bd-abc123/spec.json`
- evidence.json: `passes/<UTC>/beads/bd-abc123/evidence.json`
- compliance.json: `passes/<UTC>/beads/bd-abc123/compliance.json`
- theater.json: `passes/<UTC>/beads/bd-abc123/theater.json`
- test_depth.json: `passes/<UTC>/beads/bd-abc123/test_depth.json`
- raw test logs: `passes/<UTC>/beads/bd-abc123/raw/`

## Missing items (verbatim from spec.json, for Phase 9 remediation)
1. Implement parser error-recovery path (spec: `code.error_recovery`)
2. Wire fuzz target into CI for 60s (spec: `tests.fuzz.duration_seconds:60` + `tests.fuzz.ci_wired`)
3. Seed fuzz corpus with at least 50 inputs covering all parser branches (spec: `tests.fuzz.corpus_min:50`)
4. Implement multi-byte input handling in fuzz harness (theater: `harness.rs:14 unimplemented!()`)
5. Replace `Ok(Default::default())` in error-recovery with real recovery logic (theater: `src/parser.rs:312`)
```

**Master report** structure (`REPORT.md`):

```markdown
# Beads Compliance Audit — Master Report
Pass: <UTC>  |  Project: <path>  |  Threshold: 700  |  Beads audited: N

## Executive summary (paste-ready)
- **N** total beads audited; **X** false-closed (status=closed, score<700) — **Y%** of all closed beads (of K total closed).
- Worst offender: bd-XXX (score 187/1000) — entire conformance harness was theater.
- Best in class: bd-YYY (score 985/1000).
- Synthesis flagged Z integration gaps; W contract drifts.
- Recommendation: reopen the X false-closed beads and run /multi-pass-bug-hunting on the bottom decile.

## Distribution
| Band | Count | % |
|------|------:|--:|
| 🟢 Verified (950+)         | ... | ... |
| 🟢 Substantially complete  | ... | ... |
| 🟡 Partial                 | ... | ... |
| 🟠 False-closed (mild)     | ... | ... |
| 🔴 False-closed (severe)   | ... | ... |
| 🚨 Theater                 | ... | ... |

## Ranked scoreboard
(table: id, title, status, score, top-1-missing-item, scorecard link)

## False-closed list
(only beads where status=closed AND score<threshold; sorted by score asc)

## Trends (if prior pass exists)
(score deltas per bead between this pass and the previous)
```

**Exit criteria.**
- Every bead has a `scorecard.md` with cited evidence.
- `REPORT.md` exists with the executive summary, distribution, scoreboard, and false-closed list.
- If a prior pass exists, trends are computed.

**Failure-mode rescue.**
- A bead has zero evidence (spec.json says X, evidence.json says all MISSING) and status=closed → score 0–249 (Theater band) and call it out by name in the exec summary.

---

## Phase 9 — Remediation: Reopen & Create Follow-Up Beads ■ serial

**Goal.** Make the bead graph **truthful again**. For every false-closed bead, take an explicit action recorded in `remediation.md`.

**Inputs.** `REPORT.md` false-closed list + the user's remediation policy choice from up-front confirmations.

**Outputs.** `remediation.md` listing every action taken, with new/reopened bead IDs.

**How to run.** `subagents/remediator.md`. Per the user's policy:

| Policy | Action per false-closed bead |
|--------|------------------------------|
| **Reopen** | `br reopen <id>` + `br update <id> --status open` + post a comment with the scorecard link + missing-items list |
| **Completion-debt** *(default)* | Create new bead via `br create --title "[completion-debt] <original title>" --type task --priority <P> --parent <original-id>` + populate description with verbatim missing-items from the scorecard + add `--deps blocks:<dependents>` so downstream blocked work is correctly modeled |
| **Report only** | No bead writes; `remediation.md` lists what *would* have been done |

For both reopen and completion-debt:

- Copy the **verbatim missing-items list** from the scorecard into the bead's `description` and `acceptance_criteria` (so the next implementer doesn't have to reconstruct it).
- Cite the audit pass UTC, the score, and the path to the scorecard in `notes`.
- If the original bead's dependents (downstream beads) are still closed but transitively depended on the gap, link them too.

After all writes:

```bash
br sync --flush-only
git -C <project> add .beads/
git -C <project> commit -m "audit: remediation for pass <UTC> (creates/reopens N beads)"
```

**Exit criteria.**
- Every false-closed bead has a remediation entry.
- New / reopened bead IDs are recorded in `remediation.md`.
- Bead graph is now truthful: every gap is represented as an open bead.

**Failure-mode rescue.**
- `br reopen` fails because the bead is tombstoned → create a new bead instead, link via `external_ref: <tombstoned-id>`.
- The user's remediation policy prevents writes (Report only) → still produce `remediation.md` with full plan; the user can apply it manually later.

---

## Phase 9.5 — Mandatory Polish Loop (after Phase 9 wrote beads) ■ orchestrator-driven

**Goal.** Turn Phase 9's first-draft remediation beads into implementation-ready specs by applying the user-mandated polish prompt three times in a row, with `bv` consulted between sweeps and every edit routed through `br update`.

**When it fires.** Phase 9 wrote ≥ 1 bead AND `--policy != report-only` AND `--no-polish` was not passed. Otherwise N/A.

**Inputs.** `<pass-dir>/remediation.md` (Actions table), the bead store, optional `bv` for graph diagnostics.

**Outputs.** `<pass-dir>/polish_log.md` — three sweep sections with per-bead Decision lines, plus `<pass-dir>/polish_bv_initial.json` (initial bv hygiene snapshot).

**How to run.**

```bash
scripts/polish-remediation-beads.sh <project> <pass-dir>
# (writes the scaffold; orchestrator agent then applies the verbatim polish
#  prompt to each bead in each sweep section and makes br update / br comment
#  calls outside the script)
```

The script is **pure scaffolding**: it captures bv signals, lists target beads (filtering out the table-header row from remediation.md), and writes a 3-section template. The actual prompt application is done by the orchestrator agent (Claude / Codex / Gemini) — see [PHASE-9-5-POLISH-LOOP.md](PHASE-9-5-POLISH-LOOP.md) for the full playbook including worked example.

**Verbatim prompt** (canonical at [assets/polish-prompt.txt](../assets/polish-prompt.txt); enforced by `scripts/validate-polish-prompt-consistency.py`):

> Check over each bead super carefully — are you sure it makes sense? Is it optimal? Could we change anything to make the system work better for users? If so, revise the beads. It's a lot easier and faster to operate in "plan space" before we start implementing these things! DO NOT OVERSIMPLIFY THINGS! DO NOT LOSE ANY FEATURES OR FUNCTIONALITY! Also make sure that as part of the beads we include comprehensive unit tests and e2e test scripts with great, detailed logging so we can be sure that everything is working perfectly after implementation. Make sure to ONLY use the `br` cli tool for all changes, and you can and should also use the `bv` tool to help diagnose potential problems with the beads.

**Hard rules.**
- All edits via `br update` / `br comment` / `br create`. NEVER hand-edit `.beads/issues.jsonl` or `.beads/*.db`.
- 3 sweeps minimum; run a 4th (and 5th, up to ~6 total) if Sweep 3 still produces meaningful edits.
- Touch every new bead each sweep, even if the decision is "no change" (record via `br comment`).
- Consult `bv --robot-suggest` and `bv --robot-priority` between sweeps.
- After all sweeps: `br sync --flush-only`, `git add .beads/`, single commit. **Do NOT push.**

**Convergence signal.** Sweep 3 makes zero edits across all target beads → polish loop converged. If Sweep 3+ keeps producing edits, the bead set is under-specified — escalate to `/idea-wizard` or `/planning-workflow`.

**Idempotency.** The scaffold script REFUSES to overwrite an existing `polish_log.md` (orchestrator notes would be lost) unless `--force`. Pre-existing partial state is preserved by default.

**Failure-mode rescue.**
- `br show <new-id>` fails post-creation (tombstoned somehow) → skip in polish loop, surface in remediation.md as a Phase-9 anomaly.
- Two new beads turn out to be duplicates → merge in Sweep 1 via `br close <one-id> --reason="duplicate of <other-id>"`.
- Polish prompt drift detected by validator → STOP. Run `validate-polish-prompt-consistency.py` and re-sync from `assets/polish-prompt.txt`.
- Sweep 5 still non-converged → close the polish loop with an escalation note in `polish_log.md § Sign-off` and route to `/idea-wizard`.

Full deep-dive (worked example, bv interaction patterns, edge cases): **[PHASE-9-5-POLISH-LOOP.md](PHASE-9-5-POLISH-LOOP.md)**.

---

## Phase 10 — Re-Verification Loop & Convergence ■ serial

**Goal.** Sanity-check the audit itself. Decide whether to converge or run another pass.

**Inputs.** This pass's full artifacts + the prior pass's artifacts (if any).

**Outputs.** `convergence.json` + a written verdict in `REPORT.md`.

**How to run.** `subagents/fresh-eyes-rubric-auditor.md` is a **fresh agent** (different context from the scoring agent) that independently asks:

1. Was the rubric applied **consistently** across beads? Spot-check 5 random scorecards and re-derive the score from the evidence pack. Deviation > 50 points → flag.
2. Was the scorer **too generous** anywhere? Look for scorecards where dimension scores don't match the cited evidence (e.g., 250/250 on tests but Phase 5 found a `BLOCKING` test theater).
3. Did we **miss a whole category of bead**? E.g., did we audit only `Task` and `Feature` types but skip `Bug` beads?
4. Are the convergence criteria met (see SKILL.md `Convergence Criteria`)?

If converged → write the convergence verdict in `REPORT.md` and call the run done. If not → emit a list of what to re-do in the next pass and prompt the user to invoke the skill again.

```bash
./scripts/convergence-check.py \
  --current passes/<UTC> \
  --prior passes/<prev-UTC> \
  --threshold 10 \
  > convergence.json
```

**Exit criteria.**
- `convergence.json` exists with a `converged: true|false` field and a list of next-pass tasks if false.
- `REPORT.md` has been updated with the convergence verdict.

**Failure-mode rescue.**
- Fresh-eyes agent disagrees with the scorer on more than 20% of spot-checks → re-run Phase 8 with a tightened rubric or recalibrate the scorer subagent's prompt.
- The convergence threshold (±10 default) is too loose for the project → tighten in `rubric.md` and re-run.
