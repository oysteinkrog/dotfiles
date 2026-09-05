# fresh-eyes-reviewer-c

> Phase 14 • Third verbatim fresh-eyes review prompt (fellow-agent code review, first-principle root-cause analysis, wider net).

## Inputs
- The current state of the workspace + target after fresh-eyes-reviewer-a and fresh-eyes-reviewer-b complete.
- `git log --since=<gauntlet-start-date>` (entire gauntlet's commit history).
- Outputs of UBS scans and clippy / miri runs.

## Deliverables
- `<workspace>/phase14_fresh_eyes_c.md` with: cross-agent issues found, root-cause analyses, fixes applied, deferred items as beads.

## Coordination
- **MCP Agent Mail thread:** `gauntlet-<run-id>-phase14-fresh-eyes-c`
- **Reservations needed:** `tool://workspace-edit` (TTL 180m), `tool://ubs-run` (TTL 60m).
- **Lane:** cross-cutting.

## Verbatim Prompt

The following prompt is verbatim and MUST be applied literally:

> Ok can you now turn your attention to reviewing the code written by your fellow agents and checking for any issues, bugs, errors, problems, inefficiencies, security problems, reliability issues, etc. and carefully diagnose their underlying root causes using first-principle analysis and then fix or revise them if necessary? Don't restrict yourself to the latest commits, cast a wider net and go super deep!

**Procedure:**
1. List the entire gauntlet's commit history: `git log --oneline <gauntlet-start-sha>..HEAD`. Identify the authoring agent (or commit message tag) for each commit.
2. Run UBS (`/ubs`) against the workspace — it will surface many candidate issues; treat its output as a starting point.
3. Run `cargo clippy --workspace -- -W clippy::pedantic -W clippy::nursery`; capture all warnings.
4. Run `cargo +nightly miri test --workspace` (if applicable); capture undefined-behavior reports.
5. For each candidate issue, do a first-principle root-cause analysis:
   - What is the invariant being violated?
   - What is the call site that violates it?
   - Is this a localized bug or a cross-cutting design flaw?
   - If localized: fix in place.
   - If cross-cutting: open a bead with a remediation-architect-style entry (2+ rewrites, rubric scores, recommended).
6. Do NOT restrict yourself to recent commits. Look back through the entire gauntlet's commit history. A bug introduced 10 days ago and untouched since is just as much your responsibility.
7. Go super deep: trace each issue to its root cause, not its proximate symptom. A `panic!` in module X may be caused by a missing invariant check in module Y.

**Common cross-agent issue patterns:**
- Two agents touched the same file with conflicting assumptions (one added a counter, another removed the producer site).
- An agent added a feature without updating the FeatureUniverse entry.
- An agent added a test without updating the InvariantCatalog ProofObligation.
- An agent added a hot-path counter that's algebraically redundant with an existing one.
- An agent's "fix" reintroduced a known divergence (check against `mismatch_signature_index.json`).
- An agent's negative-ledger entry lacks the retry-condition predicate.

**Output structure:**
```markdown
## Cross-agent issues found (N)
| Severity | File | Source agents | Root cause | Fix status |
|---|---|---|---|---|
| critical | <...> | agentA + agentB | <root cause> | fixed in commit <sha> |
| ... |

## Detailed root-cause analyses
### Issue <N>: <one-line summary>
- **Symptom:** <observed bug>
- **First-principle root cause:** <why the symptom arose>
- **Fix:** <commit/diff>
- (or **Deferred bead:** <bead-id>)

## UBS / clippy / miri findings rolled up
| Source | Total | Fixed | Deferred |
|---|---|---|---|
```

**Discipline:**
- First-principle root cause means: ask "why?" until the answer is a fundamental design / invariant / assumption, not a proximate code line.
- Wider net means: every commit since the gauntlet started, not just the last few.
- "Super deep" means: don't stop at "the function returns wrong" — trace why the function was written that way, and whether the design itself is wrong.

## Exit Criteria
- Every gauntlet-era commit has been at least cursorily reviewed.
- UBS + clippy --pedantic + miri have been run; their outputs triaged.
- Every cross-agent issue has a root-cause analysis.
- Two consecutive runs of fresh-eyes-reviewer-c produce no new critical findings (the explicit "two clean rounds" termination gate before Phase 15).
- `phase14_fresh_eyes_c.md` committed.

## References
- [PHASES.md § Phase 14](../references/PHASES.md)
- [methodology/OPERATORS.md § Fresh-Eyes](../references/methodology/OPERATORS.md)
- [exemplars/EXEMPLARS.md § fresh-eyes prompts](../references/exemplars/EXEMPLARS.md)
- [/ubs](../../ubs/SKILL.md)
