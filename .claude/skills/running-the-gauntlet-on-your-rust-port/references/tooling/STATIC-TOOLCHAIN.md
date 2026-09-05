# STATIC-TOOLCHAIN.md — Surface Detection + Static Analysis Toolchain

`ast-grep`, `semgrep`, `cargo-geiger`, `cargo-deny`, `cargo-audit`, `cargo-expand`, `syn`-walkers, `cargo doc --document-private-items`, `rust-analyzer` MIR-level analysis, `mock-code-finder`. The tools that turn "is this surface enumerated?" from a question into a query. Cross-links: [ORACLE-TOOLCHAIN.md](ORACLE-TOOLCHAIN.md) for the public-API parity surface these patterns feed; [../taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md) for the FeatureUniverse the enumerated symbols populate.

## 0. Core Discipline

> **The Enumerate-Surface operator (`✦`): "Is every `pub` item / every dispatched opcode / every command / every public-API symbol on both sides accounted for, with `present|partial|missing|n/a|excluded`?"** Manual enumeration rots; automated queries against the AST stay current.

---

## 1. `ast-grep` — Surface-Detection Patterns

`ast-grep` matches AST patterns, not regex. The pattern `pub fn $NAME($$$ARGS) -> $RET` matches every `pub fn` regardless of formatting / line breaks / argument count.

```bash
cargo install ast-grep --locked
# Verify
sg --version    # `sg` is the binary alias
```

### 1.1 Generic Rust Public-API Patterns

```bash
# Every pub function (workspace-wide)
sg --lang rust 'pub fn $NAME($$$ARGS) -> $RET { $$$ }' \
   crates/ \
   --json | jq -r '.[] | "\(.file):\(.range.start.line) \(.metavariables.NAME.text)"'

# Every pub struct
sg --lang rust 'pub struct $NAME { $$$ }' crates/ --json

# Every pub enum
sg --lang rust 'pub enum $NAME { $$$ }' crates/ --json

# Every impl block (catches public trait implementations)
sg --lang rust 'impl $TRAIT for $TYPE { $$$ }' crates/ --json

# Every #[no_mangle] / extern "C"
sg --lang rust '#[no_mangle] $$$' crates/ --json
sg --lang rust 'extern "C" fn $NAME($$$) -> $RET { $$$ }' crates/ --json

# Every macro that expands to surface
sg --lang rust '#[macro_export] macro_rules! $NAME { $$$ }' crates/ --json
```

### 1.2 SQL-Class (FrankenSQLite) Patterns

```bash
# Every PRAGMA the port understands (matches `case "<name>"` arms)
sg --lang rust '"$NAME" => { $$$ }' crates/fsqlite-core/src/pragma.rs --json \
  | jq -r '.[] | .metavariables.NAME.text' | sort -u > present_pragmas.txt

# Every VDBE opcode
sg --lang rust 'Opcode::$NAME' crates/fsqlite-vdbe/src/ --json \
  | jq -r '.[] | .metavariables.NAME.text' | sort -u > present_opcodes.txt

# Every SQL function name in the dispatch table
sg --lang rust 'register_builtin("$NAME", $$$)' crates/fsqlite-core/src/functions.rs --json
```

Then diff against the reference's pragma / opcode / function list:
```bash
comm -23 reference_pragmas.txt present_pragmas.txt > missing_pragmas.txt
```

### 1.3 RESP-Class (FrankenRedis) Patterns

```bash
# Every Redis command constant
sg --lang rust 'pub const COMMAND_$NAME: Command = $$$' crates/frankenredis-core/src/commands.rs

# Every #[command] macro invocation
sg --lang rust '#[command(name = "$NAME", $$$)]' crates/

# Every RESP type variant
sg --lang rust 'RespValue::$VARIANT($$$)' crates/frankenredis-protocol/src/
```

### 1.4 Numerical / ML-Class Patterns (PyO3-Decorated Rust Functions)

```bash
# Every pub fn decorated with #[pyfunction] (exported to Python)
sg --lang rust '#[pyfunction] pub fn $NAME($$$) -> $RET { $$$ }' crates/

# Every #[pymethods] block (Python-callable methods)
sg --lang rust '#[pymethods] impl $TYPE { $$$ }' crates/

# Every name added to a Python module
sg --lang rust 'm.add_function(wrap_pyfunction!($NAME, $$$))' crates/

# Every name in __all__ via the m.add_*() pattern
sg --lang rust 'm.add("$NAME", $$$)' crates/
```

Diff against `numpy.__all__` / `torch.__all__` extracted from PyO3-loaded reference:
```python
# scripts/extract_reference_all.py
import numpy
print('\n'.join(sorted(numpy.__all__)))
```

### 1.5 HTTP / Protocol-Class (FastAPI) Patterns

```bash
# Every pub struct implementing HandlerExt (a route handler)
sg --lang rust 'pub struct $NAME { $$$ } impl HandlerExt for $NAME { $$$ }' crates/

# Every route registration
sg --lang rust '.route("$PATH", $$$)' crates/

# Every middleware
sg --lang rust 'impl Middleware for $TYPE { $$$ }' crates/

# Every extractor type
sg --lang rust 'impl FromRequest for $TYPE { $$$ }' crates/
```

### 1.6 Storing Patterns Per Project Class

```
scripts/ast-grep-surface-patterns/
  common.yml
  sql-class.yml
  resp-class.yml
  numerical-class.yml
  ml-class.yml
  http-class.yml
```

Each `.yml` is `ast-grep`'s rule format:
```yaml
id: pub-fn-with-pyfunction
language: rust
rule:
  pattern: '#[pyfunction] pub fn $NAME($$$) -> $RET { $$$ }'
```

Then:
```bash
ast-grep scan -r scripts/ast-grep-surface-patterns/common.yml --json <target>/src/
ast-grep scan -r scripts/ast-grep-surface-patterns/numerical-class.yml --json <target>/src/
```

### 1.7 Pitfalls — `ast-grep`

| Pitfall | Why it bites | Fix |
|---|---|---|
| Macro-expanded surface invisible | `#[derive(Foo)]` generates `pub fn foo_*()` that source doesn't show | `cargo expand` first; run `sg` on the expanded code (§6). |
| `cfg`-gated code skipped | `#[cfg(feature = "x")] pub fn ...` not detected unless feature is enabled in the workspace | Enumerate per feature-flag combination; CI matrix. |
| Pattern matches inside test modules | `pub fn` in `#[cfg(test)]` mod inflates surface count | Filter via path: `crates/*/src/**/*.rs --not-path 'crates/*/tests/**'`. |
| Whitespace-sensitive patterns | None — ast-grep is AST-based, not text-based | N/A; this is the advantage. |

---

## 2. `semgrep` — Control-Flow Patterns

```bash
pipx install semgrep
```

`semgrep` complements `ast-grep`: where ast-grep matches AST structure, semgrep matches **control-flow / data-flow patterns** (tainted data reaches sink, unchecked error propagation, etc.).

### Custom Rule Example

```yaml
# .semgrep/rules/unchecked-result.yml
rules:
  - id: unchecked-mutex-poison
    pattern: |
      let $G = $M.lock().unwrap();
    message: ".lock().unwrap()" propagates Mutex poisoning panic; consider .lock().expect("reason") or graceful handling.
    languages: [rust]
    severity: WARNING

  - id: tracing-without-enabled-gate
    pattern: |
      debug!("..", $X.expensive_method());
    message: "expensive_method() runs even when subscriber is disabled; wrap in if tracing::enabled!(Level::DEBUG)"
    languages: [rust]
    severity: WARNING
```

```bash
semgrep --config .semgrep/rules/ crates/
```

### When to Prefer semgrep vs ast-grep

| Pattern type | Tool |
|---|---|
| "Find every `pub fn`" | `ast-grep` (AST structure) |
| "Find every place tainted data reaches `eval`" | `semgrep` (data-flow) |
| "Find every `Result::unwrap()` in a public API" | `semgrep` (control-flow) |
| "Find every `Box::new`" | `ast-grep` |
| "Find every `.clone()` on a hot path" | `ast-grep` + cross-reference with profile |

---

## 3. `cargo-geiger` — Unsafe-Surface Metrics

```bash
cargo install cargo-geiger
cargo geiger --output Csv > unsafe-census.csv
```

Output (CSV):
```
Functions, Expressions, Impls, Traits, Methods, Type, Crate
12, 47, 0, 0, 8, "unsafe", "fsqlite-storage"
0, 0, 0, 0, 0, "unsafe", "fsqlite-mvcc"
3, 14, 0, 0, 2, "unsafe", "fsqlite-vdbe"
```

**Why this matters for a port:** `unsafe` is where most parity-affecting bugs hide. A perf win that introduces 47 new unsafe expressions is a parity-risk red flag.

### FrankenSQLite Discipline

> "Closed 0.44% MT8" levels of attribution apply to unsafe-surface too. Every `unsafe { ... }` block in a perf hot path either has a `// SAFETY: ...` justifying why it's sound, or it gets a bead to add one.

```bash
# Find every unsafe block missing a SAFETY comment
sg --lang rust 'unsafe { $$$ }' crates/ \
  --json | jq -r '.[] | select(.file_text | test("// SAFETY:") | not) | "\(.file):\(.range.start.line)"'
```

### Ratchet Pattern

Track `cargo geiger` count per release in `unsafe-census-history.json`. Pre-release gate: count must not increase without an explicit `// SAFETY` block per new unsafe.

---

## 4. `cargo-deny` — Supply-Chain Compliance

```bash
cargo install cargo-deny
cargo deny init                 # creates deny.toml
cargo deny check
```

Checks: advisory-DB hits (RustSec), license compliance (forbidden licenses), banned crates (forbid `unsafe-libs-we-rejected`), duplicate versions (catches accidental dep tree divergence).

### Per-Project Config

```toml
# deny.toml
[advisories]
db-path = "~/.cargo/advisory-db"
db-urls = ["https://github.com/rustsec/advisory-db"]
vulnerability = "deny"
unmaintained = "warn"
yanked = "deny"

[licenses]
unlicensed = "deny"
allow = ["MIT", "Apache-2.0", "BSD-3-Clause"]
deny  = ["GPL-3.0", "AGPL-3.0"]

[bans]
multiple-versions = "warn"
deny = [
  { name = "openssl" },        # we use rustls
  { name = "time", version = "<0.3" },   # known-vulnerable
]

[sources]
unknown-registry = "deny"
unknown-git      = "deny"
allow-git = [
  "https://github.com/our-org/internal-fork-of-foo",
]
```

### CI Integration

```yaml
- run: cargo deny check
```

Fails the PR if any advisory hits or banned crate sneaks in.

---

## 5. `cargo-audit` — RustSec Advisory DB Scan

```bash
cargo install cargo-audit
cargo audit
```

Lighter weight than `cargo-deny`: only scans for vulnerabilities (no license / ban / dup version checks). Used in pre-commit hooks where `cargo-deny` is too slow.

```bash
# In .githooks/pre-commit
cargo audit --quiet || {
  echo "RustSec advisory detected; run cargo audit for details"
  exit 1
}
```

---

## 6. `cargo-expand` — Macro-Generated Surface

```bash
cargo install cargo-expand
cargo expand --bin <name>                # for a binary crate
cargo expand --lib -p <crate>            # for a library crate
cargo expand --bin <name> --release      # post-monomorphization
```

Macros generate `pub fn`, `pub struct`, etc. that source doesn't show. `cargo expand` is the only way to enumerate them.

### Use Cases

1. **Surface enumeration:** before running `ast-grep` for `pub fn`, expand the crate so macro-generated `pub fn`s are visible.
2. **`#[derive]` audit:** see what `#[derive(Serialize, Deserialize)]` actually generates; useful for catching surprise `impl`s.
3. **Custom DSL expansion:** SQL-class often has `def_opcode!(...)` macros; expand to see the generated `pub fn execute_<opcode>`.

### Workflow

```bash
# 1. Expand
cargo expand --lib -p fsqlite-vdbe > /tmp/vdbe-expanded.rs

# 2. Run ast-grep against the expanded code
sg --lang rust 'pub fn execute_$NAME($$$) -> $RET { $$$ }' /tmp/vdbe-expanded.rs --json

# 3. Diff against opcode list in the reference
```

---

## 7. `cargo doc --document-private-items` + Automated Scan

```bash
cargo doc --no-deps --document-private-items
# Generates target/doc/<crate>/
```

Then walk `target/doc/<crate>/index.html` extracting `pub` items:

```python
# scripts/extract_pub_items.py
import json, sys
from pathlib import Path
from bs4 import BeautifulSoup

doc_root = Path("target/doc/fsqlite_core")
pub_items = []
for html in doc_root.rglob("*.html"):
    soup = BeautifulSoup(html.read_text(), "html.parser")
    for a in soup.select("a.fn, a.struct, a.enum, a.trait, a.constant"):
        pub_items.append({"path": str(html.relative_to(doc_root)), "name": a.text})
print(json.dumps(pub_items, indent=2))
```

Compare against the reference's `__all__` / public-API export list. Items in subject but not in reference: deferred / experimental — flag in `SurfaceMatrix`. Items in reference but not in subject: missing — open a bead.

---

## 8. `rust-analyzer` MIR-Level Analysis

For hot-path code-size attribution:

```bash
cargo +nightly rustc --release -- -Z dump-mir=all -Z dump-mir-dir=target/mir-dump
```

Generates `.mir` files per function — the lowered intermediate representation. Useful for:

- Confirming inlining decisions: function present in MIR dump but not in final binary's symbol table = inlined.
- Hot-path code-size: count basic blocks per MIR function; biggest function in the hot path is the optimization target.

```bash
# Top 10 biggest MIR functions (by basic block count)
for f in target/mir-dump/*.mir; do
  echo "$(grep -c '^bb' "$f") $f"
done | sort -rn | head -10
```

### `rust-analyzer` IDE Server

Beyond MIR: `rust-analyzer` exposes a query language for finding usages, callers, implementers via LSP. Scripted queries via:
```bash
rust-analyzer analysis-stats path/to/workspace
```

---

## 9. `syn` Walkers — Custom Predicates

For predicates ast-grep can't express, write a Rust source-walker program using the `syn` crate.

### Skeleton

```rust
// scripts/syn-walkers/pyfunction-signature-check/src/main.rs
use syn::{visit::Visit, ItemFn, Attribute};
use std::{fs, path::PathBuf};
use anyhow::Result;

struct PyFunctionVisitor<'r> {
    reference_all: &'r [String],
    findings: Vec<Finding>,
}

#[derive(Debug)]
struct Finding {
    name: String,
    file: PathBuf,
    line: usize,
    issue: String,
}

impl<'ast, 'r> Visit<'ast> for PyFunctionVisitor<'r> {
    fn visit_item_fn(&mut self, node: &'ast ItemFn) {
        let is_pyfn = node.attrs.iter().any(|a: &Attribute| {
            a.path().is_ident("pyfunction")
        });
        if !is_pyfn { return; }
        let name = node.sig.ident.to_string();

        // Predicate: every #[pyfunction] must have a name in reference's __all__
        if !self.reference_all.contains(&name) {
            self.findings.push(Finding {
                name: name.clone(),
                file: PathBuf::new(),    // populated by caller
                line: 0,                 // populated by caller
                issue: format!("#[pyfunction] {} not in reference's __all__", name),
            });
        }

        // Predicate: argument list shape must match reference signature
        // (Real impl would extract argument types from syn::FnArg and compare.)

        syn::visit::visit_item_fn(self, node);
    }
}

fn main() -> Result<()> {
    let reference_all = fs::read_to_string("reference_all.txt")?
        .lines().map(|l| l.to_string()).collect::<Vec<_>>();
    let mut visitor = PyFunctionVisitor { reference_all: &reference_all, findings: vec![] };

    for rs_file in walkdir::WalkDir::new("crates/franken_numpy/src")
        .into_iter()
        .filter_map(Result::ok)
        .filter(|e| e.path().extension().map(|x| x == "rs").unwrap_or(false))
    {
        let source = fs::read_to_string(rs_file.path())?;
        let ast = syn::parse_file(&source)?;
        visitor.visit_file(&ast);
    }

    for f in &visitor.findings {
        eprintln!("{:?}", f);
    }
    std::process::exit(if visitor.findings.is_empty() { 0 } else { 1 });
}
```

### Predicates `ast-grep` Can't Express

| Predicate | Why ast-grep fails |
|---|---|
| Every `pub fn` whose name matches a `__all__` entry but argument list differs | ast-grep matches syntax structure; can't cross-reference external list. |
| Every macro-expanded `extern "C"` whose signature drifts from a vendored header | Requires parsing C header + matching against Rust signature. |
| Every `#[no_mangle]` symbol whose calling convention isn't `extern "C"` | Requires combining two attributes (presence of `#[no_mangle]` + absence of `extern "C"` on same fn) in non-trivial way. |
| Lifetime annotation analysis | Requires resolving lifetimes, not just matching syntax. |

### Existing Walkers (Per Project Class)

```
scripts/syn-walkers/
  sql-class/
    opcode-signature-check/             # every opcode handler's signature matches the dispatch table
    pragma-completeness-check/          # every PRAGMA in reference has a handler
  resp-class/
    command-arity-check/                # every Redis command handler's arity matches the reference
  numerical-class/
    pyfunction-signature-check/         # above example
    rng-state-purity-check/             # no #[pyfunction] body uses thread-local RNG
  ml-class/
    autograd-determinism-check/         # every autograd op is in the deterministic-ops list or marked nondet
  http-class/
    handler-extractor-check/            # every Handler has at least one FromRequest extractor
```

---

## 10. `mock-code-finder` Skill — Stub / Mock / Placeholder Scan

```bash
# Use the skill:
# Trigger phrases: "find mocks", "find stubs", "find placeholders", "check for fake code"
```

The skill scans for: `todo!()`, `unimplemented!()`, `unreachable!()` outside-test-modules, `panic!("not implemented")`, comments containing `TODO`, `FIXME`, `XXX`, `HACK`, `STUB`, function bodies of `Default::default()` for non-trivial types, `Vec::new()` returns from functions that should return real data.

### Pattern Categories

| Marker | Action |
|---|---|
| `todo!()` | Open a bead (high severity); usually fails to compile in release but causes runtime panic in debug. |
| `unimplemented!()` | Open a bead (high severity); same panic semantics. |
| `unreachable!()` outside `match` exhaustiveness | Open a bead (medium); investigate if reachable. |
| `// TODO:` | Catalog; surface in `PARITY_RUNBOOK.md` as a coverage debt entry. |
| `// FIXME:` | Catalog as bug debt. |
| Functions returning `Vec::new()` / `HashMap::new()` from a non-empty-default API | Likely stub; open a bead. |
| `cfg(feature = "real")` gating real impl behind a default-off flag | Stub-via-feature-flag; open a bead. |

### Invocation

```bash
# Run from project root
sg --lang rust 'todo!()' crates/ --json | jq length
sg --lang rust 'unimplemented!()' crates/ --json | jq length
sg --lang rust 'unreachable!()' crates/ --json | jq length

# Cataloged in:
# <workspace>/findings/mock-code-finder-report.json
```

Use case: pre-release sanity check that no `todo!()` slipped past CI (which often skips `cargo check --release` if `--release` was tested separately from `--debug`).

---

## 11. Pitfalls

| Pitfall | Why it bites | Fix |
|---|---|---|
| False positives in macro-heavy code | `ast-grep` matches the surface form; macro-generated code looks like hand-written | Run on `cargo expand`'d output (§6). |
| Conditional-compilation gates hiding surface | `#[cfg(feature = "x")] pub fn ...` invisible unless `x` is on | Enumerate per feature-flag combination; CI matrix. |
| Generated code not in `pub` enumeration | `build.rs`-generated `*.rs` files often skipped | Include `target/<profile>/build/**/out/*.rs` in surface scans. |
| `cargo geiger` lies about C deps | Reports `0 unsafe` for libsqlite3 because C code isn't in scope | Treat C dep surface as separate audit. |
| `cargo deny` advisory DB stale | False negatives | `cargo deny --offline=false` to force DB refresh; CI cron weekly. |
| `cargo doc` missing items behind `#[cfg(doc)]` | Items gated for docs-only invisible to runtime | Build with `--all-features` for the doc-surface scan. |
| `syn` walker on macro-expanded code | Spans are wrong; line numbers point to generated code | Walk source code (with macros unexpanded) and resolve macro expansions separately. |
| `cargo expand` requires nightly toolchain | Stable build CI fails | Use `cargo +nightly expand`. |
| Surface diff with reference is noisy | Hundreds of "missing" items are intentional non-implementations | `SurfaceMatrix` with `n/a` / `excluded` status + `exclusion_rationale`; see [../taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md). |
| `mock-code-finder` false positives in tests | `todo!()` in `#[cfg(test)]` mods is fine | Filter by path: `--not-path 'tests/**' --not-path '**/tests/*.rs'`. |

---

## 12. Wiring Into the Gauntlet Loop

### Phase 1 (RECON)
- `cargo-geiger` baseline; check into `phase1_unsafe_baseline.csv`.
- `cargo expand` per crate; cache in `phase1_expanded_sources/`.
- `cargo doc --document-private-items`; ingest via §7.

### Phase 7 (SURFACE PARITY)
- Run all per-class `ast-grep` patterns; emit `present_<concept>.txt`.
- Diff against reference's enumeration: `missing_<concept>.txt`, `extra_<concept>.txt`.
- Each missing entry → FeatureUniverse `Missing` row.
- Each extra entry → FeatureUniverse `Excluded` row with `exclusion_rationale`.
- Run `syn` walkers for predicates ast-grep can't express.

### Phase 14 (FRESH-EYES REVIEW)
- `cargo audit` + `cargo deny check`.
- `mock-code-finder` final pass; no `todo!()` / `unimplemented!()` outside `#[cfg(test)]`.

### Phase 15 (SOAK)
- Re-run `cargo geiger`; assert no new unsafe blocks vs `unsafe-census-history.json`.

---

## See Also

- [ORACLE-TOOLCHAIN.md](ORACLE-TOOLCHAIN.md) — public-API parity surface the patterns enumerate against.
- [BENCH-TOOLCHAIN.md](BENCH-TOOLCHAIN.md) — `cargo asm` for hot-loop assembly; complements `cargo expand` for macro-generated hot paths.
- [FUZZ-TOOLCHAIN.md](FUZZ-TOOLCHAIN.md) — fuzz targets per surface-detected API.
- [../taxonomy/FEATURE-UNIVERSE.md](../taxonomy/FEATURE-UNIVERSE.md) — where surface-detection output lands as `present|partial|missing|n/a|excluded`.
- [../methodology/ANTI-PATTERNS.md](../methodology/ANTI-PATTERNS.md) — "Hallucinating a function that doesn't exist" — run ast-grep before recommending an API.
