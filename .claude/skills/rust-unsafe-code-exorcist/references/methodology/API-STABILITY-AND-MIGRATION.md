# API-STABILITY-AND-MIGRATION.md — Refactoring Without Breaking Downstream

Many (C) refactors are tempting only if they change the public API. The audit's discipline: API changes are documented, justified, and accompanied by a migration path.

This file is the protocol for the API-stability dimension of every (C) plan.

---

## Three classes of API change

| Class | Impact on downstream | Audit treatment |
|-------|----------------------|-----------------|
| **non-breaking** (additive) | New methods, new constructors; existing signatures unchanged | OK; just bump minor version |
| **breaking-but-trivial** | Renaming, parameter reordering, simple type changes | Acceptable with `#[deprecated]` shim for one release |
| **breaking-and-deep** | Changing ownership model, return type semantics, error variant set | Requires a migration guide AND major version bump |

The plan's "Risk + API change" field reads one of these classes. The reviewer in Phase 10 maintainer-empathy reads this and decides whether to land.

---

## Detecting API changes

The skill's `subagents/api-stability-reviewer.md` runs after every (C) plan is drafted. It:

1. **Diffs the proposed safe rewrite against the current `pub` surface.**
2. **Classifies each change** (non-breaking / breaking-trivial / breaking-deep).
3. **Cross-references rustdoc JSON** — every `pub` item that changes is enumerated.
4. **Flags hidden API changes:** changing the `Send`/`Sync` impl of a `pub` type is a breaking change even if the signature looks identical; changing a `pub` type's `#[repr(...)]` is a breaking change for FFI consumers.

### Subtle breaking changes that aren't obvious

- `pub struct Foo(Vec<u8>)` → `pub struct Foo(Box<[u8]>)` — looks the same; different sized-type assumptions on the consumer side, different alloc behavior.
- `pub fn frob(x: u32) -> Result<u32, Error>` → `pub fn frob(x: u32) -> Result<u32, Error2>` where `Error2: From<Error>` — additive on the receive side but the variant set may have changed.
- `impl Send for Foo` → no longer `Send` — breaking; downstream cross-thread uses fail.
- `impl Drop for Foo` added — breaking; downstream code that relied on field-level moves now hits the drop check.
- `#[repr(C)]` removed — breaking for FFI consumers.
- A previously-private field becomes effectively visible via a new pub method — increases the API's surface area.

---

## Migration shims

For `breaking-but-trivial` changes, the audit can author a `#[deprecated]` shim:

```rust
// Old API — keep for one release with #[deprecated]
#[deprecated(since = "1.5.0", note = "use Foo::new_with_capacity instead")]
pub fn new(size: usize) -> Foo {
    Foo::new_with_capacity(size)
}

// New API
pub fn new_with_capacity(capacity: usize) -> Foo {
    Foo { buf: vec![0; capacity] }
}
```

The shim allows downstream consumers to update at their own pace. After one release cycle, the shim is removed (track via a follow-up bead in the next major version).

---

## Migration guides

For `breaking-and-deep` changes, the audit produces a `MIGRATION.md` at the project root (or appended to `CHANGELOG.md`). Per-API:

```markdown
## v2.0 migration guide

### `Foo::process`

**Before (v1.x):**
```rust
let result: Result<u32, Error> = foo.process(&buf);
```

**After (v2.0):**
```rust
let result: Result<u32, ProcessError> = foo.process(&buf);
// ProcessError implements From<Error>; existing `?` propagation works.
```

**Rationale.** v2.0 separates `Error` (catastrophic) from `ProcessError` (recoverable),
which lets us mark some paths as `#[must_use]`.

**Action.** No code change required if you use `?`; explicit error matching needs the
new variant set.
```

The migration guide MUST cover every breaking change in the release. Reviewers will look for missing entries.

---

## Per-class plan additions

Each (C) plan's "Risk + API change" section gets:

### non-breaking

```
API change: non-breaking (additive only)
Migration path: N/A — downstream code requires no changes
Minor version bump: yes (v1.X → v1.X+1)
```

### breaking-but-trivial

```
API change: breaking-but-trivial
Affected items:
  - `Foo::new` → renamed `Foo::with_capacity`
Migration shim: `#[deprecated]` Foo::new wrapping Foo::with_capacity; one-release retention
Migration path: search-and-replace `Foo::new(` → `Foo::with_capacity(`
Major version bump: usually no; depends on project's semver discipline
```

### breaking-and-deep

```
API change: breaking-and-deep
Affected items:
  - `Foo::process` return type changed (Error → ProcessError)
  - `Foo: Send` no longer holds (removed unsafe impl Send)
Migration shim: not applicable
Migration path: see MIGRATION.md § Foo::process; consumers using cross-thread Foo
                must wrap in `Arc<Mutex<Foo>>`
Major version bump: yes (v1.X → v2.0)
```

---

## Tools for verifying API stability

### cargo-public-api

```bash
cargo install cargo-public-api
cargo public-api --diff-git-checkouts v1.0.0 HEAD
```

Diff of every `pub` item between two refs. The orchestrator runs this against the active checkout to verify the API-change classification.

### cargo-semver-checks

```bash
cargo install cargo-semver-checks
cargo semver-checks check-release
```

Detects whether the project's planned version bump is sufficient for the API changes. If you're cutting a minor release but actually broke API, semver-checks fails.

### rustdoc JSON diff

The skill's `rustdoc-call-graph-extract.sh` produces JSON. Diff before/after:

```bash
jq -S . <audit-dir>/phase1/<crate>__rustdoc.json > before.json
# ... apply refactor in active checkout ...
cargo +nightly rustdoc -- -Z unstable-options --output-format json
jq -S . target/doc/<crate>.json > after.json
diff before.json after.json
```

---

## Phase 10 maintainer-empathy: API-change questions

When the reviewer reads the audit, they should be able to answer:

1. **What `pub` items changed?** Listed in the plan; verified by `cargo-public-api`.
2. **What's the migration path for each?** Listed in the plan; in `MIGRATION.md` if breaking-deep.
3. **What version bump is required?** Verified by `cargo-semver-checks`.
4. **Are there shims for breaking-trivial?** Yes / no.
5. **Are downstream consumers known and notified?** For widely-used crates — check the dependents list.

If any of these is unclear, the reviewer flags it.

---

## Anti-patterns

- **"It's a private project; we don't care about API stability."** Even private projects have downstream consumers — other modules, other repos at the same company. API discipline pays off.
- **Breaking API "while we're at it" without migration shim.** Forces every consumer to update simultaneously; high friction.
- **Renaming `pub` types via `pub use` re-export without `#[deprecated]`.** Consumers see two names; ambiguity grows.
- **Removing `Send` / `Sync` silently.** Cross-thread consumers compile-fail with no migration path.
- **Adding `#[non_exhaustive]` retrospectively to a pub enum.** Breaks every `match` on the variant set.

---

## Acceptance signal

A (C) plan's API-stability dimension passes when:

1. The plan's "Risk + API change" section is filled in with the correct class.
2. Affected `pub` items are enumerated.
3. Migration path is documented (per-class — none / shim / guide).
4. The version bump is consistent with the change class.
5. `cargo-public-api` and `cargo-semver-checks` results match the plan's classification.
6. If breaking-deep: a `MIGRATION.md` section exists.

If any of these is missing, the (C) plan is not exit-ready. Phase 5 reopens.
