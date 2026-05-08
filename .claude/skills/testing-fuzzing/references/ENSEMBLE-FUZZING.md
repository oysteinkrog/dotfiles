# Ensemble Fuzzing: Multi-Engine Campaigns

Multi-engine fuzzing runs AFL++, libFuzzer, and honggfuzz simultaneously against the
same target, sharing a single corpus. Each engine uses different mutation strategies,
coverage feedback mechanisms, and scheduling heuristics, so they find different bugs.

---

## Why Ensemble

Every fuzzing engine has blind spots.

- **AFL++** excels at CMPLOG-assisted comparison solving and deterministic mutations but
  can stall on deeply nested state machines.
- **libFuzzer** is the fastest in-process engine but relies on a simpler mutation
  pipeline and misses inputs that require persistent-mode state accumulation.
- **honggfuzz** uses hardware feedback (Intel PT, BTS) that catches execution patterns
  invisible to software-only coverage, but its mutation strategies are less
  sophisticated than AFL++'s.

Running all three against the same target with a shared corpus means:
1. An input discovered by honggfuzz's hardware tracing is immediately available to
   AFL++'s CMPLOG analysis.
2. libFuzzer's speed generates raw volume that seeds the slower engines.
3. AFL++'s deterministic stage (bitflips, arithmetics) methodically explores regions
   the others skip.

The result: faster coverage growth, more diverse crash signatures, and shorter time to
find deep bugs.

### When Ensemble Beats Single Engine

- **Mixed barrier types** — target has magic bytes AND checksums AND state-dependent
  branches. No single engine handles all three well.
- **Diminishing returns** — single engine coverage plateaus after 24-48 hours. Adding a
  second engine typically breaks through within hours.
- **Critical security targets** — parsers, protocol handlers, crypto implementations
  where maximum coverage justifies the resource cost.
- **Pre-release audits** — time-boxed campaign (72h) where you need the best coverage
  achievable in that window.

---

## Practical Setup

### Prerequisites

```
# AFL++
apt install afl++ afl++-clang

# libFuzzer (via cargo-fuzz for Rust, or clang -fsanitize=fuzzer for C/C++)
cargo install cargo-fuzz

# honggfuzz
cargo install honggfuzz
# or for C/C++:
apt install honggfuzz
```

### Directory Layout

```
project/
  fuzz/
    corpus/              # Shared corpus (all engines read/write here)
    crashes/             # Merged crash directory
    afl-out/             # AFL++ output directory
    libfuzzer-out/       # libFuzzer artifacts
    honggfuzz-out/       # honggfuzz workspace
    dictionaries/        # Shared dictionaries
    merge-corpus.sh      # Automated merge script
```

### Shared Corpus Directory

All three engines use the same raw-file corpus format: one file per input, arbitrary
filenames, binary content. This is the foundation of ensemble fuzzing — no format
translation required.

```bash
# Create the shared corpus with seed inputs
mkdir -p fuzz/corpus
# Add initial seeds (valid inputs, edge cases, minimal examples)
cp seeds/* fuzz/corpus/
```

---

## Running the Engines Simultaneously

### AFL++ (primary instance + secondaries)

```bash
# Primary instance — runs deterministic mutations first
afl-fuzz -M main -i fuzz/corpus -o fuzz/afl-out \
  -x fuzz/dictionaries/target.dict \
  -- ./target_afl @@

# Secondary instance — skips deterministic stage, different power schedule
afl-fuzz -S sec01 -i fuzz/corpus -o fuzz/afl-out \
  -p rare -l 2 \
  -- ./target_afl @@
```

### libFuzzer

```bash
# Rust (cargo-fuzz)
cargo fuzz run target_name fuzz/corpus -- \
  -dict=fuzz/dictionaries/target.dict \
  -use_value_profile=1 \
  -jobs=4 -workers=4

# C/C++
./target_libfuzzer fuzz/corpus \
  -dict=fuzz/dictionaries/target.dict \
  -use_value_profile=1 \
  -jobs=4 -workers=4
```

### honggfuzz

```bash
# Rust
cargo hfuzz run target_name \
  --input fuzz/corpus \
  --output fuzz/honggfuzz-out \
  --dict fuzz/dictionaries/target.dict \
  --threads 4

# C/C++
honggfuzz -i fuzz/corpus -o fuzz/honggfuzz-out \
  -w fuzz/dictionaries/target.dict \
  -n 4 -- ./target_hfuzz
```

### Resource Allocation

On a 16-core machine, a reasonable split:

| Engine      | Cores | Role                                    |
|-------------|-------|-----------------------------------------|
| AFL++ main  | 1     | Deterministic mutations, CMPLOG         |
| AFL++ sec   | 3     | Havoc, rare power schedule              |
| libFuzzer   | 4     | Raw speed, value profiles               |
| honggfuzz   | 4     | Hardware feedback                       |
| Merge/cmin  | 1     | Periodic corpus maintenance             |
| OS/other    | 3     | Headroom                                |

---

## Corpus Sharing Protocol

The merge cycle is the heart of ensemble fuzzing. Without it, engines find inputs
independently but never cross-pollinate.

### Merge Script

```bash
#!/usr/bin/env bash
# merge-corpus.sh — run every 15-30 minutes via cron or loop
set -euo pipefail

SHARED="fuzz/corpus"
AFL_OUT="fuzz/afl-out"
HFUZZ_OUT="fuzz/honggfuzz-out"
LFUZZ_OUT="fuzz/libfuzzer-out"
MERGE_TMP="fuzz/.merge-tmp"

mkdir -p "$MERGE_TMP"

# 1. Collect all new inputs into merge dir
cp "$AFL_OUT"/main/queue/id:* "$MERGE_TMP/" 2>/dev/null || true
cp "$AFL_OUT"/sec01/queue/id:* "$MERGE_TMP/" 2>/dev/null || true
cp "$HFUZZ_OUT"/*.fuzz "$MERGE_TMP/" 2>/dev/null || true
# libFuzzer writes directly to corpus dir if configured, but check artifacts too
cp "$LFUZZ_OUT"/crash-* "$MERGE_TMP/" 2>/dev/null || true

# 2. Merge into shared corpus
# For libFuzzer-compatible targets:
./target_libfuzzer -merge=1 "$SHARED" "$MERGE_TMP"

# 3. Minimize the shared corpus
# AFL++
afl-cmin -i "$SHARED" -o "$SHARED.min" -- ./target_afl @@
rm -rf "$SHARED"
mv "$SHARED.min" "$SHARED"

# Or for Rust cargo-fuzz:
# cargo fuzz cmin target_name

# 4. Collect crashes
mkdir -p fuzz/crashes
cp "$AFL_OUT"/main/crashes/id:* fuzz/crashes/ 2>/dev/null || true
cp "$AFL_OUT"/sec01/crashes/id:* fuzz/crashes/ 2>/dev/null || true
cp "$HFUZZ_OUT"/SIGABRT.* fuzz/crashes/ 2>/dev/null || true

# 5. Cleanup
rm -rf "$MERGE_TMP"

echo "[$(date)] Merge complete. Corpus: $(ls "$SHARED" | wc -l) files"
```

### Automated Merge Loop

```bash
# Run merge every 20 minutes
while true; do
  bash fuzz/merge-corpus.sh
  sleep 1200
done
```

### Corpus Minimization

Minimization removes inputs that don't contribute unique coverage. Run it after every
merge to keep the corpus small and engines fast.

```bash
# AFL++
afl-cmin -i fuzz/corpus -o fuzz/corpus.min -- ./target @@
# Then replace corpus with minimized version

# cargo-fuzz (libFuzzer)
cargo fuzz cmin target_name

# honggfuzz
# honggfuzz does internal minimization; re-import the shared corpus after afl-cmin
```

---

## Engine-Specific Strengths

### AFL++

- **CMPLOG** — Instruments comparisons to solve magic bytes, checksums, and multi-byte
  constants. Enable with `-c 0` or a CMPLOG-instrumented binary.
- **Persistent mode** — Target function called in a loop without process restart.
  10-20x faster than fork mode.
- **Deterministic mutations** — Bitflips, arithmetic, interesting values. Methodical
  exploration that other engines skip.
- **Power schedules** — `-p explore`, `-p rare`, `-p fast`, `-p exploit`. Different
  schedules prioritize different queue entries.
- **Custom mutators** — Shared library API for structure-aware mutations.

### libFuzzer

- **In-process speed** — No fork overhead. Fastest raw exec/s for simple targets.
- **Value profiles** — `-use_value_profile=1` tracks comparison operand values, helping
  the fuzzer converge on magic bytes incrementally.
- **Merge mode** — `-merge=1` is the gold standard for corpus deduplication.
- **Built into clang** — Zero setup for C/C++ projects. Rust via `cargo-fuzz`.
- **SanitizerCoverage integration** — Tight coupling with ASan, MSan, UBSan.

### honggfuzz

- **Hardware feedback** — Intel Processor Trace (PT) and Branch Trace Store (BTS)
  capture execution flow at hardware level. Catches coverage invisible to
  software instrumentation.
- **Persistent mode** — Similar to AFL++, avoids fork overhead.
- **Robust crash detection** — Monitors for signals, timeouts, and custom exit codes.
- **Low setup overhead** — Minimal configuration needed for basic fuzzing.

---

## Architecture

```
                    +-----------+
                    |  Shared   |
              +---->|  Corpus   |<----+
              |     +-----------+     |
              |          ^            |
              |          |            |
         +----+----+  +-+--------+  ++---------+
         | AFL++   |  | libFuzzer|  | honggfuzz |
         | main    |  | (4 jobs) |  | (4 threads|
         | + sec01 |  |          |  |  + Intel  |
         | + sec02 |  |          |  |    PT)    |
         +---------+  +----------+  +-----------+
              |          |            |
              v          v            v
         +----+----+  +-+--------+  ++---------+
         | AFL     |  | libFuzzer|  | honggfuzz |
         | crashes |  | crashes  |  | crashes   |
         +---------+  +----------+  +-----------+
              \          |           /
               \         |          /
                v        v        v
              +------------------+
              | Periodic Merge   |
              | (merge-corpus.sh)|
              +--------+---------+
                       |
                       v
              +------------------+
              | Minimized Corpus |
              | (afl-cmin)       |
              +------------------+
                       |
                       v
              +------------------+
              | Shared Corpus    |
              | (fed back to all)|
              +------------------+
```

### Data Flow

1. Each engine reads seed inputs from the shared corpus at startup.
2. Engines write new interesting inputs to their own output directories.
3. Every 15-30 minutes, the merge script collects new inputs from all engines.
4. `afl-cmin` or libFuzzer `-merge=1` deduplicates and minimizes.
5. The minimized corpus replaces the shared corpus.
6. Engines pick up new inputs on their next queue scan.
7. Crashes from all engines are collected into a unified crash directory.

### Crash Deduplication

Multiple engines often find the same bug via different paths. Deduplicate:

```bash
# Use AFL++ crash exploration mode
afl-cmin -i fuzz/crashes -o fuzz/crashes.dedup -- ./target @@

# Or use casr-cluster for semantic deduplication
casr-cluster -i fuzz/crashes -o fuzz/crashes.dedup
```

---

## Monitoring

Track progress across all engines:

```bash
# AFL++ stats
afl-whatsup -s fuzz/afl-out

# libFuzzer — watch stderr output for cov: and exec/s lines
# honggfuzz — built-in TUI shows coverage and speed

# Combined coverage check
llvm-cov report ./target_cov \
  -instr-profile=merged.profdata \
  -ignore-filename-regex='test|fuzz'
```

### Signs the Ensemble Is Working

- Coverage increases after each merge cycle (visible in afl-whatsup or llvm-cov).
- Different engines contribute different crash signatures.
- No single engine accounts for more than 70% of unique coverage edges.

### Signs You Should Adjust

- One engine has zero new finds for hours — it may need different flags or a
  different power schedule.
- Merge cycle takes longer than the interval — increase the interval or reduce
  corpus size with more aggressive minimization.
- All engines plateau simultaneously — consider adding a custom mutator, a
  dictionary, or structure-aware fuzzing.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| AFL++ ignores shared corpus inputs | Wrong format or permissions | Ensure files are readable, run `afl-cmin` first |
| libFuzzer OOM during merge | Corpus too large | Split merge into batches, increase `-rss_limit_mb` |
| honggfuzz no coverage increase | Intel PT not available | Check `/proc/cpuinfo` for `intel_pt`, fall back to software mode |
| Merge script conflicts | Concurrent writes | Use `flock` or a temp directory swap |
| Engines fighting over disk I/O | Shared corpus on slow disk | Use tmpfs or SSD for corpus directory |

---

## See Also

- [AFLPP.md](AFLPP.md) — Deep dive on AFL++ flags, modes, and configuration
- [PERFORMANCE-TUNING.md](PERFORMANCE-TUNING.md) — Maximizing exec/s and coverage growth
- [CLOUD-FUZZING.md](CLOUD-FUZZING.md) — Scaling ensemble campaigns across cloud VMs
- [CORPUS.md](CORPUS.md) — Corpus construction, seeding, and maintenance
- [CUSTOM-MUTATORS.md](CUSTOM-MUTATORS.md) — Structure-aware mutations for ensemble diversity
