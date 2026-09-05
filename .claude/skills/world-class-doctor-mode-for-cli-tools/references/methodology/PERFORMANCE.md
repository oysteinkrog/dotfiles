# Performance — Detector Budgets and Hot-Path Discipline

A doctor that takes 30 seconds to diagnose is not used. A `health` command that hits 200ms feels instant. A pre-commit hook that adds 2s to every commit gets disabled within a day.

This file pins the budget per surface, the techniques to stay inside it, and how to profile when you've drifted.

---

## Budget table

| Surface | Budget | Used by | Strategy |
|---------|--------|---------|----------|
| `<tool> doctor health` | < 200 ms p95 | CI scheduling, oncall dashboards | Single fast-path detector chain; no I/O beyond `stat` and pidfile read; in-memory state checks only |
| `<tool> doctor --quick` | < 1 s p95 | Pre-commit hooks | Fast-path detectors only (those marked `tier: quick` in capabilities); no DB queries; no recursive scans |
| `<tool> doctor` (default diagnose) | < 5 s p95 on a typical workspace | Interactive use, `gh pr` review | All detectors; up to 1 DB query per detector; bounded scan depth |
| `<tool> doctor --fix` | < 30 s p95 | Manual repair | All detectors + all fixers; bounded by I/O of backup writes |
| `<tool> doctor --explain <id>` | < 500 ms | Agent expanding a finding | Pre-cached evidence from the most-recent run; no re-detection |
| `<tool> doctor capabilities --json` | < 50 ms | Agent discovery | Static; reflective from registry; no I/O |
| `<tool> doctor robot-docs` | < 50 ms | Agent in-tool docs | Static; bundled at build time |

p95 is the target; the kernel's Axiom 14 (bounded blast radius) implies bounded latency too. Outliers are bugs; investigate the slow detector.

---

## Detector tiering

Every detector declares its tier in `capabilities --json::detectors[].tier`:

- `tier: "quick"` — runs under `--quick` and in `health`. Budget: 5 ms each.
- `tier: "default"` — runs under bare `<tool> doctor`. Budget: 100 ms each.
- `tier: "deep"` — runs only when explicitly requested via `--include-deep`. Budget: 1 s each.
- `tier: "online"` — runs only with `--online`. Budget: 5 s each (network-bound).

Each tier's detectors run sequentially; tiers run in dependency order (quick → default → deep). Within a tier, detectors run in parallel (bounded by CPU count) when independent.

---

## Techniques per language

### Rust
- **Lazy-init regexes.** Per AGENTS.md § dcg, use `OnceCell` / `Lazy` for compiled regexes. Never compile-on-call.
- **Single-allocation paths.** `&Path` over `PathBuf` where the path is read-only.
- **`std::fs::metadata` over `std::fs::read`.** Stat-only checks (mtime, mode, size) avoid reading file contents.
- **Bounded scans.** `WalkDir::new(dir).max_depth(3)` — never unbounded recursion.

### Go
- **`sync.Once` for one-time setup.** Compile regexes, parse manifests once.
- **`os.Stat` over `os.ReadFile`.** Same lesson.
- **Bounded `filepath.Walk`.** Use `filepath.SkipDir` for explicit pruning.

### Python
- **`pathlib.Path.stat()` over `read_bytes()`.** Stat-only.
- **Module-level regex compiles.** `RE_X = re.compile(r"...")` at import time.
- **Generator-based scans.** `os.scandir()` lazily; break early.

### TypeScript / Node
- **`fs.stat` over `fs.readFile`.** Stat-only.
- **Cached compiled patterns.** Module-scope `const RE = /.../`.
- **Bounded async scans.** `for await (const entry of fs.opendir(dir))`; break.

---

## The hot-path file

For each language, the doctor module has ONE *hot-path file* that contains:

- The fast-path detector chain (10–20 detectors).
- The `health` implementation (which is just the fast-path chain returning a one-line summary).
- The `--quick` implementation (which is the fast-path chain returning the standard report shape).

This file gets lavish attention from Phase 7 fresh-eyes (especially prompt 1: "exit codes lying about reality"). It also gets benchmarked (`cargo bench`/`go test -bench`/`pytest --benchmark`) on every PR.

---

## When you've drifted

Symptoms:
- `<tool> doctor health` takes > 500 ms.
- Pre-commit hooks get disabled by users.
- CI doctor step shows up in the slow-CI report.

Triage:

1. **Profile.** `cargo flamegraph -- doctor health` (Rust); `go test -bench BenchmarkDoctorHealth -cpuprofile=cpu.prof` (Go); `python -m cProfile -o doctor.prof <path>/doctor health` (Python).
2. **Identify the slow detector.** Look for `__do_DETECTOR_NAME` in the flame graph.
3. **Classify.** Is it CPU-bound (regex / hashing / parsing) or I/O-bound (file reads, syscalls)?
4. **Fix.**
   - CPU-bound regex → lazy-init, simpler pattern, or move to `tier: "default"` if it can't fit `quick`.
   - I/O-bound → use `stat` over `read`, or move to `tier: "deep"`.
   - Network-bound → mark `online_required: true`, gate on `--online`.

The benchmark suite catches drift on PR review. Phase 6's scorecard generator includes `health_p95_ms` and fails the build if it drifts > 20% from the prior pass.

---

## Profile-guided detector selection

For very large doctors (50+ detectors), runtime profiling can choose which detectors to run *first*. The doctor records per-detector p50/p95 in `scorecard_history.jsonl`; subsequent runs run the highest-priority-per-cost detectors first. This is opt-in (`--profile-guided`) because deterministic order is usually more important than total speed.

---

## The `--budget` flag

`<tool> doctor --budget=5s` refuses to start if the estimated cost (sum of declared `estimated_cost_ms` in capabilities) exceeds the budget. This protects CI and pre-commit hooks from regressions where a new detector blows the budget.

```jsonc
// capabilities --json::cost_summary
{
  "cost_summary": {
    "quick_total_ms": 187,
    "default_total_ms": 1432,
    "deep_total_ms": 14237,
    "online_total_ms_estimate": 28000
  }
}
```

The estimate comes from p95 of recent runs in `scorecard_history.jsonl`. If a detector hasn't been run before, default 100 ms.

---

## Common pitfalls

- **Regex compilation on every detector call.** Use lazy-init.
- **`fs::read` instead of `fs::metadata` for stat-only checks.** Read the file only when you need its bytes.
- **Unbounded recursion.** A repo with 100k files is normal; doctor should handle it. Use bounded walkers or skip-rules.
- **Synchronous I/O in async runtime (TS/Bun).** Use the async APIs; the runtime is already async.
- **`subprocess` calls per detector** (e.g., `git log` once per detector). Batch: read `git log` once at run start, share the parse output across detectors.
- **JSON parsing on every call.** Parse once into a typed value; cache for the duration of the run.
