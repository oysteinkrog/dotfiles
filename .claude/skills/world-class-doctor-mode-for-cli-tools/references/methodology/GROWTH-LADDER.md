# Growth Ladder — From "No Doctor" to "World-Class"

The skill describes the end-state. This file maps the **path** between stages a project realistically travels. Useful when a project's appetite is "not zero, not 893, but somewhere in between." Each rung is independently shippable; later rungs assume earlier ones.

---

## Stage 0 — No doctor

The CLI exists but has no diagnostic surface. When state is broken, the user reads source, runs ad-hoc commands, files a bead.

**Symptoms:** "had to manually fix X" recurring in cass; bug-tracker tickets describing manual recovery steps; AGENTS.md sections naming workarounds.

**Effort to reach Stage 1:** ~1 day at Solo tier.

---

## Stage 1 — Read-only diagnose

Add a `<tool> doctor` subcommand that runs detectors only. No `--fix`. No backups. No undo. Just structured findings.

**What to build:**
- A `Finding` struct with `id, severity, evidence, remediation`.
- 3–10 detectors covering the highest-frequency FMs from cass/bug-tracker.
- `<tool> doctor` returns `--json` output. Exit codes 0 (healthy) and 1 (findings).
- `tests/doctor_fixtures/<fm-id>/corrupt.sh + assert.sh` per detector.

**Polish Bar items met:** detect-then-fix (trivially; no fix), stdout-data-stderr-progress, exit-code-contract (subset).
**Polish Bar items NOT met:** all the fix/backup/undo/concurrency items.

**Aggregate score expected:** 350–500.

**Effort:** ~3 days at Solo tier.

**When to stop here:** the project is too small for `--fix` to be worthwhile (< 5 FMs, low recurrence). Diagnose-only is genuinely sufficient.

---

## Stage 2 — Detect-then-fix with manual verification

Add `--fix`. No `mutate()` chokepoint yet — fixers write directly. No backups. The user verifies correctness manually.

**What to build:**
- A `Fixer` for each of the top-3 most-frequent fixable FMs.
- `<tool> doctor --fix` invokes them.
- Exit codes 0 (fix complete), 2 (partial), 3 (failed).
- Fixture round-trips: corrupt → fix → assert.

**Polish Bar items met:** previous + exit codes 2/3.
**Polish Bar items NOT met:** backups, reversibility, idempotence, concurrency, the chokepoint, capabilities.

**Aggregate score expected:** 500–650.

**Effort:** ~5 days at Solo tier.

**Risk:** without backups, a buggy fixer can lose user data. Use only for clearly-recoverable FMs (e.g., regenerating a derived index from a source-of-truth elsewhere).

**When to stop here:** prototype phase only. Stage 2 is **transitional**; the skill discourages parking here.

---

## Stage 3 — `mutate()` chokepoint + verbatim backups

Add the load-bearing invariant. Every fixer routes through `mutate(path, op)`. Every mutation writes a backup first. `actions.jsonl` records what happened.

**What to build:**
- The chokepoint per [MUTATE-CHOKEPOINT.md](MUTATE-CHOKEPOINT.md).
- Per-run artifact directory `.doctor/runs/<run-id>/{report.json,actions.jsonl,backups/}`.
- The runtime guarantees backup-before-mutate.

**Polish Bar items met:** previous + single-chokepoint, backups, hashes-witnessed, observability (basic).
**Polish Bar items NOT met:** undo, idempotence (probably yes after this, but unverified), concurrency, capabilities/robot-docs.

**Aggregate score expected:** 650–750.

**Effort:** ~5 days at Pair tier (one for chokepoint, one for fixer refactors).

**This is the smallest "production-acceptable" stage.** A doctor at Stage 3 won't lose user data; it's just not yet agent-ergonomic.

---

## Stage 4 — Reversibility + undo

Add `<tool> doctor undo <run-id>`. Each fixer is now reversible byte-for-byte.

**What to build:**
- The undo subcommand reading `actions.jsonl` in reverse.
- The strict mode (default) refuses on missing backup or hash mismatch.
- `verify-undo.sh` per FM in CI.

**Polish Bar items met:** previous + reversible.

**Aggregate score expected:** 720–820.

**Effort:** ~3 days.

**This is the smallest "agent-acceptable" stage.** The agent can run `--fix` without permanent risk.

---

## Stage 5 — Idempotence + concurrency safety

Add `verify-idempotence.sh` and `verify-concurrency.sh` to the test harness. Make any non-idempotent fixer idempotent (purify the detector). Add the lock primitive.

**What to build:**
- Per-path advisory lock at `mutate()` entry.
- Exit 5 (`concurrency_lost`) when contended.
- Idempotence enforced by detector purity + fixer short-circuit.

**Polish Bar items met:** previous + idempotent, concurrency-safe.

**Aggregate score expected:** 800–870.

**Effort:** ~3 days.

---

## Stage 6 — Capabilities + robot-docs + agent-ergonomic surface

Add the reflection layer the agent needs.

**What to build:**
- `<tool> doctor capabilities --json` (auto-generated from registry).
- `<tool> doctor robot-docs` with the negative-space spec.
- `<tool> doctor health` (cheap; < 200ms).
- `<tool> doctor --robot-triage` (mega-command).
- Stable `schema_version` in every JSON artifact.

**Polish Bar items met:** previous + capabilities, mega-command, robot-docs, schema-version.

**Aggregate score expected:** 850–920.

**Effort:** ~3 days.

**This is "production-grade."** Agents can use the doctor unsupervised in a sandbox.

---

## Stage 7 — Crash-recovery + safety harness

Add the five-test safety harness in CI. Make sure `verify-crash-recovery.sh` and `verify-metamorphic.sh` pass for every fixer.

**What to build:**
- Atomic write enforcement (temp + rename, same FS).
- Signal handlers that don't leave torn writes.
- Recovery detector for in-flight runs (per [STATE-MACHINE.md](STATE-MACHINE.md) ABORTED state).

**Polish Bar items met:** previous + crash-recoverable.

**Aggregate score expected:** 880–940.

**Effort:** ~3 days.

---

## Stage 8 — Fixture suite + adversarial review

Build the regression net. One fixture per FM plus combinatorial pairs. Run [ADVERSARIAL-REVIEW.md](ADVERSARIAL-REVIEW.md) scenarios.

**What to build:**
- `tests/doctor_fixtures/<fm-id>/` per FM.
- `tests/doctor_fixtures/pairs/<a>__<b>/` for ≥ 5 worst-offender pairs.
- `tests/doctor_fixtures/adversarial/<scenario>/` per Section A–F.
- `run_all.sh` driver in CI.

**Polish Bar items met:** previous + each-fixer-has-fixture.

**Aggregate score expected:** 900–950.

**Effort:** ~5 days.

---

## Stage 9 — Cookbook patterns + worked example

For mature projects: apply the project-specific Cookbook pattern(s) deeply. Document the project's own worked example.

**What to build:**
- Pattern-specific surface (e.g., `--watch` for daemon CLIs; `verify-install` for installers; `auth-status --online` for distributed CLIs).
- Project-specific worked example similar to [WORKED-EXAMPLE.md](WORKED-EXAMPLE.md).

**Polish Bar items met:** all previous + project-pattern coverage.

**Aggregate score expected:** 920–970.

---

## Stage 10 — World-class

Multi-pass doctor evolution. Pass-2 / Pass-3 mining (cass + bug-tracker re-run) surfaces new FMs. Phase 9 fixture coverage approaches 100%. Phase 10 cold-prober finds nothing actionable. Adversarial scenarios all pass. Aggregate ≥ 950.

This is the rare end-state. Most production tools reach Stage 7–8 and plateau there until a new failure mode surfaces.

---

## How to choose your stage target

| Project state | Recommended target |
|---------------|---------------------|
| Pre-1.0; < 100 stars; < 5 known FMs | Stage 1 (diagnose-only) |
| Pre-1.0; 5–20 known FMs; agents using it occasionally | Stage 4 (with undo) |
| Post-1.0; agents are primary users; CI must pass with green doctor health | Stage 6 (capabilities + robot-docs) |
| Production; multiple users; recurring incidents that the doctor could prevent | Stage 8 (fixture suite + adversarial) |
| Flagship of an agentic-coding stack | Stage 10 (world-class) |

---

## Anti-patterns when climbing

- **Skipping Stage 3 to get faster results.** Without `mutate()` chokepoint, every later stage is built on sand. Do Stage 3 even if it slows you down.
- **Climbing to Stage 6 before Stage 4.** Capabilities reflection is meaningless if the doctor isn't reversible — agents won't trust it.
- **Adding fixtures (Stage 8) before fixers (Stage 2-5).** Fixtures verify behavior; without behavior, fixtures are tautologies.
- **Multiple stages in one PR.** Each stage is independently shippable; review and ship them separately so regressions are bisectable.

---

## Pass cadence per stage

This skill's `add` mode targets Stage 6 in a single pass-1 (the canonical 10-phase loop produces all artifacts of Stages 1-6). Stages 7-9 are typically achieved in pass-2 (refinement). Stage 10 takes 3+ passes spaced across release cycles, with cass mining between passes catching new FMs.

`upgrade` mode varies. A project at Stage 3 needs Stages 4-6 in pass-1 + Stages 7-8 in pass-2. A project at Stage 5 may reach Stage 8 in a single pass.

The HANDOFF.md template includes a "Current stage estimate" field so the next pass starts with situational awareness.
