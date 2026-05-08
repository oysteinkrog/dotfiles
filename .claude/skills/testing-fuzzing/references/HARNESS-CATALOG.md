# Fuzz Harness Catalog

> Complete code templates for every fuzzing archetype, in every supported language. Copy, adapt, run.

## Contents

1. [Crash Detector (Raw Bytes)](#1-crash-detector-raw-bytes)
2. [Round-Trip (Serialize/Deserialize)](#2-round-trip-serializedeserialize)
3. [Differential (Two Implementations)](#3-differential-two-implementations)
4. [Stateful (Operation Sequences)](#4-stateful-operation-sequences)
5. [Grammar-Based (Syntax-Aware)](#5-grammar-based-syntax-aware)
6. [Custom Mutator (Domain-Specific)](#6-custom-mutator-domain-specific)
7. [Concurrency (Race Conditions)](#7-concurrency-race-conditions)

**Languages:** Rust, Go, Python, TypeScript, C/C++, Java

---

## 1. Crash Detector (Raw Bytes)

The simplest archetype: feed raw bytes into a parser or decoder and detect panics, crashes, or undefined behavior. The oracle is "no crash on any input."

### Rust (cargo-fuzz / libFuzzer)

```rust
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    // Size guard: avoid OOM on huge allocations
    if data.len() > 1_000_000 { return; }
    // Oracle: must not panic on any input
    let _ = my_crate::parse(data);
});
```

### Go (native fuzzing, Go 1.18+)

```go
package mypackage

import "testing"

func FuzzParse(f *testing.F) {
    // Seed corpus: one valid, one empty, one adversarial
    f.Add([]byte("valid input"))
    f.Add([]byte{})
    f.Add([]byte{0xFF, 0xFE})

    f.Fuzz(func(t *testing.T, data []byte) {
        if len(data) > 1_000_000 {
            return
        }
        // Oracle: must not panic on any input
        _ = Parse(data)
    })
}
```

### Python (Atheris)

```python
import atheris
import sys

# instrument_imports must wrap the target library for coverage
with atheris.instrument_imports():
    import my_library

def TestOneInput(data):
    if len(data) > 1_000_000:
        return
    try:
        my_library.parse(data)
    except (ValueError, TypeError):
        pass  # Expected error types -- not bugs
    # Any other exception propagates and counts as a finding

atheris.Setup(sys.argv, TestOneInput)
atheris.Fuzz()
```

### TypeScript (Jazzer.js)

```javascript
// fuzz.js -- run with: npx jazzer fuzz.js
module.exports.fuzz = function(data) {
    if (data.length > 1_000_000) return;
    try {
        myLibrary.parse(data.toString("utf-8"));
    } catch (e) {
        if (e instanceof SyntaxError) return; // Expected
        throw e; // Unexpected = bug
    }
};
```

### C/C++ (libFuzzer)

```c
// crash_fuzz.c -- compile: clang -fsanitize=fuzzer,address crash_fuzz.c -o fuzz
#include <stdint.h>
#include <stddef.h>

// Forward-declare the target function
int my_parse(const uint8_t *data, size_t size);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    // Size guard: reject enormous inputs to avoid OOM
    if (size > 1000000) return 0;
    // Oracle: must not crash, trigger ASan, or invoke UB
    my_parse(data, size);
    return 0;  // Always return 0 (non-zero is reserved by libFuzzer)
}
```

### Java (Jazzer)

```java
import com.code_intelligence.jazzer.api.FuzzedDataProvider;

// Run with: jazzer --target_class=CrashFuzzer
public class CrashFuzzer {
    public static void fuzzerTestOneInput(FuzzedDataProvider data) {
        byte[] bytes = data.consumeRemainingAsBytes();
        if (bytes.length > 1_000_000) return;
        try {
            MyLibrary.parse(bytes);
        } catch (IllegalArgumentException | NullPointerException e) {
            // Expected errors -- not bugs
        }
        // Any other uncaught exception = finding
    }
}
```

---

## 2. Round-Trip (Serialize/Deserialize)

Encode a value, decode it, and assert the result matches the original. The oracle is `decode(encode(x)) == x` -- any divergence is a bug.

### Rust (cargo-fuzz + arbitrary)

```rust
#![no_main]
use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;

#[derive(Debug, Arbitrary, PartialEq)]
enum FuzzValue {
    Null,
    Bool(bool),
    Int(i64),
    Float(f64),
    Text(String),
    Blob(Vec<u8>),
}

#[derive(Debug, Arbitrary)]
struct FuzzInput {
    raw: Vec<u8>,
    values: Vec<FuzzValue>,
}

fuzz_target!(|input: FuzzInput| {
    // Strategy 1: Raw bytes must not panic
    if input.raw.len() <= 65536 {
        let _ = parse(&input.raw);
    }

    // Strategy 2: Structured values must round-trip
    if !input.values.is_empty() && input.values.len() <= 1000 {
        let native: Vec<Value> = input.values.iter()
            .map(|v| v.into())
            .collect();
        let bytes = serialize(&native);
        let recovered = parse(&bytes)
            .expect("Cannot parse our own output");
        assert_eq!(native, recovered, "Round-trip corruption");
    }
});
```

### Go (native fuzzing)

```go
package mypackage

import (
    "encoding/json"
    "reflect"
    "testing"
)

func FuzzRoundTrip(f *testing.F) {
    f.Add([]byte(`{"key":"value"}`))
    f.Add([]byte(`[1, 2, 3]`))
    f.Add([]byte(`"hello"`))

    f.Fuzz(func(t *testing.T, data []byte) {
        // Step 1: parse -- skip if input is not valid
        var parsed interface{}
        if err := json.Unmarshal(data, &parsed); err != nil {
            return
        }
        // Step 2: re-encode
        reencoded, err := json.Marshal(parsed)
        if err != nil {
            t.Fatalf("Marshal failed on valid input: %v", err)
        }
        // Step 3: re-parse and compare
        var reparsed interface{}
        if err := json.Unmarshal(reencoded, &reparsed); err != nil {
            t.Fatalf("Round-trip parse failed: %v", err)
        }
        // Oracle: decode(encode(decode(input))) == decode(input)
        if !reflect.DeepEqual(parsed, reparsed) {
            t.Fatalf("Round-trip changed value:\n  before: %v\n  after:  %v", parsed, reparsed)
        }
    })
}
```

### Python (Atheris)

```python
import atheris
import sys
import json

with atheris.instrument_imports():
    import my_codec

def TestOneInput(data):
    if len(data) > 65536:
        return
    try:
        decoded = my_codec.decode(data)
    except my_codec.DecodeError:
        return  # Invalid input, skip

    # Oracle: re-encode then re-decode must match
    reencoded = my_codec.encode(decoded)
    redecoded = my_codec.decode(reencoded)
    assert decoded == redecoded, (
        f"Round-trip corruption:\n  original: {decoded!r}\n  after:    {redecoded!r}"
    )

atheris.Setup(sys.argv, TestOneInput)
atheris.Fuzz()
```

### TypeScript (Jazzer.js)

```javascript
const assert = require("assert");
const { encode, decode } = require("./my_codec");

module.exports.fuzz = function(data) {
    if (data.length > 65536) return;

    let decoded;
    try {
        decoded = decode(data);
    } catch (e) {
        return; // Invalid input, skip
    }

    // Oracle: round-trip must preserve the value
    const reencoded = encode(decoded);
    const redecoded = decode(reencoded);
    assert.deepStrictEqual(decoded, redecoded,
        "Round-trip corruption detected");
};
```

### C/C++ (libFuzzer)

```cpp
// roundtrip_fuzz.cc -- compile: clang++ -fsanitize=fuzzer,address roundtrip_fuzz.cc -o fuzz
#include <cassert>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <vector>

// Forward-declare encode/decode (adapt to your API)
bool decode(const uint8_t *in, size_t in_len, std::vector<uint8_t> &out);
bool encode(const uint8_t *in, size_t in_len, std::vector<uint8_t> &out);

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 65536) return 0;

    std::vector<uint8_t> decoded;
    if (!decode(data, size, decoded)) return 0; // Invalid input

    // Re-encode then re-decode
    std::vector<uint8_t> reencoded;
    assert(encode(decoded.data(), decoded.size(), reencoded) &&
           "encode() failed on its own output");

    std::vector<uint8_t> redecoded;
    assert(decode(reencoded.data(), reencoded.size(), redecoded) &&
           "decode() failed on re-encoded data");

    // Oracle: round-trip must be stable
    assert(decoded == redecoded && "Round-trip corruption");
    return 0;
}
```

### Java (Jazzer)

```java
import com.code_intelligence.jazzer.api.FuzzedDataProvider;
import java.util.Arrays;

public class RoundTripFuzzer {
    public static void fuzzerTestOneInput(FuzzedDataProvider data) {
        byte[] input = data.consumeRemainingAsBytes();
        if (input.length > 65536) return;

        Object decoded;
        try {
            decoded = MyCodec.decode(input);
        } catch (IllegalArgumentException e) {
            return; // Invalid input, skip
        }

        // Oracle: encode then decode must match
        byte[] reencoded = MyCodec.encode(decoded);
        Object redecoded = MyCodec.decode(reencoded);

        if (!decoded.equals(redecoded)) {
            throw new AssertionError(String.format(
                "Round-trip corruption:\n  original: %s\n  after:    %s",
                decoded, redecoded));
        }
    }
}
```

---

## 3. Differential (Two Implementations)

Feed identical input to two implementations and assert they produce the same output. The oracle is agreement between the reference and the implementation under test.

### Rust (cargo-fuzz + arbitrary)

```rust
#![no_main]
use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;
use std::collections::BTreeMap;

#[derive(Arbitrary, Debug)]
enum Op<K: Ord, V> {
    Insert { key: K, val: V },
    Get { key: K },
    Remove { key: K },
    Len,
}

fuzz_target!(|ops: Vec<Op<u8, u16>>| {
    if ops.len() > 500 { return; }

    let mut ours = MyMap::new();
    let mut reference = BTreeMap::new();

    for op in &ops {
        match op {
            Op::Insert { key, val } => {
                assert_eq!(ours.insert(*key, *val), reference.insert(*key, *val));
            }
            Op::Get { key } => {
                assert_eq!(ours.get(key), reference.get(key));
            }
            Op::Remove { key } => {
                assert_eq!(ours.remove(key), reference.remove(key));
            }
            Op::Len => {
                assert_eq!(ours.len(), reference.len());
            }
        }
    }
    // Final state must match
    assert!(ours.iter().eq(reference.iter()));
});
```

### Go (native fuzzing)

```go
package mypackage

import (
    "encoding/json"
    "testing"

    "github.com/example/fast_json" // the implementation under test
)

func FuzzDifferentialJSON(f *testing.F) {
    f.Add([]byte(`{"a":1,"b":[true,null]}`))
    f.Add([]byte(`"escaped\"quote"`))

    f.Fuzz(func(t *testing.T, data []byte) {
        if len(data) > 100_000 {
            return
        }

        // Reference: stdlib
        var refResult interface{}
        refErr := json.Unmarshal(data, &refResult)

        // Implementation under test
        var testResult interface{}
        testErr := fast_json.Unmarshal(data, &testResult)

        // Oracle: both must agree on validity
        if (refErr == nil) != (testErr == nil) {
            t.Fatalf("Validity disagreement on %q:\n  stdlib err: %v\n  fast err:   %v",
                data, refErr, testErr)
        }
        // If both succeeded, outputs must match
        if refErr == nil {
            refJSON, _ := json.Marshal(refResult)
            testJSON, _ := json.Marshal(testResult)
            if string(refJSON) != string(testJSON) {
                t.Fatalf("Output disagreement:\n  stdlib: %s\n  fast:   %s", refJSON, testJSON)
            }
        }
    })
}
```

### Python (Atheris)

```python
import atheris
import sys
import json

with atheris.instrument_imports():
    import ujson  # implementation under test

def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    json_str = fdp.ConsumeUnicode(min(fdp.remaining_bytes(), 100_000))

    # Run both implementations
    ref_ok, ref_val = True, None
    test_ok, test_val = True, None
    try:
        ref_val = json.loads(json_str)
    except Exception:
        ref_ok = False
    try:
        test_val = ujson.loads(json_str)
    except Exception:
        test_ok = False

    # Oracle: must agree on validity
    if ref_ok != test_ok:
        raise RuntimeError(
            f"Validity disagreement on {json_str!r}: "
            f"stdlib={'ok' if ref_ok else 'err'}, ujson={'ok' if test_ok else 'err'}"
        )
    # If both succeeded, normalize and compare
    if ref_ok:
        if json.dumps(ref_val, sort_keys=True) != json.dumps(test_val, sort_keys=True):
            raise RuntimeError(
                f"Output disagreement on {json_str!r}:\n"
                f"  stdlib: {ref_val!r}\n  ujson:  {test_val!r}"
            )

atheris.Setup(sys.argv, TestOneInput)
atheris.Fuzz()
```

### TypeScript (Jazzer.js)

```javascript
const assert = require("assert");
const refImpl = require("./reference");
const testImpl = require("./optimized");

module.exports.fuzz = function(data) {
    const input = data.toString("utf-8");
    if (input.length > 100_000) return;

    let refResult, refErr;
    let testResult, testErr;

    try { refResult = refImpl.parse(input); }
    catch (e) { refErr = e; }

    try { testResult = testImpl.parse(input); }
    catch (e) { testErr = e; }

    // Oracle: both must agree on validity
    if (!!refErr !== !!testErr) {
        throw new Error(
            `Validity disagreement: ref=${refErr ? "err" : "ok"}, test=${testErr ? "err" : "ok"}`
        );
    }

    // If both succeeded, outputs must match
    if (!refErr) {
        assert.deepStrictEqual(refResult, testResult,
            "Differential: implementations disagree on output");
    }
};
```

### C/C++ (libFuzzer)

```cpp
// diff_fuzz.cc -- compile: clang++ -fsanitize=fuzzer,address diff_fuzz.cc -o fuzz
#include <cassert>
#include <cstdint>
#include <cstddef>
#include <cstring>
#include <vector>

// Two implementations of the same function
int reference_parse(const uint8_t *data, size_t size, std::vector<uint8_t> &out);
int optimized_parse(const uint8_t *data, size_t size, std::vector<uint8_t> &out);

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 100000) return 0;

    std::vector<uint8_t> ref_out, test_out;
    int ref_rc = reference_parse(data, size, ref_out);
    int test_rc = optimized_parse(data, size, test_out);

    // Oracle: must agree on validity
    assert((ref_rc == 0) == (test_rc == 0) &&
           "Validity disagreement between implementations");

    // If both succeeded, output must match
    if (ref_rc == 0) {
        assert(ref_out == test_out &&
               "Output disagreement between implementations");
    }
    return 0;
}
```

### Java (Jazzer)

```java
import com.code_intelligence.jazzer.api.FuzzedDataProvider;
import java.util.Arrays;

public class DifferentialFuzzer {
    public static void fuzzerTestOneInput(FuzzedDataProvider data) {
        byte[] input = data.consumeRemainingAsBytes();
        if (input.length > 100_000) return;

        // Reference implementation (e.g., stdlib)
        Object refResult = null;
        Exception refErr = null;
        try { refResult = ReferenceImpl.parse(input); }
        catch (Exception e) { refErr = e; }

        // Implementation under test
        Object testResult = null;
        Exception testErr = null;
        try { testResult = OptimizedImpl.parse(input); }
        catch (Exception e) { testErr = e; }

        // Oracle: must agree on validity
        if ((refErr == null) != (testErr == null)) {
            throw new AssertionError(String.format(
                "Validity disagreement: ref=%s, test=%s",
                refErr == null ? "ok" : "err", testErr == null ? "ok" : "err"));
        }

        // If both succeeded, outputs must match
        if (refErr == null && !refResult.equals(testResult)) {
            throw new AssertionError(String.format(
                "Output disagreement:\n  ref:  %s\n  test: %s", refResult, testResult));
        }
    }
}
```

---

## 4. Stateful (Operation Sequences)

Apply a sequence of fuzzed operations to a stateful system and compare against a simple reference model after each step. The oracle is "real system state matches model state at every point."

### Rust (cargo-fuzz + arbitrary)

```rust
#![no_main]
use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;
use std::collections::{HashMap, BTreeSet};

#[derive(Debug, Arbitrary)]
enum FileOp {
    Create { name: u8, content: Vec<u8> },
    Read { name: u8 },
    Delete { name: u8 },
    Rename { from: u8, to: u8 },
    List,
    Sync,
}

fuzz_target!(|ops: Vec<FileOp>| {
    if ops.len() > 200 { return; }
    // Reject individual huge payloads
    if ops.iter().any(|op| matches!(op,
        FileOp::Create { content, .. } if content.len() > 10_000
    )) { return; }

    let fs = TestFs::new_in_memory();
    let mut model = HashMap::new();

    for op in &ops {
        match op {
            FileOp::Create { name, content } => {
                let key = format!("f{name}");
                let _ = fs.write(&key, content);
                model.insert(key, content.clone());
            }
            FileOp::Read { name } => {
                let key = format!("f{name}");
                let fs_result = fs.read(&key).ok();
                let model_result = model.get(&key);
                assert_eq!(fs_result.as_deref(), model_result.map(|v| v.as_slice()));
            }
            FileOp::Delete { name } => {
                let key = format!("f{name}");
                let _ = fs.delete(&key);
                model.remove(&key);
            }
            FileOp::Rename { from, to } => {
                let from_key = format!("f{from}");
                let to_key = format!("f{to}");
                if let Some(data) = model.remove(&from_key) {
                    let _ = fs.rename(&from_key, &to_key);
                    model.insert(to_key, data);
                }
            }
            FileOp::List => {
                let fs_list: BTreeSet<_> = fs.list().into_iter().collect();
                let model_list: BTreeSet<_> = model.keys().cloned().collect();
                assert_eq!(fs_list, model_list);
            }
            FileOp::Sync => { let _ = fs.sync(); }
        }
    }

    // Final invariant check
    fs.check_invariants().expect("Invariant violation after op sequence");
});
```

### Go (native fuzzing)

```go
package mypackage

import (
    "encoding/binary"
    "testing"
)

// Op types encoded as single bytes in the fuzz input
const (
    opPut    = 0
    opGet    = 1
    opDelete = 2
    opLen    = 3
)

func FuzzStatefulCache(f *testing.F) {
    f.Add([]byte{opPut, 1, 0x41, opGet, 1, opDelete, 1, opLen})

    f.Fuzz(func(t *testing.T, data []byte) {
        if len(data) > 10_000 {
            return
        }

        cache := NewCache(256) // system under test
        model := make(map[byte]byte) // simple reference model

        i := 0
        for i < len(data) {
            if i >= len(data) { break }
            op := data[i]
            i++

            switch op % 4 {
            case opPut:
                if i+2 > len(data) { return }
                key, val := data[i], data[i+1]
                i += 2
                cache.Put(key, val)
                model[key] = val

            case opGet:
                if i+1 > len(data) { return }
                key := data[i]
                i++
                got, ok := cache.Get(key)
                expected, exists := model[key]
                // Oracle: cache must agree with model
                if ok != exists {
                    t.Fatalf("Get(%d): cache has=%v, model has=%v", key, ok, exists)
                }
                if ok && got != expected {
                    t.Fatalf("Get(%d): cache=%d, model=%d", key, got, expected)
                }

            case opDelete:
                if i+1 > len(data) { return }
                key := data[i]
                i++
                cache.Delete(key)
                delete(model, key)

            case opLen:
                if cache.Len() != len(model) {
                    t.Fatalf("Len: cache=%d, model=%d", cache.Len(), len(model))
                }
            }
        }
    })
}
```

### Python (Atheris)

```python
import atheris
import sys

with atheris.instrument_imports():
    import my_cache

def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    cache = my_cache.LRUCache(capacity=64)
    model = {}  # simple reference dict

    num_ops = fdp.ConsumeIntInRange(0, 200)
    for _ in range(num_ops):
        op = fdp.ConsumeIntInRange(0, 3)

        if op == 0:  # PUT
            key = fdp.ConsumeUnicodeNoSurrogates(8)
            val = fdp.ConsumeUnicodeNoSurrogates(16)
            cache.put(key, val)
            model[key] = val
        elif op == 1:  # GET
            key = fdp.ConsumeUnicodeNoSurrogates(8)
            got = cache.get(key)
            expected = model.get(key)
            # Oracle: if model has it, cache must too (unless evicted -- adjust for LRU)
            if key in model:
                assert got == expected, (
                    f"GET mismatch for {key!r}: cache={got!r}, model={expected!r}"
                )
        elif op == 2:  # DELETE
            key = fdp.ConsumeUnicodeNoSurrogates(8)
            cache.delete(key)
            model.pop(key, None)
        elif op == 3:  # LEN
            # For bounded caches, len(cache) <= capacity always
            assert cache.size() <= 64, f"Cache exceeded capacity: {cache.size()}"

atheris.Setup(sys.argv, TestOneInput)
atheris.Fuzz()
```

### TypeScript (Jazzer.js)

```javascript
const assert = require("assert");
const { MyMap } = require("./my_map");

module.exports.fuzz = function(data) {
    if (data.length > 10_000) return;

    const map = new MyMap();       // system under test
    const model = new Map();       // reference model

    let i = 0;
    while (i < data.length) {
        const op = data[i++] % 4;

        if (op === 0 && i + 2 <= data.length) {
            // PUT
            const key = data[i++];
            const val = data[i++];
            map.set(key, val);
            model.set(key, val);

        } else if (op === 1 && i + 1 <= data.length) {
            // GET -- oracle: must match model
            const key = data[i++];
            assert.strictEqual(map.get(key), model.get(key),
                `GET mismatch for key=${key}`);

        } else if (op === 2 && i + 1 <= data.length) {
            // DELETE
            const key = data[i++];
            map.delete(key);
            model.delete(key);

        } else if (op === 3) {
            // SIZE -- oracle: must match
            assert.strictEqual(map.size, model.size, "Size mismatch");
        } else {
            break;
        }
    }
};
```

### C/C++ (libFuzzer)

```cpp
// stateful_fuzz.cc -- compile: clang++ -fsanitize=fuzzer,address stateful_fuzz.cc -o fuzz
#include <cassert>
#include <cstdint>
#include <cstddef>
#include <map>

#include "my_map.h"  // system under test

enum Op : uint8_t { OP_PUT = 0, OP_GET = 1, OP_DELETE = 2, OP_SIZE = 3 };

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 10000) return 0;

    MyMap sut;                            // system under test
    std::map<uint8_t, uint8_t> model;     // reference model

    size_t i = 0;
    while (i < size) {
        uint8_t op = data[i++] % 4;

        switch (op) {
        case OP_PUT:
            if (i + 2 > size) return 0;
            { uint8_t k = data[i++], v = data[i++];
              sut.put(k, v);
              model[k] = v; }
            break;

        case OP_GET:
            if (i + 1 > size) return 0;
            { uint8_t k = data[i++];
              auto sut_it = sut.find(k);
              auto mod_it = model.find(k);
              // Oracle: both must agree on presence and value
              assert((sut_it != nullptr) == (mod_it != model.end()));
              if (mod_it != model.end()) {
                  assert(*sut_it == mod_it->second);
              }
            }
            break;

        case OP_DELETE:
            if (i + 1 > size) return 0;
            { uint8_t k = data[i++];
              sut.remove(k);
              model.erase(k); }
            break;

        case OP_SIZE:
            assert(sut.size() == model.size());
            break;
        }
    }
    return 0;
}
```

### Java (Jazzer)

```java
import com.code_intelligence.jazzer.api.FuzzedDataProvider;
import java.util.HashMap;
import java.util.Map;

public class StatefulFuzzer {
    public static void fuzzerTestOneInput(FuzzedDataProvider data) {
        MyCache<String, String> cache = new MyCache<>(128);  // system under test
        Map<String, String> model = new HashMap<>();          // reference model

        int numOps = data.consumeInt(0, 200);
        for (int i = 0; i < numOps; i++) {
            int op = data.consumeInt(0, 3);

            switch (op) {
                case 0: { // PUT
                    String key = data.consumeString(8);
                    String val = data.consumeString(16);
                    cache.put(key, val);
                    model.put(key, val);
                    break;
                }
                case 1: { // GET -- oracle: must agree with model
                    String key = data.consumeString(8);
                    String got = cache.get(key);
                    String expected = model.get(key);
                    if (expected != null && !expected.equals(got)) {
                        throw new AssertionError(String.format(
                            "GET mismatch for '%s': cache='%s', model='%s'",
                            key, got, expected));
                    }
                    break;
                }
                case 2: { // DELETE
                    String key = data.consumeString(8);
                    cache.remove(key);
                    model.remove(key);
                    break;
                }
                case 3: { // SIZE
                    if (cache.size() > 128) {
                        throw new AssertionError("Cache exceeded capacity: " + cache.size());
                    }
                    break;
                }
            }
        }
    }
}
```

---

## 5. Grammar-Based (Syntax-Aware)

Generate syntactically valid inputs according to a grammar so the fuzzer spends time testing semantic logic rather than being rejected by the parser. The oracle depends on the target: crash-freedom, evaluation correctness, or invariant preservation.

### Rust (cargo-fuzz + arbitrary)

```rust
#![no_main]
use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;

/// A minimal expression grammar for arithmetic
#[derive(Debug, Arbitrary)]
enum Expr {
    Lit(i32),
    Var(u8),                              // variable index 0..3
    Add(Box<Expr>, Box<Expr>),
    Mul(Box<Expr>, Box<Expr>),
    Neg(Box<Expr>),
    If { cond: Box<Expr>, then: Box<Expr>, else_: Box<Expr> },
}

impl Expr {
    /// Depth guard: reject deeply nested trees to avoid stack overflow
    fn depth(&self) -> usize {
        match self {
            Expr::Lit(_) | Expr::Var(_) => 1,
            Expr::Add(a, b) | Expr::Mul(a, b) => 1 + a.depth().max(b.depth()),
            Expr::Neg(e) => 1 + e.depth(),
            Expr::If { cond, then, else_ } => {
                1 + cond.depth().max(then.depth()).max(else_.depth())
            }
        }
    }
}

fuzz_target!(|expr: Expr| {
    if expr.depth() > 20 { return; }

    // Oracle 1: pretty-print then re-parse must yield equivalent AST
    let source = pretty_print(&expr);
    let reparsed = parse_expr(&source).expect("Cannot parse our own output");
    assert_eq!(eval(&expr, &[1, 2, 3, 4]), eval(&reparsed, &[1, 2, 3, 4]),
        "Eval mismatch after pretty-print round-trip");

    // Oracle 2: optimizer must preserve semantics
    let optimized = optimize(&expr);
    for vars in [[0, 0, 0, 0], [1, 1, 1, 1], [i32::MAX, 0, i32::MIN, 1]] {
        assert_eq!(eval(&expr, &vars), eval(&optimized, &vars),
            "Optimizer changed semantics for vars={vars:?}");
    }
});
```

### Go (native fuzzing)

```go
package mypackage

import (
    "testing"
)

// Generate structured SQL-like queries from fuzz bytes
func buildQuery(data []byte) string {
    if len(data) < 4 {
        return "SELECT 1"
    }

    tables := []string{"users", "orders", "items"}
    cols := []string{"id", "name", "value", "created_at"}
    ops := []string{"=", "!=", ">", "<", ">=", "<="}

    i := 0
    next := func() byte {
        if i >= len(data) { return 0 }
        b := data[i]; i++; return b
    }

    table := tables[next() % byte(len(tables))]
    col := cols[next() % byte(len(cols))]
    op := ops[next() % byte(len(ops))]
    val := next()

    return "SELECT " + col + " FROM " + table + " WHERE " + col + " " + op + " " + string(rune('0' + val%10))
}

func FuzzGrammarSQL(f *testing.F) {
    f.Add([]byte{0, 0, 0, 0, 0, 0})

    f.Fuzz(func(t *testing.T, data []byte) {
        if len(data) > 1000 { return }

        query := buildQuery(data)

        // Oracle 1: parser must not panic on grammar-generated input
        ast, err := ParseSQL(query)
        if err != nil {
            t.Fatalf("Grammar produced unparseable query: %s\n  error: %v", query, err)
        }

        // Oracle 2: pretty-print round-trip
        printed := ast.String()
        ast2, err := ParseSQL(printed)
        if err != nil {
            t.Fatalf("Cannot re-parse printed query: %s\n  error: %v", printed, err)
        }
        if ast.String() != ast2.String() {
            t.Fatalf("Pretty-print not stable:\n  first:  %s\n  second: %s",
                ast.String(), ast2.String())
        }
    })
}
```

### Python (Atheris)

```python
import atheris
import sys

with atheris.instrument_imports():
    import my_eval

def generate_expr(fdp, depth=0):
    """Generate a syntactically valid arithmetic expression from fuzz bytes."""
    if depth > 10 or fdp.remaining_bytes() == 0:
        return str(fdp.ConsumeIntInRange(-1000, 1000))

    kind = fdp.ConsumeIntInRange(0, 4)
    if kind == 0:
        return str(fdp.ConsumeIntInRange(-1000, 1000))
    elif kind == 1:
        return f"({generate_expr(fdp, depth+1)} + {generate_expr(fdp, depth+1)})"
    elif kind == 2:
        return f"({generate_expr(fdp, depth+1)} * {generate_expr(fdp, depth+1)})"
    elif kind == 3:
        return f"(-{generate_expr(fdp, depth+1)})"
    else:
        return f"({generate_expr(fdp, depth+1)} - {generate_expr(fdp, depth+1)})"

def TestOneInput(data):
    fdp = atheris.FuzzedDataProvider(data)
    expr = generate_expr(fdp)

    # Oracle 1: must not crash on grammar-valid input
    try:
        result = my_eval.evaluate(expr)
    except my_eval.EvalError:
        return  # e.g., division by zero -- expected

    # Oracle 2: cross-check with Python's eval
    try:
        expected = eval(expr)  # safe: only arithmetic from our grammar
    except (ZeroDivisionError, OverflowError):
        return
    assert result == expected, (
        f"Eval mismatch for {expr}: got {result}, expected {expected}"
    )

atheris.Setup(sys.argv, TestOneInput)
atheris.Fuzz()
```

### TypeScript (Jazzer.js)

```javascript
const assert = require("assert");
const { parse, evaluate } = require("./my_eval");

// Grammar-based expression generator driven by fuzz bytes
function genExpr(data, offset, depth) {
    if (depth > 10 || offset >= data.length) {
        return { expr: String(data[offset] || 0), offset: offset + 1 };
    }
    const kind = data[offset++] % 5;
    if (kind === 0) {
        // Literal
        const val = (data[offset] || 0) - 128;
        return { expr: String(val), offset: offset + 1 };
    }
    const left = genExpr(data, offset, depth + 1);
    const right = genExpr(data, left.offset, depth + 1);
    const ops = ["+", "-", "*", "/", "%"];
    return {
        expr: `(${left.expr} ${ops[kind - 1]} ${right.expr})`,
        offset: right.offset,
    };
}

module.exports.fuzz = function(data) {
    if (data.length > 1000) return;

    const { expr } = genExpr(data, 0, 0);

    // Oracle 1: grammar-valid input must parse without error
    let ast;
    try {
        ast = parse(expr);
    } catch (e) {
        throw new Error(`Grammar produced unparseable expr: ${expr}\n  ${e.message}`);
    }

    // Oracle 2: evaluate and cross-check
    try {
        const ours = evaluate(ast);
        const ref = Function(`"use strict"; return (${expr})`)();
        if (Number.isFinite(ref)) {
            assert.strictEqual(ours, ref, `Eval mismatch for: ${expr}`);
        }
    } catch (e) {
        // Division by zero, overflow -- expected for some inputs
    }
};
```

### C/C++ (libFuzzer)

```cpp
// grammar_fuzz.cc -- compile: clang++ -fsanitize=fuzzer,address grammar_fuzz.cc -o fuzz
#include <cassert>
#include <cstdint>
#include <cstddef>
#include <string>

#include "my_parser.h"

// Build a syntactically valid expression from fuzz bytes
static size_t gen_expr(const uint8_t *data, size_t size, size_t off,
                       std::string &out, int depth) {
    if (depth > 12 || off >= size) {
        out += std::to_string(off < size ? (int8_t)data[off] : 0);
        return off + 1;
    }
    uint8_t kind = data[off++] % 4;
    if (kind == 0) {
        // Literal
        out += std::to_string(off < size ? (int8_t)data[off] : 0);
        return off + 1;
    }
    // Binary op
    const char *ops[] = {"+", "-", "*"};
    out += "(";
    off = gen_expr(data, size, off, out, depth + 1);
    out += ops[kind - 1];
    off = gen_expr(data, size, off, out, depth + 1);
    out += ")";
    return off;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 1000) return 0;

    std::string expr;
    gen_expr(data, size, 0, expr, 0);

    // Oracle 1: grammar-valid input must parse
    auto ast = my_parse(expr.c_str());
    assert(ast != nullptr && "Grammar produced unparseable expression");

    // Oracle 2: pretty-print round-trip
    std::string printed = my_pretty_print(ast);
    auto ast2 = my_parse(printed.c_str());
    assert(ast2 != nullptr && "Cannot re-parse pretty-printed output");
    assert(my_eval(ast) == my_eval(ast2) && "Pretty-print changed semantics");

    my_free_ast(ast);
    my_free_ast(ast2);
    return 0;
}
```

### Java (Jazzer)

```java
import com.code_intelligence.jazzer.api.FuzzedDataProvider;

public class GrammarFuzzer {
    // Generate a syntactically valid expression from fuzz bytes
    static String genExpr(FuzzedDataProvider data, int depth) {
        if (depth > 10 || data.remainingBytes() == 0) {
            return String.valueOf(data.consumeInt(-1000, 1000));
        }
        int kind = data.consumeInt(0, 4);
        switch (kind) {
            case 0: return String.valueOf(data.consumeInt(-1000, 1000));
            case 1: return "(" + genExpr(data, depth+1) + " + " + genExpr(data, depth+1) + ")";
            case 2: return "(" + genExpr(data, depth+1) + " * " + genExpr(data, depth+1) + ")";
            case 3: return "(" + genExpr(data, depth+1) + " - " + genExpr(data, depth+1) + ")";
            default: return "(-" + genExpr(data, depth+1) + ")";
        }
    }

    public static void fuzzerTestOneInput(FuzzedDataProvider data) {
        String expr = genExpr(data, 0);

        // Oracle 1: grammar-valid input must parse
        Object ast;
        try {
            ast = MyParser.parse(expr);
        } catch (Exception e) {
            throw new AssertionError("Grammar produced unparseable expr: " + expr, e);
        }

        // Oracle 2: pretty-print round-trip preserves semantics
        String printed = MyParser.prettyPrint(ast);
        Object ast2;
        try {
            ast2 = MyParser.parse(printed);
        } catch (Exception e) {
            throw new AssertionError("Cannot re-parse: " + printed, e);
        }

        long val1 = MyParser.evaluate(ast);
        long val2 = MyParser.evaluate(ast2);
        if (val1 != val2) {
            throw new AssertionError(String.format(
                "Pretty-print changed semantics: %s=%d vs %s=%d", expr, val1, printed, val2));
        }
    }
}
```

---

## 6. Custom Mutator (Domain-Specific)

When the input format has structure that random byte-flipping cannot explore efficiently (e.g., compressed data, checksummed packets), a custom mutator decomposes the input, applies mutations to the inner payload, then re-wraps it.

### Rust (cargo-fuzz / libFuzzer)

```rust
#![no_main]
use libfuzzer_sys::{fuzz_target, fuzz_mutator};

fuzz_target!(|data: &[u8]| {
    if data.len() > 1_000_000 { return; }
    if let Ok(decompressed) = decompress(data) {
        // Oracle: must not crash on any valid compressed payload
        let _ = parse_message(&decompressed);
    }
});

fuzz_mutator!(|data: &mut [u8], size: usize, max_size: usize, _seed: u32| {
    // Decompress -> mutate inner payload -> recompress
    if let Ok(decompressed) = decompress(&data[..size]) {
        let mut mutated = decompressed;
        libfuzzer_sys::fuzzer_mutate(&mut mutated, mutated.len(), mutated.len() * 2);
        if let Ok(recompressed) = compress(&mutated) {
            let new_size = recompressed.len().min(max_size);
            data[..new_size].copy_from_slice(&recompressed[..new_size]);
            return new_size;
        }
    }
    // Fallback: standard mutation on raw bytes
    libfuzzer_sys::fuzzer_mutate(data, size, max_size)
});
```

### Go (native fuzzing)

```go
package mypackage

import (
    "bytes"
    "compress/gzip"
    "io"
    "testing"
)

// Go's native fuzzer does not support custom mutators directly.
// Workaround: seed the corpus with pre-compressed valid inputs,
// and decompress inside the harness so coverage guides toward valid payloads.

func FuzzCompressedParser(f *testing.F) {
    // Seed with valid compressed payloads
    for _, input := range []string{"hello", `{"key":"val"}`, ""} {
        var buf bytes.Buffer
        w := gzip.NewWriter(&buf)
        w.Write([]byte(input))
        w.Close()
        f.Add(buf.Bytes())
    }

    f.Fuzz(func(t *testing.T, data []byte) {
        if len(data) > 1_000_000 { return }

        r, err := gzip.NewReader(bytes.NewReader(data))
        if err != nil {
            return // Not valid gzip -- skip
        }
        decompressed, err := io.ReadAll(io.LimitReader(r, 10_000_000))
        if err != nil {
            return // Truncated stream -- skip
        }

        // Oracle: must not panic on any decompressed payload
        _ = ParseMessage(decompressed)
    })
}
```

### Python (Atheris)

```python
import atheris
import sys
import zlib

with atheris.instrument_imports():
    import my_protocol

def TestOneInput(data):
    if len(data) > 1_000_000:
        return
    try:
        decompressed = zlib.decompress(data)
    except zlib.error:
        return
    # Oracle: must not crash on valid compressed payloads
    try:
        my_protocol.parse_message(decompressed)
    except my_protocol.ParseError:
        pass  # Expected for malformed (but decompressible) data

# Custom mutator: decompress -> mutate inner bytes -> recompress
def CustomMutator(data, max_size, seed):
    try:
        decompressed = zlib.decompress(data)
    except zlib.error:
        decompressed = b"seed_payload"
    mutated = atheris.Mutate(decompressed, len(decompressed))
    compressed = zlib.compress(mutated)
    return compressed[:max_size]

atheris.Setup(sys.argv, TestOneInput, custom_mutator=CustomMutator)
atheris.Fuzz()
```

### TypeScript (Jazzer.js)

```javascript
const zlib = require("zlib");
const { parseMessage } = require("./my_protocol");

module.exports.fuzz = function(data) {
    if (data.length > 1_000_000) return;

    // Interpret fuzz bytes as: [1-byte flags] [payload]
    // Flag bit 0: whether payload is compressed
    if (data.length < 2) return;
    const compressed = data[0] & 1;
    const payload = data.slice(1);

    let inner;
    if (compressed) {
        try {
            inner = zlib.inflateSync(payload);
        } catch (e) {
            return; // Invalid compressed data -- skip
        }
    } else {
        inner = payload;
    }

    // Oracle: must not throw unexpected errors
    try {
        parseMessage(inner);
    } catch (e) {
        if (e.name === "ParseError") return; // Expected
        throw e; // Unexpected = bug
    }
};

// Note: Jazzer.js does not natively support custom mutators as of v2.
// The flag-byte approach above lets the coverage-guided engine explore
// both compressed and uncompressed paths.
```

### C/C++ (libFuzzer)

```cpp
// custom_mutator_fuzz.cc
// compile: clang++ -fsanitize=fuzzer,address custom_mutator_fuzz.cc -lz -o fuzz
#include <cassert>
#include <cstdint>
#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <zlib.h>

#include "my_protocol.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 1000000) return 0;

    // Decompress
    uLongf decompressed_size = 10 * size + 256;
    std::vector<uint8_t> decompressed(decompressed_size);
    if (uncompress(decompressed.data(), &decompressed_size,
                   data, size) != Z_OK) {
        return 0; // Not valid zlib
    }

    // Oracle: must not crash or trigger sanitizer
    parse_message(decompressed.data(), decompressed_size);
    return 0;
}

// Custom mutator: decompress -> mutate inner -> recompress
extern "C" size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size,
                                           size_t max_size, unsigned int seed) {
    // Try to decompress
    uLongf dec_size = 10 * size + 256;
    std::vector<uint8_t> dec(dec_size);
    if (uncompress(dec.data(), &dec_size, data, size) != Z_OK) {
        // Fallback: use seed data
        const char *fallback = "hello";
        dec_size = strlen(fallback);
        memcpy(dec.data(), fallback, dec_size);
    }

    // Mutate the decompressed payload using libFuzzer's default mutator
    dec.resize(dec_size * 2 + 256);
    size_t mutated_size = LLVMFuzzerMutate(dec.data(), dec_size, dec.size());

    // Recompress
    uLongf comp_size = compressBound(mutated_size);
    std::vector<uint8_t> comp(comp_size);
    if (compress(comp.data(), &comp_size, dec.data(), mutated_size) != Z_OK) {
        return size; // compression failed, return unmutated
    }

    if (comp_size > max_size) return size;
    memcpy(data, comp.data(), comp_size);
    return comp_size;
}
```

### Java (Jazzer)

```java
import com.code_intelligence.jazzer.api.FuzzedDataProvider;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.util.zip.GZIPInputStream;

public class CustomMutatorFuzzer {
    // Jazzer supports custom mutators via the fuzzerCustomMutator method.
    // However, the simpler pattern is structured input via FuzzedDataProvider:
    // consume a "format" byte then route to compressed vs. raw paths.

    public static void fuzzerTestOneInput(FuzzedDataProvider data) {
        byte[] payload = data.consumeRemainingAsBytes();
        if (payload.length > 1_000_000) return;

        // Try to decompress as gzip
        byte[] inner;
        try {
            GZIPInputStream gis = new GZIPInputStream(
                new ByteArrayInputStream(payload));
            inner = gis.readAllBytes();
            gis.close();
        } catch (Exception e) {
            return; // Not valid gzip
        }

        // Oracle: must not throw unexpected exceptions
        try {
            MyProtocol.parseMessage(inner);
        } catch (MyProtocol.ParseException e) {
            // Expected for malformed-but-decompressible data
        }
        // Any other exception propagates as a finding
    }

    // Optional: true custom mutator for maximum exploration
    public static byte[] fuzzerCustomMutator(byte[] data, int maxSize, long seed) {
        byte[] inner;
        try {
            GZIPInputStream gis = new GZIPInputStream(
                new ByteArrayInputStream(data));
            inner = gis.readAllBytes();
            gis.close();
        } catch (Exception e) {
            inner = "seed".getBytes();
        }

        // Mutate inner bytes (simple: flip random byte)
        if (inner.length > 0) {
            int idx = (int)(seed % inner.length);
            inner[idx] ^= (byte)(seed >> 8);
        }

        // Recompress
        try {
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            java.util.zip.GZIPOutputStream gos =
                new java.util.zip.GZIPOutputStream(bos);
            gos.write(inner);
            gos.close();
            byte[] result = bos.toByteArray();
            return result.length <= maxSize ? result : data;
        } catch (Exception e) {
            return data;
        }
    }
}
```

---

## 7. Concurrency (Race Conditions)

Run fuzzed operation sequences on multiple threads against shared state. The oracle is "no data races, no deadlocks, no invariant violations after concurrent access." Pair with sanitizers (TSan, Go race detector) for maximum effectiveness.

### Rust (cargo-fuzz + ThreadSanitizer)

```rust
#![no_main]
use libfuzzer_sys::fuzz_target;
use arbitrary::Arbitrary;
use std::sync::Arc;
use std::thread;

#[derive(Debug, Arbitrary, Clone)]
enum Op {
    Insert { key: u8, val: u16 },
    Get { key: u8 },
    Remove { key: u8 },
    Len,
}

#[derive(Debug, Arbitrary)]
struct ConcurrentOps {
    thread1_ops: Vec<Op>,
    thread2_ops: Vec<Op>,
}

fn execute(map: &MyConcurrentMap, op: &Op) {
    match op {
        Op::Insert { key, val } => { map.insert(*key, *val); }
        Op::Get { key } => { let _ = map.get(key); }
        Op::Remove { key } => { map.remove(key); }
        Op::Len => { let _ = map.len(); }
    }
}

fuzz_target!(|input: ConcurrentOps| {
    if input.thread1_ops.len() > 50 || input.thread2_ops.len() > 50 { return; }

    let shared = Arc::new(MyConcurrentMap::new());
    let s1 = shared.clone();
    let s2 = shared.clone();

    let t1 = thread::spawn(move || {
        for op in &input.thread1_ops { execute(&s1, op); }
    });
    let t2 = thread::spawn(move || {
        for op in &input.thread2_ops { execute(&s2, op); }
    });

    t1.join().unwrap();
    t2.join().unwrap();

    // Oracle: must be in consistent state after concurrent access
    shared.check_invariants().expect("Concurrent invariant violation");
});
```

Run with ThreadSanitizer:
```bash
RUSTFLAGS="-Zsanitizer=thread" cargo +nightly fuzz run concurrent_target
```

### Go (native fuzzing + race detector)

```go
package mypackage

import (
    "sync"
    "testing"
)

func FuzzConcurrentMap(f *testing.F) {
    f.Add([]byte{0, 1, 2, 3, 0, 1, 2, 3})

    f.Fuzz(func(t *testing.T, data []byte) {
        if len(data) > 1000 { return }

        m := NewConcurrentMap() // system under test
        mid := len(data) / 2
        thread1Data := data[:mid]
        thread2Data := data[mid:]

        var wg sync.WaitGroup
        wg.Add(2)

        // Thread 1
        go func() {
            defer wg.Done()
            for i := 0; i < len(thread1Data)-1; i += 2 {
                op := thread1Data[i] % 3
                key := thread1Data[i+1]
                switch op {
                case 0: m.Put(key, key+1)
                case 1: m.Get(key)
                case 2: m.Delete(key)
                }
            }
        }()

        // Thread 2
        go func() {
            defer wg.Done()
            for i := 0; i < len(thread2Data)-1; i += 2 {
                op := thread2Data[i] % 3
                key := thread2Data[i+1]
                switch op {
                case 0: m.Put(key, key+1)
                case 1: m.Get(key)
                case 2: m.Delete(key)
                }
            }
        }()

        wg.Wait()

        // Oracle: structure must be internally consistent
        if err := m.CheckInvariants(); err != nil {
            t.Fatalf("Invariant violation after concurrent access: %v", err)
        }
    })
}
```

Run with race detector:
```bash
go test -fuzz=FuzzConcurrentMap -race -fuzztime=60s
```

### Python (Atheris + threading)

```python
import atheris
import sys
import threading

with atheris.instrument_imports():
    import my_concurrent_map

def TestOneInput(data):
    if len(data) > 1000:
        return

    fdp = atheris.FuzzedDataProvider(data)
    shared = my_concurrent_map.ConcurrentMap()
    errors = []

    def run_ops(ops_data):
        """Execute fuzzed operations against the shared map."""
        try:
            i = 0
            while i + 1 < len(ops_data):
                op = ops_data[i] % 3
                key = ops_data[i + 1]
                i += 2
                if op == 0:
                    shared.put(key, key + 1)
                elif op == 1:
                    shared.get(key)
                elif op == 2:
                    shared.delete(key)
        except Exception as e:
            errors.append(e)

    mid = fdp.remaining_bytes() // 2
    data1 = fdp.ConsumeBytes(mid)
    data2 = fdp.ConsumeRemainingAsBytes()

    t1 = threading.Thread(target=run_ops, args=(data1,))
    t2 = threading.Thread(target=run_ops, args=(data2,))
    t1.start()
    t2.start()
    t1.join(timeout=5)
    t2.join(timeout=5)

    # Oracle: no exceptions during concurrent access
    if errors:
        raise RuntimeError(f"Concurrent access error: {errors[0]}")

    # Oracle: internal invariants must hold
    shared.check_invariants()

atheris.Setup(sys.argv, TestOneInput)
atheris.Fuzz()
```

Note: Python's GIL limits true parallelism for CPU-bound code but does not prevent race conditions in I/O-bound or C-extension code. For C extensions, run under ThreadSanitizer.

### TypeScript (Jazzer.js + Worker threads)

```javascript
const { Worker, isMainThread, parentPort, workerData } = require("worker_threads");
const assert = require("assert");

if (!isMainThread) {
    // Worker: execute operations against the shared buffer
    const { sab, ops } = workerData;
    const view = new Int32Array(sab);
    for (const op of ops) {
        switch (op.type) {
            case "add":
                Atomics.add(view, op.index % view.length, op.value);
                break;
            case "load":
                Atomics.load(view, op.index % view.length);
                break;
            case "cas":
                Atomics.compareExchange(view, op.index % view.length,
                    op.expected, op.value);
                break;
        }
    }
    parentPort.postMessage("done");
} else {
    module.exports.fuzz = function(data) {
        if (data.length > 500) return;

        // Parse fuzz bytes into operations for two workers
        const ops1 = [], ops2 = [];
        for (let i = 0; i < data.length - 2; i += 3) {
            const op = {
                type: ["add", "load", "cas"][data[i] % 3],
                index: data[i+1],
                value: data[i+2],
                expected: 0
            };
            (i % 2 === 0 ? ops1 : ops2).push(op);
        }

        if (ops1.length === 0 && ops2.length === 0) return;

        // Shared memory between workers
        const sab = new SharedArrayBuffer(64);

        // Oracle: workers must complete without hanging or crashing
        const w1 = new Worker(__filename, { workerData: { sab, ops: ops1 } });
        const w2 = new Worker(__filename, { workerData: { sab, ops: ops2 } });

        let completed = 0;
        const done = () => { if (++completed === 2) { /* both finished */ } };
        w1.on("message", done);
        w2.on("message", done);
    };
}
```

Note: True shared-memory concurrency fuzzing in JS is limited. For most Node.js code, prefer race-condition testing via interleaved async operations using `setImmediate` or promise scheduling.

### C/C++ (libFuzzer + ThreadSanitizer)

```cpp
// concurrent_fuzz.cc
// compile: clang++ -fsanitize=fuzzer,thread concurrent_fuzz.cc -lpthread -o fuzz
#include <cassert>
#include <cstdint>
#include <cstddef>
#include <thread>
#include <vector>

#include "my_concurrent_map.h"

enum OpType : uint8_t { OP_PUT = 0, OP_GET = 1, OP_DELETE = 2 };

struct Op {
    OpType type;
    uint8_t key;
    uint8_t val;
};

static void run_ops(MyConcurrentMap &m, const std::vector<Op> &ops) {
    for (auto &op : ops) {
        switch (op.type) {
        case OP_PUT:    m.put(op.key, op.val); break;
        case OP_GET:    m.get(op.key);         break;
        case OP_DELETE: m.remove(op.key);       break;
        }
    }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (size > 1000) return 0;

    // Parse into two op lists
    std::vector<Op> ops1, ops2;
    for (size_t i = 0; i + 2 < size; i += 3) {
        Op op = { static_cast<OpType>(data[i] % 3), data[i+1], data[i+2] };
        (i % 2 == 0 ? ops1 : ops2).push_back(op);
    }

    MyConcurrentMap m;

    std::thread t1([&]() { run_ops(m, ops1); });
    std::thread t2([&]() { run_ops(m, ops2); });
    t1.join();
    t2.join();

    // Oracle: TSan detects data races; assert catches logic bugs
    assert(m.check_invariants() && "Invariant violation after concurrent ops");
    return 0;
}
```

Compile and run with ThreadSanitizer:
```bash
clang++ -fsanitize=fuzzer,thread -g concurrent_fuzz.cc my_concurrent_map.cc -lpthread -o fuzz
./fuzz -max_total_time=300
```

### Java (Jazzer + Thread Safety)

```java
import com.code_intelligence.jazzer.api.FuzzedDataProvider;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicReference;

public class ConcurrencyFuzzer {
    public static void fuzzerTestOneInput(FuzzedDataProvider data) {
        int numOps = data.consumeInt(1, 50);
        MyConcurrentMap<Integer, Integer> map = new MyConcurrentMap<>();

        // Parse operations for two threads
        int[][] ops1 = new int[numOps][3]; // [op, key, val]
        int[][] ops2 = new int[numOps][3];
        for (int i = 0; i < numOps; i++) {
            ops1[i] = new int[]{data.consumeInt(0, 2), data.consumeInt(0, 255), data.consumeInt()};
            ops2[i] = new int[]{data.consumeInt(0, 2), data.consumeInt(0, 255), data.consumeInt()};
        }

        CountDownLatch start = new CountDownLatch(1);
        AtomicReference<Throwable> failure = new AtomicReference<>();

        Thread t1 = new Thread(makeRunner(map, ops1, start, failure));
        Thread t2 = new Thread(makeRunner(map, ops2, start, failure));
        t1.start();
        t2.start();
        start.countDown(); // Release both threads simultaneously

        try {
            t1.join(5000);
            t2.join(5000);
        } catch (InterruptedException e) {
            throw new AssertionError("Deadlock: threads did not complete in 5s");
        }

        // Oracle: no thread threw an exception
        if (failure.get() != null) {
            throw new AssertionError("Concurrent access failure", failure.get());
        }

        // Oracle: invariants hold after concurrent access
        map.checkInvariants();
    }

    // Helper to create a Runnable from ops array
    private static Runnable makeRunner(
            MyConcurrentMap<Integer, Integer> map,
            int[][] ops, CountDownLatch start,
            AtomicReference<Throwable> failure) {
        return () -> {
            try {
                start.await();
                for (int[] op : ops) {
                    switch (op[0]) {
                        case 0: map.put(op[1], op[2]); break;
                        case 1: map.get(op[1]);         break;
                        case 2: map.remove(op[1]);       break;
                    }
                }
            } catch (Throwable t) {
                failure.compareAndSet(null, t);
            }
        };
    }
}
```

Run with Java's built-in thread-safety checks:
```bash
jazzer --target_class=ConcurrencyFuzzer \
       --jvm_args="-ea" \
       -max_total_time=300
```

For deeper race detection, use [jcstress](https://github.com/openjdk/jcstress) for unit-level concurrency tests and Jazzer for fuzz-driven exploration.
