---
name: security-pushback-review
description: Run a skeptical reviewer that argues a security finding is smaller than it looks, before anyone escalates it. Use before calling anything an incident or a breach, before rating a finding high or critical, before asking a DPO, owner or Oystein to act urgently, and before a production change made because of a finding. Also use when the user says "push back", "is this really an incident", "devil's advocate" or "challenge this finding".
---

# Security pushback review

Oystein's standing rule (2026-11-18): every security problem we think we found gets a
reviewer whose job is to argue that it is not an incident and not worth escalating.
The finding moves forward only with the rating that survives that argument.

The case behind it: on 2026-11-18 manager-security found that an anonymous caller
could read a licence record by subscription id (SEC-394), and proposed asking the DPO
whether it was a personal data breach. Oystein pushed back. A hole is not an
incident, and there was no evidence anyone had used it. The logs then showed 21,871
normal lookups and no guessing, and the id turned out to be a random GUID. The
pushback was right, and it should have come from a reviewer before it reached him.

## When it runs

Run it before any of these. Each one counts as an escalation:

| Trigger | Example |
|---|---|
| Calling something an incident, breach, compromise or leak | "personal data breach", "the key is exposed" |
| Rating a finding high or critical | A SEC card with HIGH in the text or summary |
| Asking a person to act urgently | DPO, an owner "today", Oystein outside the normal batch |
| Making a production change because of the finding | Turning off access, rotating a key, blocking traffic |
| Telling customers, partners or authorities | Any notice outside the company |

Low and medium findings that just get a SEC card need no review. Write them plainly.

## The reviewer

Use a model that did not find the issue, so it is not anchored on your view.

- **Default:** Astra, through the bounded command in `~/.claude/CLAUDE.md` (effort
  `medium`, tools off, one `prompt.md`).
- **Add Fable 5.2** when the decision is a breach call, a customer or authority notice, or
  a key rotation that breaks shipped clients.
- **If both fail:** a fresh Opus subagent with only the brief below.

Give the reviewer the evidence, not your conclusion: the code lines, the config
values, the log counts, and what the logs cannot show. Keep the brief under about 15k
tokens.

## The brief

Put this in `prompt.md` and fill in the parts in angle brackets:

```
You are a skeptical security reviewer. Your job is to argue that the finding below is
smaller than it looks: not an incident, lower severity, or not worth escalating. Be
fair, not contrarian: concede what the evidence proves.

Finding: <one paragraph, facts only>
Proposed action: <incident call / severity / who to ask / production change>
Evidence: <code with file:line, config values, log queries and counts>
What the evidence cannot show: <for example: client IP not logged>

Answer in under 400 words:
1. Is there evidence the hole was actually used? Separate "possible" from "happened".
2. What does an attacker need first (a secret, an id, network position, an account)?
   How hard is that to get?
3. What limits the damage (scope, data actually exposed, compensating controls)?
4. The strongest case for a lower rating, and for not escalating.
5. Your rating: incident or vulnerability; critical, high, medium or low; escalate now,
   escalate in the normal batch, or just fix. One line on what evidence would change it.
```

## Reconcile

- If the reviewer's rating is lower and its points hold up against the evidence, use the
  lower rating.
- If you still disagree, check the specific point it raised (run the log query, read the
  code). Do not just restate your view.
- If you and the reviewer still disagree after that, show both views to Oystein, side
  by side, and let him decide.
- Put the outcome on the SEC card: the rating, the reviewer's main point, and what
  evidence settled it. Name the model.

## Words

- **Vulnerability** or **hole:** a weakness that exists. This is the default.
- **Incident:** evidence that someone used a weakness, or that data reached someone it
  should not have. It needs evidence of use, not just a possibility.
- **Breach** (personal data): an incident involving personal data. Only the DPO decides
  this, and only after the review above says there is evidence of access.

Never write "exposed", "leaked" or "compromised" about data or a key unless you have
evidence of access. Write "readable by", "reachable by" or "stored in" instead.
