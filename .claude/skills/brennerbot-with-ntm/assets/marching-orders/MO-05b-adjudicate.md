# MO-05b-adjudicate.md — Adjudicate Debate; Flip H State

**Phase:** 5
**Operators activated:** † Theory-Kill, ✂ Exclusion-Test (re-verify)
**Parameters:** `<PANE_N>`, `<DEBATE_ID>`, `<SESSION_ID>`

---

You are pane `<PANE_N>` in the Adjudicator role. Your task: read `<DEBATE_ID>`, derive the two H ids from its metadata, and rule.

`<DEBATE_ID>` is the actual generated `br` issue ID. The human-readable
`DEBATE-NNN` label is stored as `external_ref` / `debate_ref` in the bead.

**Constraint:** you MUST NOT be a champion of either hypothesis in this debate. Per ROSTER-PLANS.md role rotation rule, the Adjudicator never adjudicates an H they've championed.

---

**Step 1 — Read the debate thread.**

```bash
debate_id="<DEBATE_ID>"
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

debate_json="$(br show "$debate_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end')"
debate_desc="$(printf '%s\n' "$debate_json" | jq -r '.description // ""')"
printf '%s\n' "$debate_desc"

pair_line="$(printf '%s\n' "$debate_desc" | sed -n 's/^pair:[[:space:]]*//p' | head -1)"
h_i_ref="${pair_line%% vs *}"
h_j_ref="${pair_line#* vs }"
if [ -z "$pair_line" ] || [ "$h_i_ref" = "$pair_line" ] || [ -z "$h_i_ref" ] || [ -z "$h_j_ref" ]; then
  echo "Cannot parse debate pair from $debate_id; expected description line: pair: H-A vs H-B" >&2
  exit 1
fi
h_i_id="$(require_id_by_ref "$h_i_ref")"
h_j_id="$(require_id_by_ref "$h_j_ref")"

thread_id="$(printf '%s\n' "$debate_desc" | sed -n 's/^mail_thread:[[:space:]]*//p' | head -1)"
ntm mail thread "${thread_id:-<SESSION_ID>-DEBATE-${h_i_ref}-vs-${h_j_ref}}"
```

Read all 3 rounds (or whatever rounds occurred).

**Step 2 — Read both H beads + their evidence packs.**

```bash
br show "$h_i_id" --json
br show "$h_j_id" --json
cat "evidence/packs/EV-pack-${h_i_ref}.md"
cat "evidence/packs/EV-pack-${h_j_ref}.md"
```

**Step 3 — Re-verify falsifiers.**

For each H:

- Did the debate fire the falsifier? (i.e., is there an `EV-*` cited in the debate that satisfies the falsifier text)
- If yes → kill the H.
- If no, but the falsifier was attempted and not fired → maintain or confirm.
- If the falsifier was never probed → flag in adjudication; do not confirm.

**Step 4 — Check for level confusion.**

Per ⊘ Level-Split: did Phase 3 triage miss a level confusion that this debate surfaced? E.g., are the two Hs actually about different roles (program vs interpreter)?

If yes: the debate is a false rivalry. Outcome: both Hs survive (`active`); refile a level-split note in `INVEST-coord` thread.

**Step 5 — Apply ∿ Dephase.**

Did the debate reproduce a consensus prior on autopilot? If `h_i` is what a domain expert would name first AND `h_j` is the productive-ignorance pane's contrarian alternative AND the debate flipped against `h_j`, ask: was `h_j` killed on rhetoric or on falsifier? If rhetoric, re-open.

**Step 6 — Decide.**

Possible outcomes:

| Verdict | Trigger |
|---------|---------|
| `first H confirmed; second H refuted` | second H's falsifier fired AND first H's did not |
| `second H confirmed; first H refuted` | first H's falsifier fired AND second H's did not |
| `Both refuted` | Both falsifiers fired (the third alternative may now be ascendant) |
| `Both survive, first H stronger` | Neither falsifier fired; first H has more independent supporting EVs |
| `Both survive, second H stronger` | mirror |
| `Both survive, equal` | rare; usually means triage missed a level split |
| `Superseded by H-NNN` | Debate surfaced a third alternative; both old Hs become children |
| `Deferred` | Cannot decide on current evidence; specific EV needed |

**Step 7 — Update beads.**

```bash
br update "$h_i_id" --description="$(... add fields ...)"
# Add: state: <confirmed|refuted|superseded|deferred>
# Add: refuted_by: <EV-NNN> (if refuted)
# Add: adjudication: <DEBATE_ID>
# Add: parent: <H-NNN> (if superseded — the replacement H; canonical field name per BEADS-SCHEMA.md)

br update "$h_j_id" --description="$(... add fields ...)"
# Add the same adjudication fields for the second H.
# If one H is confirmed and the other is refuted, update both states in the
# same operator pass so the ledger cannot show a half-settled debate.

br update "$debate_id" --description="$(... add fields ...)"
# Add: state: settled
# Add: adjudication: "<verdict>"
# Add: falsifier_fired: <EV-NNN if any>
```

**Step 8 — Post adjudication to debate thread.**

```markdown
**Adjudicator:** <PANE_N>  **Debate:** <DEBATE_ID>  **Settled:** <TIMESTAMP_UTC>

## Outcome
first H = <confirmed | refuted | superseded | deferred>
second H = <confirmed | refuted | superseded | deferred>

## Reasoning
<paragraph citing specific EV-NNN that fired falsifiers or supported claims>

## Falsifier event (if any)
- first H falsifier was: "<verbatim falsifier>"
- Observed via EV-NNN (<source>): "<verbatim quote>"
- Conclusion: first H killed.

## Bead state changes
- first H `state: <X>`
- second H `state: <Y>`
- <DEBATE_ID> `state: settled`
```

**Step 9 — Post adjudication summary to consolidated `RS-...-ADJUDICATE` thread.**

Brief 3-sentence summary; cross-link to the per-debate thread.

**Step 10 — Apply † Theory-Kill discipline.**

If the verdict is "refuted" but the kill feels rhetorical (no falsifier-fired EV, just "less convincing"), DON'T flip to `refuted`. Use `deferred` or lower `confidence:`; do not invent a new lifecycle state. Per AP-M05 and F-501, killing on rhetoric is anti-Brenner.

---

**Anti-patterns to avoid:**

- ✗ Compromise verdicts ("both win") without level-split justification.
- ✗ Picking the model-family-mate's H as winner (per F-502). If you find yourself doing this, request rotation.
- ✗ Ruling without citing specific `EV-*` (per AP-M05).
- ✗ Adjudicating on rhetoric. If the debate didn't fire a falsifier, the verdict is "survives" or "deferred", not "refuted".
- ✗ Skipping the consolidated `ADJUDICATE` thread post. Cross-debate consistency depends on it.

**Ship-or-Surface SLA:** within 45 minutes, post the adjudication.
