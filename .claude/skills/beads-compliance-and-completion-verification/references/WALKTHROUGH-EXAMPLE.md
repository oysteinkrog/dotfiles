# WALKTHROUGH-EXAMPLE.md — End-To-End Audit On A Synthetic 5-Bead Project

<!-- TOC: Setup | Phase 1 inventory | Phase 2 spec extraction | Phase 3 evidence | Phase 4 compliance | Phase 5 theater | Phase 6 depth | Phase 7 synthesis | Phase 8 scoring | Phase 9 remediation | Phase 10 convergence | Pass 2 -->

> Read this end-to-end before running your first audit. Every output below is realistic — drawn from running the actual scripts on a synthetic project. Use it to calibrate expectations.

---

## Setup: project state at audit time

Project: `/tmp/walkthrough` (synthetic). 5 beads:

| Bead | Type | P | Status | Notes |
|------|------|--:|--------|-------|
| bd-feat01 | feature | 1 | closed | "Implement parser" — closed with full implementation + tests |
| bd-feat02 | feature | 1 | closed | "Implement validator" — closed with `unimplemented!()` in primary deliverable |
| bd-bug01 | bug | 0 | closed | "Fix off-by-one in range" — closed with regression test that BISECTs cleanly |
| bd-docs01 | docs | 3 | closed | "README section for parser" — closed without actually updating README |
| bd-epic01 | epic | 0 | closed | "Parser epic" — parent of bd-feat01 + bd-feat02; closed despite bd-feat02 being theater |

Expected verdict: bd-feat01 ✓, bd-bug01 ✓, bd-feat02 false-closed (severe), bd-docs01 false-closed (severe), bd-epic01 false-closed (mild via dimension 6).

---

## Bootstrap

```bash
$ ./scripts/bootstrap-audit.sh /tmp/walkthrough 700 standard completion-debt
Running br doctor on /tmp/walkthrough ...
Created audit dir: /tmp/walkthrough/beads_compliance_audit
/tmp/walkthrough/beads_compliance_audit/passes/2026-05-06T14-00-00Z
```

`/tmp/walkthrough/beads_compliance_audit/manifest.json`:

```json
{
  "audit_dir_version": "1.0.0",
  "project_path": "/tmp/walkthrough",
  "project_git_sha_at_pass_start": "abc1234",
  "rubric_sha256": "9f8e7d6c5b4a...",
  "pass_id": "2026-05-06T14-00-00Z",
  "mode": "standard",
  "score_threshold": 700,
  "remediation_policy": "completion-debt",
  "bead_counts": {"total_issues": 5, "closed_issues": 5, ...}
}
```

---

## Phase 1: inventory

```bash
$ ./scripts/inventory-beads.sh /tmp/walkthrough \
    /tmp/walkthrough/beads_compliance_audit/passes/2026-05-06T14-00-00Z
Inventoried 5 beads
```

Per-bead `show.json` written. Per-bead `git_xref.txt` shows commits per bead:
- bd-feat01 → 3 commits (impl + 2 test commits)
- bd-feat02 → 1 commit (with `unimplemented!()` macro)
- bd-bug01 → 2 commits (fix + regression test)
- bd-docs01 → 0 commits ⚠ (no commits reference the bead)
- bd-epic01 → 0 commits

Phase 1 output flag: bd-docs01 + bd-epic01 have zero git xref. Strong false-closed signal.

---

## Phase 2: spec extraction

`bd-feat02/spec.json` (excerpt):

```json
{
  "bead_id": "bd-feat02",
  "bead_type": "feature",
  "checklist": {
    "code_artifacts": [
      {"id": "code.primary",
       "expected_path_hints": ["src/validator.rs"],
       "weight": 2}
    ],
    "tests": {
      "unit": [{"id": "tests.unit.validator_test", "weight": 1}],
      "fuzz": [{"id": "tests.fuzz.validator", "duration_seconds": 60, "ci_wired": true, "weight": 2}]
    },
    "acceptance_criteria": [
      {"id": "ac.1", "verbatim": "validator rejects malformed input"},
      {"id": "ac.2", "verbatim": "validator handles unicode"},
      {"id": "ac.3", "verbatim": "fuzz target 60s in CI no crashes"}
    ],
    "implicit_requirements": [
      {"id": "implicit.feature.happy_path_test", "added_because": "bead_type=feature"}
    ]
  },
  "constraints": {"no_mocks": true, "coverage_minimum_line": 0.8}
}
```

---

## Phase 3: evidence gathering

`bd-feat02/evidence.json`:

```json
{
  "checks": [
    {
      "spec_item_id": "code.primary",
      "status": "FOUND",
      "citations": [{"path": "src/validator.rs", "line_start": 1, "line_end": 24, "commit_sha": "def5678", "via": "git log --grep=bd-feat02"}]
    },
    {
      "spec_item_id": "tests.unit.validator_test",
      "status": "FOUND",
      "citations": [{"path": "tests/validator_test.rs", "line_start": 1, "line_end": 12, "commit_sha": "def5678"}]
    },
    {
      "spec_item_id": "tests.fuzz.validator",
      "status": "MISSING",
      "citations": [],
      "notes": "Searched expected_path_hints; no fuzz target found"
    }
  ]
}
```

---

## Phase 4: compliance

`bd-feat02/compliance.json`:

```json
{
  "checks": [
    {
      "spec_item_id": "tests.unit.validator_test",
      "command": "cargo test validator_test",
      "exit_code": 0,
      "duration_ms": 234,
      "stdout_path": "raw/tests_unit.stdout",
      "summary": "test result: ok. 1 passed; 0 failed",
      "verdict": "PASS"
    },
    {
      "spec_item_id": "tests.fuzz.validator",
      "command": null,
      "verdict": "MISSING",
      "failure_reason": "Phase 3 marked MISSING; no execution attempted"
    }
  ]
}
```

`raw/tests_unit.stdout`:
```
running 1 test
test validator_test ... ok

test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured
EXIT:0
```

---

## Phase 5: theater scan

`bd-feat02/theater.json`:

```json
{
  "scanned_files": ["src/validator.rs", "tests/validator_test.rs"],
  "findings": [
    {
      "id": "theater.1",
      "severity": "BLOCKING",
      "category": "unimplemented_macro",
      "path": "src/validator.rs",
      "line": 8,
      "snippet": "    fn validate(&self, _input: &str) -> Result<(), Error> { todo!() }",
      "description": "todo!() in primary deliverable",
      "invalidates_phase4_check": "tests.unit.validator_test"
    },
    {
      "id": "theater.2",
      "severity": "BLOCKING",
      "category": "trivial_assertion",
      "path": "tests/validator_test.rs",
      "line": 7,
      "snippet": "    assert!(true);",
      "description": "Test assertion is trivially true",
      "invalidates_phase4_check": "tests.unit.validator_test"
    }
  ],
  "summary": {"BLOCKING": 2, "MAJOR": 0, "MINOR": 0, "NOTE": 0}
}
```

Anomaly scan also fires: `closed_at - created_at = 4 minutes` for a `feature` bead → MAJOR finding.

---

## Phase 6: test depth

`bd-feat02/test_depth.json`:

```json
{
  "checks": [
    {"test_type": "unit", "depth_metric": "line_coverage", "value": 0.0, "threshold": 0.8, "verdict": "FAIL", "notes": "src/validator.rs: 0% (todo! macro never executes)"},
    {"test_type": "fuzz", "depth_metric": "corpus_size", "value": 0, "threshold": 50, "verdict": "INFRA_MISSING"},
    {"test_type": "fuzz", "depth_metric": "ci_wired", "value": false, "threshold": true, "verdict": "FAIL"}
  ]
}
```

---

## Phase 7: synthesis

`synthesis.md`:

```markdown
# Cross-Bead Synthesis — Pass 2026-05-06T14-00-00Z

Generated by synthesize.py over 5 beads.

## Integration gaps
(none auto-detected)

## Orphaned ACs
(none)

## Dependency-graph anomalies
| Issue | Beads | Severity |
|-------|-------|----------|
| `bd-epic01` (closed) → open: `(none — children also closed)` | many | n/a |

## Bead-graph truthfulness flags
| Bead | References | Note |
|------|------------|------|
| `bd-epic01` | `bd-feat02` | Parent claims done but child bd-feat02 is theater (BLOCKING ×2)|

## Cross-references (for awareness)
Found 2 bead-to-bead references in bead bodies.
```

---

## Phase 8: scoring

`bd-feat02/scorecard.md`:

```markdown
# Scorecard — bd-feat02

**Title:** Implement validator
**Type:** feature  **Priority:** P1
**Status (claimed):** closed
**Close reason:** "implemented" (2026-04-15T...)

**Score: 142 / 1000**
**Verdict: 🚨 Theater**
**🚨 FALSE-CLOSED** (status=closed, score=142 < threshold 700)

## Dimension scores

| Dimension | Score | Max | Why |
|-----------|------:|----:|-----|
| Implementation completeness vs. spec | 0 | 300 | code.primary: PASS but BLOCKING theater → 0 (theater.json#1) |
| Required tests present and meaningfully passing | 0 | 250 | unit: PASS but invalidated by theater.json#2; fuzz: MISSING |
| Anti-theater | 50 | 150 | BLOCKING=2 MAJOR=0 → -100 |
| Test depth | 0 | 150 | line=0% (FAIL); fuzz INFRA_MISSING |
| Docs / migrations / telemetry / flags | 100 | 100 | n/a — no non-code items |
| Cross-bead integration | 50 | 50 | No findings touch this bead |
| **TOTAL** | **142** | **1000** | |

## Citations
- spec.json, evidence.json, compliance.json, theater.json, test_depth.json
- raw logs: raw/

## Missing items (verbatim)
- spec item `tests.fuzz.validator` — Phase 3 marked MISSING; no fuzz target found
- check `tests.fuzz.validator` (MISSING) — no execution attempted
- theater [BLOCKING] `src/validator.rs:8` — todo!() in primary deliverable
- theater [BLOCKING] `tests/validator_test.rs:7` — Test assertion is trivially true
```

`REPORT.md` headline:

```markdown
## Executive summary (paste-ready)

- **5** total beads audited; **3** false-closed (status=closed, score<700) — **60%** of all closed beads (of 5 total closed).
- Worst offender: bd-feat02 (score 142/1000) — Implement validator
- Best in class: bd-feat01 (score 985/1000) — Implement parser
- Score median: 580, mean: 590.

## False-closed list

| Bead | P | Type | Score | Title | Scorecard |
|------|--:|------|------:|-------|-----------|
| bd-feat02 | P1 | feature | 142 | Implement validator | [link] |
| bd-docs01 | P3 | docs | 287 | README section for parser | [link] |
| bd-epic01 | P0 | epic | 588 | Parser epic | [link] |
```

---

## Phase 9: remediation (policy=completion-debt)

`remediation.md`:

```markdown
# Remediation — Pass 2026-05-06T14-00-00Z
## Policy: completion-debt

| Original | Score | Action | New ID | Status |
|----------|------:|--------|--------|--------|
| `bd-feat02` | 142 | Created completion-debt | `bd-feat02.1` | open, P0 (bumped from P1 due to severity) |
| `bd-docs01` | 287 | Created completion-debt | `bd-docs01.1` | open, P2 (bumped from P3) |
| `bd-epic01` | 588 | Created completion-debt | `bd-epic01.1` | open, P0 |
```

After git commit:
```
[main 1234567] audit: remediation for pass 2026-05-06T14-00-00Z (acted on 3 beads)
```

---

## Phase 10: convergence (first pass)

`convergence.json`:
```json
{
  "current_pass": "2026-05-06T14-00-00Z",
  "prior_pass": null,
  "is_converged": false,
  "criteria": {"reason": "no prior pass — convergence requires two passes"}
}
```

`REPORT.md` updated:
```
> **Convergence: ✗** — first pass; convergence undefined.
> Re-run after remediation lands.
```

---

## Pass 2 (one week later)

In the meantime:
- An agent picks up `bd-feat02.1`. Implements `validate()` properly. Adds a meaningful unit test. Adds a fuzz target with a 50-input seed corpus. Wires it to CI for 60s.
- Closes `bd-feat02.1` AND notes "see bd-feat02 — original now passes" in the close reason.

User runs: `./scripts/run-pass.sh /tmp/walkthrough --threshold 700`

New pass dir: `passes/2026-05-13T09-00-00Z/`.

Phase 5 + 6 now find:
- bd-feat02: theater.json BLOCKING=0 (todo! is gone). Coverage 92% line. Fuzz corpus=53. CI duration=60. PASS across the board.
- bd-feat02.1: same. Auto-closes when next audit runs.

Phase 8 score: bd-feat02 jumps from **142 → 985**. False-closed → 🟢 Verified.

`REPORT.md`:
```
## Trends vs prior pass

| Bead | Prior | Now | Δ |
|------|------:|----:|--:|
| bd-feat02 | 142 | 985 | +843 |
| bd-docs01 | 287 | 287 | 0 (stuck — no remediation work yet) |
| bd-epic01 | 588 | 612 | +24 (cross-bead improved as bd-feat02 healed) |
```

`convergence.json`:
```json
{
  "is_converged": false,
  "criteria": {
    "max_score_delta_within_threshold": false,
    "max_score_delta_observed": 843,
    "max_score_delta_bead": "bd-feat02",
    "no_new_false_closed": true,
    "all_remediation_beads_exist": true
  },
  "next_pass_tasks": [
    "Remediate bd-docs01 (still false-closed)",
    "Verify bd-feat02 stays at 985 in pass 3"
  ]
}
```

The audit is *closer* to convergence (one bead remediated) but not yet there.

---

## Pass 3+ until convergence

After two more passes (bd-docs01 remediated, bd-epic01 fully resolves once children pass):

Pass 4 vs Pass 3:
- Max score delta: 4 (bd-feat02 stable at 985, bd-docs01 stable at 940, bd-epic01 stable at 870)
- No new false-closed
- No new synthesis findings
- Rubric consistency: 5/5 spot-checks within ±20

```json
{
  "is_converged": true
}
```

`REPORT.md`:
```
> **Convergence: ✓** — two consecutive passes show no material change. The bead graph is now truthful.
```

---

## After convergence: tripwire

```bash
# In CI, daily
./scripts/run-pass.sh /tmp/walkthrough --threshold 700 --policy report-only --mode tripwire
# Exits 0 if still converged; non-zero if regression detected
```

If a future agent closes a new bead with theater, the daily tripwire's exit will turn non-zero, the user gets a Slack notification, and the cycle repeats.

---

## Lessons from this walkthrough

1. **Theater compounds.** bd-feat02's `unimplemented!()` zeroed two dimensions (impl + test) AND propagated to bd-epic01's cross-bead score. One stub corrupts the whole subtree.

2. **Phase 5 is doing real work.** Without it, bd-feat02's score would have been ~580 (compliance "passed", coverage low). With it, the score collapsed to 142 — accurately reflecting that the implementation is missing.

3. **Convergence takes 3-5 passes.** Even on a tiny project, the multi-pass cycle is necessary. Don't expect a single audit to fix everything.

4. **The audit dir's history tells the story.** Reading the trends table for bd-feat02 (`142 → 985`) is far more informative than any single pass score.

5. **Remediation policy matters.** `completion-debt` (default) preserved the original closures' history while creating actionable new beads. `reopen` would have lost that history. `report-only` would have missed the chance to update the bead graph.

---

## Adapting this walkthrough for your project

1. Skim through this end-to-end before your first run.
2. Run `./scripts/run-pass.sh <your-project> --threshold 700 --policy report-only` first (no bead writes).
3. Read the resulting `REPORT.md` and a few `scorecard.md` files. Compare to the patterns above.
4. If the results look reasonable, re-run with `--policy completion-debt`.
5. Plan for 3-5 passes spread over weeks before declaring convergence.