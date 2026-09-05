# MO-anomaly-quarantine.md — Quarantine an Anomaly Without Patching the Theory

**Phase:** 4 (per-round) or 7 (audit)
**Operators activated:** ΔE Exception-Quarantine, ⊘ Level-Split
**Parameters:** `<ANOMALY_BEAD_ID>` (or candidate description), `<RELATED_H_IDS>`, `<SESSION_ID>`

---

Per Brenner §110: when evidence surfaces that doesn't fit the main theory but isn't strong enough to refute it either, the temptation is to **patch the theory** (add an exception, special-case the regime). Brenner's discipline says: **don't patch — quarantine**.

This MO formalizes the quarantine procedure.

---

**Step 1 — Identify the anomaly.**

An anomaly is evidence that:
- Doesn't fit the main hypothesis under standard interpretation
- Isn't strong enough to fire the H's falsifier
- Recurs (≥2 occurrences) or has high stakes (one occurrence in critical path)
- Doesn't reduce to a known F-### code (it's surprising, not just a methodology violation)

If only seen once and low-stakes, defer (file as low-priority `anomaly` bead with `wait-for-recurrence: true`).

**Step 2 — File the anomaly bead.**

```bash
an_ref="AN-NNN"  # public ref; replace NNN before running
an_id="$(br create "$an_ref: <one-line description>" \
  --type=task --labels=anomaly --priority=2 \
  --slug="$an_ref" --external-ref="$an_ref" --silent \
  --description="$(cat <<'EOF'
related_h: [<H-NNN>, ...]
related_ev: [<EV-NNN>, ...]
recurrence_count: <N>
stakes: <low | medium | high>
quarantine_reason: <one paragraph>
patches_resisted: <what patch the operator considered but rejected>
re_evaluate_at: <re-evaluation time> (e.g., end-of-session, post-Phase-7, 30d, etc.)
session: <SESSION_ID>

## Observation
<verbatim quote(s) from corpus or measurement showing the anomaly>

## Why this doesn't fit the main hypothesis
<one paragraph explanation>

## Why this doesn't refute the main hypothesis
<one paragraph: e.g., "wrong scale regime", "different workload class", "single instance, may be noise">

## Standard patch (rejected)
<what the patch would look like>
<why we're not doing it>
EOF
)")"
printf 'Created %s as br id %s\n' "$an_ref" "$an_id"
```

**Step 3 — Note the rejected patch.**

A common pattern: someone proposes "add a special case for regime R". Document the proposal AND the reason for rejecting:

> "Standard patch: add `if regime == R: use formula F_R` to the main theory. Rejected because: (a) we don't yet know if regime R is the actual cause; (b) patches accumulate into ad-hoc special-casing that loses predictive power."

Per Brenner §110, the goal is to keep the main theory clean while tracking the anomaly separately.

**Step 4 — Mark related H beads.**

For each related H, add an annotation:

```bash
for h_id in <related-H-id-list>; do
  br update "$h_id" --description="$(br show "$h_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' \
    | awk '1; END { print "## Anomalies"; print "- AN-NNN: <one-line>"; }')"
done
```

This makes the H bead aware that there's an outstanding anomaly affecting it.

**Step 5 — Re-evaluation schedule.**

Per the `re_evaluate_at` field, schedule re-evaluation:

- Post-Phase-7: anomaly is checked during fresh-eyes audit
- 30-day: living-review tick will re-check
- Recurrence threshold: re-evaluate if seen N more times

**Step 6 — Phase 7 audit check.**

Per `MO-07a-fresh-eyes.md`, audit panes specifically check anomaly beads:

- Did the anomaly recur during this session?
- Has new evidence either confirmed it as a real pattern OR explained it away?
- If pattern: promote anomaly to a new H with `origin:anomaly_spawned`.
- If explained: close the anomaly bead with the explanation.

**Step 7 — Anomaly cluster check.**

Per `MO-anomaly-cluster.md`: ≥2 anomalies sharing a feature → cluster suggests a paradigm shift signal.

If the new anomaly clusters with existing anomaly beads:
- File a new H with `origin:anomaly_spawned`.
- The cluster suggests the existing hypothesis space may have missed something.
- Phase 4 may need to reopen on the new H.

---

**Anti-patterns:**

- ✗ Patch the theory: add a special case to handle the anomaly
- ✗ Ignore the anomaly: don't file a bead; "it's noise"
- ✗ Promote the anomaly to a counter-hypothesis prematurely: weak evidence
- ✗ Anomaly bead without related_h/related_ev: hard to re-evaluate later
- ✗ Skip the rejected-patch documentation: future operators won't know what was considered

**Ship-or-Surface SLA:** within 15 min, anomaly bead filed + related H beads annotated.

---

## Per-archetype guidance

### A1 design-space

Anomalies often surface as "this design works well in 99% of cases but fails in regime R." Resist the urge to add a special case. File anomaly; if R is real, file new H exploring the regime.

### A2 codebase

Anomalies often surface as "this code path works for most inputs but breaks for input I." If I is realistic, file as anomaly; possibly promote to bug after Phase 7.

### A3 methodology

Anomalies often surface as "method M works in domain D1 but not in D2." Per Brenner §110, this might be a paradigm-shift signal. File and watch for clusters.

### A4 incident

Per /world-class-doctor-mode-for-cli-tools, incidents often have multiple contributing factors. Quarantine factors that don't fit the primary diagnosis until the post-mortem (per MO-post-mortem-formalization).

---

## Composition with other patterns

- Per MO-anomaly-cluster.md: when ≥2 anomalies cluster, promote to new H
- Per MO-cross-domain-import.md: anomalies in our domain may be patterns from other domains
- Per OC-012 (OPERATOR-CARDS.md): spawn anomaly-driven H when cluster threshold reached
- Per MO-falsifier-fired.md: if anomaly grows into refuting evidence, promote to falsifier-fire

---

## Cross-references

- BEADS-SCHEMA.md (anomaly bead schema)
- ANTI-PATTERNS.md (`AP: patch theory with special cases`)
- OPERATORS.md `ΔE Exception-Quarantine` card
- The Brenner transcript §110 (anomaly quarantine principle)
- POST-MORTEM-FORMALIZATION-PLAYBOOK.md (post-incident anomaly tracking)
