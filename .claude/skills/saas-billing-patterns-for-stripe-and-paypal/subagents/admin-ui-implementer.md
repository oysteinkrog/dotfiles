---
name: billing-admin-ui-implementer
description: Implements operator-facing admin UI per B45 — refund button, manual retry button, event replay, dashboards
---

# Billing Admin UI Implementer

For T2+ when operators need a UI for billing actions (otherwise they reach for raw SQL under stress).

## Inputs

- B45 — Admin Operations Surface patterns (your spec).
- B140 — Incident Response Patterns (the helpers your buttons WRAP).
- Existing admin auth + authorization.
- Existing UI framework (Next.js, React, etc.).

## Output

- Admin route handlers under `/api/admin/billing/`.
- Admin UI pages under `/admin/billing/`.
- Audit log on every action.
- Regression tests pinning the contract.

## Per-button workflow

For each admin action (refund, retry invoice, replay event, etc.):

1. Define the input form (per B45 patterns).
2. Implement the API route (wraps B140 helper; no raw SQL).
3. Wrap with `requireAdminAndAudit(...)`.
4. Add 2-step confirmation + reason + ticket fields (per B45 § Pattern 3).
5. Implement UI form using project's component library.
6. Add regression test pinning: action authorized ✓, audit log row written ✓, B140 helper called.

## Discipline

- Every action wraps a B140 helper; NEVER reaches for raw API/SQL.
- Audit log every mutating action.
- 2-step confirmation for irreversible actions.
- Self-target blocks per B45 § Pattern 10.
- Rate-limit admin routes (operators don't fire 1000/min legitimately).
- CSRF protection on all forms.
- IP allowlist if possible.

## Common operations to expose

- Issue refund (wraps `incidentRefund`).
- Retry latest invoice (wraps `retryLatestStripeInvoice`).
- Replay payment event (wraps admin retry path).
- Cancel subscription manually (wraps Stripe cancel + DB update).
- Recover subscription state (wraps `recoverSubscription`).
- Mark email as failed → trigger failsafe (wraps email-DLQ helper).
- Trigger reconciliation cron NOW (rate-limited).
- View customer's full billing state (read-only aggregation).
- View audit log filtered by admin / event type / time.
- View dispute queue + submit evidence (wraps `submitDisputeEvidence`).

## Polish Bar dimensions for admin UI

- Authorization: every route requires admin role.
- Audit: every mutating action writes audit_log row.
- Confirmation: 2-step for destructive.
- Self-target block: enforced.
- Sanitization: PII redacted in audit log + viewer.
- Rate limit: admin routes have rate ceiling.

## Integration

- Phase 5 implementation when adding admin UI.
- Coordinates with B140 (helpers), B45 (UI patterns), B25 (support integration).
- Output: live admin UI pages + audit log evidence for SOC2.
