# AGENT-ATTRIBUTION.md — Who closed which beads, and what does that pattern teach us?

> **Premise:** every bead close is a *signed claim* by some agent (human or AI) at some time. The audit's job is to verify the claim. The attribution layer's job is to read the *aggregate* of claims — across many beads, by the same agent, over time — and surface patterns that single-bead audit can't see.

This is not about blame. It's about feedback: which agents close beads that audit well? Which agents reliably leave debt? Which patterns predict false-closed?

---

## Data model

Every bead's `closed_by` field records the agent. For ai-driven flows this is typically a CLI fingerprint (`claude-code:opus-4-7-1m@session-abc`); for humans it's the git committer.

The audit captures, per pass:

```json
// passes/<UTC>/attribution.json
{
  "computed_at": "2026-05-06T14:00:00Z",
  "agents": [
    {
      "id": "claude-code:opus-4-7-1m",
      "closes_total": 67,
      "closes_passing": 58,
      "closes_false_closed": 9,
      "false_closed_rate": 0.134,
      "median_score": 880,
      "p10_score": 510,
      "stuck_beads_authored": 3,
      "patterns": [
        {"name": "P-sleep-as-fake", "count": 4},
        {"name": "P-test-skip-resurrected", "count": 1}
      ]
    },
    {"id": "alice@example.com", "closes_total": 15, "closes_false_closed": 0, ...}
  ]
}
```

`scripts/synthesize.py` writes this as a side-output during Phase 7. `master-report.py` summarizes the top 5 by close volume in `REPORT.md`.

---

## Per-agent dashboards

`scripts/dashboard.py` extends with an Attribution tab:

- **Close volume timeline** (per agent, per week)
- **Score distribution** (per agent, violin plot)
- **False-closed rate trend** (per agent, line chart with 95% CI)
- **Pattern fingerprint** (which theater patterns this agent triggers most)
- **Stuck-bead authorship** (how many beads this agent left in `stuck` state)

---

## How to use the patterns (constructive)

### Calibrate prior penalties

Per `references/REMEDIATION-PRIORITIZATION.md`, when CASS mining identifies a "sloppy session" — many false-closed beads in a short window — every bead by that session gets a -25 prior penalty. Attribution makes this systematic: the rolling false-closed rate per agent IS the prior.

```yaml
# audit-policy.yaml
attribution:
  prior_penalty_threshold: 0.10        # > 10% false-closed rate triggers prior penalty
  prior_penalty_amount: -25            # subtract from each bead's expected score
  prior_window_days: 30                # rolling window
  reset_after_clean_passes: 3          # earn the prior back
```

### Targeted feedback

For agents with elevated false-closed rates, the orchestrator can route their next claim to `subagents/spec-quality-reviewer.md` first — slower but catches the upstream cause.

### Coaching loops

Pair `subagents/audit-self-explainer.md` with `dev-onboarding` audience to produce a per-agent coaching artifact: "in your last 30 closes, the recurring patterns are X, Y, Z; here's the rubric section that catches each."

This is especially powerful for AI agents — they can update their session-memory or `CLAUDE.md` based on the coaching output and improve immediately.

---

## Honest framing

Attribution is feedback, not blame. Several caveats:

- **Selection effects.** If alice always claims the hardest beads, her false-closed rate will look worse than bob's even if she's the better engineer.
- **Bead-type mix.** Migration beads false-close more often than docs beads regardless of who closes them. Normalize by bead-type before comparing agents.
- **Rubric drift.** A higher false-closed rate today than 6 months ago might mean the rubric tightened (good thing).
- **Co-authorship is real.** Many beads are closed by one agent after another did the implementation. The `closed_by` field is partial signal.

The dashboard surfaces **rates with 95% confidence intervals**, not raw counts, to keep attribution honest.

---

## Anti-patterns

- **Public per-agent leaderboards.** Demoralizes. Use this data privately for coaching.
- **Tying to compensation.** Audit becomes adversarial; bead specs degrade as agents game the rubric.
- **Single-pass judgments.** A bead with a 9% false-closed rate over 3 passes is signal; over 1 pass is noise.
- **Comparing agents across projects without normalization.** A high-debt project will make every agent look worse.

---

## Cross-skill composition

- `/cass` — verbatim quote anchors per agent (the "vibe" backing the rate).
- `/agent-mail` — agent identity registry; ties closure events to identities.
- `/agent-fungibility-philosophy` — the framing question: do we want fungible agents (no specialization, lower variance) OR specialist agents (higher variance, higher peak)?
- `subagents/trauma-guard.md` — already cross-pass repeat-mistake detection by agent; extend its trauma report with attribution rates.

---

## Operator pairing

`⌗ ATTRIBUTION` (added in this expansion) — name the closer, stratify the rate, calibrate the prior. Pairs with `⌖ TARGET` (which agent's next claim should we gate?) and `↻ RETRY` (a high-rate agent's reopen attempt should auto-route to spec-quality-gate).
