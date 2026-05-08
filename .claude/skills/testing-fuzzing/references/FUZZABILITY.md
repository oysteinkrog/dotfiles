# Making Code Fuzzable

> The art of refactoring code so a fuzzer can reach it, drive it, and judge it.

## Contents

1. [The Fuzzability Test](#the-fuzzability-test)
2. [Extract-Parse-Process Pattern](#extract-parse-process-pattern)
3. [Dependency Injection for Isolated Fuzzing](#dependency-injection-for-isolated-fuzzing)
4. [Fuzz-Friendly API Surfaces](#fuzz-friendly-api-surfaces)
5. [Building Mock Oracles](#building-mock-oracles)
6. [Separating I/O from Computation](#separating-io-from-computation)
7. [Compile-Time Fuzzing Hooks](#compile-time-fuzzing-hooks)
8. [Feature Flags for Fuzz Dependencies](#feature-flags-for-fuzz-dependencies)
9. [The Refactoring Checklist](#the-refactoring-checklist)

---

## The Fuzzability Test

Ask three questions about any function:

1. **Can you call it with `&[u8]` (or equivalent raw bytes)?** If the function requires a database handle, open socket, or filesystem path to even begin executing, it is not fuzzable yet.
2. **Is it deterministic?** Given the same input bytes, does it always produce the same output? If it reads the clock, generates random numbers, or depends on environment variables, it is not fuzzable yet.
3. **Is it side-effect free?** Does it write files, send packets, or mutate global state? If so, the fuzzer cannot safely run millions of iterations.

A function that passes all three is **fuzz-ready**. A function that fails any one needs refactoring before you write a harness.

Quick diagnostic:

```
                     &[u8] input?
                     /          \
                   YES           NO  --> Extract parser (see below)
                   /
            Deterministic?
            /          \
          YES           NO  --> Inject clock/RNG (see DI section)
          /
     Side-effect free?
     /          \
   YES           NO  --> Separate I/O (see I/O section)
   /
 FUZZ-READY
```

---

## Extract-Parse-Process Pattern

The core refactoring: split monolithic functions into **read** (I/O), **parse** (bytes to structure), and **process** (logic on structure). The fuzzer targets parse and process directly.

### Rust -- Before

```rust
fn handle_request(stream: &mut TcpStream) -> Result<()> {
    let mut buf = vec![0u8; 4096];
    let n = stream.read(&mut buf)?;
    let msg: Message = serde_json::from_slice(&buf[..n])?;
    let response = compute_response(&msg);
    stream.write_all(&serde_json::to_vec(&response)?)?;
    Ok(())
}
```

### Rust -- After

```rust
// Fuzzable: pure parse
pub fn parse_message(data: &[u8]) -> Result<Message> {
    serde_json::from_slice(data).map_err(Into::into)
}

// Fuzzable: pure computation
pub fn compute_response(msg: &Message) -> Response {
    // All logic here, no I/O
}

// Not fuzzed: I/O glue
fn handle_request(stream: &mut TcpStream) -> Result<()> {
    let mut buf = vec![0u8; 4096];
    let n = stream.read(&mut buf)?;
    let msg = parse_message(&buf[..n])?;
    let response = compute_response(&msg);
    stream.write_all(&serde_json::to_vec(&response)?)?;
    Ok(())
}
```

### Go -- Before

```go
func HandleUpload(w http.ResponseWriter, r *http.Request) {
    body, _ := io.ReadAll(r.Body)
    var req UploadRequest
    json.Unmarshal(body, &req)
    result := processUpload(req, db)
    json.NewEncoder(w).Encode(result)
}
```

### Go -- After

```go
// Fuzzable: bytes to struct
func ParseUploadRequest(data []byte) (UploadRequest, error) {
    var req UploadRequest
    err := json.Unmarshal(data, &req)
    return req, err
}

// Fuzzable: pure logic (db injected, see DI section)
func ProcessUpload(req UploadRequest) UploadResult {
    // All validation and transformation here
}

// Not fuzzed: HTTP glue
func HandleUpload(w http.ResponseWriter, r *http.Request) {
    body, _ := io.ReadAll(r.Body)
    req, err := ParseUploadRequest(body)
    if err != nil { http.Error(w, err.Error(), 400); return }
    result := ProcessUpload(req)
    json.NewEncoder(w).Encode(result)
}
```

### Python -- Before

```python
def process_config(filepath: str) -> Config:
    with open(filepath) as f:
        raw = f.read()
    data = json.loads(raw)
    validated = validate_config(data)
    apply_defaults(validated)
    return Config(**validated)
```

### Python -- After

```python
# Fuzzable: bytes to dict
def parse_config(data: bytes) -> dict:
    return json.loads(data)

# Fuzzable: dict to validated Config
def validate_and_build_config(data: dict) -> Config:
    validated = validate_config(data)
    apply_defaults(validated)
    return Config(**validated)

# Not fuzzed: I/O wrapper
def process_config(filepath: str) -> Config:
    with open(filepath, "rb") as f:
        raw = f.read()
    data = parse_config(raw)
    return validate_and_build_config(data)
```

### TypeScript -- Before

```typescript
async function ingestWebhook(req: Request): Promise<Response> {
  const body = await req.text();
  const event = JSON.parse(body);
  const result = await processEvent(event, db);
  return new Response(JSON.stringify(result));
}
```

### TypeScript -- After

```typescript
// Fuzzable: string to typed event
export function parseWebhookEvent(raw: string): WebhookEvent {
  const obj = JSON.parse(raw);
  return webhookEventSchema.parse(obj); // zod validation
}

// Fuzzable: pure logic
export function processEvent(event: WebhookEvent): EventResult {
  // All business logic, no I/O
}

// Not fuzzed: HTTP glue
async function ingestWebhook(req: Request): Promise<Response> {
  const body = await req.text();
  const event = parseWebhookEvent(body);
  const result = processEvent(event);
  return new Response(JSON.stringify(result));
}
```

### C++ -- Before

```cpp
void handle_packet(int sock_fd) {
    char buf[4096];
    ssize_t n = recv(sock_fd, buf, sizeof(buf), 0);
    Packet pkt = parse_packet(buf, n);
    auto resp = process_packet(pkt);
    send(sock_fd, resp.data(), resp.size(), 0);
}
```

### C++ -- After

```cpp
// Fuzzable: raw bytes to structured packet
Packet parse_packet(const uint8_t* data, size_t len) {
    // All parsing logic, no socket ops
}

// Fuzzable: pure computation
std::vector<uint8_t> process_packet(const Packet& pkt) {
    // All logic here
}

// Not fuzzed: socket glue
void handle_packet(int sock_fd) {
    char buf[4096];
    ssize_t n = recv(sock_fd, buf, sizeof(buf), 0);
    Packet pkt = parse_packet(reinterpret_cast<const uint8_t*>(buf), n);
    auto resp = process_packet(pkt);
    send(sock_fd, resp.data(), resp.size(), 0);
}
```

### Java -- Before

```java
public Result handleRequest(HttpServletRequest req) throws Exception {
    String body = new String(req.getInputStream().readAllBytes());
    var command = objectMapper.readValue(body, Command.class);
    return commandService.execute(command, transactionManager);
}
```

### Java -- After

```java
// Fuzzable: bytes to command
public static Command parseCommand(byte[] data) throws IOException {
    return objectMapper.readValue(data, Command.class);
}

// Fuzzable: pure logic (no transaction manager)
public static Result executeCommand(Command cmd) {
    // All validation and business logic
}

// Not fuzzed: HTTP glue
public Result handleRequest(HttpServletRequest req) throws Exception {
    byte[] body = req.getInputStream().readAllBytes();
    Command cmd = parseCommand(body);
    return executeCommand(cmd);
}
```

---

## Dependency Injection for Isolated Fuzzing

When a function needs a database, filesystem, or network client, inject the dependency as a trait/interface so the fuzzer can substitute a byte-driven fake.

### Rust -- Trait-Based I/O Abstraction

```rust
pub trait Storage {
    fn read(&self, key: &str) -> Result<Vec<u8>>;
    fn write(&mut self, key: &str, data: &[u8]) -> Result<()>;
}

// Production implementation
pub struct DiskStorage { root: PathBuf }
impl Storage for DiskStorage { /* real filesystem ops */ }

// Fuzz implementation: deterministic, in-memory
pub struct FuzzStorage {
    data: HashMap<String, Vec<u8>>,
}

impl Storage for FuzzStorage {
    fn read(&self, key: &str) -> Result<Vec<u8>> {
        self.data.get(key).cloned().ok_or(Error::NotFound)
    }
    fn write(&mut self, key: &str, data: &[u8]) -> Result<()> {
        self.data.insert(key.to_string(), data.to_vec());
        Ok(())
    }
}

// Now fuzzable with injected storage
pub fn process_file(storage: &dyn Storage, key: &str, transform: &[u8]) -> Result<Vec<u8>> {
    let content = storage.read(key)?;
    apply_transform(&content, transform)
}
```

### Go -- Interface-Based

```go
type Store interface {
    Get(key string) ([]byte, error)
    Put(key string, val []byte) error
}

// Fuzz implementation
type MemStore struct {
    data map[string][]byte
}

func (m *MemStore) Get(key string) ([]byte, error) {
    v, ok := m.data[key]
    if !ok { return nil, ErrNotFound }
    return v, nil
}

func (m *MemStore) Put(key string, val []byte) error {
    m.data[key] = val
    return nil
}

// Fuzzable
func ProcessRecord(store Store, data []byte) (Result, error) {
    rec, err := ParseRecord(data)
    if err != nil { return Result{}, err }
    return transformRecord(rec), nil
}
```

### Python -- Protocol-Based

```python
from typing import Protocol

class DataSource(Protocol):
    def fetch(self, key: str) -> bytes: ...
    def store(self, key: str, data: bytes) -> None: ...

class FuzzDataSource:
    def __init__(self) -> None:
        self._data: dict[str, bytes] = {}

    def fetch(self, key: str) -> bytes:
        if key not in self._data:
            raise KeyError(key)
        return self._data[key]

    def store(self, key: str, data: bytes) -> None:
        self._data[key] = data

# Fuzzable with injected source
def process_batch(source: DataSource, raw: bytes) -> list[Result]:
    items = parse_batch(raw)
    return [transform(item) for item in items]
```

### Java -- Abstract Class

```java
public abstract class Repository {
    public abstract byte[] load(String key) throws IOException;
    public abstract void save(String key, byte[] data) throws IOException;
}

public class FuzzRepository extends Repository {
    private final Map<String, byte[]> store = new HashMap<>();

    @Override
    public byte[] load(String key) throws IOException {
        byte[] data = store.get(key);
        if (data == null) throw new IOException("not found");
        return data;
    }

    @Override
    public void save(String key, byte[] data) {
        store.put(key, data.clone());
    }
}

// Fuzzable
public static Result process(Repository repo, byte[] input) {
    Command cmd = parseCommand(input);
    return executeWithRepo(repo, cmd);
}
```

---

## Fuzz-Friendly API Surfaces

**The rule:** every function that processes external data must have a variant accepting `&[u8]` (or the language equivalent). This is the function the harness calls.

### Checklist

| Concern | Pattern |
|---------|---------|
| Parser entry point | `pub fn parse(data: &[u8]) -> Result<T>` |
| Config loader | Separate `parse_config(bytes)` from `load_config(path)` |
| Network handler | Separate `parse_frame(bytes)` from `read_frame(socket)` |
| CLI argument parser | `pub fn parse_args(args: &[&str]) -> Result<Config>` |
| Deserializer | Accept `&[u8]`, not `File` or `BufReader` |
| Validator | Accept the parsed struct, not the raw source |
| Transformer | `fn transform(input: &T) -> T` -- no I/O at all |

### Language-Specific Entry Points

**Rust:**
```rust
pub fn parse(data: &[u8]) -> Result<Message> { /* ... */ }
pub fn parse_from_reader(r: impl Read) -> Result<Message> {
    let mut buf = Vec::new();
    r.read_to_end(&mut buf)?;
    parse(&buf)
}
```

**Go:**
```go
func Parse(data []byte) (*Message, error) { /* ... */ }
func ParseReader(r io.Reader) (*Message, error) {
    data, err := io.ReadAll(r)
    if err != nil { return nil, err }
    return Parse(data)
}
```

**Python:**
```python
def parse(data: bytes) -> Message: ...
def parse_file(path: str) -> Message:
    return parse(Path(path).read_bytes())
```

**TypeScript:**
```typescript
export function parse(data: Uint8Array): Message { /* ... */ }
export function parseString(s: string): Message {
  return parse(new TextEncoder().encode(s));
}
```

**C++:**
```cpp
Message parse(const uint8_t* data, size_t len);
Message parse_file(const std::string& path) {
    auto bytes = read_file(path);
    return parse(bytes.data(), bytes.size());
}
```

**Java:**
```java
public static Message parse(byte[] data) { /* ... */ }
public static Message parseStream(InputStream is) throws IOException {
    return parse(is.readAllBytes());
}
```

---

## Building Mock Oracles

A fuzzer that only checks for crashes finds crashes. A fuzzer with an **oracle** finds logic bugs. Three oracle patterns:

### Shadow Models (Differential)

Replace a complex data structure with a trivially-correct reference and compare every operation.

**Rust:**
```rust
// Your custom B-tree vs BTreeMap
let mut ours = MyBTree::new();
let mut reference = BTreeMap::new();

for op in &ops {
    match op {
        Op::Insert(k, v) => {
            assert_eq!(ours.insert(*k, *v), reference.insert(*k, *v));
        }
        Op::Get(k) => {
            assert_eq!(ours.get(k), reference.get(k));
        }
        Op::Remove(k) => {
            assert_eq!(ours.remove(k), reference.remove(k));
        }
    }
}
```

**Go:**
```go
ours := NewCustomMap()
ref := make(map[string]string)

for _, op := range ops {
    switch op.Kind {
    case Insert:
        ours.Set(op.Key, op.Val)
        ref[op.Key] = op.Val
    case Get:
        got, ok1 := ours.Get(op.Key)
        expected, ok2 := ref[op.Key]
        if ok1 != ok2 || got != expected {
            t.Fatalf("divergence on Get(%q)", op.Key)
        }
    }
}
```

**Python (HashMap oracle for custom cache):**
```python
ours = LRUCache(capacity=10)
ref = {}  # unlimited dict as reference

for op in ops:
    if op.kind == "set":
        ours.set(op.key, op.val)
        ref[op.key] = op.val
    elif op.kind == "get":
        result = ours.get(op.key)
        if op.key in ref:
            # If ref has it but cache evicted, that is OK
            if result is not None:
                assert result == ref[op.key]
```

### Inverse Operations (Round-Trip)

If `encode(decode(x)) == x` or `decode(encode(x)) == x`, you have a free oracle.

```rust
// For any serialization format
fuzz_target!(|data: &[u8]| {
    if let Ok(parsed) = decode(data) {
        let re_encoded = encode(&parsed);
        let re_parsed = decode(&re_encoded).expect("failed to parse own output");
        assert_eq!(parsed, re_parsed, "round-trip corruption");
    }
});
```

This works for: JSON, Protobuf, MessagePack, CBOR, custom binary formats, AST pretty-printers, SQL query planners (parse-unparse), compression codecs.

### Metamorphic Relations (Mathematical Code)

When you cannot know the correct answer, verify **relationships** between inputs and outputs.

```python
# Sorting: output must be a permutation of input and be ordered
def oracle_sort(data: bytes):
    fdp = atheris.FuzzedDataProvider(data)
    arr = [fdp.ConsumeInt(4) for _ in range(fdp.ConsumeIntInRange(0, 100))]
    result = my_sort(arr[:])

    assert sorted(arr) == result          # correctness
    assert len(result) == len(arr)        # length preserved
    assert set(result) == set(arr)        # elements preserved

# Matrix multiply: (A*B)*C == A*(B*C)
def oracle_matmul(a, b, c):
    left = matmul(matmul(a, b), c)
    right = matmul(a, matmul(b, c))
    assert allclose(left, right, atol=1e-6)

# Encryption: decrypt(encrypt(plaintext, key), key) == plaintext
# Compression: decompress(compress(data)) == data
# Search: subset(query) results are subset of superset(query) results
```

---

## Separating I/O from Computation

The fundamental insight: **I/O-bound code is unfuzzable. Computation-bound code is fuzzable.** Move the boundary.

### Pattern: Functional Core, Imperative Shell

```
+-------------------------------------------+
|  Imperative Shell (NOT fuzzed)            |
|  - reads files, sockets, env vars         |
|  - writes responses, logs, databases      |
|  - calls functional core with raw bytes   |
+-------------------------------------------+
         |            ^
         v            |
+-------------------------------------------+
|  Functional Core (FUZZED)                 |
|  - accepts &[u8] or typed structs         |
|  - returns Result<T> or typed structs     |
|  - no I/O, no globals, no clocks          |
+-------------------------------------------+
```

### Rust

```rust
// Functional core -- fuzzable
pub fn validate_certificate(der_bytes: &[u8]) -> Result<CertInfo, CertError> {
    let cert = parse_x509(der_bytes)?;
    check_signature(&cert)?;
    check_validity_period(&cert, SystemTime::UNIX_EPOCH)?; // injected time
    Ok(extract_info(&cert))
}

// Imperative shell -- not fuzzed
pub fn validate_certificate_from_pem_file(path: &Path) -> Result<CertInfo, CertError> {
    let pem = std::fs::read(path)?;
    let der = pem_to_der(&pem)?;
    validate_certificate(&der)
}
```

### Go

```go
// Functional core
func ValidateToken(tokenBytes []byte, now time.Time) (*Claims, error) {
    header, payload, sig, err := splitJWT(tokenBytes)
    if err != nil { return nil, err }
    if err := verifySig(header, payload, sig); err != nil { return nil, err }
    claims, err := parseClaims(payload)
    if err != nil { return nil, err }
    if claims.Exp.Before(now) { return nil, ErrExpired }
    return claims, nil
}

// Imperative shell
func ValidateTokenFromHeader(r *http.Request) (*Claims, error) {
    auth := r.Header.Get("Authorization")
    token := strings.TrimPrefix(auth, "Bearer ")
    return ValidateToken([]byte(token), time.Now())
}
```

### TypeScript

```typescript
// Functional core -- fuzzable
export function evaluateExpression(tokens: Token[]): Result<Value, EvalError> {
  // Pure computation, no I/O
}

export function tokenize(source: string): Result<Token[], ParseError> {
  // Pure parse, no I/O
}

// Imperative shell
export async function evaluateFile(path: string): Promise<Value> {
  const source = await fs.readFile(path, "utf-8");
  const tokens = tokenize(source).unwrap();
  return evaluateExpression(tokens).unwrap();
}
```

### Python

```python
# Functional core -- fuzzable
def score_document(doc_bytes: bytes, query_terms: list[str]) -> float:
    text = doc_bytes.decode("utf-8", errors="replace")
    tokens = tokenize(text)
    return compute_bm25(tokens, query_terms)

# Imperative shell
def score_document_from_url(url: str, query: str) -> float:
    resp = requests.get(url)
    terms = query.split()
    return score_document(resp.content, terms)
```

---

## Compile-Time Fuzzing Hooks

Insert instrumentation that the compiler eliminates entirely in production builds. Zero runtime cost when not fuzzing.

### Rust -- `#[cfg(fuzzing)]`

```rust
pub fn process(data: &[u8]) -> Result<Output> {
    #[cfg(fuzzing)]
    if data.len() > MAX_FUZZ_INPUT {
        return Err(Error::InputTooLarge);
    }

    #[cfg(fuzzing)]
    FUZZ_COUNTER.fetch_add(1, Ordering::Relaxed);

    // Real logic
    let parsed = parse(data)?;
    transform(parsed)
}

// Expose internals only under fuzzing
#[cfg(fuzzing)]
pub fn internal_parse_header(data: &[u8]) -> Result<Header> {
    parse_header(data)
}
```

`cargo fuzz` sets `#[cfg(fuzzing)]` automatically. In release builds, all guarded code is stripped.

### Go -- Build Tags

```go
//go:build fuzzing

package mypackage

// Only compiled when: go test -tags=fuzzing
var FuzzHookEnabled = true

func ExposeInternalParser(data []byte) (*Header, error) {
    return parseHeader(data)
}
```

```go
//go:build !fuzzing

package mypackage

var FuzzHookEnabled = false
```

### Python -- `__debug__`

```python
def process(data: bytes) -> Result:
    if __debug__:  # Stripped when running with python -O
        if len(data) > MAX_FUZZ_INPUT:
            raise ValueError("fuzz input too large")

    return _process_impl(data)

# Expose internals only in debug/fuzz mode
if __debug__:
    parse_header_for_testing = _parse_header
```

For finer control, use an environment variable:

```python
import os
FUZZING = os.environ.get("FUZZING") == "1"

if FUZZING:
    def _fuzz_check_invariants(state):
        assert state.is_consistent(), f"Invariant violated: {state}"
else:
    def _fuzz_check_invariants(state):
        pass
```

### TypeScript -- `NODE_ENV`

```typescript
export function process(data: Uint8Array): Result {
  if (process.env.NODE_ENV === "test") {
    if (data.length > MAX_FUZZ_INPUT) {
      throw new Error("fuzz input too large");
    }
  }
  return processImpl(data);
}

// Tree-shaken by bundlers in production
export const __test_internals = process.env.NODE_ENV === "test"
  ? { parseHeader, validateChecksum, rebuildIndex }
  : undefined;
```

### C++ -- Preprocessor Macros

```cpp
#ifdef FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
  // libFuzzer/AFL++ set this automatically
  #define FUZZ_ASSERT(cond) do { if (!(cond)) __builtin_trap(); } while(0)
  #define FUZZ_EXPORT __attribute__((visibility("default")))
#else
  #define FUZZ_ASSERT(cond) ((void)0)
  #define FUZZ_EXPORT static
#endif

void process(const uint8_t* data, size_t len) {
    FUZZ_ASSERT(len <= MAX_FUZZ_INPUT);
    auto msg = parse_message(data, len);
    FUZZ_ASSERT(msg.checksum_valid());
    handle(msg);
}

// Internal parser exposed only for fuzzing
FUZZ_EXPORT
Header parse_header_raw(const uint8_t* data, size_t len) {
    return parse_header(data, len);
}
```

---

## Feature Flags for Fuzz Dependencies

Fuzz harnesses pull in large dependencies (arbitrary, libfuzzer-sys, atheris). These must never leak into production builds.

### Rust -- Cargo.toml `[features]`

```toml
[features]
fuzz = ["arbitrary", "libfuzzer-sys"]

[dependencies]
arbitrary = { version = "1", optional = true, features = ["derive"] }
libfuzzer-sys = { version = "0.11", optional = true }
```

```rust
#[cfg(feature = "fuzz")]
#[derive(arbitrary::Arbitrary)]
pub struct FuzzInput {
    pub header: Vec<u8>,
    pub body: Vec<u8>,
}

#[cfg(feature = "fuzz")]
impl From<FuzzInput> for Request {
    fn from(input: FuzzInput) -> Self {
        Request { header: input.header, body: input.body }
    }
}
```

`cargo-fuzz` targets in `fuzz/Cargo.toml` depend on the crate with `features = ["fuzz"]`. Regular `cargo build` never pulls in fuzzing deps.

### Go -- Build Constraints

```go
//go:build ignore
// +build ignore

// fuzz_helpers.go -- only compiled by go test -fuzz
package mypackage

import "testing"

func fuzzSetup(f *testing.F) {
    // Expensive corpus generation only during fuzzing
}
```

Go's native fuzzing needs no external deps, but for go-fuzz compatibility:

```go
//go:build gofuzz

package mypackage

func Fuzz(data []byte) int {
    // go-fuzz harness
    return 0
}
```

### Python -- `extras_require`

```toml
# pyproject.toml
[project.optional-dependencies]
fuzz = ["atheris>=2.3.0", "hypothesis>=6.0"]
```

```bash
pip install mypackage[fuzz]    # Developers who fuzz
pip install mypackage          # Everyone else
```

Guard fuzz-only imports:

```python
try:
    import atheris
    HAS_ATHERIS = True
except ImportError:
    HAS_ATHERIS = False
```

### TypeScript -- Optional devDependencies

```json
{
  "devDependencies": {
    "@jazzer.js/core": "^2.0.0",
    "fast-check": "^3.0.0"
  }
}
```

These are `devDependencies`, not `dependencies`. They are excluded from production bundles automatically. For extra safety:

```typescript
// fuzz/harness.ts -- lives in fuzz/ directory, excluded from tsconfig.build.json
import { FuzzedDataProvider } from "@jazzer.js/core";
```

### Java -- Maven/Gradle Test Scope

```xml
<!-- pom.xml -->
<dependency>
    <groupId>com.code-intelligence</groupId>
    <artifactId>jazzer-api</artifactId>
    <version>0.22.1</version>
    <scope>test</scope>
</dependency>
```

```groovy
// build.gradle
testImplementation 'com.code-intelligence:jazzer-api:0.22.1'
```

Test-scoped dependencies are excluded from the production JAR.

---

## The Refactoring Checklist

Step-by-step process to make any function fuzzable. Work through in order.

### Step 1: Identify I/O Boundaries

Map every I/O operation in the function:

```
[ ] File reads/writes
[ ] Network sends/receives
[ ] Database queries
[ ] Environment variable reads
[ ] Clock/time reads
[ ] Random number generation
[ ] Logging with side effects
[ ] Global/static mutable state
```

### Step 2: Extract Computation

Move all non-I/O logic into a pure function:

```
BEFORE: handle_request(socket) -> void
AFTER:  parse_request(bytes) -> Request          # fuzzable
        process_request(Request) -> Response      # fuzzable
        handle_request(socket) -> void            # calls both
```

Rules:
- The extracted function accepts `&[u8]`, `[]byte`, `bytes`, `Uint8Array`, `const uint8_t*`, or `byte[]`
- It returns a value or `Result`/error -- never writes to an output destination
- It takes no handles, connections, or file descriptors as arguments

### Step 3: Add Byte-Accepting API

Ensure the public API has a bytes-in entry point:

```
# For a config parser:
pub fn parse_config(data: &[u8]) -> Result<Config>

# For a network protocol:
pub fn parse_frame(data: &[u8]) -> Result<Frame>

# For a file format:
pub fn parse_document(data: &[u8]) -> Result<Document>
```

If the function needs multiple inputs, use structured fuzzing:

```rust
#[derive(Arbitrary)]
struct FuzzInput {
    config: Vec<u8>,
    payload: Vec<u8>,
    flags: u32,
}
```

### Step 4: Verify Determinism

Run the function 1000 times with the same input. Output must be identical every time.

Common determinism killers and fixes:

| Non-Determinism Source | Fix |
|------------------------|-----|
| `HashMap` iteration order | Use `BTreeMap` in fuzz mode, or sort output |
| `SystemTime::now()` | Inject a clock parameter |
| `rand::thread_rng()` | Accept `&mut impl Rng` and pass `StdRng::seed_from_u64(0)` |
| Thread scheduling | Avoid shared mutable state, or use deterministic scheduler |
| Floating-point across platforms | Use integer math, or accept epsilon tolerance |
| Pointer addresses in output | Strip or normalize addresses |

### Step 5: Add an Oracle

Choose the appropriate oracle for your function type:

| Function Type | Oracle |
|---------------|--------|
| Serializer/Deserializer | Round-trip: `decode(encode(x)) == x` |
| Data structure | Shadow model: compare with `BTreeMap`/`HashMap` |
| Sort/search | Metamorphic: verify ordering, element preservation |
| Compression | Inverse: `decompress(compress(x)) == x` |
| Encryption | Inverse: `decrypt(encrypt(x, k), k) == x` |
| Compiler/transpiler | Differential: compare two backends |
| Validator | Metamorphic: valid input with noise must be rejected |
| Idempotent operation | `f(f(x)) == f(x)` |

### Step 6: Write the Harness

Combine the byte-accepting API with the oracle:

```rust
#![no_main]
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    // Step 3: byte-accepting entry
    let parsed = match parse_config(data) {
        Ok(c) => c,
        Err(_) => return, // graceful rejection
    };

    // Step 5: oracle
    let re_encoded = encode_config(&parsed);
    let re_parsed = parse_config(&re_encoded)
        .expect("cannot parse own output");
    assert_eq!(parsed, re_parsed, "round-trip corruption");

    // Bonus: invariant checks
    assert!(parsed.max_connections > 0, "invalid zero connections");
    assert!(parsed.timeout_ms <= 300_000, "timeout exceeds 5 minutes");
});
```

### Step 7: Validate the Pipeline

Before calling it done:

```
[ ] Harness compiles and runs for 60 seconds without false positives
[ ] Corpus seeds include: empty input, minimal valid input, maximum-size input
[ ] Coverage report shows the harness reaches the interesting code paths
[ ] Fuzz dependencies are behind feature flags / optional deps
[ ] CI runs the harness in regression mode (fixed corpus, bounded time)
[ ] Compile-time hooks are verified dead in release builds
[ ] SANITIZERS.md patterns applied (ASan, UBSan, MSan as appropriate)
```

Quick validation script:

```bash
# Rust
cargo fuzz run my_target -- -max_total_time=60 -print_final_stats=1

# Go
go test -fuzz=FuzzMyTarget -fuzztime=60s -v

# Python
timeout 60 python fuzz_target.py

# Check coverage (Rust)
cargo fuzz coverage my_target
llvm-cov show fuzz/target/*/release/my_target \
    -instr-profile=fuzz/coverage/my_target/coverage.profdata \
    -format=html > coverage.html
```

If coverage is below 60% of the target function's branches, the harness is not reaching enough code. Improve seed corpus or add structured fuzzing to generate more valid inputs.
