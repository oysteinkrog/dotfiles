# Forensics And Litigation Holds

When a subpoena, civil discovery request, regulatory inquiry, or internal investigation lands, the support system holds material evidence: customer-vendor communications, refund decisions, abuse reports, fraud signals, security disclosures. The schema must be ready *before* legal asks. This file is the architectural pattern for forensic-grade preservation, e-discovery, and litigation-hold workflow.

## When This Matters

- Subpoena from law enforcement requiring records production
- Civil litigation: customer suing vendor; vendor suing customer
- Regulatory inquiry (FTC, FDA, SEC, Consumer Protection bureaus, GDPR DPA)
- Internal investigation: HR matter, fraud, IP theft
- Public-safety request (CSAM, threats, imminent harm)
- Patent or trademark dispute referencing customer communications

In any of the above, the system must:

1. **Identify** all responsive records
2. **Preserve** them against deletion (litigation hold)
3. **Produce** them in a defensible chain of custody
4. **Audit** every access to them after the hold is in place

## Litigation Holds

A litigation hold suspends the normal retention/deletion lifecycle for matched records. Implementation:

```ts
export const litigationHolds = pgTable("litigation_holds", {
  id:                  uuid().primaryKey().defaultRandom(),
  matterId:            text().notNull().unique(),     // legal matter reference
  description:         text().notNull(),
  initiatedBy:         uuid().notNull().references(() => users.id),
  initiatedAt:         timestamp({ withTimezone: true }).defaultNow().notNull(),
  scope:               jsonb().notNull(),              // { userIds, ticketIds, dateRange, categories }
  status:              text().notNull(),               // 'active' | 'released'
  releasedAt:          timestamp({ withTimezone: true }),
  releasedBy:          uuid(),
  releaseReason:       text(),
  legalContact:        text().notNull(),               // outside counsel email
});

export const litigationHoldRecords = pgTable("litigation_hold_records", {
  id:               uuid().primaryKey().defaultRandom(),
  holdId:           uuid().notNull().references(() => litigationHolds.id),
  recordType:       text().notNull(),                  // 'ticket' | 'message' | 'audit_log' | 'attachment' | 'user'
  recordId:         uuid().notNull(),
  preservedAt:      timestamp({ withTimezone: true }).defaultNow().notNull(),
  recordHash:       text().notNull(),                  // SHA-256 of record content at preservation
});
```

Every record under hold becomes effectively read-only:

```ts
async function deleteRecord(recordType: string, recordId: string) {
  if (await isUnderHold(recordType, recordId)) {
    throw new LitigationHoldError(`Record ${recordType}/${recordId} is under litigation hold ${holdId}; cannot delete`);
  }
  // proceed
}
```

The same applies to GDPR erasure (per [OFFBOARDING-AND-ACCOUNT-DELETION.md](OFFBOARDING-AND-ACCOUNT-DELETION.md)) — a litigation hold *overrides* the right-to-erasure for the duration of the hold. Document this conflict explicitly with legal.

## Chain Of Custody

Every access to held records is logged with stronger audit than normal:

```ts
async function accessHeldRecord(holdId: string, recordId: string, accessor: string, purpose: string) {
  // Strong audit: include IP, user agent, accessor's role, purpose, and access type
  await auditLog.insert({
    actionType: "litigation_hold_access",
    actorId: accessor,
    actorRole: await getUserRole(accessor),
    metadata: {
      holdId,
      recordId,
      purpose,
      accessType: "read",
      ipAddress: getClientIp(),
      userAgent: getUserAgent(),
      timestamp: new Date().toISOString(),
    },
  });
  return await getRecord(recordId);
}
```

Periodically (daily for active holds), export the audit trail and submit to legal counsel — chain of custody requires *contemporaneous* documentation, not retroactive reconstruction.

## Tamper-Evident Storage

For high-stakes matters, write-once preservation is necessary. Implementation patterns:

1. **Append-only audit log**: configure Postgres triggers to deny updates/deletes on `auditLog`
2. **WORM storage**: copy held records to S3 Object Lock (write-once-read-many) buckets with retention policy matching the hold duration
3. **Cryptographic notarization**: hash each record + audit entry; chain hashes; submit chain-tip hash to a public timestamping service (Bitcoin/Ethereum, RFC 3161 TSA, OpenTimestamps)

```ts
// Daily snapshot of held records
async function snapshotHoldsForLegal() {
  const holds = await db.select().from(litigationHolds).where(eq(litigationHolds.status, 'active'));
  for (const hold of holds) {
    const records = await getHeldRecords(hold.id);
    const manifest = records.map(r => ({
      recordType: r.recordType,
      recordId: r.recordId,
      contentHash: r.recordHash,
      preservedAt: r.preservedAt,
    }));
    const manifestHash = sha256(JSON.stringify(manifest));

    await s3.putObject({
      Bucket: "legal-hold-snapshots",
      Key: `${hold.matterId}/snapshots/${todayIso()}.json`,
      Body: JSON.stringify({ hold, manifest, manifestHash }),
      ObjectLockMode: "COMPLIANCE",
      ObjectLockRetainUntilDate: hold.expectedReleaseDate,
    });
  }
}
```

## E-Discovery Production

Producing records to opposing counsel:

```ts
async function exportForProduction(holdId: string, options: ProductionOptions) {
  const records = await getHeldRecords(holdId);
  const bates = new BatesNumberer(options.batesPrefix);   // e.g., "ACME-001234"

  const package = {
    matter: hold.matterId,
    productionDate: new Date().toISOString(),
    productionId: ulid(),
    custodian: options.custodian,
    records: [] as ProducedRecord[],
  };

  for (const record of records) {
    const content = await loadRecord(record);
    const redacted = options.redactionRules ? applyRedactions(content, options.redactionRules) : content;
    const batesNumber = bates.next();

    package.records.push({
      batesNumber,
      type: record.recordType,
      content: redacted,
      contentHash: sha256(JSON.stringify(redacted)),
      originalHash: record.recordHash,
      redactionsApplied: options.redactionRules?.applied ?? [],
    });
  }

  // Sign the package with the company's signing key
  const signature = await signPackage(package);
  return { package, signature };
}
```

Production format options:

| Format | When |
|---|---|
| EDRM XML / Concordance load file | Civil litigation in U.S. |
| PDF/A | Smaller productions; immutable |
| JSON Lines | Tech-savvy opposing counsel; modern e-discovery tools |
| CSV | Simple matters; depositions |
| Native + load file | Most common for U.S. civil discovery |

## Privilege Review

Before producing, identify privileged records (attorney-client, work product, settlement-protected) and flag for review:

```ts
const privilegePatterns = [
  /\battorney(?:[-\s]client)?\s+privilege\b/i,
  /\bwork\s+product\b/i,
  /\bsettlement\s+communication\b/i,
  /\bprivileged\s+(?:and|&)\s+confidential\b/i,
];

function isLikelyPrivileged(content: string): { privileged: boolean; matchedTerms: string[] } {
  const matches: string[] = [];
  for (const pattern of privilegePatterns) {
    if (pattern.test(content)) matches.push(pattern.source);
  }
  return { privileged: matches.length > 0, matchedTerms: matches };
}
```

Don't auto-redact based on this — flag for outside counsel to review. False negatives are common; only an attorney can decide privilege.

## Records Hold Categories

Different matters need different preservation scope:

| Matter type | Typical scope |
|---|---|
| Patent infringement | Tickets mentioning the alleged infringing feature; emails to/from named engineers |
| Class action consumer | All tickets in the affected category over the class period |
| Employment / HR | Specific employee's tickets/access; complaint records |
| Regulatory inquiry (FTC) | Tickets matching specific keywords; all advertising claims |
| Subpoena (criminal) | Specific user's full history; payment records; IPs and timestamps |
| Tax audit | Billing-related tickets; refund decisions; revenue-recognition support |
| GDPR / DPA inquiry | Data subject's full record; consent decisions; deletion requests |
| Internal fraud investigation | Suspect's tickets, audit log, sessions, IPs |

The `scope` JSONB on `litigationHolds` should be expressive enough to capture each:

```ts
type HoldScope =
  | { kind: "user"; userIds: string[] }
  | { kind: "category"; categories: string[]; dateRange: [Date, Date] }
  | { kind: "keyword"; terms: string[]; dateRange: [Date, Date] }
  | { kind: "ticket"; ticketIds: string[] }
  | { kind: "compound"; conditions: HoldScope[] };
```

## Hold Notification

When a hold goes into effect, notify potential custodians (people who hold records):

```
[CONFIDENTIAL — DO NOT FORWARD]

A legal matter has triggered a litigation hold affecting [scope].

You may have records related to this matter. Effective immediately:

  • DO NOT delete tickets, messages, attachments, or audit records related to: [matter description]
  • The system has automatically suspended deletion for matched records
  • Continue normal support work; the hold runs in the background
  • Direct any questions to: [legal contact]

This notice is itself a record under hold.
```

Send via email + acknowledgment-required modal in admin UI. Track who acknowledged and when.

## Hold Release

When the matter resolves, release explicitly:

```ts
async function releaseHold(holdId: string, releaserId: string, reason: string) {
  await db.transaction(async tx => {
    await tx.update(litigationHolds).set({
      status: 'released',
      releasedAt: new Date(),
      releasedBy: releaserId,
      releaseReason: reason,
    }).where(eq(litigationHolds.id, holdId));

    await auditLog.insert({
      actionType: "litigation_hold_released",
      actorId: releaserId,
      metadata: { holdId, reason, recordsReleased: countHeldRecords(holdId) },
    });
  });
  // Records are now subject to normal retention/deletion lifecycle
}
```

After release, normal GDPR / retention deletion can proceed for previously-held records (subject to other holds that may apply).

## Forensic Investigation Playbook

When a fraud or abuse case opens:

1. **Identify** the suspect account(s) and known associates
2. **Preserve** with a litigation hold scoped to the suspect + 90-day window
3. **Snapshot** logs: support tickets, audit log, payment events, login history, IPs
4. **Correlate**: cluster by IP, payment method, device fingerprint, behavior patterns
5. **Document**: timeline of suspect's actions tied to specific evidence
6. **Hand off** to legal/security with chain-of-custody intact

Key data points for fraud forensics (per [SPAM-ABUSE-HOSTILE-USERS.md](SPAM-ABUSE-HOSTILE-USERS.md)):

```ts
type FraudEvidence = {
  user: { id: string; createdAt: Date; signupIp: string; signupUserAgent: string };
  loginHistory: Array<{ at: Date; ip: string; userAgent: string; location: GeoIp }>;
  paymentEvents: Array<{ at: Date; amount: number; method: string; chargebackAt?: Date }>;
  tickets: Array<{ id: string; subject: string; createdAt: Date; refundIssued?: number }>;
  auditEvents: AuditLogEntry[];
  associatedAccounts: string[];   // by IP, payment, device
};
```

## Subpoena Response Workflow

Receipt of a subpoena triggers a fixed sequence:

```
Day 0: Subpoena arrives → log in legal-tracker; start litigation hold immediately
Day 1: Outside counsel notified; scope defined; engineering & support contacted
Day 2-7: Preservation completed; production package drafted
Day 8-14: Privilege review; counsel signs off
Day 15-20: Production sent; chain-of-custody documented
Day 21+: Continued hold pending matter resolution
```

Some subpoenas have non-disclosure clauses — *do not* notify the affected user. Build a flag:

```ts
{
  noticeToSubject: false,                  // user must NOT be told
  noticeReason: "law_enforcement_request",
}
```

## Anti-Patterns

| ✗ | Why |
|---|---|
| Hold scoped only to "the database, all of it" | Burdensome; production impossible; courts often reject |
| Deleted records "weren't on hold yet" | Sanctions for spoliation; counsel's career nightmare |
| User notified of subpoena under non-disclosure | Obstruction of justice possible |
| GDPR erasure executed during active hold | Violates legal preservation duty |
| No chain-of-custody documentation | Production not admissible |
| Hold released without legal sign-off | Records destroyed; can't reconstruct |
| Production without privilege review | Privileged content waived; opposing counsel exploits |
| Manual gathering of records each time | Inconsistent; slow; error-prone |
| Deleted attachments before hold | Spoliation; can be presumed adverse |
| No daily snapshot of held records | Drift between recorded state and produced state |
| Same employee initiates and releases the hold | Lack of separation of duties |
| Held records readable by random support agents | Privileged info leaks; chain compromised |

## Wire Points Checklist

- [ ] `litigation_holds` and `litigation_hold_records` tables
- [ ] Deletion path checks for active hold; throws on conflict
- [ ] GDPR erasure path checks for active hold; defers and notifies counsel
- [ ] Strong audit on every held-record access
- [ ] Daily snapshot to WORM storage with cryptographic hash
- [ ] Production export pipeline (load file, Bates numbering, signature)
- [ ] Privilege review pass before production
- [ ] Hold-notification flow with acknowledgment tracking
- [ ] Hold-release flow with separation of duties
- [ ] Subpoena-response runbook documented
- [ ] Non-disclosure flag respected by all surfaces (no automated user notifications)
- [ ] Forensic-evidence query patterns (login history, payment, IP cluster)
- [ ] Outside counsel contact field on every hold
- [ ] Test: deleting held record fails with explanatory error
- [ ] Test: GDPR request defers when hold active
- [ ] Test: every access to held record logs IP, agent, purpose
- [ ] Annual tabletop exercise: simulate subpoena response
