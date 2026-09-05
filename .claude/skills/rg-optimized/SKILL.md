---
name: rg-optimized
description: >-
  Upgrade an already-installed ripgrep to a from-source build with PCRE2,
  native CPU SIMD (AVX2 etc.), and fat LTO. Use when the user has stock rg
  but needs PCRE2 features (lookahead, lookbehind, possessive quantifiers,
  atomic groups via `rg -P`), sees "PCRE2 is not available", wants faster
  ripgrep via target-cpu=native + release-lto, or is building ripgrep from
  master with all features. NOT for installing rg from scratch.
---

# Optimized ripgrep Build Guide

> **Why:** Stock ripgrep lacks PCRE2. Build from master with all features for `-P` regex support, lookahead/lookbehind, and native CPU optimizations.

## Outcome — When This Skill Has Delivered

You're done when **all** of the following hold:

- `rg --version` reports `features:+pcre2` (the line that lists compiled-in features explicitly includes `pcre2`). Absence of `+pcre2` means the rebuild silently dropped the feature.
- `rg -P '(?=...)' .` (any lookahead pattern) returns a non-error exit — confirms PCRE2 is wired and not just compiled in.
- The replaced binary is the one your shell resolves: `which rg` points to the new build, not the distro rg still on `$PATH`. A common foot-gun is installing to `~/.cargo/bin/rg` while `/usr/bin/rg` still wins via `$PATH` order.
- (If you built with `target-cpu=native`) the binary runs on the machine it was built on. Native-CPU binaries will not run on older CPUs in the same family — do not copy to a different host without rebuilding.

If `--version` shows `+pcre2` but `rg -P` still errors with "PCRE2 is not available," the binary is correct but `$PATH` is resolving the old one; fix the path before trying anything else.

## When NOT to Use This Skill

Reach for something else if:

- **`rg` is not installed at all** → install it first (`brew install ripgrep`, `apt install ripgrep`, `cargo install ripgrep`, or `jsm install` for skills that need it). This skill is an **upgrade** for an existing install, not a fresh install path.
- **You don't actually need PCRE2 features** (no lookahead, lookbehind, possessive quantifiers, atomic groups, or backreferences) → stock `rg` is fine and ~10-50 MB smaller. Don't carry the build complexity for features you don't use.
- **You need a portable binary** to ship to other machines → drop `target-cpu=native` (it pins to your host CPU's instruction set); keep `--features pcre2` + `--profile release-lto`. Native-CPU is for personal-machine performance only.
- **You're on Windows** without WSL → the build recipe here assumes a Unix toolchain (`apt-get`, `pkg-config`, `~/.cargo/bin/`). Adapt or use a prebuilt PCRE2-enabled ripgrep release from upstream.

## Quick Build (Copy-Paste)

```bash
# 1. Install PCRE2 dev libs
sudo apt-get update && sudo apt-get install -y libpcre2-dev pkg-config

# 2. Clone and build
git clone --depth 1 https://github.com/BurntSushi/ripgrep.git /tmp/rg-build
cd /tmp/rg-build
RUSTFLAGS="-C target-cpu=native" cargo +nightly build --profile release-lto --features pcre2

# 3. Find and install
RG_BIN=$(cargo metadata --format-version 1 | grep -o '"target_directory":"[^"]*"' | cut -d'"' -f4)/release-lto/rg
cp "$RG_BIN" ~/.cargo/bin/rg

# 4. Verify
rg --version  # Should show: features:+pcre2
```

---

## Decision Tree

```
rg -P pattern fails?
├─ "PCRE2 is not available" → BUILD (this skill)
├─ Pattern syntax error → Check PCRE2 syntax (not Rust regex)
└─ Works fine → No action needed

Need lookahead/lookbehind?
├─ Yes → Need PCRE2 build
└─ No → Stock rg is fine

Want maximum performance?
├─ Native CPU optimizations → Use release-lto + target-cpu=native
└─ Portable binary → Skip target-cpu=native
```

---

## Build Options Matrix

| Option | Flag | Effect |
|--------|------|--------|
| PCRE2 support | `--features pcre2` | Enables `-P` flag for PCRE2 regex |
| Fat LTO | `--profile release-lto` | Smaller binary, faster execution |
| Native SIMD | `RUSTFLAGS="-C target-cpu=native"` | AVX2/SSE optimizations for your CPU |
| Nightly Rust | `+nightly` | Required for Edition 2024 |

### Profiles (from Cargo.toml)

```toml
[profile.release-lto]
inherits = "release"
opt-level = 3
debug = "none"
strip = "symbols"
debug-assertions = false
overflow-checks = false
lto = "fat"
panic = "abort"
incremental = false
codegen-units = 1
```

---

## Prerequisites

### System Dependencies

| OS | Command |
|----|---------|
| Ubuntu/Debian | `sudo apt-get install -y libpcre2-dev pkg-config` |
| Fedora/RHEL | `sudo dnf install -y pcre2-devel pkg-config` |
| macOS | `brew install pcre2 pkg-config` |
| Arch | `sudo pacman -S pcre2 pkgconf` |

### Rust Toolchain

```bash
# Ensure nightly is installed
rustup install nightly
rustup update nightly

# Verify
rustc +nightly --version  # Should be 1.85+
```

---

## Target Directory Discovery

ripgrep may use a custom target directory (e.g., `/tmp/cargo-target` for remote compilation). Always discover it:

```bash
cd /path/to/ripgrep-source
TARGET_DIR=$(cargo metadata --format-version 1 | grep -o '"target_directory":"[^"]*"' | cut -d'"' -f4)
echo "Binary at: $TARGET_DIR/release-lto/rg"
```

---

## Installation Locations

| Location | When |
|----------|------|
| `~/.cargo/bin/rg` | User install (recommended) |
| `/usr/local/bin/rg` | System-wide |
| Project-local | Testing before install |

### Install Command

```bash
# Replace existing (may need to rm first if "Text file busy")
rm -f ~/.cargo/bin/rg
cp "$TARGET_DIR/release-lto/rg" ~/.cargo/bin/rg
chmod +x ~/.cargo/bin/rg
```

---

## Verification

```bash
rg --version
```

**Expected output:**
```
ripgrep 15.1.0 (rev XXXXXXXX)

features:+pcre2
simd(compile):+SSE2,+SSSE3,+AVX2
simd(runtime):+SSE2,+SSSE3,+AVX2

PCRE2 10.XX is available (JIT is available)
```

**Key indicators:**
- `features:+pcre2` — PCRE2 enabled
- `simd(compile):+SSE2,+SSSE3,+AVX2` — Native optimizations
- `PCRE2 X.XX is available (JIT is available)` — Full PCRE2 with JIT

---

## PCRE2 Usage Examples

```bash
# Lookahead: lines with 'foo' followed by 'bar' (not necessarily adjacent)
rg -P 'foo(?=.*bar)' file.txt

# Lookbehind: numbers preceded by '$'
rg -P '(?<=\$)\d+' file.txt

# Unicode property: em-dashes
rg -P '[\x{2014}]' file.txt

# Backreferences: repeated words
rg -P '\b(\w+)\s+\1\b' file.txt

# Atomic groups: possessive matching
rg -P '(?>a+)b' file.txt
```

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| "cannot find -lpcre2-8" | Missing dev libs | Install `libpcre2-dev` |
| "Text file busy" | Binary in use | `rm` then `cp` |
| Edition 2024 error | Old Rust | `rustup update nightly` |
| Still shows `-pcre2` | Wrong binary | Check `which rg`, install to correct location |
| Slow build | No remote compilation | Consider RCH setup |

### Common Build Errors

**pkg-config not found:**
```bash
sudo apt-get install pkg-config
```

**PCRE2 headers missing:**
```bash
# Ubuntu/Debian
sudo apt-get install libpcre2-dev

# The -dev package contains headers needed for compilation
```

---

## Cleanup

```bash
rm -rf /tmp/rg-build
```

---

## References

| Topic | File |
|-------|------|
| PCRE2 regex patterns | [PCRE2-PATTERNS.md](references/PCRE2-PATTERNS.md) |
| Cross-compilation | [CROSS-COMPILE.md](references/CROSS-COMPILE.md) |
| Benchmarking builds | [BENCHMARKS.md](references/BENCHMARKS.md) |

---

## Anti-Patterns

| Don't | Why | Do Instead |
|-------|-----|------------|
| Use `--release` | Missing optimizations | Use `--profile release-lto` |
| Skip `+nightly` | Build may fail | Always use nightly |
| Hardcode target path | May differ per system | Use `cargo metadata` |
| Install without verify | May install wrong binary | Always check `rg --version` |
