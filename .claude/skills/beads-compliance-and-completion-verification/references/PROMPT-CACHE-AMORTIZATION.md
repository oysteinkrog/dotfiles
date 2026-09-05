# PROMPT-CACHE-AMORTIZATION.md — Make 1000-bead Squad/Swarm passes affordable

Naïve audit: each subagent loads SKILL.md (~53 KB) + rubric.md (~10 KB) + bead body for every Phase 2-6 invocation. For 1000 beads × 5 phases × 6 parallel subagents, that's 30,000 loads of the same 60+ KB. Without prompt caching, the cost is dominated by re-shipping the same context.

With Anthropic prompt caching at the right breakpoints, the same workload bills as a single 60 KB prefix + per-bead deltas. Empirically: 70-90% cost reduction on Squad/Swarm tier, no quality loss.

This doc is the reference architecture; it composes with `/claude-api`.

---

## What to cache, where

### Tier 1 — global to the audit (cache for the lifetime of a pass)

| Resource | Size | Cache | Refresh on |
|----------|-----:|:-----:|------------|
| `SKILL.md` | ~53 KB | YES | rubric_sha256 change |
| `rubric.md` | ~10 KB | YES | content change |
| `references/RUBRIC.md` | ~8 KB | YES | content change |
| `references/FAILURE-MODES.md` | ~20 KB | YES | content change |
| `references/EVIDENCE-SCHEMAS.md` | ~13 KB | YES | content change |
| `manifest.json` | < 5 KB | NO | per-bead noisy |

### Tier 2 — per-phase (cache for the lifetime of a phase)

| Resource | Cache | Refresh on |
|----------|:-----:|------------|
| Phase 2 prompt module + spec extractor instructions | YES | subagent file change |
| Phase 5 theater pattern catalog (compiled) | YES | rubric.md `project_theater_patterns` change |
| Phase 6 coverage harness command + tool versions | YES | manifest.json#tool_versions change |

### Tier 3 — per-bead (always fresh)

| Resource | Cache | Why not |
|----------|:-----:|---------|
| `show.json` | NO | bead-specific |
| `evidence.json` | NO | bead-specific |
| `compliance.json#raw/` | NO | bead-specific test outputs |

---

## Anthropic API cache breakpoints

Use 4 breakpoints per request, in this order (most-stable first):

```
[SYSTEM]
  <SKILL.md>                          ← breakpoint 1
  <rubric.md>                         ← breakpoint 2
  <subagent SKILL definition>         ← breakpoint 3

[USER]
  <bead-specific evidence>            ← breakpoint 4 (per Phase, varies)
  <task instruction>
```

Breakpoints 1-3 are stable across an entire pass; breakpoint 4 changes per bead.

`/claude-api` skill has the exact patterns for `cache_control` in the messages API; use it directly. Don't re-derive.

---

## Cost projections (back-of-envelope)

For a 200-bead Pair-tier pass on Sonnet 4.6 (input $3/Mtok, output $15/Mtok, cached input $0.30/Mtok):

- **No caching:** ~50M input tok ($150) + ~5M output tok ($75) = **~$225 / pass**
- **With caching (Tier 1+2):** ~5M cached input tok ($1.50) + ~3M fresh input tok ($9) + ~5M output ($75) = **~$85 / pass**

For Squad-tier (1000 beads), the savings scale linearly: ~$1100 → ~$420 / pass.

For daily Tripwire mode at Squad tier: monthly cost goes from ~$33,000 to ~$12,500. The cache pays for the audit infrastructure many times over.

---

## Cache invalidation rules

| Trigger | What to flush |
|---------|---------------|
| `rubric.md` content change | Tier 1 + Tier 2 phase-5 catalog |
| `SKILL.md` content change | Tier 1 entirely |
| Tool version bump (rg, jq, br) | Tier 2 phase-6 |
| New `references/FAILURE-MODES.md` pattern | Tier 1 + Tier 2 phase-5 |
| Subagent prompt file change | Tier 2 for that subagent only |

`scripts/bootstrap-audit.sh` writes a `cache_breakpoint_sha.json` per-pass that records each Tier's content hashes. The orchestrator compares to the prior pass and decides which Tier to invalidate.

---

## Anti-patterns

- **Caching evidence files.** Each bead's evidence is bead-specific; caching pollutes context windows.
- **Caching tests' raw outputs.** They're per-pass volatile.
- **Multiple `cache_control` markers on the SAME static block.** Anthropic prefers ≤ 4 breakpoints; nesting wastes a slot.
- **Forgetting to refresh when rubric tightens mid-pass.** `☖ STAKE-RUBRIC` operator forbids tuning mid-pass — including via cache contamination from the prior rubric.

---

## Differential auditing (related, not the same)

Per `references/COST-OPTIMIZATION.md`, differential auditing (re-verify only beads whose evidence files changed) drops 80%+ of work to cached-forward. That's a *separate* lever from prompt caching:

- **Differential auditing** = run fewer subagent invocations.
- **Prompt caching** = make each invocation cheaper.

Stack both for compounding savings.

---

## Worked example: tripwire pass at Swarm tier

```
1000 beads in universe
880 unchanged since prior pass (cached-forward)
120 actually re-verified

Per re-verified bead:
  - Phase 2: ~5K cached prefix + ~2K fresh = ~$0.0006 input, ~$0.003 output
  - Phase 3: ~5K cached + ~3K fresh = ~$0.001 input, ~$0.005 output
  - Phase 5: ~12K cached + ~2K fresh = ~$0.0007 input, ~$0.003 output
  - Phase 6: ~5K cached + ~4K fresh = ~$0.0014 input, ~$0.007 output
  - Phase 8 (deterministic): $0
  Subtotal: ~$0.025 / bead

Phase 7 synthesis: 1 invocation, ~50K cached + ~30K fresh + ~10K output = ~$0.50
Phase 10 fresh-eyes: 1 invocation, ~50K cached + ~10K fresh + ~5K output = ~$0.20

Total: 120 × $0.025 + $0.50 + $0.20 = ~$3.70 / pass
```

Daily Tripwire at this rate is < $115/month for a 1000-bead Swarm. Without caching it would be > $30,000/month.

---

## Operator pairing

`⟴ AMORTIZE` (Phase 0.5: declare cache breakpoints upfront and reuse them across phases). Pairs with `⊠ PIN` (rubric_sha256) — the cache key IS the pinned rubric SHA.
