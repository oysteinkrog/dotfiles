# Fuzzing Walkthrough: Zero to CI in One Hour

End-to-end narrative for a Rust binary parser crate (`wire-proto`).
Adaptation notes for Go, Python, and TypeScript inline.

## Minute 0-5: Reconnaissance

```bash
cd wire-proto
cat Cargo.toml                         # deps, features, edition
grep -rn 'pub fn' src/lib.rs           # public API surface
grep -rn 'unsafe' src/                 # unsafe = high-value targets
ls tests/ benches/ fuzz/ 2>/dev/null   # existing infrastructure
```

We find: `src/parser.rs` (binary frame parser, two unsafe blocks for zero-copy slicing), `src/encoder.rs`, `src/types.rs`. No `fuzz/` yet.

**Target discovery heuristics** -- functions that accept `&[u8]`/`&str`/`Read`, have complex branching, contain `unsafe`, or sit on network/file I/O paths.

Candidates: `parse_frame(&[u8])`, `decode_header(&[u8])`, `encode_frame(&Frame)`.

> **Go**: scan for `func.*[]byte`, `io.Reader`. **Python**: `def parse(data: bytes)`. **TS**: `Buffer`/`Uint8Array` params.

## Minute 5-10: Score Targets

| Function | Input | Complexity | Unsafe | State | Score |
|---|---|---|---|---|---|
| `parse_frame` | raw bytes | high | yes | stateless | **9** |
| `decode_header` | raw bytes | medium | no | stateless | 6 |
| `encode_frame` | typed struct | low | no | stateless | 3 |

Winner: `parse_frame`.

## Minute 10-15: Check Fuzzability

1. **Accepts byte slice directly?** Yes -- `pub fn parse_frame(data: &[u8]) -> Result<Frame, ParseError>`.
2. **Pure function?** Yes (no I/O, no global state).
3. **Bounded termination?** No unbounded loops. Yes.
4. **Deterministic?** No RNG, no timestamps. Yes.

All green. If the parser were inside a TCP handler, extract it into a standalone function first.

> **Go**: no `os.Exit`/`log.Fatal`. **Python**: no `input()`. **TS**: no DOM APIs in the parse path.

## Minute 15-25: Write First Harness

```bash
cargo install cargo-fuzz && cargo fuzz init && cargo fuzz add parse_frame
```

`fuzz/fuzz_targets/parse_frame.rs`:
```rust
#![no_main]
use libfuzzer_sys::fuzz_target;
use wire_proto::parse_frame;

fuzz_target!(|data: &[u8]| {
    if data.len() > 65536 { return; }
    let _ = parse_frame(data);            // shallow oracle -- phase 1
});
```

**Seed corpus** from test fixtures and hand-crafted edges:
```bash
mkdir -p fuzz/corpus/parse_frame
cp tests/fixtures/*.bin fuzz/corpus/parse_frame/
printf '\x00' > fuzz/corpus/parse_frame/minimal
printf '' > fuzz/corpus/parse_frame/empty
```

**Dictionary** for magic bytes and field tags:
```
"\x57\x50"         # magic header "WP"
"\x00\x01"         # version 1
"\xFF\xFF\xFF\xFF"  # max length field
```

> **Go**: `go test -fuzz`. **Python**: `atheris.Setup(sys.argv, target)`. **TS**: `fast-check` with `fc.uint8Array()`.

## Minute 25-30: First Run

```bash
cargo +nightly fuzz run parse_frame -- -max_total_time=300
```

Watch: **exec/s** (must be >1000 for parsers), **NEW coverage** lines (steady growth in first minute), **crashes** (triage immediately if found).

```bash
cargo fuzz coverage parse_frame   # check for unreached branches
```

## Minute 30-45: Triage

### Crashes found:

```bash
cargo fuzz tmin parse_frame fuzz/artifacts/parse_frame/crash-abc123  # minimize
cargo fuzz run parse_frame fuzz/artifacts/parse_frame/crash-abc123 -- -runs=1  # reproduce
```

Write regression test:
```rust
#[test]
fn regression_crash_abc123() {
    let data = include_bytes!("../fuzz/artifacts/parse_frame/crash-abc123");
    let _ = parse_frame(data);  // must not panic
}
```

Fix the bug. Verify: `cargo test regression_crash_abc123`.

### No crashes:

Review coverage for unreached code. Add dictionary tokens, improve seeds, or upgrade to round-trip oracle: `assert_eq!(parse_frame(&encode_frame(&frame)), frame)`.

> **Go**: `go test -run FuzzMinimize`. **Python**: `atheris` + `ASAN_OPTIONS`. **TS**: manually bisect failing input.

## Minute 45-60: CI Integration

### PR fuzzing (`fuzz-pr.yml` -- 5-min runs):

```yaml
name: Fuzz (PR)
on: [pull_request]
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@nightly
      - run: cargo install cargo-fuzz
      - run: cargo fuzz run parse_frame -- -max_total_time=300
        env: { RUSTFLAGS: "-Zsanitizer=address" }
      - uses: actions/cache/save@v4
        with: { path: fuzz/corpus/, key: "fuzz-corpus-${{ github.sha }}" }
```

### Nightly fuzzing (`fuzz-nightly.yml` -- 2-hour runs):

```yaml
name: Fuzz (Nightly)
on:
  schedule: [{ cron: '0 2 * * *' }]
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@nightly
      - uses: actions/cache/restore@v4
        with: { path: fuzz/corpus/, key: fuzz-corpus-, restore-keys: fuzz-corpus- }
      - run: cargo install cargo-fuzz
      - run: cargo fuzz run parse_frame -- -max_total_time=7200
        env: { RUSTFLAGS: "-Zsanitizer=address" }
      - uses: actions/cache/save@v4
        if: always()
        with: { path: fuzz/corpus/, key: "fuzz-corpus-${{ github.sha }}-nightly" }
```

Commit minimized corpus:
```bash
cargo fuzz cmin parse_frame
git add fuzz/ .github/workflows/fuzz-*.yml
git commit -m "fuzz: add parse_frame harness, corpus, and CI"
```

> **Go**: `go test -fuzz -fuzztime=5m` in CI. **Python**: `timeout 300 python fuzz_target.py`. **TS**: `npx fast-check --num-runs=100000`.

## After Hour 1: Expand

1. **More targets** -- work down the scored list: `decode_header`, then `encode_frame` round-trip.
2. **Upgrade oracles** -- round-trip, then differential:
```rust
fuzz_target!(|data: &[u8]| {
    if data.len() > 65536 { return; }
    if let Ok(frame) = parse_frame(data) {
        let rt = parse_frame(&encode_frame(&frame)).expect("round-trip must succeed");
        assert_eq!(frame, rt, "round-trip divergence");
    }
});
```
3. **Sanitizer campaigns** -- MSan for unsafe paths: `RUSTFLAGS="-Zsanitizer=memory"`.
4. **Plateau response** -- corpus minimization, new dictionary tokens, structure-aware fuzzing via `Arbitrary`.
5. **Validate** -- run `scripts/validate-fuzz-harness.sh parse_frame` (see VALIDATORS.md). All seven checks must pass.

---

## Walkthrough 2: Go HTTP Parser (Zero to CI in 45 Minutes)

End-to-end narrative for a Go HTTP request parser library (`httparse`).
Uses Go-native fuzzing tooling throughout: `testing.F`, `testdata/fuzz/`, `go test -fuzz`.

### Phase 1 -- Reconnaissance (Minute 0-5)

```bash
cd httparse
cat go.mod                                   # module path, Go version, deps
grep -rn 'func ' *.go | grep -v _test.go    # public API surface
grep -rn 'unsafe' *.go                       # unsafe.Pointer usage
ls testdata/ *_test.go 2>/dev/null           # existing test infrastructure
```

We find: `parser.go` (HTTP/1.1 request parser with manual byte scanning), `headers.go` (header name/value extraction with unsafe for zero-copy), `request.go` (structured Request type). No `testdata/fuzz/` yet.

**Target candidates:**
- `ParseRequest([]byte) (*Request, error)` -- raw bytes in, structured data out, complex branching
- `ParseHeaders([]byte) ([]Header, error)` -- sub-parser, moderate complexity
- `FormatRequest(*Request) []byte` -- typed input, low complexity

### Phase 2 -- Score (Minute 5-8)

| Function | Input | Complexity | Unsafe | State | Score |
|---|---|---|---|---|---|
| `ParseRequest` | `[]byte` | high | yes | stateless | **9** |
| `ParseHeaders` | `[]byte` | medium | yes | stateless | 7 |
| `FormatRequest` | `*Request` | low | no | stateless | 3 |

Winner: `ParseRequest`. `ParseHeaders` is a close second and will be tested indirectly.

### Phase 3 -- Fuzzability Check (Minute 8-10)

1. **Accepts `[]byte` directly?** Yes -- `func ParseRequest(data []byte) (*Request, error)`.
2. **Pure function?** Yes -- no file I/O, no network, no globals modified.
3. **Bounded termination?** Single pass over input with bounded loops. Yes.
4. **Deterministic?** No `rand`, no `time.Now()` in parse path. Yes.
5. **No `os.Exit` or `log.Fatal`?** Confirmed -- errors returned, not fatal.

All clear. Proceed to harness.

### Phase 4 -- Write Harness (Minute 10-20)

Create `fuzz_test.go` in the package root:

```go
package httparse

import (
	"bytes"
	"testing"
)

func FuzzParseRequest(f *testing.F) {
	// Seed corpus: valid HTTP requests and edge cases
	f.Add([]byte("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"))
	f.Add([]byte("POST /api HTTP/1.1\r\nHost: example.com\r\nContent-Length: 5\r\n\r\nhello"))
	f.Add([]byte("GET / HTTP/1.0\r\n\r\n"))
	f.Add([]byte("\r\n"))       // just CRLF
	f.Add([]byte(""))           // empty
	f.Add([]byte("GET"))        // truncated
	f.Add([]byte("GET / HTTP/1.1\r\nX-Long: " + string(bytes.Repeat([]byte("A"), 8192)) + "\r\n\r\n"))

	f.Fuzz(func(t *testing.T, data []byte) {
		if len(data) > 65536 {
			return // bound input size for speed
		}

		// Phase 1: shallow oracle -- must not panic
		req, err := ParseRequest(data)
		if err != nil {
			return // parse errors are expected on random input
		}

		// Phase 2: round-trip oracle
		formatted := FormatRequest(req)
		req2, err := ParseRequest(formatted)
		if err != nil {
			t.Fatalf("round-trip parse failed: %v\ninput:  %q\nformatted: %q", err, data, formatted)
		}

		// Semantic equality (method, path, headers must survive round-trip)
		if req.Method != req2.Method {
			t.Fatalf("method mismatch: %q vs %q", req.Method, req2.Method)
		}
		if req.Path != req2.Path {
			t.Fatalf("path mismatch: %q vs %q", req.Path, req2.Path)
		}
		if len(req.Headers) != len(req2.Headers) {
			t.Fatalf("header count mismatch: %d vs %d", len(req.Headers), len(req2.Headers))
		}
	})
}
```

Seed corpus from existing tests:

```bash
mkdir -p testdata/fuzz/FuzzParseRequest
# Copy any .http or .txt fixtures from test data
for f in testdata/fixtures/*.http; do
    [ -f "$f" ] && cp "$f" testdata/fuzz/FuzzParseRequest/
done
```

### Phase 5 -- First Run (Minute 20-25)

```bash
# Short smoke test: 30 seconds with race detector
go test -fuzz=FuzzParseRequest -fuzztime=30s -race -v

# Watch the output for:
#   fuzz: elapsed: 3s, execs: 45231 (15077/sec)   <-- exec/s must be >1000
#   fuzz: elapsed: 6s, execs: 98412 (16402/sec), new interesting: 24
```

Check coverage of the corpus so far:

```bash
go test -coverprofile=fuzz_cover.out -run='^$' -fuzz=FuzzParseRequest -fuzztime=1x
go tool cover -html=fuzz_cover.out -o fuzz_cover.html
# Open fuzz_cover.html -- red lines are unreached branches
```

### Phase 6 -- Triage (Minute 25-35)

**If crashes are found**, Go writes failing inputs to `testdata/fuzz/FuzzParseRequest/`:

```bash
# List crash files
ls testdata/fuzz/FuzzParseRequest/

# Reproduce a specific crash
go test -run=FuzzParseRequest/corpus_file_name -v

# The crash file is already in the right format for regression testing.
# Go's native fuzzer automatically replays all files in testdata/fuzz/ on `go test`.
```

Fix the bug, then verify all corpus entries pass:

```bash
go test -run=FuzzParseRequest -v   # replays entire seed + crash corpus
go test -race ./...                # full test suite with race detector
```

**If no crashes**: review `fuzz_cover.html` for uncovered branches. Common patterns:
- Chunked transfer-encoding path never reached -- add a seed with `Transfer-Encoding: chunked`
- HTTP/2 preface handling -- add `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n` as a seed
- Multiline header folding -- add `X-Folded: value\r\n continuation\r\n\r\n`

### Phase 7 -- CI Integration (Minute 35-42)

**PR fuzzing** (`.github/workflows/fuzz-pr.yml`):

```yaml
name: Fuzz (PR)
on: [pull_request]
jobs:
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - uses: actions/cache@v4
        with:
          path: testdata/fuzz/
          key: go-fuzz-${{ github.sha }}
          restore-keys: go-fuzz-
      - name: Fuzz for 5 minutes
        run: go test -fuzz=FuzzParseRequest -fuzztime=5m -race -parallel=4
      - name: Upload crashes
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: go-fuzz-crashes
          path: testdata/fuzz/FuzzParseRequest/
```

**Nightly fuzzing** (`.github/workflows/fuzz-nightly.yml`):

```yaml
name: Fuzz (Nightly)
on:
  schedule: [{ cron: '0 2 * * *' }]
jobs:
  fuzz:
    runs-on: ubuntu-latest
    timeout-minutes: 120
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with: { go-version: '1.22' }
      - uses: actions/cache/restore@v4
        with:
          path: |
            testdata/fuzz/
            ~/.cache/go-build/fuzz/
          key: go-fuzz-nightly-
          restore-keys: go-fuzz-nightly-
      - name: Fuzz for 1 hour with race detector
        run: go test -fuzz=FuzzParseRequest -fuzztime=1h -race -parallel=8
      - uses: actions/cache/save@v4
        if: always()
        with:
          path: |
            testdata/fuzz/
            ~/.cache/go-build/fuzz/
          key: go-fuzz-nightly-${{ github.sha }}
      - name: Upload crashes
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: go-fuzz-crashes-nightly
          path: testdata/fuzz/FuzzParseRequest/
```

Commit everything:

```bash
git add fuzz_test.go testdata/fuzz/ .github/workflows/fuzz-*.yml
git commit -m "fuzz: add FuzzParseRequest harness, seeds, and CI"
```

### Phase 8 -- Expand (Minute 42+)

1. **More targets**: Add `FuzzParseHeaders` (isolated header parsing) and `FuzzParseChunked` (chunked body decoding).
2. **Differential oracle**: Compare against `net/http` stdlib parser:
```go
f.Fuzz(func(t *testing.T, data []byte) {
    ourReq, ourErr := ParseRequest(data)
    stdReq, stdErr := http.ReadRequest(bufio.NewReader(bytes.NewReader(data)))
    if stdErr == nil && ourErr != nil {
        t.Fatalf("stdlib parsed but we rejected: %q", data)
    }
    if stdErr == nil && ourErr == nil {
        if ourReq.Method != stdReq.Method {
            t.Fatalf("method divergence: ours=%q stdlib=%q", ourReq.Method, stdReq.Method)
        }
    }
})
```
3. **Race detection**: The `-race` flag is already enabled in all runs above. Go's native fuzzer + race detector catches data races that only manifest under specific input patterns.
4. **Sanitizer equivalent**: Use `GOFLAGS="-asan"` (Go 1.23+) for address sanitizer support on C-interop code:
```bash
CC=clang go test -fuzz=FuzzParseRequest -fuzztime=30m -asan
```
5. **Corpus hygiene**: Periodically minimize the corpus by removing entries that do not add unique coverage:
```bash
# Go doesn't have built-in cmin, but you can prune manually:
go test -run=FuzzParseRequest -coverprofile=cover.out
# Remove corpus entries whose coverage is a subset of others
```

---

## See Also

- [HARNESS-CATALOG.md](HARNESS-CATALOG.md) — Full templates for all 7 archetypes in 6 languages
- [PERFORMANCE-TUNING.md](PERFORMANCE-TUNING.md) — Optimize exec/s after getting fuzzing running
- [VALIDATORS.md](VALIDATORS.md) — Verify your fuzzing infrastructure quality
- [LANGUAGES.md](LANGUAGES.md) — Language-specific setup details beyond what the walkthrough covers
