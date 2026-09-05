# DEADLOCK-PATTERNS-MULTI-PANE.md — Inter-Pane Deadlocks Specific to Brennerbot

<!-- TOC: Why this matters | DL-1 mail-deadlock | DL-2 file-reservation deadlock | DL-3 bead-dep deadlock | DL-4 phase-gate deadlock | DL-5 adjudicator-rotation deadlock | DL-6 corpus-pin deadlock | DL-7 quota-staircase | DL-8 distillation chicken-and-egg | DL-9 audit-trio impossible | DL-10 cross-session lock | Detection signals | Recovery hierarchy | Prevention | Composition with /deadlock-finder-and-fixer -->

Per `/deadlock-finder-and-fixer`. Multi-pane brennerbot sessions can wedge into deadlocks that don't exist in single-pane work. The 5-role roster + Agent Mail + beads + Phase gates create cycles invisible from any single pane's perspective. This file catalogs the patterns and recovery procedures.

For T3+ sessions, walk through DL-1 through DL-5 mentally before bootstrap. For T4+, all 10.

---

## Why this matters

A deadlock burns wall-time without progress. In a Squad session, 3 panes blocked on each other's outputs while the operator's clock ticks toward T3's 5h budget — a 30-min deadlock alone is 10% of the budget. Worse: deadlocks often look like "the swarm is making progress" because individual panes have full pane-tail buffers (just not advancing artifacts).

Per LIVENESS-TRUTH-STACK in SKILL.md, advancing pane chatter ≠ advancing artifacts. Most deadlocks are detected via Layer 3 (`git log` showing no artifact landings).

---

## DL-1: Mail-deadlock (cyclic ack-required)

**Setup:** p1 sends p2 a `ack_required:true` message. p2's reply also has `ack_required:true`. p1 must ack p2's reply before reading new messages. p1 is busy investigating; p2 is waiting for p1 to respond. Both are "in progress" but blocked.

**Detection:**

```text
# Use the MCP Agent Mail `fetch_inbox` tool:
fetch_inbox(project_key="<workspace>", agent_name="<agent-mail-name-for-p1>", include_bodies=true)
fetch_inbox(project_key="<workspace>", agent_name="<agent-mail-name-for-p2>", include_bodies=true)
# Inspect returned messages where ack_required=true; both panes show pending messages from each other.
```

**Recovery:**
1. Operator force-acks one message: `acknowledge_message <project> <agent-mail-name-for-p1> <msg-id>`
2. Resume the loop
3. File anomaly: chains of >2 ack_required:true between same panes

**Prevention:** OC-031 (per OPERATOR-CARDS.md): Agent Mail conventions explicitly limit ack-chains to depth 1.

---

## DL-2: File-reservation deadlock

**Setup:** p1 reserves `corpus/ingested/S-001/**` exclusively. p2 needs to add a quote excerpt to the same source. p1 is held up waiting for p2's investigation. Classic cycle.

**Detection:**

```text
# Use Agent Mail reservations as the source of truth:
file_reservation_paths(
  project_key="<workspace>",
  agent_name="<operator-agent-mail-name>",
  paths=["corpus/ingested/S-001/**"],
  ttl_seconds=3600,
  exclusive=true,
  reason="deadlock-probe"
)
# If the response has `conflicts`, group those holders by agent_name.
```

**Recovery:**
1. `force_release_file_reservation <project> <agent_holding_old_reservation>`
2. Re-engage with non-exclusive reservation if possible
3. Document in `phase0_scope_decision.md § file-reservation-events`

**Prevention:** Use `exclusive:false` for read access; only writers reserve exclusively. Per AGENT-MAIL-CONVENTIONS.md.

---

## DL-3: Bead-dep deadlock

**Setup:** H-001 dep H-002 (per `br dep add`). H-002 dep H-001. `br ready` for either returns "blocked." Panes can't advance.

**Detection:**

```bash
bv --robot-insights --workspace=. | jq '.Cycles'
# → returns ≥1 cycle if present
```

**Recovery:**
1. `bv --robot-insights | jq '.Cycles[]'` to identify the cycle
2. Operator decides which dep to break, resolves public refs to actual IDs, then runs `br dep remove "$h1_id" "$h2_id"`
3. File DL-3 anomaly with reasoning

**Prevention:** Dependencies should reflect *causal/logical* relationships, not coincidental cross-references. Operator reviews `bv --robot-insights` at every Phase 3 → Phase 4 transition.

---

## DL-4: Phase-gate deadlock

**Setup:** Phase 4 requires kill_rate ≥ add_rate to exit. But the swarm only files supporting EVs (F-403 confirmation bias). add_rate increases each round; kill_rate stays 0. Phase 4 never exits → Phase 5 never entered → adjudicator never closes Hs → Phase 4 has no kill mechanism. Cycle.

**Detection:**

```bash
./scripts/convergence-check.sh --phase=4
# Reports kill_rate=0, add_rate=N for ≥2 rounds
```

**Recovery:** OC-011 escalation (per OPERATOR-CARDS.md):
1. Run `subagents/falsifier-grader.md` on all active Hs
2. If grade Poor → return to Phase 1 framing (the question may be unfalsifiable)
3. Else dispatch `MO-mode-flip-investigator-to-advocate.md` to flip ≥1 Investigator
4. Run a `MO-quickie-pilot.md` round to surface counter-evidence cheaply
5. After 1 more round, if still kill=0: hard-stop Phase 4; check Hs are unfalsifiable

**Prevention:** Phase 1 falsifier discipline. Per MO-01-frame-question.md, refuse to advance until each H has an observable falsifier.

---

## DL-5: Adjudicator-rotation deadlock

**Setup:** Per OC-015, the Adjudicator must NOT be a champion of the H pair AND must NOT be the previous adjudicator. With 5 panes (Squad), 2 are champions and 1 was previous adjudicator → 2 panes left. If both are unavailable (rate-limited / saturated), no valid adjudicator.

**Detection:**

```bash
./scripts/check-rotation-rules.sh
# Reports F-501-class violation OR insufficient eligible panes
```

**Recovery:**
1. **Wait recovery** (preferred): wait 5-10 min for one pane to free up; rotate-then-adjudicate
2. **Family-relax** (acceptable): allow same-family adjudicator if no cross-family options exist; document in `phase0_scope_decision.md § triangulation_degraded`
3. **Pane-respawn**: add a fresh pane (per `MO-pane-respawn.md`; e.g. `ntm add <session> --gmi=1`) and use it as adjudicator

**Prevention:** Squad+ rosters with ≥4 distinct families. For T4+ sessions where rotation rules are most critical, plan with surplus capacity.

---

## DL-6: Corpus-pin deadlock

**Setup:** Pane needs to verify a quote in S-001, but S-001 hasn't been ingested with content-hash yet. Verification requires hash. Hash requires ingestion. Ingestion requires the hashing process. (Trivial chain, but real when scripted.)

**Detection:** EV bead with `verified:false; reason:source-not-yet-pinned`. Verification-log lists S-001 as "pin-pending."

**Recovery:**
1. Run `MO-corpus-curate.md` on S-001 explicitly
2. Hash + add to corpus_index.md
3. Then re-verify EV (per MO-evidence-verify.md)

**Prevention:** During Phase 1 corpus-pin, use the script `corpus-curator.md` subagent to ingest all sources upfront before Phase 4 starts.

---

## DL-7: Quota staircase

**Setup:** All 3 cc panes hit their daily Claude quota at staggered times: pane 1 at hour 4, pane 2 at hour 5, pane 3 at hour 6. Operator rotates each via /caam, but the rotation accounts also exhaust by hour 7. Session degrades to 2 panes, then 1, then halts.

**Detection:**

```bash
ntm --robot-attention --attention-session=brennerbot-X --attention-cursor=<cursor>
ntm --robot-health-oauth=brennerbot-X | jq '.panes[]? | select(.rate_limited==true)'
caam ls --provider=claude --json | jq '[.[] | select(.daily_remaining < 0.1)] | length'
# Multiple accounts approaching exhaustion
```

**Recovery:**
1. Per OC-002 (`/vibing-with-ntm`): rotate all rate-limited panes
2. If quota fleet is empty: `MO-emergency-stop.md` → checkpoint + resume tomorrow
3. Document in scope_decision: "session paused due to quota staircase; resume X"

**Prevention:** Pre-flight (per FIRST-90-SECONDS.md seconds 45-75): caam quota check. If <30% remaining for any required family, defer the session.

---

## DL-8: Distillation chicken-and-egg

**Setup:** Phase 6b meta-synthesis requires per-family distillations (6a). 6a requires the synthesizer pane. The synthesizer is currently the adjudicator (rotating role). The adjudicator is in the middle of Phase 5 closure work. Phase 5 needs the synthesizer to finish — but the synthesizer can't start synthesizing until Phase 5 closes. Loop.

**Detection:** Phase 5 has been "almost done" for >30 min while Phase 6 is "waiting on Phase 5".

**Recovery:**
1. Identify the actual blocker: which pane is doing what right now?
2. If the role-overlap is the issue: spawn a fresh pane for synthesis OR have the rotating-adjudicator finish Phase 5 in batch first, then start 6a
3. Apply `MO-domain-handoff.md` to formally transfer the synthesizer role

**Prevention:** Squad+ rosters with role separation: synthesizer is a *different* pane from adjudicator. The rotating-adjudicator pattern is for SMALL rosters where role-collision is unavoidable.

---

## DL-9: Audit-trio impossible

**Setup:** Phase 7 trio audit needs 3 panes from cross-family rosters NOT including the synthesizers. Squad has 5 panes total; 2 are synthesizers; 1 is in mail-deadlock with another. Only 2 eligible panes left → can't form a trio.

**Detection:**

```bash
./scripts/triangulation-coverage.sh
# Reports insufficient cross-family audit candidates
```

**Recovery:**
1. Resolve the upstream deadlock (per DL-1 if mail; DL-3 if bead) first
2. If genuinely impossible: degrade to 2-pane audit with explicit caveat in HANDBACK
3. For T4+: the audit must be 3-pane; spawn fresh panes if needed

**Prevention:** Squad+ rosters with ≥6 panes for T4+ specifically to handle audit-trio robustness.

---

## DL-10: Cross-session lock

**Setup:** Two concurrent brennerbot sessions in adjacent workspaces both `git push` to the same remote. One has stale RESUME.md hashes. The push fails. Operators try to merge. Beads jsonl has merge conflicts. Sessions blocked on git.

**Detection:** `git push` failures; jsonl merge conflicts.

**Recovery:**
1. Don't auto-merge beads (data corruption risk)
2. Follow `/fixing-beads-problems` recovery steps
3. Per AGENTS.md: leave concurrent agents' working-tree changes alone until coordinated

**Prevention:** OC-Cost-1 (per COST-AWARE-EXECUTION.md) pre-flight: don't run two sessions in adjacent workspaces against the same remote. Use distinct branches per session.

---

## Detection signals (rapid scan)

For tick-time detection of any deadlock above:

```bash
# Run this every 15-30 min as part of tick.sh:
./scripts/tick.sh ~/brennerbot_sessions/<session>
# tick.sh aggregates:
#   - liveness-check.sh (Layer 1-4 of LIVENESS-TRUTH-STACK)
#   - git log artifact-landing rate (no artifacts in 30+ min = warning)
#   - bead-state-change rate (no state changes in 30+ min = warning)
#   - mail ack-pending depth (>2 = DL-1 candidate)
#   - file-reservation conflicts (>0 = DL-2 candidate)
#   - bv --robot-insights cycles (≥1 = DL-3)
#   - convergence-check kill_rate (=0 for ≥2 rounds = DL-4 candidate)
```

If any signal fires, resolve via the corresponding DL-N recovery.

---

## Recovery hierarchy

Apply recoveries in order:

1. **Wait briefly** (5-10 min) — sometimes the deadlock self-resolves as a pane finishes async work
2. **Identify which DL pattern** — match symptom to DL-1..DL-10
3. **Apply pattern-specific recovery** (per above)
4. **If recovery fails**: emergency-stop session (per `MO-emergency-stop.md`); diagnose offline; resume after fix
5. **Document in `phase0_scope_decision.md § deadlock_events`** — for cross-session learning

Don't try multiple recoveries in parallel — deadlock-on-deadlock is real.

---

## Prevention discipline

Phase-by-phase prevention:

| Phase | Most common DL | Prevention |
|-------|----------------|------------|
| 2 (bootstrap) | DL-7 quota staircase | Pre-flight caam quota check |
| 3 (hypotheses) | DL-3 bead-dep cycle | bv --robot-insights at Phase 3 → 4 transition |
| 4 (investigation) | DL-4 phase-gate | Falsifier discipline at Phase 1 |
| 4 | DL-2 file-reservation | Use exclusive:false for reads |
| 4 | DL-6 corpus-pin | Pre-pin all sources at Phase 1 |
| 5 (debate) | DL-5 adjudicator-rotation | ≥4 distinct families in roster |
| 5 | DL-1 mail-deadlock | Limit ack-chain depth to 1 |
| 6 (distillation) | DL-8 chicken-and-egg | Distinct synthesizer panes |
| 7 (audit) | DL-9 trio impossible | Squad+ ≥6 panes for T4+ |
| any | DL-10 cross-session | Distinct branches per session |

---

## Composition with /deadlock-finder-and-fixer

For deadlocks at the *system* level (process hangs, await-holding-lock, DB locks, LD_PRELOAD init), defer to `/deadlock-finder-and-fixer`. The DL-1..DL-10 above are *coordination* deadlocks specific to brennerbot's roster + protocols. The two are complementary:

- **Coordination deadlock** (this file's DL-N): solved by re-coordinating panes/MOs/beads
- **System deadlock** (`/deadlock-finder-and-fixer`): solved by debugging actual process state, lock acquisition, etc.

A symptom of "the swarm is hung" usually maps to one of these two. If neither pattern matches, escalate to /vibing-with-ntm OC-026 (pid audit) for true process-level diagnosis.

---

## Cross-references

- [SKILL.md Liveness Truth Stack](../SKILL.md) — detection layer breakdown
- [scripts/tick.sh](../scripts/tick.sh) — aggregator that catches multi-pattern signals
- [scripts/check-rotation-rules.sh](../scripts/check-rotation-rules.sh) — DL-5 detection
- [scripts/triangulation-coverage.sh](../scripts/triangulation-coverage.sh) — DL-9 detection
- [/beads-bv](../../beads-bv/SKILL.md) — DL-3 cycle detection via graph analysis
- [/vibing-with-ntm](../../vibing-with-ntm/SKILL.md) operator cards OC-001..031 — most pattern recoveries
- [/deadlock-finder-and-fixer](../../deadlock-finder-and-fixer/SKILL.md) — system-level deadlocks
- [/fixing-beads-problems](../../fixing-beads-problems/SKILL.md) — DL-10 jsonl merge recovery
- [STRESS-TEST-SCENARIOS.md](STRESS-TEST-SCENARIOS.md) — broader resilience scenarios
- [POST-MORTEM-FORMALIZATION-PLAYBOOK.md](POST-MORTEM-FORMALIZATION-PLAYBOOK.md) — when DL-N happens, document it
