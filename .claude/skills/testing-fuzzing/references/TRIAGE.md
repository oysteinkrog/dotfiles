# Crash Triage Guide

Systematic workflow for turning raw fuzzer crashes into fixed bugs and regression tests.

---

## 1. The Triage Pipeline

Every crash follows the same 9-step sequence. Skipping steps creates duplicates and wastes time.

1. **Minimize** — Shrink the input to the smallest reproducer (`cargo fuzz tmin`, `afl-tmin`, or libFuzzer `-minimize_crash=1`).
2. **Reproduce** — Confirm the crash replays deterministically outside the fuzzer. Run with the same sanitizer flags.
3. **Deduplicate** — Hash the top-N stack frames. Check against known crash hashes before proceeding.
4. **Classify** — Determine the sanitizer category: heap-buffer-overflow, use-after-free, stack-overflow, integer-overflow, null-deref, etc.
5. **Severity** — Assign severity using the exploitability ladder (Section 4).
6. **Root-cause** — Trace the bug from the crash site back to the flawed logic. Read the code, not just the stack.
7. **Fix** — Patch the root cause. Prefer bounds checks, safe APIs, and type-system enforcement over band-aids.
8. **Regression test** — Add the minimized input as a permanent test case (Section 9).
9. **Re-fuzz** — Run the fuzzer again on the patched code to confirm the crash is gone and no new crashes appear in the same area.

---

## 2. Reading Sanitizer Reports

### AddressSanitizer (ASan)

```
=================================================================
==31337==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x602000000038 at pc 0x55a3c1 bp 0x7ffd42 sp 0x7ffd3a
WRITE of size 4 at 0x602000000038 thread T0
    #0 0x55a3c0 in parse_header /src/parser.c:142:17
    #1 0x55b210 in process_input /src/parser.c:87:5
    #2 0x55c8f0 in LLVMFuzzerTestOneInput /src/fuzz_parser.c:12:3
    #3 0x43e592 in fuzzer::Fuzzer::ExecuteCallback(...) FuzzerLoop.cpp:611

0x602000000038 is located 0 bytes to the right of 24-byte region [0x602000000020,0x602000000038)
allocated by thread T0 here:
    #0 0x519a07 in malloc asan_malloc_linux.cpp
    #1 0x55a100 in parse_header /src/parser.c:130:22

SUMMARY: AddressSanitizer: heap-buffer-overflow /src/parser.c:142:17 in parse_header
Shadow bytes around the buggy address:
  0x0c047fff7fb0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
  0x0c047fff7fc0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
=>0x0c047fff8000: fa fa 00 00 00[fa]fa fa fa fa fa fa fa fa fa fa
  0x0c047fff8010: fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa fa
Shadow byte legend: 00=addressable, fa=heap left/right redzone, fd=freed heap
==31337==ABORTING
```

Line-by-line breakdown:

- **`ERROR:` line** — Sanitizer type (`AddressSanitizer`), bug class (`heap-buffer-overflow`), faulting address, program counter (`pc`).
- **`WRITE of size 4`** — Direction (READ/WRITE) and byte count. WRITE is more dangerous than READ.
- **Stack trace `#0..#N`** — Most recent frame first. Frame `#0` is the crash site: file, line, column. Frames above `#2` are fuzzer internals — ignore them.
- **`0x602... is located 0 bytes to the right of 24-byte region`** — The write landed exactly at the end of a 24-byte allocation. Classic off-by-one or missing bounds check.
- **`allocated by thread T0 here:`** — Where the buffer was originally allocated. Compare allocation size against access offset to understand the overflow distance.
- **Shadow memory** — `[fa]` marks the redzone. `00` = addressable. The bracketed byte is the faulting shadow location.

### UndefinedBehaviorSanitizer (UBSan)

```
/src/math.c:47:15: runtime error: signed integer overflow: 2147483647 + 1 cannot be represented in type 'int'
SUMMARY: UndefinedBehaviorSanitizer: undefined-behavior /src/math.c:47:15
```

UBSan reports are single-line. They name the exact UB category and the expression that triggered it. No stack trace by default — add `-fsanitize-recover=all -fno-sanitize-recover=all` to get a trap or compile with `-fsanitize=undefined -fno-omit-frame-pointer` and set `UBSAN_OPTIONS=print_stacktrace=1`.

### MemorySanitizer (MSan)

```
==12345==WARNING: MemorySanitizer: use-of-uninitialized-value
    #0 0x55a100 in check_flag /src/config.c:88:7
    #1 0x55b300 in main /src/main.c:22:5

  Uninitialized value was created by a heap allocation
    #0 0x519a07 in malloc msan_interceptors.cpp
    #1 0x55a050 in load_config /src/config.c:72:18
```

MSan has two stack traces: where the uninitialized value was **used** and where it was **created**. The fix is at the creation site — initialize the memory.

### ThreadSanitizer (TSan)

```
WARNING: ThreadSanitizer: data race (pid=9999)
  Write of size 8 at 0x7f8000 by thread T2:
    #0 increment_counter /src/stats.c:34:5
  Previous read of size 8 at 0x7f8000 by thread T1:
    #0 get_counter /src/stats.c:41:12
  Location is global 'g_counter' of size 8 at 0x7f8000
```

TSan shows two conflicting accesses with their threads and stack traces. At least one must be a write. Fix with a mutex, atomic, or by eliminating the shared state.

---

## 3. Crash Deduplication

### Stack Hash Method

Hash the top-N function names from the crash stack trace. N=5 is the standard:

```bash
#!/usr/bin/env bash
# stack-hash.sh — Hash the top N frames of a sanitizer stack trace
N="${2:-5}"
grep -oP '(?<=in )\S+' "$1" | head -n "$N" | sha256sum | cut -c1-16
```

Usage: `./stack-hash.sh crash-report.txt` produces a 16-char hex hash.

**Choosing N:**
- **N=3** — Coarse grouping. Collapses variants of the same bug that crash at slightly different depths. Good for early triage when you have hundreds of crashes.
- **N=5** — Standard. Balances precision and recall. Two crashes with the same top-5 hash are almost certainly the same bug.
- **N=7** — Fine-grained. Use when you suspect two crashes with the same top-5 hash are actually different bugs triggered through different call paths.

**Symbolization pitfalls:**
- Unsymbolized frames (`0x55a3c0 in ??`) produce unstable hashes. Symbolize first with `llvm-symbolizer` or `addr2line`.
- Inlined functions may appear or disappear depending on optimization level. Hash at `-O0` or accept some collision at higher levels.
- Strip the file:line from the hash input — use only function names. Line numbers shift with unrelated edits.

---

## 4. Severity Classification

| Category | Severity | CVSS-like | Examples |
|---|---|---|---|
| Exploitable memory write | **Critical** | 9.0-10.0 | Heap buffer overflow (write), stack buffer overflow, format string write |
| Exploitable memory read | **High** | 7.0-8.9 | Out-of-bounds read leaking secrets, info disclosure via uninit memory |
| DoS / deterministic crash | **Medium** | 4.0-6.9 | Null deref, assertion failure, division by zero, uncaught panic |
| Logic bug (wrong output) | **Medium-Low** | 3.0-5.9 | Incorrect computation, state corruption without crash |
| Timeout | **Low** | 1.0-2.9 | Algorithmic complexity, regex backtracking |
| OOM | **Low** | 1.0-2.9 | Unbounded allocation from crafted input |

Promote severity by one level if the code runs on untrusted input in a network-facing service. Demote if the code is only reachable locally or in test harnesses.

---

## 5. Exploitability Assessment

Quick heuristics — no full exploit development required:

| Bug Class | Likely Exploitable? | Reasoning |
|---|---|---|
| Heap buffer overflow (write) | **Yes** | Attacker controls heap metadata; leads to arbitrary write |
| Stack buffer overflow (write) | **Yes** | Overwrites return address or saved frame pointer |
| Use-after-free | **Yes** | Attacker can reclaim freed memory with controlled content |
| Double free | **Yes** | Corrupts allocator metadata |
| Null pointer dereference | **Usually no** | Crashes process (DoS) but page zero is typically unmapped |
| Integer overflow | **Depends** | Exploitable if it controls an allocation size or array index |
| Uninitialized memory read | **Sometimes** | Can leak secrets (keys, ASLR pointers) |
| Stack overflow (deep recursion) | **Rarely** | Usually just DoS; exploitation requires specific stack layout |

### GDB/LLDB Quick Commands

```bash
# Reproduce under GDB with the crashing input
gdb -batch -ex run -ex bt -ex 'info registers' -ex quit --args ./target crash_input.bin

# Check if the crash PC is in a write instruction
gdb -batch -ex run -ex 'x/i $pc' --args ./target crash_input.bin

# LLDB equivalent
lldb -b -o run -o bt -o 'register read' -o quit -- ./target crash_input.bin
```

Key indicators:
- **`$pc` points to a `mov [reg], ...` instruction** — write primitive, likely exploitable.
- **`$pc` points to a `mov reg, [reg]` instruction** — read primitive, severity depends on what is being read.
- **Crash in `malloc`/`free` internals** — heap metadata corruption, high exploitability.
- **`$rip` or `$pc` is a controlled value** — attacker controls execution flow, critical.

---

## 6. Auto-Filing to Issue Trackers

### GitHub Actions Script

```yaml
# .github/workflows/fuzz-triage.yml
name: Fuzz Crash Triage
on:
  workflow_dispatch:
    inputs:
      crash_dir:
        description: 'Path to crash artifacts'
        required: true

jobs:
  file-issues:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Process crashes
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          for crash in ${{ inputs.crash_dir }}/*; do
            HASH=$(./scripts/stack-hash.sh "$crash")
            # Skip if issue with this hash already exists
            if gh issue list --label "fuzz-crash" --search "$HASH" --json number | jq -e 'length > 0' > /dev/null 2>&1; then
              echo "Duplicate: $HASH"
              continue
            fi
            SANITIZER=$(grep -oP '(?<=SUMMARY: )\w+' "$crash" || echo "unknown")
            SIZE=$(wc -c < "${crash%.report}.input" 2>/dev/null || echo "N/A")
            SUMMARY_LINE=$(grep 'SUMMARY:' "$crash" | head -1)
            FUNC=$(grep -oP '(?<=in )\S+' "$crash" | head -1 || echo "unknown")
            gh issue create \
              --title "Fuzz: ${SANITIZER} in ${FUNC} [${HASH}]" \
              --label "fuzz-crash,security" \
              --body "$(cat <<INNEREOF
          ## Crash Report

          **Stack hash:** \`${HASH}\`
          **Sanitizer:** ${SANITIZER}
          **Input size:** ${SIZE} bytes
          **Summary:** ${SUMMARY_LINE}

          ### Stack Trace
          \`\`\`
          $(head -30 "$crash")
          \`\`\`

          ### Reproduction
          \`\`\`bash
          # Download the crash input from CI artifacts
          # Run: ./target/fuzz/target_name crash_input.bin
          \`\`\`

          ### Triage Checklist
          - [ ] Minimized
          - [ ] Severity assigned
          - [ ] Root-caused
          - [ ] Fix merged
          - [ ] Regression test added
          INNEREOF
          )"
          done
```

---

## 7. Crash Bucketing Strategies

| Strategy | Granularity | Pros | Cons |
|---|---|---|---|
| **Function name** (crash site only) | Coarse | Simple, stable across builds | Collapses different bugs in same function |
| **Stack hash (top-5)** | Medium | Good default, catches most dups | Misses bugs that manifest at different depths |
| **Stack hash (top-7)** | Fine | Separates distinct call paths | Over-splits; more manual merging needed |
| **Sanitizer type** | Very coarse | Good for dashboards/metrics | Useless for dedup |
| **Code location (file:line)** | Fine | Precise | Fragile; line shifts break grouping |

**Recommended approach:** Stack hash (top-5) as the primary key, then manual review within each bucket to assess severity and confirm they are truly the same root cause. Use sanitizer type as a secondary grouping for reporting.

---

## 8. Minimization Best Practices

### Tool Commands

```bash
# Rust (cargo-fuzz wraps libFuzzer)
cargo fuzz tmin target_name artifacts/crash-input-abc123

# libFuzzer native
./fuzz_target -minimize_crash=1 -exact_artifact_path=minimized.bin crash_input.bin

# AFL++
afl-tmin -i crash_input.bin -o minimized.bin -- ./target @@
```

### Size targets

- **Ideal:** Under 100 bytes. Most parser bugs minimize to 10-50 bytes.
- **Acceptable:** Under 1 KB. If stuck here, the bug likely depends on structural features (valid headers, checksums).
- **Suspicious:** Over 10 KB after minimization. Likely non-determinism or a bug that requires specific large-scale structure.

### When minimization gets stuck

- **Non-determinism** — The crash only reproduces sometimes. Pin CPU affinity (`taskset -c 0`), disable ASLR (`setarch $(uname -m) -R`), seed the PRNG. If still flaky, save the smallest input that reproduces >80% of the time.
- **Checksums/magic bytes** — The input must pass validation before reaching the buggy code. Use structure-aware minimization or write a custom minimizer that preserves the checksum.
- **Multiple dependencies** — The crash requires specific byte sequences at multiple offsets. Try libFuzzer's `-minimize_crash=1` with `-runs=100000` for more attempts.

---

## 9. Regression Test Patterns

### Rust

```rust
#[test]
fn regression_heap_overflow_parser_a1b2c3() {
    let data = include_bytes!("../crashes/heap-overflow-a1b2c3.bin");
    // Should not panic or trigger sanitizer
    let _ = parse_input(data);
}
```

Place crash inputs in `tests/crashes/` or `fuzz/regression/`. Name them by bug class and stack hash.

### Go

```go
func TestRegressionHeapOverflow_a1b2c3(t *testing.T) {
    data, err := os.ReadFile("testdata/crashes/heap-overflow-a1b2c3.bin")
    if err != nil {
        t.Fatal(err)
    }
    // Should not panic
    _ = ParseInput(data)
}
```

Go 1.18+ native fuzzing also supports `testdata/fuzz/FuzzTarget/` for seed corpora.

### Python

```python
def test_regression_overflow_a1b2c3():
    data = (Path(__file__).parent / "crashes" / "overflow-a1b2c3.bin").read_bytes()
    # Should not raise
    parse_input(data)
```

### C/C++

```c
// test_regressions.c
static const uint8_t crash_a1b2c3[] = {0x00, 0x41, 0xff, 0x0a, 0x02};

void test_regression_heap_overflow_a1b2c3(void) {
    // Should not trigger sanitizer
    parse_input(crash_a1b2c3, sizeof(crash_a1b2c3));
}
```

For small inputs, embed as byte arrays. For larger inputs (>~200 bytes), store as files and load at test time.

### Naming Convention

```
test_regression_{bugclass}_{stackhash_first6}
```

Examples: `test_regression_heap_overflow_a1b2c3`, `test_regression_uaf_f7e8d9`, `test_regression_intoverflow_3c4d5e`.

---

## 10. When NOT to Investigate

Not every crash deserves a deep dive. Save time by recognizing low-value findings:

**OOM from unbounded input size** — If the fuzzer triggers OOM by feeding a 500 MB input to a function that allocates proportionally, the fix is an input size guard, not an allocator rewrite. Add `if input.len() > MAX_INPUT_SIZE { return; }` to the harness and the production code, then move on.

**Timeout from algorithmic complexity** — A 100 MB input causing a 60-second parse is not a security bug unless the input is small (under 1 KB) and the time is still large. For large-input timeouts, add size limits. For small-input timeouts, investigate — it may be catastrophic backtracking (regex) or quadratic behavior.

**Stack overflow from deep recursion** — Recursive descent parsers will stack-overflow on deeply nested input (e.g., 10,000 nested JSON arrays). The fix is a depth counter, not a code rewrite. This is a known limitation, not a vulnerability, unless the depth limit is unreasonably shallow.

**ASan false positives in safe Rust** — Pure safe Rust cannot have memory safety bugs (barring compiler bugs). If ASan fires on safe-only Rust code, check for C dependencies linked via FFI (`-sys` crates). If none exist, it is almost certainly a false positive from ASan instrumenting the Rust allocator. Verify by running with `ASAN_OPTIONS=detect_odr_violation=0` and checking if the issue persists.

**Crashes in test-only code** — If the crash is in test scaffolding, mock objects, or harness setup — not in production code paths — it is a test bug, not a product bug. Fix the test, but do not file a security issue.

**Duplicate with different input** — After deduplication (Section 3), if a new crash hashes to an existing known issue, add the new input to the corpus for coverage but do not open a new ticket. Update the existing ticket with the new reproduction case only if it is smaller or simpler.

---

## See Also

- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — "Can't reproduce crash" and other triage blockers
- [CI-FUZZING.md](CI-FUZZING.md) — Auto-filing crashes to issue trackers from CI
- [SANITIZERS.md](SANITIZERS.md) — Sanitizer-specific report formats and configuration
