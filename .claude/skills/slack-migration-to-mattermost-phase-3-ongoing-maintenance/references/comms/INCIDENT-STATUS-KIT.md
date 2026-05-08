# Incident Status Kit

Copy-paste templates for user-facing incident updates. Pair with
[../playbooks/INCIDENT-RESPONSE.md](../playbooks/INCIDENT-RESPONSE.md).

## Initial post (within 10 minutes of detection)

> **[INCIDENT] Mattermost is currently [degraded / unreachable]**
>
> We're investigating a problem affecting [login / posting / real-time
> delivery / file uploads]. Started approximately [TIME].
>
> What we know so far: [one sentence; say "investigating" if unknown].
>
> Next update by [TIME + 15 minutes].

## Investigating (every 15 minutes while ongoing)

> [UPDATE TIME] Mattermost: still investigating. Current focus: [one
> sentence]. Next update: [TIME + 15 minutes].

## Mitigating

> [UPDATE TIME] Mattermost: mitigation in progress. We believe root cause
> is [one sentence]. Applying fix now; expect recovery in [N] minutes.

## Partial recovery

> [UPDATE TIME] Mattermost: partially recovered. [Working feature]
> restored. [Still-broken feature] still under investigation. Next update:
> [TIME + 15 min].

## Resolved

> [UPDATE TIME] Mattermost: **resolved**. Total duration: [MINUTES].
>
> Root cause: [one sentence].
>
> Follow-up: [one sentence on what we're doing to prevent recurrence].
>
> Thanks for your patience. A short post-mortem will be posted in
> [#ops-journal] within 48 hours.

## Rollback declared

> [UPDATE TIME] Mattermost: **rolling back** to previous known-good state.
> You may see another 5-10 minute disruption as we revert. We'll post
> again when the rollback is complete.

## Rollback complete

> [UPDATE TIME] Mattermost: rollback complete. Service restored on
> version [PREVIOUS]. The attempted change from [FAILED CHANGE] has been
> fully reverted. Post-mortem to follow.

## Scheduled extended downtime (DR / rebuild)

> **[MAINTENANCE] Mattermost unavailable for rebuild**
>
> We're rebuilding Mattermost on fresh infrastructure following an
> incident. Expected downtime: [N to N+2 hours]. Your conversation history
> and channels are being restored from our most recent backup ([N hours
> old]); any messages sent between [BACKUP TIME] and [INCIDENT TIME] may
> be lost.
>
> We'll post updates every 30 minutes.

## Data-loss disclosure

When the incident involves confirmed data loss (e.g. a range of messages
lost because rollback used an older backup):

> **[POST-MORTEM] Data loss between [TIME A] and [TIME B]**
>
> During today's incident, we rolled Mattermost back to a backup taken at
> [TIME A]. Messages posted between [TIME A] and [TIME B] (approximately
> [DURATION]) were lost as part of that rollback.
>
> If you posted content in that window that must be preserved, please
> repost it now.
>
> A full post-mortem will be published in [#ops-journal] by [DATE].

## What goes where

- `#general` / all-users channel: initial post, updates every 15 min, resolution.
- `#ops` or dedicated incident channel: the blow-by-blow, operator coordination.
- Status page (if you have one): mirrors `#general`.
- Email: only for extended downtime (> 1 hour) or data-loss disclosure.

## Tone rules

- Direct, short, factual.
- Acknowledge what's broken in user-visible terms ("login", "posting")
  not internal terms ("mmctl failed", "pg_connections saturated").
- No speculation about root cause until you know.
- Time-box: next update by a specific time, and post by that time even if
  there's no news.
- After resolution: brief, honest root cause. Users are more forgiving of
  "we rolled back" than of silence.
