# Mental Models — User, Agent, Operator, Maintainer

The doctor has four distinct readers, each with a different mental model. SKILL.md and most reference files address ALL of them; this file separates them so you can identify which audience a given chunk of methodology serves.

---

## The user (human, runs the tool occasionally)

**Mental model.**
- "My CLI is broken. I want to fix it. I don't want to lose my work."
- Touches the doctor maybe once a month.
- Has limited tolerance for new flags or surfaces.
- Reads the human-readable Markdown, not the JSON.

**What they need from the doctor:**
- A bare `<tool> doctor` that produces a 1-paragraph summary.
- A `<tool> doctor --fix` that says "I'll do these 5 things; OK?" before doing them.
- A `<tool> doctor undo latest` that is one command away.
- Errors that say what to do next in plain English.

**What they don't need:**
- The JSON schema. Hidden behind `--json`.
- The capabilities reflection. Hidden behind `capabilities`.
- The state machine. Surfaced only on terminal failures.
- The methodology. Lives in the workspace; users never read it.

**Files that serve them:**
- [SKILL.md "What This Skill Is For"](../../SKILL.md) — first impression.
- [assets/skill-card.md](../../assets/skill-card.md) — elevator pitch.
- `report.md` — human-readable per-run report.
- The `<tool> doctor --help` output.

---

## The agent (an AI like Claude/Codex/Gemini, runs the tool unsupervised)

**Mental model.**
- "I'm in a sandbox. The project is in some state. I need to figure out what's wrong and fix it without breaking things."
- Runs the doctor potentially many times per session.
- Has perfect attention to JSON but no patience for prose.
- Can't easily recover from a crashed shell or corrupted state.

**What they need:**
- A predictable JSON schema (`schema_version` + stable fields).
- An exit-code dictionary they can switch on.
- `capabilities --json` for discovery.
- `robot-docs` for orientation.
- `--robot-triage` for one-shot context.
- Refusal exit codes (4, 5, 6) that distinguish reasons.

**What they don't need:**
- Color or progress output (suppressed under `--json` / `--robot`).
- Spinners.
- "Press Y to continue" prompts.
- Verbose help text.

**Files that serve them:**
- [AGENT-PERSPECTIVE.md](AGENT-PERSPECTIVE.md) — explicitly written for the agent.
- [CLI-SURFACE.md](CLI-SURFACE.md) — the JSON contract.
- [OUTPUT-SCHEMA.md](OUTPUT-SCHEMA.md) — per-run artifact format.
- `<tool> doctor robot-docs` output (live).
- `<tool> doctor capabilities --json` output (live).

---

## The operator (human, runs the tool's CI / dashboards / alerts)

**Mental model.**
- "I monitor a fleet of users running this tool. I want to know if the doctor is healthy across all of them."
- Cares about trends over time, not individual runs.
- Reads structured logs and dashboards, not bare CLI output.
- Triages incidents.

**What they need:**
- `<tool> doctor health` (sub-200ms; for cron).
- `scorecard_history.jsonl` for trend tracking.
- Alert thresholds (regression > 50, panics > 0, etc).
- Per-pattern dashboards (daemon liveness, vendor 5xx counts, etc).
- Doctor metrics export to their telemetry sink.

**What they don't need:**
- Per-finding remediation (the user / agent acts; the operator observes).
- Source-level details (file:line). Aggregate-level signal is enough.

**Files that serve them:**
- [METRICS.md](METRICS.md) — observability beyond the scorecard.
- [OPS-RUNBOOK.md](OPS-RUNBOOK.md) — daily/weekly cadence.
- `scorecard_history.jsonl` (live data).
- `<tool> doctor health --watch` output (live stream).

---

## The maintainer (human, evolves the doctor over time)

**Mental model.**
- "I'm the team owning this doctor. New FMs surface; I add detectors. New CI gates; I wire them. The methodology is my reference."
- Reads the skill periodically.
- Cares about WHY decisions were made.
- Audits cross-references and consistency.

**What they need:**
- The kernel (24 axioms with rationale).
- The corpus (so they can extend it).
- Decision log (so they understand prior choices).
- Skills cross-reference (so they know what informs what).
- The cookbook (so they pattern-match new projects).

**What they don't need:**
- The agent-facing JSON schemas (they review them but don't consume them).
- The user-facing Markdown (same).

**Files that serve them:**
- [KERNEL.md](KERNEL.md), [FIRST-PRINCIPLES.md](FIRST-PRINCIPLES.md), [DECISION-LOG.md](DECISION-LOG.md).
- [CORPUS.md](CORPUS.md), [QUOTE-BANK.md](QUOTE-BANK.md).
- [COOKBOOK.md](COOKBOOK.md), [SKILLS-CROSS-REF.md](SKILLS-CROSS-REF.md).
- [CHANGELOG.md](../../CHANGELOG.md) (skill-level changelog).

---

## Where the models clash

These four readers occasionally want incompatible things. The methodology resolves clashes by ranking the agent's needs HIGHEST (per the kernel: doctor IS a contract with a future agent).

| Clash | Resolution |
|-------|------------|
| User wants prose error → agent wants structured remediation | Both: prose to stderr, structured to stdout (JSON) |
| Operator wants succinct logs → agent wants verbose evidence | `health` is succinct; `--explain` is verbose; both exist |
| Maintainer wants flexibility → user wants stability | Stable contract per `doctor_contract_version`; flexibility under the contract |
| Agent wants speed → operator wants comprehensive coverage | `--quick` for speed; default for coverage; both modes documented |
| User wants no surprises → maintainer wants new fixers | New fixers start `enabled: false` in capabilities; user opts in per major version |

When in doubt: agent's needs win. The user gets a great doctor as a side-effect.

---

## A concrete example

A doctor finds 3 P2 findings in a workspace. What does each reader see?

**User (`<tool> doctor`):**
```
Found 3 issues:
  ⚠ JSONL drift in .beads/issues.jsonl
  ⚠ Stale completion script
  ⚠ Credential file too permissive

Run `<tool> doctor --fix` to repair.
```

**Agent (`<tool> doctor --json`):**
```json
{
  "schema_version": "1.0",
  "ok": false,
  "summary": {"total_findings": 3, "by_severity": {"P2": 3}, "auto_fixable": 3},
  "findings": [
    {"id": "fm-state-files-jsonl-tombstone-drift", "severity": "P2", ...},
    ...
  ],
  "exit_code": 1,
  "next_steps": ["Run: <tool> doctor --fix", "..."]
}
```

**Operator (`<tool> doctor health`):**
```
findings  br=0.5.0 doctor=1.0.0 findings=3 P2=3 last_run=...
```

**Maintainer (looking at scorecard_pass_<N>.md):**
```
Aggregate: 893
Per-FM:
  fm-state-files-jsonl-tombstone-drift   950 (improved from 920)
  fm-external-artifacts-completion-stale 870 (new since pass-2)
  fm-permissions-credential-too-permissive 880 (unchanged)
```

The same 3 findings, four readings, four useful pieces of information. The doctor's design serves all four — but the agent's reading is the contract; the others derive from it.

---

## How to write for each reader

When you're writing methodology, first ask "who reads this?":

- **For users:** prose, Markdown, no jargon. Show, don't tell. Avoid talking about the kernel.
- **For agents:** JSON schemas, exit-code tables, schema_version pins. Name everything; assume zero context.
- **For operators:** dashboards, thresholds, cadences. Quantify everything.
- **For maintainers:** kernel-level reasoning, citations, decision rationale. Cross-link densely.

A single methodology document can serve multiple readers if the audience-shifts are clearly marked. Use H2/H3 sections per audience, or call out "**For agents:**" / "**For operators:**" inline.

---

## Future enhancement: per-reader doctor outputs

A planned (not yet implemented) doctor flag:

```
<tool> doctor --audience=user      # human-readable Markdown
<tool> doctor --audience=agent     # JSON
<tool> doctor --audience=operator  # one-line health
<tool> doctor --audience=maintainer  # full reference dump
```

Today, the implicit audiences are inferred from `--json` (agent), `--health` (operator), and bare invocation (user). Maintainer audience is served via the workspace artifacts.

The four audiences ARE the design. Naming them helps reviewers spot when one is being slighted.
