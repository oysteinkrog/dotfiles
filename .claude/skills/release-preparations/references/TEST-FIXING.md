# Test Fixing Patterns for Release Preparations

## The Philosophy

Tests fail during release prep for one reason: **the code evolved but the tests didn't keep up.** Multi-agent workflows mean many hands touch the code between releases, and test updates often lag behind. This is normal — fix it systematically.

## Diagnostic Flow

```
cargo test --workspace 2>&1 | tee /tmp/test-output.txt
grep 'FAILED\|error\[' /tmp/test-output.txt | head -30
```

### Step 1: Classify Each Failure

```bash
# Extract just the failing test names
grep '---- .* FAILED' /tmp/test-output.txt | sed 's/---- //' | sed 's/ FAILED//'
```

For each failure, determine the category:

**Category A: Struct/Enum Field Mismatch** (most common)
- Error: `missing field \`new_field\``
- Error: `no field \`removed_field\` on type`
- Cause: Fields added/removed from structs but test constructors not updated
- Fix: Add missing fields with sensible defaults, remove references to deleted fields

**Category B: Changed Return Type or Signature**
- Error: `expected X, found Y`
- Error: `this function takes N arguments but M were supplied`
- Cause: Function signature changed, callers in tests not updated
- Fix: Update test call sites to match new signatures

**Category C: Assertion Drift**
- Error: `assertion failed: expected X, got Y`
- Cause: Output format or behavior intentionally changed
- Fix: Update expected values in assertions (verify the new behavior is correct first!)

**Category D: Real Bug**
- The test correctly catches broken behavior
- Fix: Fix the production code, NOT the test

**Category E: Import/Module Errors**
- Error: `cannot find module`, `unresolved import`
- Cause: Module restructuring, moved files
- Fix: Update import paths in tests

**Category F: Compilation Errors in Tests**
- Error: `cannot find type`, `method not found`
- Cause: Type renamed, method moved or removed
- Fix: Update type/method references

## Fix Recipes

### Recipe 1: Missing Struct Fields (Category A)

```rust
// Find the struct definition
// rg "pub struct TheName" --type rust

// Check what fields exist now
// Read the struct definition

// Add missing fields to test constructors with defaults:
// - bool: false
// - Option<T>: None
// - Vec<T>: vec![]
// - String: String::new() or "".into()
// - numeric: 0
// - Duration: Duration::from_secs(0)
```

### Recipe 2: Changed Function Signature (Category B)

```bash
# Find the current function signature
rg "pub fn function_name" --type rust -A 5

# Find all test call sites
rg "function_name\(" tests/ --type rust -n
rg "function_name\(" src/ --type rust -g '*test*' -n

# Update each call site to match new signature
```

### Recipe 3: Assertion Value Drift (Category C)

```bash
# Run the specific failing test with output
cargo test --workspace -- test_name --nocapture 2>&1

# Compare expected vs actual
# If actual is the CORRECT new behavior, update the assertion
# If actual is WRONG, you have a Category D (real bug)
```

### Recipe 4: Bulk Field Addition

When a struct gains many new fields and multiple tests break:

```bash
# Find all test files that construct the struct
rg "StructName\s*\{" tests/ --type rust -l
rg "StructName\s*\{" src/ --type rust -g '*test*' -l

# For each file, add the missing fields
# Use a consistent set of defaults across all tests
```

## Test Fixing Order

1. **Fix compilation errors first** (Categories E, F) — nothing runs until these are fixed
2. **Fix struct mismatches** (Category A) — usually the bulk of failures
3. **Fix signature changes** (Category B) — update call sites
4. **Fix assertion drift** (Category C) — verify new behavior is correct
5. **Fix real bugs** (Category D) — fix the code, not the test
6. **Re-run full suite** — must be clean before proceeding

## Efficiency Tips

- **Run targeted tests first**: `cargo test -- failing_test_name` for fast iteration
- **Fix in batches**: If 10 tests fail because of the same new struct field, fix all 10 at once
- **Read the diff**: `git log --oneline --diff-filter=M -- src/types.rs` shows what changed since last release
- **Use subagents**: For large test suites with many failures, dispatch parallel fix agents
- **Don't over-fix**: Pre-existing failures unrelated to your release can be documented and skipped

## The Golden Rule

**After all fixes, the final `cargo test --workspace` must exit 0.** No exceptions for release preparation.
