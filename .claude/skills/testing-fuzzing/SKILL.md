---
name: testing-fuzzing
description: >-
  Fuzzing harnesses for crash discovery, security auditing, and correctness
  verification. Coverage-guided, structure-aware, differential, stateful,
  protocol, and API fuzzing with code instrumentation for fuzzability.
  AFL++ CMPLOG, persistent mode, sanitizers, custom mutators.
  Use when: testing parsers, protocols, serialization, cryptography,
  state machines, file formats, APIs, or smart contracts.
  Rust, Go, C/C++, Java, Python, TypeScript.
metadata:
  filePattern:
    - "**/fuzz*"
    - "**/fuzz_targets/**"
    - "**/fuzz/Cargo.toml"
    - "**/testdata/fuzz/**"
    - "**/*_fuzz_test.go"
    - "**/*_fuzz.go"
    - "**/*_fuzz.py"
    - "**/fuzz_target*.py"
    - "**/fuzz_target*.js"
    - "**/fuzz_target*.ts"
    - "**/.clusterfuzzlite/**"
    - "**/oss-fuzz/**"
    - "**/fuzz/dicts/**"
    - "**/*.dict"
    - "**/*.options"
    - "**/fuzz-corpus/**"
    - "**/fuzz_corpus/**"
    - "**/.hypothesis/**"
    - "**/.jazzer/**"
    - "**/*property_test*"
    - "**/.echidna.yml"
    - "**/echidna.yaml"
    - "**/foundry.toml"
  bashPattern:
    - "\\b(cargo[\\s.-]fuzz|cargo-fuzz|libfuzzer|afl-fuzz|afl-cc|afl-cmin|afl-tmin|afl-showmap|afl-whatsup|afl-plot|afl-analyze)\\b"
    - "\\b(honggfuzz|bolero|fuzz_target|fuzz_mutator|atheris|jazzer|fast-check|fc\\.assert)\\b"
    - "\\b(go\\s+test.*-fuzz|FuzzedDataProvider|schemathesis|hypothesis.*fuzz|boofuzz|radamsa|zzuf)\\b"
    - "\\b(clusterfuzz|oss-fuzz|libprotobuf-mutator|jqf|echidna|forge\\s+fuzz|Medusa|medusa)\\b"
    - "\\b(fsanitize|sanitizer|cargo\\s+careful|miri|sidefuzz)\\b"
    - "\\b(LLVMFuzzerTestOneInput|LLVMFuzzerInitialize|LLVMFuzzerCustomMutator|TestOneInput)\\b"
    - "\\b(sqlfuzz|sqlsmith|csmith|yarpgen|grammarinator)\\b"
    - "\\b(RuleBasedStateMachine|fc\\.commands|fc\\.modelRun)\\b"
  priority: 60
---

# Fuzzing

> **The One Rule:** Throw random-but-intelligent inputs at code until something breaks.
> Profile the fuzzer, not the code. A fuzzer that never reaches deep code paths finds nothing.

---

## Hard Rules (Non-Negotiable)

These are not guidelines. Violating any of these makes your fuzzing infrastructure defective.

| # | Rule | Why |
|---|------|-----|
| 1 | **1000 exec/s minimum for parsers, 100 for stateful targets, or your harness is broken.** Below these floors, stop and fix. See [PERFORMANCE-TUNING.md](references/PERFORMANCE-TUNING.md) for per-category targets. | Speed is the dominant factor. At equal coverage, 10x faster = 10x more bugs. |
| 2 | **Fuzz the parser, not the application.** Target the narrowest input-processing boundary. | Fuzzing the outermost API wastes coverage on routing/validation before reaching interesting code. |
| 3 | **Every `pub fn` accepting `&[u8]`, `&str`, `impl Read`, `[]byte`, or `Buffer` from untrusted sources MUST have a fuzz target.** | This is the operational definition of "what to fuzz." |
| 4 | **Structure-aware beats random bytes 10:1 on structured formats.** | Random mutation on JSON/protobuf/SQL spends 99.9% of time generating syntactically invalid inputs rejected at the first parse step. |
| 5 | **ASan without UBSan is half a tool. Always enable both.** | Integer overflow bugs are the second most common fuzzing finding after memory errors. |
| 6 | **Run separate sanitizer campaigns with shared corpora.** | ASan and MSan are incompatible. TSan needs its own run. Discoveries in one campaign feed others. |
| 7 | **MSan requires ALL dependencies to be compiled with MSan instrumentation.** | Uninstrumented deps produce false positives that waste weeks. Plan for a full rebuild. |
| 8 | **A corpus with 100K entries and the same coverage as 500 entries is 200x slower, not 200x better.** | Corpus minimization is not optional — it is a correctness requirement for efficient fuzzing. |
| 9 | **Minimize BEFORE debugging. Always.** `cargo fuzz tmin` / `afl-tmin` first. | A 4KB crash input is unreadable. A 23-byte input often makes the bug obvious. |
| 10 | **Every crash artifact becomes a regression test or it WILL regress.** | Untested fixes are temporary fixes. |
| 11 | **Deduplicate crashes by stack trace hash (top 5 frames), not by crash file.** | Multiple crash files often share the same root cause. Without dedup, triage is overwhelmed. |
| 12 | **If you can't fuzz a function in isolation, refactor until you can.** | See [Making Code Fuzzable](#making-code-fuzzable). I/O-bound code is unfuzzable by definition. |
| 13 | **Move all one-time initialization out of the fuzz target body.** | Use `LLVMFuzzerInitialize`, `lazy_static`, or `OnceCell`. This is the #1 performance fix. |
| 14 | **Fuzzing ROI follows a power law.** The first hour finds more bugs than the next 100. | Invest in breadth (more targets) before depth (longer runs on existing targets). |
| 15 | **When coverage plateaus for >30 minutes, change strategy — don't wait.** | Add dictionaries, switch to structure-aware, enable CMPLOG, or try hybrid symbolic execution. |

---

## The Loop (Mandatory)

```
1. DISCOVER   → Identify fuzz targets via automated heuristics (see Target Discovery)
2. INSTRUMENT → Make code fuzzable if needed (see Making Code Fuzzable)
3. SEED       → Craft a minimal corpus of valid + boundary inputs
4. STRUCTURE  → Derive Arbitrary/grammar if input has schema (structure-aware > random bytes)
5. HARNESS    → Write fuzz target: guard size, assert invariants, use strongest oracle available
6. SANITIZE   → Enable ASan + UBSan minimum; MSan for unsafe code; TSan for concurrency
7. RUN        → Coverage-guided fuzzing, monitor exec/s (>1000) and edge discovery rate
8. TRIAGE     → Minimize crashes, deduplicate by stack hash, classify root causes
9. REGRESS    → Convert every crash to a permanent regression test
10. ITERATE   → New corpus → deeper coverage → new crashes → repeat
```

---

## Target Discovery Heuristics (Automated)

Before writing a harness, **find** what to fuzz. Don't guess — scan the codebase.

### Per-Language Discovery

**Rust:**
```bash
# Functions accepting untrusted bytes
grep -rn 'pub fn.*\(&\[u8\]\|&str\|impl Read\|impl BufRead\)' src/
# Unsafe code density (prioritize modules with most unsafe)
grep -rcn 'unsafe' src/ --include='*.rs' | sort -t: -k2 -rn | head -20
# Deserialization entry points
grep -rn 'serde.*Deserialize\|from_bytes\|from_str\|decode\|parse' src/ --include='*.rs'
# cargo-geiger for unsafe dependency audit
cargo geiger --output-format=json
```

**Go:**
```bash
# Functions accepting byte slices or readers
grep -rn 'func.*\[\]byte\|io\.Reader\|io\.ReadCloser' --include='*.go'
# Deserialization
grep -rn 'json\.Unmarshal\|xml\.Unmarshal\|proto\.Unmarshal\|gob\.Decode' --include='*.go'
# HTTP handlers (request body parsing)
grep -rn 'func.*http\.ResponseWriter.*\*http\.Request' --include='*.go'
```

**Python:**
```bash
# File/network I/O parsers
grep -rn 'open(\|\.read()\|loads(\|fromstring(\|parse(' --include='*.py'
# Deserialization (security-critical)
grep -rn 'pickle\.load\|yaml\.load\|json\.loads\|xml\.etree' --include='*.py'
```

**TypeScript/JavaScript:**
```bash
# Input processing
grep -rn 'JSON\.parse\|Buffer\.from\|req\.body\|req\.query\|req\.params' --include='*.ts' --include='*.js'
# Deserialization/parsing
grep -rn 'parse(\|decode(\|deserialize(' --include='*.ts' --include='*.js'
```

**C/C++:**
```bash
# Functions accepting raw buffers
grep -rn 'void\s*\*.*size_t\|const\s*uint8_t\s*\*\|const\s*char\s*\*' --include='*.c' --include='*.cpp' --include='*.h'
# Memory operations near input handling
grep -rn 'memcpy\|memmove\|strcpy\|strncpy\|sscanf\|sprintf' --include='*.c' --include='*.cpp'
```

**Java:**
```bash
# Deserialization
grep -rn 'ObjectInputStream\|readObject\|fromJson\|parseFrom\|Unmarshaller' --include='*.java'
# HTTP request processing
grep -rn '@PostMapping\|@RequestBody\|HttpServletRequest' --include='*.java'
```

### Target Selection Matrix

Score each discovered target:

| Target Function | Untrusted Input? | Complexity (1-5) | Unsafe/Native? | Prior CVEs? | Score |
|----------------|----------------:|------------------:|:--------------:|:-----------:|-------|
| *func_name* | Y/N | cyclomatic | Y/N | count | Sum |

**Rule:** Fuzz highest-scoring targets first. Don't fuzz internal helpers
that only receive validated data — fuzz the validation boundary itself.

### Auto-Detection from Dependencies

| Dependency | Suggests | Fuzzing Approach |
|-----------|----------|-----------------|
| `serde`, `nom`, `pest`, `winnow` | Parser/deserializer | Crash detector + round-trip |
| `ring`, `openssl`, `rustls` | Crypto | Specialized (constant-time) + crash detector |
| `tokio`, `async-std`, `rayon` | Concurrency | Stateful + TSan campaign |
| `diesel`, `sqlx`, `sea-orm` | Database | Stateful with shadow model |
| `protobuf`, `prost`, `flatbuffers` | Structured wire format | Structure-aware (Arbitrary derive) |
| `hyper`, `actix`, `axum`, `warp` | HTTP server | Web API fuzzing + crash detector on parsers |
| `image`, `png`, `gif`, `jpeg-decoder` | Image decoder | Crash detector (high priority — many CVEs) |

---

## Decision Tree: Which Fuzzing Approach?

```
What are you fuzzing?
│
├─ Raw bytes → parser/deserializer
│  └─ COVERAGE-GUIDED (cargo-fuzz / libFuzzer / go test -fuzz / Atheris)
│     Best for: binary parsers, image decoders, protocol parsers
│     → See Archetype 1 in HARNESS-CATALOG.md
│
├─ Structured input → has grammar/schema
│  └─ STRUCTURE-AWARE (Arbitrary derive / go-fuzz-headers / fast-check / Hypothesis)
│     Best for: API fuzzing, config validation, SQL, JSON with constraints
│     → See Archetype 5 in HARNESS-CATALOG.md
│
├─ Two implementations of same thing
│  └─ DIFFERENTIAL (both in one harness, compare outputs)
│     Best for: porting across languages, optimized vs reference impl
│     → See Archetype 3 in HARNESS-CATALOG.md
│
├─ Protocol with state machine
│  └─ STATEFUL (sequence of operations with shadow model oracle)
│     Best for: file systems, databases, network protocols
│     → See Archetype 4 in HARNESS-CATALOG.md
│
├─ Serialization code (encode + decode)
│  └─ ROUND-TRIP (encode → decode must reproduce original)
│     Best for: serde, protobuf, custom wire formats, file formats
│     → See Archetype 2 in HARNESS-CATALOG.md
│
├─ Crypto / timing sensitive
│  └─ SPECIALIZED (SideFuzz, ct-fuzz, dudect)
│     Best for: constant-time verification, side-channel detection
│
├─ REST/GraphQL/HTTP API
│  └─ API FUZZING (Schemathesis / RESTler / supertest + fast-check)
│     Best for: web service endpoints, request validation
│     → See NETWORK-PROTOCOL-FUZZING.md
│
├─ Network protocol (TCP/UDP/gRPC/WebSocket)
│  └─ PROTOCOL FUZZING (boofuzz / desocketed harness / gRPC fuzz)
│     Best for: custom protocols, binary wire formats
│     → See NETWORK-PROTOCOL-FUZZING.md
│
├─ CLI tool that reads files
│  └─ BINARY FUZZING (AFL++ with `./binary @@` or extract parser and fuzz directly)
│     Best for: command-line tools, file processors
│     → Extract the parser function and fuzz it directly when possible
│
├─ Smart contract (Solidity/Vyper)
│  └─ CONTRACT FUZZING (Echidna / Foundry forge fuzz / Medusa)
│     Best for: DeFi protocols, token contracts, governance
│     → See Smart Contracts in LANGUAGES.md
│
├─ Coverage plateaued, complex branch conditions
│  └─ HYBRID (SymCC / QSYM + coverage-guided fuzzer)
│     Best for: crypto checksums, deeply nested state machines, magic bytes
│     → Use AFL++ CMPLOG first (simpler), escalate to symbolic if still stuck
│
├─ Already have proptest/Hypothesis/fast-check tests
│  └─ UNIFIED (Bolero for Rust / upgrade existing PBT framework)
│     Best for: upgrading property tests to full fuzzing without rewrite
│
├─ Embedded / no_std target
│  └─ CONSTRAINED (no allocator, cross-compile harness, AFL++ QEMU mode)
│     Best for: firmware, microcontrollers, kernel modules
│
├─ C library via FFI
│  └─ FFI BOUNDARY (fuzz from the host language, propagate sanitizer flags across FFI)
│     Best for: Rust calling C, Python C extensions, JNI native methods
│
├─ Compiler / interpreter / language runtime
│  └─ GRAMMAR-BASED + DIFFERENTIAL (generate valid programs, compare against reference)
│     Best for: parsing stages, type checkers, code generators
│     → Use csmith/yarpgen for C, grammarinator for custom grammars
│
├─ Database engine
│  └─ STATEFUL + GRAMMAR-BASED (random SQL/query sequences against shadow model)
│     Best for: query parsing, execution engine, storage layer, transaction isolation
│     → SQLsmith for SQL grammar generation, Archetype 4 for stateful oracle
│
├─ Game engine / graphics pipeline
│  └─ CRASH DETECTOR + CUSTOM MUTATOR (fuzz asset parsers, shader compilers, scene files)
│     Best for: model loaders, texture decoders, script interpreters
│
├─ Mobile app (Android/iOS)
│  └─ LIBRARY FUZZING (extract native libraries, fuzz with libFuzzer or Jazzer)
│     Best for: NDK/JNI code, data format parsers, crypto implementations
│     → For Android: Jazzer for JVM code, libFuzzer for native. iOS: libFuzzer via Xcode.
│
├─ Kernel / driver
│  └─ KERNEL FUZZING (syzkaller for syscalls, kAFL for kernel modules)
│     Best for: Linux kernel, device drivers, filesystem implementations
│     → Specialized domain. See syzkaller docs. Requires VM-based harness.
│
└─ Not sure whether to self-host or use managed fuzzing
   └─ DECISION: Open-source? → OSS-Fuzz (free, managed). Private? → ClusterFuzzLite (self-hosted).
      Short budget? → CI-only PR fuzzing. Serious security? → Dedicated fuzzing cluster.
      At scale? → See CLOUD-FUZZING.md for cost estimation and multi-machine campaigns.
```

**After choosing your approach:**
1. Copy the template from [HARNESS-CATALOG.md](references/HARNESS-CATALOG.md) for your archetype + language
2. Check [LANGUAGES.md](references/LANGUAGES.md) for language-specific setup and tooling
3. Add CI from [CI-FUZZING.md](references/CI-FUZZING.md)
4. If code is not fuzzable as-is, see [FUZZABILITY.md](references/FUZZABILITY.md) for refactoring patterns
5. For a quick command reference, see [QUICK-REF.md](references/QUICK-REF.md)

---

## Making Code Fuzzable

Most real-world code is NOT fuzzable as-is. Making it fuzzable is the hardest and most valuable step.

### The Fuzzability Test

> Can you call this function with `&[u8]` (or equivalent) and get a deterministic result with no side effects?

- **YES** → It is fuzzable. Write a harness.
- **NO** → Refactor until the answer is YES for the computation core, then fuzz that core.

**I/O-bound code is unfuzzable. Computation-bound code is fuzzable. The job of making code fuzzable is the job of separating I/O from computation.**

### Pattern: Extract-Parse-Process

**Before** (unfuzzable — I/O entangled with parsing):
```rust
fn handle_request(socket: &TcpStream) -> Result<()> {
    let mut buf = Vec::new();
    socket.read_to_end(&mut buf)?;
    let header = parse_header(&buf[..16])?;
    let body = decompress(&buf[16..], header.compression)?;
    let msg = deserialize(body, header.format)?;
    process_message(msg)?;
    Ok(())
}
```

**After** (4 fuzzable functions extracted):
```rust
// Each of these is independently fuzzable
pub fn parse_header(data: &[u8]) -> Result<Header> { ... }
pub fn decompress(data: &[u8], compression: Compression) -> Result<Vec<u8>> { ... }
pub fn deserialize(data: &[u8], format: Format) -> Result<Message> { ... }
pub fn process_message(msg: &Message) -> Result<Response> { ... }

// Thin orchestrator — does I/O, calls fuzzable functions
fn handle_request(socket: &TcpStream) -> Result<()> {
    let mut buf = Vec::new();
    socket.read_to_end(&mut buf)?;
    let header = parse_header(&buf[..16])?;
    let body = decompress(&buf[16..], header.compression)?;
    let msg = deserialize(&body, header.format)?;
    process_message(&msg)?;
    Ok(())
}
```

### Fuzz-Friendly API Checklist

For every function that processes external data:

- [ ] Accepts a file path? → Add a variant that accepts `&[u8]`
- [ ] Accepts a network socket? → Add a variant that accepts `impl Read`
- [ ] Reads from stdin? → Add a variant that accepts `&[u8]`
- [ ] Accepts a URL? → Separate fetching from parsing
- [ ] Accepts a database connection? → Separate query building from execution
- [ ] Has global mutable state? → Make state injectable or per-invocation
- [ ] Uses randomness or time? → Accept seed/timestamp as parameter

See [FUZZABILITY.md](references/FUZZABILITY.md) for complete patterns per language.

### Oracle Hierarchy

Use the **strongest** oracle available. A crash-only harness is acceptable only when no stronger oracle exists.

| Strength | Oracle Type | Example |
|:--------:|------------|---------|
| 1 (best) | **Reference implementation** | Compare two parsers on same input (differential) |
| 2 | **Simplified shadow model** | BTreeMap mimicking a database's contract |
| 3 | **Inverse operation** | `decode(encode(x)) == x` (round-trip) |
| 4 | **Metamorphic relation** | `f(sort(x)) == sort(f(x))` (combine with /testing-metamorphic) |
| 5 (worst) | **Crash oracle** | No panic, no sanitizer violation |

---

## Harness Patterns (The Seven Archetypes)

Each archetype has complete, copy-paste-ready templates for **Rust, Go, Python, TypeScript, C/C++, and Java** in [HARNESS-CATALOG.md](references/HARNESS-CATALOG.md).

| # | Archetype | When to Use | Oracle |
|---|-----------|------------|--------|
| 1 | **Crash Detector** | Raw bytes → parser. Simplest pattern. | Crash |
| 2 | **Round-Trip** | Serialization code. Gold standard for serde/protobuf. | Inverse |
| 3 | **Differential** | Two impls of same spec. Every divergence = bug. | Reference |
| 4 | **Stateful** | Databases, file systems, protocol stacks. Shadow model. | Model |
| 5 | **Grammar-Based** | Language/protocol parsers. Syntactically valid-ish inputs. | Crash + invariant |
| 6 | **Custom Mutator** | Compressed/encrypted formats where byte mutation is useless. | Varies |
| 7 | **Concurrency** | Thread-safe data structures. Run with TSan. | Invariant |

**Quick Rust example** (Crash Detector — see HARNESS-CATALOG.md for all languages):
```rust
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    if data.len() > 1_000_000 { return; }
    let _ = my_crate::parse_message(data);
});
```

**Invariant convention:** `let _ =` for expected failures. `assert!` for properties that
must hold even on garbage input.

---

## Sanitizer Discipline (Non-Negotiable)

```bash
# Campaign 1: ASan + UBSan (ALWAYS run first — finds 80% of bugs)
cargo fuzz run my_target
# or: RUSTFLAGS="-Zsanitizer=address,undefined" cargo +nightly fuzz run my_target

# Campaign 2: MSan (if target has unsafe code — requires separate build)
RUSTFLAGS="-Zsanitizer=memory" cargo +nightly fuzz run my_target

# Campaign 3: TSan (if target has concurrency)
RUSTFLAGS="-Zsanitizer=thread" cargo +nightly fuzz run my_target
```

| Sanitizer | Catches | Overhead | When |
|-----------|---------|----------|------|
| ASan | Buffer overflow, UAF, double-free | 2-4x | **Always** |
| UBSan | Integer overflow, alignment, null deref | 1.2x | **Always** (combine with ASan) |
| MSan | Uninitialized reads | 3x | Unsafe/native code |
| TSan | Data races, deadlocks | 5-15x | Concurrent code |
| LSan | Memory leaks | 1.2x | Long-running targets |

**Incompatibility:** ASan+MSan cannot coexist. ASan+TSan cannot coexist. Run separate campaigns. **Share corpus across all campaigns.**

See [SANITIZERS.md](references/SANITIZERS.md) for per-language configuration and advanced options.

---

## Corpus Engineering (Summary)

```bash
# Minimum seed corpus: empty + minimal valid + typical + boundary + large
mkdir -p fuzz/corpus/my_target
printf '' > fuzz/corpus/my_target/empty
echo '{}' > fuzz/corpus/my_target/minimal_valid
echo '{"name":"test","value":42}' > fuzz/corpus/my_target/typical
printf '\x00\xff' > fuzz/corpus/my_target/boundary

# Minimize weekly (CRITICAL — bloated corpus wastes cycles)
cargo fuzz cmin my_target

# Minimize crash inputs BEFORE debugging
cargo fuzz tmin my_target artifacts/my_target/crash-xxx
```

**Dictionaries** accelerate fuzzing of structured formats by 5-50x. See [DICTIONARIES.md](references/DICTIONARIES.md) for ready-to-use dictionaries for JSON, XML, SQL, HTTP, protobuf, and 10+ more formats.

See [CORPUS.md](references/CORPUS.md) for complete corpus engineering guide including production data distillation, coverage tracking, and plateau detection.

---

## Triage Pipeline

```
1. MINIMIZE     → cargo fuzz tmin / afl-tmin (ALWAYS first)
2. REPRODUCE    → Run minimized input 10x — must crash every time (deterministic?)
3. DEDUPLICATE  → Hash top-5 stack frames. Same hash = same bug, discard duplicates.
4. CLASSIFY     → Memory corruption? Logic bug? Panic? OOM? Timeout?
5. SEVERITY     → Exploitable memory write > DoS/crash > Logic bug > Timeout
6. ROOT-CAUSE   → Read the sanitizer stack trace, identify the vulnerable code
7. FIX          → Write the fix
8. REGRESSION   → Convert to permanent unit test:
     #[test]
     fn regression_crash_abc123() {
         let input = include_bytes!("../fuzz/artifacts/my_target/crash-abc123");
         let _ = my_crate::parse(input);  // Must not panic after fix
     }
9. RE-FUZZ      → Run again to find deeper bugs now that shallow ones are fixed
```

See [TRIAGE.md](references/TRIAGE.md) for reading sanitizer stack traces, severity classification, and auto-filing to issue trackers.

---

## Performance-Aware Fuzzing

Fuzzing infrastructure must NEVER affect production performance.

### Compile-Time Feature Flags (Rust)
```toml
# Cargo.toml — fuzz deps behind feature flag
[features]
fuzz = ["arbitrary"]

[dependencies]
arbitrary = { version = "1", optional = true, features = ["derive"] }
```

```rust
// Only derive Arbitrary when fuzzing
#[cfg_attr(feature = "fuzz", derive(arbitrary::Arbitrary))]
pub struct Message { ... }

// Zero-cost invariant hooks
#[cfg(fuzzing)]  // Set automatically by cargo-fuzz
pub fn check_invariants(state: &State) { state.assert_balanced(); }
#[cfg(not(fuzzing))]
#[inline(always)]
pub fn check_invariants(_state: &State) {}
```

### Verification Protocol
```bash
# Before adding fuzz infrastructure:
cargo bench --bench my_benchmark > before.txt
# After:
cargo bench --bench my_benchmark > after.txt
# Verify zero regression:
# If any production benchmark regresses >1%, fuzz infra leaked into prod. Fix.

# Verify zero fuzz deps in release:
cargo tree --no-dev | grep -E 'arbitrary|libfuzzer|bolero'
# Must return nothing. If it does, feature flags are wrong.
```

See [PERFORMANCE-TUNING.md](references/PERFORMANCE-TUNING.md) for exec/s optimization, persistent mode, parallel fuzzing, and memory budgets.

---

## Bolero: Write Once, Fuzz Everywhere (Rust)

**When to use Bolero:** Use Bolero when you want to run the same harness under libFuzzer, AFL++, and honggfuzz with zero code changes. Use `cargo-fuzz` directly when you only need libFuzzer (the common case for most projects).

```rust
use bolero::check;

#[test]
fn fuzz_parser_bolero() {
    check!()
        .with_type::<Vec<u8>>()
        .cloned()
        .for_each(|data| {
            let _ = my_crate::parse(&data);
        });
}
```

```bash
cargo bolero test fuzz_parser_bolero --engine libfuzzer  # Deep coverage
cargo bolero test fuzz_parser_bolero --engine afl         # Deterministic mutation
cargo bolero test fuzz_parser_bolero --engine honggfuzz    # Hardware-assisted feedback
cargo test fuzz_parser_bolero                              # Property-based mode in CI
```

---

## Anti-Patterns (Hard Constraints)

| Never | Why | Fix |
|-------|-----|-----|
| Fuzz target is the entire program | Coverage too thin | Narrow to one parser/function |
| No input size guards | OOM kills mask real bugs | `if data.len() > MAX { return; }` |
| `unwrap()` in the harness itself | Harness crash != code bug | `let _ =` for expected failures |
| No seed corpus | Wastes hours on trivially invalid inputs | Seed with valid + boundary examples |
| Never minimize crashes | Undebuggable inputs | Always `tmin` before debugging |
| Run without sanitizers | Miss memory bugs | ASan + UBSan minimum |
| Fuzz forever, never triage | Crashes pile up | Triage daily, fix weekly |
| Check error message strings | Brittle, breaks on rewording | Check error *types/categories* |
| Same sanitizer for all campaigns | Miss bug classes | Separate ASan, MSan, TSan campaigns |
| Initialization in fuzz target body | Kills exec/s | Move to `LLVMFuzzerInitialize` / `OnceCell` |
| Fuzz deps in production build | Perf regression | Feature flags + `cargo tree` verification |
| Non-deterministic harness | Can't reproduce crashes | Remove rand, time, HashMap iteration |
| Crash-only oracle when stronger exists | Miss logic bugs | Use strongest oracle (see hierarchy) |

---

## Checklist (Before Shipping Fuzz Harness)

- [ ] Target function identified (narrowest input boundary)
- [ ] Code is fuzzable (accepts bytes/reader, no I/O, deterministic)
- [ ] Seed corpus created (empty + valid + boundary + adversarial, min 5 entries)
- [ ] Dictionary provided for structured formats
- [ ] Input size bounded (`if len > MAX { return; }`)
- [ ] Value sizes bounded (no unbounded `Vec<u8>` in Arbitrary)
- [ ] Strongest available oracle used (not just crash-only)
- [ ] ASan + UBSan enabled (default for cargo-fuzz)
- [ ] MSan campaign planned if target has unsafe/native code
- [ ] TSan campaign planned if target has concurrency
- [ ] `let _ =` for expected failures, `assert!` for invariant violations
- [ ] Invariant checks at end of harness (state consistency)
- [ ] Initialization outside fuzz target body (exec/s > 1000)
- [ ] Crash artifacts convert to regression tests
- [ ] CI runs regression corpus on every PR
- [ ] Nightly continuous fuzzing scheduled
- [ ] No fuzz dependencies in production build (verified with `cargo tree` or equivalent)
- [ ] Coverage report reviewed — harness actually reaches target code

---

## Cross-Skill Integration

### Fuzzing + Metamorphic Relations (/testing-metamorphic)

Fuzzing generates diverse inputs. Metamorphic relations check properties across those inputs.

```rust
// Fuzz a JSON parser: for every input the parser accepts, verify MR
fuzz_target!(|data: &[u8]| {
    if let Ok(parsed) = serde_json::from_slice::<Value>(data) {
        // MR: parse(pretty_print(parse(x))) == parse(x)
        let pretty = serde_json::to_string_pretty(&parsed).unwrap();
        let reparsed: Value = serde_json::from_str(&pretty).unwrap();
        assert_eq!(parsed, reparsed, "Pretty-print MR violated");
    }
});
```

### Fuzzing + Conformance (/testing-conformance-harnesses)

Use fuzz-generated inputs as test vectors for conformance suites:
```rust
// Fuzz generates random but accepted inputs → feed to conformance checker
fuzz_target!(|data: &[u8]| {
    if let Ok(msg) = our_parser::parse(data) {
        // Every message we accept must also be accepted by the reference
        reference_parser::parse(data)
            .expect("CONFORMANCE: we accept input that reference rejects");
    }
});
```

### Fuzzing + Optimization Validation (/extreme-software-optimization)

After optimizing code, fuzz to verify no correctness regressions:
```rust
// Differential fuzz: original vs optimized implementation
fuzz_target!(|data: &[u8]| {
    let original = original_impl::process(data);
    let optimized = optimized_impl::process(data);
    assert_eq!(original, optimized, "Optimization introduced divergence");
});
```

### Fuzzing + Formal Verification (/lean-formal-feedback-loop)

Fuzzing finds counterexamples. Proofs close the gap:
```rust
// Step 1: Fuzz discovers that insert_sorted() fails for input [3, 1, 4, 1, 5]
// Step 2: Fix the off-by-one in the insertion logic
// Step 3: Prove in Lean/Kani that the fix makes the invariant hold universally:
//   ∀ xs : Vec<i32>, is_sorted(insert_sorted(xs))
// Step 4: Re-fuzz to verify no other counterexamples exist
```
The workflow: fuzzing rapidly explores → finds counterexample → you fix → formal proof guarantees completeness → re-fuzz to confirm.

---

## References

| Need | Reference |
|------|-----------|
| Complete harness templates (all languages, all archetypes) | [HARNESS-CATALOG.md](references/HARNESS-CATALOG.md) |
| Making code fuzzable (refactoring, DI, I/O separation) | [FUZZABILITY.md](references/FUZZABILITY.md) |
| AFL++ deep guide (CMPLOG, persistent mode, power schedules) | [AFLPP.md](references/AFLPP.md) |
| Crash triage (stack traces, dedup, severity, auto-filing) | [TRIAGE.md](references/TRIAGE.md) |
| Custom mutators per format (protobuf, compressed, encrypted) | [CUSTOM-MUTATORS.md](references/CUSTOM-MUTATORS.md) |
| Ready-to-use dictionaries (JSON, XML, SQL, HTTP, 10+ more) | [DICTIONARIES.md](references/DICTIONARIES.md) |
| Performance tuning (persistent mode, parallel, memory budgets) | [PERFORMANCE-TUNING.md](references/PERFORMANCE-TUNING.md) |
| Network protocol & web API fuzzing | [NETWORK-PROTOCOL-FUZZING.md](references/NETWORK-PROTOCOL-FUZZING.md) |
| Sanitizer deep-dive | [SANITIZERS.md](references/SANITIZERS.md) |
| Corpus engineering guide | [CORPUS.md](references/CORPUS.md) |
| Real-world CVEs found by fuzzing | [CVE-TABLE.md](references/CVE-TABLE.md) |
| CI/CD fuzzing integration | [CI-FUZZING.md](references/CI-FUZZING.md) |
| Language-specific guides (Rust, Go, Python, TS, C/C++, Java) | [LANGUAGES.md](references/LANGUAGES.md) |
| End-to-end walkthrough (clone → CI fuzzing) | [WALKTHROUGH.md](references/WALKTHROUGH.md) |
| Quality validators (is your fuzzing infrastructure good?) | [VALIDATORS.md](references/VALIDATORS.md) |
| Troubleshooting common issues | [TROUBLESHOOTING.md](references/TROUBLESHOOTING.md) |
| Fuzzer internals (coverage feedback, bitmaps, mutation pipeline) | [FUZZER-INTERNALS.md](references/FUZZER-INTERNALS.md) |
| Ensemble fuzzing (multi-engine campaigns, corpus sharing) | [ENSEMBLE-FUZZING.md](references/ENSEMBLE-FUZZING.md) |
| Cloud fuzzing at scale (cost estimation, spot instances, clusters) | [CLOUD-FUZZING.md](references/CLOUD-FUZZING.md) |
| Quick command reference (cheat sheet, no explanations) | [QUICK-REF.md](references/QUICK-REF.md) |

## Relationship to Other Testing Skills

| Technique | Use INSTEAD when | Use TOGETHER when |
|-----------|-----------------|-------------------|
| /testing-metamorphic | Logic bugs, not crashes | Fuzzing generates inputs, MRs check relations |
| /testing-conformance-harnesses | Spec compliance, not crashes | Fuzz-generated inputs feed conformance checks |
| /testing-golden-artifacts | Snapshot testing, not crash discovery | Fuzz-discovered interesting inputs become golden files |
| /extreme-software-optimization | Perf, not correctness | Fuzz after optimization to verify no regressions |
| /lean-formal-feedback-loop | Need mathematical proof | Fuzzing finds counterexamples, proofs close the gap |
| /multi-pass-bug-hunting | Broad code review, not input testing | Include fuzzing as a dedicated pass in multi-pass audit |
| /codebase-audit | Security audit scope | Fuzzing recommendations feed into audit follow-through |
