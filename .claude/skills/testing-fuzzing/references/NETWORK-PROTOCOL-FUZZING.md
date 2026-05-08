# Network Protocol & Web API Fuzzing

> Network fuzzing is different from library fuzzing: you fuzz message sequences, not single inputs. Two approaches: desocket the parser (preferred) or fuzz over the wire.

## Contents

1. [Desocketing](#desocketing)
2. [boofuzz](#boofuzz)
3. [gRPC/Protobuf Fuzzing](#grpcprotobuf-fuzzing)
4. [WebSocket Fuzzing](#websocket-fuzzing)
5. [HTTP Fuzzing](#http-fuzzing)
6. [REST API Fuzzing](#rest-api-fuzzing)
7. [GraphQL Fuzzing](#graphql-fuzzing)
8. [TLS Fuzzing](#tls-fuzzing)
9. [DNS/SMTP/MQTT](#dnssmtpmqtt)
10. [Stateful Protocol Fuzzing](#stateful-protocol-fuzzing)
11. [CI Integration](#ci-integration-for-network-fuzzing)

---

## Desocketing

The preferred approach: extract the protocol parser from the network layer and fuzz it directly. Network I/O is slow and non-deterministic --- stripping it out gives you 10-100x speedup and full reproducibility.

### preeny (LD_PRELOAD redirect)

Redirect socket I/O to stdin/stdout so the fuzzer feeds bytes directly:

```bash
# Build with preeny's desock module
LD_PRELOAD=/path/to/preeny/x86_64-linux-gnu/desock.so \
  AFL_PRELOAD=/path/to/preeny/x86_64-linux-gnu/desock.so \
  afl-fuzz -i corpus/ -o findings/ -- ./my_tcp_server
```

### Extract the parser (Rust)

```rust
// src/protocol.rs -- parser decoupled from tokio::net
pub fn parse_message(input: &[u8]) -> Result<Message, ParseError> {
    let len = u32::from_be_bytes(input.get(..4).ok_or(ParseError::Short)?.try_into().unwrap());
    let kind = input.get(4).ok_or(ParseError::Short)?;
    let body = input.get(5..5 + len as usize).ok_or(ParseError::Short)?;
    Ok(Message { kind: *kind, body: body.to_vec() })
}

// fuzz/fuzz_targets/parse_message.rs
#![no_main]
use libfuzzer_sys::fuzz_target;
fuzz_target!(|data: &[u8]| {
    let _ = myserver::protocol::parse_message(data);
});
```

### Extract the parser (Go)

```go
// protocol/parse.go -- no net.Conn dependency
func ParseMessage(r io.Reader) (*Message, error) {
    var header [5]byte
    if _, err := io.ReadFull(r, header[:]); err != nil {
        return nil, err
    }
    length := binary.BigEndian.Uint32(header[:4])
    body := make([]byte, length)
    if _, err := io.ReadFull(r, body); err != nil {
        return nil, err
    }
    return &Message{Kind: header[4], Body: body}, nil
}

// fuzz_test.go
func FuzzParseMessage(f *testing.F) {
    f.Add([]byte("\x00\x00\x00\x05\x01hello"))
    f.Fuzz(func(t *testing.T, data []byte) {
        ParseMessage(bytes.NewReader(data))
    })
}
```

### UDP and WebSocket patterns

For UDP, the parser typically operates on single datagrams --- fuzz `parse_datagram(data: &[u8])` directly.

For WebSocket handlers, extract the message handler from the frame layer:

```rust
// Fuzz the application message handler, not the WS frame parser
fuzz_target!(|data: &[u8]| {
    let _ = handle_ws_message(data);  // your business logic
});
```

For gRPC, deserialize the protobuf directly (see next section).

---

## boofuzz

The successor to Sulley. Python-based network protocol fuzzer for over-the-wire testing when desocketing is impractical.

```bash
pip install boofuzz
```

### Define a protocol grammar

```python
from boofuzz import *

def main():
    session = Session(
        target=Target(
            connection=TCPSocketConnection("127.0.0.1", 9000),
        ),
        crash_threshold_element=5,
    )

    s_initialize("login")
    s_string("USER", fuzzable=False)
    s_delim(" ", fuzzable=False)
    s_string("admin", name="username")
    s_static("\r\n")

    s_initialize("command")
    s_group("verb", values=["GET", "SET", "DEL"])
    s_delim(" ", fuzzable=False)
    s_string("key", name="key", max_len=1024)
    s_delim(" ", fuzzable=False)
    s_string("value", name="value", max_len=4096)
    s_static("\r\n")

    session.connect(s_get("login"))
    session.connect(s_get("login"), s_get("command"))

    session.fuzz()

if __name__ == "__main__":
    main()
```

### Monitor for crashes

```python
from boofuzz import ProcessMonitor

# Attach a process monitor to detect crashes
target = Target(
    connection=TCPSocketConnection("127.0.0.1", 9000),
    monitors=[ProcessMonitor("127.0.0.1", 26002)],
)
# Start the monitor on the target host:
# process_monitor_unix.py -c /path/to/crash_bin -p my_server
```

---

## gRPC/Protobuf Fuzzing

Fuzz both the wire format (malformed protobuf) AND the business logic (valid protobuf with adversarial values).

### Rust: libprotobuf-mutator + Arbitrary

```rust
// Cargo.toml: arbitrary = { version = "1", features = ["derive"] }
// plus your generated protobuf types

use arbitrary::{Arbitrary, Unstructured};

#[derive(Arbitrary, Debug)]
struct FuzzRequest {
    user_id: u64,
    query: String,
    page_size: i32,
    filters: Vec<String>,
}

fuzz_target!(|data: &[u8]| {
    if let Ok(req) = FuzzRequest::arbitrary(&mut Unstructured::new(data)) {
        // Convert to protobuf and call the handler
        let proto_req = SearchRequest {
            user_id: req.user_id,
            query: req.query,
            page_size: req.page_size,
            filters: req.filters,
        };
        let _ = search_service::handle_search(proto_req);
    }
});
```

### C++: libprotobuf-mutator

```cpp
// libprotobuf-mutator integrates with libFuzzer directly
#include "src/libfuzzer/libfuzzer_macro.h"
#include "my_service.pb.h"

DEFINE_PROTO_FUZZER(const myservice::Request& req) {
    auto ctx = make_test_context();
    handle_request(ctx, req);  // your gRPC handler logic
}
```

### Python: hypothesis + grpcio

```python
from hypothesis import given, strategies as st
import grpc
from my_service_pb2 import SearchRequest
from my_service_pb2_grpc import SearchServiceStub

@given(
    query=st.text(min_size=0, max_size=10000),
    page_size=st.integers(min_value=-1000, max_value=1000000),
)
def test_fuzz_search(query, page_size):
    channel = grpc.insecure_channel("localhost:50051")
    stub = SearchServiceStub(channel)
    req = SearchRequest(query=query, page_size=page_size)
    try:
        stub.Search(req, timeout=5)
    except grpc.RpcError:
        pass  # expected for invalid inputs
```

---

## WebSocket Fuzzing

### Frame-level: corrupt frames

Fuzz raw WebSocket frames to test frame parser robustness:

```python
import struct, random, socket

def fuzz_ws_frame(sock):
    """Generate a malformed WebSocket frame."""
    opcode = random.choice([0x0, 0x1, 0x2, 0x8, 0x9, 0xA, 0xF])  # includes invalid
    payload = bytes(random.getrandbits(8) for _ in range(random.randint(0, 65536)))
    fin = random.choice([0x00, 0x80])
    mask_bit = random.choice([0x00, 0x80])

    frame = bytes([fin | opcode])
    length = len(payload)
    if length < 126:
        frame += bytes([mask_bit | length])
    elif length < 65536:
        frame += bytes([mask_bit | 126]) + struct.pack(">H", length)
    else:
        frame += bytes([mask_bit | 127]) + struct.pack(">Q", length)

    if mask_bit:
        mask_key = bytes(random.getrandbits(8) for _ in range(4))
        frame += mask_key
        payload = bytes(b ^ mask_key[i % 4] for i, b in enumerate(payload))

    frame += payload
    sock.send(frame)
```

### Application-level: valid frames, fuzzed payloads

```typescript
// TypeScript: fuzz WebSocket message handler with fast-check
import fc from "fast-check";
import { handleMessage } from "../src/ws-handler";

describe("WebSocket handler fuzzing", () => {
  it("never throws on arbitrary JSON payloads", () => {
    fc.assert(
      fc.property(fc.jsonValue(), (payload) => {
        const result = handleMessage(JSON.stringify(payload));
        // Should return a valid response or error, never throw
        expect(result).toBeDefined();
      }),
      { numRuns: 10000 },
    );
  });

  it("handles binary payloads without crashing", () => {
    fc.assert(
      fc.property(fc.uint8Array({ minLength: 0, maxLength: 65536 }), (data) => {
        const result = handleMessage(Buffer.from(data));
        expect(result).toBeDefined();
      }),
    );
  });
});
```

---

## HTTP Fuzzing

### Request-level: fuzz everything

```python
# Fuzz HTTP requests with hypothesis
from hypothesis import given, strategies as st
import requests

methods = st.sampled_from(["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD",
                           "TRACE", "CONNECT", "PROPFIND", "MKCOL"])
paths = st.from_regex(r"/[a-zA-Z0-9/_\-\.%]{0,200}", fullmatch=True)
headers = st.dictionaries(
    st.text(min_size=1, max_size=50, alphabet="abcdefghijklmnopqrstuvwxyz-"),
    st.text(min_size=0, max_size=500),
    max_size=20,
)

@given(method=methods, path=paths, hdrs=headers)
def test_fuzz_http(method, path, hdrs):
    try:
        resp = requests.request(method, f"http://localhost:3000{path}",
                                headers=hdrs, timeout=5)
        assert resp.status_code < 600
    except requests.exceptions.ConnectionError:
        pass
```

### Response parsing: fuzz client robustness

```rust
// Fuzz your HTTP client's response parser
fuzz_target!(|data: &[u8]| {
    // Simulate a raw HTTP response
    let response_bytes = data;
    let mut cursor = std::io::Cursor::new(response_bytes);
    let _ = parse_http_response(&mut cursor);
});
```

### ffuf for path/parameter discovery

```bash
# Fuzz URL paths
ffuf -u http://localhost:3000/FUZZ -w /usr/share/wordlists/dirb/common.txt

# Fuzz query parameters
ffuf -u "http://localhost:3000/api/search?FUZZ=test" -w params.txt

# Fuzz POST body fields with matching
ffuf -u http://localhost:3000/api/login \
  -X POST -H "Content-Type: application/json" \
  -d '{"username":"FUZZ","password":"test"}' \
  -w usernames.txt -mc 200,401
```

---

## REST API Fuzzing

### Schemathesis (OpenAPI/Swagger-driven)

Generates test cases automatically from your API spec:

```bash
pip install schemathesis

# Fuzz all endpoints from an OpenAPI spec
schemathesis run http://localhost:3000/openapi.json \
  --checks all \
  --hypothesis-max-examples 1000 \
  --stateful=links

# Or from a spec file
schemathesis run ./openapi.yaml --base-url http://localhost:3000
```

Use schemathesis when you have an OpenAPI spec and want broad coverage with zero harness code.

### RESTler (stateful, from Microsoft Research)

RESTler infers producer-consumer dependencies between endpoints and generates stateful test sequences:

```bash
# Compile the spec
dotnet Restler.dll compile --api_spec openapi.json

# Fuzz
dotnet Restler.dll fuzz --grammar_file Compile/grammar.py \
  --dictionary_file Compile/dict.json \
  --time_budget 3600
```

Use RESTler when your API has inter-endpoint dependencies (e.g., create user -> create order -> get order).

### Custom harness (Node.js with supertest)

```typescript
import fc from "fast-check";
import request from "supertest";
import { app } from "../src/app";

describe("API fuzz", () => {
  it("POST /api/items never returns 500", () => {
    fc.assert(
      fc.asyncProperty(
        fc.record({
          name: fc.string({ minLength: 0, maxLength: 10000 }),
          price: fc.double({ min: -1e15, max: 1e15, noNaN: true }),
          tags: fc.array(fc.string(), { maxLength: 100 }),
        }),
        async (body) => {
          const res = await request(app).post("/api/items").send(body);
          expect(res.status).toBeLessThan(500);
        },
      ),
      { numRuns: 5000 },
    );
  });
});
```

---

## GraphQL Fuzzing

### Introspection with InQL

```bash
pip install inql
# Dump schema and generate queries
inql -t http://localhost:4000/graphql -o ./graphql-fuzz/
```

### Mutation strategies

```python
# Deep nesting attack
def deep_nesting_query(depth: int) -> str:
    """Generate a deeply nested query to test stack/recursion limits."""
    q = "{ user "
    for _ in range(depth):
        q += "{ friends "
    q += "{ id name } " + "} " * depth + "}"
    return q

# Alias-based DoS
def alias_bomb(count: int) -> str:
    """Generate many aliased fields to test resource limits."""
    aliases = " ".join(f'a{i}: user(id: {i}) {{ id name email }}' for i in range(count))
    return "{ " + aliases + " }"

# Directive injection
def directive_fuzz() -> str:
    return '{ user(id: 1) @skip(if: true) @deprecated(reason: "fuzz") { id } }'
```

### Resolver fuzzing (TypeScript)

```typescript
import fc from "fast-check";
import { graphql } from "graphql";
import { schema } from "../src/schema";

it("resolver handles arbitrary string inputs", () => {
  fc.assert(
    fc.asyncProperty(fc.string({ maxLength: 5000 }), async (input) => {
      const query = `{ search(query: ${JSON.stringify(input)}) { id title } }`;
      const result = await graphql({ schema, source: query });
      // Errors in result.errors are fine; unhandled throws are not
      expect(result).toBeDefined();
    }),
  );
});
```

---

## TLS Fuzzing

### tlsfuzzer

```bash
pip install tlsfuzzer
# Test handshake variations
python -m tlsfuzzer.runner -l localhost -p 443 \
  -s scripts/test-tls13-hello-retry-request.py
```

### Certificate parsing

```rust
fuzz_target!(|data: &[u8]| {
    // Fuzz X.509 certificate parser
    let _ = x509_parser::parse_x509_certificate(data);
});
```

### Cipher suite negotiation

```go
func FuzzTLSHandshake(f *testing.F) {
    f.Add([]byte{0x16, 0x03, 0x01}) // TLS record header
    f.Fuzz(func(t *testing.T, data []byte) {
        conn := &fakeConn{Reader: bytes.NewReader(data)}
        srv := tls.Server(conn, &tls.Config{
            Certificates: []tls.Certificate{testCert},
        })
        srv.Handshake() // must not panic
    })
}
```

---

## DNS/SMTP/MQTT

### DNS

```rust
// Fuzz DNS packet parsing (e.g., trust-dns / hickory-dns)
fuzz_target!(|data: &[u8]| {
    let _ = hickory_proto::op::Message::from_vec(data);
});
```

### SMTP

```python
# boofuzz SMTP session
s_initialize("ehlo")
s_string("EHLO", fuzzable=False)
s_delim(" ")
s_string("fuzzer.local", name="domain")
s_static("\r\n")

s_initialize("mail_from")
s_string("MAIL FROM:", fuzzable=False)
s_string("<user@example.com>", name="sender", max_len=1024)
s_static("\r\n")
```

### MQTT

```rust
// Fuzz MQTT packet parsing
fuzz_target!(|data: &[u8]| {
    let _ = mqttbytes::v4::read(
        &mut std::io::Cursor::new(data),
        1024 * 1024,  // max packet size
    );
});
```

---

## Stateful Protocol Fuzzing

Fuzzing multi-message exchanges: login -> request -> response -> logout.

### Represent state machines as Arbitrary enums (Rust)

```rust
#[derive(Arbitrary, Debug)]
enum ProtocolAction {
    Login { user: String, pass: String },
    Query { table: String, limit: u32 },
    Insert { table: String, data: Vec<u8> },
    Ping,
    Logout,
}

#[derive(Arbitrary, Debug)]
struct FuzzSession {
    actions: Vec<ProtocolAction>,  // sequence of 0-50 actions
}

fuzz_target!(|session: FuzzSession| {
    let mut state = ServerState::new();
    for action in &session.actions {
        match action {
            ProtocolAction::Login { user, pass } => { state.login(user, pass); }
            ProtocolAction::Query { table, limit } => { state.query(table, *limit); }
            ProtocolAction::Insert { table, data } => { state.insert(table, data); }
            ProtocolAction::Ping => { state.ping(); }
            ProtocolAction::Logout => { state.logout(); }
        }
    }
});
```

### Shadow model for protocol state

Compare the system under test against a simplified reference model:

```rust
fuzz_target!(|session: FuzzSession| {
    let mut real = RealServer::new();
    let mut shadow = ShadowModel::new();  // simplified in-memory model

    for action in &session.actions {
        let real_result = real.execute(action);
        let shadow_result = shadow.execute(action);

        // Both must agree on success/failure
        assert_eq!(
            real_result.is_ok(), shadow_result.is_ok(),
            "Divergence on {:?}: real={:?}, shadow={:?}",
            action, real_result, shadow_result
        );
    }
});
```

### Stateful property testing (TypeScript)

```typescript
import fc from "fast-check";

const loginCmd = fc.record({
  type: fc.constant("login" as const),
  user: fc.string({ minLength: 1, maxLength: 50 }),
});
const queryCmd = fc.record({
  type: fc.constant("query" as const),
  sql: fc.string({ maxLength: 200 }),
});
const logoutCmd = fc.record({ type: fc.constant("logout" as const) });

const command = fc.oneof(loginCmd, queryCmd, logoutCmd);

it("protocol state machine never crashes", () => {
  fc.assert(
    fc.asyncProperty(fc.array(command, { maxLength: 30 }), async (cmds) => {
      const client = new ProtocolClient("localhost", 9000);
      for (const cmd of cmds) {
        await client.send(cmd);  // must not throw unhandled
      }
      await client.close();
    }),
  );
});
```

---

## CI Integration for Network Fuzzing

### Docker-based test environment

```yaml
# docker-compose.fuzz.yml
services:
  target:
    build: .
    command: ["./my_server", "--port", "9000"]
    healthcheck:
      test: ["CMD", "nc", "-z", "localhost", "9000"]
      interval: 2s
      timeout: 5s
      retries: 10

  fuzzer:
    build:
      context: .
      dockerfile: Dockerfile.fuzz
    depends_on:
      target:
        condition: service_healthy
    command: ["python", "fuzz_runner.py", "--target", "target:9000", "--duration", "300"]
```

### GitHub Actions workflow

```yaml
name: Network Fuzz
on:
  schedule:
    - cron: "0 3 * * *"  # nightly
  workflow_dispatch:

jobs:
  fuzz:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4

      - name: Start target server
        run: |
          docker compose -f docker-compose.fuzz.yml up -d target
          docker compose -f docker-compose.fuzz.yml exec target \
            sh -c 'until nc -z localhost 9000; do sleep 1; done'

      - name: Run desocketed fuzz targets
        run: cargo fuzz run parse_message -- -max_total_time=1800

      - name: Run over-the-wire fuzzing
        run: |
          docker compose -f docker-compose.fuzz.yml run --rm fuzzer

      - name: Upload crashes
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: fuzz-crashes
          path: |
            fuzz/artifacts/
            fuzz_results/crashes/

      - name: Cleanup
        if: always()
        run: docker compose -f docker-compose.fuzz.yml down -v
```

### Port management

Avoid port conflicts in CI by using dynamic ports:

```go
func getFreePort() (int, error) {
    l, err := net.Listen("tcp", "127.0.0.1:0")
    if err != nil { return 0, err }
    defer l.Close()
    return l.Addr().(*net.TCPAddr).Port, nil
}
```

```rust
fn free_port() -> u16 {
    std::net::TcpListener::bind("127.0.0.1:0")
        .unwrap()
        .local_addr()
        .unwrap()
        .port()
}
```

### Decision matrix

| Scenario | Tool | Why |
|----------|------|-----|
| Parser has no network dependency | cargo-fuzz / go test -fuzz | Fastest, most reproducible |
| Legacy server, cannot extract parser | preeny + AFL++ | No code changes needed |
| Protocol with complex state machine | boofuzz | Built-in session graphs |
| Have an OpenAPI spec | Schemathesis | Zero-config, spec-driven |
| Stateful REST API | RESTler | Infers endpoint dependencies |
| gRPC service | libprotobuf-mutator / Arbitrary | Structure-aware mutations |
| GraphQL API | InQL + custom harness | Schema-aware, nesting attacks |
| TLS/crypto | tlsfuzzer + cert parser fuzz | Handshake and cert coverage |

---

## See Also

- [HARNESS-CATALOG.md](HARNESS-CATALOG.md) — Archetype 4 (Stateful) templates for database/protocol fuzzing
- [FUZZABILITY.md](FUZZABILITY.md) — Desocketing patterns for extracting parsers from network code
- [CUSTOM-MUTATORS.md](CUSTOM-MUTATORS.md) — Custom mutators for protobuf, TLS, and other protocol formats
