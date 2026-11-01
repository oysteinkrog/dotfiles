# Cargo profile and config template

Copy these into a new workspace, or compare an existing one against them. The
reasons and numbers are in `SKILL.md`, section 5.

## Root `Cargo.toml`

```toml
[workspace]
resolver = "3"
members = ["crates/*", "xtask"]

[workspace.package]
edition = "2024"
publish = false

# Every crate takes its dependencies from here (`dep = { workspace = true }`),
# so all crates agree on versions and features.
[workspace.dependencies]
# ...

[profile.dev]
incremental = true            # 5-10x faster edit loops; target/ is capped by a timer instead
opt-level = 0                 # use 1 only if the app is too slow to use at 0
debug = "line-tables-only"    # backtraces keep file and line; target/ stays small

[profile.dev.package."*"]
opt-level = 2                 # dependencies compile once; GUI and GPU stacks need it at run time
debug = false                 # dependency debuginfo was most of a 424 MiB test binary

[profile.test]
incremental = true
# Inherits dev. Set opt-level = 1 here only if test run time is bigger than
# compile time in your loop (tasklens: 0 cut edit compile 71 s to 22 s, tests ran 1.6x slower).

# Benchmarks, profiling and A/B runs. Thin LTO rebuilds much faster than fat.
[profile.bench-fast]
inherits = "release"
lto = "thin"
codegen-units = 16
debug = "line-tables-only"
strip = "none"

# Packaging only. Never built in an agent lane.
[profile.release]
opt-level = 3
lto = "fat"
codegen-units = 1
debug = "line-tables-only"

[workspace.lints.rust]
unsafe_code = "deny"
[workspace.lints.clippy]
dbg_macro = "deny"
```

Name the bench profile what the project already uses (`profiling`, `release-perf`)
if one exists. Do not add a second.

## `.cargo/config.toml` in the repo

```toml
[alias]
xtask = "run -p xtask --"
# Dev aliases carry the one feature set every dev command uses (SKILL.md section 3).
# Leave `--features` out if the project has no dev feature.
c = "check --all-targets --features dev"
t = "test --features dev"
b = "build --features dev"

# mold links the tasklens UI test binary in 0.6 s against 1.1 s for rust-lld.
# makepkg sets RUSTFLAGS, which replaces this, so packages use the default linker.
[target.x86_64-unknown-linux-gnu]
rustflags = ["-C", "link-arg=-fuse-ld=mold"]
```

Do not put any of these in the repo config:

- `build.build-dir` or `build.target-dir`. `~/.cargo/config.toml` already sets
  `build-dir = "{workspace-root}/target"`. A repo setting overrides it.
- `[env] CARGO_INCREMENTAL`. Let the profile decide. jobd sets it to 0 for jobs it routes
  to the other desktop, on purpose.
- `-Z` flags in a project pinned to stable. They fail the build.

## Optional, nightly projects only

```toml
[build]
rustflags = ["-Z", "threads=8", "-C", "link-arg=-fuse-ld=mold"]
```

`-Zthreads=8` cut the tasklens UI crate by 20 to 30% (81 to 97 s down to 64 s).
The `rustflags` key replaces the target one above, so keep the mold flag in it.

## `rust-toolchain.toml`

```toml
[toolchain]
channel = "1.98.1"            # exact version; upgrades are their own change
components = ["rustfmt", "clippy"]
profile = "minimal"
```

A toolchain change rebuilds everything and leaves the old units in target/ until the
prune timer removes them.
