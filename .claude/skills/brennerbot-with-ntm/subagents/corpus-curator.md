# corpus-curator Subagent

**Role:** Phase 1 — ingest source material into `corpus/ingested/` with content-hash pinning and `§`-anchor scheme.

**Reads:** raw input corpus path (markdown / PDF / txt directory, OR a code repo).

**Writes:**

- `corpus/ingested/<source-id>/...` — pinned source content
- `corpus/corpus_index.md` — index with `id, title, authors, date, path, hash, anchor scheme`
- `corpus/search_log.md` — initial search log

**Operators favored:** ⌂ Materialize (corpus must be queryable; raw paths aren't enough).

**Hard constraints:**

1. EVERY source pinned with content-hash (SHA-256). Drift detection at Phase 7 audit.
2. Anchor scheme assigned per source — typically `§-per-section` (heading-keyed) or `§-per-paragraph`.
3. NO modification of source content. Curation is copying + indexing, not editing.
4. For code repos: pin via `git rev-parse HEAD` + dirty status, NOT content-hash of every file.

---

## Procedure

**Step 1 — Catalog the input.**

```bash
# For markdown / PDF / txt corpus:
find <CORPUS_PATH> -type f \( -name '*.md' -o -name '*.pdf' -o -name '*.txt' \) | head -50

# For code repo:
( cd <CORPUS_PATH> && git rev-parse HEAD && git status --short )
```

**Step 2 — Assign source IDs.**

Format: `S-NNN` (zero-padded). One ID per file (for paper/text corpus) or one ID per repo (for code corpus).

**Step 3 — Copy to corpus/ingested/.**

```bash
mkdir -p <WORKSPACE>/corpus/ingested/<source-id>/
cp <source-file> <WORKSPACE>/corpus/ingested/<source-id>/main.md   # or main.pdf, etc.
sha256sum <WORKSPACE>/corpus/ingested/<source-id>/main.md > <WORKSPACE>/corpus/ingested/<source-id>/.hash
```

For PDFs, also extract text:

```bash
pdftotext <pdf-source> <WORKSPACE>/corpus/ingested/<source-id>/main.txt
```

**Step 4 — Assign anchor scheme.**

Read each source. Determine:

- `§-per-section` — for sources with clear section headings (most academic papers, most documentation)
- `§-per-paragraph` — for transcripts, interviews, dialog with no section structure
- `§-per-claim` — for highly-claimed argumentation; one anchor per major claim
- `§-per-line-range` — for code (e.g., `§S-005:lines-100-150`)

Annotate the source file with anchors:

```markdown
# Source S-001 (anchor scheme: §-per-section)
<!-- §1 -->
## Introduction
...

<!-- §2 -->
## Methodology
...
```

The `<!-- §N -->` comments are invisible in rendered markdown but searchable for evidence-pack citation.

**Step 5 — Build corpus_index.md.**

```markdown
# Corpus Index — RS-<YYYYMMDD>-<slug>

| Source ID | Title | Authors | Date | Path | Hash (sha256) | Anchor scheme | Notes |
|-----------|-------|---------|------|------|---------------|---------------|-------|
| S-001 | "On-Disk Format X" | Smith et al. | 2024-03 | corpus/ingested/S-001/main.md | <hash> | §-per-section | Primary source for H-001 |
| S-002 | "Event Sourcing in Y" | Jones | 2023-09 | corpus/ingested/S-002/main.txt | <hash> | §-per-paragraph | PDF extracted |
| S-003 (repo) | "<repo>" | — | <git-sha> | <repo-path> | n/a (git) | §-per-line-range | dirty: <true|false> |

## Provenance log

- <ISO-8601>: ingested S-001 from <original_url>
- <ISO-8601>: ingested S-002 from <original_url>
- <ISO-8601>: pinned repo S-003 at <sha>
```

**Step 6 — Initialize search_log.md.**

```markdown
# Corpus Search Log

| Timestamp | Searcher (pane) | Query | Source IDs scanned | Hits | Note |
|-----------|-----------------|-------|---------------------|------|------|
```

(Empty initially; investigators append rows as they search.)

**Step 7 — Output summary.**

```
corpus-curator subagent summary:

Sources ingested: <count>
  - <count> markdown/text
  - <count> PDFs (extracted)
  - <count> repos (git-pinned)

Anchor scheme distribution:
  - §-per-section: <count>
  - §-per-paragraph: <count>
  - §-per-claim: <count>
  - §-per-line-range: <count>

Total content-hashed bytes: <bytes>

corpus_index.md: written with <count> rows
search_log.md: initialized

Drift detection: at Phase 7 audit, any change to corpus/ingested/* will be detected via hash mismatch.

Next: Phase 1 framing (operator runs MO-01-frame-question.md against the curated corpus).
```

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip content-hashing | Phase 7 audit can't detect drift; F-102 (corpus drift) at high risk |
| Edit source files for "clarity" | Source corpus is read-only; curation is index, not redaction |
| Skip anchor scheme assignment | Investigators can't cite specific locations; evidence-pack quality drops |
| Bundle multiple files into one source ID | Loses per-file provenance |
| For code repos: copy files into corpus/ingested/ | Wasteful; pin via git instead |

---

## When the corpus is empty (fresh-question mode)

If the user has no prior corpus, the curator skips and writes an empty corpus_index.md + a note in `phase0_scope_decision.md`:

```
corpus_status: empty (fresh-question mode)
corpus_will_grow: per Phase 4 investigation findings; investigators may file corpus-update requests in INVEST-coord thread
```

Phase 4 investigators can request corpus additions via `INVEST-coord` thread. Operator approves and re-runs corpus-curator on the new source.
