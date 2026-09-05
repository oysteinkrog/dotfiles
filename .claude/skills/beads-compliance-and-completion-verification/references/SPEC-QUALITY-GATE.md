# SPEC-QUALITY-GATE.md — Catch the upstream cause of false-closed beads

A 0-1000 audit score, after the fact, is a downstream measurement. The upstream cause of most false-closed beads is the *spec itself* being unauditable: vague ACs, missing test types, no rollback plan, no numeric budget. A bead like that cannot close cleanly even by an honest implementer — there's no shared definition of "done" to verify against.

The spec quality gate moves friction earlier (cheap) so the audit's job (expensive) is mostly self-fulfilling.

---

## What the gate is

A pre-claim hook that scores a bead's spec on a 0-1000 dimension parallel to the audit rubric, then EITHER advises (default) OR blocks claim until the spec is rewritten.

- **Tool:** `scripts/spec-quality-gate.sh <project-path> <bead-id> [--policy advise|block]`
- **Subagent:** `subagents/spec-quality-reviewer.md` for deeper LLM-driven review (the script is the deterministic baseline).
- **Output:** a markdown report scoring 6 dimensions; verdict EXCELLENT / GOOD ENOUGH / REWRITE BEFORE CLAIM / REJECTED.

---

## When to run it

| Situation | Mode |
|---|---|
| Agent is about to `br update <id> --status in_progress` | `--policy advise` (don't break velocity) |
| Pre-implementation gate on a P0/critical-path bead | `--policy block` |
| Bulk audit of an existing backlog | `--policy advise --write` (writes per-bead reports for later review) |
| New project onboarding (audit doesn't exist yet) | Run on the entire `status:open` backlog to surface authoring patterns |
| After a false-closed bead is reopened | Re-score the spec; the original spec was probably the root cause |

---

## The 6 dimensions (rubric mirror)

| # | Dimension | Max | Heuristic |
|---|-----------|----:|-----------|
| 1 | ACs are concrete | 300 | Count testable ACs; subtract for vague qualifiers (robust, performant, secure) |
| 2 | Test types named | 200 | Search for: unit / e2e / property / metamorphic / fuzz / golden / conformance |
| 3 | Numeric budgets where applicable | 100 | Perf-flavored beads must have `[<>≤≥] N (ms\|MB\|req/s\|...)` |
| 4 | Rollback plan stated | 100 | Migration / deploy beads must answer "what undoes this?" |
| 5 | Dependencies explicit | 100 | Penalize implicit "uses the new auth helper from bd-bar" without `br dep add` |
| 6 | Implementer can recognize "done" | 200 | Heuristics: "Done when …", file:line citations, ≥ 3 ACs |

Default threshold: **700** (matches audit threshold for symmetry).

The script applies these heuristically; the subagent applies LLM judgment on top.

---

## Output sample

```
# Spec Quality Report — `bd-billing-webhook` (feature)

**Title:** Verify Stripe webhook signatures
**Score:** 510 / 1000
**Threshold:** 700
**Verdict:** REWRITE BEFORE CLAIM

| Dimension | Score | Max | Notes |
|-----------|------:|----:|-------|
| ACs concrete | 60 | 300 | 1 of 1 ACs are testable; 3 vague word(s) detected: {robust, properly} |
| Test types named | 100 | 200 | named: unit |
| Numeric budgets | 100 | 100 | not perf-flavored; rule N/A |
| Rollback plan | 0 | 100 | no rollback plan stated |
| Dependencies explicit | 80 | 100 | 1 implicit dep phrase(s); ensure `br dep add` records them |
| Done recognizable | 50 | 200 | 1/4 'done'-clarity heuristics matched |

## Strongest revisions to demand

- Replace vague qualifiers (robust / performant / secure) with measurable assertions.
- Name the required test types explicitly (unit / e2e / property / fuzz / golden / metamorphic / conformance).
- Add a rollback / recovery plan section.
- Promote implicit deps to explicit `br dep add` entries.

GATE: BLOCKED (510 < 700; --policy=block)
```

---

## Wiring into pre-claim flow

### Local (recommended)

Add to `assets/pre-commit-hook.sh` extension OR a separate `pre-claim.sh` invoked from agent orchestration. The cheapest wiring is a shell alias on `br update`:

```bash
# in your shell rc:
br_claim() {
  if [ "$2" = "--status" ] && [ "$3" = "in_progress" ]; then
    .claude/skills/beads-compliance-and-completion-verification/scripts/spec-quality-gate.sh \
      "$(git rev-parse --show-toplevel)" "$1" --policy advise || true
  fi
  br "$@"
}
```

Make it `--policy block` instead of `advise` if you want hard gating.

### Multi-agent swarm

In an `ntm` / agent-mail flow, the orchestrator that hands a bead to a worker should call the gate first. Failed gate → rewrite (or hand to a `bead-author-feedback` agent first).

---

## Tuning the rubric

The 6 dimensions and their weights are defaults. Override per-project in `audit-policy.yaml`:

```yaml
spec_gate_rubric:
  threshold: 800            # stricter than default
  weights:
    acs_concrete: 350       # we care a LOT about AC quality
    test_types: 150
    numeric_budgets: 100
    rollback: 100
    deps_explicit: 100
    done_recognizable: 200
```

---

## What this gate does NOT do

- It does **not** block the agent from CLOSING a bead. That's the audit's job. The gate is pre-CLAIM.
- It does **not** judge the implementation; the spec text is all it sees.
- It is **not** a substitute for human review on novel/risky beads. Treat it as a sanity-check, not a stamp of approval.

---

## Why this matters (worked example)

A bead whose AC reads "Webhook handling works robustly" is *unauditable*. No matter how the implementer writes the code, the audit cannot judge "robust" — the rubric will dock points for vague qualifiers, the implementer will protest, and the false-closed bead becomes contentious. With the gate:

- Pre-claim score: 510 (vague AC + missing test types).
- Author rewrites: "Webhook receives `signature` header, verifies HMAC-SHA256 with `STRIPE_WEBHOOK_SECRET`, returns 400 on mismatch. Tests: unit (HMAC mismatch → 400), e2e (Stripe CLI replay → 200)."
- Re-scored: 870. Author claims with confidence.
- After implementation: audit scores 950 (the spec made the work easy to verify).

Net cost: 5 minutes of pre-claim revision saved a 2-week false-closed dispute later.
