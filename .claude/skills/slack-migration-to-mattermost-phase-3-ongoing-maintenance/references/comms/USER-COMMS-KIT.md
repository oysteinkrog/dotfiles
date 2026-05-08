# User Comms Kit — Maintenance Windows

Copy-paste templates for the non-incident communications. Incident templates
live in [INCIDENT-STATUS-KIT.md](INCIDENT-STATUS-KIT.md).

## T-7d: Upcoming Mattermost upgrade

> Subject: Mattermost upgrade next [DAY], brief maintenance window
>
> Hi team — next [DAY OF WEEK, DATE] at [TIME] [TIMEZONE] we'll upgrade
> Mattermost from [CURRENT] to [TARGET] during a ~15 minute maintenance
> window. You may see a brief disconnect and reconnect around that time.
>
> What's changing: [one-line summary of release notes].
>
> What you need to do: nothing. Your client will reconnect automatically.
>
> Questions: [ops channel / email].

## T-24h: reboot reminder

> Subject: Mattermost reboot tonight, 1–3 minutes
>
> Tonight at [TIME] UTC (= [TIME] local) Mattermost will reboot to apply
> security patches. Expected disruption: 1 to 3 minutes. Your client will
> reconnect automatically.

## T-1h: start of maintenance window

> [#general] Heads up — Mattermost maintenance starts in 1 hour. Expect a
> 1 to 3 minute disconnect between [START] and [END]. No action needed.

## T-10m: imminent

> [#general] Mattermost maintenance in 10 minutes. We'll post again when
> it's complete.

## Complete (success)

> [#general] Mattermost maintenance complete. On version [NEW VERSION]. If
> anything looks off, reply here or ping [handle].

## Complete (extended)

> [#general] Mattermost maintenance took longer than planned; service is
> back and on [NEW VERSION]. Root cause: [one line]. Sorry for the delay.

## Quarterly restore-drill (internal-only, no user comms)

Restore-drills don't touch the live server. No user comms required. Update
your ops tracking doc so the next operator knows when the drill ran.

## Annual DR drill (internal, optional external)

If running a full DR rehearsal on a scratch host:

> [internal] DR rehearsal runs this [WEEKEND]. No impact to production
> Mattermost. Evidence and results will be in `workdir-phase3/reports/dr/`
> by [MONDAY].

If the DR drill includes a DNS cutover test to a scratch host with a
throwaway subdomain, announce it so users aren't confused:

> [#general] A "DR rehearsal" subdomain (`dr-test.chat.[DOMAIN]`) may be
> visible in browser devtools for a few hours today. It's not a real
> service; production remains at [MATTERMOST_URL].

## Credential rotation (no user comms)

PAT, SSH, token rotations are transparent to users. No announcement.

## Expected message cadence

A healthy Phase 3 produces ~1 user-facing maintenance announcement per
quarter (the upgrade heads-up). If you're sending more, your cadence is
noisy; batch the announcements into a once-a-month "maintenance digest"
instead.

## What NOT to post to users

- Specific patch version numbers (they don't care; ops does)
- Release-note deprecations that don't affect them
- Internal playbook milestones ("rotated PAT today")
- Backup success / failure notifications
- DB health metrics

These live in ops-only channels or logs.
