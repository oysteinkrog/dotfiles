# Operator Patterns — Mined from Real Release Sessions

Each pattern follows the format: **Trigger** (when this happens) → **Action** (do this) → **Why** (because this happened in a real session).

---

## OP-1: RCH Intercepts Release Builds

**Trigger:** You run `cargo build --release` and the binaries don't appear in `target/release/` — they ended up on a remote worker via RCH hooks.

**Action:**
```bash
# Bypass RCH for release builds
RCH_DISABLED=1 cargo build --release

# Or use a custom target dir that RCH doesn't intercept
CARGO_TARGET_DIR=/tmp/release_build cargo build --release
```

**Why:** In an earlier Rust project release session, `cargo build --release` was silently intercepted by the RCH PreToolUse hook, which sent the compilation to a remote worker. The agent spent time looking for binaries in `target/release/` before realizing RCH had moved them. The `RCH_DISABLED=1` env var bypass was the recovery.

**Failure mode if ignored:** You waste time searching for binaries that don't exist locally, or try to package artifacts from the wrong machine.

---

## OP-2: GitHub Actions Bot Tags Don't Trigger Downstream Workflows

**Trigger:** You push a version bump, `release-automation.yml` creates a tag via the GitHub Actions bot, but `dist.yml` (which triggers on tag push) never runs.

**Action:**
```bash
# Manually trigger the dist workflow
gh workflow run dist.yml -f ref=vX.Y.Z

# Or trigger via workflow_dispatch if the workflow supports it
gh workflow run dist.yml --ref vX.Y.Z
```

**Why:** In a CLI tool release, `release-automation.yml` successfully created the tag, but `dist.yml` never triggered. GitHub prevents recursive workflow triggers — actions created by the GITHUB_TOKEN can't trigger other workflows. The fix is always manual dispatch.

**Failure mode if ignored:** You wait indefinitely for a CI build that will never start.

---

## OP-3: Clippy Nightly Drift — CI Fails, Local Passes

**Trigger:** CI dist workflow fails on clippy despite passing locally. The error is a new lint from a newer nightly compiler on CI.

**Action:**
```bash
# Always run clippy BEFORE committing the version bump
cargo clippy --workspace --all-targets -- -D warnings 2>&1 | head -30

# Common nightly-drift fixes:
# .to_string() on a String → .clone()
# unused imports on platform-gated code → #[cfg(target_os = "...")] on the import
# new lint categories → fix the code, don't suppress

# After fixing, commit, push, and update the tag:
git add -A && git commit -m "fix: clippy lint for nightly"
git push
git tag -f vX.Y.Z && git push --tags -f   # May be blocked by dcg
```

**Why:** In a CLI tool release, the dist workflow failed because `pack.id.to_string()` should have been `pack.id.clone()` (since `PackId = String`). This lint existed locally but wasn't caught because the local nightly was older. The fix required committing, pushing, force-updating the tag, and re-triggering dist — adding 15+ minutes to the release.

**Failure mode if ignored:** CI builds fail after tagging, requiring tag gymnastics to recover.

---

## OP-4: Static Binary Verification Gotcha (ldd + "dynamic")

**Trigger:** CI verification step for musl static binaries fails even though the binary is correctly static-linked.

**Action:**
```bash
# WRONG verification (fails on static binaries):
! ldd binary | grep -q "dynamic"
# "not a dynamic executable" contains "dynamic" → false positive

# CORRECT verification:
file binary | grep -q "statically linked"
# Or: ! file binary | grep -q "dynamically linked"
```

**Why:** In a CLI tool release, the `aarch64-unknown-linux-musl` build succeeded (binary was correctly static), but the verification step failed because `ldd` outputs "not a dynamic executable" for static binaries, and `grep -q "dynamic"` matched that substring. Required a CI fix, another commit, tag update, and dist re-trigger.

**Failure mode if ignored:** Valid static binaries get rejected, release job fails, requires CI debugging mid-release.

---

## OP-5: Mac Build Host Disk Space — Clean Before Building

**Trigger:** `rsync` to mac-host fails with "No space left on device", or `cargo build --release` on mac-host fails mid-compilation.

**Action:**
```bash
# Check disk BEFORE attempting any remote build
ssh mac-host 'df -h / && du -sh ~/projects/*/target 2>/dev/null | sort -h | tail -5'

# Clean if < 2GB free (release builds need ~1-2GB)
ssh mac-host 'find ~/projects -name target -type d -exec rm -rf {} + 2>/dev/null; cargo cache --autoclean 2>/dev/null'

# Also check for stale dsr artifacts
ssh mac-host 'du -sh /tmp/dsr_* ~/projects/*/target_rch_* 2>/dev/null | sort -h'
```

**Why:** In multiple release sessions, the macOS build host was completely full. One session found a 24GB stale build directory from an unrelated project. Another found only 657MB free. In both cases, significant time was spent discovering and cleaning old artifacts before builds could proceed.

**Failure mode if ignored:** Build fails partway through, leaving incomplete artifacts and wasting time.

---

## OP-6: Path Dependency Remapping for Cross-Platform

**Trigger:** Your Cargo.toml has absolute `path = "/path/to/projects/..."` dependencies, and you need to build on a remote host where paths differ.

**Action:**
```bash
# Check what path deps exist
grep 'path = "/' Cargo.toml
grep -r 'path = "/' */Cargo.toml 2>/dev/null

# On mac-host, your project root may differ (e.g. ~/projects/ vs /path/to/projects/)
# Check if deps exist on the remote host:
ssh mac-host 'ls ~/projects/' | head -20

# Option A: Sync deps and sed-remap (temporary, for one build)
ssh mac-host "cd ~/projects/PROJECT && sed -i '' 's|/path/to/projects/|$HOME/projects/|g' Cargo.toml"

# Option B: Build locally only (skip Mac build)
# Option C: Use rch with proper path mapping
```

**Why:** In an earlier Rust project release, all external path deps used an absolute prefix that didn't exist on the Mac host. The Mac had these at a different path via `synthetic.conf`, but creating a firmlink required a reboot. The session spent significant time discovering this, trying to create symlinks (blocked by SIP), and ultimately doing a sed-remap approach.

**Failure mode if ignored:** `cargo build` fails with "failed to load manifest for workspace member" on Mac.

---

## OP-7: Release-Automation Race Condition (main vs master)

**Trigger:** Both `main` and `master` branches trigger the release-automation workflow simultaneously. One succeeds in creating the tag, the other fails.

**Action:**
```bash
# This is normal — just check the tag was created
git ls-remote --tags origin | grep vX.Y.Z

# If the tag exists, the failed run is harmless
# If BOTH failed, create the tag manually:
git tag -a vX.Y.Z -m "Release vX.Y.Z"
git push --tags
```

**Why:** In a CLI tool release, `release-automation.yml` ran on both `main` and `master`. The `master` run created the tag first, the `main` run failed with "tag already exists". This is expected behavior — don't panic about the failed run.

**Failure mode if ignored:** Wasted time investigating a "failed" workflow that was actually a harmless race.

---

## OP-8: crates.io Publish — Path Deps Need Version Specifiers

**Trigger:** `cargo publish` fails with "dependency not found on crates.io" because your path dependency doesn't include a `version` field.

**Action:**
```toml
# BEFORE (works locally, fails on crates.io):
[dependencies]
core-lib = { path = "../core_lib" }

# AFTER (works everywhere):
[dependencies]
core-lib = { version = "0.2.0", path = "../core_lib" }
```

```bash
# Find all path-only deps
grep -r 'path = "' */Cargo.toml | grep -v 'version'

# Fix each one by adding version = "X.Y.Z"
# Then dry-run before real publish:
cargo publish --dry-run -p crate-name
```

**Why:** In a Rust workspace project's crates.io publish, `app-crate` and `extras-crate` both used path-only deps without version specifiers. Each failed on `cargo publish` and required editing, committing, and retrying. The publish order also matters — leaf crates first, then dependents.

**Failure mode if ignored:** `cargo publish` fails mid-batch, requiring iterative fix-commit-retry cycles.

---

## OP-9: Workspace Publish Order (Leaf-First Topological)

**Trigger:** You need to publish multiple workspace crates to crates.io.

**Action:**
```bash
# 1. Map the dependency graph
cargo metadata --format-version 1 | jq '.packages[] | {name, deps: [.dependencies[].name]}'

# 2. Publish in dependency order (leaves first):
#    core-lib (no deps)
#    utils-lib (no deps)
#    app-crate (depends on core-lib, utils-lib)
#    my-project-macros (no external deps)
#    my-project (depends on everything)
#    extras-crate (depends on my-project)

# 3. Wait ~30s between publishes for crates.io index propagation
cargo publish -p core-lib && sleep 30
cargo publish -p utils-lib && sleep 30
# ...
```

**Why:** In a Rust workspace release session, 7 crates were published in dependency order. Publishing `app-crate` before `core-lib` would fail because crates.io wouldn't have the dependency available yet.

**Failure mode if ignored:** `cargo publish` fails with "dependency X not found" because the dependency hasn't propagated yet.

---

## OP-10: Missing README Blocks crates.io Publish

**Trigger:** `cargo publish` fails because `Cargo.toml` has `readme = "README.md"` but no README.md exists in the crate directory.

**Action:**
```bash
# Check if README exists for each crate
for dir in $(find . -name Cargo.toml -not -path './target/*' -exec dirname {} \;); do
  grep 'readme' "$dir/Cargo.toml" 2>/dev/null && ls "$dir/README.md" 2>/dev/null || echo "MISSING: $dir"
done

# Fix: either create a README or remove the readme field
```

**Why:** In a Rust workspace release session, one of the sub-crates had `readme = "README.md"` but no README.md file. `cargo publish` failed. The fix was removing the `readme` field from Cargo.toml.

**Failure mode if ignored:** `cargo publish` fails with a confusing "couldn't read README" error.

---

## OP-11: Post-Tag Commit Recovery (dcg Blocks Tag Force-Push)

**Trigger:** After tagging, you discover another fix is needed (clippy lint, CI fix, etc.). You need to update the tag but `dcg` blocks `git push --tags -f`.

**Action:**
```bash
# Option A: Accept the 1-commit offset (PREFERRED)
# The tag is 1 commit behind HEAD — this is fine for the release.
# Document it and move on.

# Option B: Create a patch version
# v0.4.1 has the bug → create v0.4.2 with the fix
git tag -a v0.4.2 -m "Release v0.4.2"
git push --tags

# Option C: If dcg is the ONLY blocker (not user policy)
# The user can manually run the force-push
```

**Why:** In a Rust workspace release session, a linter/hook updated dependency versions in Cargo.toml after the tag was created. The agent tried to force-update the tag, but dcg blocked it. The solution was accepting the 1-commit offset — the release was fine with or without that commit.

**Failure mode if ignored:** Wasted time fighting dcg, or worse, finding a way around it and potentially breaking something.

---

## OP-12: `/tmp` Full During Git Operations

**Trigger:** `git add` or `git commit` fails with "No space left on device" because `/tmp` is full.

**Action:**
```bash
# Use an alternate TMPDIR
TMPDIR=/data/tmp git add Cargo.toml Cargo.lock
TMPDIR=/data/tmp git commit -m "chore: bump version"

# Or clean /tmp (check what's using space first)
du -sh /tmp/* 2>/dev/null | sort -h | tail -10
```

**Why:** In a Rust workspace release session, `/tmp` was full (from multiple agent sessions running simultaneously). Git operations failed silently. The `TMPDIR=/data/tmp` workaround saved the release.

**Failure mode if ignored:** Git operations fail with cryptic "No space left" errors despite `/data` having plenty of space.

---

## OP-13: Batch Release Discovery — After One, Check All

**Trigger:** User releases one project, then asks "what else needs releasing?"

**Action:**
```bash
# Find all Rust projects with unreleased commits
for d in ~/projects/*; do
  [ -f "$d/Cargo.toml" ] || continue
  cd "$d"
  LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
  [ -z "$LAST_TAG" ] && continue
  COUNT=$(git rev-list --count ${LAST_TAG}..HEAD 2>/dev/null)
  [ "$COUNT" -gt 0 ] && echo "$d: $COUNT commits since $LAST_TAG"
  cd /data/projects
done

# Check which are on crates.io
for d in ~/projects/*; do
  grep -q 'crates.io' "$d/Cargo.toml" 2>/dev/null && echo "$d: on crates.io"
done
```

**Why:** In an earlier release session, after releasing one workspace project, the user asked to find all other projects on crates.io and release them too. The agent found project-a (220 commits behind) and project-b (314 commits, no tags). Both were released in parallel subagents.

**Failure mode if ignored:** Projects accumulate hundreds of unreleased commits, making individual releases harder to review.

---

## OP-14: Verify Binary Version Matches Release Tag

**Trigger:** You built and packaged the binary. Before uploading, verify it reports the correct version.

**Action:**
```bash
# Run the built binary
target/release/<binary> --version

# Compare against what you're releasing
grep '^version' Cargo.toml | head -1

# They MUST match. If they don't:
# - You forgot to bump Cargo.toml before building
# - The binary was built from a stale checkout
# - env!("CARGO_PKG_VERSION") is cached in a dependency
```

**Why:** In a CLI tool release session, the agent explicitly verified `target/release/<binary> --version` showed the expected version before proceeding. This catches the common mistake of building before bumping.

**Failure mode if ignored:** Users install the binary, run `--version`, and see the wrong version, causing confusion and bug reports.

---

## OP-15: Installer Target Triple Audit

**Trigger:** You're about to release and the project has a curl|bash installer.

**Action:**
```bash
# Read the installer to find what target triples it expects
grep -E 'TARGET=|target=' install.sh | head -10

# Compare with what CI/dsr actually produces
gh release view vPREVIOUS --json assets | jq '.assets[].name'

# They MUST use the same triple naming
# Common mismatches:
#   install.sh expects musl, release has gnu
#   install.sh expects -linux-, release has -unknown-linux-
#   install.sh expects .tar.gz, release has .zip for Linux
```

**Why:** In a CLI tool release session, the install script expected `x86_64-unknown-linux-musl` but the previous release only had `x86_64-unknown-linux-gnu` assets. Users were forced to compile from source because the installer couldn't find a matching binary. This was the entire reason for the release in the first place.

**Failure mode if ignored:** The installer silently falls back to compiling from source, which takes 5+ minutes and requires a Rust toolchain.

---

## OP-16: ONNX/ort and Other Crates That Don't Support musl

**Trigger:** CI musl build fails with "ort does not provide prebuilt binaries for target x86_64-unknown-linux-musl".

**Action:**
```bash
# Check if the crate requiring musl-incompatible deps is feature-gated
grep -A5 'ort\|onnxruntime' Cargo.toml

# Options:
# 1. Feature-gate the dep: only include on non-musl targets
# 2. Build gnu instead of musl for that platform
# 3. Use --no-default-features to skip the problematic dep
```

**Why:** In a search-engine project's CI fix session, both Linux musl builds failed because `ort-sys` (ONNX Runtime) doesn't provide musl prebuilts. This required understanding the feature gating to decide whether to skip musl or restructure the dependencies.

**Failure mode if ignored:** Linux release builds fail, leaving the release without Linux binaries — the most important platform.

---

## OP-17: Post-Release Code Review with Fresh Eyes

**Trigger:** Release is done. User asks to review all changes before moving on.

**Action:**
```bash
# Review all files you touched
git diff $(git describe --tags --abbrev=0)..HEAD --name-only

# For each changed file, read it carefully:
# - Did the test fix actually preserve the test's intent?
# - Are the new default values (0, None, vec![]) correct?
# - Did the version bump miss any internal dep references?
# - Does the binary correctly use env!("CARGO_PKG_VERSION")?
```

**Why:** In a CLI tool release session, the user explicitly asked for a fresh-eyes review after the release was created. The agent re-read every modified file, checked version caching logic, and verified `SemVer::parse` handled the 'v' prefix correctly. This is a good practice.

**Failure mode if ignored:** Subtle bugs ship in the release that a quick review would have caught.
