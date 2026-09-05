# MO-quickie-pilot.md — Cheap Pilot Experiment to De-Risk a Flagship Investigation

**Phase:** 4 (early in a round)
**Operators activated:** ⤴ "Quickie", ↑ Amplify, ⌂ Materialize
**Parameters:** `<PANE_N>`, `<H_ID>` (the hypothesis to de-risk), `<SESSION_ID>`

---

Per Brenner §99 ("So what I said, 'Well, I'll do a quickie'"), a quickie is a *cheap pilot* that, in <30 minutes, would discriminate the most likely failure mode of a flagship investigation.

When in Phase 4 you're about to start a 3-hour investigation on `<H_ID>`, ask first: *what's the cheapest experiment that would tell me this investigation is doomed?* Run that experiment first.

---

**Step 1 — Identify the most likely doom.**

Read `<H_ID>.falsifier:` and `<H_ID>.expected_evidence:`. Ask:

- What's the cheapest way the falsifier could fire on first contact with the corpus?
- What's the most likely reason the expected evidence won't be found?
- What's the most fragile assumption the hypothesis depends on?

The doom is the answer to the most worrisome of those.

**Step 2 — Design the quickie.**

The quickie satisfies:

- **Wall time:** ≤30 min from dispatch to first result
- **Decisiveness:** if it returns negative, you'd kill `<H_ID>` immediately; if positive, you'd proceed with the flagship investigation
- **Cheap proxy:** apply ⟂ Object-Transpose — pick the smallest sample / shallowest dive that still gives a yes/no answer
- **High contrast:** apply ↑ Amplify — pick a regime where the answer is binary or ≥10×

Examples:
- For a code-investigation H "the auth subsystem is the bottleneck": grep for the auth call counts in 30 minutes of profiling output. If counts are <1% of total, doom (auth isn't the bottleneck) — kill.
- For a corpus-distillation H "the methodology distills cleanly into 5 axioms": skim the 3 most-cited sources and try to extract 5 axioms in 30 min. If you can't even rough-cut 5, the methodology probably has more axioms than expected.
- For a design-space H "X dominates Y on workload W": find a single published benchmark that compares X vs Y on W-class workloads. If found, decisive; if not after 30 min of search, the comparison literature is sparse and a flagship benchmark is needed anyway.

**Step 3 — File the quickie as a `T-*` test bead with `cost_estimate:30min`.**

```bash
t_ref="T-NNN"  # public ref; replace NNN before running
t_id="$(br create "$t_ref: Quickie pilot for <H_ID>" \
  --type=task --labels=test --priority=1 \
  --slug="$t_ref" --external-ref="$t_ref" --silent \
  --description="$(cat <<'EOF'
discriminates_between: [<H_ID>, ¬<H_ID>]
potency_check: <chastity-vs-impotence — what distinguishes "we couldn't find it" from "it's not there">
expected_signal: <yes/no, or ≥10× threshold>
cost_estimate: 30min
quickie_for: <H_ID>
session: <SESSION_ID>

## Detail
<the doom we're checking>

## Procedure
<3-line description of the quickie>
EOF
)")"
printf 'Created %s as br id %s\n' "$t_ref" "$t_id"
```

**Step 4 — Run the quickie.**

In ≤30 min, complete the experiment. Output: a single yes/no result, OR an "inconclusive" with specific reason.

**Step 5 — File a result EV.**

```bash
ev_ref="EV-NNN"  # public ref; replace NNN before running
ev_id="$(br create "$ev_ref: Quickie result for $t_ref" \
  --type=task --labels=evidence --priority=2 \
  --slug="$ev_ref" --external-ref="$ev_ref" --silent \
  --description="$(cat <<'EOF'
type: experiment
source: <quickie methodology + result location>
relevance: Quickie pilot result for <H_ID>
imported_at: <ISO-8601>
imported_by: <PANE_N>
verified: true
quickie_for: <T-id>
result: matched | violated | inconclusive
session: <SESSION_ID>

## Detail
<the result, with verbatim observations or counts>
EOF
)")"
printf 'Created %s as br id %s\n' "$ev_ref" "$ev_id"
```

**Step 6 — Decide.**

Based on the quickie result:

- **Doom confirmed (falsifier fired):** Run `MO-falsifier-fired.md` immediately. Don't run the flagship investigation; the H is dead.
- **Doom rejected (expected evidence found in shallow check):** Proceed with the flagship investigation, more confident.
- **Inconclusive:** The quickie wasn't decisive. Either redesign and try again (different proxy), OR proceed with flagship but flag the persistent uncertainty.

**Step 7 — Post outcome to per-H thread.**

```
Subject: [<SESSION_ID>-<H_ID>] Quickie result: <doom-confirmed | rejected | inconclusive>

T-NNN ran in ~<minutes>min. Result: <one sentence>.

Verdict: <H_ID> = <killed via MO-falsifier-fired.md | proceed with flagship | redesign quickie>
```

---

**Anti-patterns:**

- ✗ Run a "quickie" that takes 2+ hours. That's a flagship, not a quickie. By definition ≤30 min.
- ✗ Run a quickie that doesn't actually discriminate. If the result doesn't change your next move, the quickie was wasted.
- ✗ Skip the quickie because "I think the flagship investigation will be fine." Brenner's whole point is most flagship investigations doom early; the quickie surfaces it.
- ✗ Run a quickie without the potency check (`chastity vs impotence`). A negative result without potency is uninformative.

**Ship-or-Surface SLA:** ≤30 min for the quickie execution + ≤10 min for verdict posting. If you can't design a 30-min quickie, that's evidence the flagship investigation is itself ill-defined — surface to operator.
