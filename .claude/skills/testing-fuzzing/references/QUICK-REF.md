# Fuzzing Quick Reference

Command cheat sheet. No explanations. See linked references for context.

---

## Setup

```bash
# Rust
cargo install cargo-fuzz honggfuzz
rustup default nightly  # cargo-fuzz requires nightly

# Go
go install golang.org/dl/gotip@latest && gotip download  # or use go 1.18+

# Python
pip install atheris

# TypeScript
npm install --save-dev fast-check  # property-based; or @jazzer.js/core for coverage-guided

# C/C++
apt install afl++ afl++-clang clang llvm  # or brew install afl++

# Java
# Jazzer: https://github.com/CodeIntelligenceTesting/jazzer
```

---

## Write Harness

```
Crash detector (panic/abort):        HARNESS-CATALOG.md #1
Round-trip (encode/decode):          HARNESS-CATALOG.md #2
Differential (two impls):            HARNESS-CATALOG.md #3
Grammar-based (structured input):    HARNESS-CATALOG.md #4
State machine (multi-step):          HARNESS-CATALOG.md #5
API sequence (method combinations):  HARNESS-CATALOG.md #6
```

---

## Run Fuzzer

```bash
# Rust — cargo-fuzz (libFuzzer)
cargo fuzz run TARGET
cargo fuzz run TARGET -- -max_total_time=3600 -jobs=4 -workers=4

# Rust — honggfuzz
cargo hfuzz run TARGET

# Rust — AFL++
cargo afl build && cargo afl fuzz -i corpus -o out -M main -- target/debug/TARGET

# Go
go test -fuzz=FuzzTarget -fuzztime=1h ./pkg/...

# Python
python3 harness.py  # atheris.Setup + atheris.Fuzz inside

# C/C++ — libFuzzer
clang -fsanitize=fuzzer,address -o target harness.c && ./target corpus/

# C/C++ — AFL++
afl-clang-fast -o target harness.c && afl-fuzz -i corpus -o out -- ./target @@

# C/C++ — honggfuzz
hfuzz-clang -o target harness.c && honggfuzz -i corpus -- ./target ___FILE___

# TypeScript — fast-check
npx vitest run --testPathPattern fuzz  # fast-check properties in test files

# Java — Jazzer
jazzer --cp=target.jar --target_class=FuzzTarget
```

---

## Minimize Corpus

```bash
# cargo-fuzz
cargo fuzz cmin TARGET

# AFL++
afl-cmin -i corpus -o corpus.min -- ./target @@

# libFuzzer
./target -merge=1 corpus.min corpus

# Go
# No built-in cmin; use corpus dir pruning manually

# honggfuzz
# Re-run with minimized input dir after afl-cmin
```

---

## Minimize Crash

```bash
# cargo-fuzz
cargo fuzz tmin TARGET crash-input

# AFL++
afl-tmin -i crash-input -o crash-min -- ./target @@

# libFuzzer
./target -minimize_crash=1 crash-input

# Go
go test -run=FuzzTarget/crash-input ./pkg/...  # reproduces; minimize manually
```

---

## Coverage Report

```bash
# Rust (cargo-fuzz)
cargo fuzz coverage TARGET
# Then: llvm-cov show target/x86_64.../release/TARGET \
#   -instr-profile=fuzz/coverage/TARGET/coverage.profdata \
#   -format=html -output-dir=cov-report

# Go
go test -coverprofile=cover.out -fuzz=FuzzTarget -fuzztime=10s ./pkg/...
go tool cover -html=cover.out -o cover.html

# C/C++ (source-based)
clang -fprofile-instr-generate -fcoverage-mapping -fsanitize=fuzzer -o target harness.c
./target corpus/ -runs=0
llvm-profdata merge -sparse default.profraw -o default.profdata
llvm-cov show ./target -instr-profile=default.profdata -format=html > cov.html
```

---

## Sanitizer Flags

```bash
# C/C++ — ASan + UBSan
clang -fsanitize=address,undefined -fno-sanitize-recover=all -o target harness.c

# C/C++ — MSan (uninitialized memory)
clang -fsanitize=memory -fno-sanitize-recover=all -o target harness.c

# C/C++ — TSan (data races)
clang -fsanitize=thread -o target harness.c

# Rust — ASan
RUSTFLAGS="-Zsanitizer=address" cargo fuzz run TARGET

# Rust — MSan (requires nightly + std rebuild)
RUSTFLAGS="-Zsanitizer=memory" cargo +nightly fuzz run TARGET -- -rss_limit_mb=4096

# Rust — TSan
RUSTFLAGS="-Zsanitizer=thread" cargo fuzz run TARGET

# Go
CGO_ENABLED=1 go test -race -fuzz=FuzzTarget ./pkg/...
```

---

## CI Commands

```bash
# Rust (GitHub Actions one-liner)
cargo fuzz run TARGET -- -max_total_time=300 -jobs=2 -workers=2

# Go
go test -fuzz=FuzzTarget -fuzztime=5m ./...

# C/C++ (pre-built binary)
./target corpus/ -max_total_time=300

# Python
timeout 300 python3 harness.py

# TypeScript
npx vitest run --testPathPattern fuzz --reporter=verbose
```

---

## Common Flags

```bash
# libFuzzer
-max_len=65536          # Max input size in bytes
-timeout=30             # Per-input timeout (seconds)
-dict=path/to/dict      # Dictionary file
-jobs=N                 # Parallel jobs
-workers=N              # Worker threads
-use_value_profile=1    # Track comparison values
-max_total_time=3600    # Campaign duration (seconds)
-rss_limit_mb=4096      # Memory limit
-runs=0                 # Run zero times (coverage only)
-print_final_stats=1    # Print stats at exit
-merge=1                # Corpus merge mode

# AFL++
-p schedule             # Power schedule: explore, rare, fast, exploit, coe
-l N                    # CMPLOG level: 1=transforms, 2=+routines, 3=+all
-M name                 # Primary instance
-S name                 # Secondary instance
-x dict                 # Dictionary
-t ms                   # Timeout per input (milliseconds)
-m megs                 # Memory limit (MB)
-V seconds              # Campaign duration
-c 0                    # Enable CMPLOG with auto-instrumented binary
```

---

## Dictionary Usage

```bash
# cargo-fuzz (libFuzzer)
cargo fuzz run TARGET -- -dict=fuzz/dictionaries/target.dict

# AFL++
afl-fuzz -x fuzz/dictionaries/target.dict -i corpus -o out -- ./target @@

# libFuzzer (C/C++)
./target corpus/ -dict=target.dict

# honggfuzz
honggfuzz -w target.dict -i corpus -- ./target ___FILE___
```

---

## Triage

```
1. Minimize      cargo fuzz tmin TARGET crash  |  afl-tmin -i crash -o min -- ./target @@
2. Reproduce     cargo fuzz run TARGET crash    |  ./target crash
3. Dedup         afl-cmin -i crashes/ -o dedup/ -- ./target @@  |  casr-cluster
4. Classify      ASan output -> stack trace -> root cause category
5. Fix           Patch code
6. Regress       Add minimized crash to corpus as regression test
```

---

## See Also

- [HARNESS-CATALOG.md](HARNESS-CATALOG.md) — Full harness patterns with code
- [AFLPP.md](AFLPP.md) — AFL++ deep dive
- [SANITIZERS.md](SANITIZERS.md) — Sanitizer setup and interpretation
- [DICTIONARIES.md](DICTIONARIES.md) — Writing and using dictionaries
- [TRIAGE.md](TRIAGE.md) — Full triage workflow
- [CI-FUZZING.md](CI-FUZZING.md) — CI integration details
- [ENSEMBLE-FUZZING.md](ENSEMBLE-FUZZING.md) — Multi-engine campaigns
- [CLOUD-FUZZING.md](CLOUD-FUZZING.md) — Cloud-scale fuzzing
- [PERFORMANCE-TUNING.md](PERFORMANCE-TUNING.md) — Optimizing exec/s
