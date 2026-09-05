# Commit Message Craft

Cleanup commits should be auditable months later. Each commit's body explains *why* this change is happening, not just *what*.

---

## Convention

```
<type>(<scope>): <one-line summary>

<2-3 sentence problem statement>

<bulleted list of files affected>

<optional reference rewrite list>

<verification line: "Verified: ..." with concrete command outcomes>
```

`<type>` is one of: `chore`, `fix`, `refactor`, `security`. Cleanup commits are usually `chore` (or `security` for the secret-leak playbook).

`<scope>` for cleanup commits is usually one of: `gitignore`, `repo-janitor`, or a specific area like `docs`, `scripts`, `tests`.

---

## Templates per phase

### Phase 6 — Move category

```
chore: move <category-name> into <dest-dir>/ + update load-bearing path references

<N> long-form documents at the workspace root were <category-purpose>
artefacts. They retain lasting value as a record of <reason>, but
their natural home is under <dest-dir>/.

Moved (<N>):
- <file1> (<size>) → <dest-dir>/<file1>
- <file2> → <dest-dir>/<file2>
- ... (or just summary if N is large)

Updated load-bearing path references in <M> files:
- <ref-file1>:<line> (<reason>)
- <ref-file2>:<line> (<reason>)
- ...

Verified: <test-command> passes; no stale path refs found via grep.
```

Real example (frankensqlite Apr-27):

```
chore: move long-form planning and spec docs into docs/planning/ + update load-bearing path references

Sixteen large markdown documents at the repo root are the canonical
design and planning artefacts for FrankenSQLite. They retain lasting
value as a record of how the project was scoped, but their natural
home is under docs/planning/.

Moved (16):
- COMPREHENSIVE_SPEC_FOR_FRANKENSQLITE_V1.md (846 KB)
- COMPREHENSIVE_SPEC_FOR_FRANKENSQLITE_V1_CODEX.md
- COVERAGE.md
- E2E_SCENARIO_MATRIX.md
- E2E_SCENARIO_TRACEABILITY.md
- EXISTING_SQLITE_STRUCTURE.md
- MVCC_SPECIFICATION.md
- PERFORMANCE_OPTIMIZATION_PLAN.md
- PLAN_TO_PORT_SQLITE_TO_RUST.md
- PROPOSED_ARCHITECTURE.md
- STATE_OF_THE_CODEBASE_AND_NEXT_STEPS.md
- TODO.md
- UNIT_INVARIANT_MATRIX.md
- UPGRADE_LOG.md
- BEAD_AUDIT_REPORT.md
- tasks.md

Updated load-bearing path references in 8 files:
- crates/fsqlite-harness/src/bin/spec_to_beads_audit.rs:19 (workspace_root.join)
- crates/fsqlite-harness/tests/rfc2119_hygiene_audit.rs:13 (SPEC_REL_PATH)
- crates/fsqlite-harness/tests/spec_authority_integrity_audit.rs:13,16-21 (SPEC_REL_PATH + LEGACY_DOCS array)
- crates/fsqlite-harness/tests/bd_4eue_reference_index_compliance.rs:55-60 (PROJECT_REFERENCE_DOCS array)
- crates/fsqlite-harness/tests/spec_to_beads_audit.rs:436+471 (test config spec_path)
- crates/fsqlite-harness/tests/workspace_layering.rs:313+348 (workspace_root().join in spec_section_8_3)
- e2e/reference_index_audit.sh:101-108 (project_docs array)
- e2e/bd_sxm2_compliance.sh:10 (SPEC_PATH)

Comment update: crates/fsqlite-btree/src/balance.rs:993 (referenced
STATE_OF_THE_CODEBASE_AND_NEXT_STEPS.md in a doc comment).

Verified: cargo check -p fsqlite-harness passes; comprehensive
re-grep across *.rs *.toml *.sh *.py shows 0 stale path references.
```

### Phase 7 — Delete category

```
chore: remove <category-name> from repo root

<N> files at the workspace root were <category-purpose>:

- <file1>: <description of what it was; why it shouldn't have been
  tracked; how it can be regenerated if needed>
- <file2>: <description>
- ...

Verified: <test-command> passes (or "no test impact, files were not
imported anywhere").
```

Real example (frankensqlite Apr-27):

```
chore: remove stray compiled binaries from repo root

Two compiled ELF executables left over from ad-hoc compile/run cycles
should never have been tracked. Both are reproducible from source via
the workspace's normal cargo build flow:

- rust_out: 4.4 MB stripped-but-unsymbolicated ELF; appears to have
  been the output of a quick `gcc test.c -o rust_out` debugging
  session. No source file remains.
- test_ptr: 5.2 MB ELF; output of a small ptrmap exploration program.
  Source likely lived in test_ptrmap.c (also being removed in a
  separate commit).

Verified: nothing in the workspace imports or references either
binary by name.
```

### Phase 8 — `.gitignore` update

```
chore(gitignore): forbid <category> at repo root

After Phase 7 removed <N> files matching these smells, codify the
prevention:

- <category-1> (<M> patterns): <pattern-list>
   <reason; what the patterns cover>
- <category-2> (<M> patterns): <pattern-list>
   <reason>

Verified via SHADOWING-AUDIT: no currently-tracked files match any
of the new patterns. Verified via `git check-ignore -v <fake-paths>`:
every pattern fires correctly on its target shape.
```

### Secret-leak phases

```
security: prevent private-key commits — broader .gitignore + .githooks/pre-commit + AGENTS.md

A real <secret-type> (<path>) was committed in <introducing-sha>
"<introducing-commit-message>" despite .gitignore already containing
<pre-existing-rule>. The leak was force-added with `git add -f`,
bypassing .gitignore. To prevent recurrence:

- Broaden .gitignore: add <new-patterns>
- Install .githooks/pre-commit that scans staged paths against
  secret-smells (cannot be bypassed by `git add -f`)
- Document the hook in AGENTS.md so contributors know how to install
  it on their clones (`git config core.hooksPath .githooks`)

After this commit:
- New users clone normally
- core.hooksPath needs to be set per-clone:
    git config core.hooksPath .githooks

Cross-reference: incident reported 2026-04-27; key rotated; history
rewritten via filter-repo + force-with-lease push to main and master.
```

---

## What goes in the body

| Section | Required? | Purpose |
|---------|-----------|---------|
| Problem statement | Yes | Why is this change happening? What problem does it solve? |
| Files affected | Yes | An auditable list (or summary count if N is huge) |
| Reference rewrites | Yes for moves; N/A for deletes | Every source-code path constant updated |
| Verification line | Yes | What gates were run? What was the outcome? |
| Cross-references | Optional | Links to incident logs, related commits, AGENTS.md |

---

## What does NOT go in the body

- "Co-Authored-By" lines (per AGENTS.md, the skill never adds these unless the user asks)
- "Generated with Claude Code" footers (the user may add these manually if desired)
- Marketing language ("This commit beautifies the repo")
- Promises of future work ("Will follow up with X")

---

## Tone

Cleanup commits are auditable engineering records, not narrative prose. Match the project's existing commit style — if the repo uses Conventional Commits, do that; if it uses ticket-id prefixes (`BACK-1234:`), use that. The skill's Phase 1 archetype detection includes commit-style sampling so the message-author subagent has the right template.

---

## Why focused commits matter

Three months from now, someone will run `git log --oneline docs/planning/COMPREHENSIVE_SPEC.md` and see:

```
b0de8afe chore: move long-form planning and spec docs into docs/planning/ + update load-bearing path references
```

They click through to the body and see exactly which files moved, why, what references were updated, and that gates passed. They can audit the move in 30 seconds.

The alternative — `chore: cleanup` with no body — costs them an hour of `git diff` archaeology to figure out what actually happened.
