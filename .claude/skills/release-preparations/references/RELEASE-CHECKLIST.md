# Release Checklist

Copy-paste checklist for release preparation. Each step must be completed in order.

## Pre-Flight

- [ ] Read AGENTS.md for project-specific conventions
- [ ] Check current version: `grep '^version' Cargo.toml | head -1`
- [ ] Check latest release: `gh release list --limit 3`
- [ ] Count commits since last release: `git rev-list --count $(git describe --tags --abbrev=0)..HEAD`
- [ ] Review changelog: `git log --oneline $(git describe --tags --abbrev=0)..HEAD`
- [ ] Check for uncommitted changes: `git status --short`
- [ ] Commit or stash any pending work before proceeding

## Test Gate

- [ ] Run full test suite: `cargo test --workspace`
- [ ] All tests pass (or failures are categorized and fixed)
- [ ] Run clippy: `cargo clippy --workspace --all-targets`
- [ ] Run e2e tests if they exist: `./scripts/e2e_test.sh`
- [ ] Run UBS if configured: `ubs $(git diff --name-only)`

## Version Bump

- [ ] Determine version number (ask user if unclear)
- [ ] Bump version in root Cargo.toml
- [ ] Bump version in all workspace member Cargo.toml files
- [ ] Run `cargo check --workspace` to update Cargo.lock
- [ ] Verify version: `grep '^version' Cargo.toml | head -1`

## Build

- [ ] Check dsr availability: `which dsr && dsr doctor`
- [ ] Check GH Actions throttling: `dsr check --all` or `gh run list --limit 3`
- [ ] Build for primary platform: `cargo build --release`
- [ ] Build for all targets (dsr or manual)
- [ ] Verify binary version: `target/release/<binary> --version`

## Release

- [ ] Commit version bump: `git add Cargo.toml Cargo.lock */Cargo.toml && git commit`
- [ ] Push to remote: `git push`
- [ ] Sync branches if needed: `git push origin main:master`
- [ ] Create tag: `git tag -a vX.Y.Z -m "Release vX.Y.Z" && git push --tags`
- [ ] Generate SHA256SUMS for artifacts
- [ ] Create GitHub release with artifacts
- [ ] Verify release: `gh release view vX.Y.Z`

## Post-Release Verification

- [ ] Verify release assets are complete: `gh release view vX.Y.Z --json assets | jq '.assets[].name'`
- [ ] Test installer on remote machine (if applicable)
- [ ] Verify installed binary version matches release
- [ ] Publish to crates.io (if applicable, use /rust-crates-publishing)

## Hand-Off

- [ ] Report release URL to user
- [ ] Note any pre-existing test failures that were not fixed
- [ ] Note any platforms that failed to build
