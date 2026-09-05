# Remote-As-Worktree Footgun — When `origin` Points to a Local Path

In multi-worktree workflows, a worktree's `origin` remote sometimes points at **another local working tree** (a sibling worktree, or a separate clone of the same repo) instead of the actual upstream. Pushes to `origin` go to the wrong place. Cherry-picks from `origin/<branch>` pull from the wrong tree.

Cass-mined source session: `frankensqlite`'s `origin` was set to `file:///data/projects/frankensqlite-wt-bench` (a sibling worktree) instead of `https://github.com/owner/frankensqlite.git`. The agent had to use `github` as the upstream remote name, with `origin` reserved for the local-fork relationship. Phase 11's push instructions had to print `git push github branch-rationalization-<DATE>`, not `git push origin ...`.

> **The premise.** `git remote -v` is the single source of truth for what `origin` actually points at. The skill must consult it, classify each remote, and refuse to print stale push instructions or run cleanup that depends on a confused topology.

---

## 1. The footgun

A worktree (or a fresh clone) gets its `origin` set to a local path in three common cases:

| Setup pattern | Resulting `origin` |
|---|---|
| `git clone /data/projects/foo /data/projects/foo-wt-bar` | `file:///data/projects/foo` |
| `git clone --reference /data/projects/foo /data/projects/foo-wt-bar` | The remote URL is the original (good), but `--reference` creates an alternate object dependency (caveat) |
| `git worktree add /data/projects/foo-wt-bar feature-x` | No new remote created — the worktree shares `.git` with the main repo, so `origin` is whatever the main repo's `origin` is |
| Manual `git remote set-url origin file:///path/to/sibling` | `file:///path/to/sibling` |
| Backup-clone-then-rename `git clone --bare upstream backup; rename remotes` | varies |

The first and fourth patterns produce confused topology. They show up in:
- Multi-author workflows where one user's machine has both their canonical fork and a separate clone for benchmarking
- Test setups where a worktree was created via clone-from-local instead of `git worktree add`
- Backup/mirror setups where someone hand-aliased remotes

A user who runs `git push` from such a worktree pushes to the local sibling, not the canonical upstream. The skill, if it doesn't notice, prints the wrong push instruction in Phase 11.

---

## 2. Detection at Phase 1

Phase 1 runs `git remote -v` for every worktree, classifies each remote, and records to `<workspace>/remote_topology.md`.

### 2.1 The classifier

```bash
# In scripts/discover-project.sh, called per worktree:
classify_remote() {
    local url="$1"
    case "$url" in
        http://*|https://*)
            echo "http"
            ;;
        ssh://*|*@*:*)
            echo "ssh"
            ;;
        git://*)
            echo "git-protocol"
            ;;
        file://*)
            echo "local-path"
            ;;
        /*)
            echo "local-path"   # unprefixed absolute path is a local path
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

for wt_path in $(git -C "$PROJECT" worktree list --porcelain | awk '/^worktree / {print $2}'); do
    git -C "$wt_path" remote -v | while read -r name url _direction; do
        type=$(classify_remote "$url")
        echo -e "$wt_path\t$name\t$url\t$type" >> "$WS/remote_topology.tsv"
    done
done
```

### 2.2 The remote_topology.md report

```markdown
# Remote Topology — Per-Worktree Remote Classification

Generated: 2026-05-07T13:48:21Z

## Per-Worktree Remotes

| Worktree | Remote name | URL | Type | Notes |
|---|---|---|---|---|
| /data/projects/foo (main) | origin | https://github.com/owner/foo.git | http | canonical upstream |
| /data/projects/foo (main) | upstream | https://github.com/upstream-owner/foo.git | http | fork upstream |
| /data/projects/foo-wt-bench | origin | file:///data/projects/foo | **local-path** | **FOOTGUN: origin points at sibling worktree** |
| /data/projects/foo-wt-bench | github | https://github.com/owner/foo.git | http | the real upstream |

## Footgun Summary

The following worktrees have `origin` pointing at a local path:

| Worktree | origin URL | Recommended action |
|---|---|---|
| /data/projects/foo-wt-bench | file:///data/projects/foo | Rename `origin` to `local-fork` and use `github` as the canonical remote for push/fetch |

Phase 11 push instructions for this worktree will use `github`, not `origin`.
Phase 10 cleanup for this worktree is BLOCKED until the user acknowledges this topology.

## To Acknowledge

Type at Phase 4 (PROTECTION CONFIRMATION):
  yes I understand /data/projects/foo-wt-bench has origin pointing at a local path; use github as the upstream remote
```

> **Why surface but not auto-fix?** Per AGENTS.md "Mandatory explicit plan": the user might have intentional reasons for the local-path remote (e.g., testing a fork-mirror setup, or a deliberate backup arrangement). Renaming `origin` is a `git remote rename` mutation that affects user workflow; only the user can decide whether the topology is intentional or accidental.

---

## 3. Phase 11 push instructions reference the correct remote

The handoff report's "How to push" section consults `remote_topology.tsv` and picks the appropriate upstream remote.

### 3.1 The selection logic

```bash
# In scripts/handoff-report.sh, computing the push command:
pick_upstream_remote() {
    local wt_path="$1"

    # 1. If exactly one remote of type http/ssh/git-protocol exists, use it:
    upstream_count=$(awk -F'\t' -v w="$wt_path" '$1==w && $4 ~ /^(http|ssh|git-protocol)$/' "$WS/remote_topology.tsv" | wc -l)
    if [ "$upstream_count" = "1" ]; then
        awk -F'\t' -v w="$wt_path" '$1==w && $4 ~ /^(http|ssh|git-protocol)$/ {print $2}' "$WS/remote_topology.tsv"
        return
    fi

    # 2. If multiple remote upstreams, prefer one named `github`, `gitlab`, `upstream`:
    for preferred in github gitlab upstream; do
        if awk -F'\t' -v w="$wt_path" -v p="$preferred" '$1==w && $2==p && $4 ~ /^(http|ssh|git-protocol)$/' "$WS/remote_topology.tsv" | grep -q .; then
            echo "$preferred"
            return
        fi
    done

    # 3. If origin is upstream-shaped, use it:
    if awk -F'\t' -v w="$wt_path" '$1==w && $2=="origin" && $4 ~ /^(http|ssh|git-protocol)$/' "$WS/remote_topology.tsv" | grep -q .; then
        echo "origin"
        return
    fi

    # 4. Otherwise, halt and ask the user:
    echo "AMBIGUOUS"
}
```

### 3.2 The handoff-report rendering

For the cass-mined frankensqlite example:

```markdown
## How to Push

Your rationalization branch is ready: `branch-rationalization-2026-05-07`.

NOTE: This worktree's `origin` remote points at a local path. The recommended remote
for pushing to the canonical upstream is `github`:

  cd /data/projects/foo-wt-bench
  git push github branch-rationalization-2026-05-07

After pushing, you can open a PR via:
  gh pr create --base main --head branch-rationalization-2026-05-07 --title "..." --body "..."

If you want to push to BOTH the local sibling AND the canonical upstream:
  git push origin branch-rationalization-2026-05-07         # local sibling (origin)
  git push github branch-rationalization-2026-05-07         # canonical upstream

(Skip the first if you don't want the local-sibling copy updated.)
```

---

## 4. Refusal mode — Phase 10 cleanup blocked on confused topology

If any worktree in the run has `origin` pointing at a local path, Phase 10 cleanup of that worktree is **blocked** until the user acknowledges. The acknowledgment is recorded in `cleanup_authorization.txt`.

### 4.1 The check

```bash
# In scripts/drop-retire-confirmed.sh, before each worktree removal:
wt_path="$1"
if awk -F'\t' -v w="$wt_path" '$1==w && $2=="origin" && $4=="local-path"' "$WS/remote_topology.tsv" | grep -q .; then
    if ! grep -q "yes I understand $wt_path has origin pointing at a local path" "$WS/cleanup_authorization.txt"; then
        echo "REFUSED: worktree $wt_path has confused remote topology; see remote_topology.md"
        exit 1
    fi
fi
```

### 4.2 Why refuse?

Three reasons:

1. **The bundle's recovery story depends on the right remote.** If `origin` points at a local sibling, recovery recipes that say "fetch the backup ref from origin" go to the wrong place. The user might not notice until they try to recover.
2. **`git push` from the worktree, after Phase 10 removes the sibling, fails silently or pushes to a now-broken file:// URL.** Phase 11's push instructions need to be accurate; if the topology is confused, the instructions may mislead.
3. **The user might not know the topology exists.** A clean `git push` succeeded yesterday because `origin` (the local sibling) accepted the push; the user thinks they're up-to-date with canonical, but the canonical never saw it.

The refusal forces the user to **read the topology** before continuing. Per [AGENTS.md "Note for Codex/GPT-5.5"](../../../../AGENTS.md): "you NEVER, under ANY CIRCUMSTANCE, stash, revert, overwrite, or otherwise disturb in ANY way the work of other agents." A local-path `origin` may BE another agent's working tree — disrupting it would violate this rule.

---

## 5. Edge cases

### 5.1 The `--reference` clone

`git clone --reference /path/to/upstream <real-url>` creates a clone that uses the upstream as an alternate object source. The `origin` URL is the real upstream (good), but the `.git/objects/info/alternates` file points at the local path. If the local path goes away, the clone's objects are still intact (already fetched), but new fetches may fail.

The skill detects this:

```bash
[ -f "$wt_path/.git/objects/info/alternates" ] && \
    echo "$wt_path uses --reference clone; alternates pointing at: $(cat "$wt_path/.git/objects/info/alternates")" \
    >> "$WS/remote_topology_alternates.txt"
```

The skill doesn't refuse on this (the alternate is informational); it just records the dependency in the handoff.

### 5.2 The `git worktree add` case

A worktree created via `git worktree add /path/to/wt <branch>` shares its `.git` with the main repo. Its `git remote -v` shows the **main repo's** remotes — which is correct. No footgun here.

The skill's classifier reports the worktree's remote as the main repo's `origin`, which is fine. The "footgun" only applies when someone manually overrode the remote URL.

### 5.3 Multiple local-path remotes

A worktree may have BOTH `origin` (local) AND `local-fork` (local, different path) AND `github` (real upstream). The classifier handles this — every remote gets its own row in `remote_topology.tsv`. The picker in `pick_upstream_remote()` prefers the http/ssh/git remote, regardless of name.

### 5.4 No remotes at all

Some worktrees (e.g., `/tmp` checkouts, scratch worktrees) have no remotes:

```
| /data/projects/foo-scratch | (no remotes) |
```

The skill records this. Phase 11 push instructions for such a worktree have a fallback:

```markdown
## How to Push (worktree /data/projects/foo-scratch)

This worktree has no remote configured. To push the rationalization branch, first add a remote:
  git remote add github https://github.com/owner/foo.git
  git push github branch-rationalization-2026-05-07

Or, if this worktree was meant to be local-only, the rationalization branch can be cherry-picked
to another worktree that has the canonical remote configured:
  cd /data/projects/foo
  git fetch /data/projects/foo-scratch branch-rationalization-2026-05-07:branch-rationalization-2026-05-07
  git push origin branch-rationalization-2026-05-07
```

### 5.5 Submodule remotes

Submodules have their own `.gitmodules` URLs and per-checkout `.git/modules/<name>/config` URLs. The skill **doesn't** classify submodule remotes (they're out of scope per Axiom 15: remote cleanup is out of scope). It records them informationally:

```bash
[ -f "$wt_path/.gitmodules" ] && cp "$wt_path/.gitmodules" "$WS/submodules/$sanitized.gitmodules"
```

---

## 6. The Phase 4 acknowledgment phrase

If any worktree has confused remote topology, the Phase 4 user gate adds an extra line:

```markdown
## Phase 4 — Protection Confirmation

[normal protection list]

## Remote Topology Acknowledgment Required

The following worktrees have confused remote topology:

  /data/projects/foo-wt-bench  origin = file:///data/projects/foo (local-path)

To proceed past Phase 4, type the following acknowledgment phrase verbatim:

  yes I understand /data/projects/foo-wt-bench has origin pointing at a local path; use github as the upstream remote

Or if the topology is intentional and you want to proceed without the skill modifying push
instructions, type:

  yes I understand /data/projects/foo-wt-bench has origin as a local path and that is intentional

Either acknowledgment unblocks Phase 10 cleanup for this worktree.
```

The user-typed phrase is recorded in `cleanup_authorization.txt` per AGENTS.md "Document the confirmation."

---

## 7. The bundle's README cross-references the topology

The bundle's `README.md` (Phase 3 output) references `remote_topology.md`:

```markdown
# Recovery Bundle — branch+worktree rationalization on foo

[bundle layout, recovery recipes, etc.]

## Remote Topology Note

This run was performed against worktrees with the following remote topology:

  /data/projects/foo            origin = https://github.com/owner/foo.git (canonical upstream)
  /data/projects/foo-wt-bench   origin = file:///data/projects/foo (local sibling — FOOTGUN ACKNOWLEDGED)
                                github = https://github.com/owner/foo.git (canonical upstream)

When recovering, fetch from `github`, not from `origin`, for /data/projects/foo-wt-bench.

See <workspace>/remote_topology.md for the full topology and the user's acknowledgment.
```

This way, anyone consuming the bundle later (during a recovery 6 months from now) sees the topology context immediately.

---

## 8. Worked example — frankensqlite

The cass-mined session: `frankensqlite` had `origin` set to a local sibling and `github` as the real upstream.

### 8.1 Detection (Phase 1 output)

```markdown
## Per-Worktree Remotes

| Worktree | Remote name | URL | Type |
|---|---|---|---|
| /data/projects/frankensqlite (main) | origin | file:///data/projects/frankensqlite-wt-bench | **local-path** |
| /data/projects/frankensqlite (main) | github | https://github.com/owner/frankensqlite.git | http |

## Footgun Summary

| Worktree | origin URL | Recommended action |
|---|---|---|
| /data/projects/frankensqlite | file:///data/projects/frankensqlite-wt-bench | Use `github` as the upstream remote for push/fetch |
```

### 8.2 Phase 4 acknowledgment

The user types:

```
yes I understand /data/projects/frankensqlite has origin pointing at a local path; use github as the upstream remote
```

### 8.3 Phase 11 handoff

```markdown
## How to Push

Your rationalization branch is ready: `branch-rationalization-2026-05-07`.

NOTE: This repo's `origin` is a local-path remote (file:///data/projects/frankensqlite-wt-bench).
The canonical upstream is `github`:

  cd /data/projects/frankensqlite
  git push github branch-rationalization-2026-05-07

After pushing:
  gh pr create --base main --head branch-rationalization-2026-05-07
```

The user pushes to `github` — the canonical upstream — instead of accidentally pushing to the local sibling.

---

## 9. Cross-links

- [PHASES.md § Phase 1 PROJECT RECONNAISSANCE](PHASES.md) — where remote-topology detection runs
- [PHASES.md § Phase 4 PROTECTION CONFIRMATION](PHASES.md) — where the user acknowledges confused topology
- [PHASES.md § Phase 10 DESTRUCTIVE CLEANUP](PHASES.md) — where the refusal gate blocks
- [PHASES.md § Phase 11 HANDOFF](PHASES.md) — where push instructions consult the topology
- [FAILURE-MODES.md](FAILURE-MODES.md) — add this as a new failure mode entry: "F-NEW. `origin` points at a local sibling worktree"
- [ADVANCED-RECOVERY.md](ADVANCED-RECOVERY.md) — recovery recipes that fetch from the bundle must reference the right remote
- [BUNDLE-FORMAT-SPEC.md](BUNDLE-FORMAT-SPEC.md) — bundle README cross-references topology
- [DRY-RUN-MODE.md § 3.6 Remote topology callouts](DRY-RUN-MODE.md) — dry-run surfaces this BEFORE the run
- [CI-WORKFLOW-AWARENESS.md](CI-WORKFLOW-AWARENESS.md) — sibling discovery: branch references in CI YAML
- [INTEGRATION.md](INTEGRATION.md) — `gh` integration; the skill detects branch protection rules per remote
- [AGENTS.md "Mandatory explicit plan"](../../../../AGENTS.md) — verbatim acknowledgment required
- [AGENTS.md "Note for Codex/GPT-5.5"](../../../../AGENTS.md) — never disturb other agents' working trees (a local-path origin may be a sibling agent's tree)
- [AGENTS.md "Irreversible Git Actions"](../../../../AGENTS.md) — Axiom 15 (remote cleanup out of scope)
