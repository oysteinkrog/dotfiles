# Spam, Abuse, And Hostile Users

The dark side of having a public ticket-filing surface: bots, abusers, hostile users, and the rare extortionist. Without explicit defenses, the queue gets buried and admins burn out reading slurs. This file is the layered defense.

## Threat Surface

| Threat | Vector | Damage |
|---|---|---|
| Bot spam | Form-fillers, scripted POSTs | Queue noise, admin time, potential phishing surface |
| Repeat-low-value | Same user filing 50/day "test" tickets | Admin attention drain |
| Hostile content | Slurs, threats, personal attacks | Admin morale, retention |
| Extortion | "Pay me or I'll post bad reviews" | Reputational manipulation |
| Phishing reflection | Tickets containing links the support agent might click | Account compromise |
| Account takeover signal | Tickets from a hijacked account | Privacy / billing risk |
| Legal threat | Tickets that read like pre-litigation discovery requests | Compliance and legal exposure |
| Targeted harassment | Coordinated filing campaign against a customer or admin | Trust collapse |

## Layer 1 — Anonymous-Submission Floor

The user-facing rate limiter (see [SECURITY.md](SECURITY.md) "Rate Limit Tier Awareness") already separates anon from auth. For anon, set hard caps:

```ts
const RATE_LIMIT_ANON = { perMinute: 2, perHour: 5, perDay: 10 };
```

A real customer locked out of auth needs to file at most 2-3 tickets per hour. A bot wants 200. The cap is sized for the former.

## Layer 2 — CAPTCHA / Proof-Of-Work On Anon Submission

For unauthenticated paths, require a CAPTCHA. Cloudflare Turnstile is the cleanest integration; reCAPTCHA v3 is a fallback.

```tsx
function AnonContactForm() {
  const [captchaToken, setCaptchaToken] = useState<string | null>(null);
  return (
    <form onSubmit={handleSubmit}>
      {/* fields */}
      <Turnstile siteKey={env.NEXT_PUBLIC_TURNSTILE_KEY} onSuccess={setCaptchaToken} />
      <button disabled={!captchaToken} type="submit">Send</button>
    </form>
  );
}
```

Server validates the token before accepting:

```ts
async function verifyTurnstile(token: string, ip: string): Promise<boolean> {
  const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ secret: env.TURNSTILE_SECRET, response: token, remoteip: ip }),
  });
  const json = await r.json();
  return json.success === true;
}
```

Authenticated paths skip CAPTCHA — the auth gate is the proof.

## Layer 3 — Honeypot Field

Add an invisible field most bots will fill:

```tsx
<input type="text" name="website" tabIndex={-1} autoComplete="off"
       style={{ position: "absolute", left: "-9999px", height: 0, width: 0 }} />
```

Server-side: any submission with `website !== ""` is dropped silently. Don't 403 — bots adapt; silent drops keep them guessing.

## Layer 4 — Content Heuristics

Before persisting, run cheap heuristics:

```ts
function spamScore(text: string): number {
  let s = 0;
  // High link density
  const linkCount = (text.match(/https?:\/\//g) ?? []).length;
  if (linkCount >= 5) s += 30;
  if (linkCount / Math.max(text.length / 100, 1) > 0.5) s += 20;
  // Phone number / crypto wallet
  if (/\b(?:\+?\d{1,3}[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/.test(text)) s += 10;
  if (/0x[a-fA-F0-9]{40}/.test(text)) s += 25;       // Ethereum wallet
  // Common spam phrases
  for (const phrase of SPAM_PHRASES) if (text.toLowerCase().includes(phrase)) s += 5;
  // Pure caps
  if (text.length > 50 && text === text.toUpperCase()) s += 15;
  // Excessive repetition
  if (/(.)\1{20,}/.test(text)) s += 20;
  return s;
}

const SPAM_THRESHOLD_AUTO_QUARANTINE = 50;
const SPAM_THRESHOLD_FLAG = 30;
```

`spamScore >= 50` → auto-quarantine (separate queue; don't route to admin queue). `spamScore >= 30` → flag for review. Score is advisory only; never use it to refuse customer access.

## Layer 5 — Account-Reputation Score

Per-customer score that adjusts to behavior:

```ts
interface CustomerReputation {
  userId: string;
  ticketsFiled30d: number;
  ticketsRejectedAsSpam30d: number;
  abusiveContentFlags: number;
  refundChargebacksLifetime: number;
  csatAvg: number;
  // computed
  score: number;        // 0-100, higher = more trustworthy
}
```

Score < 30 → tickets get a "low reputation" badge in the admin queue (admin review more carefully). Score < 10 + abusive content → auto-route to a moderation review queue, no admin sees in normal flow.

The score is **never customer-visible**. It influences routing and review intensity, not response quality.

## Layer 6 — Hostile Content Detection

Use a content classifier (or `/de-slopify`'s underlying model in classifier mode) to flag ticket text containing:
- Slurs / hate speech
- Direct threats ("I'll find you")
- CSAM (zero-tolerance; immediate report path; see [ATTACHMENTS-AND-FILE-UPLOAD.md](ATTACHMENTS-AND-FILE-UPLOAD.md))
- Self-harm content (route to a wellbeing-aware response template + suicide-prevention resource link)
- Doxing attempts (revealing other users' personal info)

```ts
async function classifyContent(text: string): Promise<ContentClassification> {
  // Use OpenAI moderation API, or self-hosted classifier
  const r = await openai.moderations.create({ input: text });
  return {
    hate: r.results[0].categories.hate,
    harassment: r.results[0].category_scores.harassment > 0.8,
    selfHarm: r.results[0].categories.self_harm,
    sexual: r.results[0].categories.sexual,
    sexualMinors: r.results[0].categories.sexual_minors,    // CSAM
    violence: r.results[0].categories.violence,
    threats: r.results[0].categories.violence_graphic,
  };
}
```

**CSAM gets a hard-coded path** — terminate the upload, do NOT preserve, file with NCMEC, suspend account, alert legal counsel. Legal review BEFORE shipping; the procedural details are not a code question.

## Layer 7 — Pre-Reply Wellbeing Filter For Admins

Admin opens a ticket containing slurs / threats / hostile content. UI shows a content warning before rendering:

```
⚠ This ticket contains content flagged as: harassment, slurs

The customer is being abusive. You don't have to handle this alone:
- [De-escalate template]    (proven 4-message script)
- [Escalate to lead]         (on-call lead reviews next)
- [Hostile-user policy]      (quick reference: when to terminate engagement)

[Show content anyway]
```

The friction protects the admin's emotional state. The admin can still proceed but does so deliberately. The content doesn't auto-render before they choose.

## Layer 8 — Hostile-User Policy + Termination

Document the policy:
- First infraction (slurs): one warning + de-escalation reply
- Second infraction within 90d: 7-day support cooldown
- Third: terminate engagement + ban

Termination is an owner-tier action with audit + customer notification (boilerplate email). The customer can pay-and-stay-active on the product but cannot file support. After 12 months, automatic re-evaluation; some recover.

Document this in your TOS so it isn't a surprise; cite the TOS section in the termination email.

## Layer 9 — Account Takeover Detection

Tickets that pattern-match account-takeover signals:
- Customer suddenly filing in a different language
- IP geographic distance from previous tickets
- "Help, I think someone hacked my account"
- Email change request followed immediately by billing change

When detected, the auto-reply does NOT confirm any sensitive details (don't tell an attacker the email was changed); routes to security review; suspends *outbound* customer-facing actions on the account until verified.

```ts
function detectATOSignals(ticket: SupportTicket, user: User): ATOSignal[] {
  const signals: ATOSignal[] = [];
  // Language drift
  const ticketLang = detectLanguage(ticket.description);
  const usualLang = user.usualLanguage;
  if (usualLang && ticketLang !== usualLang) signals.push({ kind: "language_drift", ... });
  // Geographic drift
  const ticketGeo = geoFromIp(ticket.metadata.clientIp);
  const usualGeo = user.usualGeoIso2;
  if (usualGeo && distanceKm(ticketGeo, usualGeo) > 5000) signals.push({ kind: "geo_drift", ... });
  // Keyword: "hacked", "compromised", "not my account"
  if (/\b(hacked|compromised|stolen|not my account|wasn'?t me)\b/i.test(ticket.description)) {
    signals.push({ kind: "ato_keyword", ... });
  }
  return signals;
}
```

Trigger on ≥ 2 signals → security review queue. False positives are acceptable; real ATOs catch fast.

## Layer 10 — Coordinated-Filing Detection

Ten tickets in 30 minutes against a single customer or admin (e.g. an employee being personally harassed) → coordinated harassment. Cron checks for:

```sql
SELECT
  ARRAY_AGG(filer_user_id) AS filers,
  target_id,
  COUNT(*) AS volume
FROM (
  -- tickets that mention an admin's name or another user's account
  SELECT user_id AS filer_user_id, mentioned_id AS target_id
  FROM support_tickets
  WHERE created_at >= NOW() - INTERVAL '30 minutes'
    AND mentioned_id IS NOT NULL
) mentions
GROUP BY target_id
HAVING COUNT(*) >= 10;
```

Auto-quarantine the cluster, alert security/owner. Don't auto-resolve; the team needs to investigate the underlying social-engineering attempt.

## Audit Trail For Sensitive Actions

Every spam/abuse action is auditable:
- Quarantine: `actionType: "support_ticket_quarantined"`, with `reason` (auto-rule or admin)
- Termination: `actionType: "user_support_terminated"`, owner-tier audit
- ATO suspension: `actionType: "user_outbound_suspended"`, security-review audit

These audits are queryable for legal discovery; assume they will be subpoenaed at some point.

## Anti-Patterns

| ✗ | Why |
|---|---|
| Returning 403 to spam submissions | Bots adapt; silent drops keep them guessing |
| Customer-visible spam-score | Triggers gaming; degrades real customers |
| Auto-banning on first hostile content | Real customers have bad days; one warning + de-escalation is the standard |
| Treating hostile users like normal customers | Admin morale collapses; turnover follows |
| Indexing ticket text into a fully searchable LLM context store | Re-ingestion of CSAM / slurs / personal data into model training |
| Honeypot field with `display: none` | Smart bots check `display`; use off-screen positioning |
| Skipping CSAM hard-stop because "it'll never happen to us" | When it happens, the response procedure can't be ad-hoc |
| Spam thresholds tuned only for English | Non-English real tickets misclassified |
| Allowing customers to see their own quarantine status | Gives them the signal to evade |

## Wire Points Checklist

- [ ] Anon rate-limit floor (`perMinute: 2, perHour: 5, perDay: 10`)
- [ ] CAPTCHA on anon submission (Turnstile or reCAPTCHA)
- [ ] Honeypot field (off-screen, not `display: none`)
- [ ] Content heuristic spam scorer
- [ ] Customer reputation score, never customer-visible
- [ ] Hostile-content classifier wired (OpenAI moderation or self-hosted)
- [ ] CSAM hard-stop with NCMEC reporting path
- [ ] Pre-reply wellbeing filter UI on admin side
- [ ] Hostile-user policy documented in TOS + admin handbook
- [ ] Termination is owner-tier audited action
- [ ] ATO signal detector wired
- [ ] ATO routes to security-review queue, suspends outbound actions
- [ ] Coordinated-filing cron detects clusters
- [ ] All sensitive actions audited with `reason`
- [ ] Test: spam score classifies known fixtures correctly
- [ ] Test: hostile content auto-routes to moderation queue
- [ ] Test: anon CAPTCHA-bypass path reliably 403s
