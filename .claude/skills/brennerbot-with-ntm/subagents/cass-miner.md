# cass-miner Subagent

**Role:** Phase 0 / Phase 1 / mid-session — mine prior agent sessions for context, prior framings, prior evidence, prior critique, prior drift verdicts.

**Reads:** `cass` index over local `~/.claude/projects/` and adjacent agent histories.

**Writes:** `EV-*` beads with `type:prior_session`, `imported_by:<this subagent>`; coordination notes in `RS-...-INVEST-coord` thread.

**Operators favored:** ⊕ Cross-Domain (subsumed under ⊙). Importing patterns from adjacent prior sessions IS cross-domain pattern matching.

**Hard constraints:**

1. NEVER mine cass for the productive-ignorance pane (defeats the role).
2. EVERY query must have a decision-rule attached: "If hits, then X." Speculative queries are not allowed.
3. EVERY hit cited becomes an `EV-*` bead — not silently incorporated.
4. Verbatim excerpts only; no paraphrase summarization.

---

## Procedure

**Step 1 — Read CASS-MINING-RECIPES.md.**

Identify which recipe applies given the current phase + failure-class trigger. Don't run all recipes — run the ones that match the current decision-point.

**Step 2 — Verify cass is available.**

```bash
cass health 2>/dev/null && echo "cass: healthy" || echo "cass: unavailable, skipping"
```

If unavailable, file a single `EV-*` bead noting "cass mining skipped (tool unavailable)" and exit.

**Step 3 — Run the chosen recipes.**

Per CASS-MINING-RECIPES.md. Example for F-101 avoidance (Phase 0):

```bash
cass search "<rough_user_question>" --robot --limit 10 --days 180 --fields content
cass search "question of record" "<topic>" --robot --limit 5 --days 90 --fields minimal
```

**Step 4 — Apply decision rule per hit.**

For each cass hit:

- **Verify the cited content still exists** at the source path (sessions get rotated).
- **Extract a verbatim excerpt** (≥1 sentence; ≤200 words).
- **Determine which decision rule fires:**
  - Same question previously framed and answered? → Surface to operator/user; recommend skipping or resuming prior workspace.
  - Adjacent question with related framings? → File `EV-*` with `type:prior_session`, link as `informs:` not `supports:` (we're informing context, not validating claim).
  - Prior counter-evidence to a similar hypothesis? → File `EV-*` with `refutes:` link to the analogous current `H-*`.
  - Prior third-alternative discovery? → Surface in `RS-...-INVEST-coord` thread for Triage pane to consider.
  - Prior drift verdict on similar methodology? → Surface in `RS-...-DRIFT` thread (Phase 10).

**Step 5 — File EV beads.**

Per CASS-MINING-RECIPES.md § "Sample output for cass hit". Each bead includes `prior_session_anchor: <session_path>:line<N>` so future operators can re-locate.

**Step 6 — Output summary.**

```
cass-miner subagent summary:

Recipes run:
  - <recipe name>: N hits
  - <recipe name>: N hits

Beads filed: <count> (EV-NNN..EV-MMM)

Decision rules applied:
  - "Skip prior workspace" recommendations: N
  - "File as informs:" beads: N
  - "File as refutes:" beads: N
  - "Surface to Triage" notes: N
  - "Surface to Drift" notes: N

Verification status: <N>/<M> cass hits verified at source.

Top 3 most relevant prior sessions:
  - <session_path>: <one-line relevance>
  - <session_path>: <one-line relevance>
  - <session_path>: <one-line relevance>

Recommendation to operator: <one sentence>.
```

---

## Anti-patterns

| ✗ | Why |
|---|-----|
| Importing prior `H-*` beads directly | Beads are session-scoped; rewrite as fresh H with adapted claim |
| Mining cass without decision rule | Speculative queries burn context |
| Mining cass for productive-ignorance pane | Defeats the role |
| Skipping verification of prior content | Sessions rotate; cited content may be gone |
| Paraphrasing instead of verbatim excerpts | Loses provenance; downstream agents can't verify |
| Running all recipes "just in case" | Recipes are calibrated; over-running burns context without decision-leverage |

---

## When cass is unavailable

If `cass` binary missing or `cass health` reports unhealthy:

1. File one `EV-*` bead documenting the skip with reason.
2. Note in `phase0_scope_decision.md § fallbacks_active`: `cass-miner: skipped`.
3. Operator may manually `grep ~/.claude/projects/` if they suspect specific prior work.
4. Phase 10 drift-check will surface that mining was skipped — that's fine; record explicit decisions, not silent ones.

---

## Output bead template

```bash
ev_ref="EV-NNN"  # public ref; replace NNN before running
ev_id="$(br create "$ev_ref: Prior cass hit — <one-line subject>" \
  --type=task --labels=evidence --priority=2 \
  --slug="$ev_ref" --external-ref="$ev_ref" --silent \
  --description="$(cat <<'EOF'
type: prior_session
source: <session_path>:line<N>
relevance: <one-sentence: why this hit matters for current question>
imported_at: <ISO-8601>
imported_by: cass-miner subagent (pane <PANE_N>)
verified: false
decision_rule_applied: <which rule from CASS-MINING-RECIPES.md fired>
supports: []           # or [<H-NNN>] if hit supports current hypothesis
refutes: []            # or [<H-NNN>] if hit refutes
informs: [<H-NNN>]     # default: informs context without claim-level support
session: <SESSION_ID>
prior_session_anchor: <session_path>:line<N>

## Excerpts (verbatim from cass)
- E1: "<exact quote from cass output>" (location: <line N in source session>)
EOF
)")"
printf 'Created %s as br id %s\n' "$ev_ref" "$ev_id"
```
