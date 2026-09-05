# Bundle Format Spec

The recovery bundle is a self-contained directory that captures every junk candidate's content + provenance + reference graph + the `.gitignore` snapshot. Tooling that consumes the bundle (e.g., backup audits, restore scripts) should follow this spec.

---

## Directory layout

```
<bundle-root>/                              # default: <project-root>/.repo_janitor_workspace/recovery-bundle-<YYYY-MM-DD>/
├── README.md                               # human-readable recovery recipes + footgun warnings
├── index.tsv                               # one row per candidate; THE source of truth
├── meta/
│   ├── 000.txt                             # path, blob SHA, last commit, author, date for candidate id=0
│   ├── 001.txt
│   └── ...
├── working-tree-copies/                    # byte-identical mirror of every candidate
│   └── <path/at/HEAD/relative/to/repo-root>
├── stashed-untracked/                      # NOT used in this skill (reserved for parity with stash-janitor)
├── gitignore-before.txt                    # full .gitignore content at start of run
├── gitignore-proposed.diff                 # diff of proposed additions (unified diff format)
├── reference-graph.json                    # every candidate's inbound references
└── verification.log                        # SHA-256 verification results from Phase 3
```

**Why the bundle lives inside `.repo_janitor_workspace/`:** The audit artifacts must stay contained within the project being analyzed. Keep `.repo_janitor_workspace/` in `.git/info/exclude` so the bundle does not pollute normal `git status`; do not put the bundle in a sibling directory.

---

## `index.tsv` schema

Tab-separated, one row per candidate. Header row is required.

| Column | Type | Description |
|--------|------|-------------|
| `id` | int | Zero-padded 3-digit, matches inventory ordering |
| `blob_sha` | string | Git blob SHA of the file at the path-at-HEAD |
| `path_at_HEAD` | string | Relative-to-repo-root POSIX path |
| `size_bytes` | int | File size at snapshot time |
| `mtime_iso` | string | ISO-8601 mtime |
| `smell_tags` | string | Comma-separated FILE-SMELLS.md tag list |
| `first_committed_in` | string | Git SHA of the commit that introduced this path |
| `has_lfs_pointer` | bool | `true` if the bundle's working-tree-copy is the LFS-smudged blob (not the pointer) |
| `content_hash_sha256` | string | SHA-256 of the bundle's working-tree-copy (for byte-equality verification) |
| `verdict` | string | One of: delete-and-gitignore, delete-no-gitignore, gitignore-only, move, keep-in-place, protected, surface-to-user (filled in at Phase 5) |
| `proposed_dest` | string | Destination path (filled in at Phase 5 for `move` rows) |
| `proposed_gitignore_pattern` | string | Glob to add (filled in at Phase 5 for `*-and-gitignore` rows) |

Example row:
```
000	abc123def456...	storage.sqlite3	12288	2026-04-22T14:32:11Z	sqlite-db,binary,root-only	def987...	false	c0ffee...	delete-and-gitignore	(none)	/storage*.sqlite3*
```

---

## `meta/<id>.txt` schema

One file per candidate. Lines are key-value pairs (`key=value`), one per line:

```
id=000
path=storage.sqlite3
blob_sha=abc123def456...
size_bytes=12288
mtime_iso=2026-04-22T14:32:11Z
smell_tags=sqlite-db,binary,root-only

first_commit=def987...
first_commit_message=feat: add dev sqlite for integration tests
first_commit_author=alice@example.com
first_commit_date=2026-03-01T10:00:00Z

last_commit=def987...
last_commit_message=feat: add dev sqlite for integration tests
last_commit_author=alice@example.com
last_commit_date=2026-03-01T10:00:00Z

verdict=delete-and-gitignore
verdict_confidence=0.97
verdict_evidence=smell=sqlite-db;refs=0;dev-runtime DB
proposed_gitignore_pattern=/storage*.sqlite3*
```

---

## `reference-graph.json` schema

```json
{
  "schema_version": "1.0",
  "snapshot_taken_at": "2026-04-27T15:00:00Z",
  "candidates": {
    "000": {
      "path": "storage.sqlite3",
      "inbound_refs": []
    },
    "017": {
      "path": "COMPREHENSIVE_PLAN_FOR_X.md",
      "inbound_refs": [
        {
          "ref_path": "crates/X-harness/src/bin/spec_audit.rs",
          "line": 19,
          "ref_form": "workspace_root.join(\"COMPREHENSIVE_PLAN_FOR_X.md\")",
          "rewrite_eligibility": "auto",
          "rewrite_old_string": "workspace_root.join(\"COMPREHENSIVE_PLAN_FOR_X.md\")",
          "rewrite_new_string": "workspace_root.join(\"docs/planning/COMPREHENSIVE_PLAN_FOR_X.md\")"
        },
        {
          "ref_path": "tests/rfc2119_audit.rs",
          "line": 13,
          "ref_form": "const SPEC_REL_PATH: &str = \"COMPREHENSIVE_PLAN_FOR_X.md\";",
          "rewrite_eligibility": "auto",
          "rewrite_old_string": "const SPEC_REL_PATH: &str = \"COMPREHENSIVE_PLAN_FOR_X.md\";",
          "rewrite_new_string": "const SPEC_REL_PATH: &str = \"docs/planning/COMPREHENSIVE_PLAN_FOR_X.md\";"
        }
      ]
    }
  }
}
```

`rewrite_eligibility` enum:
- `auto` — lexical match; safe to rewrite via Edit tool with the documented old/new strings.
- `surface-only` — reference is via alias/re-export/runtime-string-construction; cannot safely auto-rewrite.
- `comment-only` — reference is in a comment/doc-string only; rewrite is best-effort but not load-bearing.

---

## `gitignore-before.txt` and `gitignore-proposed.diff`

`gitignore-before.txt` is a verbatim copy of the repo's `.gitignore` at run start. `gitignore-proposed.diff` is a unified-diff format showing additions:

```diff
--- a/.gitignore
+++ b/.gitignore
@@ -42,6 +42,12 @@ target_*/
 *.profraw
 *.profdata
 lcov.info
+
+# Per-bead progress reports — use docs/progress/ instead
+/progress.md
+/progress_bd-*.md
+/bd-*.md
```

After Phase 8 commits, the actual `.gitignore` will match the result of applying the proposed diff (modulo any user overrides from Phase 5).

---

## `verification.log` (Phase 3)

Plain text, one verification per line:

```
2026-04-27T15:00:00Z OK    storage.sqlite3 (live=c0ffee... bundle=c0ffee...)
2026-04-27T15:00:01Z OK    progress_bd-abc.md (live=deadbeef... bundle=deadbeef...)
2026-04-27T15:00:02Z OK    COMPREHENSIVE_PLAN_FOR_X.md (live=cafef00d... bundle=cafef00d...)
...
```

Any `MISMATCH` line halts the run. Format:

```
2026-04-27T15:00:03Z MISMATCH  <path> (live=<sha> bundle=<sha>)
```

---

## `README.md` template (auto-generated)

```markdown
# Repo Cleanup Recovery Bundle

**Project:** /data/projects/<repo>
**Created:** 2026-04-27T15:00:00Z
**Run mode:** Standard
**Source skill:** git-repo-janitor

This directory contains byte-identical copies of every file the cleanup
run touched, along with provenance metadata and reference-graph snapshot.

## Layout

- `index.tsv` — one row per candidate; the source of truth.
- `meta/<id>.txt` — provenance per candidate.
- `working-tree-copies/<path>` — byte-identical copy of each candidate.
- `gitignore-before.txt` — full .gitignore at run start.
- `gitignore-proposed.diff` — unified-diff of additions.
- `reference-graph.json` — inbound references per candidate.
- `verification.log` — Phase 3 byte-equality results.

## Recovery recipes

### Restore one file
```bash
cp working-tree-copies/<path> <repo-root>/<path>
git -C <repo-root> add <path>
git -C <repo-root> commit -m "restore: <path>"
```

### Restore from git's backup ref
```bash
cd <repo-root>
git checkout refs/repo-janitor-backup/<DATE>-pre-cleanup -- <path>
```

### Audit the bundle
```bash
# Verify every working-tree-copy still matches its recorded hash
while IFS=$'\t' read -r id sha path size mtime smell first_sha lfs hash _; do
  [[ "$id" == "id" ]] && continue
  current=$(sha256sum "working-tree-copies/$path" | awk '{print $1}')
  [[ "$current" == "$hash" ]] || echo "DRIFT: $path"
done < index.tsv
```

## Footgun warnings

1. **Do NOT use `git format-patch` to recover content.** Use `git checkout
   refs/repo-janitor-backup/...` or copy from `working-tree-copies/`.

2. **Do NOT delete this bundle until you're sure nothing was lost.**
   Recommend keeping for at least one release cycle.

3. **The bundle is read-only by convention.** Tooling that audits the
   bundle should never modify these files. If you find drift, the bundle
   is no longer trustworthy — start a fresh cleanup run.

4. **For LFS-tracked files**: the working-tree-copy is the smudged blob,
   not the LFS pointer. To restore, copy and `git add` — git will
   re-pointerize correctly.
```

---

## Tooling contract

Any external tool that consumes the bundle MUST:

1. Treat `index.tsv` as authoritative for paths and hashes.
2. Verify `working-tree-copies/<path>` SHA-256 matches `index.tsv` `content_hash_sha256` before trusting the content.
3. Treat `meta/<id>.txt` as the per-candidate provenance source (not git log, which may have been rewritten if filter-repo ran).
4. Treat `reference-graph.json` as the snapshot of inbound references at Phase 2 time; it may be stale by the time of recovery and should be re-grep'd if precision matters.
5. Never modify any file in the bundle. Bundles are read-only artifacts.

---

## Versioning

The bundle's `index.tsv` header includes a schema version comment on its first line:

```tsv
# repo-janitor bundle index.tsv schema v1.0
id	blob_sha	path_at_HEAD	size_bytes	mtime_iso	smell_tags	first_committed_in	has_lfs_pointer	content_hash_sha256	verdict	proposed_dest	proposed_gitignore_pattern
000	abc123...	storage.sqlite3	12288	2026-04-22T14:32:11Z	sqlite-db,binary	def987...	false	c0ffee...	delete-and-gitignore	(none)	/storage*.sqlite3*
```

Schema-aware tooling should refuse to operate on bundles whose schema version is newer than they support.
