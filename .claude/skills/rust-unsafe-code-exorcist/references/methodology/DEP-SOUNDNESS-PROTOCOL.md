# DEP-SOUNDNESS-PROTOCOL.md — Auditing the Dependency Soundness Surface

A clean local audit is undone by an unsound dependency. This file is the protocol for the `dependency-soundness` mode.

---

## The transitive-soundness principle

If your `pub fn foo` calls `dep::bar` which internally calls `unsafe { ... }` with a contract that depends on a precondition you don't enforce, then `foo` is unsound — even though `foo` itself contains no `unsafe`.

The audit's job in dependency-soundness mode:

1. **Enumerate every dep with `cargo +nightly geiger > 0`** — these have unsafe to investigate.
2. **For each, determine which dep API surfaces our project reaches.**
3. **For each reached surface, determine whether the dep's internal unsafe is reachable via that surface.**
4. **For each reachable unsafe, determine the proof obligation.**
5. **For each proof obligation, verify our project enforces it (or document the obligation in our docs).**

---

## Step 1 — enumerate

```bash
./scripts/cargo-tree-soundness.sh <project> <audit-dir>
```

Output: `<audit-dir>/phase1/cargo-tree-soundness.md` listing every dep with non-zero geiger count.

**Triage by count.** Deps with hundreds of unsafe items (e.g., `libc`, `windows-sys`, `core-foundation`) are inherently FFI-heavy; the dep IS its unsafe surface. Deps with 1-10 unsafe items are usually performance-motivated wrappers; investigate per-item.

---

## Step 2 — reachability

For each dep, walk OUR project's rustdoc JSON forward through calls to dep's public API. The audit needs to know which dep APIs are reachable from our public API.

Tools:

- `rustdoc-call-graph-extract.sh` — extracts our project's pub→callee relationships.
- `cargo-call-stack` — analyzes the call stack of a function (if available).
- Manual inspection — for projects without good static-analysis tooling.

Output: `<audit-dir>/audit/synthesis/dep-soundness.md`:

```markdown
## libc (geiger: 213)

### APIs we reach
- `libc::open` — called from `frankenfs::open_raw_safe`
- `libc::close` — called from `frankenfs::OwnedFd::Drop`
- `libc::read` — called from `frankenfs::FdReader::read`

### Proof obligations we inherit
- `libc::open`: path is null-terminated (we enforce via `&CStr`)
- `libc::close`: fd is valid AND not previously closed (we enforce via `OwnedFd` ownership)
- `libc::read`: buf has length >= count; fd is open for reading (we enforce via type)

### Soundness verdict
- All proof obligations enforced by our wrapper layer.
- No bypass paths in our pub API.
```

Or:

```markdown
## some_crate (geiger: 8)

### APIs we reach
- `some_crate::HotPath::new` — called from `myproj::Foo::new`
- `some_crate::HotPath::process` — called from `myproj::Foo::frob`

### Proof obligations we inherit
- `HotPath::new`: caller must ensure the input slice is at least 16 bytes (some_crate docs § Safety)
- `HotPath::process`: caller must ensure no concurrent access (some_crate uses non-thread-safe internal state)

### Soundness verdict
- `HotPath::new` precondition: NOT enforced — our `Foo::new` accepts any-length slice and forwards. UNSOUND.
- `HotPath::process` precondition: PARTIALLY enforced — our `Foo` is `!Sync` via `PhantomData<*mut ()>`. OK.

### Action
- (C) refactor: add precondition enforcement in `Foo::new`.
- File upstream issue against `some_crate` to clarify the Safety docs (currently buried).
```

---

## Step 3 — mitigation per dep

Per reached-unsafe dep, the options are A/B/C/D:

### A — WRAP

Author a stricter abstraction in our project that enforces the dep's proof obligation before forwarding. The dep's internal unsafe stays; our wrapper makes it sound.

```rust
// Original — UNSOUND (forwards arbitrary slices to a function expecting >=16 bytes)
pub fn frob(buf: &[u8]) -> Result<u32, Error> {
    Ok(some_crate::HotPath::new(buf).process())
}

// Wrapped — sound
pub fn frob(buf: &[u8]) -> Result<u32, Error> {
    if buf.len() < 16 { return Err(Error::TooShort); }
    Ok(some_crate::HotPath::new(buf).process())
}
```

### B — REPLACE

Switch the dep for one with less / audited unsafe.

| Common swaps |
|--------------|
| `lazy_static` → `std::sync::OnceLock` / `once_cell` (still has unsafe internally but smaller surface) |
| `parking_lot` → `std::sync::Mutex` (slower; trade-off) |
| `crossbeam-channel` → `flume` (smaller dep tree) |
| `nix` → `rustix` (audited, no_std-friendly) |
| `mio` → direct `std::os::fd` (for simple cases) |
| custom `unsafe { transmute }` → `zerocopy` / `bytemuck` |

Document the swap in `dep-soundness.md`; benchmark to confirm acceptable perf.

### C — UPSTREAM

File an issue / PR against the dep with the soundness concern. Continue using the dep in the meantime, but document the open question in our docs.

Use `assets/upstream-issue-template.md` to draft the issue.

### D — JUSTIFY

If the obligation transfers fully to our docs (i.e., our users must understand it), write the (A)-style justification in our crate's docs:

```rust
//! # Safety considerations
//!
//! This crate uses `some_crate::HotPath` internally. The `HotPath::process` function
//! is non-thread-safe; our `Foo` is `!Sync` to enforce single-thread usage. If you
//! need cross-thread access, wrap in `Arc<Mutex<Foo>>`.
```

---

## Step 4 — special cases

### Macro-generated dep code

`zerocopy-derive`, `bytemuck-derive`, `pin-project-lite` — these emit unsafe at YOUR call site. Treat them per [40-MACRO-GENERATED-UNSAFE.md](../patterns/40-MACRO-GENERATED-UNSAFE.md): cluster by macro source, audit each cluster once.

### Procedurally-generated bindings

`bindgen`-emitted `extern "C"` blocks are huge in geiger count but inherit soundness from the C library. The audit treats them as a single cluster per `60-FFI-PATTERNS.md`.

### Build-script unsafe

Some crates have `build.rs` files with unsafe code. Build scripts run at compile time, NOT at runtime — they can't violate user runtime soundness. Still worth a quick audit (a malicious `build.rs` could exfiltrate; a buggy one could miscompile).

### Hidden deps via cargo features

A dep might pull in transitively-unsafe code only when a feature is enabled. Audit `cargo tree --all-features` to surface these.

---

## Soundness-surface freezing

After a `dependency-soundness` audit completes, lock the dep versions:

```toml
[dependencies]
some_crate = "=1.2.3"   # exact version; audit valid for this version only
```

When a new version of `some_crate` ships, the audit needs to be re-run. Add a CI check that fails if the version changes without a corresponding audit-summary update.

```bash
# .github/workflows/dep-soundness-gate.yml
- name: Check audit summary mentions current dep versions
  run: |
    grep -q "some_crate = \"$(cargo metadata --format-version 1 | jq -r '.packages[] | select(.name=="some_crate") | .version')\"" \
      audit/synthesis/dep-soundness.md
```

---

## Cargo-vet integration

[cargo-vet](https://github.com/mozilla/cargo-vet) lets multiple users share "I've audited dep version X.Y.Z" assertions. After our `dependency-soundness` audit, publish the audit results to cargo-vet:

```bash
cargo vet certify some_crate 1.2.3
# fills in the certification with our audit notes
```

Downstream users of OUR crate benefit from our audit (cargo-vet computes transitive trust).

The audit summary line for dep-soundness mode:

```
dep-soundness audit completed:
- 24 deps with geiger > 0
- 18 reach our pub API
- 4 WRAP refactors (in our crate)
- 1 REPLACE (some_crate -> another_crate)
- 2 UPSTREAM issues filed
- 11 JUSTIFY entries in our docs
- 0 reachable-unsound paths remaining
```

---

## Acceptance signal

A dep-soundness audit passes when:

1. Every dep with `geiger > 0` is enumerated.
2. Every reached-unsafe is classified into WRAP / REPLACE / UPSTREAM / JUSTIFY.
3. For each WRAP: the wrapper is implemented and tested.
4. For each REPLACE: the replacement is benchmarked and integrated.
5. For each UPSTREAM: the issue / PR is filed and linked.
6. For each JUSTIFY: the doc entry is in our crate's `lib.rs` or `README.md`.
7. The CI matrix locks dep versions to the audited ones.
8. cargo-vet certifications (optional but recommended) are published.
