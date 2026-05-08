# Fuzzing Performance Tuning Guide

## The Performance Imperative

At equal coverage, a 10x faster fuzzer finds 10x more bugs. Fuzzing is a
numbers game: every cycle spent on overhead is a mutation that never runs.

**Target exec/s by category:**

| Target Type          | Minimum   | Good      | Excellent  |
|----------------------|-----------|-----------|------------|
| Trivial (hash, CRC)  | 5,000     | 10,000    | 50,000+    |
| Parser (JSON, XML)   | 500       | 1,000     | 5,000+     |
| Stateful (protocol)  | 50        | 100       | 500+       |
| Full-system (DB, FS) | 5         | 10        | 50+        |

If your parser target runs at 200 exec/s, you have a performance bug.
Fix it before burning CPU on a slow campaign.

---

## Measuring Performance

### libFuzzer

libFuzzer prints `exec/s` on every status line:

```
#12345  NEW    cov: 1024 ft: 2048 corp: 150/32Kb exec/s: 4523 rss: 45Mb
```

Watch the `exec/s` field. It should stabilize within 60 seconds. If it
keeps dropping, your target has a memory leak or growing allocation pattern.

### AFL++

```bash
afl-fuzz -i corpus -o output -- ./target @@
# Look for "execs_per_sec" in the status screen (top-right)
# Or parse output/default/fuzzer_stats:
grep execs_per_sec output/default/fuzzer_stats
```

### System-Level Profiling

```bash
# CPU cycles per execution — lower is better
perf stat -e cycles,instructions,cache-misses -- ./fuzz_target corpus/* 2>&1 | tail -20

# Wall-clock time and peak memory for a corpus run
/usr/bin/time -v ./fuzz_target -runs=10000 corpus/ 2>&1 | grep -E "wall clock|Maximum resident"

# Flamegraph of the fuzz loop (sample for 30 seconds)
perf record -g -F 999 -p $(pgrep fuzz_target) -- sleep 30
perf script | stackcollapse-perf.pl | flamegraph.pl > fuzz_flame.svg
```

**What bad looks like:** exec/s below 100 for a parser, `cache-misses`
above 10%, RSS growing over time, flamegraph dominated by malloc/free.

---

## Persistent Mode

### The Problem

Fork-per-input mode: fork() + exec() per test case = ~500us overhead each.
At 2000 exec/s ceiling, 80% of time is kernel overhead.

### libFuzzer (Already Persistent)

libFuzzer calls `LLVMFuzzerTestOneInput` in a loop within a single process.
No fork per input. This is why libFuzzer typically outperforms AFL++ out of
the box. Nothing to configure here.

### AFL++ Persistent Mode (C/C++)

```c
// Before (fork mode): ~800 exec/s
int main(int argc, char **argv) {
    // read from stdin or file, process, exit
}

// After (persistent mode): ~25,000 exec/s
__AFL_FUZZ_INIT();
int main(int argc, char **argv) {
    __AFL_INIT();                          // deferred fork server
    unsigned char *buf = __AFL_FUZZ_TESTCASE_BUF;
    while (__AFL_LOOP(10000)) {            // 10k iterations before re-fork
        int len = __AFL_FUZZ_TESTCASE_LEN;
        process_input(buf, len);
    }
    return 0;
}
```

Compile with `afl-clang-fast` or `afl-clang-lto` to enable.

### AFL++ Persistent Mode (Rust)

```rust
// Cargo.toml: afl = "0.15"
fn main() {
    afl::fuzz!(|data: &[u8]| {
        // This macro handles __AFL_LOOP internally
        let _ = my_parser::parse(data);
    });
}
```

### Go Native Fuzzer

Already persistent. The `func FuzzXxx(f *testing.F)` framework reuses the
process across inputs. No action needed.

### Typical Speedup

| Language / Mode       | Fork exec/s | Persistent exec/s | Speedup |
|-----------------------|-------------|-------------------|---------|
| C (AFL++)             | 800         | 25,000            | 31x     |
| Rust (AFL++)          | 600         | 18,000            | 30x     |
| C (libFuzzer)         | N/A         | 30,000            | -       |
| Rust (cargo-fuzz)     | N/A         | 20,000            | -       |

---

## Deferred Initialization

Move expensive one-time setup out of the fuzz loop.

### libFuzzer / cargo-fuzz (Rust)

```rust
use std::sync::OnceLock;

static CONFIG: OnceLock<MyConfig> = OnceLock::new();

fn init_config() -> &'static MyConfig {
    CONFIG.get_or_init(|| {
        // Expensive: parse config, build lookup tables, open DB
        MyConfig::load_from_defaults()
    })
}

fuzz_target!(|data: &[u8]| {
    let config = init_config(); // free after first call
    let _ = process(data, config);
});
```

### libFuzzer (C/C++)

```c
static DatabaseHandle *db = NULL;

int LLVMFuzzerInitialize(int *argc, char ***argv) {
    db = database_open(":memory:");   // once, not per-input
    load_schemas(db);
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    query_with(db, data, size);       // reuses connection
    return 0;
}
```

### AFL++ Deferred Init

```c
__AFL_FUZZ_INIT();
int main() {
    // Heavy setup BEFORE __AFL_INIT
    DatabaseHandle *db = database_open(":memory:");
    load_schemas(db);

    __AFL_INIT();   // fork server starts HERE — child inherits initialized state

    unsigned char *buf = __AFL_FUZZ_TESTCASE_BUF;
    while (__AFL_LOOP(10000)) {
        int len = __AFL_FUZZ_TESTCASE_LEN;
        query_with(db, buf, len);
    }
}
```

### Impact

| Setup Cost           | Without Deferred | With Deferred | Speedup |
|----------------------|-----------------|---------------|---------|
| Config parse (5ms)   | 200 exec/s      | 1,000 exec/s  | 5x      |
| DB init (50ms)       | 20 exec/s       | 1,000 exec/s  | 50x     |
| ML model load (2s)   | 0.5 exec/s      | 500 exec/s    | 1000x   |

---

## Fork Server Optimization

### How Fork Servers Work

AFL++ starts one copy of the target, which initializes up to `__AFL_INIT()`,
then forks for each input. The child inherits initialized memory, avoiding
re-initialization. Persistent mode (`__AFL_LOOP`) goes further by reusing
the child for N inputs before re-forking.

libFuzzer has no fork server. It runs entirely in-process. This makes it
faster but means a crash kills the fuzzer process (libFuzzer restarts itself).

### When Fork Mode is Necessary

Use fork-per-input when:
- The target corrupts global state (static variables, singletons)
- The target calls `exit()` or `abort()` on certain paths
- You need crash isolation for stability analysis

### libFuzzer `-fork=N`

```bash
# Run N parallel workers, each in its own forked process
# Useful for crash isolation + parallelism
./fuzz_target -fork=8 -jobs=0 corpus/
```

This is slower than in-process mode but provides crash isolation.
Use it when the target is unstable.

---

## libFuzzer Flags for Performance

```bash
./fuzz_target corpus/ \
    -use_value_profile=1 \    # intercept comparisons — 20% slower, finds more
    -use_cmp=1 \              # comparison logging (usually on by default)
    -entropic=1 \             # entropy-based power scheduling (default since ~2020)
    -len_control=0 \          # disable gradual length increase (raw byte targets)
    -max_len=4096 \           # hard cap on input size — smaller = faster
    -timeout=5 \              # kill inputs taking >5s (default 1200 is too generous)
    -rss_limit_mb=4096        # OOM threshold per worker
```

**Flag-by-flag impact:**

| Flag                   | Exec/s Impact | Coverage Impact | When to Use              |
|------------------------|---------------|-----------------|--------------------------|
| `-use_value_profile=1` | -20%          | +15-30%         | Always for non-trivial   |
| `-len_control=0`       | +10%          | Neutral         | Binary/raw-byte targets  |
| `-max_len=256`         | +50-200%      | May miss bugs   | When format is small     |
| `-entropic=1`          | -5%           | +10-20%         | Default, leave on        |
| `-timeout=5`           | +0-30%        | Neutral         | Prevents slow-input drag |

---

## AFL++ Flags for Performance

```bash
# Recommended baseline
AFL_AUTORESUME=1 AFL_IMPORT_FIRST=1 \
afl-fuzz -i corpus -o output \
    -p fast \           # power schedule: fast is best general-purpose
    -l 2 \              # CMPLOG level 2 (comparison logging)
    -- ./target_cmplog @@

# Environment variables for instrumentation
export AFL_LLVM_LAF_ALL=1       # split multi-byte comparisons
export AFL_LLVM_CMPLOG=1        # enable CMPLOG instrumentation
```

**Key flags:**

| Flag / Env Var          | Effect                                         |
|-------------------------|-------------------------------------------------|
| `-p fast`               | Power schedule — prioritizes fast-executing seeds |
| `-l 2`                  | CMPLOG — solves multi-byte comparisons           |
| `AFL_LLVM_LAF_ALL=1`    | Splits strcmp/memcmp into byte-level compares     |
| `AFL_AUTORESUME=1`      | Resume without clearing output dir               |
| `AFL_IMPORT_FIRST=1`    | Import all seeds before fuzzing starts           |
| `AFL_MAP_SIZE=2097152`  | Increase coverage map for large targets          |

---

## Parallel Fuzzing

### libFuzzer

```bash
# Run 8 parallel workers, each doing its own jobs
./fuzz_target corpus/ -jobs=8 -workers=8

# Or use -fork for crash isolation + parallelism
./fuzz_target corpus/ -fork=8
```

### AFL++

```bash
# Main instance (deterministic mutations)
afl-fuzz -M main -i corpus -o sync_dir -- ./target @@

# Secondary instances (random mutations, different power schedules)
afl-fuzz -S secondary01 -p fast    -i corpus -o sync_dir -- ./target @@
afl-fuzz -S secondary02 -p explore -i corpus -o sync_dir -- ./target @@
afl-fuzz -S secondary03 -p coe     -i corpus -o sync_dir -- ./target @@

# CMPLOG secondary (use a CMPLOG-instrumented binary)
afl-fuzz -S cmplog01 -l 2 -i corpus -o sync_dir -- ./target_cmplog @@
```

### Go

```bash
go test -fuzz=FuzzParse -parallel=8 -fuzztime=1h
```

### CPU Pinning

Pin fuzzer processes to cores for stable exec/s and reduced cache thrashing:

```bash
# Pin AFL++ main to core 0
taskset -c 0 afl-fuzz -M main -i corpus -o sync_dir -- ./target @@

# Pin secondaries to cores 1-7
for i in $(seq 1 7); do
    taskset -c $i afl-fuzz -S "sec$i" -i corpus -o sync_dir -- ./target @@ &
done
```

### How Many Cores

- 1 core per distinct fuzz target (minimum viable coverage)
- Remaining cores: split across highest-priority targets
- Diminishing returns beyond 8 cores on a single target (unless coverage is still growing)

---

## Memory Management

### RSS Limits

```bash
# cargo-fuzz default is 2GB — often too low for ASan
cargo fuzz run my_target -- -rss_limit_mb=4096

# libFuzzer
./fuzz_target -rss_limit_mb=4096 corpus/
```

### Per-Campaign Memory Budgets

| Sanitizer | Memory per Worker | Reason                           |
|-----------|-------------------|----------------------------------|
| ASan      | 4 GB              | 2x shadow memory overhead        |
| MSan      | 8 GB              | Full shadow + origin tracking    |
| TSan      | 4 GB              | Thread metadata overhead         |
| None      | 2 GB              | Baseline                         |

### Monitoring

libFuzzer reports RSS on every status line:

```
#50000  PULSE  cov: 2048 ft: 4096 corp: 300/64Kb exec/s: 3200 rss: 128Mb
```

If `rss:` grows monotonically, the target or harness leaks memory.

### Detecting Leaks

```bash
# Enable LeakSanitizer (included with ASan by default on Linux)
ASAN_OPTIONS=detect_leaks=1 ./fuzz_target -runs=100000 corpus/

# For Rust cargo-fuzz
LSAN_OPTIONS=suppressions=lsan_suppress.txt cargo fuzz run my_target
```

---

## Disk Management

### Corpus Size

Long campaigns produce large corpora. Plan for it:

| Duration  | Typical Corpus Size | Typical File Count |
|-----------|--------------------|--------------------|
| 1 hour    | 50 MB              | 5,000              |
| 24 hours  | 500 MB             | 50,000             |
| 1 week    | 5 GB               | 200,000            |
| 1 month   | 20-50 GB           | 1,000,000+         |

### tmpfs for Corpus I/O

Disk I/O becomes a bottleneck for fast targets. Use tmpfs:

```bash
# Create a 4GB tmpfs mount for corpus
sudo mount -t tmpfs -o size=4G tmpfs /mnt/fuzz_corpus

# Symlink or copy corpus
cp -r fuzz/corpus/my_target/* /mnt/fuzz_corpus/
cargo fuzz run my_target /mnt/fuzz_corpus

# AFL++: point output to tmpfs
afl-fuzz -i corpus -o /mnt/fuzz_output -- ./target @@
```

Impact: 10-30% exec/s improvement for targets above 5000 exec/s.

### Artifact Cleanup

```bash
# List crash/timeout/oom artifacts
ls -lah fuzz/artifacts/my_target/

# Deduplicate crashes (keep unique stack traces)
# cargo-fuzz stores artifacts with hash names; identical crashes get same name

# Periodic corpus minimization (run weekly for long campaigns)
cargo fuzz cmin my_target

# AFL++ corpus minimization
afl-cmin -i sync_dir/main/queue -o minimized_corpus -- ./target @@
```

### Disk Space Monitoring

```bash
# Watch corpus growth
watch -n 60 'du -sh fuzz/corpus/*/  fuzz/artifacts/*/ 2>/dev/null'

# Alert if corpus exceeds threshold
[ $(du -sm fuzz/corpus/my_target | cut -f1) -gt 10240 ] && echo "WARN: corpus > 10GB"
```

---

## Reducing Target Overhead

### Disable Logging

```rust
// Rust: compile out logging when fuzzing
#[cfg(not(fuzzing))]
fn log_event(msg: &str) {
    tracing::info!(msg);
}

#[cfg(fuzzing)]
fn log_event(_msg: &str) {}
```

For C/C++, use a no-op logger or `#ifdef FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION`.

### Use In-Memory I/O

Replace file reads/writes with in-memory buffers in the harness:

```rust
// Instead of: let data = std::fs::read("input.bin")?;
// The fuzzer already gives you the bytes:
fuzz_target!(|data: &[u8]| {
    let cursor = std::io::Cursor::new(data);
    my_parser::parse_from_reader(cursor);
});
```

### Reuse Allocations

```rust
use smallvec::SmallVec;

// Pre-allocate outside the hot path
thread_local! {
    static BUF: RefCell<Vec<u8>> = RefCell::new(Vec::with_capacity(65536));
}

fuzz_target!(|data: &[u8]| {
    BUF.with(|buf| {
        let mut buf = buf.borrow_mut();
        buf.clear();           // reuse, don't reallocate
        process(data, &mut buf);
    });
});
```

### Avoid HashMap in Fuzz Targets

`HashMap` uses random seeding, causing non-deterministic execution paths.
Use `BTreeMap` instead for deterministic behavior and often better
performance under fuzzer workloads (small maps, no hash overhead).

### Avoid Dynamic Dispatch

```rust
// Slow in hot path: ~5ns per call due to vtable lookup
fn process(handler: &dyn Handler, data: &[u8]) { ... }

// Fast: monomorphized, inlinable
fn process<H: Handler>(handler: &H, data: &[u8]) { ... }
```

---

## Coverage Optimization

### Identify Uncovered Branches

```bash
# Generate coverage report from corpus run
cargo fuzz coverage my_target

# View with llvm-cov
llvm-cov show target/x86_64-unknown-linux-gnu/coverage/x86_64-unknown-linux-gnu/release/my_target \
    -instr-profile=fuzz/coverage/my_target/coverage.profdata \
    -format=html -output-dir=cov_report/

# Open cov_report/index.html — red lines are uncovered
```

### Improve Coverage

1. **Seed inputs**: Craft inputs that exercise uncovered branches. If the
   coverage report shows a `magic == 0xDEADBEEF` check is never passed,
   add a seed input containing that value.

2. **Dictionary entries**: Tell the fuzzer about magic values:
   ```
   # my_target.dict
   magic_header="RIFF"
   version="\x01\x00"
   null_terminator="\x00"
   ```
   ```bash
   cargo fuzz run my_target -- -dict=my_target.dict
   ```

3. **Structure-aware fuzzing**: For complex formats, use `arbitrary` or
   `libprotobuf-mutator` instead of raw byte mutation. Coverage plateaus
   from random bytes are often structure problems.

4. **When to switch approaches**: If coverage has not increased in 4+ hours
   with a dictionary and good seeds, switch to grammar-based or
   structure-aware fuzzing. Raw byte mutation cannot efficiently produce
   valid ASN.1, protobuf, or deeply nested JSON.

---

## Benchmarking Protocol

### Before/After Measurement

Every optimization gets measured. No exceptions.

```bash
# Baseline: run for 60 seconds, record exec/s
cargo fuzz run my_target -- -max_total_time=60 2>&1 | grep exec/s | tail -1

# Apply optimization, rebuild, re-run
cargo fuzz run my_target -- -max_total_time=60 2>&1 | grep exec/s | tail -1
```

### Coverage Over Time

Track coverage growth to detect plateaus:

```bash
# Log coverage every 10 seconds (libFuzzer outputs this naturally)
cargo fuzz run my_target -- -print_pcs=1 -max_total_time=3600 2>&1 | \
    grep -E "^#[0-9]+" | awk '{print $1, $3}' > coverage_over_time.tsv
```

### Reference Baselines (FuzzBench)

Compare your exec/s against FuzzBench published results for similar targets.
If FuzzBench shows `libpng` at 5000 exec/s and you see 500, investigate.

### When to Stop Optimizing

| Exec/s Range    | Target Type | Verdict                        |
|-----------------|-------------|--------------------------------|
| > 10,000        | Parser      | Excellent. Focus on coverage.  |
| 5,000 - 10,000  | Parser      | Good enough. Move on.          |
| 1,000 - 5,000   | Parser      | Acceptable if coverage grows.  |
| < 1,000         | Parser      | Performance bug. Fix it.       |
| > 500           | Stateful    | Excellent for this category.   |
| > 50            | Full-system | Acceptable. Hard to improve.   |

---

## When to Stop Fuzzing

### Diminishing Returns Analysis

Monitor coverage growth rate. When it flattens, you are saturated:

```bash
# Check coverage delta over last N hours
# If cov: field has not increased in 24 hours of continuous fuzzing:
# Coverage is saturated for this configuration.
```

### Decision Tree

1. **No new coverage in 24 hours** with current seeds and configuration:
   - Add more seed inputs targeting uncovered branches (see coverage report)
   - Add dictionary entries for magic values and keywords
   - Try structure-aware mutations (`arbitrary`, `libprotobuf-mutator`)

2. **No new coverage in 48 hours** after adding seeds and dictionary:
   - Switch fuzzer engine (AFL++ if using libFuzzer, or vice versa)
   - Try different power schedules (`-p explore`, `-p rare`)
   - Enable CMPLOG (`-l 2`) if not already active

3. **No new coverage in 1 week** after engine changes:
   - Consider hybrid symbolic execution (KLEE, SymCC, Fuzzolic)
   - Consider concolic execution for deep path constraints
   - Run with different sanitizers (MSan finds different bugs than ASan)

4. **Declare coverage acceptable** when:
   - All reachable branches (per `llvm-cov`) are covered
   - Or: budget is exhausted and remaining uncovered code is unreachable
     or low-risk (error handling, debug logging)
   - Document final coverage percentage and remaining gaps

### Campaign Duration Rules of Thumb

| Goal                        | Minimum Duration |
|-----------------------------|------------------|
| Smoke test (CI)             | 60 seconds       |
| Pre-release validation      | 4-8 hours        |
| Security audit              | 48-72 hours      |
| Ongoing / background        | Continuous       |

A 60-second CI run catches the easy bugs. A 72-hour campaign finds the
subtle ones. Anything beyond a week on the same configuration without new
coverage is wasted electricity.

---

## Snapshot Fuzzing

### kAFL and Nyx

Snapshot fuzzing eliminates fork overhead entirely by snapshotting the process after expensive initialization and restoring that snapshot for each new input. This achieves 10-100x speedup over fork-based fuzzing for targets with heavy startup costs.

**How it works:** Intel Processor Trace (PT) provides hardware-assisted coverage feedback. The hypervisor (Nyx) takes a memory snapshot of the VM after the target completes initialization. For each new input, the VM is restored to the snapshot in microseconds, the input is injected, and PT records coverage.

**When to use snapshot fuzzing:**
- Database engines with schema loading (>100ms init)
- Kernel modules requiring boot sequence
- Firmware targets with >100ms boot time
- Targets with complex state setup that cannot be deferred with `__AFL_INIT`
- Any target where `LLVMFuzzerInitialize` takes >50ms

**Basic setup:**

```bash
# Install kAFL (requires KVM + Intel PT support)
git clone https://github.com/IntelLabs/kAFL.git
cd kAFL
make deploy

# Check hardware support
cat /proc/cpuinfo | grep -o 'intel_pt'   # must be present
lsmod | grep kvm_intel                   # KVM must be loaded

# Create a snapshot-ready target
# The target calls kAFL hypercall to signal "ready for input"
# kAFL takes snapshot at that point

# Run kAFL
python3 kAFL/kafl_fuzz.py \
    --kernel /path/to/kernel \
    --initrd /path/to/initrd \
    --work-dir /tmp/kafl_workdir \
    --seed-dir seeds/ \
    -p 8                                 # 8 parallel workers
```

**Nyx standalone (userspace targets):**

```bash
# Build target with Nyx agent
gcc -o target target.c -lnyx_agent

# In the target, mark the snapshot point:
#   nyx_init();           // connect to Nyx
#   nyx_snapshot();       // snapshot taken HERE
#   // ... process input below ...

# Run with Nyx frontend
nyx-fuzz --sharedir /tmp/nyx_share --workdir /tmp/nyx_out -p 4
```

**Performance comparison:**

| Target Type      | Fork Mode | Persistent Mode | Snapshot Mode |
|------------------|-----------|-----------------|---------------|
| SQLite (schema)  | 5 exec/s  | 50 exec/s       | 2,000 exec/s  |
| Kernel syscall   | 20 exec/s | N/A             | 5,000 exec/s  |
| Firmware (UEFI)  | 1 exec/s  | N/A             | 500 exec/s    |

---

## Flamegraph Interpretation for Fuzzing

### Profiling a Fuzz Harness

```bash
# Step 1: Build without sanitizers for clean profiling
cargo fuzz build my_target  # or compile your C target without -fsanitize=fuzzer

# Step 2: Run the corpus through the target under perf
perf record -g -F 4999 -- ./fuzz_target -runs=50000 corpus/ 2>/dev/null

# Step 3: Generate the flamegraph
perf script | stackcollapse-perf.pl | flamegraph.pl > fuzz_flame.svg

# Step 4: Open in browser
xdg-open fuzz_flame.svg   # or: open fuzz_flame.svg (macOS)
```

### Key Patterns to Look For

**1. Tall stacks in `malloc`/`free`/`realloc` (allocation overhead)**

If `malloc` and `free` together consume >20% of the flamegraph, the harness or target is allocating too heavily per input. Fix by reusing buffers:

```rust
// Before: new Vec every iteration
fuzz_target!(|data: &[u8]| {
    let mut buf = Vec::new();      // malloc per input
    process(data, &mut buf);
});                                // free per input

// After: thread-local reuse
thread_local! { static BUF: RefCell<Vec<u8>> = RefCell::new(Vec::with_capacity(65536)); }
fuzz_target!(|data: &[u8]| {
    BUF.with(|buf| {
        let mut buf = buf.borrow_mut();
        buf.clear();
        process(data, &mut buf);
    });
});
```

**2. `__sanitizer_cov_trace_*` functions (instrumentation overhead)**

These are the coverage instrumentation callbacks. They typically consume 5-15% of the profile. This is acceptable and expected -- do not try to eliminate them. If they consume >25%, the target has very high branch density relative to computation; consider `-use_value_profile=0` to reduce overhead.

**3. `fork`/`clone`/`wait4` (not using persistent mode)**

If you see kernel fork/clone in the flamegraph, the fuzzer is forking per input. Switch to persistent mode (AFL++ `__AFL_LOOP`) or use libFuzzer (in-process by default). This is the single highest-impact fix.

**4. Logging functions (`spdlog`, `tracing`, `log4j`, `fmt::print`)**

Any logging visible in the flamegraph should be disabled during fuzzing. Logging per input is pure waste:

```c
// C/C++: compile out with FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
#ifndef FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
    LOG_INFO("processing input of size %zu", size);
#endif
```

**5. Disk I/O (`write`, `read`, `fsync`, `open`/`close`)**

File I/O in the fuzz loop kills performance. Replace with in-memory variants:
- `fopen`/`fwrite` -> `fmemopen` or `open_memstream`
- `std::fs::write` -> `std::io::Cursor`
- Database file -> `:memory:` or tmpfs-backed path

**6. `memcpy`/`memmove` with large sizes**

If `memcpy` is prominent, inputs may be too large. Reduce `-max_len` or add an early `if (size > threshold) return;` guard.

### Quick Reference

| Flamegraph Pattern | Diagnosis | Fix | Expected Impact |
|---|---|---|---|
| Wide `malloc`/`free` | Allocation churn | Reuse buffers | 2-5x |
| `fork`/`clone` | No persistent mode | `__AFL_LOOP` or libFuzzer | 10-30x |
| `__sanitizer_cov_*` >25% | Dense branches | Acceptable (or `-use_value_profile=0`) | N/A |
| `LOG_*`/`tracing::*` | Active logging | Compile out or `#[cfg(fuzzing)]` | 1.5-3x |
| `write`/`fsync` | Disk I/O in loop | In-memory I/O | 2-10x |
| `memcpy` (wide) | Large inputs | Lower `-max_len` | 1.5-5x |

---

## Exact SymCC Commands

### Hybrid Fuzzing with SymCC + AFL++

SymCC is a compiler pass that builds symbolic execution into the target binary. Running it alongside AFL++ lets the symbolic engine solve hard constraints (magic bytes, checksums, nested conditions) that mutation alone cannot crack, then feeds those solutions back into AFL++'s corpus.

**Step 1: Build the SymCC-instrumented binary**

```bash
# Clone and build SymCC
git clone https://github.com/eurecom-s3/symcc.git
cd symcc && mkdir build && cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DQSYM_BACKEND=ON \
    -DZ3_DIR=/usr/lib/cmake/z3 ..
ninja

# Build your target with SymCC's compiler wrapper
export CC=/path/to/symcc/build/symcc
export CXX=/path/to/symcc/build/sym++
cd /path/to/target
make clean && make
cp target target_symcc
```

**Step 2: Build the AFL++-instrumented binary (normal)**

```bash
export CC=afl-clang-lto
export CXX=afl-clang-lto++
make clean && make
cp target target_afl
```

**Step 3: Start AFL++ as the primary fuzzer**

```bash
# Main AFL++ instance
afl-fuzz -M main -i seeds/ -o sync_dir -- ./target_afl @@
```

**Step 4: Run SymCC as a secondary, feeding findings back**

```bash
# symcc_fuzzing_helper bridges SymCC and AFL++
# It pulls inputs from AFL++'s queue, runs them through SymCC,
# and copies new coverage-increasing inputs back to AFL++'s sync dir
python3 /path/to/symcc/util/symcc_fuzzing_helper.py \
    -o sync_dir \
    -a main \
    -n symcc01 \
    -- ./target_symcc @@
```

**What happens at runtime:**
1. AFL++ mutates inputs and discovers new coverage via instrumentation
2. `symcc_fuzzing_helper` watches AFL++'s queue for new interesting inputs
3. For each new input, SymCC executes it symbolically, solving branch constraints
4. SymCC's solutions (concrete inputs that reach new paths) are written to `sync_dir/symcc01/queue/`
5. AFL++ automatically imports these via its sync mechanism
6. AFL++ mutates the SymCC-generated inputs, combining fuzzing reach with symbolic precision

**Expected impact:** SymCC typically breaks through coverage plateaus within minutes that AFL++ alone cannot solve in hours. Most effective on targets with multi-byte comparisons, checksums, and nested conditional chains.

```bash
# Monitor progress: compare coverage between AFL++ alone vs AFL++ + SymCC
afl-whatsup sync_dir/
# Look for: "total paths found" increasing faster with symcc01 active
```

---

## See Also

- [AFLPP.md](AFLPP.md) — Persistent mode (Section 4) and power schedules (Section 6) for AFL++
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — "Fuzzing is too slow" and other performance issues
- [CORPUS.md](CORPUS.md) — Corpus minimization directly improves exec/s
- [FUZZER-INTERNALS.md](FUZZER-INTERNALS.md) — Understanding coverage feedback helps diagnose performance
