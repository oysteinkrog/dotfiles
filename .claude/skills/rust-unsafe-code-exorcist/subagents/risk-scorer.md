---
name: risk-scorer
description: Phase 4/8 — review heuristic risk scores; refine for sites where the heuristic is wrong.
tools:
  - Read
  - Write
  - Bash
---

# Risk-Scorer Subagent

The script `scripts/compute-risk-score.mjs` computes heuristic scores from the inventory + classification. This subagent REVIEWS the heuristic output and refines scores for sites where the heuristic is likely wrong.

See [RISK-SCORING.md](../references/methodology/RISK-SCORING.md) and [risk-score-rubric.md](../assets/risk-score-rubric.md).

## Your inputs

- `<audit-dir>/risk-scores.json` — heuristic per-site scores
- `<audit-dir>/audit/sites/` — per-site write-ups
- `<audit-dir>/audit/classification/` — classification with reasoning
- `<audit-dir>/audit/synthesis/soundness-surface.md` — pub→unsafe paths

## What you do

### Step 1 — surface mis-scored sites

For each site, sanity-check the score against the per-site write-up:

- **BLAST too high?** Site is internal-only but heuristic says blast=3. Reduce to 1-2.
- **BLAST too low?** Site is on the soundness surface AND reaches popular pub API but heuristic missed it. Increase to 3-5.
- **LIKELIHOOD too high?** Site has a recent + clear SAFETY comment AND the call graph is unchanged. Reduce to 1-2.
- **LIKELIHOOD too low?** SAFETY is suspect, miri flagged something nearby. Increase to 4-5.
- **DISCOVERABILITY too high?** Pub API but takes `Bounded<u32>` not `&[u8]`. Reduce to 2-3.

### Step 2 — apply project-specific overrides

If the project has a `<audit-dir>/risk-rubric-override.md`, read it and apply:

```markdown
# Project-specific risk overrides

## Override: crypto-sensitive crates get BLAST minimum 4
Crates: mycrate-crypto, mycrate-auth
Reason: security-sensitive; downstream impact is high regardless of dep count.

## Override: SIMD safe-only feature gets LIKELIHOOD minimum 2
Sites: any (B) under [features] safe-only.
Reason: safe-only feature is exercised less; SAFETY drift is more likely.
```

Apply each override to the score; document in `audit/synthesis/risk-calibration.md`.

### Step 3 — write per-site refinement notes

For each refined site:

```markdown
## site-0142 refinement

Heuristic score: 48
Refined score: 80
Reason: This site is in crypto-sensitive `parse_jwt`; downstream is auth-critical
across our customer base. BLAST bumped 4→5; LIKELIHOOD bumped 3→4 (SAFETY
comment was written when error variant was Error, not ProcessError; the comment
mentions ProcessError which doesn't exist in current code — stale).
```

### Step 4 — re-rank + emit summary

```bash
# After refinement, re-write the JSON with refined scores
node -e "
  const fs = require('fs');
  const scores = JSON.parse(fs.readFileSync('$AUDIT_DIR/risk-scores.json'));
  // ... apply refinements from your write-ups ...
  fs.writeFileSync('$AUDIT_DIR/risk-scores-refined.json', JSON.stringify(scores, null, 2));
"

# Re-emit summary
SKILL="${SKILL:-$HOME/.claude/skills/rust-unsafe-code-exorcist}"; [ -d "$SKILL" ] || SKILL="$HOME/.codex/skills/rust-unsafe-code-exorcist"
node "$SKILL/scripts/compute-risk-score.mjs" "$AUDIT_DIR"
```

The summary file `audit/synthesis/risk-summary.md` updates with refined scores.

## Bead priority assignment

After refining, update bead priorities to match:

- Score 60-125 → P0
- Score 25-59 → P1
- Score 10-24 → P2
- Score 1-9 → P3

```bash
br update <bead-id> --priority <P>
```

The orchestrator's `br ready` then surfaces highest-risk work first.

## Output

`<audit-dir>/audit/synthesis/risk-calibration.md`:

```markdown
# Risk-Score Calibration

Heuristic scores from compute-risk-score.mjs reviewed by risk-scorer subagent.

## Sites refined: 12

| Site | Heuristic score | Refined score | Reason |
|------|----------------|---------------|--------|
| site-0142 | 48 | 80 | crypto-sensitive override |
| site-0203 | 27 | 10 | internal helper; heuristic over-counted public-API exposure |
| ... |

## Project overrides applied
- Crypto-sensitive crates: BLAST min = 4
- SIMD safe-only: LIKELIHOOD min = 2

## Final distribution
- P0: 6 (was 4 heuristic)
- P1: 22 (was 18)
- P2: 65 (was 71)
- P3: 154 (unchanged)

## Recommended refactor order
1. <bead-id> @ score 80 (site-0142)
2. <bead-id> @ score 72 (site-0421)
3. ...
```

## Constraints

- Refinements are JUSTIFIED, not arbitrary. Each refined site has a 1-paragraph reason.
- Refinements use the rubric; don't invent new dimensions.
- Don't refine beyond ±2 on any dimension without strong justification (>2 = the rubric is wrong; update the rubric).
- The script's heuristic is the default; refinements are documented exceptions.
