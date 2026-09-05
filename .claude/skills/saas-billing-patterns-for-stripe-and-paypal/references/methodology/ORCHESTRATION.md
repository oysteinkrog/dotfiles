# Orchestration

How to fan out subagents across the phase loop without stepping on each other or burning context.

---

## Tier matrix

Pick based on repo size, mode, and time budget.

| Tier | Workers | Coordination | When |
|------|---------|--------------|------|
| **Solo** | 1 main agent, serial phases | none | <20 billing-touching files; `add-feature` mode; pre-launch product |
| **Pair** | 2 workers, fan-out only on Phase 5 | informal handoff via `.billing_workspace/` files | Typical Next.js SaaS, single provider, audit-and-fix |
| **Squad** | 4–6 workers, parallel by bundle in 1, 5, 6 | Agent Mail file reservations + per-bundle `phase*_<bundle>.md` artifacts | Dual-provider SaaS with team plans, full audit-and-fix |
| **Swarm** | 8–12 workers, beads-driven + multi-model triangulation in 7 | Agent Mail + beads + per-model triangulation harness | Multi-product platform; SOC2 audit pressure; greenfield with deadline |

---

## Bundle ownership

The 12 pattern bundles partition naturally:

| Bundle | Pattern file | Typical # workers |
|--------|--------------|-------------------|
| B00 — Principles | `00-NORTH-STAR.md` | 0 (read-only by all) |
| B10 — Schema | `10-SCHEMA.md` | 1 (must finish before others) |
| B20 — Constants/env | `20-CONSTANTS-AND-ENV.md` | 1 |
| B30 — Checkout | `30-CHECKOUT.md` | 1 |
| B40 — Webhooks | `40-WEBHOOKS.md` | 1 (often the longest) |
| B50 — Security | `50-SECURITY.md` | 1 (often paired with B40) |
| B60 — State / lifecycle | `60-STATE-AND-LIFECYCLE.md` | 1 |
| B70 — Dunning | `70-DUNNING-AND-PROACTIVE.md` | 1 |
| B80 — Teams | `80-TEAMS.md` | 1 (skip if no teams) |
| B90 — Reliability | `90-RELIABILITY.md` | 1 |
| B100 — Analytics | `100-ANALYTICS.md` | 1 |
| B110 — Operations | `110-OPERATIONS.md` | 1 (mostly Phase 10) |

A **Squad** typically runs 4 workers parallel: B10/B20 → B40/B50 → B60/B70 → B80/B90/B100. Different waves happen sequentially (B10 must commit before B40 reads the new schema).

A **Swarm** runs 8–12 workers across the same wave structure with finer-grained intra-bundle parallelism (B40's 5-step contract decomposes into 5 sub-agents per provider, etc.).

---

## Wave model

Phase 5 specifically has a wave structure because of inter-bundle dependencies:

```
Wave 1 (parallel):
  ┌── B10 Schema  ──> migrations + types
  └── B20 Constants/Env  ──> BUSINESS, STRIPE_API_VERSION, env.ts

Wave 2 (parallel; depends on Wave 1):
  ┌── B40 Webhooks  ──> handlers + canonical writer
  ├── B30 Checkout  ──> create-checkout routes + idempotency
  └── B50 Security  ──> validatePayPalUserId + cross-checks
                       (often paired with B40 worker)

Wave 3 (parallel; depends on Wave 2):
  ┌── B60 State/Lifecycle  ──> verify-as-write + paused_for_org + grace
  └── B80 Teams  ──> seat pricing + pause/resume intent

Wave 4 (parallel; depends on Wave 3):
  ┌── B70 Dunning  ──> ladders + manual retry + SCA
  ├── B90 Reliability  ──> reconciliation + cron + email failsafe
  └── B100 Analytics  ──> exclusions + MRR + fees + health

Wave 5 (sequential; after Wave 4):
  └── B110 Operations  ──> runbooks + secret custody + final drift-guards
```

Don't run Wave 2 before Wave 1 commits. Don't try to parallelize across waves — the artifacts won't compile.

---

## Coordination via Agent Mail

For Swarm and Squad tiers, use [MCP Agent Mail](../../../agent-mail/SKILL.md) to coordinate file edits.

```
# At session start, every worker:
ensure_project(project_key=<absolute project path>)
register_agent(project_key, program="claude-code", model="opus-4.7")

# Before editing a shared file:
file_reservation_paths(
  project_key, agent_name,
  paths=["src/db/schema.ts"],
  ttl_seconds=3600,
  exclusive=true,
  reason="b10-add-payment-events-table"
)
# (proceed with edit if granted; wait/skip if conflict)

# After committing:
release_file_reservations(project_key, agent_name, paths=["src/db/schema.ts"])
```

Files that almost always need reservation:
- `src/db/schema.ts` (or Prisma schema)
- `src/env.ts`
- `src/lib/constants/{business,stripe-config,routes,webhook-error-codes}.ts`
- `src/lib/analytics/exclusions.ts`
- `src/lib/webhooks/inbound.ts` (the canonical writer lives here; many bundles touch it)
- `src/app/api/{stripe,paypal}/webhook/route.ts`

Thread id convention: `billing-<run-id>-<phase>-<bundle>`. So if Run 7 has Phase 5 B40 work, the thread is `billing-7-5-B40`.

---

## Coordination via beads

For Swarm tier, drive Phase 5 from beads:

```bash
br create --title="B40-staleness: add last_event_at WHERE to PayPal handlers" \
          --type=task --priority=2
br dep add <child> <parent>   # if depends on another task
br ready                       # workers pick from here
br update <id> --status=in_progress
br close <id> --reason="Implemented + regression test bd-2vnz4__paypal_staleness.test.ts"
```

The beads CLI provides the dependency graph for `br ready` so workers don't claim blocked tasks. Use `bv --robot-triage` to surface the next batch.

---

## Multi-model triangulation

For Phase 7 in Swarm tier, fan out to Codex + Gemini in addition to Claude. See [TRIANGULATION.md](TRIANGULATION.md).

Key rule: triangulation is for *review*, not implementation. Implementation is single-author per bundle (continuity of context). Review benefits from independent reads.

---

## Context budget

Each subagent has its own context. The main agent's context is the bottleneck because it sees:
- The user's original request
- Phase 0 confirmations
- Phase summaries from each subagent (don't read the full per-bundle artifacts; read summaries)
- Decisions on mode + scope

Discipline:
- Subagents write artifacts to `.billing_workspace/`; main agent reads only the SUMMARY files (`phase1_index.md`, `phase2_summary.md`, etc.).
- Subagent prompts are self-contained — they don't depend on conversation context.
- When the main agent has to make a cross-phase decision, it reads the specific artifact it needs, not the whole workspace.

---

## Failure modes

- **Two workers edit the same file without reservation** → merge conflict; the slower worker's commit fails. Recovery: rebase or revert + re-do.
- **Worker drifts beyond bundle scope** → cross-cutting changes that should be Phase 6 leak into Phase 5. Recovery: `git revert` the out-of-scope commit; re-do in Phase 6.
- **Worker reads stale artifact** → coordination failure with another worker. Recovery: workers always start their session by reading the latest `phase*_summary.md`.
- **Triangulation disagreement papered over** → consensus rule violated. Recovery: re-run the disagreement explicitly; record the dissent and the decision.

---

## Tier escalation

If you start a Pair tier and discover the project is bigger than expected (e.g., dual-provider with team plans + reporting backend), escalate to Squad mid-run:

1. Pause the current bundle's worker.
2. Spawn additional workers for the remaining bundles.
3. Reset the wave plan based on what's already committed.
4. Resume.

Tier de-escalation is rare but possible: if a Swarm produces too much noise (many trivial findings, much triangulation overhead), drop to Squad with `multi-model-triangulation` deferred to the most-impactful bundles only.
