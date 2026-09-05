# Evidence Citation Style Guide

Every triage row's `evidence` column should be a compact string the user can scan. This document codifies the format.

---

## Format

```
<key1>=<val1>;<key2>=<val2>;...
```

Semicolon-separated, key=value pairs. Keys are lowercase with hyphens. Values are filename:line refs, smell tags, or short descriptors.

---

## Standard keys

| Key | Meaning | Example |
|-----|---------|---------|
| `smell` | Smell-tag list | `smell=plan-doc,multi-llm-cluster` |
| `refs` | Inbound reference count + first 2-3 paths | `refs=2:README.md,scripts/build.sh` |
| `dup-of` | When the candidate is a duplicate of another | `dup-of=illustration.webp` |
| `archetype-protected` | When archetype rules force `keep-in-place` | `archetype-protected=Cargo.toml` |
| `file` | When a `file <path>` magic-bytes match is dispositive | `file=ELF; magic=0x7fELF` |
| `size` | When file size is part of the evidence (typically 0-byte stubs or huge planning docs) | `size=0` or `size=846KB` |
| `intro` | First-commit SHA + short message | `intro=abc1234 "feat: add scratch helper"` |
| `last` | Last-touched-by + how recently | `last=alice@example.com,30d-ago` |
| `gitignored-already` | When `.gitignore` has a matching rule | `gitignored-already=signing-*.key (force-added)` |
| `same-content-as` | When two paths have identical bytes | `same-content-as=docs/HISTORY.md` |
| `dest` | Proposed destination for `move` verdicts | `dest=docs/planning/` |

---

## Examples

### Clean delete (high confidence)

```
smell=skill-output;refs=0;file=text/markdown
```

### Move with reference rewrites

```
smell=plan-doc;refs=4:src/X.rs:19,src/Y.rs:436,tests/Z.rs:13,e2e/A.sh:10;dest=docs/planning/
```

### Surface to user (low confidence)

```
smell=scratch-script;refs=1:tests/conftest.py:5;possible-test-helper
```

### Protected (archetype rule)

```
archetype-protected=Cargo.toml;refs=many
```

### Secret-suspect (Phase 2.5 filename hit, no content match)

```
smell=secret-suspect;file=signing-X.pub;size=44;content=base64-44-bytes (likely Ed25519 public — safe)
```

### Real secret-leak

```
smell=secret-leak;file=signing-77c6e768.key;size=32;content=binary;intro=6de5816 "feat: ...";pushed=yes;exposure=30d
```

### Gitignore-only

```
smell=sqlite-wal-shm;sibling=storage.sqlite3;already-removed-from-disk
```

---

## What NOT to put in evidence

- Full file contents (too long; not useful for scanning)
- The verdict itself (separate column)
- The confidence score (separate column)
- Long natural-language explanations (use the `forensic-report-template.md` for those)

---

## When evidence runs long

If the natural evidence list exceeds ~120 chars, abbreviate:

- `refs=4:README.md,src/X.rs,...` (truncate after 2-3 with `...`)
- Use a sidecar file `<workspace>/forensics/<id>_evidence.md` for the full reasoning

---

## For the user-facing decision table (Phase 5)

When `triage_decision.md` displays evidence to the user, the merger may pretty-print it:

```
| id | path | evidence | refs |
|----|------|----------|------|
| 17 | COMPREHENSIVE_PLAN.md | smell=plan-doc;refs=4 | crates/X/src/main.rs:19, tests/Y.rs:13, ... (2 more) |
```

The raw `evidence` column from `triage.tsv` is the canonical form; pretty-printing is for human consumption only.
