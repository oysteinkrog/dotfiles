# Language-Specific Fuzzing Guide

> Complete setup, harness patterns, and CI integration for every supported language.

> **For complete copy-paste templates of all 7 fuzzing archetypes, see [HARNESS-CATALOG.md](HARNESS-CATALOG.md).** This file covers language-specific setup, tooling, CI, and condensed examples.

## Contents

1. [Rust](#rust)
2. [Go](#go)
3. [Python](#python)
4. [TypeScript / JavaScript](#typescript--javascript)
5. [C / C++](#c--c)
6. [Java / JVM](#java--jvm)
7. [Smart Contracts (Solidity)](#smart-contracts-solidity)

---

## Rust

### Setup

```bash
rustup default nightly  # Required for sanitizers
cargo install cargo-fuzz
cargo fuzz init          # Creates fuzz/ directory
cargo fuzz add my_target # Creates fuzz/fuzz_targets/my_target.rs
```

### Tooling Matrix

| Tool | Purpose | Install |
|------|---------|---------|
| cargo-fuzz | libFuzzer wrapper (default, recommended) | `cargo install cargo-fuzz` |
| afl.rs | AFL++ wrapper | `cargo install afl` |
| honggfuzz-rs | honggfuzz wrapper | `cargo install honggfuzz` |
| bolero | Unified interface (any engine) | `bolero = "0.10"` in dev-deps |
| cargo-careful | Extra runtime checks (lighter than sanitizers) | `cargo install cargo-careful` |
| miri | UB detector (complementary to fuzzing) | `rustup +nightly component add miri` |

### Run Commands

```bash
cargo fuzz run my_target                           # Basic (ASan default)
cargo fuzz run my_target -- -max_len=65536         # Bound input size
cargo fuzz run my_target -- -timeout=10            # 10s timeout per input
cargo fuzz run my_target -- -dict=fuzz/dicts/json.dict  # With dictionary
cargo fuzz run my_target -- -jobs=4 -workers=4     # Parallel (4 cores)
cargo fuzz run my_target -- -use_value_profile=1   # Helps bypass comparisons
cargo fuzz cmin my_target                          # Minimize corpus
cargo fuzz tmin my_target artifacts/crash-xxx      # Minimize crash input
cargo fuzz coverage my_target                      # Coverage report
```

### Advanced Patterns

**`#[cfg(fuzzing)]` conditional compilation:**
```rust
// Set automatically by cargo-fuzz. Use to disable expensive checks during fuzzing.
#[cfg(fuzzing)]
fn verify_signature(_data: &[u8]) -> bool { true }  // Skip sig check to fuzz parser underneath

#[cfg(not(fuzzing))]
fn verify_signature(data: &[u8]) -> bool { real_verify(data) }
```

**Feature-gated fuzz dependencies:**
```toml
[features]
fuzz = ["arbitrary"]

[dependencies]
arbitrary = { version = "1", optional = true, features = ["derive"] }

[dev-dependencies]
libfuzzer-sys = "0.4"
bolero = "0.10"
```

```rust
#[cfg_attr(feature = "fuzz", derive(arbitrary::Arbitrary))]
#[derive(Debug, Clone)]
pub struct Config { /* ... */ }
```

**`Arbitrary::arbitrary` with `Unstructured` (lifetime management):**
```rust
use arbitrary::{Arbitrary, Unstructured};

impl<'a> Arbitrary<'a> for MyStruct {
    fn arbitrary(u: &mut Unstructured<'a>) -> arbitrary::Result<Self> {
        // u.int_in_range(), u.bytes(), etc. may return Err when data exhausted
        // Always use ? operator — never unwrap
        let count = u.int_in_range(0..=100)?;
        let items: Vec<Item> = (0..count)
            .map(|_| Item::arbitrary(u))
            .collect::<Result<_, _>>()?;
        Ok(MyStruct { items })
    }
}
```

**proptest deep patterns:**
```rust
use proptest::prelude::*;

proptest! {
    #![proptest_config(ProptestConfig::with_cases(100_000))]

    #[test]
    fn roundtrip(data in prop::collection::vec(any::<u8>(), 0..10000)) {
        if let Ok(parsed) = parse(&data) {
            let reencoded = encode(&parsed);
            let reparsed = parse(&reencoded).unwrap();
            prop_assert_eq!(parsed, reparsed);
        }
    }
}
```

**Workspace crate fuzzing gotcha:**
```toml
# Root Cargo.toml — fuzz/ must be a workspace member
[workspace]
members = ["crate-a", "crate-b", "fuzz"]

# fuzz/Cargo.toml
[package]
name = "my-fuzz"
[dependencies]
libfuzzer-sys = "0.4"
crate-a = { path = "../crate-a" }
```

**Miri for UB verification on crash reproducers:**
```bash
# After fixing a crash, verify with Miri for precise UB detection
cargo +nightly miri test regression_crash_abc123
```

**Bolero (write once, fuzz everywhere):**
```rust
use bolero::check;

#[test]
fn fuzz_with_bolero() {
    check!()
        .with_type::<Vec<u8>>()
        .cloned()
        .for_each(|data| {
            let _ = parse(&data);
        });
}
```

```bash
cargo bolero test fuzz_with_bolero --engine libfuzzer
cargo bolero test fuzz_with_bolero --engine afl
cargo bolero test fuzz_with_bolero --engine honggfuzz
cargo test fuzz_with_bolero  # Property-based mode in CI
```

### CI Integration (Rust)

```yaml
name: Fuzz Regression
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@nightly
      - run: cargo install cargo-fuzz
      - name: Run fuzz regression
        run: |
          for target in $(cargo fuzz list); do
            cargo fuzz run "$target" -- -max_total_time=60 -runs=10000 2>&1 || exit 1
          done
        timeout-minutes: 10
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: fuzz-crashes
          path: fuzz/artifacts/
```

---

## Go

### Setup (Go 1.18+)

Go has **native fuzzing** built into `go test`. No additional tools needed.

```bash
# Verify Go version >= 1.18
go version

# Fuzz tests are regular _test.go files with func Fuzz* signatures
# Corpus lives in testdata/fuzz/FuzzTargetName/
```

### Target Identification

```bash
# Functions accepting byte slices or readers
grep -rn 'func.*\[\]byte\|io\.Reader' --include='*.go'
# Deserialization entry points
grep -rn 'json\.Unmarshal\|xml\.Unmarshal\|proto\.Unmarshal' --include='*.go'
# HTTP handlers
grep -rn 'func.*http\.ResponseWriter.*\*http\.Request' --include='*.go'
```

### Harness Patterns

**Crash Detector (raw bytes):**
```go
func FuzzParse(f *testing.F) {
    // Seed corpus
    f.Add([]byte("valid input"))
    f.Add([]byte{})
    f.Add([]byte{0xFF, 0xFE})

    f.Fuzz(func(t *testing.T, data []byte) {
        if len(data) > 1_000_000 { return }
        _ = Parse(data)
    })
}
```

**Round-Trip (serialize/deserialize):**
```go
func FuzzRoundTrip(f *testing.F) {
    f.Add([]byte(`{"key":"value"}`))

    f.Fuzz(func(t *testing.T, data []byte) {
        var parsed interface{}
        if err := json.Unmarshal(data, &parsed); err != nil {
            return // Graceful rejection
        }
        reencoded, err := json.Marshal(parsed)
        if err != nil {
            t.Fatalf("Marshal failed: %v", err)
        }
        var reparsed interface{}
        if err := json.Unmarshal(reencoded, &reparsed); err != nil {
            t.Fatalf("Round-trip parse failed: %v", err)
        }
        if !reflect.DeepEqual(parsed, reparsed) {
            t.Fatal("Round-trip changed value")
        }
    })
}
```

**Differential (two implementations):**
```go
func FuzzDifferential(f *testing.F) {
    f.Add([]byte(`test input`))

    f.Fuzz(func(t *testing.T, data []byte) {
        ours, ourErr := OurParse(data)
        ref, refErr := ReferenceParse(data)

        if ourErr != nil && refErr != nil { return } // Both reject
        if ourErr == nil && refErr == nil {
            if !reflect.DeepEqual(ours, ref) {
                t.Fatalf("Divergence: ours=%v ref=%v", ours, ref)
            }
            return
        }
        if ourErr != nil && refErr == nil {
            t.Fatalf("Reference accepts input we reject: %v", ourErr)
        }
        // We accept, reference rejects — may be intentional
    })
}
```

**Stateful (operation sequences):**
```go
func FuzzStateful(f *testing.F) {
    f.Add([]byte{0x01, 0x02, 0x03})

    f.Fuzz(func(t *testing.T, data []byte) {
        if len(data) > 500 { return }
        db := NewInMemoryDB()
        model := make(map[byte][]byte)

        for i := 0; i < len(data)-1; i += 2 {
            op, key := data[i]%4, data[i+1]
            switch op {
            case 0: // Insert
                val := []byte{key}
                db.Set(key, val)
                model[key] = val
            case 1: // Get
                got, _ := db.Get(key)
                want := model[key]
                if !bytes.Equal(got, want) {
                    t.Fatalf("key %d: got %v, want %v", key, got, want)
                }
            case 2: // Delete
                db.Delete(key)
                delete(model, key)
            case 3: // Verify
                if db.Len() != len(model) {
                    t.Fatalf("size mismatch: db=%d model=%d", db.Len(), len(model))
                }
            }
        }
    })
}
```

**Structured input with go-fuzz-headers:**
```go
import fuzz "github.com/AdamKorcz/go-fuzz-headers"

func FuzzStructured(f *testing.F) {
    f.Add([]byte{})

    f.Fuzz(func(t *testing.T, data []byte) {
        consumer := fuzz.NewConsumer(data)
        var config Config
        if err := consumer.GenerateStruct(&config); err != nil {
            return
        }
        result := ProcessConfig(config)
        if result.IsValid() {
            // Invariant: valid configs produce valid results
            encoded := result.Encode()
            decoded, err := Decode(encoded)
            if err != nil {
                t.Fatalf("Round-trip failed: %v", err)
            }
            if !reflect.DeepEqual(result, decoded) {
                t.Fatal("Round-trip changed value")
            }
        }
    })
}
```

### Run Commands

```bash
go test -fuzz=FuzzParse -fuzztime=300s          # Run for 5 minutes
go test -fuzz=FuzzParse -fuzztime=10000x         # Run 10K iterations
go test -fuzz=FuzzParse -race                     # Enable race detector
go test -fuzz=FuzzParse -parallel=4               # 4 parallel workers
go test -run=FuzzParse/testdata/fuzz/FuzzParse/   # Replay corpus (regression)
```

**Corpus location:** `testdata/fuzz/FuzzTargetName/`

### CI Integration (Go)

```yaml
name: Fuzz
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - name: Fuzz regression
        run: |
          for pkg in $(go list ./...); do
            funcs=$(go test -list 'Fuzz.*' "$pkg" 2>/dev/null | grep '^Fuzz')
            for fn in $funcs; do
              echo "=== $pkg $fn ==="
              go test "$pkg" -fuzz="$fn" -fuzztime=30s -race || exit 1
            done
          done
        timeout-minutes: 10
```

---

## Python

### Setup

```bash
pip install atheris    # Coverage-guided fuzzer (Google)
pip install hypothesis # Property-based testing (most popular Python PBT)
```

### Atheris (Coverage-Guided)

**Crash Detector:**
```python
import atheris
import sys

with atheris.instrument_imports():
    import my_library

def TestOneInput(data):
    if len(data) > 1_000_000:
        return
    try:
        my_library.parse(data)
    except (ValueError, TypeError, KeyError):
        pass  # Expected error types — not bugs

atheris.Setup(sys.argv, TestOneInput)
atheris.Fuzz()
```

**FuzzedDataProvider (structured input):**
```python
import atheris
import sys

with atheris.instrument_imports():
    import my_library

def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    s = fdp.ConsumeUnicode(fdp.ConsumeIntInRange(0, 1024))
    i = fdp.ConsumeInt(4)
    f = fdp.ConsumeFloat()
    b = fdp.ConsumeBool()
    choice = fdp.PickValueInList(["json", "xml", "csv"])

    try:
        my_library.process(s, i, f, b, format=choice)
    except my_library.ValidationError:
        pass  # Expected

atheris.Setup(sys.argv, TestOneInput)
atheris.Fuzz()
```

**FuzzedDataProvider API Reference:**

| Method | Returns | Use For |
|--------|---------|---------|
| `ConsumeBytes(n)` | bytes | Raw byte buffers |
| `ConsumeUnicode(n)` | str | Text input |
| `ConsumeInt(n)` | int | n-byte integer |
| `ConsumeIntInRange(min, max)` | int | Bounded integer |
| `ConsumeFloat()` | float | IEEE 754 float |
| `ConsumeFloatInRange(min, max)` | float | Bounded float |
| `ConsumeBool()` | bool | Boolean flags |
| `ConsumeString(n)` | str | ASCII string |
| `PickValueInList(lst)` | any | Choose from options |
| `ConsumeIntList(count, n)` | list[int] | List of n-byte ints |
| `remaining_bytes()` | int | Bytes left to consume |

**Round-Trip:**
```python
def TestOneInput(data):
    try:
        parsed = my_lib.deserialize(data)
    except Exception:
        return
    reserialized = my_lib.serialize(parsed)
    reparsed = my_lib.deserialize(reserialized)
    assert parsed == reparsed, f"Round-trip failure: {parsed} != {reparsed}"
```

**Differential:**
```python
import json
import ujson

def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    json_str = fdp.ConsumeUnicode(10000)
    try:
        ref = json.loads(json_str)
    except Exception:
        return
    try:
        ours = ujson.loads(json_str)
    except Exception as e:
        raise RuntimeError(f"Reference accepts but we reject: {json_str!r}") from e
    # Compare outputs
    if json.dumps(ref, sort_keys=True) != json.dumps(ours, sort_keys=True):
        raise RuntimeError(f"Output divergence on: {json_str!r}")
```

### Hypothesis (Property-Based Testing)

**Basic property:**
```python
from hypothesis import given, strategies as st, settings

@given(st.binary(max_size=100_000))
@settings(max_examples=100_000)
def test_parser_handles_arbitrary_input(data):
    try:
        parse(data)
    except ValidationError:
        pass  # Expected

@given(st.from_type(MyDataclass))
def test_structured_input(config):
    result = process(config)
    assert result.is_valid(), f"Invalid result for {config}"
```

**Round-trip with Hypothesis:**
```python
from hypothesis import given, strategies as st

@given(st.dictionaries(st.text(), st.integers() | st.text() | st.booleans()))
def test_json_roundtrip(obj):
    encoded = json.dumps(obj)
    decoded = json.loads(encoded)
    assert obj == decoded
```

**Stateful testing with Hypothesis:**
```python
from hypothesis.stateful import RuleBasedStateMachine, rule, initialize

class DBStateMachine(RuleBasedStateMachine):
    @initialize()
    def init(self):
        self.db = InMemoryDB()
        self.model = {}

    @rule(key=st.binary(max_size=10), value=st.binary(max_size=100))
    def insert(self, key, value):
        self.db.set(key, value)
        self.model[key] = value

    @rule(key=st.binary(max_size=10))
    def get(self, key):
        assert self.db.get(key) == self.model.get(key)

    @rule(key=st.binary(max_size=10))
    def delete(self, key):
        self.db.delete(key)
        self.model.pop(key, None)

TestDB = DBStateMachine.TestCase
```

### Fuzzing Python C Extensions

```bash
# Build the C extension with ASan
CC="clang" CFLAGS="-fsanitize=address,fuzzer-no-link -g" pip install -e .

# Run Atheris with ASan preloaded
LD_PRELOAD=$(clang -print-file-name=libclang_rt.asan-x86_64.so) \
    python fuzz_target.py
```

### CI Integration (Python)

```yaml
name: Fuzz
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.12' }
      - run: pip install atheris hypothesis
      - name: Hypothesis tests
        run: pytest tests/ -k "fuzz or hypothesis" --hypothesis-seed=0
      - name: Atheris regression
        run: |
          for target in fuzz_targets/*.py; do
            timeout 60 python "$target" corpus/ || exit 1
          done
```

---

## TypeScript / JavaScript

### Setup

```bash
npm install --save-dev fast-check    # Property-based testing (recommended)
npm install --save-dev @jazzer.js/core  # Coverage-guided fuzzing
```

### fast-check (Property-Based Testing)

**Crash Detector:**
```typescript
import * as fc from "fast-check";

test("parser handles arbitrary input", () => {
  fc.assert(
    fc.property(fc.string(), (input) => {
      try { parse(input); } catch (e) {
        if (e instanceof SyntaxError) return; // Expected
        throw e; // Unexpected = bug
      }
    }),
    { numRuns: 100_000 }
  );
});
```

**Round-Trip:**
```typescript
test("serialize/deserialize round-trip", () => {
  fc.assert(
    fc.property(
      fc.record({
        name: fc.string(),
        age: fc.integer({ min: 0, max: 150 }),
        tags: fc.array(fc.string()),
      }),
      (input) => {
        const encoded = serialize(input);
        const decoded = deserialize(encoded);
        expect(decoded).toEqual(input);
      }
    ),
    { numRuns: 50_000 }
  );
});
```

**Differential:**
```typescript
test("our JSON parser matches native", () => {
  fc.assert(
    fc.property(fc.json(), (jsonStr) => {
      const native = JSON.parse(jsonStr);
      const ours = ourParser.parse(jsonStr);
      expect(ours).toEqual(native);
    }),
    { numRuns: 100_000 }
  );
});
```

**Stateful (model-based testing — fast-check's killer feature):**
```typescript
import * as fc from "fast-check";

// Define commands that operate on your system
class InsertCommand implements fc.Command<Model, Real> {
  constructor(readonly key: string, readonly value: string) {}
  check = () => true;
  run(model: Model, real: Real) {
    real.set(this.key, this.value);
    model.data.set(this.key, this.value);
    expect(real.get(this.key)).toBe(this.value);
  }
  toString = () => `Insert(${this.key}, ${this.value})`;
}

class GetCommand implements fc.Command<Model, Real> {
  constructor(readonly key: string) {}
  check = () => true;
  run(model: Model, real: Real) {
    expect(real.get(this.key)).toBe(model.data.get(this.key) ?? null);
  }
  toString = () => `Get(${this.key})`;
}

test("stateful store", () => {
  fc.assert(
    fc.property(
      fc.commands([
        fc.tuple(fc.string(), fc.string()).map(([k, v]) => new InsertCommand(k, v)),
        fc.string().map((k) => new GetCommand(k)),
      ]),
      (cmds) => {
        const model = { data: new Map() };
        const real = new MyStore();
        fc.modelRun(() => ({ model, real }), cmds);
      }
    ),
    { numRuns: 10_000 }
  );
});
```

**Zod schema → fast-check arbitrary:**
```typescript
import { ZodFastCheck } from "zod-fast-check";
import { z } from "zod";

const UserSchema = z.object({
  name: z.string().min(1),
  email: z.string().email(),
  age: z.number().int().min(0).max(150),
});

test("handler accepts all valid inputs", () => {
  const arb = ZodFastCheck().inputOf(UserSchema);
  fc.assert(
    fc.property(arb, (user) => {
      const response = handler(user);
      expect(response.status).not.toBe(500);
    }),
    { numRuns: 10_000 }
  );
});
```

**API endpoint fuzzing with supertest:**
```typescript
import request from "supertest";
import * as fc from "fast-check";
import app from "../src/app";

test("POST /api/users rejects invalid input with 400, not 500", () => {
  fc.assert(
    fc.asyncProperty(fc.json(), async (body) => {
      const res = await request(app)
        .post("/api/users")
        .send(JSON.parse(body))
        .set("Content-Type", "application/json");
      expect(res.status).not.toBe(500); // 400 is fine, 500 is a bug
    }),
    { numRuns: 5_000 }
  );
});
```

### Jazzer.js (Coverage-Guided)

```javascript
// fuzz_target.js
const { FuzzedDataProvider } = require("@jazzer.js/core");

module.exports.fuzz = function(fuzzerInputData) {
    const data = new FuzzedDataProvider(fuzzerInputData);
    const n = data.consumeIntegral(4);
    const s = data.consumeString(100, "utf-8");
    const b = data.consumeBoolean();

    try {
        myLibrary.process(n, s, b);
    } catch (e) {
        if (e instanceof TypeError) return; // Expected
        throw e; // Unexpected
    }
};
```

```bash
JAZZER_FUZZ=1 npx jest -- fuzz_target  # Fuzzing mode
npx jest -- fuzz_target                 # Regression mode (replays corpus)
```

### CI Integration (TypeScript)

```yaml
name: Fuzz
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '22' }
      - run: npm ci
      - name: fast-check tests
        run: npx jest --testPathPattern='fuzz|property' --forceExit
      - name: Jazzer.js regression
        run: npx jest --testPathPattern='fuzz_target' --forceExit
```

---

## C / C++

### Setup

```bash
# Verify clang with fuzzer support
clang -fsanitize=fuzzer -x c - -o /dev/null < /dev/null

# Install AFL++ (optional)
apt-get install afl++
# or build from source: https://github.com/AFLplusplus/AFLplusplus
```

### libFuzzer Harnesses

**Crash Detector:**
```c
#include <stdint.h>
#include <stddef.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 1000000) return 0;
    parse_message(data, size);
    return 0;
}
```

**With one-time initialization (CRITICAL for performance):**
```c
#include <stdint.h>
#include <stddef.h>

static Database *db = NULL;

// Called ONCE before fuzzing starts. Move expensive setup here.
int LLVMFuzzerInitialize(int *argc, char ***argv) {
    db = database_open(":memory:");
    database_create_tables(db);
    return 0;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 65536) return 0;
    database_process_query(db, data, size);
    database_reset(db);  // Reset state between inputs, don't re-create
    return 0;
}
```

**Custom Mutator:**
```c
#include <stdint.h>
#include <stddef.h>

size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size,
                                size_t max_size, unsigned int seed) {
    // Decompress → mutate → recompress
    uint8_t *decompressed = NULL;
    size_t dec_size = 0;
    if (decompress(data, size, &decompressed, &dec_size) == 0) {
        // Mutate decompressed data using standard mutator
        dec_size = LLVMFuzzerMutate(decompressed, dec_size, dec_size * 2);
        // Recompress
        uint8_t *recompressed = NULL;
        size_t rec_size = 0;
        if (compress(decompressed, dec_size, &recompressed, &rec_size) == 0) {
            size_t new_size = rec_size < max_size ? rec_size : max_size;
            memcpy(data, recompressed, new_size);
            free(recompressed);
            free(decompressed);
            return new_size;
        }
        free(decompressed);
    }
    // Fallback: standard mutation on raw bytes
    return LLVMFuzzerMutate(data, size, max_size);
}

size_t LLVMFuzzerCustomCrossOver(const uint8_t *data1, size_t size1,
                                  const uint8_t *data2, size_t size2,
                                  uint8_t *out, size_t max_out_size,
                                  unsigned int seed) {
    // Cross two inputs (optional but helps diversity)
    size_t copy_size = size1 < max_out_size ? size1 : max_out_size;
    memcpy(out, data1, copy_size);
    return copy_size;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    // ...
    return 0;
}
```

**Round-Trip:**
```c
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 65536) return 0;
    MyStruct *parsed = parse(data, size);
    if (!parsed) return 0;  // Invalid input, graceful rejection

    uint8_t *reencoded = NULL;
    size_t reencoded_size = 0;
    int ret = serialize(parsed, &reencoded, &reencoded_size);
    assert(ret == 0 && "Cannot serialize our own output");

    MyStruct *reparsed = parse(reencoded, reencoded_size);
    assert(reparsed != NULL && "Cannot parse our own output");
    assert(my_struct_eq(parsed, reparsed) && "Round-trip changed value");

    free_my_struct(parsed);
    free_my_struct(reparsed);
    free(reencoded);
    return 0;
}
```

### Compilation

```bash
# libFuzzer + ASan + UBSan (recommended)
clang -g -O1 -fsanitize=fuzzer,address,undefined target.c -o target

# libFuzzer + MSan (for uninit reads — cannot combine with ASan)
clang -g -O1 -fsanitize=fuzzer,memory -fno-omit-frame-pointer target.c -o target_msan

# libFuzzer + TSan (for data races)
clang -g -O1 -fsanitize=fuzzer,thread target.c -o target_tsan

# AFL++
afl-cc -g -O1 -fsanitize=address,undefined -o target_afl target.c
afl-fuzz -i corpus/ -o findings/ -- ./target_afl @@
```

### CMake Integration

```cmake
# CMakeLists.txt
option(ENABLE_FUZZING "Build fuzz targets" OFF)

if(ENABLE_FUZZING)
    add_executable(fuzz_parser fuzz/fuzz_parser.c)
    target_link_libraries(fuzz_parser PRIVATE mylib)
    target_compile_options(fuzz_parser PRIVATE -fsanitize=fuzzer,address,undefined)
    target_link_options(fuzz_parser PRIVATE -fsanitize=fuzzer,address,undefined)
endif()
```

```bash
cmake -B build -DENABLE_FUZZING=ON -DCMAKE_C_COMPILER=clang
cmake --build build
./build/fuzz_parser corpus/
```

### libprotobuf-mutator (Structure-Aware C++)

```cpp
#include "src/libfuzzer/libfuzzer_macro.h"
#include "my_message.pb.h"

DEFINE_PROTO_FUZZER(const MyMessage& msg) {
    // msg is always a valid protobuf message
    process_message(msg);
}
```

```cmake
# Link with libprotobuf-mutator
target_link_libraries(fuzz_target PRIVATE protobuf-mutator protobuf-mutator-libfuzzer)
```

### CI Integration (C/C++)

```yaml
name: Fuzz
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get install -y clang llvm
      - name: Build fuzz targets
        run: cmake -B build -DENABLE_FUZZING=ON && cmake --build build
      - name: Run regression
        run: |
          for target in build/fuzz_*; do
            "$target" -max_total_time=60 corpus/ || exit 1
          done
```

---

## Java / JVM

### Setup

```bash
# Jazzer (coverage-guided, recommended)
# Add to build.gradle or pom.xml

# Gradle
testImplementation 'com.code-intelligence:jazzer-junit:0.22.1'

# Maven
<dependency>
    <groupId>com.code-intelligence</groupId>
    <artifactId>jazzer-junit</artifactId>
    <version>0.22.1</version>
    <scope>test</scope>
</dependency>
```

### Jazzer Harnesses

**Crash Detector:**
```java
import com.code_intelligence.jazzer.api.FuzzedDataProvider;
import com.code_intelligence.jazzer.junit.FuzzTest;

class ParserFuzzTest {
    @FuzzTest
    void fuzzParser(FuzzedDataProvider data) {
        byte[] input = data.consumeBytes(data.remainingBytes());
        if (input.length > 1_000_000) return;
        try {
            MyParser.parse(input);
        } catch (ParseException e) {
            // Expected — not a bug
        }
    }
}
```

**Structured Input:**
```java
@FuzzTest
void fuzzWithStructuredInput(FuzzedDataProvider data) {
    String name = data.consumeString(100);
    int age = data.consumeInt(0, 150);
    boolean active = data.consumeBoolean();
    String format = data.pickValue(new String[]{"json", "xml", "csv"});

    try {
        UserService.createUser(name, age, active, format);
    } catch (ValidationException e) {
        // Expected
    }
}
```

**Round-Trip:**
```java
@FuzzTest
void fuzzRoundTrip(FuzzedDataProvider data) {
    byte[] input = data.consumeBytes(65536);
    MyMessage parsed;
    try {
        parsed = MyMessage.parseFrom(input);
    } catch (InvalidProtocolBufferException e) {
        return; // Invalid protobuf, expected
    }
    byte[] reencoded = parsed.toByteArray();
    MyMessage reparsed = MyMessage.parseFrom(reencoded);
    assert parsed.equals(reparsed) : "Round-trip changed value";
}
```

**Differential:**
```java
@FuzzTest
void fuzzDifferential(FuzzedDataProvider data) {
    String jsonStr = data.consumeRemainingAsString();
    Object ours, ref;
    try {
        ref = new ObjectMapper().readValue(jsonStr, Object.class);  // Jackson
    } catch (Exception e) {
        return; // Invalid JSON
    }
    try {
        ours = new Gson().fromJson(jsonStr, Object.class);  // Gson
    } catch (Exception e) {
        throw new AssertionError("Jackson accepts but Gson rejects: " + jsonStr, e);
    }
    // Compare outputs (need normalized comparison)
}
```

**FuzzedDataProvider API (Java):**

| Method | Returns | Use For |
|--------|---------|---------|
| `consumeBytes(n)` | byte[] | Raw bytes |
| `consumeString(n)` | String | Text |
| `consumeInt(min, max)` | int | Bounded int |
| `consumeLong(min, max)` | long | Bounded long |
| `consumeFloat()` | float | Float |
| `consumeDouble()` | double | Double |
| `consumeBoolean()` | boolean | Flag |
| `pickValue(T[])` | T | Choose from array |
| `remainingBytes()` | int | Bytes left |
| `consumeRemainingAsString()` | String | All remaining as string |

### Run Commands

```bash
# Run with Jazzer (standalone)
jazzer --target_class=com.example.ParserFuzzTest \
       --instrumentation_includes=com.example.** \
       --keep_going=10

# Run with JUnit (integrates with existing test runner)
./gradlew test --tests "*FuzzTest*"

# With JaCoCo coverage
./gradlew test jacocoTestReport
```

### JQF (Alternative — Java QuickCheck + Fuzz)

```java
import edu.berkeley.cs.jqf.fuzz.Fuzz;
import edu.berkeley.cs.jqf.fuzz.JQF;
import org.junit.runner.RunWith;

@RunWith(JQF.class)
public class ParserFuzzTest {
    @Fuzz
    public void fuzzParse(byte[] data) {
        try {
            MyParser.parse(data);
        } catch (ParseException e) {
            // Expected
        }
    }
}
```

```bash
# Run with Zest algorithm (coverage-guided)
mvn jqf:fuzz -Dclass=com.example.ParserFuzzTest -Dmethod=fuzzParse -Dtime=5m
```

### CI Integration (Java)

```yaml
name: Fuzz
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { java-version: '21', distribution: 'temurin' }
      - name: Run Jazzer fuzz tests
        run: ./gradlew test --tests "*FuzzTest*"
        timeout-minutes: 10
```

---

## Smart Contracts (Solidity)

### Echidna (Property-Based)

```solidity
// contracts/TokenTest.sol
import "./Token.sol";

contract TokenFuzzTest is Token {
    constructor() Token(1000000) {}

    // Properties that must ALWAYS hold
    function echidna_total_supply_constant() public view returns (bool) {
        return totalSupply() == 1000000;
    }

    function echidna_balance_leq_supply() public view returns (bool) {
        return balanceOf(msg.sender) <= totalSupply();
    }
}
```

```bash
echidna contracts/TokenTest.sol --contract TokenFuzzTest --test-mode assertion
```

### Foundry forge fuzz

```solidity
// test/Token.t.sol
import "forge-std/Test.sol";
import "../src/Token.sol";

contract TokenFuzzTest is Test {
    Token token;

    function setUp() public {
        token = new Token(1000000);
    }

    // Foundry automatically fuzzes parameters
    function testFuzz_transfer(address to, uint256 amount) public {
        vm.assume(to != address(0));
        vm.assume(amount <= token.balanceOf(address(this)));

        uint256 balBefore = token.balanceOf(to);
        token.transfer(to, amount);
        assertEq(token.balanceOf(to), balBefore + amount);
    }
}
```

```bash
forge test --match-test "testFuzz_" -vvv
forge test --match-test "testFuzz_" --fuzz-runs 100000
```

### CI Integration (Solidity)

```yaml
name: Fuzz
on: pull_request
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: foundry-rs/foundry-toolchain@v1
      - run: forge test --match-test "testFuzz_" --fuzz-runs 10000
```
