# CONVERGENCE — The Mechanical Convergence Rule

This file is the operational definition of when the gauntlet's main loop terminates. Convergence is not editorial — it is computed by `scripts/convergence-tracker.sh` against the three durable ledgers and every per-bucket findings file, and the script's exit code is the sole authority. See [KERNEL.md § K-12](KERNEL.md) for the axiom; see [../../SKILL.md § Convergence Rule](../../SKILL.md) for the one-paragraph summary the rest of the skill cross-links to. The implementations live in `scripts/convergence-tracker.sh` (gauntlet skill scripts dir) and run as a CI gate on the gauntlet workspace.

---

## (a) The three convergence conditions

All three must hold simultaneously for `convergence-tracker.sh` to exit 0:

### Condition 1 — Minimum rounds met
```
ROUND_COUNT ≥ 10
```
Where a *round* is one full re-execution of Phases 5→10 (Performance Harness → Conformance Harness → Surface Parity → Negative-Ledger → Baseline Run → Idea-Wizard). Each round writes a `round_N/` artifact directory; the count is the maximum N for which `round_N/.complete` exists.

Rationale: even when the loop produces zero new findings, the floor of 10 rounds is required to provide adversarial coverage. A "first-pass clean" run almost certainly missed something; the 10-round minimum is the empirical FrankenSQLite floor below which late-breaking findings still appeared.

### Condition 2 — Two consecutive clean rounds
```
NEW_GENUINE_FINDINGS(round N)     < 3
NEW_GENUINE_FINDINGS(round N − 1) < 3
```
Where `NEW_GENUINE_FINDINGS` is the count of findings in round N that:
- do **not** have a `MismatchSignature` matching a round-(N−1) finding,
- do **not** appear in any closed ledger entry from rounds 1..N−1,
- are **not** classified as `FalsePositive` or `OrderDependentDifference` (priority 4–5),
- have a populated `first_divergence_jsonptr` or equivalent localization.

The threshold is `< 3`, not `0`. Two minor refinements per round is consistent with a converged loop's residual signal; three or more is regression of the loop itself.

### Condition 3 — Every open hypothesis resolved
```
forall H in OPEN_HYPOTHESES:
    H.status in {CONFIRMED_GAP, NO_EVIDENCE, NEEDS_REFINEMENT, NEW_HYPOTHESIS_SPAWNED}
```
The four valid terminal-or-progressing states for an entry in:
- `GAUNTLET_EXPERIMENT_DESIGNS.md`
- `PERF_HYPOTHESIS_LEDGER.md`
- `CONFORMANCE_HYPOTHESIS_LEDGER.md`
- `SURFACE_PARITY_HYPOTHESIS_LEDGER.md`

`CONFIRMED_GAP` and `NO_EVIDENCE` are terminal. `NEEDS_REFINEMENT` and `NEW_HYPOTHESIS_SPAWNED` are progressing — they extend the loop because they imply work for the next round. Convergence with `NEEDS_REFINEMENT` entries open means the loop is not done; the tracker exits non-zero.

---

## (b) What "new genuine finding" means

The distinction between "new" and "rediscovered" matters because the loop will surface the same root-cause bug under multiple test inputs. Three cases:

### Re-discovery
A round-N finding with the same `MismatchSignature.hash` as a round-(N−1) finding (or any prior round) is **not new**. The signature is the truncated SHA-256 of the canonical minimal repro (see [../tooling/ORACLE-TOOLCHAIN.md § mismatch-minimizer](../tooling/ORACLE-TOOLCHAIN.md) and MINING-2 §5).

```
finding.signature.hash in PRIOR_SIGNATURES  =>  rediscovery, not new
```

### Duplicate-by-signature within the round
Within a single round, multiple test inputs hitting the same root-cause yield the same signature. Counted once.

```
unique signatures in round N  =  count for "new finding" denominator
```

### Refinement of existing
A round-N finding that maps to a round-(N−1) finding's signature but with additional context (longer first-diverging SQL, more localized jsonptr, narrower minimal-statement-count) is a **refinement**, recorded against the existing entry; not a new finding.

### Genuinely new
A finding whose `MismatchSignature.hash` has never appeared in any prior round and is not classified as `FalsePositive`. This is what increments the new-findings count.

---

## (c) How `scripts/convergence-tracker.sh` computes it

Pseudocode (the actual script also handles symlinks, partial rounds, and ledger schema versions):

```bash
#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="$1"
cd "$WORKSPACE"

# 1) Determine round count: the highest N with round_N/.complete present.
ROUND_COUNT=$(ls -1d round_*/ 2>/dev/null \
              | sed 's|round_\([0-9]\+\)/|\1|' \
              | sort -n \
              | tail -1 || echo 0)

if [[ "$ROUND_COUNT" -lt 10 ]]; then
    echo "FAIL: round count $ROUND_COUNT < 10"
    exit 1
fi

# 2) Compute new-genuine-findings per round via signature diff.
#    Each round_N/findings.jsonl is one finding per line with a
#    MismatchSignature field. We build the cumulative signature set
#    through round (N-1), then count round_N signatures NOT in that set
#    AND NOT in any closed ledger entry AND NOT classified FalsePositive/Order.

cumulative=()
declare -a NEW_PER_ROUND
for N in $(seq 1 "$ROUND_COUNT"); do
    new_count=$(jq -s --argjson prior "$(printf '%s\n' "${cumulative[@]}" | jq -R . | jq -s .)" '
        map(select(
            (.classification != "FalsePositive") and
            (.classification != "OrderDependentDifference") and
            (.signature.hash | IN($prior[]) | not) and
            (.signature.hash | in_closed_ledger | not)
        ))
        | length
    ' "round_${N}/findings.jsonl")
    NEW_PER_ROUND[$N]="$new_count"

    # extend cumulative with this round's signatures
    while read -r sig; do cumulative+=("$sig"); done < <(jq -r '.signature.hash' "round_${N}/findings.jsonl")
done

# 3) Two consecutive clean rounds <3 each.
LAST=${NEW_PER_ROUND[$ROUND_COUNT]}
PREV=${NEW_PER_ROUND[$((ROUND_COUNT-1))]}
if [[ "$LAST" -ge 3 || "$PREV" -ge 3 ]]; then
    echo "FAIL: rounds $((ROUND_COUNT-1))=$PREV, $ROUND_COUNT=$LAST; need both <3"
    exit 2
fi

# 4) Every open hypothesis resolved (status in valid set).
UNRESOLVED=$(jq -r '
    select(.status as $s | ["CONFIRMED_GAP","NO_EVIDENCE","NEEDS_REFINEMENT","NEW_HYPOTHESIS_SPAWNED"] | index($s) | not)
    | .id
' \
    GAUNTLET_EXPERIMENT_DESIGNS.jsonl \
    PERF_HYPOTHESIS_LEDGER.jsonl \
    CONFORMANCE_HYPOTHESIS_LEDGER.jsonl \
    SURFACE_PARITY_HYPOTHESIS_LEDGER.jsonl | wc -l)

if [[ "$UNRESOLVED" -gt 0 ]]; then
    echo "FAIL: $UNRESOLVED hypotheses unresolved"
    exit 3
fi

# 5) Anti-vocabulary sweep on closed ledger entries.
ANTI=$(rg -c '\b(later|if it seems important|we should revisit|tracked elsewhere|TODO|FIXME|future work|might be worth|interesting direction|worth exploring|someone should)\b' \
       docs/progress/perf-negative-results.md \
       docs/progress/conformance-negative-results.md \
       docs/progress/surface-deferrals.md 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')

if [[ "$ANTI" -gt 0 ]]; then
    echo "FAIL: $ANTI anti-vocabulary phrases in closed ledger entries"
    exit 4
fi

echo "CONVERGED: rounds=$ROUND_COUNT, last two new-findings=$PREV,$LAST"
exit 0
```

Exit codes: `0` = converged, `1` = under-rounded, `2` = noisy tail, `3` = unresolved hypotheses, `4` = forbidden retry-vocabulary in closed entries.

---

## (d) Round structure under the hood

Each round is one full re-execution of Phases 5→10 and writes:

```
<workspace>/round_<N>/
├── .start                         # ISO-8601 timestamp written at round entry
├── .complete                      # written only after every sub-phase succeeds
├── phase5_perf/                   # comprehensive_bench JSON v3 + focused benches + hot-path snapshots
├── phase6_conformance/            # oracle + differential V2 + metamorphic + fault + crash-boundary + fuzz + e-process
├── phase7_surface/                # FeatureUniverse + InvariantCatalog + dashboard
├── phase8_ledger/                 # delta to the three durable ledgers + cass-mining grep results
├── phase9_baseline/               # baseline-runners per pillar; new .bench-history candidates
├── phase10_idea-wizard/           # idea-wizard + advanced-methods + frontier-math emitted candidates
├── findings.jsonl                 # all findings from this round, one per line, with MismatchSignature
└── synthesis.md                   # synthesizer subagent's global picture (Phase 11)
```

The same script that drives the loop writes `round_N/` directories; the tracker reads them. There is no editorial "is this round done?" — the `.complete` marker is the sole signal.

---

## (e) Compaction-survival

The workspace markdown files are **source of truth**, not the agent's working memory. An agent dropping into a mid-run workspace must be able to re-derive the loop state from:

1. `phase0_*` JSONs (toolchain inventory, project class, skill availability, oracle preflight)
2. `round_<N>/` directories (per-round artifacts)
3. The three durable ledgers (`docs/progress/{perf,conformance,surface}-negative-results.md`)
4. The four hypothesis ledgers (`*_HYPOTHESIS_LEDGER.md`, `GAUNTLET_EXPERIMENT_DESIGNS.md`)
5. The convergence tracker's current exit code

The agent does not need to read the chat transcript or recall any state. Run `scripts/convergence-tracker.sh <workspace>`; the exit code says where you are. Run `ls round_*/ | tail -1`; the highest-numbered directory says the last completed round. Read its `synthesis.md`; you know what to do next.

**Specifically:** "compaction" here means Claude's context being summarized or reset. If the next message after compaction is "continue the gauntlet", the agent re-orients in <5 tool calls: tracker exit code → last round directory → synthesis.md → next phase. No state lives only in the agent's head.

---

## (f) When to declare convergence stalled and escalate

The loop is stalled (not converging, *and* not making progress toward convergence) when any of:

| Stall signal | Detection | Escalation |
|---|---|---|
| **Hypothesis ledger growing without resolution** | Round N has more open `NEEDS_REFINEMENT` entries than round (N−1), for 3 consecutive rounds. | Bring in [OPERATORS.md § ⊕ Isomorphic-Rewrite](OPERATORS.md) and [§ ⟁ Triangulate-Profile](OPERATORS.md) to attack the unresolved set; if 3 more rounds yield no resolution, escalate to a fresh-eyes round (Phase 14) early. |
| **BOCPD shows `ShiftDetected`** | `replay_harness.rs` emits `Regime::ShiftDetected` on the parity-score stream. (See [../tooling/ORACLE-TOOLCHAIN.md § BOCPD](../tooling/ORACLE-TOOLCHAIN.md).) | The loop's distributional assumptions have broken. Halt new rounds; investigate the shift point with [OPERATORS.md § ⌘ Reduce](OPERATORS.md) on the window containing the change-point; do not declare convergence until `Regime::Stable` is re-attained for ≥3 windows. |
| **E-process Ville-rejection** | `eprocess.rs` emits `E_global(t) ≥ 1/α`. An MVCC (or class-equivalent) invariant has been violated under the anytime-valid test. | A genuine invariant violation in the harness itself. Halt the gauntlet; this is a [../taxonomy/INVARIANT-CATALOG.md](../taxonomy/INVARIANT-CATALOG.md) failure and must be fixed before any convergence claim. |
| **Anti-vocabulary in closed entries** | `convergence-tracker.sh` exit code 4. | Sweep the ledgers per [RETRY-CONDITION-VOCABULARY.md § anti-vocabulary](RETRY-CONDITION-VOCABULARY.md); rewrite every offending entry with one of the 8 forms; if you cannot, reopen the entry. |
| **Fresh-eyes can't get two clean rounds** | Phase 14 produces ≥3 genuine new findings in either of the last two passes. | Loop back to Phase 12 (Remediation); the convergence loop reopens; reset the clean-round counter. |
| **Adversarial-search finds counterexample** | `adversarial_search.rs` produces a (perturbation, seed, expected vs actual) tuple that the gates accept. | The gate is biased; fix the gate; the counterexample becomes a regression test; reset the clean-round counter. |
| **Soak run surfaces late-breaking divergence** | Phase 15 24h fuzz / multi-day BOCPD / loom-shuttle produces a finding not in any prior round. | Loop back to Phase 12; the convergence loop reopens; do NOT skip phases on the second pass. |

Stalled convergence is not failure. It is the loop telling you the methodology is correctly demanding more evidence. The escalation is to the operator library (sharper tools), not to declaring victory.

---

## Cross-links

- Convergence enforces [KERNEL.md § K-12](KERNEL.md) (convergence as CI gate).
- The MismatchSignature primitive that drives "new vs rediscovered" is in [../tooling/ORACLE-TOOLCHAIN.md § mismatch-minimizer](../tooling/ORACLE-TOOLCHAIN.md).
- The four hypothesis ledgers' entry format is in [../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md](../experiments/EXPERIMENT-DESIGNS-TEMPLATE.md).
- Phase 14 (fresh-eyes) is the explicit termination gate before Phase 15 (soak); see [../PHASES.md § Phase 14](../PHASES.md).
- BOCPD regime detection is documented in [SOAK-PROTOCOL.md § BOCPD](SOAK-PROTOCOL.md) and the underlying machinery in [../tooling/ORACLE-TOOLCHAIN.md § replay_harness](../tooling/ORACLE-TOOLCHAIN.md).
- The anti-vocabulary that exit code 4 catches is in [RETRY-CONDITION-VOCABULARY.md § anti-vocabulary](RETRY-CONDITION-VOCABULARY.md).
