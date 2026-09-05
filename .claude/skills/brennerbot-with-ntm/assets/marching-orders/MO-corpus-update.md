# MO-corpus-update.md — Mid-Session Corpus Addition

**Phase:** any (typically mid-Phase-4 or pre-Phase-6)
**Operators activated:** ⌂ Materialize, ⊞ Scale-Check (volume sanity)
**Parameters:** `<NEW_SOURCE_PATH>`, `<RATIONALE>` (one-sentence why this source is being added), `<SESSION_ID>`

---

You are corpus-curator subagent extending an existing session's corpus. Per CORPUS-CURATION.md, mid-session corpus additions are allowed but require explicit decision-rule discipline.

---

**Step 1 — Verify rationale.**

Read `<RATIONALE>`. Valid reasons:

- A new source was published / discovered after Phase 1 corpus assembly
- Phase 4 investigation surfaced a gap that requires a specific additional source
- Devil's-advocate identified a known counter-evidence source that wasn't in Phase 1 corpus
- A `cass`-mined prior session pointer to a source not yet ingested

Invalid reasons:

- "I want to add this paper" (without specific gap)
- "We should be more comprehensive" (anti-Brenner; the corpus serves the question, not exhaustiveness)
- "The user mentioned this in passing" (verify the user actually wants it added)

If invalid, decline and recommend the operator confirm with user.

**Step 2 — Ingest the new source.**

Per the same procedure as `MO-corpus-curate.md`:

```bash
# Assign next source ID
S_LAST=$(grep -oE '^S-[0-9]+' corpus/corpus_index.md | sort -t- -k2 -n | tail -1)
S_NEW=$(printf "S-%03d" $(( ${S_LAST#S-} + 1 )))

mkdir -p corpus/ingested/$S_NEW
cp "$NEW_SOURCE_PATH" corpus/ingested/$S_NEW/main.md  # or main.pdf etc
sha256sum corpus/ingested/$S_NEW/main.* > corpus/ingested/$S_NEW/.hash
```

**Step 3 — Assign anchor scheme.**

Read the new source. Determine the anchor scheme. Annotate with `<!-- §N -->` markers as in MO-corpus-curate.md.

**Step 4 — Append to corpus_index.md.**

```markdown
| S-NNN | <title> | <authors> | <date> | corpus/ingested/S-NNN/main.md | <hash> | <anchor scheme> | Added mid-session: <RATIONALE> |
```

Add to provenance log.

**Step 5 — Decide: does this trigger Phase 4 reopen?**

Apply this decision rule:

- New source is *primary evidence* for a current `H-*`? → file `EV-*` immediately AND consider Phase 4 reopen on that H
- New source is *background/context*? → file as `EV-*` with `informs:` link; no Phase 4 reopen needed
- New source contradicts a `state: confirmed` H claim? → Phase 4 reopen MANDATORY for that H
- New source contradicts a `state: refuted` H claim? → file as `EV-*` flagging the contradiction; revisit at Phase 7 audit

**Step 6 — Coordinate with active panes.**

Post to `RS-...-INVEST-coord` thread:

```
Subject: [<SESSION_ID>] Corpus update: <S-NNN> added

New source: <title> at <S-NNN>
Rationale: <RATIONALE>
Decision rule fired: <one of the four above>

Action items:
- <Investigator pane>: re-read <H-NNN> evidence pack with this new source
- <Devil's-Advocate pane>: probe for falsifier-firing in new source
- (or "no action needed; informs:-only addition")
```

**Step 7 — Update phase0_scope_decision.md.**

```bash
cat >> .brenner_workspace/phase0_scope_decision.md <<EOF

## Corpus update — $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Added: <S-NNN> (<title>)
- Rationale: <RATIONALE>
- Phase 4 reopen triggered: <yes | no — reason>
EOF
```

**Step 8 — Output summary.**

```
corpus-update output:
  Source ingested: <S-NNN>
  Path: corpus/ingested/<S-NNN>/main.md
  Hash: <sha>
  Anchor scheme: <scheme>
  Phase 4 reopen: <yes | no>
  Coord notification: posted to RS-...-INVEST-coord

Operator: review and confirm Phase 4 reopen decision before continuing.
```

---

**Anti-patterns:**

- ✗ Add source without rationale tied to a current methodology need
- ✗ Skip the anchor scheme assignment ("we'll add it later")
- ✗ Update existing source content (corpus is read-only; updates require new S-ID)
- ✗ Add source without notifying active panes
- ✗ Trigger Phase 4 reopen without recording in phase0_scope_decision.md

**Ship-or-Surface SLA:** within 30 min, source ingested + decision rule applied + coord posted.
