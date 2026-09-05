# Case Study — `<short-slug>`

> **One-line summary.** What happened in <project-name>'s audit pass <UTC>:
> <e.g. "47 closed beads, 13 false-closed, 2 epics had drifted contracts">.

| Field | Value |
|---|---|
| Project | `<project-basename>` |
| Audit pass | `passes/<UTC>/` |
| Mode | `standard` / `comprehensive` / `tripwire` / `single-bead` / … |
| Tier | Solo / Pair / Squad / Swarm |
| Closed-bead universe | `<N>` |
| False-closed found | `<M>` (<percent of closed>) |
| Score median | `<S>` |
| Convergence | converged after `<K>` passes |
| Time elapsed | wall-clock `<HH:MM>` |
| Cost | `~$X.XX` (Anthropic + tooling) |

---

## Context — what was the team trying to verify?

A short paragraph: what did the human invoking this audit want to know? What
prompted it (release? incident? quarterly hygiene?)? What were they
suspicious of (a specific agent? a specific feature area?)?

---

## What the audit found

### Headline findings

- **<finding 1>.** Brief one-sentence headline + which beads it affected.
  Cite `passes/<UTC>/beads/<id>/scorecard.md` for evidence.
- **<finding 2>.** …
- **<finding 3>.** …

### Pattern signature (cross-bead)

Did `subagents/cross-bead-synthesizer.md` find anything systemic? E.g.:
- A specific agent batch-closed N beads in M minutes
- A schema change rippled through 5 sibling beads without contract updates
- A class of test (fuzz, golden, e2e) was missing across multiple beads

Cite `passes/<UTC>/synthesis.md` for the integration-gap rows.

---

## How the audit was run

```bash
# Exact invocation (paste the command the user actually ran)
~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
  /data/projects/<project> \
  --threshold 700 \
  --mode standard \
  --policy completion-debt
```

Subagents invoked (if Squad/Swarm tier):
- `bead-spec-extractor` — Phase 2 — N beads
- `evidence-gatherer` — Phase 3 — N beads
- `compliance-verifier` — Phase 4 — N beads
- `theater-detector` — Phase 5 — N beads
- `test-depth-auditor` — Phase 6 — N beads
- `cross-bead-synthesizer` — Phase 7 — 1 invocation
- `scorer` — Phase 8 — N beads
- `remediator` — Phase 9 — 1 invocation
- `fresh-eyes-rubric-auditor` — Phase 10 — 1 invocation

Specialists invoked (per `references/MODES-AND-TIERS.md` routing):
- `<security-auditor>` — for `<N>` security-tagged beads
- `<performance-auditor>` — for `<N>` perf-tagged beads
- (etc.)

---

## What surprised us

Use this section honestly. The most valuable case studies record what was
COUNTERINTUITIVE — false-closed beads that looked solid, beads that scored
high but turned out to have hidden integration gaps, agents that the team
trusted but who had a high false-closed rate.

---

## What we did with the findings

Phase 9 outcome:
- **`<N>` reopened** — the original closer is asked to actually finish
- **`<M>` completion-debt beads created** — links back to original via
  `--parent`; new bead carries the missing items verbatim
- **`<K>` report-only** — recorded in `remediation.md` but no `br` writes

Cite `passes/<UTC>/remediation.md`.

---

## Lessons learned (for the rubric / for the team)

What should change as a result of this audit?

- **Rubric:** does any pattern this audit caught deserve a specific entry
  in `references/FAILURE-MODES.md`? Add via `references/CONTRIBUTING-PATTERNS.md`.
- **Team process:** would `subagents/spec-quality-reviewer.md` (run pre-claim)
  have prevented any of these false-closed beads?
- **Tooling:** any place where the audit was slow, noisy, or hard to read?
  File against the skill via the bead store or open a PR.

---

## Reproducibility

To re-run this exact audit:

```bash
# Check out the project at the audited SHA:
git -C /data/projects/<project> checkout <project_sha_at_pass_start>

# Re-run with the same rubric:
~/.claude/skills/beads-compliance-and-completion-verification/scripts/run-pass.sh \
  /data/projects/<project> --threshold 700 --mode standard --policy report-only

# Verify scoring is deterministic:
python3 ~/.claude/skills/beads-compliance-and-completion-verification/scripts/reproducibility-check.py \
  /data/projects/<project>/beads_compliance_audit/passes/<UTC>
```

Both should produce identical scores. If not, see `references/AUDIT-REPRODUCIBILITY.md`.

---

_Author: <name>. Date: <YYYY-MM-DD>. Skill version at audit time: <semver>._
