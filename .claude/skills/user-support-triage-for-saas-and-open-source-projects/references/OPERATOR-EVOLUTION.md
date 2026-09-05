# Operator Evolution

The operator library should improve from real support work, but only through a
controlled loop. Do not let one dramatic ticket mutate the skill's doctrine.

## Evolution Sources

Use these sources as evidence:

- outcome records from [POST-SEND-OUTCOME.md](POST-SEND-OUTCOME.md);
- owner edits to draft bundles;
- repeated `TBD-OWNER` questions;
- fire-drill failures;
- recurring adapter validation failures;
- post-incident retros;
- customer replies showing confusion, appreciation, or frustration;
- closed beads or GitHub issues created from support sessions.

## Promotion Ladder

| Stage | Meaning | Allowed Change |
|---|---|---|
| Observation | One session revealed friction | Add to outcome record only. |
| Pattern | Same friction appears in 3+ sessions or a high-risk drill | Propose template/runbook/operator patch. |
| Owner-approved rule | Owner confirms this should happen going forward | Patch project-specific support-triage docs. |
| Generalizable operator | Pattern recurs across multiple projects/surfaces | Patch this skill's references. |
| Validated operator | Fire drill proves the operator routes correctly | Add to operator library or decision matrix. |

## Operator Proposal Card

When proposing a new operator or a change to an existing one, write:

```markdown
## Operator Proposal: <name>

- Trigger:
- Move:
- Inputs required:
- Outputs produced:
- Confirmation needed before customer-visible action:
- Failure modes:
- Evidence anchors:
- Fire-drill fixture:
- Why existing operators are insufficient:
```

The "why existing operators are insufficient" line prevents the library from
becoming a bag of synonyms.

## Guardrails

- Never auto-apply policy changes from session mining.
- Never add a new operator when a tighter runbook sentence would solve it.
- Never promote a provider-specific workaround into a universal rule unless it
  has been seen outside that provider.
- Keep the kernel small: routine tickets should still be triageable from the
  onboarding README plus decision matrix.
- Add validators or fire drills alongside important operator changes.

## Useful Evolution Patterns

| Pattern | Likely Improvement |
|---|---|
| Owner repeatedly rewrites the same apology | Voice calibration or response template patch. |
| Security/GDPR tickets cause hesitation | Runbook decision tree or escalation owner is missing. |
| Agent keeps asking for the same DB/admin URL | Adapter contract needs `stable_url` or evidence field. |
| Multiple tickets share one root cause but get separate replies | Strengthen `CORRELATE` and incident cohorting. |
| Triage cannot prove a fix deployed | Add deploy timestamp/version-pin step. |
| A support reply generates a second confusion ticket | KB answer or product copy is unclear. |

## Session Mining With `cass`

When available, use `cass` to mine prior support sessions:

```bash
cass search "support triage owner rewrote draft refund" --robot --limit 10
cass search "TBD-OWNER support policy" --robot --limit 10
cass search "fire drill support adapter failed" --robot --limit 10
```

Mine for patterns, not anecdotes. One prior session can inspire a hypothesis;
three independent sessions can justify a patch proposal.

## Acceptance Standard

An operator evolution patch should include:

- evidence anchors;
- one concrete failure mode it prevents;
- an example trigger;
- a fire-drill fixture or manual rehearsal note;
- no removal of existing useful operators unless the owner explicitly approves
  consolidation.
