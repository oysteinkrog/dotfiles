---
name: release-preparations
description: >-
  Prepare project releases: run test suites, fix broken/obsolete tests, bump
  versions, build cross-platform binaries via GitHub Actions CI or dsr/rch
  fallback, create GitHub releases with checksums, verify installers. Use when:
  release, cut release, prepare release, version bump, pre-release, ship it,
  tag release, gh actions release, dsr release.
---

<!-- TOC: Quick Start | Pre-Flight | Test Gate | Version Bump | Build | Release | Verify | Anti-Patterns | References -->

# Release Preparations

> **Core Principle:** Never release broken code. The test gate is mandatory and non-negotiable. Fix tests first, release second.

## Session-Mined Gotchas (Read These First)

These are the things that actually go wrong — extracted from 12+ real release sessions across 7 projects. Each "OP-N" links to a full playbook in [OPERATOR-PATTERNS.md](references/OPERATOR-PATTERNS.md).

| Gotcha | One-Line Fix | OP |
|--------|-------------|-----|
| Bot-created tags don't trigger dist.yml | `gh workflow run dist.yml -f ref=vX.Y.Z` | 2 |
| Clippy passes local, fails CI (nightly drift) | Run clippy with `-D warnings` BEFORE tagging | 3 |
| RCH hooks intercept `cargo build --release` | `RCH_DISABLED=1 cargo build --release` | 1 |
| Remote build host out of disk space mid-build | `ssh mac-host 'df -h /'` BEFORE building | 5 |
| Local path deps break CI | Use Path B (local build) or dsr | 6 |
| release-automation race (main vs master) | Harmless — just verify tag was created | 7 |
| Tag protection blocks force-push after fix | Accept offset or create vX.Y.(Z+1) | 11 |
| `/tmp` full breaks git operations | `TMPDIR=/data/tmp git commit ...` | 12 |
| Installer expects `musl`, release has `gnu` | Audit install.sh target triples vs assets | 15 |
| `ldd` false-positive on static binaries | Use `file binary \| grep "statically linked"` | 4 |
| Path deps missing version for crates.io | Add `version = "X.Y.Z"` alongside `path` | 8 |
| ort/ONNX doesn't support musl | Feature-gate or use gnu targets | 16 |

## Quick Start

```bash
# 1. Pre-flight: understand what you're releasing
cat AGENTS.md README.md 2>/dev/null | head -100
git log --oneline $(git describe --tags --abbrev=0 2>/dev/null || echo HEAD~20)..HEAD | head -30
grep '^version' Cargo.toml 2>/dev/null || jq .version package.json 2>/dev/null

# 2. Test gate (MANDATORY before any version bump)
cargo test --workspace 2>&1 | tail -5       # Rust
npm test 2>&1 | tail -10                     # Node
pytest -x 2>&1 | tail -10                   # Python

# 3. If tests fail: fix them, then re-run until green
# 4. Bump version, build, tag, release, verify
```

---

## Phase 1: Pre-Flight

### Read Project Context

Always start by reading AGENTS.md. Every project has release conventions — branch naming, tag formats, CI workflows, master/main sync requirements.

```bash
cat AGENTS.md
```

### Assess Release Scope

```bash
# What's the current version?
grep '^version' Cargo.toml | head -1

# What's the latest release?
gh release list --limit 3
git tag --sort=-v:refname | head -5

# How many commits since last release?
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
git rev-list --count ${LAST_TAG}..HEAD 2>/dev/null || echo "No tags yet"
git log --oneline ${LAST_TAG}..HEAD 2>/dev/null | head -20

# Any uncommitted changes?
git status --short
git diff --stat
```

### Determine Version

- **Patch** (x.y.Z): bug fixes only, no new features
- **Minor** (x.Y.0): new features, no breaking changes
- **Major** (X.0.0): breaking changes (rare pre-1.0)
- **Pre-1.0 projects**: use minor for features, patch for fixes

When in doubt, ask the user what version to use.

---

## Phase 2: Test Gate (MANDATORY)

**This is the most important phase.** Do NOT skip it. Do NOT proceed to version bump until all tests pass (or all failures are accounted for).

### Run the Full Test Suite

```bash
# Rust (most common in this fleet)
cargo test --workspace 2>&1 | tee /tmp/test-output.txt
echo "Exit code: $?"

# Also run e2e tests if they exist
ls scripts/e2e_test.sh tests/e2e/ 2>/dev/null && echo "E2E tests exist"

# Check for clippy warnings
cargo clippy --workspace --all-targets 2>&1 | tail -20
```

### Triage Test Failures

When tests fail, categorize each failure:

| Category | What It Means | Action |
|----------|---------------|--------|
| **Obsolete assertion** | Code changed, test wasn't updated | Update the test to match current behavior |
| **Missing struct fields** | New fields added, test constructors incomplete | Add missing fields with defaults |
| **Changed API signature** | Function signature evolved | Update test call sites |
| **Real bug** | Test caught actual broken code | Fix the code, not the test |
| **Flaky / timing** | Race condition or timeout | Fix the flake or mark `#[ignore]` with comment |
| **Pre-existing failure** | Already broken on HEAD before your changes | Fix if quick, document if not |

### Fix Obsolete Tests

The most common pattern — struct fields were added but test constructors weren't updated:

```rust
// BEFORE (test fails: missing field `embedding_retries`)
IndexingProgressSnapshot {
    total_files: 100,
    indexed_files: 50,
    // ... old fields
}

// AFTER (add missing fields with sensible defaults)
IndexingProgressSnapshot {
    total_files: 100,
    indexed_files: 50,
    // ... old fields
    embedding_retries: 0,
    embedding_failures: 0,
    semantic_deferred_files: 0,
    embedder_degraded: false,
    degradation_reason: None,
    recent_warnings: vec![],
}
```

### Fix Real Bugs

If a test reveals an actual bug in the code:

1. Understand the test's intent (read the test name and assertions)
2. Read the code under test
3. Fix the code to satisfy the test's contract
4. Verify the fix doesn't break other tests
5. Run the full suite again

### Re-run Until Green

```bash
# After fixing, run again
cargo test --workspace

# If you fixed specific tests, run those first for fast feedback
cargo test --workspace -- test_name_pattern

# Final full run must be clean
cargo test --workspace 2>&1 | tail -3
# Should show: "test result: ok. N passed; 0 failed"
```

### Document Pre-Existing Failures

If some tests were already broken before your session and are unrelated to the release:

```bash
# Run targeted tests to confirm your changes are clean
cargo test --workspace -- --skip known_broken_test
```

Note these for the user but don't let them block the release if they're clearly pre-existing.

Full test-fixing deep dive: [TEST-FIXING.md](references/TEST-FIXING.md)

---

## Phase 3: Version Bump

### Rust Workspace Projects

```bash
# Check workspace structure
grep -A5 '\[workspace\]' Cargo.toml

# Bump root version
# Edit Cargo.toml: version = "X.Y.Z" -> "X.Y.Z+1"

# Bump workspace member versions (if they have their own versions)
for toml in $(find . -name Cargo.toml -not -path './target/*'); do
  grep '^version = ' "$toml"
done

# Update Cargo.lock
cargo check --workspace
```

**Critical**: In workspace projects, bump ALL member crate versions to stay in sync. Check for `version.workspace = true` (inherits from root) vs explicit versions.

### Workspace Version Inheritance

```toml
# Root Cargo.toml — workspace version
[workspace.package]
version = "0.2.0"

# Member Cargo.toml — inherits
[package]
version.workspace = true
```

If using workspace inheritance, you only need to bump the root. Otherwise, bump each member.

### Node.js Projects

```bash
# Bump version (also updates package-lock.json)
npm version patch  # or minor, major
```

### Python Projects

```bash
# Edit pyproject.toml or setup.cfg version field
grep version pyproject.toml
```

---

## Phase 4: Build & Release

There are two paths. **Choose one based on the project's infrastructure.**

### Path A: GitHub Actions (Default — Most Projects)

Most projects have CI workflows that build cross-platform binaries and create GitHub releases automatically when a tag is pushed. This is the preferred path.

#### Step 1: Verify CI Workflows Exist

```bash
# Check for release/dist workflows
ls .github/workflows/*release* .github/workflows/*dist* 2>/dev/null

# Understand trigger: tag-push? version-bump detection? manual?
grep -l 'tags:' .github/workflows/*.yml 2>/dev/null
grep -l 'workflow_dispatch' .github/workflows/*.yml 2>/dev/null
```

Common patterns (use `/gh-actions` for deeper reference):
- **Tag-triggered**: `dist.yml` triggers on `v*` tag push → builds + uploads assets
- **Version-bump detection**: `release-automation.yml` watches for version changes in Cargo.toml → creates tag → triggers dist
- **Manual dispatch**: `workflow_dispatch` input for version

#### Step 2: Commit Version Bump and Push

```bash
git add Cargo.toml Cargo.lock */Cargo.toml
git commit -m "$(cat <<'EOF'
chore: bump version to X.Y.Z for release

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
git push
```

#### Step 3: Sync Branches (if AGENTS.md requires it)

```bash
# Many projects require main -> master sync
git push origin main:master
```

#### Step 4: Create and Push Tag

```bash
VERSION="vX.Y.Z"
git tag -a "$VERSION" -m "Release $VERSION"
git push --tags
```

If the project uses `release-automation.yml` that auto-creates tags from version bumps, skip this — but verify the tag appeared:

```bash
# Wait ~30s then check
git ls-remote --tags origin | grep "$VERSION"
```

**Gotcha:** If both `main` and `master` trigger release-automation, one run may fail with "tag already exists" — this is harmless. See [OP-7](references/OPERATOR-PATTERNS.md).

#### Step 5: Monitor CI Build

```bash
# List recent workflow runs
gh run list --limit 5

# Find the dist/release run triggered by your tag
gh run list --workflow dist.yml --limit 3

# Watch it in real-time
gh run watch <run-id>

# If it's taking too long, check individual jobs
gh run view <run-id> --json jobs | jq '.jobs[] | {name, status, conclusion}'
```

**Gotcha:** GitHub Actions bot-created tags don't trigger downstream workflows (anti-recursion). If `release-automation.yml` created the tag but `dist.yml` didn't fire, manually trigger it:

```bash
gh workflow run dist.yml -f ref=vX.Y.Z
# Or: gh workflow run dist.yml --ref vX.Y.Z
```

See [OP-2](references/OPERATOR-PATTERNS.md).

#### Step 6: Handle CI Failures

If CI fails (clippy lint, test failure, CI script bug):

```bash
# 1. Check what failed
gh run view <run-id> --log-failed 2>&1 | tail -40

# 2. Fix locally
# Common: clippy nightly drift (OP-3), static binary verification (OP-4),
#         musl-incompatible deps like ort/ONNX (OP-16)

# 3. Commit and push the fix
git add -A && git commit -m "fix: <what broke in CI>"
git push && git push origin main:master

# 4. Update the tag to include the fix
git tag -f "$VERSION"
git push --tags -f
# If dcg blocks force-push, create vX.Y.(Z+1) instead (OP-11)

# 5. Re-trigger
gh workflow run dist.yml -f ref="$VERSION"

# 6. Monitor
gh run list --workflow dist.yml --limit 3
gh run watch <new-run-id>
```

**Key insight from sessions:** A prior release required 3 rounds of fix-commit-retag-retrigger (clippy lint, then static binary verification bug, then aarch64-musl build issue). Budget time for CI iteration.

#### Step 7: Verify the Release

```bash
# Check release was created with all expected assets
gh release view "$VERSION"
gh release view "$VERSION" --json assets | jq '.assets[].name'

# Download and test a binary
gh release download "$VERSION" --pattern "*linux*x86_64*"
tar xzf *.tar.gz
./<binary> --version   # Must match the release version
```

---

### Path B: Local Build with dsr/rch (Fallback)

Use this path when:
- GH Actions queue > 10 min (`dsr check --all`)
- CI is broken or unreliable
- Cargo.toml has absolute local path dependencies (CI can't resolve these)
- You need an immediate release and can't wait for CI
- musl-incompatible deps (ort, onnx) and CI only builds musl

#### Check Infrastructure

```bash
which dsr && dsr doctor
which rch && rch check
```

#### CRITICAL: Bypass RCH for Release Builds

If RCH hooks are installed, `cargo build --release` will be intercepted and sent to a remote worker. The binaries won't be in your local `target/release/`:

```bash
RCH_DISABLED=1 cargo build --release
ls -la target/release/<binary>
target/release/<binary> --version   # Verify version BEFORE packaging
```

See [OP-1](references/OPERATOR-PATTERNS.md).

#### Check Remote Host Disk Space

```bash
ssh mac-host 'df -h / && du -sh ~/projects/*/target 2>/dev/null | sort -h | tail -5'
# Clean if < 2GB: ssh mac-host 'find ~/projects -name target -type d -exec rm -rf {} + 2>/dev/null'
```

See [OP-5](references/OPERATOR-PATTERNS.md).

#### Build with dsr

```bash
dsr repos list | grep <project>                    # Check registered
dsr build <tool> --version <version>               # Build all targets
# Or: dsr fallback <tool> <version>                # Full pipeline
```

#### Build with rch

```bash
rch workers probe --all
rch exec -- cargo build --release
```

#### Manual Cross-Platform Builds

```bash
# Linux
RCH_DISABLED=1 cargo build --release && strip target/release/<binary>

# Mac (check disk first!)
ssh mac-host 'df -h /' && ssh mac-host "cd ~/projects/PROJECT && git pull && cargo build --release"

# Package
tar czf <tool>-v<version>-x86_64-unknown-linux-gnu.tar.gz -C target/release <binary>
```

#### Path Dependency Remapping for Mac

If Cargo.toml uses absolute local paths (e.g., `/projects/`), the Mac build host needs remapping since paths differ there:

```bash
grep 'path = "/' Cargo.toml   # Find absolute path deps
rsync -az --exclude target/ ./ mac-host:~/projects/PROJECT/
ssh mac-host "cd ~/projects/PROJECT && sed -i '' 's|/projects/|$HOME/projects/|g' Cargo.toml && cargo build --release"
```

See [OP-6](references/OPERATOR-PATTERNS.md) for the full story.

#### Commit, Tag, and Upload

```bash
# Commit version bump
git add Cargo.toml Cargo.lock */Cargo.toml
git commit -m "chore: bump version to X.Y.Z" && git push
git push origin main:master   # If needed

# Tag
VERSION="vX.Y.Z"
git tag -a "$VERSION" -m "Release $VERSION" && git push --tags

# Generate checksums
cd artifacts/ && sha256sum *.tar.gz *.zip > SHA256SUMS.txt

# Create release with artifacts
gh release create "$VERSION" --title "$VERSION" --generate-notes \
  artifacts/*.tar.gz artifacts/*.zip artifacts/SHA256SUMS.txt
```

Full build matrix and host details: [BUILD-MATRIX.md](references/BUILD-MATRIX.md).

---

## Phase 5: Verify

### Verify Release Assets

```bash
gh release view "$VERSION"
gh release view "$VERSION" --json assets | jq '.assets[].name'
```

### Test Installer (if project has one)

```bash
# Test on a remote machine — NOT the build machine
ssh <host> 'curl -fsSL "https://raw.githubusercontent.com/USER/REPO/main/install.sh" | bash'
ssh <host> '<binary> --version'
```

**Gotcha:** Verify the installer's expected target triples match the release asset names. Mismatches cause silent fallback to source compilation. See [OP-15](references/OPERATOR-PATTERNS.md).

### Verify Binary

```bash
gh release download "$VERSION" --pattern "*linux*"
tar xzf *.tar.gz
./<binary> --version   # Must match release version
```

### Publish to crates.io (Optional)

If the project is a published crate, use `/rust-crates-publishing` after the GitHub release is verified. Key points:
- Publish in dependency order (leaves first) — see [OP-9](references/OPERATOR-PATTERNS.md)
- Path deps need `version = "X.Y.Z"` alongside `path = "..."` — see [OP-8](references/OPERATOR-PATTERNS.md)
- Wait ~30s between publishes for index propagation

---

## Common Pitfalls from Past Sessions

| Pitfall | What Happened | Prevention | See |
|---------|---------------|------------|-----|
| **Missing struct fields in tests** | New fields added to structs, test constructors not updated | Always run full test suite before release | TEST-FIXING.md |
| **Installer expects wrong target triple** | install.sh expected `musl`, release had `gnu` | Audit installer target names vs release asset names | OP-15 |
| **Path deps block CI** | Absolute local paths can't resolve in CI | Build locally with dsr when path deps exist | OP-6 |
| **Workspace version drift** | Root bumped but members left behind | Bump ALL workspace members, check for `version.workspace = true` | |
| **/tmp full during release** | Git operations fail with no space | Use `TMPDIR=/data/tmp` as workaround | OP-12 |
| **License field mismatch** | Cargo.toml says MIT but LICENSE file has a rider | Verify license field matches actual LICENSE | |
| **Tag force-push blocked by protection** | Can't update tag after extra commit | Accept 1-commit offset or create patch version | OP-11 |
| **Missing dependency in CLI crate** | Workspace dep exists but CLI doesn't list it | `cargo build --release` catches this early | |
| **RCH intercepts release build** | Binaries end up on remote worker, not local | Use `RCH_DISABLED=1 cargo build --release` | OP-1 |
| **GH Actions bot tag doesn't trigger dist** | Tag created by automation, dist.yml never runs | Manually trigger: `gh workflow run dist.yml` | OP-2 |
| **Clippy nightly drift** | Newer nightly on CI catches lints local misses | Run `cargo clippy --workspace --all-targets -- -D warnings` BEFORE tagging | OP-3 |
| **Static binary verification fails** | `ldd` output contains "dynamic" for static binaries | Use `file binary \| grep "statically linked"` instead | OP-4 |
| **Remote build host out of disk space** | rsync/build fails mid-way | Check `df -h` on remote hosts BEFORE building | OP-5 |
| **release-automation race (main vs master)** | Both branches trigger, one fails harmlessly | Expected — just verify the tag was created | OP-7 |
| **Path deps missing version for crates.io** | `cargo publish` fails without version specifier | Add `version = "X.Y.Z"` alongside `path = "..."` | OP-8 |
| **Missing README blocks crates.io** | `readme = "README.md"` but file doesn't exist | Remove the readme field or create the file | OP-10 |
| **ort/ONNX doesn't support musl** | Linux musl builds fail for ONNX projects | Feature-gate or use gnu targets | OP-16 |

---

## Anti-Patterns

| Don't | Do Instead |
|-------|------------|
| Skip test suite | ALWAYS run tests before bumping version |
| Fix tests by deleting them | Update assertions to match current behavior |
| Release without reading AGENTS.md | Read it first — conventions vary per project |
| Bump version without committing first | Commit all pending changes before version bump |
| Create release before pushing tag | Push tag first, then create release (Path A) |
| Ignore pre-existing test failures | Document them, fix if quick |
| Skip installer verification | Test the installer on a real machine |
| Wait forever for CI that won't trigger | Check if bot-created tag; manually trigger dist (OP-2) |
| Panic when one CI run "fails" | Check if it's just a race (main vs master, OP-7) |
| Jump to local build on first CI failure | Fix the CI issue — it'll bite you next release too |
| Build locally when CI works fine | Let CI do the cross-platform matrix; it's more reproducible |

---

## Integration with Other Skills

| Skill | When to Use |
|-------|-------------|
| `/gh-actions` | Setting up or debugging CI release workflows (Path A) — the primary path for most projects |
| `/dsr` | Building and releasing when GH Actions is throttled or has path-dep issues (Path B fallback) |
| `/rch` | Offloading builds to remote workers (Path B fallback) |
| `/commit-and-release` | Batch committing before release |
| `/library-updater` | Updating deps before release (do this BEFORE test gate) |
| `/rust-crates-publishing` | Publishing to crates.io after GitHub release is verified |
| `/ubs` | Running static analysis before release |
| `/installer-workmanship` | Writing/fixing curl\|bash install scripts |
| `/changelog-md-workmanship` | Generating a proper CHANGELOG.md from git history |

---

## Post-Release: Fresh Eyes Review

After the release is live, do a quick review pass (mined from a prior release session):

```bash
# What files changed since last release?
git diff $(git describe --tags --abbrev=0 HEAD~1)..HEAD --name-only

# For each changed file, verify:
# - Test fixes preserve the test's original intent
# - Default values (0, None, vec![]) are actually correct
# - Version string is used correctly (env!("CARGO_PKG_VERSION"))
# - No debug println! or temporary code left behind
```

---

## Batch Release: Scan All Projects

After releasing one project, scan for others that need releases (mined from an earlier batch release session):

```bash
# Find all Rust projects with unreleased commits
PROJECTS_DIR=~/projects  # Adjust to your projects directory
for d in "$PROJECTS_DIR"/*; do
  [ -f "$d/Cargo.toml" ] || continue
  cd "$d" 2>/dev/null || continue
  LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
  [ -z "$LAST_TAG" ] && { cd "$PROJECTS_DIR"; continue; }
  COUNT=$(git rev-list --count ${LAST_TAG}..HEAD 2>/dev/null)
  [ "$COUNT" -gt 0 ] && echo "$d: $COUNT commits since $LAST_TAG"
  cd "$PROJECTS_DIR"
done

# Check which are on crates.io (need publish too)
for d in "$PROJECTS_DIR"/*; do
  grep -q 'crates.io' "$d/Cargo.toml" 2>/dev/null && echo "$d: on crates.io"
done
```

Use parallel subagents for independent releases.

---

## References

| Topic | File |
|-------|------|
| Test fixing patterns | [TEST-FIXING.md](references/TEST-FIXING.md) |
| Cross-platform build matrix | [BUILD-MATRIX.md](references/BUILD-MATRIX.md) |
| Release checklist | [RELEASE-CHECKLIST.md](references/RELEASE-CHECKLIST.md) |
| Operator patterns (17 session-mined) | [OPERATOR-PATTERNS.md](references/OPERATOR-PATTERNS.md) |
