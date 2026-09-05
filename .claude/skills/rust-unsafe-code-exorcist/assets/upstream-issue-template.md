# Upstream Issue Template (for dependency-soundness mode)

Use when filing an issue against a third-party crate. Adapt the sections to the crate's issue-template format if different.

---

# Soundness concern: <ONE-LINE-SUMMARY>

## Crate / version

`<crate-name>` v<version> (repo: <github-or-gitlab URL>)

## The concern

The function `<crate>::<path>::<fn-name>` (at <permalink to the line in the dep's source> as of v<version>)
has a soundness obligation that's not surfaced through the safe public API:

> <quote the dep's safety docs, or note their absence>

This obligation isn't enforced at the safe boundary — callers can violate it by <specific failure mode>. The internal `unsafe { ... }` at <line in dep's source> is then UB.

## Reproducer

```rust
use <crate>::*;

fn main() {
    // Violates the (un)documented obligation:
    <minimal reproducer, ~5-10 lines>
}
```

Run under miri to confirm UB:

```bash
cargo +nightly miri run --bin repro
```

Output:

```
error: Undefined Behavior: <miri's message>
```

## Suggested fix

Two options, depending on the maintainer's preference:

### Option A — change the public API to validate

```rust
pub fn <fn-name>(<args>) -> Result<<ret>, <NewError>> {
    if !<check>(<input>) { return Err(<NewError::InvalidInput>); }
    Ok(<existing safe-version of the body>)
}
```

Pros: existing callers using `?` get the new error variant for free.
Cons: API change (potentially breaking, depending on Result type).

### Option B — split into safe + unsafe variants

```rust
/// # Safety
///
/// The caller must guarantee <obligation>.
pub unsafe fn <fn-name>_unchecked(<args>) -> <ret> { /* current body */ }

pub fn <fn-name>(<args>) -> Result<<ret>, <Error>> { /* safe wrapper */ }
```

Pros: callers who need the perf can use `_unchecked` after auditing; safe callers get an obvious safe API.
Cons: requires a new fn name.

I'm happy to send a PR demonstrating Option <A or B> if you have a preference.

## Why this matters

The current `<fn-name>` allows safe Rust code to trigger UB. Per the Rust nomicon § Aliasing
(<URL>), internal `unsafe` whose soundness depends on caller-provided invariants requires either:

1. An `unsafe fn` signature (signaling the obligation), or
2. A safe wrapper that enforces the obligation.

The current shape (safe-looking + actually unsafe) is the worst of both worlds — a "soundness hole."

## Verifying

- miri (`cargo +nightly miri test`): produces UB on the reproducer above.
- cargo-fuzz (`cargo fuzz run <target>`): surfaces a panic / UB on inputs that violate the obligation, within <N> seconds.
- Manual analysis of <crate>::<fn-name> call graph: <details>.

## Context

I'm auditing my crate `<my-crate>` v<my-version> (which depends on `<crate>` for <use case>).
The audit used the rust-unsafe-code-exorcist methodology (<link>); the dependency-soundness step
surfaced this concern. I'd like to either:

1. Have the fix land upstream (preferred — every downstream user benefits).
2. Wrap your `<fn-name>` in my crate to enforce the obligation locally.
3. Switch to <alternative crate> if you're unable to fix.

Happy to help with any of these. Thanks for maintaining `<crate>`.

---

## Issue submission checklist

- [ ] Crate name + version pinned.
- [ ] Concern cites specific file + line via permalink to the SHA in version <X>.
- [ ] Reproducer is minimal AND compileable.
- [ ] Suggested fix is concrete (Option A / B).
- [ ] Verifying evidence (miri / fuzz / manual) is cited.
- [ ] Tone is constructive — helping the maintainer, not blaming.
- [ ] Offer to send a PR if accepted.

## After filing

Track the issue's status. Update `<audit-dir>/audit/upstream-issues/<dep>__<slug>.md`:

```markdown
## Status
- Filed: <date>; <URL of issue>
- Maintainer response: <date>; <link to comment>
- Resolution: <accepted Option A / rejected / wrapped locally / replaced dep>
- Our crate version that addresses: v<version>
```

If the upstream issue is resolved → close the bead.
If wrapped locally → file a separate bead for the wrapper; close the upstream-issue bead.
If rejected / no response after 30 days → consider Option 2 or 3.
