# MO-falsifier-fired.md — Formal Kill Protocol When a Falsifier Fires

**Phase:** 4 or 5 (the moment a falsifier-firing event is identified)
**Operators activated:** † Theory-Kill, ✂ Exclusion-Test (verification)
**Parameters:** `<H_ID>` (the hypothesis whose falsifier fired), `<EV_OR_T_ID>` (the EV or T that fired it), `<PANE_N>` (the pane that observed the firing), `<SESSION_ID>`

---

You are pane `<PANE_N>` and you have observed a falsifier-firing event. This MO formalizes the kill so the audit trail is clean.

Per Brenner §229 ("when they go ugly, kill them") — there is no grace period. A falsifier-firing event leads to immediate state flip. Don't soften, don't equivocate, don't "let's see if more evidence comes in."

But also: per ✂ discipline, *verify* the falsifier actually fired before flipping state. Some "falsifier-fired" claims turn out to be misreadings.

---

**Step 1 — Re-read both `<H_ID>` and `<EV_OR_T_ID>`.**

```bash
h_ref="<H_ID>"
firing_ref="<EV_OR_T_ID>"
pane_n="<PANE_N>"
h_id="$(br list --all --json | jq -r --arg ref "$h_ref" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' | head -1)"
firing_id="$(br list --all --json | jq -r --arg ref "$firing_ref" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' | head -1)"
[ -n "$h_id" ] || { echo "No bead found for public ref: $h_ref" >&2; exit 1; }
[ -n "$firing_id" ] || { echo "No bead found for public ref: $firing_ref" >&2; exit 1; }
br show "$h_id" --json
br show "$firing_id" --json
```

Note `<H_ID>.falsifier:` text and the cited content of `<EV_OR_T_ID>`.

**Step 2 — Verify the firing.**

Apply this rubric:

1. Does the falsifier text describe an *observable*? (Not "if math broke" — must be observable.)
2. Does `<EV_OR_T_ID>` contain a verbatim citation of that observable from a credible source?
3. Is the citation in the right *coordinate system* (encoding) as the falsifier? (E.g., if falsifier is about latency at 100K events/sec, EV must be a benchmark at that scale.)
4. Is there a plausible alternative interpretation of `<EV_OR_T_ID>` that doesn't fire the falsifier?

If (1)-(3) pass and (4) is "no plausible alternative" → falsifier fired. Proceed to Step 3.

If any check fails → falsifier did NOT fire. Document as a near-miss in the per-H thread; do NOT flip state. Rerun investigation.

**Step 3 — Flip H state to refuted.**

Keep the Beads issue status `open` until session closeout. Downstream phase
queries use `br list --status=open` plus the description-level `state:` field;
closing the bead here would hide the refuted H from distillation, audit, and
handback steps.

```bash
old_desc="$(br show "$h_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""')"
new_desc="$(
  printf '%s\n' "$old_desc" | awk '
    BEGIN { replaced = 0 }
    /^state:/ { print "state: refuted"; replaced = 1; next }
    { print }
    END { if (!replaced) print "state: refuted" }
  '
)"
refuted_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
br update "$h_id" --description="$(
  printf '%s\n' "$new_desc" | awk -v firing="$firing_ref" -v ts="$refuted_at" -v pane="$pane_n" '
    BEGIN { saw_refuted_by = 0; saw_refuted_at = 0; saw_refuted_by_pane = 0 }
    /^refuted_by:/ { if (!saw_refuted_by) { print "refuted_by: " firing; saw_refuted_by = 1 } ; next }
    /^refuted_at:/ { if (!saw_refuted_at) { print "refuted_at: " ts; saw_refuted_at = 1 } ; next }
    /^refuted_by_pane:/ { if (!saw_refuted_by_pane) { print "refuted_by_pane: " pane; saw_refuted_by_pane = 1 } ; next }
    { print }
    END {
      if (!saw_refuted_by) print "refuted_by: " firing
      if (!saw_refuted_at) print "refuted_at: " ts
      if (!saw_refuted_by_pane) print "refuted_by_pane: " pane
    }
  '
)"
```

(Adjust the bash heredoc to your shell's quoting rules; the key invariant is `state: refuted` AND `refuted_by` is non-empty.)

**Step 4 — Post the kill announcement to the per-H thread.**

```
Subject: [<SESSION_ID>-<H_ID>] FALSIFIER FIRED — <H_ID> killed

## Falsifier text (verbatim from H bead)
<falsifier>

## Firing observation
<EV_OR_T_ID> at <source>:line<N>
Verbatim excerpt: "<verbatim quote from EV>"

## Verification rubric
- (1) Observable? <yes — observable was X>
- (2) Verbatim cite? <yes — from <source>>
- (3) Same coordinate system? <yes — both about Y>
- (4) Alternative interpretation? <no — <reasoning>>

All checks passed. <H_ID>.state flipped to refuted; refuted_by=<EV_OR_T_ID>.

Next:
- If <H_ID> had child Hs (refinements), they may also be affected — operator should review.
- If <H_ID> was a debate champion in an active DEBATE, that debate is settled in favor of the rival.
- The kill does NOT propagate to other Hs; verify each H's falsifier independently.
```

**Step 5 — Update related artifacts.**

If `<H_ID>` was being championed in any active `DEBATE-*`, update that debate:

```bash
br list --label=debate --json \
  | jq -r --arg h "$h_ref" '.issues[]? | select((.description // "") | test("pair:[^\\n]*\\b" + $h + "\\b")) | .id' \
  | while IFS= read -r debate_id; do
      [ -n "$debate_id" ] || continue
      debate_desc="$(br show "$debate_id" --json | jq -r 'if type=="array" then (.[0] // {}) else . end | .description // ""')"
      br update "$debate_id" --description="$(
        printf '%s\n' "$debate_desc"
        printf 'outcome: %s = refuted\n' "$h_ref"
        printf 'falsifier_fired: %s\n' "$firing_ref"
      )"
      br update "$debate_id" --status=closed
    done
```

**Step 6 — Re-render the evidence pack.**

```bash
./scripts/render-evidence-pack.sh "$h_ref"
```

The evidence pack now shows the kill state with refuted_by trail.

**Step 7 — Notify Adjudicator (if Phase 5).**

If we're in Phase 5 and the kill happened during a debate, the Adjudicator pane needs to formally close out the debate per `MO-05b-adjudicate.md`. File a notification in the `RS-...-ADJUDICATE` consolidated thread.

---

**Anti-patterns:**

- ✗ Kill without verification — the rubric is mandatory; soft-kills are equivocation
- ✗ Kill on the basis of a critique (`C-*`) without an underlying `EV-*`. Critiques are arguments; only evidence fires falsifiers.
- ✗ Forget `refuted_by` field. Hard invariant.
- ✗ Skip the per-H thread announcement. Other panes need to know the H is dead so they don't continue investigating it.
- ✗ Propagate the kill to "related" Hs without independent verification of each falsifier. Each H stands alone.

**Ship-or-Surface SLA:** within 15 min of observing the firing event, complete steps 1-7. The kill is high-priority — don't let it sit while continuing other work.
