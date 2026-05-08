# Corpus Engineering Guide

> The corpus is the fuzzer's memory. A well-engineered corpus reaches deep code paths faster. A bloated corpus wastes cycles.

## Seed Corpus Construction

### Sources for Seeds

| Source | Best For | Example |
|--------|---------|---------|
| Existing test suite | Known-valid inputs | Copy QA test files |
| Real-world data | Production-realistic | Anonymized user uploads |
| Spec examples | RFC/standard compliance | RFC test vectors |
| Manual crafting | Boundary conditions | Empty, max-size, null-filled |
| Generated | Format-specific | Grammar-based generators |

### Minimum Seed Corpus

Every fuzz target needs at minimum:

```bash
mkdir -p fuzz/corpus/my_target

# 1. Empty input
printf '' > fuzz/corpus/my_target/empty

# 2. Minimal valid input
echo '{}' > fuzz/corpus/my_target/minimal_valid

# 3. Typical valid input
echo '{"name":"test","value":42}' > fuzz/corpus/my_target/typical

# 4. Maximum-size valid input (near your size limit)
python3 -c "print('{\"data\":' + '\"x\"*50000' + '}')" > fuzz/corpus/my_target/large

# 5. Boundary bytes
printf '\x00' > fuzz/corpus/my_target/null_byte
printf '\xff' > fuzz/corpus/my_target/high_byte
printf '\x00\xff\x00\xff' > fuzz/corpus/my_target/alternating

# 6. Previously-found crash inputs (regression)
# cp artifacts/crash-* fuzz/corpus/my_target/
```

### Dictionaries

Provide format-specific tokens to help the fuzzer past magic-number checks:

```
# fuzz/dicts/json.dict
kw1="\""
kw2=":"
kw3=","
kw4="{"
kw5="}"
kw6="["
kw7="]"
kw8="null"
kw9="true"
kw10="false"
```

```
# fuzz/dicts/http.dict
kw1="GET "
kw2="POST "
kw3="HTTP/1.1"
kw4="Content-Type"
kw5="\\r\\n"
kw6="Content-Length"
```

```bash
# Use dictionary
cargo fuzz run my_target -- -dict=fuzz/dicts/json.dict
```

---

## Corpus Maintenance

### Minimization (CRITICAL — do regularly)

```bash
# Minimize corpus: keep only inputs that contribute unique coverage
cargo fuzz cmin my_target

# Before: 50,000 inputs, 2GB
# After:  500 inputs, 50MB — same coverage, 100x faster fuzzing
```

**Rule:** Minimize weekly. A 100K-entry corpus is SLOWER than a 500-entry corpus with identical coverage because the fuzzer wastes time re-executing redundant inputs.

### Crash Minimization

```bash
# Minimize a specific crashing input to smallest reproducer
cargo fuzz tmin my_target artifacts/my_target/crash-abc123

# Before: 4,096 bytes
# After:  23 bytes — same crash, easy to debug
```

**Always tmin before debugging.** A 4KB crash input is unreadable. A 23-byte input often makes the bug obvious.

### Merge (Combining Corpora)

```bash
# Merge corpus from another fuzzing campaign
cargo fuzz cmin my_target -- additional_corpus/

# libFuzzer merge mode
./my_fuzzer -merge=1 ./merged_corpus ./corpus_a ./corpus_b
```

---

## Coverage Tracking

### Generate Coverage Report

```bash
# Rust
cargo fuzz coverage my_target
# Produces coverage data in fuzz/coverage/my_target/

# View with llvm-cov
llvm-cov show target/x86_64-unknown-linux-gnu/coverage/my_target \
    -instr-profile=fuzz/coverage/my_target/coverage.profdata \
    -show-line-counts-or-regions

# HTML report
llvm-cov show ... -format=html > coverage.html
```

### Interpreting libFuzzer Output

```
#1234   NEW    cov: 1150 ft: 3200 corp: 250/50Kb lim: 1000 exec/s: 5000 rss: 100Mb
```

| Field | Meaning | Action If Stalling |
|-------|---------|-------------------|
| `cov` | Covered edges/blocks | Add dictionaries, improve seeds |
| `ft` | Features (edges + counters + value profiles) | Enable `-use_value_profile=1` |
| `corp` | Corpus size / total bytes | Run `cmin` if too large |
| `lim` | Max input length tried so far | Increase `-max_len` if needed |
| `exec/s` | Executions per second | Target ≥1000. <100 = harness too slow |
| `rss` | Resident set size (memory) | Watch for leaks; `-rss_limit_mb` |

### Plateau Detection

If `cov` and `ft` stop growing:
1. Check coverage report: which code is NOT reached?
2. Add seed inputs that exercise unreached code
3. Add dictionary entries for magic values the fuzzer can't guess
4. Consider structure-aware fuzzing (Arbitrary) for complex input formats
5. Consider custom mutators for compressed/encrypted formats

---

## Production Data Distillation

Real-world inputs find bugs that synthetic seeds miss. Use production data to bootstrap your corpus.

### Capturing Production Inputs

```bash
# Log request bodies to files (add temporarily to your API handler)
# WARNING: PII scrubbing is MANDATORY before using as corpus

# From server logs (extract request bodies)
grep 'POST /api/parse' access.log | jq -r '.body' > raw_inputs/

# From pcap captures (extract payloads)
tshark -r capture.pcap -T fields -e data.data | xxd -r -p > raw_inputs/payload_001
```

### PII Scrubbing (Mandatory)

Before using production data as corpus:
1. **Replace** names, emails, phone numbers with deterministic fakes
2. **Hash** user IDs and session tokens
3. **Strip** auth headers, cookies, API keys
4. **Verify** no PII remains: `grep -rE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' corpus/`

### Replay-Based Corpus Construction

```bash
# Record HTTP traffic for a session
mitmproxy --mode regular -w session.flow

# Extract request bodies as corpus entries
mitmdump -r session.flow -s extract_bodies.py

# extract_bodies.py
# from mitmproxy import io
# for flow in io.FlowReader(open("session.flow","rb")).stream():
#     if flow.request.content:
#         with open(f"corpus/{hash(flow.request.content)[:8]}", "wb") as f:
#             f.write(flow.request.content)
```

---

## Corpus Sharing Across Campaigns

Different sanitizer campaigns and fuzzer engines can share corpora to accelerate discovery.

```bash
# Merge corpus from ASan campaign into MSan campaign
cargo fuzz cmin my_target_msan -- path/to/asan_corpus/

# Share between libFuzzer and AFL++ (same format — raw files)
cp -r fuzz/corpus/my_target/* afl_findings/queue/

# After AFL++ campaign, import discoveries back
cargo fuzz cmin my_target -- afl_findings/queue/
```

**Rule:** Always minimize after merging. Different engines find different inputs but many will cover the same edges.

---

## When to Stop Fuzzing

### Diminishing Returns Analysis

Monitor `cov:` and `ft:` in libFuzzer output. If neither grows for:
- **30 minutes**: Change strategy (add dictionary, switch to structure-aware)
- **4 hours**: Try different engine (AFL++ CMPLOG, hybrid symbolic)
- **24 hours**: Coverage is saturated for this approach. Options:
  1. Add more seed inputs targeting uncovered code (use `llvm-cov show`)
  2. Write custom mutators for format-specific barriers
  3. Try hybrid symbolic execution (SymCC, QSYM)
  4. Declare current coverage acceptable and move to next target

### Coverage-Over-Time Graphing

```bash
# libFuzzer: parse stats from output
grep '^#' fuzz_output.log | awk '{print $1, $4}' > coverage_over_time.csv

# AFL++: use afl-plot
afl-plot findings/ plot_output/
# Opens HTML with exec/s, paths found, crashes over time
```

### The 80/20 Rule

Typically, 80% of reachable coverage is found in the first 20% of fuzzing time. After that, each additional hour of fuzzing has rapidly decreasing marginal returns. **Invest in breadth (more targets) before depth (longer runs on existing targets).**

---

## See Also

- [DICTIONARIES.md](DICTIONARIES.md) — Format-specific tokens that accelerate corpus exploration
- [PERFORMANCE-TUNING.md](PERFORMANCE-TUNING.md) — Corpus size directly affects exec/s
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — "Corpus too large" and other corpus issues
- [CUSTOM-MUTATORS.md](CUSTOM-MUTATORS.md) — When standard mutation can't reach deep code, custom mutators help
