# Fuzzing Troubleshooting Guide

## "Coverage isn't growing"

| Symptom | Cause | Fix |
|---------|-------|-----|
| `cov:` stuck at same number | Fuzzer can't bypass validation | Add dictionary with magic values |
| `cov:` grows slowly | Input format too strict for mutations | Switch to structure-aware (Arbitrary) |
| `ft:` stuck but `cov:` growing | Edge counts saturated | Enable `-use_value_profile=1` |
| `exec/s:` below 100 | Harness too slow | Move initialization to `LLVMFuzzerInitialize` |
| `corp:` growing but `cov:` not | Corpus bloat | Run `cargo fuzz cmin` |

## "OOM / RSS limit exceeded"

```bash
# Increase RSS limit (default: 2GB for cargo-fuzz)
cargo fuzz run my_target -- -rss_limit_mb=0    # Disable limit
cargo fuzz run my_target -- -rss_limit_mb=4096  # 4GB limit

# Bound input size in harness
if data.len() > MAX_INPUT_SIZE { return; }
```

**Root cause:** Usually unbounded allocation in the target (e.g., `Vec::with_capacity(attacker_controlled_size)`). Fix the target, don't just increase the limit.

## "Timeout"

```bash
# Increase per-input timeout (default: 10s for cargo-fuzz)
cargo fuzz run my_target -- -timeout=30

# But usually indicates a real bug:
# - Infinite loop in parser
# - Exponential regex backtracking
# - O(n²) algorithm with large input
```

## "Can't reproduce crash"

| Cause | Fix |
|-------|-----|
| Non-determinism in target | Remove `rand`, `SystemTime::now()`, `HashMap` iteration |
| Environment difference | Use same sanitizer flags, same nightly version |
| Crash was in sanitizer, not target | Check if crash is ASan false positive |
| File too large to repro | Run `cargo fuzz tmin` first |

## "ASan: heap-buffer-overflow" but code is safe Rust

This means the overflow is in a dependency's C code, a `build.rs` compiled library, or in the Rust standard library's allocator interaction. Check:

```bash
# Get detailed stack trace
ASAN_OPTIONS="symbolize=1:abort_on_error=1" cargo fuzz run my_target
```

## "Tests pass but fuzzer finds bugs"

This is expected and is WHY you fuzz. The fuzzer generates inputs your tests didn't consider. Convert each crash to a regression test:

```rust
#[test]
fn regression_crash_abc123() {
    let input = include_bytes!("../fuzz/artifacts/my_target/crash-abc123");
    let _ = my_crate::parse(input);
}
```

## "Fuzzing is too slow" (< 1000 exec/s)

| Bottleneck | Fix |
|-----------|-----|
| Expensive initialization per input | Move to `LLVMFuzzerInitialize` or `lazy_static` |
| Heap allocation in hot loop | Reuse buffers, use `SmallVec` |
| File I/O in target | Use in-memory variants |
| Logging in target | Disable logging during fuzzing |
| Target processes huge inputs | Add `if data.len() > N { return; }` early |

## "Workspace crate fuzzing won't build"

When your `fuzz/` directory lives inside a Cargo workspace, the fuzzer crate must be properly integrated:

**Common error messages:**
- `error: current package believes it's in a workspace when it's not`
- `error: failed to read /path/to/fuzz/Cargo.toml` (path dependency resolution failure)
- `error[E0463]: can't find crate for ...` when the fuzz target depends on a workspace member

**Fixes:**

1. **Add `fuzz/` as a workspace member** in the root `Cargo.toml`:
   ```toml
   [workspace]
   members = ["crates/*", "fuzz"]
   ```

2. **Or exclude it** (cargo-fuzz's default expectation) and make the fuzz crate standalone:
   ```toml
   [workspace]
   exclude = ["fuzz"]
   ```
   Then in `fuzz/Cargo.toml`, use a relative path dependency:
   ```toml
   [dependencies]
   my-crate = { path = ".." }
   ```

3. **Path dependency resolution**: If workspace members reference each other via `workspace = true` dependencies, the fuzz crate outside the workspace can't use that syntax. Spell out every dependency explicitly in `fuzz/Cargo.toml`.

4. **Profile inheritance**: Fuzz crates need `opt-level = 1` or higher for the target but `opt-level = 0` for debug info. When inside a workspace, profiles in the root `Cargo.toml` override `fuzz/Cargo.toml`. Add profile overrides in whichever `Cargo.toml` is authoritative:
   ```toml
   [profile.release]
   opt-level = 1
   debug = true
   ```

## "FFI boundary: sanitizer doesn't catch bugs in C code"

Sanitizer instrumentation must propagate across every compilation unit. When your Rust code calls C code (or Python calls a C extension), the C side must also be compiled with sanitizer flags.

**Rust calling C via `build.rs` or `-sys` crate:**

```bash
# Set BOTH Rust and C compiler flags
export RUSTFLAGS="-Zsanitizer=address"
export CFLAGS="-fsanitize=address -fno-omit-frame-pointer"
export CXXFLAGS="-fsanitize=address -fno-omit-frame-pointer"
cargo +nightly fuzz run my_target
```

If the `-sys` crate uses `cc` or `cmake` build scripts, these environment variables are usually picked up automatically. If the crate uses a pre-built vendored library, you may need to rebuild it from source with sanitizer flags.

**Python C extensions with Atheris:**

```bash
# Build the C extension with sanitizers BEFORE running the fuzzer
CC="clang" CFLAGS="-fsanitize=address,fuzzer-no-link -fno-omit-frame-pointer" \
    pip install --no-binary :all: <package>

# Then run Atheris with the sanitized extension loaded
LD_PRELOAD=$(clang -print-file-name=libclang_rt.asan-x86_64.so) \
    python my_fuzz_harness.py
```

**Verification**: If ASan is working across FFI, you'll see `AddressSanitizer` in the startup banner. If you only see `SanitizerCoverage`, the C code is traced for coverage but NOT checked for memory errors.

## "Non-deterministic crashes"

If a crash input reproduces fewer than 10 out of 10 times, you have non-determinism. This makes debugging extremely difficult.

**Diagnostic:**
```bash
# Run crash input 10 times, count successes
for i in $(seq 1 10); do
    cargo fuzz run my_target fuzz/artifacts/my_target/crash-XYZ 2>&1 | grep -c "SUMMARY"
done
# If count < 10, you have non-determinism
```

**Sources and fixes:**

| Source | Why it causes non-determinism | Fix |
|--------|-------------------------------|-----|
| `HashMap` iteration order | Different ordering triggers different code paths | Use `BTreeMap` or `IndexMap` in the code under test |
| Thread scheduling | Race conditions change behavior per run | Pin threads to cores, or use a single-threaded harness |
| `SystemTime::now()` / `Instant` | Time-dependent branching | Mock time with `mock_instant` or pass a clock trait |
| `rand` / `thread_rng()` | Random choices inside target | Seed all RNGs deterministically, or inject the RNG |
| `HashMap` with random seed | Rust's `HashMap` seeds its hasher randomly | Use `ahash` with a fixed seed, or `BTreeMap` |
| Signal handling | Asynchronous signal delivery | Mask signals during fuzz target execution |

**Nuclear option**: If you can't eliminate non-determinism, run the crash input under `rr record` to get a fully deterministic replay you can debug.

## "ASan false positive in safe Rust"

If AddressSanitizer reports a heap-buffer-overflow or use-after-free but your code is 100% safe Rust (no `unsafe`, no FFI), the bug is almost certainly in a C dependency linked via `build.rs` or a `-sys` crate.

**Diagnosis:**

```bash
# Get a symbolized stack trace
ASAN_OPTIONS="symbolize=1:print_legend=1:abort_on_error=1" cargo fuzz run my_target
```

**What to look for in the stack trace:**
- Frames from `.c`, `.cc`, `.cpp` files -- the bug is in C/C++ code
- Frames in `libsomething.so` -- an uninstrumented shared library
- Frames in `__rust_alloc` / `__rdl_alloc` -- allocator interaction (rare, usually a real bug)

**If the trace points to a C dependency:** File an issue upstream with the crash input and sanitizer output. In the meantime, you can suppress the specific report:

```bash
# Create a suppression file
echo "leak:third_party_function_name" > asan_suppressions.txt
ASAN_OPTIONS="suppressions=asan_suppressions.txt" cargo fuzz run my_target
```

**If you genuinely have no C code anywhere:** Check for `#[repr(C)]` structs with padding -- ASan can flag reads of padding bytes. This is still a real issue worth fixing.

## "MSan false positives everywhere"

MemorySanitizer (MSan) reports flood-level false positives when uninstrumented libraries return memory that MSan considers "uninitialized" because it never saw the writes.

**Classic symptom:** Every call to a function in a C library triggers an uninitialized-memory report, even though the library is correct.

**Root cause:** MSan tracks initialization at the byte level. If a library was compiled WITHOUT `-fsanitize=memory`, MSan never sees its memory writes and assumes everything it returns is uninitialized.

**Fix: Rebuild ALL dependencies with MSan:**

```bash
export RUSTFLAGS="-Zsanitizer=memory"
export CFLAGS="-fsanitize=memory -fPIE -fno-omit-frame-pointer"
export CXXFLAGS="-fsanitize=memory -fPIE -fno-omit-frame-pointer"
# You may also need to rebuild libc++ with MSan for C++ deps
cargo +nightly fuzz run my_target
```

**If rebuilding everything is impractical:**

- Exclude specific functions with `__attribute__((no_sanitize("memory")))` (C/C++ side only)
- Use an MSan ignorelist file:
  ```
  # msan_ignorelist.txt
  fun:third_party_*
  src:vendor/*
  ```
  ```bash
  CFLAGS="-fsanitize=memory -fsanitize-ignorelist=msan_ignorelist.txt" ...
  ```

**General advice:** MSan is the hardest sanitizer to deploy correctly. Start with ASan (much more forgiving of uninstrumented code) and only move to MSan when you've eliminated all ASan findings first.

## "Corpus too large (> 10GB)"

A bloated corpus slows down fuzzing (more I/O, longer corpus loads) and consumes CI disk space.

**Immediate fix -- minimize the corpus:**

```bash
# Remove inputs that don't contribute unique coverage
cargo fuzz cmin my_target

# For libFuzzer directly:
# ./fuzzer -merge=1 new_corpus/ old_corpus/
```

**Prevent future bloat:**

```bash
# Limit individual input size (e.g., 64KB max)
cargo fuzz run my_target -- -max_len=65536

# In the harness, reject oversized inputs early:
if data.len() > MAX_INPUT_SIZE { return; }
```

**Performance: use tmpfs for the corpus:**

```bash
# Mount a RAM-backed filesystem for I/O-heavy fuzzing
sudo mount -t tmpfs -o size=4G tmpfs /tmp/fuzz-corpus
cargo fuzz run my_target /tmp/fuzz-corpus
```

**CI considerations:**
- Set disk usage alerts (e.g., fail CI if corpus exceeds 2GB)
- Run `cargo fuzz cmin` as a scheduled CI job
- Store corpus in object storage (S3/GCS) rather than in the git repo
- Use `.gitignore` to exclude corpus directories; fetch on demand

## "Fuzzing embedded / no_std target"

Fuzzing `no_std` code presents challenges because libFuzzer and cargo-fuzz assume a standard library environment.

**Option 1: Extract parser logic into a std-compatible test crate** (recommended)

```toml
# fuzz-shim/Cargo.toml
[dependencies]
my-no-std-crate = { path = "..", default-features = false }
```

```rust
// fuzz-shim/src/lib.rs — thin wrapper that re-exports parsers
pub use my_no_std_crate::parse_packet;
```

Then fuzz the shim crate normally with cargo-fuzz. This works for any pure logic (parsers, codecs, state machines) that doesn't require hardware access.

**Option 2: AFL++ QEMU mode for binary-only fuzzing**

When the code can't be extracted (e.g., it interacts with memory-mapped I/O):

```bash
# Build for the target architecture
cargo build --target thumbv7em-none-eabihf --release

# Fuzz the binary with AFL++ QEMU mode
AFL_QEMU_PERSISTENT_ADDR=0x08001234 \
afl-fuzz -Q -i seeds/ -o findings/ -- ./target/thumbv7em-none-eabihf/release/firmware
```

**Option 3: Renode / QEMU full-system emulation**

For hardware-dependent code, run the full firmware in an emulator and fuzz the input interfaces (UART, SPI, network).

**Key considerations:**
- `no_std` allocators (`alloc` crate) work fine with cargo-fuzz if you provide a global allocator
- `panic = "abort"` is required for fuzzing (the default for cargo-fuzz)
- Hardware abstraction layers (HALs) can often be stubbed for fuzzing

## "Go fuzz test panics with 'too many open files'"

The Go fuzzer spawns multiple worker processes, each of which opens corpus files and intermediate state. On systems with low default file descriptor limits, this exhausts the limit quickly.

**Immediate fix:**

```bash
# Increase the file descriptor limit for the current shell
ulimit -n 65536

# Then run the fuzz test
go test -fuzz=FuzzMyParser -fuzztime=30s ./pkg/parser/
```

**Or reduce parallelism:**

```bash
# Limit the number of fuzzing workers
go test -fuzz=FuzzMyParser -parallel=2 -fuzztime=30s ./pkg/parser/
```

**Permanent fix (Linux):**

```bash
# /etc/security/limits.conf
*  soft  nofile  65536
*  hard  nofile  65536
```

**In CI (GitHub Actions):**
```yaml
- name: Raise file descriptor limit
  run: ulimit -n 65536
- name: Fuzz
  run: go test -fuzz=FuzzMyParser -fuzztime=60s ./...
```

## "Jazzer.js / fast-check: out of memory"

Node.js has a relatively small default heap (1.5-2GB depending on version), which is easily exhausted by long fuzzing sessions.

**Increase Node.js heap size:**

```bash
# Set via environment variable
NODE_OPTIONS="--max-old-space-size=4096" npx jazzer my_fuzz_target

# Or for fast-check property tests
NODE_OPTIONS="--max-old-space-size=4096" npx vitest run --test-timeout=60000
```

**For fast-check specifically -- reduce memory pressure:**

```typescript
// Reduce the number of runs
fc.assert(fc.property(myArbitrary, (input) => { ... }), { numRuns: 1000 }); // default is 100 but complex arbs grow

// Add size constraints to arbitraries
fc.string({ maxLength: 256 })       // instead of unbounded fc.string()
fc.array(fc.integer(), { maxLength: 100 }) // instead of unbounded fc.array()

// Use fc.configureGlobal for all tests
fc.configureGlobal({ numRuns: 500, maxSize: 'small' });
```

**Diagnosing the leak:**

```bash
# Run with heap snapshots to find the leak
NODE_OPTIONS="--max-old-space-size=4096 --inspect" npx jazzer my_target
# Connect Chrome DevTools, take heap snapshots at intervals
```

**Common culprits:**
- Accumulating all generated inputs in memory (fast-check stores counterexamples)
- Fuzzer target leaks closures or event listeners
- Global caches grow without bounds during long fuzz sessions
- Large generated inputs (deeply nested objects, huge arrays) -- constrain arbitraries
