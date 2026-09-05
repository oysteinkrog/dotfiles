# Observability-Driven Triage — Tickets Are Lagging; Errors Lead

By the time a customer files a ticket, the underlying error has been firing in production for minutes, hours, or days. Error tracking, structured logs, and synthetic monitors usually know first. This file is the discipline of *fusing* the observability stack with the triage stack so the agent can:

- Anticipate ticket volume from error spikes
- Correlate this customer's ticket to the exact error event in logs
- Answer "is it just me?" with data instead of speculation
- Detect when a ticket is *missing* from a known error cohort (silent affected users)

> **Core insight:** observability and support are usually two separate disciplines run by two separate teams with two separate vocabularies. The triage skill becomes 5-10x more effective when those vocabularies are joined: the customer's ticket gets a Sentry event ID, the Sentry alert gets a customer-impact count, and the same fingerprint links them.

This file complements `VOICE-OF-CUSTOMER-LOOP.md` (which mines patterns from tickets) and `SUPPORT-FORECASTING.md` (which forecasts volume). Where those work from ticket data, this file works from telemetry data — the *upstream* signal.

---

## The Three Telemetry Layers Worth Joining

| Layer | What it sees | Examples |
|---|---|---|
| **Error tracking** | Runtime exceptions, crashes, failed promises | Sentry, Rollbar, Bugsnag, Honeybadger |
| **Logging / observability** | Structured events, request traces, user actions | Datadog, New Relic, Honeycomb, Grafana Loki, OpenTelemetry |
| **Synthetic & RUM** | Continuous probes, real-user metrics | Pingdom, Datadog Synthetics, browser RUM |

Most projects have at least one of these and don't use it to drive support. The triage win is small joins:

- Add `support_url` to every error event (link out from Sentry → ticket creation form pre-filled with event ID)
- Add `error_event_id` to every ticket (when filing, the in-app form can capture the most recent client error)
- Join on user-id at query time so the agent can answer "what was happening for this user when they wrote in"

Done correctly, these three integrations move triage from "describe what you saw" to "the system describes what it did" in under a minute.

---

## The Three Observability Use Cases For Triage

### Use case 1: Anticipate

A spike in 5xx on `POST /api/sync` at 14:03 means tickets at 14:30. Anticipating means:

```
[OPERATOR-LOCAL: 📊 OBSERVE — Anticipate]
1) Subscribe the triage workspace to error-spike alerts (Sentry "regression"
   alerts, Datadog monitor breach, etc.).
2) When alert fires:
   - Compute affected-user count from error event metadata
   - Estimate ticket spike: ~2-5% of affected users typically file
   - Pre-stage:
     - Status-page draft (per CRISIS-COMMS.md cadence)
     - Internal note: "expecting ticket spike on [pattern]; root cause [...]"
     - Template reply with {error_id} placeholder ready
   - Notify owner BEFORE the first ticket lands
3) When tickets land, immediately link {ticket_id ↔ error_event_id}.
```

The asymmetry: discovering the bug *via tickets* takes 6 hours and 100 tickets; discovering it via error tracking takes 5 minutes. The anticipation lets the project look prepared rather than reactive.

### Use case 2: Correlate

This-customer-this-ticket → which error events:

```
[OPERATOR-LOCAL: 📊 OBSERVE — Correlate]
1) From the ticket, extract: user_id (or email), timestamp, action attempted.
2) Query error tracking for events matching:
   - user.id = ticket.user_id
   - timestamp within ± 1 hour of ticket creation
3) Query logs for traces matching same user_id around the timestamp.
4) Quote the most relevant evidence in the agent's investigation log:
   - Stack trace snippet
   - Request URL + status code
   - Trace ID for the failing request
5) Cite the trace ID in the customer reply (anchored evidence).
```

The output of this is much sharper than "I see; can you tell me more?" The reply can say: "I see your sync failed at 14:23:11 with a 504 on `POST /api/sync`. The trace shows the upstream Postgres query timed out during a transaction with [N] rows. We've pushed a fix as of [version]; please retry and let me know if it's still happening."

### Use case 3: Reverse-correlate (silent cohort detection)

The most powerful use. An error fingerprint affected 200 users; only 4 filed tickets. Who are the other 196?

```
[OPERATOR-LOCAL: 📊 OBSERVE — Reverse-Correlate]
1) For a known error fingerprint:
   - Query users who triggered it in the affected window
   - Subtract users who already filed tickets
   - The remainder is the silent cohort
2) Hand off to 🩹 PROACTIVE per [PROACTIVE-SUPPORT.md] §"Incident-driven outreach"
3) Message includes the trace-ID-equivalent so customer can verify
4) Outcome record (📈 OUTCOME) tracks reach rate + reverse-CSAT
```

This is the loop that converts an outage into a proactive trust deposit. Without it, the 196 silent users churn slowly over the next quarter and never tell you why.

---

## Required Joins And Naming Conventions

For these patterns to work, the data has to be joinable. Conventions worth adopting (project-specific overrides go in `07-secrets.md` schema notes):

| Field | Where to set | Why |
|---|---|---|
| `user.id` (consistent UUID) | Set on every error event, log line, and ticket | Single key for join |
| `session.id` (per-tab/per-app session) | Same | Disambiguate concurrent issues |
| `trace.id` (per-request) | Set in distributed tracing | Pinpoint single failing operation |
| `release.version` | Set on every event | Map to deploy / git SHA |
| `feature.flags.active` | Set on every event | Disambiguate experiment cohorts |
| `account.tier` | Set on every event | Tier-blind issues are common bugs |
| `region` / `pop` / `cell` | Set on every event | Region-specific issues |

If any of these are missing, the join is fuzzy. Onboarding can detect the gaps via `scripts/detect-support-surface.sh` (extension) and propose adding the missing instrumentation.

---

## The "Is It Just Me?" Answer

The single most common implicit question in a ticket is "is it just me?" The customer rarely asks it explicitly, but the answer changes how they receive the reply:

| Truth | Reply |
|---|---|
| Just them (truly user-side) | "Looking at our logs, the error is local to your environment; the request didn't reach our servers. Likely [...specific cause]." |
| One of N (small cohort) | "We see the same error pattern affecting [N] accounts in the last hour. Investigating now; [ETA]." |
| Widespread (>1% of users) | "This is a real outage on our side. Status page: [link]. We'll send a personal update when fixed." |
| Was just them; pattern detected via this ticket | "You may have caught a new bug — your report is the first instance. Looking now; expect an update by [ETA]." |

Each of these is a different reply structure. With observability, the agent picks the right one by looking; without it, the agent guesses.

---

## Saved Queries / Dashboards Worth Building

These are practical artifacts to build during onboarding:

| Query / dashboard | Purpose |
|---|---|
| "Errors by user_id, last 24h" | Pulled when a ticket lands; correlate user with their errors |
| "Top error fingerprints, last 1h vs last 7d" | Spot regressions before tickets |
| "Tickets-per-fingerprint, last 30d" | Identify error fingerprints that consistently generate tickets (engineering priority) |
| "Silent-cohort gap, by fingerprint" | Affected users minus reporting users; outreach targets |
| "Time-to-first-ticket after error first seen" | How fast does observability beat tickets? Used to tune anticipation cadence |
| "Tickets without correlating error event" | Either errors are missing instrumentation, or these are non-bug categories |

The first four are the most-used; build them first.

---

## What The Agent Can Do Even Without Joined Data

A worse-but-workable mode for projects that haven't wired the joins:

1. Ask the customer for a *trace ID* / *correlation ID* / *request ID* if the product surfaces one in error messages — many do, even if it's not connected to support backend
2. Ask for *time of failure in customer's timezone, plus action attempted* — gives you a search window
3. Use the customer's account email to manually cross-search Sentry / Datadog
4. Note in `📈 OUTCOME` records that "join not available; manual correlation took [N] min"; aggregate to justify wiring the join

The wired-join target (per `📊 OBSERVE` operator) is "5 second correlation"; manual correlation is the current state for many projects.

---

## Observability As Triage Self-Defense

The agent's own audit log (per `AI-AUTO-RESPONSE-GOVERNANCE.md`) should also flow into observability:

- Every draft hash, owner approval, send response → structured log event
- Every operator invocation → metric (count, duration)
- Every classification disagreement (owner edits) → metric tagged with original classification

This lets you:

- Detect agent regressions ("approval rate dropped 10% after model update")
- Compare cohorts of tickets handled before/after a runbook change
- Spot operator misuse (e.g., 🪞 SECOND-OPINION never invoked despite high-stakes triggers)
- Audit for AI-on-AI loops (per `AI-AUTO-RESPONSE-GOVERNANCE.md`)

The triage skill is itself a system worth observing.

---

## Common Pitfalls

| Pitfall | Why it bites |
|---|---|
| Joining on email instead of stable user_id | Email changes; users have multiple emails; doesn't match Sentry events keyed on user_id |
| Logging PII into Sentry breadcrumbs | Privacy violation; some jurisdictions require minimisation |
| Quoting Sentry stack traces verbatim to the customer | Reveals internal architecture; sometimes reveals other users' info if not carefully scrubbed |
| "Showing your work" with too much detail | The customer wants the answer, not the diagnostic process |
| Not retaining errors long enough for ticket correlation | Sentry default retention is short; tickets land later |
| Errors scrubbed of user_id "for privacy" but unjoinable | The win is *agent-side* join; obfuscation prevents help |

For projects with privacy obligations (GDPR/HIPAA-adjacent), the right pattern is: *hash* user_id at error-event time, retain the hash, accept that joins must go through the same hash function. Don't fully anonymize errors that you might need for support.

---

## How This File Plugs In

| Used by | How |
|---|---|
| 📊 OBSERVE operator | The 3-mode workflow |
| 🩹 PROACTIVE operator | Reverse-correlate cohort detection |
| 🔮 PREDICT operator | Telemetry-driven volume forecasting |
| 🐞 BEAD operator | High-volume error fingerprints become engineering beads |
| 01-architecture.md | Document the project's observability stack here |
| 07-secrets.md | Naming conventions for joins |
| ANTI-PATTERNS.md | Adds "guessing without telemetry" failure mode |

---

## Cross-References

- [VOICE-OF-CUSTOMER-LOOP.md](VOICE-OF-CUSTOMER-LOOP.md) — downstream-of-tickets mining
- [SUPPORT-FORECASTING.md](SUPPORT-FORECASTING.md) — volume forecasting
- [PROACTIVE-SUPPORT.md](PROACTIVE-SUPPORT.md) — silent-cohort outreach
- [STATUS-PAGE.md](STATUS-PAGE.md) — public surface for telemetry-detected outages
- [METRICS-AND-DASHBOARDS.md](METRICS-AND-DASHBOARDS.md) — joining triage and observability metrics
