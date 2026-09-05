# Live Escalation Protocol

For when a paying user is reporting failures *in real time* — via chat, X DM, or relayed by the owner. Stakes are higher than async triage; rules differ.

## Rules (Hard-Won)

1. **The first fix is rarely the last.** Each layer peels back another. Keep the loop open with the user; don't send "all fixed!" until they confirm end-to-end.
2. **Root causes shift mid-debug.** The initial hypothesis is usually correct *but incomplete*. After deploying the first fix, expect new failure modes to appear immediately.
3. **Relay verbatim quotes.** "Too Many Requests" tells you rate-limit-tier-bug; "the thing didn't work" tells you nothing. Paste raw chat transcripts to whoever's investigating.
4. **Protect parallel work.** Other agents may have live edits. Do not stash, revert, overwrite, or commit their work just to get a clean tree. Narrow your edit surface, coordinate ownership, and touch only the files needed for the live fix.
5. **Schedule a fresh-eyes audit the next day.** Hotfixes-under-pressure miss things. A calm second pass catches the bugs the live session glossed over.
6. **Token persistence can fail silently.** Login appears to succeed but `whoami`-equivalent says not-logged-in. Always have the user run a verification command after the "fixed" state.

## Live Session Shape

```
00:00  User reports failure (relayed by owner)
00:01  Acknowledge to owner; check dirty files and reserve/narrow the fix surface
00:02  Pull verbatim user message + their version + timestamps
00:05  Reproduce against production with the user's exact path
       (NOT a curl proxy — the chained flow may have a second bug)
00:10  Identify root cause; draft fix
00:15  Surface fix to owner — get approval before deploying
00:20  Deploy; watch deployment logs
00:25  Verify fix against production using user's exact path again
00:27  Owner relays "try now" to user
00:30  User reports back:
        - Still failing → loop back to step 00:05 with new evidence
        - Different failure → there's a second bug; classify and continue
        - Works → confirm with user, close loop, schedule next-day audit
```

## After-Session Audit (Next Day)

Spawn a fresh agent (or session) and tell it:

```
Last night we fixed <issue>. The fixes touched <files / SHAs>. Run a fresh-eyes
audit looking specifically for:

1. Bugs adjacent to what we fixed (often a sibling has the same issue)
2. Token / credential / state-write paths that could fail silently
3. Webhook handlers that swallow errors
4. Telemetry / event-id type mismatches (CLI sends int, server expects UUID — etc.)
5. Auto-deploy state — is it on, or did we manually deploy and forget to flip it back?
6. Tests that should have caught this — write or strengthen them

Output: a punch list of follow-up beads. Don't send any customer messages.
```

The audit catches:

- Sibling bugs in the same code path
- Telemetry deduplication breakage (event-ID type drift)
- Host-construction or path-prefix regressions adjacent to the fix
- "Manually deployed once, didn't re-enable auto-deploy" footguns

## Communication During Live Session

| Owner says | We do |
|---|---|
| "Customer says it's still broken" | Pull their verbatim words; do NOT summarize. Reproduce the exact path |
| "Can we ship a quick fix?" | Surface the fix + its blast radius before deploying. Quick ≠ unsafe |
| "Can you verify?" | Run the user's failing scenario against production and paste the output |
| "How confident are you?" | High only if you've reproduced both the failure and the fix on production. Otherwise be specific about what you haven't confirmed |

Confidence-without-evidence is the most damaging response category — see [ANTI-PATTERNS.md](ANTI-PATTERNS.md) §10.
