# Anti-Patterns (Hard-Won, With Case Notes)

Each entry is a real failure mode with the lesson distilled from SaaS and open-source support incidents.

## 1. Trusting In-Memory Counts

**Failure:** Owner says "I think there are two open tickets" — there were three. Agent pulls the two it was told about and misses the third. The third has the highest SLA breach.

**Rule:** Always re-fetch the canonical list from the system of record before triage. Counts in conversation memory are unreliable.

## 2. Declaring A Fix Without End-to-End Repro

**Failure:** Agent fixes OAuth state validation, verifies individual API endpoints with `curl`, declares success. The chained user flow (`login → token exchange → metadata lookup → download`) has a *second* bug — slug-vs-UUID query mismatch — that only surfaces when running the full sequence.

**Rule:** Reproduce the exact user path, not a proxy. Individual endpoint checks are necessary but not sufficient.

## 3. First Fix Is Rarely The Last

**Failure:** Fix one layer → 429 rate limits surface → fix that → metadata query bug surfaces → fix that → token persistence fails silently. Three deploys, four fixes, one increasingly frustrated user.

**Rule:** After deploying any live fix, expect the next bug to appear. Don't send "all fixed!" until the user confirms end-to-end.

## 4. Failing To Correlate Before Responding

**Failure:** Two users report "different" bugs (500 on device code endpoint; login broken on macOS). Both share one root cause: an unapplied database migration for `device_code_hash`. Each got a custom investigation, doubling effort.

**Rule:** Read all open tickets before drafting any individual reply. Hypothesize shared root cause first.

## 5. Quoting Stale Admin Notes

**Failure:** Admin notes referenced "fixed in tool 0.1.3" but the live version is 0.1.5 and the fix had not actually shipped. The note was outdated.

**Rule:** Cross-reference admin notes against git history and actual deployed code before quoting version numbers to users.

## 6. Deploy Blockers Compounding Under Pressure

**Failure:** Missing `CRON_SECRET` env var, TypeScript errors in unrelated files, dirty workspace — deployment failed seven times while a user waited.

**Rule:** Keep production deploy prerequisites green at all times. Workspace clean, CI passing, env vars complete. Hotfixes need to ship instantly.

## 7. Tier-Blind Rate Limiting

**Failure:** Paying subscribers hit 429 errors because the rate limiter treated them the same as anonymous visitors. Subscriber bypass was incomplete.

**Rule:** Rate limit tier calculation must resolve identity *before* checking the limit. For paid users, never default to anonymous bucket.

## 8. Infrastructure Issues Without A Tracking Ticket

**Failure:** User reported `support@yourdomain.com` bounced — MX records pointed to the registrar instead of Cloudflare Email Routing. Noted in a prior ticket; never fixed; happened again.

**Rule:** Infra problems get a tracking ticket and a definition of done. "Noted" is not a resolution.

## 9. Internal Notes Are Not User Notification

**Failure:** Support request system had `adminNotes` field, but no email notification path. A bug was diagnosed and fixed in the admin UI, but the user was never told.

**Rule:** Verify the message-out path actually reaches the user. Internal notes are for the team, not the customer.

## 10. Confidence Without Evidence

**Failure:** Agent says "yes, this works" based on partial API checks. When it didn't work for the user, the response was severe: "why should I believe you when you were SO CONFIDENT?"

**Rule:** Never assert a fix works without running the user's failing scenario against production. Trust is built by reproducible evidence; "I'm confident" is the failure signature.

---

## Meta-Pattern: The Verification Hierarchy

When asked "is X working?", the answer must come from the level matching the question:

| Level | What it proves | When to use |
|---|---|---|
| Code review | Syntax / types / obvious logic | Pre-commit |
| Unit test | One function's behavior | Per-PR |
| Integration test | Module boundaries hold | Per-PR + CI |
| Local run | The build runs | Pre-deploy |
| Staging deploy | The deploy works | Pre-prod |
| Production curl | One endpoint works in prod | After deploy |
| **User-path repro in prod** | The actual feature works | **Before claiming "fixed"** |

A confident "fixed!" needs the bottom row. Anything less is "the next-level test passes" — useful but not the answer.

---

## Communication Anti-Patterns

| Don't | Why | Do |
|---|---|---|
| "I think this is the issue" before reproducing | Speculation reads as confidence | "I'd guess X — let me reproduce to confirm" |
| Send fix-confirmation message before user retries | Locks the agent into being wrong | Send "we believe this is fixed — please retry" |
| Summarize verbatim user error messages | Loses signal | Paste exact wording with timestamps |
| Apologize for things that weren't actually problems | Reads as anxious / lacks judgment | Apologize once, specifically, for the real friction |
| Promise timelines you don't control | Sets up a second failure | "We're investigating actively; updates within X" |
| Use "as soon as possible" | Lazy and meaningless | Give a real window or say "we don't have an ETA yet" |
