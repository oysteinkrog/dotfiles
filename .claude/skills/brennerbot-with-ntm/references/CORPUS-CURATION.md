# CORPUS-CURATION.md — Authoring and Maintaining a Research Corpus

<!-- TOC: When this matters | Source intake | Anchor schemes | Content-hash discipline | Mid-session updates | Drift detection | Cross-corpus reuse -->

Goes deeper than `MO-corpus-curate.md` (the dispatch template) and `subagents/corpus-curator.md` (the agent role). This file is the *methodology* of corpus authorship — when to do it, how to do it well, what to watch for.

---

## When corpus curation matters

Different modes / archetypes have different corpus-discipline needs:

| Mode | Corpus discipline |
|------|-------------------|
| `fresh-question` | Optional; corpus may be empty if questions are first-principles |
| `code-investigation` | Mandatory: pin codebase via `git rev-parse HEAD` |
| `corpus-distillation` | Critical: full content-hash + anchor-scheme discipline |
| `methodology-drift-check` | Read-only over prior session's frozen corpus |
| `incident-investigation` | Compressed: pin logs/dashboards/metrics at investigation start |
| `living-review` | Periodic re-curation as sources update |

For T4+ sessions in any mode, corpus discipline is mandatory regardless of mode.

---

## Source intake — the discipline

When ingesting a new source, the curator (per `subagents/corpus-curator.md`) MUST do:

### 1. Verify the source is what it claims to be

- For papers: confirm DOI / arXiv ID resolves
- For repos: clone fresh, don't use a stale local copy
- For URLs: fetch fresh; record `etag` / `last-modified`
- For PDFs: verify the PDF actually contains the claimed text (OCR may have issues)

### 2. Determine the source class (per VERIFICATION-FIRST.md)

- Frozen text → content-hash sufficient
- Versioned source → git SHA pin
- Live URL → etag/last-modified + scheduled re-fetch
- Live benchmark → snapshot + access timestamp
- In-flight discussion → permalink + comment ID
- Regulatory → version date

### 3. Compute and pin a content hash

```bash
sha256sum corpus/ingested/<source-id>/main.* > corpus/ingested/<source-id>/.hash
```

The hash IS the source's identity. Future drift checks compare hashes; mismatch = drift.

### 4. Assign an anchor scheme

Per EXTENDED-PROJECT-TYPES.md domain table. Common choices:

- **§-per-section** — each top-level heading is an anchor (default for papers, structured docs)
- **§-per-paragraph** — for transcripts, dialog, prose without clear sections
- **§-per-claim** — for highly-claimed argumentation
- **§-per-line-range** — for code (e.g., `S-007:lines-100-150`)
- **§-per-test-case** — for benchmark suites
- **§-per-row** — for tabular data

Annotate the source with `<!-- §N -->` markers at logical breakpoints. Investigators cite via `§N` in evidence packs.

### 5. Update corpus_index.md

Required columns: Source ID, Title, Authors, Date, Path, Hash, Anchor scheme, Class (per VERIFICATION-FIRST.md), Notes.

### 6. Initialize verification log entry

For volatile-class sources, append to `analyses/official-source-log.md`:

```markdown
| <ISO> | <S-NNN> | <class> | initial-pin | corpus-curator | n/a | first ingest |
```

---

## Anchor scheme depth

A common mistake: anchor scheme too coarse (one anchor per source) OR too fine (one anchor per sentence).

### Heuristic: aim for 5-30 anchors per source

- Below 5: too coarse, can't cite specific points
- Above 30: too fine, citation overhead exceeds value

For a typical 10-page paper: ~10-15 anchors (per section + per major claim)
For a 100-page book: ~40-80 anchors (per chapter + per sub-section)
For source code: ~one anchor per major function or test

### Heuristic: anchor at semantic boundaries

Don't anchor every paragraph mechanically. Anchor where:
- A new claim is introduced
- A key piece of evidence is cited
- A method step is described
- A counter-argument is presented

---

## Content-hash discipline

The hash is the *contract*. Phase 7 audit verifies hashes; mismatch is a finding.

### When to refresh the hash

- Never silently. The point is detection, not auto-fix.
- Operator decides explicitly: "this source has updated; we should pin to new version."
- The original hash + new hash both recorded in corpus_index.md provenance log.

### Hash mismatch protocol

When `audit-bead-invariants.sh § layout_invariants` detects hash mismatch:

1. Note in `analyses/official-source-log.md`: `hash_mismatch_at: <ISO>`
2. Diff the source: what changed?
3. If changes don't affect cited evidence → update hash + note in provenance ("source revised; cited content unchanged")
4. If changes DO affect cited evidence → re-verify each affected `EV-*`; potentially flip H state
5. File audit-finding for each affected H

Don't skip step 3+4. Hash mismatch without follow-up is silent corruption.

---

## Mid-session corpus updates

When Phase 4 surfaces a need for additional sources, run `MO-corpus-update.md`. The discipline:

### Decision rule for adding a source

The new source must satisfy ≥1 of:
- A current `H-*.expected_evidence` would be answerable from this source
- A current `H-*.falsifier` would be probeable from this source
- A `C-*` (critique) needs evidence-to-confirm from this source
- An anomaly (`AN-*`) might be explained by this source

Skip:
- "We should be more comprehensive" (anti-Brenner; corpus serves question, not exhaustiveness)
- "I want to read this paper anyway" (separate from session)

### Decision rule for triggering Phase 4 reopen

After adding a source:
- Source is *primary evidence* for a current `H-*`? → file `EV-*` immediately AND consider Phase 4 reopen
- Source is *background/context*? → file as `EV-*` with `informs:` link; no reopen
- Source contradicts a `state: confirmed` H claim? → Phase 4 reopen MANDATORY
- Source contradicts a `state: refuted` H claim? → file flagging; revisit at Phase 7

---

## Drift detection

`scripts/audit-bead-invariants.sh` checks layout invariants including hash matching. For volatile-class sources, also need periodic re-fetch (per VERIFICATION-FIRST.md Recipe V3).

### Continuous drift monitoring (T4+ sessions)

For long-running sessions where sources may drift mid-session:

```bash
# Run hourly (via /loop if available, or cron)
for SRC in corpus/ingested/*/.hash; do
  EXPECTED=$(cat "$SRC")
  CURRENT=$(sha256sum "$(dirname "$SRC")/main."* | awk '{print $1}')
  if [ "$EXPECTED" != "$CURRENT" ]; then
    echo "DRIFT: $(dirname "$SRC")"
  fi
done
```

### Drift notification

When drift detected mid-session, dispatch operator alert + file an `audit-finding`:

```bash
af_ref="AF-NNN"  # public ref; replace NNN before running
af_id="$(br create "$af_ref: Corpus drift detected on $SOURCE" \
  --type=task --labels=audit-finding --priority=1 \
  --slug="$af_ref" --external-ref="$af_ref" --silent \
  --description="severity: high
target_artifact: corpus/ingested/$SOURCE/
recommendation: Investigate change; re-verify cited EVs
by_pane: drift-monitor
session: $SESSION_ID")"
printf 'Created %s as br id %s\n' "$af_ref" "$af_id"
```

---

## Cross-corpus reuse

A corpus that's been carefully curated for one session can be reused (with attribution) in subsequent sessions on related questions.

### Pattern: shared corpus across multiple sessions

For a research domain with stable core sources, maintain a *meta-corpus* outside any single workspace:

```
~/research/meta-corpora/<domain>/
├── corpus_index.md
├── ingested/
│   ├── S-001/
│   ├── S-002/
│   └── ...
```

Sessions then symlink (or copy) selected sources from the meta-corpus into their workspace's `corpus/ingested/`. Provenance log notes the meta-corpus as origin.

### Hash discipline preserved

When importing from meta-corpus, the hash MUST match. If meta-corpus has updated since last session, the new session decides: import current OR pin to historical version.

---

## Corpus quality metrics

For T3+ sessions, periodically check:

- **Coverage:** are the sources sufficient for the question? (Phase 4 surfaces gaps)
- **Independence:** are sources independent (different authors, different methods)?
- **Verification rate:** what % of cited EVs are `verified:true`?
- **Volatile-source rate:** what % are class:live or class:in-flight?
- **Anchor density:** average anchors per source

Healthy ranges depend on session type, but extreme values warrant investigation:
- Verification rate <50% at Phase 7 → audit must catch
- Volatile-source rate >50% → mandatory verification-first protocol
- Anchor density <3 per source → likely under-curated

---

## Corpus anti-patterns

| ✗ | Why |
|---|-----|
| Skip content-hash; "we'll trust the URL" | Drift undetected; recommendations age silently |
| Anchor only at top of source | Investigators can't cite specific points; evidence-pack quality drops |
| Edit source content for clarity | Source is read-only; edits are research fraud-adjacent |
| Bundle multiple files into one source ID | Loses per-file provenance |
| Mid-session corpus addition without decision rule | Scope creep; questions drift |
| Corpus that exceeds the question's scope | Investigators chase tangents |
| Never re-verify volatile sources | Phase 9 recommendations rest on stale data |
| Skip the .hash file | Layout invariants can't verify |

---

## Operator's corpus checklist

At Phase 1 exit:

- [ ] All sources in corpus_index.md have content hashes
- [ ] Anchor schemes assigned per source
- [ ] Volatile sources flagged with verification class
- [ ] Provenance log started
- [ ] No source > 50% reliance on (avoid single-source dependence)

At Phase 7 audit:

- [ ] All cited EVs trace to a corpus source
- [ ] Volatile sources re-verified within session
- [ ] No silent corpus drift (hashes match)
- [ ] Anchor density adequate (≥3 per source citing the source)

At Phase 8 freeze:

- [ ] corpus_index.md and all .hash files committed
- [ ] `analyses/official-source-log.md` committed for volatile-class sources
- [ ] No uncommitted changes in corpus/

These checks are the difference between a research session and an opinion piece.
