# Response Templates (Generic)

These are *starting points*. Customize per project and store the customized versions in `<project>/.claude/support-triage/04-templates/<NAME>.md`. The customized version takes precedence at triage time.

**Brand voice:** Match the project's existing voice. The onboarding pass should pull 5–10 historical replies from the owner / team and identify their tone (warm-and-casual, formal-and-precise, terse-and-technical, etc.).

## REQUEST-INFO

```
Thanks for the report! To investigate, we need a few details:

- Exact error message (full output, please — partial messages often miss the actual signal)
- {{ command-or-action }} version: {{ how to get it }}
- Operating system and version
- Steps to reproduce, in the order you ran them

Happy to dig in once we have those.
```

## ACKNOWLEDGE (SLA Breached — Stops the clock; substantive reply follows)

```
Thanks for reporting this — we see it slipped past our response SLA. Acknowledging
now and investigating actively. Full update within {{ next response window }}.
```

## CODE-BUG (Confirmed)

```
Confirmed — and thanks for catching this. {{ one-line description of the root cause }}.

We've shipped a fix in {{ commit / version }}. Please {{ action — upgrade / refresh / retry }}
and let us know if it persists. Sorry for the friction.
```

## CODE-FIXED (Already shipped)

```
This was fixed in {{ version / SHA }}, released {{ date }}. Please upgrade with:

  {{ upgrade command }}

If the issue persists after the upgrade, that's a separate bug — let us know with
the new version output.
```

## INSTALL-FAIL

```
Thanks for the install report. To pinpoint this, we need:

- Your OS and version
- The exact one-line install command you ran
- Full error output (please paste, don't summarize — small details matter)
- Shell version: `{{ shell }} --version`  (e.g. `bash --version`)

The installer needs {{ minimum requirements }}. If you're past that, the verbatim
error tells us exactly which check failed.
```

## AUTH-FAIL

```
Thanks for the login report. We've seen a few variants — the right diagnosis
depends on the symptom:

1. "Invalid state" / "expired code"   →  upgrade to the latest CLI/app
2. "401 Unauthorized" after success   →  credential write may have failed silently;
                                         try `{{ whoami-equivalent }}` to verify
3. "500 server error"                 →  please share the timestamp + your account email
                                         so we can correlate to logs

Could you share which variant you're seeing, plus your version and the timestamp
of the failed attempt?
```

## RATE-LIMIT (Tier Mismatch)

```
Sorry about the 429 — paying customers shouldn't be hitting rate limits. We've
verified your subscription is active and we're investigating why the limiter
didn't honor your tier. We'll patch and let you know when you can retry.
```

## REFUND (Approved)

```
Refund processed. Here's what we did:

- Subscription cancelled effective immediately
- {{ amount }} refunded to your original payment method (5–10 business days)
- Account access revoked

Sorry it didn't work out. If there's anything we could have done differently, we'd
genuinely appreciate the feedback.
```

## REFUND (Declined — out of policy window)

```
Thanks for reaching out. Our refund policy is {{ policy text }}, and at {{ duration }}
since the charge, this falls outside that window. I can't issue a refund here, but
I'd like to make sure you can get value going forward — what was the friction that
led you to reach out?

(If you'd like to cancel future renewals, I can do that immediately so you're not
billed again.)
```

## BILLING (Subscription state mismatch)

```
Thanks for flagging this — looking at your account, {{ what we found }}.

We've corrected your subscription status on our end. You should now see {{ expected
state }}. Could you {{ verification step }} to confirm everything looks right? If
something's still off, please share what you're seeing and we'll keep digging.
```

## FEATURE-REQUEST (Logged, no commit)

```
Thanks for the suggestion! {{ specific reason this idea is interesting / how it
fits the product }}. We've logged it for product planning.

We can't commit to a timeline, but we'll update this thread if it ships. In the
meantime, {{ workaround or alternative if applicable }}.
```

## DECLINE-FEATURE

```
Thanks for the thoughtful suggestion. After thinking about it, we don't think
{{ feature }} is a good fit for {{ project }} — {{ reason: scope / maintenance /
philosophy / overlap }}.

If you'd like, {{ alternative path: workaround, plugin point, fork-friendly note }}.
```

## QUESTION (Answer + redirect to community)

```
{{ direct answer }}

For future how-to questions, you'll usually get faster answers in {{ Discussions /
Discord / community-channel }} where other users can chime in too.
```

## COSMETIC (Harmless warning)

```
Good catch — that warning is cosmetic and doesn't affect functionality. It comes
from {{ source: underlying library / stale log / known minor issue }}.

We're tracking it for cleanup. Your {{ install / data / account }} is fine despite
the message.
```

## INFRA (Owner-side issue)

```
Thanks for flagging this — we've identified the root cause as {{ infra issue:
DNS, MX, CDN, etc. }}, and we're working on the fix.

In the meantime, {{ workaround if any, or "we'll update once it's resolved" }}.
```

## DUPLICATE

```
Thanks — this is a duplicate of {{ canonical issue / ticket }}, where we're
tracking it. I'll close this one to keep the conversation in one place.

Subscribe to {{ canonical }} for updates.
```

## STALE (OSS issues, pre-cutoff)

```
Closing this as stale — it's been quiet since {{ date }}, and the surrounding
code has changed substantially in the meantime. If you're still seeing this on
the latest release, please open a fresh issue with:

- Exact version
- Reproduction steps
- Full error output

Thanks for the original report!
```

## TOKEN-PERSIST (Login succeeds but `whoami` says not-logged-in)

```
Thanks for the report. Sounds like login completed but credentials weren't saved.

Quick checks:
1. `{{ whoami-equivalent }}` → does it say not-logged-in?
2. `ls -la {{ creds-dir }}` → are the files there with the right permissions?
3. On a headless server? Try `export {{ DISABLE_KEYRING_VAR }}=1` then re-login.

If those don't help, please share output of `{{ whoami }}` and `{{ login --verbose }}`.
```

## SECURITY (Initial private acknowledgement — NOT a public reply)

```
Thanks for the responsible disclosure. We're treating this privately. We'll
investigate and respond within {{ window }}. Please don't post details publicly
in the meantime.

If you'd like, our security contact is {{ email or page }}.
```

---

## Customization Patterns

When customizing per project:

- Replace `{{ placeholders }}` with actual project values
- Add a project-specific opening line (e.g. signoff with first name)
- Match capitalization conventions (some teams use sentence case in subjects, others Title Case)
- Pull in domain-specific terms ("workspace", "deployment", "skill", "channel" — whatever the product calls things)
- Reference the project's actual upgrade/install commands, not generic placeholders
