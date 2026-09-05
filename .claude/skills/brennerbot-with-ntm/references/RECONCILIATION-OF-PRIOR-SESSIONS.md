# RECONCILIATION-OF-PRIOR-SESSIONS.md — When Sessions Disagree

<!-- TOC: Why reconcile | Conflict types | The reconciliation procedure | Multi-session triangulation T5 | Catalog of resolved conflicts | Anti-patterns -->

Sometimes multiple brennerbot sessions on the same (or related) question reach different verdicts. This file documents the reconciliation discipline.

Mirrors patterns from wills-and-estate-planning's PRIOR-PLAN-GAP-ANALYSIS.md and saas-billing's MIGRATION-CUTOVER.md.

---

## Why reconcile

Three reasons sessions might disagree:

1. **Corpus drift** — the source material changed between sessions
2. **Question drift** — the framing was subtly different
3. **Genuine under-determination** — the question is ambiguous; either verdict is defensible

Reconciliation distinguishes which case applies. Without reconciliation, the user picks the latest session's verdict by default — silently treating it as authoritative when it may not be.

---

## Conflict types

### Type 1: Same workspace, resume produced different verdict

Setup: original session in workspace W produced "H-005 confirmed". Resume of W produced "H-005 refuted."

Most likely cause: corpus drift OR new evidence surfaced during resume that wasn't in original Phase 4.

### Type 2: Different workspaces, same question

Setup: workspace W1 (cc-dominant Squad) produced verdict A. Workspace W2 (gmi-dominant Squad) on same question produced verdict B.

Most likely cause: model-family bias (per F-602); reconciliation should use a third family OR external review.

### Type 3: Different workspaces, related questions

Setup: W1 said "X is bottleneck"; W2 (slightly different question) said "Y is bottleneck."

Most likely cause: question framing difference; both may be correct in their respective scopes.

### Type 4: Sequential sessions, methodology evolved

Setup: W1 (pre-improvement) used methodology version V1. W2 (post-improvement) used V2 with improved Phase 7 audit. W2's verdict differs from W1.

Most likely cause: methodology improvement caught what V1 missed; W2 is more defensible.

---

## The reconciliation procedure

When conflict detected:

### Step 1: Establish the conflict

Run `subagents/reconciler.md` (Tier-4 subagent) with both workspaces as input. Output: structured conflict description.

### Step 2: Diagnose conflict type

For each session pair:

- Run `subagents/cass-miner.md` to find prior reconciliation patterns
- Compare workspaces' `intake/question_of_record.md` content-hashes — same question?
- Compare workspaces' `corpus/corpus_index.md` content-hashes — same corpus?
- Compare workspaces' methodology version — same operator algebra, marching orders?
- Compare workspaces' rosters — same model-family mix?

Match to Type 1-4 above.

### Step 3: Apply reconciliation per type

#### Type 1 reconciliation

Verify: did corpus drift between sessions?

- If yes: re-run the affected Phase 4 investigation with current corpus; W1's verdict is stale
- If no: did new EVs surface that contradict W1? File the new evidence; the resume's verdict supersedes
- Document in `deliverables/RECONCILIATION-MEMO.md` per template

#### Type 2 reconciliation

Verify: model-family bias?

- Run a third session with a NEUTRAL family (or all 3 if not previously)
- The 3-session triangulation produces the canonical verdict
- Per CROSS-SESSION-LEARNING.md, document the cc-vs-gmi disagreement as a pattern; may surface a methodology issue

#### Type 3 reconciliation

Don't reconcile — both sessions are correct in their scope. Instead:

- Cross-link W1 and W2 in their respective HANDBACK.md files
- Document "X is bottleneck under scope S1" + "Y is bottleneck under scope S2"
- The user picks based on which scope applies to their use case

#### Type 4 reconciliation

The newer methodology is more defensible. Document:

- W1's verdict was reached under methodology version V1
- V1 missed <specific issue> that V2 catches
- W2's verdict supersedes W1 for the question

But also: was there a methodology improvement between V1 and V2? If yes, it caught the issue. If no, then the methodology improvement should be retroactively applied to W1 too.

### Step 4: Produce RECONCILIATION-MEMO.md

```markdown
# Reconciliation Memo — RS-<NEW>-vs-RS-<OLD>

**Reconciliation date:** <ISO>
**Operator:** <name>

## Sessions in conflict

- W1 (RS-...): verdict A; cited evidence <list>
- W2 (RS-...): verdict B; cited evidence <list>

## Conflict diagnosis

**Type:** Type 1 / 2 / 3 / 4

**Diagnosis:**
- Question hash match: yes / no
- Corpus hash match: yes / no
- Methodology version match: yes / no
- Roster match: yes / no
- Model family difference: <details>

## Reconciliation verdict

**Per Type <N>:** <verdict explanation>

**Canonical session for the question:** <W1 | W2 | merge | both>

**Action for user:**
- <specific recommendation>

## Methodology lessons

- <lesson 1>
- <lesson 2>

## Cross-references

- Update W1's HANDBACK § Cross-session note: "Reconciled vs RS-..."
- Update W2's HANDBACK § Cross-session note: "Reconciled vs RS-..."
- Update CROSS-SESSION-DRIFT-CATALOG.md with this conflict pattern
```

---

## Multi-session triangulation (T5)

For T5 (existential) decisions, multiple sessions on the SAME question may be deliberate (per CROSS-SESSION-LEARNING.md "Cross-session triangulation"). The reconciliation discipline applies but is *expected*.

For T5:

1. Plan ≥3 sessions in advance
2. Each session uses different operator (different person), different roster, different time
3. Reconciliation memo cites all 3 sessions
4. Disagreements across sessions go into `meta-DRIFT-CHECK.md` (a Phase 10 across all 3)
5. Final decision memo (per ADR-PATTERNS.md) cites the meta-DRIFT-CHECK

This is heavyweight; only justifiable for decisions with multi-year + irreversible consequences.

---

## Catalog of resolved conflicts

`references/RECONCILIATION-CATALOG.md` (created on first reconciliation):

```markdown
# Reconciliation Catalog

| Conflict ID | Sessions | Type | Verdict | Date | Notes |
|-------------|----------|------|---------|------|-------|
| RC-001 | RS-A vs RS-B | Type 1 | RS-B canonical (corpus drift) | 2026-05-12 | New paper invalidated H-005 |
| RC-002 | RS-C vs RS-D | Type 2 | merged via 3-family triangulation | 2026-06-03 | Family-bias detected |
| RC-003 | RS-E vs RS-F | Type 3 | both canonical for distinct scopes | 2026-06-15 | Workload-class boundary |
```

The catalog feeds Phase 10 drift analysis and surfaces patterns:

- Many Type 1 conflicts → corpus is too volatile; verification-first protocol needs strengthening
- Many Type 2 conflicts → model-family bias systemic; rotation rules need tightening
- Many Type 4 conflicts → methodology evolves frequently; document lessons better

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Pick latest session's verdict by default without reconciliation | Treats verdict order as authoritative; ignores type 2-4 conflicts |
| Reconcile by averaging the verdicts | Per F-601 silent averaging — anti-Brenner |
| Skip reconciliation memo (just pick one) | Loses methodology trail; future readers can't verify |
| Run reconciliation before both sessions complete | Premature; let each session reach Phase 9 first |
| Reconcile from a swarm pane of either session | Like Phase 10 drift, reconciliation requires fresh perspective |
| Treat reconciliation as a "tie-breaker" | It's evidence-based, not procedural; type matters |
| Skip catalog entry | Patterns won't emerge across sessions |

---

## Reconciler subagent

`subagents/reconciler.md` is the canonical entry point. Like `drift-auditor.md`, it must be a FRESH agent — not a swarm pane from either session.

```
Agent({
  description: "Reconcile brennerbot sessions",
  subagent_type: "general-purpose",
  prompt: "<contents of subagents/reconciler.md, with <SESSION_W1_PATH> and <SESSION_W2_PATH> filled>"
})
```

The reconciler reads both workspaces in read-only fashion, produces RECONCILIATION-MEMO.md, and updates the catalog.

---

## When reconciliation surfaces a methodology bug

Sometimes reconciliation reveals that the methodology itself produces inconsistent verdicts on the same question. This is a Phase 10 lesson:

- Update OPERATORS.md if an operator card was misapplied in one session
- Update FAILURE-TABLE.md if a new failure mode is identified
- Update OPERATOR-CALIBRATION-LOG.md with the inconsistency

Track via CROSS-SESSION-DRIFT-CATALOG.md. After ≥3 reconciliations all surfacing the same methodology issue, promote to canonical fix.

---

## Reconciliation as a service

For organizations running many brennerbot sessions, reconciliation can be operationalized:

- Quarterly review of all completed sessions; identify pairs that should be reconciled
- Designated reconciler role (often a methodology expert)
- Reconciliation memos as cross-session evidence base
- Catalog feeds methodology evolution

For solo operators, reconciliation is on-demand when the operator notices conflict.

---

## Composition with other patterns

- Per CROSS-SESSION-LEARNING.md: reconciliation feeds the lesson-commitment protocol
- Per ADR-PATTERNS.md: reconciled verdicts may produce or update ADRs
- Per VERIFICATION-FIRST.md: Type 1 corpus drift triggers verification-first re-fetch
- Per MIGRATION-FROM-BRENNER-CLI.md (if applicable): when migrating from brenner_bot CLI sessions to brennerbot-with-ntm, reconcile the prior verdicts

Use the composition that fits the conflict context.
