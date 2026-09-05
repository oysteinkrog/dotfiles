# CLOSER-DEFENSE.md — Give The Original Closer A Chance To Defend

<!-- TOC: Why give defense | The defense flow | What counts as valid defense | When to skip | Worked example | Anti-patterns -->

> Phase 9 normally creates remediation beads or reopens. But sometimes the audit is wrong: the closer had context the audit missed, or the audit's evidence-gather missed real implementation. Closer-defense is an optional Phase 8.5 that lets the original closer respond before remediation. Implements the `☍ DISCLAIMER-WINDOW` operator.

---

## Why give defense

The audit is *deterministic and citable*, but not *omniscient*. Real reasons a flagged bead might actually be done:

- The implementation lives in a sibling repo / monorepo package the audit doesn't see.
- The bead's spec was deliberately under-specified; the closer's intent matched the over-the-wire behavior, not the literal AC.
- The "theater" finding is a documented exception (e.g., `unimplemented!()` in a trait method that's intentionally never called).
- The test that "always passes" is a sanity check by design, with the real verification elsewhere.
- Coverage threshold isn't met because the bead's code path is exercised by an integration test the auditor didn't classify as relevant.

Without a defense window, every false-positive becomes either a wasted remediation bead OR an argumentative back-and-forth in the bead's comments.

---

## The defense flow

```
Phase 8 — scoring complete; bead flagged false-closed
   │
   ▼
Phase 8.5 — closer-defense (optional, configurable per audit)
   │
   ├── Notify the closer (via /agent-mail or human channel)
   ├── Wait <defense_window_hours> for response (default 24h)
   ├── Closer responds with evidence
   │   ├── Implementation cited (file:line) in another repo / package
   │   ├── Documentation explaining the deliberate choice
   │   ├── Adjacent test that does verify behavior
   │   └── Or: "I accept the audit; remediate"
   ├── Audit reviews defense
   │   ├── Defense valid → upgrade dimension scores; bead may exit false-closed list
   │   └── Defense invalid OR no response → proceed to Phase 9 normally
   │
   ▼
Phase 9 — remediation (only for beads where defense was inconclusive)
```

---

## What counts as a valid defense

The defense is **not an opportunity to negotiate the rubric**. It's an opportunity to surface evidence the audit missed.

| Defense type | Example | Valid? |
|--------------|---------|:------:|
| Cite implementation in a sibling repo | "The validator lives in /dp/validator-utils, not this repo" | ✓ if file:line confirmed |
| Cite a non-obvious test that exercises the behavior | "tests/integration/foo.rs:128 covers this via the chain" | ✓ if test runs and asserts |
| Document an explicit exception | "This `unimplemented!()` is in a trait method we never call; see ADR-007" | ✓ if ADR exists and rationale is plausible |
| Argue the rubric is too strict | "80% coverage is excessive; we only need 60%" | ✗ — change the rubric, don't argue per bead |
| Claim the audit misread the bead | "I never said no mocks" | ✓ ONLY if bead body literally doesn't say no mocks; otherwise the audit's literal reading wins |
| Promise to fix later | "I'll address this next sprint" | ✗ — that's what completion-debt beads are for |
| Push back on severity classification | "This `assert true` was placeholder during dev; not actually theater" | ✗ unless there's a follow-up commit removing it |

The defense reviewer (a fresh subagent) applies these criteria mechanically.

---

## When to skip closer-defense

| Scenario | Skip defense? |
|----------|:-------------:|
| Tripwire mode (autonomous) | ✓ Skip — no human in the loop |
| Closer is no longer active (left the team / agent retired) | ✓ Skip |
| `closed_by_session` is empty | ✓ Skip |
| Severity is severe (score < 250) | ✗ Run defense — even if score is bad, surface the closer's input first |
| Single-bead deep-dive | ✗ Run defense |
| Onboarding mode (lots of false-closed expected) | ✓ Skip — too much volume to wait on each |
| `mode == comprehensive` | ✗ Run defense |

Configure via `manifest.json#closer_defense_enabled: true|false`.

---

## Defense window mechanics

```bash
# In Phase 8.5, for each false-closed bead:
CLOSED_BY=$(jq -r '.closed_by_session // empty' "$BEAD_DIR/show.json")
[ -n "$CLOSED_BY" ] || continue   # Skip if no closer recorded

# Send notification (via /agent-mail if available)
mcp__mcp-agent-mail__send_message \
  --thread_id "audit-defense-${BEAD_ID}-${PASS_ID}" \
  --subject "[audit-defense] ${BEAD_ID} flagged false-closed; you can respond" \
  --body "$(cat <<EOF
Bead ${BEAD_ID} ("$BEAD_TITLE") was flagged false-closed by the audit pass ${PASS_ID}.

Score: ${SCORE}/1000 (threshold ${THRESHOLD})
Verdict: ${VERDICT}

Missing items:
${MISSING_ITEMS}

You have ${DEFENSE_WINDOW_HOURS}h to respond before Phase 9 remediation runs.

To respond:
1. Reply in this thread with your evidence (file:line citations preferred).
2. OR run: ~/.claude/skills/.../scripts/closer-respond.sh ${BEAD_ID} <evidence-file>
3. OR remain silent → audit proceeds with Phase 9 as normal.
EOF
)" \
  --ack_required true

# Wait
DEFENSE_DEADLINE=$(date -d "+${DEFENSE_WINDOW_HOURS} hours" +%s)
while [ "$(date +%s)" -lt "$DEFENSE_DEADLINE" ]; do
  RESPONSE=$(check_for_defense_response "$BEAD_ID")
  if [ -n "$RESPONSE" ]; then break; fi
  sleep 300  # poll every 5 min
done

# Process response. Defense processing is LLM-driven — no deterministic
# `process-defense.py` exists because the acceptance judgment is contextual.
# Invoke the closer-defender subagent (subagents/closer-defender.md) via
# your orchestrator's Task tool with $BEAD_DIR + $RESPONSE as inputs.
# The subagent reads closer_response.md, applies the acceptance criteria,
# writes defense.json next to the evidence pack, and updates scorecard.md
# in place if the defense moved the score. Then re-run the deterministic
# scorer against the updated evidence:
if [ -n "$RESPONSE" ]; then
  echo "→ invoke subagents/closer-defender.md with bead_dir=$BEAD_DIR response=$RESPONSE" >&2
  # After the subagent has updated the bead's evidence pack:
  python3 ~/.claude/skills/.../scripts/score-bead.py "$BEAD_DIR" \
    --rubric "$AUDIT_DIR/rubric.md" \
    --synthesis "$PASS_DIR/synthesis.md"
fi
```

If the defense is valid, the bead's evidence pack gets a new file. **The
`audit_verdict_change` schema MUST use one numbered key per dimension being
overridden** — `scripts/score-bead.py` reads keys of the form
`dimension_<N>_new` (or `_score`, `_override`, `_post_defense`) and ignores
single-dimension `{dimension, new_score}` payloads. To override more than one
dimension, list each as its own key. Acceptable per-dimension keys (consumed
by `scripts/score-bead.py::defense_dimension_overrides`):

| Numbered key | Maps to dimension |
|--------------|-------------------|
| `dimension_1_new` | implementation completeness |
| `dimension_2_new` | required tests |
| `dimension_3_new` | anti-theater |
| `dimension_4_new` | test depth |
| `dimension_5_new` | docs / migrations / telemetry |
| `dimension_6_new` | cross-bead integration |

You can equivalently use a top-level `dimensions: {…}` object whose keys are
dimension names (e.g. `implementation`, `tests`, `docs`, `integration`) — the
scorer's alias map accepts both styles. The canonical defense.json:

```
passes/<UTC>/beads/<BEAD_ID>/defense.json
{
  "defended_at": "2026-05-06T16:00:00Z",
  "defended_by": "<closed_by_session>",
  "defense_type": "cited_implementation_in_sibling_repo",
  "defense_verdict": "ACCEPTED",
  "evidence": [
    {"path": "/dp/validator-utils/src/validator.rs", "line_start": 1, "line_end": 50,
     "commit_sha": "def5678", "via": "closer-defense response"}
  ],
  "audit_verdict_change": {
    "dimension_1_old": 0,
    "dimension_1_new": 240,
    "total_old": 287,
    "total_new": 527,
    "reason": "Implementation found in sibling repo as defended; coverage scope unchanged"
  }
}
```

The scorer applies overrides only when `defense_verdict` (or `verdict`) is
`ACCEPTED` or `PARTIAL`. The scorecard is regenerated; if the new total ≥
threshold, the bead exits the false-closed list.

---

## What if the closer disagrees with the defense reviewer?

If the closer's defense is rejected (invalid type per the criteria above), the closer can:

1. Accept the verdict (silent → Phase 9 proceeds).
2. Escalate to a human for adjudication (creates a manual review bead).

The audit doesn't endlessly negotiate. After one round of defense + one optional escalation, the verdict stands.

---

## Worked example

**Audit pass.** `bd-validator-impl` scored 287/1000. Theater finding: `src/validator.rs:8` returns `Ok(Default::default())`. Verdict: 🔴 False-closed (severe).

**Defense window opens.** The closer (session `2026-04-15-claude-code-abc`) receives notification.

**Defense response (12 hours later):**

```
Bead bd-validator-impl was completed via /dp/validator-rust crate, which this project
imports as a workspace dependency. The `validator.rs` file in THIS repo is a thin
wrapper that delegates to the real impl at:
  /dp/validator-rust/src/lib.rs:42-180

The "Ok(Default::default())" line is the wrapper's pass-through for the trivial case
(empty input → Default trait value), per the bead's AC bullet "validator handles empty
input gracefully".

Tests at /dp/validator-rust/tests/integration/full_suite.rs cover the full
behavior (the spec extractor missed the workspace dependency).

Evidence files:
- /dp/validator-rust/src/lib.rs:42-180
- /dp/validator-rust/tests/integration/full_suite.rs:1-300
```

**Defense reviewer evaluates.** Both files exist; `cargo test --package validator-rust full_suite` runs and passes; the AC bullet "handles empty input gracefully" matches the wrapper's behavior.

Verdict: defense valid (type: `cited_implementation_in_sibling_repo`). Re-score:

- Dimension 1: 240/300 (was 0; impl found via defense)
- Dimension 2: 200/250 (was 100; defense-cited tests count)
- Dimension 3: 100/150 (was 50; the trivial pass-through isn't theater given context)
- Other dimensions unchanged.
- New total: 740/1000 → 🟡 Partial (above threshold, no longer false-closed)

The defense.json is committed; the scorecard is updated; the bead exits the false-closed list. No remediation bead is created.

`remediation.md` notes:
```
| Original | Score | Action | Notes |
|----------|------:|--------|-------|
| `bd-validator-impl` | 287 → 740 | Defended successfully | Cited /dp/validator-rust workspace dep |
```

---

## Anti-patterns

| Don't | Why |
|-------|-----|
| Use defense to argue rubric strictness | Change the rubric instead |
| Accept "I'll fix it later" as defense | That's a remediation bead, not a defense |
| Re-open defense window after deadline expires | Defense is a one-shot; closer had their window |
| Auto-accept defense without review | The defense reviewer applies the criteria mechanically |
| Skip defense in tripwire mode but apply it in standard | Be consistent; either always or never (per project) |
| Escalate every rejected defense to human | Most rejections are clear; only ambiguous ones escalate |

---

## Configuration

```yaml
# rubric.md frontmatter
closer_defense:
  enabled: true              # default false
  window_hours: 24           # default 24
  notify_via: agent-mail     # or: slack, email, none
  auto_accept_types:         # types automatically accepted without reviewer
    - cited_implementation_in_sibling_repo
  manual_review_types:       # types that always require human adjudication
    - rubric_dispute
```

---

## Cost / time impact

Closer-defense adds 24h+ wall time to Phase 9 (during the defense window). For projects where this is unacceptable:

- Use `mode=tripwire` (skips defense).
- Use `closer_defense.window_hours: 1` for fast turnaround.
- Run defense in parallel with the next pass's Phase 1 — the next inventory doesn't depend on the defense outcome.

---

## When closer-defense materially improves the audit

Empirically, closer-defense reduces false-positive false-closed by ~5-15%. Most defenses are rejected (the audit's literal reading is usually correct), but the 1-in-10 valid defenses build trust and surface real audit gaps that lead to better evidence-gather logic in future passes.

For projects with strong written-down conventions (AGENTS.md, ADRs, sibling-skill integrations), defenses are higher value because the closers have explicit context to cite. For projects without such conventions, defenses are mostly noise.