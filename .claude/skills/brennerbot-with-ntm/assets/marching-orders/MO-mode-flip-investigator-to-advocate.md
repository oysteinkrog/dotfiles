# MO-mode-flip-investigator-to-advocate.md — Flip a Confirmation-Biased Investigator

**Phase:** 4
**Operators activated:** ✂ Exclusion-Test, † Theory-Kill (preparation)
**Parameters:** `<PANE_N>`, `<H_ID>`, `<SESSION_ID>`, `<WORKSPACE_PATH>`

---

You were assigned `<H_ID>` as Investigator. The operator has detected confirmation-only bias in your evidence pack (per F-403): all `EV-*.supports[]`, none `refutes[]`. Per AP-M03, this is anti-Brenner.

**Your role flips: you are now the Devil's-Advocate against `<H_ID>`.**

For shell snippets, set the dispatch parameters once:

```bash
pane_n="<PANE_N>"
h_ref="<H_ID>"
session_id="<SESSION_ID>"
workspace_path="<WORKSPACE_PATH>"
```

---

**Step 1 — Acknowledge.**

Reply to the per-H thread:

```
[<SESSION_ID>-<H_ID>] Pane <PANE_N>: role flipped Investigator → Devil's-Advocate. Will probe falsifier this round.
```

**Step 2 — Read the pack you wrote.**

```bash
cat "$workspace_path/evidence/packs/EV-pack-$h_ref.md"
```

For each `EV-*` you filed as supporting:

- Could the cited source be misread?
- Is the cited excerpt genuinely entailing the claim, or only correlating?
- Is there a stronger alternative interpretation?

**Step 3 — Probe the falsifier (this is now your primary task).**

Read `<H_ID>.falsifier`. Find evidence — in the corpus, in the codebase, anywhere — that *fires* the falsifier.

If the falsifier doesn't fire under any search you can do in 30 minutes, you've genuinely confirmed the H. File `EV-NNN` documenting the negative search:

```bash
ev_ref="EV-NNN"  # public ref; replace NNN before running
ev_id="$(br create "$ev_ref: Falsifier of $h_ref not fired under search X" \
  --type=task --labels=evidence --priority=2 \
  --slug="$ev_ref" --external-ref="$ev_ref" --silent \
  --description="$(cat <<EOF
type: observation
source: <search log / negative-search description>
relevance: Phase 4 falsifier probe — negative result
imported_by: $pane_n (mode-flipped to advocate)
verified: true
supports: [$h_ref]
refutes: []
session: $session_id

## Detail
The falsifier of $h_ref states: "<falsifier>"
I attempted the following searches:
1. <search 1, source, result>
2. <search 2, source, result>
3. <search 3, source, result>
None returned evidence matching the falsifier. This is a negative result that strengthens (but does not confirm) $h_ref.
EOF
)")"
printf 'Created %s as br id %s\n' "$ev_ref" "$ev_id"
```

If the falsifier *does* fire under your search, file as a refuting EV and a critique:

```bash
ev_ref="EV-NNN"  # public ref; replace NNN before running
ev_id="$(br create "$ev_ref: Falsifier of $h_ref fired" \
  --type=task --labels=evidence --priority=1 \
  --slug="$ev_ref" --external-ref="$ev_ref" --silent \
  --description="...")"
c_ref="C-NNN"  # public ref; replace NNN before running
c_id="$(br create "$c_ref: $h_ref falsifier fired by $ev_ref" \
  --type=task --labels=critique --priority=1 \
  --slug="$c_ref" --external-ref="$c_ref" --silent \
  --description="severity: critical; ...")"
printf 'Created %s as br id %s\n' "$ev_ref" "$ev_id"
printf 'Created %s as br id %s\n' "$c_ref" "$c_id"
```

**Step 4 — Re-read the assumption ledger.**

```bash
br list --label=assumption --json | jq --arg h "$h_ref" '
  def affects($h):
    ((try ((.description // "") | capture("(^|\\n)affects:[[:space:]]*\\[(?<ids>[^\\]]*)\\]").ids) catch "")
     | split(",")
     | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
     | index($h)) != null;
  .issues[]? | select(affects($h))
'
```

For each assumption, ask:
- Is `type:scale_physics` calculation correct?
- Is `status:unchecked` survivable, or is it Don't-Worry technical debt?

File a critique on any weak assumption:

```bash
c_ref="C-NNN"  # public ref; replace NNN before running
c_id="$(br create "$c_ref: Assumption A-NNN underpinning $h_ref is weak" \
  --type=task --labels=critique --priority=2 \
  --slug="$c_ref" --external-ref="$c_ref" --silent \
  --description="...")"
printf 'Created %s as br id %s\n' "$c_ref" "$c_id"
```

**Step 5 — Post the flip-round summary.**

```
Subject: [<SESSION_ID>-<H_ID>] Pane <PANE_N> flip-round complete
Body:
  Role: now Devil's-Advocate
  Falsifier probe: <fired | not fired>
  EVs filed (refutes): <count>
  Critiques filed: <count>
  Recommended: <continue investigating | escalate to Phase 5 debate | accept H as confirmed>
```

---

**Anti-patterns to avoid:**

- ✗ Defending the H you previously investigated. The flip is real — you're now arguing against your earlier work.
- ✗ Filing a "supports[]" EV during this round. The flip means: this round, you only file `refutes[]` or `informs[]` (negative-search documentation).
- ✗ Pretending the flip didn't happen and continuing to file confirmations. The operator detected the bias; the flip is the recovery.

**Ship-or-Surface SLA:** within 30 minutes, post the flip-round summary with at least one filed bead (refutes EV, critique, or negative-search EV).
