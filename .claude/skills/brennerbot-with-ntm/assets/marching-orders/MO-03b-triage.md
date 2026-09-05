# MO-03b-triage.md — Hypothesis Triage

**Phase:** 3
**Operators activated:** ⊘ Level-Split, 𝓛 Recode (across rivals)
**Parameters:** `<PANE_N>`, `<SESSION_ID>`

---

You are pane `<PANE_N>` in the Triage role for session `<SESSION_ID>`. Your job is to consolidate the proposed hypothesis slate from all Proposer panes.

**Step 1 — Read all proposed beads.**

```bash
br list --label=hypothesis --status=open --json | jq '.issues[]? | select((.description // "") | contains("origin: proposed") or contains("origin: anomaly_spawned"))'
```

For each, parse: `claim`, `mechanism`, `falsifier`, `expected_evidence`, `category`, `origin`, `confidence`.

**Step 2 — Apply ⊘ Level-Split: detect duplicates and false rivalries.**

For every pair of hypotheses, ask:

- Are they making the same claim about *different roles*? (e.g., one is about the program, other about the interpreter — they're not rivals)
- Are they making the same claim in *different words*? (true duplicates — merge)
- Do they actually disagree on observables? If not, they need representation change (Step 3) or merge (Step 4).

**Step 3 — Apply 𝓛 Recode: detect false rivalries from coordinate mismatch.**

For each pair, check: in what encoding do their predictions differ? If no encoding makes them differ, they're not rivals.

**Step 4 — Merge duplicates.**

For each duplicate pair, pick the better-worded one as winner. The loser becomes a refinement:

```bash
id_by_ref() {
  br list --all --json \
    | jq -r --arg ref "$1" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' \
    | head -1
}

loser_ref="<loser-H-ref>"    # e.g. H-004
winner_ref="<winner-H-ref>"  # e.g. H-001
loser_id="$(id_by_ref "$loser_ref")"
winner_id="$(id_by_ref "$winner_ref")"
[ -n "$loser_id" ] || { echo "No bead found for public ref: $loser_ref" >&2; exit 1; }
[ -n "$winner_id" ] || { echo "No bead found for public ref: $winner_ref" >&2; exit 1; }

old_desc="$(br show "$loser_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""')"
new_desc="$(
  printf '%s\n' "$old_desc" | awk '
    BEGIN { done = 0 }
    /^state:/ && !done { print "state: superseded"; done = 1; next }
    { print }
    END { if (!done) print "state: superseded" }
  '
)"
br update "$loser_id" --description="$(
  printf '%s\n' "$new_desc" | awk -v parent="$winner_ref" -v reason="duplicate of $winner_ref" '
    BEGIN { saw_parent = 0; saw_reason = 0 }
    /^parent:/ { if (!saw_parent) { print "parent: " parent; saw_parent = 1 } ; next }
    /^superseded_reason:/ { if (!saw_reason) { print "superseded_reason: " reason; saw_reason = 1 } ; next }
    { print }
    END {
      if (!saw_parent) print "parent: " parent
      if (!saw_reason) print "superseded_reason: " reason
    }
  '
)"
```

Optionally add a traversable dependency edge too: `br dep add "$loser_id" "$winner_id"`.

**Step 5 — Cluster and rank.**

Group remaining hypotheses by:

- `category` (mechanistic vs phenomenological vs boundary, etc.)
- `confidence` (high → low)
- `origin` (proposed vs third_alternative)

Rank by initial confidence × diversity-of-mechanism. Goal: 3–5 distinct, high-coverage hypotheses for Phase 4.

**Step 6 — Detect false binary.**

Count hypotheses with `origin:third_alternative`. If count is 0 OR if the surviving slate is structurally a 2-way choice, **trigger MO-03c-third-alternative.md** (the operator will dispatch this to you next).

A "structurally 2-way" slate is one where:

- The surviving hypotheses partition into exactly 2 mutually-exclusive camps
- A third alternative ("both are wrong; the real mechanism is Z") would be coherent

**Step 7 — Activate the surviving hypotheses.**

Every surviving hypothesis should transition from compact lifecycle `state: proposed` to `state: active` in its description. Keep the Beads issue status `open`; later scripts use `br list --status=open` plus the description `state:` field, and session-end closeout is the point where the Beads status changes.

```bash
for H in $(br list --label=hypothesis --status=open --json | jq -r '.issues[]? | select(((.description // "") | test("(^|\\n)state:[[:space:]]*proposed([[:space:]]|$)")) or (((.description // "") | test("(^|\\n)state:") | not))) | .id'); do
  desc="$(br show "$H" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""')"
  if printf '%s\n' "$desc" | grep -q '^state:'; then
    desc="$(printf '%s\n' "$desc" | awk 'BEGIN { done=0 } /^state:/ && !done { print "state: active"; done=1; next } { print }')"
  else
    desc="${desc}"$'\nstate: active'
  fi
  br update "$H" --description="$desc"
done
```

**Step 8 — Post triage report to the main session thread.**

```
Subject: [<SESSION_ID>] Phase 3 triage complete
Body:
  Active slate (N=X):
  - H-001 (cat=mechanistic, conf=high, origin=proposed): <claim summary>
  - H-002 (cat=phenomenological, conf=medium, origin=proposed): <claim summary>
  - H-003 (cat=boundary, conf=low, origin=third_alternative): <claim summary>

  Merged: H-004 → H-001 (duplicate); H-006 → H-002 (refinement)

  False-binary check: <pass | fail — trigger MO-03c>

  Ready for Phase 4 dispatch.
```

**Step 9 — Run audit.**

```bash
./scripts/audit-bead-invariants.sh --check=phase3_exit
```

Report any violations to the operator immediately.

---

**Anti-patterns to avoid:**

- ✗ Merging hypotheses that are actually different `categories` of claim (program vs interpreter). Apply ⊘ Level-Split first.
- ✗ Allowing the slate to grow >7. The point of triage is compression.
- ✗ Filing your own *new* hypotheses during triage. That's Phase 3a, not Phase 3b. If you spot a gap, note it and let MO-03c fill it explicitly.

**Ship-or-Surface SLA:** within 30 minutes, post the triage report.
