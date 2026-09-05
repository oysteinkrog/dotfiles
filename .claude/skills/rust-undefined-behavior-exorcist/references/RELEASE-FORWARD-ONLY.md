# Release Forward-Only — The Topological Re-Publish Workflow

Anchor: cass Q-501 — *"asupersync v0.2.6 — All 7 crates published to crates.io in dependency order"* / *"Publish frankensqlite to crates.io — 22 crates, ~13 min — With 35s sleep between each for index propagation."*

The user's release pattern is **forward-only**: bump the workspace version, re-publish the entire dependency closure in topological order with a per-crate sleep. No backporting.

This file documents the workflow + how the UB exorcist composes with it.

---

## The pattern

```
1. Bump workspace version in top-level Cargo.toml
2. Bump member crate versions (workspace.dependencies if used)
3. Topologically sort the workspace dependency graph
4. For each crate in topo order:
     - cargo publish
     - sleep 35s     (let crates.io index propagate)
5. Tag the workspace: git tag v$VERSION
6. Push tag: git push github v$VERSION
7. Push branch: git push github main
```

Mined from Q-501 specifically:
- **`pi_agent_rust v0.1.7`** — single crate; tag `v0.1.7` to commit `5bffab9e`
- **`asupersync v0.2.6`** — 7 crates in dep order; tag pushed to both `main` and `master` branches on origin
- **`frankensqlite v?`** — 22 crates, ~13 min, 35s sleep per crate

---

## Why 35 seconds?

Crates.io's index is a Git repo (`crates.io-index`). After `cargo publish`, the new version takes seconds-to-minutes to appear in the index. If the next crate in the topo order depends on the just-published one and the index hasn't updated yet, `cargo publish` for crate B fails with "dependency not found".

35 seconds is the user's empirically-tuned floor. Increase if the index is slow (during peak hours).

---

## Topological order

For an N-crate workspace, the topological order is the reverse DFS post-order on the dep graph. Tools:

```bash
# Using cargo-workspaces:
cargo workspaces ls --json | jq -r '.[] | .name' | xargs cargo tree -p ...

# Or with cargo-hakari / cargo-workspaces:
cargo workspaces list --topological
```

If `cargo workspaces` isn't available, hand-roll:

```bash
# Heuristic: leaves of the dep graph publish first.
# The angle-bracket "<... topo sort ...>" form is a bash syntax error (bash
# treats `<` as redirection); insert your own topo-sort pipeline instead.
for crate in $(cargo metadata --format-version=1 \
                | jq -r '.packages[] | .name' \
                | sort); do
  # TODO: pipe through a real topo-sort by dep edges before this loop.
  echo "$crate"
done
```

Always sanity-check the order: a crate that depends on `<foo>` must publish *after* `<foo>`.

---

## Script template

```bash
#!/usr/bin/env bash
# release-forward-only.sh — topological re-publish.
set -euo pipefail

REPO="${1:?repo dir required}"
VERSION="${2:?version required (e.g., 0.2.6)}"
INTER_CRATE_SLEEP="${INTER_CRATE_SLEEP:-35}"

cd "$REPO"

# Step 1-2: bump versions
# (caller is expected to have done this via cargo workspaces or manually)

# Step 3: topological order
CRATES=$(cargo workspaces list --topological 2>/dev/null \
        || cargo metadata --format-version=1 \
           | jq -r '.packages[] | .name' \
           | sort)

# Step 4: publish each
for crate in $CRATES; do
    echo "=== Publishing $crate v$VERSION ==="
    if cargo publish -p "$crate" --no-verify; then
        echo "  [✓] published"
    else
        echo "  [✗] failed; aborting" >&2
        exit 1
    fi
    sleep "$INTER_CRATE_SLEEP"
done

# Step 5: tag
git tag "v$VERSION"
echo "Tagged v$VERSION."

# Step 6-7: push (manual confirmation per AGENTS.md)
echo
echo "Next steps (run manually):"
echo "  git push github v$VERSION"
echo "  git push github main"
```

---

## UB exorcism integration

When Phase 9 lands the bead ladder for a UB remediation, the release happens *after* all beads close. The release-bead chain (per [UB-BEAD-LADDER.md](UB-BEAD-LADDER.md)):

```
[remediation epic]
  ...
  br-205 [e2e]              All tests green
  br-206 [docs]             SAFETY comments updated
  br-207 [release-prep]     Bump workspace version + member versions
                           depends on br-205, br-206
  br-208 [release-publish]  scripts/release-forward-only.sh ...
                           depends on br-207
  br-209 [release-tag]      git tag v$VERSION; push
                           depends on br-208
  br-210 [advisory]         File RUSTSEC advisory (if applicable)
                           depends on br-209
```

---

## What about backporting?

Per Q-501 evidence, the user does NOT backport. The release model is forward-only.

The [BACKPORTING.md](BACKPORTING.md) document in the skill is therefore an *advisory-only* reference — it covers the case where a downstream consumer asks for a backport. The user's first-line response is: "Upgrade to the latest version; that's where the fix is."

When backport DOES apply (rare for this user; common for OSS-with-paying-customers projects):
- Treat as a separate parallel ladder branched from a `release-N.M` branch
- Cherry-pick the minimal fix from main
- See [BACKPORTING.md](BACKPORTING.md) for the full workflow

---

## Naming the version

For a UB-fix release, the version bump follows semver strictly:
- **Patch bump** (0.x.Y → 0.x.Y+1): UB fix without public API change
- **Minor bump** (0.X.y → 0.X+1.0): UB fix requires public API change (e.g., adding a `cx` parameter — see Q-103)
- **Major bump**: rare for UB fixes; reserved for "intent of API changed" cases

Tag format: `v$VERSION` (e.g., `v0.2.6`, `v1.0.0-rc.3`).

For OSS releases with downstream awareness, also tag a soundness-specific reference:

```bash
git tag v0.2.6
git tag soundness-fix-RUSTSEC-2026-XXXX
git push github v0.2.6 soundness-fix-RUSTSEC-2026-XXXX
```

The second tag lets advisories link to a specific commit.

---

## Both `main` and `master` branches

Q-501: *"Pushed to both `main` and `master` branches on origin."* Some of the user's projects maintain both branch names (one is symbolic for the other). The release script should push to both if both exist:

```bash
for branch in main master; do
    if git rev-parse --verify --quiet "$branch" >/dev/null; then
        git push github "$branch"
    fi
done
```

---

## Honest gap

Cass deep-mining round 2 shows zero hits for `cargo yank` (the "undo a release" operation). If a UB-bearing release went out by mistake, the user may not have done a yank historically. The skill recommends `cargo yank` for soundness-grade regressions even if it's a new practice — see [DISCLOSURE.md](DISCLOSURE.md).

---

## Cross-references

- cass Q-501 — verbatim source
- [UB-BEAD-LADDER.md](UB-BEAD-LADDER.md) — bead structure
- [BACKPORTING.md](BACKPORTING.md) — backport workflow when needed
- [DISCLOSURE.md](DISCLOSURE.md) — advisory + yank workflow
- [WORKTREE-PATTERNS.md](WORKTREE-PATTERNS.md) — retired worktree guidance; current active-checkout/remote-selection rules
- `/rust-crates-publishing` skill — broader release context
