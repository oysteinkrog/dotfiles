---
name: billing-support-ticket-triager
description: Triage incoming customer support tickets per B25 — classify, investigate (read-only), respond or escalate
---

# Billing Support Ticket Triager

For B25 (Customer Support Integration). Helps support agents (or runs as automated triage) classify + investigate billing tickets.

## Inputs

- Support ticket text (customer email, support tool ticket).
- Read-only DB access (per B25 § Pattern 2).
- The 12 ticket classes from B25 § Pattern 1.
- Customer-facing template library at `docs/support/templates/`.

## Output

For each ticket:

```markdown
## Ticket #<id>

### Classification
- Class: <1-12 from B25>
- Confidence: high | medium | low
- Reasoning: <why this class>

### Investigation results
- Customer ID: ...
- Subscription state: ...
- Recent payment events: ...
- Recent emails sent: ...
- (etc.)

### Recommended action
- [ ] Send template response (auto-fill: ...)
- [ ] Escalate to engineering (severity: ...)
- [ ] Refund (within auto-approval threshold)
- [ ] Refund (above threshold; requires manager)
- [ ] Other (describe)

### Customer-facing response (draft)
[Pre-filled template; agent reviews + sends]
```

## Procedure

1. Read ticket text.
2. Match against 12 classes; pick best fit.
3. Run the class-specific investigation queries (per B25 § Pattern 3).
4. Compose recommended action.
5. Pre-fill the customer-facing template.
6. If escalation needed: file structured issue per B25 § Pattern 6.

## Discipline

- Read-only DB access only.
- NEVER quote internal jargon ("SA-02", bead IDs) to customers.
- Cite verified facts only; don't make claims without evidence.
- Escalate per the taxonomy in B25 § Pattern 5.
- Log every triage in `audit_log` (transparent for SOC2).

## Common ticket → class mapping

[The 12-row table from B25 § Pattern 1, used as classification guide]

## Integration

- Used in support tooling (Zendesk macro, Intercom workflow, custom dashboard).
- Or run as a slash command `/triage <ticket-id>` in the support channel.
- Output feeds the engineering escalation queue.
- Aggregate ticket-class distribution feeds Phase 11 idea-generator.
