# CASS-MINING-RECIPES.md — Calibrated cass Queries Per Phase

<!-- TOC: When to mine | By failure class | By question archetype | Output handling | Anti-patterns | The cass-miner subagent | Resume-session mining | Sample output -->

`cass` indexes prior agent conversations. Mining it before/during a brennerbot session can save substantial work (re-solve avoidance) AND introduce risk (anchoring on prior framings).

These recipes mirror saas-billing's CASS-MINING-RECIPES-DEEP.md but tuned for *research* sessions rather than *implementation* sessions.

**Discipline:** every cass query has a *purpose* (what would I do differently if it returns hits?). Queries without a decision-rule attached are speculative and burn context.

---

## When to mine cass

| Phase | Trigger | Worth it? |
|-------|---------|-----------|
| 0 (pre-bootstrap) | Operator suspects this question has been investigated before | Yes — avoid duplicating prior work |
| 1 (framing) | Operator wants to ground the falsifier in a prior session's outcome | Yes — but flag any inheritance |
| 2 (bootstrap) | Operator wants to seed onboarding briefings with prior-session warnings | Optional |
| 3 (proposing) | Productive-ignorance pane should NOT mine cass (defeats role) | No — never for ignorance pane |
| 3 (proposing) | Other Proposers may mine cass for hypothesis-space precedents | Selectively — avoid anchoring |
| 4 (investigating) | Investigator wants to find prior `EV-*`-equivalent citations | Yes — for verbatim-quote reuse |
| 4 (investigating) | Devil's-Advocate wants prior counter-evidence | Yes — for known-attack patterns |
| 5 (debating) | Adjudicator wants to see how prior debates on similar Hs resolved | Optional — may anchor |
| 6 (distilling) | Synthesizer wants to compare with prior-session distillations | Selectively — flag inheritance |
| 7 (auditing) | Auditor wants to find prior audit findings on similar artifacts | Yes — for known-bug-class warnings |
| 10 (drift check) | Drift auditor wants prior drift verdicts | Yes — explicit cross-session learning |

---

## Recipes by failure class

### Avoiding F-101 (question too broad)

Before Phase 1 framing, mine cass for prior framings of related questions:

```bash
# Find prior question-framing sessions
cass search "question of record" "research session framing" --robot --limit 5 --days 90 \
  --fields minimal --agent claude

# Find sessions where the user previously framed "<rough question>"
cass search "<rough user question keywords>" --robot --limit 10 --days 180 \
  --fields content
```

**Decision rule:** if hits show this exact question was framed (and answered) before, surface to operator + user — they may want to skip to fresh-pass on prior workspace, not redo. If hits show *related* questions, extract the framing patterns (verbiage, scope/out-of-scope structures) but do NOT inherit the falsifier.

### Avoiding F-301 (false-binary slate)

Before Phase 3 triage, mine cass for prior third-alternative discoveries:

```bash
cass search "both could be wrong" "third alternative" "false binary" --robot --limit 5 \
  --days 90
```

**Decision rule:** prior third alternatives are starting points, not adoptions. Triage pane reads them and asks: "could this third alternative apply here?" Then files a NEW H bead with adapted claim — does not import the bead directly.

### Avoiding F-403 (confirmation-only bias)

Phase 4 — Devil's-Advocate mines cass for known counter-evidence patterns:

```bash
# Find prior critiques of similar hypothesis claims
cass search "<hypothesis_claim_keywords> counter-evidence OR critique OR refutation" \
  --robot --limit 10 --days 365

# Find prior falsifier-fired events
cass search "falsifier fired" "killed hypothesis" --robot --limit 5
```

**Decision rule:** if a prior `EV-*`-equivalent fired a similar falsifier, it's a strong starting point. Verify the verbatim source still exists. Re-cite as fresh `EV-*` in the current session (don't claim it was found in this session — proper provenance).

### Avoiding F-602 (single-family dominance)

Phase 6 — Meta-synthesizer checks if prior distillations leaned heavily on one model family:

```bash
cass search "meta synthesis" "model family" "distillation" --robot --limit 10
```

**Decision rule:** if past sessions had cc-dominance, weight the disagreement register toward cod/gmi readings this round. Track a "model-family pendulum" across sessions.

### Avoiding F-1001 (drift rationalized as improvement)

Phase 10 — Drift auditor mines past drift checks:

```bash
cass search "drift check" "Replacement Test" "improvement vs regression" --robot --limit 10
```

**Decision rule:** if the same "improvement" was claimed in 3 prior sessions and never measurably validated, mark it as suspicious in DRIFT-CHECK.md. Skill drift to "this is how we always do it" is itself a regression.

---

## Recipes by question archetype

### Architecture/design-space questions

```bash
cass search "design space for <X>" "alternative architecture" --robot --limit 10 --days 180
cass search "<X> weaknesses OR limitations OR failure modes" --robot --limit 10
```

### Methodology distillation questions

```bash
cass search "operationalizing expertise" "<methodology name>" --robot --limit 10
cass search "operator algebra" "<domain>" --robot --limit 10
```

### Codebase-investigation questions

```bash
cass search "<repo_name> architecture audit" --robot --limit 10
cass search "<repo_name> bug class OR design weakness" --robot --limit 10
```

### Incident-investigation questions

```bash
cass search "<incident_keywords> root cause" --robot --limit 10 --days 30
cass search "post-mortem <component>" --robot --limit 10
```

---

## Output handling discipline

`cass` returns excerpts. Each cass hit cited in this session must:

1. Become an `EV-*` bead with `type:prior_session`, `source:<session_path>`, `imported_by:<pane>`, `relevance:<one-sentence>`.
2. Carry verbatim excerpt(s) from the cass output.
3. Carry `prior_session_anchor:` field with `<file>:line<N>` (so the cass session can be re-located).
4. Be subject to verification — Phase 7 audit asks: "did we verify this prior-session claim against the current corpus?"

This is the same discipline as any other evidence — prior-session content is *evidence*, not *truth*.

---

## Anti-patterns in cass mining

| ✗ | Why |
|---|-----|
| Mining cass before defining the falsifier | Anchoring on prior framings prevents genuine reframing |
| Importing a prior `H-*` bead directly into this session | Beads are session-scoped; rewrite as a new H with adapted claim |
| Mining cass without a decision-rule | Every query must have "if hits, then X" — otherwise it's speculative |
| Mining cass to "see what we've done" without a phase-bound purpose | Burns context; produces vibes, not evidence |
| Letting the productive-ignorance pane mine cass | Defeats the role |
| Skipping cass when the question is clearly novel | If novel, no need to mine; explicit decision is fine |

---

## The cass-miner subagent

`subagents/cass-miner.md` is the canonical entry point. Operator dispatches:

```bash
Agent({
  description: "Mine cass for prior brennerbot work on <topic>",
  subagent_type: "general-purpose",
  prompt: "<contents of subagents/cass-miner.md, with <TOPIC> filled>"
})
```

The subagent runs the recipes above, files prior-session `EV-*` beads, and returns a summary including: hit count per query, top 3 relevant prior sessions, decision-rule applications.

If `cass` is not installed (per phase0_skill_inventory.json), the subagent skips with a noted fallback: operator can manually grep `~/.claude/projects/` if desired.

---

## Resume-session cass mining

When resuming, mine cass for activity *between* the prior session's freeze and now:

```bash
# Find sessions tagged with this RESUME's session_id
cass search "<SESSION_ID>" --robot --limit 50 --days 30
```

**Decision rule:** if the user has worked on related topics since the freeze (different sessions, different agents), the resumed swarm should be aware. File those as `EV-*` beads with `type:prior_session` so the next round of investigation can incorporate.

---

## Sample output for cass hit

When cass returns a useful hit, file like this:

```bash
ev_ref="EV-NNN"  # public ref; replace NNN before running
ev_id="$(br create "$ev_ref: Prior session at <session_path> investigated similar claim" \
  --type=task --labels=evidence --priority=2 \
  --slug="$ev_ref" --external-ref="$ev_ref" --silent \
  --description="$(cat <<'EOF'
type: prior_session
source: <session_path>:line<N>
relevance: "Prior agent session previously evaluated H-NNN-equivalent and reached <verdict>"
imported_at: <ISO-8601>
imported_by: <PANE_N> (via cass-miner subagent)
verified: false
supports: [<H_ID>]   # or refutes, depending on prior verdict
session: <SESSION_ID>
prior_session_anchor: <session_path>:line<N>

## Excerpts
- E1 (verbatim from cass): "<quote>"
EOF
)")"
printf 'Created %s as br id %s\n' "$ev_ref" "$ev_id"
```

Then Phase 4 investigation must independently verify by reading the prior-session content directly.
