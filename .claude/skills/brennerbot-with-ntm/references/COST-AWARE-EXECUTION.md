# COST-AWARE-EXECUTION.md — Running brennerbot Under Budget Constraints

<!-- TOC: Why cost matters | Cost dimensions | Per-tier cost envelopes | Compression strategies | When to escalate | When to compress | Cost vs methodology tradeoffs | Cost-aware operator-cards | Anti-patterns | Per-mode cost adjustments -->

Companion to WALL-TIME-BUDGET.md. Wall-time is one cost dimension; tokens, model spend, attention, and human-time are others. Operators routinely face budget constraints that don't map cleanly to tier × phase tables.

This file gives the operator a framework for cost-aware decisions: when to compress, when to escalate, when to decline.

---

## Why cost matters

A T3 session that does the right methodology costs ~5-8h wall + 50k-200k tokens + 1-3 model accounts. Done weekly across many questions, this adds up. Operators who don't manage cost:

- Burn through quota mid-session (rate limits)
- Miss windows for time-sensitive decisions
- Accumulate "complete-but-not-actionable" sessions

Cost-aware operators:

- Match tier to actual stakes (don't over-engineer)
- Front-load cost-cutting decisions (compose with existing data)
- Recognize when a question doesn't justify a session at all

---

## Cost dimensions

```
Cost(session) = wall_time + token_burn + model_account_quota +
                human_attention + decision_latency + downstream_followup
```

### Wall time

Per WALL-TIME-BUDGET.md. Operator's clock-time investment + parallel pane work. Solo: 1-3h. Pair: 2-5h. Squad: 4-8h. Swarm: 6-15h.

### Token burn

Per-pane × per-round. Investigators read corpus + write evidence packs. Synthesizers read distillations + write meta-synthesis. Auditors re-read everything.

Rough estimates:
- Solo session: 30k-80k tokens
- Pair: 50k-150k
- Squad: 150k-400k
- Swarm: 400k-1.5M

For sessions with large corpus (T4 academic-replication on 100MB+ papers): 1M-5M tokens.

### Model account quota

Each pane runs on a model account (Claude Max, GPT Pro, Gemini Ultra). Per-account daily/weekly quotas. A Squad session running 4-8h consumes ~30-60% of a single account's daily quota.

If quota is shared across multiple sessions per day, sessions compete.

### Human attention

The operator is the bottleneck. They tend the swarm, dispatch MOs, run audits, write HANDBACK. Estimated: 20-40% of wall time = active operator work.

For T4+: 40-60% (heavier judgment load).

### Decision latency

Time from "user asked" to "user can act on verdict". Includes:
- Phase 1 framing (often 20-60 min with user iteration)
- Bootstrap (5-15 min)
- Active phases (per tier)
- Phase 9 handback (15-30 min)
- Possible Phase 10 drift (15-60 min)

Total decision latency: typically 1.2-1.5× wall time due to user-side iteration.

### Downstream followup

Some sessions surface Phase 10 lessons that demand methodology changes. That's time spent OUTSIDE the session updating references/ and committing.

---

## Per-tier cost envelopes

```
TIER | Wall  | Tokens     | Accts | Op-hr | Use case
-----|-------|------------|-------|-------|----------
T1   | <1h   | 30k-80k    |   1   | 0.3-1 | Curiosity, dry-run, individual learning
T2   | 1-3h  | 80k-300k   | 1-2   | 0.7-2 | Engineering decision, reversible
T3   | 3-8h  | 300k-1.5M  | 2-4   | 2-4   | High-stakes engineering or research question
T4   | 1-3d  | 1M-5M      | 3-6   | 8-20  | Pre-publication, security audit, major architecture
T5   | 1-4w  | 5M+        | 6+    | 40+   | Foundational decision, regulatory commitment
```

These are rough envelopes. Specific scenarios deviate by 2-3× depending on corpus size, mode (incident vs methodology), and recipe.

---

## Compression strategies (saving cost without quality loss)

When budget is tight but the question warrants the tier:

### C1 Recipe-driven bootstrap

Per DOMAIN-RECIPE-LIBRARY.md, recipes save 30-60 min of Phase 1 + Phase 2. For T2-T3 sessions, this is 10-20% of total wall.

### C2 Compose with existing data

Run /flywheel + /cass to find prior sessions on related topics. If a prior session answered 80% of the current question, the new session can skip Phase 4 entirely and just verify + extend.

### C3 Tighter Phase 1 framing

Anti-AE-1.* practices. A session with sound Phase 1 framing avoids 20-40% of Phase 4 churn caused by mid-session reframing.

### C4 Quickie-pilot first

Per OC-010 (OPERATOR-CARDS.md): a 30-min cheap probe before a 3-hour flagship investigation. Often kills the H or surfaces the answer for ~10× cheaper.

### C5 Targeted Phase 7 audit

Don't audit everything. Per OPERATOR-CARDS.md OC-019 + OC-020 + OC-021: focus the audit on (a) load-bearing claims, (b) scale_physics assumptions, (c) any softened falsifier. This reduces audit cost ~50% with minimal quality loss.

### C6 Skip Phase 10 (with caveat)

For T1-T2 sessions, Phase 10 drift check is optional. Saves 15-30 min at the cost of cross-session learning.

### C7 Roster prune

For Pair tier with rate-limit risk: 1 cc + 1 gmi instead of 2 cc + 1 cod. Slight diversity loss but better quota margin.

### C8 Per-family trimming

For Squad tier where one family is degraded: explicit "only 2 families available" note in scope_decision; reduce per-family distillation expectations.

---

## When to escalate (don't compress further)

Escalate from compressed to full when:

- **Stakes mismatch detected**: started as T2, but Phase 4 reveals load-bearing decision is T3+
- **Convergence failure at compressed tier**: kill_rate < add_rate persistently → tier may be insufficient
- **Audit reveals methodology gap**: Phase 7 catches issues that Phase 4 didn't probe
- **External event**: regulatory deadline, customer commitment, team-decision blocker

When escalating:
1. Explicit checkpoint with user (per P7.2 OPERATOR-PROMPT-LIBRARY.md)
2. Estimate budget delta
3. Get explicit OK before proceeding
4. Update `phase0_scope_decision.md § tier_escalation` log

---

## When to compress (don't escalate)

Compress when:

- **Stakes lower than initially estimated**: started as T3, Phase 1 framing reveals it's curiosity
- **Recipe match indicates lower tier**: question shape matches T1-T2 recipe
- **Time-pressure demands ship-or-pass decision**: incident-investigation mode uses compressed Phase 1 + Phase 3 + Phase 5 with inline investigation + Phase 7

When compressing:
1. Document in scope_decision: "compressed from T<N> to T<N-1> because <specific reason>"
2. Mark deliverables with compressed-tier caveat
3. Flag in HANDBACK: "Tier-compressed; if stakes are higher than estimated, re-run at T<N+1>"

---

## Cost vs methodology tradeoffs

Some methodology elements are NOT compressible without quality collapse:

### Non-negotiable at any tier

- ✂ Exclusion-Test (Phase 4 falsifier-firing) — without this, you're not running brennerbot
- Independent verification of load-bearing EVs (per VERIFICATION-FIRST.md)
- Disagreement register (per F-603) when ≥2 families distilled
- Phase 10 drift verdict from FRESH agent (not swarm pane) for T3+

### Compressible at T1-T2

- Phase 6 disagreement register (Solo/Pair tier may have only 1 distillation)
- Phase 10 lesson commitment (defer to next session)
- Pre-bootstrap recipe checks (operator can mentally apply)
- Replication of cited evidence (defer if not load-bearing)

### Tradeoff matrix

```
ELEMENT                  | T1 | T2 | T3 | T4 | T5
-------------------------|----|----|----|----|-----
Phase 1 framing rigor    | M  | H  | M  | M  | M    (M=mandatory, H=helpful, S=skip)
✂ Exclusion-Test         | M  | M  | M  | M  | M
Cross-family triangulation | S | H  | M  | M  | M
Independent verification | S  | H  | M  | M  | M
Replication              | S  | S  | H  | M  | M
Phase 7 audit            | H  | M  | M  | M  | M
Phase 10 drift           | S  | H  | M  | M  | M
External review (Layer 6)| S  | S  | S  | M  | M (≥2)
```

---

## Cost-aware operator cards

### OC-Cost-1: Quota pre-check

Before bootstrap, check `/caam` quota state across all accounts. If <30% remaining for any required family: defer or escalate to fresh accounts.

### OC-Cost-2: Token-aware pane selection

For long-corpus sessions (T4+), prefer model versions with larger context windows. Document in scope_decision.

### OC-Cost-3: Mid-session quota alert

At each tick, check token burn vs estimate. If burning > 1.5× estimate by mid-Phase-4: pause and decide (compress remaining phases OR escalate budget).

### OC-Cost-4: Phase-aware compression

Compression generally happens at Phase 4 round count and Phase 7 audit depth. Phase 1 (framing) and Phase 6 (disagreement register) are less compressible without quality loss.

### OC-Cost-5: Resume-friendly mid-session pause

If wall-time budget exhausted but Phase 4 incomplete: don't push through. Run Phase 8 freeze early; HANDBACK indicates "session paused; resume from Phase 4 round N". Resume in next budget window.

---

## Per-mode cost adjustments

### Mode: incident-investigation (≤60min compressed)

- Phases 1, 3, 5, 7 only
- Pair tier (1 cc + 1 cod)
- ~80k-200k tokens
- Skip Phase 6 distillation (Pair tier doesn't have it anyway)
- Skip Phase 10 (covered by post-mortem-formalization mode if recurrence)

### Mode: post-mortem-formalization (4-6h)

- All 10 phases
- Squad tier
- ~500k-1M tokens
- Per POST-MORTEM-FORMALIZATION-PLAYBOOK.md

### Mode: living-review (per-tick incremental)

- Phase 4 + 7 refresh per tick (cadence: weekly/monthly/quarterly)
- ~30-100k tokens per tick
- Pair tier sustaining session
- Total cost amortized across the long-running review

### Mode: red-team-only (focused audit)

- Phase 1 (compressed) + Phase 4 + Phase 7
- Pair or Squad
- ~150-400k tokens
- Compose with /security-audit-for-saas

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Run T4 always to be safe | Burns quota; most questions don't need T4 |
| Compress methodology to fit budget | Some elements are non-negotiable |
| Skip cost-pre-check (quota) | Mid-session rate-limit is operationally expensive |
| Treat all token burn as equal | Long-corpus reads burn 10× more than typical |
| Skip recipe-driven bootstrap | 30-60 min savings compound across many sessions |
| Hide compression from user | User should know what tier was actually applied |
| Ignore decision latency | A "fast" T3 still has 1.2-1.5× decision-latency multiplier |

---

## Operator self-check before bootstrap

1. What's the actual tier for this question's stakes?
2. Are there prior sessions (per /flywheel + /cass) I should compose with?
3. Is my account quota adequate for this tier × roster?
4. Does a recipe match? If yes, use it.
5. Will I have operator-attention to tend the swarm for the estimated wall time?
6. What's my fallback if quota / time runs short mid-session?

This 5-min self-check saves 30-60 min of wasted work per session.

---

## Cross-references

- WALL-TIME-BUDGET.md (the wall-time-specific protocol)
- TIER-TRIAGE.md (tier selection)
- DOMAIN-RECIPE-LIBRARY.md (recipe-driven bootstrap)
- /caam (account quota management)
- /vibing-with-ntm OC-001 rate-limit probe
- EXTENDED-OPERATING-MODES.md (mode-specific cost adjustments)
