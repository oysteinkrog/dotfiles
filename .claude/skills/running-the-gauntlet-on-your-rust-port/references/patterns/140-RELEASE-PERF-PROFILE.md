# Pattern 140 — release-perf Profile

## What

A dedicated Cargo profile `release-perf` that inherits from `release` and pins compilation knobs (`opt-level=3`, `lto="thin"`, `codegen-units=1`, `debug="line-tables-only"`, `strip=false`) plus a `RUSTFLAGS` contract (`-C force-frame-pointers=yes`). The plain `--release` profile is *size-optimized* and incompatible with honest perf measurement: it strips frame pointers (kills flamegraphs), changes LTO settings under your feet, and uses higher `codegen-units` (introduces inlining drift run-to-run). Any perf claim made under `--release` is invalid by construction.

## Why

> "Never `--release` (size-optimized) for any perf claim." — MINING-3 §1.7

Failure mode prevented: a kept perf win measured under one cargo profile, a regression detector running under another, a flamegraph captured under a third. The profile name is the *single* line that makes them all the same compile.

## Where in FrankenSQLite

- `Cargo.toml` workspace root — the `[profile.release-perf]` block.
- `.cargo/config.toml` — `RUSTFLAGS` per-profile via `[env]` if needed.
- `scripts/run-bench-matrix.sh` and `scripts/run-narrow-benches.sh` — invoke `cargo build --profile release-perf` exclusively.
- CI: `.github/workflows/verification-gates.yml` — bench jobs use `--profile release-perf`.

## Verbatim shape

```toml
[profile.release-perf]
inherits = "release"
opt-level = 3
lto = "thin"
codegen-units = 1
debug = "line-tables-only"
strip = false
RUSTFLAGS = "-C force-frame-pointers=yes"
```

### Why each knob

| Knob | Setting | Why |
|---|---|---|
| `inherits = "release"` | release base | get the release defaults; override deliberately |
| `opt-level = 3` | max | guarantees the LLVM passes that production runs; avoids accidental opt-level 2 from a workspace ancestor |
| `lto = "thin"` | thin LTO | inlines across crates *deterministically*; "fat" LTO can OOM on large workspaces; "off" leaves crate-boundary calls un-inlined and skews ratios |
| `codegen-units = 1` | single unit | removes one variable (CGU partition is non-deterministic across builds otherwise); the cost is build time, not run time |
| `debug = "line-tables-only"` | line tables on | enough for flamegraph symbolicate without bloating the binary |
| `strip = false` | symbols present | `strip = "symbols"` (the release default) destroys flamegraph attribution |
| `RUSTFLAGS = "-C force-frame-pointers=yes"` | frame pointers on | every sample in `perf`/`samply`/`flamegraph` has an unwound stack |

### Why a plain `--release` is forbidden

The plain `--release` profile uses `opt-level = 3, lto = false, codegen-units = 16, debug = false, strip = "symbols"`. Frame pointers are omitted (depends on target ABI and rustc default), symbols are stripped, codegen-units = 16 means *different rebuilds inline differently*. A bench number from `--release` is not comparable to a bench number from a profiler under `--release` (because the profiler can't unwind), and not comparable to two `--release` builds three days apart (because CGU partitions drifted).

### Invocation contract

Every script and CI step that produces perf evidence must invoke `cargo build --profile release-perf` (not `--release`) and `cargo bench --profile release-perf` (not the default `bench` profile, which is yet another set of defaults). Reading the `cargo_profile` field from the bench JSON is the audit:

```bash
jq -r '.detected_environment.cargo_profile' artifacts/bench/run-*.json | sort -u
# must print exactly: release-perf
```

Anything else and the artifact is rejected before the regression detector runs.

## Per-class instantiation

| Class | Equivalent build-profile contract |
|---|---|
| Rust (all classes) | `release-perf` as above. Add `panic = "abort"` only if the project's panic policy is abort-not-unwind in production. |
| Python-bridge (Numerical-Python / ML-System) | `release-perf` for the Rust side **plus** Python interpreter built with `--enable-optimizations` and pinned `PYTHONHASHSEED=0` for cross-platform RNG determinism. |
| RESP (vendored redis-server) | Reference oracle built with vendored `redis-server` compiled with `-O2 -fno-omit-frame-pointer` (matching the Rust flags). Both sides need frame pointers for joint flamegraph attribution. |
| ML-System (CUDA) | Add `CUDA_LAUNCH_BLOCKING=1` to the *profile-capture* run only (not the timing run); pinned cuDNN version recorded in `detected_environment`. |
| HTTP-Protocol | TLS off in bench (controlled flag); pinned tokio runtime flavor (single-thread or multi-thread, never default-on-runtime); jemalloc or default allocator declared. |

For all classes the rule generalizes: there is one perf-build profile per class, it is named, it pins every variable that affects either *runtime* or *attribution*, and the regression detector rejects artifacts produced under any other.

## Composition

- [pattern:125-COMPREHENSIVE-BENCH](125-COMPREHENSIVE-BENCH.md) — comprehensive bench *only* runs under `release-perf`; `detected_environment.cargo_profile` is the audit field.
- [pattern:130-FOCUSED-BENCHES](130-FOCUSED-BENCHES.md) — all focused benches inherit the same profile contract.
- [pattern:145-HOT-PATH-COUNTERS](145-HOT-PATH-COUNTERS.md) — counters compiled under `release-perf` have the same inlining as the timed binary; counters under `--release` would diverge.
- [pattern:150-PROFILE-FIRST-CARD](150-PROFILE-FIRST-CARD.md) — the proof-pack card mandates a `RUSTFLAGS` field and a `cargo_profile` field; both must match the contract.
- [pattern:160-MT8-ATTRIBUTION](160-MT8-ATTRIBUTION.md) — MT8 flamegraphs must be captured under `release-perf` or attribution is wrong.
- [pattern:175-CONCURRENT-MODE-GUARD](175-CONCURRENT-MODE-GUARD.md) — guard file should include `CARGO_PROFILE=release-perf` for completeness.

## Pitfalls

- **`cargo bench` without `--profile release-perf`** — uses the implicit `bench` profile, which has its own defaults. The bench result has no relationship to the build the user runs.
- **Setting `RUSTFLAGS` via shell env** — non-portable, easy to forget; CI silently uses different flags than dev. Put it in `.cargo/config.toml` per-profile or directly in the `[profile.release-perf]` block via a custom build script (rustc < 1.78 didn't support `RUSTFLAGS` per profile; for older rustc, use `.cargo/config.toml`).
- **Letting a downstream crate override `lto`** — workspace profiles are inheritable but downstream `Cargo.toml`s can re-declare; CI must `cargo build --profile release-perf -vv` and grep for any rustc invocation with conflicting flags.
- **Using `strip = "debuginfo"` to "shrink"** — kills `samply` and `cargo-flamegraph` symbolication.
- **Adding `panic = "abort"` without auditing** — changes which destructors run; benches that assumed unwinding now leak resources between iters in subtle ways.
- **Switching between `lto = "thin"` and `lto = "fat"` between baseline and new** — silent inlining diff. Pin once and never edit in a perf bead.
- **Forgetting the guard file** — `cargo_profile=release-perf` must be a *file* in the artifact lane (see [pattern:175-CONCURRENT-MODE-GUARD](175-CONCURRENT-MODE-GUARD.md)), not just an embedded field. The file is the gate the regression detector reads first.
- **Re-declaring the profile in nested workspaces** — every nested workspace inherits the parent unless re-declared; if a leaf re-declares, audit it against the root contract.
- **Comparing `release-perf` Rust-side vs default-profile reference-side** — both sides must be in the per-class equivalent perf profile; mismatched profiles produce uninterpretable ratios.
