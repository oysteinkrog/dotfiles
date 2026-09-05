# Subagent: risk-scorer

**Phase:** 4.5 (between Phase 4 triage and Phase 5 plan composition)
**Spawn:** Once per run.

## Role

Score every triage verdict by exploitability × blast-radius × reversibility. Helps Phase 5 prioritize the user's review attention to the highest-risk rows first.

Per CONFIDENCE-SCORING.md, but expanded with risk dimensions (not just confidence).

## Prompt

You are scoring the risk of each triage verdict.

Read `<workspace>/triage.tsv`. For each row:

### Risk dimensions (1-5 each, higher = more risk)

1. **Action irreversibility (R)**: how hard is it to undo?
   - 1: keep-in-place / move (fully reversible via git revert)
   - 2: gitignore-only (revert via .gitignore edit)
   - 3: delete-and-gitignore (revert via git revert OR bundle copy)
   - 4: delete-no-gitignore (revert via bundle only; future recurrence not blocked)
   - 5: history rewrite via git filter-repo (irreversible without mirror; affects every clone)

2. **Blast radius (B)**: how widely does the action affect things?
   - 1: single file at root, no inbound refs
   - 2: 2-5 inbound refs in markdown only
   - 3: 5+ inbound refs in source code; rewrites needed
   - 4: 10+ inbound refs spanning multiple file types
   - 5: cross-repo refs (CI/CD configs, deployment scripts)

3. **Surprise factor (S)**: how likely is the verdict wrong?
   - 1: unambiguous (e.g., 0-byte stub)
   - 2: clear smell rule + no inbound refs
   - 3: ambiguous purpose (e.g., scratch.py with one ref)
   - 4: false-positive risk (filename matches but content doesn't)
   - 5: high-stakes (secret-suspect; phantom-deletion candidate)

### Risk score

```
risk_score = R * B * S  (range: 1 to 125)
```

### Risk band

- 1-15: low (auto-confirm in Phase 5)
- 16-50: medium (surface in normal Phase 5 review)
- 51-100: high (surface prominently; user attention recommended)
- 101-125: critical (require explicit verbatim authorization beyond plan-level)

### Output

Add a `risk_score` and `risk_band` column to `triage.tsv`:

```
id  verdict             confidence  evidence  proposed_dest  pattern  EQ  SS  RGC  R  risk_score  risk_band
000 delete-and-gitignore 0.97       smell=skill-output  (none)  .skill-loop-progress.md  5  5  5  4  4   low
017 move                 0.92       smell=plan-doc  docs/planning/  (none)  4  5  3  5  20  medium
099 secret-leak          0.20       smell=ed25519-key  (none)  signing-*.key  5  5  5  1  125  critical
102 surface-to-user      0.40       smell=scratch;refs=1  (none)  (none)  2  4  2  3  72  high
```

### Phase 5 prioritization

The triage-merger uses risk_band to order the categorized plan:

1. CRITICAL: surface first; require verbatim auth before continuing
2. HIGH: surface in expanded form; user reviews each
3. MEDIUM: standard review (table format)
4. LOW: collapsed by default; user expands if interested

This makes Phase 5 efficient: low-band rows pass with bulk confirmation; medium gets normal attention; high/critical get scrutiny.

## Output

`<workspace>/triage.tsv` updated with risk_score and risk_band columns.

## Tools used

Read, Edit.

## Time budget

1-3 min (compute is fast).
