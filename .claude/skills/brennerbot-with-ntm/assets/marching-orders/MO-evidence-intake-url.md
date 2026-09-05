# MO-evidence-intake-url.md — Ingest a URL as Evidence with Verification Discipline

**Phase:** any (typically Phase 4)
**Operators activated:** ⌂ Materialize (URL becomes specific source), ⊞ Scale-Check (size sanity)
**Parameters:** `<URL>`, `<RELEVANCE>` (one-sentence why this URL matters), `<H_ID>` (which H this evidence supports/refutes/informs), `<SESSION_ID>`, `<PANE_N>`

---

A URL is volatile by default (per VERIFICATION-FIRST.md Recipe V3). This MO ingests a URL with the verification discipline that prevents F-102 corpus drift.

---

**Step 1 — Fetch the URL.**

```bash
mkdir -p corpus/ingested/<S-NNN-NEW>
# Use WebFetch tool if available, OR curl with cache headers:
curl -sL -D corpus/ingested/<S-NNN-NEW>/.headers \
  -o corpus/ingested/<S-NNN-NEW>/main.html \
  "<URL>"

# Extract last-modified / etag for drift detection:
ETAG=$(grep -i 'etag' corpus/ingested/<S-NNN-NEW>/.headers | awk -F': ' '{print $2}' | tr -d '\r"')
LAST_MOD=$(grep -i 'last-modified' corpus/ingested/<S-NNN-NEW>/.headers | awk -F': ' '{print $2}' | tr -d '\r')

# Convert HTML to text for searchability (if not already text):
# Could use html2text, pandoc, or python BeautifulSoup
python3 -c "
from bs4 import BeautifulSoup
import sys
soup = BeautifulSoup(open('corpus/ingested/<S-NNN-NEW>/main.html').read(), 'html.parser')
print(soup.get_text())
" > corpus/ingested/<S-NNN-NEW>/main.txt 2>/dev/null

# Compute content hash:
sha256sum corpus/ingested/<S-NNN-NEW>/main.html | awk '{print $1}' > corpus/ingested/<S-NNN-NEW>/.hash
```

**Step 2 — Sanity-check the content.**

Reject and abort if:
- File size <100 bytes (likely error page)
- File contains common error markers ("404", "Forbidden", "Cloudflare challenge")
- HTTP status was non-200 (check headers)

Don't ingest as evidence if the source isn't actually accessible.

**Step 3 — Determine source class.**

Per VERIFICATION-FIRST.md:

- **Frozen/archived URL** (e.g., archive.org snapshot, DOI-resolved paper) → class: frozen
- **Versioned source** (specific commit, tagged release URL) → class: versioned
- **Live page** (default for most URLs) → class: live (volatile)
- **In-flight discussion** (issue tracker comment) → class: in-flight (very volatile)
- **Regulatory** (statute URL, official .gov page) → class: regulatory (with version date)

**Step 4 — Update corpus_index.md.**

```markdown
| <S-NNN-NEW> | <title> | <author/source> | <date> | corpus/ingested/<S-NNN-NEW>/main.html | <hash> | §-per-section | class:<class>; etag:<etag value>; last-modified:<last-modified value>; ingested-by:<PANE_N>; rationale:<RELEVANCE> |
```

**Step 5 — Append to `analyses/official-source-log.md` (source-level verification log).**

Ensure `analyses/` exists first if this workspace predates the current bootstrap layout.

```markdown
| <TIMESTAMP_UTC> | <S-NNN-NEW> | <class> | initial-pin | <PANE_N> | n/a | first ingest from URL <URL> |
```

**Step 6 — Assign §-anchor scheme.**

For HTML/markdown content with structure: §-per-section.
For prose: §-per-paragraph.
For tables/lists: §-per-row.

Annotate the source file with `<!-- §N -->` markers as in MO-corpus-curate.md.

**Step 7 — File the EV bead.**

```bash
ev_ref="EV-NNN"  # public ref; replace NNN before running
ev_id="$(br create "$ev_ref: <one-line claim from URL>" \
  --type=task --labels=evidence --priority=2 \
  --slug="$ev_ref" --external-ref="$ev_ref" --silent \
  --description="$(cat <<'EOF'
type: paper | observation | code_artifact | regulatory  # depending on URL content
source: <URL>
source_id: <S-NNN-NEW>
source_freshness: <class> | last_verified_at: <TIMESTAMP_UTC>
relevance: <RELEVANCE>
imported_at: <TIMESTAMP_UTC>
imported_by: <PANE_N>
verified: false  # Will be verified independently per MO-evidence-verify.md
supports: [<H_ID>]   # or refutes / informs
session: <SESSION_ID>

## Excerpts
- E1 (verbatim from §<N>): "<exact quote>"
EOF
)")"
printf 'Created %s as br id %s\n' "$ev_ref" "$ev_id"
```

**Step 8 — Schedule re-verification.**

Per VERIFICATION-FIRST.md class-specific recipes:

- frozen: no re-verification needed
- versioned: one-time check (won't change)
- live: re-verify every 1-4h during session
- in-flight: re-verify every 30 min
- regulatory: re-verify at end of session

Add to `analyses/verification-schedule.md`:

```markdown
- <S-NNN-NEW>: re-verify every <interval> until <session end>
```

**Step 9 — Independent verification.**

Per MO-evidence-verify.md, a *different* pane should re-verify the EV before it counts toward `verified:true`. Schedule.

---

**Anti-patterns:**

- ✗ Skip content-hash (no drift detection later)
- ✗ Use `verified:true` for the URL on initial ingest (verification requires independent re-check)
- ✗ Ingest error pages as evidence (404 isn't evidence; reject)
- ✗ Skip source class assessment (volatile URLs need different handling)
- ✗ Ingest URLs without rationale (anti-corpus-bloat per CORPUS-CURATION.md)
- ✗ Use a single live URL as primary evidence for `confidence:high` H (need ≥2 independent sources per F-405)

**Ship-or-Surface SLA:** within 15 min, EV bead filed + corpus_index.md updated + re-verification scheduled.
