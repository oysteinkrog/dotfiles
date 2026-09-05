# Marketplace And Disputes

A two-sided marketplace turns support into arbitration. Buyer says "didn't ship"; seller says "did ship." One transaction, two angry counterparties, real money on the line, and a support team that has to decide. Get this wrong consistently and one side abandons the platform — buyers if you favor sellers, sellers if you favor buyers. The discipline of marketplace dispute handling is *neutrality enforced by structure*, not by good intentions.

This file is the pattern for dispute handling when the support system is the arbitration layer.

## What's Different From Normal Support

In a single-sided SaaS, support represents the customer to the company. In a marketplace, support represents *the platform* to two adversarial customers. The shifts:

| Single-sided | Marketplace |
|---|---|
| One ticketer, one issue | Two parties, possibly opposing accounts of the same event |
| Support advocates for the customer | Support advocates for the rules |
| Refund authority on behalf of the company | Refund decision splits cost between buyer, seller, platform |
| One source of evidence | Both sides submit evidence, may contradict |
| Outcome favors customer if ambiguous | Ambiguity must resolve to *the rules*, not "split the difference" |

## The `disputes` Table

```ts
export const disputes = pgTable("disputes", {
  id:                       uuid().primaryKey().defaultRandom(),
  orgId:                    uuid().notNull(),
  ticketId:                 uuid().notNull(),                     // master ticket
  buyerTicketId:            uuid(),                               // buyer-side facing ticket
  sellerTicketId:           uuid(),                               // seller-side facing ticket
  transactionId:            uuid().notNull(),
  buyerId:                  uuid().notNull(),
  sellerId:                 uuid().notNull(),
  claimedAmount:            numeric({ precision: 12, scale: 2 }).notNull(),
  currency:                 text().notNull(),
  reason:                   text().notNull(),                     // 'item_not_received' | 'not_as_described' | 'wrong_item' | 'damaged' | 'service_not_rendered' | 'unauthorized'
  reasonSubcategory:        text(),
  status:                   text().notNull(),                     // 'open' | 'evidence_buyer' | 'evidence_seller' | 'evidence_both' | 'review' | 'ruled' | 'appealed' | 'closed'
  openedAt:                 timestamp({ withTimezone: true }).notNull(),
  evidenceDeadlineBuyerAt:  timestamp({ withTimezone: true }),
  evidenceDeadlineSellerAt: timestamp({ withTimezone: true }),
  rulingDueAt:              timestamp({ withTimezone: true }),
  ruling:                   text(),                                // 'buyer_full_refund' | 'partial_refund_X' | 'seller_protected' | 'split_70_30' | 'platform_credit_buyer'
  rulingAmount:             numeric({ precision: 12, scale: 2 }),
  rulingNotes:              text(),
  ruledBy:                  uuid(),
  ruledAt:                  timestamp({ withTimezone: true }),
  appealedAt:               timestamp({ withTimezone: true }),
  appealReviewedBy:         uuid(),
  appealRuling:             text(),
  chargebackId:             uuid(),                                // if escalated to payment processor
  fraudFlags:               jsonb(),                                // pattern hits
  metadata:                 jsonb(),
  createdAt:                timestamp({ withTimezone: true }).defaultNow().notNull(),
  updatedAt:                timestamp({ withTimezone: true }).defaultNow().notNull(),
});

export const disputeEvidence = pgTable("dispute_evidence", {
  id:           uuid().primaryKey().defaultRandom(),
  disputeId:    uuid().notNull(),
  submittedBy:  uuid().notNull(),                       // buyer or seller user id
  submitterRole: text().notNull(),                      // 'buyer' | 'seller' | 'support'
  kind:         text().notNull(),                       // 'screenshot' | 'tracking_number' | 'message' | 'invoice' | 'photo' | 'video'
  storageKey:   text(),                                  // R2/S3 key for binary evidence
  description:  text(),
  visibleToCounterparty: boolean().default(true).notNull(),
  submittedAt:  timestamp({ withTimezone: true }).defaultNow().notNull(),
});
```

The two-ticket pattern (`buyerTicketId` and `sellerTicketId`) is important: each party has their own ticket-thread for their communications with support, but both threads link to the master `dispute`. Per [TICKET-LINKING-AND-RELATIONSHIPS.md](TICKET-LINKING-AND-RELATIONSHIPS.md), the dispute is the *anchor* and the two tickets are *related-by-dispute*.

## The Three-Stage Flow

### Stage 1 — Open

Buyer or seller opens a dispute via a structured form, not free-text. Reason is enum-bounded. Claimed amount is bounded by transaction amount.

```
┌── Open a dispute ────────────────────────────────────────────┐
│ Transaction: ORDER-2026-04-27-A91                            │
│ Counterparty: SellerCo                                       │
│ Amount: $129.99                                              │
│                                                              │
│ Reason (required): [v Item not received                  ]   │
│ Subcategory:        [v Tracking shows delivered, not received]│
│                                                              │
│ Describe what happened:                                      │
│ ┌──────────────────────────────────────────────────────┐    │
│ │ [...]                                                │    │
│ └──────────────────────────────────────────────────────┘    │
│                                                              │
│ Evidence (you can add more after opening):                  │
│ [+ Upload]                                                   │
│                                                              │
│ Refund amount you're requesting: [$129.99] (max: $129.99)    │
│                                                              │
│ [Open dispute]                                               │
└──────────────────────────────────────────────────────────────┘
```

On open, the system:

1. Creates the master `dispute` row.
2. Creates `buyer_ticket` (visible to buyer) and `seller_ticket` (visible to seller).
3. Sets evidence deadlines (typically 5–7 days each).
4. Notifies both parties — *with the same baseline information*.

The seller is told: "A dispute has been opened on ORDER-X. The buyer claims [reason]. You have until [date] to submit evidence."

### Stage 2 — Evidence

Both parties have a window to submit evidence. The system enforces:

- **Symmetric visibility by default.** Whatever the buyer submits, the seller sees, and vice versa. Hide-from-counterparty is the *exception* (e.g., personal address), not the rule.
- **Time-stamped, immutable evidence.** Once submitted, evidence cannot be retracted — it can be marked-disputed, but not deleted.
- **Required evidence by reason.** "Item not received" requires tracking lookup and shipping address; "not as described" requires photos.

```ts
const REQUIRED_EVIDENCE_BY_REASON: Record<string, EvidenceRequirement[]> = {
  item_not_received: [
    { role: 'seller', kind: 'tracking_number', required: true },
    { role: 'seller', kind: 'shipping_label_screenshot', required: false },
    { role: 'buyer',  kind: 'shipping_address_confirmation', required: true },
  ],
  not_as_described: [
    { role: 'buyer',  kind: 'photo', required: true, minCount: 1 },
    { role: 'seller', kind: 'listing_screenshot', required: false },
  ],
  damaged: [
    { role: 'buyer', kind: 'photo', required: true, minCount: 2 },
    { role: 'buyer', kind: 'packaging_photo', required: false },
  ],
  // ...
};
```

If a required piece of evidence is missing at the deadline, that side loses the inference (default ruling against them on that point). This is *the* lever that prevents stalling.

### Stage 3 — Ruling

After both evidence windows close, a support agent (or auto-rule for clear cases) issues a decision:

```ts
const RULING_KINDS = [
  'buyer_full_refund',          // buyer gets 100%, platform pulls from seller
  'buyer_partial_refund',       // buyer gets X%, seller keeps rest
  'seller_protected',           // seller wins; no refund
  'split_70_30',                // common compromise
  'platform_credit_buyer',      // platform absorbs cost (rare; for goodwill)
  'inconclusive_split',         // when neither side has evidence and amount low
];

interface Ruling {
  kind: typeof RULING_KINDS[number];
  amountToBuyer: number;
  amountToSeller: number;
  reasoning: string;            // shown to both parties
  citedRules: string[];         // policy IDs invoked
  citedEvidence: string[];      // evidence IDs the ruling weighs on
}
```

The ruling shows *to both parties* the same explanation: cited rules, cited evidence, dollar split. This is the single most important UX decision in the dispute flow — both parties read the same ruling, in the same words, with the same evidence.

```
┌── Dispute resolved ──────────────────────────────────────────┐
│ Dispute D-2026-04-27-117                                     │
│ Ruling: BUYER_PARTIAL_REFUND                                 │
│                                                              │
│ Buyer receives: $80.00 (out of $129.99 claimed)              │
│ Seller keeps:   $49.99                                       │
│                                                              │
│ Reasoning:                                                   │
│ The buyer demonstrated the item arrived damaged (photos      │
│ submitted 2026-04-25; packaging-damage visible). The seller  │
│ did not contest the photos but provided proof of intact      │
│ shipping condition (tracking weight matched listed weight).  │
│ Per Marketplace Policy 4.2 (shared damage liability), a      │
│ proportional refund is granted.                              │
│                                                              │
│ This ruling is final after a 7-day appeal window.            │
│                                                              │
│ [Appeal] [Acknowledge]                                        │
└──────────────────────────────────────────────────────────────┘
```

## Refund Authority Tiers

Refund authority is tiered (encode in policy + capability whitelist, per [POLICIES-PER-CATEGORY.md](POLICIES-PER-CATEGORY.md)):

| Tier | Authority | Notes |
|---|---|---|
| Auto | Up to $50 + clear-cut by rules engine | E.g., chargeback already filed by bank; tracking shows undelivered after 30d |
| T1 agent | Up to $200 | With both-sides documented |
| T2 agent | $200–$2,000 | Standard manual rulings |
| Manager | $2K–$10K | Includes seller suspensions |
| Chargeback specialist | > $10K or chargeback-eligible | Coordinates with payment processor |
| Legal | Disputes over $25K, or alleging fraud requiring law enforcement | Holds, evidence preservation per [FORENSICS-AND-LITIGATION-HOLDS.md](FORENSICS-AND-LITIGATION-HOLDS.md) |

## Neutrality Protocols

The structural defenses against bias:

1. **Same-time notification.** When a dispute opens, both parties are notified at the same instant.
2. **Symmetric evidence visibility.** Evidence one side submits is shown to the other (with redaction only for genuine PII).
3. **Same ruling text shown to both.** Don't tell the buyer "we found in your favor" while telling the seller "the buyer was rude." Both read the same words.
4. **Random assignment of disputes to agents.** Avoid giving one agent a beat covering one type of seller — bias forms.
5. **Two-pass review for amounts > $X.** Senior agent reviews after T2 ruling but before notification.
6. **Bias monitoring.** Track per-agent ruling patterns. Agent ruling 90% buyer-favorable on close calls is a flag (could be right; could be biased).

```ts
async function detectAgentRulingBias() {
  const agents = await getActiveDisputeAgents();
  for (const a of agents) {
    const rulings = await getAgentRulings(a.id, { lookbackDays: 90 });
    const closeCallRulings = rulings.filter(r => r.evidence_balance === 'close');
    const buyerFavorablePct = closeCallRulings.filter(r => r.beneficiary === 'buyer').length / closeCallRulings.length;

    if (buyerFavorablePct > 0.85 || buyerFavorablePct < 0.15) {
      await flagForReview({ agentId: a.id, metric: 'close_call_bias', pct: buyerFavorablePct });
    }
  }
}
```

## Buyer Protection vs Seller Protection Tradeoff

Marketplaces choose where to land on this spectrum. The choice is structural, not per-dispute:

| Strategy | Buyer-favoring | Balanced | Seller-favoring |
|---|---|---|---|
| Examples | eBay, Etsy, Amazon | Mercari, Reverb | Uber driver claims, freelance platforms |
| Default for ambiguity | Buyer wins | Split or rules-based | Seller wins |
| Required evidence | Heavy on seller | Symmetric | Heavy on buyer |
| Reputation effect | Seller risk; buyers trust | Some friction both sides | Driver/freelancer risk; users distrust |

Pick consciously. A platform that "tries to be balanced" while the *implementation* defaults to buyer wins is dishonest with sellers. Document the choice publicly in the policies.

## Fraud-Pattern Detection

Disputes are also a high-signal source for fraud:

```ts
const FRAUD_PATTERNS = [
  {
    name: 'serial_buyer_disputer',
    detect: async (b: Buyer) => {
      const r = await getDisputeRate(b.id, 90);
      return r.disputesPerOrder > 0.30 && r.totalOrders >= 10;   // 30%+ of orders disputed
    },
  },
  {
    name: 'fresh_account_high_value_dispute',
    detect: async (b: Buyer) => {
      return b.accountAgeDays < 30 && pendingDisputeAmount(b.id) > 500;
    },
  },
  {
    name: 'seller_against_repeated_buyer',
    detect: async (s: Seller) => {
      const buyerCounts = await getDisputingBuyersAgainstSeller(s.id, 90);
      return Math.max(...buyerCounts.values()) >= 3;        // same buyer disputing 3× the same seller
    },
  },
  {
    name: 'address_in_high_risk_zone',
    detect: async (b: Buyer) => isHighRiskShippingZone(b.shippingAddress),
  },
  {
    name: 'tracking_says_delivered_but_dispute_immediate',
    detect: async (d: Dispute) =>
      d.reason === 'item_not_received' && hasDeliveryConfirmation(d) && hoursBetween(d.openedAt, d.deliveryConfirmedAt) < 24,
  },
];
```

A buyer matching multiple patterns gets escalated to chargeback specialist before rulings; a seller matching patterns gets review for marketplace suspension. Per [SPAM-ABUSE-HOSTILE-USERS.md](SPAM-ABUSE-HOSTILE-USERS.md), fraud is a separate process from genuine dispute resolution.

## Chargeback Coordination

When the buyer files a chargeback with their bank instead of (or after) opening a dispute:

```ts
async function onChargebackReceived(c: Chargeback) {
  const existingDispute = await findExistingDispute({ transactionId: c.transactionId });

  if (existingDispute && existingDispute.status === 'open') {
    // Buyer went to bank in parallel — common signal of impatience or escalation
    await convertDisputeToChargeback(existingDispute.id, c.id);
  }

  await prepareChargebackEvidence({
    chargebackId: c.id,
    evidence: assembleEvidenceFromDispute(existingDispute),
    deadline: c.responseDeadline,
  });
}
```

Chargeback responses have hard deadlines (often 7–14 days from notification). Miss the deadline and you lose by default. The dispute system must surface chargeback-eligible disputes urgently.

## Marketplace-Specific Rules

The dispute logic varies by marketplace shape:

| Shape | Dispute character | Examples |
|---|---|---|
| **Goods (eBay-like)** | Item-condition / shipping disputes; tracking-driven | eBay, Mercari |
| **Crafted goods (Etsy-like)** | "Not as described" common; subjective | Etsy, Reverb |
| **Services (Uber-like)** | Service-rendered vs not; ride-quality disputes | Uber, DoorDash |
| **Freelance (Upwork-like)** | Scope and milestone disputes; complex evidence | Upwork, Fiverr |
| **Tickets (StubHub-like)** | Time-bounded; can't redo if event passed | StubHub, Ticketmaster |
| **Rentals (Airbnb-like)** | Two-party + property; long evidence trails | Airbnb, Vrbo |

Each shape has its own evidence ontology and ruling templates. Don't try to use one set of rules across all of them.

## Volume And SLA

Disputes are slow-burn relative to normal support tickets. Reasonable SLA targets:

| Stage | Target | Rationale |
|---|---|---|
| First-response (master ticket) | 24h | Acknowledge dispute opened |
| Evidence window per side | 5–7 days | Reasonable to gather |
| Agent review of complete evidence | 2 business days | Real evaluation time |
| Total time-to-ruling | 14 days | Standard expectation |
| Appeal review | 7 days | Fast track for clear errors |

Per [SLA-AS-CONTRACT.md](SLA-AS-CONTRACT.md), these are *external commitments* and need to be in the marketplace policies.

## Mock Agent Dispute UI

```
┌── Dispute D-2026-04-27-117 ──────────────────────────────────┐
│ Status: REVIEW (evidence both sides closed 2h ago)           │
│ Buyer: jane@example.com   Seller: handcrafted-co             │
│ Amount claimed: $129.99    Reason: damaged                    │
│                                                              │
│ EVIDENCE (visible to both):                                  │
│   Buyer:                                                     │
│     • Photo of damaged item (3 angles, timestamped 4-25)     │
│     • Original packaging photo                                │
│   Seller:                                                    │
│     • Listing photo (pre-shipment)                            │
│     • Carrier weight log                                      │
│                                                              │
│ POLICY MATCHES:                                              │
│   • 4.2 — Shared damage liability when packaging shows wear  │
│   • 7.1 — Buyer-photo evidence is presumed valid if          │
│           timestamped within 48h of receipt                   │
│                                                              │
│ FRAUD FLAGS: none                                            │
│                                                              │
│ SUGGESTED RULING (from rules engine):                        │
│   buyer_partial_refund — $80 to buyer, $49.99 to seller      │
│   Confidence: 0.78                                            │
│                                                              │
│ [Apply suggested ruling]  [Override and rule manually]       │
└──────────────────────────────────────────────────────────────┘
```

## Anti-Patterns

| ✗ | Why |
|---|---|
| Free-text "reason" instead of enum | Can't run rules engine, can't aggregate, can't measure fraud patterns |
| One ticket shared by buyer and seller | Privacy disasters; one party reads the other's private details |
| Different ruling text shown to each side | Trust collapse if they ever compare; they will |
| No evidence deadlines | Disputes drag forever; both sides game it |
| Refund authority unbounded per agent | Massive cost variance, no audit pattern |
| Auto-favor buyer on ambiguity without disclosing the policy | Sellers feel cheated when they discover the rule |
| Not tracking per-agent ruling patterns | Bias goes undetected for years |
| Chargeback deadlines missed | Lose by default; lose appeal too |
| No fraud-pattern detection on disputes | Marketplace becomes a fraudster honeypot |
| Treating disputes as normal support tickets | Wrong SLA, wrong evidence model, wrong UI |
| Same evidence required regardless of claim | "Item not received" doesn't need photos; "damaged" does |
| Appeal goes back to the same agent | No second opinion; rulings re-ratified |

## Wire Points Checklist

- [ ] `disputes` and `dispute_evidence` tables with master/buyer/seller-ticket linking
- [ ] Structured open-dispute form (enum reason, bounded amount)
- [ ] Symmetric evidence visibility by default
- [ ] Required-evidence enforcement per reason
- [ ] Dual-deadline enforcement (buyer + seller)
- [ ] Same ruling text shown to both parties
- [ ] Refund-authority caps encoded in capability whitelist (per [POLICIES-PER-CATEGORY.md](POLICIES-PER-CATEGORY.md))
- [ ] Per-agent ruling-bias detection
- [ ] Fraud-pattern engine on dispute volume
- [ ] Chargeback integration with hard deadline tracking
- [ ] Marketplace-shape-specific rules (goods vs services vs rentals)
- [ ] Appeal flow goes to a different agent than the original ruler
- [ ] Cross-link to [FORENSICS-AND-LITIGATION-HOLDS.md](FORENSICS-AND-LITIGATION-HOLDS.md) for high-value disputes
- [ ] Cross-link to [SPAM-ABUSE-HOSTILE-USERS.md](SPAM-ABUSE-HOSTILE-USERS.md) for fraud escalation
- [ ] Public marketplace policies document the rules invoked in rulings
- [ ] Test: dispute auto-closes against side that misses evidence deadline
- [ ] Test: ruling text identical for buyer and seller view
- [ ] Test: agent cannot rule on dispute they have a relationship to
