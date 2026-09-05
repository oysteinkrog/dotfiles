# PHASE-4-ENVIRONMENTS.md — Sandboxing the test re-runs

Phase 4 runs the actual tests, builds, fuzzers, and conformance harnesses cited in each bead's evidence pack. That means it executes arbitrary code on the auditor's machine. Three problems follow:

1. **The host's state contaminates results.** A test that "passes locally" may rely on `~/.aws/credentials`, an installed package version, an open port — none of which exist on a fresh CI runner.
2. **The tests can mutate state we don't want mutated.** Connection to a prod-like DB, side-effects to a real API, file writes outside the project tree.
3. **Replayability requires a frozen environment.** Time-machine audits and Bayesian calibration both need to re-run Phase 4 against historical commits with historical dependencies.

Phase 4 environments are how we control the blast radius and the variance.

---

## Four environments

| Kind | Isolation | Replayability | Cost | When to use |
|------|-----------|:-------------:|:----:|-------------|
| **native** | none — runs on auditor host | low | lowest | Local development, fast iteration, low-risk projects |
| **docker** | container | medium | medium | Default for Standard mode; isolates packages + filesystem |
| **nix** | nix flake | high | medium | Reproducibility-required audits; pinned dep graph |
| **testcontainers** | per-service container per test | high | highest | Integration tests requiring real DBs / queues |

---

## Configure via `audit-policy.yaml`

```yaml
phase_4_environment:
  kind: docker
  network_policy: localhost-only
  allow_real_services:
    - postgres
    - redis
  capture_strace: false
  resource_caps:
    memory: 4G
    cpus: 4
    pids: 1024
```

`bootstrap-audit.sh` reads this and emits a per-pass environment-setup script that the compliance-verifier subagent runs before any test execution.

---

## Network policy

| Policy | What it allows | Trade-off |
|--------|----------------|-----------|
| `allow` | All outbound | Tests can hit any service. Fast, but verdict depends on the world. |
| `localhost-only` | Loopback only | Tests can hit local services (testcontainers). External APIs are dark. |
| `deny` | No network | Pure unit tests only. e2e tests will fail even if correct. |
| `allowlist:[hosts]` | Only specified hosts | Mid-ground; allow `api.stripe.com` but block analytics CDNs. |

Mocks-where-forbidden in security beads (per `subagents/security-auditor.md`) interact: if the bead spec says "no mocks; hit Stripe sandbox," `network_policy: deny` would force the test to fail — that's a Phase 4 environment misconfiguration, not a bead theater. The Phase 4 environment should match the bead's stated dependencies.

---

## Capture-only resource access

For destructive operations (DB writes, S3 uploads, email sends), the env can route to a **capture-only proxy** that records the call but doesn't forward it. Frameworks:

- **WireMock** for HTTP capture/replay.
- **localstack** for AWS service emulation.
- **Stripe test-mode** for real-but-sandboxed payment flows (matches `/testing-real-service-e2e-no-mocks`).
- **Mailpit** for outbound-email capture.

The bead's spec drives the choice: a bead that says "verify webhook delivery to Slack" needs a real Slack workspace OR an explicit acknowledgment that delivery is captured-only.

---

## Frozen-time mode

For replayable audits, freeze:

- **Code:** project SHA (handled by `time-machine-audit.sh`).
- **Dependencies:** `Cargo.lock`, `package-lock.json`, `pnpm-lock.yaml`, `go.sum`, `Pipfile.lock`. Audit fails if any is missing or out-of-sync.
- **System:** docker image SHA (NOT just tag — tags float).
- **Clock:** for tests that branch on date (e.g. "expires after 30 days"), use a clock-injection library (`chrono::Utc::now` mockable in Rust; `freezegun` in Python; `vi.useFakeTimers()` in Vitest).
- **Random:** seed every PRNG. Property-based tests should record their seed in `compliance.json#checks[].seed` so failures replay.

The frozen-time mode is required for Bayesian calibration (`references/VERIFICATION-UNDER-UNCERTAINTY.md`) — the conformal interval is meaningless if the test environment isn't pinned.

---

## Per-language defaults

| Language | Default kind | Coverage tool | Sandbox notes |
|----------|--------------|---------------|---------------|
| Rust | docker | `cargo llvm-cov` | Pin toolchain in `rust-toolchain.toml`. |
| TypeScript | docker | `vitest --coverage` | Use `node:20-alpine`; lock `pnpm`/`npm`. |
| Python | docker | `coverage.py` | Pin `requirements.txt` AND `Pipfile.lock`. |
| Go | nix | `go test -cover` | nix flake pins compiler + module versions. |
| Polyglot monorepo | docker-compose | per-language | One container per language; share volume for source. |

---

## Strace-capture for "passes locally / fails in CI"

When a test passes natively but fails in the docker env (or vice versa), enabling `capture_strace: true` records every syscall the test made. The diff against the failing run usually points at the missing dependency: a file open that 404s, a DNS lookup that times out, a UID/GID mismatch.

`scripts/anomaly-scan.sh` flags any test whose strace shows file opens outside the project tree (or `/etc/hosts`, etc.) as an environmental dependency the bead spec didn't declare.

---

## Container hygiene

For docker / testcontainers env:

- **Build a single image per pass**, not per bead. Massive cache hit on re-runs.
- **Mount source read-only** (`-v $PWD:/workspace:ro`); write outputs to a separate volume.
- **Drop capabilities** beyond the project's actual needs (`--cap-drop=ALL --cap-add=NET_BIND_SERVICE` if needed).
- **Set deterministic UID/GID** in the image so file-mode tests don't drift.
- **Tear down per-test containers** even on test failure — leaks accumulate fast in long passes.

---

## When to escalate from native → docker → nix

| Symptom | Escalate to |
|---------|-------------|
| "Works on my machine, fails on the audit machine" | docker |
| Different scores across two auditor machines | docker |
| Bayesian calibration drifts > 5pt across passes | nix (pin everything) |
| Pre-release audit (regulator-bound) | nix (audit submission requires reproducibility evidence) |
| Multi-repo portfolio with mixed languages | docker-compose, one container per project |

---

## Operator pairing

`⊡ FRAME` (Phase 0.5: declare the environment frame upfront and record it in `manifest.json`) and `⌥ ROLLBACK-PROOF` (don't let Phase 4 mutations leak past the pass).
