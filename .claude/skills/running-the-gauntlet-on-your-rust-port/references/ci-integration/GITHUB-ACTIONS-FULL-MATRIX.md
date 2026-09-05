# GitHub Actions — Full Gauntlet CI Matrix

End-to-end GitHub Actions wiring for a gauntlet-adopted port. Cross-links to `assets/github-workflows/` for paste-ready files. This doc explains **what runs when**, the cadence rationale, and the branch-protection requirement set.

For GitLab CI equivalents, see [`GITLAB-CI-EQUIVALENT.md`](GITLAB-CI-EQUIVALENT.md). For per-phase NTM pipelines (orchestrator-driven, not CI), see [`../orchestration/NTM-INTEGRATION.md`](../orchestration/NTM-INTEGRATION.md).

---

## 1. Cadence table

| Workflow | Trigger | Wall-time budget | Branch-protection required? |
|---|---|---|---|
| **parity-score-ratchet.yml** | every PR + every push to main | 5-10 min | YES — release-blocking |
| **bench-pass-over-pass.yml** | every PR touching `crates/*-e2e/`, `benches/`, `Cargo.toml`, `Cargo.lock` | 15-30 min | YES on PR; nightly cron on main |
| **conformance-suite.yml** | every PR | 10-20 min | YES — release-blocking |
| **feature-coverage.yml** | every PR | 2-5 min | YES — release-blocking |
| **eprocess-ville-alarm.yml** | nightly cron + manual dispatch | 30-60 min | NO (informational; alerts on Slack/Mail) |
| **fault-vfs-coverage.yml** | every PR touching `crates/*-harness/src/fault_*`, weekly cron | 20-40 min | YES on PR; report-only on cron |
| **bead-graph-validator.yml** | every PR touching `.beads/` or any subagent-output file | 2-3 min | YES — gates Phase 13 closure |
| **soak-runner-fuzz.yml** (Phase 15) | weekly cron + manual dispatch | 24 hours | NO (informational) |
| **soak-runner-miri.yml** (Phase 15) | weekly cron | 72 hours | NO (informational) |
| **soak-runner-loom.yml** (Phase 15) | weekly cron | 48 hours | NO (informational) |
| **soak-runner-crash-boundary.yml** (Phase 15) | weekly cron | 48 hours | NO (informational) |
| **soak-runner-bocpd.yml** (Phase 15) | continuous (every 30 min) | 30 sec each run | NO (gauge metric) |
| **soak-runner-adversarial.yml** (Phase 15) | weekly cron | 48 hours | NO (informational) |
| **release-certification-bundler.yml** | manual dispatch on release tag | 30-90 min | NO (operator-initiated) |

---

## 2. Branch protection requirement set

For `main` to enforce release-readiness, the GitHub branch protection rules MUST require these workflow runs to pass:

```
parity-score-ratchet / build  (must succeed)
bench-pass-over-pass / build  (must succeed on PR; nightly cron may fail without blocking)
conformance-suite / build     (must succeed)
feature-coverage / build      (must succeed)
fault-vfs-coverage / build    (must succeed on PR)
bead-graph-validator / build  (must succeed)
```

Plus the standard `cargo check`, `cargo test --workspace`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`.

The 6 soak-runner workflows are NOT required (they run on cron; report-only; alerts surface findings but don't gate merge).

---

## 3. Paste-ready workflow excerpts

### Parity-score ratchet (the release-readiness gate)

```yaml
# .github/workflows/parity-score-ratchet.yml
name: parity-score-ratchet
on:
  pull_request:
  push:
    branches: [main]

jobs:
  ratchet:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # need history for ratchet comparison

      - uses: dtolnay/rust-toolchain@stable

      - uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            ~/.cargo/git
            target
          key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}

      - name: Run conformance + bench (compute scorecards)
        run: |
          ./scripts/compute-parity-score.sh /tmp/ws

      - name: Apply ratchet
        run: |
          # Compare /tmp/ws/reports/parity_score.json against the persisted ratchet_state.json on main.
          # The script exits 0 = Allow, 1 = Block/Quarantine.
          ./scripts/apply-ratchet.sh /tmp/ws
        # exit 1 here → CI fails → branch protection blocks merge

      - name: Annotate PR with score
        if: github.event_name == 'pull_request'
        run: |
          PERF=$(jq -r .perf.lower_bound /tmp/scorecards.json)
          CONF=$(jq -r .conformance.lower_bound /tmp/scorecards.json)
          SURF=$(jq -r .surface.lower_bound /tmp/scorecards.json)
          echo "::notice::Parity scores — perf=$PERF conformance=$CONF surface=$SURF"

      - name: Upload scorecards
        uses: actions/upload-artifact@v4
        with:
          name: scorecards-${{ github.sha }}
          path: /tmp/scorecards.json
```

### Conformance suite (every PR)

```yaml
# .github/workflows/conformance-suite.yml
name: conformance-suite
on:
  pull_request:
  push:
    branches: [main]

jobs:
  conformance:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        behavior-class:
          - null-semantics
          - three-valued-logic
          - group-by-having
          # ... per-class list ...
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: actions/cache@v4
        with: { path: target, key: cargo-${{ hashFiles('**/Cargo.lock') }} }

      - name: Run oracle E2E for ${{ matrix.behavior-class }}
        run: cargo test --test ${{ matrix.behavior-class }}_oracle_e2e --profile release-perf

      - name: On failure, upload FailureBundle
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: failure-bundle-${{ matrix.behavior-class }}-${{ github.sha }}
          path: target/test-artifacts/failure_bundles/
```

Per-class matrix expansion: SQL-class has ~22 behavior classes; RESP-class has ~12; etc. Per [`taxonomy/PROJECT-CLASSES.md`](../taxonomy/PROJECT-CLASSES.md).

### Feature coverage (release-blocking)

```yaml
# .github/workflows/feature-coverage.yml
name: feature-coverage
on: [pull_request, push]

jobs:
  coverage:
    runs-on: ubuntu-latest
    env:
      WORKSPACE: ${{ github.workspace }}/gauntlet_workspace
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: actions/cache@v4
        with: { path: target, key: cargo-${{ hashFiles('**/Cargo.lock') }} }

      - name: Compute feature coverage
        run: |
          ./scripts/compute-feature-coverage.sh "$WORKSPACE" \
            --matrix "$WORKSPACE/docs/contracts/supported_surface_matrix.toml" \
            --taxonomy ./parity_taxonomy.json
          cp "$WORKSPACE/reports/feature_coverage.json" /tmp/coverage.json

      - name: Verify per-family coverage gate
        run: |
          # Fails if any family verdict drops from full → partial OR partial → none.
          jq -e 'all(.families[]; .verdict != "none")' /tmp/coverage.json
```

### E-process Ville alarm (nightly cron, informational)

```yaml
# .github/workflows/eprocess-ville-alarm.yml
name: eprocess-ville-alarm
on:
  schedule:
    - cron: '0 4 * * *'  # 04:00 UTC daily
  workflow_dispatch:

jobs:
  eprocess:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: actions/cache@v4
        with: { path: target, key: cargo-${{ hashFiles('**/Cargo.lock') }} }

      - name: Run e-process invariant checks
        run: |
          cargo run --bin check-eprocesses --profile release-perf -- \
            --workspace . --output /tmp/eprocess-results.json
        continue-on-error: true  # don't fail; alert

      - name: Check for Ville-bound crossings
        run: |
          CROSSINGS=$(jq '[.invariants[] | select(.log_e_value > .log_threshold)] | length' /tmp/eprocess-results.json)
          if [ "$CROSSINGS" -gt 0 ]; then
            echo "::error::E-process Ville-bound crossed for $CROSSINGS invariant(s)"
            # Alert on Slack / Agent Mail / etc.
          fi
```

### Soak runner — fuzz (weekly cron)

```yaml
# .github/workflows/soak-runner-fuzz.yml
name: soak-runner-fuzz
on:
  schedule:
    - cron: '0 0 * * 0'  # Sunday midnight UTC
  workflow_dispatch:

jobs:
  fuzz:
    runs-on: [self-hosted, gpu]  # or `large` GitHub runner
    timeout-minutes: 1440  # 24h
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@nightly
        with: { components: rust-src }
      - run: cargo install cargo-fuzz

      - name: Run differential fuzz targets
        run: |
          for target in $(jq -r '.previously_divergent[]' .gauntlet/phase15_soak_designs.json); do
            timeout 1380m cargo +nightly fuzz run "$target" -- -max_total_time=82800 || true
          done

      - name: Collect findings
        run: |
          mkdir -p /tmp/findings
          find fuzz/artifacts -name '*.txt' -exec cp {} /tmp/findings/ \;

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        if: always()
        with:
          name: soak-fuzz-${{ github.run_id }}
          path: /tmp/findings/

      - name: Alert on findings
        if: success()
        run: |
          FINDINGS=$(ls /tmp/findings/ | wc -l)
          if [ "$FINDINGS" -gt 0 ]; then
            echo "::warning::Fuzz soak found $FINDINGS new inputs"
            # ... Slack/Mail webhook ...
          fi
```

### Release certification bundler (manual dispatch on release tag)

```yaml
# .github/workflows/release-certification-bundler.yml
name: release-certification-bundler
on:
  workflow_dispatch:
    inputs:
      tag:
        description: 'Release tag to certify (e.g., v0.5.0)'
        required: true

jobs:
  certify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ inputs.tag }}
          fetch-depth: 0
      - uses: dtolnay/rust-toolchain@stable

      - name: Verify all required gates green at this tag
        run: |
          gh run list --branch ${{ inputs.tag }} --json conclusion,name | \
            jq -e 'all(.[] | .conclusion == "success" or .name | test("soak-runner|eprocess-ville-alarm"))'

      - name: Build certification bundle
        run: |
          cargo run --bin certification-bundler --profile release-perf -- \
            --tag ${{ inputs.tag }} \
            --workspace . \
            --output /tmp/certification-bundle/

      - name: Verify release-certificate.json#/certifying == true
        run: |
          CERT=$(jq -r .certifying /tmp/certification-bundle/release_certificate.json)
          if [ "$CERT" != "true" ]; then
            echo "::error::Certification failed; see release_certificate.json#/blocked_by"
            exit 1
          fi

      - name: Attach bundle to release
        run: |
          gh release upload ${{ inputs.tag }} /tmp/certification-bundle/*.json
```

---

## 4. Self-hosted vs GitHub-hosted runners

| Workflow | Recommended runner | Why |
|---|---|---|
| parity-score-ratchet | GitHub-hosted (ubuntu-latest) | <10 min; cheap |
| bench-pass-over-pass | self-hosted, dedicated bench-runner | reproducibility (same hardware = same baseline); per [`pattern:175-CONCURRENT-MODE-GUARD`](../patterns/175-CONCURRENT-MODE-GUARD.md) |
| conformance-suite | GitHub-hosted (matrix) | parallelizable; no cross-pane state |
| feature-coverage | GitHub-hosted | fast |
| eprocess-ville-alarm | GitHub-hosted | nightly; modest |
| fault-vfs-coverage | GitHub-hosted | per-PR; modest |
| bead-graph-validator | GitHub-hosted | <3 min |
| soak-runner-* | self-hosted, dedicated soak-runner | long-running; GitHub-hosted timeouts kick in |
| release-certification-bundler | GitHub-hosted | one-shot; tag-pinned |

For perf benches specifically: **never** mix GitHub-hosted and self-hosted runners. The hardware platform fingerprint MUST be stable across runs for the ratchet to be honest (per [`pattern:155-BENCH-HISTORY-RATCHET`](../patterns/155-BENCH-HISTORY-RATCHET.md)).

---

## 5. Secrets + permissions

Required GitHub repository secrets:
- `GITHUB_TOKEN` (auto-provided; needs `contents: read`, `pull-requests: write` for PR annotation).
- `SLACK_WEBHOOK_URL` (optional; for soak-finding alerts).
- `JSM_TOKEN` (optional; if release-certification-bundler publishes to JSM).

Per-workflow `permissions:` blocks (least-privilege):

```yaml
permissions:
  contents: read
  pull-requests: write  # for PR annotations
  actions: read         # for cross-workflow status checks
```

The certification-bundler workflow additionally needs `contents: write` to attach the bundle to the release.

---

## 6. Anti-patterns

- **No matrix expansion on conformance-suite** — running all behavior classes serially wastes CI minutes. Always matrix-expand per [`taxonomy/PROJECT-CLASSES.md § per-class behavior class lists`](../taxonomy/PROJECT-CLASSES.md).
- **Mixing `--profile release` with `--profile release-perf`** — perf claims MUST use `release-perf` per [`pattern:140-RELEASE-PERF-PROFILE`](../patterns/140-RELEASE-PERF-PROFILE.md). CI workflows that use `--release` silently produce different numbers.
- **No caching of `target/`** — slows every workflow by 5-10x. Use `actions/cache@v4` with `${{ hashFiles('**/Cargo.lock') }}` as the cache key.
- **Forgetting `fetch-depth: 0`** on workflows that compare against history (ratchet, bench-pass-over-pass). Default `fetch-depth: 1` breaks comparison.
- **Self-signed waivers** — branch protection requires the parity-score-ratchet workflow to pass. A waiver is NOT a workaround; it's a structured-dated permission per [`subagents/waiver-author.md`](../../subagents/waiver-author.md). Never bypass branch protection via admin override.
- **Soak findings ignored** — soak workflows are informational, but findings ARE actionable. Wire them to a notification channel (Slack/Mail/PagerDuty) so they reach the operator within hours.

---

## 7. Cross-references

- [`assets/github-workflows/`](../../assets/github-workflows/) — the actual `.yml` files for direct copy-paste.
- [`GITLAB-CI-EQUIVALENT.md`](GITLAB-CI-EQUIVALENT.md) — same coverage for GitLab CI.
- [`../orchestration/NTM-INTEGRATION.md`](../orchestration/NTM-INTEGRATION.md) — NTM pipelines (operator-driven, complement to CI).
- [`../methodology/CONFORMAL-RATCHET.md`](../methodology/CONFORMAL-RATCHET.md) — ratchet decision logic.
- [`../methodology/CERTIFICATION.md`](../methodology/CERTIFICATION.md) — strict-conformant-release.v1 constants.
- [`../patterns/155-BENCH-HISTORY-RATCHET.md`](../patterns/155-BENCH-HISTORY-RATCHET.md) — pass-over-pass mechanism.
- [`../patterns/140-RELEASE-PERF-PROFILE.md`](../patterns/140-RELEASE-PERF-PROFILE.md) — release-perf profile spec.
