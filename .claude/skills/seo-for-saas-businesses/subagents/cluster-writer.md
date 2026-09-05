# subagent: cluster-writer

Role: Phase 4 brief + draft for one cluster. Same agent that researched the cluster in Phase 2 writes its content here — preserves intent fidelity and voice.

## Parameters

- `cluster`: cluster name (from Phase 2)
- `cluster_research_path`: `analyses/clusters/<cluster>.md`
- `audit_findings_path`: filtered `analyses/audit-issues.json` for this cluster's URLs
- `brand_voice_samples`: paths to existing on-site copy that represents brand voice
- `proof_inventory_path`: `analyses/proof-library.md`

## Tasks

For each priority page in the cluster:

1. Build a brief per [BRIEF-TEMPLATE](../assets/BRIEF-TEMPLATE.md). Three-plus unique data points are non-negotiable.
2. Draft the page following the brief exactly.
3. Run slop-check via `/de-slopify` if installed, or the [SLOP-CHECKLIST](../references/SLOP-CHECKLIST.md) manually.
4. Run AI-citation-eligibility check: passages of 50–150 words, direct answer up front, dated numeric data points, source links.
5. Run high-risk gate if applicable per [HIGH-RISK-GATE](../references/HIGH-RISK-GATE.md).
6. Cross-reference Phase 3 audit findings — if rendering / schema / metadata findings touch this page, note in brief so Phase 6 PR addresses both.

## Outputs

- `deliverables/briefs/<cluster>/<page>.md`
- `deliverables/drafts/<cluster>/<page>.md`
- Optional: schema JSON-LD ready to embed

## Done when

- Brief has all sections complete, no `TBD`.
- Draft passes slop-check.
- Draft has at least three unique data points (research, screenshot, internal benchmark, dated quote, original analysis) visible without JS.
- All factual claims sourced + confidence-labelled.
- Conversion path explicit.
- High-risk gate (if applicable) complete.
- Owner human assigned and refresh cadence documented.

## Anti-patterns

- Dumping LLM output without verification, sourcing, or human ownership.
- Generic comparison content that fabricates competitor limitations.
- Word-count theatre.
- Padded introductions.
- "It's worth noting that…" filler.
- Three-of-a-kind generic adjectives.
- Skipping the brief and going straight to draft.
- Targeting a query whose SERP wants product / video / forum and writing an article instead.
