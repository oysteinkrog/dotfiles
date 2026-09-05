# Rust Deep Dive — Per-Construct Harmonization, Fingerprinting, and Cherry-Pick Gotchas

[LANGUAGE-PROFILES.md § Rust](LANGUAGE-PROFILES.md#rust) covers the basic fingerprint patterns and same-signature heuristic. This file goes deeper into Rust-specific harmonization decisions: which constructs compose additively vs. exclusively, which carry latent risk, and how the harmonization-planner should treat each. It pairs with [TYPESCRIPT-DEEP-DIVE.md](TYPESCRIPT-DEEP-DIVE.md) — the same kind of deep dive for TS/JS.

> **Why a separate reference?** Rust has more *construct-level* harmonization rules than most languages (trait impls, cfg attributes, lifetime parameters, unsafe blocks, macro definitions). Each one has subtle composition semantics. A single harmonization-planner subagent reading [HARMONIZATION.md § 4](HARMONIZATION.md) can produce decent syntheses, but a Rust-aware planner using *this file* will catch construct-level issues a generic synthesis would miss.

The skill activates this reference when `project_profile.json:archetypes` includes `cargo-workspace` or any branch fingerprint contains Rust constructs. Comprehensive and Council modes spawn a `language-specialist-rust` subagent that reads this file in full.

---

## 1. `Cargo.toml` Conflicts

The most common Rust collision: every branch may modify `Cargo.toml`.

### 1.1 Dependency additions are additive

```toml
# branch A: adds tracing
[dependencies]
tracing = "0.1"

# branch B: adds anyhow
[dependencies]
anyhow = "1.0"

# synthesis: both
[dependencies]
tracing = "0.1"
anyhow = "1.0"
```

Trivial union; the harmonization-planner adopts both.

### 1.2 Version bumps need careful merging

```toml
# branch A: bumps serde
serde = "1.0.180"

# branch B: bumps serde to a different version
serde = "1.0.197"

# synthesis: pick the highest semver
serde = "1.0.197"
```

The harmonization-planner picks the highest version across branches. Tiebreaker: most-recent commit date.

If branches diverge on the *major* version (`1.0` vs. `2.0`), surface to user — major-version bumps usually require code changes elsewhere.

### 1.3 Feature flag composition

```toml
# branch A
serde = { version = "1.0", features = ["derive"] }

# branch B
serde = { version = "1.0", features = ["rc"] }

# synthesis: union of features
serde = { version = "1.0", features = ["derive", "rc"] }
```

Always additive. Never *remove* a feature one variant has — features are only used when called.

### 1.4 Refactor of existing entries

If branch A reorganizes the `[dependencies]` block (alphabetizing, grouping by category) AND branch B adds a new dep, the harmonization-planner must integrate both:

1. Apply A's reorganization first.
2. Apply B's new dep into the reorganized structure.

If A's reorganization removes a dep that exists on canonical, that's a `divergent-refactor` — surface to user.

---

## 2. `Cargo.lock` Conflicts

`Cargo.lock` is regenerated from `Cargo.toml` + the lockfile resolver. Branches that **only** modify `Cargo.lock` are usually `garbage` — the lockfile delta will be regenerated post-merge.

```bash
# Detection: branch's diff is only Cargo.lock
git diff --name-only <merge-base>..<branch>
# If output is exactly "Cargo.lock", verdict: garbage (regenerate)
```

When a branch modifies `Cargo.toml` AND `Cargo.lock`, only the `Cargo.toml` matters; the planner discards the `Cargo.lock` diff and lets the post-merge `cargo build` regenerate it.

### 2.1 The "stale lockfile after harmonization" gotcha

After Phase 8 lands harmonized `Cargo.toml` changes (combining deps from multiple branches), `Cargo.lock` becomes stale. Phase 8's gates catch this — `cargo build --workspace` regenerates the lockfile, and the apply succeeds with a fresh lockfile commit:

```bash
# scripts/apply-keeper.sh fragment for harmonized synthesis on Cargo.toml
git add Cargo.toml
cargo build --workspace            # regenerates Cargo.lock
git add Cargo.lock                 # adds the regenerated lock
git commit -m "..."
```

The skill never edits `Cargo.lock` by hand; it lets cargo do it.

---

## 3. `#[cfg(...)]` Attribute Conflicts

Two branches add different `cfg` gates to the same fn:

```rust
// branch A: gate on `feature = "tls"`
#[cfg(feature = "tls")]
fn handle(req: Request) -> Response { ... }

// branch B: gate on `target_os = "linux"`
#[cfg(target_os = "linux")]
fn handle(req: Request) -> Response { ... }
```

Synthesis options:

1. **Union (`any`)** — when both intents are wanted (most common):
   ```rust
   #[cfg(any(feature = "tls", target_os = "linux"))]
   fn handle(req: Request) -> Response { ... }
   ```
2. **Intersection (`all`)** — when both gates must be active:
   ```rust
   #[cfg(all(feature = "tls", target_os = "linux"))]
   fn handle(req: Request) -> Response { ... }
   ```
3. **Surface to user** — when intent is unclear.

Default: **surface to user**. Cfg gates encode build-time decisions; combining them automatically can produce builds that no agent intended. The harmonization plan asks: "Branch A says only when TLS feature is on; Branch B says only on Linux. Should the function be available when *either* condition holds, *both* must hold, or surface as divergent?"

---

## 4. `mod.rs` and Module Declarations

Branches that add new modules need their `mod foo;` line on the parent module:

```rust
// branch A adds src/api/mod.rs:
//   - file: src/api/handler.rs (new)
//   - line in src/api/mod.rs: + pub mod handler;

// branch B adds src/api/mod.rs:
//   - file: src/api/router.rs (new)
//   - line in src/api/mod.rs: + pub mod router;

// synthesis: both mod declarations
pub mod handler;     // from branch A
pub mod router;      // from branch B
```

Always additive. The harmonization-planner preserves all module declarations from all branches.

### 4.1 Edition-2018 vs. classical mod files

Rust 2018 makes `mod foo;` resolve `src/foo.rs` OR `src/foo/mod.rs`. If branch A creates `src/api.rs` and branch B creates `src/api/mod.rs`, that's a conflict:

```bash
# detection
[ -f src/api.rs ] && [ -d src/api ] && echo "EDITION-2018 MOD CONFLICT"
```

Surface to user — the project's convention should win, not whichever branch happens to be applied first.

---

## 5. `use` Statement Ordering

Rustfmt canonicalizes `use` statement ordering (alphabetical, grouped by std/extern/local). Diffs that are *only* reordering of `use` statements are `garbage` — rustfmt will re-canonicalize post-merge.

```bash
# The triage worker checks: is the file's ONLY change reordering of `use` lines?
git diff <merge-base>..<branch> -- <file> | \
  awk '/^[+-]use / {used=1} /^[+-][^use]/ {non_use=1} END {exit used && !non_use}'
# If only `use` lines changed, classify the hunk as `garbage`
```

The fingerprint extraction explicitly *ignores* `use` reordering for the purpose of determining novelty.

---

## 6. Trait Impls

Two branches add different methods to the same `impl` block:

```rust
// canonical
impl Handler {
    pub fn handle(&self) -> Response { ... }
}

// branch A
impl Handler {
    pub fn handle(&self) -> Response { ... }
    pub fn handle_async(&self) -> impl Future<Output = Response> { ... }
}

// branch B
impl Handler {
    pub fn handle(&self) -> Response { ... }
    pub fn handle_with_timeout(&self, t: Duration) -> Response { ... }
}

// synthesis: compose all methods
impl Handler {
    pub fn handle(&self) -> Response { ... }
    pub fn handle_async(&self) -> impl Future<Output = Response> { ... }
    pub fn handle_with_timeout(&self, t: Duration) -> Response { ... }
}
```

Additive composition unless the methods conflict (same name, different signatures). When two branches add a method with the same name and different signatures, that's a `divergent-refactor` — surface to user.

### 6.1 Trait derives

```rust
#[derive(Debug, Clone)]                            // branch A
#[derive(Debug, Clone, PartialEq)]                 // branch B
#[derive(Debug, Clone, PartialEq, Eq, Hash)]       // synthesis: union
```

Union the derive list. Watch for incompatible derives (rare): `Clone` is incompatible with `Copy` if the type has fields that don't implement `Copy`. Surface compile errors to the user.

### 6.2 Trait impl blocks for a foreign trait

```rust
// branch A
impl From<u32> for MyType { ... }

// branch B
impl From<i64> for MyType { ... }

// synthesis: both impls (different `From<T>` impls are different items)
impl From<u32> for MyType { ... }
impl From<i64> for MyType { ... }
```

Different `From<T>` impls don't conflict (orphan rule respected; foreign trait + local type).

### 6.3 Conflicting trait impls (same `From<T>`, different bodies)

```rust
// branch A
impl From<u32> for MyType {
    fn from(n: u32) -> Self { Self::from_u32_safe(n) }
}

// branch B
impl From<u32> for MyType {
    fn from(n: u32) -> Self { Self::Unchecked(n) }
}
```

Compiler error: conflicting impls. Surface to user; this is a `divergent-refactor`.

---

## 7. Lifetime Parameter Changes

Lifetime additions/changes are high-risk. If a branch changes:

```rust
// canonical
fn parse(s: &str) -> Token

// branch
fn parse<'a>(s: &'a str) -> Token<'a>
```

This is a structural change with cascading implications for callers. The synthesis can't simply adopt the new signature unless every call site is also updated.

**Default action:** surface to user as `divergent-refactor`. Lifetime additions are rarely safe to harmonize automatically.

If the user opts to adopt: the harmonization-planner must enumerate every call site of `parse()` on canonical and ensure they're compatible with the new lifetime. If any are not, lift the corresponding tests from the branch and verify they still pass with canonical's call sites.

---

## 8. `unsafe` Block Additions

`unsafe` blocks always get extra scrutiny. The harmonization-planner flags them for the user even on `superseded` verdicts:

```rust
// branch
unsafe fn raw_pointer_arithmetic(p: *const u8, off: usize) -> u8 {
    *p.add(off)
}
```

UBS (Ultimate Bug Scanner) warns; the per-apply gate runs UBS; flag for user even if the apply succeeds.

### 8.1 Composition of unsafe variants

If branch A and branch B both add `unsafe` blocks at the same location with different bodies, **never auto-compose**. Each `unsafe` block represents a manual safety contract; combining them blindly violates the contract.

```rust
// branch A
unsafe fn fast_copy(src: &[u8], dst: &mut [u8]) {
    std::ptr::copy_nonoverlapping(src.as_ptr(), dst.as_mut_ptr(), src.len());
}

// branch B
unsafe fn fast_copy(src: &[u8], dst: &mut [u8]) {
    debug_assert!(dst.len() >= src.len());
    std::ptr::copy(src.as_ptr(), dst.as_mut_ptr(), src.len());
}
```

Surface to user with both bodies; ask: "Branch A uses `copy_nonoverlapping` (faster, requires non-overlap); Branch B uses `copy` with debug_assert (safer but slower). Pick one or describe a third synthesis."

---

## 9. Test-Only Diffs (`#[cfg(test)]`)

Test code is usually additive. Two branches each adding tests under `#[cfg(test)] mod tests` compose by appending:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_a_thing() { ... }              // from branch A

    #[test]
    fn test_b_thing() { ... }              // from branch B
}
```

Conflicts only on test-name collisions (`test_handler_returns_ok` defined in two branches with different bodies). Resolve by giving each test a distinct name in the synthesis (`test_handler_returns_ok_path_a`, `test_handler_returns_ok_path_b`) — the harmonization-planner generates the rename and updates fixture references.

---

## 10. Workspace Member Additions

`Cargo.toml [workspace] members` is additive across branches:

```toml
# branch A
[workspace]
members = ["crates/api", "crates/db"]

# branch B
[workspace]
members = ["crates/api", "crates/web"]

# synthesis: union
[workspace]
members = ["crates/api", "crates/db", "crates/web"]
```

Watch for: a workspace member that's a NEW directory only one branch creates. The harmonization plan must lift the entire crate's source tree from the source branch, not just the workspace declaration.

---

## 11. Macros

`macro_rules!` definitions across branches need careful merging.

### 11.1 Disjoint macros (different names)

```rust
macro_rules! foo { ... }       // branch A
macro_rules! bar { ... }       // branch B

// synthesis: both
macro_rules! foo { ... }
macro_rules! bar { ... }
```

Trivial union.

### 11.2 Same-name macros, different bodies

```rust
macro_rules! validate {
    ($x:expr) => { /* A's body */ };
}

macro_rules! validate {
    ($x:expr) => { /* B's body */ };
}
```

Cannot have two `macro_rules!` with the same name in the same scope. Compile error. Surface to user as `divergent-refactor`.

### 11.3 Same-name macro, additive arms

```rust
// branch A
macro_rules! validate {
    ($x:expr) => { /* original arm */ };
}

// branch B
macro_rules! validate {
    ($x:expr) => { /* original arm */ };
    ($x:expr, $msg:literal) => { /* new arm with custom message */ };
}
```

If branch B's body is a strict superset of branch A's (same first arm + new arms), synthesis adopts B's body. If the first arms differ in body, surface to user.

### 11.4 Procedural macros (`#[proc_macro]`, `#[proc_macro_derive]`)

Procedural macros are crate-level; conflicts are rare (different crates). When two branches add proc macros to the same crate, follow the same rules as trait impls.

---

## 12. `build.rs` Modifications

`build.rs` is build-time code; changes here have higher blast radius than runtime code.

| Change type | Action |
|---|---|
| New env var read (`println!("cargo:rustc-env=...")`) | Additive; compose |
| New file generation (`std::fs::write(...)`) | Additive if generated paths are different; surface if same path |
| Dependency on a build-time crate | Additive; compose with `[build-dependencies]` |
| Logic change in existing build step | Surface to user; build.rs changes are rarely cleanly composable |

Default: **surface most build.rs changes to user**. Build-time code interacts with the project's CI in ways the harmonization-planner can't fully reason about.

---

## 13. `rustfmt.toml` and `clippy.toml`

Formatter / linter config files. Conflicts are usually `superseded` — canonical's config is authoritative.

```toml
# rustfmt.toml on canonical
edition = "2021"
max_width = 100

# branch's variant
edition = "2021"
max_width = 120
imports_granularity = "Crate"
```

Variants that *add* config keys: surface to user (the addition may be intentional but should match team conventions).
Variants that *change* canonical's config keys: surface to user (the change may be intentional but should match team conventions).
Variants that *remove* canonical's config keys: prefer canonical (don't drop config without explicit user OK).

---

## 14. Worked Example — `feature/redact-secrets` Synthesis on `logger.rs`

A concrete synthesis showing every Rust-specific composition rule applied at once. This is the canonical Rust example for the harmonization plan.

### 14.1 Variant matrix (excerpt)

```
file: src/util/logger.rs

variant                           | hunks                                                    | intent       | conf
----------------------------------|----------------------------------------------------------|--------------|-----
canonical                         | (baseline; pub fn log(level, msg))                       | base         | —
agent-cleanup-pass-3              | + null-arg guard at top                                  | defensive    | 0.92
feature/length-cap                | + length cap → 4 KiB on msg                              | defensive    | 0.94
feature/redact-secrets            | + redact_secrets(msg) before write + regex const         | defensive    | 0.91
feature/non-empty-newtype         | + NonEmptyStr<'a> wrapper; signature change              | type-narrow  | 0.78
feature/structured-tracing        | + tracing::Span::current() + #[instrument]               | refactor     | 0.83
feature/test-fixtures             | + test fixtures for each defensive case                  | test         | 0.96
```

### 14.2 Composition decisions

Per [HARMONIZATION.md § 4](HARMONIZATION.md):

1. **Defensive checks compose** — null-arg + length-cap + redact_secrets all survive.
2. **Type-narrowing requires call-site updates** — `feature/non-empty-newtype` changes `&str` to `NonEmptyStr<'a>`. Surface to user; the synthesis defaults to keeping `&str` (canonical's signature) and applying the null-check inside the body.
3. **Structured tracing is a refactor** — adopt as a wrapping pattern around the body.
4. **Tests lift additively** — all test fixtures from `feature/test-fixtures` plus tests from individual variants.
5. **Refactor + defensive composition** — apply defensive checks first (entry guards), then the refactored body (instrumented tracing).

### 14.3 Final synthesis (the actual Rust code)

```rust
//! Logger module — harmonized synthesis from 6 branches.
//!
//! Recovered defensive checks from agent-cleanup-pass-3, feature/length-cap,
//! feature/redact-secrets, plus structured tracing from feature/structured-tracing,
//! plus test fixtures from feature/test-fixtures. Type-narrowing from
//! feature/non-empty-newtype DEFERRED — surfaced to user as a follow-up.

use crate::level::Level;
use crate::error::LoggerError;
use tracing::instrument;
use std::sync::OnceLock;
use regex::Regex;

const MAX_LOG_MSG_BYTES: usize = 4096;                           // from feature/length-cap

// Compiled once at first use; from feature/redact-secrets
static REDACTION_RE: OnceLock<Regex> = OnceLock::new();

fn redaction_pattern() -> &'static Regex {
    REDACTION_RE.get_or_init(|| {
        Regex::new(r"\b(sk_live_\w+|api_key=\S+|Bearer \S+)\b")
            .expect("redaction regex is valid")
    })
}

fn redact_secrets(msg: &str) -> std::borrow::Cow<'_, str> {
    redaction_pattern().replace_all(msg, "[REDACTED]")
}

/// Log a message at the given level.
///
/// Defensive guards (in entry order, cheapest first):
///   1. Empty-message check (from agent-cleanup-pass-3)
///   2. Length cap to MAX_LOG_MSG_BYTES (from feature/length-cap)
///   3. Secret redaction (from feature/redact-secrets)
///
/// The function body is wrapped in a tracing span (from feature/structured-tracing).
#[instrument(name = "log", skip(msg))]
pub fn log(level: Level, msg: &str) -> Result<(), LoggerError> {
    // Defensive layer
    if msg.is_empty() {
        return Err(LoggerError::EmptyMessage);                   // from agent-cleanup-pass-3
    }
    if msg.len() > MAX_LOG_MSG_BYTES {
        return Err(LoggerError::MessageTooLong(msg.len()));      // from feature/length-cap
    }

    let msg = redact_secrets(msg);                               // from feature/redact-secrets

    // Body (canonical's structure preserved; tracing instrumentation added)
    write_log_entry(level, &msg)
}

fn write_log_entry(level: Level, msg: &str) -> Result<(), LoggerError> {
    // Implementation preserved from canonical
    eprintln!("[{}] {}", level, msg);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    // From feature/test-fixtures + per-variant tests:

    #[test]
    fn test_log_rejects_empty_msg() {                            // from agent-cleanup-pass-3
        assert!(matches!(log(Level::Info, ""), Err(LoggerError::EmptyMessage)));
    }

    #[test]
    fn test_log_rejects_oversize_msg() {                         // from feature/length-cap
        let big = "a".repeat(MAX_LOG_MSG_BYTES + 1);
        assert!(matches!(log(Level::Info, &big), Err(LoggerError::MessageTooLong(_))));
    }

    #[test]
    fn test_log_redacts_stripe_keys() {                          // from feature/redact-secrets
        // Indirect verification: redact_secrets is the helper; check via the public fn
        // (the actual log call to write_log_entry is not asserting on output directly;
        // for redaction unit testing, expose redact_secrets via #[cfg(test)] or use a
        // mock writer. Per the harmonization plan, this is a follow-up refinement.)
        assert_eq!(redact_secrets("sk_live_abc"), "[REDACTED]");
    }

    #[test]
    fn test_redaction_regex_compiles() {                         // from feature/redact-secrets
        let _ = redaction_pattern();
    }

    #[test]
    fn test_log_happy_path() {                                   // from feature/test-fixtures
        assert!(log(Level::Info, "hello").is_ok());
    }
}
```

### 14.4 What the harmonization plan documents

```markdown
## src/util/logger.rs synthesis

### Adopted variants
- agent-cleanup-pass-3       (intent: defensive — empty-message check)
- feature/length-cap         (intent: defensive — length cap)
- feature/redact-secrets     (intent: defensive — secret redaction; regex const)
- feature/structured-tracing (intent: refactor — tracing instrumentation; #[instrument])
- feature/test-fixtures      (intent: test — happy-path fixtures)

### Deferred to user
- feature/non-empty-newtype  (intent: type-narrowing — would change pub fn log signature)
  RATIONALE: changing &str to NonEmptyStr<'a> requires updating every call site of log()
  on canonical (12 sites identified). The empty-message check now covers the same
  invariant at the function entry; type-narrowing is redundant unless the team wants
  it for documentation/IDE-hint reasons.
  USER ACTION: confirm whether to defer or to take it up as a separate refactor PR.

### Composition order rationale
1. Empty-message check first — cheapest (single is_empty() call), eliminates largest input class.
2. Length cap next — also cheap (.len() comparison), eliminates oversized inputs.
3. Redaction last — most expensive (regex), only on inputs that survived the prior gates.

### Tests lifted
5 tests, one per defensive intent + happy-path + regex-compilation sanity check.

Confidence: 0.89 (high; the deferred type-narrowing is the only ambiguous decision).
```

---

## 15. Cherry-Pick Gotchas Specific to Rust

### 15.1 Macros expanding differently in different contexts

A cherry-picked commit using `vec![]` may compile fine in the source branch but fail in the rationalization branch if the rat-branch lacks `use std::vec;` (rare, but possible in `no_std` settings).

### 15.2 `#[derive]` requiring trait bounds the rat-branch lacks

Branch adds `#[derive(Hash)]` to a struct that has a field whose type doesn't `impl Hash` on canonical. Cherry-pick succeeds; `cargo build` fails.

The per-apply gate catches this:

```bash
cargo build --workspace 2>&1 | grep -E 'error\[E0277\]|trait .* is not implemented'
```

Surface the error; ask the user to either skip the keeper or add the missing trait impl manually.

### 15.3 Edition-2021 vs. Edition-2018 const generics

Branches authored against different editions may use syntax that doesn't work in the other. The harmonization-planner reads `edition` from the workspace's `Cargo.toml`; if a branch uses an edition feature unavailable on canonical, surface to user.

### 15.4 `#[cfg(feature = "...")]` vs. workspace feature unification

Cargo unifies features across the workspace. A branch's `#[cfg(feature = "tls")]` may compile differently when applied to a workspace where another crate has activated `feature = "tls"`. The per-apply `cargo test --workspace` catches feature-unification surprises.

---

## 16. Integration with UBS

The Ultimate Bug Scanner (UBS) is the project's static analyzer. The skill runs UBS as part of every Phase 8 apply gate:

```bash
ubs <changed_paths> 2>&1 | tee "$WS/ubs/keeper_<n>.log"
```

UBS findings on harmonized syntheses are surfaced explicitly:

| UBS class | Action |
|---|---|
| `unsafe_block_added` | Always flag for user |
| `panic_added` | Flag for user; review whether the panic is justified |
| `unwrap_added` | Flag if the project's UBS config treats unwrap as an error |
| `clone_in_hot_path` | Cosmetic; ignore unless project flags as error |
| `lifetime_change` | Flag for user; correlate with [§ 7](#7-lifetime-parameter-changes) |

UBS warning-only findings don't block the apply but appear in `handoff_report.md:ubs_findings_summary`.

---

## 17. Cross-References

- General language profile for Rust: [LANGUAGE-PROFILES.md § Rust](LANGUAGE-PROFILES.md#rust)
- TypeScript counterpart: [TYPESCRIPT-DEEP-DIVE.md](TYPESCRIPT-DEEP-DIVE.md)
- Harmonization methodology: [HARMONIZATION.md](HARMONIZATION.md)
- Workspace + Cargo specifics: [REPO-ARCHETYPES.md A5](REPO-ARCHETYPES.md#a5--monorepo-turborepo--nx--pnpm-workspaces--yarn-workspaces--cargo-workspace)
- Operator `◇ HARMONIZE` cards: [OPERATOR-LIBRARY.md](OPERATOR-LIBRARY.md)
- The `language-specialist-rust` subagent: `subagents/language-specialist.md`
- Worked example A (Rust CLI): [WORKED-EXAMPLES-EXTENDED.md scenario A](WORKED-EXAMPLES-EXTENDED.md#a-solo-developer--quick-mode--small-rust-cli)
