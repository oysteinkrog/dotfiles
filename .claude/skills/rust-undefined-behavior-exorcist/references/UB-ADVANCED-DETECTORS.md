# Advanced UB Detectors — Surfaces the Standard Sweep Misses

The Phase 1/2/3 sweeps cover the 25 [UB-TAXONOMY](UB-TAXONOMY.md) buckets against the audited crate's `src/`. That deliberately scopes the audit, but it leaves several high-value detection surfaces uncovered:

- **Compile-time code that runs during build** (`build.rs`, proc-macros) is itself Rust code; if it has UB, it corrupts the build artifact silently.
- **Conditional compilation (`cfg(miri)`, `cfg(test)`)** can replace unsafe with safe stubs, making Miri prove a *phantom* invariant about prod behavior.
- **Cross-target UB** sits invisible when the audit runs only on the host triple — alignment, endianness, pointer width.
- **Cross-axis verdict diffing** is a free signal the skill currently throws away: Miri runs default / tree-borrows / strict-provenance / symbolic-alignment, but never *diffs* them. An axis-pair where one accepts and the other rejects is a confirmed soundness gradient, not noise.
- **Comparative testing vs the last published version** catches soundness *regressions* that single-version audit cannot.
- **Runtime corners** (TLS destructor ordering, panic across FFI, custom allocator alignment edge cases) are sound on typical test input but UB on cold paths.

Each detector below names a specific Phase 2/3 sweep extension, the recipe to run it, and the bucket(s) of UB it surfaces.

---

## D-1: Cross-axis Miri verdict diff

**What it finds:** Sites that one Miri axis tolerates but another rejects — typically a Stacked-vs-Tree-Borrows split, or a strict-vs-loose provenance split. These splits are *latent* soundness bugs: the code is UB under one borrow model, accidentally accepted by the other.

**Why the standard sweep misses it:** [run-miri-matrix.sh](../scripts/run-miri-matrix.sh) tees per-axis logs but reports each axis pass/fail in isolation. A reader has to manually cross-reference four logs to spot a split.

**Recipe:**
```bash
# After run-miri-matrix.sh has populated phase3_raw/miri_*.log, diff the verdicts.
./scripts/miri-axis-differ.sh "$WORKSPACE"
# Produces phase3_raw/miri_axis_diff.md listing every test that diverges.
```

The differ extracts each test name's exit verdict per axis and emits rows of `test_name | default | tree_borrows | strict_provenance | symbolic_alignment`. Anything that is not all-PASS or all-FAIL is a finding worth a Phase 5 experiment.

**Bucket affinity:** [#1 Aliasing](UB-TAXONOMY.md#1-aliasing--t--mut-t-violations), [#2 Provenance](UB-TAXONOMY.md#2-provenance--pointer-identity--arithmetic), [#3 Alignment](UB-TAXONOMY.md#3-alignment).

**When to run:** Every Standard / Exhaustive audit, after `run-miri-matrix.sh`. Free signal — no extra Miri time.

---

## D-2: Cross-target Miri sweep

**What it finds:** UB that the source-target compiler can't observe — alignment requirements on ARM that x86 silently tolerates, endianness-sensitive `transmute`s, pointer-width-sensitive offset arithmetic, `usize` overflow that's a wraparound on 64-bit but a constraint violation on 32-bit.

**Why the standard sweep misses it:** Miri defaults to the host target. The audit only sees what the host's combination of pointer width + endianness + ABI allows.

**Prerequisites** (each target needs its standard library + rust-src component installed under the nightly toolchain):

```bash
# Install target + rust-src for each non-host target you intend to audit.
# Without this, `cargo miri test --target $tgt` errors:
#   "can't find crate for `std` --target $tgt"
for tgt in \
    aarch64-unknown-linux-gnu \
    i686-unknown-linux-gnu \
    powerpc64-unknown-linux-gnu \
    wasm32-unknown-unknown \
; do
    rustup +nightly target add "$tgt"
done
# Miri's component already covers rust-src for all targets it supports; no
# separate `rustup component add rust-src --target $tgt` is needed.
```

**Recipe** (run after the prerequisites complete):
```bash
# After the default-axis Miri pass is clean, re-run with simulated targets.
for tgt in \
    aarch64-unknown-linux-gnu \
    i686-unknown-linux-gnu \
    powerpc64-unknown-linux-gnu \
    wasm32-unknown-unknown \
; do
    env MIRIFLAGS="-Zmiri-disable-isolation" \
        cargo +nightly miri test --target "$tgt" 2>&1 \
        | tee "$WORKSPACE/phase3_raw/miri_target_${tgt}.log"
done
```

Big-endian (powerpc64) catches every `from_le_bytes` / `to_be_bytes` mistake. 32-bit (i686) catches every `as usize` assumption that "pointers are 8 bytes". wasm32 catches everything involving thread locals or signals.

**Bucket affinity:** [#3 Alignment](UB-TAXONOMY.md#3-alignment), [#6 Transmute](UB-TAXONOMY.md#6-type-punning-via-transmute--union), [#10 FFI](UB-TAXONOMY.md#10-ffi-contracts--extern-c-reprctransparentpacked), [#15 Lifetime Escape](UB-TAXONOMY.md#15-lifetimes--escape--raw-pointer-outliving-its-construction-scope).

**When to run:** Exhaustive mode, or any project that ships to non-x86 targets. Quick mode skips this.

**Cost:** Each target adds ~5–15 min on a moderate test suite. Budget accordingly.

---

## D-3: build.rs + proc-macro audit

**What it finds:** `unsafe` that runs at *compile time* — inside `build.rs` scripts (executed by `cargo build`) and inside proc-macro crates (executed by `rustc`). UB here corrupts the build artifact silently and is invisible to runtime tooling like Miri.

**Why the standard sweep misses it:** Phase 1's `unsafe-surface-mapper` greps `src/`. `build.rs` lives at the crate root (not under `src/`) and proc-macro crates are separate workspace members or path-dependencies that may not be in the audit's partition.

**Recipe** (uses POSIX `find` so it runs on any system the skill ships to; `fd` is faster but not universally installed):
```bash
# Static surface: every build.rs in the workspace
find "$SOURCE_PATH" -type f -name build.rs 2>/dev/null | while read -r b; do
    rg -nC2 '(^|[^a-zA-Z])unsafe\b' "$b" \
        | tee -a "$WORKSPACE/phase2_findings_build_scripts.md"
done

# Static surface: every proc-macro crate (Cargo.toml `proc-macro = true`)
find "$SOURCE_PATH" -type f -name Cargo.toml 2>/dev/null | while read -r c; do
    if grep -lq 'proc-macro = true' "$c" 2>/dev/null; then
        d="$(dirname "$c")"
        rg -nC2 '(^|[^a-zA-Z])unsafe\b' "$d/src/" 2>/dev/null \
            | tee -a "$WORKSPACE/phase2_findings_proc_macros.md"
    fi
done

# Dynamic surface: run build.rs under Miri. Requires the build script to be a
# pure host-rust program (not a wrapper around cc/bindgen — those are unobservable to Miri).
( cd "$SOURCE_PATH" && \
  cargo +nightly miri run --bin build_script_audit 2>&1 \
  | tee "$WORKSPACE/phase3_raw/miri_build_script.log" )
```

For proc-macro crates: the typical UB is `unsafe` inside `TokenStream` manipulation. Treat them as ordinary unsafe-bearing crates with their own Phase 1/2/3 partition.

**Bucket affinity:** All buckets apply identically; the *context* is different (compile-time vs runtime), not the UB kind.

**When to run:** Every audit. The 5-minute static scan catches 90% of issues.

---

## D-4: cfg(miri) and cfg(test) divergence detector

**What it finds:** Code paths that compile differently under `cfg(miri)` or `cfg(test)` than under prod cfg. Common pattern: `#[cfg(miri)] mock_function()` replaces an unsafe FFI call with a safe stub. Miri then proves invariants about the *stub*, not about prod code — a phantom green.

**Why the standard sweep misses it:** Phase 3 reports "Miri passed" but Miri saw a different program than ships. The skill currently has no detector for "Miri's view diverged from prod's view".

**Recipe:**
```bash
# Find every cfg(miri) / cfg(test) block that wraps unsafe or replaces a function body
ast-grep run -l Rust -p '#[cfg(miri)] fn $NAME($$$ARGS) -> $RET { $$$BODY }' "$SOURCE_PATH/src/"
ast-grep run -l Rust -p '#[cfg(miri)] $$$BLOCK' "$SOURCE_PATH/src/"
ast-grep run -l Rust -p '#[cfg(not(miri))] fn $NAME($$$ARGS) -> $RET { $$$BODY }' "$SOURCE_PATH/src/"

# For each hit: read the cfg-gated path AND its inverse, confirm the unsafe
# shape is the same in both. If miri replaces unsafe → safe, flag as
# "Phase 3 Miri verdict is suspect; the audited binary is not the prod binary."
```

**Bucket affinity:** any. The bug is a methodology bug, not a UB-kind bug; treat the finding as "Miri-coverage gap" in the report.

**When to run:** Every audit, in Phase 1 RECON. Output flags every miri-divergent path; the synthesizer must downgrade any "Miri proved clean" finding that touched a divergent path.

---

## D-5: Differential fuzz against the last published version

**What it finds:** Soundness regressions introduced in the unreleased delta — a function that returned `Result::Ok` for a class of inputs in v1.2 but now returns `Ok` with corrupted state in v1.3. Pure correctness regressions surface too; a soundness regression is a correctness regression that hits an `unsafe` invariant.

**Why the standard sweep misses it:** Phase 3 fuzz finds *new* crashes. It does NOT compare verdicts against a prior version. A regression that flips behavior on inputs the fuzzer doesn't *crash* on is silent.

**Recipe** — the Cargo manifest cannot list `current` and `previous` both pointing at a crate named `$CRATE_NAME` (cargo rejects duplicate crate identities). The trick is to vendor the previous version's source under a separate path so cargo sees two physically-different crates:

```bash
# 0. Install cargo-download if not present (one-time):
cargo install cargo-download 2>/dev/null || true

# 1. Vendor the previous published version into a sibling directory.
PREV_DIR="$WORKSPACE/diff-fuzz/previous-$LAST_PUBLISHED_VERSION"
mkdir -p "$PREV_DIR"
cargo download "$CRATE_NAME==$LAST_PUBLISHED_VERSION" --output "$PREV_DIR.crate"
tar -xf "$PREV_DIR.crate" --strip-components=1 -C "$PREV_DIR"
# Rename the vendored crate so it doesn't collide with the current one.
# (Cargo identifies a crate by its declared `name`, not by its path.)
sed -i.bak 's/^name = "'"$CRATE_NAME"'"/name = "'"$CRATE_NAME"'_previous"/' "$PREV_DIR/Cargo.toml"

# 2. Author the diff-fuzz harness as a fresh crate.
mkdir -p "$WORKSPACE/diff-fuzz/harness"
cd "$WORKSPACE/diff-fuzz/harness"
cargo init --name diff_fuzz_harness
cat >> Cargo.toml <<EOF
[dependencies]
current  = { package = "$CRATE_NAME",            path = "$SOURCE_PATH" }
previous = { package = "${CRATE_NAME}_previous", path = "$PREV_DIR" }
libfuzzer-sys = "0.4"
EOF

# 3. Author a fuzz target that exercises the same API on both, asserting verdict equality.
mkdir -p fuzz/fuzz_targets/
cat > fuzz/fuzz_targets/diff.rs <<'EOF'
#![no_main]
use libfuzzer_sys::fuzz_target;
fuzz_target!(|input: &[u8]| {
    let lhs = std::panic::catch_unwind(|| current::api(input));
    let rhs = std::panic::catch_unwind(|| previous::api(input));
    assert_eq!(
        lhs.as_ref().map(|v| v.summary()).map_err(|_| "panic"),
        rhs.as_ref().map(|v| v.summary()).map_err(|_| "panic"),
        "verdict divergence on input {:?}", input
    );
});
EOF

cd "$WORKSPACE/diff-fuzz/harness"
cargo +nightly fuzz run diff -- -max_total_time=600
```

The `summary()` accessor should compare *behavior under the unsafe contract*, not bitwise output (which legitimate refactors can change). Examples: "the function returned an aligned pointer", "the same input produced the same hash", "the function returned in finite time".

**Caveat:** if `$CRATE_NAME` contains a hyphen (e.g., `tokio-stream`), cargo will rewrite the package name to `tokio_stream` for import paths — substitute `_previous` after the underscore form, not the hyphen form. The `sed` step works on either; the import path in `fuzz_targets/diff.rs` should use `tokio_stream_previous`.

**Bucket affinity:** any. Each divergence is its own finding; the bucket assignment happens in Phase 4 synthesis.

**When to run:** Pre-release (`/rust-undefined-behavior-exorcist` mode W7). Skip on greenfield projects with no published version.

---

## D-6: TLS destructor ordering audit

**What it finds:** A `thread_local!` whose `Drop` impl accesses freed statics. TLS destructors run after `main` returns, after `lazy_static!` / `OnceLock`-held statics may have been dropped. The result: use-after-free in a destructor that ran "after the program ended".

**Why the standard sweep misses it:** Miri doesn't run destructors past program exit by default. The crash happens in production at process shutdown, often invisible to logs.

**Recipe:**
```bash
# Static: find every thread_local! with a Drop impl
ast-grep run -l Rust -p 'thread_local! { $$$BODY }' "$SOURCE_PATH/src/" \
  | grep -B1 'impl Drop for'

# For each hit, read the Drop body. If it touches:
#   - a `static` of any kind
#   - a `OnceLock` / `lazy_static!` / `once_cell` cell
#   - another `thread_local!`
# flag as a TLS-Drop hazard. Recommend `OnceLock::take`-into-local-scope before Drop.
```

**Bucket affinity:** [#15 Lifetime Escape](UB-TAXONOMY.md#15-lifetimes--escape--raw-pointer-outliving-its-construction-scope), [#17 Async Drop Hazards](UB-TAXONOMY.md#17-async-drop-hazards) (semantic cousin), [#20 Dangling Box](UB-TAXONOMY.md#20-dangling-box--manual-memory-pairing).

**When to run:** Every audit that has a `thread_local!` in [phase1_unsafe_surface_inventory.md](ARTIFACTS.md). Static; 2 minutes.

---

## D-7: panic-across-`extern "C"` audit

**What it finds:** Every `extern "C" fn` whose body can unwind without a `catch_unwind` barrier. Panic-across-FFI is instant UB; Rust 2024 makes `extern "C-unwind"` opt-in but bare `extern "C"` still defaults to non-unwinding, and a panic that crosses it is UB.

**Why the standard sweep misses it:** Clippy's `transmute_undefined_repr` and friends catch many FFI hazards but not "function body can panic". You need either type-system enforcement (which Rust doesn't have for panics) or per-function audit.

**Recipe** — ast-grep patterns need to cover `pub`/`pub(crate)` visibility AND the implicit `-> ()` return type. Run all four variants and union the results:
```bash
# For every extern "C" fn declared in the crate's src/ — four ast-grep patterns
# cover the combinations of (with/without visibility) × (with/without explicit return).
{
    ast-grep run -l Rust -p 'extern "C" fn $NAME($$$ARGS) { $$$BODY }'              "$SOURCE_PATH/src/" --json
    ast-grep run -l Rust -p 'extern "C" fn $NAME($$$ARGS) -> $RET { $$$BODY }'       "$SOURCE_PATH/src/" --json
    ast-grep run -l Rust -p 'pub extern "C" fn $NAME($$$ARGS) { $$$BODY }'           "$SOURCE_PATH/src/" --json
    ast-grep run -l Rust -p 'pub extern "C" fn $NAME($$$ARGS) -> $RET { $$$BODY }'   "$SOURCE_PATH/src/" --json
    # Catch pub(crate) / pub(super) too.
    ast-grep run -l Rust -p 'pub($V) extern "C" fn $NAME($$$ARGS) { $$$BODY }'           "$SOURCE_PATH/src/" --json
    ast-grep run -l Rust -p 'pub($V) extern "C" fn $NAME($$$ARGS) -> $RET { $$$BODY }'   "$SOURCE_PATH/src/" --json
} | jq -r '.[]? | .file + ":" + (.range.start.line|tostring) + " " + .meta_variables.NAME.text' \
  | sort -u \
  > "$WORKSPACE/phase2_extern_c_fns.txt"

# For each: confirm the body is wrapped in catch_unwind, or that EVERY .unwrap()
# / .expect() / panic!() / assert! / [N] indexing operation is provably unreachable.
# Cheap heuristic: rg -nC1 'panic!|unwrap|expect|assert' inside each fn body.
```

Same caveat applies if the project uses `#[unsafe(no_mangle)] extern "C" fn ...` (Rust 2024 syntax) — extend with an additional ast-grep pattern that prefixes `#[unsafe(no_mangle)]`.

The remediation is `std::panic::catch_unwind(AssertUnwindSafe(|| { ... })).unwrap_or_else(|_| ABORT_HANDLER)`. Document in [REMEDIATION-PATTERNS.md](REMEDIATION-PATTERNS.md).

**Bucket affinity:** [#10 FFI Contracts](UB-TAXONOMY.md#10-ffi-contracts--extern-c-reprctransparentpacked), [#11 Panic Safety](UB-TAXONOMY.md#11-panic-safety-memforget-manuallydrop).

**When to run:** Every audit with `ffi_present=yes` in `preflight_smoke.json`. Static; 3 minutes per 100 extern fns.

---

## D-8: `unreachable_unchecked` reachability proof

**What it finds:** Every site where `core::hint::unreachable_unchecked()` or `std::hint::unreachable_unchecked()` is reachable on some input. Reaching `unreachable_unchecked` is instant UB.

**Why the standard sweep misses it:** Miri catches it *if the test case reaches the site*. The site is reached only if a non-trivial input triggers it. The standard fuzz corpus is rarely shaped to exercise these branches; the optimizer often elides the branches entirely in release.

**This detector requires source-code modification (a new `reach_check` cargo feature + per-site guards).** That is outside Phase 2's read-only contract, so it MUST be paused for user approval before applying — surface the candidate sites to the user, confirm they accept the Cargo.toml + per-site edits, then proceed under Phase 5's experiment-execution discipline.

**Recipe:**
```bash
# 1. Find every site (read-only; safe to run in Phase 2)
ast-grep run -l Rust -p 'unreachable_unchecked()' "$SOURCE_PATH/src/" --json \
  | jq -r '.[] | .file + ":" + (.range.start.line|tostring)' \
  > "$WORKSPACE/phase2_unreachable_unchecked_sites.txt"

# 2. PAUSE FOR USER OK. Show the site list. If user approves, apply step 3.

# 3. (Phase 5 EXPERIMENT) Add the feature flag to Cargo.toml:
#    Append exactly these lines (do NOT touch the [package] section):
cat >> "$SOURCE_PATH/Cargo.toml" <<'EOF'

[features]
reach_check = []  # debug-only: convert unreachable_unchecked sites to panics
EOF

# 4. At each call site recorded in step 1, replace
#       unsafe { unreachable_unchecked() }
#    with the cfg-gated equivalent:
#       #[cfg(feature = "reach_check")] { panic!("would have been UB at {}:{}", file!(), line!()); }
#       #[cfg(not(feature = "reach_check"))] { unsafe { unreachable_unchecked() } }
#    The Edit tool's exact-string match is the right primitive — do NOT use
#    sed (per AGENTS.md "No Script-Based Changes").

# 5. Run the existing fuzz suite with the feature enabled:
cargo +nightly fuzz run <existing-target> --features reach_check -- -max_total_time=900

# 6. ANY panic message of the form "would have been UB at <file>:<line>" is a
#    confirmed-reachable site. Open a Phase 5 entry per site.

# 7. (cleanup) revert the cargo feature + site guards once the fuzz pass is
#    complete; the production binary should not ship with reach_check enabled.
```

This is the canonical Rust "convert UB to crash so we can find it" pattern. Variants apply to `get_unchecked` (turn into `get`), `assume_init` (turn into `assert!(self.is_init)`), etc. The same user-OK requirement applies to every variant: any source modification must get explicit consent before Phase 5 executes it.

**Bucket affinity:** [#5 Uninit](UB-TAXONOMY.md#5-uninitialized-memory) (assume_init variant), [#4 Validity](UB-TAXONOMY.md#4-validity-invariants--bit-patterns-that-are-always-invalid).

**When to run:** Any project with >5 hits in step 1. Targeted fuzz; needs a feature flag pre-arranged by the project.

---

## D-9: `#[global_allocator]` alignment + layout audit

**What it finds:** Custom global allocator UB — `GlobalAlloc::alloc(Layout)` returning a pointer that doesn't satisfy `Layout::align()`, or `dealloc(ptr, Layout)` where the `Layout` doesn't match the alloc call. Both are instant UB in any code that touched the returned pointer.

**Why the standard sweep misses it:** Custom allocators are project-specific and Miri's default allocator doesn't exercise the path. Without targeted property tests, the alignment edge cases are invisible.

**Recipe** (uses the [standalone-cargo-project harness pattern](EXPERIMENT-DESIGNS.md#standalone-cargo-project-harness-recommended-default) so the harness is a complete, separately-buildable crate — not a loose `main.rs`):
```bash
# Detect: does the project install a custom global allocator?
ast-grep run -l Rust -p '#[global_allocator] static $NAME: $TY = $INIT;' "$SOURCE_PATH/src/"

# If yes, scaffold a standalone harness crate (Cargo.toml + src/lib.rs + tests/).
HARNESS="$WORKSPACE/exp-harness-allocator"
mkdir -p "$HARNESS/src" "$HARNESS/tests"

cat > "$HARNESS/Cargo.toml" <<EOF
[package]
name = "allocator_audit_harness"
version = "0.0.0"
edition = "2024"
publish = false

[dependencies]
target_crate = { package = "$CRATE_NAME", path = "$SOURCE_PATH" }
proptest = "1"
EOF

# Empty lib (Miri test mode requires a lib or bin target to exist)
echo '// allocator audit harness' > "$HARNESS/src/lib.rs"

# Integration test that hammers Layout combinations
cat > "$HARNESS/tests/alloc_dealloc.rs" <<'EOF'
use proptest::prelude::*;

proptest! {
    #[test]
    fn alloc_dealloc_round_trip(size in 1usize..1<<20, align_log in 0u32..=20) {
        let align = 1usize << align_log;
        let layout = std::alloc::Layout::from_size_align(size, align).unwrap();
        unsafe {
            let p = std::alloc::alloc(layout);
            prop_assert!(!p.is_null());
            prop_assert_eq!(p as usize % align, 0, "misaligned alloc");
            std::alloc::dealloc(p, layout);
        }
    }
}
EOF

# Run under Miri. `cargo test --test <name>` works because the test file is
# an integration test (lives under tests/), giving it an explicit binary name.
( cd "$HARNESS" && \
  env MIRIFLAGS="-Zmiri-disable-isolation" \
      cargo +nightly miri test --test alloc_dealloc 2>&1 \
      | tee "$WORKSPACE/phase3_raw/miri_allocator_audit.log" )
```

Same harness pattern detects: `realloc` aliasing UB, zero-size-alloc UB, max-size-alloc UB. Add additional integration tests under `tests/` for each case.

**Bucket affinity:** [#3 Alignment](UB-TAXONOMY.md#3-alignment), [#13 Refcount Lifecycle](UB-TAXONOMY.md#13-reference-count-lifecycle--arcfrom_raw--boxfrom_raw--rcfrom_raw), [#20 Dangling Box](UB-TAXONOMY.md#20-dangling-box--manual-memory-pairing).

**When to run:** Only when [phase1_unsafe_surface_inventory.md](ARTIFACTS.md) shows a `#[global_allocator]` site.

---

## D-10: Niche-optimization round-trip audit

**What it finds:** Every `transmute` / `from_bits` / `from_raw_parts` whose source or destination type has *niche* optimizations (`NonZero*`, `&T`, `&mut T`, `Box<T>`, `enum` with niche). Round-tripping through a wider type can produce a value that is a legal `u32` but an illegal `NonZeroU32`.

**Why the standard sweep misses it:** Miri catches the `transmute` into a value-with-niche if the test case constructs a niche-violating value. The audit's existing fuzz rarely exercises `0` as a value to be transmuted into `NonZeroU32`; the bug is invisible until prod has the right input shape.

**Recipe** — ast-grep patterns must cover all three import styles of `transmute` (bare, `mem::`-qualified, `std::mem::`-qualified). Run all three and union:
```bash
# Find candidate transmute sites across all qualification styles
{
    ast-grep run -l Rust -p 'transmute::<$SRC, $DST>($EXPR)'           "$SOURCE_PATH/src/" --json
    ast-grep run -l Rust -p 'mem::transmute::<$SRC, $DST>($EXPR)'      "$SOURCE_PATH/src/" --json
    ast-grep run -l Rust -p 'std::mem::transmute::<$SRC, $DST>($EXPR)' "$SOURCE_PATH/src/" --json
    ast-grep run -l Rust -p 'core::mem::transmute::<$SRC, $DST>($EXPR)' "$SOURCE_PATH/src/" --json
} | jq -r '.[]? | .file + ":" + (.range.start.line|tostring) + " " + .meta_variables.SRC.text + "->" + .meta_variables.DST.text' \
  | sort -u \
  > "$WORKSPACE/phase2_transmute_sites.txt"

# For each: if DST is a known niched type, author a Miri test that constructs
# the niche-violating bit pattern:
#   - NonZeroU32: 0
#   - &T / &mut T: 0 (null ref), or 1 (misaligned for align>1)
#   - enum with N variants: N or higher
#   - Box<T>: 0 (null Box)
# Run cargo +nightly miri test on each.
```

Bonus pattern: `mem::zeroed::<NonZeroU32>()` is instant UB and grep-able directly.

**Bucket affinity:** [#4 Validity Invariants](UB-TAXONOMY.md#4-validity-invariants--bit-patterns-that-are-always-invalid), [#6 Transmute / Union](UB-TAXONOMY.md#6-type-punning-via-transmute--union).

**When to run:** Every Standard / Exhaustive audit. Static find + Miri-test author is ~10 min per site.

---

## D-11: Rustonomicon anti-pattern catalogue

**What it finds:** Every code shape the [Rustonomicon](https://doc.rust-lang.org/nomicon/) explicitly calls out as UB or "wrong". The Rustonomicon is a stable, version-locked source of patterns the language team has documented as bugs — running its anti-pattern list against the audited source is a free signal.

**Why the standard sweep misses it:** UB-TAXONOMY.md's 25 buckets describe *kinds* of UB; the Rustonomicon describes *specific code shapes* that exhibit those kinds. The shape-level patterns are concrete enough for ast-grep but the taxonomy doesn't enumerate them.

**Recipe:**
```bash
./scripts/rustonomicon-antipatterns.sh "$SOURCE/src/"
# Writes phase2_findings_rustonomicon.md with one section per anti-pattern.
# Each section lists matching file:line + the Rustonomicon URL that documents
# why it's UB.
```

The script bundles ~25 ast-grep rules derived from the Rustonomicon's verbatim "Don't do this" examples (e.g., `mem::zeroed::<&T>()`, `transmute::<&T, &mut T>`, `Box::from_raw(stack_ptr)`, `Vec::set_len(self.capacity() + 1)`). Each rule cites its Rustonomicon section so a finding is self-documenting.

**Bucket affinity:** all 25 — this is the meta-detector that fans out across them.

**When to run:** Every audit, including Quick mode. Static; ~30 seconds.

---

## D-12: `MaybeUninit::assume_init` initialization audit

**What it finds:** Every `assume_init` call where data-flow analysis can't prove the slot was written. The canonical Rust UB: `MaybeUninit::<T>::uninit().assume_init()` is UB *even for `T = u8`* because reading uninitialized MEMORY (not just invalid bit patterns) is UB.

**Why the standard sweep misses it:** Miri catches it only if the test reaches the site AND observes the uninit read. Many `assume_init` callers are guarded by complex preconditions that fuzz inputs rarely exercise; the bug is invisible until production has the right shape.

**Recipe:**
```bash
# 1. Locate every site
ast-grep run -l Rust -p '$E.assume_init()'         "$SOURCE_PATH/src/" --json
ast-grep run -l Rust -p '$E.assume_init_ref()'     "$SOURCE_PATH/src/" --json
ast-grep run -l Rust -p '$E.assume_init_mut()'     "$SOURCE_PATH/src/" --json
ast-grep run -l Rust -p '$E.assume_init_read()'    "$SOURCE_PATH/src/" --json

# 2. For each site, trace the receiver $E backwards within the same fn body:
#    - Was it produced by MaybeUninit::new(x)? → safe (x was committed)
#    - Was it produced by MaybeUninit::zeroed() + T is zero-valid? → safe
#    - Was it produced by MaybeUninit::uninit() THEN .write(x)? → safe
#    - Was it produced by MaybeUninit::uninit() with NO subsequent .write()? → UB
#    - Was the producer threaded through a function param? → escalate to /multi-model-triangulation
#
# 3. Convert each ambiguous case to a Miri experiment: write a unit test that
#    exercises the path and assert Miri verdicts.
```

**Bucket affinity:** [#5 Uninitialized Memory](UB-TAXONOMY.md#5-uninitialized-memory) (primary), [#4 Validity](UB-TAXONOMY.md#4-validity-invariants--bit-patterns-that-are-always-invalid) (secondary when T has invalid bit patterns).

**When to run:** Every audit where Phase 1 reports `assume_init` sites. The data-flow proof is per-site manual; automation reaches "list every site" but the proof step is human-judgment.

---

## D-13: Cross-edition differential audit (2018 / 2021 / 2024)

**What it finds:** UB that one Rust edition's semantics tolerates but another rejects. Examples:
- Rust 2021's *disjoint capture* changed which fields a closure borrows; code that was sound under 2018's whole-struct capture can be UB under 2021's partial capture (or vice versa).
- Rust 2024 tightened `unsafe extern` and `unsafe attribute` rules; code that compiled clean on 2021 can fail to compile on 2024 — and the failure is "your unsafe assertion was wrong".

**Why the standard sweep misses it:** Phase 3 runs Miri against the edition declared in Cargo.toml. The audited binary's edition is the only one tested. UB that surfaces under a different edition is invisible.

**Recipe:**
```bash
# For each edition the project might migrate to, do a parallel build + test.
# Run only on a copy of the source to avoid disturbing the audited Cargo.toml.
mkdir -p "$WORKSPACE/edition-audit"
for edition in 2018 2021 2024; do
    cp -r "$SOURCE_PATH" "$WORKSPACE/edition-audit/$edition-src"
    sed -i.bak "s/^edition = .*/edition = \"$edition\"/" \
        "$WORKSPACE/edition-audit/$edition-src/Cargo.toml"
    rm -f "$WORKSPACE/edition-audit/$edition-src/Cargo.toml.bak"
    (cd "$WORKSPACE/edition-audit/$edition-src" && \
     cargo +nightly miri test 2>&1 \
     | tee "$WORKSPACE/phase3_raw/miri_edition_${edition}.log") || true
done

# Diff verdicts via miri-axis-differ.sh (reuses the same diff machinery,
# treating editions as additional axes).
```

**Bucket affinity:** [#1 Aliasing](UB-TAXONOMY.md#1-aliasing--t--mut-t-violations) (disjoint capture changes aliasing), [#8 Send/Sync](UB-TAXONOMY.md#8-sendsync-invariants) (2024 tightened auto-trait inference), [#10 FFI](UB-TAXONOMY.md#10-ffi-contracts--extern-c-reprctransparentpacked) (2024 `unsafe extern`).

**When to run:** Pre-edition-migration audits, and Exhaustive mode for any project published to crates.io (downstream users may pin a different edition).

---

## D-14: Mutation-testing for unsafe coverage

**What it finds:** *Test-coverage gaps* in the unsafe surface. For every `unsafe { ... }` block, apply a small syntactic mutation (swap operators, swap argument order, flip a comparison) and verify the project's test suite catches each mutation. Mutations that survive indicate the test suite doesn't exercise that unsafe path.

**Why the standard sweep misses it:** Phase 3 measures "does Miri report UB?". It doesn't measure "would Miri report UB if the unsafe block were wrong?". A clean verdict on never-exercised unsafe code is meaningless.

**Recipe:**
```bash
# Install cargo-mutants:
cargo install cargo-mutants

# cargo-mutants only supports --test-tool={cargo,nextest} (verified against
# https://github.com/sourcefrog/cargo-mutants/blob/main/src/options.rs).
# Miri is NOT a supported test runner. Two-stage strategy:
#
# Stage 1: native test mutation sweep. cargo-mutants drives `cargo test`.
# --re filters mutants by their printed description; "unsafe" reliably hits
# fn signatures containing the unsafe keyword. (Not an AST filter — it's a
# substring match on the mutant name, so it may also catch unrelated lines
# that mention "unsafe" in identifiers/strings; filter the survivor list
# manually.) DO NOT use --in-place: it edits the working tree and is
# incompatible with --jobs.
cargo mutants \
    --re 'unsafe' \
    --jobs 3 \
    --output "$WORKSPACE/phase3_raw/mutants/" \
    --test-tool=cargo

# Stage 2: for each surviving mutant whose location is inside an `unsafe`
# block, the kill-set is missing a test. Open a Phase 5 experiment per
# survivor, design the test that should kill it, run it under Miri natively
# (not via cargo-mutants) to confirm it surfaces UB if the unsafe block is
# subtly wrong. cargo-mutants' "caught" verdict is necessary but not
# sufficient for the unsafe-coverage claim — only Miri proves the test
# would have caught a real soundness defect.
```

**Bucket affinity:** This is a meta-detector for test-coverage of unsafe; the surviving mutants then map to specific buckets via the unsafe block's site.

**When to run:** Exhaustive mode; the campaign takes hours but produces the highest-confidence "your unsafe code IS tested" signal available short of formal verification.

---

## D-15: Reverse-direction caller audit (per-public-unsafe API)

**What it finds:** Every `pub unsafe fn` in the audited crate has *preconditions* documented in its `# Safety` doc comment. The standard sweep audits the IMPLEMENTATION (does it uphold what it promises?). The reverse-direction audit audits the USAGE: for each public unsafe API, sweep all callers (in-crate and reachable downstream) for preconditions-satisfaction.

**Why the standard sweep misses it:** Phase 1's RECON tags unsafe sites. Phase 2's static-bucket-sweepers verify each site against the taxonomy. Neither sweep cross-references "is the contract satisfied at every call site?". A function whose body upholds its contract perfectly can still be involved in UB if a caller violates it.

**Recipe:**
```bash
# 1. Extract the unsafe-fn contract surface — two patterns to cover fns with
#    and without an explicit return type. ast-grep meta-vars: $NAME / $$$ARGS /
#    $RET / $$$BODY. `--json` for downstream jq.
{
    ast-grep run -l Rust --json -p 'pub unsafe fn $NAME($$$ARGS) { $$$BODY }'           "$SOURCE_PATH/src/"
    ast-grep run -l Rust --json -p 'pub unsafe fn $NAME($$$ARGS) -> $RET { $$$BODY }'   "$SOURCE_PATH/src/"
} | jq -r '.[]? | .metaVariables.single.NAME.text + " " + .file' \
  | sort -u \
  > "$WORKSPACE/phase1_pub_unsafe_apis.txt"

# 2. Generate rustdoc ONCE (not per-fn), then extract every fn's # Safety section.
#    `cargo +nightly rustdoc --output-format json -- -Z unstable-options` produces
#    machine-readable docs with the Safety block isolatable per item.
cargo +nightly rustdoc --output-format json -- -Z unstable-options \
    > "$WORKSPACE/rustdoc.json" 2>/dev/null || true
# Parse phase1_pub_unsafe_apis.txt + rustdoc.json to extract each fn's # Safety
# rustdoc paragraph (jq query is project-specific; see the rustdoc-json schema).

# 3. Sweep every callsite of each pub unsafe fn
while IFS= read -r fn; do
    [[ -z "$fn" ]] && continue
    ast-grep run -l Rust --json -p "$fn(\$\$\$CALLARGS)" "$SOURCE_PATH" \
        > "$WORKSPACE/phase2_callsites_${fn}.json"
done < <(awk '{print $1}' "$WORKSPACE/phase1_pub_unsafe_apis.txt" | sort -u)

# 4. For each (callsite, contract) pair: does the surrounding code prove the
# precondition holds? This step is per-site human review; the script's job
# is to enumerate them. Open a Phase 5 entry for every callsite where the
# proof isn't obvious.
```

**Bucket affinity:** all — this is meta-analysis over the audited unsafe surface.

**When to run:** Standard and Exhaustive modes for any crate with `pub unsafe fn` items reachable from external code. Pure-internal-unsafe crates skip this.

---

## D-16: Profile-guided UB triage

**What it finds:** Reprioritizes the audit's attention based on *runtime importance*. Cold unsafe blocks (those never exercised by typical workloads) carry low UB-incidence risk in practice; hot blocks (exercised millions of times per request) carry high risk. Audit the hot ones FIRST.

**Why the standard sweep misses it:** Phase 4 synthesis prioritizes by severity. Severity is a property of *what* the bug is; profile data is a property of *how often* the buggy path runs. Multiplying the two gives a better triage signal than severity alone.

**Recipe:**
```bash
# 1. Build a PGO/coverage-instrumented binary
RUSTFLAGS="-C instrument-coverage" cargo build --release
# Or: use cargo-bolero's coverage mode if the project uses bolero fuzz harnesses

# 2. Run the project's representative workload (CI test suite or production trace)
LLVM_PROFILE_FILE="$WORKSPACE/coverage/%p.profraw" \
    "./target/release/<bin>" < representative-workload

# 3. Merge + extract per-line counts
llvm-profdata merge -sparse "$WORKSPACE/coverage/"*.profraw \
    -o "$WORKSPACE/coverage/merged.profdata"
llvm-cov export "./target/release/<bin>" \
    -instr-profile="$WORKSPACE/coverage/merged.profdata" \
    --format=lcov > "$WORKSPACE/coverage/cov.lcov"

# 4. For each unsafe site in phase1_unsafe_surface_inventory.md, look up its
# execution count in cov.lcov. Rank descending; the top decile gets Phase 5
# experiment priority.
```

**Bucket affinity:** none directly; this is a prioritization layer over Phase 4 synthesis.

**When to run:** Any audit where a representative workload exists. Crates with no canonical workload skip this.

---

## D-17: `compiler_fence` vs `atomic::fence` audit

**What it finds:** Every `compiler_fence` call in concurrent code paths. `compiler_fence` only constrains the COMPILER's reordering; it does NOT emit a CPU memory barrier. Using it where you need cross-thread synchronization on weak memory models (ARM, PowerPC) is silent UB on those targets.

**Why the standard sweep misses it:** Miri runs on a strong memory model; sanitizers don't model fences; loom catches some but only if the test exercises the path. The bug is real on aarch64 but invisible on x86_64.

**Recipe:**
```bash
# Find every compiler_fence in the source
ast-grep run -l Rust -p 'compiler_fence($ORD)'           "$SOURCE_PATH/src/" --json
ast-grep run -l Rust -p 'std::sync::atomic::compiler_fence($ORD)' "$SOURCE_PATH/src/" --json

# For each hit, determine context:
#   - Used between a non-volatile read/write and ANOTHER thread's read/write
#     of the SAME atomic? → suspect: should likely be atomic::fence(Ordering::SeqCst)
#   - Used to prevent compiler reordering around `asm!` or volatile? → legitimate use
#   - Used to prevent reordering around setjmp/longjmp boundaries? → legitimate

# Cross-reference with [D-2 Cross-target Miri](#d-2-cross-target-miri-sweep):
# run the Miri matrix with --target aarch64-unknown-linux-gnu and see if any
# tests fail under weak memory but pass on host.
```

**Bucket affinity:** [#7 Data Races](UB-TAXONOMY.md#7-data-races) — compiler_fence misuse is a stealth race.

**When to run:** Standard and Exhaustive modes when Phase 1 reports any `compiler_fence` use.

---

## D-18: Fault-injection sweep (LD_PRELOAD-based)

**What it finds:** UB that's only triggered under abnormal kernel/library behavior — `malloc` returns NULL, `write` returns EINTR, `mmap` returns MAP_FAILED, `read` returns short-counts, `clock_gettime` returns errors. Production hits these edge cases; CI rarely does.

**Why the standard sweep misses it:** Miri models the language, not the kernel. Sanitizers see allocator behavior but don't INDUCE failures. The bug is invisible under happy-path testing.

**Recipe:**
```bash
# Use libfaultinject or write a minimal LD_PRELOAD that randomizes errnos.
# Example: a wrapper that fails 1% of allocations:
cat > "$WORKSPACE/fault-inject.c" <<'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>

static void *(*real_malloc)(size_t) = NULL;
// Thread-local recursion guard. dlsym() and some allocator paths internally
// call malloc; without this guard, the wrapper recurses infinitely.
static __thread int in_malloc = 0;

__attribute__((constructor))
static void fault_inject_init(void) {
    // Seed once at library load. Without this, every run uses the same
    // sequence and CI repeats reproduce the same injection points.
    srand((unsigned)time(NULL));
}

void *malloc(size_t size) {
    if (!real_malloc) real_malloc = dlsym(RTLD_NEXT, "malloc");
    if (in_malloc) return real_malloc(size);   // reentrant call → pass through
    in_malloc = 1;
    int rate = getenv("FAULT_RATE") ? atoi(getenv("FAULT_RATE")) : 0;
    if (rate > 0 && (rand() % 100) < rate) {
        in_malloc = 0;
        errno = ENOMEM;
        return NULL;
    }
    void *p = real_malloc(size);
    in_malloc = 0;
    return p;
}
EOF
# GNU ld is order-sensitive: -l<lib> must come AFTER the .c source files that
# reference its symbols. -ldl provides dlsym/dlfcn.
gcc -shared -fPIC -o "$WORKSPACE/fault-inject.so" "$WORKSPACE/fault-inject.c" -ldl

# Run the test suite under fault injection. Note: Miri normally does NOT honor
# LD_PRELOAD because it runs as an interpreter. Apply this against the
# native-build path (cargo test) and against any binary the audit launches.
LD_PRELOAD="$WORKSPACE/fault-inject.so" FAULT_RATE=5 \
    cargo +nightly test 2>&1 \
    | tee "$WORKSPACE/phase3_raw/fault_injection.log"
```

Any crash, panic, or Miri UB report under fault injection is a candidate finding. Common shapes: unsafe code that assumes `malloc` always succeeds; FFI code that doesn't check return codes; `mem::transmute` of `Option<NonNull<T>>` assuming the inner is non-null.

**Bucket affinity:** [#4 Validity](UB-TAXONOMY.md#4-validity-invariants--bit-patterns-that-are-always-invalid), [#5 Uninit](UB-TAXONOMY.md#5-uninitialized-memory), [#11 Panic Safety](UB-TAXONOMY.md#11-panic-safety-memforget-manuallydrop), [#20 Dangling Box](UB-TAXONOMY.md#20-dangling-box--manual-memory-pairing).

**When to run:** Exhaustive mode for projects with significant FFI or custom-allocator surface. The campaign needs 30+ minutes and a representative workload.

---

## Composition with existing phases

Each detector slots into the existing phase model:

| Detector | Maps to Phase | Subagent / script | Adds to artifact |
|---|---|---|---|
| D-1 Miri-axis diff | Phase 3 (post-miri-matrix) | new `scripts/miri-axis-differ.sh` | `phase3_raw/miri_axis_diff.md` |
| D-2 Cross-target | Phase 3 (parallel axis) | extend `miri-runner` subagent | `phase3_raw/miri_target_<tgt>.log` |
| D-3 build.rs + proc-macro | Phase 1 partition + Phase 2 sweep | `static-bucket-sweeper` (new bucket `build_meta`) | `phase2_findings_build_scripts.md`, `phase2_findings_proc_macros.md` |
| D-4 cfg(miri) divergence | Phase 1 (RECON) | `unsafe-surface-mapper` (extended) | section in `phase1_unsafe_surface_inventory.md` |
| D-5 Differential fuzz | Phase 3 (W7 pre-release only) | new pattern in `fuzz-author-and-runner` | `phase3_raw/diff_fuzz.log` |
| D-6 TLS-Drop | Phase 2 (static bucket) | new `static-bucket-sweeper` rule | `phase2_findings_tls_drop.md` |
| D-7 panic-across-FFI | Phase 2 (static bucket) | new `static-bucket-sweeper` rule | `phase2_findings_extern_c_panic.md` |
| D-8 `unreachable_unchecked` | Phase 5 (experiment design) | new pattern in `experiment-designer` | per-EXP entry |
| D-9 Custom-allocator | Phase 5 (conditional on global allocator) | new pattern in `experiment-designer` | per-EXP entry |
| D-10 Niche round-trip | Phase 2 (static find) + Phase 5 (experiment) | `static-bucket-sweeper` + `experiment-designer` | `phase2_findings_niche.md` + per-EXP |
| D-11 Rustonomicon antipatterns | Phase 2 (static bucket) | new `scripts/rustonomicon-antipatterns.sh` | `phase2_findings_rustonomicon.md` |
| D-12 `assume_init` flow | Phase 1 (extend `unsafe-surface-mapper`) → Phase 5 per ambiguous site | extension of `unsafe-surface-mapper` | section in `phase1_unsafe_surface_inventory.md` + per-EXP |
| D-13 Cross-edition | Phase 3 (parallel axis) | extension of `miri-runner` | `phase3_raw/miri_edition_<N>.log` + axis-differ output |
| D-14 Mutation testing | Phase 11 (Exhaustive only) | new `soak-designer` campaign | `phase11_artifacts/mutants/` |
| D-15 Reverse caller audit | Phase 2 (per pub unsafe fn) | new `static-bucket-sweeper` rule | `phase2_callsites_<fn>.json` + Phase 5 follow-ups |
| D-16 Profile-guided triage | Phase 4 (synthesis prioritization) | extension of `synthesizer` | priority column in `phase4_unified_findings.md` |
| D-17 compiler_fence vs fence | Phase 2 (static bucket) | new `static-bucket-sweeper` rule | `phase2_findings_compiler_fence.md` |
| D-18 Fault-injection sweep | Phase 11 (Exhaustive only) | new `soak-designer` campaign | `phase3_raw/fault_injection.log` |

## Cross-references

- [UB-TAXONOMY.md](UB-TAXONOMY.md) — the 25 buckets each detector contributes to
- [PHASES.md](PHASES.md) — phase-by-phase placement
- [TOOLING.md](TOOLING.md) — for the Miri / fuzz / proptest tools each detector invokes
- [EXPERIMENT-DESIGNS.md](EXPERIMENT-DESIGNS.md) — for the standalone-harness pattern that D-9 + D-10 build on
- [FALSE-POSITIVES.md](FALSE-POSITIVES.md) — D-1's verdict diffs sometimes reflect legitimate axis-specific behavior; the false-positives catalog is the right place to document the calibration
