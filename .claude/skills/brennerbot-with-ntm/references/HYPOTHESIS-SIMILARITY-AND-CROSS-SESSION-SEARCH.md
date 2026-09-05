# HYPOTHESIS-SIMILARITY-AND-CROSS-SESSION-SEARCH.md — Vector Search for Brenner Sessions

<!-- TOC: Why similarity search | The two search dimensions | Hypothesis-similarity matching | Operator-aware quote matching | The semantic-quote sidebar pattern | Cross-session reconciliation triggers | Per-archetype clustering | Anti-patterns | Cross-references -->

A 10+-session-per-week operator (per BRENNERBOT-AT-SCALE.md) accumulates dozens of hypotheses, hundreds of evidence packs, thousands of Brenner quote anchors. Without semantic search, this corpus is write-only.

Brenner_bot adds **vector-based semantic similarity search** across two dimensions: hypothesis-to-hypothesis (find prior sessions that asked similar questions) and operator-to-quote (surface Brenner anchors relevant to the current operator move).

This file specifies the similarity-search infrastructure, the two dimensions, the integration patterns, and the cross-session reconciliation triggers.

Mined from `/dp/brenner_bot/CHANGELOG.md` v0.2.0 § Search & Discovery.

---

## Why similarity search

Three failures without:

1. **Reinventing wheels** — operator A in March asks H-001-shaped question; operator B in June asks H-001-shaped question; neither knows the other ran it
2. **Lost quote leverage** — Brenner's transcript has 200+ anchored sections; the operator can't recall which §n applies to "what would I see if this were true?"
3. **Cross-session conflict invisible** — two sessions reach contradictory verdicts on similar questions; no one notices

Three benefits:

1. **Cross-session reuse** — prior sessions surface as evidence-pack candidates
2. **Quote retrieval at the moment of need** — the operator's current dispatch suggests relevant Brenner anchors
3. **Reconciliation triggered automatically** — semantic similarity flags conflicts for explicit resolution

---

## The two search dimensions

### Dimension A: Hypothesis-similarity

For a given hypothesis claim:
> "Cell fate is primarily determined by intrinsic, cell-autonomous mechanisms involving PAR protein polarization"

Search across all sessions for semantically-similar prior H beads:

```
brenner hypothesis search "intrinsic polarity-driven fate determination" --limit 5
```

Returns:

```json
[
  {
    "session_id": "RS-20251205-ascidian-fate",
    "h_id": "H-002",
    "claim": "Polarity-driven fate in ascidian embryos: PAR2-3 establish cortical asymmetry",
    "state": "validated",
    "similarity_score": 0.91,
    "verdict": "PAR-driven asymmetry validated"
  },
  {
    "session_id": "RS-20251128-drosophila-bcd",
    "h_id": "H-005",
    "claim": "Bicoid-driven cortical-fate determination",
    "state": "killed",
    "similarity_score": 0.78,
    "verdict": "Killed by EV-013"
  }
]
```

Use cases:
- **Phase 3 hypothesis generation**: don't propose what's already been killed; build on what's validated
- **Phase 7 audit**: cross-session conflict check
- **Cross-session reconciliation**: per RECONCILIATION-OF-PRIOR-SESSIONS.md Type 2 (semantic-conflict)

### Dimension B: Operator-aware quote matching

For a given operator move and current pane state:

```
brenner quote search --operator "✂ Exclusion-Test" --context "designing test that distinguishes H-001 from H-002"
```

Returns the top-N Brenner transcript anchors tagged with the relevant operator + semantic-fit:

```json
[
  { "anchor": "§103", "text": "You've forgotten there's a third alternative...", "operator_tags": ["✂", "⊕"], "fit": 0.93 },
  { "anchor": "§147", "text": "Exclusion is always a tremendously good thing.", "operator_tags": ["✂"], "fit": 0.88 },
  { "anchor": "§99", "text": "Well, I'll do a quickie.", "operator_tags": ["⌂", "🔧"], "fit": 0.81 }
]
```

Use cases:
- **MO dispatch**: include relevant Brenner quotes in the marching order
- **Critique grounding**: per CITATION-PROVENANCE-RULES.md, every load-bearing claim cites `§n`; quote-search makes this fast
- **HANDBACK voice**: surface the most relevant Brenner anchor for the verdict

---

## The semantic-quote sidebar pattern

Per `/dp/brenner_bot/CHANGELOG.md` v0.2.0 § Integrate semantic quote matching sidebar into session pages:

In the brennerbot web app, every session page has a **sidebar** showing the top-5 Brenner anchors relevant to the current artifact state. As the operator works:

- A new H is proposed → sidebar updates with anchors relevant to the H's claim
- An EV is added → sidebar updates with anchors relevant to the EV's relevance field
- A C is filed → sidebar updates with anchors relevant to the critique's attack

The sidebar is **passive context** — the operator doesn't query; the system suggests. Per OBSERVABILITY.md tick cadence: the sidebar refreshes every tick.

In a CLI-only environment (no web app), the equivalent would be `scripts/quote-sidebar.sh --watch` (Tier-7 future addition). Until that exists, the operator runs `./scripts/quote-bank-extract.sh` periodically and reads the output.

---

## Cross-session reconciliation triggers

When a new session's H bead has high similarity (>0.8) to a prior session's terminal-state H, the system **auto-flags**:

```
DETECTION: H-002 in RS-20260301-... matches H-005 in RS-20251128-... (similarity: 0.85)
PRIOR VERDICT: H-005 was killed (kill_reason: "Contradicted by EV-013 [verbatim] showing fate-loss after ablation")
ACTION REQUIRED: file CF-NNN counterfactual; OR cite RS-20251128-...:H-005 verdict in current H-002
```

The operator must:
1. Acknowledge the prior session
2. Either: cite the prior verdict, OR explain why the current question differs
3. File a `CF-NNN` if running a counterfactual (per WHAT-IF-COUNTERFACTUAL-EXPLORER.md)

Bypassing the trigger generates an audit-finding bead (`severity: high`).

---

## Per-archetype clustering

Hypothesis search returns more useful results when clustered by question archetype (per QUESTION-ARCHETYPES.md):

```bash
brenner hypothesis search "tail-latency p99 spike under memory pressure" --archetype A4 --limit 5
```

A4 (incident) archetype returns prior incident sessions only. Per ARCHETYPE-START-PACKS.md: each archetype has its own embedding namespace, so cross-archetype false-positives are rare.

---

## Implementation: vector embeddings

The similarity search is implemented via **vector embeddings**:

1. Each H, EV, anchor is embedded via a sentence-transformer model
2. Embeddings stored in a local vector DB (per `.bv/semantic` in workspace)
3. Search is k-NN against the embedding store

Properties:
- **Local-first** — no API calls; embeddings computed once
- **Fast** — sub-100ms per query for ≤10k embeddings
- **Operator-tag aware** — operator-tagged search filters by tags before semantic ranking

Per BRENNERBOT-AT-SCALE.md: at 10+ sessions/week, the embedding store grows to ~10k items per quarter; `bv` indexer rebuilds incrementally.

---

## Output integration

### Phase 3 hypothesis generation MO

The MO-03a-propose.md template includes:

```
Before proposing, run `brenner hypothesis search <draft-claim>` and review prior sessions.
If similarity >0.8 with prior validated H, cite that H and state how this proposal differs.
If similarity >0.8 with prior killed H, you MUST acknowledge: "Prior session killed similar H; this differs because ..."
```

### Phase 4 evidence MO

The MO-04a-investigate.md template includes:

```
Before importing new EV, run `brenner evidence search <topic>` to check if a prior session imported the same source.
If yes, use `brenner evidence import-from-session` rather than re-importing.
```

### Phase 9 HANDBACK MO

The MO-09-handback.md template includes:

```
Run `brenner quote search --context "<verdict-claim>"` and cite the most-relevant Brenner anchor in the verdict line.
```

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Skip similarity check at Phase 3 | Risk of re-running prior killed Hs |
| Use plain string match instead of vector similarity | Semantic similarity catches paraphrase; string match doesn't |
| Cross-archetype search without filter | False positives from unrelated domains |
| Trust similarity score as truth ("0.85 means same H") | Verify by reading; similarity is a *trigger*, not a verdict |
| Skip auto-trigger reconciliation | Audit-finding generated; reviewer will catch later |
| Embed only H claims (not anchors, not EVs) | Operator-aware quote matching needs all 3 dimensions |
| Re-embed everything daily | Incremental indexing; only re-embed changed items |
| Use single-language embedding model for multi-domain | Per archetype; tune per domain pack |

---

## Cross-references

- [RECONCILIATION-OF-PRIOR-SESSIONS.md](RECONCILIATION-OF-PRIOR-SESSIONS.md) — Type 2 (semantic-conflict) reconciliation
- [WHAT-IF-COUNTERFACTUAL-EXPLORER.md](WHAT-IF-COUNTERFACTUAL-EXPLORER.md) — counterfactual filing on conflict
- [QUESTION-ARCHETYPES.md](QUESTION-ARCHETYPES.md) — per-archetype embedding namespaces
- [ARCHETYPE-START-PACKS.md](ARCHETYPE-START-PACKS.md) — embedding-store seed
- [QUOTE-BANK-METHODOLOGY.md](QUOTE-BANK-METHODOLOGY.md) — anchor-tagged quote bank as embedding source
- [CITATION-PROVENANCE-RULES.md](CITATION-PROVENANCE-RULES.md) — `§n` citation for verdict claims
- [OBSERVABILITY.md](OBSERVABILITY.md) — quote-sidebar tick cadence
- [BRENNERBOT-AT-SCALE.md](BRENNERBOT-AT-SCALE.md) — at-scale embedding store
- /dp/brenner_bot/CHANGELOG.md v0.2.0 § Search & Discovery — feature source
