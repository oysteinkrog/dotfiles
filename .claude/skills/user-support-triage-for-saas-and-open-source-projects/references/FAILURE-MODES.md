# Failure-Mode Catalog

40+ specific things that go wrong in support systems. Indexed by category for quick search during triage. Each entry: symptom → likely cause → first thing to check → fix shape.

The catalog grows. If you hit a new failure mode, add it here so future triage spots it.

## Email / Communication

### F-1: Support replies land in spam

**Symptom**: customer says "I never got your reply"; mailbox provider flags as spam.
**Cause**: SPF/DKIM/DMARC misalignment; sending IP reputation; recipient marked prior reply as spam.
**Check**: `dig TXT <yourdomain> +short` for SPF; provider dashboard for DKIM signing; `mail-tester.com` end-to-end test.
**Fix**: align SPF/DKIM/DMARC with sending domain (Resend wizard); ask customer to whitelist sender; adjust DMARC policy from `quarantine` to `none` while debugging then back.

### F-2: Support mailbox bounces

**Symptom**: customer replies to support@yourdomain bounce with "550 mailbox not found".
**Cause**: MX records still point to registrar parking page after switching email providers (real JSM incident).
**Check**: `dig MX <yourdomain> +short` — should resolve to your email provider, not the registrar.
**Fix**: update MX records to email provider (Cloudflare Email Routing, Google Workspace, etc.).

### F-3: Reply-to ≠ From; customer replies disappear

**Symptom**: customer says "I replied to your email but never heard back".
**Cause**: From-address is `noreply@`; Reply-To header is set but email client doesn't honor it.
**Check**: pull a recent outbound email; look at headers.
**Fix**: send From a real, monitored mailbox; remove Reply-To unless absolutely needed.

### F-4: Customer marked legit reply as spam

**Symptom**: subsequent replies to same customer don't arrive; sender reputation degrades.
**Cause**: customer hit "spam" once; Gmail/Outlook now training all your replies as spam for them.
**Check**: Resend bounce log; check if a complaint event was logged.
**Fix**: ask customer to mark as "not spam" + add to contacts; add unsubscribe link so they don't have to use the spam button.

### F-5: Long reply truncated

**Symptom**: customer says "I can only see part of your reply"; clicks "view full message" and finds the rest.
**Cause**: Gmail truncates at 102 KB; long replies + signatures + threading exceed it.
**Fix**: keep reply body under 50 KB; link to longer content rather than inlining.

### F-6: Auto-reply loops

**Symptom**: support@ inbox flooded with "Out of office" replies bouncing between two systems.
**Cause**: your auto-ack and the customer's vacation reply each replying to each other.
**Fix**: add `Auto-Submitted: auto-replied` header to outgoing auto-acks; receiving systems honor that and won't loop.

### F-7: Curly-quote in From-name breaks DMARC

**Symptom**: emails inconsistently quarantined.
**Cause**: smart-quotes / non-ASCII in `From: "Acme's Support" <...>` breaks header alignment.
**Fix**: ASCII-only From-name; or use proper RFC 5322 quoting.

## Webhook / Payment

### F-8: Webhook secret rotated; signature 500s silently

**Symptom**: payments work in dashboard but DB doesn't update; subscriptions stuck on "past_due".
**Cause**: Stripe / PayPal webhook signing secret rotated; old secret in env; signature verify fails 500.
**Check**: webhook delivery logs in provider dashboard; recent 5xx spike; env var matches dashboard.
**Fix**: update env var; ensure rotation procedure includes app deploy.

### F-9: 200 response, async error swallowed

**Symptom**: webhook delivery shows 200 in Stripe; DB unchanged.
**Cause**: handler `await`s a promise inside a `setTimeout` / unhandled async path; throws are lost.
**Fix**: top-level `try/catch` with logging; sentry around the entire handler.

### F-10: Idempotency key missing → duplicates after retry

**Symptom**: webhook retries after 5xx outage create duplicate subscription rows.
**Cause**: handler doesn't check if the event has already been processed.
**Fix**: store processed event IDs in `payment_events` with unique constraint; check before processing.

### F-11: PayPal `BILLING.SUBSCRIPTION.UPDATED` silent drop

**Symptom**: customer changes plan in PayPal; your DB unchanged.
**Cause**: handler switch doesn't include this event type.
**Fix**: add the case; backfill missed events from PayPal event history.

### F-12: Provider cross-match failure

**Symptom**: customer cancelled but still being charged; "I cancelled in Stripe but PayPal keeps charging".
**Cause**: customer paid via PayPal first, then upgraded via Stripe; `users.customerId` overwritten with `cus_*`; PayPal's `payer_id` lookup fails silently.
**Fix**: maintain a `payment_provider_history` table; never overwrite; cancel old provider on switch.

### F-13: Late `PAYMENT.SALE.COMPLETED` resurrects cancelled team

**Symptom**: team subscription cancelled, then re-activated mysteriously.
**Cause**: PayPal queues an in-flight payment; processed after cancellation; reconciliation cron interprets it as resubscribe.
**Fix**: cancellation handler refuses payments older than the cancellation timestamp.

### F-14: Cache invalidation > webhook timeout

**Symptom**: Stripe retry storm; plan change doesn't take effect; customer charged but old plan persists.
**Cause**: synchronous `invalidateUserCache` hangs under Redis degradation, push webhook response past Stripe's 10s window.
**Fix**: invalidate async (queue or after-response); webhook responds immediately.

## Auth / Accounts

### F-15: Customer changes email; tickets orphan

**Symptom**: customer's old tickets vanish from their dashboard after email change.
**Cause**: tickets keyed by email at lookup time, not user ID at creation.
**Fix**: tickets reference `users.id`; UI looks them up by current user.

### F-16: SSO migration locks customer out

**Symptom**: customer can no longer log in after the project switched from Auth0 to Supabase Auth.
**Cause**: SSO identity not migrated; original auth method removed.
**Fix**: migration retains original auth as fallback for 90 days; users prompted to re-auth proactively.

### F-17: OAuth state-param length validation

**Symptom**: older CLIs / SDKs fail OAuth with "invalid state".
**Cause**: server validates state as 32-128 chars; older clients generate 22-char states.
**Fix**: relax validation; or release a CLI version with longer states.

### F-18: Device-code TTL too short

**Symptom**: customer copies device URL but pastes too late; "code expired".
**Cause**: 60-second TTL on the auth code is shorter than the human paste-and-login flow.
**Fix**: extend TTL to 5+ minutes; warn user near expiry.

### F-19: Token persistence silently fails

**Symptom**: login appears to succeed; `whoami` reports "not logged in".
**Cause**: file write to `~/.config/<tool>/credentials` failed silently; or keyring unavailable on headless and fallback didn't engage.
**Check**: `ls -la ~/.config/<tool>/`; logs from login flow.
**Fix**: error early on credential-write failure; don't silently fall through.

### F-20: TTY check disables headless fallback

**Symptom**: customer on VPS can't complete OAuth; the `--manual` paste fallback doesn't engage.
**Cause**: `atty::is(stdin)` returns false on the VPS, but the code only offers manual paste when `atty::is == true`.
**Fix**: invert the logic — manual paste should be the *fallback* when browser-open fails or stdout isn't a TTY; or always offer `--manual` flag explicitly.

## Ticketing System Internals

### F-21: `Math.random()` for ticket IDs

**Symptom**: ID collisions; predictable IDs leak ordering.
**Cause**: `Math.random()` instead of `crypto.randomUUID()` (real, found in cass-mined sessions).
**Fix**: always `crypto.randomUUID()`.

### F-22: SLA clock running on awaiting_customer

**Symptom**: tickets in "waiting on customer" alarm as SLA breaches.
**Cause**: SLA computation uses elapsed time without subtracting paused-state intervals.
**Fix**: track pause intervals; SLA = elapsed − sum(pause windows). Exclude `awaiting_customer` from `OPEN_TICKET_STATUSES`.

### F-23: Reopen-on-reply for closed tickets

**Symptom**: customer replies to a year-old closed ticket asking an unrelated question; ticket reopens; SLA "breaches" immediately.
**Cause**: status transition logic doesn't refuse reply on `closed`.
**Fix**: closed = terminal; new replies prompt "open new ticket".

### F-24: Internal note marked public

**Symptom**: customer sees a snarky "this user is being unreasonable" message that was meant for internal only.
**Cause**: visibility flag default is wrong; or copy-paste from internal-only field.
**Fix**: render internal notes with distinct visual; require explicit "send to customer" toggle.

### F-25: Bulk-action skips silently

**Symptom**: agent bulk-resolves 50 tickets; one stays open; doesn't notice.
**Cause**: a permission-check fails silently for one ticket (different org).
**Fix**: bulk-action UI returns per-item result; show partial-success summary.

### F-26: Time-zone bug in SLA

**Symptom**: SLA "due in 4h" shown to agent at 3pm local; cron alarms at 11pm local.
**Cause**: backend computes UTC; UI displays local; ambiguity.
**Fix**: store + display UTC consistently; only convert at the very last UI edge.

### F-27: Search index lag

**Symptom**: ticket created; refresh of admin queue doesn't show it for 30s.
**Cause**: async index pipeline (Algolia, Typesense, Elastic) has propagation lag.
**Fix**: write-through both DB and index; admin list reads from DB primary, not the index.

### F-28: Attachment orphan in S3

**Symptom**: ticket save fails after attachment upload; blob in S3, no DB row.
**Cause**: two-step upload; second step failed; first not rolled back.
**Fix**: presigned-upload: blob exists first, ticket-save references it; if save fails, garbage-collect the blob via lifecycle rule.

### F-29: Markdown XSS in admin UI

**Symptom**: admin UI executes JavaScript when viewing a ticket with `<script>` in body.
**Cause**: rendered customer markdown in admin without sanitization.
**Fix**: sanitize via DOMPurify; or render in iframe sandbox.

### F-30: CSV export contains PII for non-DSAR-cleared user

**Symptom**: agent exports tickets; CSV includes emails + IPs; emailed to a coworker who shouldn't have access.
**Cause**: no role-based gate on export feature.
**Fix**: gate export behind `support.export` permission; mask sensitive fields by default.

## Process / Human

### F-31: Two agents reply simultaneously

**Symptom**: customer gets two replies with different answers within minutes.
**Cause**: no collision detection.
**Fix**: surface "another agent is viewing/typing" indicator; soft-lock on draft.

### F-32: Stale macro

**Symptom**: agent uses the "v1.2 fixed" macro; customer is on v1.5; no v1.2 fix relevant.
**Cause**: macros not version-aware.
**Fix**: macros reference live data via templating; version-pin operator (✓ VERSION-PIN) before sending.

### F-33: Agent closes with one-line "fixed"

**Symptom**: customer reopens because they didn't know what was done.
**Cause**: lazy close.
**Fix**: closing reply must include: what was done + how to verify + when it shipped.

### F-34: Auto-close hits genuine waiting

**Symptom**: ticket waiting on engineering for 10 days; auto-close cron fires.
**Cause**: cron treats `awaiting_engineering` like `awaiting_customer`.
**Fix**: explicit list of statuses safe for auto-close; never include any `awaiting_internal_*`.

### F-35: Routing rule loop

**Symptom**: ticket reassigned every minute between two teams.
**Cause**: rule A reassigns to team B; rule B reassigns to A.
**Fix**: add reassignment counter; refuse > 3 reassigns; log loop and alert ops.

### F-36: Holiday/timezone SLA

**Symptom**: Friday 6pm ticket alarms at 10pm Saturday.
**Cause**: SLA computed continuously, not in business hours.
**Fix**: opt-in business-hours mode per tier; document on customer-facing SLA.

### F-37: Hostile-user ban leaves replies visible

**Symptom**: banned user's hostile reply is still visible in a thread other customers can see.
**Cause**: ban flag scoped to user, not their content.
**Fix**: optionally hide content from banned users at admin discretion.

## Compliance / Data

### F-38: DSAR erasure leaves audit-log emails

**Symptom**: erased user; their email still appears in audit log; they re-DSAR.
**Cause**: erasure script touches `users` table only.
**Fix**: pseudonymize all PII references in audit log atomically.

### F-39: Webhook payload logs include card last-4

**Symptom**: PCI auditor flags log retention.
**Cause**: log handler dumps full webhook payload for debugging.
**Fix**: redact PCI/PII fields before logging; have a minimal "incident" mode that includes more for live debug.

### F-40: Audit log isn't immutable

**Symptom**: agent edits ticket history; audit log shows the new version, no record of old.
**Cause**: audit_log allows UPDATE.
**Fix**: append-only by constraint; no UPDATE/DELETE permissions on the table for app-level roles.

### F-41: Status page green while support is buried

**Symptom**: status page "all green"; queue is 6h backed up; customers furious.
**Cause**: status page measures uptime, not customer experience.
**Fix**: add "support response time" to the status page; declare a degraded state when FRT P90 exceeds SLA.

## Infrastructure

### F-42: Cron silent because CRON_SECRET missing

**Symptom**: SLA breaches not flagging; cron runs but returns 403.
**Cause**: deploy didn't include the secret env var.
**Fix**: smoke test that pings cron at deploy time; fail deploy on 403.

### F-43: Auto-deploy disabled

**Symptom**: fix in main; user still hits the bug.
**Cause**: `vercel.json` has auto-deploy off; no one noticed.
**Fix**: assert auto-deploy is on at deploy-script time; alert if disabled.

### F-44: Rate-limit before identity

**Symptom**: paying user gets 429.
**Cause**: rate-limit middleware runs before requireUser; classifies as anonymous.
**Fix**: identity resolution first; then rate-limit with tier-aware bucket.

### F-45: Email provider outage

**Symptom**: tickets created but no notification email arrives; customers unaware.
**Cause**: Resend / Postmark transient failure; no retry queue.
**Fix**: queue email sends; retry with backoff; alert ops on failure rate spike.

### F-46: DB read-replica lag

**Symptom**: admin updates a ticket then refreshes; old state shows.
**Cause**: writes to primary, reads from replica; lag.
**Fix**: read your own writes (sticky to primary for N seconds after a write); or read from primary in admin UI.

## How To Use This Catalog

1. During triage Phase 2 (🔍 REPRO + ⊕ CORRELATE), if a symptom matches a catalog entry, the root cause is likely the cataloged one.
2. After confirming, file a bead (🐞 BEAD) referencing the catalog entry by ID (F-N).
3. After fixing, update `06-recurring-issues.md` for that project to mark this class as "fixed in <SHA>".
4. If you hit a NEW failure mode, **add it here** with the same shape: symptom → cause → check → fix.

## Pattern Recognition

Failure modes cluster by:
- **Provider-side** (F-2, F-8, F-11, F-15) — your control limited; fix the integration
- **Async-pipeline** (F-9, F-14, F-27, F-46) — eventual-consistency edge cases
- **Identity / cross-match** (F-12, F-15, F-16, F-44) — keying assumptions break under change
- **Silent failure** (F-2, F-9, F-19, F-30, F-42, F-43) — most expensive class; add observability

When you see one in a cluster, check the others.
