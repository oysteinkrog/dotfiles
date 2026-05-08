# Custom Mutator Guide

> When the fuzzer's input must be structurally valid to reach interesting code, naive byte mutation wastes every cycle on rejected inputs. Custom mutators decode the format, mutate the payload, and re-encode it so every generated input penetrates past the parsing layer.

## When You Need Custom Mutators

Standard coverage-guided fuzzers flip bits, insert bytes, and splice inputs. This works for raw parsers. It fails catastrophically for:

| Format | Why Naive Mutation Fails |
|--------|------------------------|
| zlib / gzip / brotli / zstd | Corrupted compressed stream is rejected in <10 instructions |
| Protobuf / FlatBuffers / Cap'n Proto | Invalid wire format discarded before business logic |
| ASN.1 / DER | Tag-length-value structure must be self-consistent |
| MessagePack / CBOR | Type prefixes and length fields must agree |
| Encrypted payloads | Random bytes never decrypt to valid plaintext |
| Checksummed formats (PNG, ZIP, TCP) | CRC/hash mismatch triggers immediate rejection |

**The universal pattern:** decode -> mutate decoded payload -> re-encode.

---

## libFuzzer Custom Mutator API

### Rust (`fuzz_mutator!`)

```rust
#![no_main]
use libfuzzer_sys::{fuzz_target, fuzz_mutator};
use flate2::read::ZlibDecoder;
use flate2::write::ZlibEncoder;
use flate2::Compression;
use std::io::{Read, Write};

fuzz_target!(|data: &[u8]| {
    if let Ok(decompressed) = zlib_decompress(data) {
        let _ = my_crate::process_message(&decompressed);
    }
});

fuzz_mutator!(|data: &mut [u8], size: usize, max_size: usize, _seed: u32| {
    // 1. Decompress
    let decompressed = match zlib_decompress(&data[..size]) {
        Ok(d) => d,
        Err(_) => {
            // Invalid input: fall back to raw byte mutation
            return libfuzzer_sys::fuzzer_mutate(data, size, max_size);
        }
    };

    // 2. Mutate the decompressed payload with libFuzzer's built-in mutator
    let mut buf = decompressed;
    buf.resize(buf.len() + 1024, 0); // Extra room for growth
    let payload_len = buf.len() - 1024;
    let mutated_len = libfuzzer_sys::fuzzer_mutate(&mut buf, payload_len, buf.len());
    buf.truncate(mutated_len);

    // 3. Recompress
    let mut encoder = ZlibEncoder::new(Vec::new(), Compression::fast());
    if encoder.write_all(&buf).is_ok() {
        if let Ok(compressed) = encoder.finish() {
            let new_size = compressed.len().min(max_size);
            data[..new_size].copy_from_slice(&compressed[..new_size]);
            return new_size;
        }
    }

    // Fallback
    libfuzzer_sys::fuzzer_mutate(data, size, max_size)
});

fn zlib_decompress(data: &[u8]) -> Result<Vec<u8>, std::io::Error> {
    let mut decoder = ZlibDecoder::new(data);
    let mut buf = Vec::new();
    decoder.read_to_end(&mut buf)?;
    Ok(buf)
}
```

### C/C++ (`LLVMFuzzerCustomMutator`)

```c
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

// Required: declared by libFuzzer, call for default mutation
extern size_t LLVMFuzzerMutate(uint8_t *data, size_t size, size_t max_size);

size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size,
                                size_t max_size, unsigned int seed) {
    // Decompress
    uint8_t decompressed[1 << 20]; // 1MB limit
    uLongf decomp_len = sizeof(decompressed);
    if (uncompress(decompressed, &decomp_len, data, size) != Z_OK) {
        return LLVMFuzzerMutate(data, size, max_size);
    }

    // Mutate the decompressed data
    size_t mutated_len = LLVMFuzzerMutate(decompressed, decomp_len, sizeof(decompressed));

    // Recompress
    uLongf comp_len = compressBound(mutated_len);
    uint8_t *compressed = malloc(comp_len);
    if (compress(compressed, &comp_len, decompressed, mutated_len) == Z_OK
        && comp_len <= max_size) {
        memcpy(data, compressed, comp_len);
        free(compressed);
        return comp_len;
    }

    free(compressed);
    return LLVMFuzzerMutate(data, size, max_size);
}

// Optional: cross two compressed inputs
size_t LLVMFuzzerCustomCrossOver(const uint8_t *data1, size_t size1,
                                  const uint8_t *data2, size_t size2,
                                  uint8_t *out, size_t max_out_size,
                                  unsigned int seed) {
    uint8_t d1[1 << 20], d2[1 << 20];
    uLongf len1 = sizeof(d1), len2 = sizeof(d2);
    if (uncompress(d1, &len1, data1, size1) != Z_OK) return 0;
    if (uncompress(d2, &len2, data2, size2) != Z_OK) return 0;

    // Crossover: take first half of d1, second half of d2
    size_t split1 = len1 / 2, split2 = len2 / 2;
    size_t raw_len = split1 + (len2 - split2);
    uint8_t *raw = malloc(raw_len);
    memcpy(raw, d1, split1);
    memcpy(raw + split1, d2 + split2, len2 - split2);

    uLongf comp_len = compressBound(raw_len);
    uint8_t *comp = malloc(comp_len);
    int ok = (compress(comp, &comp_len, raw, raw_len) == Z_OK && comp_len <= max_out_size);
    if (ok) memcpy(out, comp, comp_len);
    free(raw);
    free(comp);
    return ok ? comp_len : 0;
}
```

---

## AFL++ Custom Mutator API

Build as a shared library and point AFL++ at it with `AFL_CUSTOM_MUTATOR_LIBRARY`.

```c
// afl_custom_zlib_mutator.c
// Build: gcc -shared -fPIC -O2 -o zlib_mutator.so afl_custom_zlib_mutator.c -lz
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

typedef struct {
    uint8_t *buf;
    size_t   buf_size;
} mutator_state_t;

void *afl_custom_init(void *afl, unsigned int seed) {
    mutator_state_t *state = calloc(1, sizeof(mutator_state_t));
    state->buf_size = 1 << 20;
    state->buf = malloc(state->buf_size);
    return state;
}

size_t afl_custom_fuzz(void *data, uint8_t *buf, size_t buf_size,
                       uint8_t **out_buf, uint8_t *add_buf,
                       size_t add_buf_size, size_t max_size) {
    mutator_state_t *state = (mutator_state_t *)data;

    // Decompress input
    uLongf decomp_len = state->buf_size;
    if (uncompress(state->buf, &decomp_len, buf, buf_size) != Z_OK) {
        // Pass through if not valid zlib
        *out_buf = buf;
        return buf_size;
    }

    // Flip a random byte in the decompressed payload
    if (decomp_len > 0) {
        size_t pos = rand() % decomp_len;
        state->buf[pos] ^= (1 << (rand() % 8));
    }

    // Recompress
    uLongf comp_len = compressBound(decomp_len);
    uint8_t *out = malloc(comp_len);
    if (compress(out, &comp_len, state->buf, decomp_len) == Z_OK
        && comp_len <= max_size) {
        *out_buf = out;
        return comp_len;
    }
    free(out);
    *out_buf = buf;
    return buf_size;
}

// Called after every mutation to fix up the output (e.g., fix checksums)
size_t afl_custom_post_process(void *data, uint8_t *buf, size_t buf_size,
                                uint8_t **out_buf) {
    *out_buf = buf;
    return buf_size;  // No post-processing needed for zlib
}

// Optional: participate in havoc stage with extra mutations
size_t afl_custom_havoc_mutation(void *data, uint8_t *buf, size_t buf_size,
                                  uint8_t **out_buf, size_t max_size) {
    // Return 0 to skip; nonzero = replacement input length
    return 0;
}

// Optional: filter which queue entries to fuzz
uint8_t afl_custom_queue_get(void *data, const uint8_t *filename) {
    return 1;  // Fuzz all entries
}

void afl_custom_deinit(void *data) {
    mutator_state_t *state = (mutator_state_t *)data;
    free(state->buf);
    free(state);
}
```

```bash
# Usage
gcc -shared -fPIC -O2 -o zlib_mutator.so afl_custom_zlib_mutator.c -lz
AFL_CUSTOM_MUTATOR_LIBRARY=./zlib_mutator.so afl-fuzz -i corpus/ -o findings/ -- ./target @@
```

---

## libprotobuf-mutator

Structure-aware protobuf fuzzing in C++. Generates valid protobuf messages then mutates fields while maintaining wire-format validity.

```cmake
# CMakeLists.txt
find_package(Protobuf REQUIRED)
include(FetchContent)
FetchContent_Declare(
    libprotobuf-mutator
    GIT_REPOSITORY https://github.com/google/libprotobuf-mutator
    GIT_TAG        master
)
FetchContent_MakeAvailable(libprotobuf-mutator)

protobuf_generate_cpp(PROTO_SRCS PROTO_HDRS message.proto)

add_executable(fuzz_proto fuzz_proto.cc ${PROTO_SRCS})
target_link_libraries(fuzz_proto
    protobuf-mutator-libfuzzer protobuf-mutator ${Protobuf_LIBRARIES})
```

```protobuf
// message.proto
syntax = "proto3";
message Request {
    string method = 1;
    string path = 2;
    map<string, string> headers = 3;
    bytes body = 4;
}
```

```cpp
// fuzz_proto.cc
#include "src/libfuzzer/libfuzzer_macro.h"
#include "message.pb.h"

using protobuf_mutator::libfuzzer::PostProcessorRegistration;

// Constrain generated messages to be semi-realistic
static PostProcessorRegistration<Request> reg = {
    [](Request *msg, unsigned int seed) {
        if (msg->method().empty()) msg->set_method("GET");
        if (msg->path().empty()) msg->set_path("/");
    }};

DEFINE_PROTO_FUZZER(const Request &input) {
    ProcessRequest(input.method(), input.path(),
                   input.headers(), input.body());
}
```

---

## Compressed Format Patterns

### zlib/gzip (Python)

```python
import zlib, atheris, sys

def TestOneInput(data):
    try:
        payload = zlib.decompress(data)
    except zlib.error:
        return
    my_library.process(payload)

def CustomMutator(data, max_size, seed):
    try:
        payload = zlib.decompress(data)
    except zlib.error:
        payload = b"\x00" * 16  # Start with something valid
    payload = atheris.Mutate(payload, len(payload) * 2)
    compressed = zlib.compress(payload)
    return compressed[:max_size]

atheris.Setup(sys.argv, TestOneInput, custom_mutator=CustomMutator)
atheris.Fuzz()
```

### zstd with Dictionary (Rust)

```rust
fuzz_mutator!(|data: &mut [u8], size: usize, max_size: usize, _seed: u32| {
    let dict = include_bytes!("../dicts/my_format.zstd_dict");
    let decompressor = zstd::bulk::Decompressor::with_dictionary(dict).unwrap();
    let compressor = zstd::bulk::Compressor::with_dictionary(3, dict).unwrap();

    let decompressed = match decompressor.decompress(&data[..size], 1 << 20) {
        Ok(d) => d,
        Err(_) => return libfuzzer_sys::fuzzer_mutate(data, size, max_size),
    };

    let mut buf = decompressed;
    buf.resize(buf.len() + 512, 0);
    let orig = buf.len() - 512;
    let new_len = libfuzzer_sys::fuzzer_mutate(&mut buf, orig, buf.len());
    buf.truncate(new_len);

    match compressor.compress(&buf) {
        Ok(compressed) if compressed.len() <= max_size => {
            data[..compressed.len()].copy_from_slice(&compressed);
            compressed.len()
        }
        _ => libfuzzer_sys::fuzzer_mutate(data, size, max_size),
    }
});
```

---

## Encrypted Format Patterns

Fuzz the **pre-encryption** logic unless you are specifically testing decryption.

```rust
// Scenario: testing your own encrypt-then-process pipeline.
// The key is known because it is YOUR test harness.
fuzz_mutator!(|data: &mut [u8], size: usize, max_size: usize, _seed: u32| {
    let key = b"test_key_for_fuzzing_only_16b!";
    let nonce = [0u8; 12]; // Fixed nonce for reproducibility

    // Decrypt the corpus input
    let plaintext = match aes_gcm_decrypt(key, &nonce, &data[..size]) {
        Ok(p) => p,
        Err(_) => return libfuzzer_sys::fuzzer_mutate(data, size, max_size),
    };

    // Mutate the plaintext
    let mut buf = plaintext;
    buf.resize(buf.len() + 256, 0);
    let orig = buf.len() - 256;
    let new_len = libfuzzer_sys::fuzzer_mutate(&mut buf, orig, buf.len());
    buf.truncate(new_len);

    // Re-encrypt
    match aes_gcm_encrypt(key, &nonce, &buf) {
        Ok(ct) if ct.len() <= max_size => {
            data[..ct.len()].copy_from_slice(&ct);
            ct.len()
        }
        _ => libfuzzer_sys::fuzzer_mutate(data, size, max_size),
    }
});
```

**When to fuzz pre-encryption vs. post-encryption:**

| Goal | Strategy |
|------|----------|
| Test business logic after decryption | Custom mutator: decrypt -> mutate -> re-encrypt |
| Test the decryption code itself | Fuzz raw bytes directly (no custom mutator needed) |
| Test authenticated encryption rejection | Fuzz raw bytes, verify all invalid inputs are rejected |

---

## Checksummed Format Patterns

### Generic CRC32 (strip, mutate, recompute)

```rust
fuzz_mutator!(|data: &mut [u8], size: usize, max_size: usize, _seed: u32| {
    if size < 4 { return libfuzzer_sys::fuzzer_mutate(data, size, max_size); }

    // Strip trailing CRC32
    let payload_len = size - 4;
    let mut payload = data[..payload_len].to_vec();
    payload.resize(payload.len() + 256, 0);
    let orig = payload.len() - 256;
    let new_len = libfuzzer_sys::fuzzer_mutate(&mut payload, orig, payload.len());
    payload.truncate(new_len);

    // Recompute CRC32
    let crc = crc32fast::hash(&payload);
    let total = payload.len() + 4;
    if total > max_size { return libfuzzer_sys::fuzzer_mutate(data, size, max_size); }
    data[..payload.len()].copy_from_slice(&payload);
    data[payload.len()..total].copy_from_slice(&crc.to_le_bytes());
    total
});
```

### PNG Chunk Mutator (C++)

PNG stores data in chunks: `[4-byte length][4-byte type][data][4-byte CRC]`. The CRC covers type+data.

```cpp
size_t LLVMFuzzerCustomMutator(uint8_t *data, size_t size,
                                size_t max_size, unsigned int seed) {
    // Verify PNG signature
    static const uint8_t PNG_SIG[] = {0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A};
    if (size < 8 || memcmp(data, PNG_SIG, 8) != 0) {
        return LLVMFuzzerMutate(data, size, max_size);
    }

    // Walk chunks, pick a random one to mutate
    size_t offset = 8;
    std::vector<size_t> chunk_offsets;
    while (offset + 12 <= size) {
        uint32_t chunk_len = ntohl(*(uint32_t *)(data + offset));
        chunk_offsets.push_back(offset);
        offset += 12 + chunk_len;
    }
    if (chunk_offsets.empty()) return LLVMFuzzerMutate(data, size, max_size);

    // Mutate a random chunk's data
    size_t chosen = chunk_offsets[seed % chunk_offsets.size()];
    uint32_t chunk_len = ntohl(*(uint32_t *)(data + chosen));
    uint8_t *chunk_data = data + chosen + 8;
    LLVMFuzzerMutate(chunk_data, chunk_len, chunk_len);

    // Fix the CRC (covers type + data)
    uint8_t *type_start = data + chosen + 4;
    uint32_t new_crc = crc32(0, type_start, 4 + chunk_len);
    *(uint32_t *)(data + chosen + 8 + chunk_len) = htonl(new_crc);

    return size;
}
```

---

## FlatBuffers / Cap'n Proto

Zero-copy formats encode offset tables and vtables that break instantly under byte mutation. Generate valid messages, then corrupt individual fields.

### Rust (FlatBuffers)

```rust
#![no_main]
use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;
use flatbuffers::FlatBufferBuilder;

#[derive(Debug, Arbitrary)]
struct FuzzedMessage {
    id: u32,
    name: String,
    payload: Vec<u8>,
    flags: u16,
    corrupt_field: Option<u8>, // Which field to corrupt
}

fuzz_target!(|input: FuzzedMessage| {
    if input.name.len() > 1024 || input.payload.len() > 65536 { return; }

    let mut builder = FlatBufferBuilder::new();
    let name = builder.create_string(&input.name);
    let payload = builder.create_vector(&input.payload);

    let msg = MyMessage::create(&mut builder, &MyMessageArgs {
        id: input.id,
        name: Some(name),
        payload: Some(payload),
        flags: input.flags,
    });
    builder.finish(msg, None);
    let buf = builder.finished_data();

    // Optionally corrupt a single byte (tests verifier robustness)
    let mut data = buf.to_vec();
    if let Some(pos) = input.corrupt_field {
        let idx = pos as usize % data.len();
        data[idx] ^= 0xFF;
    }

    // This exercises the verifier and access paths
    let _ = flatbuffers::root::<MyMessage>(&data);
});
```

### C++ (Cap'n Proto)

```cpp
DEFINE_PROTO_FUZZER(const CapnpSeed &seed) {
    capnp::MallocMessageBuilder builder;
    auto msg = builder.initRoot<MySchema>();
    msg.setId(seed.id());
    msg.setName(seed.name());
    msg.setPayload(capnp::Data::Reader(
        (const capnp::byte *)seed.payload().data(), seed.payload().size()));

    auto serialized = capnp::messageToFlatArray(builder);
    auto bytes = serialized.asBytes();

    // Feed to the target parser
    capnp::FlatArrayMessageReader reader(
        kj::ArrayPtr<const capnp::word>(
            reinterpret_cast<const capnp::word *>(bytes.begin()),
            bytes.size() / sizeof(capnp::word)));
    processMessage(reader);
}
```

---

## ASN.1 / DER

X.509 certificates, SNMP packets, and LDAP messages use ASN.1/DER. The tag-length-value encoding makes random mutation useless.

**Strategy:** Use `asn1tools` (Python) or `der-parser` (Rust) to decode, mutate fields, re-encode.

```python
# Python: mutate X.509 certificate fields
import asn1tools, atheris, sys

SCHEMA = asn1tools.compile_files("rfc5280.asn", codec="der")

def CustomMutator(data, max_size, seed):
    try:
        cert = SCHEMA.decode("Certificate", data)
    except Exception:
        return atheris.Mutate(data, max_size)

    # Mutate specific fields
    tbs = cert["tbsCertificate"]
    serial = tbs.get("serialNumber", 1)
    tbs["serialNumber"] = serial ^ (1 << (seed % 64))

    # Corrupt issuer name
    if seed % 3 == 0 and tbs.get("issuer"):
        name_bytes = tbs["issuer"]["rdnSequence"][0][0]["value"]
        tbs["issuer"]["rdnSequence"][0][0]["value"] = atheris.Mutate(
            name_bytes, len(name_bytes) * 2)

    try:
        return SCHEMA.encode("Certificate", cert)[:max_size]
    except Exception:
        return atheris.Mutate(data, max_size)
```

**Rust:** Use the `der` crate to parse and re-serialize, or `x509-cert` for certificate-specific fuzzing.

---

## MessagePack / CBOR

Simpler than protobuf: no schema file needed. Deserialize to a dynamic value, mutate, reserialize.

```rust
#![no_main]
use libfuzzer_sys::{fuzz_target, fuzz_mutator};
use rmpv::Value;

fuzz_target!(|data: &[u8]| {
    if let Ok(val) = rmpv::decode::read_value(&mut &data[..]) {
        let _ = my_crate::process_msgpack(val);
    }
});

fuzz_mutator!(|data: &mut [u8], size: usize, max_size: usize, seed: u32| {
    let val = match rmpv::decode::read_value(&mut &data[..size]) {
        Ok(v) => v,
        Err(_) => return libfuzzer_sys::fuzzer_mutate(data, size, max_size),
    };

    // Mutate the value tree
    let mutated = mutate_value(val, seed);
    let mut buf = Vec::new();
    if rmpv::encode::write_value(&mut buf, &mutated).is_ok() && buf.len() <= max_size {
        data[..buf.len()].copy_from_slice(&buf);
        return buf.len();
    }
    libfuzzer_sys::fuzzer_mutate(data, size, max_size)
});

fn mutate_value(val: Value, seed: u32) -> Value {
    match val {
        Value::Integer(n) => Value::Integer(
            (n.as_i64().unwrap_or(0) ^ (seed as i64)).into()),
        Value::String(s) => {
            let mut bytes = s.into_bytes().unwrap_or_default();
            if !bytes.is_empty() {
                bytes[seed as usize % bytes.len()] ^= 0xFF;
            }
            Value::String(bytes.into())
        }
        Value::Array(items) => Value::Array(
            items.into_iter()
                .map(|v| mutate_value(v, seed.wrapping_add(1)))
                .collect()
        ),
        Value::Map(entries) => Value::Map(
            entries.into_iter()
                .map(|(k, v)| (k, mutate_value(v, seed)))
                .collect()
        ),
        other => other,
    }
}
```

---

## Grammar-Based Custom Mutators

For text formats (SQL, JavaScript, HTML, CSS), generate syntactically valid inputs from a grammar.

### Rust: Arbitrary Trait for SQL

```rust
#[derive(Debug, Arbitrary)]
enum SqlStatement {
    Select(SelectQuery),
    Insert(InsertQuery),
    Delete(DeleteQuery),
}

#[derive(Debug, Arbitrary)]
struct SelectQuery {
    columns: Vec<Column>,
    table: TableName,
    where_clause: Option<WhereClause>,
    limit: Option<u16>,
}

#[derive(Debug, Arbitrary)]
enum Column { Star, Named(ColumnName) }

#[derive(Debug, Arbitrary)]
struct ColumnName(#[arbitrary(with = |u: &mut arbitrary::Unstructured| {
    Ok(["id", "name", "email", "created_at"]
        [u.int_in_range(0..=3)?].to_string())
})] String);

#[derive(Debug, Arbitrary)]
struct TableName(#[arbitrary(with = |u: &mut arbitrary::Unstructured| {
    Ok(["users", "orders", "products"]
        [u.int_in_range(0..=2)?].to_string())
})] String);

impl std::fmt::Display for SqlStatement {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            SqlStatement::Select(q) => {
                write!(f, "SELECT ")?;
                for (i, col) in q.columns.iter().enumerate() {
                    if i > 0 { write!(f, ", ")?; }
                    match col {
                        Column::Star => write!(f, "*")?,
                        Column::Named(n) => write!(f, "{}", n.0)?,
                    }
                }
                write!(f, " FROM {}", q.table.0)?;
                if let Some(limit) = q.limit {
                    write!(f, " LIMIT {limit}")?;
                }
                Ok(())
            }
            _ => write!(f, "SELECT 1"),
        }
    }
}

fuzz_target!(|stmt: SqlStatement| {
    let sql = stmt.to_string();
    let _ = my_db::parse_and_execute(&sql);
});
```

---

## Combining Custom Mutators with Standard Mutation

Never rely solely on custom mutation. Always fall back to raw byte mutation so the fuzzer can still discover bugs in the decoding layer itself.

### The Fallback Pattern (Rust)

```rust
fuzz_mutator!(|data: &mut [u8], size: usize, max_size: usize, seed: u32| {
    // 70% of the time: try structure-aware mutation
    if seed % 10 < 7 {
        if let Some(new_size) = try_structured_mutation(data, size, max_size, seed) {
            return new_size;
        }
    }
    // 30% or on failure: raw byte mutation (tests the parser itself)
    libfuzzer_sys::fuzzer_mutate(data, size, max_size)
});
```

### AFL++ Havoc Integration

In AFL++, `afl_custom_havoc_mutation` is called during the havoc stage alongside AFL's built-in mutations. Return 0 to skip your custom mutation for that round.

```c
size_t afl_custom_havoc_mutation(void *data, uint8_t *buf, size_t buf_size,
                                  uint8_t **out_buf, size_t max_size) {
    mutator_state_t *state = (mutator_state_t *)data;

    // Only fire 30% of havoc rounds
    if (rand() % 10 >= 3) return 0;

    // Structured mutation here
    uLongf decomp_len = state->buf_size;
    if (uncompress(state->buf, &decomp_len, buf, buf_size) != Z_OK) return 0;

    if (decomp_len > 0)
        state->buf[rand() % decomp_len] ^= (1 << (rand() % 8));

    uLongf comp_len = compressBound(decomp_len);
    uint8_t *out = malloc(comp_len);
    if (compress(out, &comp_len, state->buf, decomp_len) == Z_OK
        && comp_len <= max_size) {
        *out_buf = out;
        return comp_len;
    }
    free(out);
    return 0;  // Skip this round
}
```

**Key principle:** The custom mutator gets past the format gate. The standard mutator finds bugs in the format gate. You need both.

---

## See Also

- [AFLPP.md](AFLPP.md) — AFL++ custom mutator API (Section 7) for building shared library mutators
- [DICTIONARIES.md](DICTIONARIES.md) — Dictionaries are simpler than custom mutators; try them first
- [HARNESS-CATALOG.md](HARNESS-CATALOG.md) — Archetype 6 (Custom Mutator) templates for all languages
