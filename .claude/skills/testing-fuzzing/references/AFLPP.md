# AFL++ Deep Guide

Operator-grade reference for AFL++ (American Fuzzy Lop plus plus): the state-of-the-art
coverage-guided fuzzer. Covers compilation, modes, subtools, tuning, and language integrations.

---

## 1. Overview: AFL++ vs Vanilla AFL

AFL++ is a community fork of Michal Zalewski's original AFL. It incorporates years of
academic research and practical improvements that vanilla AFL never received:

- **CMPLOG** — automatic magic-byte solving (no manual dictionary needed)
- **Persistent mode** — 10-100x speedup via in-process looping
- **Custom mutator API** — pluggable mutation strategies
- **MOpt** — particle-swarm-optimized mutation scheduling
- **QEMU 5.1+ and Frida modes** — binary-only fuzzing
- **Redqueen-style input-to-state** — solves comparisons without source
- **Better scheduling** — multiple power schedules (fast, explore, rare, etc.)
- **LTO instrumentation** — link-time optimized, collision-free edge coverage

Vanilla AFL is unmaintained since 2017. Always use AFL++.

Repository: `https://github.com/AFLplusplus/AFLplusplus`

---

## 2. Installation

### From source (recommended for latest features)

```bash
sudo apt-get install -y build-essential python3-dev automake cmake git flex bison \
  libglib2.0-dev libpixman-1-dev python3-setuptools cargo libgtk-3-dev \
  lld llvm llvm-dev clang
git clone https://github.com/AFLplusplus/AFLplusplus
cd AFLplusplus
make distrib    # builds everything: afl-fuzz, QEMU mode, Frida mode, unicorn mode
sudo make install
```

`make distrib` vs `make all`: `distrib` includes QEMU, Frida, and unicorn support.
Use `make all` if you only need source-based fuzzing.

### Package managers

```bash
# Debian/Ubuntu (may lag behind upstream)
sudo apt install afl++

# Arch Linux
sudo pacman -S afl++

# macOS (Homebrew)
brew install aflplusplus
```

### Docker

```bash
docker pull aflplusplus/aflplusplus
docker run -ti -v $(pwd):/src aflplusplus/aflplusplus
```

The Docker image includes all modes (QEMU, Frida, unicorn) pre-built.

---

## 3. CMPLOG Mode (`-l` flag)

CMPLOG instruments comparison instructions to automatically solve magic bytes,
checksums, and multi-byte constants. It replaces the need for hand-crafted
dictionaries in most cases.

### When to use

- Parsers that check magic numbers (e.g., `if (header == 0x89504E47)` for PNG)
- Protocol implementations with fixed framing bytes
- Any target where coverage plateaus due to unsolved comparisons

### Compilation

Build two binaries: one normal, one with CMPLOG instrumentation:

```bash
# Normal instrumented binary
afl-cc -O2 -o target target.c

# CMPLOG-instrumented binary (used only for comparison logging)
AFL_LLVM_CMPLOG=1 afl-cc -O2 -o target_cmplog target.c
```

### Running

```bash
afl-fuzz -i corpus/ -o findings/ -l 2 -c ./target_cmplog -- ./target @@
```

### CMPLOG level modes

| Flag  | Behavior                                       | Use case                          |
|-------|-------------------------------------------------|-----------------------------------|
| `-l 1` | Arithmetic solving only                        | Simple integer comparisons        |
| `-l 2` | Arithmetic + transform solving (recommended)   | General-purpose, most targets     |
| `-l 2AT` | Level 2 + ASCII-to-integer transforms        | Targets parsing numeric strings   |
| `-l 3` | All transforms + brute force                   | Last resort, slower               |

**Default recommendation**: `-l 2` for most targets. Use `-l 2AT` if the target
parses text-encoded numbers (e.g., `atoi`, `strtol`).

---

## 4. Persistent Mode

Normal fuzzing forks a new process per input. Persistent mode loops inside a single
process, eliminating fork overhead.

### C: `__AFL_LOOP` macro

```c
#include <stdio.h>
#include <unistd.h>

__AFL_FUZZ_INIT();

int main(int argc, char **argv) {
    __AFL_INIT();                          // deferred init (optional)
    unsigned char *buf = __AFL_FUZZ_TESTCASE_BUF;

    while (__AFL_LOOP(10000)) {
        int len = __AFL_FUZZ_TESTCASE_LEN;
        if (len < 4) continue;
        parse_input(buf, len);             // your target function
    }
    return 0;
}
```

Key macros:
- `__AFL_FUZZ_INIT()` — declares shared-memory test case buffer
- `__AFL_FUZZ_TESTCASE_BUF` — pointer to current input bytes
- `__AFL_FUZZ_TESTCASE_LEN` — length of current input
- `__AFL_LOOP(N)` — loop N times before restarting the process

### Rust: `afl::fuzz!`

```rust
use afl::fuzz;

fn main() {
    fuzz!(|data: &[u8]| {
        let _ = my_parser::parse(data);
    });
}
```

The `afl::fuzz!` macro handles persistent mode automatically.

### Performance impact

| Mode        | Typical exec/s | Relative speedup |
|-------------|-----------------|-------------------|
| Fork mode   | 500-2,000       | 1x (baseline)     |
| Persistent  | 10,000-200,000  | 10-100x            |

The exact speedup depends on how expensive fork+exec is relative to the
target function. Lightweight parsers see the largest gains.

### Caveats

- Target function must not retain global state between iterations
  (or you must reset it manually)
- Memory leaks accumulate over N iterations — tune N accordingly
- Crashes during persistent mode are replayed in fork mode for confirmation

---

## 5. Deferred Initialization

`__AFL_INIT()` tells AFL++ to defer the fork point until after expensive startup
(config parsing, library loading, etc.).

### When to use

- Targets that load large config files, models, or databases at startup
- Targets with slow constructors or static initializers
- Any target where startup cost dominates per-iteration cost

### Placement rules

1. Place `__AFL_INIT()` **after** all one-time initialization
2. Place it **before** any code that reads or depends on the fuzz input
3. No file descriptors or threads may be open at the `__AFL_INIT()` point
   (they will not survive the fork)

```c
int main(int argc, char **argv) {
    load_config("/etc/target.conf");  // expensive one-time init
    init_lookup_tables();             // more startup work

    __AFL_INIT();                     // fork point: everything above runs once

    FILE *f = fopen(argv[1], "rb");   // now read fuzz input
    process(f);
    fclose(f);
    return 0;
}
```

---

## 6. Power Schedules (`-p`)

Power schedules control how much fuzzing energy (mutations) each seed receives.

```bash
afl-fuzz -i corpus/ -o findings/ -p fast -- ./target @@
```

| Schedule   | Strategy                                        | Best for                          |
|------------|-------------------------------------------------|-----------------------------------|
| `explore`  | Uniform energy across all seeds                 | Initial exploration phase         |
| `fast`     | Favor seeds exercised less often (default)      | **Most targets — recommended**    |
| `exploit`  | Favor seeds closer to new coverage              | Mature campaigns with stale seeds |
| `rare`     | Favor seeds hitting rare edges                  | Targets with large state spaces   |
| `mmopt`    | Modified MOpt integration                       | When MOpt alone underperforms     |
| `seek`     | Favor seeds that recently found new coverage    | Active exploration campaigns      |

**Default recommendation**: `-p fast` (this is the AFL++ default and wins on most
benchmarks). Use `-p explore` for the first few hours of a new target, then switch
to `-p fast`.

When running multi-core campaigns, assign different schedules to secondary instances:

```bash
afl-fuzz -M main -p fast    -i corpus/ -o findings/ -- ./target @@
afl-fuzz -S sec01 -p explore -i corpus/ -o findings/ -- ./target @@
afl-fuzz -S sec02 -p rare    -i corpus/ -o findings/ -- ./target @@
```

---

## 7. Custom Mutator API

AFL++ supports pluggable custom mutators for structure-aware fuzzing.

### API functions

| Function                     | Required | Purpose                                    |
|------------------------------|----------|--------------------------------------------|
| `afl_custom_init`            | Yes      | Initialize mutator state                   |
| `afl_custom_fuzz`            | No       | Generate a mutated test case               |
| `afl_custom_post_process`    | No       | Transform buffer before writing to disk    |
| `afl_custom_havoc_mutation`  | No       | Inject mutations during havoc stage        |
| `afl_custom_havoc_mutation_probability` | No | Probability of custom havoc firing  |
| `afl_custom_deinit`          | Yes      | Clean up mutator state                     |

### Complete C example: JSON-aware mutator

```c
#include "afl-fuzz.h"
#include <stdlib.h>
#include <string.h>

typedef struct {
    afl_state_t *afl;
    unsigned char *mutated;
    size_t mutated_size;
} my_mutator_t;

my_mutator_t *afl_custom_init(afl_state_t *afl, unsigned int seed) {
    my_mutator_t *data = calloc(1, sizeof(my_mutator_t));
    data->afl = afl;
    data->mutated = malloc(MAX_FILE);
    data->mutated_size = 0;
    srand(seed);
    return data;
}

size_t afl_custom_fuzz(my_mutator_t *data, uint8_t *buf, size_t buf_size,
                       uint8_t **out_buf, uint8_t *add_buf,
                       size_t add_buf_size, size_t max_size) {
    // Copy input, flip a random byte
    size_t len = buf_size < max_size ? buf_size : max_size;
    memcpy(data->mutated, buf, len);
    if (len > 0) {
        size_t pos = rand() % len;
        data->mutated[pos] ^= (1 + rand() % 255);
    }
    *out_buf = data->mutated;
    return len;
}

size_t afl_custom_post_process(my_mutator_t *data, uint8_t *buf,
                                size_t buf_size, uint8_t **out_buf) {
    // Ensure output is valid JSON by wrapping in braces if needed
    if (buf_size > 0 && buf[0] != '{') {
        data->mutated[0] = '{';
        memcpy(data->mutated + 1, buf, buf_size < MAX_FILE - 2 ? buf_size : MAX_FILE - 2);
        size_t new_len = (buf_size < MAX_FILE - 2 ? buf_size : MAX_FILE - 2) + 1;
        data->mutated[new_len] = '}';
        *out_buf = data->mutated;
        return new_len + 1;
    }
    *out_buf = buf;
    return buf_size;
}

void afl_custom_deinit(my_mutator_t *data) {
    free(data->mutated);
    free(data);
}
```

### Compilation and usage

```bash
gcc -shared -fPIC -O2 -o my_mutator.so my_mutator.c -I /path/to/AFLplusplus/include
AFL_CUSTOM_MUTATOR_LIBRARY=./my_mutator.so afl-fuzz -i corpus/ -o findings/ -- ./target @@
```

To combine with AFL++'s built-in mutators (recommended), also set:

```bash
AFL_CUSTOM_MUTATOR_ONLY=1  # use ONLY your mutator (not recommended unless you're sure)
```

Omit `AFL_CUSTOM_MUTATOR_ONLY` to let AFL++ use your mutator alongside its own.

---

## 8. MOpt Mutation Scheduling (`-L`)

MOpt uses particle-swarm optimization to select the best mutation operators
during fuzzing. It learns which operators produce new coverage most efficiently.

```bash
afl-fuzz -i corpus/ -o findings/ -L 0 -- ./target @@
```

`-L 0` enables MOpt in "pacemaker" mode from the start. Positive values (e.g.,
`-L 10`) delay MOpt activation until a coverage plateau lasting that many minutes.

### When it helps

- Mature campaigns where standard mutations have plateaued
- Targets with complex input structure (30% more unique bugs in LAVA-M benchmarks)
- Multi-day campaigns where mutation efficiency matters

### When to skip it

- Short campaigns (< 1 hour) — not enough time to learn operator weights
- Combined with custom mutators that already handle structure

---

## 9. QEMU Mode (`-Q`)

Fuzzes closed-source binaries using QEMU-based dynamic binary translation.

```bash
# Build QEMU support (done automatically by `make distrib`)
cd AFLplusplus/qemu_mode && ./build_qemu_support.sh

# Run
afl-fuzz -Q -i corpus/ -o findings/ -- ./closed_source_binary @@
```

### When to use

- Security audits of proprietary software
- Embedded firmware extracted from devices
- Any binary without source code

### Performance

Expect 2-5x slowdown compared to compile-time instrumentation. Persistent mode
is also available in QEMU mode via `AFL_QEMU_PERSISTENT_ADDR`.

```bash
# QEMU persistent mode (address of the function to loop)
AFL_QEMU_PERSISTENT_ADDR=0x401000 \
AFL_QEMU_PERSISTENT_CNT=10000 \
afl-fuzz -Q -i corpus/ -o findings/ -- ./target @@
```

### CMPLOG with QEMU

```bash
AFL_QEMU_CMPLOG=1 afl-fuzz -Q -c 0 -l 2 -i corpus/ -o findings/ -- ./target @@
```

The `-c 0` tells AFL++ to use the same binary for CMPLOG (since there is no
separate CMPLOG build for closed-source targets).

---

## 10. Frida Mode (`-O`)

Uses Frida for dynamic binary instrumentation. Faster than QEMU on most targets.

```bash
afl-fuzz -O -i corpus/ -o findings/ -- ./closed_source_binary @@
```

### When preferred over QEMU

- **macOS support** — QEMU mode does not support macOS; Frida does
- **Speed** — Frida is typically 1.5-3x faster than QEMU mode
- **ARM targets on ARM hosts** — native speed with Stalker engine

### Frida persistent mode

```bash
AFL_FRIDA_PERSISTENT_ADDR=0x401000 \
AFL_FRIDA_PERSISTENT_CNT=10000 \
afl-fuzz -O -i corpus/ -o findings/ -- ./target @@
```

### Limitations

- No snapshot support on all platforms
- Frida's Stalker can miss some edge cases in self-modifying code

---

## 11. AFL++ Subtools Reference

### `afl-cc` — Compiler wrapper

Wraps clang/gcc to inject instrumentation at compile time.

```bash
afl-cc -O2 -o target target.c           # auto-selects best instrumentation
afl-c++ -O2 -o target target.cpp        # C++ variant
AFL_USE_ASAN=1 afl-cc -o target target.c # with AddressSanitizer
```

Key env vars for `afl-cc`:
- `AFL_LLVM_INSTRUMENT=PCGUARD` — use PC-guard instrumentation (default, recommended)
- `AFL_LLVM_INSTRUMENT=CLASSIC` — classic AFL-style instrumentation
- `AFL_LLVM_INSTRUMENT=LTO` — link-time-optimized, collision-free (best quality)
- `AFL_LLVM_CMPLOG=1` — build a CMPLOG binary
- `AFL_USE_ASAN=1` — enable AddressSanitizer
- `AFL_USE_MSAN=1` — enable MemorySanitizer
- `AFL_USE_UBSAN=1` — enable UndefinedBehaviorSanitizer

### `afl-fuzz` — Main fuzzer

```
afl-fuzz -i <input_dir> -o <output_dir> [options] -- <target> [target_args]
```

Essential flags:

| Flag          | Purpose                                          |
|---------------|--------------------------------------------------|
| `-i dir`      | Input corpus directory                           |
| `-o dir`      | Output directory (findings, crashes, queue)       |
| `-M name`     | Main instance (multi-core)                       |
| `-S name`     | Secondary instance (multi-core)                  |
| `-p schedule` | Power schedule (fast, explore, rare, etc.)       |
| `-l level`    | CMPLOG level (1, 2, 2AT, 3)                     |
| `-c binary`   | CMPLOG binary path                               |
| `-L minutes`  | MOpt pacemaker (0 = immediate)                   |
| `-Q`          | QEMU mode (binary-only)                          |
| `-O`          | Frida mode (binary-only)                         |
| `-t ms`       | Timeout per execution (default: auto-calibrated) |
| `-m megs`     | Memory limit (default: 200 MB, `none` to disable)|
| `-x dict`     | Dictionary file                                  |
| `-D`          | Deterministic mutations (use sparingly)          |
| `-V seconds`  | Fuzz for this duration then exit                 |

### `afl-cmin` — Corpus minimizer

Reduces a corpus to the smallest set that maintains the same coverage.

```bash
afl-cmin -i large_corpus/ -o minimized_corpus/ -- ./target @@
afl-cmin -T 8 -i large_corpus/ -o minimized_corpus/ -- ./target @@  # 8 threads
```

### `afl-tmin` — Test case minimizer

Shrinks a single input while preserving the same crash or coverage path.

```bash
afl-tmin -i crash_input -o minimized_input -- ./target @@
afl-tmin -x -i crash_input -o minimized_input -- ./target @@  # exact crash mode
```

### `afl-showmap` — Coverage map viewer

Runs a single input and prints the coverage bitmap.

```bash
afl-showmap -o /dev/stdout -- ./target < input.bin
afl-showmap -C -i corpus/ -o coverage_map -- ./target @@  # cumulative coverage
```

### `afl-whatsup` — Campaign status

Displays summary of all running fuzzer instances.

```bash
afl-whatsup -s findings/     # summary: instances, speed, crashes, hangs
afl-whatsup findings/        # detailed per-instance view
```

### `afl-plot` — Coverage plot

Generates gnuplot graphs from fuzzer stats.

```bash
afl-plot findings/main/ plot_output/
# Open plot_output/index.html in a browser
```

### `afl-analyze` — Input analysis

Identifies which bytes in an input are "critical" (flipping them changes behavior).

```bash
afl-analyze -i input_file -- ./target @@
```

### `afl-gotcputime` — CPU timing

Measures CPU speed for AFL++ calibration.

```bash
afl-gotcputime
```

---

## 12. Key Environment Variables

### Instrumentation control

| Variable                      | Purpose                                          |
|-------------------------------|--------------------------------------------------|
| `AFL_LLVM_INSTRUMENT`         | Instrumentation backend: `PCGUARD`, `CLASSIC`, `LTO` |
| `AFL_LLVM_CMPLOG`            | Build with CMPLOG instrumentation (`=1`)         |
| `AFL_LLVM_LAF_ALL`           | Enable all LAF-Intel comparison splitting (`=1`) |
| `AFL_MAP_SIZE`                | Override shared memory map size (power of 2)     |

### Runtime control

| Variable                      | Purpose                                          |
|-------------------------------|--------------------------------------------------|
| `AFL_AUTORESUME`              | Resume a previous session without `-i-` (`=1`)   |
| `AFL_IMPORT_FIRST`            | Import test cases from other fuzzers first (`=1`)|
| `AFL_PRELOAD`                 | Preload shared library into target               |
| `AFL_NO_UI`                   | Disable the TUI status screen (`=1`)             |
| `AFL_SKIP_BIN_CHECK`          | Skip binary validation checks (`=1`)             |
| `AFL_CUSTOM_MUTATOR_LIBRARY`  | Path to custom mutator `.so`                     |
| `AFL_CUSTOM_MUTATOR_ONLY`     | Disable built-in mutators (`=1`)                 |
| `AFL_TMPDIR`                  | Directory for temp files (use ramdisk for speed) |
| `AFL_SKIP_CPUFREQ`           | Skip CPU frequency scaling check (`=1`)          |
| `AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES` | Skip crash uniqueness check (`=1`)  |
| `AFL_FORKSRV_INIT_TMOUT`     | Timeout for forkserver startup (ms)              |

### Sanitizer integration

```bash
AFL_USE_ASAN=1 afl-cc -o target target.c    # AddressSanitizer
AFL_USE_MSAN=1 afl-cc -o target target.c    # MemorySanitizer
AFL_USE_UBSAN=1 afl-cc -o target target.c   # UndefinedBehaviorSanitizer
AFL_USE_CFISAN=1 afl-cc -o target target.c  # Control-Flow Integrity
AFL_USE_TSAN=1 afl-cc -o target target.c    # ThreadSanitizer
AFL_USE_LSAN=1 afl-cc -o target target.c    # LeakSanitizer
```

**Important**: ASAN and MSAN cannot be combined. Run separate instances.

---

## 13. CmpCov / LAF-Intel Transforms

LAF-Intel (also called CmpCov) splits multi-byte comparisons into single-byte
comparisons so that the fuzzer can solve them incrementally.

### How it works

A comparison like `if (input == 0xDEADBEEF)` becomes four single-byte checks.
Each solved byte provides new coverage feedback, guiding the fuzzer to the full value.

### Enabling

```bash
AFL_LLVM_LAF_ALL=1 afl-cc -O2 -o target target.c
```

Individual transforms:

| Variable                     | What it splits                          |
|------------------------------|-----------------------------------------|
| `AFL_LLVM_LAF_SPLIT_SWITCHES` | Switch statements with large cases     |
| `AFL_LLVM_LAF_TRANSFORM_COMPARES` | `strcmp`, `memcmp` family         |
| `AFL_LLVM_LAF_SPLIT_COMPARES` | Multi-byte integer comparisons         |
| `AFL_LLVM_LAF_SPLIT_FLOATS`  | Floating-point comparisons              |
| `AFL_LLVM_LAF_ALL`           | All of the above                        |

### LAF-Intel vs CMPLOG

| Aspect         | LAF-Intel                    | CMPLOG                          |
|----------------|------------------------------|---------------------------------|
| Mechanism      | Compile-time transform       | Runtime comparison logging      |
| Binary size    | Larger (more edges)          | Separate binary needed          |
| Performance    | Slower (more edges to track) | Slight overhead during solve    |
| Effectiveness  | Good for integers            | Better for strings/magic bytes  |

**Recommendation**: Use CMPLOG (`-l 2`) as the primary solver. Add LAF-Intel only
if CMPLOG alone is not solving specific comparisons (e.g., `switch` with 100+ cases).

---

## 14. Multi-Core Fuzzing

AFL++ supports parallel fuzzing with one main instance and multiple secondaries.

### Basic setup

```bash
# Terminal 1: Main instance (deterministic mutations + sync)
afl-fuzz -M main -i corpus/ -o findings/ -p fast -l 2 -c ./target_cmplog -- ./target @@

# Terminal 2-N: Secondary instances
afl-fuzz -S sec01 -i corpus/ -o findings/ -p explore -- ./target @@
afl-fuzz -S sec02 -i corpus/ -o findings/ -p rare -- ./target @@
afl-fuzz -S sec03 -i corpus/ -o findings/ -p fast -L 0 -- ./target @@
```

### Scaling to 16+ cores

```bash
#!/bin/bash
# Launch script for 16-core campaign
CORPUS=corpus/
OUTPUT=findings/
TARGET="./target @@"
CMPLOG="./target_cmplog"

# 1 main instance with CMPLOG
afl-fuzz -M main -i $CORPUS -o $OUTPUT -p fast -l 2 -c $CMPLOG -- $TARGET &

# 5 secondaries with CMPLOG (varied power schedules)
for i in $(seq 1 5); do
    afl-fuzz -S "cmplog_$i" -i $CORPUS -o $OUTPUT -p fast -l 2 -c $CMPLOG -- $TARGET &
done

# 5 secondaries without CMPLOG (varied schedules)
SCHEDULES=(explore rare seek mmopt exploit)
for i in $(seq 0 4); do
    afl-fuzz -S "sched_$i" -i $CORPUS -o $OUTPUT -p "${SCHEDULES[$i]}" -- $TARGET &
done

# 3 secondaries with MOpt
for i in $(seq 1 3); do
    afl-fuzz -S "mopt_$i" -i $CORPUS -o $OUTPUT -L 0 -- $TARGET &
done

# 1 secondary with ASAN binary
afl-fuzz -S "asan" -i $CORPUS -o $OUTPUT -- ./target_asan @@ &

# 1 secondary with LAF-Intel binary
afl-fuzz -S "laf" -i $CORPUS -o $OUTPUT -- ./target_laf @@ &

wait
```

### Instance sync behavior

- The main instance (`-M`) syncs interesting inputs to all secondaries
- Secondaries (`-S`) import from the main's queue periodically
- All instances share the same `-o` output directory
- Crashes are deduplicated across instances

### Monitoring

```bash
watch -n 5 afl-whatsup -s findings/
```

---

## 15. AFL++ with Rust

### Setup with `cargo-afl`

```bash
cargo install cargo-afl
```

### Creating a fuzz target

```toml
# Cargo.toml
[package]
name = "my-fuzz"
version = "0.1.0"
edition = "2021"

[dependencies]
afl = "0.15"
my-library = { path = "../my-library" }
```

```rust
// src/main.rs
use afl::fuzz;

fn main() {
    fuzz!(|data: &[u8]| {
        // This runs in persistent mode automatically
        let _ = my_library::parse(data);
    });
}
```

### Building and running

```bash
# Build with AFL++ instrumentation
cargo afl build --release

# Create seed corpus
mkdir -p corpus/
echo '{"key": "value"}' > corpus/seed1.json

# Run the fuzzer
cargo afl fuzz -i corpus/ -o findings/ target/release/my-fuzz
```

### Adding CMPLOG

```bash
# Build a CMPLOG binary
RUSTFLAGS="-C llvm-args=-afl-cmplog" cargo afl build --release
cp target/release/my-fuzz target/release/my-fuzz-cmplog

# Rebuild the normal binary
cargo afl build --release

# Run with CMPLOG
cargo afl fuzz -i corpus/ -o findings/ -l 2 -c target/release/my-fuzz-cmplog \
  target/release/my-fuzz
```

### Integration with Bolero

Bolero provides a unified API for both `cargo-fuzz` (libFuzzer) and `cargo-afl`:

```rust
use bolero::check;

#[test]
fn fuzz_parse() {
    check!().for_each(|data: &[u8]| {
        let _ = my_library::parse(data);
    });
}
```

```bash
# Run with AFL++ backend
cargo bolero test fuzz_parse --engine afl --runs 1000000

# Run with libFuzzer backend
cargo bolero test fuzz_parse --engine libfuzzer
```

Bolero's value: write the harness once, run with either engine.

---

## 16. AFL++ with Go

### Options for fuzzing Go code

**Option 1: Native Go fuzzing (Go 1.18+)** — preferred for pure Go

```go
func FuzzParse(f *testing.F) {
    f.Add([]byte(`{"key":"value"}`))
    f.Fuzz(func(t *testing.T, data []byte) {
        _, _ = Parse(data)
    })
}
```

```bash
go test -fuzz=FuzzParse -fuzztime=1h
```

**Option 2: go-fuzz** — mature but pre-dates native fuzzing

```bash
go install github.com/dvyukov/go-fuzz/go-fuzz@latest
go install github.com/dvyukov/go-fuzz/go-fuzz-build@latest

go-fuzz-build -o fuzz.zip
go-fuzz -bin=fuzz.zip -workdir=fuzz_corpus/
```

**Option 3: AFL++ with Go instrumentation**

```bash
# Build with afl-cc via CGO
CC=afl-cc CGO_ENABLED=1 go build -o target ./cmd/target

# Run
afl-fuzz -i corpus/ -o findings/ -- ./target @@
```

### Recommendation

Use native Go fuzzing for Go-only code. Use AFL++ only when you need CMPLOG,
QEMU mode, or multi-core coordination that `go test -fuzz` does not support.

---

## 17. AFL++ vs libFuzzer Comparison

| Dimension                | AFL++                              | libFuzzer                          |
|--------------------------|------------------------------------|------------------------------------|
| **Execution model**      | Fork-based (or persistent)         | In-process only                    |
| **Speed (persistent)**   | High (10k-200k exec/s)            | Very high (50k-500k exec/s)       |
| **CMPLOG**               | Yes (automatic magic-byte solving) | No (needs manual dictionaries)     |
| **Binary-only fuzzing**  | Yes (QEMU, Frida modes)           | No                                 |
| **Multi-core**           | Native (-M/-S with sync)          | Manual (separate processes)        |
| **Custom mutators**      | Rich C API + Python bindings       | `LLVMFuzzerCustomMutator`         |
| **Corpus management**    | `afl-cmin`, `afl-tmin`            | `-merge=1`                         |
| **MOpt scheduling**      | Yes (`-L`)                         | No                                 |
| **Power schedules**      | 6 strategies (`-p`)               | No                                 |
| **Sanitizer support**    | Via `AFL_USE_*` env vars           | Native (same LLVM pipeline)        |
| **Rust integration**     | `cargo-afl`                        | `cargo-fuzz` (libfuzzer-sys)       |
| **OSS-Fuzz support**     | Yes                                | Yes (primary engine)               |

### When to choose AFL++

- You need CMPLOG to solve magic bytes automatically
- You are fuzzing closed-source binaries (QEMU/Frida)
- You want multi-core fuzzing with automatic sync
- You want MOpt or custom power schedules
- You are running long campaigns (days/weeks) where scheduling matters

### When to choose libFuzzer

- Maximum raw execution speed is the priority
- You are fuzzing a library with a clean `LLVMFuzzerTestOneInput` API
- You want tight integration with LLVM sanitizers
- You are contributing to OSS-Fuzz (libFuzzer is the default engine)
- Your target has no magic-byte barriers

### Best practice: run both

For critical targets, run both engines. They find different bugs due to different
mutation strategies and scheduling. Use Bolero (Rust) or a thin harness adapter
to share the same target code.

```bash
# AFL++ campaign (8 cores, 24 hours)
cargo afl fuzz -i corpus/ -o afl_findings/ -V 86400 target/release/fuzz_target

# libFuzzer campaign (8 cores, 24 hours)
cargo fuzz run fuzz_target -- -max_total_time=86400 -jobs=8 -workers=8
```

Merge corpora afterward:

```bash
# Import libFuzzer corpus into AFL++
cp libfuzzer_corpus/* afl_corpus/
afl-cmin -i afl_corpus/ -o merged_corpus/ -- ./target @@
```
