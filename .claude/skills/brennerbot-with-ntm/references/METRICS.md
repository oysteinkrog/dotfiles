# METRICS.md — Measurable Session Quality Metrics

<!-- TOC: Per-phase metrics | Cross-phase metrics | Health dashboard | Cross-session metrics | Anti-patterns in metric usage | Adding new metrics -->

Vibes-based quality assessment is anti-Brenner. This file specifies the measurable metrics this skill tracks across a session, per phase, and across sessions.

Every metric below has: **definition**, **how to compute**, **healthy range**, **red-flag threshold**, **what it predicts**.

---

## Per-phase metrics

### M-101 — Falsifier-density (Phase 1)

**Definition:** Length of the `Falsifier` section in `intake/question_of_record.md`, in words.

**Compute:** `awk '/^## Falsifier/,/^##/' intake/question_of_record.md | wc -w`

**Healthy:** 30–150 words. Concrete, observable, decidable.

**Red flag:** <15 (vague) or >250 (likely hedging).

**Predicts:** Phase 4 investigation tractability. Vague falsifiers predict F-401 (evidence inflation) at high rates.

---

### M-102 — Scope-out-of-scope ratio (Phase 1)

**Definition:** ratio of bullet items in `Out of Scope` to bullets in `Scope`.

**Compute:**
```bash
S=$(awk '/^## Scope/,/^##/' intake/question_of_record.md | grep -c '^- ')
O=$(awk '/^## Out of Scope/,/^##/' intake/question_of_record.md | grep -c '^- ')
echo "scale=2; $O / $S" | bc
```

**Healthy:** 0.5–1.5 (Out of Scope should be roughly comparable to Scope).

**Red flag:** ratio < 0.3. Out-of-Scope is empty or trivially short → question scope is uncontrolled.

**Predicts:** Phase 4 drift. Insufficient out-of-scope predicts investigators wandering off-topic.

---

### M-201 — Onboarding-ack latency (Phase 2)

**Definition:** wall-time between `MO-02-onboarding.md` dispatch and last pane's ack.

**Compute:** parse from `session-logs/dispatch-*.log` and `mail inbox` ack timestamps.

**Healthy:** ≤5 min for Pair, ≤10 min for Squad, ≤20 min for Swarm.

**Red flag:** any pane >30 min without ack. Likely F-201 (zsh) or F-202 (mail down).

**Predicts:** Phase 3 dispatch readiness. Slow onboarding correlates with fragile coordination.

---

### M-301 — Hypothesis slate diversity (Phase 3 exit)

**Definition:** Counts by category, by origin, by confidence.

**Compute:**
```bash
br list --label=hypothesis --status=open --json | jq '
  {
    by_category: [.issues[]? | ((.description // "") | capture("category: (?<category>\\w+)")? | .category)] | group_by(.) | map({key: .[0], value: length}) | from_entries,
    by_origin:   [.issues[]? | ((.description // "") | capture("origin: (?<origin>\\w+)")? | .origin)]     | group_by(.) | map({key: .[0], value: length}) | from_entries,
    by_confidence: [.issues[]? | ((.description // "") | capture("confidence: (?<confidence>\\w+)")? | .confidence)] | group_by(.) | map({key: .[0], value: length}) | from_entries
  }'
```

**Healthy:**
- ≥3 distinct categories represented
- ≥1 `origin:third_alternative` (mandatory)
- Mix of confidences (not all `high` — that's confirmation bias; not all `speculative` — that's analysis paralysis)

**Red flag:**
- 0 `origin:third_alternative` → F-301
- All H in same `category` → triage missed level-splits → F-302
- All H `confidence:high` → proposers anchored on tacit consensus → ∿ Dephase needed

**Predicts:** Phase 4 informativeness. Diverse slate predicts more decisive Phase 4.

---

### M-401 — Kill rate vs add rate (Phase 4 — primary convergence signal)

**Definition:** Per round, `kill_rate = (refuted) + (superseded) + 0.5×(confidence-degraded)`; `add_rate = (new H) + 0.3×(confidence-upgraded)`.

**Compute:** [`scripts/convergence-check.sh --phase=4`](../scripts/convergence-check.sh).

**Healthy:** kill_rate ≥ add_rate by round 3. Kill rate climbs steadily.

**Red flag:** add_rate > kill_rate for ≥2 consecutive rounds → F-401 evidence inflation.

**Predicts:** Phase 4 wall-time. If kill_rate remains low, the round is producing prose, not knowledge.

---

### M-402 — Falsifier-firing rate (Phase 4)

**Definition:** count of `EV-*.refutes:` populating `H-*` falsifier in the round.

**Compute:**
```bash
br list --label=evidence --json | jq '
  [.issues[]? | select((.description // "") | contains("refutes: [")) ] | length'
```

**Healthy:** ≥1 falsifier-firing event per round across the swarm.

**Red flag:** 0 across ≥2 rounds → F-403 confirmation bias.

**Predicts:** Phase 5 decisiveness. No falsifier events in Phase 4 means Phase 5 debates will rule on rhetoric (F-503).

---

### M-403 — Evidence pack depth distribution

**Definition:** for each active `H-*`, count of `EV-*.supports[H_ID]` and `EV-*.refutes[H_ID]`.

**Compute:**
```bash
# Use a bracket-scoped, word-boundary regex so multi-H lists like
# `supports: [H-001, H-007]` count for both H-001 and H-007 while an H-ID that
# only appears in a sibling field (e.g., `refutes: [H-001]`) does NOT count
# toward the `supports` total. The previous `contains("supports: [") and contains($h)`
# form double-counted any EV whose description happened to mention `$h` anywhere.
for H in $(br list --label=hypothesis --status=open --json | jq -r '.issues[]?.id'); do
  S=$(br list --label=evidence --json | jq --arg h "$H" '[.issues[]? | select((.description // "") | test("supports:[[:space:]]*\\[[^\\]]*\\b" + $h + "\\b[^\\]]*\\]"))] | length')
  R=$(br list --label=evidence --json | jq --arg h "$H" '[.issues[]? | select((.description // "") | test("refutes:[[:space:]]*\\[[^\\]]*\\b"  + $h + "\\b[^\\]]*\\]"))] | length')
  echo "$H supports=$S refutes=$R"
done
```

**Healthy:** every active H has ≥2 supports AND ≥1 refute attempt (regardless of whether refute fired).

**Red flag:** any H with 0 refute attempts → F-403.

---

### M-501 — Adjudicator kill rate (Phase 5)

**Definition:** fraction of adjudications that flip H to `refuted` or `superseded`.

**Compute:**
```bash
br list --label=debate --status=closed --json | jq '
  {
    total: [.issues[]?] | length,
    killed: [.issues[]? | select((.description // "") | test("(^|\\n)state:[[:space:]]*(refuted|superseded)([[:space:]]|$)"))] | length
  }
  | if .total == 0 then 0 else (.killed / .total) end'
```

**Healthy:** 30–70% kill rate. Lower → adjudicator is risk-averse (F-501); higher → adjudicator is rabid (kills on rhetoric, F-503).

**Red flag:** 0% (never kills) or 100% (kills everything) — both anti-Brenner.

---

### M-502 — Adjudicator-family bias

**Definition:** correlation between adjudicator's model family and which H champion's family wins the debate.

**Compute:** cross-tabulate adjudications by `(adjudicator_family, winning_family)`.

**Healthy:** no strong correlation (verdicts independent of adjudicator family).

**Red flag:** strong correlation → F-502.

**Predicts:** Phase 6 distillation bias risk.

---

### M-601 — Disagreement register density

**Definition:** count of D-NNN entries per pair of distillations.

**Compute:** `grep -cE '^## D-' distillations/disagreement_register.md`.

**Healthy:** ≥(N choose 2) where N = model families. For 3 families, ≥3.

**Red flag:** 0 → F-603. Below threshold → F-601 (averaged) or F-602 (single dominance).

---

### M-602 — Distillation-family balance

**Definition:** for each per-family distillation, count of citations from `meta_synthesis.md`. Balance across families.

**Compute:**
```bash
for FAM in cc cod gmi; do
  CITES=$(grep -c "by_${FAM}.md" distillations/meta_synthesis.md)
  echo "$FAM cites=$CITES"
done
```

**Healthy:** roughly balanced (within 2x of each other).

**Red flag:** one family >5x another → F-602 single-family dominance.

---

### M-701 — Audit finding distribution

**Definition:** counts of audit findings per severity per trio-round.

**Compute:**
```bash
br list --label=audit-finding --json | jq '
  [.issues[]? | try ((.description // "") | match("severity: (\\w+)") .captures[0].string) catch empty]
  | group_by(.) | map({key: .[0], count: length})'
```

**Healthy in trio-round 1:** Critical 0–2, High 1–5, Medium 3–10, Low 5+.

**Healthy in trio-round 2:** Critical 0, High 0–1, Medium 0–3, Low 0–5.

**Red flag:** trio-round 1 has 0 findings → F-701 (auditors rubber-stamping). Trio-round 2 has critical findings unaddressed → cannot exit Phase 7.

---

### M-702 — Time-to-fix per finding severity

**Definition:** wall-time between `audit-finding` filed and addressed (state changes to `addressed`).

**Compute:** difference between `created_at` and `closed_at` in br data.

**Healthy:** Critical ≤30 min, High ≤2h, Medium ≤8h, Low can be deferred.

**Red flag:** critical finding open >1h → block Phase 8.

---

## Cross-phase metrics

### M-CX1 — Source-corpus coverage

**Definition:** count of distinct `§`-anchors cited across all `EV-*` beads in the session.

**Compute:**
```bash
br list --label=evidence --json | \
  jq -r '.issues[]? | (.description // "")' | \
  grep -oE '§[0-9]+' | sort -u | wc -l
```

**Healthy ranges (per [SOURCE-CORPUS.md § Source-coverage map](SOURCE-CORPUS.md)):**
- Saturating: ≥30 anchors
- Adequate: 15–29
- Thin: 6–14
- Sparse: ≤5

**Red flag:** Sparse → likely operator concentration. Phase 10 drift-check should flag.

---

### M-CX2 — Operator coverage

**Definition:** for each of the 15 operators, did it fire at least once in the session?

**Compute:** scan session-logs for operator glyphs `◊ ⊘ 𝓛 ≡ ✂ ⟂ ↑ ⌂ 🔧 ⊞ 🤝 ΔE † ∿ ⊙`:

```bash
for OP in '◊' '⊘' '𝓛' '≡' '✂' '⟂' '↑' '⌂' '🔧' '⊞' '🤝' 'ΔE' '†' '∿' '⊙'; do
  C=$(grep -c "$OP" session-logs/*.md 2>/dev/null | awk -F: '{s+=$NF} END {print s}')
  echo "$OP: $C"
done
```

**Healthy:** all 15 fire at least once.

**Red flag:** ≥3 operators never fired → Phase 10 drift-check should explain why.

---

### M-CX3 — Wall-time per phase

**Definition:** seconds between `phase_<N>_complete.flag` timestamps.

**Compute:**
```bash
for N in 1 2 3 4 5 6 7 8 9; do
  FLAG="$WORKSPACE/.brenner_workspace/phase_${N}_complete.flag"
  [ -f "$FLAG" ] && stat -c %Y "$FLAG"
done
```

**Healthy ranges by tier:**
- Solo: 30–60 min total
- Pair: 1–2h total
- Squad: 3–5h total
- Swarm: 4–8h total

**Red flag:** any phase 3× expected → likely stuck pane (per `/vibing-with-ntm` cards). Run liveness-check.sh.

---

### M-CX4 — Productivity ground truth

**Definition:** git commits per hour during Phases 4-6.

**Compute:** `git log --since='start of phase 4' --until='end of phase 6' --oneline | wc -l` divided by phase wall-time.

**Healthy:** ≥3 commits/hour during active phases.

**Red flag:** 0 commits in 1+ hour during a "working" phase → F-401 prose-without-commits per `/vibing-with-ntm` AP-32.

---

### M-CX5 — Anomaly cluster index

**Definition:** Are anomalies scattered or clustered? Compute via:
```bash
br list --label=anomaly --json | \
  jq '[.issues[]? | (((.description // "") | capture("cluster_with: \\[(?<cluster>.+?)\\]")? | .cluster) // "scattered")]
      | group_by(.) | map({cluster: .[0], count: length})'
```

**Healthy in Phase 4:** mostly scattered (anomalies are unrelated noise).

**Red flag:** ≥2 anomalies clustering → spawn new H with `origin:anomaly_spawned` (per ΔE).

---

## Health dashboard (one-shot quickref)

`scripts/emit-quickref.sh` (Tier 2) renders a single-screen dashboard:

```
=== RS-YYYYMMDD-<slug> session health ===
Phase: 4 round 3 (active)
Wall time: 2h 14min (Squad tier; healthy range 3-5h total)
Roster: 5 panes (cc:3 cod:1 gmi:1) — productive-ignorance: pane 1

Beads:
  Hypotheses: 7 active, 2 refuted, 1 superseded (kill_rate=3, add_rate=1 — CONVERGED for round)
  Evidence:   23 (15 supports, 6 refutes, 2 informs)
  Tests:      4 (all completed)
  Anomalies:  3 (1 cluster of 2, 1 scattered)

Falsifier coverage: 7/7 H have falsifier (100%)
Expected-evidence coverage: 7/7 (100%)
Third-alternative present: yes (H-006)
Scale-physics calculations: 3/3 verified

Source corpus coverage: 18 §-anchors (adequate)
Operator coverage: 13/15 fired (missing: ⊙ Productive-Ignorance, 🔧 DIY)

Productivity (last 1h): 8 commits, 3 EVs filed, 1 H state change.

Phase 4 ready to exit? YES
Phase 5 ready to start? YES (debate pairs: H-002 vs H-003, H-005 vs H-006)
```

---

## Cross-session metrics (across multiple brennerbot runs)

If the operator runs many sessions, track these across:

### M-XSESS1 — Drift-verdict distribution

Across N drift checks: how many were `convergent` vs `divergent-improvement` vs `divergent-regression` vs `mixed`?

**Healthy:** mostly `convergent` with occasional `divergent-improvement` (the methodology evolves).

**Red flag:** rising `divergent-regression` rate → operator is drifting; reread the kernel.

### M-XSESS2 — Operator-application matrix

Across sessions: for each of the 15 operators × 10 phases, how often did it fire?

**Healthy:** all 15 × ≥3 phases each.

**Red flag:** any cell at 0 across many sessions → that operator/phase combination may need a clearer marching-order template.

---

## Anti-patterns in metric usage

| ✗ | Why |
|---|-----|
| Reading metrics in isolation | Metrics are signals, not verdicts; cross-check with Liveness Truth Stack |
| Using metrics as exit criteria when invariants would do | The invariant (every H has falsifier) is binary; the metric (falsifier density) is continuous — they're different |
| Optimizing metrics ("more EVs!") | Goodhart's law; metrics chosen for diagnostic value, not optimization targets |
| Skipping metrics during incident-investigation mode | Compressed mode SHOULD watch convergence; just at faster cadence |
| Treating all healthy ranges as universal | Ranges are tier-and-question-dependent; calibrate per session |

---

## Adding new metrics

When extending: each metric must have:

1. Operationally precise definition
2. Computable formula (with example shell command)
3. Healthy range (with rationale)
4. Red-flag threshold (with corresponding F-### code if applicable)
5. Predictive value (what does this metric predict about subsequent phases?)

Don't add metrics for the sake of metrics. Add them when a session has surfaced a recurring failure mode that one metric would have predicted.
