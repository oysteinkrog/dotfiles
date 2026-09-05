# GitLab CI — Gauntlet CI Equivalent

Same coverage as [`GITHUB-ACTIONS-FULL-MATRIX.md`](GITHUB-ACTIONS-FULL-MATRIX.md) but expressed as `.gitlab-ci.yml`. Use this if your project lives on GitLab; the underlying scripts (`scripts/apply-ratchet.sh`, `scripts/compute-parity-score.sh`, etc.) are CI-system-agnostic.

For GitHub Actions equivalents, see [`GITHUB-ACTIONS-FULL-MATRIX.md`](GITHUB-ACTIONS-FULL-MATRIX.md). For NTM pipelines (operator-driven, not CI), see [`../orchestration/NTM-INTEGRATION.md`](../orchestration/NTM-INTEGRATION.md).

---

## 1. Cadence + branch protection (identical to GitHub Actions doc)

See [`GITHUB-ACTIONS-FULL-MATRIX.md § 1`](GITHUB-ACTIONS-FULL-MATRIX.md) for the cadence table. GitLab's equivalent of GitHub's "required status checks" is `rules:` + protected branches; same effect, different syntax.

---

## 2. Paste-ready `.gitlab-ci.yml` excerpt (the full matrix)

```yaml
# .gitlab-ci.yml
stages:
  - check
  - test
  - parity
  - soak
  - certify

variables:
  CARGO_HOME: ${CI_PROJECT_DIR}/.cargo
  CARGO_TARGET_DIR: ${CI_PROJECT_DIR}/target
  GAUNTLET_WORKSPACE: ${CI_PROJECT_DIR}/gauntlet_workspace
  RUST_BACKTRACE: 1

default:
  image: rust:1.85
  cache:
    key:
      files:
        - Cargo.lock
    paths:
      - .cargo/
      - target/

# ----------------------------------------------------------------------------
# Stage: check (static gates)
# ----------------------------------------------------------------------------

cargo-check:
  stage: check
  script:
    - cargo check --all-targets --profile release-perf

cargo-fmt:
  stage: check
  script:
    - rustup component add rustfmt
    - cargo fmt --check

cargo-clippy:
  stage: check
  script:
    - rustup component add clippy
    - cargo clippy --all-targets -- -D warnings

# ----------------------------------------------------------------------------
# Stage: test (unit + conformance matrix)
# ----------------------------------------------------------------------------

cargo-test:
  stage: test
  script:
    - cargo test --workspace --profile release-perf
  needs: [cargo-check]

conformance-suite:
  stage: test
  parallel:
    matrix:
      - BEHAVIOR_CLASS:
        - null-semantics
        - three-valued-logic
        - group-by-having
        - recursive-cte
        - join-type-semantics
        - trigger-semantics
        - window-function
        # ... per-class list per taxonomy/PROJECT-CLASSES.md ...
  script:
    - cargo test --test ${BEHAVIOR_CLASS}_oracle_e2e --profile release-perf
  artifacts:
    when: on_failure
    paths:
      - target/test-artifacts/failure_bundles/
    expire_in: 30 days
  needs: [cargo-check]

# ----------------------------------------------------------------------------
# Stage: parity (the release-readiness gates)
# ----------------------------------------------------------------------------

parity-score-ratchet:
  stage: parity
  script:
    - ./scripts/compute-parity-score.sh /tmp/ws
    # apply-ratchet.sh exits 0=Allow, 1=Block/Quarantine
    - ./scripts/apply-ratchet.sh /tmp/ws
  artifacts:
    paths:
      - /tmp/ws/reports/parity_score.json
      - /tmp/ws/reports/ratchet_decision.json
    expire_in: 90 days
    reports:
      junit: /tmp/scorecards.junit.xml  # if cargo-junit-test wrapper used
  needs: [conformance-suite, cargo-test]
  rules:
    # Block merge if ratchet fails (regression detected)
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

bench-pass-over-pass:
  stage: parity
  image: rust:1.85
  tags: [bench-runner]  # self-hosted; SAME hardware as previous baseline
  variables:
    PROFILE: release-perf
  script:
    - ./scripts/run-bench-matrix.sh . "${GAUNTLET_WORKSPACE}"
    # Compare against ${GAUNTLET_WORKSPACE}/.bench-history/comprehensive_bench.latest.json
    - jq -n --slurpfile current "${GAUNTLET_WORKSPACE}/artifacts/bench/comprehensive_bench/comprehensive_bench_report.json" \
        --slurpfile baseline "${GAUNTLET_WORKSPACE}/.bench-history/comprehensive_bench.latest.json" \
        '($current[0].summary.geomean_ratio / $baseline[0].summary.geomean_ratio - 1) * 100'
  artifacts:
    paths:
      - ${GAUNTLET_WORKSPACE}/artifacts/bench/
      - ${GAUNTLET_WORKSPACE}/.bench-history/*.latest.json
    expire_in: 90 days
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        - "crates/*-e2e/**/*"
        - "benches/**/*"
        - "Cargo.toml"
        - "Cargo.lock"

feature-coverage:
  stage: parity
  script:
    - ./scripts/compute-feature-coverage.sh "${GAUNTLET_WORKSPACE}" \
        --matrix "${GAUNTLET_WORKSPACE}/docs/contracts/supported_surface_matrix.toml" \
        --taxonomy ./parity_taxonomy.json
    - jq -e 'all(.families[]; .verdict != "none")' \
        "${GAUNTLET_WORKSPACE}/reports/feature_coverage.json"

fault-vfs-coverage:
  stage: parity
  script:
    - cargo run --bin verify-fault-vfs-coverage --profile release-perf
  rules:
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"
      changes:
        - "crates/*-harness/src/fault_*"
    - if: $CI_PIPELINE_SCHEDULE == "weekly"

bead-graph-validator:
  stage: parity
  script:
    - br dep cycles | tee /tmp/cycles.txt
    - test ! -s /tmp/cycles.txt  # fails if non-empty
    - bv --robot-insights | jq -e '(.Cycles // []) | length == 0'

# ----------------------------------------------------------------------------
# Stage: soak (long-running; cron-only)
# ----------------------------------------------------------------------------

soak-fuzz:
  stage: soak
  image: rust:nightly
  tags: [soak-runner]
  timeout: 24h
  script:
    - cargo install cargo-fuzz
    - |
      for target in $(jq -r '.previously_divergent[]' .gauntlet/phase15_soak_designs.json); do
        timeout 1380m cargo +nightly fuzz run "$target" -- -max_total_time=82800 || true
      done
  artifacts:
    when: always
    paths:
      - fuzz/artifacts/
    expire_in: 365 days
  rules:
    - if: $CI_PIPELINE_SCHEDULE == "weekly-fuzz"

soak-miri:
  stage: soak
  image: rustlang/rust:nightly
  tags: [soak-runner]
  timeout: 72h
  script:
    - rustup component add miri
    - cargo +nightly miri test --lib
  rules:
    - if: $CI_PIPELINE_SCHEDULE == "weekly-miri"

soak-loom:
  stage: soak
  image: rust:1.85
  tags: [soak-runner]
  timeout: 48h
  script:
    - LOOM_MAX_PREEMPTIONS=8 cargo test --features loom --release
    - SHUTTLE_ITERS=100000 cargo test --features shuttle --release
  rules:
    - if: $CI_PIPELINE_SCHEDULE == "weekly-loom"

soak-crash-boundary:
  stage: soak
  image: rust:1.85
  tags: [soak-runner]
  timeout: 48h
  script:
    - |
      for boundary in $(jq -r '.named_boundaries[]' docs/contracts/crash_boundaries.json); do
        for fault in TornWrite PartialWrite PowerCut IoError; do
          cargo test --test fault_vfs -- --exact "crash_${boundary}_${fault}"
        done
      done
  rules:
    - if: $CI_PIPELINE_SCHEDULE == "weekly-crash"

soak-bocpd:
  stage: soak
  image: rust:1.85
  script:
    - cargo run --bin compute-parity-score --profile release-perf
    - cargo run --bin bocpd-update --profile release-perf -- \
        --append-observation /tmp/scorecards.json \
        --state .gauntlet/bocpd_state.json
  rules:
    - if: $CI_PIPELINE_SCHEDULE == "continuous-bocpd"  # every 30 min

soak-adversarial:
  stage: soak
  image: rust:1.85
  tags: [soak-runner]
  timeout: 48h
  script:
    - |
      for lens in agent-honesty-bias cross-pillar-coupling temporal-monotonicity \
                  evidence-laundering silent-skip green-on-different-corpus; do
        cargo test --test adversarial_search -- --exact "${lens}"
      done
  rules:
    - if: $CI_PIPELINE_SCHEDULE == "weekly-adversarial"

# ----------------------------------------------------------------------------
# Stage: certify (manual; tag-pinned release certification)
# ----------------------------------------------------------------------------

release-certification:
  stage: certify
  when: manual
  script:
    # Verify all required gates green at this tag
    - ./scripts/verify-all-gates-green.sh ${CI_COMMIT_TAG}
    - cargo run --bin certification-bundler --profile release-perf -- \
        --tag ${CI_COMMIT_TAG} \
        --workspace . \
        --output /tmp/certification-bundle/
    # Verify the bundle's release-certificate.json says certifying: true
    - CERT=$(jq -r .certifying /tmp/certification-bundle/release_certificate.json)
    - test "$CERT" = "true"  # else fail
  artifacts:
    paths:
      - /tmp/certification-bundle/
    expire_in: 5 years  # certification bundles are long-lived audit artifacts
  rules:
    - if: $CI_COMMIT_TAG
```

---

## 3. Scheduling (cron-equivalent)

GitLab CI uses pipeline schedules (Settings → CI/CD → Schedules). Configure:

| Schedule name | Cron | Variables |
|---|---|---|
| `weekly-fuzz` | `0 0 * * 0` (Sunday midnight) | `CI_PIPELINE_SCHEDULE=weekly-fuzz` |
| `weekly-miri` | `0 0 * * 1` (Monday midnight) | `CI_PIPELINE_SCHEDULE=weekly-miri` |
| `weekly-loom` | `0 0 * * 2` (Tuesday midnight) | `CI_PIPELINE_SCHEDULE=weekly-loom` |
| `weekly-crash` | `0 0 * * 3` (Wednesday midnight) | `CI_PIPELINE_SCHEDULE=weekly-crash` |
| `weekly-adversarial` | `0 0 * * 4` (Thursday midnight) | `CI_PIPELINE_SCHEDULE=weekly-adversarial` |
| `continuous-bocpd` | `*/30 * * * *` (every 30 min) | `CI_PIPELINE_SCHEDULE=continuous-bocpd` |

Stagger the weekly soaks across different days so a single soak-runner host can serve all of them.

---

## 4. Self-hosted runners (tags)

Per [`GITHUB-ACTIONS-FULL-MATRIX.md § 4`](GITHUB-ACTIONS-FULL-MATRIX.md), perf benchmarks REQUIRE stable hardware. In GitLab CI, this means **tagged self-hosted runners**:

```yaml
bench-pass-over-pass:
  tags: [bench-runner]   # only run on runners tagged 'bench-runner'
```

Where the `bench-runner` tag identifies a specific physical host with:
- Pinned CPU governor (performance, not powersave).
- Disabled turbo + hyperthreading (for reproducibility).
- Dedicated; no other workloads scheduled.
- Cached cargo target; pre-warmed.

For soak runners, `tags: [soak-runner]` — different hardware (often GPU-equipped for ML-class fuzz / inference benches).

---

## 5. Merge request approval rules

Configure protected branches (Settings → Repository → Protected branches → main):
- Allowed to merge: Maintainers.
- Allowed to push: No one (force PR workflow).
- Code Owner approval required: YES (use CODEOWNERS file per [`assets/contributing-templates/CODEOWNERS`](../../assets/contributing-templates/CODEOWNERS)).

Configure pipeline rules (Settings → CI/CD → General pipelines):
- "Pipelines must succeed before merging": YES.
- The required gates (per [`GITHUB-ACTIONS-FULL-MATRIX.md § 2`](GITHUB-ACTIONS-FULL-MATRIX.md)) MUST all be in the `parity` stage so a single stage gate covers them.

---

## 6. Secrets

GitLab CI/CD variables (Settings → CI/CD → Variables):
- `SLACK_WEBHOOK_URL` (Protected, Masked) — soak findings + Ville-bound crossings.
- `JSM_TOKEN` (Protected, Masked) — if certification publishes to JSM.

Per-job variable scope: limit `SLACK_WEBHOOK_URL` to soak jobs only.

---

## 7. Anti-patterns (additional vs GitHub Actions)

- **Forgetting `tags:` on bench jobs** — GitLab will schedule the job on any available runner, including shared ones; perf numbers become noise.
- **Not setting `timeout:` on soak jobs** — GitLab's default 1h job timeout kills soaks. Always `timeout: 24h` (fuzz), `72h` (miri), etc.
- **Using `interruptible: true` on parity stage** — interruption can corrupt the `.bench-history/` baseline. Set `interruptible: false` for any job that writes to `reports/`, `.bench-history/`, or `.gauntlet/`.
- **Mixing `image: rust:1.85` and `image: rust:nightly` across the matrix** — toolchain divergence breaks reproducibility. Pin one toolchain per workflow stage.

---

## 8. Cross-references

- [`GITHUB-ACTIONS-FULL-MATRIX.md`](GITHUB-ACTIONS-FULL-MATRIX.md) — GitHub Actions equivalent (same coverage).
- [`assets/github-workflows/`](../../assets/github-workflows/) — the GitHub Actions workflow files (the underlying scripts are CI-agnostic; same commands work in GitLab).
- [`../orchestration/NTM-INTEGRATION.md`](../orchestration/NTM-INTEGRATION.md) — NTM pipelines (operator-driven, complement to CI).
- [`../methodology/CONFORMAL-RATCHET.md`](../methodology/CONFORMAL-RATCHET.md) — ratchet decision logic.
- [`../patterns/155-BENCH-HISTORY-RATCHET.md`](../patterns/155-BENCH-HISTORY-RATCHET.md) — pass-over-pass.
- [`../patterns/140-RELEASE-PERF-PROFILE.md`](../patterns/140-RELEASE-PERF-PROFILE.md) — release-perf profile.
