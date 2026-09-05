# Runbook: ACCOUNT-RECOVERY

A user can't access their account. The single most common ticket category in B2C SaaS, and the one most often handled badly — either by being too lax (account-takeover risk) or too strict (locks out the real owner).

## Triggers

- "I forgot my password"
- "I'm locked out / account suspended"
- "2FA isn't working" / "lost my authenticator"
- "I changed phones and lost my SSO"
- "Magic link isn't arriving"
- "My account was deleted but I didn't delete it"
- "Someone else has my email" / disputed ownership

## Hard Rule: Identity Verification First

**Never** restore access without verifying the requester. The default verification — magic link to email of record — is sufficient for self-serve cases. For ambiguous cases, raise the bar.

### Verification Levels

| Signal in ticket | Required verification |
|---|---|
| Standard password reset | Magic link to email on file (self-serve) |
| Email-of-file inaccessible | Backup methods (recovery email / SMS) OR identity check |
| 2FA reset | Backup codes OR identity check |
| Disputed account ownership | Government ID + matching billing details |
| Suspended for ToS / fraud | Owner-only path; do not unsuspend on customer request alone |

### Identity Check (When Magic Link Fails)

Ask for at least 2 of:
1. Last 4 digits of payment card on file
2. Approximate signup date (month + year)
3. Specific feature usage history (project name, team count)
4. Billing email if different from login email
5. Plan tier and approximate billing amount

If they can answer 2+, proceed. If not, escalate to owner — don't make the call alone.

## Investigation Procedure

```bash
# 1. Find the account by email
curl -s "$BASE/api/admin/users?email=$EMAIL" \
  -H "Authorization: Bearer $ADMIN_KEY"

# 2. Recent auth events
psql -c "SELECT event_type, ip, ts FROM auth_events
         WHERE user_id = '<id>' ORDER BY ts DESC LIMIT 20;"

# 3. Status of the account
psql -c "SELECT id, email, status, suspended_at, suspended_reason
         FROM users WHERE id = '<id>';"

# 4. 2FA / SSO state
psql -c "SELECT type, last_used_at, backup_codes_remaining
         FROM auth_methods WHERE user_id = '<id>';"

# 5. Recent password resets / magic links
psql -c "SELECT type, ts, ip FROM auth_tokens
         WHERE user_id = '<id>' AND ts > NOW() - INTERVAL '7 days';"
```

## Common Failure Modes

### A. Magic Link Not Arriving

Causes (in order of likelihood):
1. Email going to spam (most common)
2. Email-provider blocking (corporate gmail; gmail security)
3. Resend / SendGrid bounced — check delivery logs
4. Wrong email address typed
5. Domain reputation issue (your sender domain is blacklisted)

Diagnosis:
```bash
# Resend delivery log. Same RESEND_API_KEY env var as the email pipeline.
curl -s "https://api.resend.com/emails?to=$EMAIL" \
  -H "Authorization: Bearer $RESEND_API_KEY"
```

Fix path:
1. Check spam folder
2. Try alternate channel (admin-issued one-time login link sent via the in-app inbox)
3. Whitelist your sender domain at the user's mail provider
4. Re-send from a different sender address

### B. 2FA Lost (Phone Replaced / Authenticator App Wiped)

```
Verification: standard identity check (above)
                ↓ verified
Disable 2FA for the user temporarily
        ↓
User logs in with password
        ↓
User sets up 2FA fresh on new device
        ↓
Enable 2FA again; confirm working
```

**Don't** keep 2FA disabled. Re-enable as soon as they're back in.

### C. SSO Provider Changed

If the user signed up with Google, then their Google account was deleted/changed:

```
1. Confirm via identity check (matching email, last login IP, billing)
2. Convert account from SSO-Google → password-based
3. Send password-set magic link to email of record
4. User sets password
5. (Optional) Re-link a different SSO provider
```

### D. Account Suspended

```
Read suspension record:
  - Reason cited
  - Who suspended (manual / automated)
  - Date

Decision tree:
- Manual suspension by owner → DO NOT auto-unsuspend; route to owner
- Automated for fraud (chargeback abuse) → DO NOT unsuspend; review evidence
- Automated for spam abuse → DO NOT unsuspend; check fingerprint
- Automated for unpaid invoice → user can self-serve via Stripe portal
- "Inactive cleanup" → restore + apologize
```

### E. Disputed Ownership

Two people claim the same account. This is rare but high-stakes:

```
1. Lock the account (no logins from either party)
2. Both parties asked to provide identity proofs
3. Owner reviews evidence:
   - Original signup IP
   - Payment method history (which person's card?)
   - Email domain match
   - Communication history
4. Decision: restore to verified original owner
5. Communicate decision to BOTH parties (rejected gets export of their personal contributions if any)
```

This case has legal teeth — document everything. Counsel may be appropriate for disputed enterprise accounts.

### F. Account Said "Deleted But I Didn't"

Check audit log:
- Was there a delete event? When? From which IP?
- Was it from the user themselves or admin?
- Account-recovery still possible? (Soft-delete? Backup?)

If user honestly didn't initiate deletion: this is a security incident.
- Force password reset on their email provider (suggest)
- Check their other auth events for compromise indicators
- Restore from soft-delete or backup
- Report findings honestly: "Someone gained access to your email and triggered the delete from there. We've restored. Please secure your email."

## Drafts

### ACCOUNT-RECOVERY-MAGIC-LINK-OK

```
You should have a login link in your inbox now (sent to <email>). Check
spam too — it sometimes lands there.

If it doesn't arrive in 10 minutes, reply and I'll dig into delivery logs.
```

### ACCOUNT-RECOVERY-2FA-RESET

```
Got it — verified your identity. I've reset 2FA on your account, so your
next login will be password-only.

When you're back in: please set up 2FA again on your new device. We don't
keep accounts unprotected.

Reply when you're back in and I'll close this out.
```

### ACCOUNT-RECOVERY-DECLINE-NO-VERIFY

```
I'm not able to restore access to <email> based on what we have. The info
provided doesn't match what we have on file, which makes this look (from
where I sit) like an attempt by someone other than the account owner.

If you ARE the owner, here's what would help:
- Last 4 of the card on file
- Approximate signup year
- Name of the first <project/team/whatever> you created

Reply with those if you can.

If you can't, I won't be able to restore — but I won't lock you out of
trying again.
```

### ACCOUNT-RECOVERY-SUSPENDED-DECLINE

```
Your account was suspended on <date> for <ToS-clause>. The suspension
stands — this isn't an automated lockout I can reverse.

If you want to appeal: reply with your reasoning. Owner will review within
7 days. If the appeal is upheld, the account is restored. If not, the
suspension stands and we'd issue a final-notice with export instructions
for any data you want to take with you.
```

## Anti-Patterns

| Don't | Why |
|---|---|
| Restore based on "I'm the real owner, trust me" | Account takeover vector |
| Send password reset to a "secondary" email the user provides in the ticket | Attacker-controlled fallback |
| Disable 2FA without identity check | Trivial takeover |
| Auto-unsuspend tickets escalated as "lockout" | Bypasses owner-only decisions |
| Decline without offering an alternate path | Customer rage-tweets at you |
| Take more than 24h to respond on free tier | Account locked = customer can't use product |
| Restore an account with the disputed-owner question pending | Picks a side in a dispute |

## Time Budget

| Case | Target |
|---|---|
| Self-serve magic link | 5 min |
| 2FA reset (verified) | 30 min |
| Suspended-account appeal | 7 days |
| Disputed ownership | 30 days (with counsel input) |

## Companion Refs

- [HOSTILE-USER.md](HOSTILE-USER.md) — when recovery requests come with hostility
- [GDPR-DSAR.md](GDPR-DSAR.md) — when "delete my account" follows
- [SECURITY-DISCLOSURE.md](SECURITY-DISCLOSURE.md) — if recovery indicates compromise
- `../POLICY-ELICITATION.md` — recovery policy is a TBD-OWNER for new projects
