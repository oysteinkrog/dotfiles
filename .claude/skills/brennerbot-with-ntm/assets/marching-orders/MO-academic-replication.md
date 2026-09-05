# MO-academic-replication.md — Replicate Published Results Before Citing

**Phase:** Phase 4 (when EV cites a published claim)
**Operators activated:** 🔧 DIY (run our own version), ✂ Exclusion-Test (does our run match the paper?)
**Parameters:** `<PAPER_ID>`, `<CLAIM>`, `<H_ID>`, `<EV_ID>`, `<SESSION_ID>`

---

For T4-T5 sessions, an EV that cites a published result without independent replication is a weak EV. This MO replicates the result.

Per Brenner §229: "Run a small experiment yourself before believing it."

---

**Step 1 — Identify replicable claim.**

Not every published claim can be replicated within session budget. Triage:

- **Replicable in <2h**: small dataset, public code, simple metric → run it
- **Replicable in <8h with infrastructure**: medium dataset, partial code → consider for T4+ sessions
- **Not realistically replicable**: massive compute, proprietary data, complex setup → cite without replication; mark EV with `replication_attempted: false; reason: out-of-scope`

If the load-bearing claim is in the "not realistically replicable" tier AND the H rests heavily on it, that's a methodology vulnerability — note in HANDBACK.

**Step 2 — Locate code/data.**

```bash
# Try common locations:
# 1. Paper's GitHub (search arxiv abs page)
# 2. Authors' personal sites
# 3. PapersWithCode entry
# 4. Replicability databases (e.g., RaaS)
```

Document discovered repo URL + commit SHA + dataset URL in `analyses/replication-attempts/<PAPER_ID>.md`.

**Step 3 — Reproduce minimally.**

Don't run the full pipeline. Run the specific result that the EV cites.

```bash
mkdir -p analyses/replication-attempts/<PAPER_ID>
cd analyses/replication-attempts/<PAPER_ID>

# Clone code with SHA pin (per VERIFICATION-FIRST.md):
git clone <code_url> code/
git -C code/ checkout <sha>

# Acquire dataset:
# (may require auth, agreement, etc.)

# Run the specific experiment:
# (paper-specific; document)
```

**Step 4 — Compare results.**

Paper claim: "<claim>"
Our replication: "<result>"

Statuses:

- **Match**: results within reasonable error bars → strong support for EV
- **Partial match**: same direction, different magnitude → moderate support; note discrepancy
- **No match**: different direction or magnitude beyond error → file critical audit-finding; the EV is unreliable
- **Inconclusive**: replication itself failed (errors, missing data) → mark EV `replication_attempted: true; outcome: inconclusive; reason: <details>`

**Step 5 — File replication record.**

```markdown
# In analyses/replication-attempts/<PAPER_ID>/REPLICATION-RECORD.md:

# Paper: <full citation>
# DOI: <doi>
# Original code: <url> @ <sha>
# Original dataset: <url>
# Our replication: <TIMESTAMP_UTC> | <runner pane>

## Setup
<config used>

## Results
| Metric | Paper | Our run | Status |
|--------|-------|---------|--------|
| <m1>   | <p1>  | <r1>    | match  |
| ...    | ...   | ...     | ...    |

## Discrepancies (if any)
<list>

## Confidence in EV citing this paper
- Original confidence (paper alone): <low/medium/high>
- After replication: <low/medium/high>

## Caveats
<list>
```

**Step 6 — Update EV bead.**

```bash
ev_ref="<EV_ID>"
ev_id="$(br list --all --json | jq -r --arg ref "$ev_ref" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' | head -1)"
[ -n "$ev_id" ] || { echo "No bead found for public ref: $ev_ref" >&2; exit 1; }
br update "$ev_id" --description="$(br show "$ev_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' | sed 's/replication_attempted: false/replication_attempted: true; replication_outcome: <match|partial|nomatch|inconclusive>; replication_record: analyses\/replication-attempts\/<PAPER_ID>\/REPLICATION-RECORD.md/')"
```

**Step 7 — If discrepancy, escalate.**

If our replication doesn't match the paper:

- File audit-finding severity:critical citing the discrepancy
- The H depending on this EV may need re-evaluation
- Possibly: file a new H "the published result is wrong"
- For T5 sessions: contact paper authors via reasonable channel (this is rare; document the contact attempt)

---

**Anti-patterns:**

- ✗ Replicate every cited paper (excessive; only do for load-bearing claims)
- ✗ Skip replication because "the paper has 1000 citations" (citation count is not validation)
- ✗ Skip docs of replication setup (un-reproducible by future reader)
- ✗ Trust author-provided code without SHA pin (code drift)
- ✗ Replicate only successful runs; hide failures (selection bias)

**Ship-or-Surface SLA:** depends on replication complexity; document time spent.

---

## When NOT to use this MO

- T1-T2 sessions (overhead not worth it)
- Claims that aren't load-bearing for any active H
- Replication impossible (proprietary data, withdrawn code)
- Question is theory, not empirical

For impossible cases, the EV's confidence is bounded by the paper's reputation alone — note explicitly in HANDBACK.

---

## Pattern: replication-driven discovery

Sometimes replication reveals discoveries the paper missed (e.g., the result holds but for a different reason). This is valuable — file as new EV with provenance "discovered during replication of <PAPER_ID>."

Per CASS-MINING-RECIPES.md, this is a high-value-per-hour pattern at T4+.
