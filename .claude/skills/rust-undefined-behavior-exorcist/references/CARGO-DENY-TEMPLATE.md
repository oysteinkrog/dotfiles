# cargo-deny Template — Modern `db-urls` Form

Anchor: cass Q-601 — the user's `deny.toml` migration from deprecated `url=` to modern `db-urls = [...]`.

---

## The corpus-verified `deny.toml`

```toml
[advisories]
# Modern form (Rust 2024); the bare `url=` was deprecated.
db-urls = ["https://github.com/rustsec/advisory-db"]

# Per the user's existing CI practice — deny vulnerabilities by default.
vulnerability = "deny"
unmaintained = "warn"
yanked = "warn"
notice = "warn"

# Confidence threshold for unmaintained / notice classification.
# Default is "medium"; "high" reduces false positives at the cost of slower
# detection.
severity-threshold = "medium"

# Specific advisories to ignore (with rationale). Only add here after
# investigation; this is the soundness-bypass surface.
ignore = [
    # Example:
    # "RUSTSEC-2024-0001",  # Affects only a feature we don't enable; tracked at issue #N
]

[bans]
# Disallow specific crate versions (forks, vulnerable, etc.)
multiple-versions = "warn"
wildcards = "deny"

[licenses]
# Standard OSS license allowlist
allow = [
    "MIT",
    "Apache-2.0",
    "Apache-2.0 WITH LLVM-exception",
    "BSD-2-Clause",
    "BSD-3-Clause",
    "ISC",
    "Unicode-DFS-2016",
    "CC0-1.0",
]

[sources]
# Restrict sources to crates.io + your own forks (if any)
unknown-registry = "deny"
unknown-git = "warn"
```

---

## CI integration

```yaml
deny:
  runs-on: ubuntu-latest
  timeout-minutes: 5
  steps:
    - uses: actions/checkout@v4
    - uses: dtolnay/rust-toolchain@stable
    - uses: Swatinem/rust-cache@v2
      with: { key: deny }
    - run: cargo install --locked cargo-deny
    - run: cargo deny check
```

The job runs in <2 minutes (after first run; subsequent runs are cached). Failure = a new RustSec advisory landed against one of your deps.

---

## What `cargo deny check` does

It runs four sub-checks:

1. **advisories** — Cross-reference `Cargo.lock` against the RustSec advisory database
2. **bans** — Forbid specific crates/versions you've disallowed
3. **licenses** — Verify all dep licenses are in the allow list
4. **sources** — Verify crates come from approved registries

For UB-exorcism purposes, **advisories** is the critical one. The audit may have produced a RustSec entry (see [DISCLOSURE.md](DISCLOSURE.md)); downstream consumers' `cargo deny` will catch when they need to upgrade.

---

## Honoring the audit's outputs

When Phase 12 produces a `RUSTSEC-YYYY-XXXX.md` advisory, the entries flow to `rustsec/advisory-db`. Downstream consumers' `deny.toml`:
- Picks up the advisory automatically (it's in `db-urls`)
- Flags every consumer of the affected version range
- Forces an upgrade or an `ignore` entry with rationale

This is the *post-audit lifecycle* — `cargo deny` is how the audit's findings reach downstream users.

---

## Migration from old `url=` form

If the project still uses the deprecated:
```toml
[advisories]
url = "https://github.com/rustsec/advisory-db"
```

Update to:
```toml
[advisories]
db-urls = ["https://github.com/rustsec/advisory-db"]
```

`cargo deny` 0.14+ requires the array form. Older versions accept both during migration.

---

## When to add multiple db-urls

If your organization maintains a private advisory DB (e.g., for internal-only crates), add it:

```toml
[advisories]
db-urls = [
    "https://github.com/rustsec/advisory-db",
    "https://github.internal.example.com/security/advisory-db",
]
```

`cargo deny` checks both; if any flags a crate, the build fails.

---

## Cross-references

- cass Q-601 — verbatim source
- [DISCLOSURE.md](DISCLOSURE.md) — RustSec workflow
- [TOOLING.md §cargo-audit / cargo-deny](TOOLING.md#cargo-audit--cargo-deny) — broader tool context
