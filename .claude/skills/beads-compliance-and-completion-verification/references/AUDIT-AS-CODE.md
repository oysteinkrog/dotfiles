# AUDIT-AS-CODE.md — The Rubric DSL

<!-- TOC: Why a DSL | The rubric.md frontmatter schema | Custom check pipelines | Custom theater patterns | Custom severity weights | Per-bead-type overrides | Per-label overrides | Worked examples -->

> The rubric is a *declarative* spec for how the audit scores. Project-specific tunings live in `rubric.md` frontmatter as YAML. This file is the schema reference.

---

## Why a DSL

Without a declarative rubric:
- Tunings live in scorer subagent prompts (hard to version, easy to drift).
- Each project re-implements scoring logic in code (impossible to reuse).
- Convergence semantics break because two scorers can apply "the same" rubric differently.

With a declarative rubric:
- Every project has its own `rubric.md` with explicit knobs.
- Convergence-check.py compares `rubric_sha256` to detect drift.
- The rubric is auditable evidence ("we used these weights for SOC2").
- New patterns slot in without code changes.

---

## The schema

```yaml
---
# Required: identity
rubric_version: 1.0.0           # semver; bump on any tuning
score_threshold: 700            # below = false-closed

# Optional: convergence
delta_threshold_for_convergence: 10       # ±10 score points
allow_new_false_closed: 0
spot_check_count: 5
spot_check_max_deviation: 50

# Optional: coverage thresholds (used by Phase 6 ◐ MEASURE)
coverage_minimum_line: 0.80
coverage_minimum_branch: 0.70

# Optional: dimension weights (default 300/250/150/150/100/50)
dimension_weights:
  implementation: 300
  tests: 250
  anti_theater: 150
  test_depth: 150
  docs_etc: 100
  cross_bead: 50

# Optional: per-bead-type weight overrides
type_weights:
  bug:
    implementation: 200
    tests: 350
  epic:
    implementation: 100
    tests: 100
    anti_theater: 100
    test_depth: 100
    docs_etc: 100
    cross_bead: 500
  docs:
    implementation: 50
    tests: 50
    anti_theater: 50
    test_depth: 50
    docs_etc: 750
    cross_bead: 50

# Optional: per-label threshold overrides (Release-Gating use case)
label_thresholds:
  security: 800       # security beads need higher confidence
  hipaa: 850
  pci: 800
  release-v1.5: 800   # release-milestone beads
  experimental: 600   # research beads relaxed

# Optional: project-specific theater patterns (CASS-mined or post-mortem-derived)
project_specific_patterns:
  - name: hedge_close_reason
    severity: MAJOR
    detection: 'rg -i "(for now|will follow up|first pass)" <close_reason>'
    description: "Apologetic close reason; closer self-disclosed incompleteness"
    rubric_dimension: anti_theater
    penalty: 25

  - name: tokio_sleep_in_prod
    severity: BLOCKING
    detection: 'rg "tokio::time::sleep" src/ --type rust'
    description: "Production code sleeps to simulate work"
    rubric_dimension: implementation
    penalty: 100

# Optional: allowed-mocks (project-wide)
allowed_mocks:
  - service: email-provider
    rationale: "Email tests don't need real SMTP — Stripe webhook tests do"
  - service: third-party-search-api
    rationale: "External API has no sandbox; fixture is canonical"

# Optional: closer-defense settings
closer_defense:
  enabled: false      # default false; opt-in for projects with active humans
  window_hours: 24
  notify_via: agent-mail

# Optional: scoring mode (deterministic | bayesian)
scoring_mode: deterministic     # default; switch to bayesian for high-stakes

# Optional: cost optimization
caching:
  re_verification_diff_aware: true     # only re-execute changed beads
  prompt_cache_breakpoints: true        # use Anthropic prompt cache for SKILL.md
  global_coverage_per_pass: true        # coverage tool runs once, filtered per bead

# Optional: integration with bead-author-feedback
author_feedback:
  on_create: false      # auto-review every new bead's spec
  on_close: true        # review at close time

# Optional: tunings audit log (free-form append-only)
tunings:
  - date: 2026-04-15
    field: type_weights.bug.tests
    old: 250
    new: 350
    reason: "Post-mortem CSRF: bug regression tests need higher weight"
    rubric_version: 1.0.0 → 1.0.1

# Optional: rubric change history
rubric_change_history:
  - date: 2026-04-15
    version: 1.0.0 → 1.0.1
    summary: "Added pattern non_constant_time_secret_compare; bumped bug.tests weight"
---

# Project-Specific Rubric — <project>

(Body — same content as the default rubric template, then any project-specific notes)
```

---

## Custom check pipelines

For projects with bespoke verification needs, define check pipelines that the compliance-verifier subagent invokes:

```yaml
custom_pipelines:
  - name: "frankensqlite_concurrency_test"
    triggers:
      - bead_label: concurrency
      - bead_type: bug
    steps:
      - command: "cargo test --release --features=loom"
        timeout: 120
        verdict_field: loom_test
      - command: "cargo test concurrency::"
        timeout: 60
        verdict_field: concurrency_test
    pass_condition: "loom_test == PASS AND concurrency_test == PASS"
```

The compliance-verifier subagent reads this and runs each step, recording verdicts in `compliance.json#custom_pipelines`.

---

## Custom severity weights

Override the default theater penalties (per `RUBRIC.md`):

```yaml
theater_penalties:
  BLOCKING: 75    # default 50; tighter for security-critical projects
  MAJOR: 25       # default 15
  MINOR: 5        # default 3
  NOTE: 0         # always 0
```

Convergence checks treat any change here as a rubric drift; bump `rubric_version`.

---

## Per-label thresholds

A bead with multiple labels picks the **highest** threshold from any matching label override:

```yaml
label_thresholds:
  security: 800
  pci: 800
  experimental: 600
```

A bead labeled `security,experimental`: threshold = max(800, 600) = 800. Conservative-by-default.

---

## Worked examples

### Example 1 — A SaaS project tightening security

```yaml
---
rubric_version: 2.0.0
score_threshold: 700
label_thresholds:
  security: 850
  auth: 850
  rbac: 850
project_specific_patterns:
  - name: non_constant_time_compare
    severity: BLOCKING
    detection: 'rg -n "==" src/auth/ | rg -v "(==.+null|==.+0)"'
    description: "Use constant-time comparison for secrets"
    rubric_dimension: anti_theater
    penalty: 100
  - name: hardcoded_role_check
    severity: BLOCKING
    detection: 'rg -n "user.is_admin" src/api/ | rg -v "// SAFE:"'
    description: "Inline admin check; should use centralized authorization middleware"
---
```

Effect: security beads need 850/1000; non-constant-time compare = BLOCKING auto-detected.

### Example 2 — A research project relaxing thresholds

```yaml
---
rubric_version: 1.0.0
score_threshold: 600     # relaxed (research code)
label_thresholds:
  experimental: 500
  spike: 400
type_weights:
  task:
    implementation: 200
    tests: 100
    docs_etc: 400        # research projects value documentation more
    test_depth: 100
caching:
  re_verification_diff_aware: true
---
```

Effect: research project audits with relaxed bar; documentation weighted heavily.

### Example 3 — A library project shipping to crates.io

```yaml
---
rubric_version: 1.0.0
score_threshold: 800     # tight (it's a library; downstream consumers rely on it)
type_weights:
  feature:
    implementation: 300
    tests: 300            # tests weighted equal to impl
    test_depth: 200       # depth weighted higher (library API surface)
    docs_etc: 100         # docs critical for libraries
project_specific_patterns:
  - name: missing_changelog_entry
    severity: MAJOR
    detection: 'git log --grep=<bead-id> -- CHANGELOG.md | wc -l | grep ^0$'
    description: "Library bead closed without CHANGELOG update"
    rubric_dimension: docs_etc
    penalty: 50
---
```

---

## Validation: rubric.md schema check

`scripts/validate-rubric.py` (sketch — to add):

```bash
python3 scripts/validate-rubric.py <audit-dir>/rubric.md
# Verifies:
# - rubric_version is semver
# - dimension_weights sum to 1000 (or use defaults)
# - thresholds in [0, 1000]
# - severity penalties non-negative
# - project_specific_patterns reference valid rubric_dimension
# - tunings entries trace to rubric_change_history
```

The validator is invoked at bootstrap. A malformed rubric blocks the audit.

---

## Migration between rubric versions

When upgrading rubric (1.0 → 2.0):

1. **Run final pass on 1.0** to capture state.
2. **Bump rubric_version** in rubric.md to 2.0.
3. **Document changes** in `rubric_change_history`.
4. **Run pass on 2.0** — `convergence-check.py` flags rubric_changed.
5. **Trends.md note** the rubric boundary visually.

The audit dir's history shows both:
- `passes/<UTC1>/` — last 1.0 pass.
- `passes/<UTC2>/` — first 2.0 pass.

Score deltas across the 1.0/2.0 boundary are *expected* and not regressions.

---

## Anti-patterns

- Tuning the rubric mid-pass (use `☖ STAKE-RUBRIC` operator).
- Lowering thresholds to "make the audit converge faster" (defeats the audit's purpose).
- Encoding project-specific patterns in scorer subagent prompts instead of rubric.md (loses versioning).
- Forgetting to bump `rubric_version` after any change (breaks convergence-check).
- Using untyped strings for severities (always uppercase: BLOCKING, MAJOR, MINOR, NOTE).

---

## Future: rubric inheritance

Eventually, rubrics could inherit from a base template:

```yaml
extends: ~/.claude/skills/.../assets/rubric-templates/saas-strict.md
overrides:
  score_threshold: 750     # tighten beyond the saas-strict default
```

Not yet implemented. For now, projects copy `assets/rubric-template.md` and edit in-place. Pull requests for templates welcome.