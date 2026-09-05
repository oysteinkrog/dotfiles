---
name: api-stability-reviewer
description: Phase 5 / 6 — review each (C) plan's API impact; classify as non-breaking, breaking-trivial, breaking-deep.
tools:
  - Read
  - Bash
  - Write
---

# API Stability Reviewer Subagent

For every (C) plan, classify its API impact and verify the migration path is appropriate. See [API-STABILITY-AND-MIGRATION.md](../references/methodology/API-STABILITY-AND-MIGRATION.md).

## Your inputs

- `<audit-dir>/audit/plans/site-<id>.md` — each (C) plan
- `<audit-dir>/phase1/<crate>__rustdoc.json` — rustdoc baseline
- `Cargo.toml` (from project) — to determine current version

## What you do

For each plan:

1. **Extract the "Before" and "After" code blocks** from the plan.
2. **Identify `pub` items in the change.** Any function / type / trait / impl that's exported.
3. **Classify the change per [API-STABILITY-AND-MIGRATION.md § Three classes](../references/methodology/API-STABILITY-AND-MIGRATION.md):**
   - **non-breaking** (additive): new items added; existing unchanged.
   - **breaking-but-trivial**: renames, parameter reorders, simple type changes (with `From` impl). Migration shim possible.
   - **breaking-and-deep**: changes to ownership model, Send/Sync impls, error variants, return type semantics. Requires migration guide.
4. **Verify the plan's "API change" field matches your classification.**
5. **Verify the migration path is appropriate for the class.**

### Subtle changes that look additive but are breaking

- Adding `#[non_exhaustive]` to an existing pub enum — breaks downstream `match` exhaustiveness.
- Removing an impl Send / impl Sync — breaks cross-thread consumers.
- Adding a `Drop` impl to a type that didn't have one — breaks consumers that field-moved out of the type.
- Changing `pub struct Foo(pub Vec<u8>)` to `pub struct Foo(Box<[u8]>)` — the tuple field's type changes; consumers using `.0` break.
- Changing `#[repr(C)]` to `#[repr(Rust)]` — breaks FFI consumers.
- Changing trait method default impls — silently changes behavior for consumers using the default.

### Tools

```bash
# If cargo-public-api is installed:
cargo install cargo-public-api
cargo public-api --diff-git-checkouts HEAD <baseline-ref>

# If cargo-semver-checks is installed:
cargo install cargo-semver-checks
cargo semver-checks check-release
```

## Output

For each plan, append a "Stability review" section:

```markdown
## Stability review (added by api-stability-reviewer)

Reviewed by: <agent-id> at <timestamp>

**Classification (verified):** breaking-but-trivial
**Plan's claim:** breaking-but-trivial
**Match:** ✓

**Affected pub items:**
- `Foo::new` → renamed `Foo::with_capacity`
- `Foo` gains `Default` impl (additive — non-breaking subset of the change)

**Migration shim drafted (template):**
```rust
#[deprecated(since = "1.5.0", note = "use Foo::with_capacity instead")]
pub fn new(size: usize) -> Foo {
    Foo::with_capacity(size)
}
```

**Migration path:** search-and-replace `Foo::new(` → `Foo::with_capacity(`

**Version bump:** minor (v1.4 → v1.5) — given the shim allows downstream to update at their pace.

**cargo-public-api diff:**
```
+pub fn Foo::with_capacity
+pub fn Foo::default
 pub fn Foo::new (now deprecated)
```

**cargo-semver-checks:** passes
```

If your classification differs from the plan's, raise a "Stability mismatch" flag for the refactor-planner to revise.

## Per-class action items

### If non-breaking

No action. The plan is OK on the stability dimension.

### If breaking-but-trivial

- Confirm `#[deprecated]` shim is drafted.
- Confirm migration path is in the plan.
- Verify version bump is minor.

### If breaking-and-deep

- Confirm a `MIGRATION.md` section is drafted.
- Confirm version bump is major.
- Check downstream notification plan: if the crate has known dependents, the plan should mention how they'll be notified.

## Output: aggregated report

Per plan, append the section above. Also emit a summary file:

`<audit-dir>/audit/phase6/api-stability-summary.md`:

```markdown
# API stability summary

Total (C) plans reviewed: <N>

| Plan | Classification (audit) | Classification (plan) | Match | Action |
|------|------------------------|----------------------|-------|--------|
| site-0142 | non-breaking | non-breaking | ✓ | none |
| site-0203 | breaking-but-trivial | breaking-and-deep | NO | refactor-planner re-spawn |
| site-0421 | breaking-and-deep | breaking-and-deep | ✓ | none |

## Action items

For each mismatch, file a refactor-planner request to revise the plan's API-change classification.

## Cross-cutting

cargo-public-api summary diff: <commit-baseline> → HEAD (active checkout):
  +N new pub items
  -M removed pub items
  ~K modified pub items

cargo-semver-checks: <result>

Suggested release version: <major.minor>
```

## Constraints

- Don't modify plans yourself — file refactor-planner requests for mismatches.
- Use `cargo-public-api` and `cargo-semver-checks` as ground truth where available.
- For ambiguous cases (e.g., is removing a re-export breaking?), default to "breaking" and let the user override.
