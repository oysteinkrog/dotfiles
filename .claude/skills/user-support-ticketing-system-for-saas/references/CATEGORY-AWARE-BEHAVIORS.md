# Category-Aware Behaviors

Different ticket categories demand different policies, side effects, and escalation paths. A single "support ticket" type that ignores category is the most common reason ticketing systems plateau in usefulness — every well-run support team has *implicit* category-aware behavior; this file makes it explicit.

The default categories from the canonical implementation: **`auth`, `billing`, `access`, `bug`, `content_moderation`, `other`**. Each has distinct considerations below. Use this file to:

1. Decide which categories your project supports.
2. Wire per-category overrides into the service layer (not the route — every consumer benefits).
3. Surface category-specific UI affordances in the admin queue.

---

## Auth (`auth`)

**Examples.** Customer can't sign in. CLI auth token expired. SSO redirect failed. Magic-link email stuck in spam.

### Special Considerations

- **Bypass tier-aware rate-limit floor.** If the customer can't authenticate, they may not have a subscription claim attached to the request. Allow a small floor of unauthenticated submissions per IP per hour (e.g. 3) so a locked-out customer can file. Resolve identity from email + last-seen if the JWT is invalid.
- **Auto-include auth context.** Service layer enriches description with the customer's last 5 auth log lines (success/failure/timestamp/IP) — not the customer's password or session token, but enough that the support agent can correlate.
- **Refer to known-issue feed.** If `auth_provider_status === "degraded"` (Google OAuth outage), append a banner to the auto-reply: "Google OAuth is currently experiencing issues. Your ticket is queued; we'll respond as soon as the upstream issue is resolved."
- **Cooldown on duplicates.** A customer who has filed 3 auth tickets in 24 hours is likely flooded by a single underlying issue. Surface in the admin UI as a "repeat filer" badge; deduplicate before responding individually.

### Permissions / Access

- Tier-1 admins can resolve.
- No special escalation; auth issues rarely become legal/security events unless they coincide with an account-takeover (in which case re-route to security category).

### Recommended SLA Override

Auth tickets often have a higher P0 frequency (account locked → P0 even on individual tier). Consider auto-bumping `auth` tickets one priority level on the individual tier (P2 → P1).

---

## Billing (`billing`)

**Examples.** Charge appears wrong. Invoice missing. Card declined. Refund request. Plan downgrade.

### Special Considerations

- **Auto-attach billing context.** Service layer fetches and attaches: most-recent 3 invoices, current subscription state, last 30 days of charge events, dunning state. Surfaced as an admin-only sidecar (NOT visible to customer).
- **Refund authority gate.** Only `support.billing` (a separate permission key from `support.resolve`) can issue refunds. See [POLICIES-PER-CATEGORY.md](POLICIES-PER-CATEGORY.md) "Refund Authority Matrix."
- **Idempotency for refunds.** See [INCIDENT-PATTERNS.md](INCIDENT-PATTERNS.md) #10. Refund button maintains an idempotency key on first click; subsequent clicks dedupe via Stripe's API.
- **Read-after-write verification.** After issuing a refund, verify with a Stripe `retrieve` call that the refund object exists with the expected amount before notifying the customer.
- **Customer-visible side effects fork via owner gate.** Plan downgrade with credit, contract amendment, etc. — none execute without an owner-tier confirmation.

### Permissions / Access

- Read: tier-1 admins.
- Refund: `support.billing` (typically owner + 1 trusted lead).
- Plan changes: `support.billing` + owner-confirmation modal.

### Recommended SLA Override

Billing has high financial-stakes density. Tighter SLAs on enterprise tier:
- Enterprise: 1h response, 4h resolution (vs 4h/24h default)
- Individual: same as default

---

## Access (`access`)

**Examples.** Premium skill not unlocking. Org member can't see paid feature. Feature flag stuck.

### Special Considerations

- **Auto-attach entitlement state.** Service layer attaches the customer's full entitlement matrix at ticket-create time so the agent doesn't have to query separately.
- **Common resolution: re-sync.** Many access tickets resolve by force-syncing the subscription/entitlement from Stripe. Provide a one-click "Re-sync entitlements" admin action that's audited but doesn't require a free-text reason (use `reason: "force resync"`).
- **Customer-visible feature flag changes require owner.** Granting a customer a flag they aren't entitled to (out of goodwill) requires an owner-tier action; otherwise it accumulates as untracked goodwill credit.

### Permissions / Access

- Read + resync: tier-1.
- Granting one-off entitlements: owner only, with reason and 30-day auto-expire.

### Recommended SLA Override

Match default. Most access issues are not life-threatening.

---

## Bug (`bug`)

**Examples.** Feature broken. UI glitch. Export fails. Performance degraded.

### Special Considerations

- **Capture environment.** Customer-side ticket form auto-includes browser, OS, screen size, viewport, page URL, and (with consent) the last 10 console errors. Persist in `metadata.environment`.
- **Search for recent regressions.** AI assist (advisory) compares ticket subject to commits + bug reports from the last 14 days; surfaces "this looks like the auth-redirect regression from #5421" as an internal note.
- **Auto-link to engineering tracker.** When a bug ticket is escalated, create a linked issue in the engineering tracker (Linear/GitHub) with the customer's description and metadata; the linked-issue ID is stored on the ticket. Resolution of the engineering issue auto-comments back on the support ticket — but does not auto-resolve it (humans confirm with the customer).
- **Severity escalation by repeat-customer.** Same bug filed by N different customers in M hours auto-escalates priority. See [CREATIVITY-AND-INNOVATION.md](CREATIVITY-AND-INNOVATION.md) Innovation 5 and the triage skill's [PROACTIVE-SUPPORT.md](../../user-support-triage-for-saas-and-open-source-projects/references/PROACTIVE-SUPPORT.md).

### Permissions / Access

- Tier-1 admins handle the conversation.
- Escalation to engineering does not require permission (any tier-1 can route).
- Closing a bug ticket without the linked engineering ticket being resolved requires `support.resolve` with reason — accountability for "we won't fix it."

### Recommended SLA Override

Match default for first response. For resolution, recognize that resolution-time depends on engineering, not support — surface this in the customer-visible UI ("we've identified the issue and engineering is on it").

---

## Content Moderation (`content_moderation`)

**Examples.** Copyright claim. Reported abuse. DMCA. Inappropriate content. Privacy violation.

### Special Considerations

- **Legal-touch.** Many content-moderation tickets imply legal exposure. Auto-route to a `content_moderation_owner` (typically legal counsel + a designated trust-and-safety lead) with strict response policies (typically 48-72h legal-team SLA).
- **Strict audit trail.** Every action on a content_moderation ticket — even reads — gets audited. Reason: legal discovery requires reproducing exactly what the team knew when, and from whom.
- **Take-down workflow.** Removing flagged content requires:
  1. A written reason
  2. A snapshot of the content as it existed (for audit)
  3. A notice to the content author
  4. A retention policy on the snapshot (typically 7 years for DMCA)
- **Counter-notice path.** DMCA counter-notices auto-flag the original taker-down and route to legal review.
- **No AI suggestions on this category.** Hallucinated legal advice has acute risk. AI-assist disabled by default. Even AI-categorization is checked: if it routes a non-content-moderation ticket here, it surfaces with a "categorization may be wrong" banner.

### Permissions / Access

- Read: legal + owner only. NOT tier-1 admins.
- Mutations: dual confirmation (legal lead + one other owner).
- Read-action audited.

### Recommended SLA Override

48-72h response for non-urgent. Imminent CSAM or threats: pre-existing escalation path that bypasses the ticketing system entirely — call the police, then file the ticket as documentation.

---

## Other (`other`)

**Examples.** General feedback. Feature request. Question that doesn't fit a category. Compliments.

### Special Considerations

- **Auto-categorize.** AI assist (advisory) suggests a re-categorization on intake. Admin can accept/reject in the queue. Frequent recategorizations into a specific bucket suggest the categorization UX needs revision.
- **Lower-priority default.** Default to P3.
- **Aggregate for product insights.** Feature requests that match a clustering pipeline get rolled into the product-insights weekly report. See [METRICS-AND-REPORTING.md](METRICS-AND-REPORTING.md) and [CREATIVITY-AND-INNOVATION.md](CREATIVITY-AND-INNOVATION.md) Innovation 4.
- **Respond fast for compliments.** A 2-minute "thank you" response to a compliment ticket is a cheap, asymmetric brand investment. Surface compliments in a separate tab in the admin queue.

### Permissions / Access

- Standard.

### Recommended SLA Override

Match default. Some teams choose to never set a hard SLA on `other` — they batch-respond on Friday afternoons.

---

## Per-Category Configuration Schema

```ts
interface CategoryConfig {
  // Auto-routing
  autoEscalateOwner?: PermissionKey;        // e.g. 'content_moderation_owner'
  autoEscalatePriority?: TicketPriority;    // bump up by category

  // SLA overrides (use defaults from SLA-ENGINE.md if absent)
  slaConfig?: {
    enterprise?: { firstResponse: PriorityHours; resolution: PriorityHours };
    individual?: { firstResponse: PriorityHours; resolution: PriorityHours };
  };

  // Required permissions for actions on this category
  requiredPermissions?: {
    read?: PermissionKey;
    resolve?: PermissionKey;
    mutate?: PermissionKey;        // status / priority / assignee changes
  };

  // Auto-attached context (admin-only sidecar)
  contextProviders?: Array<(userId: string, ticketId: string) => Promise<Record<string, unknown>>>;

  // AI-assist scope
  aiAssist?: {
    autoCategorize?: boolean;       // run categorization
    suggestReplies?: boolean;       // draft replies
    surfaceKnownIssues?: boolean;   // link recent regressions
    dual_human_required?: boolean;  // disable AI entirely
  };

  // Audit policy
  auditReadActions?: boolean;       // audit GETs (default false)

  // Customer-visible status text override
  customerStatusLabels?: Partial<Record<TicketStatus, string>>;

  // Special workflows
  takedownFlow?: { snapshotBucket: string; retentionYears: number };
    counterNoticeFlow?: { rerouteTo: PermissionKey };
}

const CATEGORY_CONFIG: Record<SupportCategory, CategoryConfig> = {
  auth: {
    autoEscalatePriority: "p1",  // for individual tier
    contextProviders: [getRecentAuthLogs],
  },
  billing: {
    requiredPermissions: { resolve: "support.billing" },
    contextProviders: [getRecentInvoices, getSubscriptionState, getDunningState],
    slaConfig: {
      enterprise: { firstResponse: { p0: 1, p1: 1, p2: 1, p3: 4 }, resolution: { p0: 4, p1: 4, p2: 4, p3: 24 } },
    },
  },
  access: {
    contextProviders: [getEntitlementMatrix],
  },
  bug: {
    contextProviders: [getEnvironmentMetadata],
    aiAssist: { autoCategorize: true, suggestReplies: true, surfaceKnownIssues: true },
  },
  content_moderation: {
    autoEscalateOwner: "content_moderation_owner",
    requiredPermissions: { read: "support.content_moderation_read", resolve: "support.content_moderation_resolve" },
    aiAssist: { dual_human_required: true },
    auditReadActions: true,
    takedownFlow: { snapshotBucket: "moderation-snapshots", retentionYears: 7 },
    counterNoticeFlow: { rerouteTo: "legal_owner" },
  },
  other: {
    aiAssist: { autoCategorize: true },
  },
};
```

Wire through service layer; consume in route handlers, cron, and UI alike.

---

## UI: Per-Category Affordances

The admin queue shows a per-category icon + filter chip. Selecting a category filter reveals the category's special affordances:

- `billing` selected → "Issue refund" button visible (gated by permission).
- `bug` selected → "Link to engineering issue" button visible.
- `content_moderation` selected → "Take down content" button + reason field visible.
- `auth` selected → "Force re-sync session" button visible.

Hide buttons by default; expose only when category matches. Reduces visual clutter and prevents misclicks.

---

## Customer-Facing Category Selector

The new-ticket form uses category-aware UX:

```tsx
<select onChange={onCategoryChange}>
  <option value="auth">Login & Auth</option>
  <option value="billing">Billing & Subscription</option>
  <option value="access">Access & Entitlements</option>
  <option value="bug">Bug Report</option>
  <option value="content_moderation">Content / Copyright</option>
  <option value="other">Other</option>
</select>

{category === "billing" && (
  <p className="hint">For refund requests, please include the order ID.</p>
)}

{category === "bug" && (
  <>
    <input name="reproSteps" placeholder="Steps to reproduce" />
    <input name="expectedBehavior" placeholder="What did you expect?" />
    <input name="actualBehavior" placeholder="What happened?" />
  </>
)}

{category === "content_moderation" && (
  <p className="hint">If this is a copyright claim, see <a href="/legal/dmca">our DMCA policy</a>.</p>
)}
```

The hints are self-service deflection: customers see the relevant policy before filing, sometimes solve their own issue, file a more useful ticket if they don't.

---

## Anti-Patterns

| ✗ | Why |
|---|---|
| Single-priority default ignoring category | Auth tickets need different urgency than feature requests |
| AI-suggesting replies on `content_moderation` | Hallucinated legal advice = lawsuit |
| Refund button visible on non-billing categories | Misclick risk; permission scope leak |
| Customer-facing status labels identical across categories | "Awaiting customer" on a bug they reported is confusing — say "Engineering is investigating" |
| No category in the audit log payload | Per-category abuse patterns invisible |
| Hardcoded category list in 4 places | Drift; new category requires touching every consumer. Centralize. |

---

## Adding A New Category

1. Add the enum value to `supportCategoryEnum`.
2. Add `CATEGORY_CONFIG[newCategory]` to the central config.
3. Run `bun typecheck` — every consumer that switches on category will now error if it doesn't handle the new case (use exhaustive switch with `assertUnreachable` for compile-time guarantees).
4. Update the customer-form select.
5. Add per-category UI affordances if applicable.
6. Add tests.

The compile-time safety is the most important guard: never use `string` for category in code; always the enum union.
