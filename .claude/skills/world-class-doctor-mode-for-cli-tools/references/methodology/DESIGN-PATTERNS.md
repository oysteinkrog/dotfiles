# Design Patterns — Higher-Order Patterns for Doctors

The 15 cookbook patterns are project-shape patterns (single-binary, daemon, distributed, etc.). This file captures higher-order *behavioral* patterns: composable techniques that any doctor of any shape can adopt to address recurring design challenges.

Each pattern: name, when-to-use, sketch, trade-offs, citation.

---

## DP-001 — Probe-then-Commit

**When:** a fix has multiple steps; later steps' viability depends on earlier steps' results.

**Sketch:**
```
1. probe(): cheap read to confirm preconditions still hold (after locking).
2. plan(): assemble the full mutation set in memory.
3. validate(): self-check the plan (e.g., diffs are within scope).
4. commit(): write all backups, then atomic mutations, in order.
5. verify(): re-run probe(); expect None.
```

**Trade-off:** robust but verbose. For simple fixers (single mutation), Probe-then-Commit is overkill. For multi-step fixers (e.g., schema migration), it's load-bearing.

**Cited:** [Q-007 (bv two-phase)](QUOTE-BANK.md) is a related pattern (instant + async with timeout).

---

## DP-002 — Quarantine Before Verify

**When:** a fixer might leave residual state if the verification fails.

**Sketch:**
```
1. mutate(target, Op::Rename to quarantine).
2. mutate(target, Op::WriteFile new_content).
3. verify(target).
4a. if verify ok → quarantine stays as backup; success.
4b. if verify fails → restore from quarantine (mutate Rename quarantine → target).
```

**Why:** the quarantine IS the rollback. No special undo path needed for this fixer.

**Trade-off:** adds disk overhead (the quarantined file lingers until gc).

---

## DP-003 — Refuse-with-Bridge

**When:** the doctor can't auto-fix but has structured information about how a HUMAN would fix.

**Sketch:** the finding's `remediation` field carries:
```jsonc
{
  "command_or_instruction": "<paste-ready next step>",
  "after_user_acts": "<tool> doctor --fix --only fm-XXX",
  "rationale": "<why doctor can't auto-fix>"
}
```

**Trade-off:** writes more verbose remediation; pays off when an agent reads it (the `after_user_acts` field tells the agent what to do next without re-asking the user).

---

## DP-004 — Bayesian Detector Tier

**When:** detectors of different cost levels need to be ranked dynamically.

**Sketch:** each detector publishes a prior probability of finding something, updated from `scorecard_history.jsonl`:
```
priority(detector) = prior_probability × frequency_recently × cost_inverse
```

`--quick` mode runs the top-N highest-priority detectors that fit a 200ms budget.

**Trade-off:** more sophisticated than tiering by `tier: quick|default|deep`. Worth it for projects with > 50 detectors where some are seasonally noisy.

**Cited:** decision-theoretic rigor framing from Bayesian / conformal-prediction literature.

---

## DP-005 — Circuit-Breaker for `--online`

**When:** `--online` detectors collectively exceed a budget OR a single vendor returns repeated 5xx.

**Sketch:**
```
1. Per-vendor failure window (last 60s).
2. If failure_count > threshold: trip circuit; mark all of that vendor's detectors as `findings_only_offline` for the next 5 minutes.
3. Half-open: after 5 min, allow ONE detector through; if succeeds, reset; if fails, re-trip.
```

**Trade-off:** prevents one vendor's outage from wedging the doctor; adds per-vendor state.

**When NOT to use:** at small scale (< 5 vendor-dependent detectors), the circuit-breaker is overhead.

---

## DP-006 — Bulkhead by Subsystem

**When:** an unrelated subsystem's detector failure shouldn't affect others.

**Sketch:** each subsystem's detectors run in their own logical "bulkhead". A panic / timeout in `state_files` detectors doesn't propagate to `configs` or `caches`.

```rust
fn run_subsystem_detectors(subsystem: &str, ctx: &Ctx) -> Vec<Finding> {
    let mut findings = vec![];
    for detector in detectors_for(subsystem) {
        match catch_unwind(|| detector.run(ctx)) {
            Ok(Ok(Some(f))) => findings.push(f),
            Ok(Ok(None)) => {}
            Ok(Err(e)) => findings.push(Finding::detector_error(detector.id, e)),
            Err(_) => findings.push(Finding::detector_panic(detector.id)),
        }
    }
    findings
}
```

**Trade-off:** more code; better resilience. Required at Stage 7+.

---

## DP-007 — Saga for Multi-Step Fixers

**When:** a fixer has multiple steps that must each succeed or the whole thing rolls back.

**Sketch (per the saga pattern):**
```
1. step_1(): forward.
2. step_2(): forward. If fails, run compensate_1() and abort.
3. step_3(): forward. If fails, run compensate_2(); compensate_1(); abort.
4. all done: commit.
```

Each step's compensate is the inverse. The `mutate()` chokepoint already records `before_hash`/`after_hash`; saga compensations are the same as `undo` at the per-step level.

**Trade-off:** adds compensate functions per step. For schema migrations and similar, indispensable.

---

## DP-008 — Fingerprint Cache

**When:** a detector's predicate is expensive (e.g., parsing a large file).

**Sketch:**
```
1. Stat the file → mtime, size.
2. Hash (mtime, size) → cache key.
3. Lookup in `<run-dir>/cache/detector_<id>.cache`. If hit and key matches → return cached verdict.
4. Else: run the detector; cache verdict + key.
```

**Trade-off:** false negatives if the file changes content but not (mtime, size). For determinism-critical detectors, don't use this; for performance-critical hot-path detectors, it's a 10x speedup.

**Caveat:** the cache file goes in `.doctor/runs/<run-id>/cache/`, not at the project root. Not shared across runs by default.

---

## DP-009 — Two-Phase Commit Across Subsystems

**When:** a fix requires changes to multiple subsystems atomically.

**Sketch:**
```
1. Phase 1 (prepare): each subsystem's "pre-commit" check runs. All must vote yes.
2. Phase 2 (commit): if all yes, each subsystem's actual mutation runs.
3. If ANY mutation fails: each subsystem's rollback runs (in reverse subsystem-dep order).
```

**Trade-off:** classic 2PC overhead; appropriate for cross-subsystem fixes. Most fixes don't need this; single-subsystem fixers are simpler.

---

## DP-010 — Read-Repair on Detect

**When:** the detector itself can perform a trivial sanitization (whitespace, idempotent normalization) without a fixer.

**Sketch:** controversial — this VIOLATES Axiom 1 (detector purity). Only use when:
- The "repair" is documenting state, not changing user-visible behavior.
- Example: the detector caches its read so subsequent runs don't re-stat.

In practice, NEVER do this. The cleaner pattern: a detector marks something for the runtime to re-fetch, but the detector itself doesn't write.

**Cited as anti-pattern.** Listed here so future maintainers don't propose it.

---

## DP-011 — Health Snapshot Streaming (NDJSON)

**When:** an operator wants continuous monitoring (Pattern 4 daemon).

**Sketch:**
```
<tool> doctor health --watch | jq -c .
```

Each line:
```jsonc
{"ts":"2026-05-06T14:00:00Z","ok":true,"findings":0,"daemon_alive":true,...}
```

The doctor emits one event per second (or per state-change-detected). Subscribers consume.

**Trade-off:** keeps a process alive; unsuitable for short-lived agent sessions.

**Cited:** [Q-017 (caam robot watch)](QUOTE-BANK.md).

---

## DP-012 — Dependency-Aware Detector Ordering

**When:** detector B's predicate depends on detector A's verdict.

**Sketch:** the runtime sorts detectors by their declared `depends_on` field in capabilities. If A says "broken", B can be skipped (its predicate is undefined under A-broken).

```jsonc
{
  "id": "fm-state-files-jsonl-tombstone-drift",
  "depends_on": ["fm-state-files-db-integrity"]
}
```

**Trade-off:** adds dependency graph to capabilities. Worth it for projects with 30+ detectors.

---

## DP-013 — Provenance-Tagged Cache (Axiom 17)

**When:** detectors fetch data from external sources whose freshness varies.

**Sketch:**
```jsonc
{
  "field": "value",
  "_provenance": "live"     // or "fallback" or "unavailable"
}
```

Readers check `_provenance` before trusting the value.

**Cited:** Axiom 17. Already documented in KERNEL.md.

---

## DP-014 — Speculative Pre-Diagnose

**When:** the doctor is invoked from a hot path (pre-commit hook).

**Sketch:** the doctor runs only the fast-path tier in pre-commit. If those pass, the full doctor runs in the background after the commit (results emitted on next interactive doctor invocation).

**Trade-off:** delays full feedback by one interactive cycle; unblocks the commit faster. Requires the doctor to support background mode.

---

## DP-015 — Adapter for Foreign Tools (Pattern 8 reinforcement)

**When:** the doctor needs to wrap a third-party tool's output.

**Sketch:**
```rust
// adapter.rs
fn parse_third_party_output(stdout: &str) -> Result<NativeFinding> {
    // parse the third-party tool's output (JSON, lines, whatever)
    // map to native Finding type
}
```

The adapter normalizes external schema → internal schema. Detectors operate on internal schema only.

**Trade-off:** an adapter to maintain whenever the third-party tool's output changes.

**Cited:** Pattern 8 (cookbook).

---

## DP-016 — Score Decay (Axiom 21)

**When:** a fixer's `frequency` weight should decrease over time if not invoked.

**Sketch:** the priority formula multiplies by a decay factor:
```
priority = base × (0.5 ^ months_since_last_invocation)
```

After a year of no invocations, the priority halves; after two years, halves again. Eventually the fixer's priority drops below the retirement threshold.

**Cited:** Axiom 21.

---

## DP-017 — Adaptive Tier Promotion

**When:** a `tier: deep` detector starts firing frequently and graduates to `tier: default`.

**Sketch:** each pass's scorecard analysis includes a "tier review": detectors in `deep` whose findings_per_invocation > 0.1 get promoted to `default`; detectors in `default` whose findings_per_invocation < 0.01 get demoted to `deep`.

**Trade-off:** automatic but inscrutable; better as a quarterly manual review.

---

## DP-018 — Sentinel-Error Prefix Discipline (Q-012)

**When:** the doctor refuses with exit 4 due to a known unsafe state.

**Sketch:** error messages start with a documented prefix:
```
Cannot repair: <reason>
Refusing: <reason>
Unsafe: <reason>
```

Agents pattern-match on the prefix, not the variable rest.

**Cited:** [Q-012 (br doctor sentinel prefixes)](QUOTE-BANK.md).

---

## How to use these patterns

When a fixer's design is hard:

1. Match against this list. Often a pattern fits.
2. If not, propose a new DP-NNN here.
3. Cite the pattern in the repair spec (DP-002 + DP-007 for a complex schema migration, etc.).

The patterns compose. A complex fixer might be `DP-002 (Quarantine Before Verify) + DP-007 (Saga) + DP-018 (Sentinel-Error Prefix)`.

---

## Patterns NOT in this library (for now)

- **Event sourcing** — too heavy for most doctors; specialized state stores benefit.
- **CQRS (Command-Query Responsibility Segregation)** — overlaps with detect-then-fix but is more elaborate.
- **Master-Master replication** — out of scope; doctors are local-first.
- **Strangler-Fig migration** — relevant for [MIGRATION-GUIDE.md](MIGRATION-GUIDE.md), not for fixer design.

If a future doctor needs them, propose addition here with concrete justification.
