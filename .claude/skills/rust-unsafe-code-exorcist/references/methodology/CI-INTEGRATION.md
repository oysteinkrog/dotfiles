# CI-INTEGRATION.md — Auditor-in-CI

The skill's adoption pathway. A GitHub Actions workflow (or equivalent on GitLab / CircleCI / Buildkite / Jenkins) that runs the audit's core checks on every PR.

The result: soundness drift is gated by CI. New unsafe sites can't sneak in. Geiger counts can't regress silently. The audit's standards are enforced by default.

---

## What CI runs

The integration runs THREE classes of check on each PR:

### 1. Drift detection (mandatory)

```yaml
- name: Enumerate unsafe (PR head)
  run: |
    PR_AUDIT="$PWD/.unsafe-audit-ci-pr"
    ./skills/rust-unsafe-code-exorcist/scripts/enumerate-unsafe.sh "$PWD" "$PR_AUDIT"
    node ./skills/rust-unsafe-code-exorcist/scripts/generate-inventory.mjs "$PR_AUDIT"

- name: Enumerate unsafe (main baseline)
  uses: actions/checkout@v4
  with:
    ref: ${{ github.event.repository.default_branch }}
    path: main-checkout

- name: Generate main baseline inventory
  run: |
    MAIN_CHECKOUT="$PWD/main-checkout"
    MAIN_AUDIT="$MAIN_CHECKOUT/.unsafe-audit-ci-main"
    ./skills/rust-unsafe-code-exorcist/scripts/enumerate-unsafe.sh "$MAIN_CHECKOUT" "$MAIN_AUDIT"
    node ./skills/rust-unsafe-code-exorcist/scripts/generate-inventory.mjs "$MAIN_AUDIT"

- name: Diff
  run: |
    PR_AUDIT="$PWD/.unsafe-audit-ci-pr"
    MAIN_AUDIT="$PWD/main-checkout/.unsafe-audit-ci-main"
    diff <(jq -s -S 'sort_by(.id) | .[] | {crate, file, line_start, kind}' "$MAIN_AUDIT/unsafe-inventory.jsonl") \
         <(jq -s -S 'sort_by(.id) | .[] | {crate, file, line_start, kind}' "$PR_AUDIT/unsafe-inventory.jsonl") \
         > "$PR_AUDIT/drift.diff" || true
    cat "$PR_AUDIT/drift.diff"
```

If the PR adds new unsafe sites, the workflow can:
- Comment on the PR with the new sites.
- Fail (if `fail_on_new_unsafe_without_safety_comment = true` in continuous-mode.toml).
- Pass (warn only).

### 2. Verify.sh (full harness)

```yaml
- name: Run verify.sh
  run: |
    PR_AUDIT="${PR_AUDIT:-$PWD/.unsafe-audit-ci-pr}"
    ./skills/rust-unsafe-code-exorcist/scripts/verify.sh "$PR_AUDIT" "$PWD"
```

This runs miri / careful / loom / fuzz / mutants / geiger. Takes 5-30 minutes depending on project size. Configured to run on relevant PRs (e.g., changes to source code, not just docs).

### 3. Geiger regression check

```yaml
- name: Compare geiger counts
  run: |
    PR_AUDIT="${PR_AUDIT:-$PWD/.unsafe-audit-ci-pr}"
    MAIN_AUDIT="${MAIN_AUDIT:-/tmp/main/.unsafe-audit-ci-main}"
    sum_geiger_dir() {
      local dir="$1" sum=0 part found=0
      for f in "$dir"/phase1/*__geiger.json; do
        [ -f "$f" ] || continue
        found=1
        part=$(jq '[.packages[]?.package.metrics.counters | objects | .[] | numbers] | add // 0' "$f")
        case "$part" in ''|null) part=0 ;; esac
        sum=$((sum + part))
      done
      if [ "$found" -eq 0 ]; then
        echo "::error::no cargo-geiger files under $dir/phase1" >&2
        return 1
      fi
      echo "$sum"
    }
    PR_COUNT=$(sum_geiger_dir "$PR_AUDIT")
    MAIN_COUNT=$(sum_geiger_dir "$MAIN_AUDIT")
    if [ "$PR_COUNT" -gt "$MAIN_COUNT" ]; then
      echo "::error::geiger regression: $MAIN_COUNT → $PR_COUNT"
      exit 1
    fi
```

A geiger increase requires explicit `[OPT-IN]` label on the PR.

---

## Full workflow template

See [assets/gh-actions-auditor.yml.template](../../assets/gh-actions-auditor.yml.template). Copy to `<project>/.github/workflows/soundness.yml`.

The template has the following jobs:

| Job | When | Time | Required for merge? |
|-----|------|------|---------------------|
| `feature-matrix` | every PR | ~5 min | yes |
| `miri` | every PR | ~10-30 min | yes |
| `careful` | every PR | ~5 min | yes |
| `loom` | every PR (if applicable) | ~5 min | yes |
| `fuzz-smoke` | every PR | ~5 min | yes |
| `mutants` | weekly | ~30-90 min | no (advisory) |
| `geiger-delta` | every PR | ~2 min | YES if `fail_on_geiger_regression` |
| `drift-report` | every PR | ~2 min | NO (PR comment only) |
| `soundness-gate` | every PR | ~30 sec | YES — meta-job that gates merge |

---

## Auto-classifier for new sites

When the PR adds new unsafe, CI can auto-classify (best-effort) and post a PR comment:

```
🤖 Auditor-bot:
Found 2 new unsafe sites in this PR:

| File | Line | Kind | Heuristic class | Risk score |
|------|------|------|-----------------|------------|
| src/foo.rs | 142 | block | (C) [tentative] | 12 |
| src/bar.rs | 89 | unsafe_impl | (A) [needs hardening] | 4 |

Tentative classifications are based on heuristics. Confirm by running:

    /skills/rust-unsafe-code-exorcist/scripts/classify-new.sh --base "$BASE_REF"
```

The auto-classifier is a diff-only CI guard. It uses the same risk dimensions as
`compute-risk-score.mjs` (blast, likelihood, discoverability) plus operator-like
heuristics for tentative bucket assignment. Treat its output as a PR comment,
not as a replacement for Phase 1-4 classification.

---

## PR labels

The workflow respects PR labels for nuanced gating:

- `soundness:opt-in-new-unsafe` — author has authorized new unsafe; skip the new-site gate. Required for new (B) feature-flag sites.
- `soundness:opt-in-geiger-up` — author has authorized geiger increase; skip the geiger gate.
- `soundness:hardening-only` — this PR only changes SAFETY comments + clippy lints; skip the test suite for speed.
- `soundness:expansion-of-surface` — this PR intentionally expands the soundness surface; skip the surface-expanded gate.

Labels can be set by the PR author OR by maintainers via review.

---

## Required vs informational checks

The workflow distinguishes:

- **Required.** Must pass for merge. (Geiger regression, miri, etc.)
- **Advisory.** Comment-only; don't block. (Mutants coverage, drift heuristic classifications.)

The user configures via `continuous-mode.toml § continuous.gates`. The skill ships defaults that are strict but reasonable.

---

## Caching

CI runs are expensive. The workflow caches:

- `~/.cargo` — for Rust deps.
- `target/` — for incremental compilation.
- `~/.cache/miri/<host>-...` — miri's sysroot (large; rebuild slow).
- `<audit-dir>/baseline/` — read-only; only updated on main.

```yaml
- uses: actions/cache@v4
  with:
    path: |
      ~/.cargo/registry
      ~/.cargo/git
      target
      ~/.cache/miri
    key: ${{ runner.os }}-${{ steps.toolchain.outputs.cachekey }}-${{ hashFiles('**/Cargo.lock') }}
```

The cache hit rate determines whether CI takes 5 minutes or 30 minutes.

---

## Adoption sequence

For a project rolling out the integration:

### Day 1 — read-only mode

```toml
[continuous.gates]
fail_on_geiger_regression = false   # warn only
fail_on_new_unsafe_without_safety_comment = false
```

Workflow runs, comments on PRs, but doesn't gate merge. Lets the team see what the gates WOULD say.

### Week 1-2 — observation

Read the workflow comments on a handful of PRs. Are the gates triggering on real issues, or on false positives? If false positives, refine the heuristic (e.g., the auto-classifier).

### Week 3+ — enable gating

```toml
[continuous.gates]
fail_on_geiger_regression = true
fail_on_new_unsafe_without_safety_comment = true
```

Gates start blocking. The team adjusts to the discipline.

---

## What CI is NOT

- **Not a replacement for the periodic full audit.** CI catches drift; the periodic audit revisits classifications + addresses accumulated debt.
- **Not a substitute for human review.** CI gates the FORM; humans gate the SUBSTANCE.
- **Not perfect.** A determined contributor can `[OPT-IN]` past the gates. The skill makes drift VISIBLE, not impossible.

---

## Other CI hosts

The template is GitHub Actions, but the audit's commands are portable:

| Host | Adaptation |
|------|------------|
| GitLab CI | `.gitlab-ci.yml` template; `before_script` + `script` blocks |
| CircleCI | `.circleci/config.yml`; `jobs` + `workflows` |
| Buildkite | `.buildkite/pipeline.yml`; `steps` |
| Jenkins | `Jenkinsfile`; `stages` blocks |
| Local-only (no CI) | Use `pre-commit` hooks via [cc-hooks](../../../cc-hooks/SKILL.md) |

Same scripts; different orchestration shell.

---

## Acceptance signal

The CI integration is healthy when:

1. Every PR runs the soundness workflow.
2. The required gates are active (per `continuous-mode.toml`).
3. PR comments include the drift summary + heuristic classifications.
4. Failed gates have clear messages (so the contributor knows what to fix).
5. Cache hit rate keeps CI runtime acceptable (~5-15 min).
6. False-positive rate on gates is < 5% (otherwise contributors lose trust).

The integration makes the audit's standards LIVED, not aspirational.
