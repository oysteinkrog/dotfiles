#!/usr/bin/env bash
# release-forward-only.sh — topological re-publish of every crate in a Rust
# workspace; no force-push, no history rewrite, no remote operations beyond
# `cargo publish`. See RELEASE-FORWARD-ONLY.md.
#
# Usage:
#   release-forward-only.sh <repo> <version>
#
# Env vars:
#   INTER_CRATE_SLEEP    Seconds to sleep between publishes (default 35; crates.io
#                        index propagation can lag).
#   CARGO_PUBLISH_FLAGS  Extra flags appended to `cargo publish` (default --no-verify).
#   DRY_RUN              If set to "1", prints the plan but does not run publish or tag.
#
# Workflow:
#   1. Validate repo is git + has Cargo.toml.
#   2. Verify the working tree is clean (uncommitted changes block release).
#   3. Verify every crate's manifest already declares the target version (caller
#      bumped them; this script doesn't edit manifests).
#   4. Compute topological order (cargo workspaces if installed, else metadata).
#   5. For each crate: cargo publish; sleep INTER_CRATE_SLEEP on success; abort
#      on failure (do NOT continue).
#   6. After all publishes: git tag v$VERSION (annotated).
#   7. Print manual push commands (per AGENTS.md: never push without explicit OK).
#
# Exit codes:
#   0 — all crates published, tag created locally, push commands printed
#   1 — at least one cargo publish failed (no tag created)
#   2 — usage / repo / clean-tree / version-mismatch / missing dep (jq)
set -euo pipefail

case "${1:-}" in
    -h|--help)
        awk 'NR>1 && /^#/{sub(/^# ?/, ""); print; next} NR>1{exit}' "$0"
        exit 0
        ;;
esac

if [[ $# -ne 2 ]]; then
    echo "Usage: release-forward-only.sh <repo> <version>" >&2
    exit 2
fi

REPO="$1"
VERSION="$2"

if ! command -v jq >/dev/null 2>&1; then
    echo "jq not installed (required to parse cargo metadata). Install via apt/brew/dnf." >&2
    exit 2
fi

INTER_CRATE_SLEEP="${INTER_CRATE_SLEEP:-35}"
CARGO_PUBLISH_FLAGS="${CARGO_PUBLISH_FLAGS:---no-verify}"
DRY_RUN="${DRY_RUN:-0}"

REPO_REAL="$(realpath -m "$REPO")"
if [[ ! -d "$REPO_REAL/.git" ]]; then
    echo "Not a git repo: $REPO_REAL" >&2
    exit 2
fi
if [[ ! -f "$REPO_REAL/Cargo.toml" ]]; then
    echo "No Cargo.toml at $REPO_REAL" >&2
    exit 2
fi
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?$ ]]; then
    echo "Version doesn't look like semver: $VERSION" >&2
    exit 2
fi

cd "$REPO_REAL"

# 2. Working tree clean?
if [[ "$DRY_RUN" != "1" ]] && [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree has uncommitted changes — refusing to release." >&2
    echo "Commit or stash first." >&2
    git status --short >&2
    exit 2
fi

# 3. Verify every crate's version matches
mismatch=0
while IFS= read -r line; do
    crate=$(echo "$line" | jq -r '.name')
    declared=$(echo "$line" | jq -r '.version')
    if [[ "$declared" != "$VERSION" ]]; then
        echo "Version mismatch: $crate declares $declared, expected $VERSION" >&2
        mismatch=$((mismatch+1))
    fi
done < <(cargo metadata --format-version=1 --no-deps 2>/dev/null \
         | jq -c '.packages[] | {name, version}')

if [[ "$mismatch" -gt 0 ]]; then
    echo "Bump all crate versions to $VERSION before re-running." >&2
    exit 2
fi

# 4. Topological order
if command -v cargo-workspaces >/dev/null 2>&1; then
    CRATES=$(cargo workspaces list --topological 2>/dev/null || true)
fi
if [[ -z "${CRATES:-}" ]]; then
    # Fallback: metadata + tsort by dependency
    CRATES=$(
        cargo metadata --format-version=1 --no-deps 2>/dev/null \
        | jq -r '
            .packages as $pkgs |
            $pkgs[] |
            . as $p |
            ([ $p.dependencies[] | select(.path) | .name ]) as $deps |
            ($deps[]? + " " + $p.name),
            ($p.name + " " + $p.name)
        ' \
        | tsort 2>/dev/null \
        | awk 'NF==1' \
        | uniq
    )
fi

if [[ -z "$CRATES" ]]; then
    echo "Could not determine topological order; aborting." >&2
    exit 2
fi

echo "=== Release-forward-only — $VERSION ==="
echo "Topological order:"
while IFS= read -r crate; do
    [[ -n "$crate" ]] && printf '  %s\n' "$crate"
done <<< "$CRATES"
echo

if [[ "$DRY_RUN" == "1" ]]; then
    echo "DRY_RUN=1 — would publish each crate then tag v$VERSION; exiting."
    exit 0
fi

# 5. Publish each
FAILED_CRATE=""
while IFS= read -r crate; do
    [[ -z "$crate" ]] && continue
    echo "── Publishing $crate v$VERSION ──"
    # shellcheck disable=SC2086
    if cargo publish -p "$crate" $CARGO_PUBLISH_FLAGS; then
        echo "  [✓] $crate published"
        echo "  Sleeping ${INTER_CRATE_SLEEP}s for crates.io index propagation..."
        sleep "$INTER_CRATE_SLEEP"
    else
        echo "  [✗] $crate FAILED; aborting (no tag created)" >&2
        FAILED_CRATE="$crate"
        break
    fi
done <<< "$CRATES"

if [[ -n "$FAILED_CRATE" ]]; then
    echo
    echo "FAILURE: $FAILED_CRATE did not publish. The crates that DID publish are now"
    echo "live on crates.io but the workspace is partially released."
    echo "Recovery: investigate the failure, fix, and re-run THIS script — already-published"
    echo "crates will skip themselves with 'crate version already exists'."
    exit 1
fi

# 6. Tag (annotated, references the audit run if a workspace is around)
TAG_MSG="Release $VERSION (forward-only re-publish)"
if [[ -d "$REPO_REAL/.ub-exorcism" ]]; then
    # Pick by mtime (newest), not lexical sort — workspace names use various
    # schemes (timestamp, slug+date, …) and the most recent audit is the one
    # to attribute. Print "<epoch>\t<basename>", sort -rn, then cut.
    RUN_ID=$(find "$REPO_REAL/.ub-exorcism" -mindepth 1 -maxdepth 1 -type d \
                  -printf '%T@\t%f\n' 2>/dev/null \
             | sort -rn | head -1 | cut -f2-)
    [[ -n "$RUN_ID" ]] && TAG_MSG="$TAG_MSG (audit run $RUN_ID)"
fi
git tag -a "v$VERSION" -m "$TAG_MSG"
echo "Tagged v$VERSION locally."

# 7. Print manual-push instructions per AGENTS.md (no auto-push)
echo
echo "═══════════════════════════════════════════════════════════════════"
echo "Next steps (RUN MANUALLY — AGENTS.md forbids auto-push):"
echo "  git push origin v$VERSION"
echo "  git push origin main"
echo "  # If the repo mirrors to a 'master' branch:"
echo "  git push origin main:master"
echo "═══════════════════════════════════════════════════════════════════"
exit 0
