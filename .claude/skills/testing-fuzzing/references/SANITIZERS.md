# Sanitizer Integration Guide

> Sanitizers are NON-NEGOTIABLE companions to fuzzing. A fuzzer without sanitizers is a random test generator, not a security tool.

## The Sanitizer Matrix

| Sanitizer | Flag | Detects | Overhead | When |
|-----------|------|---------|----------|------|
| **ASan** | `-fsanitize=address` | Buffer overflow, use-after-free, double-free, stack overflow | 2-4x | **ALWAYS** (default for cargo-fuzz) |
| **UBSan** | `-fsanitize=undefined` | Integer overflow, alignment, null deref, misaligned access | 1.2x | **ALWAYS** (combine with ASan) |
| **MSan** | `-fsanitize=memory` | Uninitialized memory reads | 3x | Unsafe code only |
| **TSan** | `-fsanitize=thread` | Data races, deadlocks | 5-15x | Concurrent code only |
| **LSan** | `-fsanitize=leak` | Memory leaks | 1.2x | Long-running targets |

**Incompatibility:** ASan and MSan cannot run simultaneously. ASan and TSan cannot run simultaneously. Run separate fuzzing campaigns.

## Usage

### Rust

```bash
# ASan (default for cargo-fuzz)
cargo fuzz run my_target

# UBSan (combine with ASan)
# cargo-fuzz doesn't have a direct flag; use RUSTFLAGS
RUSTFLAGS="-Zsanitizer=address,undefined" cargo +nightly fuzz run my_target

# MSan (for unsafe code — requires nightly)
RUSTFLAGS="-Zsanitizer=memory" cargo +nightly fuzz run my_target

# TSan (for concurrent code)
RUSTFLAGS="-Zsanitizer=thread" cargo +nightly fuzz run my_target

# Safe Rust only? Disable sanitizers for speed
cargo fuzz run my_target --sanitizer=none
```

### C/C++

```bash
# Compile with sanitizers
clang -g -O1 -fsanitize=fuzzer,address,undefined target.c -o target

# MSan requires full dependency rebuild
clang -g -O1 -fsanitize=fuzzer,memory -fno-omit-frame-pointer target.c

# TSan
clang -g -O1 -fsanitize=fuzzer,thread target.c
```

### Go

```bash
# Go's native fuzzer includes race detection by default
go test -fuzz=FuzzMyTarget -race
```

### Python

```bash
# Atheris with native extension sanitizers
# Build the extension with ASan first, then:
LD_PRELOAD=$(clang -print-file-name=libclang_rt.asan-x86_64.so) \
    python fuzz_target.py
```

## Environment Variables

```bash
# ASan options
ASAN_OPTIONS="verbosity=1:abort_on_error=1:detect_leaks=0:malloc_context_size=30"

# Disable RSS limit (cargo-fuzz sets 2GB by default, can cause false OOMs)
cargo fuzz run my_target -- -rss_limit_mb=0

# MSan options
MSAN_OPTIONS="verbosity=1"

# TSan options
TSAN_OPTIONS="verbosity=1:second_deadlock_stack=1"
```

## Sanitizer Strategy

```
Campaign 1: ASan + UBSan (ALWAYS run first)
    → Finds: buffer overflows, use-after-free, integer overflow
    → Duration: Hours to days

Campaign 2: MSan (if target has `unsafe` code)
    → Finds: uninitialized memory reads
    → Duration: Hours

Campaign 3: TSan (if target has concurrency)
    → Finds: data races, lock order violations
    → Duration: Hours

Rule: Share corpus across campaigns. Bugs found in one
campaign may expose deeper bugs under another sanitizer.
```

## Critical Warning

**NEVER deploy sanitizers in production.** Sanitizers:
- Add significant overhead
- Can be exploited (ASan shadow memory is predictable)
- Abort on violations (turns bugs into crashes)
- Are for testing ONLY

---

## MSan Full-Rebuild Requirement (CRITICAL)

**WARNING:** MSan requires **ALL** code in the process to be compiled with MSan instrumentation. If ANY dependency (including libc, libc++, or system libraries) is uninstrumented, MSan reports false positives on reads from those libraries.

### C/C++ MSan Full Rebuild

```bash
# Step 1: Build instrumented libc++
git clone https://github.com/llvm/llvm-project.git
cd llvm-project && mkdir build_msan && cd build_msan
cmake -G Ninja ../llvm -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
    -DLLVM_ENABLE_PROJECTS="libcxx;libcxxabi" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_USE_SANITIZER=MemoryWithOrigins
ninja cxx cxxabi

# Step 2: Build your target against instrumented libc++
clang++ -fsanitize=memory,fuzzer -stdlib=libc++ \
    -L/path/to/build_msan/lib -lc++abi \
    -I/path/to/build_msan/include/c++/v1 \
    target.cpp -o target_msan
```

### Rust MSan

cargo-fuzz handles MSan compilation automatically. However, if your Rust code links C libraries via `-sys` crates, those C libraries need MSan instrumentation too:

```bash
# Set C/CXX flags for sys crates
CFLAGS="-fsanitize=memory" CXXFLAGS="-fsanitize=memory" \
    RUSTFLAGS="-Zsanitizer=memory" cargo +nightly fuzz run my_target
```

---

## LSan (LeakSanitizer)

Detects memory leaks. Useful for fuzz targets in persistent mode where leaks accumulate.

```bash
# Standalone LSan
clang -g -fsanitize=leak target.c -o target_lsan

# LSan is included in ASan by default. To disable:
ASAN_OPTIONS="detect_leaks=0" cargo fuzz run my_target

# To enable more verbose leak reporting:
LSAN_OPTIONS="verbosity=1:log_threads=1" ./target corpus/
```

**When useful:** Persistent-mode fuzz targets that run millions of iterations. Small per-iteration leaks accumulate and eventually OOM.

---

## SanitizerCoverage (SanCov)

Advanced: custom coverage feedback for fuzzers.

```c
// The fuzzer calls these callbacks to learn about comparisons
void __sanitizer_cov_trace_cmp4(uint32_t arg1, uint32_t arg2);
void __sanitizer_cov_trace_cmp8(uint64_t arg1, uint64_t arg2);
void __sanitizer_cov_trace_switch(uint64_t val, uint64_t *cases);
```

This is how libFuzzer's `-use_cmp=1` and AFL++'s CMPLOG work under the hood. You rarely need to use SanCov directly, but understanding it helps explain why CMPLOG is so effective at bypassing magic-byte checks.

---

## Go Race Detector

```bash
# Enable during fuzzing
go test -fuzz=FuzzTarget -race

# Race detector adds ~5-10x overhead
# Disable for initial coverage exploration, enable for concurrency targets
go test -fuzz=FuzzTarget -fuzztime=60s       # Fast: no race detector
go test -fuzz=FuzzTarget -fuzztime=60s -race  # Thorough: with race detector
```

**Known nuances:**
- Race detector uses a finite-size shadow memory. Very long-running tests can exhaust it.
- Some lock-free algorithms trigger false positives (rare). Use `//go:nosync` annotations judiciously.
- `GORACE="halt_on_error=1"` makes race detector abort immediately (useful for fuzzing).

---

## Java Sanitizer Alternatives

The JVM doesn't support ASan/UBSan. Alternatives:

| Tool | Detects | How |
|------|---------|-----|
| Jazzer built-in detectors | Injection, SSRF, deserialization, regex DoS | Automatic with `@FuzzTest` |
| `-XX:+CheckJNICalls` | JNI boundary violations | JVM flag |
| `-ea` (enable assertions) | Assertion failures | JVM flag (always enable during fuzzing) |
| SpotBugs / FindBugs | Common bug patterns | Static analysis (complement to fuzzing) |
| Error Prone | Compile-time bug detection | Google's Java compiler plugin |

For JNI code (Java calling C/C++), build the native library with ASan and run:
```bash
LD_PRELOAD=$(clang -print-file-name=libclang_rt.asan-x86_64.so) \
    java -XX:+CheckJNICalls -ea -jar my-app.jar
```

---

## See Also

- [TRIAGE.md](TRIAGE.md) — After sanitizers find bugs, triage them here
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — ASan/MSan false positives and other sanitizer issues
- [PERFORMANCE-TUNING.md](PERFORMANCE-TUNING.md) — Sanitizer overhead affects exec/s budgets
