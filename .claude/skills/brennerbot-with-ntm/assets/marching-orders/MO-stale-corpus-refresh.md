# MO-stale-corpus-refresh.md — Refresh Corpus When Drift Detected

**Phase:** any (typically triggered by `check-volatile-source-staleness.sh`)
**Operators activated:** ⌂ Materialize (re-pin), ✂ Exclusion-Test (verify drift impact)
**Parameters:** `<DRIFTED_SOURCES>` (list of source IDs from staleness scan), `<SESSION_ID>`, `<PANE_N>`

---

Per VERIFICATION-FIRST.md and `check-volatile-source-staleness.sh`. When stale sources are detected, this MO formalizes the refresh procedure to prevent silent F-102 corpus drift.

---

**Step 1 — Confirm staleness.**

```bash
./scripts/check-volatile-source-staleness.sh
```

For each STALE entry, identify:
- Source ID
- Class (live / regulatory / in-flight / etc.)
- Age vs cadence threshold
- Last-verified ISO

**Step 2 — Per-source refresh.**

For each STALE source, follow class-specific recipe:

### Class: live (default for URLs)

```bash
SOURCE_URL="<source URL from corpus_index.md for <S-NNN>>"

# Re-fetch:
curl -sL -D corpus/ingested/<S-NNN>/.headers.new \
  -o corpus/ingested/<S-NNN>/main.html.new \
  "$SOURCE_URL"

# Compute new hash:
NEW_HASH=$(sha256sum corpus/ingested/<S-NNN>/main.html.new | awk '{print $1}')
OLD_HASH=$(cat corpus/ingested/<S-NNN>/.hash)

if [ "$NEW_HASH" != "$OLD_HASH" ]; then
    # Drift detected
    diff corpus/ingested/<S-NNN>/main.html corpus/ingested/<S-NNN>/main.html.new \
        > corpus/ingested/<S-NNN>/.drift-diff
    # Decide: how significant is the drift?
fi
```

### Class: in-flight (issue tracker comments, etc.)

Re-fetch every 30 min during active session. Same drift detection.

### Class: regulatory

Re-check at session end. Drift here may invalidate compliance claims.

### Class: versioned (specific commit / tagged release)

Should never drift. If drift detected, the source pin was wrong. Investigate.

### Class: paywalled

Re-fetch may require auth. Note in scope_decision.

**Step 3 — Assess drift impact.**

For each drifted source:

```bash
# Find EVs that cite this source:
br list --label=evidence --json 2>/dev/null \
  | jq -r --arg sid "<S-NNN>" '.issues[]? | select((.description // "") | contains($sid)) | .id'
```

For each cited EV, check whether the cited content changed:

```bash
# Extract verbatim quotes from each affected EV bead:
affected_ev_id="<affected EV id>"
br show "$affected_ev_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' | grep -E '^- E[0-9]+\s*\(verbatim'

# Verify each quote still appears in updated source:
for quote in "$VERBATIM_QUOTES"; do
    grep -F "$quote" corpus/ingested/<S-NNN>/main.html.new >/dev/null \
        && echo "  $quote: STILL PRESENT" \
        || echo "  $quote: DRIFTED"
done
```

**Step 4 — Categorize drift impact.**

For each EV, the drift is one of:

- **No-impact**: cited content unchanged; just metadata (date stamps, etc.)
- **Cosmetic**: nearby content changed but cited content unchanged
- **Substantive**: cited content drifted; the EV's verbatim quote is no longer accurate
- **Invalidating**: source has been retracted / corrected and the cited content is no longer authoritative

**Step 5 — Per-impact response.**

### No-impact

Update `analyses/official-source-log.md` with new last_verified_at. No bead changes.

### Cosmetic

Update `analyses/official-source-log.md`. Note in EV bead that source was re-verified at this point.

### Substantive

This is F-102. Per FAILURE-TABLE.md:
- Mark `EV-*.verified=false` with reason
- File audit-finding severity:high
- Re-investigate the H depending on this EV
- May trigger Phase 4 reopen for the affected H

### Invalidating

Same as substantive PLUS:
- Mark EV as superseded
- Investigation must find an alternative source for the claim
- HANDBACK must explicitly note the source-invalidation event

**Step 6 — Update corpus_index.md.**

```bash
# Update the row for the drifted source:
| <S-NNN> | <title> | ... | <new_hash> | ... | class:<class>; last_refreshed:<TIMESTAMP_UTC>; drift_diff:<.drift-diff path>; impact:<no/cos/sub/inv> |
```

**Step 7 — Append to `analyses/official-source-log.md` (source-level verification log).**

Ensure `analyses/` exists first if this workspace predates the current bootstrap layout.

```markdown
| <TIMESTAMP_UTC> | <S-NNN> | <class> | refresh-detected-drift | <PANE_N> | <new_hash> | impact:<level>; affected_evs:<list> |
```

**Step 8 — If substantive/invalidating, propagate.**

For affected H:
- Re-evaluate state
- File `audit-finding` per Phase 7 protocol
- May require operator decision: continue with caveat OR reopen Phase 4

For affected H downstream:
- If H was load-bearing for HANDBACK verdict: flag in HANDBACK as needing re-evaluation
- If session is mid-Phase: pause and decide

**Step 9 — Document in scope_decision.**

```yaml
# In .brenner_workspace/phase0_scope_decision.md
corpus_drift_events:
  - timestamp: <TIMESTAMP_UTC>
    source: <S-NNN>
    class: <class>
    impact: <level>
    affected_evs: [<EV-NNN>, ...]
    response: <continued / paused / phase-4-reopened>
```

---

**Anti-patterns:**

- ✗ Skip drift detection because "the source is stable" — verify, don't assume
- ✗ Update last_verified_at without actually re-fetching
- ✗ Treat all drift as substantive — most is cosmetic; categorize properly
- ✗ Continue session despite invalidating drift — must address before Phase 8
- ✗ Drift detected but no audit-finding filed — Phase 7 won't catch it later

**Ship-or-Surface SLA:** within 15 min per source, refresh + impact assessment + decision.

---

## When drift is too frequent

If drift is detected on >25% of sources per cadence:
- Cadence is too lax for the corpus volatility
- Reduce cadence (e.g., live sources from 4h → 1h)
- OR: corpus selection is poor (too many volatile sources)
- Pin frozen / archived versions of volatile sources where possible

Document in `references/CORPUS-CURATION.md` lessons.

---

## Composition with other patterns

- Per VERIFICATION-FIRST.md (the per-class cadence)
- Per scripts/check-volatile-source-staleness.sh (detection)
- Per F-102 (recovery code in FAILURE-TABLE.md)
- Per LIVING-DOCUMENTATION-PATTERNS.md (per-tick refresh in living-review mode)

---

## Cross-references

- VERIFICATION-FIRST.md (per-class re-verification cadence)
- CORPUS-CURATION.md (corpus authoring discipline)
- check-volatile-source-staleness.sh (the validator)
- FAILURE-TABLE.md (F-102)
- POST-MORTEM-FORMALIZATION-PLAYBOOK.md (cross-incident pattern detection)
