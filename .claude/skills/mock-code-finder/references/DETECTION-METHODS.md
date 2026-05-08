# Detection Methods — Full Reference

## Method 1: Keyword Search (ripgrep)

### Universal Keywords

```bash
# Explicit markers — highest confidence
rg -n "TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER|MOCK|DUMMY|FAKE|TEMP\b|TEMPORARY" \
  --type-not json --type-not lock \
  -g '!target/' -g '!node_modules/' -g '!.git/' -g '!vendor/' -g '!dist/' .

# Weaker signals — need manual review
rg -n "WORKAROUND|KLUDGE|REFACTOR|REVISIT|LATER|WIP|INCOMPLETE|SKELETON|BOILERPLATE" \
  --type-not json --type-not lock \
  -g '!target/' -g '!node_modules/' -g '!.git/' .
```

### Language-Specific Unimplemented Patterns

```bash
# Rust
rg -n 'todo!\(|unimplemented!\(|panic!\("not (yet )?implemented|panic!\("TODO' --type rust .

# Python
rg -n 'raise NotImplementedError|pass\s*$|\.\.\.(\s*#.*)?$' --type py .

# TypeScript / JavaScript
rg -n 'throw new Error\(.*(not implemented|TODO|stub)|return undefined\b' --type ts --type js .

# Go
rg -n 'panic\("not implemented|panic\("TODO|// TODO|return nil, nil\b' --type go .

# Java
rg -n 'throw new UnsupportedOperationException|throw new RuntimeException\("TODO|// TODO' --type java .
```

### Suspicious Return Values

```bash
# Functions returning hardcoded trivial values (likely placeholders)
rg -n 'return true$|return false$|return 0$|return -1$|return ""$|return \[\]$|return \{\}$|return None$|return nil$' \
  --type rust --type py --type ts --type js --type go .

# Rust-specific: Ok(()) in functions that should return real data
rg -n 'Ok\(Default::default\(\)\)|Ok\(vec!\[\]\)|Ok\(String::new\(\)\)|Ok\(HashMap::new\(\)\)' --type rust .
```

---

## Method 2: AST Structural Analysis (ast-grep)

### Finding Suspiciously Short Functions

The insight: a function with only 1-2 statements is suspicious if it's supposed to do real work. Use ast-grep to find these structurally.

```bash
# Rust — single-statement functions (likely stubs)
ast-grep run -l Rust -p 'fn $NAME($$$ARGS) { $SINGLE }' --json

# Rust — functions with only todo!/unimplemented!
ast-grep run -l Rust -p 'fn $NAME($$$ARGS) -> $RET { todo!() }' --json
ast-grep run -l Rust -p 'fn $NAME($$$ARGS) -> $RET { unimplemented!() }' --json

# Rust — empty impl blocks
ast-grep run -l Rust -p 'impl $TYPE { }' --json

# Python — pass-only functions
ast-grep run -l Python -p 'def $NAME($$$ARGS):
    pass' --json

# Python — ellipsis-only functions (protocol stubs)
ast-grep run -l Python -p 'def $NAME($$$ARGS):
    ...' --json

# TypeScript — empty/trivial functions
ast-grep run -l TypeScript -p 'function $NAME($$$ARGS) { }' --json
ast-grep run -l TypeScript -p 'function $NAME($$$ARGS) { return; }' --json
ast-grep run -l TypeScript -p '($$$ARGS) => { }' --json

# Go — empty functions
ast-grep run -l Go -p 'func $NAME($$$ARGS) $RET { }' --json
```

### Measuring Function Length

Use ast-grep JSON output to extract function bodies and measure line count:

```bash
# Extract all function definitions with their ranges
ast-grep run -l Rust -p 'fn $NAME($$$) $$$BODY' --json | \
  jq '[.[] | {name: .metaVariables.NAME.text, file: .file, lines: (.range.end.line - .range.start.line)}] | sort_by(.lines) | .[:20]'
```

Functions under 3 lines in a non-trivial codebase deserve scrutiny.

---

## Method 3: Cross-Reference Analysis

### Finding Dead / Uncalled Functions

```bash
# List all function definitions
rg -n "^(pub )?(fn|def|function|func) \w+" --type rust --type py --type ts --type go . > /tmp/fn_defs.txt

# For each function name, check if it's called anywhere else
# (manual step — read the function name, grep for call sites)
```

### Finding Functions With No Tests

```bash
# List functions in src/
rg -on "fn (\w+)" --type rust src/ | sed 's/.*fn //' | sort -u > /tmp/src_fns.txt

# List functions mentioned in tests/
rg -on "\w+" --type rust tests/ | sort -u > /tmp/test_refs.txt

# Functions in src not referenced in tests
comm -23 /tmp/src_fns.txt /tmp/test_refs.txt
```

---

## Method 4: Heuristic Patterns

### Comment-Heavy, Logic-Light

Functions that are mostly comments suggesting what should happen but contain minimal actual logic:

```bash
# Find functions where comment lines outnumber code lines
# (manual analysis — read the function, count comments vs code)
rg -n "// TODO|# TODO|// PLACEHOLDER|# PLACEHOLDER" --type rust --type py --type ts .
```

### Configuration Stubs

```bash
# Default configs that look too simple
rg -n "default.*\{|Default for" --type rust .
rg -n "DEFAULT_.*=|config\[.default.\]" --type py .
```

### Error Handling Stubs

```bash
# Swallowed errors (catch-and-ignore)
rg -n "catch.*\{\s*\}|except.*pass|\.unwrap_or_default\(\)|_ =>" --type rust --type py --type ts .

# Empty error arms in match/switch
ast-grep run -l Rust -p 'Err(_) => {}' --json
ast-grep run -l Rust -p 'Err(_) => Ok(())' --json
```

---

## Method 5: Behavioral Detection (From Real Session Mining)

Discovered across sessions in midas-edge, rch, ntm, mcp-agent-mail-rust, frankensearch:

### Simulated Work (sleep/delay as placeholder for real operations)

```bash
# sleep() used to fake real work (SSH, network calls, processing)
rg -n "sleep\(|thread::sleep|time\.sleep|tokio::time::sleep|setTimeout" \
  --type rust --type py --type ts --type go . | \
  grep -vi "test\|spec\|bench\|retry\|backoff\|rate.limit\|throttle"

# Functions that log "simulating" or "fake" or "mock"
rg -n "simulat|faking|mocking|pretend" --type rust --type py --type ts --type go .
```

### Hardcoded Scores/Metrics (Should Be Computed)

```bash
# Hardcoded numeric scores that should be calculated from data
rg -n "score\s*[:=]\s*[0-9]|rarity.*[:=]\s*[0-9]|count.*[:=]\s*0[^.]|dau.*[:=]\s*0" \
  --type rust --type py --type ts .

# Always-zero metrics (DAU, MRR, counters that never increment)
rg -n "always.*0|= 0.*//|= 0.*#.*todo\|stub\|placeholder\|hack" \
  --type rust --type py --type ts .
```

### API Route Stubs (Return 501/Not Implemented)

```bash
# HTTP endpoints that return 501 or "Not Implemented"
rg -n "501|Not Implemented|not.yet.implemented|NextResponse.*501" \
  --type ts --type py --type rust --type go .
```

### Caching/Storage Stubs (Functions That Skip Real I/O)

```bash
# Functions that should persist but don't (return false, skip, no-op)
rg -n "cacheToR2.*return false|checkCache.*return null|return false.*//.*cache|return null.*//.*cache" \
  --type ts --type rust --type py .

# "warm" config disabled (feature not wired up)
rg -n "warm.*false|enable.*false|config.*false.*//.*todo\|stub\|later\|disabled" \
  --type ts --type rust --type py .
```

### Divergent Code Paths (Real Logic Exists Elsewhere)

This is the subtlest form — the function is a stub, but a *different* code path already does the real work:

```bash
# Find functions with same/similar names in different files
# Example from midas-edge: batch-enrichment.ts returned redFlagsDetected=0
# but the API route transcript-sentiment/route.ts actually counted them
rg -n "redFlags|red_flags" --type ts --type rust --type py .
# If two files have the same concept but different implementations, one is likely a stub
```

### Stub Tests (Test Files That Are Themselves Stubs)

```bash
# Test files with very few assertions (likely placeholder tests)
rg -c "assert|expect|should" tests/ --type rust --type ts --type py | \
  sort -t: -k2 -n | head -20
# Files with < 5 assertions are suspicious
```

---

## Triage: Real Stub vs False Positive

| Signal | Likely Real Stub | Likely False Positive |
|--------|-----------------|----------------------|
| `todo!()` / `unimplemented!()` | Always real | — |
| `pass` / empty body | In production code | In abstract base class / protocol |
| `return true` | In validation function | In feature flag check |
| Short function (1-2 lines) | In complex module | Legitimate accessor/getter |
| `// TODO` | With description of missing work | Old resolved TODO left behind |
| Hardcoded return | In function that should compute | In test fixture / constant |

**Rule of thumb:** Trace callers. If the function's callers depend on real output, it's a stub. If callers only need the type signature (trait impl, protocol), it may be intentional.
