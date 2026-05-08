# Fuzzing Quality Validators

Checklists and an automated script to verify fuzzing infrastructure correctness.

## 1. Harness Quality Validators (7 checks)

### 1.1 Input Size Bound

```bash
grep -qE 'if.*(len|size|length).*>.*return' fuzz/fuzz_targets/*.rs && echo PASS || echo FAIL
```
Caps: parsers 4-64 KB, crypto 1-4 KB, protocol 16-256 KB.

### 1.2 Exec/s Benchmark

```bash
timeout 30 cargo fuzz run <target> -- -max_total_time=30 2>&1 | tail -1
```
| Target type | Min exec/s |
|---|---|
| Parser / deserializer | 1 000 |
| Crypto primitive | 5 000 |
| State machine | 500 |
| Network protocol (mocked I/O) | 200 |

Below threshold? Profile with `perf record`, cut allocations, pre-allocate buffers.

### 1.3 Coverage Delta

```bash
cargo fuzz coverage <target>
cargo cov -- show fuzz/coverage/<target>/ --format=text | grep -A2 "target_fn"
# Must cover >5% of target function lines after a 5-minute run
```
Stuck? Add dictionary tokens, improve seeds, inspect unreachable branches.

### 1.4 Seed Corpus Non-Empty

```bash
[ $(ls fuzz/corpus/<target>/ 2>/dev/null | wc -l) -ge 5 ] && echo PASS || echo FAIL
```
Need at minimum: minimal valid, maximal valid, edge cases (empty, all-zeros), one real-world sample.

### 1.5 Sanitizer Verification

```bash
grep -qE 'RUSTFLAGS.*-Zsanitizer=(address|memory)' .github/workflows/*fuzz* && echo PASS || echo FAIL
```
Rust nightly: `RUSTFLAGS="-Zsanitizer=address"`. C/C++: `-fsanitize=address,undefined`.

### 1.6 Regression Test Conversion

Every crash artifact must have a corresponding unit test.
```bash
artifacts=$(ls fuzz/artifacts/<target>/ 2>/dev/null | wc -l)
regressions=$(grep -rl "crash-\|oom-\|timeout-" tests/ 2>/dev/null | wc -l)
[ "$regressions" -ge "$artifacts" ] && echo PASS || echo "FAIL: $((artifacts-regressions)) uncovered"
```

### 1.7 Determinism Check

Same artifact, 10 runs, all must crash:
```bash
failures=0
for i in $(seq 1 10); do
  cargo fuzz run <target> "$artifact" -- -runs=1 2>&1 | grep -q SUMMARY || failures=$((failures+1))
done
[ "$failures" -eq 0 ] && echo PASS || echo "FAIL: reproduced $((10-failures))/10"
```

## 2. Infrastructure Quality Validators (3 checks)

### 2.1 CI Pipeline

Both PR (short, ~5 min) and nightly (long, hours) fuzzing workflows must exist.
```bash
grep -qrl 'max_total_time' .github/workflows/ && echo "PR fuzzing: PASS" || echo FAIL
grep -qrl 'schedule:' .github/workflows/*fuzz* && echo "Nightly: PASS" || echo FAIL
```

### 2.2 Corpus Persistence

Minimized corpus must be committed to git or stored in CI cache:
```bash
[ $(git ls-files fuzz/corpus/ | wc -l) -ge 5 ] && echo "PASS: git" \
  || (grep -q 'cache.*fuzz/corpus' .github/workflows/*fuzz* && echo "PASS: CI cache" || echo FAIL)
```

### 2.3 Dictionary Present

Structured-format targets (JSON, protobuf, XML, ASN.1) require dictionaries:
```bash
structured=$(grep -rlE 'json|proto|xml|asn1' fuzz/fuzz_targets/ 2>/dev/null | wc -l)
dicts=$(ls fuzz/dictionaries/*.dict 2>/dev/null | wc -l)
[ "$structured" -eq 0 ] && echo SKIP || ([ "$dicts" -ge "$structured" ] && echo PASS || echo FAIL)
```

## 3. Depth Validators (3 checks)

### 3.1 Oracle Quality

| Level | Pattern | Catches |
|---|---|---|
| Shallow | `let _ = parse(data);` | Panics/crashes only |
| Adequate | `assert_eq!(decode(encode(x)), x)` | Logic bugs via round-trip |
| Excellent | Differential oracle / shadow model | Semantic divergence |

```bash
grep -c 'let _ =' fuzz/fuzz_targets/*.rs | awk -F: '{s+=$2} END {print "Shallow:", s}'
grep -cE 'assert|unwrap_err' fuzz/fuzz_targets/*.rs | awk -F: '{s+=$2} END {print "With assertions:", s}'
```

### 3.2 Multi-Sanitizer Campaigns

For `unsafe` or concurrent code, run separate campaigns:
- **ASan** -- memory errors (use-after-free, overflow)
- **MSan** -- uninitialized reads (C/C++ FFI)
- **TSan** -- data races in concurrent code

Verify separate CI jobs exist for each relevant sanitizer.

### 3.3 Plateau Response

Evidence of coverage monitoring and strategy adjustment when growth stalls: coverage trend logs, corpus minimization commits, dictionary updates, or harness refactoring after flat periods.

## 4. Automated Validation Script

Save as `scripts/validate-fuzz-harness.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:?Usage: $0 <fuzz-target-name>}"
PASS=0; FAIL=0

check() {
  local name="$1"; shift
  if eval "$@" >/dev/null 2>&1; then
    echo "  [PASS] $name"; PASS=$((PASS+1))
  else
    echo "  [FAIL] $name"; FAIL=$((FAIL+1))
  fi
}

echo "=== Validating: $TARGET ==="
check "Input size bound" \
  "grep -qE 'if.*(len|size|length).*>.*return' fuzz/fuzz_targets/${TARGET}.rs"
check "Seed corpus >= 5" \
  "[ \$(ls fuzz/corpus/$TARGET/ 2>/dev/null | wc -l) -ge 5 ]"
check "Sanitizer in CI" \
  "grep -qrE 'sanitizer=(address|memory)' .github/workflows/*fuzz*"
check "Dictionary (if structured)" \
  "! grep -qE 'json|proto|xml' fuzz/fuzz_targets/${TARGET}.rs || [ -f fuzz/dictionaries/${TARGET}.dict ]"
check "Regression tests >= artifacts" \
  "[ \$(ls fuzz/artifacts/$TARGET/ 2>/dev/null | wc -l) -le \$(grep -rl 'crash-' tests/ 2>/dev/null | wc -l) ]"
check "PR fuzzing in CI" "grep -qrl 'max_total_time' .github/workflows/"
check "Nightly fuzzing in CI" "grep -qrl 'schedule:' .github/workflows/*fuzz*"

echo ""; echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
```

Run all targets: `for t in fuzz/fuzz_targets/*.rs; do scripts/validate-fuzz-harness.sh "$(basename "$t" .rs)"; done`

---

## See Also

- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — If validation fails, common fixes are here
- [CI-FUZZING.md](CI-FUZZING.md) — CI pipeline setup for automated fuzzing
- [PERFORMANCE-TUNING.md](PERFORMANCE-TUNING.md) — If exec/s validation fails, optimization guide
