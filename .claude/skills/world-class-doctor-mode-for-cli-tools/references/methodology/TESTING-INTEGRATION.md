# Testing Integration — Wiring `/testing-*` Skills

This skill's Phase 5 ships five built-in safety tests (reversibility, idempotence, crash-recovery, concurrency, detector metamorphic repeatability). They cover the load-bearing invariants. The `/testing-*` skills extend the harness for stronger guarantees and broader coverage.

Each section below: the testing skill, what it adds beyond Phase 5's baseline, the integration pattern, and a paste-ready prompt.

---

## `/testing-fuzzing` — Fault-injection into the `mutate()` chokepoint

**What it adds.** Coverage-guided fuzzing of `mutate()` itself: random input bytes, random op enum variants, random path components. Catches bugs the baseline tests miss (e.g., a path with a NUL byte; a fixer that produces 1 GB of content).

**Integration.**

1. Phase 5's safety-harness-runner subagent dispatches `/testing-fuzzing` after the five baseline tests pass.
2. The fuzzer harness (`fuzz/fuzz_targets/mutate.rs` for Rust; `fuzz/mutate_test.go` for Go; `fuzz/test_mutate.py` for Python) drives `mutate()` with random `Op` instances against a sandbox repo.
3. CI gate: 1 minute fuzzing per fixer per release branch; 1 hour per major release.
4. Crashes get auto-minimized into Phase 9 fixtures via `cargo fuzz tmin` (Rust) / `go-fuzz`-equivalent (Go).

**Prompt to dispatch:**

```
Apply /testing-fuzzing to the mutate() chokepoint at <path-to-mutate.rs>.
Fuzz target: mutate(path, op) where path is a random valid filesystem path
and op is a random Op enum variant. Minimize any crashes into Phase 9 fixtures.
Run for 60 seconds; report coverage delta and any crashes.
```

---

## `/testing-metamorphic` — `fix(corrupt(x)) ≡ x` property tests

**What it adds.** Property-based assertions about doctor behavior:

- **Reversibility property.** For every fixture: `apply_corrupt → apply_fix → apply_undo → state ≡ corrupt(initial_state)`. Generalizes Phase 5's per-fixer reversibility test to a universal property.
- **Idempotence property.** For every fixture: `apply_fix(apply_fix(corrupt(x))) ≡ apply_fix(corrupt(x))`. Generalizes Phase 5's per-fixer idempotence test.
- **Composition property.** For every pair (FM-A, FM-B) NOT in the conflict matrix: `corrupt_A → corrupt_B → apply_fix → no_findings`. Verifies the dependency graph is correct.
- **Order-invariance.** For every triplet (FM-A, FM-B, FM-C) in disjoint subsystems: applying fixes in any order produces the same result. Verifies subsystem isolation.

**Integration.** Phase 5's safety-harness-runner adds a `--metamorphic` flag that dispatches `/testing-metamorphic` to derive properties from the repair specs, generate `proptest`/`hypothesis`/`fast-check` test files, and run them.

**Prompt:**

```
Apply /testing-metamorphic to the doctor at <target>. Derive metamorphic
relations from the repair specs at <workspace>/analysis/repair_specs/.
Generate proptest (Rust) / hypothesis (Python) / fast-check (TS) properties.
Run with 1000 inputs per property. Minimize counterexamples to fixtures.
```

---

## `/testing-conformance-harnesses` — Round-trip backup/restore against a golden corpus

**What it adds.** A reference golden corpus of `actions.jsonl` files + their corresponding `backups/` directories from prior known-good runs. The harness asserts that a fresh doctor's run-artifact, given the same fixture input, matches the golden's hash transitions byte-for-byte (modulo the run-id and timestamps).

**Why it matters.** Catches drift in the `actions.jsonl` schema that Phase 5's verifiers don't (the verifiers don't read `actions.jsonl` content; they only check end-state).

**Integration.** Phase 5 stage 2 (after the five baseline tests). The conformance harness lives at `tests/doctor_conformance/` with a `golden/` subtree of pre-recorded run artifacts.

**Prompt:**

```
Apply /testing-conformance-harnesses to <target>'s doctor. Build a
conformance corpus of (fixture, expected actions.jsonl) pairs at
tests/doctor_conformance/golden/. The harness re-runs doctor on each
fixture and asserts: same actions in same order, same path/op/hash trio
per line (run_id and timestamps elided). Wire to CI.
```

---

## `/testing-golden-artifacts` — Snapshot tests for `report.json` / `scorecard.json`

**What it adds.** `insta` (Rust) / Jest snapshot / approvaltests-style snapshots of every JSON artifact the doctor emits, with scrubbing of run-id and timestamps.

**Why it matters.** Schema drift is the silent killer. A renamed JSON field breaks every downstream agent. Golden-artifact tests fail loudly the moment a schema changes; the user reviews and decides whether to bump `schema_version`.

**Integration.**

- For each canonical fixture, snapshot:
  - `report.json` (scrubbed of `run_id`, `started_at`, `finished_at`, `duration_ms`)
  - `scorecard.json` (same scrubbing)
  - `capabilities --json` (scrubbed of `tool_version`)
  - `--robot-triage` output
- CI fails on snapshot drift; reviewer bumps `schema_version` if the change is intentional.

**Prompt:**

```
Apply /testing-golden-artifacts to <target>'s doctor. Snapshot:
report.json, scorecard.json, capabilities --json, robot-triage output.
Scrub run_id, timestamps, durations, tool_version. Use insta (Rust) /
Jest (TS) / pytest-approvaltests (Python). Wire to CI.
```

---

## `/testing-real-service-e2e-no-mocks` — Online detectors against real vendor APIs

**What it adds.** End-to-end tests for `--online` detectors against real vendor APIs (Stripe test mode, GitHub sandbox account, Cloudflare staging account). No mocks; structured logging.

**Why it matters.** Mocked tests of online detectors give a false sense of security. A vendor changes a field name, the mock keeps passing, the real call fails. Mock-free tests catch this.

**Integration.** Phase 5 stage 3 (gated on `--online` test config). Requires the user to provision sandbox credentials; the testing skill helps set up.

**Prompt:**

```
Apply /testing-real-service-e2e-no-mocks to <target>'s doctor's online
detectors. Use vendor sandbox accounts (Stripe test mode, GitHub sandbox,
etc.). Each online detector gets one e2e test that hits the real API
and asserts the finding fires when the vendor returns an error condition.
Tests honor --online; skipped without credentials.
```

---

## Layering the testing skills

The full Phase 5 with all testing skills:

```
Phase 5.1 — Built-in safety harness (always runs)
              verify-undo.sh × N
              verify-idempotence.sh × N
              verify-crash-recovery.sh × N
              verify-concurrency.sh × N
              verify-metamorphic.sh × N

Phase 5.2 — Fuzzing (60s per fixer)
              testing-fuzzing on mutate() chokepoint

Phase 5.3 — Metamorphic properties (1000 inputs each)
              testing-metamorphic derives + runs

Phase 5.4 — Conformance against golden corpus
              testing-conformance-harnesses replays

Phase 5.5 — Snapshot tests for schemas
              testing-golden-artifacts captures + checks

Phase 5.6 — Real-service e2e (--online + sandbox creds)
              testing-real-service-e2e-no-mocks
```

Every layer is opt-in; the baseline (5.1) is mandatory. Phase 5.2–5.6 are *additive* — you can run them in any order, in parallel, or skip them. Each layer's failure is a P0 / P1 finding for the corresponding spec.

---

## When NOT to use these

- **Ultra-tight pre-1.0 dev cycle.** The baseline five tests are enough. Add layers as the doctor matures.
- **No vendor sandbox available.** Skip 5.6.
- **Zero-network CI.** Skip 5.6.
- **A doctor with very few fixers (<= 3).** The properties may not pay off; the five baseline tests cover most ground.

For a mature project, all six layers running on every PR catches roughly 95% of the regressions a doctor would otherwise ship. The remaining 5% are caught by Phase 7's fresh-eyes and Phase 9's combinatorial fixtures.
