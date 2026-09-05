# EVIDENCE-SCHEMAS.md — Per-File JSON Schemas

Every artifact has a fixed schema so phases can pipe outputs into each other deterministically. All schemas use ISO-8601 UTC timestamps, stable IDs (bead IDs, commit SHAs, file:line ranges, test names), and never embed transient context ("see prior conversation").

---

## `manifest.json` (top-level + per-pass)

```json
{
  "audit_dir_version": "1.0.0",
  "project_path": "/data/projects/frankensqlite",
  "project_git_sha_at_pass_start": "abc1234deadbeef",
  "skill_version": "1.0.0",
  "rubric_version": "1.0.0",
  "rubric_sha256": "<hash of rubric.md>",
  "pass_id": "2026-05-05T12-00-00Z",
  "pass_started_at": "2026-05-05T12:00:00Z",
  "pass_completed_at": "2026-05-05T13:42:17Z",
  "mode": "full-audit",
  "score_threshold": 700,
  "remediation_policy": "completion-debt",
  "parallelism": 6,
  "tools": {
    "br": "0.21.3",
    "bv": "0.13.0",
    "ast_grep": "0.18.0",
    "ripgrep": "14.1.0"
  },
  "bead_counts": {
    "total": 247,
    "open": 32, "in_progress": 4, "closed": 198, "blocked": 8,
    "deferred": 2, "draft": 3, "tombstone": 0, "pinned": 0
  },
  "phase_status": {
    "1": "completed", "2": "completed", "3": "completed",
    "4": "completed", "5": "completed", "6": "completed",
    "7": "completed", "8": "completed", "9": "completed", "10": "completed"
  },
  "convergence": {
    "is_converged": false,
    "compared_to_pass": "2026-04-28T09-00-00Z",
    "max_score_delta": 47,
    "new_false_closed_count": 3
  }
}
```

**Mode-specific extension fields.** Wrappers extend the canonical manifest with
metadata describing the run kind. The scorer / dashboard / drift-check tolerate
their absence (no field → not that kind of audit), so adding new ones never
breaks readers.

| Field | Written by | Meaning |
|-------|-----------|---------|
| `single_bead_target` | `scripts/single-bead-audit.sh` | The `<bead-id>` the run was scoped to. Phase 1 / 7 still saw the full universe; Phases 2-6, 8, 9 only ran on this bead. |
| `as_of_ref` | `scripts/time-machine-audit.sh` | The user-supplied git ref (`HEAD~30`, `v1.2.3`, branch name, …). |
| `as_of_sha` | `scripts/time-machine-audit.sh` | The resolved 40-char SHA the worktree was checked out at. Stable even if the ref later moves. |
| `audit_kind` | `scripts/time-machine-audit.sh` | Set to `"time-machine"` so downstream tools can filter these passes out of "today's state" rollups. |
| `audit_invoked_at` | `scripts/time-machine-audit.sh` | When the time-machine wrapper started — distinct from `pass_started_at` / `pass_completed_at`, which describe the inner run-pass invocation. |

---

## `spec.json` (Phase 2)

```json
{
  "bead_id": "bd-abc123",
  "extracted_at": "2026-05-05T12:14:33Z",
  "extractor": "subagents/bead-spec-extractor.md",
  "bead_status_at_extraction": "closed",
  "bead_close_reason": "Implemented and tested",
  "bead_closed_at": "2026-04-12T15:33:00Z",
  "bead_type": "feature",
  "bead_priority": 1,
  "checklist": {
    "code_artifacts": [
      {
        "id": "code.parser",
        "description": "Parser module that handles X",
        "source_quote": "from bead description: 'implement parser at src/parser.rs supporting X grammar'",
        "expected_path_hints": ["src/parser.rs", "src/parser/"],
        "weight": 2
      }
    ],
    "tests": {
      "unit": [
        {"id": "tests.unit.parser_basic", "description": "Happy-path parser tests", "weight": 1}
      ],
      "integration": [],
      "fuzz": [
        {
          "id": "tests.fuzz.parser",
          "description": "Fuzz harness for parser, 60s in CI without crashes",
          "duration_seconds": 60,
          "ci_wired": true,
          "no_crashes": true,
          "corpus_min": 10,
          "weight": 2
        }
      ],
      "e2e": [],
      "property": [],
      "metamorphic": [],
      "golden": [],
      "conformance": []
    },
    "documentation": [
      {"id": "docs.readme.parser_section", "description": "README section explaining parser usage"}
    ],
    "migrations": [],
    "feature_flags": [],
    "telemetry": [
      {"id": "telemetry.metric.parse_duration_ms", "description": "Histogram of parse durations"}
    ],
    "ci_workflows": [
      {"id": "ci.fuzz_workflow", "description": "GH Actions workflow that runs fuzz on PR"}
    ],
    "acceptance_criteria": [
      {"id": "ac.1", "verbatim": "Parser handles UTF-8 BOM gracefully"},
      {"id": "ac.2", "verbatim": "Fuzz target runs for 60s in CI without crashes"}
    ],
    "implicit_requirements": [
      {"id": "implicit.feature.happy_path_test", "description": "Implicit: a feature bead needs at least one happy-path test", "added_because": "bead_type=feature"}
    ]
  },
  "constraints": {
    "no_mocks": false,
    "allowed_mocks": [],
    "coverage_minimum_line": 0.8,
    "coverage_minimum_branch": 0.7
  },
  "coverage_gaps": [],
  "extraction_notes": "Bead body was well-structured; ACs explicit; no ambiguity."
}
```

Field notes (matches `scripts/extract-spec.py` output exactly):
- `checklist.tests` is keyed by test type. The deterministic extractor (`scripts/extract-spec.py::TEST_TYPE_KEYWORDS`) recognises 8 types: `unit`, `integration`, `e2e`, `fuzz`, `property`, `metamorphic`, `golden`, `conformance`. `gather-evidence.sh` and `score-bead.py` both iterate this same list — keep them in sync if you add a new type. Each type maps to a (possibly empty) list of items.
- `constraints.no_mocks` and `constraints.allowed_mocks` are always present (defaulting to `false` / `[]`).
- `constraints.coverage_minimum_<kind>` (where `<kind>` is `line` or `branch`) is emitted ONLY when the bead body contains a phrase like "80% line coverage" — absence means "no project-specific constraint, scorer applies the rubric default".
- `performance_budgets` is currently NOT emitted by the deterministic extractor; bead-spec-extractor subagent (LLM-driven) MAY populate it for perf-flavored beads. If absent, the scorer treats the bead as having no project-specific budget.
- `fatal_extraction_error` (string) is emitted by the stub fallback when `show.json` itself fails to parse (per `scripts/extract-spec.py::main`). When present, the bead-level `coverage_gaps` records the exception, downstream phases see an empty checklist, and `score-bead.py::write_fatal_scorecard` short-circuits to a 0-score scorecard with a clear failure marker.

---

## `evidence.json` (Phase 3)

```json
{
  "bead_id": "bd-abc123",
  "gathered_at": "2026-05-05T12:22:11Z",
  "gatherer": "subagents/evidence-gatherer.md",
  "checks": [
    {
      "spec_item_id": "code.parser",
      "status": "FOUND",
      "citations": [
        {
          "path": "src/parser.rs",
          "line_start": 1,
          "line_end": 450,
          "commit_sha": "def5678abc",
          "via": "git log --grep=bd-abc123",
          "snippet_preview": "pub fn parse(input: &str) -> Result<Ast, Err> {"
        }
      ],
      "notes": "Single-file implementation; matches expected_path_hints."
    },
    {
      "spec_item_id": "tests.fuzz.parser",
      "status": "FOUND",
      "citations": [
        {"path": "fuzz/fuzz_targets/parser.rs", "line_start": 1, "line_end": 24, "commit_sha": "def5678abc"},
        {"path": ".github/workflows/fuzz.yml", "line_start": 1, "line_end": 30, "commit_sha": "def5678abc"}
      ],
      "notes": "Fuzz target compiles; CI workflow exists."
    },
    {
      "spec_item_id": "telemetry.metric.parse_duration_ms",
      "status": "MISSING",
      "citations": [],
      "notes": "Searched for `parse_duration_ms` across src/; no emission found."
    }
  ]
}
```

---

## `compliance.json` (Phase 4)

```json
{
  "bead_id": "bd-abc123",
  "executed_at": "2026-05-05T12:35:00Z",
  "executor": "subagents/compliance-verifier.md",
  "host": "ubuntu/x86_64",
  "checks": [
    {
      "spec_item_id": "tests.unit.parser_basic",
      "command": "cargo test --package frankensqlite parser_basic",
      "cwd": "/data/projects/frankensqlite",
      "exit_code": 0,
      "duration_ms": 1234,
      "started_at": "2026-05-05T12:35:00Z",
      "completed_at": "2026-05-05T12:35:01Z",
      "stdout_path": "raw/tests_unit.stdout",
      "stderr_path": "raw/tests_unit.stderr",
      "summary": "test result: ok. 7 passed; 0 failed; 0 ignored",
      "verdict": "PASS"
    },
    {
      "spec_item_id": "tests.fuzz.parser",
      "command": "cargo fuzz run parser -- -max_total_time=60 -runs=0",
      "exit_code": 0,
      "duration_ms": 61234,
      "ran_for_seconds": 61,
      "stdout_path": "raw/fuzz.stdout",
      "stderr_path": "raw/fuzz.stderr",
      "crashes_found": 0,
      "corpus_size_after": 1247,
      "verdict": "PASS"
    },
    {
      "spec_item_id": "ci.fuzz_workflow",
      "command": "cat .github/workflows/fuzz.yml | grep max_total_time",
      "exit_code": 0,
      "summary": "max_total_time=10 (CI workflow runs only 10s, not the bead's required 60s)",
      "verdict": "FAIL",
      "failure_reason": "CI duration mismatch: bead spec requires 60s, workflow has 10s."
    },
    {
      "spec_item_id": "telemetry.metric.parse_duration_ms",
      "command": null,
      "verdict": "MISSING",
      "failure_reason": "Phase 3 marked MISSING; no execution attempted."
    }
  ]
}
```

`verdict` enum: `PASS | FAIL | MISSING | ERROR | TIMEOUT | SKIPPED | UNVERIFIED_INFRA | WAIVED`.

---

## `theater.json` (Phase 5)

```json
{
  "bead_id": "bd-abc123",
  "scanned_at": "2026-05-05T12:40:11Z",
  "scanner": "subagents/theater-detector.md",
  "scanned_files": ["src/parser.rs", "fuzz/fuzz_targets/parser.rs", ".github/workflows/fuzz.yml"],
  "findings": [
    {
      "id": "theater.1",
      "severity": "BLOCKING",
      "category": "stub_in_implementation",
      "pattern": "Default::default\\(\\)",
      "path": "src/parser.rs",
      "line": 312,
      "snippet": "    Err(ParseErr::Recovery) => Ok(Default::default()),",
      "description": "Error-recovery branch returns default value instead of recovering. Bead spec says error-recovery must produce a partial AST.",
      "invalidates_phase4_check": "tests.unit.parser_basic",
      "invalidates_dimension": 1,
      "evidence_link": "evidence.json#code.parser"
    },
    {
      "id": "theater.2",
      "severity": "BLOCKING",
      "category": "unimplemented_macro",
      "path": "fuzz/fuzz_targets/parser.rs",
      "line": 14,
      "snippet": "        _ => unimplemented!(\"multi-byte input\"),",
      "description": "Fuzz target panics on multi-byte input; would never reach the 60s budget on UTF-8 corpus.",
      "invalidates_phase4_check": "tests.fuzz.parser",
      "evidence_link": "evidence.json#tests.fuzz.parser"
    },
    {
      "id": "theater.3",
      "severity": "MINOR",
      "category": "todo_comment",
      "path": "src/parser.rs",
      "line": 87,
      "snippet": "    // TODO: optimize tokenizer",
      "description": "Optimization TODO; not blocking correctness.",
      "invalidates_phase4_check": null
    }
  ],
  "summary": {
    "BLOCKING": 2,
    "MAJOR": 0,
    "MINOR": 1,
    "NOTE": 0
  }
}
```

`severity` enum: `BLOCKING | MAJOR | MINOR | NOTE | ADVISORY` (matches
`scripts/validate-evidence.py::ALLOWED_SEVERITIES`; `ADVISORY` is reserved
for committee-mode 1-of-N findings, see [MULTI-MODEL-COMMITTEE.md](MULTI-MODEL-COMMITTEE.md)).

`pattern` (optional, since v1.1): the literal regex pattern that triggered
the finding, when emitted by `theater-scan.sh`. Subagents may set this to
`null` (the default) when their finding wasn't pattern-matched (e.g.,
LLM-judged contradictions). Downstream tooling can group findings by pattern:
`jq '.findings | group_by(.pattern)'`. Producers SHOULD populate this when
the finding came from a deterministic pattern match so consumers can filter,
allowlist, or graph false-positive rates per detector.

`category` enum (must match what producers actually emit; consumers may rely
on the prefix structure, not just the literal value):

| Category | Emitted by | Severity (typical) |
|----------|-----------|---------------------|
| `unimplemented_macro` | theater-scan.sh | BLOCKING |
| `hardcoded_return` | theater-scan.sh | MAJOR |
| `trivial_assertion` | theater-scan.sh | BLOCKING |
| `skipped_test` | theater-scan.sh | MAJOR |
| `conditional_skip_in_test_mode` | theater-scan.sh | MAJOR |
| `mock_where_forbidden` | theater-scan.sh (only when spec sets `no_mocks`) | BLOCKING |
| `sleep_as_fake_work` | theater-scan.sh (production paths only; v1.1+: requires duration ≥ 1s AND no retry/backoff context) | MAJOR (was BLOCKING in v1.0) |
| `api_501_stub` | theater-scan.sh | MAJOR |
| `todo_comment` | theater-scan.sh | MINOR |
| `anomaly_apologetic_close` | anomaly-scan.sh | MAJOR |
| `anomaly_wip_close_reason` | anomaly-scan.sh | BLOCKING |
| `anomaly_no_git_xref` | anomaly-scan.sh | MAJOR (v1.1+: demoted to NOTE when project-wide git xref coverage <30%; see `git_xref_coverage.json`) |
| `anomaly_empty_diff` | anomaly-scan.sh | MAJOR |
| `anomaly_fast_close` | anomaly-scan.sh (feature/bug/epic only) | MAJOR |
| `anomaly_batch_close` | anomaly-scan.sh | MAJOR |
| `anomaly_ignore_list_growth` | anomaly-scan.sh | BLOCKING |
| `<custom>` | `audit-policy.yaml#project_theater_patterns[].id` (project-specific) | as-defined |

Subagents (`subagents/theater-detector.md`, `subagents/security-auditor.md`,
etc.) MAY introduce new category strings; the scorer and validator only key
on `severity`, so new categories surface in `theater.json` and the scorecard
without code changes. The `anomaly_` prefix is a convention — categories
mined from git/inventory metadata rather than from grepping evidence files —
so consumers can filter on it (e.g. dashboards split anomaly vs. theater
findings into separate panels).

---

## `test_depth.json` (Phase 6)

```json
{
  "bead_id": "bd-abc123",
  "audited_at": "2026-05-05T12:45:00Z",
  "auditor": "subagents/test-depth-auditor.md",
  "checks": [
    {
      "test_type": "unit",
      "depth_metric": "line_coverage",
      "scope_files": ["src/parser.rs"],
      "value": 0.78,
      "threshold": 0.80,
      "verdict": "PARTIAL",
      "raw_path": "raw/coverage.json"
    },
    {
      "test_type": "unit",
      "depth_metric": "branch_coverage",
      "scope_files": ["src/parser.rs"],
      "value": 0.65,
      "threshold": 0.70,
      "verdict": "PARTIAL",
      "raw_path": "raw/coverage.json"
    },
    {
      "test_type": "fuzz",
      "depth_metric": "corpus_size",
      "value": 0,
      "threshold": 50,
      "verdict": "FAIL",
      "notes": "Fuzz corpus directory exists but is empty; never seeded."
    },
    {
      "test_type": "fuzz",
      "depth_metric": "ran_for_stated_duration",
      "value": 61,
      "threshold": 60,
      "verdict": "PASS"
    },
    {
      "test_type": "fuzz",
      "depth_metric": "ci_wired",
      "value": false,
      "threshold": true,
      "verdict": "FAIL",
      "notes": "Workflow exists but max_total_time=10, not 60."
    },
    {
      "test_type": "e2e",
      "depth_metric": "real_service_evidence",
      "value": "n/a",
      "verdict": "WAIVED",
      "notes": "Bead spec did not require e2e."
    }
  ]
}
```

`verdict` enum: `PASS | PARTIAL | FAIL | WAIVED | INFRA_MISSING`.

---

## `scorecard.md` (Phase 8)

Markdown, not JSON. Template in `assets/scorecard-template.md`. Required sections:

1. **Header** — bead id, title, type, priority, claimed status, claimed close reason and date, `closed_by_session` if known, total score, verdict band.
2. **Dimension scores table** — six rows (one per rubric dimension), each with score / max and a one-sentence "why" citing the evidence file. Synthesis findings that touch this bead belong in dimension 6's "why" cell — NOT in a separate "Cross-bead links" section. (`scripts/score-bead.py` and `scripts/master-report.py` both rely on this convention; a separate section would break the master-report's table parser.)
3. **Citations** — explicit paths to spec.json, evidence.json, compliance.json, theater.json, test_depth.json, raw logs.
4. **Missing items (verbatim)** — verbatim list of what's absent (Phase 9 copies this into the remediation bead body — never paraphrase).
5. **Score-trend** — if a prior pass exists, the `**Trend:**` line above the dimension table shows `<prev_score> → <new_score> (Δ <signed-delta>)`.

---

## `synthesis.md` (Phase 7)

Markdown. Sections in `PHASES.md` Phase 7. Every finding cites bead IDs and evidence paths.

---

## `remediation.md` (Phase 9)

```markdown
# Remediation — Pass <UTC>

## Policy: completion-debt (default)

## Actions

| Original bead | Score | Action | New/reopened ID | Status |
|---------------|------:|--------|-----------------|--------|
| bd-abc123     |  612  | Created completion-debt bead | bd-new001 | open, P1, blocks: bd-orig-dependents |
| bd-def456     |  287  | Reopened original (severe theater) | bd-def456 (reopened) | open, P0 |

## Per-action detail

### bd-abc123 → bd-new001

Created via:
\`\`\`
br create --title "[completion-debt] <original title>" \\
  --type task --priority 1 --parent bd-abc123 \\
  --description "<verbatim missing-items list from scorecard>"
\`\`\`

Description (verbatim from `passes/<UTC>/beads/bd-abc123/scorecard.md`):

1. Implement parser error-recovery path (spec: code.error_recovery)
2. Wire fuzz target into CI for 60s (spec: tests.fuzz.duration_seconds:60 + tests.fuzz.ci_wired)
3. ...

Linked dependencies: bd-new001 blocks [list of beads that depended on bd-abc123 doing what it claimed].

## Bead-graph state after remediation

- Closed beads now truthful: N - X (where X is the number we just exposed)
- New open beads: Y (= number of completion-debt beads created)
- Reopened beads: Z
- Total false-closed beads remaining: 0 (or the count for which user explicitly chose "Report only")
```

---

## `convergence.json` (Phase 10)

```json
{
  "computed_at": "2026-05-05T13:42:17Z",
  "current_pass": "2026-05-05T12-00-00Z",
  "prior_pass": "2026-04-28T09-00-00Z",
  "is_converged": false,
  "criteria": {
    "max_score_delta_within_threshold": false,
    "max_score_delta_observed": 47,
    "max_score_delta_bead": "bd-abc123",
    "no_new_false_closed": false,
    "new_false_closed_beads": ["bd-foo", "bd-bar", "bd-baz"],
    "no_new_synthesis_findings": true,
    "new_synthesis_finding_count": 0,
    "rubric_consistency_pass": true,
    "fresh_eyes_review_path": "passes/<UTC>/fresh_eyes_review.json",
    "fresh_eyes_review_reason": null,
    "fresh_eyes_review_is_wrapper_stub": false,
    "all_remediation_beads_exist": true,
    "missing_remediation_beads": []
  },
  "next_pass_tasks": [
    "Re-verify bd-abc123 after the parser error-recovery fix lands",
    "Investigate why bd-foo, bd-bar, bd-baz weren't flagged in prior pass — possible spec extraction miss"
  ],
  "rubric_changed_since_prior_pass": false,
  "rubric_changed_reason": null
}
```

Field notes (matches `scripts/convergence-check.py` output exactly):
- `max_score_delta_within_threshold` is gated by `--threshold` (default 10 pts/pass), NOT a hardcoded 10. The field name reflects "within the configured threshold," not the literal number.
- `fresh_eyes_review_path` / `fresh_eyes_review_reason` come from the Phase-10 fresh-eyes verdict artifact (`fresh_eyes_review.json` or `convergence_review.json`); fail-closed when missing.
- `fresh_eyes_review_is_wrapper_stub` — `true` when the verdict came from `run-pass.sh`'s deterministic stub instead of an actual fresh-eyes subagent run. Convergence is reported but rubric-consistency is unverified — gate on `fresh_eyes_review_is_wrapper_stub == false` for "real" convergence in CI / release-gate logic.
- `rubric_changed_reason` is populated when the prior pass's `manifest.json` was unparseable OR its `rubric_sha256` differs from the current rubric.
