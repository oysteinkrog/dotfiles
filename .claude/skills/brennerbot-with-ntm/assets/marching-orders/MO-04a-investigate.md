# MO-04a-investigate.md — Fill Evidence Pack for One Hypothesis

**Phase:** 4
**Operators activated:** ⟂ Object-Transpose, ↑ Amplify, ⌂ Materialize, ⊞ Scale-Check, ≡ Invariant-Extract, ΔE Exception-Quarantine, 🔧 DIY
**Parameters:** `<PANE_N>`, `<H_ID>`, `<SESSION_ID>`

---

You are pane `<PANE_N>` in the Investigator role. Your assigned hypothesis is `<H_ID>`. Your job: fill the evidence pack.

**Step 1 — Read the hypothesis.**

```bash
h_ref="<H_ID>"
h_id="$(br list --all --json | jq -r --arg ref "$h_ref" '.issues[]? | select(.id == $ref or .external_ref == $ref or ((.title // "") | startswith($ref + ":"))) | .id' | head -1)"
[ -n "$h_id" ] || { echo "No bead found for public ref: $h_ref" >&2; exit 1; }
br show "$h_id" --json
```

Note: `claim`, `mechanism`, `falsifier`, `expected_evidence`, `category`.

**Step 2 — Materialize ⌂.**

Your *first* output (within 30 minutes) is a verbatim citation that confirms or denies `expected_evidence:`. Reach for the cheapest source first.

If positive (expected_evidence found): file `EV-NNN` as `supports[<H_ID>]`.
If negative (not found): note in `evidence/packs/EV-pack-<H_ID>.md § Materialization log`.

**Step 3 — Choose proxy (⟂).**

If the natural surface (full corpus / full codebase / full benchmark) is too expensive, list 3-5 proxy surfaces and pick the cheapest with adequate signal. Record your choice in the pack:

```markdown
## Methodology
### Proxy choice (⟂ Object-Transpose)
Considered:
- Full corpus search (cost: 3h, signal: high)
- Section §X-§Y subset (cost: 30min, signal: high)
- Single canonical paper (cost: 10min, signal: medium)

Chosen: Section §X-§Y. Rationale: signal-cost ratio dominates.
```

**Step 4 — Amplify ↑.**

Prefer evidence sources with high contrast: yes/no readouts, presence/absence, ≥10× magnitude differences. If you find yourself measuring continuous values, find a threshold where the data goes binary.

**Step 5 — Probe the falsifier ✂.**

Before only filing supportive evidence, probe the falsifier. Try to find evidence that would *kill* the hypothesis. If no such evidence exists in the corpus, that's a finding — record in `## Falsifier probe` section.

A round of investigation that produces zero attempted falsifiers is anti-Brenner (per F-403). Don't be that round.

**Step 6 — Extract invariants ≡.**

For each evidence record, capture `key_findings:` — what holds regardless of detail? These become the building blocks of Phase 6 distillation.

**Step 7 — Scale-check ⊞.**

For any load-bearing claim that depends on physical/computational/economic scale (memory, bandwidth, latency, cost, throughput): file an `assumption.type:scale_physics` bead with a `calculation:` block.

```bash
a_ref="A-NNN"  # public ref; replace NNN before running
a_id="$(br create "$a_ref: <claim being scale-checked>" \
  --type=task --labels=assumption --priority=2 \
  --slug="$a_ref" --external-ref="$a_ref" --silent \
  --description="$(cat <<'EOF'
statement: <claim>
type: scale_physics
load_description: <what fails if this is false>
affects: [<H_ID>]
calculation: |
  <show the math: bandwidth = ... ; latency = ... ; assumed bound holds because ...>
session: <SESSION_ID>
EOF
)")"
printf 'Created %s as br id %s\n' "$a_ref" "$a_id"
```

**Step 8 — Quarantine anomalies ΔE.**

If you find observations that don't fit ANY active hypothesis, file as `anomaly` rather than silently fitting them into `<H_ID>`:

```bash
an_ref="AN-NNN"  # public ref; replace NNN before running
an_id="$(br create "$an_ref: <observation>" \
  --type=task --labels=anomaly --priority=2 \
  --slug="$an_ref" --external-ref="$an_ref" --silent \
  --description="$(cat <<'EOF'
observation: <what was seen>
conflicts_with: <list of H IDs it conflicts with, or 'none'>
source_type: experiment | literature | discussion | calculation
session: <SESSION_ID>
EOF
)")"
printf 'Created %s as br id %s\n' "$an_ref" "$an_id"
```

If 2+ anomalies share a feature, propose a new H with `origin:anomaly_spawned` (file via Triage thread or operator).

**Step 9 — File evidence beads.**

Every claim in your evidence pack needs a corresponding `EV-*` bead:

```bash
ev_ref="EV-NNN"  # public ref; replace NNN before running
ev_id="$(br create "$ev_ref: <one-line claim>" \
  --type=task --labels=evidence --priority=2 \
  --slug="$ev_ref" --external-ref="$ev_ref" --silent \
  --description="$(cat <<'EOF'
type: paper | experiment | observation | code_artifact | benchmark
source: <URL | file path:line | DOI>
relevance: <one sentence>
imported_at: <ISO-8601>
imported_by: <PANE_N>
verified: false
supports: [<H_ID>]
refutes: []
informs: []
session: <SESSION_ID>
key_findings:
  - <invariant 1>
  - <invariant 2>

## Excerpts
- E1 (verbatim): "<exact quote>" (location: <section/line>)
EOF
)")"
printf 'Created %s as br id %s\n' "$ev_ref" "$ev_id"
```

**Step 10 — Render evidence pack.**

```bash
./scripts/render-evidence-pack.sh "$h_ref"
```

This script reads all `EV-*` beads with `supports[<H_ID>]` or `refutes[<H_ID>]` and produces the markdown pack.

**Step 11 — DIY 🔧 if blocked.**

If you're blocked waiting for tooling: write a quick bash/python script in `deliverables/scripts/` that approximates what you need. The script doesn't have to be production-grade; it has to *let you start the loop*.

**Step 12 — Post round summary to per-H thread.**

```
Subject: [<SESSION_ID>-<H_ID>] Investigator round <N> complete
Body:
  EVs filed: <count>
    - <count> supports
    - <count> refutes (target ≥1 per round)
  Falsifier probe: <fired | not fired | not probed yet>
  Operators applied: ⟂ <proxy choice>, ↑ <amplification>, ⌂ <materialization result>, ⊞ <scale check>
  Anomalies: <count, with cluster note if applicable>
  Pack rendered: evidence/packs/EV-pack-<H_ID>.md
  Next action: <specific next investigation step>
```

---

**Anti-patterns to avoid:**

- ✗ Filing only `supports:` evidence (per F-403). Your job includes probing the falsifier.
- ✗ Skipping the proxy choice and grinding through the most expensive surface first (per ⟂).
- ✗ Citing evidence without a verbatim excerpt. Future readers (Devil's-Advocate, Adjudicator) need the text.
- ✗ Writing prose instead of beads. Every meaningful claim is a bead. Prose belongs in the evidence pack file, with bead links.

**Ship-or-Surface SLA:** within 60 minutes, file ≥1 `EV-*` AND post the round summary OR surface a specific blocker.
