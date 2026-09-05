# MO-05a-cross-exam.md — Pairwise Adversarial Debate

**Phase:** 5
**Operators activated:** 🤝 GAN, ✂ Exclusion-Test, † Theory-Kill (preparation)
**Parameters:** `<PANE_N>`, `<H_I>` (the H you champion), `<H_J>` (the rival), `<SESSION_ID>`, `<ROUND>` (1, 2, or 3)

---

You are pane `<PANE_N>`, championing `<H_I>` in a structured debate against the pane championing `<H_J>`. Round `<ROUND>` of max 3.

The thread is `<SESSION_ID>-DEBATE-<H_I>-vs-<H_J>`.

---

**Step 1 — Read both hypotheses + their evidence packs.**

```bash
h_i_ref="<H_I>"
h_j_ref="<H_J>"
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
h_i_id="$(require_id_by_ref "$h_i_ref")"
h_j_id="$(require_id_by_ref "$h_j_ref")"
br show "$h_i_id" --json
br show "$h_j_id" --json
cat "evidence/packs/EV-pack-${h_i_ref}.md"
cat "evidence/packs/EV-pack-${h_j_ref}.md"
```

**Step 2 — Apply the round-specific format.**

Per [AGENT-MAIL-CONVENTIONS.md § Pairwise debate thread](../../references/AGENT-MAIL-CONVENTIONS.md#pairwise-debate-thread):

| Round | Your post |
|-------|-----------|
| 1 | `[opening]` Your case for <H_I> in ≤300 words. Cite ≥2 EV from your pack. State the falsifier you DON'T expect to fire. |
| 2 | `[rebuttal]` Attack <H_J>'s opening. Cite ≥2 EV that contradict <H_J>'s claim. Specifically address why <H_J>'s falsifier should fire on the available evidence. |
| 3 | `[counter-rebuttal]` Defend <H_I> against <H_J>'s rebuttal. Concede where conceded; counter where countered. Final position. |

**Round gate:** before posting Round 2, confirm the opposing champion's Round 1
opening exists in the thread. Before posting Round 3, confirm the opposing
champion's Round 2 rebuttal exists. If the needed prior post is absent, do not
invent the missing argument; surface `waiting_for_round_<N>` in your pane and
stop until the operator re-dispatches or the missing post appears.

**Step 3 — Mandatory citations.**

Every post in this thread MUST contain a `## Evidence cited` block with ≥1 `EV-NNN`. Posts without citations are auto-rejected by the Adjudicator. Per AP-M05.

**Step 4 — Apply 🤝 GAN discipline.**

You are the Generator for `<H_I>`; the opposing pane is the Discriminator. Per Brenner §66 ("never restrain yourself"), be specific, forthright, and concrete. Don't waste rounds on rhetoric. Don't waste rounds on definitional disputes — those should have been resolved at Phase 3 triage.

**Step 5 — Specifically attack falsifiers.**

Per ✂, the way to win this debate is to fire a falsifier. Either:

- **Find evidence that fires <H_J>'s falsifier** — you win this round.
- **Show that <H_I>'s falsifier did NOT fire under attempted searches** — you maintain.
- **Show that <H_J>'s `expected_evidence` is unobserved** — you weaken <H_J>'s prior.

**Step 6 — Post format.**

```markdown
**Pane:** <PANE_N>  **Champion of:** <H_I>  **Round:** <ROUND>  **Position:** [opening | rebuttal | counter-rebuttal]

## Argument
<your case in ≤300 words>

## Evidence cited
- EV-NNN: <one-line claim + verbatim excerpt>
- EV-NNN: <...>

## Falsifier status
- <H_I>'s falsifier ("<text>"): probed; did not fire (searched <X>; outcome <Y>)
- <H_J>'s falsifier ("<text>"): I claim it fires under EV-NNN
```

**Step 7 — After Round 3, stand silent.**

After your Round 3 post, do NOT post further to this thread. The Adjudicator (different pane, rotating role) will read both sides and rule per `MO-05b-adjudicate.md`.

---

**Anti-patterns to avoid:**

- ✗ More than 300 words per post. The Adjudicator skims; brevity wins.
- ✗ Personal disagreement with the opposing pane. Stay focused on the hypothesis.
- ✗ Citing EVs not in the pack. If you bring new evidence, file it as a new `EV-*` first, then cite it.
- ✗ Round 4. Hard cap is 3.
- ✗ Conceding everything. If your hypothesis is dead, file it explicitly: "I withdraw <H_I>; the falsifier appears to fire under EV-NNN." That's a kill, not a concession.

**Ship-or-Surface SLA:** within 30 minutes per round, post your debate move OR concede explicitly.
