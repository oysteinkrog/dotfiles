# Scale — When Project Size Changes the Methodology

The methodology defaults assume a "typical" CLI: 100k–1M lines of source, 10–50 failure modes, single-machine workspace. When projects are very small or very large, the methodology adapts.

This file pins the adjustments per scale.

---

## Tiny scale — < 1k LOC, < 5 FMs

**Examples:** a single-purpose Bash script; a 200-line Rust binary; a microservice with one job.

**Adjustments:**
- Skip Phase 2.5 (spec review) — same agent did Phase 1 and Phase 4; review-by-self is low-value.
- Combine workspace + target — no separate worktree; edit in-place.
- Skip cookbook patterns 4-15 — Pattern 1 (or 3) covers tiny projects.
- Aggregate score target: ≥ 600 (instead of 700). The Polish Bar floor relaxes.

**When to skip the skill entirely:** if the project has zero recurring incidents and no bug tracker history, building a doctor is premature optimization. Wait until the second incident.

---

## Small scale — 1k–10k LOC, 5–15 FMs

**Examples:** Most CLI tools start here. Single-binary, clear scope.

**Adjustments:**
- Solo tier is fine.
- Triangulation: peer-claude (multi-model is overkill).
- CASS appetite: quick (10 canned queries).
- Workspace: sibling.

**Recommended target stage:** [GROWTH-LADDER.md](GROWTH-LADDER.md) Stage 4 (with undo) within first pass; Stage 6 (capabilities + robot-docs) within second pass.

---

## Medium scale — 10k–100k LOC, 15–40 FMs

**Examples:** Mature CLI tools, single-binary or 2-3 binary toolkit.

**Adjustments (defaults):** This is the methodology's calibrated "default" scale. No adjustments needed; everything as written.

---

## Large scale — 100k–1M LOC, 40–100 FMs

**Examples:** `git`, `cargo`, `kubectl`, `go` toolchain, `wezterm`.

**Adjustments:**
- Squad tier or Swarm tier.
- Multi-model triangulation in Phase 4 + 7.
- Subsystem partition gets finer-grained (e.g., `state_files` → `state_files_db`, `state_files_jsonl`, `state_files_sidecar_files`).
- Detector tiering becomes critical (per [PERFORMANCE.md](PERFORMANCE.md)) — health budget could be exceeded by even quick-tier detectors at this scale.
- The cookbook patterns 2 (multi-binary), 4 (daemon), 9 (distributed) often combine.

**Per-pass effort:** 8-16 hours at Squad tier; days at Swarm tier with a deep audit.

---

## Very large scale — 1M+ LOC, 100+ FMs

**Examples:** Linux kernel build tools, the LLVM toolchain, Bazel itself, monorepos with hundreds of subdirs.

**Adjustments:**
- Multi-pass evolution becomes essential. Single-pass coverage of all FMs is infeasible.
- Pattern 12 (meta-doctor) becomes urgent — the doctor itself is now complex enough to need its own validator.
- Pattern 14 (build-system) often applies in addition to others.
- Per-subsystem doctors may emerge (`<tool> doctor state` vs `<tool> doctor schemas` vs ...) before the unified `<tool> doctor` ties them together.
- CASS mining is deeper (38+ queries; 180-day window).
- The fixture suite is partitioned: `tests/doctor_fixtures/<subsystem>/<fm>/`.

**Per-pass effort:** half-week to full week at Swarm tier.

---

## What changes by scale axis

### Detector budget

| Scale | Health budget (p95) | Default tier (p95) | Deep tier (p95) |
|-------|---------------------|---------------------|-----------------|
| Tiny | < 50 ms | < 1 s | < 5 s |
| Small | < 100 ms | < 3 s | < 10 s |
| Medium | < 200 ms | < 5 s | < 30 s |
| Large | < 500 ms | < 10 s | < 60 s |
| Very large | < 1 s | < 30 s | unbounded |

Health budget grows because the project state is bigger. But agents' patience for `<tool> doctor health` doesn't scale; if you're at 1 second on health, consider whether some "fast-path" detectors really need to run on every pre-commit.

### Subsystem partition

| Scale | Subsystems to partition |
|-------|--------------------------|
| Tiny | One subsystem (everything together) |
| Small | 3-5 standard subsystems |
| Medium | 6-12 standard subsystems |
| Large | 12+ subsystems including project-specific |
| Very large | Per-major-component subsystems; second-level partitions |

### Fixture suite size

| Scale | Fixture count |
|-------|---------------|
| Tiny | 3-5 |
| Small | 10-15 |
| Medium | 20-40 |
| Large | 40-80 + 5+ pair fixtures |
| Very large | 100+ + 10+ pair fixtures + 5+ adversarial scenarios |

### Pass cadence

| Scale | Add pass | Upgrade pass | Quarterly |
|-------|----------|--------------|-----------|
| Tiny | 1-2 hours | < 1 hour | re-score only |
| Small | 2-4 hours | 1-2 hours | scope review + 1-2 new FMs |
| Medium | 4-8 hours | 2-4 hours | 3-5 new FMs typical |
| Large | 8-16 hours | 4-8 hours | 5-10 new FMs |
| Very large | days | 1-2 days | broader subsystem reviews |

---

## Anti-patterns by scale

**Tiny scale:**
- Building all 15 cookbook patterns into a 200-line bash script. Overkill.
- Multi-model triangulation for a project that only one person uses. Pointless.

**Small scale:**
- Trying to hit aggregate ≥ 950 in pass-1. Stage 4-6 is enough; pursue stretch axioms in pass-2.

**Medium scale:**
- (No specific anti-patterns; this is the calibrated default.)

**Large scale:**
- Trying to do a "complete" pass that covers every FM. Always partial; commit + iterate.
- Skipping the meta-doctor (Pattern 12). At this scale, the doctor's own consistency is non-trivial.

**Very large scale:**
- Synchronous Phase 4 implementation. Use NTM swarms.
- Single-doctor architecture. Consider per-subsystem doctors federated by a meta-orchestrator.

---

## Scaling DOWN — when a project shrinks

Counter-intuitively, projects sometimes shrink (a refactor consolidates code; a feature is removed). The doctor SHOULD shrink too:

- Run [Axiom 21 decay analysis](KERNEL.md). Some fixers haven't been invoked in 6+ months.
- Per [OPS-RUNBOOK.md "When to retire a fixer"](OPS-RUNBOOK.md): mark `deprecated: true`; keep the source per AGENTS.md no-delete; eventually move to `deprecated/`.
- Aggregate score may drop slightly (fewer high-frequency detectors). Per the rubric, that's fine; the score's denominator shrinks too.

---

## Cross-cutting: workspace size

The workspace's own size grows over time:

- After 1 pass: ~200 KB.
- After 4 passes (1 year): ~2 MB.
- After 16 passes (4 years): ~10-20 MB.

The workspace is on disk forever (per AGENTS.md no-delete); it's checked into the workspace's own git history (which is a sibling to the target's). For very large projects, consider:

- Compressing per-pass historical artifacts (move `passes/<n-old>/` to `passes/<n-old>.tar.gz`).
- Periodic gc of `cass_findings_<old-pass>.jsonl` (keep summary; archive raw).

These are tooling enhancements; not foundational.

---

## When to NOT use the methodology at scale

- **The project is throw-away.** A one-shot demo doesn't need a doctor; the demo is over.
- **The project's lifetime is shorter than the doctor's value horizon.** A doctor takes hours to build and pays off over months.
- **The project is a wrapper for one external tool.** Pattern 8 covers this, but if the wrapper has zero state of its own, even Pattern 8 is overhead.
- **The project has perfect operational discipline already.** If incidents have been zero for a year, the doctor isn't justified.

The methodology has cost. Use it when the cost is less than the value.

---

## Scale and the kernel

The kernel's 24 axioms apply at every scale. What changes:

- The CARDINALITY (how many fixers, how many fixtures) scales with project size.
- The COST (per-axiom budget) scales with project size.
- The DISCIPLINE doesn't — every axiom holds at every scale.

A doctor at tiny scale that violates Axiom 1 (chokepoint) is just as broken as one at very large scale.
