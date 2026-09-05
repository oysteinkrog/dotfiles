# MO-03c-third-alternative.md — Force-Inject "Both Could Be Wrong"

**Phase:** 3
**Operators activated:** ⊘ Level-Split, ◊ Paradox-Hunt
**Parameters:** `<PANE_N>`, `<SESSION_ID>`

---

You are pane `<PANE_N>`. The Phase 3 triage detected a false-binary slate. If the operator named a specific pair in the dispatch context, use that pair. Otherwise, read the active hypothesis slate and pick the closest binary pair yourself.

Per Brenner §103 ("Both could be wrong"), every hypothesis slate must include an explicit third alternative. Your job is to inject one.

**Step 1 — Read the binary.**

Read both selected H beads in full. Assign local names `h_a` and `h_b` in your notes. Identify:

- What axis are they implicitly disagreeing on?
- What assumption are they BOTH making (their shared blind spot)?
- What would a third alternative look like — one that rejects both?

**Step 2 — Generate ≥3 third-alternative candidates.**

Apply ⊘ Level-Split: are H_a and H_b actually about the same level? Maybe both are wrong because they conflate program and interpreter. Apply ◊ Paradox-Hunt: is there a paradox the binary doesn't address — a third fact that neither H_a nor H_b explains?

For each candidate third alternative:

- It must reject the shared assumption of H_a and H_b
- It must have its own `falsifier:` and `expected_evidence:`
- It must be at least as well-motivated as H_a or H_b individually

**Step 3 — File ≥1 third alternative.**

You don't have to file all candidates — file the strongest 1 or 2. Each gets `origin:third_alternative`:

```bash
h_ref="H-NNN"  # public ref; replace NNN before running
h_id="$(br create "$h_ref: <one-line third-alt claim>" \
  --type=task --labels=hypothesis --priority=2 \
  --slug="$h_ref" --external-ref="$h_ref" --silent \
  --description="$(cat <<'EOF'
claim: <full claim, explicitly rejecting both H_a and H_b's shared assumption>
mechanism: <the production rule>
falsifier: <observable falsifier>
expected_evidence: <observable evidence>
category: <typically mechanistic or boundary>
origin: third_alternative
confidence: speculative
parent: <h_a>
session: <SESSION_ID>

## Detail
H-<a> claims X; H-<b> claims Y. Both implicitly assume Z. This third alternative rejects Z and posits W instead.

## Coordinates
H-a and H-b disagree along axis A. This third alternative disagrees along axis B (orthogonal).
EOF
)")"
printf 'Created %s as br id %s\n' "$h_ref" "$h_id"
```

**Step 4 — Update the main session thread.**

```
Subject: [<SESSION_ID>] Third alternative injected
Body:
  Detected binary:
  - <h_a>: <claim>
  - <h_b>: <claim>
  Shared assumption: <Z>

  Third alternative(s):
  - H-NNN (origin: third_alternative, confidence: speculative): <claim>

  Per Brenner §103: "Both could be wrong."
```

**Step 5 — Audit.**

```bash
./scripts/audit-bead-invariants.sh --check=third_alternative_present
```

Should now report at least one `origin:third_alternative` in the active slate.

---

**Anti-patterns to avoid:**

- ✗ Filing a "third alternative" that's actually a softer version of H_a or H_b. The third alternative must reject the shared assumption.
- ✗ Filing >3 third alternatives. The point is to break the binary; you don't need to swarm.
- ✗ Filing a third alternative without a falsifier. Same rule as MO-03a — every H needs `falsifier:`.

**Ship-or-Surface SLA:** within 20 minutes, file ≥1 `origin:third_alternative` H, OR surface a specific blocker.
