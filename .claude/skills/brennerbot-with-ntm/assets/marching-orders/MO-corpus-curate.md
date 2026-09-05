# MO-corpus-curate.md — Phase 1 Corpus Ingestion + Pinning

**Phase:** 1
**Operators activated:** ⌂ Materialize (corpus must be queryable), ⊞ Scale-Check (volume sanity)
**Parameters:** `<CORPUS_INPUT_PATH>` (path to raw input — directory of files OR a code repo), `<CORPUS_TYPE>` (papers | transcripts | code | mixed), `<WORKSPACE_PATH>`

---

You are the corpus-curator subagent. Your job: ingest source material into `corpus/ingested/` with content-hash pinning and `§`-anchor scheme.

NEVER modify source content. Curation is index + copy + pin, not redaction.

---

**Step 1 — Validate inputs.**

```bash
test -d "<CORPUS_INPUT_PATH>" || { echo "input not a directory"; exit 1; }
echo "Corpus type: <CORPUS_TYPE>"
```

If input is a code repo (`<CORPUS_TYPE>=code`), verify `git rev-parse HEAD` works in it.

**Step 2 — Catalog the input.**

Per `subagents/corpus-curator.md` Step 1.

**Step 3 — Assign source IDs and copy.**

For each file/repo, assign `S-NNN`. Copy files into `<WORKSPACE_PATH>/corpus/ingested/<source-id>/`. For PDFs, also extract text. For code repos, pin via `git rev-parse HEAD` rather than copying every file.

**Step 4 — Compute content hashes.**

```bash
sha256sum <WORKSPACE_PATH>/corpus/ingested/<source-id>/main.* > <WORKSPACE_PATH>/corpus/ingested/<source-id>/.hash
```

**Step 5 — Assign anchor schemes per source.**

Per `subagents/corpus-curator.md` Step 4. Annotate sources with `<!-- §N -->` comments at logical breakpoints.

**Step 6 — Build corpus_index.md.**

Per `subagents/corpus-curator.md` Step 5. Required columns: Source ID, Title, Authors, Date, Path, Hash, Anchor scheme, Notes.

**Step 7 — Initialize search_log.md.**

Empty table, ready for Phase 4 investigators to append search-event rows.

**Step 8 — Output summary + scope check.**

```
corpus-curator output:
  Sources ingested: <count>
  Anchor scheme distribution: <breakdown>
  Total content-hashed bytes: <bytes>
  Corpus size category: <small <50KB | medium <5MB | large <500MB | huge ≥500MB>

  Drift detection at Phase 7 audit will compare current hashes to pinned values in corpus_index.md.

  Operator: review corpus_index.md before Phase 1 framing exits. If any source is missing or wrong, fix now.
```

---

**Anti-patterns:**

- ✗ Edit source files for "clarity." Source is read-only.
- ✗ Skip content-hashing. Phase 7 audit can't detect drift.
- ✗ Copy git repos file-by-file instead of pinning via SHA. Wasteful.
- ✗ Skip anchor scheme. Investigators can't cite specific locations.
- ✗ Bundle multiple files into one source ID. Loses provenance.

**Ship-or-Surface SLA:** within 30–60 min depending on corpus size. If the corpus is huge (≥500MB), surface to operator before continuing — may need a sub-selection pass.
