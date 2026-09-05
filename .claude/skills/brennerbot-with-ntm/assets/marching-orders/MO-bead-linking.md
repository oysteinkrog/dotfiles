# MO-bead-linking.md — Formalize Dependencies Between Beads

**Phase:** 3 / 4 / 5
**Operators activated:** ≡ Invariant-Extract (link surfaces structural relationships)
**Parameters:** `<PARENT_BEAD>`, `<CHILD_BEAD>`, `<RELATIONSHIP_TYPE>`

---

Beads have a description-level link convention (`supports: [H-NNN]`, `refutes: [H-NNN]`, `parent: H-NNN`) but ALSO a `br dep` graph. Both serve different purposes:

- **Description-level links**: semantic, used by jq queries and operator reasoning
- **`br dep` graph**: structural, used by `bv` for bottleneck/critical-path analysis

This MO ensures both stay in sync when forming a relationship between beads.

When a command needs to address an existing bead, resolve the public ref
(`H-001`, `EV-014`, `AN-003`) to the actual generated `br` ID first. Keep the
public ref in description fields for human readability.

---

**Step 1 — Identify the relationship type.**

| Relationship | When to use | Description-level | br dep |
|--------------|-------------|-------------------|--------|
| EV supports H | Phase 4 evidence pack | `supports: [H-NNN]` in EV.description | none (description suffices) |
| EV refutes H | Phase 4 counter-evidence | `refutes: [H-NNN]` in EV.description | none |
| H spawned-from anomaly | Phase 4 anomaly cluster | `origin: anomaly_spawned; parent: AN-NNN` | resolve refs, then `br dep add "$h_id" "$an_id"` |
| H is third-alternative of another | Phase 3 MO-03c | `origin: third_alternative; sibling: H-001` | none (siblings, not parents) |
| H superseded by another | Phase 3 triage merge | `state: superseded; parent: H-001` | resolve refs, then `br dep add "$h2_id" "$h1_id"` |
| Investigation T blocks H | Phase 4 test plan | `blocks: H-001` in T.description | resolve refs, then `br dep add "$h_id" "$t_id"` |
| C critique targets H | Phase 4-5 critique | `target: H-NNN` in C.description | none (target is implicit) |
| AF audit-finding targets EV/H | Phase 7 | `target_artifact: H-NNN` | none |

The decision: when does the relationship affect `br ready` resolution? If yes → use `br dep`. If no → description only.

Use this resolver before any snippet that addresses an existing public ref:

```bash
id_by_ref() {
  br list --all --json \
    | jq -r --arg ref "$1" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' \
    | head -1
}

require_id_by_ref() {
  local ref="$1" id
  id="$(id_by_ref "$ref")"
  [ -n "$id" ] || { echo "No bead found for public ref: $ref" >&2; return 1; }
  printf '%s\n' "$id"
}
```

**Step 2 — Apply description-level link.**

Update the bead description with the appropriate field:

```bash
child_ref="H-002"
parent_ref="H-001"
relationship_field="parent"
child_id="$(require_id_by_ref "$child_ref")"
parent_id="$(require_id_by_ref "$parent_ref")"

br update "$child_id" --description="$(br show "$child_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' \
    | awk -v rel="$relationship_field" -v parent="$parent_ref" '
        1
        END { print rel ": " parent }
    ')"
```

(Or, more carefully: if the field already exists, replace it via sed; if not, append.)

**Step 3 — Apply `br dep` if structural relationship.**

```bash
# When the parent must be RESOLVED before the child can be worked:
br dep add "$child_id" "$parent_id"
```

This makes `br ready` skip the child until the parent is closed.

**Step 4 — Verify the link is consistent.**

```bash
# Description-level:
br show "$child_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""' | grep -E "parent|supports|refutes|target"

# br-dep level:
bv --robot-insights | jq --arg c "$child_id" '.dependencies[] | select(.from==$c)'
```

Both should agree on the relationship.

**Step 5 — Avoid cycles.**

After adding any `br dep`, run:

```bash
bv --robot-insights | jq '.Cycles'
```

If `.Cycles` is non-empty: you've introduced a cycle (DL-3 deadlock per DEADLOCK-PATTERNS-MULTI-PANE.md). Remove the offending dep:

```bash
br dep remove "$child_id" "$parent_id"
```

And document the failed link in `session-logs/`. Don't try alternative dep-add patterns — investigate WHY the cycle wanted to form.

**Step 6 — Document semantic intent.**

In a comment field of the bead, explain:

> "Linked H-002 to H-001 because Phase 4 EV-018 showed they share the load-bearing assumption A-007. Per ⊘ Level-Split, both must succeed/fail together if A-007 holds."

Future operators (or you on Phase 10 review) need to understand WHY the link exists, not just THAT it exists.

---

**Anti-patterns:**

- ✗ Update description without `br dep` for structural deps → `br ready` returns wrong items
- ✗ `br dep add` without description update → reasoning is opaque
- ✗ Add a dep that creates a cycle → DL-3 deadlock; refuse
- ✗ Skip the WHY documentation → undebuggable later
- ✗ Use `parent: X` for sibling-of-X relationship → semantic confusion

**Ship-or-Surface SLA:** within 5-10 min per link.

---

## Common patterns

### Phase 3: marking H-002 as superseded by H-001

```bash
h1_id="$(require_id_by_ref H-001)"
h2_id="$(require_id_by_ref H-002)"
old_desc="$(br show "$h2_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""')"
new_desc="$(
  printf '%s\n' "$old_desc" | awk '
    BEGIN { done = 0 }
    /^state:/ && !done { print "state: superseded"; done = 1; next }
    { print }
    END { if (!done) print "state: superseded" }
  '
)"
br update "$h2_id" --description="$(
  printf '%s\n' "$new_desc" | awk '
    BEGIN { saw_parent = 0; saw_reason = 0 }
    /^parent:/ { if (!saw_parent) { print "parent: H-001"; saw_parent = 1 } ; next }
    /^superseded_reason:/ { if (!saw_reason) { print "superseded_reason: duplicate of H-001"; saw_reason = 1 } ; next }
    { print }
    END {
      if (!saw_parent) print "parent: H-001"
      if (!saw_reason) print "superseded_reason: duplicate of H-001"
    }
  '
)"
br dep add "$h2_id" "$h1_id"
# Verify:
bv --robot-insights | jq '.Cycles | length'  # → 0
```

### Phase 4: filing EV-014 supporting H-001

```bash
# (Inside MO-04a-investigate dispatch; see BEADS-WORKFLOW-CHEATSHEET.md)
ev_ref="EV-014"
ev_id="$(br create "$ev_ref: <one-line claim>" \
    --type=task --labels=evidence \
    --slug="$ev_ref" --external-ref="$ev_ref" --silent \
    --description="...
supports: [H-001]
...")"
# No br dep needed; description-level link suffices for EV→H.
```

### Phase 4: anomaly cluster spawning new H

```bash
# AN-001 and AN-003 share feature 'connection_pool_under_pressure'
# Spawn new H:
h_ref="H-007"
h_id="$(br create "$h_ref: connection-pool pressure under workload class W'" \
    --type=task --labels=hypothesis --priority=2 \
    --slug="$h_ref" --external-ref="$h_ref" --silent \
    --description="...
origin: anomaly_spawned
parent: AN-001
related_anomalies: [AN-001, AN-003]
state: active
falsifier: <observable>
...")"
an1_id="$(require_id_by_ref AN-001)"
an3_id="$(require_id_by_ref AN-003)"
br dep add "$h_id" "$an1_id"
br dep add "$h_id" "$an3_id"
# H-007 is now ready-blocked until both anomalies are resolved.
```

### Phase 5: linking C-007 to H-005

```bash
c_ref="C-007"
c_id="$(br create "$c_ref: H-005 fails under workload class W''" \
    --type=task --labels=critique \
    --slug="$c_ref" --external-ref="$c_ref" --silent \
    --description="
target: H-005
attack: <specific>
severity: serious
...")"
# No br dep — critique is bidirectional ("targets") not structural.
```

---

## Cross-references

- BEADS-SCHEMA.md — bead types and field conventions
- BEADS-WORKFLOW-CHEATSHEET.md — concrete br commands per phase
- DEADLOCK-PATTERNS-MULTI-PANE.md DL-3 — cycle detection
- /beads-bv — graph-aware analysis of dep graph
- /beads-br — full beads CLI reference
