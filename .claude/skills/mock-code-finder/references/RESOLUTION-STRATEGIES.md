# Resolution Strategies

## Decision Tree: How to Resolve Each Finding

```
Finding identified
│
├─ Is it an explicit TODO/FIXME with description?
│  └─ YES → Implement what the comment describes, remove the comment
│
├─ Is it todo!()/unimplemented!()/NotImplementedError?
│  └─ YES → Trace callers to understand expected behavior, implement fully
│
├─ Is it a function returning a hardcoded value?
│  ├─ Validation function returning `true` → Implement real validation logic
│  ├─ Fetch function returning `{}` → Implement real data fetching
│  └─ Conversion returning default → Implement real conversion
│
├─ Is it an empty error handler?
│  └─ YES → Implement proper error propagation or recovery
│
├─ Is it a `pass`/empty body in production code?
│  ├─ Abstract method → May be intentional (verify)
│  └─ Concrete method → Implement real logic
│
└─ Is it a suspiciously short function?
   ├─ Getter/accessor → Likely fine (false positive)
   ├─ Builder pattern → Likely fine (false positive)
   └─ Business logic → Needs real implementation
```

---

## Resolution with Beads (br)

### Creating the Bead Structure

For each stub/mock found, create a bead with enough detail that a future agent can implement it without any additional context:

```bash
# Parent epic
br create \
  --title="Resolve all mocks/stubs/placeholders" \
  --type=epic \
  --priority=1 \
  --comment="Systematic resolution of N stubs/mocks/placeholders identified by mock-code-finder scan on $(date +%Y-%m-%d). See individual child tasks for details."

# Child task (one per finding)
br create \
  --title="Implement real logic for validate_input() in src/parser.rs:42" \
  --type=task \
  --priority=2 \
  --comment="CURRENT STATE: fn validate_input() -> bool { true }
PROBLEM: Always returns true — no actual validation occurs.
CALLERS: Called from process_request() at src/handler.rs:88. Callers depend on this returning false for malformed input.
REQUIRED IMPLEMENTATION:
  1. Parse input according to schema defined in src/schema.rs
  2. Validate required fields present
  3. Validate field types match schema
  4. Return false with error details on failure
FILES TO MODIFY: src/parser.rs
TESTS TO ADD: tests/parser_validation_test.rs — test valid input (returns true), missing fields (returns false), wrong types (returns false), edge cases (empty input, unicode, max-length)"

# Add dependency
br dep add <task-id> <depends-on-id>
```

### Bead Comment Template

Each bead comment should include ALL of these sections:

```
CURRENT STATE: [What the stub currently does — exact code]
PROBLEM: [Why this is insufficient]
CALLERS: [Who calls this function, what they expect]
REQUIRED IMPLEMENTATION: [Numbered steps for the real implementation]
FILES TO MODIFY: [Exact paths]
TESTS TO ADD: [What tests, what they assert]
DEPENDENCIES: [Other stubs that must be resolved first, if any]
CONSIDERATIONS: [Edge cases, performance, compatibility notes]
```

### Validation with bv

After creating all beads:

```bash
# Check dependency graph health
bv --robot-triage | jq '.quick_ref'

# Find circular dependencies (must fix!)
bv --robot-insights | jq '.Cycles'

# Find quick wins (stubs with no dependencies, easy to resolve)
bv --robot-triage | jq '.quick_wins'

# Optimal execution order
bv --robot-plan | jq '.plan.tracks'
```

---

## Resolution with TODO Tracking (No Beads)

For smaller lists or projects without beads, maintain a markdown checklist:

```markdown
## Mock/Stub Resolution Plan

### 1. src/parser.rs:42 — validate_input() always returns true
- [ ] Implement real validation against schema
- [ ] Add test: valid input returns true
- [ ] Add test: missing fields returns false
- [ ] Add test: wrong types returns false
- [ ] Remove stub comment

### 2. src/handler.rs:100 — process_error() is empty
- [ ] Implement error logging
- [ ] Implement error recovery / retry
- [ ] Add test: errors are logged
- [ ] Add test: transient errors trigger retry
```

---

## Post-Resolution Verification

After resolving all stubs:

```bash
# Re-run the full detection scan
rg -n "TODO|FIXME|HACK|XXX|STUB|PLACEHOLDER|MOCK|DUMMY|FAKE" \
  --type-not json --type-not lock -g '!target/' -g '!node_modules/' .

# Re-run ast-grep short-function scan
ast-grep run -l Rust -p 'fn $NAME($$$) -> $RET { todo!() }' --json

# Run test suite
cargo test --all  # or npm test, pytest, etc.

# Confirm zero remaining stubs
echo "Target: 0 findings on rescan"
```

---

## Common Pitfalls in Resolution

| Pitfall | Why It's Bad | Do Instead |
|---------|-------------|------------|
| Replace stub with slightly better stub | Still not real code | Implement fully or defer explicitly |
| Skip tests for resolved stubs | No proof it works | Every resolution needs at least one test |
| Resolve in random order | May hit dependency issues | Use `bv --robot-plan` or resolve leaves first |
| Oversimplify the implementation | Loses functionality | Trace callers to understand full requirements |
| Forget to remove TODO comments | Future scans find stale markers | Delete the marker when the work is done |
| Create beads without enough detail | Future agent can't implement independently | Use the bead comment template above |
