# MO-evidence-intake-pdf.md — Ingest a PDF as Evidence

**Phase:** any (typically Phase 4)
**Operators activated:** ⌂ Materialize, ⊞ Scale-Check (page count sanity)
**Parameters:** `<PDF_INPUT>` (local path or URL), `<RELEVANCE>`, `<H_ID>`, `<SESSION_ID>`, `<PANE_N>`

---

PDFs are usually frozen sources (papers, archived reports, books). Ingestion discipline differs from URL-class:

- Page anchoring (per-page §-anchor) is more useful than per-paragraph
- Often large (10-300 pages) — must be reduced to relevant excerpts
- DOI / archive snapshot URL is the canonical source

---

**Step 1 — Acquire the PDF.**

```bash
mkdir -p corpus/ingested/<S-NNN-NEW>

PDF_INPUT="<PDF_INPUT>"
case "$PDF_INPUT" in
  http://*|https://*)
    curl -sL -o corpus/ingested/<S-NNN-NEW>/main.pdf "$PDF_INPUT"
    ;;
  *)
    cp "$PDF_INPUT" corpus/ingested/<S-NNN-NEW>/main.pdf
    ;;
esac

# Compute hash (PDFs are stable so hash is highly reliable):
sha256sum corpus/ingested/<S-NNN-NEW>/main.pdf | awk '{print $1}' > corpus/ingested/<S-NNN-NEW>/.hash
```

**Step 2 — Page count sanity.**

```bash
# Use pdfinfo or qpdf:
PAGES=$(pdfinfo corpus/ingested/<S-NNN-NEW>/main.pdf 2>/dev/null | grep Pages | awk '{print $2}')
echo "PDF has $PAGES pages"
```

If pages > 100 and the EV concerns a specific section, extract only the relevant pages:

```bash
# Extract pages 12-18:
qpdf --pages corpus/ingested/<S-NNN-NEW>/main.pdf 12-18 -- \
  corpus/ingested/<S-NNN-NEW>/excerpt.pdf
```

For Read tool compatibility, the PDF can be read directly with the `pages:` parameter. Don't try to read 100+ pages at once.

**Step 3 — Determine source class.**

PDFs are typically:

- **Frozen** (DOI-published paper, archived report) — most common
- **Versioned** (preprint v1, v2, ...) — requires version annotation in corpus_index
- **Living document** (rarely, e.g., a regularly-updated standard) — class:live

**Step 4 — Update corpus_index.md.**

```markdown
| <S-NNN-NEW> | <title> | <author/source> | <date> | corpus/ingested/<S-NNN-NEW>/main.pdf | <hash> | §-per-page | class:frozen; pages:N; ingested-by:<PANE_N>; rationale:<RELEVANCE>; doi:<DOI?> |
```

**Step 5 — Append to `analyses/official-source-log.md` (source-level verification log).**

Ensure `analyses/` exists first if this workspace predates the current bootstrap layout.

```markdown
| <TIMESTAMP_UTC> | <S-NNN-NEW> | frozen | initial-pin | <PANE_N> | n/a | first ingest from PDF (pages: N) |
```

**Step 6 — Read relevant pages.**

Use the Read tool with `pages` parameter:

```python
# Read pages 12-18 (max 20 per request):
Read(file_path="corpus/ingested/<S-NNN-NEW>/main.pdf", pages="12-18")
```

For papers: read abstract first, then methods, then results, then discussion. Take notes. Identify the load-bearing claim that justifies the EV.

**Step 7 — File the EV bead.**

```bash
ev_ref="EV-NNN"  # public ref; replace NNN before running
ev_id="$(br create "$ev_ref: <one-line claim from PDF>" \
  --type=task --labels=evidence --priority=2 \
  --slug="$ev_ref" --external-ref="$ev_ref" --silent \
  --description="$(cat <<'EOF'
type: paper
source: <PDF_INPUT>
source_id: <S-NNN-NEW>
source_freshness: frozen
relevance: <RELEVANCE>
imported_at: <TIMESTAMP_UTC>
imported_by: <PANE_N>
verified: false  # Will be verified independently per MO-evidence-verify.md
supports: [<H_ID>]
session: <SESSION_ID>

## Excerpts
- E1 (verbatim from page <N>): "<exact quote>"
- E2 (verbatim from page <M>): "<exact quote>"

## Why this matters for <H_ID>
<one-paragraph explaining mechanism>
EOF
)")"
printf 'Created %s as br id %s\n' "$ev_ref" "$ev_id"
```

**Step 8 — DOI / canonical URL annotation.**

If PDF has a DOI, document it:

```markdown
# In analyses/external-references.md:
- <S-NNN-NEW>: DOI <doi> | archive: <archive.org snapshot url>
```

Future verifiers can re-fetch from canonical URL if local PDF goes missing.

---

**Anti-patterns:**

- ✗ Read the entire PDF when only a section matters (wasteful)
- ✗ Quote without page anchor (un-verifiable)
- ✗ Treat scanned/OCR'd PDFs as authoritative quotes (OCR errors are common; verify against original if possible)
- ✗ Skip DOI annotation (loses canonical source pointer)
- ✗ Trust PDF metadata blindly (sometimes published-date is wrong; cite actual content)

**Ship-or-Surface SLA:** within 20 min, EV bead filed + corpus_index.md updated.

---

## Special: paywalled papers

If PDF is paywalled and you only have abstract access:

- Class is `paywalled`; mark in corpus_index.md
- EV's confidence is `low` (limited access)
- Phase 4 may need to seek open-access alternative source

If user has institutional access, use it via WebFetch with auth headers (separate setup).
