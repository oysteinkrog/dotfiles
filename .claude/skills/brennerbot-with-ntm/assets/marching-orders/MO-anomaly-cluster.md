# MO-anomaly-cluster.md — Promote Clustered Anomalies into a New Hypothesis

**Phase:** 4 (during investigation rounds)
**Operators activated:** ΔE Exception-Quarantine, ◊ Paradox-Hunt
**Parameters:** `<PANE_N>`, `<CLUSTER_AN_IDS>` (comma-separated AN-NNN beads sharing a feature), `<SHARED_FEATURE>` (one-sentence description), `<SESSION_ID>`

---

Per Brenner §110 ("we didn't conceal them; we put them in an appendix") + the cluster-check rule (per ΔE operator card): if ≥2 anomalies share a feature, they're not unrelated noise — they're revealing a missing rule. Promote them to a new hypothesis.

You are pane `<PANE_N>` and the orchestrator has flagged that `<CLUSTER_AN_IDS>` share `<SHARED_FEATURE>`. Your job: file a new H bead with `origin:anomaly_spawned`.

---

**Step 1 — Read all clustered anomalies.**

```bash
id_by_ref() {
  br list --all --json \
    | jq -r --arg ref "$1" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' \
    | head -1
}

cluster_an_refs="<CLUSTER_AN_IDS>"  # AN refs, separated by spaces or commas
for an_ref in $(printf '%s\n' "$cluster_an_refs" | tr ',' ' '); do
  an_id="$(id_by_ref "$an_ref")"
  [ -n "$an_id" ] || { echo "No bead found for public ref: $an_ref" >&2; exit 1; }
  br show "$an_id" --json
done
```

Note each anomaly's `observation:` and `conflicts_with:` fields.

**Step 2 — Identify the missing rule.**

Ask: what production rule, if added to our model, would make these anomalies *no longer* anomalies but expected observations?

The missing rule is the new hypothesis.

**Step 3 — Frame the hypothesis (Brenner-style).**

The new H must satisfy all standard invariants:

- `claim:` — the missing rule, stated affirmatively
- `mechanism:` — why this rule produces these specific anomalies
- `falsifier:` — what observation would kill this hypothesis (must be observable)
- `expected_evidence:` — what additional observations would support it (beyond the cluster)
- `category:` — typically `mechanistic` or `boundary`
- `origin: anomaly_spawned`
- `confidence: speculative` (anomaly-spawned Hs are speculative until further evidence)
- `parent:` — link to the FIRST anomaly that started the cluster

**Step 4 — File the bead.**

```bash
h_ref="H-NNN"  # public ref; replace NNN before running
h_id="$(br create "$h_ref: Anomaly-spawned hypothesis from <CLUSTER_AN_IDS>" \
  --type=task --labels=hypothesis --priority=2 \
  --slug="$h_ref" --external-ref="$h_ref" --silent \
  --description="$(cat <<'EOF'
claim: <the missing rule, stated affirmatively>
mechanism: <why this rule produces the anomalies>
falsifier: <observable falsifier>
expected_evidence: <additional observations supporting the rule>
category: mechanistic
origin: anomaly_spawned
confidence: speculative
parent: <first AN-NNN in cluster>
session: <SESSION_ID>
spawned_from_cluster: [<CLUSTER_AN_IDS>]

## Detail
The clustered anomalies share <SHARED_FEATURE>. If we add the rule "<missing rule>" to our model, these anomalies become expected. The rule's falsifier and additional expected evidence are above.

## Coordinates (per 𝓛 Recode)
This claim is most clearly evaluated under encoding: <encoding>.
EOF
)")"
printf 'Created %s as br id %s\n' "$h_ref" "$h_id"
```

**Step 5 — Update each anomaly bead.**

Mark each clustered anomaly with `spawned_hypothesis:` field:

```bash
id_by_ref() {
  br list --all --json \
    | jq -r --arg ref "$1" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' \
    | head -1
}

spawned_ref="H-NNN"
cluster_an_refs="<CLUSTER_AN_IDS>"  # AN refs, separated by spaces or commas
for an_ref in $(printf '%s\n' "$cluster_an_refs" | tr ',' ' '); do
  an_id="$(id_by_ref "$an_ref")"
  [ -n "$an_id" ] || { echo "No bead found for public ref $an_ref" >&2; exit 1; }
  br update "$an_id" --description="$(br show "$an_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""')$(printf '\n\nspawned_hypothesis: %s' "$spawned_ref")"
done
```

**Step 6 — Post to per-H thread + INVEST-coord.**

```
Subject: [<SESSION_ID>] New anomaly-spawned hypothesis: H-NNN

Cluster: <CLUSTER_AN_IDS> share <SHARED_FEATURE>.
Promoted to: H-NNN with origin:anomaly_spawned, confidence:speculative.

This is now a candidate for Phase 4 investigation. Operator: assign an Investigator pane to H-NNN if backlog allows.

If H-NNN survives Phase 4 with supporting EVs, it may be the missing rule that resolves the anomaly cluster. If the falsifier fires, the anomalies remain unresolved — file as `paradigm_shifting` candidates per ΔE.
```

**Step 7 — Trigger Phase 4 follow-up dispatch.**

The operator typically responds to this MO by dispatching `MO-04a-investigate.md` for the new H-NNN. The anomaly-spawned H gets its own evidence pack and either confirms (the rule explains the anomalies) or refutes (the cluster is unrelated noise after all).

---

**Anti-patterns:**

- ✗ Promote anomalies that don't actually share a feature ("they're all confusing"). Forced clustering produces noise hypotheses.
- ✗ File the new H without a falsifier. Same invariant as any H.
- ✗ Skip updating the anomaly beads with `spawned_hypothesis:` field. Audit trail breaks.
- ✗ Treat the new H as confirmed because anomalies clustered. Anomaly-spawn is a *hypothesis*, not a verdict.
- ✗ Ignore the cluster ("it's probably noise") without testing. Per Brenner §110, anomalies that cluster *probably reveal a missing rule*.

**Ship-or-Surface SLA:** within 30 min, file the new H bead OR explicitly state the cluster is not actually a cluster (cite which features are shared and which are not).
