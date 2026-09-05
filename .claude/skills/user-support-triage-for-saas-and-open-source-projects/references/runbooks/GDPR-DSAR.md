# Runbook: GDPR / Data Subject Access Request (DSAR)

A user invokes their EU/UK data rights. **Time-bound (1 month, extendable +2 by notice). Mishandling = ICO complaint + €20M / 4% turnover fines.**

## Trigger Conditions

- "Right of access" / "give me my data" / "Article 15"
- "Right to be forgotten" / "delete my account and all data" / "Article 17"
- "Data portability" / "export my data" / "Article 20"
- "Restrict processing" / "object to processing" (Articles 18, 21)
- A formal letter from a privacy authority (ICO, CNIL, DPA)
- Any explicit "GDPR" mention from an EU/UK customer

## First 72 Hours

1. **Acknowledge receipt within 72 hours.** Even if you can't fulfill yet.
2. **Verify identity (Article 12.6).** Don't disclose to someone who's not the data subject. Methods:
   - Logged-in account verification (their session matches the request)
   - Email verification from the address on file
   - Last-4 of payment method (don't store; verify via Stripe)
   - For high-stakes: government-ID (collect, don't store)
3. **Log the request:** date, type, contact, identity-verification method used.
4. **Start a 30-day clock** from the date of receipt. If complex, you can extend by 2 months but MUST notify the requester within the first month.

## Article 15 — Right of Access

What to provide (Recital 63 + Article 15.1):
- Confirmation of processing
- Categories of personal data being processed
- Recipients (or categories) the data was disclosed to
- Retention period or criteria
- Source of the data if not collected from the subject
- Whether automated decision-making (including profiling) occurs
- A copy of the personal data itself

**Format**: machine-readable (JSON / CSV) is best practice; PDF is acceptable. If many exports, provide a download link valid for 14+ days.

**Pulling the data** — typical SaaS:

```sql
-- User profile + auth
SELECT * FROM users WHERE id = '<user_id>';
SELECT * FROM sessions WHERE user_id = '<user_id>';
SELECT * FROM oauth_accounts WHERE user_id = '<user_id>';

-- Subscription + billing
SELECT * FROM subscriptions WHERE user_id = '<user_id>';
SELECT * FROM payment_events WHERE user_id = '<user_id>';

-- Activity / events
SELECT * FROM events WHERE user_id = '<user_id>' ORDER BY ts DESC;

-- User-generated content
SELECT * FROM <project-specific tables>;

-- Support history
SELECT * FROM support_tickets WHERE user_id = '<user_id>';
SELECT m.* FROM support_messages m
  JOIN support_tickets t ON m.ticket_id = t.id
  WHERE t.user_id = '<user_id>';

-- Audit log (their actions only — NOT admin actions on them, those are
-- legitimate-interest)
SELECT * FROM audit_log WHERE actor_user_id = '<user_id>';
```

Bundle as a ZIP with one CSV/JSON per table, plus a `README.md` describing each.

## Article 17 — Right to Erasure ("Right To Be Forgotten")

**Erasure is not absolute.** You can refuse if:
- Legal obligation requires retention (e.g., tax records — typically 7 years)
- Legitimate interest in defending legal claims
- Public interest archiving / scientific research / journalistic
- Freedom of expression

**What to delete (typical SaaS):**

```sql
-- 1. Anonymize or delete user-controllable rows
UPDATE users SET
  email = 'erased-' || id || '@example.invalid',
  display_name = 'Erased User',
  avatar_url = NULL,
  deleted_at = NOW(),
  erased_at = NOW(),
  -- keep id (referenced by audit logs); delete everything else identifiable
WHERE id = '<user_id>';

-- 2. Delete content the user explicitly created and asked to forget
DELETE FROM user_content WHERE user_id = '<user_id>';

-- 3. Anonymize support messages but keep the ticket structure
UPDATE support_messages SET
  message = '[content erased per GDPR Article 17 on ' || NOW() || ']'
WHERE sender_id = '<user_id>';

-- 4. Audit log: pseudonymize. Don't delete (legitimate interest).
UPDATE audit_log SET
  actor_email = 'erased-' || actor_user_id || '@example.invalid'
WHERE actor_user_id = '<user_id>';

-- 5. Sessions / tokens
DELETE FROM sessions WHERE user_id = '<user_id>';
DELETE FROM oauth_tokens WHERE user_id = '<user_id>';

-- 6. Payment provider — DELETE the customer there too
-- stripe customers delete cus_XXX
-- paypal subscriptions cancel  (if not already)
```

**Backups**: erasure SHOULD propagate to backups, but courts have accepted "next-restore" deletion (i.e., don't restore the erased user; mark them in a tombstone log). Document your stance.

**Don't forget**:
- Email lists (Mailchimp / SendGrid / Resend lists)
- Analytics platforms (Mixpanel, GA4, PostHog) — most have user-deletion APIs
- Logging providers (Datadog, Logflare)
- Customer-success tools (Intercom, Pylon)
- Any third-party support tool that has the user's data
- File storage (S3 / R2 user-uploaded files)
- AI-training corpora (if you've used customer data for fine-tuning, that's a separate problem)

## Article 20 — Data Portability

Like Article 15, but **machine-readable + commonly used format** required. JSON is canonical. Provide for portability to ANOTHER controller (i.e., the user wants to take it to a competitor).

## Article 18 — Restriction of Processing

User asks you to *stop processing* but not delete. Common scenario: contesting accuracy. Implement by:
- Adding a `processing_restricted` flag to the user row
- Excluding restricted users from analytics + ML training
- Continuing storage but no active use

## Drafts

### DSAR-ACK

```
Thanks — we received your request on <DATE>. Under GDPR Article 12, we'll
respond within 30 days. If your request is complex, we may extend by 2
months and will notify you before <DATE+30> if so.

To verify your identity, we need: <one of: a reply from your account
email; the last 4 digits of your payment method; for high-volume requests,
a government-issued ID (we'll delete it after verification)>.

Once verified, we'll proceed with: <Right of Access / Erasure / Portability>.

Questions? Reply here.
```

### DSAR-ACCESS-FULFILLED

```
Here's everything we hold about you: <link, valid 14 days>.

Format: ZIP containing one CSV per data category, plus a README explaining
each file. If anything is unclear, reply and we'll explain.

If you'd like portability (taking this to another service), let us know
and we can adjust the format.

Closing this request as fulfilled. Reply within 30 days if you need
clarification or more data.
```

### DSAR-ERASURE-FULFILLED

```
Erasure complete. As of <DATE>:

- Account deactivated; profile data anonymized
- Session tokens revoked
- User-generated content deleted: <list>
- Payment provider record deleted (Stripe customer cus_XXX removed)
- Email list subscriptions removed
- Third-party services notified: <list>

What we retained, and why:
- Audit log entries (pseudonymized) — Article 17(3)(e), legitimate interest
  in defending legal claims
- Tax / billing records (7 years) — Article 17(3)(b), legal obligation
- Backups: will not be restored to identifiable form on next restore

You may file a complaint with your supervisory authority if you disagree:
ICO (UK) https://ico.org.uk | CNIL (FR) https://cnil.fr | etc.

Sorry to see you go.
```

### DSAR-ERASURE-PARTIAL-DECLINE

```
Most of your erasure request is complete (see list below). However, some
items must be retained:

- <retained category>: <legal basis>
- ...

You have the right to challenge this with your supervisory authority. If
you believe our basis is wrong, please reply with specifics and we'll
re-evaluate.
```

### DSAR-CCPA / CPRA (California)

CCPA differs from GDPR. Key:
- 45-day window (extendable 45 more)
- "Right to know" + "right to delete" + "right to opt-out of sale/sharing"
- No identity-verification standard as strict as GDPR
- "Do Not Sell" link required if you sell/share data

Covered later in `runbooks/CCPA.md`.

## Identity Verification Templates

```
To verify your identity before proceeding:

Option 1: Reply from <email-on-file>
Option 2: Send the last 4 digits of your most recent payment method (we'll
          verify with Stripe and not store)
Option 3: For high-volume requests, send a redacted ID showing your name
          and DOB (we'll delete after verification)

This is required by GDPR Article 12.6 to prevent unauthorized disclosure.
```

## Anti-Patterns

| Don't | Why |
|---|---|
| Process without verifying identity | Could disclose to an attacker |
| Delete `users.email` while keeping `audit_log.actor_email` text | Incomplete erasure → re-DSAR |
| Refuse politely and hope they go away | They'll file with the regulator |
| Auto-delete on request without re-confirmation | Some users mean "deactivate", not "erase" |
| Forget Mailchimp / Intercom / Mixpanel / etc. | Third-party data leaks → another DSAR |
| Take >30 days without extending notice | Article 12 violation; ICO/DPA case |
| Ask for excessive verification (passport + bank + utility bill) | "Excessive" verification is itself a violation |
| Send the export over unencrypted email | Sensitive PII in transit |

## Audit Trail (Required)

Log every DSAR:
- Date received, date acknowledged, date fulfilled
- Type (access / erasure / portability / restriction)
- Identity verification method
- Data categories disclosed / erased
- Any retentions + their legal basis
- Approver

Store for 3+ years for accountability (Article 5(2)).

## Companion Reading

- ICO DSAR guidance: https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/individual-rights/right-of-access/
- EDPB Guidelines 01/2022 on data subject rights — right of access
- WP29 Guidelines on the right to data portability
- For Switzerland (FADP), Brazil (LGPD), South Korea (PIPA): similar patterns; check jurisdiction-specific rules.
